import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Operación de Dirección (PLAN §6.5): el cronograma de proyectos internos por objetivo («Sin objetivo» en gris), DIR-03
/// como atención que se guarda con «Colgar de un objetivo / Seguir sin objetivo» (criterio F2-6), mover corre al lunes,
/// el mapa con el cuello, la cronología de decisiones, «Registrar decisión» y el plan de 4 semanas (con tu OK).
@Suite("Áreas · Dirección · Operación", .serialized)
@MainActor
struct DireccionOperacionTests {
    let pruebas = SesionEscrituraTests()

    @Test("Cronograma: internos de las seis áreas por objetivo, «Sin objetivo» al final y en gris; nada de entrega ni privado")
    func cronograma() throws {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        try ApoyoAreasA.preparar(carpeta)
        let d = DatosDireccion.calcular(foto: ApoyoAreasA.foto(carpeta), hoy: ApoyoAreasA.hoy)
        let c = d.cronograma
        let nombres = Set(c.barras.map(\.nombre))
        #expect(nombres == ["Guion de seguimiento", "Casos de éxito", "Manual del implementador", "Cierre trimestral T3", "Rumbo 2027"])
        #expect(!nombres.contains("Proyecto reservado"))
        #expect(!nombres.contains { $0.contains("Talleres") || $0.contains("Clínica") })
        // Grupos: cada objetivo con sus proyectos y su ritmo; «Sin objetivo» el último y en gris.
        let ultimo = try #require(c.grupos.last)
        #expect(ultimo.id == Cronograma.idSinObjetivo && ultimo.gris && ultimo.titulo == "Sin objetivo")
        #expect(Set(ultimo.barras.map(\.nombre)) == ["Manual del implementador", "Rumbo 2027"])
        let ventas = try #require(c.grupos.first { $0.titulo == "6.000 € de ventas cobradas al mes" })
        #expect(ventas.barras.map(\.nombre) == ["Guion de seguimiento"] && !ventas.gris && ventas.ritmo != nil)
        // Rumbo 2027 no tiene fechas: va aparte, no se inventan.
        #expect(c.sinFechas.map(\.nombre) == ["Rumbo 2027"])
        // La ventana va de lunes a domingo e incluye hoy.
        #expect(c.desde.weekday == 1 && c.hasta.weekday == 7 && c.desde <= ApoyoAreasA.hoy && c.hasta >= ApoyoAreasA.hoy)
        // DIR-03: el manual está en curso sin objetivo: atención con sus dos salidas.
        let manual = try #require(c.barras.first { $0.ruta == ApoyoAreasA.manual })
        let aviso = try #require(manual.atencion)
        #expect(aviso.codigo == "DIR-03" && aviso.nivel == .atencion)
        #expect(aviso.alternativas.map(\.titulo) == ["Colgar de un objetivo", "Seguir sin objetivo"])
        #expect(c.barras.filter { $0.atencion != nil }.count == 1)
        // Cifras de Control: DIR-DEC14 (sin meta en Ribera: no está en Metas.md) y DIR-OBJ, nunca un 0 inventado.
        #expect(d.cifras.map(\.codigo) == ["DIR-DEC14", "DIR-OBJ"])
        #expect(d.cifras.first { $0.codigo == "DIR-DEC14" }?.meta == "Sin meta")
        #expect(d.cifras.first { $0.codigo == "DIR-OBJ" }?.valor == "67 %")
    }

    @Test("Mover corre al lunes: arrastrar, un día laborable y cambiar el fin")
    func moverAlLunes() {
        let lunes = LocalDate(year: 2026, month: 10, day: 12)!, viernes = LocalDate(year: 2026, month: 11, day: 6)!
        // +5 días: el inicio cae en sábado y pasa al lunes 19; el fin, el miércoles 11.
        let r = Cronograma.mover(inicio: lunes, fin: viernes, dias: 5)
        #expect(r.inicio == LocalDate(year: 2026, month: 10, day: 19)! && r.fin == LocalDate(year: 2026, month: 11, day: 11)!)
        #expect(!r.inicio.isWeekend && !r.fin.isWeekend)
        // Un día antes desde un lunes es el viernes anterior (no el domingo).
        let atras = Cronograma.moverUnDia(inicio: lunes, fin: viernes, adelante: false)
        #expect(atras.inicio == LocalDate(year: 2026, month: 10, day: 9)! && atras.fin == LocalDate(year: 2026, month: 11, day: 5)!)
        let adelante = Cronograma.moverUnDia(inicio: lunes, fin: viernes, adelante: true)
        #expect(adelante.fin == LocalDate(year: 2026, month: 11, day: 9)!)
        // El fin nunca antes del inicio, y en fin de semana pasa al lunes.
        #expect(Cronograma.cambiarFin(inicio: lunes, fin: viernes, dias: -40) == lunes)
        #expect(Cronograma.cambiarFin(inicio: lunes, fin: viernes, dias: 1) == LocalDate(year: 2026, month: 11, day: 9)!)
    }

