import AppKit
import EventKit
import Foundation
import OSLog
import TLSAgents
import TLSCore
import TLSGateway
import TLSIntegrations
import TLSMCPHost
import TLSUI

// F5 · integración (PLAN §7 y §8, «Cambios pedidos» de docs/F5-CONTRATOS.md). Las conexiones de **una** empresa abierta
// con escritor, montadas y paradas con ella (como el motor de los asistentes de F4):
//
// - Mail: `LectorDeCorreo` (JXA lanzado por la app, nunca por un asistente) en rondas de 15 minutos con el Cartero activo
//   y los asistentes encendidos, y justo antes de cada trabajo del Cartero (el triaje de las 08:30 lee lo último). Lo
//   guardado (`AlmacenDeCorreo`, fuera de la carpeta) es lo que lee `tls_correo_pendiente`. Automatización denegada →
//   tarjeta en Decisiones y no se vuelve a intentar hasta que la persona lo pida. Al aprobar un correo, `MailComposer`
//   abre la redacción en Mail: el clic de Enviar es de la persona.
// - Calendario: `SincronizadorCalendario` (de ficheros a calendario, sin invitados) al abrir, con cada cambio de la
//   carpeta y con `EKEventStoreChanged`; sus tarjetas («¿Actualizo la ficha?») en Decisiones; lo ocupado de otros
//   calendarios en Hoy y en `tls_agenda` (solo bloques «Ocupado»).
// - Otros programas: `Pasarela` (claves en el Llavero), `ExposicionExterna` en `tls-mcp`, `GatewayRouter` al aprobar,
//   la revisión de herramientas nuevas en Decisiones y la sincronización de cada conector cada 5 minutos (con los
//   asistentes encendidos).
//
// En el ejemplo (Ribera) Mail y Calendario no se conectan (nada del Mac de verdad) y «Otros programas» trae un programa
// de mentira marcado «Simulado» (`ConectorSimulado`), con un llavero en memoria.

/// Lo del sistema que usan las conexiones: en la app, lo de verdad; en pruebas, dobles (nunca Mail, EventKit, TCC ni el
/// Llavero reales en pruebas).
public struct SistemaDeConexiones: Sendable {
    public var permisos: any ConsultorDePermisos
    public var jxa: any EjecutorJXA
    public var redactor: any RedactorDeMail
    public var eventos: @Sendable () -> any AlmacenDeEventos
    public var llavero: any AlmacenDeSecretos
    /// La fábrica de clientes de otros programas para una empresa: su directorio de estado y las carpetas que un programa
    /// de este Mac no puede leer (todas las empresas).
    public var fabrica: @Sendable (_ estado: URL, _ prohibidas: [String]) -> any FabricaDeClientes
    /// Escuchar `EKEventStoreChanged` (solo la app).
    public var escucharCalendario: Bool
    /// Cada cuánto se lee el correo y se miran las sincronizaciones pendientes.
    public var rondaCorreo: TimeInterval
    public var rondaPasarela: TimeInterval
    public var ahora: @Sendable () -> Date

    public init(permisos: any ConsultorDePermisos, jxa: any EjecutorJXA, redactor: any RedactorDeMail,
                eventos: @escaping @Sendable () -> any AlmacenDeEventos, llavero: any AlmacenDeSecretos,
                fabrica: @escaping @Sendable (URL, [String]) -> any FabricaDeClientes, escucharCalendario: Bool = false,
                rondaCorreo: TimeInterval = 15 * 60, rondaPasarela: TimeInterval = 5 * 60,
                ahora: @escaping @Sendable () -> Date = { Date() }) {
        self.permisos = permisos; self.jxa = jxa; self.redactor = redactor; self.eventos = eventos; self.llavero = llavero
        self.fabrica = fabrica; self.escucharCalendario = escucharCalendario; self.rondaCorreo = rondaCorreo
        self.rondaPasarela = rondaPasarela; self.ahora = ahora
    }

