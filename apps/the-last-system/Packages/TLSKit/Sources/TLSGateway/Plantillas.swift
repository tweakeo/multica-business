import Foundation
import TLSCore

/// Qué ficha se rellena con lo que llega de otro programa (las cuatro herramientas de dominio, PLAN §5.4).
public enum TipoDeRegistro: String, Codable, Sendable, Hashable, CaseIterable {
    case contacto
    case oportunidad
    case metricas
    case cobro

    /// La herramienta de `tls-mcp` que lo apunta.
    public var herramienta: String {
        switch self {
        case .contacto: "tls_registrar_contacto"
        case .oportunidad: "tls_registrar_oportunidad"
        case .metricas: "tls_registrar_metricas_contenido"
        case .cobro: "tls_registrar_cobro_externo"
        }
    }

    public var texto: String {
        switch self {
        case .contacto: "contactos"
        case .oportunidad: "oportunidades"
        case .metricas: "cifras de contenido"
        case .cobro: "cobros (sin confirmar)"
        }
    }
}

/// Un campo que pide la conexión (la clave va al Llavero; nunca se enseña después).
public struct CampoDeConexion: Sendable, Hashable {
    public let id: String
    public let etiqueta: String
    public let ayuda: String
    public let secreto: Bool
}

/// Un interruptor en lenguaje llano: «El Comercial puede leer contactos de GoHighLevel».
public struct PermisoDePlantilla: Sendable, Hashable, Identifiable {
    public let id: String
    /// Asistente al que se le da (`comercial`).
    public let asistente: String
    /// «puede leer contactos de» (el texto entero lo compone `texto(conexion:)`).
    public let que: String
    /// Herramientas a las que se refiere: patrones sobre el nombre en el otro programa (`*contact*`; `*` = todas).
    public let patrones: [String]
    /// Solo las de lectura (si no, solo las sensibles).
    public let lectura: Bool

    public func texto(conexion: String) -> String {
        "\(AsistenteConfigurado.nombre(de: asistente)) \(que) \(conexion)"
    }

    /// ¿Se refiere a esta herramienta?
    public func incluye(_ h: HerramientaExterna) -> Bool {
        (h.clase == .lectura) == lectura && Patrones.casa(h.nombre, patrones)
    }
}

/// Cómo se refleja en las fichas lo que lista una herramienta de lectura (sincronización, sin webhooks).
public struct ReflejoDePlantilla: Sendable, Hashable, Identifiable {
    public let id: String
    public let registro: TipoDeRegistro
    /// Herramientas de lectura que listan lo que se refleja (patrones).
    public let herramientas: [String]
    /// Asistente a cuyo nombre se apunta (lo gobierna su modo; necesita permiso de lectura de esa herramienta).
    public let asistente: String
    /// Claves donde puede venir la lista (`contacts`, `data`…); si la respuesta ya es una lista, esa.
    public let listas: [String]
    /// Claves del identificador en el otro programa (`id`).
    public let identificador: [String]
    /// Argumento de `tls_registrar_*` → claves posibles en cada elemento, por orden de preferencia.
    public let campos: [String: [String]]
    /// Argumentos fijos para la herramienta que lista (vacío = ninguno).
    public let argumentos: [String: String]

    public init(id: String, registro: TipoDeRegistro, herramientas: [String], asistente: String,
                listas: [String] = ["items", "data", "results", "contacts", "leads", "submissions", "records"],
                identificador: [String] = ["id", "uuid", "uri"], campos: [String: [String]], argumentos: [String: String] = [:]) {
        self.id = id; self.registro = registro; self.herramientas = herramientas; self.asistente = asistente
        self.listas = listas; self.identificador = identificador; self.campos = campos; self.argumentos = argumentos
    }
}

