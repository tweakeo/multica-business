import Foundation
import TLSCore

// F5 · rol conexiones. Un `ServiciosDeConexiones` que no toca el sistema: ni Mail, ni Calendario, ni avisos de macOS,
// ni red, ni Llavero. Lo usan las pruebas, las capturas y, si la integración quiere, el ejemplo (Ribera), donde nada
// sale de verdad. Las plantillas y sus textos son los de `PlantillasDeSerie` (TLSGateway) en llano.

/// Servicios de Conexiones en memoria, con su estado a la vista para las pruebas.
public actor ServiciosDeConexionesEnMemoria: ServiciosDeConexiones {
    /// Cómo contestaría macOS a cada permiso cuando se pide.
    public var respuestaAlPedir: [PermisoDeConexion: EstadoDePermisoConexion] = [.mail: .concedido, .calendario: .concedido]
    public var permisos: [PermisoDeConexion: EstadoDePermisoConexion] = [.mail: .sinPreguntar, .calendario: .sinPreguntar]
    public var cuentas: CuentasDeMailConexion = .cuentas(["Trabajo", "Personal"])
    public var ajustes = AjustesDeMailConexion()
    public var cartero = false
    public var calendarioCreado = false
    public var resumenCalendario = "Tu reunión de los lunes y 3 sesiones con clientes"
    /// Lo que se pidió a macOS, en orden (nunca sin explicación).
    public private(set) var peticiones: [PermisoDeConexion] = []
    public private(set) var activaciones: [Bool] = []
    /// Lo que guardaría el Llavero: `<id>.token` → valor. Solo aquí; nunca vuelve a la pantalla.
    public private(set) var llavero: [String: String] = [:]
    public private(set) var programas: [ProgramaEnMemoria] = []
    public private(set) var sincronizaciones: [String] = []
    private var vistas: Set<UUID> = []

    /// Un programa conectado de mentira, con su catálogo.
    public struct ProgramaEnMemoria: Sendable, Hashable {
        public var id: String
        public var nombre: String
        public var plantilla: String
        public var local: Bool
        public var activa = true
        public var probado = false
        public var error: String?
        /// Herramientas (nombre, solo lee, estado: `activa` · `pendiente` · `rechazada`).
        public var herramientas: [(nombre: String, lectura: Bool, estado: String)] = []
        /// Interruptores encendidos (id del permiso).
        public var encendidos: Set<String> = []
        public var ultima: Date?

        public static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.encendidos == b.encendidos && a.activa == b.activa }
        public func hash(into h: inout Hasher) { h.combine(id) }
    }

    public init() {}

    /// Lo que contestaría el otro programa al probarlo, por plantilla.
    public static func catalogoDeEjemplo(_ plantilla: String) -> [(nombre: String, lectura: Bool, estado: String)] {
        switch plantilla {
        case "ghl":
            [("contacts_list", true, "activa"), ("contact_get", true, "activa"), ("opportunities_list", true, "activa"),
             ("contact_update", false, "activa"), ("send_sms", false, "activa")]
        case "stripe":
            [("customers_list", true, "activa"), ("balance_transactions_list", true, "activa"), ("refund_create", false, "activa")]
        case "calendly":
            [("scheduled_events_list", true, "activa"), ("invitees_list", true, "activa")]
        case "web":
            [("form_submissions_list", true, "activa")]
        default:
            [("records_list", true, "activa"), ("record_update", false, "activa")]
        }
    }

    // MARK: Preparar (pruebas y capturas)

    public func poner(permiso p: PermisoDeConexion, _ e: EstadoDePermisoConexion) { permisos[p] = e }
    public func poner(alPedir p: PermisoDeConexion, _ e: EstadoDePermisoConexion) { respuestaAlPedir[p] = e }
    public func poner(cuentas c: CuentasDeMailConexion) { cuentas = c }
    public func poner(ajustes a: AjustesDeMailConexion, cartero c: Bool) { ajustes = a; cartero = c }
    public func poner(calendarioCreado c: Bool) { calendarioCreado = c }

    /// Un programa ya conectado (y probado) con herramientas nuevas por revisar si se pide.
    public func sembrar(id: String, nombre: String, plantilla: String, encendidos: Set<String> = [], nuevas: [(String, Bool)] = [],
                        ultima: Date? = nil) {
        var p = ProgramaEnMemoria(id: id, nombre: nombre, plantilla: plantilla, local: false)
        p.probado = true
        p.herramientas = Self.catalogoDeEjemplo(plantilla) + nuevas.map { ($0.0, $0.1, "pendiente") }
        p.encendidos = encendidos
        p.ultima = ultima
        programas.append(p)
    }

    // MARK: Permisos

    public func situacion(_ p: PermisoDeConexion) async -> SituacionDeConexion {
        switch permisos[p] ?? .sinPreguntar {
        case .concedido: .listo
        case .sinPreguntar: .explicar(Self.explicacion(p))
        case .denegado, .restringido: .recuperar(Self.recuperacion(p))
        case .desconocido: .sinComprobar
        }
    }

    public func explicar(_ p: PermisoDeConexion) async -> PermisoExplicado {
        let e = PermisoExplicado(permiso: p, explicacion: Self.explicacion(p))
        vistas.insert(e.id)
        return e
    }

    public func pedir(_ p: PermisoDeConexion, tras e: PermisoExplicado) async throws -> EstadoDePermisoConexion {
        guard e.permiso == p, vistas.remove(e.id) != nil else {
            throw ErrorDeConexion("Antes de pedir el permiso hay que explicar para qué es.")
        }
        let ahora = permisos[p] ?? .sinPreguntar
        guard ahora == .sinPreguntar || ahora == .desconocido else { return ahora }
        peticiones.append(p)
        let r = respuestaAlPedir[p] ?? .denegado
        permisos[p] = r
        return r
    }

    // MARK: Mail

    public func cuentasDeMail() async -> CuentasDeMailConexion {
        if (permisos[.mail] ?? .sinPreguntar).necesitaRecuperacion { return .sinPermiso(Self.recuperacion(.mail)) }
        return cuentas
    }

    public func ajustesDeMail() async -> AjustesDeMailConexion { ajustes }
    public func guardarAjustesDeMail(_ a: AjustesDeMailConexion) async throws { ajustes = a }
    public func carteroActivo() async -> Bool { cartero }

    public func activarCartero(_ activo: Bool) async throws {
        cartero = activo
        activaciones.append(activo)
    }

    // MARK: Calendario

    public func estadoDelCalendario() async -> CalendarioConexion {
        switch permisos[.calendario] ?? .sinPreguntar {
        case .denegado, .restringido: .sinPermiso(Self.recuperacion(.calendario))
        case .concedido: calendarioCreado ? .conectado(resumen: resumenCalendario) : .sinConectar
        default: .sinConectar
        }
    }

    public func conectarCalendario() async -> CalendarioConexion {
        guard permisos[.calendario] == .concedido else { return await estadoDelCalendario() }
        calendarioCreado = true
        return .conectado(resumen: resumenCalendario)
    }

    public func desconectarCalendario() async throws {
        calendarioCreado = false
    }

    // MARK: Otros programas

    public nonisolated func plantillas() -> [PlantillaDeOtroPrograma] { Self.plantillasDeSerie }

    public func otrosProgramas() async -> [OtroProgramaConexion] {
        programas.map { p in
            let estado: EstadoDeOtroPrograma = if let e = p.error { .error(e) } else if !p.activa { .pausado }
                else if !p.probado { .sinProbar } else { .conectado }
            return OtroProgramaConexion(id: p.id, nombre: p.nombre, plantilla: p.plantilla, estado: estado,
                                        activas: p.herramientas.filter { $0.estado == "activa" }.count,
                                        porRevisar: p.herramientas.filter { $0.estado == "pendiente" }.count,
                                        ultimaSincronizacion: p.ultima, local: p.local)
        }
    }

    public func anadir(_ alta: AltaDeOtroPrograma) async throws {
        guard !programas.contains(where: { $0.id == alta.id }) else { throw ErrorDeConexion("Ya tienes un programa con ese nombre.") }
        var local = false
        switch alta.transporte {
        case .web(let d):
            guard d.hasPrefix("https://") || d.hasPrefix("http://localhost") else {
                throw ErrorDeConexion("La dirección tiene que empezar por https://.")
            }
        case .local(_, _, let aceptado):
            guard aceptado else { throw ErrorDeConexion("Acepta antes el aviso de los programas de este Mac.") }
            guard (alta.clave ?? "").isEmpty else { throw ErrorDeConexion("Un programa de este Mac no recibe claves.") }
            local = true
        }
        if let c = alta.clave, !c.isEmpty { llavero["\(alta.id).token"] = c }
        programas.append(ProgramaEnMemoria(id: alta.id, nombre: alta.nombre, plantilla: alta.plantilla, local: local))
    }

    public func probar(_ id: String) async throws -> String {
        guard let i = programas.firstIndex(where: { $0.id == id }) else { throw ErrorDeConexion("Ese programa ya no está.") }
        if programas[i].herramientas.isEmpty { programas[i].herramientas = Self.catalogoDeEjemplo(programas[i].plantilla) }
        programas[i].probado = true
        programas[i].error = nil
        let hs = programas[i].herramientas
        let lee = hs.filter(\.lectura).count
        return "Responde. Trae \(hs.count) herramientas: \(lee) solo leen y \(hs.count - lee) piden tu OK."
    }

    public func interruptores(_ id: String) async -> [InterruptorDeOtroPrograma] {
        guard let p = programas.first(where: { $0.id == id }) else { return [] }
        return Self.plantilla(p.plantilla).permisosDetalle.map { d in
            let hs = p.herramientas.filter { $0.estado == "activa" && $0.lectura == d.lectura && Self.casa($0.nombre, d.patrones) }
            return InterruptorDeOtroPrograma(id: d.id, texto: d.texto(p.nombre), encendido: p.encendidos.contains(d.id) && !hs.isEmpty,
                                             disponible: !hs.isEmpty, asistenteActivo: d.asistente != "contable",
                                             lectura: d.lectura, herramientas: hs.map(\.nombre))
        }
    }

    public func cambiarInterruptor(_ id: String, permiso: String, encender: Bool) async throws {
        guard let i = programas.firstIndex(where: { $0.id == id }) else { throw ErrorDeConexion("Ese programa ya no está.") }
        if encender { programas[i].encendidos.insert(permiso) } else { programas[i].encendidos.remove(permiso) }
    }

    public func revisiones() async -> [RevisionDeOtroPrograma] {
        programas.compactMap { p in
            let nuevas = p.herramientas.filter { $0.estado == "pendiente" }
            guard !nuevas.isEmpty else { return nil }
            let n = nuevas.count
            return RevisionDeOtroPrograma(
                id: "conexion-revisar:\(p.id):\(nuevas.map(\.nombre).joined(separator: ","))", conexion: p.id, nombreConexion: p.nombre,
                titulo: "\(p.nombre) trae \(n == 1 ? "1 herramienta nueva o cambiada" : "\(n) herramientas nuevas o cambiadas"): están desactivadas hasta que las revises",
                herramientas: nuevas.map { h in
                    let sensible = !h.lectura || Self.palabraSensible(h.nombre) != nil
                    return HerramientaNueva(
                        nombre: h.nombre, descripcion: "Herramienta de \(p.nombre).",
                        clase: sensible ? "Cambia cosas: pide tu OK" : "Solo lee",
                        motivo: Self.palabraSensible(h.nombre).map { "Su nombre lleva «\($0)»: siempre pide tu OK." }
                            ?? (h.lectura ? "El programa dice que solo lee." : "El programa no dice que solo lea: se trata como sensible."),
                        sensible: sensible)
                })
        }
    }

    public func revisar(_ r: RevisionDeOtroPrograma, aceptar: Bool) async throws {
        guard let i = programas.firstIndex(where: { $0.id == r.conexion }) else { throw ErrorDeConexion("Ese programa ya no está.") }
        let nombres = Set(r.herramientas.map(\.nombre))
        programas[i].herramientas = programas[i].herramientas.map { h in
            nombres.contains(h.nombre) && h.estado == "pendiente" ? (h.nombre, h.lectura, aceptar ? "activa" : "rechazada") : h
        }
    }

    public func sincronizarAhora(_ id: String) async throws -> String {
        guard let i = programas.firstIndex(where: { $0.id == id }) else { throw ErrorDeConexion("Ese programa ya no está.") }
        sincronizaciones.append(id)
        programas[i].ultima = Date()
        return "Sin novedades: no había nada nuevo en \(programas[i].nombre)."
    }

    public func pausar(_ id: String, _ pausado: Bool) async throws {
        guard let i = programas.firstIndex(where: { $0.id == id }) else { throw ErrorDeConexion("Ese programa ya no está.") }
        programas[i].activa = !pausado
    }

    public func quitar(_ id: String) async throws {
        programas.removeAll { $0.id == id }
        llavero = llavero.filter { !$0.key.hasPrefix(id + ".") }
    }

    public func matriz(_ id: String) async -> [FilaDeMatrizConexion] {
        guard let p = programas.first(where: { $0.id == id }) else { return [] }
        let detalle = Self.plantilla(p.plantilla).permisosDetalle
        return p.herramientas.map { h in
            let sensible = !h.lectura || Self.palabraSensible(h.nombre) != nil
            var asist: [String: Bool] = [:]
            for d in detalle where p.encendidos.contains(d.id) && d.lectura == h.lectura && Self.casa(h.nombre, d.patrones) {
                asist[d.asistente] = true
            }
            for d in detalle where asist[d.asistente] == nil { asist[d.asistente] = false }
            let estado = switch h.estado {
            case "pendiente": "Nueva: desactivada hasta que la revises"
            case "rechazada": "Desactivada por ti"
            default: "Activa"
            }
            return FilaDeMatrizConexion(
                expuesta: "ext_\(p.id)_\(h.nombre)", nombre: h.nombre, clase: sensible ? "sensible" : "lectura",
                motivo: Self.palabraSensible(h.nombre).map { "nombre con «\($0)»" } ?? (h.lectura ? "solo lee" : "sin indicación"),
                estado: estado, huellaCorta: Self.huellaCorta(h.nombre), asistentes: asist)
        }
    }

    /// Una huella corta estable (FNV-1a), solo para enseñarla en la matriz del doble.
    static func huellaCorta(_ s: String) -> String {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return String(format: "%08x", h)
    }

    // MARK: Textos de serie (los de Permisos y Plantillas del núcleo, en llano)

    static let palabrasSensibles = ["send", "publish", "pay", "charge", "refund", "invoice", "transfer", "delete", "email", "sms", "message"]

    static func palabraSensible(_ nombre: String) -> String? {
        let n = nombre.lowercased().filter { $0.isLetter || $0.isNumber }
        return palabrasSensibles.first { n.contains($0) }
    }

    static func casa(_ nombre: String, _ patrones: [String]) -> Bool {
        let n = nombre.lowercased()
        return patrones.contains { p in
            p == "*" || n.contains(p.lowercased().replacingOccurrences(of: "*", with: ""))
        }
    }

    public static func explicacion(_ p: PermisoDeConexion) -> ExplicacionDeConexion {
        switch p {
        case .mail:
            ExplicacionDeConexion(
                titulo: "Dejar que la app lea tu correo nuevo en Mail",
                para: "Para que el Cartero sepa qué ha llegado: cada 15 minutos, con Mail abierto, la app mira la bandeja de entrada de la cuenta que elijas; cada mañana el Cartero lo clasifica y lo apunta en tu Buzón.",
                hace: ["Lee el remitente, el asunto y el principio de cada correo nuevo (unas pocas líneas).",
                       "De los adjuntos solo ve el nombre y el tamaño.",
                       "Cuando apruebas un correo, abre en Mail la redacción ya rellena."],
                nunca: ["Enviar nada: el botón Enviar lo pulsas tú.", "Marcar como leído, mover ni borrar ningún correo.",
                        "Leer los correos de los remitentes que marques como privados."],
                queVeras: "Ahora macOS te preguntará si The Last System puede controlar Mail. Pulsa «Permitir».")
        case .calendario:
            ExplicacionDeConexion(
                titulo: "Dejar que la app use tu Calendario",
                para: "Para poner tus rituales y las sesiones con clientes en un calendario propio, «The Last System», y saber qué huecos tienes libres.",
                hace: ["Crea y actualiza eventos solo en el calendario «The Last System».",
                       "De tus otros calendarios solo mira cuándo estás ocupado, sin títulos."],
                nunca: ["Invitar a nadie: invitar sería enviar.", "Cambiar ni borrar eventos de tus otros calendarios."],
                queVeras: "Ahora macOS te preguntará si The Last System puede acceder a tus calendarios. Pulsa «Permitir acceso total».")
        }
    }

    public static func recuperacion(_ p: PermisoDeConexion) -> RecuperacionDeConexion {
        switch p {
        case .mail:
            RecuperacionDeConexion(
                titulo: "La app no tiene permiso para usar Mail",
                texto: "Sin este permiso, el Cartero no puede ver el correo nuevo y al aprobar un correo no se abre la redacción en Mail. Nada se ha enviado ni se ha tocado en tu correo.",
                pasos: ["Pulsa «Abrir Ajustes del Sistema».",
                        "Ve a Privacidad y seguridad › Automatización › The Last System › Mail.",
                        "Activa el interruptor y vuelve a la app."],
                enlace: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!,
                detalleTecnico: "Apple Events -1743 (la persona no lo permitió)")
        case .calendario:
            RecuperacionDeConexion(
                titulo: "La app no tiene permiso para usar tu Calendario",
                texto: "Sin este permiso, tus rituales y sesiones no aparecen en Calendario. Las fichas siguen igual en tu carpeta.",
                pasos: ["Pulsa «Abrir Ajustes del Sistema».", "Ve a Privacidad y seguridad › Calendarios › The Last System.",
                        "Activa el interruptor y vuelve a la app."],
                enlace: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        }
    }

    struct DetallePermiso: Sendable {
        let id: String
        let asistente: String
        let que: String
        let patrones: [String]
        let lectura: Bool
        func texto(_ conexion: String) -> String { "\(AsistenteConfigurado.nombre(de: asistente)) \(que) \(conexion)" }
    }

    struct PlantillaCompleta: Sendable {
        let base: PlantillaDeOtroPrograma
        let permisosDetalle: [DetallePermiso]
    }

    static let detalles: [String: (nombre: String, explicacion: String, ejemplo: String, permisos: [DetallePermiso])] = [
        "web": ("Web y formularios", "Trae a tus fichas los contactos que llegan por los formularios de tu web.", "https://",
                [DetallePermiso(id: "leer-formularios", asistente: "comercial", que: "puede leer los formularios recibidos de",
                                patrones: ["*lead*", "*submission*", "*form*", "*entr*", "*contact*"], lectura: true)]),
        "ghl": ("GoHighLevel", "Trae tus contactos y oportunidades de GoHighLevel a tus fichas; lo que cambie allí pide tu OK.",
                "https://services.leadconnectorhq.com/mcp/",
                [DetallePermiso(id: "leer-contactos", asistente: "comercial", que: "puede leer contactos de", patrones: ["*contact*"], lectura: true),
                 DetallePermiso(id: "leer-oportunidades", asistente: "comercial", que: "puede leer oportunidades de",
                                patrones: ["*opportunit*", "*pipeline*"], lectura: true),
                 DetallePermiso(id: "pedir-acciones", asistente: "comercial", que: "puede pedirte cambios (siempre con tu OK) en",
                                patrones: ["*"], lectura: false)]),
        "stripe": ("Stripe", "Apunta en Finanzas los cobros de Stripe sin confirmarlos: confirmar es tuyo al conciliar.", "https://mcp.stripe.com",
                   [DetallePermiso(id: "leer-clientes", asistente: "contable", que: "puede leer clientes y movimientos de",
                                   patrones: ["*customer*", "*balance*"], lectura: true),
                    DetallePermiso(id: "pedir-acciones", asistente: "contable", que: "puede pedirte cambios (siempre con tu OK) en",
                                   patrones: ["*"], lectura: false)]),
        "calendly": ("Calendly", "Trae a tus fichas a quien reserva una cita contigo.", "https://",
                     [DetallePermiso(id: "leer-citas", asistente: "comercial", que: "puede leer las citas reservadas en",
                                     patrones: ["*event*", "*invitee*", "*booking*"], lectura: true)]),
        "generico": ("Otro programa", "Cualquier otro programa compatible. Tú decides qué puede usar cada asistente.", "https://",
                     [DetallePermiso(id: "mika-lee", asistente: "mika", que: "puede leer de", patrones: ["*"], lectura: true),
                      DetallePermiso(id: "mika-pide", asistente: "mika", que: "puede pedirte cambios (siempre con tu OK) en",
                                     patrones: ["*"], lectura: false)]),
    ]

    static let orden = ["web", "ghl", "stripe", "calendly", "generico"]

    static func plantilla(_ id: String) -> PlantillaCompleta {
        let d = detalles[id] ?? detalles["generico"]!
        let clave = id == "generico" || detalles[id] != nil ? CampoDeClave() : nil
        return PlantillaCompleta(
            base: PlantillaDeOtroPrograma(id: detalles[id] == nil ? "generico" : id, nombre: d.nombre, explicacion: d.explicacion,
                                          direccionDeEjemplo: d.ejemplo, clave: clave, permisos: d.permisos.map { $0.texto(d.nombre) }),
            permisosDetalle: d.permisos)
    }

    /// Las cinco plantillas de serie (Web y formularios, GoHighLevel, Stripe, Calendly, Otro programa).
    public static let plantillasDeSerie: [PlantillaDeOtroPrograma] = orden.map { plantilla($0).base }
}