    /// Lo del Mac de verdad. **Solo la app** (`TheLastSystemApp`): permisos de macOS, `osascript`, EventKit y el Llavero.
    public static var delMac: SistemaDeConexiones {
        let jxa = EjecutorJXAOsascript()
        return SistemaDeConexiones(
            permisos: ConsultorDePermisosDelSistema(), jxa: jxa, redactor: RedactorDeMailJXA(ejecutor: jxa),
            eventos: { AlmacenEventKit() }, llavero: LlaveroDelSistema(),
            fabrica: { estado, prohibidas in
                FabricaMCP(directorioStdio: { c in
                    estado.appendingPathComponent("conexiones", isDirectory: true).appendingPathComponent(c.id, isDirectory: true)
                }, carpetasProhibidas: prohibidas)
            },
            escucharCalendario: true)
    }
}

@MainActor
public final class ConexionesDeEmpresa {
    public let piezas: PiezasDeLaEmpresa
    public let sistema: SistemaDeConexiones
    public private(set) weak var sesion: VaultSession?
    /// El motor de los asistentes de la empresa (su servidor de herramientas registra lo que llega de otros programas).
    weak var motor: MotorDeEmpresa?

    /// En el ejemplo: sin Mail ni Calendario, y otros programas simulados.
    public let ejemplo: Bool
    public let puerta: PuertaDePermisos?
    public let lector: LectorDeCorreo?
    public let almacenDeCorreo: AlmacenDeCorreo?
    public let calendario: SincronizadorCalendario?
    let mapa: MapaCalendario?
    public let pasarela: Pasarela
    public let exposicion: ExposicionExterna
    /// El adaptador de la pantalla Conexiones (y del paso 7).
    public private(set) var servicios: ServiciosDeConexionesDeLaApp!

    public private(set) var arrancada = false
    private var rondas: [Task<Void, Never>] = []
    private var observadorCalendario: NSObjectProtocol?
    private var calendarioPendiente: Task<Void, Never>?
    /// Lo último de cada pieza (diagnóstico y pruebas).
    public private(set) var ultimaLectura: ResultadoDeLectura?
    public private(set) var ultimoInforme: InformeCalendario?
    public private(set) var ultimasSincronizaciones: [InformeDeSincronizacion] = []
    private static let log = Logger(subsystem: "es.thelast.system", category: "Conexiones")

    public init(sesion: VaultSession, piezas: PiezasDeLaEmpresa, sistema: SistemaDeConexiones, prohibidas: [String] = []) throws {
        self.sesion = sesion
        self.piezas = piezas
        self.sistema = sistema
        ejemplo = piezas.esEjemplo
        let estado = piezas.estadoDeCarpeta
        let zona = Self.zona(root: piezas.root)
        if ejemplo {
            puerta = nil
            lector = nil
            almacenDeCorreo = nil
            calendario = nil
            mapa = nil
            pasarela = Pasarela(almacen: AlmacenDeConexiones(directorio: estado), llavero: LlaveroEnMemoria(),
                                fabrica: FabricaSimulada(), ahora: sistema.ahora)
        } else {
            puerta = PuertaDePermisos(consultor: sistema.permisos)
            let almacen = AlmacenDeCorreo(estado: estado, zona: zona)
            almacenDeCorreo = almacen
            lector = LectorDeCorreo(ejecutor: sistema.jxa, almacen: almacen, cursor: try CursorDeCorreo(estado: estado),
                                    ajustes: { AjustesDeCorreo.leer(estado) }, ahora: sistema.ahora)
            let mapa = try MapaCalendario(directory: estado)
            self.mapa = mapa
            calendario = SincronizadorCalendario(almacen: sistema.eventos(), mapa: mapa, reloj: sistema.ahora)
            pasarela = Pasarela(almacen: AlmacenDeConexiones(directorio: estado), llavero: sistema.llavero,
                                fabrica: sistema.fabrica(estado, prohibidas), ahora: sistema.ahora)
        }
        exposicion = ExposicionExterna.deGobierno(pasarela, autorizador: piezas.autorizador)
        servicios = ServiciosDeConexionesDeLaApp(conexiones: self)
    }

