import Darwin
import Foundation
import Testing
import TLSCore
import TLSImport
@testable import TLSUI

/// «Pasar a mi carpeta real» en pantalla (F6 · buzon-relevo) **solo con carpetas sintéticas**: una «real» de prueba en
/// un temporal, su copia hecha con `DemoCopier` y trabajo en las dos. Nunca la carpeta de nadie, ni iCloud.
@Suite("F6 · Pasar a mi carpeta real (pantalla, carpetas sintéticas)", .serialized)
@MainActor
struct RelevoUITests {
    /// Real sintética, su copia y cambios en las dos (uno en conflicto).
    final class Escenario: @unchecked Sendable {
        let base: URL
        let real: URL
        let asup: URL
        let estadoReal: URL
        let estadoFork: URL
        let registro: VaultRegistry
        let realEntry: VaultEntry
        let copiaEntry: VaultEntry
        let copia: URL
        let busCopia: CommandBus
        static let empresa = "Panadería Prueba"
        static let privado = "Expediente privado"
        static let antiguo = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01

        init() async throws {
            base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tls-relevo-ui-\(UUID().uuidString)")
                .standardizedFileURL.resolvingSymlinksInPath()
            real = base.appendingPathComponent(Self.empresa, isDirectory: true)
            asup = base.appendingPathComponent("asup", isDirectory: true)
            estadoReal = base.appendingPathComponent("estado-real", isDirectory: true)
            estadoFork = base.appendingPathComponent("estado-fork", isDirectory: true)
            registro = VaultRegistry(directory: asup)
            let ficheros: [(String, String)] = [
                (".tls/layout.json", "{\"preset\": \"humana\"}"),
                ("Empresa.md", "# Panadería Prueba\n\nLas tareas viven en `Tareas.md`.\n"),
                ("Notas/plan.md", "Plan v1\n"),
                ("Notas/conflicto.md", "Original\n"),
                ("Viejo/obsoleto.md", "Ya no sirve\n"),
                ("\(Self.privado)/secreto.md", "contenido privado de prueba\n"),
            ]
            for (r, t) in ficheros { try Self.escribir(real, r, t, fecha: Self.antiguo) }
            let r = VaultEntry(nombre: Self.empresa, ruta: real.path, bookmark: nil, clase: .real, escritura: .bloqueada)
            try registro.upsert(r)
            realEntry = r
            let copias = base.appendingPathComponent("copias", isDirectory: true)
            try FileManager.default.createDirectory(at: copias, withIntermediateDirectories: true)
            let (inf, entry) = try await DemoCopier(appSupport: asup).copy(
                from: real, into: copias, options: CopyOptions(exclusiones: [VaultPath(Self.privado)])) { _ in }
            copiaEntry = entry
            copia = URL(fileURLWithPath: inf.destino)
            try registro.upsert(entry)
            busCopia = CommandBus(writer: try await VaultWriter.open(
                entry: entry, root: copia, options: .init(stateDirectory: base.appendingPathComponent("estado-copia"), appSupport: asup)))
        }

        static func escribir(_ raiz: URL, _ rel: String, _ t: String, fecha: Date? = nil) throws {
            let url = raiz.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(t.utf8).write(to: url)
            if let fecha { try FileManager.default.setAttributes([.modificationDate: fecha, .creationDate: fecha], ofItemAtPath: url.path) }
        }

        var despues: Date { copiaEntry.creada.addingTimeInterval(120) }

        /// En la copia (como persona, con su escritor): cambia el plan y el conflicto, crea una nota y retira lo viejo.
        /// En la real, después de la copia: cambia el conflicto.
        func trabajar() async throws {
            let manu = Autor.persona("Manu")
            let plan = try Data(contentsOf: copia.appendingPathComponent("Notas/plan.md"))
            let conflicto = try Data(contentsOf: copia.appendingPathComponent("Notas/conflicto.md"))
            let r = try await busCopia.ejecutar(WritePlan(autor: manu, descripcion: "trabajo en la copia", ops: [
                WriteOp.replaceText(VaultPath("Notas/plan.md"), base: plan, text: "Plan v2 de la copia\n")!,
                WriteOp.replaceText(VaultPath("Notas/conflicto.md"), base: conflicto, text: "Versión de la copia\n")!,
                .create(VaultPath("Notas/nueva.md"), text: "Nueva en la copia\n"),
                .retire(VaultPath("Viejo/obsoleto.md")),
            ]))
            #expect(r.hecho)
            try Self.escribir(real, "Notas/conflicto.md", "Versión de la real\n", fecha: despues)
        }

