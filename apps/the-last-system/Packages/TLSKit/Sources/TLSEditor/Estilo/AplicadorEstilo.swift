import AppKit
import TLSDesign

/// Pone los atributos de una línea analizada en el texto. **Nunca cambia un carácter**: las marcas se
/// esconden con atributos (letra casi nula y color transparente) y la longitud del párrafo no cambia.
@MainActor
struct AplicadorEstilo {
    let tema: TemaEditor

    /// Qué se sabe fuera del análisis para pintar una línea.
    struct Contexto {
        /// La línea del cursor (en Edición en vivo): las marcas se ven, atenuadas.
        var cursor = false
        /// Alto del bloque de la incrustación de esta línea, si el proveedor la sabe pintar.
        var altoIncrustacion: CGFloat?
        /// Estado de cada enlace (existe, roto, externo).
        var estadoEnlace: (EnlaceMarkdown) -> EstadoEnlace = { $0.esExterno ? .externa : .existe }
    }

    private struct Marca: OptionSet, Hashable {
        let rawValue: UInt32
        static let negrita = Marca(rawValue: 1 << 0)
        static let cursiva = Marca(rawValue: 1 << 1)
        static let tachado = Marca(rawValue: 1 << 2)
        static let codigo = Marca(rawValue: 1 << 3)
        static let resaltado = Marca(rawValue: 1 << 4)
        static let comentario = Marca(rawValue: 1 << 5)
        static let etiqueta = Marca(rawValue: 1 << 6)
        static let html = Marca(rawValue: 1 << 7)
        static let marcador = Marca(rawValue: 1 << 8)
        static let sustituido = Marca(rawValue: 1 << 9)
        static let casilla = Marca(rawValue: 1 << 10)
        static let casillaHecha = Marca(rawValue: 1 << 11)
        static let vineta = Marca(rawValue: 1 << 12)
        static let numero = Marca(rawValue: 1 << 13)
        static let tareaHecha = Marca(rawValue: 1 << 14)
        static let tituloAviso = Marca(rawValue: 1 << 15)
        static let puntuacionTabla = Marca(rawValue: 1 << 16)
    }

    /// Cómo se tratan las marcas en esta línea.
    private enum Marcas { case visibles, escondidas, crudas }

