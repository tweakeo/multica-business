import AppKit
import Observation
import os
import TLSCore
import TLSDesign

/// El tutorial de una empresa abierta: qué recorrido va, en qué paso está, qué partes se han hecho y qué enseña la
/// burbuja. Uno por sesión (lo comparten sus pestañas). Nunca escribe en la carpeta: solo lee lo que cambió y guarda
/// su avance en `tutorial.json`.
@MainActor
@Observable
public final class ControladorTutorial {
    private static let log = Logger(subsystem: "es.thelast.system", category: "Tutorial")

    // MARK: Uno por sesión

    private final class Entrada {
        weak var sesion: VaultSession?
        let controlador: ControladorTutorial
        init(_ s: VaultSession, _ c: ControladorTutorial) { sesion = s; controlador = c }
    }

    private static var porSesion: [ObjectIdentifier: Entrada] = [:]

    /// El de una sesión (se crea la primera vez). Una sesión con su estado aparte (las pruebas) guarda el tutorial
    /// junto a ese estado y nunca empieza sola: así ninguna prueba toca el Application Support de verdad.
    public static func de(_ sesion: VaultSession, almacen: AlmacenTutorial? = nil, appSupport: URL? = nil) -> ControladorTutorial {
        porSesion = porSesion.filter { $0.value.sesion != nil }
        let k = ObjectIdentifier(sesion)
        if let e = porSesion[k], e.sesion === sesion { return e.controlador }
        let deLaApp = sesion.estado == nil
        let base = appSupport ?? (deLaApp ? AppLocations.appSupport : sesion.directorioEstado.deletingLastPathComponent())
        let a = almacen ?? (deLaApp ? .compartido : AlmacenTutorial(archivo: base.appendingPathComponent(AlmacenTutorial.nombreFichero)))
        let c = ControladorTutorial(sesion: sesion, almacen: a, appSupport: base, empiezaSolo: deLaApp)
        porSesion[k] = Entrada(sesion, c)
        return c
    }

    /// El de una empresa abierta, si hay ventana.
    static func abierto(empresa: UUID) -> ControladorTutorial? {
        porSesion.values.first { $0.sesion?.entry.id == empresa }?.controlador
    }

    /// «Repasar la puesta en marcha» del ejemplo: lo pone quien tenga la pantalla de la puesta en marcha. Sin él, el
    /// botón no sale.
    public static var repasarPuestaEnMarcha: (@MainActor (VaultSession) -> Void)?

    // MARK: Estado

    @ObservationIgnored weak var sesion: VaultSession?
    let empresa: UUID
    let almacen: AlmacenTutorial
    /// Donde está `onboarding.json` (el de la app o, en pruebas, uno temporal).
    let appSupport: URL
    /// El ejemplo empieza su recorrido solo la primera vez (no en las pruebas).
    let empiezaSolo: Bool
    /// El recorrido que va (el ejemplo en Ribera; el tuyo en tu empresa).
    let tipo: TipoRecorrido
    private(set) var pasos: [PasoTutorial]
    private(set) var estado: EstadoRecorrido
    private(set) var contexto = ContextoRecorrido.vacio
    /// La última ficha que se tocó (para «Mostrar en Finder»).
    private(set) var ultimaFicha: VaultPath?
    /// Sube cuando cambia algo que se ve en la burbuja aunque no cambie el estado (anclas, navegación).
    private(set) var pulso = 0

    @ObservationIgnored let observador = ObservadorCarpeta()
    @ObservationIgnored weak var ventana: NSWindow?
    /// «Mostrar en Finder». Por defecto, el de la sesión (las pruebas ponen otro para no abrir el Finder).
    @ObservationIgnored var revelar: ((VaultPath?) -> Void)?
    @ObservationIgnored private var monitorClics: Any?
    @ObservationIgnored private var preparando = false
    /// Ventanas (pestañas) con la raíz del tutorial puesta.
    @ObservationIgnored var raices = 0

    init(sesion: VaultSession, almacen: AlmacenTutorial, appSupport: URL, empiezaSolo: Bool) {
        self.sesion = sesion
        self.empresa = sesion.entry.id
        self.almacen = almacen
        self.appSupport = appSupport
        self.empiezaSolo = empiezaSolo
        let tipo: TipoRecorrido = sesion.entry.clase == .demo ? .ejemplo : .tuEmpresa
        self.tipo = tipo
        self.estado = almacen.estado(tipo, empresa: sesion.entry.id)
        self.pasos = Recorridos.pasos(tipo)
    }

