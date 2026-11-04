import Foundation
import Observation
import TLSCore
import TLSDesign

// F5 · rol conexiones. El modelo de la pantalla Conexiones (Ajustes y paso 7 de la puesta en marcha): una fila por
// conexión con su estado en texto e icono y su «Ahora no", y lo que hace falta para conectar cada una:
//
// - Claude Code (F4): lo que dice la comprobación (`ClaudeEnConexiones`).
// - Mail: explicación ANTES del aviso de Automatización → aviso de macOS → cuenta → remitentes privados → Cartero.
//   Denegado → recuperación (con enlace a Ajustes del Sistema), sin volver a preguntar.
// - Calendario: explicación → aviso → calendario «The Last System». Denegado → recuperación.
// - Banco: ya funciona con extractos (Finanzas › Banco): aquí solo se enlaza.
// - Otros programas: plantillas, alta (la clave va al Llavero y se olvida aquí), probar, interruptores en llano,
//   «Revisar herramientas nuevas» y lo sensible «Siempre con tu OK». La matriz técnica, solo en Ajustes › Avanzado.
// - Avisos y «Trabajar con la ventana cerrada» (F4, `PreferenciasPresencia`, apagados de serie).

/// Cómo está una conexión, en texto e icono (el color solo refuerza).
public enum EstadoConexion: Sendable, Hashable {
    case conectado
    case sinPermiso
    case ahoraNo
    case error(String)
    /// F5 · integración: en el ejemplo no se conecta (Mail y Calendario de Ribera).
    case enEjemplo

    public var palabra: String {
        switch self {
        case .conectado: "Conectado"
        case .sinPermiso: "Sin permiso"
        // F5 · corrector (P2-6): el estado no repite el botón «Ahora no».
        case .ahoraNo: "Sin conectar"
        case .error: "Con error"
        case .enEjemplo: "Desactivado (ejemplo)"
        }
    }

    public var simbolo: String {
        switch self {
        case .conectado: "checkmark.circle.fill"
        case .sinPermiso: "lock.fill"
        case .ahoraNo: "moon.zzz"
        case .error: "exclamationmark.triangle.fill"
        case .enEjemplo: "graduationcap"
        }
    }

    public var tlsEstado: TLSEstado {
        switch self {
        case .conectado: .bien
        case .sinPermiso: .atencion
        case .ahoraNo, .enEjemplo: .sinDato
        case .error: .mal
        }
    }
}

/// Lo que se sabe de Claude Code (de `ComprobacionClaude` en Ajustes o del paso 7 en la puesta en marcha).
public struct InfoClaude: Sendable, Hashable {
    public var estado: EstadoConexion
    public var texto: String
    public var consejo: String?
    public var ocupado: Bool
    public var puedeProbar: Bool
    public var puedeBuscar: Bool

    public init(estado: EstadoConexion, texto: String, consejo: String? = nil, ocupado: Bool = false, puedeProbar: Bool = false,
                puedeBuscar: Bool = true) {
        self.estado = estado; self.texto = texto; self.consejo = consejo; self.ocupado = ocupado
        self.puedeProbar = puedeProbar; self.puedeBuscar = puedeBuscar
    }
}

/// Claude Code dentro de Conexiones: lo que se ve y lo que se puede pulsar.
public struct ClaudeEnConexiones {
    public var info: @MainActor () -> InfoClaude
    public var buscar: @MainActor () async -> Void
    public var probar: @MainActor () async -> Void

    public init(info: @escaping @MainActor () -> InfoClaude, buscar: @escaping @MainActor () async -> Void,
                probar: @escaping @MainActor () async -> Void) {
        self.info = info; self.buscar = buscar; self.probar = probar
    }

    /// Sin comprobación (no se busca nada).
    @MainActor public static var ninguno: ClaudeEnConexiones {
        ClaudeEnConexiones(info: { InfoClaude(estado: .ahoraNo, texto: "Sin comprobar.", puedeBuscar: false) }, buscar: {}, probar: {})
    }
}

/// Dónde se enseña la pantalla.
public enum ModoConexiones {
    /// Ajustes › Conexiones: la elección «Ahora no» se recuerda en este Mac (por empresa).
    case ajustes
    /// Paso 7 «Conectar» de la puesta en marcha: cada elección es la respuesta a su pregunta.
    case paso(EleccionesDelPaso)

