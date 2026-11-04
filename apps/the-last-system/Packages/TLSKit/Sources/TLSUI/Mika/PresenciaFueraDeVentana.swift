import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement
import TLSCore
import UserNotifications

// F4 · rol mika. La app fuera de la ventana (PLAN §6.1 `MenuBarExtra`, §6.7 paso 7 «Conectar», §5.2 presupuesto de
// interrupciones). **Todo opcional y apagado de serie**; se enciende en Ajustes › Asistentes o en el paso 7:
//
// - **Barra de menús:** el estado de los asistentes, el interruptor y «Abrir Decisiones».
// - **Avisos:** solo lo rojo y lo que espera tu OK (aprobaciones y permisos cambiados fuera de la app), con el tope de
//   `avisos.tope_notificaciones_no_rojas_dia` (3) al día que no sean rojos; cada cosa se avisa una vez
//   (`PresupuestoDeInterrupciones`, TLSCore).
// - **Trabajar con la ventana cerrada:** la app se abre al iniciar sesión (ítem de inicio con `SMAppService`), se queda
//   en la barra de menús y mantiene abierta la última empresa para que los asistentes sigan con lo suyo.
//
// Solo la app de verdad (`es.thelast.system` dentro de un `.app`) guarda las preferencias en el Mac, registra el ítem
// de inicio y manda avisos; en pruebas todo queda en memoria y nada toca el sistema.

/// El ítem de inicio («Abrir al iniciar sesión»).
@MainActor
protocol ItemDeInicio: AnyObject {
    var activo: Bool { get }
    /// macOS pide que lo permitas en Ajustes del Sistema.
    var pidePermiso: Bool { get }
    func poner(_ activo: Bool) throws
    func abrirAjustesDelSistema()
}

/// `SMAppService.mainApp` (macOS 13+).
@MainActor
final class ItemDeInicioDelSistema: ItemDeInicio {
    var activo: Bool { SMAppService.mainApp.status == .enabled }
    var pidePermiso: Bool { SMAppService.mainApp.status == .requiresApproval }
    func poner(_ activo: Bool) throws {
        if activo { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
    func abrirAjustesDelSistema() { SMAppService.openSystemSettingsLoginItems() }
}

/// En pruebas (y fuera de la app): solo recuerda lo pedido.
@MainActor
final class ItemDeInicioEnMemoria: ItemDeInicio {
    private(set) var activo = false
    var pidePermiso = false
    private(set) var cambios: [Bool] = []
    func poner(_ activo: Bool) throws { self.activo = activo; cambios.append(activo) }
    func abrirAjustesDelSistema() {}
}

/// Quien manda los avisos del Mac.
@MainActor
protocol Notificador: AnyObject {
    /// Pide permiso al Mac (la primera vez sale su diálogo).
    func pedirPermiso() async -> Bool
    func avisar(id: String, titulo: String, texto: String, empresa: UUID)
}

/// `UNUserNotificationCenter`: solo en la app.
@MainActor
final class NotificadorDelSistema: NSObject, Notificador, UNUserNotificationCenterDelegate {
    func pedirPermiso() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func avisar(id: String, titulo: String, texto: String, empresa: UUID) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = texto
        c.userInfo = ["empresa": empresa.uuidString, "destino": "decisiones"]
        let centro = UNUserNotificationCenter.current()
        centro.delegate = self
        centro.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// Pulsar un aviso abre Decisiones de esa empresa.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let empresa = (response.notification.request.content.userInfo["empresa"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if let empresa { PreferenciasPresencia.abrir(empresa, .decisiones) }
        }
        completionHandler()
    }
}

/// En pruebas: apunta lo que se habría avisado.
@MainActor
final class NotificadorEnMemoria: Notificador {
    var permiso = true
    private(set) var avisados: [(id: String, titulo: String, texto: String)] = []
    func pedirPermiso() async -> Bool { permiso }
    func avisar(id: String, titulo: String, texto: String, empresa: UUID) { avisados.append((id, titulo, texto)) }
}

