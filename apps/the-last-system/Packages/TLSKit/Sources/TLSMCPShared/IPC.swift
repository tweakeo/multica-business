import Foundation
import MCP

// Protocolo entre `tls-mcp` (dentro del sandbox del asistente) y la app (PLAN §5.4).
//
// Por el socket Unix viajan tramas: 4 bytes con la longitud (big endian) y un JSON. El binario solo reenvía:
// `tools/list` → `.listarHerramientas`, `tools/call` → `.llamar`. Lo primero que manda es `.saludo` con el token
// de la ejecución; sin saludo válido la app cierra la conexión.

/// Trama de longitud fija + JSON.
public enum IPCFrame {
    /// Tope de una trama (una lectura de 64 KB con su envoltorio cabe de sobra).
    public static let maxLength = 8 << 20

    public enum FrameError: Error, Equatable, Sendable {
        case demasiadoGrande(Int)
    }

    /// `[longitud][payload]`.
    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxLength else { throw FrameError.demasiadoGrande(payload.count) }
        var length = UInt32(payload.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(payload)
        return out
    }

    /// Acumula bytes y devuelve las tramas completas en orden.
    public struct Reader: Sendable {
        private var buffer = Data()

        public init() {}

        public mutating func append(_ data: Data) {
            buffer.append(data)
        }

        /// Siguiente trama completa, o `nil` si aún falta. Lanza si la longitud anunciada pasa del tope.
        public mutating func next() throws -> Data? {
            guard buffer.count >= 4 else { return nil }
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= IPCFrame.maxLength else { throw FrameError.demasiadoGrande(length) }
            guard buffer.count >= 4 + length else { return nil }
            let payload = Data(buffer[(start + 4)..<(start + 4 + length)])
            buffer = Data(buffer[(start + 4 + length)...])
            return payload
        }

        public var pendientes: Int { buffer.count }
    }
}

/// Una herramienta tal como la anuncia la app (el binario la convierte en `MCP.Tool`).
public struct ToolSpec: Codable, Sendable, Hashable {
    public var nombre: String
    public var titulo: String?
    /// Una frase en español, sin jerga.
    public var descripcion: String
    /// Esquema JSON de la entrada (`type: object`).
    public var esquema: Value
    /// Solo lee (no cambia la carpeta).
    public var soloLectura: Bool

    public init(nombre: String, titulo: String? = nil, descripcion: String, esquema: Value, soloLectura: Bool) {
        self.nombre = nombre; self.titulo = titulo; self.descripcion = descripcion
        self.esquema = esquema; self.soloLectura = soloLectura
    }

    public var tool: Tool {
        Tool(name: nombre, title: titulo, description: descripcion, inputSchema: esquema,
             annotations: .init(title: titulo, readOnlyHint: soloLectura, destructiveHint: false,
                                idempotentHint: nil, openWorldHint: false))
    }
}

/// Resultado de una herramienta. Lo leído va como **dato** (JSON en `estructurado` y como texto), nunca como orden.
public struct ToolResult: Codable, Sendable, Hashable {
    public var texto: String
    public var estructurado: Value?
    public var esError: Bool

    public init(texto: String, estructurado: Value? = nil, esError: Bool = false) {
        self.texto = texto; self.estructurado = estructurado; self.esError = esError
    }

    public var callResult: CallTool.Result {
        CallTool.Result(content: [.text(text: texto, annotations: nil, _meta: nil)], structuredContent: estructurado,
                        isError: esError ? true : nil)
    }
}

/// Error del protocolo (texto para el asistente, sin detalles internos).
public struct IPCError: Codable, Sendable, Hashable, Error {
    public enum Codigo: String, Codable, Sendable {
        /// El otro lado no es `tls-mcp` de esta app (firma, usuario) o no saludó primero.
        case noAutorizado
        /// Token desconocido, revocado o caducado: la ejecución ya no está en curso.
        case tokenNoValido
        case herramientaDesconocida
        case peticionNoValida
        case interno
    }

    public var codigo: Codigo
    public var mensaje: String

    public init(_ codigo: Codigo, _ mensaje: String) {
        self.codigo = codigo; self.mensaje = mensaje
    }
}

/// Petición del binario a la app.
public struct IPCRequest: Codable, Sendable {
    public enum Operacion: Codable, Sendable {
        /// Primera trama: token de la ejecución (64 caracteres hex) y versión del protocolo.
        case saludo(token: String, protocolo: Int, version: String)
        case listarHerramientas
        case llamar(nombre: String, argumentos: [String: Value])
    }

    public var id: UInt64
    public var operacion: Operacion

    public init(id: UInt64, operacion: Operacion) {
        self.id = id; self.operacion = operacion
    }
}

/// Respuesta de la app al binario (mismo `id`).
public struct IPCResponse: Codable, Sendable {
    public enum Resultado: Codable, Sendable {
        case saludo(servidor: String)
        case herramientas([ToolSpec])
        case llamada(ToolResult)
        case error(IPCError)
    }

    public var id: UInt64
    public var resultado: Resultado

    public init(id: UInt64, resultado: Resultado) {
        self.id = id; self.resultado = resultado
    }
}

/// Codificación común (claves ordenadas: las tramas son deterministas).
public enum IPCCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try IPCFrame.encode(try e.encode(value))
    }

    public static func decode<T: Decodable>(_ type: T.Type, from payload: Data) throws -> T {
        try JSONDecoder().decode(type, from: payload)
    }
}