    public var esPaso: Bool { if case .paso = self { true } else { false } }
}

/// Las respuestas del paso 7 (`.conexion(c)`: «conectar» / «ahora-no»; «Trabajar con la ventana cerrada», sí o no).
public struct EleccionesDelPaso {
    /// `true` conectar, `false` ahora no, `nil` sin contestar.
    public var leer: @MainActor (ConexionPuesta) -> Bool?
    public var elegir: @MainActor (ConexionPuesta, Bool) async -> Void

    public init(leer: @escaping @MainActor (ConexionPuesta) -> Bool?, elegir: @escaping @MainActor (ConexionPuesta, Bool) async -> Void) {
        self.leer = leer; self.elegir = elegir
    }
}

/// En qué punto está conectar Mail.
public enum FaseMail: Sendable, Hashable {
    case inicio
    case comprobando
    /// La explicación previa: su botón «Continuar» lanza el aviso de macOS.
    case explicacion(PermisoExplicado)
    case recuperacion(RecuperacionDeConexion)
    case mailCerrado
    /// Elegir la cuenta y los remitentes privados.
    case cuentas([String])
    case conectado
    case error(String)
}

/// En qué punto está conectar el Calendario.
public enum FaseCalendario: Sendable, Hashable {
    case inicio
    case comprobando
    case explicacion(PermisoExplicado)
    case recuperacion(RecuperacionDeConexion)
    case conectado(resumen: String?)
    case error(String)
}

/// El alta de un programa mientras se rellena. La clave solo vive aquí hasta entregarla.
public struct BorradorDeOtroPrograma: Sendable, Hashable {
    public var plantilla: PlantillaDeOtroPrograma
    public var nombre: String
    public var direccion: String
    public var clave: String

    public init(plantilla: PlantillaDeOtroPrograma) {
        self.plantilla = plantilla
        nombre = plantilla.nombre
        direccion = plantilla.direccionDeEjemplo == "https://" ? "" : plantilla.direccionDeEjemplo
        clave = ""
    }
}

/// Un programa de este Mac (solo en Ajustes › Avanzado): sin claves y con aviso.
public struct BorradorProgramaLocal: Sendable, Hashable {
    public var nombre = ""
    public var ejecutable = ""
    public var argumentos = ""
    public var avisoAceptado = false

    public init() {}
}

@MainActor
@Observable
public final class ModeloConexiones {
    public let modo: ModoConexiones
    @ObservationIgnored public let servicios: (any ServiciosDeConexiones)?
    @ObservationIgnored public let claude: ClaudeEnConexiones
    @ObservationIgnored let presencia: PreferenciasPresencia
    @ObservationIgnored let abrirEnlace: @MainActor (URL) -> Void
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let empresa: UUID?

    /// Las que dijiste «Ahora no» (en Ajustes; en el paso, la respuesta de su pregunta).
    public private(set) var ahoraNoElegidas: Set<ConexionPuesta> = []
    /// La fila abierta (su panel debajo).
    public var abierta: ConexionPuesta?

    // Mail
    public private(set) var faseMail: FaseMail = .inicio
    public private(set) var permisoMail: EstadoDePermisoConexion?
    public private(set) var carteroActivo = false
    public var ajustesMail = AjustesDeMailConexion()
    public var activarCartero = true
    public var nuevoPrivado = RemitentePrivadoConexion(patron: "", etiqueta: "")
    public private(set) var errorPrivado: String?

    /// F5 · integración: lo que no se conecta en el ejemplo, con su porqué.
    public private(set) var enEjemplo: [PermisoDeConexion: String] = [:]

    // Calendario
    public private(set) var faseCalendario: FaseCalendario = .inicio
    public private(set) var permisoCalendario: EstadoDePermisoConexion?

