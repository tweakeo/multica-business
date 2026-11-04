import Foundation
import MCP
import TLSCore

/// Lo que se aprueba al pedir una herramienta sensible de otro programa: va, en JSON canónico, en la sección «Mensaje»
/// del borrador, así que la huella de la aprobación (`SHA256("externa:<herramienta>|" + carga)`) ata **la herramienta,
/// su versión (huella) y los argumentos exactos**. Si cambia una coma, ya no es lo aprobado.
public struct PeticionExterna: Codable, Sendable, Hashable {
    /// `ext_<servidor>_<herramienta>`.
    public var herramienta: String
    /// Huella de la herramienta cuando se pidió (si el programa la cambia, no se ejecuta).
    public var huella: String
    public var argumentos: [String: Value]

    public init(herramienta: String, huella: String, argumentos: [String: Value]) {
        self.herramienta = herramienta; self.huella = huella; self.argumentos = argumentos
    }

    /// JSON canónico (una línea).
    public var texto: String { JSONCanonico.texto(self) }

    public static func leer(_ texto: String) -> PeticionExterna? {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        // Por si alguien la dejó en un bloque de código al «Aprobar con mis cambios».
        if t.hasPrefix("```") {
            t = t.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
                .filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        return try? JSONDecoder().decode(PeticionExterna.self, from: Data(t.utf8))
    }
}

/// El hueco de pasarela de `EjecutorDeAprobaciones` (PLAN §5.2): al aprobar, **la app** llama a la herramienta con los
/// argumentos exactos aprobados (los de `aprobacion.carga`, no los de la ficha), si la herramienta sigue activa, con la
/// misma huella y el asistente sigue teniendo permiso. Lo deja en la Actividad del borrador y en la Bitácora.
public struct GatewayRouter: ProtocoloDePasarela {
    public let pasarela: Pasarela
    /// ¿El asistente sigue teniendo esa herramienta? (`herramientas_externas` de la configuración confirmada).
    public let permiso: (@Sendable (_ asistente: String, _ expuesta: String) async -> Bool)?
    public let reloj: (@Sendable (VaultSnapshot) -> Reloj)?

    public init(pasarela: Pasarela, permiso: (@Sendable (String, String) async -> Bool)? = nil,
                reloj: (@Sendable (VaultSnapshot) -> Reloj)? = nil) {
        self.pasarela = pasarela; self.permiso = permiso; self.reloj = reloj
    }

    public func llamar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
        let ap = a.aprobacion
        guard let expuesta = ap.herramienta, expuesta.hasPrefix(TLSGatewayInfo.prefijo) else {
            return .pendienteDeConexion("Aprobado. No dice a qué programa va: no ha salido nada.")
        }
        guard let peticion = ap.carga.cuerpo.flatMap(PeticionExterna.leer), peticion.herramienta == expuesta else {
            throw ErrorDePasarela.argumentosNoValidos("lo aprobado no se entiende como datos para el programa; no he hecho nada.")
        }
        let hc = pasarela.buscar(expuesta: expuesta)
        let nombre = hc.map { "«\($0.herramienta.nombreVisible)» en \($0.conexion.nombre)" } ?? "«\(expuesta)»"
        if let permiso, !(await permiso(ap.agente, expuesta)) {
            throw ErrorDePasarela.sinPermiso("\(AsistenteConfigurado.nombre(de: ap.agente)) ya no puede usar \(nombre): no hago lo que preparó.")
        }
        let registro = RegistroEnFicheros(bus: a.bus, foto: { a.snapshot }, reloj: reloj)
        do {
            _ = try await pasarela.ejecutarAprobada(expuesta: expuesta, huella: peticion.huella, argumentos: peticion.argumentos)
        } catch {
            await registro.anotar(agente: ap.agente, que: "Usar \(nombre) (aprobado por \(a.persona.etiqueta))",
                                  resultado: "con error", ejecucion: ap.ejecucion, hash: ap.hash,
                                  actividadEn: ap.ruta, actividad: Self.textoDeFallo(error),
                                  quien: a.persona.etiqueta)
            throw error
        }
        await registro.anotar(agente: ap.agente, que: "Usó \(nombre) (aprobado por \(a.persona.etiqueta))", resultado: "hecho",
                              ejecucion: ap.ejecucion, hash: ap.hash, actividadEn: ap.ruta,
                              actividad: "Aprobado y hecho en \(hc?.conexion.nombre ?? "el otro programa"), con los datos exactos aprobados.",
                              quien: a.persona.etiqueta)
        return .enviadoAPasarela("Hecho: \(nombre), con los datos exactos que aprobaste.")
    }

    /// Lo que queda en la Actividad de la ficha si falla: nuestros motivos tal cual; lo que diga el otro programa, no
    /// (S6: es un dato suyo y puede traer instrucciones o claves).
    static func textoDeFallo(_ error: any Error) -> String {
        if case ErrorDePasarela.programaConError? = error as? ErrorDePasarela {
            return "No se pudo hacer en el otro programa: respondió con un error. No ha cambiado nada en tu carpeta."
        }
        return "No se pudo hacer en el otro programa: \(error.localizedDescription)"
    }
}

/// Lo que la pasarela deja en la carpeta (como la app, `Autor.sistema`, por el `CommandBus`): una línea de Bitácora y,
/// si hay ficha, una entrada en su «Actividad». Nunca falla hacia fuera: si no se puede escribir, no se para nada.
public struct RegistroEnFicheros: Sendable {
    public let bus: CommandBus?
    public let foto: @Sendable () async -> VaultSnapshot
    public let reloj: (@Sendable (VaultSnapshot) -> Reloj)?

    public init(bus: CommandBus?, foto: @escaping @Sendable () async -> VaultSnapshot,
                reloj: (@Sendable (VaultSnapshot) -> Reloj)? = nil) {
        self.bus = bus; self.foto = foto; self.reloj = reloj
    }

    /// Una línea de Bitácora y, si se da, una entrada de Actividad en `actividadEn` (y en `masFichas`).
    public func anotar(agente: String, capacidad: String? = nil, que: String, resultado: String, ejecucion: String? = nil,
                       hash: String? = nil, actividadEn: VaultPath? = nil, masFichas: [VaultPath] = [], actividad: String? = nil,
                       quien: String? = nil) async {
        guard let bus else { return }
        let f = await foto()
        let r = reloj?(f) ?? Reloj.deCarpeta(f)
        let hora = Self.hora(r)
        let linea = LineaBitacora(fecha: r.hoy, hora: hora, agente: agente, capacidad: capacidad, que: que, resultado: resultado,
                                  ejecucion: ejecucion, hash: hash)
        var ops = Bitacora.ops([linea], layout: f.layout, existe: { f.existing($0) != nil })
        if let texto = actividad {
            let cabecera = "### \(r.hoy) \(hora) · \(quien ?? "agente:\(ConfigAgentes.slug(agente))")"
            for ruta in ([actividadEn].compactMap { $0 } + masFichas) where f.existing(ruta) != nil {
                ops.append(.appendToSection(ruta, section: "Actividad", text: cabecera + "\n" + texto, blankLine: true))
            }
        }
        _ = try? await bus.ejecutar(WritePlan(autor: .sistema, descripcion: "Otros programas: \(que)", ops: ops))
    }

    static func hora(_ r: Reloj) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = r.zona
        let c = cal.dateComponents([.hour, .minute], from: r.ahora)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