    /// Aplica el estilo de `p` (que debe corresponder al texto actual) en `storage`.
    func aplicar(_ p: ParrafoMarkdown, en storage: NSTextStorage, contexto c: Contexto) {
        let completo = p.rangoCompleto
        guard NSMaxRange(completo) <= storage.length else { return }
        let modo = tema.modo
        let marcas: Marcas = modo == .fuente ? .crudas : (c.cursor && modo == .vivo ? .visibles : .escondidas)
        var bloque = p.bloque
        let incrustada = c.altoIncrustacion != nil && modo != .fuente
        // Una incrustación que nadie sabe pintar se ve como un enlace normal.
        if case .incrustacion = bloque.tipo, !incrustada { bloque.tipo = .texto }
        let colapsada = incrustada && marcas == .escondidas
        let estilo = tema.estilo(de: bloque)
        let fuenteBase = tema.fuente(estilo)

        // Banderas por carácter.
        let n = p.longitud
        var banderas = [Marca](repeating: [], count: n)
        var enlaceDe = [Int](repeating: -1, count: n)
        var enlaces: [EnlaceMarkdown] = []
        for t in p.tramos {
            let a = max(0, t.rango.location), b = min(n, NSMaxRange(t.rango))
            guard b > a else { continue }
            var m: Marca = []
            switch t.clase {
            case .negrita: m = .negrita
            case .cursiva: m = .cursiva
            case .tachado: m = .tachado
            case .codigo: m = .codigo
            case .resaltado: m = .resaltado
            case .comentario: m = .comentario
            case .etiqueta: m = .etiqueta
            case .htmlEnLinea: m = .html
            case .marcador:
                // En una incrustación que no se pinta como bloque, el enlace se ve entero.
                if case .incrustacion = p.bloque.tipo, !incrustada { continue }
                m = .marcador
            case .sustituido: m = .sustituido
            case .casilla(let hecha): m = hecha ? [.casilla, .casillaHecha] : .casilla
            case .vineta: m = .vineta
            case .numero: m = .numero
            case .tareaHecha: m = .tareaHecha
            case .tituloAviso: m = .tituloAviso
            case .puntuacionTabla: m = .puntuacionTabla
            case .enlace(let e):
                enlaces.append(e)
                for i in a..<b { enlaceDe[i] = enlaces.count - 1 }
                continue
            }
            for i in a..<b { banderas[i].formUnion(m) }
        }

        // Atributos de la línea entera.
        var base: [NSAttributedString.Key: Any] = [
            .font: fuenteBase,
            .foregroundColor: tema.texto,
            .paragraphStyle: tema.parrafo(bloque, sangria: sangria(p, banderas: banderas, fuente: fuenteBase, storage: storage, marcas: marcas),
                                          colapsada: colapsada, alto: incrustada ? c.altoIncrustacion : nil),
        ]
        if modo != .fuente {
            var fondo: DecoracionBloque.Fondo?
            switch bloque.tipo {
            case .codigo(let pos): fondo = .codigo(pos)
            case .vallaCodigo(let pos, _): fondo = .codigo(pos)
            default: break
            }
            if let a = bloque.aviso { fondo = .aviso(tipo: a.tipo, a.posicion) }
            var separador = false
            if case .separador = bloque.tipo { separador = marcas != .visibles }
            let deco = DecoracionBloque(fondo: fondo, cita: bloque.aviso == nil ? bloque.cita : 0, separador: separador,
                                        marcasVisibles: marcas != .escondidas)
            if deco.dibujaAlgo || banderas.contains(where: { !$0.isDisjoint(with: [.casilla, .vineta, .codigo, .etiqueta, .resaltado]) }) {
                base[.tlsBloque] = deco
            }
            if case .subrayadoEncabezado = bloque.tipo { base[.foregroundColor] = tema.secundario }
        }
        storage.setAttributes(base, range: completo)
        guard n > 0 else { return }

        // Tramos con el mismo estilo.
        var i = 0
        while i < n {
            var j = i + 1
            while j < n, banderas[j] == banderas[i], enlaceDe[j] == enlaceDe[i] { j += 1 }
            let atributos = atributosDeTramo(banderas[i], enlace: enlaceDe[i] >= 0 ? enlaces[enlaceDe[i]] : nil,
                                             estilo: estilo, bloque: bloque, marcas: marcas, contexto: c)
            if !atributos.isEmpty {
                storage.addAttributes(atributos, range: NSRange(location: p.inicio + i, length: j - i))
            }
            i = j
        }
    }

    /// Sangría de las líneas partidas de un elemento de lista: hasta donde empieza el texto.
    private func sangria(_ p: ParrafoMarkdown, banderas: [Marca], fuente: NSFont, storage: NSTextStorage, marcas: Marcas) -> CGFloat {
        guard p.bloque.elementoLista, tema.modo != .fuente else { return 0 }
        var fin = 0
        while fin < banderas.count, banderas[fin].contains(.marcador) || banderas[fin].contains(.vineta)
                || banderas[fin].contains(.casilla) || banderas[fin].contains(.numero) { fin += 1 }
        // Espacios de sangría y tras la marca.
        let ns: NSString = storage.mutableString
        while fin < p.longitud, ns.character(at: p.inicio + fin) == 0x20 || ns.character(at: p.inicio + fin) == 0x09 { fin += 1 }
        guard fin > 0 else { return 0 }
        // Lo que se ve del principio de la línea (sin las marcas escondidas), medido una vez por forma.
        var visible = ""
        for k in 0..<fin {
            let oculto = banderas.indices.contains(k) && banderas[k].contains(.marcador) && marcas == .escondidas
            if !oculto, let u = UnicodeScalar(ns.character(at: p.inicio + k)) { visible.unicodeScalars.append(u) }
        }
        return tema.ancho(visible, fuente: fuente)
    }

