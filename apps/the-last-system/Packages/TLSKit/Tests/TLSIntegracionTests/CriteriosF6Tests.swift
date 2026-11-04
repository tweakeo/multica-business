import Darwin
import Foundation
import Testing
@testable import TLSCore
@testable import TLSImport
@testable import TLSIntegracion
@testable import TLSUI

/// Los criterios de aceptación de F6 (PLAN §9) con la hoja de verdad (`ModeloRelevo.deLaSesion`) y carpetas
/// **sintéticas**: una «real» hecha con la fixture G3 (`EmpresaMinima`) en un temporal y su copia hecha con `DemoCopier`,
/// registradas como lo haría la app (la real, `clase: real` y en solo lectura). Nadie lo ejecuta sobre la carpeta real
/// de nadie: ni iCloud, ni `~/Library/Application Support/TLS` (el estado de la otra aplicación es otro temporal).
@Suite("F6 · criterios de aceptación con carpetas sintéticas", .serialized)
@MainActor
struct CriteriosF6Tests {
    nonisolated static let empresa = "Estudio Prueba"
    nonisolated static let privado = "Privado"

    nonisolated static var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../TLSCoreTests/Fixtures/EmpresaMinima").standardizedFileURL
    }

    /// La real sintética, su copia, el registro y las dos sesiones como en la app.
    @MainActor
    final class Escenario {
        let base: URL
        let real: URL
        let estadoReal: URL
        let estadoCopia: URL
        let estadoFork: URL
        let registro: VaultRegistry
        let model: AppModel
        var realEntry: VaultEntry
        var copiaEntry: VaultEntry
        let copia: URL
        var sesionCopia: VaultSession!
        var sesionReal: VaultSession?

        init() async throws {
            base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tls-f6-\(UUID().uuidString.prefix(8))")
                .standardizedFileURL.resolvingSymlinksInPath()
            real = base.appendingPathComponent(CriteriosF6Tests.empresa, isDirectory: true)
            estadoReal = base.appendingPathComponent("er", isDirectory: true)
            estadoCopia = base.appendingPathComponent("ec", isDirectory: true)
            estadoFork = base.appendingPathComponent("fork", isDirectory: true)
            // El registro vive donde la sesión de la real busca sus ajustes (como `AppLocations.appSupport` en la app).
            registro = VaultRegistry(directory: estadoReal.appendingPathComponent("asup", isDirectory: true))
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: CriteriosF6Tests.fixture, to: real)
            Self.envejecer(real)
            realEntry = VaultEntry(nombre: CriteriosF6Tests.empresa, ruta: real.path, bookmark: nil, clase: .real, escritura: .bloqueada)
            try registro.upsert(realEntry)
            let copias = base.appendingPathComponent("copias", isDirectory: true)
            try FileManager.default.createDirectory(at: copias, withIntermediateDirectories: true)
            let (inf, entry) = try await DemoCopier(appSupport: registro.directory).copy(
                from: real, into: copias, options: CopyOptions(exclusiones: [VaultPath(CriteriosF6Tests.privado)])) { _ in }
            copiaEntry = entry
            copia = URL(fileURLWithPath: inf.destino)
            try registro.upsert(copiaEntry)
            model = AppModel(registry: registro)
        }

        /// Abre la copia como en la app (con escritor) y trabaja en ella como la persona; después, cambios en la real.
        func trabajar() async throws {
            let s = VaultSession(entry: copiaEntry, estado: estadoCopia)
            s.persona = "Manu"
            sesionCopia = s
            await s.start(using: model)
            try await esperar("la copia escribe", segundos: 20) { s.puedeEscribir }
            let foto = VaultSnapshot.read(root: copia)
            let rumbo = try #require(foto.text(VaultPath("1 · Dirección/Rumbo.md")))
            let decisiones = try #require(foto.text(VaultPath("1 · Dirección/Decisiones.md")))
            let r = try await s.escribirComoPersona(WritePlan(autor: .persona("Manu"), descripcion: "Trabajo en la copia", ops: [
                WriteOp.replaceText(VaultPath("1 · Dirección/Rumbo.md"), base: Data(rumbo.utf8), text: rumbo + "\nObjetivo: 12 clientes.\n")!,
                WriteOp.replaceText(VaultPath("1 · Dirección/Decisiones.md"), base: Data(decisiones.utf8),
                                    text: decisiones + "\n- Decisión de la copia\n")!,
                .create(VaultPath("2 · Ventas/Contactos/Nueva clienta.md"), text: "# Nueva clienta\n"),
                .retire(VaultPath("2 · Ventas/Contactos/José Núñez.md")),
            ]))
            #expect(r.hecho)
            // En la real, después de la copia (Finder, Obsidian o la otra aplicación).
            let despues = copiaEntry.creada.addingTimeInterval(120)
            try escribir("1 · Dirección/Decisiones.md", "# Decisiones\n\n- Decisión de la real\n", fecha: despues)
            try escribir("Notas de la real.md", "Nueva en la real\n", fecha: despues)
            try escribir("\(CriteriosF6Tests.privado)/Expediente personal.md", "Expediente privado cambiado\n", fecha: despues)
        }

        /// Todo, con fecha del 1 de enero de 2026: anterior a la copia.
        nonisolated static func envejecer(_ raiz: URL) {
            let antiguo = Date(timeIntervalSince1970: 1_767_225_600)
            guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: nil) else { return }
            while let u = e.nextObject() as? URL {
                try? FileManager.default.setAttributes([.modificationDate: antiguo], ofItemAtPath: u.path)
            }
        }

        func escribir(_ rel: String, _ texto: String, fecha: Date) throws {
            let url = real.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(texto.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: url.path)
        }

        /// Inventario completo de la real (con lo oculto, `escritor.json` y `Archivo/`), **con** lo privado.
        func inventario() async throws -> String {
            try await Inventory.make(of: real, exclusiones: [], incluirArchivo: true, completo: true).hashArbol
        }

        func huellaPrivado() throws -> Data {
            try Data(contentsOf: real.appendingPathComponent("\(CriteriosF6Tests.privado)/Expediente personal.md"))
        }

        func modelo() throws -> ModeloRelevo {
            try #require(ModeloRelevo.deLaSesion(sesionCopia, registro: registro, estadoDelFork: estadoFork))
        }

        func cerrar() {
            sesionCopia?.close()
            sesionReal?.close()
            try? FileManager.default.removeItem(at: base)
        }
    }

    static func con(_ cuerpo: (Escenario) async throws -> Void) async throws {
        let e = try await Escenario()
        do {
            try await e.trabajar()
            try await cuerpo(e)
        } catch {
            e.cerrar()
            throw error
        }
        e.cerrar()
    }

    // MARK: F6 · 1

    @Test("F6-1 · Sin pulsar el botón, el inventario de G3 queda idéntico en todas las fases (comprobar, vista previa, conflictos, confirmar mal)")
    func sinPulsar() async throws {
        try await Self.con { e in
            let antes = try await e.inventario()
            let privado = try e.huellaPrivado()
            // Solo aparece en la copia de una real registrada; el botón nace desactivado.
            let m = try e.modelo()
            #expect(!m.puedePasar)
            #expect(try await e.inventario() == antes)
            #expect(await m.comprobar())
            #expect(try await e.inventario() == antes)
            await m.preparar()
            #expect(m.fase == .vistaPrevia)
            let v = try #require(m.vista)
            #expect(v.anadir >= 1 && v.cambiar >= 1 && v.archivar >= 1)
            #expect(v.conflictos.map(\.ruta.raw).contains("1 · Dirección/Decisiones.md"))
            #expect(try await e.inventario() == antes)
            m.elegir(.quedarseConLaCopia, para: VaultPath("1 · Dirección/Decisiones.md"))
            m.elegir(.quedarseConLaReal, para: VaultPath("1 · Dirección/Decisiones.md"))
            #expect(try await e.inventario() == antes)
            // Confirmar con otro nombre: sigue desactivado y no escribe.
            m.escrito = "Otra empresa"
            #expect(!m.puedePasar)
            #expect(await m.pasar() == false)
            #expect(try await e.inventario() == antes)
            #expect(try e.huellaPrivado() == privado)
            #expect(e.registro.load().first { $0.id == e.realEntry.id }?.escritura == .bloqueada)
            #expect(RegistroDeRelevo.leer(appSupport: e.registro.directory, real: e.realEntry.id) == nil)
            // La real sigue sin poder escribirse fuera del relevo.
            #expect(throws: WriteError.self) { try WritePolicy.comprobar(e.realEntry, root: e.real, appSupport: e.registro.directory) }
        }
    }

    // MARK: F6 · 2

    @Test("F6-2 · Al pulsarlo se aplica exactamente la vista previa; la real queda escribible (y sigue así al volver a arrancar) y lo privado intacto")
    func alPulsar() async throws {
        try await Self.con { e in
            let privado = try e.huellaPrivado()
            let m = try e.modelo()
            await m.preparar()
            let v = try #require(m.vista)
            let efectivos = v.efectivos
            m.escrito = Self.empresa
            #expect(m.puedePasar)
            #expect(await m.pasar(), "\(m.aviso ?? "")")
            #expect(m.fase == .hecho)
            let r = try #require(m.resultado)
            #expect(r.correcto, "Diferencias: \(r.diferencias)")
            // Exactamente la vista previa: cada cambio, con el SHA-256 que enseñó; lo demás, como estaba.
            for c in efectivos {
                let enReal = c.ruta.url(in: e.real)
                switch c.accion {
                case .anadir, .cambiar:
                    #expect(ContentHash.of(try Data(contentsOf: enReal)) == c.shaCopia, "\(c.ruta.raw)")
                case .archivar:
                    #expect(!FileManager.default.fileExists(atPath: enReal.path), "\(c.ruta.raw)")
                }
            }
            #expect(r.comprobados == efectivos.count)
            // El conflicto: se quedó la real.
            #expect(try String(contentsOf: e.real.appendingPathComponent("1 · Dirección/Decisiones.md"), encoding: .utf8)
                .contains("Decisión de la real"))
            #expect(FileManager.default.fileExists(atPath: e.real.appendingPathComponent("Notas de la real.md").path))
            #expect(try e.huellaPrivado() == privado)
            // `privado` en la configuración de la real, `vaults.json` permitida y la marca del relevo.
            #expect(try String(contentsOf: e.real.appendingPathComponent(".tls/config.yaml"), encoding: .utf8).contains(Self.privado))
            #expect(e.registro.load().first { $0.id == e.realEntry.id }?.escritura == .permitida)
            #expect(RegistroDeRelevo.leer(appSupport: e.registro.directory, real: e.realEntry.id)?.estado == .hecho)

            // Al volver a arrancar la app, la real no se vuelve a bloquear.
            _ = try e.registro.permitirEscrituraEnCopias()
            #expect(e.registro.load().first { $0.id == e.realEntry.id }?.escritura == .permitida)

            // Se suelta el escritor del relevo y la real se abre como una carpeta que escribe.
            await m.terminar()
            e.model.reload()
            let realActual = try #require(e.model.entry(id: e.realEntry.id))
            #expect(realActual.realTrasRelevo)
            #expect(realActual.claseDescripcion == "Tu carpeta real")
            let s = VaultSession(entry: realActual, estado: e.estadoReal)
            s.persona = "Manu"
            e.sesionReal = s
            await s.start(using: e.model)
            try await esperar("la real escribe", segundos: 20) { s.puedeEscribir }
            #expect(s.esRealConRelevo)
            let w = try await s.escribirComoPersona(WritePlan(autor: .persona("Manu"), descripcion: "Primera nota en la real",
                                                              ops: [.create(VaultPath("Primera nota.md"), text: "Hola\n")]))
            #expect(w.hecho)
        }
    }

    // MARK: F6 · 3

    @Test("F6-3 · Si la otra aplicación tiene su cerrojo, se rechaza con un mensaje claro y no se cambia nada")
    func cerrojoOcupado() async throws {
        try await Self.con { e in
            let antes = try await e.inventario()
            let cerrojo = try #require(CerrojoDelRelevo.cerrojosDelFork(real: e.real, rutaRegistrada: e.realEntry.ruta,
                                                                         estadoDelFork: e.estadoFork).first)
            try FileManager.default.createDirectory(at: cerrojo.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fd = open(cerrojo.path, O_CREAT | O_RDWR, 0o600)
            #expect(fd >= 0)
            #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
            defer { flock(fd, LOCK_UN); close(fd) }
            let m = try e.modelo()
            await m.preparar()
            guard case .bloqueado(let mensaje) = m.fase else { Issue.record("Debía quedar bloqueado: \(m.fase)"); return }
            #expect(mensaje.contains("Multica") && mensaje.contains("Ciérrala") && mensaje.contains("No se ha cambiado nada"))
            #expect(!m.puedePasar)
            #expect(try await e.inventario() == antes)
            #expect(e.registro.load().first { $0.id == e.realEntry.id }?.escritura == .bloqueada)
        }
    }
}
