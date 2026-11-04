import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol areas-b. El `init` es contrato con `AreaScaffold` (docs/F2-CONTRATOS.md §2). PLAN §6.5: Calendario editorial ·
// Contenido en tablero de idea a publicado · Distribución y seguimiento · Conversaciones con «Proponer a Ventas».
// Acción rápida: Generar borrador de pieza (llega con los asistentes, F4). Se pinta dentro del andamio.

/// Las secciones de Marca › Operación (recordadas por pestaña de ventana en `"marca.seccion"`).
enum SeccionMarca: String, CaseIterable, Sendable {
    case calendario = "Calendario"
    case contenido = "Contenido"
    case distribucion = "Distribución"
    case conversaciones = "Conversaciones"
}

/// Pestaña Operación de Marca.
struct MarcaOperacion: View {
    let contexto: ContextoArea
    let sesion: VaultSession
    @State private var modelo: ModeloMarca
    @Environment(\.navegacion) private var nav

    init(contexto: ContextoArea, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
        _modelo = State(initialValue: ModeloMarca(sesion: sesion))
    }

    static let claveSeccion = "marca.seccion"

    private var seccion: SeccionMarca {
        nav?.recuerdo(de: .area(.marca)).extra[Self.claveSeccion].flatMap(SeccionMarca.init(rawValue:)) ?? .calendario
    }

    private func ir(_ s: SeccionMarca) {
        nav?.actualizarRecuerdo(de: .area(.marca)) { $0.extra[Self.claveSeccion] = s == .calendario ? nil : s.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            barra
            if let e = modelo.error { AvisoEnLinea(e, estado: .mal).accessibilityIdentifier("marca.error") }
            if let h = modelo.hecho { AvisoEnLinea(h, estado: .bien).accessibilityIdentifier("marca.hecho") }
            if let l = modelo.lectura {
                switch seccion {
                case .calendario: CalendarioMarca(lectura: l, modelo: modelo)
                case .contenido: TableroMarca(lectura: l, modelo: modelo)
                case .distribucion: DistribucionMarca(lectura: l, contexto: contexto)
                case .conversaciones: ConversacionesMarca(lectura: l, modelo: modelo)
                }
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo las piezas…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: sesion.revision) { await modelo.cargar() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("area.operacion.marca")
    }

    private var barra: some View {
        let l = modelo.lectura
        let nuevas = l?.conversaciones.filter { $0.estado == .nueva }.count ?? 0
        let pestanas = SeccionMarca.allCases.map { s -> PestanaCapsula in
            switch s {
            case .calendario: PestanaCapsula(id: s.rawValue, titulo: s.rawValue, contador: l.map { $0.piezas.filter { $0.dia != nil && $0.estado != .descartado }.count })
            case .contenido: PestanaCapsula(id: s.rawValue, titulo: s.rawValue, contador: l.map { $0.piezas.filter { $0.estado != .descartado }.count })
            case .distribucion: PestanaCapsula(id: s.rawValue, titulo: s.rawValue, contador: l.map { $0.publicadas.count })
            case .conversaciones: PestanaCapsula(id: s.rawValue, titulo: s.rawValue, contador: l.map { $0.conversaciones.count },
                                                 aviso: nuevas > 0 ? (numero: nuevas, palabra: "Nuevas") : nil)
            }
        }
        let selector = PestanasCapsula(seleccion: Binding(get: { seccion.rawValue }, set: { ir(SeccionMarca(rawValue: $0) ?? .calendario) }),
                                       pestanas: pestanas, atajosControl: false)
            .accessibilityLabel("Secciones de Marca")
            .accessibilityIdentifier("marca.secciones")
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                selector
                Spacer(minLength: TLSEspacio.e8)
                generar
            }
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                selector
                generar
            }
        }
    }

    /// «Generar borrador de pieza» (F4): un trabajo del asistente de Marca; el borrador te espera en Decisiones. Si no
    /// puede trabajar ahora (en reposo, en pausa o sin motor), el motivo a la vista.
    private var generar: some View {
        let motivo = PedirAAsistente.motivo(sesion, slug: "marca")
        return HStack(spacing: TLSEspacio.e8) {
            if let motivo {
                Text(motivo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await PedirAAsistente.encargar("marca", accion: "borrador-pieza", sesion: sesion, pantalla: "Marca › Operación") }
            } label: { Label("Generar borrador de pieza", systemImage: "sparkle") }
                .tlsBoton(.secundario)
                .disabled(motivo != nil)
                .help(motivo ?? "Lo prepara el asistente de Marca; el borrador te espera en Decisiones")
                .accessibilityHint(motivo ?? "Lo prepara el asistente de Marca")
                .accessibilityIdentifier("marca.accion.generar")
        }
    }
}
