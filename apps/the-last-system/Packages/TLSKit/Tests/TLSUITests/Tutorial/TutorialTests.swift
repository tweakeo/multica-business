import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Tutorial (PLAN §6.8, F3): hitos que se marcan con la acción real, `tutorial.json`, el velo y la burbuja, el
/// recorrido de Ribera completo (criterio F3-8) y «Reiniciar ejemplo» con las huellas prístinas (F3-7). Todo con
/// carpetas y Application Support temporales.
@Suite("Tutorial", .serialized)
@MainActor
struct TutorialTests {
    let pruebas = SesionEscrituraTests()

    // MARK: Definición

    // F4 · integración: ⌘J y «pausar y reanudar» ya se hacen de verdad (antes «llegaban con los asistentes»).
    // F5 · integración: un paso más, que explica las conexiones (solo explica).
    @Test("Diez hitos, todos se hacen ya (F4: también ⌘J y pausar y reanudar); trece pasos en el ejemplo")
    func hitos() {
        #expect(HitoTutorial.allCases.count == 10)
        #expect(HitoTutorial.disponibles.count == 10)
        #expect(HitoTutorial.allCases.filter(\.llegaConLosAsistentes).isEmpty)
        let pasos = Recorridos.pasos(.ejemplo)
        #expect(pasos.count == 13)
        #expect(pasos.first?.id == "bienvenida" && pasos.last?.id == "final")
        // Cada hito tiene su paso, con las mismas partes.
        for h in HitoTutorial.allCases {
            let p = pasos.first { $0.id == h.rawValue }
            #expect(p != nil, "Falta el paso de \(h)")
            #expect(p?.partes == h.partes)
            #expect(p?.llegaConLosAsistentes == h.llegaConLosAsistentes)
        }
        // Dos o tres líneas: ningún texto pasa de 200 caracteres.
        for p in pasos + Recorridos.pasos(.tuEmpresa, contexto: .init(ficha: nil, cuello: .ventas)) {
            #expect(p.texto.count <= 200, "«\(p.titulo)» es largo: \(p.texto.count)")
        }
    }

    @Test("El recorrido con tu empresa usa los hitos del paso 8 de la puesta en marcha")
    func recorridoTuEmpresa() {
        let pasos = Recorridos.pasos(.tuEmpresa, contexto: .init(ficha: VaultPath("Empresa.md"), cuello: .ventas))
        let conHito = pasos.filter { !$0.partes.isEmpty }.map(\.id)
        #expect(conHito == HitoRecorrido.allCases.map(\.rawValue))
        // F4: la propuesta de Mika ya se aprueba de verdad (en Decisiones).
        #expect(pasos.first { $0.id == "aprobar-propuesta" }?.llegaConLosAsistentes == false)
        #expect(pasos.first { $0.id == "aprobar-propuesta" }?.destino == .decisiones)
        #expect(pasos.first { $0.id == "area-del-cuello" }?.destino == .area(.ventas))
        #expect(pasos.first { $0.id == "area-del-cuello" }?.partes == ["area:VEN"])
        // Sin cuello conocido, el mapa.
        let sinCuello = Recorridos.pasos(.tuEmpresa)
        #expect(sinCuello.first { $0.id == "area-del-cuello" }?.partes == ["mapa"])
    }

    // MARK: tutorial.json

