import Foundation
import Testing
@testable import TLSCore

@Suite("Gobierno · borradores, Bitácora y Actividad", .serialized)
struct BitacoraYBorradoresTests {
    @Test("Un borrador vive en N · Área/Borradores/<slug>.md, sin fecha, y su versión no cambia con el espejo")
    func borrador() throws {
        let layout = VaultLayout.humana
        let b = NuevoBorrador(accion: .enviarCorreo, area: .ventas, asunto: "Seguimiento día 7", cuerpo: "Hola:\n\nTexto.",
                              para: ["a@example.com", "b@example.com"], paraTi: "Por qué lo preparo.", ejecucion: "r-1")
        let (ruta, plan) = Borradores.plan(b, layout: layout, autor: .agente("comercial"))
        #expect(ruta == VaultPath("2 · Ventas/Borradores/seguimiento-dia-7.md"))
        #expect(plan.autor == .agente("comercial") && plan.ops.count == 1)
        guard case .create(_, let datos) = plan.ops[0] else { Issue.record("Debía crear"); return }
        let texto = String(decoding: datos, as: UTF8.self)
        let leido = try #require(Borrador.leer(ruta, texto: texto, layout: layout))
        #expect(leido.accion == .enviarCorreo && leido.tipo == "correo" && leido.estado == .borrador)
        #expect(leido.para == ["a@example.com", "b@example.com"] && leido.asunto == "Seguimiento día 7")
        #expect(leido.cuerpo == "Hola:\n\nTexto." && leido.creadoPor == "agente:comercial" && leido.asistente == "comercial")
        // El espejo no cambia la versión; cambiar el texto, sí.
        var doc = FrontmatterDocument(text: texto)
        doc.merge(set: [Property(key: "estado", value: .text("Pendiente de tu OK")), Property(key: "aprobacion", value: .text("apr-1"))], unset: [])
        #expect(Borrador.version(doc.text) == leido.version)
        #expect(Borrador.version(texto.replacingOccurrences(of: "Texto.", with: "Texto!")) != leido.version)
        #expect(Borradores.esRutaDeBorrador(ruta, layout: layout))
        #expect(!Borradores.esRutaDeBorrador(VaultPath("Borradores/x.md"), layout: layout))
    }

    @Test("La línea de la Bitácora es la del PLAN §4.4 y se vuelve a leer igual")
    func lineaBitacora() throws {
        let l = LineaBitacora(fecha: LocalDate(parsing: "2026-10-21")!, hora: "10:32", agente: "agente:comercial", capacidad: "VEN-08",
                              que: "Preparó seguimiento para nexo-estudio", resultado: "pendiente de aprobación", usoUSD: 0.04,
                              ejecucion: "r-7f3a", hash: "abc")
        #expect(l.texto == #"- 2026-10-21 10:32 · agente:comercial · VEN-08 · Preparó seguimiento para nexo-estudio · pendiente de aprobación · uso 0,04 USD <!-- tls:audit {"hash":"abc","run":"r-7f3a"} -->"#)
        #expect(LineaBitacora.leer(l.texto) == l)
        let sin = LineaBitacora(fecha: LocalDate(parsing: "2026-10-21")!, hora: "11:00", agente: "mika", que: "Revisó: nada en rojo · ok",
                                resultado: "hecho")
        #expect(sin.texto == "- 2026-10-21 11:00 · agente:mika · Revisó: nada en rojo, ok · hecho")
        #expect(LineaBitacora.leer(sin.texto)?.que == "Revisó: nada en rojo, ok")
        #expect(Bitacora.ruta(LocalDate(parsing: "2026-10-21")!, layout: .humana) == VaultPath("6 · Equipo/Bitácora/2026-10.md"))
        // Las líneas de antes, sin «agente:», también se leen.
        let vieja = try #require(LineaBitacora.leer("- 2026-10-15 09:00 · mika · DIR-02 · revisé la semana · hecho · uso 1,50 USD"))
        #expect(vieja.agente == "mika" && vieja.capacidad == "DIR-02" && vieja.usoUSD == 1.5)
    }

