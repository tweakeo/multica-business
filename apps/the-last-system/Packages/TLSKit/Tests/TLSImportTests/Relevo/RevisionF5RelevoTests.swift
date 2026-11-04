import Foundation
import Testing
import TLSCore
@testable import TLSImport

/// Revisión adversarial de seguridad y privacidad de F6 (rol revisión-seguridad): «Pasar a mi carpeta real», SOLO con
/// carpetas sintéticas (el `Escenario` de `RelevoTests`). Lo que hoy falla va en `withKnownIssue` (S-…).
@Suite("Revisión F6 · relevo (carpetas sintéticas)", .serialized)
struct RevisionF5RelevoTests {
    typealias Escenario = RelevoTests.Escenario

    // MARK: S10 · Lo marcado privado en la copia se archiva en la real

    /// El inventario de la copia poda lo que la **copia** declara privado (`.tls/config.yaml`). Si Manu marca una carpeta
    /// como privada mientras trabaja en la copia (Ajustes, la puesta en marcha o «Ordenar»), esa carpeta desaparece del
    /// lado de la copia y, en la real (donde no es privada), sus ficheros quedan «solo en la real y anteriores a la copia»
    /// → **archivar**: el relevo mueve a `Archivo/Relevo …` justo lo que Manu acaba de proteger. Y el paso 5 solo lleva
    /// a la real lo que se dejó fuera al copiar (`carpetasPrivadasDeLaCopia`), no lo que se marcó después.
    @Test("S10 · Una carpeta marcada privada en la copia no se archiva en la real y queda privada en la real")
    func privadoDeLaCopiaSeArchiva() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        // En la copia, Manu marca «Clientes» como privado (lo que la app escribe en `.tls/config.yaml`).
        let config = e.copia.appendingPathComponent(".tls/config.yaml")
        let actual = try? String(contentsOf: config, encoding: .utf8)
        let nuevo = try #require(VaultLayout.configConPrivado(actual, anadir: [VaultPath("Clientes")]))
        try nuevo.write(to: config, atomically: true, encoding: .utf8)
        // Y hace algo en la copia para que haya relevo.
        try Escenario.escribir(e.copia, "Notas/nueva.md", Data("Nueva en la copia\n".utf8), fecha: e.despues)

