import Foundation
import Testing
@testable import TLSCore

/// Aplica en memoria lo que haría el plan de una vista previa (enlaces, alias y movimientos).
func simular(_ preview: RefactorPreview, en foto: VaultSnapshot) -> VaultSnapshot {
    let map = MoveMap(moves: preview.traslados.map { ($0.de, $0.a) })
    var texts: [VaultPath: VaultSnapshot.Texto] = [:]
    var editados: [VaultPath: String] = [:]
    for (p, t) in foto.texts { editados[p] = t.text }
    for op in preview.plan.ops {
        switch op {
        case .editRanges(let p, let edits, _):
            var bytes = Array(editados[p]!.utf8)
            for e in edits.sorted(by: { $0.offset > $1.offset }) {
                bytes.replaceSubrange(e.offset..<(e.offset + e.length), with: Array(e.replacement.utf8))
            }
            editados[p] = String(decoding: bytes, as: UTF8.self)
        case .mergeFrontmatter(let p, let set, let unset):
            var doc = FrontmatterDocument(text: editados[p]!)
            doc.merge(set: set, unset: unset)
            editados[p] = doc.text
        default:
            break
        }
    }
    for (p, t) in editados { texts[map.map(p)] = .init(data: Data(t.utf8), text: t) }
    let files = foto.files.map(map.map).sorted()
    let dirs = foto.directories.map(map.map).sorted()
    var lower: [String: VaultPath] = [:]
    for p in files + dirs { lower[TextFolding.pathKey(p.raw)] = p }
    return VaultSnapshot(root: foto.root, layout: foto.layout, files: files, directories: dirs, dataless: [],
                         noEditables: [], texts: texts, lowerIndex: lower)
}

/// El texto con el destino de cada enlace tapado: si dos esqueletos coinciden, solo cambiaron destinos.
func esqueleto(_ text: String) -> String {
    var b = Array(text.utf8)
    for occ in LinkScanner.scan(text).reversed() {
        b.replaceSubrange(occ.targetRange, with: Array("§".utf8))
    }
    return String(decoding: b, as: UTF8.self)
}

@Suite("Renombrar: propiedades en toda la Ribera")
struct RefactorPropiedadesTests {
    func comprobar(_ preview: RefactorPreview, _ foto: VaultSnapshot, _ etiqueta: String) {
        #expect(preview.esSeguro, "\(etiqueta): \(preview.problemas.prefix(3))")
        let despues = simular(preview, en: foto)
        let map = MoveMap(moves: preview.traslados.map { ($0.de, $0.a) })
        let fallos = comprobarEnlaces(antes: foto, despues: despues, mapa: map.map)
        #expect(fallos.isEmpty, "\(etiqueta): \(fallos.prefix(3))")
        // Solo cambian destinos (salvo los alias añadidos a la nota renombrada).
        let conAlias = Set(preview.cambios.filter { $0.alias != nil }.map(\.ruta))
        for p in foto.notes where !conAlias.contains(p) {
            guard let a = foto.text(p), let d = despues.text(map.map(p)) else { continue }
            if esqueleto(a) != esqueleto(d) { Issue.record("\(etiqueta): \(p.raw) cambió algo más que destinos") }
        }
    }

    @Test func renombrarCadaNota() throws {
        let foto = VaultSnapshot.read(root: RutasRepo.ribera)
        let r = LinkRefactor(snapshot: foto)
        let notas = foto.notes
        #expect(notas.count > 100)
        for p in notas {
            let preview = try r.renombrar(p, a: p.stem + " nuevo")
            comprobar(preview, foto, p.raw)
        }
    }

    @Test func moverCadaNotaAOtraArea() throws {
        let foto = VaultSnapshot.read(root: RutasRepo.ribera)
        let r = LinkRefactor(snapshot: foto)
        for (n, p) in foto.notes.enumerated() where n % 3 == 0 {
            let destino = VaultPath("6 · Equipo/Movidas/\(n)")
            let preview = try r.mover(p, a: destino)
            comprobar(preview, foto, p.raw)
        }
    }

