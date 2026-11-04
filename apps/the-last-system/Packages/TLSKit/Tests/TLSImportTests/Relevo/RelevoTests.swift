import Darwin
import Foundation
import Testing
import TLSCore
@testable import TLSImport

/// «Pasar a mi carpeta real» (PLAN §9 F6) SOLO con carpetas sintéticas: una «real» de prueba en una carpeta temporal y
/// su copia hecha con `DemoCopier`. Nada de iCloud, ni de la carpeta de nadie.
@Suite("F6 · Pasar a mi carpeta real (carpetas sintéticas)", .serialized)
struct RelevoTests {
    /// Escenario: real sintética, su copia y cambios en las dos.
    final class Escenario: @unchecked Sendable {
        let base: URL
        let real: URL
        let asup: URL
        let estadoReal: URL
        let estadoFork: URL
        let registro: VaultRegistry
        var realEntry: VaultEntry
        var copiaEntry: VaultEntry
        let copia: URL
        let informe: CopyReport
        let busCopia: CommandBus
        static let empresa = "Panadería Prueba"
        static let privado = "Expediente privado"
        static let antiguo = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01

        init() async throws {
            base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tls-relevo-\(UUID().uuidString)")
                .standardizedFileURL.resolvingSymlinksInPath()
            real = base.appendingPathComponent(Self.empresa, isDirectory: true)
            asup = base.appendingPathComponent("asup", isDirectory: true)
            estadoReal = base.appendingPathComponent("estado-real", isDirectory: true)
            estadoFork = base.appendingPathComponent("estado-fork", isDirectory: true)
            registro = VaultRegistry(directory: asup)
            // La real sintética, con todo «antiguo» (anterior a la copia).
            let ficheros: [(String, Data)] = [
                (".tls/layout.json", Data("{\"preset\": \"humana\"}".utf8)),
                ("Empresa.md", Data("# Panadería Prueba\n\nLas tareas viven en `Tareas.md`.\n".utf8)),
                ("AGENTS.md", Data("# Instrucciones\n\nApunta las tareas en Tareas.md.\n".utf8)),
                ("Notas/plan.md", Data("Plan v1\n".utf8)),
                ("Notas/conflicto.md", Data("Original\n".utf8)),
                ("Notas/real-cambia.md", Data("Original\n".utf8)),
                ("Notas/quitar-en-real.md", Data("Se quitará en la real\n".utf8)),
                ("Viejo/obsoleto.md", Data("Ya no sirve\n".utf8)),
                ("Clientes/ana.md", Data("# Ana\n".utf8)),
                ("Facturas/f1.pdf", Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF, 0x01])),
                ("Facturas/f2.pdf", Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFE, 0x02])),
                ("Fotos/clip.mov", Data([0x00, 0x01, 0x02, 0x03])),
                ("\(Self.privado)/secreto.md", Data("contenido privado de prueba\n".utf8)),
            ]
            for (r, d) in ficheros { try Self.escribir(real, r, d, fecha: Self.antiguo) }
            realEntry = VaultEntry(nombre: Self.empresa, ruta: real.path, bookmark: nil, clase: .real, escritura: .bloqueada)
            try registro.upsert(realEntry)
            // La copia, como la hace la app (sin lo privado).
            let copias = base.appendingPathComponent("copias", isDirectory: true)
            try FileManager.default.createDirectory(at: copias, withIntermediateDirectories: true)
            let (inf, entry) = try await DemoCopier(appSupport: asup).copy(
                from: real, into: copias, options: CopyOptions(exclusiones: [VaultPath(Self.privado)])) { _ in }
            informe = inf
            copiaEntry = entry
            copia = URL(fileURLWithPath: inf.destino)
            try registro.upsert(copiaEntry)
            busCopia = CommandBus(writer: try await VaultWriter.open(
                entry: entry, root: copia,
                options: .init(stateDirectory: base.appendingPathComponent("estado-copia"), appSupport: asup)))
        }

        static func escribir(_ raiz: URL, _ rel: String, _ d: Data, fecha: Date? = nil) throws {
            let url = raiz.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try d.write(to: url)
            if let fecha { try FileManager.default.setAttributes([.modificationDate: fecha, .creationDate: fecha], ofItemAtPath: url.path) }
        }

        /// Fecha «después de la copia».
        var despues: Date { copiaEntry.creada.addingTimeInterval(120) }

        /// Lo que se hace en la copia (con su escritor, como persona) y, después, en la real.
        func trabajar() async throws {
            let manu = Autor.persona("Manu")
            let plan = try Data(contentsOf: copia.appendingPathComponent("Notas/plan.md"))
            let conflicto = try Data(contentsOf: copia.appendingPathComponent("Notas/conflicto.md"))
            let r = try await busCopia.ejecutar(WritePlan(autor: manu, descripcion: "trabajo en la copia", ops: [
                WriteOp.replaceText(VaultPath("Notas/plan.md"), base: plan, text: "Plan v2 de la copia\n")!,
                WriteOp.replaceText(VaultPath("Notas/conflicto.md"), base: conflicto, text: "Versión de la copia\n")!,
                .create(VaultPath("Notas/nueva.md"), text: "Nueva en la copia\n"),
                .retire(VaultPath("Viejo/obsoleto.md")),
                .move(VaultPath("Clientes/ana.md"), to: VaultPath("2 · Ventas/Contactos/ana.md")),
                .retire(VaultPath("Facturas/f1.pdf"), apartado: "Viejas"),
                .create(VaultPath("Facturas/f1.pdf"), contents: Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xAA, 0xBB])),
                .retire(VaultPath("Fotos/clip.mov")),
            ]))
            #expect(r.hecho)
            // La app no escribe ahí en la copia (lo dejado fuera está excluido); alguien lo crea desde Finder.
            try Self.escribir(copia, "\(Self.privado)/intruso.md", Data("No debe pasar a la real\n".utf8))
            // En la real, después de la copia.
            try Self.escribir(real, "Notas/conflicto.md", Data("Versión de la real\n".utf8), fecha: despues)
            try Self.escribir(real, "Notas/real-cambia.md", Data("Cambió en la real\n".utf8), fecha: despues)
            try Self.escribir(real, "Notas/real-nueva.md", Data("Nueva en la real\n".utf8), fecha: despues)
            try Self.escribir(real, "\(Self.privado)/secreto.md", Data("privado cambiado en la real\n".utf8), fecha: despues)
            try Self.escribir(real, "\(Self.privado)/otro.md", Data("más privado\n".utf8), fecha: despues)
            try FileManager.default.removeItem(at: real.appendingPathComponent("Notas/quitar-en-real.md"))
        }

        /// En las pruebas, el escritor de la real se abre con la carpeta sintética: `WritePolicy` todavía bloquea la clase
        /// `real` (cambio pedido en docs/F5-CONTRATOS.md). La entrada conserva el id de la real.
        var abrir: AplicadorDeRelevo.AbrirEscritor {
            let estado = estadoReal, asup = asup
            return { entry, root in
                var e = entry
                e.clase = .copia
                e.escritura = .permitida
                return CommandBus(writer: try await VaultWriter.open(entry: e, root: root,
                                                                     options: .init(stateDirectory: estado, appSupport: asup)))
            }
        }

        var aplicador: AplicadorDeRelevo { aplicador(LocalFileSystem()) }

        func aplicador(_ fs: any FileSystemAccess) -> AplicadorDeRelevo {
            AplicadorDeRelevo(entorno: .init(appSupport: asup, registro: registro, estadoDelFork: estadoFork, app: "The Last System prueba"),
                              fileSystem: fs)
        }

        func preparar(fs: any FileSystemAccess = LocalFileSystem()) async throws -> VistaPreviaDeRelevo {
            try await PlanDeRelevo.preparar(copia: copia, copiaEntry: copiaEntry, real: real, realEntry: realEntry,
                                            hoy: LocalDate(year: 2026, month: 10, day: 24)!,
                                            informeCopia: AplicadorDeRelevo.informeDeLaCopia(appSupport: asup, id: copiaEntry.id),
                                            fileSystem: fs)
        }

        /// Inventario completo de la real (con lo oculto, `escritor.json` y `Archivo/`; sin lo privado).
        func inventarioCompleto() async throws -> Inventory {
            try await Inventory.make(of: real, exclusiones: [VaultPath(Self.privado)], completo: true)
        }

        /// Huella de la real tal como la compara «Deshacer» (sin `Archivo/` ni lo privado).
        func huella() async throws -> String {
            try await Inventory.make(of: real, exclusiones: [VaultPath(Self.privado)]).hashArbol
        }

        func privadoSHA() throws -> [String] {
            try ["secreto.md", "otro.md"].map {
                ContentHash.of(try Data(contentsOf: real.appendingPathComponent(Self.privado).appendingPathComponent($0)))
            }
        }

        func texto(_ rel: String) -> String? {
            try? String(contentsOf: real.appendingPathComponent(rel), encoding: .utf8)
        }

        func entradaReal() -> VaultEntry? { registro.load().first { $0.id == realEntry.id } }

        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    /// La real «tiene» `Fotos/clip.mov` solo en iCloud (simulado: nunca se toca iCloud de verdad).
    static func discoConICloud(_ e: Escenario) -> RecordingFileSystem {
        RecordingFileSystem(datalessPaths: [e.real.appendingPathComponent("Fotos/clip.mov").path])
    }

    // MARK: Vista previa

    @Test("Vista previa: añade, cambia y archiva lo justo; conflictos con la real por defecto; nada privado; sin pulsar la real no cambia")
    func vistaPreviaSinPulsar() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        let antes = try await e.inventarioCompleto()
        let privadoAntes = try e.privadoSHA()
        let fs = Self.discoConICloud(e)

        let v = try await e.preparar(fs: fs)
        #expect(v.cambios.filter { $0.accion == .anadir }.map(\.ruta.raw).sorted() == ["2 · Ventas/Contactos/ana.md", "Notas/nueva.md"])
        #expect(v.cambios.filter { $0.accion == .cambiar }.map(\.ruta.raw).sorted() == ["Facturas/f1.pdf", "Notas/plan.md"])
        #expect(v.cambios.filter { $0.accion == .archivar }.map(\.ruta.raw).sorted() == ["Clientes/ana.md", "Viejo/obsoleto.md"])
        #expect(v.conflictos.map(\.ruta.raw) == ["Notas/conflicto.md"])
        #expect(v.conflictos.first?.tipo == .cambiaronLasDos)
        #expect(v.eleccion(VaultPath("Notas/conflicto.md")) == .quedarseConLaReal)
        #expect(v.soloEnICloud.map(\.raw) == ["Fotos/clip.mov"])
        #expect(v.nuevosEnLaReal.map(\.raw) == ["Notas/real-nueva.md"])
        #expect(v.soloCambiaronEnLaReal.map(\.raw) == ["Notas/real-cambia.md"])
        #expect(v.quitadosEnLaReal.map(\.raw) == ["Notas/quitar-en-real.md"])
        #expect(v.noSePasan.map(\.raw) == ["\(Escenario.privado)/intruso.md"])
        #expect(v.privado.map(\.raw) == [Escenario.privado])
        #expect(v.efectivos.allSatisfy { !$0.ruta.raw.hasPrefix(Escenario.privado) })
        #expect(v.resumen == "Añadir 2 · Cambiar 2 · Archivar 2 · 1 conflicto: se queda la real · 1 solo en iCloud, no se tocan · No se borra nada")
        #expect(v.textoDeConfirmacion.hasPrefix(
            "Se van a añadir 2 ficheros, cambiar 2 ficheros y archivar 2 ficheros en tu carpeta real «Panadería Prueba». No se borra nada"))
        // Ni se lista ni se lee lo privado; nada fuera del hilo protegido de iCloud.
        #expect(!fs.log.withLock { $0.listed + $0.hashed }.contains { $0.contains(Escenario.privado) && $0.contains(e.real.path) })
        #expect(fs.log.withLock { $0.unprotectedCalls }.isEmpty)

        // Sin pulsar el botón (y con una confirmación mal escrita), la real queda con el mismo inventario.
        await #expect(throws: ErrorDeRelevo.sinConfirmar) {
            try await e.aplicador.aplicar(v, confirmacion: ConfirmacionDeRelevo(nombreEmpresa: Escenario.empresa, escrito: "Panaderia"),
                                          abrir: e.abrir)
        }
        let despues = try await e.inventarioCompleto()
        #expect(despues.hashArbol == antes.hashArbol)
        #expect(try e.privadoSHA() == privadoAntes)
        #expect(!FileManager.default.fileExists(atPath: e.real.appendingPathComponent(".tls/escritor.json").path))
        #expect(e.entradaReal()?.escritura == .bloqueada)
        #expect(RegistroDeRelevo.leer(appSupport: e.asup, real: e.realEntry.id) == nil)
    }

    // MARK: Aplicar y deshacer

    @Test("Al aplicar se hace exactamente la vista previa (recuento y SHA-256); lo privado no se toca; «Deshacer» deja la real con su huella previa")
    func aplicarYDeshacer() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        let huellaAntes = try await e.huella()
        let privadoAntes = try e.privadoSHA()
        let disco = Self.discoConICloud(e)
        let v = try await e.preparar(fs: disco)
        let conf = ConfirmacionDeRelevo(nombreEmpresa: Escenario.empresa, escrito: "  panadería prueba ")
        #expect(conf.confirmada)

        let r = try await e.aplicador(disco).aplicar(v, confirmacion: conf, abrir: e.abrir)
        #expect(r.correcto, "Diferencias: \(r.diferencias)")
        #expect(r.comprobados == v.efectivos.count && r.comprobados == 6)
        // Paso 4: lo de la vista previa, tal cual.
        #expect(e.texto("Notas/plan.md") == "Plan v2 de la copia\n")
        #expect(e.texto("Notas/nueva.md") == "Nueva en la copia\n")
        #expect(e.texto("2 · Ventas/Contactos/ana.md") == "# Ana\n")
        #expect(try Data(contentsOf: e.real.appendingPathComponent("Facturas/f1.pdf")) == Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xAA, 0xBB]))
        #expect(!FileManager.default.fileExists(atPath: e.real.appendingPathComponent("Viejo/obsoleto.md").path))
        #expect(e.texto("Archivo/Relevo 2026-10-24/Viejo/obsoleto.md") == "Ya no sirve\n")
        #expect(e.texto("Archivo/Relevo 2026-10-24/Clientes/ana.md") == "# Ana\n")
        // Lo que no estaba en la vista previa, igual.
        #expect(e.texto("Notas/conflicto.md") == "Versión de la real\n")          // conflicto: gana la real
        #expect(e.texto("Notas/real-cambia.md") == "Cambió en la real\n")
        #expect(e.texto("Notas/real-nueva.md") == "Nueva en la real\n")
        #expect(!FileManager.default.fileExists(atPath: e.real.appendingPathComponent("Notas/quitar-en-real.md").path))
        #expect(FileManager.default.fileExists(atPath: e.real.appendingPathComponent("Fotos/clip.mov").path))   // solo en iCloud: no se toca
        #expect(try e.privadoSHA() == privadoAntes)
        #expect(!FileManager.default.fileExists(atPath: e.real.appendingPathComponent("\(Escenario.privado)/intruso.md").path))
        // Paso 5: lo privado, declarado en la real.
        let config = try #require(e.texto(".tls/config.yaml"))
        #expect(config.contains("privado:") && config.contains(Escenario.privado))
        #expect(try VaultLayout.declaredPrivado(root: e.real).map(\.raw) == [Escenario.privado])
        // Paso 6: escritor y `vaults.json`.
        let escritor = try #require(try WriterClaim.read(root: e.real))
        #expect(escritor.instalacion == e.registro.installationID().uuidString.lowercased())
        #expect(escritor.vault_id == e.realEntry.id.uuidString.lowercased())
        #expect(e.entradaReal()?.escritura == .permitida)
        let marca = try #require(RegistroDeRelevo.leer(appSupport: e.asup, real: e.realEntry.id))
        #expect(marca.estado == .hecho && marca.anadidos == 2 && marca.cambiados == 2 && marca.archivados == 2)
        // Paso 7: la nota con las propuestas (no aplicadas): Empresa.md y AGENTS.md siguen igual.
        let nota = try #require(r.notaDePropuestas)
        #expect(nota.raw == "Buzón/Propuestas del relevo 2026-10-24.md")
        let textoNota = try #require(e.texto(nota.raw))
        #expect(textoNota.contains("No he aplicado ninguno") && textoNota.contains("validar.py") && textoNota.contains("## Descripción"))
        #expect(textoNota.contains("Línea 3") && textoNota.contains("la carpeta `Tareas/` de cada área"))
        #expect(e.texto("Empresa.md") == "# Panadería Prueba\n\nLas tareas viven en `Tareas.md`.\n")
        // Copia de seguridad, fuera de la carpeta y comprobada.
        #expect(r.respaldo.path.hasPrefix(e.asup.path))
        #expect(try String(contentsOf: r.respaldo.appendingPathComponent("ficheros/Notas/plan.md"), encoding: .utf8) == "Plan v1\n")
        #expect(try String(contentsOf: r.respaldo.appendingPathComponent("ficheros/Viejo/obsoleto.md"), encoding: .utf8) == "Ya no sirve\n")
        #expect(FileManager.default.fileExists(atPath: r.respaldo.appendingPathComponent("indice.json").path))
        #expect(FileManager.default.fileExists(atPath: r.respaldo.appendingPathComponent("vaults.json.anterior").path))
        #expect(!(FileManager.default.enumerator(atPath: r.respaldo.path)?.allObjects as? [String] ?? []).contains { $0.contains(Escenario.privado) })

        // Deshacer: la real vuelve a su huella, a solo lectura y sin escritor (antes no había).
        let ok = try await e.aplicador(disco).deshacer(r, vista: v, con: r.bus)
        #expect(ok)
        #expect(try await e.huella() == huellaAntes)
        #expect(e.texto("Notas/plan.md") == "Plan v1\n")
        #expect(e.texto("Viejo/obsoleto.md") == "Ya no sirve\n")
        #expect(!FileManager.default.fileExists(atPath: e.real.appendingPathComponent(".tls/escritor.json").path))
        #expect(FileManager.default.fileExists(atPath: r.respaldo.appendingPathComponent("escritor.json.apartado").path))
        #expect(e.entradaReal()?.escritura == .bloqueada)
        #expect(RegistroDeRelevo.leer(appSupport: e.asup, real: e.realEntry.id)?.estado == .deshecho)
        #expect(try e.privadoSHA() == privadoAntes)
    }

    @Test("Conflicto: «quedarse con la copia» lo pasa; el texto de confirmación cambia sus cifras")
    func conflictoConLaCopia() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        var v = try await e.preparar()
        v.elegir(.quedarseConLaCopia, para: VaultPath("Notas/conflicto.md"))
        #expect(v.cambiar == 3)
        #expect(v.textoDeConfirmacion.hasPrefix("Se van a añadir 2 ficheros, cambiar 3 ficheros y archivar"))
        let r = try await e.aplicador.aplicar(v, confirmacion: ConfirmacionDeRelevo(nombreEmpresa: Escenario.empresa, escrito: Escenario.empresa),
                                              abrir: e.abrir)
        #expect(r.correcto, "Diferencias: \(r.diferencias)")
        #expect(e.texto("Notas/conflicto.md") == "Versión de la copia\n")
        #expect(try String(contentsOf: r.respaldo.appendingPathComponent("ficheros/Notas/conflicto.md"), encoding: .utf8) == "Versión de la real\n")
    }

    // MARK: Cerrojos y cambios a destiempo

    @Test("Con el cerrojo de la otra aplicación ocupado se rechaza con un mensaje claro y no se toca nada; libre, se reclama su escritor y «Deshacer» lo devuelve")
    func cerrojoDelFork() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        // La carpeta la llevaba el fork.
        let delFork = Data("{\"instalacion\":\"go-1\",\"equipo\":\"Mac de prueba\",\"workspace_id\":\"ws-1\",\"empresa\":\"Panadería Prueba\",\"desde\":\"2026-01-01\"}\n".utf8)
        try Escenario.escribir(e.real, ".tls/escritor.json", delFork, fecha: Escenario.antiguo)
        let v = try await e.preparar()
        let antes = try await e.inventarioCompleto()
        // El fork, abierto: tiene su cerrojo en exclusiva.
        let cerrojo = try #require(CerrojoDelRelevo.cerrojosDelFork(real: e.real, rutaRegistrada: e.realEntry.ruta,
                                                                     estadoDelFork: e.estadoFork).first)
        try FileManager.default.createDirectory(at: cerrojo.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(cerrojo.path, O_CREAT | O_RDWR, 0o600)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        let conf = ConfirmacionDeRelevo(nombreEmpresa: Escenario.empresa, escrito: Escenario.empresa)
        do {
            _ = try await e.aplicador.aplicar(v, confirmacion: conf, abrir: e.abrir)
            Issue.record("Debía rechazarse con el fork abierto")
        } catch let error as ErrorDeRelevo {
            #expect(error == .otraAplicacionAbierta)
            let msg = error.localizedDescription
            #expect(msg.contains("Multica") && msg.contains("Ciérrala") && msg.contains("No se ha cambiado nada"))
        }
        #expect(try await e.inventarioCompleto().hashArbol == antes.hashArbol)
        #expect(try Data(contentsOf: e.real.appendingPathComponent(".tls/escritor.json")) == delFork)
        #expect(e.entradaReal()?.escritura == .bloqueada)
        // El fork, cerrado: se puede.
        flock(fd, LOCK_UN)
        close(fd)
        let r = try await e.aplicador.aplicar(v, confirmacion: conf, abrir: e.abrir)
        #expect(r.correcto, "Diferencias: \(r.diferencias)")
        #expect(r.escritorAnterior == delFork)
        #expect(try WriterClaim.read(root: e.real)?.instalacion == e.registro.installationID().uuidString.lowercased())
        #expect(try Data(contentsOf: r.respaldo.appendingPathComponent("escritor.json.anterior")) == delFork)
        // Mientras dura el relevo, el fork no podía tomar su cerrojo; al acabar, sí (se soltó).
        let fd2 = open(cerrojo.path, O_RDWR)
        #expect(flock(fd2, LOCK_EX | LOCK_NB) == 0)
        flock(fd2, LOCK_UN); close(fd2)
        // Deshacer devuelve el escritor del fork tal cual.
        #expect(try await e.aplicador.deshacer(r, vista: v, con: r.bus))
        #expect(try Data(contentsOf: e.real.appendingPathComponent(".tls/escritor.json")) == delFork)
    }

    @Test("Otra ventana con la real abierta para escribir, u otro Mac como escritor: se rechaza sin tocar nada")
    func otrosEscritores() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        let v = try await e.preparar()
        let antes = try await e.inventarioCompleto()
        let conf = ConfirmacionDeRelevo(nombreEmpresa: Escenario.empresa, escrito: Escenario.empresa)
        // Otra ventana de esta app con el cerrojo propio de la real.
        let propio = WriterClaim.lockURL(root: e.real, appSupport: e.asup)
        try FileManager.default.createDirectory(at: propio.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(propio.path, O_CREAT | O_RDWR, 0o600)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: ErrorDeRelevo.otraVentanaAbierta) {
            try await e.aplicador.aplicar(v, confirmacion: conf, abrir: e.abrir)
        }
        flock(fd, LOCK_UN); close(fd)
        // Otro Mac.
        try Escenario.escribir(e.real, ".tls/escritor.json",
                               Data("{\"instalacion\":\"otra\",\"equipo\":\"Mac de la oficina\",\"vault_id\":\"x\",\"empresa\":\"P\",\"app\":\"x\",\"desde\":\"2026-02-01\"}\n".utf8),
                               fecha: Escenario.antiguo)
        let antes2 = try await e.inventarioCompleto()
        do {
            _ = try await e.aplicador.aplicar(v, confirmacion: conf, abrir: e.abrir)
            Issue.record("Debía rechazarse con otro Mac como escritor")
        } catch let error as ErrorDeRelevo {
            #expect(error == .otroEquipo(equipo: "Mac de la oficina", desde: "2026-02-01"))
            #expect(error.localizedDescription.contains("Mac de la oficina"))
        }
        #expect(try await e.inventarioCompleto().hashArbol == antes2.hashArbol)
        #expect(antes.hashArbol != antes2.hashArbol)
    }

    @Test("Si la real o la copia cambian después de la vista previa, no se escribe nada")
    func vistaPreviaCaducada() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        let conf = ConfirmacionDeRelevo(nombreEmpresa: Escenario.empresa, escrito: Escenario.empresa)
        let v = try await e.preparar()
        try Escenario.escribir(e.real, "Notas/plan.md", Data("Plan tocado en la real\n".utf8))
        let antes = try await e.inventarioCompleto()
        await #expect(throws: ErrorDeRelevo.self) {
            try await e.aplicador.aplicar(v, confirmacion: conf, abrir: e.abrir)
        }
        #expect(try await e.inventarioCompleto().hashArbol == antes.hashArbol)
        #expect(!FileManager.default.fileExists(atPath: e.real.appendingPathComponent(".tls/escritor.json").path))
        // La copia cambia tras la vista previa.
        let v2 = try await e.preparar()
        try Escenario.escribir(e.copia, "Notas/nueva.md", Data("Otra cosa\n".utf8))
        await #expect(throws: ErrorDeRelevo.laCopiaCambio("nueva.md")) {
            try await e.aplicador.aplicar(v2, confirmacion: conf, abrir: e.abrir)
        }
        #expect(try await e.inventarioCompleto().hashArbol == antes.hashArbol)
    }

    @Test("Solo desde una copia cuyo origen es una real registrada")
    func soloDesdeUnaCopiaDeLaReal() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        #expect(DisponibilidadDelRelevo.evaluar(e.copiaEntry, registradas: e.registro.load()).real?.id == e.realEntry.id)
        #expect(DisponibilidadDelRelevo.evaluar(e.realEntry, registradas: e.registro.load()).real == nil)
        var huérfana = e.copiaEntry
        huérfana.origen = e.base.appendingPathComponent("otra").path
        await #expect(throws: ErrorDeRelevo.self) {
            try await PlanDeRelevo.preparar(copia: e.copia, copiaEntry: huérfana, real: e.real, realEntry: e.realEntry,
                                            hoy: LocalDate(year: 2026, month: 10, day: 24)!)
        }
    }
}