        let v = try await e.preparar()
        // Corregido (S10): lo privado de la copia queda protegido en la real y declarado privado allí.
        #expect(!v.efectivos.contains { $0.ruta.raw.hasPrefix("Clientes/") })
        #expect(v.privado.map(\.raw).contains("Clientes"))
        #expect(!v.inventarioReal.entradas.contains { $0.ruta.hasPrefix("Clientes/") })
    }

    // MARK: S11 · Un cambio de la real con fecha antigua se pisa sin conflicto

    /// La vista previa decide «la real cambió» solo por la fecha de modificación frente a la de la copia (no guarda las
    /// huellas de la real al copiar). Un cambio en la real con fecha anterior (otro Mac o iPhone con el reloj atrasado,
    /// una restauración de Time Machine o de una copia con `cp -p`/`rsync -t`, una app que conserva la fecha) cuenta como
    /// «sin cambios en la real» → **cambiar** (o **archivar** si la copia lo quitó): se sustituye sin preguntar. La
    /// versión de la real solo queda en la copia de seguridad de los ajustes de la app, que Manu no ve.
    @Test("S11 · Si el fichero de la real ya no es el que se copió, es un conflicto aunque su fecha sea antigua")
    func cambioEnLaRealConFechaAntigua() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        // En la real, alguien cambió el plan, pero el fichero conserva una fecha anterior a la copia.
        try Escenario.escribir(e.real, "Notas/plan.md", Data("Plan v1 con lo que añadió Manu en el iPhone\n".utf8),
                               fecha: Escenario.antiguo)
        let v = try await e.preparar()
        // Corregido (S11): la línea base de la copia (SHA-256 al copiar) decide, no las fechas.
        #expect(!v.cambios.contains { $0.ruta.raw == "Notas/plan.md" })
        #expect(v.conflictos.contains { $0.ruta.raw == "Notas/plan.md" })
    }

    // MARK: P1-3 · «Deshacer el último relevo» después de cerrar la hoja

    /// F6 · corrector: con la marca (`relevo.json`) y la copia de seguridad, otro escritor (como el de Ajustes, sin el
    /// resultado en memoria) deshace el relevo, devuelve el escritor del fork y deja la real en solo lectura.
    @Test("P1-3 · Deshacer el último relevo con un escritor nuevo, tras cerrar la hoja")
    func deshacerTrasCerrarLaHoja() async throws {
        let e = try await Escenario()
        defer { e.limpiar() }
        try await e.trabajar()
        let delFork = Data("{\"instalacion\":\"go-1\",\"equipo\":\"Mac de prueba\",\"workspace_id\":\"ws-1\",\"empresa\":\"Panadería Prueba\",\"desde\":\"2026-01-01\"}\n".utf8)
        try Escenario.escribir(e.real, ".tls/escritor.json", delFork, fecha: Escenario.antiguo)
        let antes = try await e.huella()
        let v = try await e.preparar()
        let r = try await e.aplicador.aplicar(v, confirmacion: ConfirmacionDeRelevo(nombreEmpresa: Escenario.empresa,
                                                                                    escrito: Escenario.empresa), abrir: e.abrir)
        #expect(r.correcto)
        #expect(RegistroDeRelevo.leer(appSupport: e.asup, real: e.realEntry.id)?.estado == .hecho)
        // Se cierra la hoja: se suelta el escritor del relevo y se pierde el resultado en memoria.
        await r.bus.writer.close()
        #expect(AplicadorDeRelevo.ultimoRelevo(appSupport: e.asup, real: e.realEntry.id) != nil)
        let bus = try await e.abrir(e.realEntry, e.real)
        #expect(try await e.aplicador.deshacerUltimo(real: e.realEntry, root: e.real, con: bus))
        await bus.writer.close()
        #expect(try await e.huella() == antes)
        #expect(try Data(contentsOf: e.real.appendingPathComponent(".tls/escritor.json")) == delFork)
        #expect(e.entradaReal()?.escritura == .bloqueada)
        #expect(RegistroDeRelevo.leer(appSupport: e.asup, real: e.realEntry.id)?.estado == .deshecho)
        #expect(AplicadorDeRelevo.ultimoRelevo(appSupport: e.asup, real: e.realEntry.id) == nil)
    }

    /// Fecha de la copia de seguridad en llano (P2-10), en la hora del Mac y nunca en UTC técnico.
    @Test("P2-10 · La fecha del relevo se dice en llano")
    func fechaEnLlano() {
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        let ahora = ISO8601DateFormatter().date(from: "2026-10-24T10:00:00Z")!
        #expect(TextosDelRelevo.respaldo(iso: "2026-10-24T01:33:00Z", ahora: ahora, zona: madrid)
                == "Guardada hoy a las 03:33 en tu Mac (no en tu carpeta)")
        #expect(TextosDelRelevo.cuando(iso: "2026-10-23T16:05:00Z", ahora: ahora, zona: madrid) == "ayer a las 18:05")
        #expect(TextosDelRelevo.cuando(iso: "2026-09-02T07:10:00Z", ahora: ahora, zona: madrid) == "el 2 de septiembre a las 09:10")
    }

    /// Revisión de seguridad (sin prueba entonces): la marca solo dice «hecho» si la comprobación final cuadra; si no,
    /// «sin comprobar», y con ella la carpeta real no se escribe aunque `vaults.json` dijera «permitida».
    @Test("relevo.json «sin comprobar» no deja escribir la carpeta real")
    func marcaSinComprobarNoDejaEscribir() throws {
        let asup = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tls-marca-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: asup) }
        let real = VaultEntry(nombre: "Empresa de prueba", ruta: "/tmp/no-existe", bookmark: nil, clase: .real, escritura: .permitida)
        var marca = MarcaDeRelevo(real_id: real.id.uuidString.lowercased(), copia_id: UUID().uuidString.lowercased(),
                                  fecha: "2026-10-24T08:00:00Z", estado: .sinComprobar, planes: [], respaldo: asup.path,
                                  anadidos: 1, cambiados: 0, archivados: 0, hash_antes: "x")
        try RegistroDeRelevo.guardar(marca, appSupport: asup, real: real.id)
        #expect(!WritePolicy.realConRelevoHecho(real, appSupport: asup))
        #expect(AplicadorDeRelevo.ultimoRelevo(appSupport: asup, real: real.id) != nil, "se puede deshacer")
        marca.estado = .hecho
        try RegistroDeRelevo.guardar(marca, appSupport: asup, real: real.id)
        #expect(WritePolicy.realConRelevoHecho(real, appSupport: asup))
    }
}
