import AppKit
import SwiftUI
import TLSCore
import TLSDesign

// Hoy (PLAN §6.2, DISENO §6, maqueta M2-Hoy; F2 · rol hoy-decisiones). El `init` es contrato con el enrutador
// (docs/F2-CONTRATOS.md §2). Las pruebas usan `HoyPantalla.saludo(_:calendario:)` y `HoyPantalla.fechaLarga(_:)`.
//
// De arriba abajo: la cabecera azul noche (fecha de la carpeta, saludo y la frase del día) y, al lado, **el único**
// destacado violeta (tu foco, con sus cinco preguntas, la recomendación y su botón); «Revisar» si hay conflictos o
// fichas repetidas; «Pide tu decisión» (como mucho 3, insignia magenta y «Ver todas»); **Alertas, solo si hay algo en
// rojo**; tu inicio con sus módulos (caja, ritmo, tu semana, lo que cabe hoy…); y la línea de Mika, determinista (los
// asistentes llegan en F4). Mientras la puesta en marcha no esté terminada, debajo de la cabecera sale «Seguir con la
// puesta en marcha · paso N de 9» con «Quedan ~N min» (F3, `Shell/PuestaDeLaEmpresa`).

/// Hoy.
struct HoyPantalla: View {
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar
    /// La puesta en marcha a medias (F3): «Seguir con la puesta en marcha · paso N de 9».
    @State private var puesta: ProgresoPuestaEnMarcha?

    init(sesion: VaultSession) {
        self.sesion = sesion
    }

    private var almacen: AlmacenHoy { AlmacenHoy.de(sesion) }

    var body: some View {
        let datos = almacen.datos
        ContenedorPantalla(destino: .hoy) {
            if let datos {
                contenido(datos)
            } else {
                arriba(nil)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo tu empresa…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
        .task(id: sesion.revision) {
            puesta = AvisoPuestaEnMarcha.progreso(de: sesion)
            await almacen.actualizar()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            puesta = AvisoPuestaEnMarcha.progreso(de: sesion)
        }
        .tlsPantalla("Hoy")
        .accessibilityIdentifier("pantalla.hoy")
    }

    @ViewBuilder
    private func contenido(_ d: DatosHoy) -> some View {
        let secciones = d.secciones(hayQueRevisar: sesion.hayQueRevisar)
        arriba(d)
        AvisoPuestaEnMarcha(sesion: sesion, progreso: puesta)
        if secciones.contains(.revisar) { revisar }
        PideTuDecision(datos: d, sesion: sesion)
        if secciones.contains(.alertas) { AlertasHoy(alertas: d.alertas, sesion: sesion) }
        InicioModulos(inicio: .hoy, datos: d.modulos, sesion: sesion, titulo: "Tu inicio", hora: d.hora, minutosAhora: d.minutosAhora)
        LineaMikaHoy(datos: d, sesion: sesion)  // F4 · rol mika: la línea de Mika con su última revisión (Mika/LineaMikaHoy)
    }

    /// La cabecera y el foco, uno al lado del otro si caben (como en M2-Hoy); si no, uno encima del otro.
    @ViewBuilder
    private func arriba(_ d: DatosHoy?) -> some View {
        ViewThatFits(in: .horizontal) {
            RepartoFlex(bases: [340, 460], pesos: [1, 1.6], espacio: TLSEspacio.entreMosaicos) {
                CabeceraHoy(datos: d, sesion: sesion)
                foco(d)
            }
            VStack(spacing: TLSEspacio.entreMosaicos) {
                CabeceraHoy(datos: d, sesion: sesion)
                foco(d)
            }
        }
    }

    @ViewBuilder
    private func foco(_ d: DatosHoy?) -> some View {
        if let d {
            FocoHoy(tarjeta: d.foco, hoy: d.hoy, codigo: d.panel.foto.tareas.first { $0.tarea.ruta == d.foco.contexto }?.tarea.numero,
                    sesion: sesion, enAlerta: d.foco.area.map(d.panel.enAlerta) ?? d.panel.hayRojo)
                .id(d.foco.id)
        } else {
            DestacadoVacio(rotulo: "Tu foco de hoy", texto: "Mirando qué es lo más importante hoy…").frame(minHeight: 220)
        }
    }

    private var revisar: some View {
        let n = sesion.tarjetas.count
        let texto = n == 0 ? (sesion.textoRecuperacion ?? "") :
            "\(TLSFormat.cuenta(n, "cosa necesita", "cosas necesitan")) que elijas: versiones distintas de una nota o fichas repetidas."
        return HStack(spacing: TLSEspacio.e12) {
            Image(systemName: TLSEstado.atencion.simbolo)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TLSPaleta.atencion.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Revisar").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                Text(texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Revisar") { navegar(.revisar, modo: .entrar) }.tlsBoton(.principal)
        }
        .padding(TLSEspacio.e16)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hoy.revisar")
    }

    // MARK: Textos

    static func saludo(_ fecha: Date, calendario: Calendar = .tlsGregoriano) -> String {
        switch calendario.component(.hour, from: fecha) {
        case 6..<14: "Buenos días"
        case 14..<21: "Buenas tardes"
        default: "Buenas noches"
        }
    }

    /// «Jueves, 22 de octubre» de un día de la carpeta.
    static func fechaLarga(_ dia: LocalDate) -> String {
        let s = "\(diasLargos[dia.weekday - 1]), \(dia.day) de \(FormatoBase.mesesLargos[dia.month - 1])"
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// 1 = lunes, como `LocalDate.weekday`.
    static let diasLargos = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

    /// «Jueves, 22 de octubre».
    static func fechaLarga(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.calendar = .tlsGregoriano
        f.dateFormat = "EEEE, d 'de' MMMM"
        let s = f.string(from: fecha)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

/// Dos (o más) vistas en fila, como `flex: peso 1 base` de la maqueta: cada una parte de su base y el ancho que sobra se
/// reparte según su peso; todas con el alto de la más alta. Su ancho ideal es la suma de las bases (para `ViewThatFits`).
struct RepartoFlex: Layout {
    var bases: [CGFloat]
    var pesos: [CGFloat]
    var espacio: CGFloat

    private func anchos(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let b = (0..<n).map { $0 < bases.count ? bases[$0] : 0 }
        let p = (0..<n).map { $0 < pesos.count ? pesos[$0] : 1 }
        let sobra = max(0, total - b.reduce(0, +) - espacio * CGFloat(max(0, n - 1)))
        let suma = max(p.reduce(0, +), 0.0001)
        return (0..<n).map { b[$0] + sobra * p[$0] / suma }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let n = subviews.count
        let ideal = bases.prefix(n).reduce(0, +) + espacio * CGFloat(max(0, n - 1))
        let total = proposal.width ?? ideal
        let w = anchos(total, n)
        let alto = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = anchos(bounds.width, subviews.count)
        var x = bounds.minX
        for (s, ancho) in zip(subviews, w) {
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: ancho, height: bounds.height))
            x += ancho + espacio
        }
    }
}
