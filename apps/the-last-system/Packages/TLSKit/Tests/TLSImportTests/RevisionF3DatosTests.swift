import Foundation
import Testing
import TLSCore
@testable import TLSImport

// Revisión adversarial de datos y privacidad de F3 (importador, «Actualizar la copia» y Multica). Cada prueba
// reproducía un fallo encontrado; el corrector final los arregló y quitó los envoltorios de fallo conocido: ahora
// comprueban que no vuelven. Todo en temporales propios, con nombres neutros («Otro expediente», «Expediente privado»)
// y sin lanzar Claude ni Multica de verdad.

@Suite("Revisión F3 · datos y privacidad del importador", .serialized)
struct RevisionF3DatosImportarTests {
    // MARK: Apoyo

    static let carpetaPrivadaDeLaZona = "Otro expediente"

    /// Ruta (relativa a la carpeta) a la que lleva un enlace Markdown relativo escrito en `nota`, o `nil`.
    static func destinoDelEnlace(_ texto: String, nota: VaultPath) -> VaultPath? {
        guard let r = texto.range(of: #"\]\(([^)]+)\)"#, options: .regularExpression) else { return nil }
        let destino = String(texto[r].dropFirst(2).dropLast())
        return nota.resolvingRelative(destino)
    }

    // MARK: Fechas de documentos

    @Test("Fechas (comprobado, sin fallo): la fila «manual» sigue a su documento cuando se mueve")
    func filaManualSigueAlDocumento() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        var zona = try await prepararZona(e)
        // La persona lleva el recibo (que tiene su fecha escrita a mano en el CSV) a otro trimestre.
        try zona.cambiarDestino("Carpeta/4 · Finanzas/Fiscal/2026/T1/Gastos/recibo.pdf",
                                a: VaultPath("4 · Finanzas/Fiscal/2026/T2/Gastos/recibo.pdf"))
        let vista = try await applier(e).preparar(zona)
        let r = try await applier(e).aplicar(vista, con: try await e.bus())
        #expect(r.verificacion.sinDiferencias)
        #expect(e.existe("4 · Finanzas/Fiscal/2026/T2/Gastos/recibo.pdf"))
        let filas = FechasDeDocumentos.leer(try #require(e.texto("4 · Finanzas/Fechas de documentos.csv")))
        #expect(filas.contains { $0.ruta == "Fiscal/2026/T2/Gastos/recibo.pdf" && $0.fecha == "2026-01-10" && $0.esManual },
                "\(filas)")
        #expect(!filas.contains { $0.ruta == "Fiscal/2026/T1/Gastos/recibo.pdf" }, "Queda una fila que no apunta a nada")
    }

    // MARK: Lo privado de la zona

