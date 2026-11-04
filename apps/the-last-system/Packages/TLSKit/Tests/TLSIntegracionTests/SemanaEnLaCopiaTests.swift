import Foundation
import Testing
@testable import TLSAgents
@testable import TLSCore
@testable import TLSIntegracion
import TLSMCPHost
@testable import TLSUI

/// PLAN §10, «Escenario de punta a punta final» («una semana en la copia»), sobre una **copia temporal** de Asesoría
/// Ribera abierta como en la app, con los asistentes simulados (`SimulatedRuntime`, cada herramienta se ejecuta de verdad
/// por `tls-mcp`) y el reloj del motor inyectado: importar un extracto → conciliar → cobro confirmado (el clic de la
/// persona) → Ganada y proyecto → tareas de la plantilla → kit del Implementador → resumen del lunes de Mika → decisión
/// registrada → Bitácora del mes coherente con la Actividad.
@Suite("Una semana en la copia (PLAN §10)", .serialized)
@MainActor
struct SemanaEnLaCopiaTests {
    static let extracto = "4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/Extractos/2026-10-19 cuenta-corriente-2026-07-a-10.csv"
    static let pagos = "4 · Finanzas/Registros/pagos.csv"
    static let opoJorge = "2 · Ventas/Oportunidades/jorge-martin-trimestrales.md"
    static let proyectos = "3 · Entrega/Proyectos/"
    static let t1 = "1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md"
    static let registro = "1 · Dirección/Decisiones.md"

    /// El kit de la primera sesión que prepara el Implementador (grabación de la prueba: un comentario en la tarea).
    static func grabacionKit() -> [String] {
        [
            FlujoF4.inicio(),
            FlujoF4.herramienta("tls_comentar", id: "k1", entrada: [
                "tarea": "{{tarea}}",
                "texto": "Kit de la sesión S1 (simulado): orden del día (bienvenida, calendario fiscal, accesos), lo que trae el cliente (certificado digital y últimas declaraciones) y lo pendiente (nada).",
            ]),
            FlujoF4.resultadoHerramienta(id: "k1", texto: "{}"),
            FlujoF4.herramienta("tls_finalizar", id: "k2", entrada: ["resumen": "Kit de la S1 preparado en la primera tarea del proyecto."]),
            FlujoF4.resultadoHerramienta(id: "k2", texto: "{}"),
            FlujoF4.resultado("Kit de la S1 preparado."),
        ]
    }

    @Test("Extracto → conciliación → cobro con tu clic → Ganada y proyecto → tareas → kit → resumen del lunes → decisión → Bitácora coherente")
    func unaSemana() async throws {
        let grabaciones = try EntornoF4.grabaciones(["implementador-preparar-kit": Self.grabacionKit()])
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        let domingo = EntornoF4.fecha(18, 10, 0)
        try await EntornoF4.con(clase: .copia, inicio: domingo, runtime: { puerta in
            SimulatedRuntime(grabaciones: grabaciones, servidor: puerta)
        }) { e in
            let sesion = try #require(e.sesion)
            let host = try #require(e.host)
            try await e.esperarTrabajos(segundos: 60)

            // 1. Importar el extracto (dos movimientos nuevos): importar no confirma nada.
            let finanzas = ModeloFinanzas(sesion: sesion)
            await finanzas.cargar()
            let original = try Data(contentsOf: e.carpeta.appendingPathComponent(Self.extracto))
            let nuevo = String(decoding: original, as: UTF8.self)
                + "19/10/2026;19/10/2026;RECIBO MODELO 111 AEAT;-120,00;19544,65\n"
                + "19/10/2026;19/10/2026;TRANSFERENCIA DE CLIENTE NUEVO;300,00;19844,65\n"
            await finanzas.previsualizar(datos: Data(nuevo.utf8), nombre: "cuenta-corriente-hasta-19-oct.csv")
            #expect(finanzas.vista?.resumen == "31 movimientos · 2 nuevos · 29 ya importados")
            let pagosAntes = e.texto(Self.pagos)
            #expect(await finanzas.importar(deshacer: nil))
            #expect(e.texto(Self.pagos) == pagosAntes)
            // El Contable atiende `extracto.importado` (simulado): propone, pero no confirma nada.
            try await e.esperarTrabajos(segundos: 60)
            #expect(e.texto(Self.pagos) == pagosAntes)

            // 2–3. Conciliar: la propuesta exacta del cobro de Jorge, confirmada con el clic → Ganada y un proyecto.
            await finanzas.cargar(forzar: true)
            let p = try #require(finanzas.lectura?.propuestas.first { $0.factura.id == "F-2026-0007" })
            #expect(p.exacta)
            #expect(await finanzas.confirmar(p, deshacer: nil))
            #expect(e.texto(Self.opoJorge)?.contains("estado: Ganada") == true)
            let proyectos = e.foto().notes.map(\.raw).filter { $0.hasPrefix(Self.proyectos) && $0.hasSuffix("/Proyecto.md") }
            #expect(proyectos.count == 1)
            let proyecto = try #require(proyectos.first)

            // 4. Las tareas de la plantilla del proyecto, en días laborables.
            let carpetaTareas = (VaultPath(proyecto).parent ?? .root).appending("Tareas").raw + "/"
            let tareas = e.foto().notes.map(\.raw).filter { $0.hasPrefix(carpetaTareas) }.sorted()
            #expect(!tareas.isEmpty)
            for t in tareas {
                if let texto = NoteDocument(text: e.texto(t) ?? "").frontmatter.text("planificada"), let dia = LocalDate(parsing: texto) {
                    #expect(dia.weekday >= 1 && dia.weekday <= 5, "\(t) cae en fin de semana: \(dia)")
                }
            }
            // El Implementador atiende `proyecto.creado` (simulado).
            try await e.esperarTrabajos(segundos: 60)

            // 5. El kit del Implementador (Entrega está activa en Ribera; simulado): en la primera tarea del proyecto.
            let primera = try #require(tareas.first)
            let kit = try #require(try await host.pedir(a: "implementador", instruccion: "Prepara el kit de la S1.",
                                                        tarea: VaultPath(primera), accion: "preparar-kit"))
            try await e.esperarTrabajos(segundos: 60)
            #expect(await host.ejecuciones().first { $0.id == kit.id }?.estado == .completada)
            let textoPrimera = try #require(e.texto(primera))
            #expect(textoPrimera.contains("Kit de la sesión S1 (simulado)"))
            #expect(textoPrimera.contains("agente:implementador"))