    @Test func renombrarCadaCarpeta() throws {
        let foto = VaultSnapshot.read(root: RutasRepo.ribera)
        let r = LinkRefactor(snapshot: foto)
        for d in foto.directories where !d.raw.hasPrefix("Archivo") && !d.raw.hasPrefix("Buzón") {
            let preview = try r.renombrar(d, a: d.name + " (2)")
            comprobar(preview, foto, d.raw)
        }
    }

    @Test func cincuentaEnlacesMezclados() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let formas = [
            "[[Ferretería Ejemplo]]", "[[Ferretería Ejemplo|la ferretería]]", "[[Ferretería Ejemplo#Notas]]",
            "![[Ferretería Ejemplo]]", "[[2 · Ventas/Empresas/Ferretería Ejemplo]]", "[[Ferretería Ejemplo.md]]",
            "[f](../2%20·%20Ventas/Empresas/Ferretería%20Ejemplo.md)", "[f](../2%20%C2%B7%20Ventas/Empresas/Ferreter%C3%ADa%20Ejemplo.md)",
            "[f](<../2 · Ventas/Empresas/Ferretería Ejemplo.md>)", "[f](../2%20·%20Ventas/Empresas/Ferretería%20Ejemplo)",
            "[f](../2%20·%20Ventas/Empresas/Ferretería%20Ejemplo.md#Notas)", "![f](../2%20·%20Ventas/Empresas/Ferretería%20Ejemplo.md)",
            "[f](./../2%20·%20Ventas/Empresas/Ferretería%20Ejemplo.md \"título\")",
        ]
        var cuerpo = "---\nempresa: \"[[Ferretería Ejemplo|Ferretería]]\"\nrelacionadas: [\"[[Ferretería Ejemplo]]\", \"[[Rumbo]]\"]\n---\n# Mezcla\n"
        for i in 0..<50 { cuerpo += "Línea \(i): \(formas[i % formas.count]) y [[Rumbo]].\n" }
        env.escribir("1 · Dirección/Mezcla.md", cuerpo)
        env.escribir("4 · Finanzas/Registros/docs.csv", "id,documento\nD1,../2 · Ventas/x\nD2,\"2 · Ventas/Empresas/Ferretería Ejemplo.md\"\n")
        let foto = env.foto()
        let preview = try LinkRefactor(snapshot: foto).renombrar(VaultPath("2 · Ventas/Empresas/Ferretería Ejemplo.md"), a: "Ferretería Sol")
        comprobar(preview, foto, "mezcla")
        #expect(preview.filasCSV == 1)
        let antes = env.texto("1 · Dirección/Mezcla.md")!
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        let despues = env.texto("1 · Dirección/Mezcla.md")!
        #expect(esqueleto(antes) == esqueleto(despues))
        #expect(despues.contains("[f](../2%20%C2%B7%20Ventas/Empresas/Ferreter%C3%ADa%20Sol.md)"))
        #expect(despues.contains("[f](<../2 · Ventas/Empresas/Ferretería Sol.md>)"))
        #expect(despues.contains("[f](../2%20·%20Ventas/Empresas/Ferretería%20Sol)"))
        #expect(despues.contains("[[Ferretería Sol.md]]"))
        #expect(despues.contains("[[2 · Ventas/Empresas/Ferretería Sol]]"))
        #expect(despues.contains("empresa: \"[[Ferretería Sol|Ferretería]]\""))
        #expect(despues.contains("[f](./../2%20·%20Ventas/Empresas/Ferretería%20Sol.md \"título\")"))
        #expect(env.texto("4 · Finanzas/Registros/docs.csv") == "id,documento\nD1,../2 · Ventas/x\nD2,\"2 · Ventas/Empresas/Ferretería Sol.md\"\n")
    }
}
