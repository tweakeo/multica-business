import AppKit
import SwiftUI

// Velo con hueco y burbuja del tutorial (PLAN §6.8), con la estética de Mosaico v2: velo del color de detrás de
// las hojas, burbuja como la vista previa (superficie elevada, radio 16, sombra de nivel 2), botones propios y sin
// magenta. El velo solo deja pulsar dentro del hueco; sin ancla en pantalla no hay velo y la burbuja queda abajo a
// la derecha, sin tapar nada.

/// Un botón de la burbuja. La burbuja devuelve su `id` al pulsarlo.
public struct TutorialBoton: Hashable, Sendable, Identifiable {
    public enum Tipo: Hashable, Sendable { case principal, secundario, enlace }
    public let id: String
    public let titulo: String
    public let tipo: Tipo

    public init(id: String, titulo: String, tipo: Tipo = .secundario) {
        self.id = id; self.titulo = titulo; self.tipo = tipo
    }
}

/// Una línea de la lista de hitos dentro de la burbuja («Mueve una oportunidad · Hecho»).
public struct TutorialItem: Hashable, Sendable, Identifiable {
    public let id: String
    public let titulo: String
    public let marca: TutorialPasoVisible.Marca
    public init(id: String, titulo: String, marca: TutorialPasoVisible.Marca) {
        self.id = id; self.titulo = titulo; self.marca = marca
    }
}

/// Lo que enseña la capa del tutorial en un momento dado.
public struct TutorialPasoVisible: Hashable, Sendable, Identifiable {
    /// Cómo está el hito de este paso.
    public enum Marca: Hashable, Sendable {
        case ninguna
        case porHacer
        case hecho
        /// Hito que necesita los asistentes (⌘J, pausar): se explica, pero aún no se puede hacer.
        case llegaConLosAsistentes
    }

    public let id: String
    public let ancla: TutorialAnclaID?
    /// «Conoce la app · paso 3 de 12».
    public let rotulo: String
    public let titulo: String
    /// Dos o tres líneas.
    public let texto: String
    public let marca: Marca
    /// «3 de 8 hitos · Quedan ~6 min» (siempre visible).
    public let progreso: String
    public let botones: [TutorialBoton]
    /// Con hueco, el velo solo deja pulsar dentro de él.
    public let bloquearFuera: Bool
    /// Lista de hitos con su estado (al empezar y al terminar el recorrido).
    public let items: [TutorialItem]

    public init(id: String, ancla: TutorialAnclaID?, rotulo: String, titulo: String, texto: String, marca: Marca = .ninguna,
                progreso: String, botones: [TutorialBoton], bloquearFuera: Bool = true, items: [TutorialItem] = []) {
        self.id = id; self.ancla = ancla; self.rotulo = rotulo; self.titulo = titulo; self.texto = texto
        self.marca = marca; self.progreso = progreso; self.botones = botones; self.bloquearFuera = bloquearFuera
        self.items = items
    }

    /// Lo que dice VoiceOver al llegar al paso.
    public var anuncio: String {
        var partes = [rotulo, titulo, texto]
        switch marca {
        case .hecho: partes.append("Hecho.")
        case .llegaConLosAsistentes: partes.append("Llega con los asistentes.")
        case .ninguna, .porHacer: break
        }
        partes.append(progreso)
        return partes.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

/// Dónde va la burbuja: debajo del hueco si cabe; si no, encima, a la derecha o a la izquierda; siempre dentro.
public enum TutorialColocacion {
    public static let margen: CGFloat = 16
    public static let separacion: CGFloat = 14

    public static func origen(burbuja tamano: CGSize, hueco: CGRect?, en espacio: CGSize) -> CGPoint {
        let m = margen
        func dentro(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, m), max(m, espacio.width - tamano.width - m)),
                    y: min(max(p.y, m), max(m, espacio.height - tamano.height - m)))
        }
        guard let h = hueco, !h.isNull, !h.isEmpty else {
            return dentro(CGPoint(x: espacio.width - tamano.width - 24, y: espacio.height - tamano.height - 24))
        }
        let s = separacion
        if h.maxY + s + tamano.height + m <= espacio.height {
            return dentro(CGPoint(x: h.minX, y: h.maxY + s))
        }
        if h.minY - s - tamano.height >= m {
            return dentro(CGPoint(x: h.minX, y: h.minY - s - tamano.height))
        }
        if h.maxX + s + tamano.width + m <= espacio.width {
            return dentro(CGPoint(x: h.maxX + s, y: h.minY))
        }
        if h.minX - s - tamano.width >= m {
            return dentro(CGPoint(x: h.minX - s - tamano.width, y: h.minY))
        }
        // No cabe al lado: abajo a la derecha, encima del velo.
        return dentro(CGPoint(x: espacio.width - tamano.width - 24, y: espacio.height - tamano.height - 24))
    }

    /// El hueco: el ancla con 6 pt de aire, recortado a lo que se ve. `nil` si no se ve nada.
    public static func hueco(_ ancla: CGRect?, en espacio: CGSize) -> CGRect? {
        guard let a = ancla, !a.isNull, !a.isEmpty else { return nil }
        let visible = a.insetBy(dx: -6, dy: -6).intersection(CGRect(origin: .zero, size: espacio))
        return visible.isNull || visible.width < 8 || visible.height < 8 ? nil : visible
    }
}