    private func atributosDeTramo(_ m: Marca, enlace: EnlaceMarkdown?, estilo: TLSEstiloTexto, bloque: BloqueLinea,
                                  marcas: Marcas, contexto c: Contexto) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [:]
        let enCodigo = m.contains(.codigo) && !bloque.esCodigo && tema.modo != .fuente
        let estiloTramo = enCodigo ? tema.codigoEnLinea : estilo
        let negrita = m.contains(.negrita) || m.contains(.tituloAviso)
        let cursiva = m.contains(.cursiva) || (m.contains(.comentario) && tema.modo != .fuente)
        if negrita || cursiva || enCodigo {
            a[.font] = tema.fuente(estiloTramo, negrita: negrita, cursiva: cursiva)
        }
        if m.contains(.tachado) || m.contains(.tareaHecha) {
            a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if m.contains(.tareaHecha) || m.contains(.comentario) || m.contains(.html) || m.contains(.puntuacionTabla)
            || m.contains(.numero) {
            a[.foregroundColor] = tema.secundario
        }
        if tema.modo != .fuente {
            if enCodigo { a[.tlsFondo] = TLSColorCaja(TLSPaleta.bandeja) }
            if m.contains(.etiqueta) {
                a[.foregroundColor] = tema.principal
                a[.tlsFondo] = TLSColorCaja(TLSPaleta.principalSuave)
            }
            if m.contains(.resaltado) { a[.tlsFondo] = TLSColorCaja(TLSPaleta.principalSuave) }
            if m.contains(.tituloAviso), let tipo = bloque.aviso?.tipo {
                a[.foregroundColor] = AspectoAviso.colores(tipo).tinta.ns
            }
        } else if m.contains(.codigo) || m.contains(.etiqueta) {
            a[.foregroundColor] = tema.principal
        }
        if let enlace {
            let estado = c.estadoEnlace(enlace)
            a[.tlsEnlace] = CajaEnlace(enlace, estado: estado)
            a[.foregroundColor] = estado == .rota ? tema.secundario : tema.enlace
            a[.underlineStyle] = estado == .rota
                ? NSUnderlineStyle([.single, .patternDash]).rawValue : NSUnderlineStyle.single.rawValue
        }
        // Marcas: atenuadas, escondidas o en su sitio pero invisibles (se dibuja algo encima).
        let esMarca = m.contains(.marcador) || m.contains(.sustituido) || m.contains(.casilla) || m.contains(.vineta)
        if esMarca {
            a[.tlsMarcador] = true
            switch marcas {
            case .crudas, .visibles:
                a[.foregroundColor] = tema.secundario
                a[.underlineStyle] = nil
                a.removeValue(forKey: .tlsFondo)
            case .escondidas:
                a[.foregroundColor] = NSColor.clear
                a.removeValue(forKey: .underlineStyle)
                a.removeValue(forKey: .strikethroughStyle)
                a.removeValue(forKey: .tlsFondo)
                if m.contains(.marcador) || (m.contains(.comentario) && tema.modo == .lectura) {
                    a[.font] = tema.fuenteOculta
                }
                if m.contains(.casilla) { a[.tlsCasilla] = m.contains(.casillaHecha) }
                if m.contains(.vineta) { a[.tlsVineta] = true }
            }
        } else if m.contains(.comentario), tema.modo == .lectura, marcas == .escondidas {
            // En Lectura, los comentarios `%%…%%` no se ven (como en Obsidian).
            a[.font] = tema.fuenteOculta
            a[.foregroundColor] = NSColor.clear
            a[.tlsMarcador] = true
        }
        return a
    }
}