        /// El escritor de la real con la carpeta sintética (`WritePolicy` aún bloquea la clase `real`: cambio pedido).
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

        @MainActor func modelo() -> ModeloRelevo {
            ModeloRelevo(entorno: EntornoDelRelevo(
                copia: copia, copiaEntry: copiaEntry, real: real, realEntry: realEntry,
                hoy: LocalDate(year: 2026, month: 10, day: 24)!,
                aplicador: AplicadorDeRelevo(entorno: .init(appSupport: asup, registro: registro, estadoDelFork: estadoFork,
                                                            app: "The Last System prueba")),
                abrir: abrir))
        }

        func texto(_ rel: String) -> String { (try? String(contentsOf: real.appendingPathComponent(rel), encoding: .utf8)) ?? "" }

        func huella() async throws -> String {
            try await Inventory.make(of: real, exclusiones: [VaultPath(Self.privado)]).hashArbol
        }

        func inventarioCompleto() async throws -> Inventory {
            try await Inventory.make(of: real, exclusiones: [], completo: true)
        }

        func limpiar() async {
            await busCopia.writer.close()
            try? FileManager.default.removeItem(at: base)
        }
    }

    @Test("Sin pulsar el botón: la explicación, la comprobación y la vista previa no cambian nada en la real")
    func sinPulsarNadaCambia() async throws {
        let s = try await Escenario()
        try await s.trabajar()
        let antes = try await s.inventarioCompleto()
        let m = s.modelo()
        #expect(m.fase == .inicio)
        #expect(m.motivoNoPasar == "Antes, prepara la vista previa.")
        #expect(ModeloRelevo.explicacionCorta == "Hasta ahora trabajabas en una copia. Esto pasa tus cambios a tu carpeta de verdad.")
        await m.preparar()
        #expect(m.fase == .vistaPrevia)
        #expect(m.cerrojo?.contains("Nadie más está usando tu carpeta real") == true)
        let v = try #require(m.vista)
        #expect(m.cifras.map(\.valor) == [v.anadir, v.cambiar, v.archivar, 0])
        #expect(v.anadir == 1 && v.cambiar == 1 && v.archivar == 1 && v.conflictos.count == 1)
        #expect(v.resumen.hasSuffix("No se borra nada"))
        #expect(m.lista(.anadir).map(\.ruta.raw) == ["Notas/nueva.md"])
        #expect(m.lista(.archivar).map(\.ruta.raw) == ["Viejo/obsoleto.md"])
        // El conflicto: por defecto se queda la real.
        let c = try #require(v.conflictos.first)
        #expect(c.ruta.raw == "Notas/conflicto.md" && m.eleccion(c.ruta) == .quedarseConLaReal)
        // El botón sigue desactivado hasta escribir el nombre; con otro nombre, también.
        #expect(!m.puedePasar && m.motivoNoPasar == "Escribe el nombre de tu empresa, «Panadería Prueba», para confirmar.")
        m.escrito = "Panaderia"
        #expect(!m.puedePasar)
        #expect(await m.pasar() == false)
        let despues = try await s.inventarioCompleto()
        #expect(despues.hashArbol == antes.hashArbol, "la real no cambia sin pulsar")
        await s.limpiar()
    }