/// La capa entera: velo con hueco y burbuja. Va encima del contenido de la ventana.
public struct TutorialCapa: View {
    let paso: TutorialPasoVisible?
    let alPulsar: (String) -> Void
    @State private var sonda = ReferenciaVista()
    @State private var tamanoBurbuja = CGSize(width: 380, height: 220)
    @Environment(\.accessibilityReduceMotion) private var reducir
    private var anclas: TutorialAnclas { .compartidas }

    public init(paso: TutorialPasoVisible?, alPulsar: @escaping (String) -> Void) {
        self.paso = paso
        self.alPulsar = alPulsar
    }

    public var body: some View {
        GeometryReader { geo in
            // Solo un paso con ancla escucha a las anclas.
            let _ = paso?.ancla != nil ? anclas.version : 0
            let hueco = paso.flatMap { p in
                p.ancla.flatMap { id in sonda.vista.flatMap { anclas.rectangulo(id, respectoA: $0) } }
            }.flatMap { TutorialColocacion.hueco($0, en: geo.size) }
            ZStack(alignment: .topLeading) {
                if let paso {
                    if let hueco {
                        VeloConHueco(hueco: hueco)
                            .fill(TLSPaleta.velo.color, style: FillStyle(eoFill: true))
                            .contentShape(VeloConHueco(hueco: hueco), eoFill: true)
                            .allowsHitTesting(paso.bloquearFuera)
                            .accessibilityHidden(true)
                        RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
                            .strokeBorder(TLSPaleta.principal.color, lineWidth: 2)
                            .frame(width: hueco.width, height: hueco.height)
                            .offset(x: hueco.minX, y: hueco.minY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    let origen = TutorialColocacion.origen(burbuja: tamanoBurbuja, hueco: hueco, en: geo.size)
                    TutorialBurbuja(paso: paso, alPulsar: alPulsar)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { tamanoBurbuja = $0 }
                        .offset(x: origen.x, y: origen.y)
                        .id(paso.id)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(SondaCapa(referencia: sonda).allowsHitTesting(false).accessibilityHidden(true))
        .animation(reducir ? nil : .easeOut(duration: 0.2), value: paso?.id)
        .onChange(of: paso?.id, initial: true) { _, nuevo in
            if nuevo != nil, let paso { TutorialAnuncio.anunciar(paso.anuncio) }
        }
    }
}

/// Rectángulo entero con el hueco redondeado (se rellena con la regla par-impar).
struct VeloConHueco: Shape {
    let hueco: CGRect

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRoundedRect(in: hueco, cornerSize: CGSize(width: TLSRadio.bloque, height: TLSRadio.bloque), style: .continuous)
        return p
    }
}

/// La burbuja del paso: rótulo, título, dos o tres líneas, el estado del hito, el progreso y los botones.
public struct TutorialBurbuja: View {
    let paso: TutorialPasoVisible
    let alPulsar: (String) -> Void
    @AccessibilityFocusState private var focoVoiceOver: Bool

    public init(paso: TutorialPasoVisible, alPulsar: @escaping (String) -> Void) {
        self.paso = paso
        self.alPulsar = alPulsar
    }

    public static let ancho: CGFloat = 380

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.previa, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text(paso.rotulo)
                .tlsTexto(TLSTipo.rotulo)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
            Text(paso.titulo)
                .tlsTexto(TLSTipo.tituloSeccion)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focoVoiceOver)
            Text(paso.texto)
                .tlsTexto(TLSTipo.lectura)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            switch paso.marca {
            case .hecho: PastillaEstado(.bien, palabra: "Hecho")
            case .llegaConLosAsistentes: PastillaEstado(.sinDato, palabra: "Llega con los asistentes")
            case .ninguna, .porHacer: EmptyView()
            }
            if !paso.items.isEmpty { lista }
            let acciones = paso.botones.filter { $0.tipo != .enlace }
            let enlaces = paso.botones.filter { $0.tipo == .enlace }
            if !acciones.isEmpty {
                HStack(spacing: TLSEspacio.e8) {
                    ForEach(acciones) { b in boton(b) }
                }
            }
            if !enlaces.isEmpty {
                HStack(spacing: TLSEspacio.e4) {
                    ForEach(enlaces) { b in boton(b) }
                }
            }
            Text(paso.progreso)
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityIdentifier("tutorial.progreso")
        }
        .padding(TLSEspacio.e20)
        .frame(width: Self.ancho, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficieElevada.color))
        .tlsSombra(.dos, forma: forma)
        .contentShape(forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tutorial: \(paso.titulo)")
        .accessibilityIdentifier("tutorial.burbuja")
        .onAppear { focoVoiceOver = true }
    }

    /// Los hitos, uno por línea, con su estado en palabra e icono (el color nunca va solo).
    private var lista: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(paso.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: Self.simbolo(item.marca))
                        .foregroundStyle(Self.color(item.marca))
                        .accessibilityHidden(true)
                    Text(item.titulo)
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(Self.palabra(item.marca))
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(TLSEspacio.e12)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .accessibilityIdentifier("tutorial.hitos")
    }

