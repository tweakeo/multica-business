import Foundation
import Testing
@testable import TLSCore

/// Criterio F1 6: un cambio externo con una edición abierta muestra el aviso y las dos versiones
/// se pueden recuperar; si fuera solo cambiaron propiedades, se fusiona sin aviso.
/// También duplicados «X 2.md» y conflictos de iCloud como tarjetas.
@Suite(.serialized) struct EscrituraConflictosTests {
    static let manu = Autor.persona("Manu")
    static let tarea = "3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md"

    @Test func cambioExternoConEdicionAbiertaEsConflicto() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let path = VaultPath(Self.tarea)
        let abierta = try #require(e.texto(Self.tarea))
        let mia = abierta.replacingOccurrences(of: "Preparar la reunión de arranque con", with: "Preparar y enviar la agenda a")
        // Mientras edito, alguien cambia el cuerpo en Obsidian.
        let fuera = abierta.replacingOccurrences(of: "## Descripción\n", with: "## Descripción\nNota de Obsidian.\n")
        e.escribir(Self.tarea, fuera)
        let r = try await bus.ejecutar(.guardarNota(path, base: abierta, texto: mia), autor: Self.manu)
        let tarjeta = try #require(r.conflicto)
        // No se escribió nada encima.
        #expect(e.texto(Self.tarea) == fuera)
        #expect(tarjeta.tipo == .edicion && tarjeta.ruta == path)
        #expect(bus.writer.conflicts.pendientes().map(\.id) == [tarjeta.id])
        // Las dos versiones se pueden recuperar.
        let tuya = try #require(tarjeta.versiones.first { $0.etiqueta == "Tu versión" })
        let laDeFuera = try #require(tarjeta.versiones.first { $0.etiqueta == "La de fuera" })
        #expect(bus.writer.conflicts.datos(de: tuya, root: e.root) == Data(mia.utf8))
        #expect(bus.writer.conflicts.datos(de: laDeFuera, root: e.root) == Data(fuera.utf8))
        // Me quedo con la de fuera: la mía va a Archivo/Conflictos.
        let res = try await bus.resolverConflicto(tarjeta.id, eleccion: .otra, autor: Self.manu)
        #expect(e.texto(Self.tarea) == fuera)
        let guardada = try #require(res.creadas.first)
        #expect(guardada.raw.hasPrefix("Archivo/Conflictos/3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque (tu versión "))
        #expect(e.texto(guardada.raw) == mia)
        #expect(bus.writer.conflicts.pendientes().isEmpty)
    }

    @Test func soloPropiedadesFueraSeFusionaSinAviso() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let path = VaultPath(Self.tarea)
        let abierta = try #require(e.texto(Self.tarea))
        let mia = abierta + "\nMás detalle escrito en el editor.\n"
        // Fuera (otra regla, Obsidian, un asistente) solo cambia el estado.
        let fuera = abierta.replacingOccurrences(of: "estado: Por hacer", with: "estado: En curso")
        e.escribir(Self.tarea, fuera)
        let r = try await bus.ejecutar(.guardarNota(path, base: abierta, texto: mia), autor: Self.manu)
        #expect(r.hecho)
        #expect(e.texto(Self.tarea) == mia.replacingOccurrences(of: "estado: Por hacer", with: "estado: En curso"))
        #expect(bus.writer.conflicts.pendientes().isEmpty)
        // Fuera se añadió Actividad (un asistente) mientras yo cambiaba la descripción: también.
        let abierta2 = try #require(e.texto(Self.tarea))
        let mia2 = abierta2.replacingOccurrences(of: "Más detalle", with: "Mucho más detalle")
        let actividad = abierta2 + "\n## Actividad\n\n### 2026-10-22 10:00 · agente:comercial\nPreparé la agenda.\n"
        e.escribir(Self.tarea, actividad)
        let r2 = try await bus.ejecutar(.guardarNota(path, base: abierta2, texto: mia2), autor: Self.manu)
        #expect(r2.hecho)
        #expect(e.texto(Self.tarea) == mia2 + "\n## Actividad\n\n### 2026-10-22 10:00 · agente:comercial\nPreparé la agenda.\n")
        // Guardar sin cambios fuera: compare-and-swap normal.
        let abierta3 = try #require(e.texto(Self.tarea))
        let r3 = try await bus.ejecutar(.guardarNota(path, base: abierta3, texto: abierta3 + "Fin.\n"), autor: Self.manu)
        #expect(r3.hecho)
        // Los asistentes no usan el guardado del editor.
        await esperaErrorAsync(.noPermitidoAsistente(Self.tarea)) {
            try await bus.ejecutar(.guardarNota(path, base: abierta3, texto: "x"), autor: .agente("comercial"))
        }
    }

    @Test func cuerpoDeLaPersonaContraCambioExterno() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let path = VaultPath(Self.tarea)
        let base = ContentHash.of(try #require(e.datos(Self.tarea)))
        e.escribir(Self.tarea, e.texto(Self.tarea)! + "Fuera.\n")
        let r = try await bus.ejecutar(.sustituirCuerpo(path, cuerpo: "\nCuerpo nuevo.\n", baseHash: base), autor: Self.manu)
        let tarjeta = try #require(r.conflicto)
        #expect(e.texto(Self.tarea)?.hasSuffix("Fuera.\n") == true)
        // Combinar a mano: el texto final manda y la versión propia se guarda.
        let final = e.texto(Self.tarea)!.replacingOccurrences(of: "Fuera.\n", with: "Fuera y dentro.\n")
        let res = try await bus.resolverConflicto(tarjeta.id, eleccion: .combinada(final), autor: Self.manu)
        #expect(res.hecho)
        #expect(e.texto(Self.tarea) == final)
        #expect(res.creadas.count == 1)
    }

    // MARK: Duplicados

    @Test func duplicadosComoTarjetas() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let opo = "2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md"
        let original = try #require(e.texto(opo))
        // iCloud dejó «X 2.md»: mismo id, contenido distinto.
        e.escribir("2 · Ventas/Oportunidades/web-ferreteria-ejemplo 2.md", original.replacingOccurrences(of: "valor: 1200", with: "valor: 1300"))
        // Una copia idéntica sin id y un «X 2» que no es duplicado (otro id).
        e.escribir("1 · Dirección/Rumbo 2.md", e.texto("1 · Dirección/Rumbo.md")!)
        e.escribir("1 · Dirección/Decisiones 2.md", "---\nid: otra\n---\nOtra cosa\n")
        e.escribir("Archivo/2025/Propuesta antigua 2.md", e.texto("Archivo/2025/Propuesta antigua.md")!)
        let detector = DuplicateDetector(root: e.root)
        let dups = detector.scan()
        #expect(dups.map(\.duplicado.raw) == ["1 · Dirección/Rumbo 2.md", "2 · Ventas/Oportunidades/web-ferreteria-ejemplo 2.md"])
        #expect(dups.first { $0.duplicado.raw.hasPrefix("2 ·") }?.id == "6f1c2a9e-0000-4000-8000-000000000001")
        #expect(dups.first { $0.duplicado.raw.hasPrefix("1 ·") }?.identicos == true)
        #expect(detector.scan(paths: [VaultPath("1 · Dirección/Rumbo 2.md"), VaultPath("1 · Dirección/Decisiones 2.md")]).count == 1)
        let tarjetas = try detector.registrar(dups, en: bus.writer.conflicts)
        // Registrar dos veces no repite tarjetas.
        _ = try detector.registrar(detector.scan(), en: bus.writer.conflicts)
        #expect(bus.writer.conflicts.pendientes().count == 2)
        let t = try #require(tarjetas.first { $0.ruta.raw == opo })
        // Apartar el duplicado: va a Archivo/Duplicados con su ruta; nada se borra.
        let r = try await bus.descartarDuplicado(t.id, autor: Self.manu)
        #expect(r.movidas.first?.a.raw == "Archivo/Duplicados/2 · Ventas/Oportunidades/web-ferreteria-ejemplo 2.md")
        #expect(e.texto(opo) == original)
        #expect(e.texto("Archivo/Duplicados/2 · Ventas/Oportunidades/web-ferreteria-ejemplo 2.md")?.contains("valor: 1300") == true)
        // Quedarse con el duplicado: el original se aparta y el duplicado toma su nombre.
        let t2 = try #require(tarjetas.first { $0.ruta.raw == "1 · Dirección/Rumbo.md" })
        let rumbo2 = e.datos("1 · Dirección/Rumbo 2.md")
        _ = try await bus.descartarDuplicado(t2.id, quedarmeConElDuplicado: true, autor: Self.manu)
        #expect(e.datos("1 · Dirección/Rumbo.md") == rumbo2 && !e.existe("1 · Dirección/Rumbo 2.md"))
        #expect(e.existe("Archivo/Duplicados/1 · Dirección/Rumbo.md"))
        #expect(bus.writer.conflicts.pendientes().isEmpty)
    }

    // MARK: iCloud

    final class VersionesFalsas: ConflictVersionProvider, @unchecked Sendable {
        let lock = NSLock()
        var versiones: [String: [ConflictVersionInfo]] = [:]
        var resueltas: [String] = []
        func unresolvedVersions(of url: URL) -> [ConflictVersionInfo] { lock.withLock { versiones[url.lastPathComponent] ?? [] } }
        func markResolved(_ url: URL) throws { lock.withLock { resueltas.append(url.lastPathComponent); versiones[url.lastPathComponent] = nil } }
    }

    @Test func conflictosDeICloud() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let falsas = VersionesFalsas()
        falsas.versiones["Rumbo.md"] = [ConflictVersionInfo(data: Data("# Rumbo del otro Mac\n".utf8), equipo: "MacBook de Manu", fecha: nil)]
        let rumbo = VaultPath("1 · Dirección/Rumbo.md")
        let tarjetas = try ICloudConflicts.scan([rumbo, VaultPath("1 · Dirección/Decisiones.md")], root: e.root,
                                                registry: bus.writer.conflicts, provider: falsas)
        #expect(tarjetas.count == 1)
        let t = try #require(tarjetas.first)
        #expect(t.tipo == .icloud && t.versiones.map(\.etiqueta) == ["La de ahora", "Versión de MacBook de Manu"])
        // Volver a mirar no repite la tarjeta.
        _ = try ICloudConflicts.scan([rumbo], root: e.root, registry: bus.writer.conflicts, provider: falsas)
        #expect(bus.writer.conflicts.pendientes().count == 1)
        // Me quedo con la del otro Mac: la actual va a Archivo/Conflictos.
        let actual = e.texto(rumbo.raw)
        let r = try await bus.resolverICloud(t.id, quedarmeCon: 0, provider: falsas, autor: Self.manu)
        #expect(e.texto(rumbo.raw) == "# Rumbo del otro Mac\n")
        #expect(r.creadas.count == 1 && e.texto(r.creadas[0].raw) == actual)
        #expect(falsas.resueltas == ["Rumbo.md"])
        #expect(bus.writer.conflicts.pendientes().isEmpty)
    }
}