    /// Va un recorrido y se ve.
    public var activo: Bool { estado.fase == .enCurso }

    var indice: Int { min(max(estado.paso, 0), max(pasos.count - 1, 0)) }

    var pasoActual: PasoTutorial? { activo && !pasos.isEmpty ? pasos[indice] : nil }

    /// Pasos con algo que hacer ya (los de asistentes no cuentan).
    var pasosConAccion: [PasoTutorial] { pasos.filter(\.tieneAccion) }

    var hechos: Int { pasosConAccion.filter { $0.hecho(estado.partesHechas) }.count }

    /// «Quedan ~N min» desde el paso actual.
    var quedanMinutos: Int {
        let restantes = pasos[indice...].filter { !$0.hecho(estado.partesHechas) }
        return max(1, Int(restantes.reduce(0) { $0 + $1.minutos }.rounded(.up)))
    }

    // MARK: Empezar, pausar, terminar

    /// Al abrir la empresa: en el ejemplo, la puesta en marcha queda hecha y el recorrido empieza solo la primera vez;
    /// si se dejó a medias, sigue donde estaba.
    func alAbrir() async {
        guard let sesion, sesion.isReady else { return }
        if tipo == .ejemplo {
            EjemploTutorial.prepararPuestaEnMarcha(sesion, appSupport: appSupport)
            if empiezaSolo, estado.fase == .sinEmpezar { await empezar() }
        }
        if estado.fase == .enCurso { await prepararObservacion() }
    }

    /// Empieza (o retoma) el recorrido de esta empresa.
    public func empezar() async {
        almacen.cambiar(tipo, empresa: empresa) { e in
            if e.fase == .terminado { e.paso = 0 }
            e.fase = .enCurso
        }
        refrescar()
        await prepararObservacion()
    }

    /// «Seguir más tarde»: se oculta y se retoma en el mismo paso.
    public func seguirMasTarde() {
        almacen.cambiar(tipo, empresa: empresa) { $0.fase = .enPausa }
        refrescar()
        pararMonitor()
    }

    func terminar() {
        almacen.cambiar(tipo, empresa: empresa) { $0.fase = .terminado }
        refrescar()
        pararMonitor()
    }

    func irA(_ i: Int) {
        guard !pasos.isEmpty else { return }
        let nuevo = min(max(i, 0), pasos.count - 1)
        almacen.cambiar(tipo, empresa: empresa) { $0.paso = nuevo }
        refrescar()
    }

    private func refrescar() {
        estado = almacen.estado(tipo, empresa: empresa)
        actualizarMonitor()
    }

    /// Foto de partida y contexto (ficha y cuello). Una vez por apertura; en segundo plano.
    private func prepararObservacion() async {
        guard !preparando, !observador.preparado, let sesion else { return }
        preparando = true
        defer { preparando = false }
        guard let foto = await sesion.instantanea() else { return }
        let hoy = sesion.hoy
        let tipo = self.tipo
        let contexto = await Task.detached(priority: .utility) { () -> ContextoRecorrido in
            Self.contexto(tipo, foto: foto, hoy: hoy)
        }.value
        let huellas = await Task.detached(priority: .utility) { ObservadorCarpeta.huellas(foto) }.value
        observador.preparar(huellas: huellas, layout: foto.layout)
        self.contexto = contexto
        pasos = Recorridos.pasos(tipo, contexto: contexto)
        actualizarMonitor()
    }

    nonisolated static func contexto(_ tipo: TipoRecorrido, foto: VaultSnapshot, hoy: LocalDate) -> ContextoRecorrido {
        switch tipo {
        case .ejemplo:
            let ficha = foto.existing(Recorridos.fichaEjemplo)
                ?? foto.notes.first { $0.raw.hasPrefix("2 · Ventas/Contactos/") && $0.name != "Contactos.md" }
            return ContextoRecorrido(ficha: ficha, cuello: nil)
        case .tuEmpresa:
            let cuello = DatosDireccion.calcular(foto: foto, hoy: hoy).mapa.cuello?.area
            let ficha = foto.existing(VaultPath("Empresa.md"))
                ?? cuello.flatMap { foto.existing(foto.layout.areaFolder($0).appending("Área.md")) }
            return ContextoRecorrido(ficha: ficha, cuello: cuello)
        }
    }