    @Test("Privado en la zona: su gemelo visible no se aparta a «Duplicados» y la ruta privada no sale en el mapa")
    func gemeloDeLoPrivado() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let datos = pdf("Contrato marco de prueba")
        let privado = try e.escribir("\(Self.carpetaPrivadaDeLaZona)/Contrato marco.pdf", datos: datos)
        try e.escribir("Contratos/Contrato marco.pdf", datos: datos)
        // El privado es el más antiguo: por eso es «el que se queda» del grupo de idénticos.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_500_000_000)],
                                              ofItemAtPath: privado.path)
        var zona = try await prepararZona(e)
        zona.marcarPrivado(bloque: "Carpeta/\(Self.carpetaPrivadaDeLaZona)")
        #expect(!zona.visibles.contains { $0.clave.hasPrefix("Carpeta/\(Self.carpetaPrivadaDeLaZona)/") })
        let vista = try await applier(e).preparar(zona)
        let visible = try #require(vista.movimientos.first { $0.clave == "Carpeta/Contratos/Contrato marco.pdf" })
        #expect(visible.accion != .duplicado, "El visible se retira a Archivo/Duplicados por un gemelo privado")
        #expect(!vista.mapa.csv.contains(Self.carpetaPrivadaDeLaZona), "La ruta privada sale en el mapa")
        #expect(!visible.conflicto.contains(Self.carpetaPrivadaDeLaZona))
        #expect(!zona.duplicados.contains { g in g.claves.contains { $0.contains(Self.carpetaPrivadaDeLaZona) } })
    }

    @Test("Privado en la zona: «Aplicar» no le reescribe los enlaces por dentro (lo privado no se toca) y lo declara")
    func enlacesDentroDeLoPrivado() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        try e.escribir("\(Self.carpetaPrivadaDeLaZona)/Notas.md",
                       "# Notas\nHablar con [Ana](../Clientes/Ana%20L%C3%B3pez.md).\n")
        var zona = try await prepararZona(e)
        zona.marcarPrivado(bloque: "Carpeta/\(Self.carpetaPrivadaDeLaZona)")
        let vista = try await applier(e).preparar(zona)
        let tocanLoPrivado = vista.plan.ops.filter { $0.path.raw.hasPrefix(Self.carpetaPrivadaDeLaZona + "/") }
        #expect(tocanLoPrivado.isEmpty, "\(tocanLoPrivado.map(\.resumen))")
        // Lo que sí hace: declararlo privado en los ajustes (en el mismo plan) y decirlo en la vista previa.
        #expect(vista.privadas == [VaultPath(Self.carpetaPrivadaDeLaZona)])
        #expect(vista.plan.ops.contains { $0.path.raw == ".tls/config.yaml" })
    }

    // MARK: Enlaces

    @Test("Enlaces: una nota de fuera que enlaza a un duplicado que no se trae lleva al que ya estaba en la carpeta")
    func enlaceRotoAlDuplicado() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let factura = try Data(contentsOf: e.url("Facturas/Factura proveedor luz.pdf"))
        let fuera = try CarpetaDeFuera(e.base, nombre: "Drive")
        try fuera.escribir("Docs/Luz.pdf", datos: factura)   // la misma factura que ya está en la carpeta
        try fuera.escribir("Contactos/Carla Gil.md", "# Carla Gil\nSu [factura](../Docs/Luz.pdf).\n")
        let zona = try await prepararZona(e, externas: [FuenteImportacion(alias: "Drive", raiz: fuera.raiz, clase: .externa)])
        let vista = try await applier(e).preparar(zona)
        let luz = try #require(vista.movimientos.first { $0.clave == "Drive/Docs/Luz.pdf" })
        #expect(luz.accion == .noMigrar)   // no se trae: ya está en la carpeta
        let r = try await applier(e).aplicar(vista, con: try await e.bus())
        #expect(r.verificacion.sinDiferencias)
        let nota = VaultPath("2 · Ventas/Contactos/carla-gil.md")
        let carla = try #require(e.texto(nota.raw))
        let destino = Self.destinoDelEnlace(carla, nota: nota)
        let resuelve = destino.map { e.existe($0.raw) } ?? false
        #expect(resuelve, "Enlace: \(destino?.raw ?? "—")")
        #expect(vista.enlacesEnRiesgo.isEmpty)
    }

    // MARK: Inventario sobre una copia hecha por la app

    @Test("Ordenar sobre una copia de verdad: lo que se dejó fuera de la copia no está y el inventario no se niega")
    func inventarioDeUnaCopiaConPrivado() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let privada = VaultPath("4 · Finanzas/Trámites/Privada X")
        let (_, entry) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [privada])) { _ in }
        let copia = URL(fileURLWithPath: entry.ruta, isDirectory: true)
        // La copia guarda lo que se dejó fuera (la carpeta privada y «Archivo»), pero esas rutas no existen en ella.
        #expect(entry.exclusionesCopia.contains(privada.raw))
        #expect(!FileManager.default.fileExists(atPath: privada.url(in: copia).path))
        // Igual que `ModeloOrdenar.fuenteDeLaEmpresa`.
        let fuente = FuenteImportacion.carpetaDeLaEmpresa(copia, privado: VaultLayout.load(root: copia).layout.privado,
                                                          exclusiones: entry.exclusionesCopia.map { VaultPath($0) })
        let inv = try await InventarioImportacion.hacer([fuente], opciones: .init(hoy: EmpresaDePrueba.hoy))
        #expect(!inv.elementos.isEmpty)
        #expect(!inv.elementos.contains { $0.ruta.raw.hasPrefix(privada.raw) })
        // Sin nada privado pasa lo mismo: la copia apunta «Archivo» (no se copió) y en la copia no está.
        let (_, sinPrivado) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas 2"), options: CopyOptions(exclusiones: [])) { _ in }
        #expect(sinPrivado.exclusionesCopia == ["Archivo"])
        let copia2 = URL(fileURLWithPath: sinPrivado.ruta, isDirectory: true)
        let fuente2 = FuenteImportacion.carpetaDeLaEmpresa(copia2, privado: VaultLayout.load(root: copia2).layout.privado,
                                                           exclusiones: sinPrivado.exclusionesCopia.map { VaultPath($0) })
        let inv2 = try await InventarioImportacion.hacer([fuente2], opciones: .init(hoy: EmpresaDePrueba.hoy))
        #expect(!inv2.elementos.isEmpty)
    }
}