    @Test("Al cerrar un trabajo: una entrada en la Actividad de la tarea y una línea en la Bitácora, en un solo plan de la app")
    func cierreDeTrabajo() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, _) = try await e.gobierno()
        // Un comentario escrito a mano debajo de la última entrada (en Obsidian).
        e.escribir(EntornoGobierno.tareaPath.raw, EntornoGobierno.tarea + "Ojo, llama por la tarde.\n")
        let r = ResumenDeTrabajo(ejecucion: "r-7f3a", agente: "comercial", tarea: EntornoGobierno.tareaPath, capacidad: "VEN-08",
                                 texto: "Preparé el seguimiento del día 7: [borrador](../Borradores/seguimiento.md). Pendiente de tu OK en Decisiones.",
                                 fin: .pendienteDeAprobacion, estadoDe: "Por hacer", estadoA: .enRevision, costeUSD: 0.04,
                                 aprobacion: "apr-91c2", hash: "h1")
        let plan = try ActividadDeAsistente.plan(r, snapshot: e.foto())
        #expect(plan.autor == .sistema)
        #expect(try await bus.ejecutar(plan).hecho)
        let texto = try #require(e.texto(EntornoGobierno.tareaPath.raw))
        #expect(texto.contains("### 2026-10-19 ") && texto.contains(" · agente:comercial\nEstado: Por hacer → En revisión. Preparé el seguimiento"))
        #expect(texto.contains("· Manu\nOjo, llama por la tarde."), "el comentario a mano recibe su encabezado, sin tocar su texto")
        #expect(texto.contains(#""coste_usd":0.04"#) && texto.contains(#""run":"r-7f3a""#) && texto.contains(#""aprobacion":"apr-91c2""#))
        #expect(e.foto().frontmatter(EntornoGobierno.tareaPath).text("estado") == "En revisión")
        let bit = try #require(e.texto("6 · Equipo/Bitácora/2026-10.md"))
        #expect(bit.contains("tls_type: log") && bit.contains("## 2026-10-19"))
        let lineas = Bitacora.leer(bit)
        #expect(lineas.count == 1 && lineas[0].agente == "comercial" && lineas[0].resultado == "pendiente de aprobación")
        #expect(lineas[0].que == "Preparé el seguimiento del día 7: [borrador](../Borradores/seguimiento.md)" && lineas[0].usoUSD == 0.04)
        // Otro trabajo el mismo día: se añade bajo el mismo día.
        let otro = ResumenDeTrabajo(ejecucion: "r-2", agente: "mika", texto: "Revisé: nada en rojo.", fin: .hecho)
        #expect(try await bus.ejecutar(try ActividadDeAsistente.plan(otro, snapshot: e.foto())).hecho)
        #expect(Bitacora.leer(e.texto("6 · Equipo/Bitácora/2026-10.md")!).count == 2)
        // Se deshace.
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(Bitacora.leer(e.texto("6 · Equipo/Bitácora/2026-10.md")!).count == 1)
        // Nunca deja una tarea Hecha ni Cancelada.
        var cerrar = r
        cerrar.estadoA = .hecha
        #expect(throws: TareaError.noPermitidoAgente("Hecha")) { try ActividadDeAsistente.plan(cerrar, snapshot: e.foto()) }
        // Lo privado no existe.
        var priv = r
        priv.tarea = EntornoGobierno.privada
        #expect(throws: ErrorDeGobierno.self) { try ActividadDeAsistente.plan(priv, snapshot: e.foto()) }
    }
}

