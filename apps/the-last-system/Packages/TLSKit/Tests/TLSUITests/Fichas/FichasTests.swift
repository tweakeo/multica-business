import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

@Suite("Fichas · pestaña inicial y pestañas por tipo")
struct PestanaInicialTests {
    @Test("La pestaña con la que abre cada ficha según su tipo y su estado (§3.3)")
    func pestanaInicial() {
        func p(_ t: NoteKind, _ e: String?, sesiones: Bool = false) -> String {
            TipoFicha.pestanaInicial(tipo: t, estado: e, conSesiones: sesiones)
        }
        #expect(p(.contact, "Activo") == "Resumen")
        #expect(p(.organization, "Interesado") == "Resumen")
        #expect(p(.opportunity, "Prospecto") == "Reuniones")
        #expect(p(.opportunity, "Diagnóstico") == "Reuniones")
        #expect(p(.opportunity, "Propuesta") == "Propuestas")
        #expect(p(.opportunity, "Aceptada") == "Facturas")
        #expect(p(.opportunity, "Ganada") == "Resumen")
        #expect(p(.opportunity, "Perdida") == "Notas")
        #expect(p(.opportunity, "Pausada") == "Notas")
        #expect(p(.project, "Sin empezar") == "Resumen")
        #expect(p(.project, "En curso") == "Tareas")
        #expect(p(.project, "Pausado") == "Tareas")
        #expect(p(.project, "En curso", sesiones: true) == "Viaje")
        #expect(p(.project, "Cerrado") == "Resumen")
        #expect(p(.meeting, "Prevista") == "Resumen")
        #expect(p(.meeting, "Hecha") == "Notas")
        #expect(p(.invoice, "Emitida") == "Resumen")
        #expect(p(.task, "Por hacer") == "Actividad")
        #expect(p(.system, "montado") == "Resumen")
        // La pestaña inicial existe en las pestañas de su tipo (Viaje la añade el proyecto con sesiones).
        for (t, e) in [(NoteKind.opportunity, "Aceptada"), (.opportunity, "Perdida"), (.project, "En curso"), (.meeting, "Hecha"),
                       (.task, "Hecha"), (.invoice, "Borrador"), (.system, "falta"), (.contact, "Activo")] {
            let titulos = TipoFicha.de(t).pestanas.map(\.titulo)
            #expect(titulos.contains(p(t, e)), "\(t) \(e)")
        }
    }

    @Test("Pestañas en el orden de §3.4")
    func orden() {
        #expect(TipoFicha.de(.contact).pestanas.map(\.titulo) ==
                ["Resumen", "Oportunidades", "Reuniones", "Propuestas", "Proyectos", "Facturas", "Tareas", "Conversaciones",
                 "Notas", "Actividad", "Fichero"])
        #expect(TipoFicha.de(.project).pestanas.map(\.titulo).prefix(8) ==
                ["Resumen", "Tareas", "Reuniones", "Facturas", "Materiales", "Notas", "Actividad", "Fichero"])
        #expect(TipoFicha.de(.task).pestanas.map(\.titulo) == ["Actividad", "Subtareas", "Fichero"])
        #expect(TipoFicha.de(.invoice).pestanas.map(\.titulo) == ["Resumen", "Cobros", "Envíos", "Actividad", "Fichero"])
        #expect(TipoFicha.de(.contact).nuevo.map(\.titulo) == ["Reunión", "Propuesta", "Proyecto", "Factura", "Tarea"])
    }

    @Test("Formato: euros, fechas y la línea de resumen")
    func formato() throws {
        #expect(FormatoFicha.euros("181.50") == "181,50 €")
        #expect(FormatoFicha.euros("1500") == "1.500 €")
        #expect(FormatoFicha.euros("x") == nil)
        let hoy = try #require(LocalDate(parsing: "2026-10-19"))
        #expect(FormatoFicha.cuando(try #require(LocalDate(parsing: "2026-10-20")), hoy: hoy) == "mañana")
        #expect(FormatoFicha.fechaConDia(try #require(LocalDate(parsing: "2026-10-30")), hoy: hoy) == "vie 30 oct")
        #expect(FormatoFicha.lineaResumen("# Jorge Martín\n> Talleres Martín e Hijos SL · Interesado\n\n## Notas") == "Talleres Martín e Hijos SL · Interesado")
        #expect(FormatoFicha.lineaResumen("# X\n> Guía: no\n") == nil)
        let cita = PestanaResumen.citaEntreComillas("«Que en enero no me tenga que acordar de nada.» Frase destino de Jorge.")
        #expect(cita?.cita == "Que en enero no me tenga que acordar de nada.")
        #expect(cita?.resto == "Frase destino de Jorge")
        #expect(PestanaResumen.citaEntreComillas("Sin comillas") == nil)
        #expect(FormatoFicha.extracto("| Contacto |  | Jorge Martín · jorge@x.example |") == "Contacto · Jorge Martín · jorge@x.example")
        #expect(FormatoFicha.extracto("- [ ] Llamar a [Jorge](../jorge.md)") == "Llamar a Jorge")
    }
}