    @Test("Al pulsar se hace exactamente la vista previa (con el conflicto elegido), se comprueba y «Deshacer» la deja como estaba")
    func pasarYDeshacer() async throws {
        let s = try await Escenario()
        try await s.trabajar()
        let huellaAntes = try await s.huella()
        let m = s.modelo()
        await m.preparar()
        let c = try #require(m.vista?.conflictos.first)
        m.elegir(.quedarseConLaCopia, para: c.ruta)
        #expect(m.vista?.cambiar == 2, "al elegir la copia, el conflicto pasa a «cambian»")
        m.elegir(.quedarseConLaReal, para: c.ruta)
        #expect(m.vista?.cambiar == 1)
        m.escrito = "  panadería prueba "
        #expect(m.puedePasar)
        let confirmacion = try #require(m.vista?.textoDeConfirmacion)
        #expect(confirmacion.hasPrefix("Se van a añadir 1 fichero, cambiar 1 fichero y archivar 1 fichero en tu carpeta real «Panadería Prueba». No se borra nada"))
        #expect(await m.pasar())
        #expect(m.fase == .hecho)
        let r = try #require(m.resultado)
        #expect(r.correcto && r.diferencias.isEmpty)
        #expect(m.textoDeComprobacion?.hasPrefix("Hecho y comprobado") == true)
        #expect(s.texto("Notas/plan.md") == "Plan v2 de la copia\n")
        #expect(s.texto("Notas/nueva.md") == "Nueva en la copia\n")
        #expect(s.texto("Notas/conflicto.md") == "Versión de la real\n", "gana la real, como se eligió")
        #expect(!FileManager.default.fileExists(atPath: s.real.appendingPathComponent("Viejo/obsoleto.md").path))
        #expect(s.texto("\(Escenario.privado)/secreto.md") == "contenido privado de prueba\n", "lo privado no se toca")
        // La copia de seguridad, en los ajustes de la app (nunca en la carpeta).
        #expect(r.respaldo.path.hasPrefix(s.asup.path))
        // Deshacer.
        #expect(await m.deshacer())
        #expect(m.fase == .deshecho && m.deshechoBien == true)
        #expect(try await s.huella() == huellaAntes)
        await s.limpiar()
    }

    @Test("Si la otra aplicación tiene la carpeta real (su cerrojo ocupado), se rechaza con un mensaje claro y no se toca nada")
    func cerrojoOcupado() async throws {
        let s = try await Escenario()
        try await s.trabajar()
        let antes = try await s.inventarioCompleto()
        // La otra aplicación (el fork) tiene su cerrojo en exclusiva.
        let lock = try #require(CerrojoDelRelevo.cerrojosDelFork(real: s.real, rutaRegistrada: s.realEntry.ruta, estadoDelFork: s.estadoFork).first)
        try FileManager.default.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: lock.path, contents: Data())
        let fd = open(lock.path, O_RDWR)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        let m = s.modelo()
        await m.preparar()
        guard case .bloqueado(let mensaje) = m.fase else {
            Issue.record("Debía quedar bloqueado: \(m.fase)")
            flock(fd, LOCK_UN); close(fd)
            await s.limpiar()
            return
        }
        #expect(mensaje == ErrorDeRelevo.otraAplicacionAbierta.localizedDescription)
        #expect(mensaje.contains("Multica") && mensaje.contains("No se ha cambiado nada"))
        #expect(m.vista == nil && m.motivoNoPasar != nil)
        // Al cerrarla, «Volver a comprobar» sigue.
        flock(fd, LOCK_UN)
        close(fd)
        await m.preparar()
        #expect(m.fase == .vistaPrevia)
        #expect(try await s.inventarioCompleto().hashArbol == antes.hashArbol)
        await s.limpiar()
    }

    @Test("Si la real cambia entre la vista previa y el botón, no se escribe nada y hay que volver a prepararla")
    func laRealCambio() async throws {
        let s = try await Escenario()
        try await s.trabajar()
        let m = s.modelo()
        await m.preparar()
        m.escrito = Escenario.empresa
        try Escenario.escribir(s.real, "Notas/otra.md", "Alguien escribió en la real\n")
        let antes = try await s.inventarioCompleto()
        #expect(await m.pasar() == false)
        guard case .error(let t) = m.fase else {
            Issue.record("Debía pedir otra vista previa: \(m.fase)")
            await s.limpiar()
            return
        }
        #expect(t.contains("Vuelve a preparar la vista previa") && t.contains("No se ha cambiado nada"))
        #expect(try await s.inventarioCompleto().hashArbol == antes.hashArbol)
        await s.limpiar()
    }

    @Test("Solo aparece en una copia con su carpeta real registrada: en el ejemplo (y en la propia real) queda oculto")
    func soloEnUnaCopia() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        #expect(ModeloRelevo.deLaSesion(a.sesion, registro: a.entorno.model.registry) == nil)
        let s = try await Escenario()
        #expect(DisponibilidadDelRelevo.evaluar(s.copiaEntry, registradas: s.registro.load()).real?.id == s.realEntry.id)
        #expect(DisponibilidadDelRelevo.evaluar(s.realEntry, registradas: s.registro.load()).real == nil)
        await s.limpiar()
    }
}
