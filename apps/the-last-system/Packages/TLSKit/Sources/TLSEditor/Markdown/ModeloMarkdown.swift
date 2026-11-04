import Foundation

// Lo que el analizador sabe de cada línea del texto. Es puro, `Sendable` y sin AppKit: se calcula fuera del
// hilo principal y lo aplica `AplicadorEstilo` en el hilo principal. Los rangos son `NSRange` (UTF-16)
// **relativos al principio de la línea**, para que dos análisis se puedan comparar línea a línea aunque el
// texto de encima haya cambiado de longitud.

/// Cómo está escrito un enlace.
public enum EstiloEnlace: String, Sendable, Hashable {
    /// `[[destino#ancla|texto]]`
    case wiki
    /// `[texto](destino#ancla)`
    case markdown
}

/// Un enlace del texto, tal cual está escrito. Es lo que se resuelve al ⌘clic y lo que se incrusta.
public struct EnlaceMarkdown: Sendable, Hashable {
    /// Destino sin `#ancla` ni texto: `../Empresas/panaderia-sol.md`, `Materiales/acta%20final.pdf`, `jorge-martin`.
    public var destino: String
    /// Lo que va tras `#` (`page=3`, una sección), sin la almohadilla.
    public var ancla: String?
    public var estilo: EstiloEnlace
    /// Lo que se ve: el alias, el texto del enlace o, si no hay, el destino.
    public var texto: String

    public init(destino: String, ancla: String? = nil, estilo: EstiloEnlace, texto: String) {
        self.destino = destino; self.ancla = ancla; self.estilo = estilo; self.texto = texto
    }

    /// `true` si lleva fuera de la carpeta (web o correo).
    public var esExterno: Bool {
        let d = destino.lowercased()
        return d.hasPrefix("http://") || d.hasPrefix("https://") || d.hasPrefix("mailto:") || d.hasPrefix("www.")
    }

    /// Forma que entiende el núcleo para resolverlo: `[[destino]]` o el destino Markdown tal cual.
    public var paraResolver: String {
        switch estilo {
        case .wiki: "[[\(destino)]]"
        case .markdown: destino
        }
    }

    /// Destino legible (sin `%20`), para avisos y vistas previas.
    public var destinoLegible: String {
        estilo == .markdown ? (destino.removingPercentEncoding ?? destino) : destino
    }

    /// Extensión del destino en minúsculas (`pdf`, `png`, `md`, `""`).
    public var extensionDestino: String {
        let nombre = destinoLegible.split(separator: "/").last.map(String.init) ?? destinoLegible
        guard let punto = nombre.lastIndex(of: "."), punto != nombre.startIndex else { return "" }
        return nombre[nombre.index(after: punto)...].lowercased()
    }
}

/// Un fichero incrustado en la nota: `![[x.pdf#page=3]]`, `![[imagen.png|300]]`, `![](Materiales/acta.pdf)`.
/// El texto plano no cambia: la incrustación es un enlace normal que la app pinta como bloque.
public struct Incrustacion: Sendable, Hashable {
    public var enlace: EnlaceMarkdown
    /// `#page=N` de un PDF.
    public var pagina: Int?
    /// `|300` o `|300x200` de una imagen (ancho en puntos).
    public var ancho: Int?
    /// `#height=500` de un PDF o `|300x200` de una imagen (alto en puntos).
    public var alto: Int?

    public init(enlace: EnlaceMarkdown, pagina: Int? = nil, ancho: Int? = nil, alto: Int? = nil) {
        self.enlace = enlace; self.pagina = pagina; self.ancho = ancho; self.alto = alto
    }

    /// Lee `height=N` del ancla.
    static func alto(deAncla ancla: String?) -> Int? {
        guard let ancla else { return nil }
        for parte in ancla.split(separator: "&") {
            let kv = parte.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "height", let n = Int(kv[1]), n > 0 { return n }
        }
        return nil
    }

