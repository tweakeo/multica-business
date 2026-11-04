import AppKit

/// El `NSTextView` del editor. Siempre TextKit 2 (`init(usingTextLayoutManager: true)`); **nunca** se toca
/// `.layoutManager` (pasaría la vista a TextKit 1) y no se usa `NSTextTable`. Pasa al controlador los clics
/// en enlaces y casillas, las teclas propias y los cambios de foco, ventana, tamaño y apariencia.
final class VistaTextoMarkdown: NSTextView {
    weak var controlador: ControladorEditor?

    override func mouseDown(with event: NSEvent) {
        if controlador?.gestionarClic(event) == true { return }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        controlador?.actualizarPuntero(event)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        controlador?.actualizarPuntero(event)
    }

    override func keyDown(with event: NSEvent) {
        if controlador?.gestionarTecla(event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { controlador?.focoCambiado() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { controlador?.focoCambiado(perdido: true) }
        return ok
    }

    override func layout() {
        super.layout()
        controlador?.colocarIncrustaciones()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controlador?.ventanaCambiada(window)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        controlador?.aparienciaCambiada()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let ancho = frame.width
        super.setFrameSize(newSize)
        if abs(ancho - newSize.width) > 0.5 { controlador?.anchoCambiado() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        return controlador?.menuContextual(menu, evento: event) ?? menu
    }
}