    @Test("tutorial.json guarda partes, hitos, fase y paso, y se vuelve a leer igual")
    func almacen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tls-tutorial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("tutorial.json")
        let a = AlmacenTutorial(archivo: url)
        #expect(a.estado(.ejemplo).fase == .sinEmpezar)
        let id = UUID()
        a.cambiar(.ejemplo) { e in e.fase = .enCurso; e.paso = 3; e.partes["foco"] = Date() }
        a.cambiar(.tuEmpresa, empresa: id) { $0.fase = .enPausa }
        let b = AlmacenTutorial(archivo: url)
        #expect(b.estado(.ejemplo).fase == .enCurso)
        #expect(b.estado(.ejemplo).paso == 3)
        #expect(b.estado(.ejemplo).partesHechas == ["foco"])
        #expect(b.estado(.tuEmpresa, empresa: id).fase == .enPausa)
        #expect(b.estado(.tuEmpresa, empresa: UUID()).fase == .sinEmpezar)
        let texto = try String(contentsOf: url, encoding: .utf8)
        #expect(texto.contains("\"ejemplo\""))
        #expect(texto.contains(id.uuidString.lowercased()))
        b.reiniciar(.ejemplo)
        #expect(AlmacenTutorial(archivo: url).estado(.ejemplo).fase == .sinEmpezar)
        // Un fichero roto no impide empezar.
        try Data("{roto".utf8).write(to: url)
        #expect(AlmacenTutorial(archivo: url).estado(.ejemplo).fase == .sinEmpezar)
    }

    // MARK: Detector

    @Test("De lo que cambió en la carpeta a los eventos del tutorial")
    func detector() {
        let layout = VaultLayout.humana
        func h(_ tipo: String?, estado: String? = nil, responsable: String? = nil, tipoTarea: String? = nil,
               decisiones: Int? = nil, contenido: Int = 1) -> HuellaNota {
            HuellaNota(tipo: tipo, estado: estado, responsable: responsable, tipoTarea: tipoTarea, decisiones: decisiones,
                       contenido: contenido)
        }
        let opo = VaultPath("2 · Ventas/Oportunidades/x.md")
        let tarea = VaultPath("2 · Ventas/Tareas/t-0009-llamar.md")
        let decision = VaultPath("1 · Dirección/Tareas/t-0001-x.md")
        let registro = RegistroDecisiones.ruta(layout)
        let contacto = VaultPath("2 · Ventas/Contactos/ana.md")
        let extracto = VaultPath("4 · Finanzas/Registros/Bancos/c/Extractos/2026-10-19 e.csv")
        typealias C = DetectorHitos.Cambio
        #expect(DetectorHitos.eventos([C(ruta: opo, antes: h("opportunity", estado: "Diagnóstico"),
                                         despues: h("opportunity", estado: "Propuesta", contenido: 2))], layout: layout)
                == [.oportunidadMovida(opo)])
        #expect(DetectorHitos.eventos([C(ruta: tarea, antes: nil, despues: h("task", responsable: "Manu"))], layout: layout)
                == [.tareaCreadaYAsignada(tarea)])
        #expect(DetectorHitos.eventos([C(ruta: tarea, antes: nil, despues: h("task"))], layout: layout).isEmpty,
                "sin responsable aún no está asignada")
        #expect(DetectorHitos.eventos([C(ruta: tarea, antes: h("task"), despues: h("task", responsable: "Manu", contenido: 2))],
                                      layout: layout) == [.tareaCreadaYAsignada(tarea)])
        // Aprobar: la tarea de decisión cambia de estado y el registro gana una línea; cuenta como aprobar.
        let aprobar = [C(ruta: decision, antes: h("task", estado: "En revisión", tipoTarea: "decision"),
                         despues: h("task", estado: "Hecha", tipoTarea: "decision", contenido: 2)),
                       C(ruta: registro, antes: h(nil, decisiones: 3), despues: h(nil, decisiones: 4, contenido: 2))]
        #expect(DetectorHitos.eventos(aprobar, layout: layout) == [.decisionResuelta(decision)])
        #expect(DetectorHitos.eventos([aprobar[1]], layout: layout) == [.decisionRegistrada])
        #expect(DetectorHitos.eventos([C(ruta: contacto, antes: h("contact"), despues: h("contact", contenido: 2))], layout: layout)
                == [.fichaEditada(contacto)])
        #expect(DetectorHitos.eventos([C(ruta: contacto, antes: h("contact"), despues: h("contact"))], layout: layout).isEmpty)
        #expect(DetectorHitos.eventos([C(ruta: extracto, antes: nil, despues: h(nil))], layout: layout) == [.extractoImportado])
        // Lo de `.tls/` y el Archivo no cuenta.
        #expect(DetectorHitos.eventos([C(ruta: VaultPath("Archivo/2 · Ventas/Contactos/ana.md"), antes: h("contact"),
                                         despues: h("contact", contenido: 2))], layout: layout).isEmpty)
        #expect(DetectorHitos.eventos([C(ruta: VaultPath(".tls/config.yaml"), antes: h(nil), despues: h(nil, contenido: 2))],
                                      layout: layout).isEmpty)
    }

    // MARK: Con una sesión de verdad

    struct Prueba {
        let e: SesionEscrituraTests.Entorno
        let sesion: VaultSession
        let c: ControladorTutorial
        let almacen: AlmacenTutorial
        var finder: [VaultPath?] = []
    }

    func abrir(clase: VaultClass = .demo) async throws -> Prueba {
        let (e, entry) = try pruebas.entorno(clase: clase, escritura: .permitida)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        let almacen = AlmacenTutorial(archivo: e.base.appendingPathComponent("tutorial.json"))
        let c = ControladorTutorial.de(sesion, almacen: almacen, appSupport: e.base)
        return Prueba(e: e, sesion: sesion, c: c, almacen: almacen)
    }

    @Test("En pruebas no empieza solo ni toca el Application Support de verdad; el ejemplo queda con su puesta en marcha hecha")
    func aislado() async throws {
        let p = try await abrir()
        defer { p.sesion.close(); p.e.limpiar() }
        // Una sesión con su estado aparte guarda el tutorial junto a él.
        let otro = ControladorTutorial.de(p.sesion)
        #expect(otro === p.c)
        #expect(p.c.appSupport.path == p.e.base.path)
        #expect(!p.c.empiezaSolo)
        await p.c.alAbrir()
        #expect(p.c.estado.fase == .sinEmpezar)
        #expect(p.c.pasoVisible(anclasPresentes: []) == nil)
        // onboarding.json del ejemplo: hecho, repasable paso a paso.
        let puesta = try #require(AlmacenPuesta(vaultID: p.sesion.entry.id, appSupport: p.e.base).leer())
        #expect(puesta.terminada)
        #expect(PasoPuesta.allCases.allSatisfy { puesta.paso($0).fase == .aplicado })
        #expect(!puesta.respuestas.isEmpty)
    }

    @Test("La burbuja: rótulo, dos o tres líneas, «Seguir más tarde» y «Quedan ~N min» siempre; Llévame si el sitio no está")
    func burbuja() async throws {
        let p = try await abrir()
        defer { p.sesion.close(); p.e.limpiar() }
        await p.c.empezar()
        var v = try #require(p.c.pasoVisible(anclasPresentes: []))
        #expect(v.rotulo == "Conoce la app")   // un solo contador: el de los hitos
        #expect(v.botones.map(\.id).contains("seguirMasTarde"))
        #expect(v.progreso.hasSuffix("min") && v.progreso.contains("Quedan ~"))
        #expect(v.items.count == 10, "al empezar, la lista de hitos")
        #expect(v.botones.first?.titulo == "Empezar")
        p.c.irA(1)
        v = try #require(p.c.pasoVisible(anclasPresentes: [], destinoActual: .tareas))
        #expect(v.ancla == .hoyFoco)
        #expect(v.marca == .porHacer)
        #expect(v.botones.first?.id == "llevarme")
        #expect(v.botones.map(\.id).contains("saltar"))
        #expect(v.bloquearFuera)
        // En su sitio, sin «Llévame».
        v = try #require(p.c.pasoVisible(anclasPresentes: [.hoyFoco], destinoActual: .hoy))
        #expect(!v.botones.map(\.id).contains("llevarme"))
        // Un paso de asistentes (F4): ya se hace de verdad, con «Llévame» a Hoy y ⌘J.
        p.c.irA(9)
        v = try #require(p.c.pasoVisible(anclasPresentes: []))
        #expect(v.marca == .porHacer)
        #expect(v.botones.map(\.id).contains("saltar"))
        #expect(!v.anuncio.contains("Llega con los asistentes"))
        // «Seguir más tarde»: se oculta y se retoma en el mismo paso, también tras cerrar y volver a abrir.
        p.c.pulsar("seguirMasTarde", nav: nil, acciones: .init())
        #expect(p.c.pasoVisible(anclasPresentes: []) == nil)
        #expect(AlmacenTutorial(archivo: p.almacen.archivo).estado(.ejemplo).fase == .enPausa)
        #expect(AlmacenTutorial(archivo: p.almacen.archivo).estado(.ejemplo).paso == 9)
        await p.c.empezar()
        #expect(p.c.pasoActual?.id == HitoTutorial.abrirAsistente.rawValue)
    }

    @Test("Una acción que no es real no marca nada: «Siguiente» y «Saltar» solo avanzan")
    func siguienteNoMarca() async throws {
        let p = try await abrir()
        defer { p.sesion.close(); p.e.limpiar() }
        await p.c.empezar()
        // F5 · integración: once pasos más el de las conexiones (solo explica) antes del final.
        for _ in 0..<12 { p.c.pulsar("saltar", nav: nil, acciones: .init()) }
        #expect(p.c.pasoActual?.id == "final")
        #expect(p.c.estado.partes.isEmpty)
        #expect(p.c.estado.hitos.isEmpty)
        // Sin recorrido en marcha, un evento no cuenta.
        p.c.pulsar("terminar", nav: nil, acciones: .init())
        p.c.registrar(.decisionRegistrada)
        #expect(p.c.estado.partes.isEmpty)
    }

    /// Ventana fuera de pantalla con la empresa (nunca se enseña).
    func ventana(_ p: Prueba, nav: Navegacion) -> NSWindow {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let vista = ContenidoEmpresa(sesion: p.sesion, nav: nav)
            .environment(p.e.model)
            .environment(\.navegacion, nav)
            .frame(width: 1280, height: 860)
        let hosting = NSHostingView(rootView: vista)
        hosting.frame = NSRect(x: 0, y: 0, width: 1280, height: 860)
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView, .resizable],
                         backing: .buffered, defer: false)
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        return w
    }

    func pasar(_ w: NSWindow, _ veces: Int = 6) async {
        for _ in 0..<veces {
            w.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    func escribir(_ p: Prueba, plan: WritePlan) async throws {
        let antes = p.sesion.revision
        let r = try await p.sesion.escribir(plan: plan, aviso: "")
        #expect(r.hecho)
        await pruebas.esperar { p.sesion.revision > antes }
        await p.c.carpetaCambio([])
    }

    func escribir(_ p: Prueba, _ comando: CommandBus.Comando) async throws {
        let antes = p.sesion.revision
        let r = try await p.sesion.escribir(comando, aviso: "")
        #expect(r.hecho)
        await pruebas.esperar { p.sesion.revision > antes }
        await p.c.carpetaCambio([])
    }

    @Test("Recorre el tutorial de Ribera completo: cada hito con su acción real (criterio F3-8)")
    func recorridoCompleto() async throws {
        var p = try await abrir()
        defer { p.sesion.close(); p.e.limpiar() }
        let nav = Navegacion(raiz: .hoy)
        let w = ventana(p, nav: nav)
        defer { w.close() }
        var vistosEnFinder: [VaultPath?] = []
        p.c.revelar = { vistosEnFinder.append($0) }
        p.c.ventana = w
        await p.c.empezar()
        #expect(p.c.pasoActual?.id == "bienvenida")
        let acciones = AccionesVentanaTutorial()
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 1 · Foco de Hoy: el foco aparece y un clic dentro lo marca.
        #expect(p.c.pasoActual?.id == HitoTutorial.focoDeHoy.rawValue)
        await pruebas.esperar({ TutorialAnclas.compartidas.presentes(en: w).contains(.hoyFoco) }, segundos: 15)
        await pasar(w)
        let hosting = try #require(w.contentView)
        let sonda = try #require(TutorialAnclas.compartidas.rectangulo(.hoyFoco, respectoA: hosting))
        // Un clic fuera no cuenta; uno dentro, sí.
        p.c.clic(en: w, punto: NSPoint(x: 2, y: 2))
        #expect(p.c.estado.partes["foco"] == nil)
        let centro = hosting.convert(NSPoint(x: sonda.midX, y: hosting.isFlipped ? sonda.midY : hosting.bounds.height - sonda.midY), to: nil)
        p.c.clic(en: w, punto: centro)
        #expect(p.c.estado.hitos[HitoTutorial.focoDeHoy.rawValue] != nil)
        #expect(p.c.pasoVisible(anclasPresentes: [.hoyFoco])?.marca == .hecho)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 2 · Aprobar o cambiar una decisión (lo que escribe «Aprobar»: la tarea 1-3-1 pasa a Hecha).
        let decision = VaultPath("1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md")
        try await escribir(p, .cambiarPropiedades(decision, poner: [Property(key: "estado", value: .text("Hecha"))], quitar: []))
        #expect(p.c.estado.hitos[HitoTutorial.aprobarOModificar.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 3 · Mover una oportunidad de etapa.
        let foto = try #require(await p.sesion.instantanea())
        let opo = try #require(foto.notes.first { r in
            r.raw.hasPrefix("2 · Ventas/Oportunidades/") && ["Diagnóstico", "Propuesta", "Prospecto"]
                .contains(foto.frontmatter(r).properties.first { $0.key == "estado" }?.value.displayText ?? "")
        })
        let estadoOpo = foto.frontmatter(opo).properties.first { $0.key == "estado" }?.value.displayText
        try await escribir(p, .cambiarPropiedades(opo, poner: [Property(key: "estado", value: .text(estadoOpo == "Propuesta" ? "Diagnóstico" : "Propuesta"))], quitar: []))
        #expect(p.c.estado.hitos[HitoTutorial.moverOportunidad.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 4 · Crear una tarea y dársela a alguien (lo que escribe «Nueva tarea»).
        let store = TaskStore(snapshot: try #require(await p.sesion.instantanea()))
        let nueva = try store.crear(NuevaTarea(titulo: "Llamar a la panadería por el trimestre", area: .ventas, responsable: "Manu",
                                              autor: p.sesion.autor))
        try await escribir(p, plan: nueva.plan)
        #expect(p.c.estado.hitos[HitoTutorial.crearYAsignarTarea.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 5 · Editar una ficha y verla en Finder (los dos hacen falta).
        #expect(p.c.pasoActual?.destino == .ficha(Recorridos.fichaEjemplo))
        try await escribir(p, .cambiarPropiedades(Recorridos.fichaEjemplo, poner: [Property(key: "telefono", value: .text("600 000 000"))], quitar: []))
        #expect(p.c.estado.partes["editar"] != nil)
        #expect(p.c.estado.hitos[HitoTutorial.editarYVerEnFinder.rawValue] == nil, "falta verla en Finder")
        p.c.pulsar("finder", nav: nav, acciones: acciones)
        #expect(vistosEnFinder == [Recorridos.fichaEjemplo])
        #expect(p.c.estado.hitos[HitoTutorial.editarYVerEnFinder.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 6 · Apuntar una decisión en el registro.
        let (planRegistro, _) = try RegistroDecisiones.anadir(
            NuevaDecision(fecha: p.sesion.hoy, decision: "Probar la cuota mensual con dos clientes", porque: "Para ver si simplifica el cobro",
                          area: "Dirección"),
            en: try #require(await p.sesion.instantanea()), autor: p.sesion.autor)
        try await escribir(p, plan: planRegistro)
        #expect(p.c.estado.hitos[HitoTutorial.registrarDecision.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 7 · Importar un extracto: el de ejemplo trae dos movimientos nuevos.
        let csv = try #require(EjemploTutorial.extractoDeEjemplo(appSupport: p.e.base))
        #expect(csv.path.hasPrefix(p.e.base.path), "el extracto va fuera de la carpeta")
        let fotoBanco = try #require(await p.sesion.instantanea())
        let cuenta = try #require(RegistrosFinanzas(snapshot: fotoBanco).cuentas.first { $0.carpeta.name == "cuenta-corriente-banco-demo" })
        let previa = try ImportadorExtracto(snapshot: fotoBanco).vistaPrevia(
            try Data(contentsOf: csv), nombre: csv.lastPathComponent, cuenta: cuenta, adivinarFormato: false)
        #expect(previa.nuevas.count == 2)
        try await escribir(p, plan: try #require(previa.plan(autor: p.sesion.autor)))
        #expect(p.c.estado.hitos[HitoTutorial.importarExtracto.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 8 · El mapa: «Llévame» lleva a la Operación de Dirección; al abrir «Mapa» aparece y queda marcado.
        #expect(p.c.pasoActual?.id == HitoTutorial.mapaYCuello.rawValue)
        p.c.pulsar("llevarme", nav: nav, acciones: acciones)
        #expect(nav.actual == .area(.direccion, pestana: PestanaArea.operacion.rawValue))
        nav.actualizarRecuerdo(de: .area(.direccion)) { $0.extra["direccion.vista"] = "Mapa" }
        await pruebas.esperar({ TutorialAnclas.compartidas.presentes(en: w).contains(.direccionMapa) }, segundos: 15)
        await pasar(w, 3)
        p.c.anclasCambiaron()
        #expect(p.c.estado.hitos[HitoTutorial.mapaYCuello.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // 9 · ⌘J (F4): preguntar a Mika lo marca al recibir la respuesta (aquí, sin Claude, contesta el enrutador).
        #expect(p.c.pasoActual?.id == HitoTutorial.abrirAsistente.rawValue)
        #expect(p.c.pasoVisible(anclasPresentes: [])?.marca == .porHacer)
        await ConversacionMika.de(p.sesion).enviar("¿Qué tengo hoy?", mostrar: "¿Qué tengo hoy?")
        #expect(p.c.estado.hitos[HitoTutorial.abrirAsistente.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)
        // 10 · Pausar y reanudar (F4): el interruptor de verdad, como la persona.
        #expect(p.c.pasoActual?.id == HitoTutorial.pausarAsistentes.rawValue)
        try await EscrituraAsistentes.ponerInterruptor(false, sesion: p.sesion)
        try await EscrituraAsistentes.ponerInterruptor(true, sesion: p.sesion)
        #expect(p.c.estado.hitos[HitoTutorial.pausarAsistentes.rawValue] != nil)
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)
        // F5 · integración: las conexiones (solo explica; no es un hito).
        #expect(p.c.pasoActual?.id == "conexiones")
        p.c.pulsar("siguiente", nav: nav, acciones: acciones)

        // Final: los diez hitos, hechos y guardados.
        let fin = try #require(p.c.pasoVisible(anclasPresentes: []))
        #expect(fin.items.filter { $0.marca == .hecho }.count == 10)
        #expect(fin.items.filter { $0.marca == .llegaConLosAsistentes }.isEmpty)
        #expect(fin.progreso.hasPrefix("10 de 10 hitos"))
        #expect(fin.botones.map(\.id).contains("reiniciar"))
        let guardado = AlmacenTutorial(archivo: p.almacen.archivo).estado(.ejemplo)
        #expect(Set(guardado.hitos.keys) == Set(HitoTutorial.disponibles.map(\.rawValue)))
        p.c.pulsar("terminar", nav: nav, acciones: acciones)
        #expect(AlmacenTutorial(archivo: p.almacen.archivo).estado(.ejemplo).fase == .terminado)
        p.finder = vistosEnFinder
    }

    @Test("F3-8 · las anclas: cada paso del tutorial que señala algo lo encuentra en su pantalla de Ribera")
    func anclasDeCadaPaso() async throws {
        let p = try await abrir()
        defer { p.sesion.close(); p.e.limpiar() }
        let nav = Navegacion(raiz: .hoy)
        let w = ventana(p, nav: nav)
        defer { w.close() }
        // Los pasos de los dos recorridos (el del área del cuello, con Ventas) con su ancla y su pantalla.
        let pasos = Recorridos.pasos(.ejemplo)
            + Recorridos.pasos(.tuEmpresa, contexto: .init(ficha: Recorridos.fichaEjemplo, cuello: .ventas))
        var vistas: Set<TutorialAnclaID> = []
        for paso in pasos {
            guard let ancla = paso.ancla, let destino = paso.destino, !vistas.contains(ancla) else { continue }
            if ancla == .direccionMapa {
                nav.actualizarRecuerdo(de: .area(.direccion)) { $0.extra["direccion.vista"] = "Mapa" }
            }
            nav.nuevaRaiz(destino)
            await pruebas.esperar({ TutorialAnclas.compartidas.presentes(en: w).contains(ancla) }, segundos: 20)
            await pasar(w, 2)
            #expect(TutorialAnclas.compartidas.presentes(en: w).contains(ancla), "«\(paso.titulo)»: no aparece \(ancla) en \(destino)")
            // Con el ancla en su sitio, la burbuja no ofrece «Llévame» y el hueco tiene tamaño.
            let hosting = try #require(w.contentView)
            let r = try #require(TutorialAnclas.compartidas.rectangulo(ancla, respectoA: hosting), "\(ancla) sin rectángulo")
            #expect(r.width > 0 && r.height > 0)
            vistas.insert(ancla)
        }
        // Las nueve anclas del tutorial salen en algún paso y se han encontrado todas.
        let todas: Set<TutorialAnclaID> = [.hoyFoco, .decisionesGrupo, .ventasCRM, .tareasNueva, .ficha, .direccionRegistrarDecision,
                                            .direccionMapa, .bancoImportar, .areaPestanas]
        #expect(vistas == todas, "faltan: \(todas.subtracting(vistas))")
    }

    @Test("Recorrido con tu empresa: los hitos llegan también al paso 8 de la puesta en marcha")
    func tuEmpresaMarcaLaPuesta() async throws {
        let p = try await abrir(clase: .copia)
        defer { p.sesion.close(); p.e.limpiar() }
        #expect(p.c.tipo == .tuEmpresa)
        // Su puesta en marcha (en Application Support temporal).
        let almacenPuesta = AlmacenPuesta(vaultID: p.sesion.entry.id, appSupport: p.e.base)
        try almacenPuesta.guardar(EstadoPuestaEnMarcha(vaultID: p.sesion.entry.id, ruta: .copiaG3))
        await TutorialEventos.empezar(.tuEmpresa, empresa: p.sesion.entry.id, almacen: p.almacen)
        #expect(p.c.activo)
        #expect(p.c.pasoActual?.id == "hoy")
        p.c.registrar(.focoDeHoy)
        p.c.navego(a: .area(.direccion))
        try await escribir(p, .cambiarPropiedades(VaultPath("2 · Ventas/Contactos/marta-soler.md"),
                                                  poner: [Property(key: "telefono", value: .text("600 000 001"))], quitar: []))
        var revelado: [VaultPath?] = []
        p.c.revelar = { revelado.append($0) }
        p.c.irA(4)
        p.c.pulsar("finder", nav: nil, acciones: .init())
        #expect(revelado.count == 1)
        let recorrido = try #require(almacenPuesta.leer()).recorrido
        #expect(recorrido[HitoRecorrido.hoy.rawValue] != nil)
        #expect(recorrido[HitoRecorrido.editarFicha.rawValue] != nil)
        #expect(recorrido[HitoRecorrido.verEnFinder.rawValue] != nil)
        #expect(recorrido[HitoRecorrido.aprobarPropuesta.rawValue] == nil, "aún no se ha aprobado ninguna propuesta de Mika")
    }

    // MARK: Reiniciar ejemplo (criterio F3-7)

    @Test("«Reiniciar ejemplo» devuelve los hashes prístinos y vuelve a empezar el recorrido")
    func reiniciarEjemplo() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-reiniciar-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let empresas = base.appendingPathComponent("Empresas", isDirectory: true)
        let papelera = base.appendingPathComponent("Papelera", isDirectory: true)
        try FileManager.default.createDirectory(at: papelera, withIntermediateDirectories: true)
        let instalador = InstaladorEjemplo(origen: SesionEscrituraTests.ribera, empresas: empresas) { url in
            try FileManager.default.moveItem(at: url, to: papelera.appendingPathComponent(UUID().uuidString))
        }
        let model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("asup", isDirectory: true)))
        let pristinas = try EjemploTutorial.huellas(de: SesionEscrituraTests.ribera)
        #expect(pristinas.count > 100)

        let primera = try await instalador.instalarOAbrir(en: model).entrada
        let destino = instalador.destino
        #expect(try EjemploTutorial.huellas(de: destino) == pristinas)

        // Se trabaja en el ejemplo: cambia un fichero, aparece otro y el recorrido avanza.
        try Data("cambiado".utf8).write(to: destino.appendingPathComponent("Empresa.md"))
        try Data("nuevo".utf8).write(to: destino.appendingPathComponent("2 · Ventas/Contactos/nuevo.md"))
        #expect(try EjemploTutorial.huellas(de: destino) != pristinas)
        let almacen = AlmacenTutorial(archivo: base.appendingPathComponent("tutorial.json"))
        almacen.cambiar(.ejemplo) { $0.fase = .enCurso; $0.paso = 5; $0.partes["foco"] = Date() }

        let nueva = try #require(await EjemploTutorial.reiniciar(empresa: primera.id, model: model, instalador: instalador,
                                                              almacen: almacen, appSupport: base))
        #expect(nueva.id != primera.id)
        #expect(try EjemploTutorial.huellas(de: destino) == pristinas)
        #expect(almacen.estado(.ejemplo).fase == .sinEmpezar)
        // Lo de antes no se borró: está en la Papelera (de prueba).
        #expect(try FileManager.default.contentsOfDirectory(atPath: papelera.path).count == 1)
        // Y el nuevo ejemplo vuelve con su puesta en marcha hecha.
        #expect(AlmacenPuesta(vaultID: nueva.id, appSupport: base).leer()?.terminada == true)
    }

    @Test("El extracto de ejemplo va fuera de la carpeta y no repite movimientos de Ribera")
    func extractoDeEjemplo() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-extracto-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let url = try #require(EjemploTutorial.extractoDeEjemplo(appSupport: base))
        #expect(url.lastPathComponent == EjemploTutorial.nombreExtracto)
        let foto = VaultSnapshot.read(root: SesionEscrituraTests.ribera)
        let cuenta = try #require(RegistrosFinanzas(snapshot: foto).cuentas.first { $0.carpeta.name == "cuenta-corriente-banco-demo" })
        let previa = try ImportadorExtracto(snapshot: foto).vistaPrevia(
            try Data(contentsOf: url), nombre: url.lastPathComponent, cuenta: cuenta, adivinarFormato: false)
        #expect(previa.nuevas.count == 2)
        #expect(previa.yaImportadas.isEmpty)
    }
}
