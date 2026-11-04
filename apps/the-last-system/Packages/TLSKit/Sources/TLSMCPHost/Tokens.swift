import CryptoKit
import Foundation
import Security
import TLSCore

/// Lo que la app sabe de la ejecución que está al otro lado del socket. Lo rellena el motor al lanzar (con la
/// configuración **confirmada** de `config.yaml`) y nunca viene del asistente.
public struct ContextoDelAsistente: Sendable, Hashable {
    /// Identificador de la ejecución (`AgentPaths.runID`).
    public var ejecucion: String
    /// `slug` del asistente (`mika`, `comercial`…): las escrituras van como `Autor.agente(slug)`.
    public var asistente: String
    /// El coordinador lee todas las áreas y es el único que puede delegar.
    public var coordinador: Bool
    /// Áreas propias (escribe y lee).
    public var areas: [AreaCode]
    /// Áreas que solo lee (`lee_areas`). `todas` = `AreaCode.allCases`.
    public var leeAreas: [AreaCode]
    /// 0 = lanzada por un disparador o por ti; 1 = delegada por el coordinador; 2 = delegada desde una delegada.
    public var profundidad: Int
    /// Ficha de tarea que la disparó (si la hay): ahí va la Actividad al terminar.
    public var tarea: VaultPath?
    /// `chat:<mensaje>` (⌘J) o `pregunta:<id>` (respuesta a una pregunta): lo único que permite
    /// `tls_registrar_decision` sin convertirla en propuesta.
    public var origen: String?
    /// `max_tareas_por_ejecucion` de su configuración.
    public var maxTareas: Int
    /// Trabaja en el Buzón (Cartero, Ordenador): puede leerlo y mover desde él.
    public var buzon: Bool
    /// Ejecución simulada (`SimulatedRuntime`): lo que crea lleva `simulado: true`.
    public var simulado: Bool

    public init(ejecucion: String, asistente: String, coordinador: Bool = false, areas: [AreaCode] = [],
                leeAreas: [AreaCode] = [], profundidad: Int = 0, tarea: VaultPath? = nil, origen: String? = nil,
                maxTareas: Int = 10, buzon: Bool = false, simulado: Bool = false) {
        self.ejecucion = ejecucion; self.asistente = asistente; self.coordinador = coordinador; self.areas = areas
        self.leeAreas = leeAreas; self.profundidad = profundidad; self.tarea = tarea; self.origen = origen
        self.maxTareas = maxTareas; self.buzon = buzon; self.simulado = simulado
    }

    public var autor: Autor { .agente(asistente) }

    /// Áreas que puede leer: el coordinador, todas; si no, las suyas y las de `lee_areas`.
    public var areasLegibles: Set<AreaCode> {
        coordinador ? Set(AreaCode.allCases) : Set(areas).union(leeAreas)
    }

    /// Áreas donde puede escribir (crear tareas, comentar…): el coordinador, todas.
    public var areasEscribibles: Set<AreaCode> {
        coordinador ? Set(AreaCode.allCases) : Set(areas)
    }

    /// Dónde lee: sus áreas, `lee_areas` y, si trabaja en él (o coordina), el Buzón.
    public var lectura: Alcance { Alcance(areas: areasLegibles, buzon: buzon || coordinador) }

    /// Dónde escribe: sus áreas y, si trabaja en él (o coordina), el Buzón.
    public var escritura: Alcance { Alcance(areas: areasEscribibles, buzon: buzon || coordinador) }

    /// Profundidad máxima de delegación (PLAN §5.1 y §5.2, paso 9).
    public static let profundidadMaxima = 2
}

/// Token de 32 bytes por ejecución, en hexadecimal (64 caracteres). Solo vale mientras la ejecución está en curso:
/// el motor lo revoca al terminar o al cancelar (y caduca solo, por si acaso, a las `duracionMaxima` horas).
public final class AlmacenDeTokens: @unchecked Sendable {
    struct Entrada {
        var contexto: ContextoDelAsistente
        var emitido: Date
    }

    private let lock = NSLock()
    /// Por la huella SHA-256 del token: nunca se compara el token en claro.
    private var entradas: [Data: Entrada] = [:]
    public let duracionMaxima: TimeInterval
    private let ahora: @Sendable () -> Date

    public init(duracionMaxima: TimeInterval = 3 * 3600, ahora: @escaping @Sendable () -> Date = { Date() }) {
        self.duracionMaxima = duracionMaxima
        self.ahora = ahora
    }

    /// Emite el token de una ejecución que empieza.
    public func emitir(_ contexto: ContextoDelAsistente) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Sin aleatoriedad del sistema no se emite nada utilizable.
            bytes = Array(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        lock.withLock { entradas[Self.huella(token)] = Entrada(contexto: contexto, emitido: ahora()) }
        return token
    }

    /// Contexto de un token válido; `nil` si no existe, se revocó o caducó.
    public func contexto(de token: String) -> ContextoDelAsistente? {
        let h = Self.huella(token)
        return lock.withLock {
            guard let e = entradas[h] else { return nil }
            guard ahora().timeIntervalSince(e.emitido) <= duracionMaxima else {
                entradas[h] = nil
                return nil
            }
            return e.contexto
        }
    }

    /// Revoca un token (la ejecución terminó o se canceló).
    public func revocar(_ token: String) {
        _ = lock.withLock { entradas.removeValue(forKey: Self.huella(token)) }
    }

    /// Revoca todos los tokens de una ejecución.
    public func revocar(ejecucion: String) {
        lock.withLock { entradas = entradas.filter { $0.value.contexto.ejecucion != ejecucion } }
    }

    /// Al cerrar la empresa o salir de la app.
    public func revocarTodos() {
        lock.withLock { entradas.removeAll() }
    }

    public var vigentes: Int { lock.withLock { entradas.count } }

    static func huella(_ token: String) -> Data {
        Data(SHA256.hash(data: Data(token.lowercased().utf8)))
    }
}
