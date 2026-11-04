import Foundation
import MCP
import Testing
import TLSCore
import TLSGateway
@testable import TLSIntegracion
import TLSIntegrations

// Apoyo de las pruebas de F5 y F6 de la integración. **Nada real**: ni Mail, ni `osascript` contra Mail, ni EventKit,
// ni TCC, ni el Llavero, ni red ni descargas. Mail, Calendario y permisos van por dobles; otros programas, con un
// servidor de herramientas PROPIO escrito con el SDK Swift 0.12.1 (`Server` + `StatelessHTTPServerTransport`) al que el
// cliente de la app (`HTTPClientTransport` dentro de `FabricaMCP`) habla a través de un `URLProtocol` de prueba.
// Los nombres de lo privado son neutros («Expediente privado»).

// MARK: - Mail y permisos

/// `osascript` falso: apunta cada guion y responde lo que le digas (nunca lanza nada).
final class JXADoble: EjecutorJXA, @unchecked Sendable {
    struct Llamada: Sendable { let guion: String; let argumentos: [String] }
    private let lock = NSLock()
    private var _llamadas: [Llamada] = []
    private var _responder: @Sendable (Llamada) -> ResultadoJXA

    init(_ responder: @escaping @Sendable (Llamada) -> ResultadoJXA = { _ in ResultadoJXA(salida: #"{"estado":"ok","mensajes":[],"mas":false}"#) }) {
        _responder = responder
    }

    var llamadas: [Llamada] { lock.withLock { _llamadas } }
    var lecturas: Int { llamadas.filter { $0.guion == GuionesDeMail.leer }.count }

    func responder(_ r: @escaping @Sendable (Llamada) -> ResultadoJXA) { lock.withLock { _responder = r } }

    func ejecutar(_ guion: String, argumentos: [String], tope: TimeInterval) async throws -> ResultadoJXA {
        let l = Llamada(guion: guion, argumentos: argumentos)
        let r = lock.withLock { () -> @Sendable (Llamada) -> ResultadoJXA in
            _llamadas.append(l)
            return _responder
        }
        return r(l)
    }

    /// Lo que devolvería el guion de lectura (sin filtrar: la app filtra otra vez).
    static func correos(_ lista: [[String: Any]]) -> ResultadoJXA {
        let d = try! JSONSerialization.data(withJSONObject: ["estado": "ok", "mensajes": lista, "mas": false] as [String: Any])
        return ResultadoJXA(salida: String(decoding: d, as: UTF8.self))
    }

    static func correo(_ id: String, _ fecha: Date, de: String, asunto: String, texto: String,
                       adjuntos: [[String: Any]] = []) -> [String: Any] {
        ["id": id, "fecha": fecha.timeIntervalSince1970 * 1000, "de": de, "para": ["hola@ribera.example"], "asunto": asunto,
         "leido": false, "texto": texto, "adjuntos": adjuntos]
    }

    static let cuentas = ResultadoJXA(salida: #"{"estado":"ok","cuentas":["Asesoría"]}"#)
    /// Automatización denegada (-1743), como la devuelve `osascript`.
    static let denegada = ResultadoJXA(salida: "", errores: "execution error: Not authorized to send Apple events to Mail. (-1743)",
                                       estado: 1)
}

/// Redactor de Mail falso: apunta lo que se le pide abrir. No tiene (ni puede tener) «enviar».
final class RedactorDoble: RedactorDeMail, @unchecked Sendable {
    private let lock = NSLock()
    private var _abiertas: [RedaccionDeCorreo] = []
    var abiertas: [RedaccionDeCorreo] { lock.withLock { _abiertas } }

    func abrirRedaccion(_ r: RedaccionDeCorreo) async throws {
        lock.withLock { _abiertas.append(r) }
    }
}

/// Permisos falsos: estados fijos y lo que se pidió.
final class PermisosDoble: ConsultorDePermisos, @unchecked Sendable {
    private let lock = NSLock()
    private var estados: [PermisoDelSistema: EstadoDePermiso]
    private var _pedidos: [PermisoDelSistema] = []
    var alPedir: EstadoDePermiso

    init(_ estados: [PermisoDelSistema: EstadoDePermiso] = [:], alPedir: EstadoDePermiso = .concedido) {
        self.estados = estados; self.alPedir = alPedir
    }

    var pedidos: [PermisoDelSistema] { lock.withLock { _pedidos } }
    func poner(_ p: PermisoDelSistema, _ e: EstadoDePermiso) { lock.withLock { estados[p] = e } }

    func estado(_ p: PermisoDelSistema) async -> EstadoDePermiso { lock.withLock { estados[p] ?? .sinPreguntar } }

    func pedir(_ p: PermisoDelSistema) async -> EstadoDePermiso {
        lock.withLock {
            _pedidos.append(p)
            estados[p] = alPedir
            return alPedir
        }
    }
}

// MARK: - Calendario

/// El Calendario del Mac en memoria (nunca EventKit). Como EventKit: la app no puede poner invitados.
final class CalendarioDoble: AlmacenDeEventos, @unchecked Sendable {
    private let lock = NSLock()
    private var _permiso: PermisoCalendario
    private var _calendarios: [(id: String, titulo: String)] = []
    private var _eventos: [String: EventoDelCalendario] = [:]
    private var _ajenos: [(calendario: String, inicio: Date, fin: Date, titulo: String)] = []
    private var siguiente = 0
    private var _guardados: [EventoDelCalendario] = []

    init(permiso: PermisoCalendario = .sinPreguntar) { _permiso = permiso }

    private func c<T>(_ f: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try f()
    }

    func ponerPermiso(_ p: PermisoCalendario) { c { _permiso = p } }
    var calendarios: [String] { c { _calendarios.map(\.titulo) } }
    var eventos: [EventoDelCalendario] { c { Array(_eventos.values) } }
    var guardados: [EventoDelCalendario] { c { _guardados } }

    /// Un evento de otro calendario, con un título que nunca debe salir.
    func anadirAjeno(titulo: String, inicio: Date, fin: Date) {
        c {
            if !_calendarios.contains(where: { $0.titulo == "Personal" }) {
                siguiente += 1
                _calendarios.append(("cal-\(siguiente)", "Personal"))
            }
            let id = _calendarios.first { $0.titulo == "Personal" }!.id
            _ajenos.append((id, inicio, fin, titulo))
        }
    }

    func editarFuera(_ id: String, _ cambio: (inout EventoDelCalendario) -> Void) {
        c {
            guard var e = _eventos[id] else { return }
            cambio(&e)
            _eventos[id] = e
        }
    }

    func permiso() -> PermisoCalendario { c { _permiso } }

    func calendario(llamado nombre: String) throws -> String? {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario("Sin permiso") }
            return _calendarios.first { $0.titulo == nombre }?.id
        }
    }

    func crearCalendario(llamado nombre: String) throws -> String {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario("Sin permiso") }
            siguiente += 1
            let id = "cal-\(siguiente)"
            _calendarios.append((id, nombre))
            return id
        }
    }

    func evento(id: String) throws -> EventoDelCalendario? { c { _eventos[id] } }

    func evento(url: URL, enCalendario calendario: String) throws -> EventoDelCalendario? {
        c { _eventos.values.first { $0.url == url && $0.calendario == calendario } }
    }

    func guardar(_ e: EventoDelCalendario, enCalendario calendario: String) throws -> String {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario("Sin permiso") }
            _guardados.append(e)
            var nuevo = e
            let id: String
            if let i = e.id, let viejo = _eventos[i] {
                id = i
                nuevo.invitados = viejo.invitados
            } else {
                siguiente += 1
                id = "ev-\(siguiente)"
                nuevo.invitados = 0
            }
            nuevo.id = id
            nuevo.calendario = calendario
            _eventos[id] = nuevo
            return id
        }
    }

    func retirar(id: String) throws {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario("Sin permiso") }
            _eventos[id] = nil
        }
    }

    func ocupado(desde: Date, hasta: Date, excepto: Set<String>) throws -> [BloqueOcupado] {
        c {
            _ajenos.filter { !excepto.contains($0.calendario) && $0.inicio < hasta && $0.fin > desde }
                .map { BloqueOcupado(inicio: $0.inicio, fin: $0.fin) }
        }
    }
}

