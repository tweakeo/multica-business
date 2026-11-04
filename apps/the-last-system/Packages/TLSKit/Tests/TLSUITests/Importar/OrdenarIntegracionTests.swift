import Foundation
import Testing
import TLSCore
import TLSImport
@testable import TLSUI

/// El paso 2 con la empresa abierta en una ventana (por su sesión), «Actualizar la copia desde la real» (F3-9) e
/// «Importar de Multica» desde la puesta en marcha (segunda vez: «0 nuevas»). Temporales propios; Multica falso.
@Suite("Ordenar lo que tienes · sesión, copia y Multica", .serialized)
@MainActor
struct OrdenarIntegracionTests {
    let pruebas = SesionEscrituraTests()

    @Test("Con la empresa abierta, se ordena por su sesión: la ventana se entera y «Deshacer» la deja igual")
    func porLaSesion() async throws {
        let (e, entry) = try pruebas.entorno(clase: .copia, escritura: .permitida)
        defer { e.limpiar() }
        // Un poco de desorden en la copia de Ribera.
        let suelto = e.carpeta.appendingPathComponent("Clientes sueltos/Juan Prueba.md")
        try FileManager.default.createDirectory(at: suelto.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\ntipo: persona\n---\n# Juan Prueba\n".utf8).write(to: suelto)
        let antes = try await Inventory.make(of: e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        #expect(sesion.puedeEscribir)
        let acceso = try #require(AccesoEmpresa(sesion: sesion))
        #expect(acceso.motivoSoloLectura == nil)
        let m = ModeloOrdenar(acceso: acceso, ruta: .ordenar, hoy: sesion.hoy)
        m.ocr = nil
        await m.arrancar()
        await m.prepararVista()
        let vista = try #require(m.vista, "\(m.error ?? "")")
        #expect(vista.mover >= 1)
        let revision = sesion.revision
        await m.aplicar()
        #expect(m.hecho?.sinDiferencias == true, "\(m.error ?? "")")
        #expect(!FileManager.default.fileExists(atPath: suelto.path))
        await pruebas.esperar { sesion.revision > revision }
        #expect(sesion.revision > revision, "la ventana de la empresa se entera")
        // Ninguna regla del dominio escribió nada por lo importado (modo importación).
        if let motor = DominioEmpresa.motor(de: sesion) { #expect(try motor.estado.eventos().isEmpty) }
        await m.deshacer()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(FileManager.default.fileExists(atPath: suelto.path))
        let tras = try await Inventory.make(of: e.carpeta)
        #expect(tras.hashArbol == antes.hashArbol, "\(antes.diferencias(con: tras))")
    }

    @Test("Una copia en solo lectura no se ordena: se dice por qué y no se escribe nada")
    func soloLectura() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        var entry = e.entry
        entry.escritura = .bloqueada
        let acceso = AccesoEmpresa(entry: entry, raiz: e.raiz, appSupport: e.asup, estado: e.estado)
        #expect(acceso.motivoSoloLectura == "esta copia está en solo lectura")
        let antes = try await e.fotoCompleta()
        let m = ModeloOrdenar(acceso: acceso, ruta: .ordenar, hoy: EmpresaOrdenar.hoy)
        m.ocr = nil
        await m.arrancar()
        await m.prepararVista()
        #expect(m.motivoNoAplicar == "No se puede escribir: esta copia está en solo lectura")
        await m.aplicar()
        #expect(m.hecho == nil)
        #expect(try await e.fotoCompleta().hashArbol == antes.hashArbol)
    }

    @Test("Repasar (solo mirar): se ve todo y no se escribe nada")
    func soloMirar() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        let antes = try await e.fotoCompleta()
        let m = e.modelo()
        m.soloMirar = true
        await m.arrancar()
        await m.prepararVista()
        #expect(m.vista?.hayCambios == true)
        #expect(m.motivoNoAplicar == "Repasando: aquí solo se mira")
        await m.aplicar()
        await m.revisarCalidad()
        if let a = m.calidad?.avisos.first { await m.crearTarea(a) }
        #expect(m.hecho == nil && m.planes.isEmpty)
        #expect(try await e.fotoCompleta().hashArbol == antes.hashArbol)
    }

    @Test("Actualizar la copia desde la real: trae lo nuevo sin pisar nada y la real queda igual (F3-9)")
    func actualizarCopia() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-real-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("Real", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: EmpresaOrdenar.fixtureG3, to: real)
        let e = try EmpresaOrdenar(copiaDe: real, exclusiones: ["Privado"], origenReal: real.path)
        defer { e.limpiar() }
        // En la real: un contacto nuevo, un cambio en una nota que también está en la copia y algo privado nuevo.
        try Data("# Nueva Persona\n".utf8).write(to: real.appendingPathComponent("2 · Ventas/Contactos/Nueva Persona.md"))
        let rumbo = real.appendingPathComponent("1 · Dirección/Rumbo.md")
        try (String(contentsOf: rumbo, encoding: .utf8) + "\nCambio hecho en la real.\n").write(to: rumbo, atomically: true, encoding: .utf8)
        try Data("privado de prueba\n".utf8).write(to: real.appendingPathComponent("Privado/Otro expediente.md"))
        let realAntes = try await Inventory.make(of: real, completo: true)
        let rumboCopia = e.texto("1 · Dirección/Rumbo.md")

        #expect(ModeloActualizarCopia.carpetaReal(de: e.entry, registro: VaultRegistry(directory: e.asup))?.path == real.path)
        let m = ModeloActualizarCopia(acceso: e.acceso, real: real)
        await m.leer()
        #expect(m.fase == .previa, "\(m.error ?? "")")
        let a = try #require(m.actualizacion)
        #expect(a.nuevos.map(\.destino.raw) == ["2 · Ventas/Contactos/Nueva Persona.md"])
        #expect(a.distintos.map(\.raw) == ["1 · Dirección/Rumbo.md"])
        #expect(a.resumen == "Traer 1 nuevo · 1 distinto no se toca · No se borra nada")
        #expect(!a.nuevos.contains { $0.origen.raw.hasPrefix("Privado") })
        // Leer no escribe nada en la copia.
        #expect(!e.existe("2 · Ventas/Contactos/Nueva Persona.md"))

        await m.aplicar(deshacer: nil)
        #expect(m.fase == .hecho, "\(m.error ?? "")")
        let r = try #require(m.resultado)
        #expect(r.realIntacta && r.diferencias.isEmpty && r.comprobados == 1)
        #expect(e.texto("2 · Ventas/Contactos/Nueva Persona.md") == "# Nueva Persona\n")
        #expect(e.texto("1 · Dirección/Rumbo.md") == rumboCopia, "lo distinto no se pisa")
        #expect(!e.existe("Privado/Otro expediente.md"))
        #expect(try await Inventory.make(of: real, completo: true).hashArbol == realAntes.hashArbol, "la real no cambia")
        #expect(m.planEscrito != nil)
        await m.deshacer()
        #expect(m.deshecho)
        #expect(!e.existe("2 · Ventas/Contactos/Nueva Persona.md"))
    }