            // 6. El lunes a las 08:05: el resumen de la semana de Mika (su rutina; simulado).
            e.reloj.fijar(EntornoF4.fecha(19, 8, 5))
            _ = await host.revisar()
            await host.cola.procesar()
            try await e.esperarTrabajos(segundos: 60)
            let resumen = try #require(await host.ejecuciones(limite: 500).first {
                $0.agente == "mika" && $0.disparo.rutina == "resumen-semana"
            })
            #expect(resumen.estado == .completada)
            try await esperar("el resumen en la Bitácora", segundos: 15) { e.bitacora().contains(resumen.id) }

            // 7. Una decisión registrada: una línea en Decisiones.md con su origen y la tarea cerrada.
            let hoy = AlmacenHoy.de(sesion)
            await hoy.actualizar(forzar: true)
            let datos = try #require(hoy.datos)
            let tarjeta = try #require(datos.decisiones.first { $0.ruta?.raw == Self.t1 })
            let registroAntes = e.texto(Self.registro) ?? ""
            #expect(await Decidir.decidir(tarjeta, opcion: nil, texto: "Subir Trimestrales a 165 € desde T1 2027",
                                          porque: "Clínica y Panadería valoran el trato", sesion: sesion))
            let registro = try #require(e.texto(Self.registro))
            let nuevas = registro.components(separatedBy: "\n").filter { !registroAntes.components(separatedBy: "\n").contains($0) }
            #expect(nuevas.count == 1)
            #expect(nuevas.first?.contains("(T-0001)") == true)
            #expect(e.texto(Self.t1)?.contains("estado: Hecha") == true)

            // 8. La Bitácora del mes, coherente con la Actividad.
            try await e.esperarTrabajos(segundos: 60)
            let lineas = Bitacora.leer(e.bitacora())
            let trabajos = await host.ejecuciones(limite: 2000).filter { $0.estado.esFinal }
            #expect(trabajos.count >= 3)
            // a) Cada trabajo terminado tiene su línea (con su ejecución) en la Bitácora.
            for t in trabajos where t.estado == .completada {
                #expect(lineas.contains { $0.ejecucion == t.id && $0.agente == t.agente }, "Sin línea de Bitácora: \(t.agente) \(t.id)")
            }
            // b) Cada línea con ejecución es de un trabajo que existió, del mismo asistente, y del mes.
            let porId = Dictionary(trabajos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for l in lineas {
                #expect(l.fecha.year == 2026 && l.fecha.month == 10)
                if let id = l.ejecucion, id.hasPrefix("r-") || porId[id] != nil {
                    #expect(porId[id]?.agente == l.agente, "Línea de \(l.agente) con una ejecución que no es suya: \(id)")
                }
            }
            // c) Cada entrada de Actividad de un asistente en las fichas tiene su asistente en la Bitácora del mes.
            let f = e.foto()
            var conActividad = Set<String>()
            for n in f.notes where !n.raw.hasPrefix("Archivo/") {
                guard let t = f.text(n), t.contains("## Actividad") else { continue }
                for m in t.matches(of: /### 2026-10-\d\d[^\n]*· agente:([a-z]+)/) { conActividad.insert(String(m.1)) }
            }
            #expect(conActividad.contains("implementador"))
            let enBitacora = Set(lineas.map(\.agente))
            #expect(conActividad.isSubset(of: enBitacora), "Actividad sin Bitácora: \(conActividad.subtracting(enBitacora))")
        }
    }
}