// MARK: - Otros programas: servidor de herramientas propio (SDK Swift) sin red

struct HerramientaDePruebaF5: Sendable {
    var tool: Tool
    var responder: @Sendable ([String: Value]) -> CallTool.Result
}

final class EstadoServidorF5: @unchecked Sendable {
    private let lock = NSLock()
    private var _herramientas: [HerramientaDePruebaF5] = []
    private var _llamadas: [(String, [String: Value])] = []
    let token: String

    init(token: String) { self.token = token }

    var herramientas: [HerramientaDePruebaF5] {
        get { lock.withLock { _herramientas } }
        set { lock.withLock { _herramientas = newValue } }
    }
    var llamadas: [(String, [String: Value])] { lock.withLock { _llamadas } }
    func anotar(_ n: String, _ a: [String: Value]) { lock.withLock { _llamadas.append((n, a)) } }
}

/// Servidor MCP de prueba (SDK Swift 0.12.1) detrás de un `URLProtocol`: el «mcp-everything-server» de esta tanda.
final class ServidorMCPF5: @unchecked Sendable {
    let estado: EstadoServidorF5
    let transporte: StatelessHTTPServerTransport
    let servidor: Server
    let direccion: String

    static let lock = NSLock()
    nonisolated(unsafe) static var registrados: [String: ServidorMCPF5] = [:]