    func abrir() async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        try ApoyoAreasA.preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        return (e, sesion)
    }

    func datos(_ sesion: VaultSession) async -> DatosDireccion? {
        let carga = CargaOperacion<DatosDireccion>(sesion: sesion) { f, h in DatosDireccion.calcular(foto: f, hoy: h) }
        await carga.cargar()
        return carga.datos
    }

    @Test("DIR-03: un proyecto en curso sin objetivo se guarda y queda en atención; «Seguir sin objetivo» y «Colgar» lo quitan")
    func dir03() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        // Crear uno nuevo en curso sin objetivo: el dominio lo deja guardar (atención, no bloqueo).
        let nuevo = VaultPath("5 · Marca/Proyectos/fotos-del-equipo/Proyecto.md")
        let r = try await sesion.escribirConDominio(.crear(nuevo, texto: ApoyoAreasA.proyecto("Fotos del equipo", clase: "interno", estado: "En curso",
                                                                                              extra: "inicio: 2026-10-20\nfin: 2026-10-30\n")))
        #expect(r.invariantes.atenciones.contains { $0.codigo == "DIR-03" })
        #expect(FileManager.default.fileExists(atPath: nuevo.url(in: e.carpeta).path))
        await pruebas.esperar { sesion.revision > 0 }
        var d = try #require(await datos(sesion))
        let barra = try #require(d.cronograma.barras.first { $0.ruta == nuevo })
        #expect(barra.atencion?.alternativas.map(\.titulo) == ["Colgar de un objetivo", "Seguir sin objetivo"])
        #expect(d.cronograma.grupos.last?.barras.contains { $0.ruta == nuevo } == true)

        // «Seguir sin objetivo»: una línea nueva (sin_objetivo), deja de avisar; Deshacer deja los mismos bytes.
        let url = nuevo.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        #expect(await AccionesDireccion.seguirSinObjetivo(barra, sesion: sesion, deshacer: um) == nil)
        um.endUndoGrouping()
        let despues = try String(contentsOf: url, encoding: .utf8)
        #expect(despues.components(separatedBy: "\n").filter { !String(decoding: antes, as: UTF8.self).components(separatedBy: "\n").contains($0) }
            == ["sin_objetivo: true"])
        let rev = sesion.revision
        await pruebas.esperar { sesion.revision > rev }
        d = try #require(await datos(sesion))
        #expect(d.cronograma.barras.first { $0.ruta == nuevo }?.atencion == nil)
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)

        // «Colgar de un objetivo»: escribe el enlace y el proyecto pasa al grupo de ese objetivo.
        let objetivo = VaultPath("1 · Dirección/Objetivos/8-conversaciones-cualificadas-al-mes.md")
        let rev2 = sesion.revision
        await pruebas.esperar { sesion.revision > rev2 }
        #expect(await AccionesDireccion.colgar(barra, de: objetivo, sesion: sesion, deshacer: nil) == nil)
        let colgado = try String(contentsOf: url, encoding: .utf8)
        #expect(colgado.contains("objetivo: \"[[") && colgado.contains("8-conversaciones-cualificadas-al-mes"))
        let rev3 = sesion.revision
        await pruebas.esperar { sesion.revision > rev3 }
        d = try #require(await datos(sesion))
        let grupo = try #require(d.cronograma.grupos.first { $0.barras.contains { $0.ruta == nuevo } })
        #expect(grupo.objetivo == objetivo && !grupo.gris)
        #expect(d.cronograma.barras.first { $0.ruta == nuevo }?.atencion == nil)
    }

    @Test("Mover un proyecto escribe solo inicio y fin; si cae en sábado, el lunes")
    func moverEscribe() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let d = try #require(await datos(sesion))
        let b = try #require(d.cronograma.barras.first { $0.ruta == ApoyoAreasA.guion })
        let url = ApoyoAreasA.guion.url(in: e.carpeta)
        let antes = try String(contentsOf: url, encoding: .utf8)
        let r = Cronograma.mover(inicio: b.inicio!, fin: b.fin!, dias: 5)   // 17 oct (sábado) → lunes 19
        #expect(await AccionesDireccion.mover(b, inicio: r.inicio, fin: r.fin, sesion: sesion, deshacer: nil) == nil)
        let despues = try String(contentsOf: url, encoding: .utf8)
        #expect(ApoyoAreasA.lineasCambiadas(antes, despues) == ["inicio: 2026-10-19", "fin: 2026-11-11"])
        #expect(sesion.aviso?.texto.contains("19 oct") == true)
    }

    @Test("Registrar decisión añade una línea a Decisiones.md y se deshace")
    func registrarDecision() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let ruta = VaultPath("1 · Dirección/Decisiones.md")
        let url = ruta.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        let error = await AccionesDireccion.registrar(NuevaDecision(fecha: ApoyoAreasA.hoy, decision: "Los trimestrales suben a 165 € desde el T1 de 2027",
                                                                    porque: "Más horas por cliente", area: "Dirección"),
                                                      sesion: sesion, deshacer: um)
        um.endUndoGrouping()
        #expect(error == nil)
        let a = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n")
        let despues = try String(contentsOf: url, encoding: .utf8)
        let nuevas = despues.components(separatedBy: "\n").filter { !a.contains($0) }
        #expect(nuevas.count == 1)
        #expect(nuevas.first?.hasPrefix("- 2026-10-19 · Los trimestrales suben a 165 € desde el T1 de 2027 · Más horas por cliente · Dirección") == true)
        await pruebas.esperar { sesion.revision > 0 }
        let d = try #require(await datos(sesion))
        #expect(d.decisiones.first?.decision == "Los trimestrales suben a 165 € desde el T1 de 2027")
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("Plan de 4 semanas para el cuello: propuesta para Ventas y, con tu OK, 4 tareas planificadas en lunes en un solo paso")
    func planCuello() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let d = try #require(await datos(sesion))
        #expect(d.mapa.cuello?.area == .ventas)
        #expect(d.mapa.textoCuello.contains("Ventas"))
        let plan = try #require(d.plan)
        #expect(plan.area == .ventas && plan.semanas.count == 4)
        #expect(plan.semanas.map(\.lunes) == [26, 33, 40, 47].map { ApoyoAreasA.hoy.adding(days: $0 - 19) })
        #expect(plan.semanas.allSatisfy { $0.lunes.weekday == 1 })
        #expect(plan.semanas.last?.titulo == "Volver a diagnosticar 2 · Ventas")
        // Hasta el OK no se escribe nada.
        let tareas = e.carpeta.appendingPathComponent("2 · Ventas/Tareas")
        let antes = (try? FileManager.default.contentsOfDirectory(atPath: tareas.path)) ?? []
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        #expect(await AccionesDireccion.crearPlan(plan, semanas: Set(plan.semanas.map(\.numero)), sesion: sesion, deshacer: um) == nil)
        um.endUndoGrouping()
        let despues = try FileManager.default.contentsOfDirectory(atPath: tareas.path).filter { !antes.contains($0) }.sorted()
        #expect(despues.count == 4)
        for (i, f) in despues.enumerated() {
            let t = try String(contentsOf: tareas.appendingPathComponent(f), encoding: .utf8)
            #expect(t.contains("planificada: \(plan.semanas[i].lunes)"))
            #expect(t.contains("titulo: \"Plan del cuello · semana \(i + 1)") || t.contains("titulo: Plan del cuello · semana \(i + 1)"))
            #expect(t.contains("responsable: Manu") && t.contains("estado: Por hacer"))
        }
        // Un solo Deshacer las quita todas.
        um.undo()
        await pruebas.esperar { ((try? FileManager.default.contentsOfDirectory(atPath: tareas.path)) ?? []).count == antes.count }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: tareas.path)) ?? []).sorted() == antes.sorted())
    }

    @Test("En solo lectura no se escribe nada y se dice por qué")
    func soloLectura() async throws {
        let (e, entry) = try pruebas.entorno(clase: .copia, escritura: .bloqueada)
        defer { e.limpiar() }
        try ApoyoAreasA.preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let carga = CargaOperacion<DatosDireccion>(sesion: sesion) { f, h in DatosDireccion.calcular(foto: f, hoy: h) }
        await carga.cargar()
        #expect(carga.motivoSoloLectura != nil)
        let d = try #require(carga.datos)
        let b = try #require(d.cronograma.barras.first { $0.ruta == ApoyoAreasA.guion })
        let antes = try Data(contentsOf: ApoyoAreasA.guion.url(in: e.carpeta))
        #expect(await AccionesDireccion.mover(b, inicio: ApoyoAreasA.hoy, fin: ApoyoAreasA.hoy.adding(days: 4), sesion: sesion, deshacer: nil) != nil)
        #expect(try Data(contentsOf: ApoyoAreasA.guion.url(in: e.carpeta)) == antes)
    }
}