@Suite("Revisión F3 · «Actualizar la copia desde la real»", .serialized)
struct RevisionF3DatosActualizarTests {
    /// Una «real» y su copia (como la deja `DemoCopier`, sin `.tls/` de la real).
    struct Par {
        let t: TempTree
        let real: URL
        let copia: URL
        init() throws {
            t = try TempTree()
            real = t.dir("Real")
            copia = t.dir("Copia")
            for (rel, texto) in [("Empresa.md", "# Empresa de prueba\n"),
                                 ("Clientes/Ana López.md", "---\ntipo: persona\n---\n# Ana López\n"),
                                 ("Notas/Ideas.md", "Ideas.\n")] {
                try t.write(rel, texto, in: "Real")
                try t.write(rel, texto, in: "Copia")
            }
            try t.write(".tls/layout.json", "{\"preset\": \"humana\"}", in: "Copia")
        }
        func limpiar() { t.remove() }
    }

    @Test("Un cambio en la real de un fichero que la copia ya ordenó sale como distinto (no se pierde en silencio)")
    func cambioEnLaRealDeLoOrdenado() async throws {
        let p = try Par()
        defer { p.limpiar() }
        // En la copia, «Ordenar» llevó a Ana a su sitio y le añadió propiedades (así lo apunta el mapa).
        let movida = VaultPath("2 · Ventas/Contactos/ana-lopez.md").url(in: p.copia)
        try FileManager.default.createDirectory(at: movida.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: VaultPath("Clientes/Ana López.md").url(in: p.copia), to: movida)
        let mapa = MapaImportacion(filas: [FilaMapa(origen: "Carpeta/Clientes/Ana López.md",
                                                    destino: "2 · Ventas/Contactos/ana-lopez.md", accion: .mover,
                                                    motivo: "Parece una persona")])
        // Después, en la real, la persona apunta algo nuevo en Ana.
        try p.t.write("Clientes/Ana López.md", "---\ntipo: persona\n---\n# Ana López\nTeléfono nuevo: 600 000 000.\n", in: "Real")
        let a = try await ActualizacionDesdeLaReal.preparar(real: p.real, copia: p.copia, exclusiones: [], mapas: [mapa])
        let visto = a.nuevos.contains { $0.origen.raw == "Clientes/Ana López.md" }
            || a.distintos.contains { $0.raw == "Clientes/Ana López.md" }
        #expect(visto, "\(a.resumen)")
        #expect(a.distintos.contains { $0.raw == "Clientes/Ana López.md" })
        // Sin cambios en la real (con la huella del mapa, o sin ella y solo con las propiedades que añadió ordenar), «ya está».
        let original = try #require(FileManager.default.contents(atPath: VaultPath("Notas/Ideas.md").url(in: p.real).path))
        let conHuella = MapaImportacion(filas: [FilaMapa(origen: "Carpeta/Notas/Ideas.md", destino: "Notas/Ideas.md", accion: .mantener,
                                                         motivo: "", sha256: ContentHash.of(original))])
        let b = try await ActualizacionDesdeLaReal.preparar(real: p.real, copia: p.copia, exclusiones: [], mapas: [mapa, conHuella])
        #expect(!b.distintos.contains { $0.raw == "Notas/Ideas.md" })
        try p.t.write("Clientes/Ana López.md", "---\ntipo: persona\n---\n# Ana López\n", in: "Real")
        try "---\ntipo: persona\ntls_type: contact\n---\n# Ana López\n".write(to: movida, atomically: true, encoding: .utf8)
        let c = try await ActualizacionDesdeLaReal.preparar(real: p.real, copia: p.copia, exclusiones: [], mapas: [mapa])
        #expect(c.distintos.isEmpty, "\(c.distintos)")
    }

