import CryptoKit
import Darwin
import Foundation
import Testing
@testable import TLSCore

/// Piezas del núcleo de «Pasar a mi carpeta real» (PLAN §9 F6), con carpetas temporales sintéticas.
@Suite("F6 · Núcleo del relevo")
struct RelevoNucleoTests {
    static func temporal() throws -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tls-relevo-nucleo-\(UUID().uuidString)")
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test("La confirmación pide el nombre de la empresa tal cual (sin contar espacios, mayúsculas ni la forma de las tildes)")
    func confirmacion() {
        var c = ConfirmacionDeRelevo(nombreEmpresa: "Panadería Sol")
        #expect(!c.confirmada)
        c.escrito = "Panaderia Sol"
        #expect(!c.confirmada)
        c.escrito = "  panadería   sol "
        #expect(c.confirmada)
        c.escrito = "Panaderi\u{301}a Sol"   // tilde escrita en NFD
        #expect(c.confirmada)
        #expect(!ConfirmacionDeRelevo(nombreEmpresa: " ", escrito: " ").confirmada)
        #expect(TextosDelRelevo.pideNombre("Panadería Sol") == "Para confirmar, escribe el nombre de tu empresa: «Panadería Sol».")
    }

    @Test("El texto de confirmación dice literalmente cuántos ficheros se añaden, cambian y archivan")
    func textoDeConfirmacion() {
        let t = TextosDelRelevo.confirmacion(empresa: "Panadería Sol", anadir: 3, cambiar: 1, archivar: 0, conflictos: 2,
                                             privado: 1, propuestas: true)
        #expect(t.hasPrefix("Se van a añadir 3 ficheros, cambiar 1 fichero y archivar 0 ficheros en tu carpeta real «Panadería Sol». No se borra nada"))
        #expect(t.contains("En 2 ficheros que cambiaron en las dos se queda lo que elegiste."))
        #expect(t.contains("1 carpeta privada queda marcada como privada"))
        #expect(t.contains("copia de seguridad") && t.contains("deshacer"))
        for palabra in ["vault", "yaml", "mcp", "hash", "agente", "frontmatter"] {
            #expect(!t.lowercased().contains(palabra))
            #expect(!TextosDelRelevo.explicacion.lowercased().contains(palabra))
        }
    }

    @Test("Solo aparece en una copia cuyo origen es una carpeta real registrada")
    func disponibilidad() {
        let real = VaultEntry(nombre: "Panadería Sol", ruta: "/tmp/Empresas/Panadería Sol/", bookmark: nil, clase: .real,
                              escritura: .bloqueada)
        let copia = VaultEntry(nombre: "Panadería Sol (copia)", ruta: "/tmp/copias/x", bookmark: nil, clase: .copia,
                               escritura: .permitida, origen: "/tmp/Empresas/panaderi\u{301}a sol")
        #expect(DisponibilidadDelRelevo.evaluar(copia, registradas: [real, copia]) == .disponible(real: real))
        #expect(DisponibilidadDelRelevo.evaluar(real, registradas: [real, copia]).real == nil)
        var demo = copia
        demo.clase = .demo
        #expect(DisponibilidadDelRelevo.evaluar(demo, registradas: [real, demo]).real == nil)
        var sinOrigen = copia
        sinOrigen.origen = nil
        #expect(DisponibilidadDelRelevo.evaluar(sinOrigen, registradas: [real, sinOrigen]).real == nil)
        // El origen registrado como copia (no como real): no aparece.
        var noReal = real
        noReal.clase = .copia
        #expect(DisponibilidadDelRelevo.evaluar(copia, registradas: [noReal, copia]).real == nil)
    }

