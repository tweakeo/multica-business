import Foundation
import Testing
@testable import TLSCore

/// Criterio F1 4: si el proceso muere a mitad de una escritura (`kill -9`), no hay ficheros
/// truncados, la copia previa existe y al volver a abrir no aparecen falsos conflictos.
/// La muerte se simula parando el escritor en seco tras escribir el temporal (o tras un paso):
/// no limpia, no revierte y suelta el cerrojo, como haría el sistema.
@Suite(.serialized) struct EscrituraRecuperacionTests {
    static let manu = Autor.persona("Manu")
    static let rumbo = VaultPath("1 · Dirección/Rumbo.md")
    static let decisiones = VaultPath("1 · Dirección/Decisiones.md")

    @Test func muereTrasElTemporal() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let w = try await e.writer()
        let bus = CommandBus(writer: w)
        let antes = try #require(e.texto(Self.rumbo.raw))
        let huellaAntes = e.huella()
        await w.setFault(.trasTemporal(0))
        await esperaErrorAsync(.interrumpido) {
            try await bus.ejecutar(.anadirLinea(Self.rumbo, linea: "Nueva línea."), autor: Self.manu)
        }
        // El fichero sigue entero (ni truncado ni a medias) y no hay restos en la carpeta
        // (solo la ficha del escritor, que se toma antes de escribir).
        #expect(e.texto(Self.rumbo.raw) == antes)
        var huellaTras = e.huella()
        #expect(huellaTras.removeValue(forKey: ".tls/escritor.json") != nil)
        #expect(huellaTras == huellaAntes)
        // La copia previa existe y el plan está pendiente en el diario.
        let copias = e.state.appendingPathComponent("copias")
        let dia = try #require(try FileManager.default.contentsOfDirectory(atPath: copias.path).first)
        let plan = try #require(try FileManager.default.contentsOfDirectory(atPath: copias.appendingPathComponent(dia).path).first)
        #expect(try String(contentsOf: copias.appendingPathComponent("\(dia)/\(plan)/\(Self.rumbo.raw)"), encoding: .utf8) == antes)
        let diario = try String(contentsOf: e.state.appendingPathComponent("diario.jsonl"), encoding: .utf8)
        #expect(diario.contains("\"estado\":\"pendiente\"") && !diario.contains("\"estado\":\"hecho\""))
        // El escritor «muerto» ya no hace nada.
        await esperaErrorAsync(.interrumpido) {
            try await bus.ejecutar(.anadirLinea(Self.rumbo, linea: "Otra."), autor: Self.manu)
        }
        // Al volver a abrir: el fichero estaba como antes, así que se aplica. Sin conflictos.
        let w2 = try await e.writer()
        let informe = await w2.lastRecovery
        #expect(informe.aplicados == 1 && informe.conflictos.isEmpty)
        #expect(w2.conflicts.pendientes().isEmpty)
        #expect(e.texto(Self.rumbo.raw) == antes + "Nueva línea.\n")
        let diario2 = try String(contentsOf: e.state.appendingPathComponent("diario.jsonl"), encoding: .utf8)
        #expect(diario2.contains("\"estado\":\"hecho\""))
        // Se puede deshacer como cualquier otro plan.
        _ = try await CommandBus(writer: w2).deshacer(autor: Self.manu)
        #expect(e.texto(Self.rumbo.raw) == antes)
    }

    @Test func muereEntreDosFicheros() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let w = try await e.writer()
        let plan = WritePlan(autor: Self.manu, descripcion: "Dos notas", ops: [
            .appendLine(Self.rumbo, line: "Rumbo nuevo."), .appendLine(Self.decisiones, line: "- 2026-10-22 · Decidido")])
        await w.setFault(.trasPaso(0))
        await esperaErrorAsync(.interrumpido) { try await CommandBus(writer: w).ejecutar(plan) }
        // Decisiones (paso 0) quedó escrita; Rumbo (paso 1), no.
        #expect(e.texto(Self.decisiones.raw)?.hasSuffix("- 2026-10-22 · Decidido\n") == true)
        #expect(e.texto(Self.rumbo.raw)?.contains("Rumbo nuevo.") == false)
        let w2 = try await e.writer()
        let informe = await w2.lastRecovery
        #expect(informe.aplicados == 1 && informe.conflictos.isEmpty)
        #expect(e.texto(Self.rumbo.raw)?.hasSuffix("Rumbo nuevo.\n") == true)
        // Ya escrito del todo antes de marcarlo: se reconoce como hecho sin escribir nada.
        let f = EntornoEscritura()
        defer { f.limpiar() }
        let wf = try await f.writer()
        await wf.setFault(.antesDeHecho)
        await esperaErrorAsync(.interrumpido) { try await CommandBus(writer: wf).ejecutar(plan) }
        let huella = f.huella()
        let wf2 = try await f.writer()
        let informeF = await wf2.lastRecovery
        #expect(informeF.completados == 1 && informeF.aplicados == 0 && informeF.conflictos.isEmpty)
        #expect(f.huella() == huella)
    }

    /// Si lo cambian fuera entre la muerte y el arranque, no se pisa: tarjeta con las dos versiones.
    @Test func cambioDeFueraTrasLaMuerteEsConflicto() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let w = try await e.writer()
        await w.setFault(.trasTemporal(0))
        await esperaErrorAsync(.interrumpido) {
            try await CommandBus(writer: w).ejecutar(.anadirLinea(Self.rumbo, linea: "De la app."), autor: Self.manu)
        }
        let antes = try #require(e.texto(Self.rumbo.raw))
        e.escribir(Self.rumbo.raw, "# Rumbo\n\nEscrito en Obsidian.\n")
        let w2 = try await e.writer()
        let informe = await w2.lastRecovery
        #expect(informe.conflictos.count == 1)
        #expect(e.texto(Self.rumbo.raw) == "# Rumbo\n\nEscrito en Obsidian.\n")
        let tarjeta = try #require(w2.conflicts.pendientes().first)
        #expect(tarjeta.tipo == .recuperacion && tarjeta.ruta == Self.rumbo)
        let iba = try #require(tarjeta.versiones.first { $0.etiqueta == "Lo que iba a guardar la app" })
        #expect(w2.conflicts.datos(de: iba, root: e.root) == Data((antes + "De la app.\n").utf8))
        // Quedarse con la de la app: la de Obsidian va a Archivo/Conflictos (nada se pierde).
        let r = try await CommandBus(writer: w2).resolverConflicto(tarjeta.id, eleccion: .mia, autor: Self.manu)
        #expect(r.hecho)
        #expect(e.texto(Self.rumbo.raw) == antes + "De la app.\n")
        let archivada = try #require(r.creadas.first)
        #expect(archivada.raw.hasPrefix("Archivo/Conflictos/1 · Dirección/Rumbo (versión de fuera "))
        #expect(e.texto(archivada.raw) == "# Rumbo\n\nEscrito en Obsidian.\n")
        #expect(w2.conflicts.pendientes().isEmpty)
    }

    /// Muertes en puntos al azar de planes al azar: nunca un fichero a medias, nunca un falso
    /// conflicto, y al reabrir la carpeta queda igual que si nada hubiera fallado.
    @Test func muertesAlAzar() async throws {
        var g = Semilla(2026)
        let lucia = VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")
        let planes: [[WriteOp]] = [
            [.appendLine(Self.rumbo, line: "Una.")],
            [.appendLine(Self.rumbo, line: "Una."), .appendLine(Self.decisiones, line: "- Otra")],
            [.move(lucia, to: VaultPath("2 · Ventas/Contactos/lucia-prueba.md")),
             .mergeFrontmatter(VaultPath("2 · Ventas/Contactos/lucia-prueba.md"), set: [Property(key: "aliases", value: .list(["Lucía Prueba"]))], unset: []),
             .appendLine(VaultPath("2 · Ventas/Contactos/José Núñez.md"), line: "Enlace a [[lucia-prueba]].")],
            [.create(VaultPath("2 · Ventas/Tareas/t-0002-llamar.md"), text: "---\ntls_type: task\n---\n"),
             .upsertCSVRow(VaultPath("4 · Finanzas/Registros/emitidas.csv"), row: ["id": "F-2026-003", "importe": "10.00"], key: "id")],
            [.move(VaultPath("2 · Ventas/Empresas"), to: VaultPath("2 · Ventas/Clientes")),
             .appendToSection(VaultPath("2 · Ventas/Clientes/Ferretería Ejemplo.md"), section: "Actividad", text: "### hoy · Manu\nMovida.")],
            [.move(Self.rumbo, to: VaultPath("1 · Dirección/RUMBO.md")), .appendLine(VaultPath("1 · Dirección/RUMBO.md"), line: "Más.")],
        ]
        for vuelta in 0..<36 {
            let ops = planes[vuelta % planes.count]
            let faults: [VaultWriter.FaultPoint] = (0..<ops.count + 1).flatMap { [.trasTemporal($0), .trasPaso($0)] } + [.antesDeHecho]
            let fault = faults.aleatorio(&g)
            // Lo esperado: el mismo plan sin fallos.
            let gemelo = EntornoEscritura()
            defer { gemelo.limpiar() }
            let base = gemelo.huella()
            _ = try await CommandBus(writer: try await gemelo.writer()).ejecutar(WritePlan(autor: Self.manu, descripcion: "x", ops: ops))
            var esperado = gemelo.huella()
            esperado.removeValue(forKey: ".tls/escritor.json")

            let e = EntornoEscritura()
            defer { e.limpiar() }
            let w = try await e.writer()
            await w.setFault(fault)
            do {
                _ = try await CommandBus(writer: w).ejecutar(WritePlan(autor: Self.manu, descripcion: "x", ops: ops))
            } catch WriteError.interrumpido {}
            // Justo tras morir: cada fichero tiene un contenido completo (el de antes o el que debía
            // quedar), nunca uno a medias.
            let completos = Set(base.values).union(esperado.values)
            for (path, hash) in e.huella() where path != ".tls/escritor.json" {
                #expect(completos.contains(hash), "vuelta \(vuelta) \(fault): \(path)")
            }
            let w2 = try await e.writer()
            let informe = await w2.lastRecovery
            #expect(informe.conflictos.isEmpty, "vuelta \(vuelta) \(fault)")
            var final = e.huella()
            final.removeValue(forKey: ".tls/escritor.json")
            #expect(final == esperado, "vuelta \(vuelta) \(fault)")
            await w2.close()
        }
    }

    /// Una línea del diario cortada a medias (el proceso murió escribiéndola) no estropea nada.
    @Test func diarioConLineaCortada() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let w = try await e.writer()
        _ = try await CommandBus(writer: w).ejecutar(.anadirLinea(Self.rumbo, linea: "Uno."), autor: Self.manu)
        await w.close()
        let diario = e.state.appendingPathComponent("diario.jsonl")
        let h = try FileHandle(forWritingTo: diario)
        try h.seekToEnd()
        try h.write(contentsOf: Data(#"{"tipo":"plan","id":"cortad"#.utf8))
        try h.close()
        let w2 = try await e.writer()
        #expect(await w2.lastRecovery.conflictos.isEmpty)
        let r = try await CommandBus(writer: w2).ejecutar(.anadirLinea(Self.rumbo, linea: "Dos."), autor: Self.manu)
        #expect(r.hecho)
        let lineas = try String(contentsOf: diario, encoding: .utf8).split(separator: "\n")
        #expect(lineas.filter { $0.contains("cortad") }.count == 1)
        #expect(lineas.last?.hasPrefix("{") == true)
        // Y se puede deshacer lo último.
        _ = try await CommandBus(writer: w2).deshacer(autor: Self.manu)
        #expect(e.texto(Self.rumbo.raw)?.hasSuffix("Uno.\n") == true)
    }
}
