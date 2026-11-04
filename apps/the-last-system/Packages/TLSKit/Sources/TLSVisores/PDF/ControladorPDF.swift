import AppKit
import Combine
import Observation
import PDFKit
import TLSDesign

/// Un resultado de «Buscar en el PDF»: la página y el trozo de línea donde sale.
public struct ResultadoPDF: Identifiable, Hashable, Sendable {
    public let id: Int
    /// Página (1 = la primera).
    public let pagina: Int
    /// La línea donde aparece, recortada.
    public let fragmento: String
}

/// Una entrada del índice del PDF (si lo trae).
public struct EntradaIndicePDF: Identifiable, Hashable, Sendable {
    public let id: Int
    public let titulo: String
    /// 0 = primer nivel.
    public let nivel: Int
    /// Página a la que lleva (1 = la primera), si la tiene.
    public let pagina: Int?
}

/// Panel lateral del visor de PDF.
public enum PanelPDF: String, CaseIterable, Sendable, Identifiable {
    case miniaturas, indice, resultados
    public var id: String { rawValue }
    public var titulo: String {
        switch self {
        case .miniaturas: "Páginas"
        case .indice: "Índice"
        case .resultados: "Resultados"
        }
    }
}

/// Estado y órdenes del visor de PDF (R1): páginas, zoom con ajuste a ancho y a página, búsqueda en el texto,
/// índice, selección y copia. **Nunca escribe** el fichero: ni edita ni guarda anotaciones.
@Observable @MainActor
public final class ControladorPDF {
    public enum Ajuste: String, Sendable, Equatable {
        /// La página ocupa el ancho, con desplazamiento continuo.
        case ancho
        /// Se ve la página entera, de una en una.
        case pagina
        /// Zoom elegido a mano.
        case libre
    }

    public private(set) var url: URL?
    public private(set) var documento: PDFDocument?
    /// Página que se ve (0 = la primera).
    public private(set) var indicePagina = 0
    public private(set) var totalPaginas = 0
    public private(set) var ajuste: Ajuste = .ancho
    /// Zoom actual (1 = tamaño real).
    public private(set) var escala: CGFloat = 1
    public private(set) var busqueda = ""
    public private(set) var resultados: [ResultadoPDF] = []
    public private(set) var resultadoElegido: Int?
    public private(set) var indice: [EntradaIndicePDF] = []
    public var panel: PanelPDF?
    /// Texto llano si no se pudo abrir.
    public private(set) var error: String?
    /// Texto elegido ahora mismo (para «Copiar»).
    public private(set) var textoSeleccionado: String?

    /// La vista de PDFKit (una por controlador).
    @ObservationIgnored public let vista: PDFViewTLS
    @ObservationIgnored private var selecciones: [PDFSelection] = []
    @ObservationIgnored private var suscripciones: Set<AnyCancellable> = []

    public static let escalaMinima: CGFloat = 0.25
    public static let escalaMaxima: CGFloat = 6