/// Ficha con Ribera en una copia temporal (con escritura, como el ejemplo).
@Suite("Fichas · Ribera en una copia", .serialized)
@MainActor
struct FichaRiberaTests {
    let pruebas = SesionEscrituraTests()
    let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")
    let talleres = VaultPath("2 · Ventas/Empresas/talleres-martin-e-hijos.md")
    let nexo = VaultPath("2 · Ventas/Empresas/arquitectura-nexo.md")
    let opo = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
    let reunion = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales/Reuniones/2026-10-09-descubrimiento-trimestrales.md")

    func abrir(_ preparar: (URL) throws -> Void = { _ in }) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        try preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        #expect(sesion.puedeEscribir)
        return (e, sesion)
    }

    func modelo(_ ruta: VaultPath, _ sesion: VaultSession) async -> FichaModelo {
        let m = FichaModelo(ruta: ruta, sesion: sesion)
        await m.cargar()
        return m
    }

    func esperarRevision(_ sesion: VaultSession, desde r: Int) async {
        await pruebas.esperar { sesion.revision > r }
    }

    @Test("Contacto: destacado = siguiente paso; «Conectado con» con su empresa y el servicio calculado")
    func resumenJorge() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(jorge, sesion)
        let r = try #require(m.resumen)
        #expect(r.rotulo == "Contacto · 2 · Ventas")
        #expect(r.protagonista?.rotulo == "Siguiente paso")
        #expect(r.protagonista?.valor == "Emitir factura y confirmar cobro")
        #expect(r.protagonista?.contexto?.hasPrefix("Mañana") == true)
        let empresa = try #require(r.conectado.first { $0.propiedad == "empresa" })
        #expect(empresa.destino == talleres)
        #expect(!empresa.calculado)
        let servicio = try #require(r.conectado.first { $0.propiedad == "servicio" })
        #expect(servicio.calculado)
        #expect(servicio.guardaEn == opo)
        // Pestañas: cuentan lo abierto; las vacías sin «Nuevo» propio van a «Más».
        let t = m.pestanas()
        #expect(t.visibles.first { $0.id == "Oportunidades" }?.contador == 1)
        #expect(t.visibles.first { $0.id == "Facturas" }?.contador == 1)
        #expect(t.visibles.first { $0.id == "Propuestas" }?.contador == nil)
        #expect(t.visibles.contains { $0.id == "Proyectos" })
        #expect(t.mas.map(\.id).contains("Tareas"))
        #expect(m.pestanaElegida(nil, nav: nil) == "Resumen")
    }

    @Test("Oportunidad Aceptada: abre en Facturas, valor ponderado y Ganada bloqueada con su motivo")
    func oportunidad() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(opo, sesion)
        #expect(m.pestanaElegida(nil, nav: nil) == "Facturas")
        let nav = Navegacion(raiz: .ficha(opo))
        nav.actualizarRecuerdo(de: .ficha(opo)) { $0.extra["pestana"] = "Notas" }
        #expect(m.pestanaElegida(nil, nav: nav) == "Notas")
        #expect(m.pestanaElegida("Reuniones", nav: nav) == "Reuniones")
        #expect(m.resumen?.protagonista?.valor == "135 €")
        #expect(m.resumen?.protagonista?.contexto == "150 € al 90 %")
        let ficha = try #require(m.ficha)
        let ganada = try #require(m.opcionesEstado(ficha).first { $0.id == "Ganada" })
        #expect(ganada.motivoDesactivado?.contains("F-2026-0007") == true)
        #expect(m.opcionesEstado(ficha).first { $0.id == "Perdida" }?.motivoDesactivado == nil)
        #expect(m.resumen?.ahora.first?.clase == .decision)
    }

    @Test("Cambiar la empresa de Jorge pide confirmación con la línea antes y después; confirmar cambia una línea y Deshacer deja los mismos bytes")
    func confirmarYDeshacer() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let url = jorge.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let m = await modelo(jorge, sesion)
        let c = await EdicionRelaciones.hacer(CambioDeRelacion(dueno: jorge, propiedad: "empresa", accion: .poner(nexo)),
                                              sesion: sesion, almacen: m.almacen)
        let confirmacion = try #require(c)
        #expect(try Data(contentsOf: url) == antes)
        #expect(confirmacion.preparada.lineas.antes == #"empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]""#)
        #expect(confirmacion.preparada.lineas.despues == #"empresa: "[[arquitectura-nexo|Arquitectura Nexo SLP]]""#)
        #expect(confirmacion.pregunta.contains("¿Pasarlo a Arquitectura Nexo SLP?"))
        let r = sesion.revision
        await EdicionRelaciones.confirmar(confirmacion, sesion: sesion, almacen: m.almacen)
        let despues = try String(contentsOf: url, encoding: .utf8)
        let la = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n"), lb = despues.components(separatedBy: "\n")
        #expect(la.count == lb.count)
        #expect(zip(la, lb).filter { $0 != $1 }.count == 1)
        #expect(sesion.aviso?.texto.contains("Arquitectura Nexo SLP") == true)
        #expect(sesion.aviso?.accion != nil)
        await esperarRevision(sesion, desde: r)
        let ultimo = try #require(await sesion.bus?.ultimoDeshacible())
        await sesion.deshacer(plan: ultimo.planID)
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("«Añadir existente…» desde el contacto escribe en la reunión (personas), una línea; Deshacer deja los mismos bytes")
    func anadirDesdeElOtroLado() async throws {
        let (e, sesion) = try await abrir { carpeta in
            let u = reunion.url(in: carpeta)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("""
            ---
            tls_type: meeting
            titulo: Descubrimiento · Trimestrales · Talleres Martín
            tipo: descubrimiento
            estado: Hecha
            fecha: 2026-10-09
            personas: []
            empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
            oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
            ---
            # Descubrimiento · Trimestrales · Talleres Martín

            """.utf8).write(to: u)
        }
        defer { sesion.close(); e.limpiar() }
        let url = reunion.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let jorgeAntes = try Data(contentsOf: jorge.url(in: e.carpeta))
        let m = await modelo(jorge, sesion)
        // La reunión ya sale por su oportunidad (indirecta); al añadir a Jorge, pasa a directa.
        m.abrirSelectorInverso(tipos: [.meeting])
        let p = try #require(m.selector)
        #expect(p.nota.contains("«personas»"))
        await m.elegido(reunion, en: p, navegar: nil)
        #expect(m.confirmacion == nil)
        let texto = try String(contentsOf: url, encoding: .utf8)
        #expect(texto.contains(#"personas: ["[[jorge-martin|Jorge Martín]]"]"#))
        let la = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n"), lb = texto.components(separatedBy: "\n")
        #expect(zip(la, lb).filter { $0 != $1 }.count == 1)
        #expect(try Data(contentsOf: jorge.url(in: e.carpeta)) == jorgeAntes)
        await m.almacen.actualizar()
        await m.cargar()
        #expect(m.relacionados([.meeting]).first?.via == .directa(propiedad: "personas"))
        let ultimo = try #require(await sesion.bus?.ultimoDeshacible())
        await sesion.deshacer(plan: ultimo.planID)
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("Una relación obligatoria no se quita: avisa con el motivo y no escribe")
    func obligatoria() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = try Data(contentsOf: opo.url(in: e.carpeta))
        let m = await modelo(opo, sesion)
        await m.quitar(propiedad: "empresa", destino: talleres, guardaEn: opo)
        #expect(sesion.aviso?.texto.contains("siempre tiene empresa") == true)
        #expect(try Data(contentsOf: opo.url(in: e.carpeta)) == antes)
    }

    @Test("La vista previa no escribe nada (criterio §11.8)")
    func vistaPreviaNoEscribe() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = huella(e.carpeta)
        _ = NSApplication.shared
        for ruta in [jorge, opo, talleres] {
            let vista = VistaPreviaPopover(ruta: ruta, sesion: sesion).environment(\.navegacion, Navegacion(raiz: .ficha(ruta)))
            let hosting = NSHostingView(rootView: vista.frame(width: 360, height: 320))
            hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 320)
            for _ in 0..<4 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        #expect(huella(e.carpeta) == antes)
    }

    @Test("Lo privado no sale en lo relacionado ni en el selector")
    func privado() async throws {
        let (e, sesion) = try await abrir { carpeta in
            let config = carpeta.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: config, encoding: .utf8).replacingOccurrences(of: "privado: []", with: "privado: [\"4 · Finanzas/Fiscal/2026/T4\"]")
            try Data(t.utf8).write(to: config)
        }
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(jorge, sesion)
        #expect(!m.relacionados.contains { $0.ficha.tipo == .invoice })
        #expect(m.grafo?.fichas(de: [.invoice]).contains { $0.numero == "F-2026-0007" } == false)
        #expect(sesion.esPrivado(VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")))
    }

    @Test("Reunión Hecha: «Convertir en tareas» crea una tarea por acción, enlazada, y la línea enlaza su tarea")
    func accionesDeReunion() async throws {
        let (e, sesion) = try await abrir { carpeta in
            let u = reunion.url(in: carpeta)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("""
            ---
            tls_type: meeting
            titulo: Descubrimiento · Trimestrales · Talleres Martín
            estado: Hecha
            fecha: 2026-10-09
            personas: ["[[jorge-martin|Jorge Martín]]"]
            empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
            oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
            ---
            # Descubrimiento · Trimestrales · Talleres Martín

            ## Acciones
            > Guía: una por línea.
            - Pedir las facturas de proveedores escaneadas · @lucia · vence 2026-10-30

            """.utf8).write(to: u)
        }
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(reunion, sesion)
        let acciones = AccionDeReunion.leer(MarkdownSections.content(of: "Acciones", in: m.cuerpo ?? "") ?? "")
        #expect(acciones.count == 1)
        #expect(acciones.first?.responsable == "lucia")
        #expect(acciones.first?.vence == LocalDate(parsing: "2026-10-30"))
        #expect(m.pestanaElegida(nil, nav: nil) == "Notas")
        await AccionesReunion.convertir(acciones, modelo: m)
        await m.almacen.actualizar()
        let tareas = m.grafo?.fichas(de: [.task]).filter { $0.nombre == "Pedir las facturas de proveedores escaneadas" } ?? []
        let tarea = try #require(tareas.first)
        #expect(m.grafo?.destinos(de: tarea.ruta, propiedad: "oportunidad") == [opo])
        #expect(m.grafo?.destinos(de: tarea.ruta, propiedad: "empresa") == [talleres])
        #expect(tarea.texto("responsable") == "lucia")
        let texto = try String(contentsOf: reunion.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("· vence 2026-10-30 → [T-"))
        #expect(AccionDeReunion.leer(MarkdownSections.content(of: "Acciones", in: NoteDocument(text: texto).body) ?? "").first?.convertida == true)
    }

    @Test("«Nueva tarea» desde el proyecto: nace en su carpeta, enlazada, y Deshacer la retira")
    func nuevaTareaEnProyecto() async throws {
        let proyecto = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md")
        let (e, sesion) = try await abrir { carpeta in try CapturasFichasTests.prepararProyecto(carpeta) }
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(proyecto, sesion)
        #expect(m.pestanaElegida(nil, nav: nil) == "Tareas")
        #expect(m.relacionados([.task]).count == 6)
        let foto = try #require(m.almacen.foto)
        let nota = try TaskStore(snapshot: foto).crear(NuevaTarea(titulo: "Llamar a Jorge", proyecto: proyecto, autor: sesion.autor))
        #expect(nota.ruta.parent == VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Tareas"))
        let r = try await sesion.escribir(plan: nota.plan, aviso: "Creé la tarea")
        #expect(r.hecho)
        m.almacen.invalidar()
        await m.cargar()
        #expect(m.relacionados([.task]).count == 7)
        // Fases del plan: Recogida contiene T-0042 (por su propiedad `fase`).
        let plan = PlanDeEntrega.leer(try #require(m.almacen.foto?.text(VaultPath("3 · Entrega/Planes de entrega/trimestrales.md"))))
        let fases = FasesDelPlan.delProyecto(plan: plan, inicio: LocalDate(parsing: "2026-10-19"), tareas: m.relacionados([.task]).map(\.ficha), hoy: m.hoy)
        #expect(fases.first?.tareas.count == 1)
        #expect(fases.first?.situacion == .enCurso)
        await sesion.deshacer(plan: r.planID)
        #expect(!FileManager.default.fileExists(atPath: nota.ruta.url(in: e.carpeta).path))
    }

    @Test("«Confirmar el cobro» desde la factura: un recibo confirmado por la persona y la factura Cobrada en un paso; Ganada se desbloquea; Deshacer deja los mismos bytes")
    func confirmarCobro() async throws {
        let factura = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(factura, sesion)
        // Emitida y sin vencer: la principal es preparar el envío y la segunda, confirmar el cobro.
        #expect(AccionDocumento.de(m).map(\.titulo) == ["Preparar el envío", "Confirmar el cobro"])
        #expect(AccionDocumento.de(m).allSatisfy { $0.motivo == nil })
        let antes = huella(e.carpeta)
        let bytesFactura = try Data(contentsOf: factura.url(in: e.carpeta))
        let p = PreparadorNuevo(opcion: OpcionNuevo(titulo: "Recibo de cobro", plantilla: "recibo-de-cobro", tipo: .receipt), modelo: m)
        #expect(!p.pideTitulo)
        guard case .lista(let nota) = p.estado() else { Issue.record("El recibo no se pudo preparar"); return }
        #expect(huella(e.carpeta) == antes)  // preparar no escribe
        let r0 = sesion.revision
        let ruta = try #require(await p.crear())
        #expect(ruta == nota.ruta)
        let texto = try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8)
        let fm = NoteDocument(text: texto).frontmatter
        #expect(fm.text("confirmado_por") == "Manu")
        #expect(fm.text("importe") == "181.50")
        #expect(fm.text("factura")?.contains("f-2026-0007") == true)
        // La factura pasa a Cobrada en el mismo paso: cambia una sola línea.
        let facturaDespues = try String(contentsOf: factura.url(in: e.carpeta), encoding: .utf8)
        #expect(facturaDespues.contains("estado: Cobrada"))
        let la = String(decoding: bytesFactura, as: UTF8.self).components(separatedBy: "\n"), lb = facturaDespues.components(separatedBy: "\n")
        #expect(zip(la, lb).filter { $0 != $1 }.count == 1)
        await esperarRevision(sesion, desde: r0)
        // La oportunidad de Jorge ya puede pasar a Ganada.
        let mo = await modelo(opo, sesion)
        let fichaOpo = try #require(mo.ficha)
        let ganada = try #require(mo.opcionesEstado(fichaOpo).first { $0.id == "Ganada" })
        #expect(ganada.motivoDesactivado == nil)
        // Cobrada: no ofrece más acciones ni un segundo recibo.
        await m.cargar()
        #expect(AccionDocumento.de(m).isEmpty)
        if case .bloqueada = PreparadorNuevo(opcion: p.opcion, modelo: m).estado() {} else { Issue.record("Debería decir que ya está cobrada") }
        let ultimo = try #require(await sesion.bus?.ultimoDeshacible())
        await sesion.deshacer(plan: ultimo.planID)
        #expect(!FileManager.default.fileExists(atPath: ruta.url(in: e.carpeta).path))
        #expect(try Data(contentsOf: factura.url(in: e.carpeta)) == bytesFactura)
    }

    @Test("«Nueva reunión» desde el contacto: nace enlazada con él (personas), su empresa y su oportunidad")
    func nuevaReunionDesdeContacto() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(jorge, sesion)
        var p = PreparadorNuevo(opcion: OpcionNuevo(titulo: "Reunión", plantilla: "reunion", tipo: .meeting), modelo: m,
                                titulo: "Revisión del primer trimestre", fecha: LocalDate(parsing: "2026-10-28"))
        #expect(p.usaOportunidad)
        #expect(p.oportunidades.map(\.ruta) == [opo])
        p.oportunidad = opo
        let ruta = try #require(await p.crear())
        let fm = NoteDocument(text: try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8)).frontmatter
        #expect(fm.value("personas")?.displayText.contains("jorge-martin") == true)
        #expect(fm.text("oportunidad")?.contains("jorge-martin-trimestrales") == true)
        #expect(fm.text("fecha") == "2026-10-28")
        #expect(sesion.aviso?.accion != nil)
    }

    @Test("Factura en borrador: «Revisar y emitir» sale desactivada con su motivo; sus tablas se leen como tablas")
    func accionesDeFactura() async throws {
        let factura = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
        let (e, sesion) = try await abrir { carpeta in
            let u = factura.url(in: carpeta)
            let t = try String(contentsOf: u, encoding: .utf8).replacingOccurrences(of: "estado: Emitida", with: "estado: Borrador")
            try Data(t.utf8).write(to: u)
        }
        defer { sesion.close(); e.limpiar() }
        let m = await modelo(factura, sesion)
        let acciones = AccionDocumento.de(m)
        #expect(acciones.map(\.titulo) == ["Revisar y emitir"])
        #expect(acciones.first?.motivo?.isEmpty == false)
        // Las tablas del documento se leen como tablas.
        let conceptos = try #require(MarkdownSections.content(of: "Conceptos", in: m.cuerpo ?? "", level: 2))
        let tabla = try #require(TablaMarkdown.leer(conceptos.components(separatedBy: "\n")))
        #expect(tabla.cabecera.first == "Concepto")
        #expect(tabla.filas.first?.first == "Trimestrales")
        #expect(DocumentoFicha.importes(try #require(m.ficha)).contains("Base 150 €"))
    }

    /// Huella de todos los ficheros de la carpeta (sin `.tls/escritor.json`, que el escritor toca al abrir).
    func huella(_ raiz: URL) -> [String: Data] {
        var out: [String: Data] = [:]
        let fm = FileManager.default
        guard let en = fm.enumerator(at: raiz, includingPropertiesForKeys: [.isDirectoryKey]) else { return [:] }
        for case let u as URL in en {
            var dir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &dir), !dir.boolValue, u.lastPathComponent != "escritor.json" else { continue }
            out[u.path] = try? Data(contentsOf: u)
        }
        return out
    }
}
