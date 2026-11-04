import AppKit
import TLSDesign

/// Cómo se ve la nota.
public enum ModoEditor: String, CaseIterable, Sendable, Hashable, Codable {
    /// Como Obsidian: el Markdown se pinta y las marcas se esconden salvo en la línea del cursor.
    case vivo
    /// El texto tal cual, en JetBrains Mono («Ver como texto»).
    case fuente
    /// Sin cursor: todo pintado, los enlaces se abren con un clic.
    case lectura

    public var titulo: String {
        switch self {
        case .vivo: "Edición en vivo"
        case .fuente: "Como texto"  // el mismo nombre que «Ver como texto» del menú de la ficha
        case .lectura: "Lectura"
        }
    }

    public var simbolo: String {
        switch self {
        case .vivo: "square.and.pencil"
        case .fuente: "chevron.left.forwardslash.chevron.right"
        case .lectura: "book"
        }
    }

    /// `true` si se puede escribir en este modo (si la carpeta lo permite).
    public var editable: Bool { self != .lectura }
}

/// Claves de atributo propias del editor (las lee el fragmento de TextKit 2 para dibujar).
public extension NSAttributedString.Key {
    /// `CajaEnlace`: un enlace del texto (se abre con ⌘clic, o con clic en Lectura).
    static let tlsEnlace = NSAttributedString.Key("es.thelast.enlace")
    /// `NSNumber(bool)`: los tres caracteres `[ ]` de una casilla (en su sitio se dibuja la casilla).
    static let tlsCasilla = NSAttributedString.Key("es.thelast.casilla")
    /// `NSNumber(true)`: la viñeta de una lista (en su sitio se dibuja un punto).
    static let tlsVineta = NSAttributedString.Key("es.thelast.vineta")
    /// `TLSColorCaja`: fondo redondeado de un tramo (código, etiqueta, resaltado).
    static let tlsFondo = NSAttributedString.Key("es.thelast.fondo")
    /// `NSNumber(true)`: una marca de sintaxis (atenuada o escondida).
    static let tlsMarcador = NSAttributedString.Key("es.thelast.marcador")
    /// `DecoracionBloque`: lo que se dibuja detrás o al lado de la línea (fondo de código, barra de cita…).
    static let tlsBloque = NSAttributedString.Key("es.thelast.bloque")
}

/// Estado de un enlace para pintarlo.
public enum EstadoEnlace: Sendable, Hashable {
    /// Lleva a algo de la carpeta.
    case existe
    /// No lleva a nada (todavía): se pinta en gris con subrayado discontinuo.
    case rota
    /// Web o correo.
    case externa
}

/// Un enlace como valor de atributo.
public final class CajaEnlace: NSObject, @unchecked Sendable {
    public let enlace: EnlaceMarkdown
    public let estado: EstadoEnlace
    init(_ enlace: EnlaceMarkdown, estado: EstadoEnlace) { self.enlace = enlace; self.estado = estado }
    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CajaEnlace else { return false }
        return o.enlace == enlace && o.estado == estado
    }
    public override var hash: Int { enlace.hashValue }
}

/// Un color de Mosaico v2 como valor de atributo (se resuelve con la apariencia al dibujar).
public final class TLSColorCaja: NSObject, @unchecked Sendable {
    public let color: TLSColor
    init(_ color: TLSColor) { self.color = color }
    public override func isEqual(_ object: Any?) -> Bool { (object as? TLSColorCaja)?.color == color }
    public override var hash: Int { color.hashValue }
}

/// Lo que el fragmento dibuja en una línea entera.
public final class DecoracionBloque: NSObject, @unchecked Sendable {
    public enum Fondo: Sendable, Hashable {
        case codigo(PosicionEnBloque)
        case aviso(tipo: String, PosicionEnBloque)
    }

    public let fondo: Fondo?
    /// Barras de cita a la izquierda (0 si no hay o si es un aviso).
    public let cita: Int
    public let separador: Bool
    /// `true` si en esta línea van las marcas visibles (línea del cursor): no se dibujan viñetas ni casillas.
    public let marcasVisibles: Bool