    @Test("Un fichero nuevo que no se puede crear sale aparte, con su motivo, y no cuenta como traído")
    func nuevoDescartadoEnSilencio() async throws {
        let p = try Par()
        defer { p.limpiar() }
        try p.t.write("Notas/Nueva.md", "# Nueva\n", in: "Real")
        try p.t.write("Notas/Con propiedades rotas.md", "---\nclave: [sin cerrar\n---\n# Rota\n", in: "Real")
        let a = try await ActualizacionDesdeLaReal.preparar(real: p.real, copia: p.copia, exclusiones: [])
        #expect(a.nuevos.count == 1)
        #expect(a.noSeTraen.map(\.ruta.raw) == ["Notas/Con propiedades rotas.md"])
        #expect(a.resumen.hasPrefix("Traer 1 nuevo · 1 no se puede traer"), "\(a.resumen)")
        let writer = try await VaultWriter.open(
            entry: VaultEntry(nombre: "Copia", ruta: p.copia.path, bookmark: nil, clase: .copia, escritura: .permitida),
            root: p.copia, options: .init(stateDirectory: p.t.dir("estado"), appSupport: p.t.dir("asup"), app: "pruebas"))
        let r = try await a.aplicar(con: CommandBus(writer: writer))
        await writer.close()
        #expect(r.realIntacta)
        #expect(r.comprobados + r.diferencias.count == a.nuevos.count,
                "comprobados \(r.comprobados), diferencias \(r.diferencias.count), anunciados \(a.nuevos.count)")
        #expect(r.diferencias.isEmpty)
    }

    @Test("«Tu carpeta real no ha cambiado» (comprobado, sin fallo) también ve un `.tls/escritor.json` nuevo en la real")
    func realIntactaMiraLosAjustes() async throws {
        let p = try Par()
        defer { p.limpiar() }
        try p.t.write("Notas/Nueva.md", "# Nueva\n", in: "Real")
        let a = try await ActualizacionDesdeLaReal.preparar(real: p.real, copia: p.copia, exclusiones: [])
        // Algo escribe en los ajustes de la real entre «preparar» y «aplicar» (lo que nunca debe pasar).
        try p.t.write(".tls/escritor.json", "{\"vault_id\": \"x\"}", in: "Real")
        let writer = try await VaultWriter.open(
            entry: VaultEntry(nombre: "Copia", ruta: p.copia.path, bookmark: nil, clase: .copia, escritura: .permitida),
            root: p.copia, options: .init(stateDirectory: p.t.dir("estado"), appSupport: p.t.dir("asup"), app: "pruebas"))
        let r = try await a.aplicar(con: CommandBus(writer: writer))
        await writer.close()
        #expect(!r.realIntacta)
    }
}

@Suite("Revisión F3 · Multica")
struct RevisionF3DatosMulticaTests {
    static func snapshotVacio() throws -> (VaultSnapshot, TempTree) {
        let t = try TempTree()
        try t.write(".tls/layout.json", "{\"preset\": \"humana\"}", in: "Empresa")
        try t.write("Empresa.md", "# Empresa\n", in: "Empresa")
        return (VaultSnapshot.read(root: t.dir("Empresa")), t)
    }