    // Otros programas
    public private(set) var plantillas: [PlantillaDeOtroPrograma] = []
    public private(set) var programas: [OtroProgramaConexion] = []
    public private(set) var interruptores: [String: [InterruptorDeOtroPrograma]] = [:]
    public private(set) var revisiones: [RevisionDeOtroPrograma] = []
    public private(set) var matrices: [String: [FilaDeMatrizConexion]] = [:]
    public var alta: BorradorDeOtroPrograma?
    public var local = BorradorProgramaLocal()
    /// Lo último que dijo cada programa al probarlo o sincronizarlo.
    public private(set) var mensajes: [String: String] = [:]
    /// F5 · corrector (P3-18): el error tal cual, solo para «Detalle técnico».
    public private(set) var tecnicos: [String: String] = [:]
    public private(set) var errorAlta: String?

    /// Algo salió mal fuera de un panel (en una frase).
    public private(set) var problema: String?
    public private(set) var trabajando = false
    public private(set) var cargado = false

    /// `empresa` y `defaults`: dónde se recuerda «Ahora no» en Ajustes (sin ellos, solo en memoria).
    public convenience init(servicios: (any ServiciosDeConexiones)?, modo: ModoConexiones = .ajustes,
                            claude: ClaudeEnConexiones = .ninguno, abrirEnlace: (@MainActor (URL) -> Void)? = nil,
                            empresa: UUID? = nil, defaults: UserDefaults? = nil) {
        self.init(servicios: servicios, modo: modo, claude: claude, presencia: nil, abrirEnlace: abrirEnlace, empresa: empresa,
                  defaults: defaults)
    }

    init(servicios: (any ServiciosDeConexiones)?, modo: ModoConexiones = .ajustes,
         claude: ClaudeEnConexiones = .ninguno, presencia: PreferenciasPresencia?,
         abrirEnlace: (@MainActor (URL) -> Void)? = nil, empresa: UUID? = nil, defaults: UserDefaults? = nil) {
        self.servicios = servicios
        self.modo = modo
        self.claude = claude
        self.presencia = presencia ?? .compartidas
        self.abrirEnlace = abrirEnlace ?? ConexionesDeLaApp.abrirEnlace
        self.empresa = empresa
        self.defaults = defaults
        if let defaults, let empresa, let guardadas = defaults.array(forKey: Self.clave(empresa)) as? [String] {
            ahoraNoElegidas = Set(guardadas.compactMap(ConexionPuesta.init(rawValue:)))
        }
    }

    static func clave(_ empresa: UUID) -> String { "tls.conexiones.ahoraNo.\(empresa.uuidString)" }

    /// El orden de las filas.
    public static let orden: [ConexionPuesta] = [.claude, .mail, .calendario, .banco, .otros, .avisos, .ventanaCerrada]

    public var hayServicios: Bool { servicios != nil }

    // MARK: Leer

    /// Lee el estado de todo sin preguntar nada a nadie (ni a macOS).
    public func cargar() async {
        plantillas = servicios?.plantillas() ?? ServiciosDeConexionesEnMemoria.plantillasDeSerie
        guard let s = servicios else { cargado = true; return }
        var ejemplo: [PermisoDeConexion: String] = [:]
        for p in PermisoDeConexion.allCases { ejemplo[p] = await s.enEjemplo(p) }
        enEjemplo = ejemplo
        if !ejemplo.isEmpty {
            // En el ejemplo no se pregunta nada a macOS por lo que no se conecta.
            await leerOtros()
            cargado = true
            return
        }
        switch await s.situacion(.mail) {
        case .listo: permisoMail = .concedido
        case .explicar: permisoMail = .sinPreguntar
        case .recuperar(let r):
            permisoMail = .denegado
            if case .inicio = faseMail { faseMail = .recuperacion(r) }
        case .sinComprobar: permisoMail = .desconocido
        }
        carteroActivo = await s.carteroActivo()
        ajustesMail = await s.ajustesDeMail()
        if carteroActivo, permisoMail == .concedido, ajustesMail.cuenta != nil, case .inicio = faseMail { faseMail = .conectado }
        switch await s.estadoDelCalendario() {
        case .conectado(let r):
            permisoCalendario = .concedido
            if case .inicio = faseCalendario { faseCalendario = .conectado(resumen: r) }
        case .sinPermiso(let r):
            permisoCalendario = .denegado
            if case .inicio = faseCalendario { faseCalendario = .recuperacion(r) }
        case .sinConectar:
            if case .listo = await s.situacion(.calendario) { permisoCalendario = .concedido } else { permisoCalendario = .sinPreguntar }
        case .fallo(let t): faseCalendario = .error(t)
        }
        await leerOtros()
        cargado = true
    }

