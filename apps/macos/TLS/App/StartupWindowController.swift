import AppKit

/// Small native window shown while the embedded stack starts.
final class StartupWindowController: NSWindowController {
    private let label = NSTextField(labelWithString: "Arrancando TLS…")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "TLS"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setStatus(_ text: String) { label.stringValue = text }
}
