import Foundation
import Testing
import TLSCore
import TLSImport
@testable import TLSUI

// Revisión adversarial de datos y privacidad de F3 (pantallas de ordenar). Lo que fallaba ya está arreglado (corrector
// final): las pruebas comprueban que no vuelve. Las de «Ordenar» de la integración copian la carpeta con `FileManager`
// (la carpeta privada viaja con la copia); aquí la copia la hace `DemoCopier`, como en la app: lo privado y «Archivo»
// no están en ella.

@Suite("Revisión F3 · ordenar sobre una copia hecha por la app", .serialized)
@MainActor
struct RevisionF3DatosOrdenarTests {
    /// Copia de la fixture G3 hecha como la hace la app («Privado» fuera; «Archivo» fuera por defecto).
    @MainActor
    struct CopiaDeVerdad {
        let base: URL
        let entry: VaultEntry
        let raiz: URL
        let asup: URL

        init(privadas: [VaultPath]) async throws {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-revision-f3-\(UUID().uuidString)", isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath()
            asup = base.appendingPathComponent("asup", isDirectory: true)
            let empresas = base.appendingPathComponent("Empresas", isDirectory: true)
            try FileManager.default.createDirectory(at: asup, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: empresas, withIntermediateDirectories: true)
            // La «real» es una copia propia de la fixture (nunca se toca la del repositorio).
            let real = base.appendingPathComponent("Real", isDirectory: true)
            try FileManager.default.copyItem(at: EmpresaOrdenar.fixtureG3, to: real)
            let (_, e) = try await DemoCopier(appSupport: asup)
                .copy(from: real, into: empresas, options: CopyOptions(exclusiones: privadas)) { _ in }
            entry = e
            raiz = URL(fileURLWithPath: e.ruta, isDirectory: true)
        }

        var acceso: AccesoEmpresa {
            AccesoEmpresa(entry: entry, raiz: raiz, appSupport: asup,
                          estado: asup.appendingPathComponent(entry.id.uuidString.lowercased(), isDirectory: true), persona: "Manu")
        }

        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    @Test("Copia de G3 con «Privado» fuera: «Completar las fichas» arranca (lo dejado fuera no se exige en la copia)")
    func completarSobreCopiaDeVerdad() async throws {
        let c = try await CopiaDeVerdad(privadas: [VaultPath("Privado")])
        defer { c.limpiar() }
        #expect(c.entry.exclusionesCopia.contains("Privado"))
        #expect(!FileManager.default.fileExists(atPath: c.raiz.appendingPathComponent("Privado").path))
        let m = ModeloOrdenar(acceso: c.acceso, ruta: .completar, hoy: EmpresaOrdenar.hoy)
        m.ocr = nil
        await m.arrancar()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(m.inventario != nil)
        // Y se puede aplicar: la vista previa se prepara y la comprobación sale sin diferencias.
        await m.prepararVista()
        #expect(m.error == nil, "\(m.error ?? "")")
        if m.vista?.hayCambios == true {
            await m.aplicar()
            #expect(m.hecho?.sinDiferencias == true, "\(m.error ?? "")")
        }
    }

    @Test("Copia de G3 sin nada privado: arranca aunque «Archivo» no se copiara")
    func ordenarSinPrivadoConArchivo() async throws {
        let c = try await CopiaDeVerdad(privadas: [])
        defer { c.limpiar() }
        #expect(c.entry.exclusionesCopia == ["Privado", "Archivo"] || c.entry.exclusionesCopia == ["Archivo"],
                "\(c.entry.exclusionesCopia)")
        let m = ModeloOrdenar(acceso: c.acceso, ruta: .completar, hoy: EmpresaOrdenar.hoy)
        m.ocr = nil
        await m.arrancar()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(m.inventario != nil)
    }

    @Test("«Calidad» en una copia de verdad: los repetidos salen (la foto de huellas no falla)")
    func calidadSinRepetidos() async throws {
        let c = try await CopiaDeVerdad(privadas: [VaultPath("Privado")])
        defer { c.limpiar() }
        let nota = Data("# Notas de la reunión\nLo mismo en dos sitios.\n".utf8)
        try nota.write(to: c.raiz.appendingPathComponent("Buzón/Reunión.md"))
        try nota.write(to: c.raiz.appendingPathComponent("1 · Dirección/Reunión copia.md"))
        let m = ModeloOrdenar(acceso: c.acceso, ruta: .completar, hoy: EmpresaOrdenar.hoy)
        m.ocr = nil
        await m.revisarCalidad()
        let calidad = try #require(m.calidad)
        #expect(calidad.cuantos(.duplicado) > 0, "\(calidad.resumen)")
    }

    @Test("«Es privado…» en Preparar: tras aplicar queda privado en la carpeta, y «Deshacer» lo quita con lo demás")
    func privadoDeLaZonaNoQuedaPrivado() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        try e.escribir("Otro expediente/Notas.md", "# Notas\nAlgo que solo es mío.\n")
        let m = e.modelo()
        await m.arrancar()
        let bloque = try #require(m.bloques.first { $0.bloque.nombre.contains("Otro expediente") }, "\(m.error ?? "")")
        m.marcarPrivado(bloque: bloque.id)
        #expect(m.privadosEnLaZona == 1)
        await m.prepararVista()
        await m.aplicar()
        #expect(m.hecho?.sinDiferencias == true, "\(m.error ?? "") \(m.hecho?.textoVerificacion ?? "") \(m.verificacion?.diferencias.map { "\($0.tipo) \($0.origen) → \($0.destino)" } ?? [])")
        #expect(e.existe("Otro expediente/Notas.md"))   // no se movió, bien
        let layout = VaultLayout.load(root: e.raiz).layout
        #expect(layout.isPrivate(VaultPath("Otro expediente/Notas.md")), "privado: \(layout.privado.map(\.raw))")
        await m.deshacer()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(!VaultLayout.load(root: e.raiz).layout.isPrivate(VaultPath("Otro expediente/Notas.md")))
    }
}