/// Lo que eliges sobre la app fuera de la ventana. Todo apagado de serie.
@MainActor
@Observable
final class PreferenciasPresencia {
    /// El icono de los asistentes en la barra de menús.
    var barraDeMenus: Bool {
        didSet {
            guard barraDeMenus != oldValue else { return }
            guardar(barraDeMenus, Self.claveBarra)
            if !barraDeMenus, ventanaCerrada { ventanaCerrada = false }
        }
    }
    /// Avisos del Mac: solo lo rojo y lo que espera tu OK.
    var avisos: Bool {
        didSet { guard avisos != oldValue else { return }; guardar(avisos, Self.claveAvisos) }
    }
    /// Abrir al iniciar sesión y seguir con la ventana cerrada (también enciende la barra de menús).
    var ventanaCerrada: Bool {
        didSet {
            guard ventanaCerrada != oldValue else { return }
            guardar(ventanaCerrada, Self.claveVentana)
            if ventanaCerrada, !barraDeMenus { barraDeMenus = true }
            do { try item.poner(ventanaCerrada) } catch {
                Self.log.error("No se pudo cambiar el ítem de inicio: \(error.localizedDescription, privacy: .public)")
                problema = "macOS no dejó abrir la app al iniciar sesión. Puedes permitirlo en Ajustes del Sistema › General › Ítems de inicio."
            }
        }
    }
    /// Lo que salió mal al cambiar algo, en palabras.
    var problema: String?

    @ObservationIgnored let item: any ItemDeInicio
    @ObservationIgnored let notificador: any Notificador
    @ObservationIgnored private let defaults: UserDefaults?
    private static let log = Logger(subsystem: "es.thelast.system", category: "Presencia")
    static let claveBarra = "tls.presencia.barraDeMenus"
    static let claveAvisos = "tls.presencia.avisos"
    static let claveVentana = "tls.presencia.ventanaCerrada"

    init(defaults: UserDefaults? = nil, item: any ItemDeInicio = ItemDeInicioEnMemoria(),
         notificador: any Notificador = NotificadorEnMemoria()) {
        self.defaults = defaults
        self.item = item
        self.notificador = notificador
        barraDeMenus = defaults?.bool(forKey: Self.claveBarra) ?? false
        avisos = defaults?.bool(forKey: Self.claveAvisos) ?? false
        ventanaCerrada = defaults?.bool(forKey: Self.claveVentana) ?? false
    }

    private func guardar(_ v: Bool, _ clave: String) { defaults?.set(v, forKey: clave) }

    /// ¿Es la app de verdad? (y no las pruebas ni una herramienta).
    static var esLaApp: Bool {
        Bundle.main.bundleIdentifier == "es.thelast.system" && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Las de la app (las preferencias del Mac) o, fuera de ella, unas en memoria.
    static let compartidas: PreferenciasPresencia = esLaApp
        ? PreferenciasPresencia(defaults: .standard, item: ItemDeInicioDelSistema(), notificador: NotificadorDelSistema())
        : PreferenciasPresencia()

    /// Encender los avisos pide permiso al Mac; si lo niega, se quedan apagados y se dice por qué.
    func encenderAvisos(_ v: Bool) async {
        guard v else { avisos = false; return }
        if await notificador.pedirPermiso() {
            avisos = true
            problema = nil
        } else {
            avisos = false
            problema = "macOS no deja a la app mandar avisos. Puedes permitirlo en Ajustes del Sistema › Notificaciones."
        }
    }

    /// Cómo abrir una empresa en un destino desde fuera de su ventana (avisos, barra de menús). Lo pone la primera
    /// vista que tenga `openWindow`.
    static var abrirEmpresa: (@MainActor (UUID, Destino) -> Void)?

    static func abrir(_ empresa: UUID, _ destino: Destino) {
        NSApp?.activate()
        if let s = AvisosDeAsistentes.sesion(de: empresa), let nav = s.navegacionActiva {
            nav.nuevaRaiz(destino)
            NSApp?.windows.first { $0.tabbingIdentifier == AppModel.identificadorPestanas(empresa) && $0.isVisible }?
                .makeKeyAndOrderFront(nil)
            return
        }
        abrirEmpresa?(empresa, destino)
    }
}

/// Los avisos del Mac de una empresa abierta: cuando cambia la bandeja, avisa de lo rojo y de lo que espera tu OK,
/// dentro del presupuesto del día.
@MainActor
final class AvisosDeAsistentes {
    private weak var sesion: VaultSession?
    private var vigilando = false
    let preferencias: PreferenciasPresencia

    private final class Entrada {
        weak var sesion: VaultSession?
        let valor: AvisosDeAsistentes
        init(_ s: VaultSession, _ v: AvisosDeAsistentes) { sesion = s; valor = v }
    }

    private static var porSesion: [ObjectIdentifier: Entrada] = [:]