    func leerOtros() async {
        guard let s = servicios else { return }
        programas = await s.otrosProgramas()
        var ints: [String: [InterruptorDeOtroPrograma]] = [:]
        for p in programas { ints[p.id] = await s.interruptores(p.id) }
        interruptores = ints
        revisiones = await s.revisiones()
    }

    // MARK: Filas

    /// El estado de cada fila, en texto e icono.
    public func estado(_ c: ConexionPuesta) -> EstadoConexion {
        let elegida = eleccion(c)
        switch c {
        case .claude:
            let i = claude.info()
            return elegida == false && i.estado != .conectado ? .ahoraNo : i.estado
        case .mail:
            if enEjemplo[.mail] != nil { return .enEjemplo }
            if case .error(let t) = faseMail { return .error(t) }
            if permisoMail?.necesitaRecuperacion == true { return .sinPermiso }
            if carteroActivo, permisoMail == .concedido, ajustesMail.cuenta != nil { return .conectado }
            return .ahoraNo
        case .calendario:
            if enEjemplo[.calendario] != nil { return .enEjemplo }
            if case .error(let t) = faseCalendario { return .error(t) }
            if permisoCalendario?.necesitaRecuperacion == true { return .sinPermiso }
            if case .conectado = faseCalendario { return .conectado }
            return .ahoraNo
        case .banco:
            return elegida == false ? .ahoraNo : .conectado
        case .otros:
            if let e = programas.compactMap({ if case .error(let t) = $0.estado { t } else { nil } }).first { return .error(e) }
            return programas.contains { $0.estado == .conectado } ? .conectado : .ahoraNo
        case .avisos:
            return presencia.avisos ? .conectado : .ahoraNo
        case .ventanaCerrada:
            return presencia.ventanaCerrada ? .conectado : .ahoraNo
        }
    }

    /// La palabra de la pastilla de cada fila (los interruptores dicen «Encendido»).
    public func palabra(_ c: ConexionPuesta) -> String {
        let e = estado(c)
        switch (c, e) {
        case (.avisos, .conectado): return "Encendidos"
        case (.ventanaCerrada, .conectado): return "Encendido"
        case (.banco, .conectado): return "Con extractos"
        default: return e.palabra
        }
    }

    /// Una línea bajo el nombre de cada fila: lo que hace ahora o lo que haría.
    public func detalle(_ c: ConexionPuesta) -> String {
        switch c {
        case .claude:
            return claude.info().texto
        case .mail:
            if let e = enEjemplo[.mail] { return e }
            if estado(.mail) == .conectado, let cuenta = ajustesMail.cuenta {
                let n = ajustesMail.privados.count
                return "El Cartero mira la bandeja de entrada de «\(cuenta)»" + (n == 0 ? "." : n == 1 ? "; 1 remitente privado." : "; \(n) remitentes privados.")
            }
            if permisoMail?.necesitaRecuperacion == true { return "Falta el permiso de Mail en Ajustes del Sistema. Nada se ha tocado en tu correo." }
            return Self.queHaceMail
        case .calendario:
            if let e = enEjemplo[.calendario] { return e }
            if case .conectado(let r) = faseCalendario {
                return "Calendario «The Last System»" + (r.map { ": \($0)." } ?? ".") + " Sin invitar a nadie."
            }
            if permisoCalendario?.necesitaRecuperacion == true { return "Falta el permiso de Calendarios en Ajustes del Sistema. Tus fichas siguen igual." }
            return Self.queCreaCalendario
        case .banco:
            return "Importas el extracto de tu banco en 4 · Finanzas › Banco y la app concilia contigo. Sin dar las claves de tu banco."
        case .otros:
            let activos = programas.filter { $0.estado == .conectado }
            if !activos.isEmpty {
                return activos.map(\.nombre).joined(separator: ", ") + (revisiones.isEmpty ? "." : ". Hay herramientas nuevas por revisar.")
            }
            return "Web y formularios, GoHighLevel, Stripe, Calendly u otro: lo que llega queda en tus fichas y lo que cambia allí pide tu OK."
        case .avisos:
            return "Avisos del Mac solo de lo que está en rojo y de lo que espera tu OK: como mucho 3 al día que no sean rojos. Apagados de serie."
        case .ventanaCerrada:
            return "La app se abre al iniciar sesión y se queda en la barra de menús: los asistentes siguen con lo suyo aunque cierres la ventana. Apagado de serie."
        }
    }

