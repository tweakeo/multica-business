import Foundation
@testable import TLSCore

/// Ribera copiada a una carpeta temporal propia, con su índice fuera de ella. Nunca se toca el ejemplo del
/// repositorio.
struct EntornoBases {
    let base: URL
    let root: URL
    let estado: URL
    let entry: VaultEntry

    static var ribera: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    /// `antes` deja preparar la copia (añadir ficheros) antes de indexarla.
    init(antes: ((URL) throws -> Void)? = nil) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-bases-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Ribera", isDirectory: true)
        estado = base.appendingPathComponent("estado", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: Self.ribera, to: root)
            try antes?(root)
        } catch {
            try? FileManager.default.removeItem(at: base)
            throw error
        }
        entry = VaultEntry(nombre: "Asesoría Ribera", ruta: root.path, bookmark: nil, clase: .demo, escritura: .permitida)
    }

    func servicio(privado: [VaultPath] = []) async throws -> VaultService {
        let s = try VaultService(entry: entry, root: root,
                                 options: .init(privado: privado, stateDirectory: estado, vigilar: false))
        _ = try await s.open { _ in }
        return s
    }

    func lector(_ s: VaultService, persona: String? = "Manu") -> LectorBases {
        LectorBases(service: s, ajustes: AjustesBases.leer(root: root), persona: persona)
    }

    func escribir(_ ruta: String, _ texto: String) throws {
        let u = VaultPath(ruta).url(in: root)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: u)
    }

    func datos(_ ruta: String) -> Data? { try? Data(contentsOf: VaultPath(ruta).url(in: root)) }

    func limpiar() { try? FileManager.default.removeItem(at: base) }
}
