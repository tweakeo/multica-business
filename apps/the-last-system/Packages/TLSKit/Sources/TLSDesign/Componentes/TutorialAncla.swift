import AppKit
import Observation
import SwiftUI

// Tutorial (PLAN §6.8, F3): anclas que el recorrido puede señalar con el velo y su hueco.
//
// Cada pantalla marca sus sitios con una línea, `.tutorialAnchor("hoy.foco")`. El ancla no cambia nada de la vista:
// pone detrás una sonda de AppKit invisible (sin clics ni VoiceOver) que sabe dónde está en su ventana. Así el
// hueco sale bien aunque la vista viva en otra columna (barra lateral, detalle) o dentro de un desplazamiento,
// donde las preferencias de SwiftUI no llegan a la raíz. Si un paso pide un ancla que no está en pantalla, el
// paso enseña solo su texto, sin hueco.

/// Nombre de un sitio de la pantalla que el tutorial puede señalar.
public struct TutorialAnclaID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
}

public extension View {
    /// Marca esta vista como un sitio que el tutorial puede señalar (velo con hueco y burbuja). No cambia su
    /// aspecto ni su comportamiento: es una línea en cada pantalla.
    func tutorialAnchor(_ id: TutorialAnclaID) -> some View {
        modifier(AnclaTutorialModifier(id: id))
    }
}

struct AnclaTutorialModifier: ViewModifier {
    let id: TutorialAnclaID

    func body(content: Content) -> some View {
        content
            .background(SondaAncla(id: id).allowsHitTesting(false).accessibilityHidden(true))
            // Desplazar o redimensionar mueve el ancla en la ventana sin cambiar su marco de AppKit.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { _ in
                TutorialAnclas.compartidas.movida()
            }
    }
}

/// Las anclas que hay ahora en pantalla, por ventana. Lo leen el velo (dónde va el hueco) y el recorrido (qué
/// sitio acaba de aparecer). Solo en el hilo principal.
@MainActor
@Observable
public final class TutorialAnclas {
    public static let compartidas = TutorialAnclas()

    /// Sube cuando un ancla aparece, se va o se mueve (para volver a pintar el hueco).
    public private(set) var version = 0

    @ObservationIgnored private var sondas: [ObjectIdentifier: Debil] = [:]
    @ObservationIgnored private var avisoPendiente = false

    private final class Debil {
        weak var sonda: SondaAnclaVista?
        init(_ s: SondaAnclaVista) { sonda = s }
    }

    public init() {}

    func entrar(_ s: SondaAnclaVista) {
        sondas[ObjectIdentifier(s)] = Debil(s)
        movida()
    }

    func salir(_ s: SondaAnclaVista) {
        guard sondas.removeValue(forKey: ObjectIdentifier(s)) != nil else { return }
        movida()
    }

    /// Algo se movió: se avisa una vez, después de la pasada de maquetación en curso (nunca durante ella).
    public func movida() {
        guard !avisoPendiente else { return }
        avisoPendiente = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.avisoPendiente = false
                self.sondas = self.sondas.filter { $0.value.sonda?.window != nil }
                self.version &+= 1
            }
        }
    }

    private func vivas(en ventana: NSWindow?) -> [SondaAnclaVista] {
        sondas.values.compactMap(\.sonda).filter { $0.window != nil && (ventana == nil || $0.window === ventana) }
    }

    /// Anclas presentes en una ventana (todas si `ventana` es `nil`).
    public func presentes(en ventana: NSWindow?) -> Set<TutorialAnclaID> {
        Set(vivas(en: ventana).filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.id))
    }

    /// Rectángulo del ancla en las coordenadas de `vista` (origen arriba a la izquierda), si está en su misma
    /// ventana. Con varias vistas con la misma ancla, la que más se ve.
    public func rectangulo(_ id: TutorialAnclaID, respectoA vista: NSView) -> CGRect? {
        guard let ventana = vista.window else { return nil }
        let candidatos = vivas(en: ventana).filter { $0.id == id && !$0.isHiddenOrHasHiddenAncestor }
        let rects = candidatos.map { s -> CGRect in
            let enVentana = s.convert(s.bounds, to: nil)
            var r = vista.convert(enVentana, from: nil)
            if !vista.isFlipped { r.origin.y = vista.bounds.height - r.maxY }
            return r
        }
        return rects.max { $0.intersection(vista.bounds).area < $1.intersection(vista.bounds).area }
    }

    /// `true` si el punto (coordenadas de ventana, origen abajo a la izquierda, como `NSEvent.locationInWindow`)
    /// cae dentro del ancla en esa ventana.
    public func contiene(_ id: TutorialAnclaID, punto: NSPoint, en ventana: NSWindow) -> Bool {
        vivas(en: ventana).contains { s in
            s.id == id && !s.isHiddenOrHasHiddenAncestor && s.convert(s.bounds, to: nil).contains(punto)
        }
    }
}

extension CGRect {
    /// Superficie (0 si está vacío o es nulo).
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

/// Sonda invisible detrás de la vista anclada.
struct SondaAncla: NSViewRepresentable {
    let id: TutorialAnclaID

    func makeNSView(context: Context) -> SondaAnclaVista { SondaAnclaVista(id: id) }

    func updateNSView(_ vista: SondaAnclaVista, context: Context) {
        if vista.id != id {
            vista.id = id
            TutorialAnclas.compartidas.movida()
        }
    }

    static func dismantleNSView(_ vista: SondaAnclaVista, coordinator: ()) {
        TutorialAnclas.compartidas.salir(vista)
    }
}

/// La vista de AppKit de la sonda: no se pinta, no recibe clics y VoiceOver no la ve.
final class SondaAnclaVista: NSView {
    var id: TutorialAnclaID

    init(id: TutorialAnclaID) {
        self.id = id
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { TutorialAnclas.compartidas.entrar(self) } else { TutorialAnclas.compartidas.salir(self) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        TutorialAnclas.compartidas.movida()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        TutorialAnclas.compartidas.movida()
    }
}

/// Anuncio hablado para VoiceOver (cambio de paso del tutorial, hito conseguido).
@MainActor
public enum TutorialAnuncio {
    public static func anunciar(_ texto: String) {
        guard !texto.isEmpty else { return }
        let destino: Any = NSApp?.keyWindow ?? NSApp as Any
        NSAccessibility.post(element: destino, notification: .announcementRequested,
                             userInfo: [.announcement: texto, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
