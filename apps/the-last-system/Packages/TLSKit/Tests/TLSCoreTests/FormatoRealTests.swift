import Foundation
import Testing
@testable import TLSCore

/// Comprobaciones contra carpetas de fuera del repositorio, solo si se indican por entorno.
/// Ningún dato real se guarda en el código: las rutas llegan por variables de entorno y
/// solo se comprueba la forma del resultado.
///
/// - `TLS_AREAS_REALES`: carpeta con `N · Área/Área.md` (solo se leen esos 6 ficheros).
/// - `TLS_RIBERA_DIR`: carpeta de la demo antigua (formato G2).
@Suite struct FormatoRealTests {
    static let areasDir = ProcessInfo.processInfo.environment["TLS_AREAS_REALES"]
    static let riberaDir = ProcessInfo.processInfo.environment["TLS_RIBERA_DIR"]

    @Test(.enabled(if: areasDir != nil)) func areaRealConFormatoActual() throws {
        let base = URL(fileURLWithPath: Self.areasDir!, isDirectory: true)
        for code in AreaCode.allCases {
            let folder = VaultPath("\(code.numero) · \(code.nombre)")
            let file = folder.appending(AreaReader.fileName)
            let text = try String(contentsOf: file.url(in: base), encoding: .utf8)
            // Sin disco: el resolvedor solo calcula la ruta relativa.
            let a = AreaReader.parse(markdown: text, code: code, folder: folder) { target in
                LinkResolver(paths: []).resolve(target, from: file) ?? file.resolvingRelative(target)
            }
            print("\(code.rawValue) · \(a.estado.rawValue) · lleva=\(a.lleva != nil) · rol=\(a.rol != nil) · transforma=\(a.transforma?.count ?? 0) car. · sistemas=\(a.sistemas.count) (con ruta \(a.sistemas.filter { $0.path != nil }.count), con resumen \(a.sistemas.filter { $0.resumen != nil }.count))")
            #expect(a.estado != .desconocido, "\(code.rawValue)")
            #expect(a.lleva != nil)
            #expect(a.rol != nil)
            #expect(a.transforma != nil)
            #expect(!a.sistemas.isEmpty)
            #expect(a.sistemas.allSatisfy { $0.path?.isDescendant(of: folder.appending("Sistemas")) == true })
        }
    }

    @Test(.enabled(if: riberaDir != nil)) func demoAntiguaDegradaConElegancia() async throws {
        let root = URL(fileURLWithPath: Self.riberaDir!, isDirectory: true)
        let antes = Apoyo.huellaDeArbol(root)
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        let svc = try VaultService(entry: Apoyo.entrada(root), root: root,
                                   options: .init(stateDirectory: state, vigilar: false))
        #expect(svc.layout.preset == .demo)
        let stats = try await svc.open { _ in }
        let areas = svc.areas()
        print("Demo antigua: \(stats.notes) notas en \(String(format: "%.2f", stats.seconds)) s; áreas: \(areas.map { "\($0.folder.raw)=\($0.estado.rawValue)" })")
        #expect(areas.count == 6)
        #expect(areas.allSatisfy { $0.estado == .desconocido && !$0.tieneFicha })
        let kinds = Set((try svc.indexDump()).filter { $0.hasPrefix("N|") }.map { $0.split(separator: "|")[4].replacingOccurrences(of: "\"", with: "") })
        #expect(kinds.contains("contact"))
        #expect(kinds.contains("opportunity"))
        #expect(!svc.quickOpen("ren", limit: 3).isEmpty)
        svc.close()
        #expect(Apoyo.huellaDeArbol(root) == antes)
    }
}
