import Foundation
import TLSCore

/// Lo que necesita quien calcula los números clave de un área.
public struct ContextoNumeros: Sendable {
    /// Foto de toda la carpeta. **Incluye lo privado**: el proveedor lo salta con `foto.layout.isPrivate(_:)`.
    public let foto: VaultSnapshot
    /// El día de la carpeta (en el ejemplo, su día fijo).
    public let hoy: LocalDate
    /// Las filas de `Metas.md` (todas las áreas), con meta y alerta tal como están escritas.
    public let metas: [FilaControl]

    public init(foto: VaultSnapshot, hoy: LocalDate, metas: [FilaControl]) {
        self.foto = foto; self.hoy = hoy; self.metas = metas
    }
}

/// Lo que el proveedor sabe de un área: la lectura de cada código y su etapa.
public struct NumerosDeArea: Sendable, Hashable {
    /// Lectura de los códigos que sabe calcular (los demás, «Sin dato»).
    public var lecturas: [String: LecturaNumero]
    /// Etapa del área (1 a 6) si la sabe calcular; manda la que diga `Área.md`.
    public var etapa: Int?

    public init(lecturas: [String: LecturaNumero] = [:], etapa: Int? = nil) {
        self.lecturas = lecturas; self.etapa = etapa
    }

    public static let ninguno = NumerosDeArea()
}

/// Quien pone el valor, el ritmo y la fuente de los códigos de `Metas.md` (rol de números, F2). Se llama fuera
/// del hilo principal, una vez por área y foto. Lo que no sabe, no lo devuelve: el andamio enseña «Sin dato».
/// **Nunca un 0 inventado.**
public protocol ProveedorNumerosArea: Sendable {
    func numeros(de area: AreaCode, codigos: [String], contexto: ContextoNumeros) -> NumerosDeArea
}

/// Sin números: todo «Sin dato».
public struct SinNumeros: ProveedorNumerosArea {
    public init() {}
    public func numeros(de area: AreaCode, codigos: [String], contexto: ContextoNumeros) -> NumerosDeArea { .ninguno }
}

/// Dónde se elige el proveedor de números de las áreas (uno para toda la app).
@MainActor
public enum ProveedoresArea {
    /// El proveedor que usan el andamio de las áreas y sus pantallas: por defecto, el del núcleo
    /// (`NumerosDelNucleo`: `KPIEvaluador` y `EtapaCalculador`). Las pruebas pueden poner otro.
    public static var numeros: any ProveedorNumerosArea = NumerosDelNucleo()
}