    init(fondo: Fondo?, cita: Int, separador: Bool, marcasVisibles: Bool) {
        self.fondo = fondo; self.cita = cita; self.separador = separador; self.marcasVisibles = marcasVisibles
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? DecoracionBloque else { return false }
        return o.fondo == fondo && o.cita == cita && o.separador == separador && o.marcasVisibles == marcasVisibles
    }
    public override var hash: Int { cita &+ (separador ? 7 : 0) }

    var dibujaAlgo: Bool { fondo != nil || cita > 0 || separador }
}

/// Aspecto de un aviso de Obsidian según su tipo.
enum AspectoAviso {
    static func simbolo(_ tipo: String) -> String {
        switch tipo {
        case "warning", "caution", "attention": "exclamationmark.triangle.fill"
        case "danger", "error", "failure", "fail", "missing", "bug": "xmark.octagon.fill"
        case "success", "check", "done": "checkmark.circle.fill"
        case "question", "help", "faq": "questionmark.circle.fill"
        case "tip", "hint", "important": "lightbulb.fill"
        case "quote", "cite": "quote.opening"
        case "example": "list.bullet"
        case "todo": "checkmark.square"
        case "abstract", "summary", "tldr": "doc.text"
        default: "info.circle.fill"
        }
    }

    /// Color del icono (tinta) y del fondo (tinte).
    static func colores(_ tipo: String) -> (tinta: TLSColor, fondo: TLSColor) {
        switch tipo {
        case "warning", "caution", "attention": (TLSEstado.atencion.color, TLSEstado.atencion.tinte)
        case "danger", "error", "failure", "fail", "missing", "bug": (TLSEstado.mal.color, TLSEstado.mal.tinte)
        case "success", "check", "done": (TLSEstado.bien.color, TLSEstado.bien.tinte)
        case "quote", "cite": (TLSPaleta.textoSecundario, TLSPaleta.bandeja)
        default: (TLSPaleta.principal, TLSPaleta.principalSuave)
        }
    }
}

/// Letras, colores y párrafos del editor para un modo y una escala de texto (85–200 %). Guarda en caché lo
/// que cuesta crear (letras variables de CoreText, estilos de párrafo).
@MainActor
final class TemaEditor {
    let modo: ModoEditor
    let escala: CGFloat

    init(modo: ModoEditor, escala: CGFloat) {
        self.modo = modo
        self.escala = min(max(escala, 0.85), 2)
    }

    // MARK: Letra

    private struct ClaveFuente: Hashable {
        let estilo: TLSEstiloTexto
        let negrita: Bool
        let cursiva: Bool
    }

    private struct ClaveParrafo: Hashable {
        let tipo: TipoLinea
        let cita: Int
        let aviso: AvisoMarkdown?
        let sangria: Int
        let colapsada: Bool
        let alto: Int
    }

    private var fuentes: [ClaveFuente: NSFont] = [:]
    private var parrafos: [ClaveParrafo: NSParagraphStyle] = [:]
    private var anchos: [String: CGFloat] = [:]

    /// Ancho de un texto corto con una letra (sangría de las listas), en caché.
    func ancho(_ texto: String, fuente: NSFont) -> CGFloat {
        let clave = "\(fuente.fontName)|\(fuente.pointSize)|\(texto)"
        if let a = anchos[clave] { return a }
        let a = (texto as NSString).size(withAttributes: [.font: fuente]).width
        anchos[clave] = a
        return a
    }

    /// Letra invisible de las marcas escondidas: ocupa casi nada.
    let fuenteOculta = NSFont.systemFont(ofSize: 0.01)