    @Test("Tareas de salud corrientes se reconocen como personales y salen desmarcadas")
    func personalesSinMarcar() throws {
        let (foto, t) = try Self.snapshotVacio()
        defer { t.remove() }
        let titulos = ["Recoger el análisis de sangre", "Pedir cita en la clínica", "Ponerme la vacuna de la gripe",
                       "Revisión con el ginecólogo", "Operación de rodilla: preparar el preoperatorio"]
        let tareas = titulos.enumerated().map { i, s in
            TareaMultica(identificador: "MANU-\(i + 10)", titulo: s, estado: "Todo", categoria: .todo)
        }
        let previa = ImportadorMultica(snapshot: foto, reloj: Reloj(hoy: EmpresaDePrueba.hoy)).previa(tareas)
        let marcadas = previa.candidatas.filter { !$0.parecePersonal && $0.marcada }.map(\.tarea.titulo)
        #expect(marcadas.isEmpty, "\(marcadas)")
        // Y lo de trabajo con palabras parecidas no se aparta.
        for t in ["Revisar el catálogo de servicios", "Preparar el diálogo con el gestor", "Instalar la nueva tecnología"] {
            #expect(ClasificadorPersonal.motivo(t) == nil, "\(t)")
        }
    }

    @Test("Una tarea importada que la persona retira a Archivo no vuelve a salir marcada en la siguiente importación")
    func retiradaVuelveAImportarse() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let reloj = Reloj(hoy: EmpresaDePrueba.hoy)
        let tareas = [TareaMultica(identificador: "MANU-30", titulo: "Preparar la propuesta del cliente nuevo",
                                   estado: "Todo", categoria: .todo)]
        let primera = ImportadorMultica(snapshot: VaultSnapshot.read(root: e.raiz), reloj: reloj)
        let plan = try primera.plan(primera.previa(tareas), autor: .persona("Manu"))
        let bus = try await e.bus()
        let r = try await ImportadorMultica.aplicar(plan, con: bus)
        let ficha = try #require(r.creadas.first)
        // La persona decide que no le sirve y la retira (va a Archivo; no se borra).
        _ = try await bus.ejecutar(WritePlan(autor: .persona("Manu"), descripcion: "Retirar", ops: [.retire(ficha)]))
        let otra = ImportadorMultica(snapshot: VaultSnapshot.read(root: e.raiz), reloj: reloj).previa(tareas)
        let c = try #require(otra.candidatas.first)
        #expect(!c.marcada && c.enArchivo != nil, "\(otra.resumen)")
        #expect(c.nota?.contains("Archivo") == true)
        #expect(throws: ErrorImportacionMultica.nadaMarcado) { try ImportadorMultica(snapshot: VaultSnapshot.read(root: e.raiz), reloj: reloj).plan(otra, autor: .persona("Manu")) }
    }

    @Test("Sin `status_category`, «Hecho», «Cancelada» o «Won't do» no cuentan como abiertas; lo desconocido sale desmarcado")
    func estadosSinCategoria() throws {
        let json = #"{"issues":[{"identifier":"MANU-20","title":"Enviar la propuesta","status":"Hecho"},{"identifier":"MANU-21","title":"Llamar al banco","status":"Cancelada"},{"identifier":"MANU-29","title":"Revisar contrato","status":"Won't do"}]}"#
        let (tareas, _) = try LecturaMultica.tareas(Data(json.utf8))
        #expect(tareas.count == 3)
        let abiertas = tareas.filter(\.abierta).map(\.identificador)
        #expect(abiertas.isEmpty, "\(abiertas)")
        let rara = TareaMultica(identificador: "MANU-23", titulo: "Algo", estado: "Congelada")
        #expect(rara.abierta && rara.estadoDesconocido)
        let (foto, t) = try Self.snapshotVacio()
        defer { t.remove() }
        let previa = ImportadorMultica(snapshot: foto, reloj: Reloj(hoy: EmpresaDePrueba.hoy)).previa([rara])
        #expect(previa.candidatas.first?.marcada == false)
        #expect(previa.candidatas.first?.nota?.contains("Congelada") == true)
    }
}