    @Test("Cerrojo del escritor antiguo: misma ruta que el fork (`locks/<sha256[:8]>.lock`); ocupado → rechazo; libre → compartido")
    func cerrojoDelFork() throws {
        let base = try Self.temporal()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("Real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let fork = base.appendingPathComponent("estado-fork", isDirectory: true)
        let asup = base.appendingPathComponent("asup", isDirectory: true)
        let esperado = SHA256.hash(data: Data(real.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        #expect(esperado.count == 16)
        let rutas = CerrojoDelRelevo.cerrojosDelFork(real: real, rutaRegistrada: real.path + "/", estadoDelFork: fork)
        #expect(rutas.first?.lastPathComponent == "\(esperado).lock")
        #expect(CerrojoDelRelevo.limpiar("/a//b/./c/../d/") == "/a/b/d")
        // Sin fichero de cerrojo: libre, y no se crea nada en el estado del fork.
        let libre = try CerrojoDelRelevo.tomar(real: real, rutaRegistrada: real.path, appSupport: asup, estadoDelFork: fork,
                                               instalacion: UUID())
        #expect(libre.cerrojosDelFork.isEmpty && libre.escritorAnterior == .ninguno)
        libre.soltar()
        #expect(!FileManager.default.fileExists(atPath: fork.path))
        // El fork abierto (cerrojo exclusivo): se rechaza con mensaje claro.
        try FileManager.default.createDirectory(at: fork.appendingPathComponent("locks"), withIntermediateDirectories: true)
        let fd = open(rutas[0].path, O_CREAT | O_RDWR, 0o600)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: ErrorDeRelevo.otraAplicacionAbierta) {
            try CerrojoDelRelevo.tomar(real: real, rutaRegistrada: real.path, appSupport: asup, estadoDelFork: fork, instalacion: UUID())
        }
        flock(fd, LOCK_UN)
        // Cerrado: se toma compartido y, mientras, el fork no puede tomarlo en exclusiva.
        let tomado = try CerrojoDelRelevo.tomar(real: real, rutaRegistrada: real.path, appSupport: asup, estadoDelFork: fork,
                                                instalacion: UUID())
        #expect(tomado.cerrojosDelFork.count == 1)
        #expect(flock(fd, LOCK_EX | LOCK_NB) != 0)
        tomado.soltar()
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        flock(fd, LOCK_UN)
        close(fd)
    }

    @Test("Quién lleva la carpeta: ninguno, el fork, esta instalación u otro Mac (sin descargar nada)")
    func escritorAnterior() throws {
        let real = try Self.temporal()
        defer { try? FileManager.default.removeItem(at: real) }
        let yo = UUID()
        #expect(try EscritorAnterior.leer(root: real, instalacion: yo).0 == .ninguno)
        let url = real.appendingPathComponent(".tls/escritor.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"workspace_id\":\"ws\",\"empresa\":\"P\"}".utf8).write(to: url)
        #expect(try EscritorAnterior.leer(root: real, instalacion: yo).0 == .fork(empresa: "P"))
        try Data("{\"instalacion\":\"\(yo.uuidString.lowercased())\"}".utf8).write(to: url)
        #expect(try EscritorAnterior.leer(root: real, instalacion: yo).0 == .estaInstalacion)
        try Data("{\"instalacion\":\"otra\",\"equipo\":\"Mac B\",\"desde\":\"ayer\"}".utf8).write(to: url)
        #expect(try EscritorAnterior.leer(root: real, instalacion: yo).0 == .otraInstalacion(equipo: "Mac B", desde: "ayer"))
        try Data("no es json".utf8).write(to: url)
        #expect(throws: ErrorDeRelevo.escritorIlegible) { try EscritorAnterior.leer(root: real, instalacion: yo) }
    }

    @Test("Reclamar el escritor sustituye el del fork solo si sigue igual, y restaurarlo devuelve sus mismos bytes")
    func reclamarYRestaurar() throws {
        let real = try Self.temporal()
        defer { try? FileManager.default.removeItem(at: real) }
        let entry = VaultEntry(nombre: "Panadería Sol", ruta: real.path, bookmark: nil, clase: .real, escritura: .bloqueada)
        let yo = UUID()
        let fork = Data("{\"workspace_id\":\"ws\"}\n".utf8)
        let url = real.appendingPathComponent(".tls/escritor.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fork.write(to: url)
        // Si cambió desde que se leyó, no se pisa.
        #expect(throws: (any Error).self) {
            try RegistroDeRelevo.reclamarEscritor(root: real, entry: entry, instalacion: yo, app: "prueba", now: Date(),
                                                  anterior: Data("{}".utf8))
        }
        #expect(try Data(contentsOf: url) == fork)
        let info = try RegistroDeRelevo.reclamarEscritor(root: real, entry: entry, instalacion: yo, app: "prueba", now: Date(),
                                                         anterior: fork)
        #expect(info.instalacion == yo.uuidString.lowercased() && info.vault_id == entry.id.uuidString.lowercased())
        #expect(try WriterClaim.read(root: real)?.instalacion == yo.uuidString.lowercased())
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let puesto = RegistroDeRelevo.escritorActual(root: real)
        try RegistroDeRelevo.restaurarEscritor(root: real, anterior: fork, puesto: puesto, apartarEn: real.appendingPathComponent("x"))
        #expect(try Data(contentsOf: url) == fork)
    }

    @Test("Marca del relevo y `vaults.json`: permitida tras el relevo, bloqueada al deshacer")
    func marcaYRegistro() throws {
        let asup = try Self.temporal()
        defer { try? FileManager.default.removeItem(at: asup) }
        let registro = VaultRegistry(directory: asup)
        let real = VaultEntry(nombre: "P", ruta: "/tmp/P", bookmark: nil, clase: .real, escritura: .bloqueada)
        try registro.upsert(real)
        try RegistroDeRelevo.fijarEscritura(.permitida, registro: registro, real: real.id)
        #expect(registro.load().first?.escritura == .permitida)
        try RegistroDeRelevo.fijarEscritura(.bloqueada, registro: registro, real: real.id)
        #expect(registro.load().first?.escritura == .bloqueada)
        let m = MarcaDeRelevo(real_id: "r", copia_id: "c", fecha: "f", estado: .hecho, planes: ["p"], respaldo: "/x",
                              anadidos: 1, cambiados: 2, archivados: 3, hash_antes: "h")
        try RegistroDeRelevo.guardar(m, appSupport: asup, real: real.id)
        #expect(RegistroDeRelevo.leer(appSupport: asup, real: real.id) == m)
    }

    @Test("Propuestas: localiza las menciones a Tareas.md y deja el parche de validar.py sin aplicar")
    func propuestas() throws {
        let hoy = try #require(LocalDate(year: 2026, month: 10, day: 24))
        let c = PropuestasDelRelevo.cambios(en: "# Empresa\n\nLas tareas viven en `Tareas.md`.\r\nOtra línea\n", fichero: "Empresa.md")
        #expect(c.count == 1 && c[0].linea == 3)
        #expect(c[0].despues == "Las tareas viven en la carpeta `Tareas/` de cada área (una ficha por tarea).")
        let nota = PropuestasDelRelevo.nota(hoy: hoy, empresa: "Tareas en Tareas.md\n", agentes: nil, soloEnICloud: [])
        #expect(PropuestasDelRelevo.nombre(hoy) == "Propuestas del relevo 2026-10-24.md")
        #expect(nota.contains("No he aplicado ninguno"))
        #expect(nota.contains("### AGENTS.md\n\nNo está en tu carpeta real"))
        #expect(nota.contains("## Parche de validar.py") && nota.contains("```diff") && nota.contains("## Descripción"))
        #expect(nota.contains(#"ruta.replace("\\", "/")"#))
        let icloud = PropuestasDelRelevo.nota(hoy: hoy, empresa: nil, agentes: nil, soloEnICloud: ["Empresa.md"])
        #expect(icloud.contains("solo en iCloud"))
    }
}