    /// Lee `page=N` del ancla.
    static func pagina(deAncla ancla: String?) -> Int? {
        guard let ancla else { return nil }
        for parte in ancla.split(separator: "&") {
            let kv = parte.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == "page", let n = Int(kv[1]), n > 0 { return n }
        }
        return nil
    }
}

/// Dónde cae una línea dentro de un bloque de varias (código, aviso).
public enum PosicionEnBloque: Sendable, Hashable {
    case unica, primera, media, ultima

    static func de(_ i: Int, en n: Int) -> PosicionEnBloque {
        if n <= 1 { return .unica }
        if i == 0 { return .primera }
        if i == n - 1 { return .ultima }
        return .media
    }

    public var esPrimera: Bool { self == .unica || self == .primera }
    public var esUltima: Bool { self == .unica || self == .ultima }
}

/// Qué es una línea.
public enum TipoLinea: Sendable, Hashable {
    case texto
    case vacia
    case encabezado(Int)
    /// La línea `===` o `---` de un encabezado subrayado.
    case subrayadoEncabezado(Int)
    /// Línea de un bloque de código (con su posición, para pintar el fondo redondeado).
    case codigo(PosicionEnBloque)
    /// Valla ``` o ~~~ de un bloque de código.
    case vallaCodigo(PosicionEnBloque, lenguaje: String?)
    case tablaCabecera
    case tablaSeparador
    case tablaFila
    case separador
    /// Una línea que solo tiene una incrustación.
    case incrustacion(Incrustacion)
    case html
}

/// Un aviso de Obsidian (`> [!nota] Título`).
public struct AvisoMarkdown: Sendable, Hashable {
    /// Tipo en minúsculas (`note`, `warning`, `tip`…).
    public var tipo: String
    public var posicion: PosicionEnBloque
    public init(tipo: String, posicion: PosicionEnBloque) { self.tipo = tipo; self.posicion = posicion }
}

/// Lo que marca el bloque de una línea (además de su tipo).
public struct BloqueLinea: Sendable, Hashable {
    public var tipo: TipoLinea
    /// Profundidad de cita (`>`).
    public var cita: Int
    public var aviso: AvisoMarkdown?
    /// `true` en la primera línea de un elemento de lista.
    public var elementoLista: Bool
    /// Sangría de la lista (número de listas anidadas).
    public var nivelLista: Int

    public init(tipo: TipoLinea = .texto, cita: Int = 0, aviso: AvisoMarkdown? = nil, elementoLista: Bool = false,
                nivelLista: Int = 0) {
        self.tipo = tipo; self.cita = cita; self.aviso = aviso; self.elementoLista = elementoLista; self.nivelLista = nivelLista
    }

    public var esCodigo: Bool {
        switch tipo {
        case .codigo, .vallaCodigo: true
        default: false
        }
    }

    public var esTabla: Bool {
        switch tipo {
        case .tablaCabecera, .tablaSeparador, .tablaFila: true
        default: false
        }
    }

    public var nivelEncabezado: Int? {
        if case .encabezado(let n) = tipo { return n }
        return nil
    }
}

/// Un tramo con estilo dentro de una línea (rango relativo a la línea).
public struct TramoMarkdown: Sendable, Hashable {
    public enum Clase: Sendable, Hashable {
        case negrita, cursiva, tachado, codigo, resaltado, comentario, etiqueta, htmlEnLinea
        case enlace(EnlaceMarkdown)
        /// Marcas de sintaxis: se ven atenuadas en la línea del cursor y se esconden en las demás.
        case marcador
        /// Marcas que se dejan invisibles pero ocupan su sitio, porque en su lugar se dibuja algo
        /// (la viñeta de una lista, la raya de un separador, las vallas de código).
        case sustituido
        /// `[ ]` o `[x]` de una casilla: invisible fuera del cursor; en su sitio se dibuja la casilla.
        case casilla(marcada: Bool)
        /// `-`, `*` o `+` de una lista: en su sitio se dibuja la viñeta.
        case vineta
        /// `1.` de una lista numerada.
        case numero
        /// Texto de una tarea hecha (tachado y atenuado).
        case tareaHecha
        /// Título de un aviso.
        case tituloAviso
        /// Barras y guiones de una tabla: siempre atenuados.
        case puntuacionTabla
    }

