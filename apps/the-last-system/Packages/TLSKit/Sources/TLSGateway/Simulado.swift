import Foundation
import MCP

// F5 · integración. El programa de mentira del ejemplo (Asesoría Ribera): un «CRM de ejemplo» con contactos y
// oportunidades ficticios que la app enseña marcado «Simulado». No hay red, ni clave, ni Llavero: el cliente vive en la
// app y responde siempre lo mismo. Sirve para ver en el ejemplo cómo funciona «Otros programas» (herramientas que solo
// leen, una que cambia cosas y pide tu OK, y una con un nombre sensible bloqueada), sin que nada salga del Mac.

public enum ConectorSimulado {
    /// Identificador de la conexión del ejemplo.
    public static let id = "simulado"
    public static let nombre = "CRM de ejemplo"
    /// La dirección no se usa nunca (`FabricaSimulada` no abre conexiones), pero `Conexion.validar` pide una.
    public static let direccion = "https://ejemplo.invalid/mcp"

    /// La conexión del ejemplo (plantilla GoHighLevel: sus interruptores y su reflejo de contactos y oportunidades).
    public static func conexion(ahora: Date = Date()) -> Conexion {
        Conexion(id: id, nombre: nombre, plantilla: "ghl",
                 transporte: .http(HTTPDeConexion(url: direccion, cabecera: nil, campo: nil)), creada: ahora)
    }

    /// Lo que ofrece: dos que solo leen, una que cambia cosas (sin indicación: pide tu OK) y una con nombre sensible.
    public static var herramientas: [Tool] {
        let vacio: Value = .object(["type": "object", "properties": .object([:])])
        return [
            Tool(name: "contacts_list", description: "Lista los contactos del CRM de ejemplo (ficticios).",
                 inputSchema: vacio, annotations: .init(readOnlyHint: true)),
            Tool(name: "opportunities_list", description: "Lista las oportunidades del CRM de ejemplo (ficticias).",
                 inputSchema: vacio, annotations: .init(readOnlyHint: true)),
            Tool(name: "contacts_update", description: "Cambia la etapa de un contacto en el CRM de ejemplo.",
                 inputSchema: .object(["type": "object",
                                       "properties": .object(["id": .object(["type": "string"]),
                                                              "etapa": .object(["type": "string"])]),
                                       "required": .array(["id", "etapa"]), "additionalProperties": false])),
            Tool(name: "send_message", description: "Envía un mensaje a un contacto desde el CRM de ejemplo.",
                 inputSchema: .object(["type": "object",
                                       "properties": .object(["id": .object(["type": "string"]),
                                                              "texto": .object(["type": "string"])]),
                                       "required": .array(["id", "texto"]), "additionalProperties": false])),
        ]
    }

    /// Contactos ficticios (nombres neutros; ningún dato real).
    static let contactos: Value = .object(["contacts": .array([
        .object(["id": "sim-001", "name": "Lead de ejemplo · Taller Norte", "email": "contacto@taller-norte.invalid",
                 "company": "Taller Norte (ficticio)", "source": "Formulario web"]),
        .object(["id": "sim-002", "name": "Lead de ejemplo · Clínica Sur", "email": "hola@clinica-sur.invalid",
                 "company": "Clínica Sur (ficticia)", "source": "Recomendación"]),
    ])])

    static let oportunidades: Value = .object(["opportunities": .array([
        .object(["id": "sim-op-1", "name": "Asesoría mensual · Taller Norte", "monetaryValue": 180, "source": "Formulario web"]),
    ])])

    static func respuesta(_ nombre: String, argumentos: [String: Value]) -> CallTool.Result {
        let texto: String
        switch nombre {
        case "contacts_list": texto = JSONCanonico.texto(contactos)
        case "opportunities_list": texto = JSONCanonico.texto(oportunidades)
        default: texto = "Hecho en el CRM de ejemplo (simulado): no ha salido nada de tu Mac."
        }
        return CallTool.Result(content: [.text(text: texto, annotations: nil, _meta: nil)])
    }
}

/// Clientes de mentira: cualquier conexión del ejemplo responde con `ConectorSimulado` (nunca abre la red ni lanza nada).
public struct FabricaSimulada: FabricaDeClientes {
    public init() {}

    public func abrir(_ c: Conexion, secretos: [String: String],
                      alCambiarLista: @escaping @Sendable () async -> Void) async throws -> any ClienteExterno {
        ClienteSimulado()
    }
}

struct ClienteSimulado: ClienteExterno {
    func listarHerramientas() async throws -> [Tool] { ConectorSimulado.herramientas }
    func llamar(_ nombre: String, argumentos: [String: Value]) async throws -> CallTool.Result {
        ConectorSimulado.respuesta(nombre, argumentos: argumentos)
    }
    func cerrar() async {}
}
