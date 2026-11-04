import AppKit
import Markdown
import SwiftUI
import TLSDesign

/// El editor en SwiftUI: enseña la vista de un `ControladorEditor` (que guarda el texto y el estado y vive
/// lo que la pantalla). Teclear no pasa por el estado de SwiftUI: la pantalla se entera por
/// `controlador.alCambiarTexto`.
public struct EditorMarkdown: NSViewRepresentable {
    let controlador: ControladorEditor
    @Environment(\.tlsEscalaTexto) private var escala

    public init(controlador: ControladorEditor) {
        self.controlador = controlador
    }

    public func makeNSView(context: Context) -> NSScrollView {
        controlador.escala = escala
        return controlador.scroll
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        if controlador.escala != escala { controlador.escala = escala }
    }
}

/// Editor con enlace a un `String` (para trozos pequeños, como una sección de una ficha). Para una nota
/// entera, mejor `ControladorEditor` + `EditorMarkdown`: así teclear no actualiza SwiftUI en cada tecla.
public struct EditorTextoMarkdown: View {
    @Binding var texto: String
    let soloLectura: Bool
    let modo: ModoEditor
    weak var autocompletado: AutocompletarEnlaces?
    weak var resolutor: ResolutorEnlaces?
    weak var incrustaciones: ProveedorIncrustaciones?
    @State private var controlador = ControladorEditor()

    /// Los proveedores se guardan sin retener: quien los da los mantiene vivos.
    public init(texto: Binding<String>, soloLectura: Bool = false, modo: ModoEditor = .vivo,
                autocompletado: AutocompletarEnlaces? = nil, resolutor: ResolutorEnlaces? = nil,
                incrustaciones: ProveedorIncrustaciones? = nil) {
        self._texto = texto
        self.soloLectura = soloLectura
        self.modo = modo
        self.autocompletado = autocompletado
        self.resolutor = resolutor
        self.incrustaciones = incrustaciones
    }

    public var body: some View {
        EditorMarkdown(controlador: controlador)
            .onAppear {
                controlador.autocompletado = autocompletado
                controlador.resolutor = resolutor
                controlador.incrustaciones = incrustaciones
                controlador.cambiarModo(modo)
                controlador.soloLectura = soloLectura
                if controlador.texto != texto { controlador.cargar(texto) }
                controlador.alCambiarTexto = { [controlador] in
                    let nuevo = controlador.texto
                    if nuevo != texto { texto = nuevo }
                }
            }
            .onChange(of: texto) { _, nuevo in
                if nuevo != controlador.texto { controlador.sustituir(con: nuevo) }
            }
            .onChange(of: soloLectura) { _, nuevo in controlador.soloLectura = nuevo }
            .accessibilityLabel("Texto de la nota")
    }
}

/// Títulos `##` de un texto Markdown (para el índice de secciones y las pruebas del editor).
public enum SeccionesMarkdown {
    public static func titulos(_ texto: String, nivel: Int = 2) -> [String] {
        Document(parsing: texto).children.compactMap { ($0 as? Heading).flatMap { $0.level == nivel ? $0.plainText : nil } }
    }
}
