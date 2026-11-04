import Foundation
import Testing
import TLSCore
@testable import TLSImport

@Suite("Ordenar lo que tienes · calidad de los datos y actualizar la copia desde la real", .serialized)
struct CalidadYActualizarTests {
    @Test("Calidad: sin fecha, sin tipo, duplicados y enlaces rotos; «Crear tarea» e «Ignorar»")
    func calidad() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        try e.escribir("4 · Finanzas/Fiscal/2026/T2/Gastos/luz.pdf", datos: pdf("sin fecha"))
        try e.escribir("2 · Ventas/Contactos/sin-tipo.md", "# Sin tipo\n")
        try e.escribir("1 · Dirección/Rumbo.md", "# Rumbo\nVer [el plan](Plan%20que%20no%20existe.md) y [[Una miga]].\n")
        try e.escribir("5 · Marca/copia-a.md", "igual\n")
        try e.escribir("5 · Marca/copia-b.md", "igual\n")
        let snap = VaultSnapshot.read(root: e.raiz, excluded: [VaultPath("Expediente privado")])
        let huellas = try await e.foto()
        let informe = InformeCalidad.revisar(snapshot: snap, huellas: huellas)
        #expect(informe.avisos.contains { $0.tipo == .sinFecha && $0.ruta.raw == "4 · Finanzas/Fiscal/2026/T2/Gastos/luz.pdf" })
        #expect(!informe.avisos.contains { $0.tipo == .sinFecha && $0.ruta.name == "recibo.pdf" })   // tiene fila manual
        #expect(informe.avisos.contains { $0.tipo == .sinTipo && $0.ruta.raw == "2 · Ventas/Contactos/sin-tipo.md" })
        #expect(informe.avisos.contains { $0.tipo == .duplicado && $0.ruta.raw == "5 · Marca/copia-b.md" })
        #expect(informe.avisos.contains { $0.tipo == .enlaceRoto && $0.detalle.contains("Plan que no existe.md") || $0.detalle.contains("Plan%20que") })
        #expect(!informe.avisos.contains { $0.detalle.contains("Una miga") })   // una miga no es un fallo
        #expect(!informe.avisos.contains { $0.ruta.raw.contains("Expediente privado") })
        #expect(informe.avisos.allSatisfy { jerga($0.detalle + " " + $0.queHacer + " " + $0.tipo.titulo).isEmpty })
        #expect(!informe.resumen.isEmpty && jerga(informe.resumen).isEmpty)

        // «Crear tarea»: un plan normal de tarea, en su área.
        let aviso = try #require(informe.avisos.first { $0.tipo == .sinFecha })
        let plan = try InformeCalidad.crearTarea(aviso, snapshot: snap, reloj: Reloj(hoy: EmpresaDePrueba.hoy))
        let r = try await (try await e.bus()).ejecutar(plan)
        #expect(r.hecho)
        let tarea = try #require(r.creadas.first { $0.raw.contains("/Tareas/t-") })
        #expect(tarea.raw.hasPrefix("4 · Finanzas/Tareas/"))
        #expect(e.texto(tarea.raw)?.contains("origen: importacion") == true)