    private init(estado: EstadoServidorF5, transporte: StatelessHTTPServerTransport, servidor: Server, direccion: String) {
        self.estado = estado; self.transporte = transporte; self.servidor = servidor; self.direccion = direccion
    }

    static func arrancar(token: String, herramientas: [HerramientaDePruebaF5]) async throws -> ServidorMCPF5 {
        let estado = EstadoServidorF5(token: token)
        estado.herramientas = herramientas
        let transporte = StatelessHTTPServerTransport(validationPipeline: StandardValidationPipeline(validators: [
            AcceptHeaderValidator(mode: .jsonOnly), ContentTypeValidator(), ProtocolVersionValidator(),
        ]))
        let servidor = Server(name: "programa-de-prueba", version: "1.0", capabilities: .init(tools: .init(listChanged: true)))
        await servidor.withMethodHandler(ListTools.self) { _ in ListTools.Result(tools: estado.herramientas.map(\.tool)) }
        await servidor.withMethodHandler(CallTool.self) { p in
            estado.anotar(p.name, p.arguments ?? [:])
            guard let h = estado.herramientas.first(where: { $0.tool.name == p.name }) else {
                return CallTool.Result(content: [.text(text: "No existe", annotations: nil, _meta: nil)], isError: true)
            }
            return h.responder(p.arguments ?? [:])
        }
        try await servidor.start(transport: transporte)
        let puerto = Int.random(in: 20_000...60_000)
        let s = ServidorMCPF5(estado: estado, transporte: transporte, servidor: servidor, direccion: "http://localhost:\(puerto)/mcp")
        lock.withLock { registrados["localhost:\(puerto)"] = s }
        return s
    }

    func parar() async {
        Self.lock.withLock { Self.registrados = Self.registrados.filter { $0.value !== self } }
        await servidor.stop()
    }

    static func servidor(para url: URL?) -> ServidorMCPF5? {
        guard let u = url, let h = u.host, let p = u.port else { return nil }
        return lock.withLock { registrados["\(h):\(p)"] }
    }