    func estilo(de b: BloqueLinea) -> TLSEstiloTexto {
        if modo == .fuente {
            if case .encabezado = b.tipo { return TLSTipo.textoPlano.peso(700) }
            return TLSTipo.textoPlano
        }
        switch b.tipo {
        case .encabezado(let n), .subrayadoEncabezado(let n):
            switch n {
            case 1: return TLSTipo.tituloPantalla
            case 2: return TLSTipo.tituloSeccion
            case 3: return TLSTipo.tituloModulo.peso(600).tamano(17, interlinea: 23)
            default: return TLSTipo.lectura.peso(650)
            }
        case .codigo, .vallaCodigo, .tablaCabecera, .tablaSeparador, .tablaFila, .html:
            return TLSTipo.textoPlano
        default:
            return TLSTipo.lectura
        }
    }

    func fuente(_ e: TLSEstiloTexto, negrita: Bool = false, cursiva: Bool = false) -> NSFont {
        let clave = ClaveFuente(estilo: e, negrita: negrita, cursiva: cursiva)
        if let f = fuentes[clave] { return f }
        var x = e
        if negrita { x = x.peso(max(x.peso + 250, 650)) }
        if cursiva, x.familia == .dmSans { x = x.enItalica }
        var f = x.nsFont(escala: escala)
        if cursiva, x.familia != .dmSans {
            // Space Grotesk y JetBrains Mono no traen itálica: inclinación sintética.
            let m = AffineTransform(m11: 1, m12: 0, m21: 0.2, m22: 1, tX: 0, tY: 0)
            f = NSFont(descriptor: f.fontDescriptor, textTransform: m) ?? f
        }
        fuentes[clave] = f
        return f
    }

    var codigoEnLinea: TLSEstiloTexto { TLSTipo.textoPlano.tamano(13.5, interlinea: 20) }

    // MARK: Párrafo

    /// Estilo de párrafo de una línea. `alto`: espacio reservado debajo para una incrustación.
    func parrafo(_ b: BloqueLinea, sangria: CGFloat, colapsada: Bool, alto: CGFloat?) -> NSParagraphStyle {
        let e = estilo(de: b)
        var tipo = b.tipo
        if case .incrustacion = tipo { tipo = .texto }
        let clave = ClaveParrafo(tipo: tipo, cita: b.cita, aviso: b.aviso, sangria: Int(sangria.rounded()),
                                 colapsada: colapsada, alto: Int(alto ?? -1))
        if let p = parrafos[clave] { return p }
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.lineSpacing = e.espacioEntreLineas(escala: escala)
        var izquierda: CGFloat = 0
        var derecha: CGFloat = 0
        if modo != .fuente {
            switch b.tipo {
            case .encabezado(let n):
                p.paragraphSpacingBefore = [0, 14, 12, 8][min(n, 3)] * escala
            case .codigo, .vallaCodigo:
                izquierda += 14
                derecha += 14
            default: break
            }
            if b.aviso != nil {
                izquierda += 40
                derecha += 14
                if b.aviso?.posicion.esPrimera == true { p.paragraphSpacingBefore = 6 * escala }
                if b.aviso?.posicion.esUltima == true { p.paragraphSpacing = 6 * escala }
            } else if b.cita > 0 {
                izquierda += CGFloat(b.cita) * 16
            }
            if case .codigo(let pos) = b.tipo, pos.esPrimera { p.paragraphSpacingBefore = 4 * escala }
            if case .vallaCodigo(let pos, _) = b.tipo {
                if pos.esPrimera { p.paragraphSpacingBefore = 4 * escala }
                if pos.esUltima { p.paragraphSpacing = 4 * escala }
            }
        }
        p.firstLineHeadIndent = izquierda
        p.headIndent = izquierda + sangria
        p.tailIndent = -derecha
        if colapsada {
            p.lineSpacing = 0
            p.minimumLineHeight = 2
            p.maximumLineHeight = 2
            p.paragraphSpacingBefore = 6 * escala
        }
        if let alto { p.paragraphSpacing = alto + 14 }
        parrafos[clave] = p
        return p
    }

    // MARK: Color

    let texto = TLSPaleta.texto.ns
    let secundario = TLSPaleta.textoSecundario.ns
    let enlace = TLSPaleta.enlace.ns
    let principal = TLSPaleta.principal.ns
}