@Suite("Gobierno · presupuesto de interrupciones", .serialized)
struct PresupuestoTests {
    static func tarjeta(_ id: String, dia: LocalDate, roja: Bool = false) -> TarjetaDecision {
        TarjetaDecision(id: id, tipo: .pregunta, prioridad: roja ? .roja : .normal, motivo: nil, titulo: id, problema: nil,
                        opciones: [], porque: nil, ruta: nil, conflicto: nil, area: nil, responsable: nil, creada: dia, vence: nil)
    }

    @Test("F4-8 · 14 días con muchas tarjetas: como mucho 5 nuevas al día que no sean rojas; el resto, al resumen semanal")
    func catorceDias() {
        let inicio = LocalDate(parsing: "2026-10-19")!
        var todas: [TarjetaDecision] = []
        for d in 0..<14 {
            let dia = inicio.adding(days: d)
            for n in 0..<(4 + d % 6) { todas.append(Self.tarjeta("t-\(d)-\(n)", dia: dia)) }
            if d % 5 == 0 { todas.append(Self.tarjeta("roja-\(d)", dia: dia, roja: true)) }
        }
        let b = BandejaDeDecisiones.presupuesto(todas, tope: 5)
        let porDia = Dictionary(grouping: b.visibles.filter { $0.prioridad != .roja }, by: { $0.creada! }).mapValues(\.count)
        #expect(porDia.values.allSatisfy { $0 <= 5 })
        #expect(Double(porDia.values.reduce(0, +)) / 14 <= 5)
        #expect(b.visibles.filter { $0.prioridad == .roja }.count == 3, "las rojas, siempre")
        #expect(b.alResumen.count == todas.count - b.visibles.count && !b.alResumen.isEmpty)
        #expect(b.resumenPorGrupoF4["Preguntas"] == b.alResumen.count)
    }

    @Test("Como mucho 3 avisos al día que no sean rojos; los rojos siempre; cada tarjeta, una vez")
    func avisos() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let estado = try EstadoGobierno(directory: e.state)
        let hoy = LocalDate(parsing: "2026-10-19")!
        let tarjetas = (0..<5).map { Self.tarjeta("n-\($0)", dia: hoy) } + [Self.tarjeta("r-1", dia: hoy, roja: true)]
        let b = BandejaDeDecisiones.presupuesto(tarjetas, tope: 5)
        let p = PresupuestoDeInterrupciones(estado: estado, tope: 3)
        let primera = p.avisar(b, hoy: hoy)
        #expect(primera.filter { $0.prioridad != .roja }.count == 3 && primera.contains { $0.id == "r-1" })
        #expect(p.avisar(b, hoy: hoy).isEmpty, "ni repite ni pasa del tope")
        let manana = p.avisar(b, hoy: hoy.adding(days: 1))
        #expect(manana.count == 2, "al día siguiente, las que faltaban")
    }

    @Test("Las tarjetas que fabrica la app cuentan el día en que se vieron por primera vez")
    func primeraVez() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (_, a) = try await e.gobierno()
        _ = a.estadoDeConfig()
        e.escribir(".tls/config.yaml", e.texto(".tls/config.yaml")!.replacingOccurrences(of: "max_tareas_por_ejecucion: 2", with: "max_tareas_por_ejecucion: 3"))
        let lectura = LecturaDominio(snapshot: e.foto())
        let b1 = BandejaDeDecisiones.consultar(lectura, gobierno: .de(a), estado: a.estado)
        let t = try #require(b1.visibles.first { $0.gobierno?.clase == .cambioDePermisos })
        #expect(t.creada == lectura.hoy && t.prioridad == .alta)
        // Al día siguiente sigue naciendo el día que se vio.
        let otro = LecturaDominio(snapshot: e.foto(), reloj: Reloj(hoy: lectura.hoy.adding(days: 1)))
        let b2 = BandejaDeDecisiones.consultar(otro, gobierno: .de(a), estado: a.estado)
        #expect(b2.tarjetas.first { $0.id == t.id }?.creada == lectura.hoy)
    }
}
