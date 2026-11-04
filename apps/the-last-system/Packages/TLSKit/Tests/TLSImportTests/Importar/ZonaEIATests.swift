import Foundation
import Testing
import TLSCore
@testable import TLSImport

@Suite("Ordenar lo que tienes · zona de preparación, mapa e IA", .serialized)
struct ZonaEIATests {
    @Test("Duplicados por SHA-256 y por nombre parecido")
    func duplicados() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        try e.escribir("Notas/Presupuesto.md", "Versión A\n")
        try e.escribir("Notas/Presupuesto copia.md", "Versión B, distinta\n")
        var zona = try await prepararZona(e)
        let exactos = try #require(zona.duplicados.first { $0.clase == .identicos })
        #expect(Set(exactos.claves) == ["Carpeta/Notas/Ideas sueltas.md", "Carpeta/Notas/Ideas sueltas (1).md"])
        #expect(exactos.seQueda == "Carpeta/Notas/Ideas sueltas.md")
        let parecidos = try #require(zona.duplicados.first { $0.clase == .nombreParecido })
        #expect(parecidos.seQueda == nil)
        // Con contenido distinto no se aparta nada hasta que la persona elige.
        #expect(zona.decisiones().filter { $0.accion == .duplicado }.count == 1)
        zona.quedarseCon("Carpeta/Notas/Presupuesto.md", enGrupo: parecidos.id)
        let d = try #require(zona.decisiones().first { $0.elemento.clave == "Carpeta/Notas/Presupuesto copia.md" })
        #expect(d.accion == .duplicado && d.destino?.raw == "Archivo/Duplicados/Notas/Presupuesto copia.md")
    }

    @Test("«Todo / lo activo / nada» por herramienta, con fecha de corte; privado y dejar fuera")
    func alcanceYAjustes() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        var zona = try await prepararZona(e)
        zona.fijarAlcance(.carpetas, .loActivo(desde: LocalDate(year: 2024, month: 1, day: 1)!))
        var d = Dictionary(uniqueKeysWithValues: zona.decisiones().map { ($0.elemento.clave, $0) })
        #expect(d["Carpeta/Viejo/Acta reunión 2019-05-02.md"]?.accion == .archivar)
        #expect(d["Carpeta/Viejo/Acta reunión 2019-05-02.md"]?.destino?.raw == "Archivo/Importación 2026-10-19/Viejo/Acta reunión 2019-05-02.md")
        #expect(d["Carpeta/Facturas/Factura 2025-03-15 Proveedor.pdf"]?.accion == .mover)
        zona.fijarAlcance(.carpetas, .nada)
        d = Dictionary(uniqueKeysWithValues: zona.decisiones().map { ($0.elemento.clave, $0) })
        #expect(d["Carpeta/Facturas/Factura 2025-03-15 Proveedor.pdf"]?.accion == .mantener)
        zona.fijarAlcance(.carpetas, .todo)
        zona.dejarFuera(bloque: "Carpeta/Fotos")
        zona.marcarPrivado(bloque: "Carpeta/Notas")
        try zona.cambiarDestino("Carpeta/Facturas/Factura proveedor luz.pdf", a: VaultPath("4 · Finanzas/Fiscal/2025/T1/Gastos/Luz.pdf"))
        d = Dictionary(uniqueKeysWithValues: zona.decisiones().map { ($0.elemento.clave, $0) })
        #expect(d["Carpeta/Fotos/logo.png"]?.accion == .fuera)
        #expect(d["Carpeta/Notas/Ideas sueltas.md"] == nil)   // privado: ya no se ve
        #expect(!zona.bloques.contains { $0.id == "Carpeta/Notas" })
        #expect(!zona.mapa().csv.contains("Ideas sueltas"))
        #expect(!zona.candidatosIA().contains { $0.clave.hasPrefix("Carpeta/Notas/") })
        #expect(d["Carpeta/Facturas/Factura proveedor luz.pdf"]?.destino?.raw == "4 · Finanzas/Fiscal/2025/T1/Gastos/Luz.pdf")
        #expect(d["Carpeta/Facturas/Factura proveedor luz.pdf"]?.accion == .moverYRenombrar)
        #expect(throws: ImportError.self) { try zona.cambiarDestino("Carpeta/Fotos/logo.png", a: VaultPath(".tls/x.png")) }
    }

    @Test("El mapa tiene el formato de mapa-migracion.csv y se puede revisar y volver a cargar")
    func mapa() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        var zona = try await prepararZona(e)
        let mapa = zona.mapa()
        #expect(mapa.csv.hasPrefix("origen,destino,accion,motivo,conflicto,sha256\n"))
        let leido = try MapaImportacion(csv: mapa.csv)
        #expect(leido == mapa)
        // Revisado a mano: otro destino y algo que se deja fuera.
        var filas = leido.filas
        let i = try #require(filas.firstIndex { $0.origen == "Carpeta/Fotos/logo.png" })
        filas[i].destino = "5 · Marca/Recursos/Logo/logo.png"
        let j = try #require(filas.firstIndex { $0.origen == "Carpeta/Notas/Ideas sueltas.md" })
        filas[j].accion = .fuera
        try zona.aplicar(mapa: try MapaImportacion(csv: MapaImportacion(filas: filas).csv))
        let d = Dictionary(uniqueKeysWithValues: zona.decisiones().map { ($0.elemento.clave, $0) })
        #expect(d["Carpeta/Fotos/logo.png"]?.destino?.raw == "5 · Marca/Recursos/Logo/logo.png")
        #expect(d["Carpeta/Notas/Ideas sueltas.md"]?.accion == .fuera)
        // Guardado fuera de la carpeta de la empresa.
        let url = try mapa.guardar(en: e.estado, nombre: "2026-10-19 prueba")
        #expect(url.path.hasPrefix(e.estado.path))
        #expect(MapaImportacion.guardados(en: e.estado) == [mapa])
        #expect(throws: ImportError.self) { try MapaImportacion(csv: "origen,destino\nx,y\n") }
    }

    @Test("IA: solo lo dudoso, con permiso, nunca lo privado; argumentos de Claude y esquema JSON")
    func ia() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        var zona = try await prepararZona(e)
        zona.marcarPrivado("Carpeta/Fotos/logo.png")
        let candidatos = zona.candidatosIA()
        #expect(!candidatos.isEmpty)
        #expect(candidatos.allSatisfy { (zona.propuestas[$0.clave]?.confianza ?? 1) < AIClassifier.umbral })
        #expect(!candidatos.contains { $0.clave.contains("logo.png") || $0.clave.contains("Expediente privado") })
        let ideas = try #require(candidatos.firstIndex { $0.clave == "Carpeta/Notas/Ideas sueltas.md" })
        let respuesta = #"{"type":"result","is_error":false,"structured_output":{"elementos":[{"id":\#(ideas + 1),"coleccion":"direccion.recursos","confianza":0.8,"motivo":"Son ideas para el plan de la empresa"},{"id":999,"coleccion":"inventada","confianza":0.9,"motivo":"x"}]}}"#
        let claude = try ClaudeFalso(base: e.base, respuesta: respuesta)

        // Sin permiso, nada.
        let sin = await AIClassifier(ejecutor: claude, consentimiento: false).clasificar(zona)
        #expect(!sin.usada && sin.propuestas.isEmpty && claude.entradas.isEmpty)

        let r = await AIClassifier(ejecutor: claude, consentimiento: true, tamanoLote: 100).clasificar(zona)
        #expect(r.usada && r.enviados == candidatos.count && r.avisos.isEmpty)
        #expect(claude.argumentos.contains("--json-schema") && claude.argumentos.contains("--no-session-persistence"))
        #expect(!claude.entradas.contains("logo.png") && !claude.entradas.contains("Expediente privado"))
        #expect(!claude.entradas.contains("contenido privado"))
        let p = try #require(r.propuestas["Carpeta/Notas/Ideas sueltas.md"])
        #expect(p.origen == .ia && p.destino?.raw == "1 · Dirección/Recursos/Ideas sueltas.md")
        #expect(p.motivo == "Según Claude: Son ideas para el plan de la empresa")
        #expect(r.propuestas.count == 1)   // la colección inventada se descarta
        zona.incorporar(r.propuestas)
        #expect(zona.propuestas["Carpeta/Notas/Ideas sueltas.md"]?.origen == .ia)
        // El esquema solo deja elegir colecciones del catálogo.
        let esquema = try JSONSerialization.jsonObject(with: Data(AIClassifier.esquema.utf8)) as? [String: Any]
        #expect(esquema != nil)
        #expect(ColeccionV2.catalogo.allSatisfy { AIClassifier.esquema.contains("\"\($0.clave)\"") })
    }

    @Test("IA: si Claude falla o no está, se sigue con las reglas")
    func iaFalla() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let zona = try await prepararZona(e)
        let claude = try ClaudeFalso(base: e.base, respuesta: "", falla: true)
        let r = await AIClassifier(ejecutor: claude, consentimiento: true).clasificar(zona)
        #expect(r.propuestas.isEmpty && !r.avisos.isEmpty)
        #expect(r.avisos.allSatisfy { $0.contains("Sigo con las reglas") && jerga($0).isEmpty })
        let sinClaude = await AIClassifier(ejecutor: nil, consentimiento: true).clasificar(zona)
        #expect(!sinClaude.usada)
    }
}
