import SwiftUI
import TLSCore
import TLSDesign

// Rol areas-a (F2). El `init` es contrato con `AreaScaffold` (docs/F2-CONTRATOS.md §2). PLAN §6.5 y SISTEMAS §4.2:
// Cronograma de proyectos internos de las 6 áreas agrupados por objetivo («Sin objetivo» en gris; arrastrar corre al
// lunes) · Objetivos con su ritmo · Mapa 6×6 con el cuello en texto · Cronología de decisiones. Arriba, DIR-DEC14 y
// DIR-OBJ. Acciones rápidas: Registrar decisión · Plan de 4 semanas para el cuello (con tu OK).

/// Pestaña Operación de Dirección.
struct DireccionOperacion: View {
    let contexto: ContextoArea
    let sesion: VaultSession

    @State private var carga: CargaOperacion<DatosDireccion>
    @State private var hoja: Hoja?
    @State private var error: String?
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager

    enum Hoja: String, Identifiable {
        case decision, plan
        var id: String { rawValue }
    }

    static let secciones = ["Cronograma", "Objetivos", "Mapa", "Decisiones"]
    static let clave = "direccion.vista"

    init(contexto: ContextoArea, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
        _carga = State(initialValue: CargaOperacion(sesion: sesion) { foto, hoy in DatosDireccion.calcular(foto: foto, hoy: hoy) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let d = carga.datos {
                contenido(d)
            } else {
                CargandoOperacion(texto: "Leyendo proyectos, objetivos y decisiones…")
            }
        }
        .task(id: sesion.revision) { await carga.cargar() }
        .sheet(item: $hoja) { h in hojaVista(h) }
        .accessibilityIdentifier("area.operacion.direccion")
    }

    @ViewBuilder
    private func contenido(_ d: DatosDireccion) -> some View {
        FranjaCifras(cifras: d.cifras)
        HStack(spacing: TLSEspacio.e8) {
            Button { hoja = .decision } label: { Label("Registrar decisión", systemImage: "signpost.right.and.left") }
                .tlsBoton(.secundario)
                .disabled(carga.motivoSoloLectura != nil)
                .help(carga.motivoSoloLectura ?? "Añade una línea a Decisiones.md")
                .accessibilityIdentifier("direccion.registrarDecision")
                .tutorialAnchor(.direccionRegistrarDecision)
            Button { hoja = .plan } label: { Label("Plan de 4 semanas para el cuello", systemImage: "calendar.badge.plus") }
                .tlsBoton(.secundario)
                .disabled(d.plan == nil)
                .help(d.plan == nil ? "No hay cuello: ninguna área frena a las demás" : "Propone tres acciones y una revisión; nada se crea sin tu OK")
                .accessibilityIdentifier("direccion.planCuello")
            Spacer(minLength: 0)
        }
        if let error { AvisoEnLinea(error, estado: .mal) }
        SeccionesOperacion(area: .direccion, clave: Self.clave, secciones: secciones(d))
        switch SeccionesOperacion.elegida(nav, area: .direccion, clave: Self.clave, secciones: Self.secciones) {
        case "Objetivos":
            BloqueOperacion("Objetivos con su ritmo", detalle: "El ritmo compara lo conseguido con lo que tocaría a día de hoy.") {
                ObjetivosDireccion(objetivos: d.objetivos, proyectos: d.proyectosPorObjetivo, hoy: d.hoy) { r in abrir(r) }
            }
        case "Mapa":
            BloqueOperacion("Mapa de las seis áreas", detalle: "Cada área en su etapa, calculada con lo que tienes montado. El cuello es la que frena a las demás.") {
                MapaMadurezVista(mapa: d.mapa)
            }
        case "Decisiones":
            BloqueOperacion("Cronología de decisiones", detalle: "De Decisiones.md: cada decisión una vez, con su porqué. Lo superado queda marcado, nunca se borra.") {
                CronologiaDecisiones(decisiones: d.decisiones, hoy: d.hoy)
            }
        default:
            cronograma(d)
        }
    }

    private func secciones(_ d: DatosDireccion) -> [PestanaCapsula] {
        let atencion = d.cronograma.barras.filter { $0.atencion != nil }.count
        return [
            PestanaCapsula(id: "Cronograma", titulo: "Cronograma", contador: d.cronograma.barras.isEmpty ? nil : d.cronograma.barras.count,
                           urgente: atencion > 0 ? .atencion : nil),
            PestanaCapsula(id: "Objetivos", titulo: "Objetivos", contador: d.objetivos.isEmpty ? nil : d.objetivos.count),
            PestanaCapsula(id: "Mapa", titulo: "Mapa"),
            PestanaCapsula(id: "Decisiones", titulo: "Decisiones", contador: d.decisiones.isEmpty ? nil : d.decisiones.count),
        ]
    }

    @ViewBuilder
    private func cronograma(_ d: DatosDireccion) -> some View {
        let atenciones = d.cronograma.barras.filter { $0.atencion != nil }
        BloqueOperacion("Cronograma de proyectos internos",
                        detalle: "Los proyectos de las seis áreas por objetivo. Arrastra una barra para moverla o su borde para cambiar el fin; si cae en fin de semana, pasa al lunes.") {
            if d.cronograma.vacio {
                Text("Aún no hay proyectos internos abiertos. Un proyecto interno vive en la carpeta Proyectos de su área.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                CronogramaVista(cronograma: d.cronograma, motivoSoloLectura: carga.motivoSoloLectura,
                                alMover: { b, i, f in hacer { await AccionesDireccion.mover(b, inicio: i, fin: f, sesion: sesion, deshacer: undoManager) } },
                                alAbrir: { b in abrir(b.ruta) })
            }
        }
        .accessibilityIdentifier("direccion.cronograma")
        if !atenciones.isEmpty {
            BloqueOperacion("En curso sin objetivo", detalle: "Se guardaron igual. Si los cuelgas de un objetivo, cuentan en su ritmo.") {
                AtencionesDIR03(barras: atenciones, objetivos: d.objetivosAbiertos, motivoSoloLectura: carga.motivoSoloLectura,
                                alColgar: { b, o in hacer { await AccionesDireccion.colgar(b, de: o, sesion: sesion, deshacer: undoManager) } },
                                alSeguirSin: { b in hacer { await AccionesDireccion.seguirSinObjetivo(b, sesion: sesion, deshacer: undoManager) } })
            }
            .accessibilityIdentifier("direccion.dir03")
        }
    }

    @ViewBuilder
    private func hojaVista(_ h: Hoja) -> some View {
        switch h {
        case .decision:
            RegistrarDecisionHoja(hoy: sesion.hoy, motivoSoloLectura: carga.motivoSoloLectura) { nueva in
                await AccionesDireccion.registrar(nueva, sesion: sesion, deshacer: undoManager)
            }
        case .plan:
            if let plan = carga.datos?.plan {
                PlanCuelloHoja(plan: plan, hoy: sesion.hoy, motivoSoloLectura: carga.motivoSoloLectura) { semanas in
                    await AccionesDireccion.crearPlan(plan, semanas: semanas, sesion: sesion, deshacer: undoManager)
                }
            }
        }
    }

    private func abrir(_ ruta: VaultPath) { navegar(sesion.destino(para: ruta), modo: .automatico) }

    private func hacer(_ accion: @escaping () async -> String?) {
        error = nil
        Task { error = await accion() }
    }
}