    public static let queHaceMail = "Solo leo la bandeja de entrada de las cuentas que elijas; nunca envío, muevo ni borro nada."
    public static let queCreaCalendario = "Pongo en un calendario propio, «The Last System», tus rituales y las sesiones con clientes, sin invitar a nadie."

    /// En el paso: la respuesta; en Ajustes: «Ahora no» recordado.
    public func eleccion(_ c: ConexionPuesta) -> Bool? {
        switch modo {
        case .paso(let e): return e.leer(c)
        case .ajustes: return ahoraNoElegidas.contains(c) ? false : nil
        }
    }

    /// «Ahora no» en una fila: no se conecta nada, se cierra su panel y se recuerda. En avisos y ventana cerrada, apaga.
    public func ahoraNo(_ c: ConexionPuesta) async {
        if abierta == c { abierta = nil }
        switch c {
        case .mail:
            if case .conectado = faseMail {} else { faseMail = .inicio }
        case .calendario:
            if case .conectado = faseCalendario {} else { faseCalendario = .inicio }
        case .avisos: await presencia.encenderAvisos(false)
        case .ventanaCerrada: presencia.ventanaCerrada = false
        default: break
        }
        switch modo {
        case .paso(let e): await e.elegir(c, false)
        case .ajustes:
            ahoraNoElegidas.insert(c)
            guardarAhoraNo()
        }
    }

    /// La persona eligió conectar (en el paso, su respuesta; en Ajustes, deja de estar en «Ahora no»).
    func elegirConectar(_ c: ConexionPuesta) async {
        switch modo {
        case .paso(let e): await e.elegir(c, true)
        case .ajustes:
            if ahoraNoElegidas.remove(c) != nil { guardarAhoraNo() }
        }
    }

    private func guardarAhoraNo() {
        guard let defaults, let empresa else { return }
        defaults.set(ahoraNoElegidas.map(\.rawValue).sorted(), forKey: Self.clave(empresa))
    }

    /// Abre (o cierra) el panel de una fila.
    public func alternar(_ c: ConexionPuesta) { abierta = abierta == c ? nil : c }

    // MARK: Claude, banco, avisos y ventana cerrada

    public func encender(_ c: ConexionPuesta) async {
        switch c {
        case .avisos: await presencia.encenderAvisos(true)
        case .ventanaCerrada: presencia.ventanaCerrada = true
        case .claude: await claude.buscar()
        default: break
        }
        await elegirConectar(c)
    }

    // MARK: Mail

    /// «Conectar» Mail: según el permiso, la explicación (antes del aviso), la recuperación o las cuentas.
    public func conectarMail() async {
        guard enEjemplo[.mail] == nil else { return }
        abierta = .mail
        guard let s = servicios else { return }
        faseMail = .comprobando
        switch await s.situacion(.mail) {
        case .listo:
            permisoMail = .concedido
            await leerCuentas()
        case .explicar:
            permisoMail = .sinPreguntar
            faseMail = .explicacion(await s.explicar(.mail))
        case .recuperar(let r):
            permisoMail = .denegado
            faseMail = .recuperacion(r)
        case .sinComprobar:
            permisoMail = .desconocido
            await leerCuentas()
        }
    }

    /// «Continuar» en la explicación: ahora sí, el aviso de macOS.
    public func continuarMail() async {
        guard let s = servicios, case .explicacion(let e) = faseMail else { return }
        faseMail = .comprobando
        do {
            let r = try await s.pedir(.mail, tras: e)
            permisoMail = r
            switch r {
            case .concedido, .desconocido: await leerCuentas()
            case .denegado, .restringido:
                if case .recuperar(let rec) = await s.situacion(.mail) { faseMail = .recuperacion(rec) }
                else { faseMail = .recuperacion(ServiciosDeConexionesEnMemoria.recuperacion(.mail)) }
            case .sinPreguntar: faseMail = .inicio
            }
        } catch {
            faseMail = .error(error.localizedDescription)
        }
    }