    static func de(_ sesion: VaultSession, preferencias: PreferenciasPresencia = .compartidas) -> AvisosDeAsistentes {
        porSesion = porSesion.filter { $0.value.sesion != nil }
        let k = ObjectIdentifier(sesion)
        if let e = porSesion[k], e.sesion === sesion { return e.valor }
        let v = AvisosDeAsistentes(sesion: sesion, preferencias: preferencias)
        porSesion[k] = Entrada(sesion, v)
        return v
    }

    static func sesion(de empresa: UUID) -> VaultSession? {
        porSesion.values.compactMap(\.sesion).first { $0.entry.id == empresa }
    }

    init(sesion: VaultSession, preferencias: PreferenciasPresencia) {
        self.sesion = sesion
        self.preferencias = preferencias
    }

    /// Mientras la empresa siga abierta, cada vez que cambie Hoy (la bandeja) mira si hay algo que avisar.
    func vigilar() {
        guard let sesion, !vigilando else { return }
        vigilando = true
        let almacen = AlmacenHoy.de(sesion)
        withObservationTracking {
            _ = almacen.datos?.bandeja
            _ = preferencias.avisos
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.vigilando = false
                self.revisar()
                self.vigilar()
            }
        }
        revisar()
    }

    /// Avisa de lo que toque ahora. Devuelve lo avisado (para las pruebas).
    @discardableResult
    func revisar() -> [TarjetaDecision] {
        guard preferencias.avisos, let sesion, let d = AlmacenHoy.de(sesion).datos,
              let a = AsistentesDeLaEmpresa.de(sesion).autorizador else { return [] }
        let tope = a.estadoDeConfig().efectiva.avisos.topeNotificacionesNoRojasDia
        // Solo lo que de verdad se avisa gasta el tope del día (F4 · integración: antes lo gastaban todas las visibles).
        let elegidas = PresupuestoDeInterrupciones(estado: a.estado, tope: tope).avisar(d.bandeja, hoy: d.hoy, filtro: Self.seAvisa)
        for t in elegidas {
            preferencias.notificador.avisar(id: t.id, titulo: Self.titulo(t, empresa: sesion.entry.nombre), texto: Self.texto(t),
                                            empresa: sesion.entry.id)
        }
        return elegidas
    }

    /// Solo lo rojo y lo que espera tu OK (aprobaciones y permisos cambiados fuera de la app).
    static func seAvisa(_ t: TarjetaDecision) -> Bool {
        if t.prioridad == .roja { return true }
        switch t.gobierno?.clase {
        case .aprobacion, .cambioDePermisos: return true
        default: return t.tipo == .paraAprobar
        }
    }

    static func titulo(_ t: TarjetaDecision, empresa: String) -> String {
        if t.prioridad == .roja { return "\(empresa) · En rojo" }
        if t.gobierno?.clase == .cambioDePermisos { return "\(empresa) · Permisos sin confirmar" }
        return "\(empresa) · Espera tu OK"
    }

    /// Sin el contenido de lo que sale (eso se ve en la hoja de confirmación): quién lo pide y qué es.
    static func texto(_ t: TarjetaDecision) -> String {
        if let s = t.gobierno?.asistente, t.gobierno?.clase == .aprobacion {
            let accion = t.gobierno?.accion?.titulo ?? "Revisar un borrador"
            return "\(AsistenteConfigurado.nombre(de: s)) prepara «\(t.titulo)»: \(accion.prefix(1).lowercased() + accion.dropFirst())."
        }
        return t.titulo + (t.motivo.map { ". \($0)" } ?? "")
    }
}

/// Lo de la app fuera de la ventana para otros módulos (el paso 7 de la puesta en marcha): las mismas preferencias que
/// Ajustes › Asistentes.
@MainActor
public enum PresenciaDeLaApp {
    public static var barraDeMenus: Bool { PreferenciasPresencia.compartidas.barraDeMenus }
    public static var avisos: Bool { PreferenciasPresencia.compartidas.avisos }
    public static var trabajaConLaVentanaCerrada: Bool { PreferenciasPresencia.compartidas.ventanaCerrada }

    /// Enciende o apaga los avisos (encender pide permiso al Mac la primera vez).
    public static func encenderAvisos(_ v: Bool) async { await PreferenciasPresencia.compartidas.encenderAvisos(v) }

    /// «Trabajar con la ventana cerrada»: ítem de inicio y barra de menús.
    public static func ventanaCerrada(_ v: Bool) { PreferenciasPresencia.compartidas.ventanaCerrada = v }
}