/// Plantilla por conector (PLAN §7.4): qué pide, qué interruptores enseña y qué refleja en las fichas.
public struct PlantillaDeConector: Sendable, Hashable, Identifiable {
    public let id: String
    public let nombre: String
    /// En una frase, qué hace por ti.
    public let explicacion: String
    /// Dirección de ejemplo (vacía en la genérica).
    public let direccionDeEjemplo: String
    public let campos: [CampoDeConexion]
    public let permisos: [PermisoDePlantilla]
    public let reflejos: [ReflejoDePlantilla]
}

/// Patrones sencillos sobre el nombre de una herramienta: `*` = cualquier cosa; sin distinguir mayúsculas.
public enum Patrones {
    public static func casa(_ nombre: String, _ patrones: [String]) -> Bool {
        let n = nombre.lowercased()
        return patrones.contains { p in
            let partes = p.lowercased().split(separator: "*", omittingEmptySubsequences: false).map(String.init)
            guard partes.count > 1 else { return n == p.lowercased() }
            var resto = Substring(n)
            for (i, parte) in partes.enumerated() where !parte.isEmpty {
                if i == 0 {
                    guard resto.hasPrefix(parte) else { return false }
                    resto = resto.dropFirst(parte.count)
                } else if i == partes.count - 1 {
                    return resto.hasSuffix(parte)
                } else {
                    guard let r = resto.range(of: parte) else { return false }
                    resto = resto[r.upperBound...]
                }
            }
            return true
        }
    }

    /// ¿La lista de `herramientas_externas` de un asistente deja esta herramienta? Nombres exactos
    /// (`ext_ghl_contacts_list`) o un prefijo con asterisco (`ext_ghl_*`).
    public static func permite(_ lista: [String], expuesta: String) -> Bool {
        lista.contains { l in
            let t = l.trimmingCharacters(in: .whitespaces).lowercased()
            if t.hasSuffix("*") { return t.count > TLSGatewayInfo.prefijo.count + 1 && expuesta.lowercased().hasPrefix(String(t.dropLast())) }
            return t == expuesta.lowercased()
        }
    }
}

/// Las plantillas de serie.
public enum PlantillasDeSerie {
    static let token = CampoDeConexion(id: "token", etiqueta: "Clave de acceso",
                                       ayuda: "Se guarda en el Llavero de tu Mac. Ningún asistente la ve.", secreto: true)

    static let camposContacto: [String: [String]] = [
        "nombre": ["name", "nombre", "full_name", "fullName", "contactName", "first_name"],
        "email": ["email", "correo", "mail"],
        "telefono": ["phone", "telefono", "teléfono", "phone_number"],
        "empresa": ["company", "empresa", "companyName", "organization"],
        "canal": ["source", "canal", "origin"],
    ]

    public static let web = PlantillaDeConector(
        id: "web", nombre: "Web y formularios",
        explicacion: "Trae a tus fichas los contactos que llegan por los formularios de tu web.",
        direccionDeEjemplo: "https://", campos: [token],
        permisos: [
            PermisoDePlantilla(id: "leer-formularios", asistente: "comercial", que: "puede leer los formularios recibidos de",
                               patrones: ["*lead*", "*submission*", "*form*", "*entr*", "*contact*"], lectura: true),
        ],
        reflejos: [
            ReflejoDePlantilla(id: "formularios", registro: .contacto,
                               herramientas: ["*lead*", "*submission*", "*form*", "*entr*", "*contact*"], asistente: "comercial",
                               campos: camposContacto),
        ])