        // «Ignorar»: se apunta fuera de la carpeta y deja de salir.
        let antes = relativeFiles(under: e.raiz)
        try InformeCalidad.ignorar(aviso, estado: e.estado)
        #expect(relativeFiles(under: e.raiz) == antes)
        let otra = InformeCalidad.revisar(snapshot: VaultSnapshot.read(root: e.raiz, excluded: [VaultPath("Expediente privado")]),
                                          huellas: huellas, ignorados: InformeCalidad.ignorados(estado: e.estado))
        #expect(!otra.avisos.contains { $0.id == aviso.id })
    }

    @Test("«Actualizar la copia desde la real» trae lo nuevo sin pisar nada y la real queda intacta (criterio F3-9)")
    func actualizarCopia() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tls-actualizar-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = try CarpetaDeFuera(base, nombre: "Empresa real")
        try real.escribir(".tls/layout.json", "{\"preset\": \"humana\"}")
        try real.escribir("Empresa.md", "# Empresa\n")
        try real.escribir("2 · Ventas/Área.md", "# Ventas\n")
        try real.escribir("Clientes/Ana López.md", "# Ana\n")
        try real.escribir("Clientes/Bruno.md", "# Bruno\n")
        try real.escribir("Notas/plan.md", "Plan v1\n")
        try real.escribir("Expediente privado/secreto.md", "contenido privado de prueba\n")
        // La copia (como la hace DemoCopier, sin lo privado).
        let asup = base.appendingPathComponent("asup")
        let copiaURL = base.appendingPathComponent("copias")
        try FileManager.default.createDirectory(at: copiaURL, withIntermediateDirectories: true)
        let (informe, entry) = try await DemoCopier(appSupport: asup).copy(
            from: real.raiz, into: copiaURL, options: CopyOptions(exclusiones: [VaultPath("Expediente privado")])) { _ in }
        let copia = URL(fileURLWithPath: informe.destino)
        let estado = base.appendingPathComponent("estado")
        let bus = CommandBus(writer: try await VaultWriter.open(entry: entry, root: copia,
                                                                options: .init(stateDirectory: estado, appSupport: asup)))
        // En la copia se ordenó «Clientes» (con su mapa) y se cambió una nota.
        let mapa = MapaImportacion(filas: [
            FilaMapa(origen: "Carpeta/Clientes/Ana López.md", destino: "2 · Ventas/Contactos/ana-lopez.md", accion: .moverYRenombrar, motivo: "x"),
            FilaMapa(origen: "Carpeta/Clientes/Bruno.md", destino: "2 · Ventas/Contactos/bruno.md", accion: .moverYRenombrar, motivo: "x"),
        ])
        _ = try await bus.ejecutar(WritePlan(autor: .persona("Manu"), descripcion: "ordenar", ops: [
            .move(VaultPath("Clientes/Ana López.md"), to: VaultPath("2 · Ventas/Contactos/ana-lopez.md")),
            .move(VaultPath("Clientes/Bruno.md"), to: VaultPath("2 · Ventas/Contactos/bruno.md")),
        ]))
        _ = try await bus.ejecutar(.anadirLinea(VaultPath("Notas/plan.md"), linea: "Cambio en la copia."), autor: .persona("Manu"))
        // Mientras, en la real: algo nuevo junto a los clientes, algo nuevo suelto y un cambio.
        try real.escribir("Clientes/Carla.md", "# Carla\n")
        try real.escribir("Facturas/nueva.pdf", datos: pdf("nueva"))
        try real.escribir("Notas/plan.md", "Plan v2 en la real\n")
        try real.escribir("Expediente privado/otro.md", "más privado\n")
        let fs = RecordingFileSystem()
        let realAntes = try await Inventory.make(of: real.raiz, exclusiones: [VaultPath("Expediente privado")], completo: true)

        let a = try await ActualizacionDesdeLaReal.preparar(real: real.raiz, copia: copia, exclusiones: [VaultPath("Expediente privado")],
                                                           mapas: [mapa], fileSystem: fs)
        #expect(Set(a.nuevos.map(\.destino.raw)) == ["2 · Ventas/Contactos/Carla.md", "Facturas/nueva.pdf"])
        #expect(a.distintos.map(\.raw) == ["Notas/plan.md"])
        #expect(a.resumen == "Traer 2 nuevos · 1 distinto no se toca · No se borra nada")
        #expect(!fs.log.withLock { $0.listed }.contains { $0.contains("Expediente privado") })
        #expect(fs.log.withLock { $0.unprotectedCalls }.isEmpty)
        let res = try await a.aplicar(con: bus, fileSystem: fs)
        #expect(res.realIntacta && res.comprobados == 2 && res.diferencias.isEmpty)
        #expect(FileManager.default.fileExists(atPath: copia.appendingPathComponent("2 · Ventas/Contactos/Carla.md").path))
        #expect(try String(contentsOf: copia.appendingPathComponent("Notas/plan.md"), encoding: .utf8).contains("Cambio en la copia."))
        #expect(!FileManager.default.fileExists(atPath: copia.appendingPathComponent("Expediente privado").path))
        let realDespues = try await Inventory.make(of: real.raiz, exclusiones: [VaultPath("Expediente privado")], completo: true)
        #expect(realDespues.hashArbol == realAntes.hashArbol)
        // Otra vez: ya no hay nada nuevo.
        let b = try await ActualizacionDesdeLaReal.preparar(real: real.raiz, copia: copia, exclusiones: [VaultPath("Expediente privado")],
                                                           mapas: [mapa])
        #expect(b.nuevos.isEmpty && b.plan == nil)
        // Nunca la real sobre sí misma.
        await #expect(throws: ImportError.self) {
            try await ActualizacionDesdeLaReal.preparar(real: real.raiz, copia: real.raiz, exclusiones: [VaultPath("Expediente privado")])
        }
    }
}
