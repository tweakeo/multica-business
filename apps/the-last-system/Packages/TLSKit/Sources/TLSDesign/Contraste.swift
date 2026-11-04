import Foundation

/// Contraste con la fórmula de WCAG 2.x (luminancia relativa en sRGB).
public enum TLSContraste {
    /// Mínimo para texto normal.
    public static let texto = 4.5
    /// Mínimo para iconos, bordes de control y anillo de foco.
    public static let grafico = 3.0

    public static func luminancia(_ c: TLSTokens.RGBA) -> Double {
        func lineal(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lineal(c.r) + 0.7152 * lineal(c.g) + 0.0722 * lineal(c.b)
    }

    /// Relación de contraste entre un primer plano (que puede ser translúcido) y un fondo opaco.
    public static func relacion(_ primerPlano: TLSTokens.RGBA, sobre fondo: TLSTokens.RGBA) -> Double {
        let a = luminancia(primerPlano.sobre(fondo))
        let b = luminancia(fondo)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public extension TLSTokens.RGBA {
    /// Composición sobre un fondo opaco (alfa simple).
    func sobre(_ fondo: TLSTokens.RGBA) -> TLSTokens.RGBA {
        guard a < 1 else { return self }
        return TLSTokens.RGBA(r: r * a + fondo.r * (1 - a), g: g * a + fondo.g * (1 - a), b: b * a + fondo.b * (1 - a))
    }
}

/// Una pareja de colores de §1 que tiene que pasar un mínimo de contraste.
public struct TLSPareja: Sendable, Hashable, CustomStringConvertible {
    public let nombre: String
    public let primerPlano: TLSColor
    public let fondo: TLSColor
    /// Si el fondo es translúcido (el tinte de una pastilla), se compone antes sobre esta base.
    public let base: TLSColor?
    public let oscuro: Bool
    public let contraste: Bool
    public let minimo: Double
    /// Valor que da el documento de diseño (para detectar que alguien cambió un color sin cambiar el documento).
    public let documentado: Double?

    public init(_ nombre: String, _ primerPlano: TLSColor, sobre fondo: TLSColor, base: TLSColor? = nil,
                oscuro: Bool, contraste: Bool = false, minimo: Double, documentado: Double? = nil) {
        self.nombre = nombre; self.primerPlano = primerPlano; self.fondo = fondo; self.base = base
        self.oscuro = oscuro; self.contraste = contraste; self.minimo = minimo; self.documentado = documentado
    }

    public var relacion: Double {
        var f = fondo.valor(oscuro: oscuro, contraste: contraste)
        if let base { f = f.sobre(base.valor(oscuro: oscuro, contraste: contraste)) }
        return TLSContraste.relacion(primerPlano.valor(oscuro: oscuro, contraste: contraste), sobre: f)
    }

    public var description: String {
        "\(nombre) (\(oscuro ? "oscuro" : "claro")\(contraste ? ", más contraste" : ""))"
    }
}

/// Todas las parejas de color de `DISENO-MOSAICO-V2.md` §1, con su mínimo (criterio §11.2).
public enum TLSParejas {
    public static var todas: [TLSPareja] {
        typealias P = TLSPaleta
        let fondosClaro = [P.fondo, P.superficie, P.bandeja]
        let fondosOscuro = [P.fondo, P.superficie, P.superficieElevada]
        var out: [TLSPareja] = []

        /// Primer plano sobre los tres fondos de cada modo.
        func sobreFondos(_ nombre: String, _ c: TLSColor, minimo: Double, claro: [Double]? = nil, oscuro: [Double]? = nil,
                         contraste: Bool = false) {
            for (i, f) in fondosClaro.enumerated() {
                out.append(TLSPareja("\(nombre) sobre \(f.id)", c, sobre: f, oscuro: false, contraste: contraste,
                                     minimo: minimo, documentado: claro?[i]))
            }
            for (i, f) in fondosOscuro.enumerated() {
                out.append(TLSPareja("\(nombre) sobre \(f.id)", c, sobre: f, oscuro: true, contraste: contraste,
                                     minimo: minimo, documentado: oscuro?[i]))
            }
        }
        func ambos(_ nombre: String, _ c: TLSColor, sobre f: TLSColor, minimo: Double, claro: Double? = nil,
                   oscuro: Double? = nil, base: TLSColor? = nil) {
            out.append(TLSPareja(nombre, c, sobre: f, base: base, oscuro: false, minimo: minimo, documentado: claro))
            out.append(TLSPareja(nombre, c, sobre: f, base: base, oscuro: true, minimo: minimo, documentado: oscuro))
        }

        // §1.2 Neutros
        sobreFondos("texto", P.texto, minimo: TLSContraste.texto, claro: [16.55, 18.06, 15.16], oscuro: [18.48, 15.99, 14.11])
        sobreFondos("textoSecundario", P.textoSecundario, minimo: TLSContraste.texto, claro: [6.17, 6.73, 5.65], oscuro: [8.27, 7.16, 6.31])
        sobreFondos("bordeControl", P.bordeControl, minimo: TLSContraste.grafico, claro: [3.52, 3.84, 3.22], oscuro: [4.53, 3.92, 3.46])
        ambos("subtituloCabecera sobre cabecera", P.subtituloCabecera, sobre: P.cabecera, minimo: TLSContraste.texto, claro: 7.79, oscuro: 7.79)
        ambos("blanco sobre cabecera", P.sobreColor, sobre: P.cabecera, minimo: TLSContraste.texto, claro: 12.67, oscuro: 12.67)

        // §1.3 Azul noche
        ambos("sobrePrincipal sobre principal", P.sobrePrincipal, sobre: P.principal, minimo: TLSContraste.texto, claro: 12.67, oscuro: 6.24)
        out.append(TLSPareja("principal frente al fondo", P.principal, sobre: P.fondo, oscuro: false, minimo: TLSContraste.grafico, documentado: 11.61))
        for (f, v) in zip(fondosOscuro, [7.05, 6.10, 5.39]) {
            out.append(TLSPareja("principal frente a \(f.id)", P.principal, sobre: f, oscuro: true, minimo: TLSContraste.grafico, documentado: v))
        }
        ambos("sobrePrincipal sobre principalHover", P.sobrePrincipal, sobre: P.principalHover, minimo: TLSContraste.texto, claro: 9.69, oscuro: 7.86)
        ambos("sobrePrincipal sobre principalPulsado", P.sobrePrincipal, sobre: P.principalPulsado, minimo: TLSContraste.texto, claro: 15.57, oscuro: 4.84)
        ambos("desactivadoTexto sobre desactivadoRelleno", P.desactivadoTexto, sobre: P.desactivadoRelleno, minimo: TLSContraste.texto, claro: 5.65, oscuro: 6.31)
        // Botón desactivado sobre la cabecera y sobre el destacado (revisión F1: el gris daba 1,9:1 y 1,2:1).
        ambos("desactivadoSobreColor sobre cabecera", P.desactivadoSobreColor, sobre: P.cabecera, minimo: TLSContraste.texto)
        ambos("desactivadoSobreColor sobre violeta", P.desactivadoSobreColor, sobre: P.violeta, minimo: TLSContraste.texto)
        ambos("borde desactivado sobre cabecera", P.desactivadoSobreColorBorde, sobre: P.cabecera, minimo: 1.5)
        ambos("principal sobre principalSuave", P.principal, sobre: P.principalSuave, minimo: TLSContraste.texto, claro: 10.55, oscuro: 4.64)
        sobreFondos("enlace", P.enlace, minimo: TLSContraste.texto, claro: [6.89, 7.51, 6.31])
        out.append(TLSPareja("enlace sobre superficie", P.enlace, sobre: P.superficie, oscuro: true, minimo: TLSContraste.texto, documentado: 7.69))

        // §1.4 Violeta
        ambos("blanco sobre violeta", P.sobreColor, sobre: P.violeta, minimo: TLSContraste.texto, claro: 5.70, oscuro: 5.70)
        out.append(TLSPareja("violeta frente al fondo", P.violeta, sobre: P.fondo, oscuro: false, minimo: TLSContraste.grafico, documentado: 5.22))
        out.append(TLSPareja("violeta frente al fondo", P.violeta, sobre: P.fondo, oscuro: true, minimo: TLSContraste.grafico, documentado: 3.69))
        out.append(TLSPareja("violeta frente a la superficie", P.violeta, sobre: P.superficie, oscuro: true, minimo: TLSContraste.grafico, documentado: 3.19))
        ambos("blanco sobre violetaHover", P.sobreColor, sobre: P.violetaHover, minimo: TLSContraste.texto, claro: 7.10, oscuro: 4.69)
        ambos("blanco sobre violetaPulsado", P.sobreColor, sobre: P.violetaPulsado, minimo: TLSContraste.texto, claro: 8.98, oscuro: 7.10)
        ambos("violeta sobre blanco (botón del destacado)", P.violeta, sobre: P.sobreColor, minimo: TLSContraste.texto, claro: 5.70, oscuro: 5.70)
        sobreFondos("violetaTexto", P.violetaTexto, minimo: TLSContraste.texto, claro: [5.22, 5.70, 4.78], oscuro: [7.72, 6.68, 5.89])
        out.append(TLSPareja("violeta sobre violetaSuave", P.violeta, sobre: P.violetaSuave, oscuro: false, minimo: TLSContraste.texto, documentado: 4.91))
        out.append(TLSPareja("violetaTexto sobre violetaSuave", P.violetaTexto, sobre: P.violetaSuave, oscuro: true, minimo: TLSContraste.texto, documentado: 5.56))

        // §1.5 Magenta
        for (f, v) in zip(fondosClaro, [4.13, 4.50, 3.78]) {
            out.append(TLSPareja("anillo frente a \(f.id)", P.anillo, sobre: f, oscuro: false, minimo: TLSContraste.grafico, documentado: v))
        }
        for (f, v) in zip(fondosOscuro + [P.bandeja], [4.67, 4.04, 3.56, 4.28]) {
            out.append(TLSPareja("anillo frente a \(f.id)", P.anillo, sobre: f, oscuro: true, minimo: TLSContraste.grafico, documentado: v))
        }
        ambos("anillo blanco sobre la cabecera", P.sobreColor, sobre: P.cabecera, minimo: TLSContraste.grafico, claro: 12.67, oscuro: 12.67)
        ambos("anillo blanco sobre el violeta", P.sobreColor, sobre: P.violeta, minimo: TLSContraste.grafico, claro: 5.70, oscuro: 5.70)
        ambos("número blanco sobre la insignia", P.sobreColor, sobre: P.chispa, minimo: TLSContraste.texto, claro: 4.50, oscuro: 4.50)
        out.append(TLSPareja("número blanco sobre la insignia", P.sobreColor, sobre: P.chispa, oscuro: false, contraste: true, minimo: TLSContraste.texto, documentado: 5.90))
        out.append(TLSPareja("número blanco sobre la insignia", P.sobreColor, sobre: P.chispa, oscuro: true, contraste: true, minimo: TLSContraste.texto, documentado: 5.90))
        sobreFondos("chispaTexto", P.chispaTexto, minimo: TLSContraste.texto, claro: [5.41, 5.90, 4.95], oscuro: [6.39, 5.53, 4.88])

        // §1.6 Estados y pastillas (la palabra va en `texto` sobre el tinte)
        let estados: [(TLSEstado, [Double], [Double])] = [
            (.bien, [4.92, 5.37, 4.51], [9.72, 8.41, 7.42]),
            (.atencion, [4.93, 5.38, 4.51], [9.70, 8.40, 7.41]),
            (.mal, [4.93, 5.38, 4.52], [9.75, 8.44, 7.44]),
            (.sinDato, [4.93, 5.37, 4.51], [9.73, 8.42, 7.43]),
        ]
        for (e, claro, oscuro) in estados {
            sobreFondos("estado \(e.rawValue)", e.color, minimo: TLSContraste.texto, claro: claro, oscuro: oscuro)
            for f in fondosClaro {
                out.append(TLSPareja("palabra sobre la pastilla \(e.rawValue) en \(f.id)", P.texto, sobre: e.tinte, base: f, oscuro: false, minimo: TLSContraste.texto))
            }
            for f in fondosOscuro {
                out.append(TLSPareja("palabra sobre la pastilla \(e.rawValue) en \(f.id)", P.texto, sobre: e.tinte, base: f, oscuro: true, minimo: TLSContraste.texto))
            }
            out.append(TLSPareja("icono \(e.rawValue) sobre la pastilla en el destacado", e.color, sobre: P.sobreColor, oscuro: false, minimo: TLSContraste.grafico))
        }

        // §1.7 Áreas: tinta ≥ 4,5 y relleno ≥ 3 sobre los tres fondos de cada modo; glifo ≥ 3 sobre el relleno.
        for area in TLSArea.allCases {
            sobreFondos("tinta \(area.rawValue)", area.tinta, minimo: TLSContraste.texto)
            sobreFondos("relleno \(area.rawValue)", area.relleno, minimo: TLSContraste.grafico)
            ambos("glifo sobre el relleno \(area.rawValue)", P.glifo, sobre: area.relleno, minimo: TLSContraste.grafico)
            out.append(TLSPareja("glifo sobre el relleno \(area.rawValue)", P.glifo, sobre: area.relleno, oscuro: false, contraste: true, minimo: TLSContraste.grafico))
            out.append(TLSPareja("glifo sobre el relleno \(area.rawValue)", P.glifo, sobre: area.relleno, oscuro: true, contraste: true, minimo: TLSContraste.grafico))
            ambos("icono \(area.rawValue) en blanco sobre la cabecera", area.glifoSobreBlanco, sobre: P.sobreColor, minimo: TLSContraste.grafico)
        }
        // Valores documentados de las áreas (el peor de los tres fondos).
        let docAreas: [(TLSArea, Double, Double, Double, Double, Double, Double)] = [
            (.direccion, 9.39, 7.83, 9.33, 6.16, 4.26, 4.80),
            (.equipo, 8.13, 6.52, 7.77, 6.97, 5.23, 5.89),
            (.entrega, 7.07, 5.45, 6.49, 7.89, 6.24, 7.03),
            (.marca, 6.07, 4.44, 5.28, 8.85, 7.44, 8.38),
            (.ventas, 5.20, 3.65, 4.35, 9.97, 8.75, 9.86),
            (.finanzas, 4.60, 3.07, 3.66, 11.13, 10.23, 11.52),
        ]
        for (a, tC, rC, gC, tO, rO, gO) in docAreas {
            out.append(TLSPareja("tinta \(a.rawValue) (peor fondo)", a.tinta, sobre: P.bandeja, oscuro: false, minimo: TLSContraste.texto, documentado: tC))
            out.append(TLSPareja("relleno \(a.rawValue) (peor fondo)", a.relleno, sobre: P.bandeja, oscuro: false, minimo: TLSContraste.grafico, documentado: rC))
            out.append(TLSPareja("glifo \(a.rawValue)", P.glifo, sobre: a.relleno, oscuro: false, minimo: TLSContraste.grafico, documentado: gC))
            out.append(TLSPareja("tinta \(a.rawValue) (peor fondo)", a.tinta, sobre: P.superficieElevada, oscuro: true, minimo: TLSContraste.texto, documentado: tO))
            out.append(TLSPareja("relleno \(a.rawValue) (peor fondo)", a.relleno, sobre: P.superficieElevada, oscuro: true, minimo: TLSContraste.grafico, documentado: rO))
            out.append(TLSPareja("glifo \(a.rawValue)", P.glifo, sobre: a.relleno, oscuro: true, minimo: TLSContraste.grafico, documentado: gO))
        }

        // §1.8 Aumentar contraste
        sobreFondos("textoSecundario con más contraste", P.textoSecundario, minimo: TLSContraste.texto,
                    claro: [8.58, 9.36, 7.86], oscuro: [11.81, 10.22, 9.02], contraste: true)
        sobreFondos("separador con más contraste", P.separador, minimo: TLSContraste.grafico, contraste: true)
        sobreFondos("texto con más contraste", P.texto, minimo: TLSContraste.texto, contraste: true)
        return out
    }
}
