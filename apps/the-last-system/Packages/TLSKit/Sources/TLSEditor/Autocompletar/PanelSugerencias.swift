import AppKit
import Observation
import SwiftUI
import TLSDesign

/// Estado de la lista de sugerencias (lo pinta `ListaSugerencias`).
@Observable @MainActor
final class EstadoSugerencias {
    var disparo: DisparoEnlace?
    var sugerencias: [SugerenciaEnlace] = []
    var elegida = 0
    var buscando = false
    var elegir: (SugerenciaEnlace) -> Void = { _ in }
}

/// La lista que aparece bajo el cursor al escribir `[[` o `](`.
struct ListaSugerencias: View {
    let estado: EstadoSugerencias

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            if estado.sugerencias.isEmpty {
                Text(estado.buscando ? "Buscando…" : "Ninguna nota coincide. Sigue escribiendo o borra los corchetes.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36, alignment: .leading)
            }
            ForEach(Array(estado.sugerencias.enumerated()), id: \.element.id) { i, s in
                Button {
                    estado.elegir(s)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.simbolo)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(i == estado.elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.titulo).tlsTexto(TLSTipo.interfazFuerte).lineLimit(1)
                            if let detalle = s.porOtroNombre.map({ "También «\($0)»" }) ?? s.detalle {
                                Text(detalle).tlsTexto(TLSTipo.secundario).lineLimit(1)
                                    .foregroundStyle(i == estado.elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(i == estado.elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                        .fill(i == estado.elegida ? TLSPaleta.principal.color : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.titulo + (s.detalle.map { ", \($0)" } ?? ""))
                .accessibilityAddTraits(i == estado.elegida ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 360, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.superficieElevada.color))
        .overlay(forma.strokeBorder(TLSPaleta.separador.color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notas para enlazar")
    }
}

/// El autocompletado de enlaces: detecta `[[` y `](`, pide sugerencias y escribe el enlace elegido.
@MainActor
final class ControladorSugerencias {
    let estado = EstadoSugerencias()
    private weak var vista: NSTextView?
    private var panel: NSPanel?
    private var tarea: Task<Void, Never>?
    weak var proveedor: AutocompletarEnlaces?

    init(vista: NSTextView) {
        self.vista = vista
        estado.elegir = { [weak self] s in self?.aceptar(s) }
    }

    var abierto: Bool { estado.disparo != nil }

    /// Tras cada cambio de texto o de cursor.
    func actualizar() {
        guard let vista, vista.isEditable, proveedor != nil else { cerrar(); return }
        let sel = vista.selectedRange()
        guard sel.length == 0,
              let d = DisparoEnlace.detectar(en: vista.textStorage?.mutableString ?? "", cursor: sel.location) else {
            cerrar()
            return
        }
        let cambio = d != estado.disparo
        estado.disparo = d
        guard cambio else { return }
        estado.buscando = true
        tarea?.cancel()
        tarea = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self, let proveedor = self.proveedor else { return }
            let lista = await proveedor.sugerencias(d.consulta, disparador: d.disparador)
            guard !Task.isCancelled, self.estado.disparo == d else { return }
            self.estado.sugerencias = Array(lista.prefix(8))
            self.estado.elegida = 0
            self.estado.buscando = false
            self.mostrar()
        }
        mostrar()
    }

    /// Flechas, ↩, ⇥ y Esc mientras la lista está abierta. `true` si se ha usado.
    func comando(_ selector: Selector) -> Bool {
        guard abierto else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            if !estado.sugerencias.isEmpty { estado.elegida = (estado.elegida + 1) % estado.sugerencias.count }
            return true
        case #selector(NSResponder.moveUp(_:)):
            if !estado.sugerencias.isEmpty {
                estado.elegida = (estado.elegida - 1 + estado.sugerencias.count) % estado.sugerencias.count
            }
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            guard estado.sugerencias.indices.contains(estado.elegida) else { cerrar(); return false }
            aceptar(estado.sugerencias[estado.elegida])
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cerrar()
            return true
        default:
            return false
        }
    }

    /// Escribe el enlace elegido (con Deshacer, como si se hubiera tecleado).
    func aceptar(_ s: SugerenciaEnlace) {
        guard let vista, let d = estado.disparo, let proveedor else { cerrar(); return }
        let texto: NSString = vista.textStorage?.mutableString ?? ""
        let r = d.rangoSustitucion(en: texto, cursor: vista.selectedRange().location)
        let insercion = proveedor.insercion(para: s, disparador: d.disparador, textoVisible: d.textoVisible)
        cerrar()
        vista.insertText(insercion, replacementRange: r)
    }

    func cerrar() {
        tarea?.cancel()
        tarea = nil
        estado.disparo = nil
        estado.sugerencias = []
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func mostrar() {
        guard let vista, let ventana = vista.window, ventana.isVisible, let d = estado.disparo else { return }
        let p = panel ?? crearPanel()
        panel = p
        let caret = vista.firstRect(forCharacterRange: NSRange(location: d.inicio, length: 0), actualRange: nil)
        let tamano = (p.contentView as? NSHostingView<ListaSugerencias>)?.fittingSize ?? NSSize(width: 372, height: 200)
        p.setContentSize(tamano)
        p.setFrameOrigin(NSPoint(x: caret.minX - 8, y: caret.minY - tamano.height - 4))
        if p.parent == nil { ventana.addChildWindow(p, ordered: .above) }
        p.orderFront(nil)
    }

    private func crearPanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 372, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.level = .popUpMenu
        let hosting = NSHostingView(rootView: ListaSugerencias(estado: estado))
        hosting.sizingOptions = [.intrinsicContentSize]
        p.contentView = hosting
        return p
    }
}