    @Test("Una carpeta que no es copia no tiene real de la que traer nada")
    func sinReal() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        #expect(ModeloActualizarCopia.carpetaReal(de: e.entry, registro: VaultRegistry(directory: e.asup)) == nil)
        let m = ModeloActualizarCopia(acceso: e.acceso, real: nil)
        await m.leer()
        if case .sinOriginal(let t) = m.fase { #expect(jergaOrdenar(t).isEmpty) } else { Issue.record("Debía decir que no hay real") }
    }

    /// Multica falso con tres tareas de trabajo (ninguna personal), en memoria.
    struct MulticaDeTrabajo: EjecutorMultica {
        func ejecutar(_ orden: OrdenMultica) async throws -> Data {
            switch orden {
            case .perfiles: Data(#"["default"]"#.utf8)
            case .espacios: Data(#"{"workspaces":[{"id":"0f6c1a2e-1111-4222-8333-944455556666","name":"Empresa de prueba"}]}"#.utf8)
            case .tareas: Data("""
                {"issues":[
                {"identifier":"MANU-1","title":"Preparar propuesta para un cliente nuevo","status":"Todo","status_category":"todo","priority":"high"},
                {"identifier":"MANU-3","title":"Publicar artículo en el blog","status":"In Progress","status_category":"in_progress"},
                {"identifier":"MANU-4","title":"Cerrar el trimestre con la gestoría","status":"Backlog","status_category":"backlog"}
                ],"has_more":false}
                """.utf8)
            }
        }
    }

    @Test("Multica desde la puesta en marcha: lo personal sale desmarcado, se importa, se deshace y la segunda vez dice «0 nuevas»")
    func multicaSegundaVez() async throws {
        let e = try EmpresaOrdenar(copiaDe: EmpresaOrdenar.ribera)
        defer { e.limpiar() }
        let config = e.url(".tls/config.yaml")
        try String(contentsOf: config, encoding: .utf8).replacingOccurrences(of: "clase: demo", with: "clase: copia")
            .write(to: config, atomically: true, encoding: .utf8)
        // Con una tarea que parece personal: sale desmarcada.
        let conPersonal = ModeloImportarMultica(acceso: e.acceso, ejecutor: CapturasTutorialTests.MulticaEnMemoria())
        await conPersonal.arrancar()
        await conPersonal.leer()
        #expect(conPersonal.fase == .previa, "\(conPersonal.error ?? "")")
        #expect(conPersonal.nuevas == 5)
        #expect(conPersonal.previa?.marcadas.count == 4, "la que parece personal sale desmarcada")

        let primera = ModeloImportarMultica(acceso: e.acceso, ejecutor: MulticaDeTrabajo())
        await primera.arrancar()
        await primera.leer()
        #expect(primera.nuevas == 3)
        await primera.aplicar(deshacer: nil)
        guard case .hecho = primera.fase else { Issue.record("No terminó: \(primera.error ?? "")"); return }
        #expect(primera.planEscrito != nil)

        let segunda = ModeloImportarMultica(acceso: e.acceso, ejecutor: MulticaDeTrabajo())
        await segunda.arrancar()
        await segunda.leer()
        #expect(segunda.nuevas == 0, "la segunda vez: 0 nuevas")
        #expect(segunda.previa?.marcadas.isEmpty == true)
        #expect(segunda.previa?.resumen.contains("3 ya importadas") == true, "\(segunda.previa?.resumen ?? "")")

        // «Deshacer» desde la hoja: las fichas van al Archivo y otra lectura vuelve a ver 3 nuevas.
        await primera.deshacerImportacion()
        #expect(primera.deshecho, "\(primera.error ?? "")")
        let tercera = ModeloImportarMultica(acceso: e.acceso, ejecutor: MulticaDeTrabajo())
        await tercera.arrancar()
        await tercera.leer()
        #expect(tercera.nuevas == 3)
    }
}
