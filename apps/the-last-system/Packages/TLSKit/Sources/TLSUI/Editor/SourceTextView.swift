import AppKit
import OSLog
import SwiftUI
import TLSDesign

/// Texto fuente con estilo, no editable, en un `NSTextView` de TextKit 2.
///
/// Reglas (plan §6.6): `NSTextView(usingTextLayoutManager: true)` y nunca se toca `.layoutManager`
/// (acceder a él pasa la vista a TextKit 1). Se vigila `willSwitchToNSLayoutManagerNotification`.
struct SourceTextView: NSViewRepresentable {
    enum Mode: Equatable { case markdown, plain }

    let text: String
    let mode: Mode
    /// Tramos de estilo ya calculados fuera del hilo principal (`nil`: se calculan aquí si la nota es pequeña).
    var spans: [MarkdownSpan]? = nil
    /// Identidad de la lectura: el texto solo se sustituye cuando cambia.
    let identity: String
    let onLink: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = TLSTokens.fondoNS
        scroll.borderType = .noBorder

        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = TLSTokens.fondoNS
        textView.textContainerInset = NSSize(width: 28, height: 22)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: TLSTokens.enlaceNS,
            .cursor: NSCursor.pointingHand,
        ]
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("visor.texto")
        textView.setAccessibilityLabel("Contenido de la nota")

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.watchLayoutManagerSwitch(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onLink = onLink
        guard context.coordinator.identity != identity,
              let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.identity = identity
        let styled = mode == .markdown ? MarkdownStyler.attributed(markdown: text, spans: spans) : MarkdownStyler.plain(text)
        textView.textStorage?.setAttributedString(styled)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(.zero)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.stopWatching()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var identity: String?
        var onLink: (@MainActor (String) -> Void)?
        weak var textView: NSTextView?
        private var observer: NSObjectProtocol?
        private nonisolated static let log = Logger(subsystem: "es.thelast.system", category: "SourceTextView")

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let target: String? = switch link {
            case let s as String: s
            case let u as URL: u.absoluteString
            default: nil
            }
            if let target { onLink?(target) }
            return true
        }

        func watchLayoutManagerSwitch(_ textView: NSTextView) {
            observer = NotificationCenter.default.addObserver(
                forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: textView, queue: .main
            ) { _ in
                Self.log.fault("El visor ha pasado a TextKit 1: alguien ha tocado .layoutManager")
            }
        }

        func stopWatching() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
