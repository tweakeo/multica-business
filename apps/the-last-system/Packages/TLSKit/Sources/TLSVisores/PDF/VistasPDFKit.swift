import AppKit
import PDFKit
import SwiftUI
import TLSDesign

/// `PDFView` de solo lectura con el menú contextual de la app (Copiar, Buscar, Ajustar, Vista Previa,
/// Finder). No ofrece resaltar, anotar ni nada que cambie el documento.
public final class PDFViewTLS: PDFView {
    weak var controlador: ControladorPDF?
    private var objetivos: [ObjetivoMenu] = []

    override public func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "PDF")
        objetivos = []
        if let texto = currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !texto.isEmpty {
            agregar(menu, "Copiar") { [weak self] in self?.controlador?.copiarSeleccion() }
            let corto = texto.count > 24 ? String(texto.prefix(24)) + "…" : texto
            agregar(menu, "Buscar «\(corto)» en el PDF") { [weak self] in
                self?.controlador?.buscar(texto)
            }
            menu.addItem(.separator())
        }
        agregar(menu, "Ajustar a ancho") { [weak self] in self?.controlador?.ajustarAncho() }
        agregar(menu, "Ajustar a página") { [weak self] in self?.controlador?.ajustarPagina() }
        agregar(menu, "Tamaño real") { [weak self] in self?.controlador?.tamanoReal() }
        if let url = controlador?.url {
            menu.addItem(.separator())
            agregar(menu, "Abrir en Vista Previa") { AccionesFichero.abrirEnVistaPrevia(url) }
            agregar(menu, "Mostrar en Finder") { AccionesFichero.mostrarEnFinder(url) }
        }
        return menu
    }

    private func agregar(_ menu: NSMenu, _ titulo: String, _ accion: @escaping @MainActor () -> Void) {
        let objetivo = ObjetivoMenu(accion)
        objetivos.append(objetivo)
        let item = NSMenuItem(title: titulo, action: #selector(ObjetivoMenu.ejecutar), keyEquivalent: "")
        item.target = objetivo
        menu.addItem(item)
    }
}

/// Destino de un elemento de menú de AppKit con un cierre.
final class ObjetivoMenu: NSObject {
    let accion: @MainActor () -> Void
    init(_ accion: @escaping @MainActor () -> Void) { self.accion = accion }
    @MainActor @objc func ejecutar() { accion() }
}

/// La vista de PDFKit del controlador, para SwiftUI.
struct VistaPDFKit: NSViewRepresentable {
    let controlador: ControladorPDF
    var fondo: TLSColor = TLSPaleta.bandeja

    func makeNSView(context: Context) -> PDFViewTLS {
        let v = controlador.vista
        v.backgroundColor = fondo.ns
        v.setAccessibilityLabel("Contenido del PDF")
        return v
    }

    func updateNSView(_ v: PDFViewTLS, context: Context) {
        v.backgroundColor = fondo.ns
    }
}

/// Miniaturas de las páginas (PDFKit), enlazadas al visor del controlador.
struct MiniaturasPDF: NSViewRepresentable {
    let controlador: ControladorPDF

    func makeNSView(context: Context) -> PDFThumbnailView {
        let t = PDFThumbnailView()
        t.pdfView = controlador.vista
        t.thumbnailSize = CGSize(width: 96, height: 128)
        t.maximumNumberOfColumns = 1
        t.backgroundColor = TLSPaleta.superficie.ns
        t.allowsDragging = false
        t.allowsMultipleSelection = false
        t.setAccessibilityLabel("Páginas del PDF")
        return t
    }

    func updateNSView(_ t: PDFThumbnailView, context: Context) {
        t.backgroundColor = TLSPaleta.superficie.ns
        if t.pdfView !== controlador.vista { t.pdfView = controlador.vista }
    }
}