    static func simbolo(_ m: TutorialPasoVisible.Marca) -> String {
        switch m {
        case .hecho: TLSEstado.bien.simbolo
        case .llegaConLosAsistentes: "clock"
        case .ninguna, .porHacer: "circle"
        }
    }

    static func color(_ m: TutorialPasoVisible.Marca) -> Color {
        switch m {
        case .hecho: TLSPaleta.bien.color
        case .llegaConLosAsistentes, .ninguna, .porHacer: TLSPaleta.textoSecundario.color
        }
    }

    static func palabra(_ m: TutorialPasoVisible.Marca) -> String {
        switch m {
        case .hecho: "Hecho"
        case .llegaConLosAsistentes: "Llega con los asistentes"
        case .ninguna, .porHacer: "Por hacer"
        }
    }

    /// Sin atajos de teclado: el tutorial convive con el editor (↩ y Esc son de quien escribe). Se llega con
    /// el tabulador y con VoiceOver.
    @ViewBuilder
    private func boton(_ b: TutorialBoton) -> some View {
        let base = Button(b.titulo) { alPulsar(b.id) }
            .accessibilityIdentifier("tutorial.boton.\(b.id)")
        switch b.tipo {
        case .principal: base.tlsBoton(.principal, alto: 36)
        case .secundario: base.tlsBoton(.secundario)
        case .enlace: base.tlsBoton(.enlace)
        }
    }
}

/// Guarda la vista de AppKit de la capa para pasar a sus coordenadas los rectángulos de las anclas.
@MainActor
final class ReferenciaVista {
    weak var vista: NSView?
}

struct SondaCapa: NSViewRepresentable {
    let referencia: ReferenciaVista

    func makeNSView(context: Context) -> NSView {
        let v = VistaSondaCapa()
        referencia.vista = v
        return v
    }

    func updateNSView(_ vista: NSView, context: Context) { referencia.vista = vista }
}

/// Vista de AppKit de la capa: en coordenadas de arriba abajo y sin clics.
final class VistaSondaCapa: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        TutorialAnclas.compartidas.movida()
    }
}
