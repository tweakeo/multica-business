import Foundation
import Markdown

/// Análisis del Markdown de una nota para la vista previa en vivo: el árbol de swift-markdown (bloques,
/// negritas, enlaces, código…) más lo propio de Obsidian (wikilinks, incrustaciones, avisos, etiquetas,
/// resaltados, comentarios) y las marcas de sintaxis que se esconden.
///
/// Es puro: se llama fuera del hilo principal y no cambia ningún carácter.
public enum AnalizadorMarkdown {
    /// A partir de este tamaño el editor solo enseña el texto fuente, sin análisis (PLAN §6.6).
    public static let limiteBytes = 2 * 1024 * 1024

    public static func analizar(_ texto: String) -> AnalisisMarkdown {
        let tabla = TablaLineas(texto)
        let ns = texto as NSString
        var r = Recorrido(tabla: tabla, texto: ns)
        r.visit(Document(parsing: texto, options: []))
        r.terminar()
        let parrafos = tabla.lineas.indices.map { i in
            ParrafoMarkdown(inicio: tabla.lineas[i].inicio, longitud: tabla.lineas[i].longitud, salto: tabla.lineas[i].salto,
                            bloque: r.bloques[i], tramos: ordenar(r.tramos[i]))
        }
        return AnalisisMarkdown(parrafos: parrafos, longitud: tabla.longitud)
    }

    /// Orden de aplicación: estilos de texto primero; marcas al final (mandan sobre lo anterior).
    static func ordenar(_ tramos: [TramoMarkdown]) -> [TramoMarkdown] {
        func prioridad(_ c: TramoMarkdown.Clase) -> Int {
            switch c {
            case .negrita, .cursiva, .tachado, .resaltado, .tituloAviso, .tareaHecha: 0
            case .codigo, .comentario, .htmlEnLinea, .etiqueta: 1
            case .enlace: 2
            case .puntuacionTabla, .numero: 3
            case .marcador, .sustituido, .casilla, .vineta: 4
            }
        }
        return tramos.sorted { a, b in
            let pa = prioridad(a.clase), pb = prioridad(b.clase)
            if pa != pb { return pa < pb }
            if a.rango.location != b.rango.location { return a.rango.location < b.rango.location }
            return a.rango.length < b.rango.length
        }
    }

    // MARK: Expresiones de lo propio de Obsidian