    public static let ghl = PlantillaDeConector(
        id: "ghl", nombre: "GoHighLevel",
        explicacion: "Trae tus contactos y oportunidades de GoHighLevel a tus fichas; lo que cambie allí pide tu OK.",
        direccionDeEjemplo: "https://services.leadconnectorhq.com/mcp/", campos: [token],
        permisos: [
            PermisoDePlantilla(id: "leer-contactos", asistente: "comercial", que: "puede leer contactos de",
                               patrones: ["*contact*"], lectura: true),
            PermisoDePlantilla(id: "leer-oportunidades", asistente: "comercial", que: "puede leer oportunidades de",
                               patrones: ["*opportunit*", "*pipeline*"], lectura: true),
            PermisoDePlantilla(id: "pedir-acciones", asistente: "comercial", que: "puede pedirte cambios (siempre con tu OK) en",
                               patrones: ["*"], lectura: false),
        ],
        reflejos: [
            ReflejoDePlantilla(id: "contactos", registro: .contacto, herramientas: ["*contact*"], asistente: "comercial",
                               campos: camposContacto),
            ReflejoDePlantilla(id: "oportunidades", registro: .oportunidad, herramientas: ["*opportunit*"],
                               asistente: "comercial", listas: ["opportunities", "items", "data"],
                               campos: ["nombre": ["name", "title", "nombre"], "valor": ["monetaryValue", "value", "valor"],
                                        "canal": ["source", "canal"]]),
        ])

    public static let stripe = PlantillaDeConector(
        id: "stripe", nombre: "Stripe",
        explicacion: "Apunta en Finanzas los cobros de Stripe sin confirmarlos: confirmar es tuyo al conciliar.",
        direccionDeEjemplo: "https://mcp.stripe.com", campos: [token],
        permisos: [
            PermisoDePlantilla(id: "leer-clientes", asistente: "contable", que: "puede leer clientes y movimientos de",
                               patrones: ["*customer*", "*balance*"], lectura: true),
            PermisoDePlantilla(id: "pedir-acciones", asistente: "contable", que: "puede pedirte cambios (siempre con tu OK) en",
                               patrones: ["*"], lectura: false),
        ],
        reflejos: [
            // Las de cobros y pagos (charge, pay…) son sensibles por su nombre: se refleja desde los movimientos.
            ReflejoDePlantilla(id: "movimientos", registro: .cobro, herramientas: ["*balance_transaction*"], asistente: "contable",
                               campos: ["importe": ["amount_eur", "importe", "amount"], "fecha": ["date", "fecha", "created_date"],
                                        "tercero": ["customer_name", "description", "tercero"], "metodo": ["type", "metodo"]]),
        ])

    public static let calendly = PlantillaDeConector(
        id: "calendly", nombre: "Calendly",
        explicacion: "Trae a tus fichas a quien reserva una cita contigo.",
        direccionDeEjemplo: "https://", campos: [token],
        permisos: [
            PermisoDePlantilla(id: "leer-citas", asistente: "comercial", que: "puede leer las citas reservadas en",
                               patrones: ["*event*", "*invitee*", "*booking*"], lectura: true),
        ],
        reflejos: [
            ReflejoDePlantilla(id: "invitados", registro: .contacto, herramientas: ["*invitee*", "*booking*"], asistente: "comercial",
                               listas: ["invitees", "collection", "items", "data"], campos: camposContacto),
        ])

    public static let generico = PlantillaDeConector(
        id: "generico", nombre: "Otro programa",
        explicacion: "Cualquier otro programa compatible. Tú decides qué puede usar cada asistente.",
        direccionDeEjemplo: "https://", campos: [token],
        permisos: [
            PermisoDePlantilla(id: "mika-lee", asistente: "mika", que: "puede leer de", patrones: ["*"], lectura: true),
            PermisoDePlantilla(id: "mika-pide", asistente: "mika", que: "puede pedirte cambios (siempre con tu OK) en",
                               patrones: ["*"], lectura: false),
        ],
        reflejos: [])

    public static let todas: [PlantillaDeConector] = [web, ghl, stripe, calendly, generico]

    public static func plantilla(_ id: String) -> PlantillaDeConector {
        todas.first { $0.id == id } ?? generico
    }
}

