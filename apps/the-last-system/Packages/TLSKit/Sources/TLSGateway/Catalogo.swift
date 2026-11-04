import CryptoKit
import Foundation
import MCP

/// Lectura o sensible (PLAN §7.4). Lo sensible pide siempre aprobación atada a la huella.
public enum ClaseExterna: String, Codable, Sendable, Hashable {
    case lectura
    case sensible

    /// En pantalla.
    public var texto: String {
        switch self {
        case .lectura: "Solo lee"
        case .sensible: "Cambia cosas: pide tu OK"
        }
    }
}

/// Por qué una herramienta quedó en su clase.
public enum MotivoDeClase: Codable, Sendable, Hashable {
    /// El otro programa dice que solo lee (`readOnlyHint`).
    case soloLectura
    /// No dice que solo lea: sensible por prudencia.
    case sinIndicacion
    /// Su nombre lleva una palabra de salida (send, pay, delete…): sensible siempre, diga lo que diga.
    case nombreSensible(String)

    public var texto: String {
        switch self {
        case .soloLectura: "El programa dice que solo lee."
        case .sinIndicacion: "El programa no dice que solo lea: se trata como sensible."
        case .nombreSensible(let p): "Su nombre lleva «\(p)»: siempre pide tu OK."
        }
    }
}

/// Estado de una herramienta en la conexión.
public enum EstadoHerramienta: String, Codable, Sendable, Hashable {
    /// Se puede usar (si además el asistente tiene permiso).
    case activa
    /// Nueva o cambiada desde la última revisión: desactivada hasta que la revises.
    case pendienteDeRevision = "pendiente_de_revision"
    /// La revisaste y dijiste que no.
    case rechazada
    /// El programa ya no la ofrece.
    case retirada

    public var texto: String {
        switch self {
        case .activa: "Activa"
        case .pendienteDeRevision: "Nueva: desactivada hasta que la revises"
        case .rechazada: "Desactivada por ti"
        case .retirada: "El programa ya no la ofrece"
        }
    }
}

/// Una herramienta de otro programa tal como la guarda la app.
public struct HerramientaExterna: Codable, Sendable, Hashable {
    /// Nombre en el otro programa (`contacts_list`).
    public var nombre: String
    /// Nombre que ven los asistentes (`ext_ghl_contacts_list`).
    public var expuesta: String
    public var titulo: String?
    /// Como mucho 300 caracteres, con los secretos ocultados.
    public var descripcion: String
    public var esquema: Value
    public var clase: ClaseExterna
    public var motivo: MotivoDeClase
    /// Huella de lo que dijo el programa (nombre, título, descripción entera, esquema e indicaciones).
    public var huella: String
    public var estado: EstadoHerramienta
    public var vista: Date

    public var nombreVisible: String { titulo?.nilSiVacio ?? nombre }
}

/// El catálogo de una conexión con su huella.
public struct CatalogoDeConexion: Codable, Sendable, Hashable {
    /// Huella del catálogo entero (las huellas de cada herramienta, ordenadas).
    public var huella: String
    public var herramientas: [HerramientaExterna]
    public var actualizado: Date

    public func herramienta(_ nombre: String) -> HerramientaExterna? { herramientas.first { $0.nombre == nombre } }
    public func herramienta(expuesta: String) -> HerramientaExterna? { herramientas.first { $0.expuesta == expuesta } }
    public var activas: [HerramientaExterna] { herramientas.filter { $0.estado == .activa } }
    public var pendientes: [HerramientaExterna] { herramientas.filter { $0.estado == .pendienteDeRevision } }
}

/// Qué cambió al volver a listar.
public struct CambiosDeCatalogo: Sendable, Hashable {
    public var primeraVez: Bool
    public var nuevas: [String]
    public var cambiadas: [String]
    public var retiradas: [String]
    public var huellaAnterior: String?
    public var huella: String

    public var cambioLaHuella: Bool { huellaAnterior != nil && huellaAnterior != huella }
    /// Lo que queda desactivado hasta que lo revises.
    public var paraRevisar: [String] { nuevas + cambiadas }
}

/// Clasificación, huellas, nombres expuestos y revisión del catálogo (PLAN §7.4).
public enum Catalogo {
    /// Palabras que hacen sensible una herramienta por su nombre, diga lo que diga el programa.
    public static let palabrasSensibles = ["send", "publish", "pay", "charge", "refund", "invoice", "transfer", "delete",
                                          "email", "sms", "message"]

    /// La palabra de salida que lleva el nombre, si lleva alguna. Se busca dentro del nombre entero, en minúsculas y
    /// sin separadores (así `sendEmail`, `send-sms` o `createinvoice` también cuentan); alguna de lectura que la
    /// contenga por casualidad (`display_…`) queda sensible: mejor pedir un OK de más que uno de menos.
    public static func palabraSensible(_ nombre: String) -> String? {
        let plano = nombre.lowercased().filter { $0.isLetter || $0.isNumber }
        return palabrasSensibles.first { plano.contains($0) }
    }

    public static func clasificar(_ t: Tool) -> (ClaseExterna, MotivoDeClase) {
        if let p = palabraSensible(t.name) { return (.sensible, .nombreSensible(p)) }
        if t.annotations.readOnlyHint == true { return (.lectura, .soloLectura) }
        return (.sensible, .sinIndicacion)
    }