    // MARK: Lo que pone en `tls-mcp` y en el motor

    /// `tls_correo_pendiente` (Mail), `tls_agenda` (lo ocupado del Calendario) y `ext_*` (otros programas).
    func completar(_ deps: inout ServidorDeHerramientas.Dependencias) {
        deps.externas = exposicion
        guard !ejemplo else { return }
        deps.correo = almacenDeCorreo
        if let calendario {
            deps.ocupado = calendario.fuenteDeOcupado(zona: zona)
        }
    }

    /// Antes de cada trabajo del Cartero, el correo más reciente (el triaje de las 08:30 lee lo de esta mañana).
    nonisolated func antesDeLanzar(_ e: Ejecucion) async {
        guard e.agente == ConexionDelCartero.slug else { return }
        await leerCorreo()
    }

    var zona: TimeZone { Self.zona(root: piezas.root) }

    /// La zona de la carpeta (`agenda.zona` de `.tls/config.yaml`; Madrid por defecto).
    nonisolated static func zona(root: URL) -> TimeZone {
        let texto = try? String(contentsOf: VaultPath(VaultLayout.configFile).url(in: root), encoding: .utf8)
        return TimeZone(identifier: ConfigMetricas.leer(texto).zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
    }

    // MARK: Arrancar y parar

    /// Tras montar el motor: huecos de las aprobaciones, tarjetas, rondas y el Calendario en Hoy.
    public func arrancar() async {
        guard !arrancada else { return }
        arrancada = true
        ConexionesDeLaApp.registrar(servicios, para: piezas.entry.id)
        if ejemplo { asegurarConectorSimulado() }
        actualizarHuecos()
        ponerRevisiones()
        await sincronizarCalendario()
        if sistema.escucharCalendario, calendario != nil {
            observadorCalendario = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.calendarioCambio() }
            }
        }
        let rondaCorreo = sistema.rondaCorreo, rondaPasarela = sistema.rondaPasarela
        if lector != nil {
            rondas.append(Task { [weak self] in
                await self?.rondaDeCorreo()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(rondaCorreo))
                    guard !Task.isCancelled else { return }
                    await self?.rondaDeCorreo()
                }
            })
        }
        rondas.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(rondaPasarela))
                guard !Task.isCancelled else { return }
                await self?.rondaDePasarela()
            }
        })
    }

    /// Al cerrar la empresa, pasarla a solo lectura o salir: nada queda en marcha.
    public func parar() async {
        guard arrancada else { return }
        arrancada = false
        for t in rondas { t.cancel() }
        rondas = []
        calendarioPendiente?.cancel()
        calendarioPendiente = nil
        if let o = observadorCalendario { NotificationCenter.default.removeObserver(o) }
        observadorCalendario = nil
        await pasarela.cerrarTodo()
        ConexionesDeLaApp.quitar(para: piezas.entry.id, servicios)
        if let sesion {
            let d = ConexionesEnDecisiones.de(sesion)
            d.huecos.correo = nil
            d.huecos.pasarela = nil
            for origen in ["mail", "calendario"] { d.poner([], origen: origen) }
            for c in pasarela.conexiones() { d.poner([], origen: "pasarela:\(c.id)") }
            await CalendarioEnHoy.conectar(sesion, ocupado: nil)
        }
        mapa?.cerrar()
    }

    /// La carpeta cambió: el Calendario se pone al día (agrupando cambios seguidos).
    public func carpetaCambio() {
        guard arrancada, calendario != nil else { return }
        calendarioPendiente?.cancel()
        calendarioPendiente = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.sincronizarCalendario()
        }
    }

    func calendarioCambio() {
        carpetaCambio()
    }

    // MARK: Mail

    /// ¿Mail está conectado? El Cartero activo (en la configuración confirmada) y una cuenta elegida.
    public var mailConectado: Bool {
        guard !ejemplo else { return false }
        return carteroActivo && AjustesDeCorreo.leer(piezas.estadoDeCarpeta).cuenta?.isEmpty == false
    }

    public var carteroActivo: Bool {
        piezas.autorizador.estadoDeConfig().efectiva.asistente(ConexionDelCartero.slug)?.activo == true
    }

    func interruptorEncendido() async -> Bool {
        await AjustesDeGobierno(autorizador: piezas.autorizador).ajustes().interruptor
    }

    func rondaDeCorreo() async {
        guard arrancada, mailConectado, await interruptorEncendido() else { return }
        await leerCorreo()
    }

    /// Lee el correo nuevo (si Mail está conectado). Con la Automatización denegada, tarjeta en Decisiones; leído bien,
    /// la tarjeta se va.
    @discardableResult
    public func leerCorreo() async -> ResultadoDeLectura? {
        guard let lector, mailConectado else { return nil }
        let r = await lector.leer()
        ultimaLectura = r
        switch r {
        case .automatizacionDenegada(let t):
            ponerPermiso(t, origen: "mail")
        case .leidos:
            sesion.map { ConexionesEnDecisiones.de($0).poner([], origen: "mail") }
        default:
            break
        }
        return r
    }

    /// La persona arregló el permiso de Mail: se puede volver a leer.
    public func reintentarCorreo() async {
        await lector?.reintentar()
        sesion.map { ConexionesEnDecisiones.de($0).poner([], origen: "mail") }
    }

    /// `MailComposer` con Mail conectado; `GatewayRouter` siempre (lo sensible aprobado sale solo por él).
    func actualizarHuecos() {
        guard let sesion else { return }
        let h = ConexionesEnDecisiones.de(sesion).huecos
        h.correo = mailConectado ? MailComposer(redactor: sistema.redactor) : nil
        let exposicion = self.exposicion
        h.pasarela = GatewayRouter(pasarela: pasarela, permiso: { slug, herramienta in await exposicion.permite(slug, herramienta) })
    }

    func ponerPermiso(_ t: TarjetaDePermiso, origen: String) {
        guard let sesion else { return }
        let tarjeta = TarjetaDeConexion.permiso(id: t.id, titulo: t.titulo, texto: t.texto, pasos: t.pasos, boton: t.boton,
                                                enlace: t.enlace, detalleTecnico: t.detalleTecnico, origen: origen)
        ConexionesEnDecisiones.de(sesion).poner([tarjeta], origen: origen)
    }

    // MARK: Calendario

    /// Pone el Calendario al día con la carpeta (solo si esta empresa lo conectó) y lleva sus tarjetas a Decisiones y lo
    /// ocupado a Hoy.
    @discardableResult
    public func sincronizarCalendario() async -> InformeCalendario? {
        guard let calendario, let mapa, let sesion else { return nil }
        let habia = ((try? mapa.calendarioPropio()) ?? nil) != nil
        guard habia else {
            await CalendarioEnHoy.conectar(sesion, ocupado: nil)
            return nil
        }
        let foto = await piezas.foto()
        let informe: InformeCalendario
        do {
            informe = try await calendario.sincronizar(foto: foto)
        } catch {
            Self.log.error("No se pudo poner al día el Calendario: \(String(describing: error), privacy: .public)")
            return nil
        }
        ultimoInforme = informe
        ponerTarjetasDeCalendario(informe)
        let conectado = await calendario.conectado()
        await CalendarioEnHoy.conectar(sesion, ocupado: conectado ? calendario.fuenteDeOcupado(zona: zona) : nil)
        return informe
    }

    /// Permiso (si falta) y «¿Actualizo la ficha?» en **una** llamada con origen «calendario».
    func ponerTarjetasDeCalendario(_ informe: InformeCalendario) {
        guard let sesion, let calendario else { return }
        var tarjetas: [TarjetaDeConexion] = []
        if let t = informe.tarjetaDePermiso {
            tarjetas.append(.permiso(id: t.id, titulo: t.titulo, texto: t.texto, pasos: t.pasos, boton: t.boton, enlace: t.enlace,
                                     detalleTecnico: t.detalleTecnico, origen: "calendario"))
        }
        let persona = piezas.persona
        let foto = piezas.foto
        for t in informe.tarjetas {
            let difs = t.diferencias.map { DiferenciaDeConexion(campo: $0.campo, enFicha: $0.enFicha, enCalendario: $0.enCalendario) }
            switch t.tipo {
            case .cambiadoEnCalendario:
                tarjetas.append(.calendario(
                    id: t.id, titulo: t.titulo, texto: t.texto, diferencias: difs, ruta: t.ruta, boton: t.boton, botonNo: t.botonNo,
                    hacer: { [weak self] in
                        guard let plan = try await calendario.planParaActualizarFicha(t, foto: await foto(), persona: persona) else {
                            return "La ficha ya dice lo mismo que el Calendario."
                        }
                        try await self?.sesion?.escribirComoPersona(plan, aviso: "Ficha actualizada con lo del Calendario.")
                        return "He puesto en la ficha lo que cambiaste en Calendario."
                    },
                    noHacer: { [weak self] in
                        _ = try await calendario.devolverAlaFicha(t, foto: await foto())
                        self?.carpetaCambio()
                        return "El evento vuelve a lo que dice la ficha."
                    }))
            case .quitadoEnCalendario:
                let dejar: @MainActor @Sendable () async throws -> String = { [weak self] in
                    guard let plan = calendario.planParaDejarDeApuntar(t, persona: persona) else { return "No había nada que cambiar." }
                    try await self?.sesion?.escribirComoPersona(plan, aviso: "La rutina deja de ir al Calendario.")
                    return "La ficha se queda; ya no va al Calendario."
                }
                tarjetas.append(.calendario(
                    id: t.id, titulo: t.titulo, texto: t.texto, diferencias: difs, ruta: t.ruta, boton: t.boton, botonNo: t.botonNo,
                    hacer: { [weak self] in
                        _ = try await calendario.devolverAlaFicha(t, foto: await foto())
                        self?.carpetaCambio()
                        return "Vuelve a estar en tu Calendario."
                    },
                    noHacer: t.botonNo == nil ? nil : dejar))
            case .conInvitados:
                tarjetas.append(.calendario(id: t.id, titulo: t.titulo, texto: t.texto, diferencias: difs, ruta: t.ruta,
                                            boton: t.boton, botonNo: nil, hacer: { "Entendido: la app no toca ese evento." }))
            }
        }
        ConexionesEnDecisiones.de(sesion).poner(tarjetas, origen: "calendario")
    }

    // MARK: Otros programas

    /// El ejemplo trae su programa de mentira (una vez; si lo quitas, no vuelve hasta la próxima vez que abras Ribera).
    func asegurarConectorSimulado() {
        guard ejemplo, pasarela.almacen.conexion(ConectorSimulado.id) == nil else { return }
        do {
            try pasarela.almacen.guardar(ConectorSimulado.conexion(ahora: sistema.ahora()))
        } catch {
            Self.log.error("No se pudo preparar el programa del ejemplo: \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
        }
    }

    /// «Revisar herramientas nuevas de X» en Decisiones (la misma pieza que en Conexiones).
    public func ponerRevisiones() {
        guard let sesion else { return }
        let d = ConexionesEnDecisiones.de(sesion)
        let tarjetas = pasarela.tarjetasDeRevision()
        let conTarjeta = Set(tarjetas.map(\.conexion))
        for c in pasarela.conexiones() where !conTarjeta.contains(c.id) { d.poner([], origen: "pasarela:\(c.id)") }
        for t in tarjetas {
            let nombres = t.herramientas.map(\.nombre)
            let id = t.conexion
            let tarjeta = TarjetaDeConexion.herramientas(
                id: t.id, programa: t.nombreConexion, conexion: t.conexion, texto: t.titulo + ".",
                herramientas: t.herramientas.map {
                    HerramientaDeLaTarjeta(nombre: $0.nombreVisible, descripcion: $0.descripcion, cambiaCosas: $0.clase == .sensible,
                                           motivo: $0.motivo.texto, estado: $0.estado.texto)
                },
                activar: { [weak self] in
                    try await self?.revisar(id, herramientas: nombres, aceptar: true)
                    return "Activadas. Ningún asistente las usa hasta que enciendas su interruptor en Conexiones."
                },
                dejar: { [weak self] in
                    try await self?.revisar(id, herramientas: nombres, aceptar: false)
                    return "Se quedan desactivadas."
                })
            d.poner([tarjeta], origen: "pasarela:\(t.conexion)")
        }
    }

    func revisar(_ id: String, herramientas: [String], aceptar: Bool) async throws {
        try await pasarela.revisar(id, herramientas: herramientas, aceptar: aceptar, autor: .persona(piezas.persona))
        ponerRevisiones()
    }

    /// El sincronizador de reflejos (necesita el servidor de herramientas del motor).
    func sincronizador() -> Sincronizador? {
        guard let servidor = motor?.servidor else { return nil }
        let p = piezas
        return Sincronizador(pasarela: pasarela,
                             registrador: RegistradorPorHerramientas.deGobierno(servidor: servidor, autorizador: p.autorizador),
                             registro: RegistroEnFicheros(bus: p.bus, foto: p.foto, reloj: relojDeCarpeta))
    }

    /// El ejemplo vive el día que fija su carpeta.
    var relojDeCarpeta: (@Sendable (VaultSnapshot) -> Reloj)? {
        guard let hoy = piezas.hoyCarpeta else { return nil }
        let ahora = sistema.ahora
        return { f in
            let z = TimeZone(identifier: ConfigMetricas.leer(f.text(VaultPath(".tls/config.yaml"))).zona) ?? .current
            return Reloj(hoy: hoy, ahora: ahora(), zona: z)
        }
    }

    /// Cada 5 minutos, con los asistentes encendidos: las conexiones a las que les toca se sincronizan.
    func rondaDePasarela() async {
        guard arrancada, await interruptorEncendido(), let s = sincronizador() else { return }
        for c in s.pendientes(ahora: sistema.ahora()) {
            _ = await sincronizarConexion(c.id, con: s)
        }
        ponerRevisiones()
    }

    /// «Sincronizar ahora» (o la ronda): lo que lista el programa queda en las fichas, sin repetir.
    @discardableResult
    public func sincronizarConexion(_ id: String) async throws -> InformeDeSincronizacion {
        guard let s = sincronizador() else {
            throw ErrorDeConexion("Los asistentes de esta empresa no están en marcha: sin ellos no se puede apuntar nada.")
        }
        guard let i = await sincronizarConexion(id, con: s, lanzar: true) else {
            throw ErrorDeConexion("No se pudo sincronizar.")
        }
        return i
    }

    private func sincronizarConexion(_ id: String, con s: Sincronizador, lanzar: Bool = false) async -> InformeDeSincronizacion? {
        do {
            let i = try await s.sincronizar(id)
            ultimasSincronizaciones.append(i)
            if ultimasSincronizaciones.count > 20 { ultimasSincronizaciones.removeFirst() }
            return i
        } catch {
            Self.log.error("Sincronización de \(id, privacy: .public): \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
            return nil
        }
    }
}