    func leerCuentas() async {
        guard let s = servicios else { return }
        switch await s.cuentasDeMail() {
        case .cuentas(let cs):
            if ajustesMail.cuenta == nil || !cs.contains(ajustesMail.cuenta ?? "") { ajustesMail.cuenta = cs.first }
            faseMail = cs.isEmpty ? .error("Mail no tiene ninguna cuenta. Añade una en Mail y vuelve a intentarlo.") : .cuentas(cs)
        case .mailCerrado: faseMail = .mailCerrado
        case .sinPermiso(let r):
            permisoMail = .denegado
            faseMail = .recuperacion(r)
        case .fallo(let t): faseMail = .error(t)
        }
    }

    /// «Volver a mirar» (Mail estaba cerrado o el permiso se cambió en Ajustes del Sistema).
    public func volverAMirarMail() async {
        await conectarMail()
    }

    /// Añade un remitente o dominio privado (`persona@dominio`, `@dominio` o `dominio`).
    public func anadirPrivado() {
        let patron = nuevoPrivado.patron.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let etiqueta = nuevoPrivado.etiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.patronValido(patron) else {
            errorPrivado = "Escribe una dirección (nombre@dominio.es) o un dominio (dominio.es)."
            return
        }
        guard !etiqueta.isEmpty else {
            errorPrivado = "Pon un nombre neutro: es lo único que verá el Cartero («correo privado de …»)."
            return
        }
        guard !ajustesMail.privados.contains(where: { $0.patron == patron }) else {
            errorPrivado = "Ya está en la lista."
            return
        }
        ajustesMail.privados.append(RemitentePrivadoConexion(patron: patron, etiqueta: etiqueta))
        nuevoPrivado = RemitentePrivadoConexion(patron: "", etiqueta: "")
        errorPrivado = nil
    }

    public func quitarPrivado(_ patron: String) {
        ajustesMail.privados.removeAll { $0.patron == patron }
    }

    static func patronValido(_ p: String) -> Bool {
        guard !p.isEmpty, !p.contains(" "), p.contains(".") else { return false }
        let partes = p.split(separator: "@", omittingEmptySubsequences: false)
        guard partes.count <= 2 else { return false }
        let dominio = partes.last.map(String.init) ?? ""
        return !dominio.isEmpty && !dominio.hasPrefix(".") && !dominio.hasSuffix(".")
    }

    /// «Conectar Mail»: guarda la cuenta y los privados (fuera de la carpeta) y, si se pidió, activa al Cartero (como tú).
    public func terminarMail() async {
        guard let s = servicios, ajustesMail.cuenta != nil else { return }
        trabajando = true
        defer { trabajando = false }
        do {
            try await s.guardarAjustesDeMail(ajustesMail)
            if activarCartero != carteroActivo {
                try await s.activarCartero(activarCartero)
                carteroActivo = activarCartero
            }
            faseMail = carteroActivo ? .conectado : .inicio
            if carteroActivo { await elegirConectar(.mail) }
        } catch {
            faseMail = .error(error.localizedDescription)
        }
    }

    /// «Cambiar»: vuelve a la cuenta y los privados.
    public func cambiarMail() async {
        abierta = .mail
        await leerCuentas()
    }

    /// «Desconectar»: el Cartero deja de trabajar (la cuenta y los privados se quedan guardados).
    public func desconectarMail() async {
        guard let s = servicios else { return }
        do {
            try await s.activarCartero(false)
            carteroActivo = false
            faseMail = .inicio
        } catch {
            faseMail = .error(error.localizedDescription)
        }
    }

    // MARK: Calendario

    /// F5 · corrector (P2-7): «Desconectar»: la app deja de poner tus rituales en Calendario (lo que ya está, se queda).
    public func desconectarCalendario() async {
        guard let s = servicios else { return }
        do {
            try await s.desconectarCalendario()
            faseCalendario = .inicio
        } catch {
            faseCalendario = .error(error.localizedDescription)
        }
    }