    func atender(_ r: URLRequest, cuerpo: Data?) async -> (Int, [String: String], Data) {
        guard (r.value(forHTTPHeaderField: "Authorization") ?? "") == "Bearer " + estado.token else {
            return (401, ["Content-Type": "application/json"], Data(#"{"error":"sin clave"}"#.utf8))
        }
        var cabeceras: [String: String] = [:]
        for (k, v) in r.allHTTPHeaderFields ?? [:] { cabeceras[k] = v }
        let resp = await transporte.handleRequest(HTTPRequest(method: r.httpMethod ?? "GET", headers: cabeceras, body: cuerpo,
                                                              path: r.url?.path))
        var datos = resp.bodyData ?? Data()
        if case .stream(let s, _) = resp {
            do { for try await d in s { datos.append(d) } } catch {}
        }
        return (resp.statusCode, resp.headers, datos)
    }

    /// La configuración de URL del cliente de la app: solo con el `URLProtocol` de prueba (nada sale a la red).
    static func configuracion() -> URLSessionConfiguration {
        let c = FabricaMCP.configuracionPorDefecto()
        c.protocolClasses = [ProtocoloMCPF5.self]
        return c
    }

    static func texto(_ s: String) -> CallTool.Result { CallTool.Result(content: [.text(text: s, annotations: nil, _meta: nil)]) }

    static func lectura(_ nombre: String, _ responder: @escaping @Sendable ([String: Value]) -> CallTool.Result) -> HerramientaDePruebaF5 {
        HerramientaDePruebaF5(tool: Tool(name: nombre, description: "Lista lo que hay.",
                                         inputSchema: .object(["type": "object", "properties": .object([:])]),
                                         annotations: .init(readOnlyHint: true)), responder: responder)
    }

    static func cambia(_ nombre: String, propiedades: [String: Value]) -> HerramientaDePruebaF5 {
        HerramientaDePruebaF5(tool: Tool(name: nombre, description: "Cambia algo en el programa.",
                                         inputSchema: .object(["type": "object", "properties": .object(propiedades),
                                                               "additionalProperties": false])),
                              responder: { a in texto("Hecho con \(JSONCanonico.texto(Value.object(a)))") })
    }

    /// Un lead de prueba (nombre neutro).
    static let contactos = JSONCanonico.texto(Value.object(["contacts": .array([
        .object(["id": "c-001", "name": "Lead de prueba", "email": "lead@ejemplo.test", "phone": "600000000", "source": "Formulario web"]),
    ])]))

    /// Las de serie: una que lee contactos, una sensible por su nombre y una sensible por no decir que solo lee.
    static func herramientas() -> [HerramientaDePruebaF5] {
        [
            lectura("contacts_list") { _ in texto(contactos) },
            cambia("send_sms", propiedades: ["to": .object(["type": "string"]), "text": .object(["type": "string"])]),
            cambia("contacts_update", propiedades: ["id": .object(["type": "string"]), "stage": .object(["type": "string"])]),
        ]
    }
}

final class ProtocoloMCPF5: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { ServidorMCPF5.servidor(para: request.url) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let r = request
        guard let s = ServidorMCPF5.servidor(para: r.url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var cuerpo = r.httpBody
        if cuerpo == nil, let flujo = r.httpBodyStream {
            flujo.open()
            var d = Data()
            var buf = [UInt8](repeating: 0, count: 16_384)
            while flujo.hasBytesAvailable {
                let n = flujo.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                d.append(buf, count: n)
            }
            flujo.close()
            cuerpo = d
        }
        let c = cuerpo
        let caja = CajaMCPF5(p: self)
        Task {
            let yo = caja.p
            let (codigo, cabeceras, datos) = await s.atender(r, cuerpo: c)
            let http = HTTPURLResponse(url: r.url!, statusCode: codigo, httpVersion: "HTTP/1.1", headerFields: cabeceras)!
            yo.client?.urlProtocol(yo, didReceive: http, cacheStoragePolicy: .notAllowed)
            if !datos.isEmpty { yo.client?.urlProtocol(yo, didLoad: datos) }
            yo.client?.urlProtocolDidFinishLoading(yo)
        }
    }

    override func stopLoading() {}
}

struct CajaMCPF5: @unchecked Sendable { let p: ProtocoloMCPF5 }

// MARK: - El sistema de prueba

/// Todos los dobles de una empresa, para mirar qué pasó.
final class DoblesF5: @unchecked Sendable {
    let permisos: PermisosDoble
    let jxa: JXADoble
    let redactor = RedactorDoble()
    let calendario: CalendarioDoble
    let llavero = LlaveroEnMemoria()

    init(permisos: PermisosDoble = PermisosDoble(), jxa: JXADoble = JXADoble(), calendario: CalendarioDoble = CalendarioDoble()) {
        self.permisos = permisos; self.jxa = jxa; self.calendario = calendario
    }

    /// Lo que la integración usa en vez del Mac: rondas largas (las pruebas leen a mano) y el reloj de la prueba.
    func sistema(ahora: @escaping @Sendable () -> Date = { Date() }) -> SistemaDeConexiones {
        let cal = calendario
        return SistemaDeConexiones(
            permisos: permisos, jxa: jxa, redactor: redactor, eventos: { cal }, llavero: llavero,
            fabrica: { _, prohibidas in
                FabricaMCP(configuracionHTTP: { ServidorMCPF5.configuracion() }, escucharAvisos: false, plazo: .seconds(20),
                           carpetasProhibidas: prohibidas)
            },
            escucharCalendario: false, rondaCorreo: 3600, rondaPasarela: 3600, ahora: ahora)
    }
}

extension EntornoF4 {
    /// Lunes 19 de octubre de 2026 a las 09:00 en Madrid (el día de Ribera).
    nonisolated static let lunes: Date = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9))!
    }()

    /// Espera a que las conexiones de la empresa estén montadas.
    func esperarConexiones() async throws -> ConexionesDeEmpresa {
        try await esperar("conexiones montadas", segundos: 20) { [self] in conexiones?.arrancada == true }
        return try #require(conexiones)
    }

    /// Todos los ficheros (con su contenido) bajo una carpeta, para buscar algo que no debe estar.
    static func ficherosCon(_ aguja: String, en raiz: URL) -> [String] {
        guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: nil) else { return [] }
        var out: [String] = []
        for case let u as URL in e {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let d = try? Data(contentsOf: u) else { continue }
            if d.range(of: Data(aguja.utf8)) != nil { out.append(u.path) }
        }
        return out
    }
}