    // MARK: Eventos

    /// Algo real que pasó en la app. Solo cuenta mientras va el recorrido.
    public func registrar(_ evento: TutorialEvent) {
        guard activo else { return }
        if let r = evento.ruta { ultimaFicha = r }
        let parte = evento.parte
        guard estado.partes[parte] == nil else { return }
        let antes = pasoActual.map { $0.hecho(estado.partesHechas) } ?? false
        let pasosDef = pasos
        let tipo = self.tipo
        almacen.cambiar(tipo, empresa: empresa) { e in
            let ahora = Date()
            e.partes[parte] = ahora
            let hechas = e.partesHechas
            switch tipo {
            case .ejemplo:
                for h in HitoTutorial.allCases where e.hitos[h.rawValue] == nil && Set(h.partes).isSubset(of: hechas) {
                    e.hitos[h.rawValue] = ahora
                }
            case .tuEmpresa:
                for p in pasosDef where p.tieneAccion && e.hitos[p.id] == nil && p.hecho(hechas) {
                    e.hitos[p.id] = ahora
                }
            }
        }
        let nuevos = Set(almacen.estado(tipo, empresa: empresa).hitos.keys).subtracting(estado.hitos.keys)
        refrescar()
        if tipo == .tuEmpresa {
            for h in nuevos { PuenteRecorrido.marcar(h, empresa: empresa, appSupport: appSupport) }
        }
        if let paso = pasoActual, !antes, paso.hecho(estado.partesHechas) {
            TutorialAnuncio.anunciar("Hecho: \(paso.titulo)")
        }
    }

    /// Cambió lo que se ve en la pestaña.
    func navego(a destino: Destino) {
        if case .area(let a, _) = destino { registrar(.areaVista(a)) }
        pulso &+= 1
    }

    /// Apareció, se fue o se movió alguna ancla.
    func anclasCambiaron() {
        guard activo else { return }
        let presentes = TutorialAnclas.compartidas.presentes(en: ventana)
        if presentes.contains(.direccionMapa) { registrar(.mapaVisto) }
        pulso &+= 1
    }

    /// Se escribió en la carpeta (la app o fuera): se mira qué cambió.
    func carpetaCambio(_ rutas: Set<VaultPath>) async {
        guard activo, let sesion else { return }
        if !observador.preparado { await prepararObservacion(); return }
        let eventos: [TutorialEvent]
        if rutas.isEmpty {
            guard let foto = await sesion.instantanea() else { return }
            eventos = observador.cambios(foto: foto)
        } else {
            eventos = observador.cambios(rutas, leer: { r in
                sesion.url(for: r).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            }, existe: { r in
                sesion.url(for: r).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            })
        }
        for e in eventos { registrar(e) }
    }

    // MARK: Clics dentro del sitio señalado

    private func actualizarMonitor() {
        let quiere = pasoActual?.porClic == true && pasoActual.map { !$0.hecho(estado.partesHechas) } == true
        if quiere, monitorClics == nil {
            monitorClics = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] evento in
                MainActor.assumeIsolated { self?.clic(evento) }
                return evento
            }
        } else if !quiere {
            pararMonitor()
        }
    }

    private func clic(_ evento: NSEvent) {
        guard let w = evento.window else { return }
        clic(en: w, punto: evento.locationInWindow)
    }

    /// Un clic en `punto` (coordenadas de la ventana, como `NSEvent.locationInWindow`): si cae dentro del sitio
    /// señalado por un paso «por clic», es la acción del paso.
    func clic(en w: NSWindow, punto: NSPoint) {
        guard let paso = pasoActual, paso.porClic, let ancla = paso.ancla else { return }
        if let ventana, w !== ventana { return }
        if TutorialAnclas.compartidas.contiene(ancla, punto: punto, en: w), ancla == .hoyFoco {
            registrar(.focoDeHoy)
        }
    }

    func pararMonitor() {
        if let m = monitorClics { NSEvent.removeMonitor(m) }
        monitorClics = nil
    }
}