    public func conectarCalendario() async {
        guard enEjemplo[.calendario] == nil else { return }
        abierta = .calendario
        guard let s = servicios else { return }
        faseCalendario = .comprobando
        switch await s.situacion(.calendario) {
        case .listo:
            permisoCalendario = .concedido
            await crearCalendario()
        case .explicar:
            permisoCalendario = .sinPreguntar
            faseCalendario = .explicacion(await s.explicar(.calendario))
        case .recuperar(let r):
            permisoCalendario = .denegado
            faseCalendario = .recuperacion(r)
        case .sinComprobar:
            faseCalendario = .inicio
        }
    }

    public func continuarCalendario() async {
        guard let s = servicios, case .explicacion(let e) = faseCalendario else { return }
        faseCalendario = .comprobando
        do {
            let r = try await s.pedir(.calendario, tras: e)
            permisoCalendario = r
            switch r {
            case .concedido: await crearCalendario()
            case .denegado, .restringido:
                if case .recuperar(let rec) = await s.situacion(.calendario) { faseCalendario = .recuperacion(rec) }
                else { faseCalendario = .recuperacion(ServiciosDeConexionesEnMemoria.recuperacion(.calendario)) }
            default: faseCalendario = .inicio
            }
        } catch {
            faseCalendario = .error(error.localizedDescription)
        }
    }

    func crearCalendario() async {
        guard let s = servicios else { return }
        switch await s.conectarCalendario() {
        case .conectado(let r):
            faseCalendario = .conectado(resumen: r)
            await elegirConectar(.calendario)
        case .sinPermiso(let rec):
            permisoCalendario = .denegado
            faseCalendario = .recuperacion(rec)
        case .sinConectar: faseCalendario = .inicio
        case .fallo(let t): faseCalendario = .error(t)
        }
    }

    // MARK: Recuperación

    /// «Abrir Ajustes del Sistema».
    public func abrirAjustes(_ r: RecuperacionDeConexion) { abrirEnlace(r.enlace) }

    /// «Ya lo he cambiado»: se vuelve a mirar sin preguntar a macOS.
    public func volverAMirar(_ p: PermisoDeConexion) async {
        switch p {
        case .mail:
            faseMail = .inicio
            await conectarMail()
        case .calendario:
            faseCalendario = .inicio
            await conectarCalendario()
        }
    }

    // MARK: Otros programas

    public func empezarAlta(_ p: PlantillaDeOtroPrograma) {
        abierta = .otros
        alta = BorradorDeOtroPrograma(plantilla: p)
        errorAlta = nil
    }

    public func cancelarAlta() {
        alta = nil
        errorAlta = nil
    }

    /// Un identificador corto (2–20 minúsculas o cifras) a partir del nombre, sin repetir.
    public func idNuevo(_ nombre: String) -> String {
        let base = nombre.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased().filter { ($0.isASCII && $0.isLetter) || $0.isNumber }
        var raiz = String(base.prefix(18))
        if raiz.count < 2 { raiz = "programa" }
        var id = raiz
        var n = 2
        while programas.contains(where: { $0.id == id }) {
            id = String(raiz.prefix(18 - String(n).count)) + "\(n)"
            n += 1
        }
        return id
    }

    /// Lo que falta en el alta, en una frase (o `nil` si se puede añadir).
    public func faltaEnAlta(_ b: BorradorDeOtroPrograma) -> String? {
        let d = b.direccion.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.nombre.trimmingCharacters(in: .whitespaces).isEmpty { return "Ponle un nombre." }
        if d.isEmpty { return "Pega la dirección que te da \(b.plantilla.nombre)." }
        guard let u = URL(string: d), let esquema = u.scheme?.lowercased(),
              esquema == "https" || (esquema == "http" && (u.host == "localhost" || u.host == "127.0.0.1")) else {
            return "La dirección tiene que empezar por https://."
        }
        if u.user != nil || u.password != nil || (u.query ?? "").lowercased().contains("token") || (u.query ?? "").lowercased().contains("key") {
            return "La dirección no puede llevar la clave dentro: pégala en su campo, que va al Llavero."
        }
        if b.plantilla.clave != nil, b.clave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Pega la clave de acceso." }
        return nil
    }