/// Un interruptor tal como se enseña en Conexiones.
public struct FilaDeInterruptor: Sendable, Hashable, Identifiable {
    public var id: String { permiso.id }
    public let permiso: PermisoDePlantilla
    /// «El Comercial puede leer contactos de GoHighLevel».
    public let texto: String
    public let encendido: Bool
    /// Hay herramientas activas a las que se refiere (si no, el interruptor se enseña apagado y sin efecto).
    public let disponible: Bool
    /// El asistente existe y está activo.
    public let asistenteActivo: Bool
    public let herramientas: [String]
}

/// Los interruptores por asistente: viven en `herramientas_externas` de cada asistente en la configuración (que solo
/// cambia una persona, con `EditorConfigAgentes.aplicar(.asistente(…))`), así que el Autorizador y la configuración
/// confirmada los gobiernan como todo lo demás.
public enum Interruptores {
    /// Las herramientas activas a las que se refiere un permiso.
    public static func herramientas(_ p: PermisoDePlantilla, en c: Conexion) -> [HerramientaExterna] {
        (c.catalogo?.activas ?? []).filter(p.incluye)
    }

    public static func encendido(_ p: PermisoDePlantilla, en c: Conexion, asistente a: AsistenteConfigurado?) -> Bool {
        let hs = herramientas(p, en: c)
        guard let a, !hs.isEmpty else { return false }
        return hs.allSatisfy { Patrones.permite(a.herramientasExternas, expuesta: $0.expuesta) }
    }

    /// El asistente con el interruptor encendido o apagado (para `EditorConfigAgentes.aplicar(.asistente(…))`).
    /// Encender añade los nombres exactos de las herramientas activas de hoy: lo que llegue después queda fuera
    /// hasta que lo revises y vuelvas a encenderlo.
    public static func aplicar(_ p: PermisoDePlantilla, encender: Bool, en c: Conexion, a: AsistenteConfigurado) -> AsistenteConfigurado {
        var b = a
        let nombres = herramientas(p, en: c).map(\.expuesta)
        var lista = a.herramientasExternas.filter { !nombres.contains($0) }
        if encender { lista += nombres }
        b.herramientasExternas = lista
        return b
    }

    public static func filas(_ c: Conexion, config: ConfigAgentes) -> [FilaDeInterruptor] {
        let plantilla = PlantillasDeSerie.plantilla(c.plantilla)
        return plantilla.permisos.map { p in
            let a = config.asistente(p.asistente)
            let hs = herramientas(p, en: c)
            return FilaDeInterruptor(permiso: p, texto: p.texto(conexion: c.nombre), encendido: encendido(p, en: c, asistente: a),
                                     disponible: !hs.isEmpty, asistenteActivo: a?.activo == true, herramientas: hs.map(\.nombreVisible))
        }
    }
}

/// La matriz técnica (solo en Ajustes › Avanzado): cada herramienta, su clase, su estado y qué asistentes la tienen.
public struct FilaDeMatriz: Sendable, Hashable, Identifiable {
    public var id: String { expuesta }
    public let expuesta: String
    public let nombre: String
    public let clase: ClaseExterna
    public let motivo: MotivoDeClase
    public let estado: EstadoHerramienta
    public let huella: String
    /// Asistente → la tiene permitida.
    public let asistentes: [String: Bool]
}

public enum MatrizTecnica {
    public static func filas(_ c: Conexion, config: ConfigAgentes) -> [FilaDeMatriz] {
        let asistentes = config.agentes.keys.sorted()
        return (c.catalogo?.herramientas ?? []).filter { $0.estado != .retirada }.map { h in
            var m: [String: Bool] = [:]
            for s in asistentes { m[s] = Patrones.permite(config.agentes[s]?.herramientasExternas ?? [], expuesta: h.expuesta) }
            return FilaDeMatriz(expuesta: h.expuesta, nombre: h.nombre, clase: h.clase, motivo: h.motivo, estado: h.estado,
                                huella: String(h.huella.prefix(12)), asistentes: m)
        }
    }
}