    static let wikilink = try! NSRegularExpression(pattern: #"(!?)\[\[([^\[\]\n]+?)\]\]"#)
    static let resaltado = try! NSRegularExpression(pattern: #"==(?=\S)([^=\n]+?)(?<=\S)=="#)
    static let comentario = try! NSRegularExpression(pattern: #"%%.*?%%"#)
    static let etiqueta = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&/#\]\)])#(?=[\p{L}\p{N}_/\-]*[\p{L}_/\-])[\p{L}\p{N}_/\-]+"#)
    static let escape = try! NSRegularExpression(pattern: #"\\[!-/:-@\[-`{-~]"#)
    static let incrustacionWiki = try! NSRegularExpression(pattern: #"^[ \t]*!\[\[([^\[\]\n]+?)\]\][ \t]*$"#)
    static let incrustacionMarkdown = try! NSRegularExpression(pattern: #"^[ \t]*!\[([^\]\n]*)\]\((<[^>\n]+>|[^)\s]+)(?:[ \t]+"[^"\n]*")?\)[ \t]*$"#)
    static let aviso = try! NSRegularExpression(pattern: #"^\[!([A-Za-z][\w-]*)\]([+-]?)[ \t]*"#)
    static let marcaLista = try! NSRegularExpression(pattern: #"^[ \t]*([-*+]|\d{1,9}[.)])([ \t]+|$)"#)
    static let casilla = try! NSRegularExpression(pattern: #"^\[([ xX])\]([ \t]|$)"#)
    static let detectorWeb = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Partes de un wikilink: `destino#ancla|texto`.
    static func partesWiki(_ interior: String) -> (destino: String, ancla: String?, texto: String?) {
        var cuerpo = interior
        var texto: String?
        if let barra = interior.firstIndex(of: "|") {
            cuerpo = String(interior[..<barra])
            texto = String(interior[interior.index(after: barra)...])
        }
        var destino = cuerpo
        var ancla: String?
        if let h = cuerpo.firstIndex(of: "#") {
            destino = String(cuerpo[..<h])
            ancla = String(cuerpo[cuerpo.index(after: h)...])
        }
        return (destino.trimmingCharacters(in: .whitespaces), ancla, texto)
    }

    /// Destino Markdown sin `<…>` y separado del ancla (si no es externo).
    static func partesMarkdown(_ destino: String) -> (destino: String, ancla: String?) {
        var d = destino.trimmingCharacters(in: .whitespaces)
        if d.hasPrefix("<"), d.hasSuffix(">") { d = String(d.dropFirst().dropLast()) }
        let externo = d.lowercased().hasPrefix("http") || d.lowercased().hasPrefix("mailto:")
        if !externo, let h = d.firstIndex(of: "#") {
            return (String(d[..<h]), String(d[d.index(after: h)...]))
        }
        return (d, nil)
    }

    /// Incrustación de una línea que solo tiene `![[…]]` o `![…](…)`.
    static func incrustacion(enLinea linea: String) -> (Incrustacion, rangoTexto: NSRange)? {
        let ns = linea as NSString
        let todo = NSRange(location: 0, length: ns.length)
        if let m = incrustacionWiki.firstMatch(in: linea, range: todo) {
            let interior = ns.substring(with: m.range(at: 1))
            let p = partesWiki(interior)
            guard !p.destino.isEmpty else { return nil }
            var ancho: Int?
            var alto = Incrustacion.alto(deAncla: p.ancla)
            if let t = p.texto {
                let medidas = t.lowercased().split(separator: "x", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                ancho = medidas.first.flatMap { Int($0) }
                if ancho != nil, medidas.count == 2, let h = Int(medidas[1]) { alto = h }
            }
            let enlace = EnlaceMarkdown(destino: p.destino, ancla: p.ancla, estilo: .wiki,
                                        texto: (ancho == nil ? p.texto : nil) ?? p.destino)
            return (Incrustacion(enlace: enlace, pagina: Incrustacion.pagina(deAncla: p.ancla), ancho: ancho, alto: alto),
                    m.range(at: 1))
        }
        if let m = incrustacionMarkdown.firstMatch(in: linea, range: todo) {
            let alt = ns.substring(with: m.range(at: 1))
            let p = partesMarkdown(ns.substring(with: m.range(at: 2)))
            guard !p.destino.isEmpty else { return nil }
            let enlace = EnlaceMarkdown(destino: p.destino, ancla: p.ancla, estilo: .markdown,
                                        texto: alt.isEmpty ? (p.destino.removingPercentEncoding ?? p.destino) : alt)
            return (Incrustacion(enlace: enlace, pagina: Incrustacion.pagina(deAncla: p.ancla), alto: Incrustacion.alto(deAncla: p.ancla)),
                    m.range(at: 2))
        }
        return nil
    }
}

// MARK: - Recorrido del árbol

private struct Recorrido: MarkupWalker {
    let tabla: TablaLineas
    let texto: NSString
    var bloques: [BloqueLinea]
    var tramos: [[TramoMarkdown]]
    /// Rangos absolutos donde no se buscan wikilinks, etiquetas…: código, HTML, destinos de enlaces.
    var excluidos: [[NSRange]]
    /// Listas anidadas abiertas mientras se recorre.
    var profundidadLista = 0

    init(tabla: TablaLineas, texto: NSString) {
        self.tabla = tabla
        self.texto = texto
        let n = tabla.lineas.count
        bloques = Array(repeating: BloqueLinea(), count: n)
        tramos = Array(repeating: [], count: n)
        excluidos = Array(repeating: [], count: n)
        for i in 0..<n where tabla.lineas[i].longitud == 0 || Self.enBlanco(texto, tabla.lineas[i]) {
            bloques[i].tipo = .vacia
        }
    }

    static func enBlanco(_ texto: NSString, _ l: TablaLineas.Linea) -> Bool {
        guard l.longitud > 0 else { return true }
        return texto.substring(with: NSRange(location: l.inicio, length: l.longitud))
            .allSatisfy { $0 == " " || $0 == "\t" }
    }

    func contenido(_ i: Int) -> String {
        let l = tabla.lineas[i]
        return texto.substring(with: NSRange(location: l.inicio, length: l.longitud))
    }

    // MARK: Apoyo

    /// Añade un tramo (absoluto) repartido por líneas.
    mutating func anadir(_ clase: TramoMarkdown.Clase, _ r: NSRange) {
        guard r.length > 0 else { return }
        var i = tabla.indice(de: r.location)
        let fin = NSMaxRange(r)
        while i < tabla.lineas.count {
            let l = tabla.lineas[i]
            guard l.inicio < fin else { break }
            let a = max(r.location, l.inicio)
            let b = min(fin, l.inicio + l.longitud)
            if b > a { tramos[i].append(TramoMarkdown(clase, NSRange(location: a - l.inicio, length: b - a))) }
            i += 1
        }
    }

    mutating func excluir(_ r: NSRange) {
        guard r.length > 0 else { return }
        var i = tabla.indice(de: r.location)
        while i < tabla.lineas.count, tabla.lineas[i].inicio < NSMaxRange(r) {
            excluidos[i].append(r)
            i += 1
        }
    }

    /// Longitud de la marca de cita (`> > `) al principio de una línea con `profundidad` niveles.
    func marcaCita(_ linea: String, profundidad: Int) -> Int {
        guard profundidad > 0 else { return 0 }
        let u = Array(linea.utf16)
        var i = 0
        for _ in 0..<profundidad {
            var espacios = 0
            while i < u.count, u[i] == 0x20, espacios < 3 { i += 1; espacios += 1 }
            guard i < u.count, u[i] == 0x3E else { return i - espacios }
            i += 1
            if i < u.count, u[i] == 0x20 || u[i] == 0x09 { i += 1 }
        }
        return i
    }

    // MARK: Bloques

    mutating func visitBlockQuote(_ cita: BlockQuote) {
        guard let ls = tabla.lineas(de: cita.range) else { descendInto(cita); return }
        for i in ls { bloques[i].cita += 1 }
        // Aviso de Obsidian: `> [!tipo] Título` en la primera línea de una cita de primer nivel.
        let primera = contenido(ls.lowerBound)
        let marca = marcaCita(primera, profundidad: bloques[ls.lowerBound].cita)
        let resto = (primera as NSString).substring(from: marca)
        if bloques[ls.lowerBound].aviso == nil,
           let m = AnalizadorMarkdown.aviso.firstMatch(in: resto, range: NSRange(location: 0, length: (resto as NSString).length)) {
            let tipo = (resto as NSString).substring(with: m.range(at: 1)).lowercased()
            let n = ls.count
            for (k, i) in ls.enumerated() {
                bloques[i].aviso = AvisoMarkdown(tipo: tipo, posicion: PosicionEnBloque.de(k, en: n))
            }
            let l = tabla.lineas[ls.lowerBound]
            let finMarca = marca + m.range.length
            let restoTitulo = (resto as NSString).length - m.range.length
            if restoTitulo > 0 {
                anadir(.marcador, NSRange(location: l.inicio + marca, length: m.range.length))
                anadir(.tituloAviso, NSRange(location: l.inicio + finMarca, length: restoTitulo))
            } else {
                // Sin título: se ve el tipo («note») como título y se esconden `[!` y `]`.
                let tipoR = m.range(at: 1)
                anadir(.marcador, NSRange(location: l.inicio + marca, length: 2))
                anadir(.tituloAviso, NSRange(location: l.inicio + marca + tipoR.location, length: tipoR.length))
                anadir(.marcador, NSRange(location: l.inicio + marca + NSMaxRange(tipoR),
                                          length: m.range.length - NSMaxRange(tipoR)))
            }
        }
        descendInto(cita)
    }

    mutating func visitHeading(_ h: Heading) {
        guard let ls = tabla.lineas(de: h.range) else { descendInto(h); return }
        let primera = ls.lowerBound
        let l = tabla.lineas[primera]
        let linea = contenido(primera)
        let marca = marcaCita(linea, profundidad: bloques[primera].cita)
        let u = Array(linea.utf16)
        var i = marca
        while i < u.count, u[i] == 0x20 { i += 1 }
        if i < u.count, u[i] == 0x23 {
            // ATX: `## Título ##`
            for k in ls { bloques[k].tipo = .encabezado(h.level) }
            var j = i
            while j < u.count, u[j] == 0x23 { j += 1 }
            while j < u.count, u[j] == 0x20 || u[j] == 0x09 { j += 1 }
            anadir(.marcador, NSRange(location: l.inicio + marca, length: j - marca))
            // Cierre opcional: espacios y almohadillas al final.
            var fin = u.count
            while fin > j, u[fin - 1] == 0x20 || u[fin - 1] == 0x09 { fin -= 1 }
            var k = fin
            while k > j, u[k - 1] == 0x23 { k -= 1 }
            if k < fin, k > j, u[k - 1] == 0x20 || u[k - 1] == 0x09 {
                var desde = k
                while desde > j, u[desde - 1] == 0x20 || u[desde - 1] == 0x09 { desde -= 1 }
                anadir(.marcador, NSRange(location: l.inicio + desde, length: u.count - desde))
            }
        } else {
            // Subrayado (`===` o `---` en la línea de abajo).
            for k in ls { bloques[k].tipo = k == ls.upperBound ? .subrayadoEncabezado(h.level) : .encabezado(h.level) }
            let ul = tabla.lineas[ls.upperBound]
            anadir(.marcador, NSRange(location: ul.inicio, length: ul.longitud))
        }
        descendInto(h)
    }

    mutating func visitCodeBlock(_ c: CodeBlock) {
        guard let ls = tabla.lineas(de: c.range) else { return }
        let n = ls.count
        let primera = contenido(ls.lowerBound)
        let marca = marcaCita(primera, profundidad: bloques[ls.lowerBound].cita)
        let sinCita = (primera as NSString).substring(from: marca).drop(while: { $0 == " " })
        let valla: Character? = sinCita.hasPrefix("```") ? "`" : (sinCita.hasPrefix("~~~") ? "~" : nil)
        for (k, i) in ls.enumerated() {
            let l = tabla.lineas[i]
            let pos = PosicionEnBloque.de(k, en: n)
            excluir(NSRange(location: l.inicio, length: l.longitud))
            if valla != nil, k == 0 {
                bloques[i].tipo = .vallaCodigo(pos, lenguaje: c.language)
                anadir(.sustituido, NSRange(location: l.inicio, length: l.longitud))
            } else if let valla, k == n - 1, n > 1,
                      contenido(i).trimmingCharacters(in: .whitespaces).drop(while: { $0 == ">" || $0 == " " })
                        .allSatisfy({ $0 == valla }),
                      !contenido(i).trimmingCharacters(in: .whitespaces).isEmpty {
                bloques[i].tipo = .vallaCodigo(pos, lenguaje: nil)
                anadir(.sustituido, NSRange(location: l.inicio, length: l.longitud))
            } else {
                bloques[i].tipo = .codigo(pos)
            }
            if bloques[i].cita > 0 {
                let m = marcaCita(contenido(i), profundidad: bloques[i].cita)
                if m > 0 { anadir(.marcador, NSRange(location: l.inicio, length: m)) }
            }
        }
    }

    mutating func visitHTMLBlock(_ h: HTMLBlock) {
        guard let ls = tabla.lineas(de: h.range) else { return }
        for i in ls {
            let l = tabla.lineas[i]
            bloques[i].tipo = .html
            excluir(NSRange(location: l.inicio, length: l.longitud))
        }
    }

    mutating func visitThematicBreak(_ t: ThematicBreak) {
        guard let ls = tabla.lineas(de: t.range) else { return }
        let l = tabla.lineas[ls.lowerBound]
        bloques[ls.lowerBound].tipo = .separador
        anadir(.sustituido, NSRange(location: l.inicio, length: l.longitud))
    }

    mutating func visitTable(_ t: Table) {
        guard let ls = tabla.lineas(de: t.range) else { descendInto(t); return }
        for (k, i) in ls.enumerated() {
            let l = tabla.lineas[i]
            bloques[i].tipo = k == 0 ? .tablaCabecera : (k == 1 ? .tablaSeparador : .tablaFila)
            if k == 1 {
                anadir(.puntuacionTabla, NSRange(location: l.inicio, length: l.longitud))
                continue
            }
            // Las barras (no escapadas) se ven siempre atenuadas.
            let u = Array(contenido(i).utf16)
            var j = 0
            var enCodigo = false
            while j < u.count {
                if u[j] == 0x60 { enCodigo.toggle() }
                if u[j] == 0x5C { j += 2; continue }
                if u[j] == 0x7C, !enCodigo { anadir(.puntuacionTabla, NSRange(location: l.inicio + j, length: 1)) }
                j += 1
            }
        }
        descendInto(t)
    }

    mutating func visitListItem(_ item: ListItem) {
        guard let ls = tabla.lineas(de: item.range) else { descendInto(item); return }
        profundidadLista += 1
        defer { profundidadLista -= 1 }
        let primera = ls.lowerBound
        for i in ls { bloques[i].nivelLista = max(bloques[i].nivelLista, profundidadLista) }
        bloques[primera].elementoLista = true
        let l = tabla.lineas[primera]
        let linea = contenido(primera)
        let marca = marcaCita(linea, profundidad: bloques[primera].cita)
        let resto = (linea as NSString).substring(from: marca)
        let ns = resto as NSString
        if let m = AnalizadorMarkdown.marcaLista.firstMatch(in: resto, range: NSRange(location: 0, length: ns.length)) {
            let signo = m.range(at: 1)
            let tras = NSMaxRange(m.range)
            let abs = l.inicio + marca
            if let casilla = item.checkbox,
               let c = AnalizadorMarkdown.casilla.firstMatch(in: ns.substring(from: tras),
                                                             range: NSRange(location: 0, length: ns.length - tras)) {
                // Tarea: se esconde la viñeta y en el sitio de `[ ]` se dibuja la casilla.
                let hecha = casilla == .checked
                anadir(.marcador, NSRange(location: abs + signo.location, length: tras - signo.location))
                anadir(.casilla(marcada: hecha), NSRange(location: abs + tras, length: 3))
                let textoInicio = abs + tras + c.range.length
                let finItem = min(tabla.lineas[ls.upperBound].inicio + tabla.lineas[ls.upperBound].longitud, tabla.longitud)
                if hecha, finItem > textoInicio {
                    anadir(.tareaHecha, NSRange(location: textoInicio, length: finItem - textoInicio))
                }
            } else {
                let signoTexto = ns.substring(with: signo)
                if signoTexto == "-" || signoTexto == "*" || signoTexto == "+" {
                    anadir(.vineta, NSRange(location: abs + signo.location, length: signo.length))
                } else {
                    anadir(.numero, NSRange(location: abs + signo.location, length: signo.length))
                }
            }
        }
        descendInto(item)
    }

    mutating func visitParagraph(_ p: Paragraph) {
        // Una línea que solo tiene `![[…]]` o `![…](…)` es una incrustación (también dentro de un párrafo de
        // varias líneas, como en Obsidian). Sus tramos se rehacen al terminar.
        if let ls = tabla.lineas(de: p.range) {
            for i in ls where bloques[i].cita == 0 && bloques[i].nivelLista == 0 {
                if let (inc, _) = AnalizadorMarkdown.incrustacion(enLinea: contenido(i)) {
                    bloques[i].tipo = .incrustacion(inc)
                }
            }
        }
        descendInto(p)
    }

    // MARK: En línea

    mutating func delimitado(_ markup: Markup, clase: TramoMarkdown.Clase, ancho: (NSString, NSRange) -> Int) {
        guard let r = tabla.rango(markup.range), r.length > 0 else { return }
        anadir(clase, r)
        let n = min(ancho(texto, r), r.length / 2)
        if n > 0 {
            anadir(.marcador, NSRange(location: r.location, length: n))
            anadir(.marcador, NSRange(location: NSMaxRange(r) - n, length: n))
        }
    }

    static func repetidos(_ c: unichar, _ t: NSString, _ r: NSRange, maximo: Int) -> Int {
        var n = 0
        while n < r.length, n < maximo, t.character(at: r.location + n) == c { n += 1 }
        return n
    }

    mutating func visitStrong(_ s: Strong) {
        delimitado(s, clase: .negrita) { t, r in
            let c = t.character(at: r.location)
            return (c == 0x2A || c == 0x5F) ? 2 : 0
        }
        descendInto(s)
    }

    mutating func visitEmphasis(_ e: Emphasis) {
        delimitado(e, clase: .cursiva) { t, r in
            let c = t.character(at: r.location)
            return (c == 0x2A || c == 0x5F) ? 1 : 0
        }
        descendInto(e)
    }

    mutating func visitStrikethrough(_ s: Strikethrough) {
        delimitado(s, clase: .tachado) { t, r in Self.repetidos(0x7E, t, r, maximo: 2) }
        descendInto(s)
    }

    mutating func visitInlineCode(_ c: InlineCode) {
        guard let r = tabla.rango(c.range), r.length > 0 else { return }
        excluir(r)
        delimitado(c, clase: .codigo) { t, r in Self.repetidos(0x60, t, r, maximo: r.length / 2) }
    }

    mutating func visitInlineHTML(_ h: InlineHTML) {
        guard let r = tabla.rango(h.range), r.length > 0 else { return }
        excluir(r)
        anadir(.htmlEnLinea, r)
    }

    /// Enlace o imagen en línea: se ve el texto; `[`, `](destino)` (y `!` en las imágenes) son marcas.
    mutating func enlazado(_ markup: Markup, destino: String?) {
        guard let r = tabla.rango(markup.range), r.length > 0, let destino, !destino.isEmpty else {
            descendInto(markup)
            return
        }
        let hijos = Array(markup.children).compactMap { tabla.rango($0.range) }
        let p = AnalizadorMarkdown.partesMarkdown(destino)
        let textoVisible: String
        if let a = hijos.first, let b = hijos.last, NSMaxRange(b) > a.location {
            let visible = NSRange(location: a.location, length: NSMaxRange(b) - a.location)
            textoVisible = texto.substring(with: visible)
            let antes = NSRange(location: r.location, length: max(0, visible.location - r.location))
            let despues = NSRange(location: NSMaxRange(visible), length: max(0, NSMaxRange(r) - NSMaxRange(visible)))
            anadir(.enlace(EnlaceMarkdown(destino: p.destino, ancla: p.ancla, estilo: .markdown, texto: textoVisible)),
                   antes.length == 0 && despues.length == 0 ? r : visible)
            if antes.length > 0 { anadir(.marcador, antes) }
            if despues.length > 0 {
                anadir(.marcador, despues)
                excluir(despues)
            }
        } else {
            textoVisible = p.destino
            anadir(.enlace(EnlaceMarkdown(destino: p.destino, ancla: p.ancla, estilo: .markdown, texto: textoVisible)), r)
            excluir(r)
        }
        descendInto(markup)
    }

    mutating func visitLink(_ link: Link) {
        enlazado(link, destino: link.destination)
    }

    mutating func visitImage(_ image: Image) {
        enlazado(image, destino: image.source)
    }

    // MARK: Lo propio de Obsidian

    mutating func terminar() {
        for i in tabla.lineas.indices {
            guard case .incrustacion(let inc) = bloques[i].tipo else { continue }
            let l = tabla.lineas[i]
            let todo = NSRange(location: 0, length: l.longitud)
            tramos[i] = [TramoMarkdown(.enlace(inc.enlace), todo), TramoMarkdown(.marcador, todo)]
            excluidos[i] = [NSRange(location: l.inicio, length: l.longitud)]
        }
        for i in tabla.lineas.indices {
            let l = tabla.lineas[i]
            guard l.longitud > 0 else { continue }
            switch bloques[i].tipo {
            case .codigo, .vallaCodigo, .html, .incrustacion, .vacia: continue
            default: break
            }
            let linea = contenido(i)
            let ns = linea as NSString
            let todo = NSRange(location: 0, length: ns.length)
            var ocupados = excluidos[i].map { NSRange(location: $0.location - l.inicio, length: $0.length) }
            let enlacesAST = tramos[i].compactMap { t -> NSRange? in if case .enlace = t.clase { return t.rango }; return nil }
            func libre(_ r: NSRange) -> Bool {
                !ocupados.contains { NSIntersectionRange($0, r).length > 0 }
            }

            for m in AnalizadorMarkdown.wikilink.matches(in: linea, range: todo) where libre(m.range) {
                guard !enlacesAST.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { continue }
                let interiorR = m.range(at: 2)
                let p = AnalizadorMarkdown.partesWiki(ns.substring(with: interiorR))
                guard !p.destino.isEmpty || p.ancla != nil else { continue }
                // Lo que se ve: el texto tras `|` o, si no hay, el destino con su ancla.
                let visible: NSRange
                if let t = p.texto, !t.isEmpty {
                    let barra = ns.range(of: "|", range: interiorR)
                    visible = NSRange(location: NSMaxRange(barra), length: NSMaxRange(interiorR) - NSMaxRange(barra))
                } else {
                    visible = interiorR
                }
                let enlace = EnlaceMarkdown(destino: p.destino, ancla: p.ancla, estilo: .wiki,
                                            texto: ns.substring(with: visible))
                tramos[i].append(TramoMarkdown(.enlace(enlace), visible))
                tramos[i].append(TramoMarkdown(.marcador, NSRange(location: m.range.location, length: visible.location - m.range.location)))
                tramos[i].append(TramoMarkdown(.marcador, NSRange(location: NSMaxRange(visible), length: NSMaxRange(m.range) - NSMaxRange(visible))))
                ocupados.append(m.range)
            }
            for m in AnalizadorMarkdown.comentario.matches(in: linea, range: todo) where libre(m.range) {
                tramos[i].append(TramoMarkdown(.comentario, m.range))
                tramos[i].append(TramoMarkdown(.marcador, NSRange(location: m.range.location, length: 2)))
                tramos[i].append(TramoMarkdown(.marcador, NSRange(location: NSMaxRange(m.range) - 2, length: 2)))
                ocupados.append(m.range)
            }
            for m in AnalizadorMarkdown.resaltado.matches(in: linea, range: todo) where libre(m.range) {
                tramos[i].append(TramoMarkdown(.resaltado, m.range))
                tramos[i].append(TramoMarkdown(.marcador, NSRange(location: m.range.location, length: 2)))
                tramos[i].append(TramoMarkdown(.marcador, NSRange(location: NSMaxRange(m.range) - 2, length: 2)))
            }
            let enlacesWeb = linea.contains("://") ? AnalizadorMarkdown.detectorWeb.matches(in: linea, range: todo).map(\.range) : []
            if linea.contains("#") {
                for m in AnalizadorMarkdown.etiqueta.matches(in: linea, range: todo) where libre(m.range) {
                    guard !enlacesWeb.contains(where: { NSIntersectionRange($0, m.range).length > 0 }),
                          !enlacesAST.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { continue }
                    // `#` de un título ATX no es una etiqueta (ya es marca).
                    if case .encabezado = bloques[i].tipo,
                       tramos[i].contains(where: { $0.clase == .marcador && NSLocationInRange(m.range.location, $0.rango) }) { continue }
                    tramos[i].append(TramoMarkdown(.etiqueta, m.range))
                }
            }
            if linea.contains("\\") {
                for m in AnalizadorMarkdown.escape.matches(in: linea, range: todo) where libre(m.range) {
                    tramos[i].append(TramoMarkdown(.marcador, NSRange(location: m.range.location, length: 1)))
                }
            }
            // Marcas de cita (`>`) de cada línea, también en los avisos.
            if bloques[i].cita > 0 {
                let m = marcaCita(linea, profundidad: bloques[i].cita)
                if m > 0, !tramos[i].contains(where: { $0.clase == .marcador && $0.rango.location == 0 && $0.rango.length >= m }) {
                    tramos[i].append(TramoMarkdown(.marcador, NSRange(location: 0, length: m)))
                }
            }
        }
        // Las citas de líneas de código ya tienen su marca; en las vacías no hace falta.
        for i in tabla.lineas.indices where bloques[i].cita > 0 && bloques[i].tipo == .vacia {
            let m = marcaCita(contenido(i), profundidad: bloques[i].cita)
            if m > 0 { tramos[i].append(TramoMarkdown(.marcador, NSRange(location: 0, length: m))) }
        }
    }
}