    /// «Añadir y probar»: la clave va al Llavero (por `anadir`) y se olvida aquí; luego se prueba.
    public func anadirPrograma() async {
        guard let s = servicios, var b = alta else { return }
        if let f = faltaEnAlta(b) { errorAlta = f; return }
        trabajando = true
        defer { trabajando = false }
        let id = idNuevo(b.nombre)
        let clave = b.clave.trimmingCharacters(in: .whitespacesAndNewlines)
        b.clave = ""
        alta = b
        do {
            try await s.anadir(AltaDeOtroPrograma(id: id, nombre: b.nombre.trimmingCharacters(in: .whitespaces), plantilla: b.plantilla.id,
                                                  transporte: .web(direccion: b.direccion.trimmingCharacters(in: .whitespacesAndNewlines)),
                                                  clave: clave.isEmpty ? nil : clave))
            alta = nil
            errorAlta = nil
            await elegirConectar(.otros)
            await probar(id)
        } catch {
            errorAlta = error.localizedDescription
        }
    }

    /// Añade un programa de este Mac (Avanzado): sin claves y solo con el aviso aceptado.
    public func anadirProgramaLocal() async {
        guard let s = servicios else { return }
        let ejecutable = local.ejecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !local.nombre.trimmingCharacters(in: .whitespaces).isEmpty, ejecutable.hasPrefix("/") else {
            errorAlta = "Pon un nombre y la ruta completa del programa (empieza por /)."
            return
        }
        guard local.avisoAceptado else { errorAlta = "Lee el aviso y márcalo antes de añadirlo."; return }
        let id = idNuevo(local.nombre)
        do {
            try await s.anadir(AltaDeOtroPrograma(
                id: id, nombre: local.nombre, plantilla: "generico",
                transporte: .local(ejecutable: ejecutable, argumentos: local.argumentos.split(separator: " ").map(String.init),
                                   avisoAceptado: true),
                clave: nil))
            local = BorradorProgramaLocal()
            errorAlta = nil
            await probar(id)
        } catch {
            errorAlta = error.localizedDescription
        }
    }

    public func probar(_ id: String) async {
        guard let s = servicios else { return }
        do {
            mensajes[id] = try await s.probar(id)
            tecnicos[id] = nil
        } catch {
            mensajes[id] = "No responde. Comprueba la dirección y la clave, o prueba más tarde."
            tecnicos[id] = error.localizedDescription
        }
        await leerOtros()
    }

    public func sincronizar(_ id: String) async {
        guard let s = servicios else { return }
        do {
            mensajes[id] = try await s.sincronizarAhora(id)
            tecnicos[id] = nil
        } catch {
            mensajes[id] = "No se ha podido sincronizar ahora. Lo vuelvo a intentar en la próxima ronda."
            tecnicos[id] = error.localizedDescription
        }
        await leerOtros()
    }

    public func cambiarInterruptor(_ programa: String, _ i: InterruptorDeOtroPrograma, encender: Bool) async {
        guard let s = servicios else { return }
        do {
            try await s.cambiarInterruptor(programa, permiso: i.id, encender: encender)
        } catch {
            problema = error.localizedDescription
        }
        await leerOtros()
    }

    public func revisar(_ r: RevisionDeOtroPrograma, aceptar: Bool) async {
        guard let s = servicios else { return }
        do {
            try await s.revisar(r, aceptar: aceptar)
        } catch {
            problema = error.localizedDescription
        }
        await leerOtros()
    }

    public func pausar(_ id: String, _ pausado: Bool) async {
        guard let s = servicios else { return }
        do { try await s.pausar(id, pausado) } catch { problema = error.localizedDescription }
        await leerOtros()
    }

    public func quitar(_ id: String) async {
        guard let s = servicios else { return }
        do { try await s.quitar(id) } catch { problema = error.localizedDescription }
        mensajes[id] = nil
        tecnicos[id] = nil
        matrices[id] = nil
        await leerOtros()
    }

    /// La matriz técnica de un programa (Ajustes › Avanzado).
    public func leerMatriz(_ id: String) async {
        guard let s = servicios else { return }
        matrices[id] = await s.matriz(id)
    }

    public func leerMatrices() async {
        for p in programas { await leerMatriz(p.id) }
    }
}