    public init() {
        vista = PDFViewTLS()
        vista.displayMode = .singlePageContinuous
        vista.displaysPageBreaks = true
        vista.autoScales = true
        vista.backgroundColor = TLSPaleta.bandeja.ns
        vista.controlador = self
        let centro = NotificationCenter.default
        centro.publisher(for: .PDFViewPageChanged, object: vista)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.sincronizarPagina() } }
            .store(in: &suscripciones)
        centro.publisher(for: .PDFViewScaleChanged, object: vista)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.sincronizarEscala() } }
            .store(in: &suscripciones)
        centro.publisher(for: .PDFViewSelectionChanged, object: vista)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.sincronizarSeleccion() } }
            .store(in: &suscripciones)
    }

    // MARK: Abrir

    /// Abre un PDF que ya está en el Mac (comprobar iCloud antes). `pagina` empieza en 1.
    @discardableResult
    public func cargar(url: URL, pagina: Int? = nil) -> Bool {
        self.url = url
        guard let doc = AccesoICloudSistema.sinDescargar({ PDFDocument(url: url) }) else {
            documento = nil
            vista.document = nil
            totalPaginas = 0
            error = "No he podido abrir este PDF. Puede que esté dañado o protegido con contraseña."
            return false
        }
        if doc.isLocked {
            documento = nil
            vista.document = nil
            totalPaginas = 0
            error = "Este PDF está protegido con contraseña. Ábrelo en Vista Previa para verlo."
            return false
        }
        cargar(documento: doc, pagina: pagina)
        return true
    }

    /// Enseña un documento ya abierto (pruebas y miniaturas).
    public func cargar(documento doc: PDFDocument, pagina: Int? = nil) {
        error = nil
        documento = doc
        vista.document = doc
        totalPaginas = doc.pageCount
        indice = Self.leerIndice(doc)
        busqueda = ""
        resultados = []
        resultadoElegido = nil
        selecciones = []
        aplicarAjuste(ajuste)
        if let pagina { ir(aPagina: pagina) } else { sincronizarPagina() }
        sincronizarEscala()
    }

    // MARK: Páginas

    /// Número de la página que se ve (1 = la primera).
    public var numeroPagina: Int { totalPaginas == 0 ? 0 : indicePagina + 1 }

    /// «Página 3 de 12».
    public var textoPagina: String {
        totalPaginas == 0 ? "Sin páginas" : "Página \(numeroPagina) de \(totalPaginas)"
    }

    /// Va a una página (1 = la primera). Fuera de rango, a la más cercana.
    public func ir(aPagina numero: Int) {
        guard let doc = documento, doc.pageCount > 0 else { return }
        let i = min(max(numero - 1, 0), doc.pageCount - 1)
        guard let page = doc.page(at: i) else { return }
        vista.go(to: page)
        indicePagina = i
    }

    public var puedeIrAtras: Bool { indicePagina > 0 }
    public var puedeIrAdelante: Bool { indicePagina + 1 < totalPaginas }

    public func paginaSiguiente() { ir(aPagina: numeroPagina + 1) }
    public func paginaAnterior() { ir(aPagina: numeroPagina - 1) }

    // MARK: Zoom

    /// La página ocupa el ancho del visor (desplazamiento continuo).
    public func ajustarAncho() { aplicarAjuste(.ancho) }
    /// Se ve la página entera.
    public func ajustarPagina() { aplicarAjuste(.pagina) }

    public func acercar() { ponerEscala(escala * 1.25) }
    public func alejar() { ponerEscala(escala / 1.25) }
    public func tamanoReal() { ponerEscala(1) }

    /// «125 %».
    public var textoEscala: String { "\(Int((escala * 100).rounded())) %" }

    private func ponerEscala(_ e: CGFloat) {
        let pagina = indicePagina
        ajuste = .libre
        vista.autoScales = false
        vista.scaleFactor = min(max(e, Self.escalaMinima), Self.escalaMaxima)
        escala = vista.scaleFactor
        if documento != nil { ir(aPagina: pagina + 1) }
    }

    private func aplicarAjuste(_ a: Ajuste) {
        let pagina = indicePagina
        ajuste = a
        switch a {
        case .ancho:
            vista.displayMode = .singlePageContinuous
            vista.autoScales = true
        case .pagina:
            vista.displayMode = .singlePage
            vista.autoScales = true
        case .libre:
            vista.autoScales = false
        }
        escala = vista.scaleFactor
        if documento != nil { ir(aPagina: pagina + 1) }
    }

    // MARK: Buscar

    /// Busca en el texto del PDF (sin distinguir mayúsculas ni tildes). Devuelve cuántas veces sale y va a
    /// la primera.
    @discardableResult
    public func buscar(_ texto: String) -> Int {
        busqueda = texto
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let doc = documento, !t.isEmpty else {
            limpiarBusqueda(dejarTexto: true)
            return 0
        }
        let encontradas = Array(doc.findString(t, withOptions: [.caseInsensitive, .diacriticInsensitive]).prefix(500))
        selecciones = encontradas
        resultados = encontradas.enumerated().map { i, sel in
            let pagina = sel.pages.first.map { doc.index(for: $0) + 1 } ?? 1
            return ResultadoPDF(id: i, pagina: pagina, fragmento: Self.fragmento(de: sel, buscando: t))
        }
        vista.highlightedSelections = encontradas.isEmpty ? nil : encontradas.map { s in
            let c = s.copy() as? PDFSelection ?? s
            c.color = NSColor.systemYellow.withAlphaComponent(0.55)
            return c
        }
        resultadoElegido = nil
        if !resultados.isEmpty {
            irAResultado(0)
            if panel == nil || panel == .miniaturas { panel = .resultados }
        }
        return resultados.count
    }

    /// Quita la búsqueda (y los resaltados).
    public func limpiarBusqueda(dejarTexto: Bool = false) {
        if !dejarTexto { busqueda = "" }
        resultados = []
        selecciones = []
        resultadoElegido = nil
        vista.highlightedSelections = nil
        if panel == .resultados { panel = nil }
    }

    /// Va a un resultado y lo deja elegido.
    public func irAResultado(_ i: Int) {
        guard selecciones.indices.contains(i) else { return }
        resultadoElegido = i
        let sel = selecciones[i]
        vista.setCurrentSelection(sel, animate: false)
        vista.go(to: sel)
        if let page = sel.pages.first, let doc = documento { indicePagina = doc.index(for: page) }
        sincronizarSeleccion()
    }

    public func siguienteResultado() {
        guard !resultados.isEmpty else { return }
        irAResultado(((resultadoElegido ?? -1) + 1) % resultados.count)
    }

    public func anteriorResultado() {
        guard !resultados.isEmpty else { return }
        irAResultado(((resultadoElegido ?? 0) - 1 + resultados.count) % resultados.count)
    }

    /// «3 de 12» o «No sale en el PDF».
    public var textoResultados: String? {
        let t = busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if resultados.isEmpty { return "No sale en el PDF" }
        if let r = resultadoElegido { return "\(r + 1) de \(resultados.count)" }
        return resultados.count == 1 ? "1 resultado" : "\(resultados.count) resultados"
    }

    // MARK: Índice

    public func ir(a entrada: EntradaIndicePDF) {
        if let p = entrada.pagina { ir(aPagina: p) }
    }

    // MARK: Selección y copia

    /// Copia el texto elegido. Devuelve `false` si no hay nada elegido.
    @discardableResult
    public func copiarSeleccion(en portapapeles: NSPasteboard = .general) -> Bool {
        guard let texto = vista.currentSelection?.string, !texto.isEmpty else { return false }
        portapapeles.clearContents()
        portapapeles.setString(texto, forType: .string)
        return true
    }

    /// Elige un texto de una página (accesibilidad y pruebas).
    public func elegir(texto: String) -> Bool {
        guard let doc = documento,
              let sel = doc.findString(texto, withOptions: [.caseInsensitive]).first else { return false }
        vista.setCurrentSelection(sel, animate: false)
        sincronizarSeleccion()
        return true
    }

    /// Texto de una página (1 = la primera), para VoiceOver y pruebas.
    public func texto(dePagina numero: Int) -> String? {
        documento?.page(at: numero - 1)?.string
    }

    // MARK: Sincronizar con PDFKit

    func sincronizarPagina() {
        guard let doc = documento, let page = vista.currentPage else { return }
        let i = doc.index(for: page)
        if i != NSNotFound, i != indicePagina { indicePagina = i }
    }

    func sincronizarEscala() {
        let e = vista.scaleFactor
        if abs(e - escala) > 0.0001 { escala = e }
    }

    func sincronizarSeleccion() {
        let s = vista.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        textoSeleccionado = (s?.isEmpty ?? true) ? nil : s
    }

    // MARK: Ayudas

    static func leerIndice(_ doc: PDFDocument) -> [EntradaIndicePDF] {
        guard let raiz = doc.outlineRoot else { return [] }
        var salida: [EntradaIndicePDF] = []
        func recorrer(_ nodo: PDFOutline, nivel: Int) {
            for i in 0..<nodo.numberOfChildren {
                guard let hijo = nodo.child(at: i), salida.count < 2_000 else { continue }
                let pagina = hijo.destination?.page.map { doc.index(for: $0) + 1 }
                let titulo = (hijo.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                salida.append(EntradaIndicePDF(id: salida.count, titulo: titulo.isEmpty ? "Sin título" : titulo,
                                               nivel: nivel, pagina: pagina))
                if nivel < 8 { recorrer(hijo, nivel: nivel + 1) }
            }
        }
        recorrer(raiz, nivel: 0)
        return salida
    }

    static func fragmento(de sel: PDFSelection, buscando texto: String) -> String {
        guard let linea = sel.copy() as? PDFSelection else { return texto }
        linea.extendForLineBoundaries()
        let completo = (linea.string ?? texto)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard completo.count > 90 else { return completo }
        guard let r = completo.range(of: texto, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(completo.prefix(90)) + "…"
        }
        let antes = completo.distance(from: completo.startIndex, to: r.lowerBound)
        let desde = completo.index(completo.startIndex, offsetBy: max(0, antes - 30))
        let hasta = completo.index(desde, offsetBy: min(90, completo.distance(from: desde, to: completo.endIndex)))
        return (desde > completo.startIndex ? "…" : "") + completo[desde..<hasta] + (hasta < completo.endIndex ? "…" : "")
    }
}
