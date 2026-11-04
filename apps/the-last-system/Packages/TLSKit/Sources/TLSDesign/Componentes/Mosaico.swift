import SwiftUI

/// Tamaños de mosaico (§6): Pequeño 1×1, Mediano 2×1, Grande 2×2 y Ancho 4×1.
public enum TamanoMosaico: String, CaseIterable, Sendable, Hashable, Codable {
    case pequeno, mediano, grande, ancho

    public var columnas: Int {
        switch self {
        case .pequeno: 1
        case .mediano, .grande: 2
        case .ancho: 4
        }
    }

    public var filas: Int { self == .grande ? 2 : 1 }
}

struct TamanoMosaicoKey: LayoutValueKey {
    static let defaultValue: TamanoMosaico = .pequeno
}

public extension View {
    /// Cuánto ocupa la vista dentro de un `MosaicoLayout`.
    func tamanoMosaico(_ tamano: TamanoMosaico) -> some View {
        layoutValue(key: TamanoMosaicoKey.self, value: tamano)
    }
}

/// Un mosaico (§6): `superficie`, radio 22, sombra 1. Arriba el icono del área (16 pt) y el nombre en
/// `rotulo`; en medio el contenido; al pie, «Sale de…» en `secundario`.
public struct Mosaico<Contenido: View>: View {
    let titulo: String
    let icono: String?
    let area: TLSArea?
    let tamano: TamanoMosaico
    let pie: String?
    let contenido: Contenido

    public init(_ titulo: String, icono: String? = nil, area: TLSArea? = nil, tamano: TamanoMosaico = .pequeno,
                pie: String? = nil, @ViewBuilder contenido: () -> Contenido) {
        self.titulo = titulo; self.icono = icono; self.area = area; self.tamano = tamano; self.pie = pie
        self.contenido = contenido()
    }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: TLSEspacio.e8) {
                if let area {
                    IconoArea(area, tamano: 16)
                } else if let icono {
                    Image(systemName: icono)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .accessibilityHidden(true)
                }
                Rotulo(titulo)
                Spacer(minLength: 0)
            }
            contenido.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if let pie {
                Text(pie)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(2)
            }
        }
        .padding(tamano == .grande ? TLSEspacio.mosaicoGrande : TLSEspacio.mosaicoPequeno)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(titulo)
        .tamanoMosaico(tamano)
    }
}

/// Rejilla de 4 columnas de los inicios (Hoy, el Resumen de un área y el de una ficha), §6 y §7.3.
/// Coloca cada vista en el primer hueco donde quepa, de izquierda a derecha y de arriba abajo. Con poco
/// ancho baja a 2 columnas y a 1.
public struct MosaicoLayout: Layout {
    public var columnas: Int
    public var espacio: CGFloat
    public var altoFila: CGFloat
    public var anchoMinimoColumna: CGFloat

    public init(columnas: Int = 4, espacio: CGFloat = TLSEspacio.entreMosaicos, altoFila: CGFloat = 156,
                anchoMinimoColumna: CGFloat = 180) {
        self.columnas = columnas; self.espacio = espacio; self.altoFila = altoFila
        self.anchoMinimoColumna = anchoMinimoColumna
    }

    /// Una celda colocada: columna, fila y cuántas ocupa.
    public struct Celda: Hashable, Sendable {
        public let columna: Int, fila: Int, ancho: Int, alto: Int
    }

    public func columnasEfectivas(ancho: CGFloat) -> Int {
        let caben = Int((ancho + espacio) / (anchoMinimoColumna + espacio))
        return max(1, min(columnas, caben >= 4 ? 4 : (caben >= 2 ? 2 : 1)))
    }

    /// Primer hueco libre para cada tamaño, en orden (pura: la usan las pruebas).
    public static func colocar(_ tamanos: [TamanoMosaico], columnas: Int) -> [Celda] {
        var ocupado: [[Bool]] = []
        func libre(_ c: Int, _ f: Int, _ w: Int, _ h: Int) -> Bool {
            for y in f..<(f + h) {
                while ocupado.count <= y { ocupado.append(Array(repeating: false, count: columnas)) }
                for x in c..<(c + w) where ocupado[y][x] { return false }
            }
            return true
        }
        var out: [Celda] = []
        for t in tamanos {
            let w = min(t.columnas, columnas)
            let h = columnas == 1 ? 1 : t.filas
            var fila = 0
            colocado: while true {
                for col in 0...(columnas - w) where libre(col, fila, w, h) {
                    for y in fila..<(fila + h) { for x in col..<(col + w) { ocupado[y][x] = true } }
                    out.append(Celda(columna: col, fila: fila, ancho: w, alto: h))
                    break colocado
                }
                fila += 1
            }
        }
        return out
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? (CGFloat(columnas) * anchoMinimoColumna + CGFloat(columnas - 1) * espacio)
        let cols = columnasEfectivas(ancho: ancho)
        let celdas = Self.colocar(subviews.map { $0[TamanoMosaicoKey.self] }, columnas: cols)
        let filas = celdas.map { $0.fila + $0.alto }.max() ?? 0
        return CGSize(width: ancho, height: filas == 0 ? 0 : CGFloat(filas) * altoFila + CGFloat(filas - 1) * espacio)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columnasEfectivas(ancho: bounds.width)
        let anchoColumna = (bounds.width - CGFloat(cols - 1) * espacio) / CGFloat(cols)
        let celdas = Self.colocar(subviews.map { $0[TamanoMosaicoKey.self] }, columnas: cols)
        for (vista, celda) in zip(subviews, celdas) {
            let x = bounds.minX + CGFloat(celda.columna) * (anchoColumna + espacio)
            let y = bounds.minY + CGFloat(celda.fila) * (altoFila + espacio)
            let w = CGFloat(celda.ancho) * anchoColumna + CGFloat(celda.ancho - 1) * espacio
            let h = CGFloat(celda.alto) * altoFila + CGFloat(celda.alto - 1) * espacio
            vista.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: h))
        }
    }
}