    /// Huella de una herramienta (todo lo que dijo el programa, en JSON canónico).
    public static func huella(_ t: Tool) -> String {
        let v: Value = .object([
            "name": .string(t.name), "title": t.title.map(Value.string) ?? .null,
            "description": t.description.map(Value.string) ?? .null, "inputSchema": t.inputSchema,
            "readOnlyHint": t.annotations.readOnlyHint.map(Value.bool) ?? .null,
            "destructiveHint": t.annotations.destructiveHint.map(Value.bool) ?? .null,
            "openWorldHint": t.annotations.openWorldHint.map(Value.bool) ?? .null,
        ])
        return sha256(JSONCanonico.texto(v))
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `ext_<servidor>_<herramienta>` en minúsculas, letras, cifras y `_`; 60 caracteres como mucho.
    public static func nombreExpuesto(servidor: String, herramienta: String) -> String {
        var limpio = ""
        var anteriorGuion = false
        for ch in herramienta.lowercased() {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                limpio.append(ch)
                anteriorGuion = false
            } else if !anteriorGuion {
                limpio.append("_")
                anteriorGuion = true
            }
        }
        limpio = limpio.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if limpio.isEmpty { limpio = "h" + String(sha256(herramienta).prefix(6)) }
        let base = TLSGatewayInfo.prefijo + servidor + "_"
        let maximo = 60 - base.count
        if limpio.count > maximo { limpio = String(limpio.prefix(maximo - 7)) + "_" + String(sha256(herramienta).prefix(6)) }
        return base + limpio
    }

    /// Recorta una descripción a 300 caracteres sin partir palabras y oculta lo que parezca un secreto.
    public static func descripcion(_ d: String?, secretos: [String] = []) -> String {
        let limpio = Ocultador.ocultar((d ?? "").replacingOccurrences(of: "\r", with: " "), secretos: secretos)
            .split(whereSeparator: { $0.isNewline }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard limpio.count > TLSGatewayInfo.topeDescripcion else { return limpio }
        let corte = limpio.prefix(TLSGatewayInfo.topeDescripcion - 1)
        let hasta = corte.lastIndex(of: " ").map { corte[..<$0] } ?? corte
        return String(hasta) + "…"
    }

    /// Revisa lo que lista el programa frente a lo guardado. La primera vez, todo queda activo (lo estás conectando
    /// tú y lo ves). Después, lo nuevo **y lo que cambió** queda desactivado hasta que lo revises; lo que ya no está,
    /// retirado.
    public static func revisar(previo: CatalogoDeConexion?, herramientas: [Tool], servidor: String, secretos: [String] = [],
                               ahora: Date = Date()) -> (CatalogoDeConexion, CambiosDeCatalogo) {
        var out: [HerramientaExterna] = []
        var nuevas: [String] = []
        var cambiadas: [String] = []
        var usados: Set<String> = []
        var vistos: Set<String> = []
        for t in herramientas.sorted(by: { $0.name < $1.name }) where !vistos.contains(t.name) {
            vistos.insert(t.name)
            let (clase, motivo) = clasificar(t)
            let h = huella(t)
            var expuesta = nombreExpuesto(servidor: servidor, herramienta: t.name)
            if usados.contains(expuesta) {
                expuesta = String(expuesta.prefix(53)) + "_" + String(sha256(t.name).prefix(6))
            }
            usados.insert(expuesta)
            let antes = previo?.herramienta(t.name)
            let estado: EstadoHerramienta
            if previo == nil {
                estado = .activa
            } else if let a = antes, a.huella == h, a.estado != .retirada {
                estado = a.estado
            } else if let a = antes, a.estado != .retirada {
                // Mismo nombre, otra huella (otra descripción, otro esquema…): se revisa otra vez.
                estado = a.estado == .rechazada ? .rechazada : .pendienteDeRevision
                cambiadas.append(t.name)
            } else {
                estado = .pendienteDeRevision
                nuevas.append(t.name)
            }
            out.append(HerramientaExterna(
                nombre: t.name, expuesta: expuesta,
                titulo: t.title.map { Ocultador.ocultar(String($0.prefix(120)), secretos: secretos) },
                descripcion: descripcion(t.description, secretos: secretos), esquema: t.inputSchema, clase: clase,
                motivo: motivo, huella: h, estado: estado,
                vista: (antes?.huella == h ? antes?.vista : nil) ?? ahora))
        }
        var retiradas: [String] = []
        for a in previo?.herramientas ?? [] where !vistos.contains(a.nombre) {
            if a.estado != .retirada { retiradas.append(a.nombre) }
            var r = a
            r.estado = .retirada
            out.append(r)
        }
        let huellaTotal = sha256(out.filter { $0.estado != .retirada }.map { "\($0.nombre)=\($0.huella)" }.sorted().joined(separator: "\n"))
        let cat = CatalogoDeConexion(huella: huellaTotal, herramientas: out, actualizado: ahora)
        return (cat, CambiosDeCatalogo(primeraVez: previo == nil, nuevas: nuevas, cambiadas: cambiadas, retiradas: retiradas,
                                       huellaAnterior: previo?.huella, huella: huellaTotal))
    }
}

/// JSON canónico de un `Value`: claves ordenadas, sin espacios, barras sin escapar.
public enum JSONCanonico {
    public static func texto(_ v: Value) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    public static func texto<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
}

extension String {
    var nilSiVacio: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
