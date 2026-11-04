import AppKit
import SwiftUI

/// Tokens visuales de The Last System: **Mosaico v2**, paleta «Azul noche» (`DISENO-MOSAICO-V2.md` §1).
///
/// - Azul noche para actuar y encabezar; violeta para el destacado (uno por pantalla); magenta solo para
///   el foco y los avisos que piden tu acción. Ver `TLSPaleta`.
/// - Las áreas son iconos de app con tinta y relleno por modo (`TLSArea`); el color nunca va solo.
/// - Letra: Space Grotesk, DM Sans y JetBrains Mono, incluidas en el paquete (`TLSTipo`, `TLSFuentes`).
/// - Todo sólido: sin materiales ni cristal.
///
/// Los nombres de F0 (`marca`, `fondo`, `superficie`, `Tipo`…) se mantienen para que el código anterior
/// compile, pero apuntan ya a los valores de Mosaico v2. El código nuevo usa `TLSPaleta`, `TLSTipo`,
/// `TLSEspacio`, `TLSRadio` y los componentes.
public enum TLSTokens {
    // MARK: Compatibilidad con F0

    public static let marcaHex = "#E6007E"

    /// Magenta de marca. En Mosaico v2 solo es foco y aviso (`TLSPaleta.chispa`).
    public static var marca: Color { TLSPaleta.chispa.color }

    public static var marcaNS: NSColor { TLSPaleta.chispa.ns }

    /// Fondo de una fila elegida con el teclado (antes magenta suave; ahora `principalSuave`).
    public static var marcaSuave: Color { TLSPaleta.principalSuave.color }

    public static var fondoNS: NSColor { TLSPaleta.fondo.ns }

    public static var fondo: Color { TLSPaleta.fondo.color }

    /// Fondo de hojas y del selector de empresa.
    public static var fondoAgrupado: Color { TLSPaleta.fondo.color }

    /// Antes, gris translúcido para banner, insignias y código: ahora `bandeja`.
    public static var superficie: Color { TLSPaleta.bandeja.color }

    public static var superficieNS: NSColor { TLSPaleta.bandeja.ns }

    public static var separador: Color { TLSPaleta.separador.color }

    /// Color de los enlaces dentro de una nota (siempre con subrayado).
    public static var enlaceNS: NSColor { TLSPaleta.enlace.ns }

    /// Color a partir de un hexadecimal cualquiera, aclarado en oscuro. Las áreas usan `TLSArea`.
    public static func area(hex: String) -> Color {
        Color(nsColor: areaNS(hex: hex))
    }

    public static func areaNS(hex: String) -> NSColor {
        guard let base = RGBA(hex: hex) else { return .secondaryLabelColor }
        return dynamic(name: "tls.area.\(hex)", light: base, dark: base.aclarado(0.28))
    }

    // MARK: Medidas (F0; las nuevas están en TLSEspacio, TLSRadio y TLSAltura)

    public enum Espacio {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Radio {
        public static let fila: CGFloat = TLSRadio.fila
        public static let insignia: CGFloat = 999
        public static let boton: CGFloat = 999
    }

    /// Altura mínima de un objetivo táctil (§1.10).
    public static let alturaFila: CGFloat = TLSAltura.objetivoMinimo

    /// Ancho de la barra de área.
    public static let barraArea: CGFloat = 3

    // MARK: Tipografía (F0 → Mosaico v2)

    public enum Tipo {
        public static var tituloGrande: Font { TLSTipo.tituloPantalla.font() }
        public static var titulo: Font { TLSTipo.tituloSeccion.font() }
        public static var seccion: Font { TLSTipo.rotulo.font() }
        public static var cuerpo: Font { TLSTipo.interfaz.font() }
        public static var detalle: Font { TLSTipo.interfaz.font() }
        public static var pie: Font { TLSTipo.secundario.font() }
        public static var insignia: Font { TLSTipo.rotulo.font() }
        public static var mono: Font { TLSTipo.textoPlano.font() }
        public static var cifra: Font { TLSTipo.cifraFila.font() }
    }

    // MARK: Colores dinámicos

    /// Componentes RGBA en sRGB. `Sendable`, para poder capturarlos en el proveedor dinámico.
    public struct RGBA: Sendable, Hashable {
        public var r: Double, g: Double, b: Double, a: Double
        public init(r: Double, g: Double, b: Double, a: Double = 1) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }

        /// `#RRGGBB` o `#RRGGBBAA`, con o sin almohadilla.
        public init?(hex: String) {
            var s = hex.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
            if s.count == 6 {
                self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255,
                          b: Double(v & 0xFF) / 255)
            } else {
                self.init(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255,
                          b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
            }
        }

        /// Mezcla con blanco (`cantidad` entre 0 y 1).
        public func aclarado(_ cantidad: Double) -> RGBA {
            RGBA(r: r + (1 - r) * cantidad, g: g + (1 - g) * cantidad, b: b + (1 - b) * cantidad, a: a)
        }

        public var hex: String {
            String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()),
                   Int((b * 255).rounded()))
        }

        var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    }

    /// Color que cambia con la apariencia (claro / oscuro).
    public static func dynamic(name: String, light: RGBA, dark: RGBA) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            (TLSApariencia.modo(de: appearance).oscuro ? dark : light).nsColor
        }
    }
}

public extension NSColor {
    /// Color desde `#RRGGBB`.
    convenience init?(tlsHex hex: String) {
        guard let c = TLSTokens.RGBA(hex: hex) else { return nil }
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