    public var clase: Clase
    public var rango: NSRange

    public init(_ clase: Clase, _ rango: NSRange) { self.clase = clase; self.rango = rango }
}

/// Una línea analizada.
public struct ParrafoMarkdown: Sendable, Hashable {
    /// Desplazamiento UTF-16 del principio de la línea en el texto.
    public var inicio: Int
    /// Longitud UTF-16 sin el salto de línea.
    public var longitud: Int
    /// Longitud UTF-16 del salto (0, 1 o 2).
    public var salto: Int
    public var bloque: BloqueLinea
    public var tramos: [TramoMarkdown]

    public init(inicio: Int, longitud: Int, salto: Int, bloque: BloqueLinea = BloqueLinea(), tramos: [TramoMarkdown] = []) {
        self.inicio = inicio; self.longitud = longitud; self.salto = salto; self.bloque = bloque; self.tramos = tramos
    }

    /// Rango de la línea sin el salto.
    public var rangoContenido: NSRange { NSRange(location: inicio, length: longitud) }
    /// Rango de la línea con el salto (el párrafo de TextKit).
    public var rangoCompleto: NSRange { NSRange(location: inicio, length: longitud + salto) }

    /// Igual de estilo (sin mirar dónde empieza): si dos análisis coinciden aquí, la línea no se repinta.
    public func mismoEstilo(que o: ParrafoMarkdown) -> Bool {
        longitud == o.longitud && salto == o.salto && bloque == o.bloque && tramos == o.tramos
    }

    /// Las incrustaciones y los enlaces de la línea.
    public var enlaces: [EnlaceMarkdown] {
        tramos.compactMap { if case .enlace(let e) = $0.clase { return e }; return nil }
    }

    public var incrustacion: Incrustacion? {
        if case .incrustacion(let i) = bloque.tipo { return i }
        return nil
    }
}

/// El análisis de un texto entero.
public struct AnalisisMarkdown: Sendable, Hashable {
    public var parrafos: [ParrafoMarkdown]
    /// Longitud UTF-16 del texto analizado.
    public var longitud: Int

    public init(parrafos: [ParrafoMarkdown], longitud: Int) {
        self.parrafos = parrafos; self.longitud = longitud
    }

    public static let vacio = AnalisisMarkdown(parrafos: [ParrafoMarkdown(inicio: 0, longitud: 0, salto: 0, bloque: BloqueLinea(tipo: .vacia))], longitud: 0)

    /// Índice de la línea que contiene `posicion` (UTF-16). La posición tras el último salto es la última línea.
    public func indice(de posicion: Int) -> Int {
        guard !parrafos.isEmpty else { return 0 }
        var lo = 0, hi = parrafos.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if parrafos[mid].inicio <= posicion { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Líneas que han cambiado de estilo respecto a otro análisis (índices de este): lo que no coincide
    /// ni por delante ni por detrás.
    public func cambiadas(respectoA viejo: AnalisisMarkdown) -> Range<Int> {
        let a = viejo.parrafos, b = parrafos
        var prefijo = 0
        while prefijo < a.count, prefijo < b.count, a[prefijo].mismoEstilo(que: b[prefijo]) { prefijo += 1 }
        var sufijo = 0
        while sufijo < a.count - prefijo, sufijo < b.count - prefijo,
              a[a.count - 1 - sufijo].mismoEstilo(que: b[b.count - 1 - sufijo]) { sufijo += 1 }
        return prefijo..<(b.count - sufijo)
    }

    /// Títulos del texto (para el índice del inspector): nivel, título y posición.
    public var titulos: [(nivel: Int, rango: NSRange)] {
        parrafos.compactMap { p in p.bloque.nivelEncabezado.map { ($0, p.rangoContenido) } }
    }
}
