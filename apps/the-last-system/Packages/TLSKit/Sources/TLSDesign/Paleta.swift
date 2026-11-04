import AppKit
import os
import SwiftUI

/// Un color de Mosaico v2 con sus cuatro variantes: claro y oscuro, normal y con «Aumentar contraste».
///
/// Se resuelve con la apariencia de la vista (`NSAppearance`) y el ajuste «Aumentar contraste» del Mac
/// (`TLSApariencia.modo`), así que sirve igual en SwiftUI (`color`) que en AppKit (`ns`). Los valores salen de `DISENO-MOSAICO-V2.md` §1 y los comprueba
/// `DesignTests` con la fórmula de WCAG.
public struct TLSColor: Sendable, Hashable, Identifiable {
    public typealias RGBA = TLSTokens.RGBA

    public let id: String
    public let claro: RGBA
    public let oscuro: RGBA
    public let claroContraste: RGBA
    public let oscuroContraste: RGBA

    public init(_ id: String, claro: RGBA, oscuro: RGBA, claroContraste: RGBA? = nil, oscuroContraste: RGBA? = nil) {
        self.id = id
        self.claro = claro
        self.oscuro = oscuro
        self.claroContraste = claroContraste ?? claro
        self.oscuroContraste = oscuroContraste ?? oscuro
    }

    /// Con valores `#RRGGBB` (o `#RRGGBBAA`). Las variantes de contraste, si no se dan, son las normales.
    public init(_ id: String, _ claro: String, _ oscuro: String, contraste claroC: String? = nil, _ oscuroC: String? = nil) {
        self.init(id, claro: .h(claro), oscuro: .h(oscuro), claroContraste: claroC.map(RGBA.h), oscuroContraste: oscuroC.map(RGBA.h))
    }

    /// El mismo valor en todos los modos.
    public static func fijo(_ id: String, _ hex: String) -> TLSColor {
        TLSColor(id, hex, hex)
    }

    /// Valor para un modo concreto (pruebas, capturas y cálculos de contraste).
    public func valor(oscuro esOscuro: Bool, contraste: Bool = false) -> RGBA {
        switch (esOscuro, contraste) {
        case (false, false): claro
        case (true, false): oscuro
        case (false, true): claroContraste
        case (true, true): oscuroContraste
        }
    }

    /// El mismo color con otra opacidad en todos los modos.
    public func opacidad(_ a: Double) -> TLSColor {
        func con(_ c: RGBA) -> RGBA { RGBA(r: c.r, g: c.g, b: c.b, a: a) }
        return TLSColor("\(id)@\(a)", claro: con(claro), oscuro: con(oscuro),
                        claroContraste: con(claroContraste), oscuroContraste: con(oscuroContraste))
    }

    /// Color de AppKit que cambia con la apariencia (también con «Aumentar contraste»).
    public var ns: NSColor {
        let valores = (claro, oscuro, claroContraste, oscuroContraste)
        return NSColor(name: NSColor.Name("tls.\(id)")) { appearance in
            let modo = TLSApariencia.modo(de: appearance)
            switch (modo.oscuro, modo.contraste) {
            case (false, false): return valores.0.nsColor
            case (true, false): return valores.1.nsColor
            case (false, true): return valores.2.nsColor
            case (true, true): return valores.3.nsColor
            }
        }
    }

    public var color: Color { Color(nsColor: ns) }
}

/// Modo de la apariencia: oscuro o no, y con «Aumentar contraste» o no.
public enum TLSApariencia {
    /// Claro u oscuro sale de la apariencia; «Aumentar contraste», de la apariencia **o** del ajuste del Mac.
    /// SwiftUI resuelve `Color(nsColor:)` con una apariencia hecha solo con `colorScheme` (comprobado: con
    /// `colorSchemeContrast = .increased` sigue pasando `aqua`/`darkAqua`), así que sin mirar el ajuste las
    /// variantes de contraste no llegaban nunca a las vistas de SwiftUI.
    public static func modo(de appearance: NSAppearance) -> (oscuro: Bool, contraste: Bool) {
        let m: (oscuro: Bool, contraste: Bool) = switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                                                 .accessibilityHighContrastDarkAqua]) {
        case .darkAqua?: (true, false)
        case .accessibilityHighContrastAqua?: (false, true)
        case .accessibilityHighContrastDarkAqua?: (true, true)
        default: (false, false)
        }
        if let forzado = contrasteForzado { return (m.oscuro, forzado) }
        return (m.oscuro, m.contraste || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    private static let forzado = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    /// Solo para pruebas y capturas: `true` pinta como con «Aumentar contraste», `false` como sin él y `nil`
    /// (lo normal) sigue a la apariencia y al ajuste del Mac.
    public static var contrasteForzado: Bool? {
        get { forzado.withLock { $0 } }
        set { forzado.withLock { $0 = newValue } }
    }

    /// Apariencia de AppKit para un modo (capturas fuera de pantalla y pruebas).
    public static func appearance(oscuro: Bool, contraste: Bool) -> NSAppearance? {
        switch (oscuro, contraste) {
        case (false, false): NSAppearance(named: .aqua)
        case (true, false): NSAppearance(named: .darkAqua)
        case (false, true): NSAppearance(named: .accessibilityHighContrastAqua)
        case (true, true): NSAppearance(named: .accessibilityHighContrastDarkAqua)
        }
    }
}

/// Paleta «Azul noche» de Mosaico v2 (§1.2–§1.6).
///
/// Quién hace qué (§1.1): **azul noche** (`principal`, `cabecera`) para actuar y encabezar; **violeta**
/// para el destacado, uno por pantalla como mucho; **magenta** (`chispa`, `anillo`) solo para el foco y
/// los avisos que piden tu acción. El magenta nunca rellena botones, selección ni nada mayor de 24 pt.
public enum TLSPaleta {
    // MARK: Neutros (§1.2)

    public static let fondo = TLSColor("fondo", "#F3F5FA", "#000000")
    /// Mosaicos y barra lateral.
    public static let superficie = TLSColor("superficie", "#FFFFFF", "#10142A")
    /// Vista previa, menús, hojas y tarjeta levantada (en claro, blanco con sombra 2).
    public static let superficieElevada = TLSColor("superficieElevada", "#FFFFFF", "#1A1F3E")
    /// Hundida: columnas del tablero, buscador, chips.
    public static let bandeja = TLSColor("bandeja", "#E8EBF5", "#0A0D1F")
    /// Relleno de las cabeceras (el mismo en los dos modos).
    public static let cabecera = TLSColor.fijo("cabecera", "#1E2A78")
    public static let subtituloCabecera = TLSColor.fijo("subtituloCabecera", "#C3C9EE")
    /// Texto e iconos sobre la cabecera y sobre el destacado.
    public static let sobreColor = TLSColor.fijo("sobreColor", "#FFFFFF")
    public static let texto = TLSColor("texto", "#0F1430", "#EEF0FA")
    public static let textoSecundario = TLSColor("textoSecundario", "#545A7A", "#9AA1C4", contraste: "#3F4563", "#BCC1DD")
    /// Línea fina. Nunca es la única pista. Con «Aumentar contraste» pasa a `bordeControl`.
    public static let separador = TLSColor("separador", "#DFE3EE", "#252B4D", contraste: "#7A819F", "#6A72A0")
    /// Campos, casillas y la bandeja «Ocultos».
    public static let bordeControl = TLSColor("bordeControl", "#7A819F", "#6A72A0")
    /// Detrás de una hoja.
    public static let velo = TLSColor("velo", "#0F14304D", "#00000099")

    // MARK: Azul noche (§1.3)

    public static let principal = TLSColor("principal", "#1E2A78", "#7C8CFF")
    public static let principalHover = TLSColor("principalHover", "#2B3A99", "#95A2FF")
    public static let principalPulsado = TLSColor("principalPulsado", "#151D58", "#6577F2")
    /// Texto e iconos sobre `principal` (y sobre la selección).
    public static let sobrePrincipal = TLSColor("sobrePrincipal", "#FFFFFF", "#0B1030")
    /// Selección secundaria, rango de la gráfica, fila de la ventana inactiva.
    public static let principalSuave = TLSColor("principalSuave", "#E8EAF2", "#232A50")
    /// Texto que lleva a otra ficha. **Siempre subrayado** (frente al texto no llega a 3).
    public static let enlace = TLSColor("enlace", "#3346C2", "#95A2FF")
    public static let desactivadoRelleno = TLSColor("desactivadoRelleno", "#E8EBF5", "#1A1F3E")
    public static let desactivadoTexto = TLSColor("desactivadoTexto", "#545A7A", "#9AA1C4", contraste: "#3F4563", "#BCC1DD")
    /// Texto de un botón desactivado sobre la cabecera o el destacado: blanco al 85 % (9,6:1 sobre azul noche,
    /// 4,55:1 sobre violeta). Con borde `desactivadoSobreColorBorde`. Lleva su motivo al lado (§1.3).
    public static let desactivadoSobreColor = TLSColor.fijo("desactivadoSobreColor", "#FFFFFFD9")
    public static let desactivadoSobreColorBorde = TLSColor.fijo("desactivadoSobreColorBorde", "#FFFFFF59")

    // MARK: Violeta: el destacado (§1.4)

    public static let violeta = TLSColor.fijo("violeta", "#7C3AED")
    public static let violetaHover = TLSColor("violetaHover", "#6D28D9", "#8B4CF7")
    public static let violetaPulsado = TLSColor("violetaPulsado", "#5B21B6", "#6D28D9")
    /// Solo el rótulo «Destacado» en la galería de módulos.
    public static let violetaTexto = TLSColor("violetaTexto", "#7C3AED", "#A78BFA")
    /// El destacado vacío o en edición.
    public static let violetaSuave = TLSColor("violetaSuave", "#F2EBFD", "#281C55")
    /// Borde del destacado con «Aumentar contraste» en oscuro.
    public static let violetaBorde = TLSColor("violetaBorde", "#00000000", "#00000000", contraste: "#00000000", "#FFFFFF3D")

    // MARK: Magenta: la chispa (§1.5)

    /// Insignia «te toca», punto de novedad y línea «ahora». Con «Aumentar contraste», `#C4006B`.
    public static let chispa = TLSColor("chispa", "#E6007E", "#E6007E", contraste: "#C4006B", "#C4006B")
    /// Anillo de foco del teclado (2 pt; 3 pt con «Aumentar contraste»).
    public static let anillo = TLSColor.fijo("anillo", "#E6007E")
    /// Texto magenta: solo «Nuevo» junto al punto, si hace falta palabra.
    public static let chispaTexto = TLSColor("chispaTexto", "#C4006B", "#FF3D9A")

    // MARK: Estados (§1.6)

    public static let bien = TLSColor("bien", "#00786E", "#59C1B5")
    public static let atencion = TLSColor("atencion", "#C33900", "#FF946C")
    public static let mal = TLSColor("mal", "#D01C36", "#FF928D")
    public static let sinDato = TLSColor("sinDato", "#6A6A70", "#B0B0B6")

    // MARK: Glifos y bordes

    /// Glifo dentro del icono de app de un área: blanco en claro, `#0F1430` en oscuro.
    public static let glifo = TLSColor("glifo", "#FFFFFF", "#0F1430")
    /// Borde de nivel 1 (mosaicos): ninguno en claro; blanco al 8 % en oscuro. Con contraste, más marcado.
    public static let borde1 = TLSColor("borde1", "#00000000", "#FFFFFF14", contraste: "#0F143033", "#FFFFFF3D")
    /// Borde de nivel 2 (vista previa, menús, tarjeta levantada): blanco al 12 % en oscuro.
    public static let borde2 = TLSColor("borde2", "#00000000", "#FFFFFF1F", contraste: "#0F143033", "#FFFFFF3D")
    /// Relleno translúcido sobre la cabecera (datos clave, avatar de tipo).
    public static let sobreCabeceraSuave = TLSColor.fijo("sobreCabeceraSuave", "#FFFFFF1A")
    /// F4 · corrector: un interruptor encendido sobre la cabecera azul noche (5,3:1; el violeta daba 2,2:1).
    public static let interruptorSobreCabecera = TLSColor.fijo("interruptorSobreCabecera", "#95A2FF")

    /// Todos los colores con nombre (para pruebas y la galería de diseño).
    public static let todos: [TLSColor] = [
        fondo, superficie, superficieElevada, bandeja, cabecera, subtituloCabecera, sobreColor, texto,
        textoSecundario, separador, bordeControl, velo, principal, principalHover, principalPulsado,
        sobrePrincipal, principalSuave, enlace, desactivadoRelleno, desactivadoTexto, violeta, violetaHover,
        violetaPulsado, violetaTexto, violetaSuave, violetaBorde, chispa, anillo, chispaTexto, bien, atencion,
        mal, sinDato, glifo, borde1, borde2, sobreCabeceraSuave, interruptorSobreCabecera,
    ] + TLSArea.allCases.flatMap { [$0.tinta, $0.relleno] }
}

/// Estado de algo (§1.6): siempre icono **y** palabra; el color solo refuerza.
public enum TLSEstado: String, CaseIterable, Sendable, Hashable, Codable {
    /// En ritmo, Hecho, Cobrada.
    case bien
    /// Vence pronto, quieta, falta un dato.
    case atencion
    /// En alerta, vencida, bloqueada.
    case mal
    /// Sin dato, sin meta.
    case sinDato

    public var simbolo: String {
        switch self {
        case .bien: "checkmark.circle.fill"
        case .atencion: "exclamationmark.triangle.fill"
        case .mal: "xmark.octagon.fill"
        case .sinDato: "minus.circle"
        }
    }

    public var color: TLSColor {
        switch self {
        case .bien: TLSPaleta.bien
        case .atencion: TLSPaleta.atencion
        case .mal: TLSPaleta.mal
        case .sinDato: TLSPaleta.sinDato
        }
    }

    /// Fondo de la pastilla: el color del estado al 10 % (claro) o al 18 % (oscuro).
    public var tinte: TLSColor {
        let c = color
        return TLSColor("\(rawValue).tinte",
                        claro: RGBA(c.claro, a: 0.10), oscuro: RGBA(c.oscuro, a: 0.18),
                        claroContraste: RGBA(c.claroContraste, a: 0.10), oscuroContraste: RGBA(c.oscuroContraste, a: 0.18))
    }

    /// Palabra por defecto. Cada pantalla puede decir la suya («Cobrada», «Vence hoy»).
    public var palabra: String {
        switch self {
        case .bien: "Bien"
        case .atencion: "Atención"
        case .mal: "Mal"
        case .sinDato: "Sin dato"
        }
    }

    public typealias RGBA = TLSTokens.RGBA
}

/// Las seis áreas reajustadas de Mosaico v2 (§1.7): ciruela, verde, petróleo, ámbar, oliva y granate.
///
/// No depende de `TLSCore` (`AreaCode` se traduce en `TLSUI`). Cada área es un **icono de app**: cuadrado
/// con el relleno y el glifo (`TLSPaleta.glifo`); la tinta es para texto e iconos sueltos.
public enum TLSArea: String, CaseIterable, Sendable, Hashable, Codable {
    case direccion, ventas, entrega, finanzas, marca, equipo

    public var numero: Int {
        switch self {
        case .direccion: 1
        case .ventas: 2
        case .entrega: 3
        case .finanzas: 4
        case .marca: 5
        case .equipo: 6
        }
    }

    public var nombre: String {
        switch self {
        case .direccion: "Dirección"
        case .ventas: "Ventas"
        case .entrega: "Entrega"
        case .finanzas: "Finanzas"
        case .marca: "Marca"
        case .equipo: "Equipo"
        }
    }

    /// Nombre del tono (para VoiceOver y la galería): ciruela, verde, petróleo, ámbar, oliva, granate.
    public var tono: String {
        switch self {
        case .direccion: "ciruela"
        case .ventas: "verde"
        case .entrega: "petróleo"
        case .finanzas: "ámbar"
        case .marca: "oliva"
        case .equipo: "granate"
        }
    }

    /// SF Symbol del icono de app (§1.11), en variante rellena cuando existe.
    public var simbolo: String {
        switch self {
        case .direccion: "safari.fill"
        case .ventas: "chart.line.uptrend.xyaxis"
        case .entrega: "shippingbox.fill"
        case .finanzas: "creditcard.fill"
        case .marca: "sparkles"
        case .equipo: "person.2.fill"
        }
    }

    /// Texto e iconos en el color del área.
    public var tinta: TLSColor {
        switch self {
        case .direccion: TLSColor("direccion.tinta", "#6B0C68", "#DE7ED6")
        case .equipo: TLSColor("equipo.tinta", "#841A2E", "#FC8992")
        case .entrega: TLSColor("entrega.tinta", "#0A546B", "#4CC3ED")
        case .marca: TLSColor("marca.tinta", "#575B0B", "#C1C75D")
        case .ventas: TLSColor("ventas.tinta", "#106F49", "#72E1A9")
        case .finanzas: TLSColor("finanzas.tinta", "#925E10", "#FDCF9B")
        }
    }

    /// Icono de app, punto, barra y serie. Con «Aumentar contraste» pasa a la tinta.
    public var relleno: TLSColor {
        let t = tinta
        switch self {
        case .direccion: return TLSColor("direccion.relleno", claro: .h("#791E74"), oscuro: .h("#BE61B7"), claroContraste: t.claro, oscuroContraste: t.oscuro)
        case .equipo: return TLSColor("equipo.relleno", claro: .h("#952C3C"), oscuro: .h("#E1717B"), claroContraste: t.claro, oscuroContraste: t.oscuro)
        case .entrega: return TLSColor("entrega.relleno", claro: .h("#0F6681"), oscuro: .h("#32AED7"), claroContraste: t.claro, oscuroContraste: t.oscuro)
        case .marca: return TLSColor("marca.relleno", claro: .h("#6D7010"), oscuro: .h("#B1B74C"), claroContraste: t.claro, oscuroContraste: t.oscuro)
        case .ventas: return TLSColor("ventas.relleno", claro: .h("#178A5C"), oscuro: .h("#65D49E"), claroContraste: t.claro, oscuroContraste: t.oscuro)
        case .finanzas: return TLSColor("finanzas.relleno", claro: .h("#B87817"), oscuro: .h("#FDC483"), claroContraste: t.claro, oscuroContraste: t.oscuro)
        }
    }

    /// Glifo sobre el cuadrado blanco cuando el icono va encima de la cabecera azul noche: la tinta clara
    /// en los dos modos (la oscura no se leería sobre blanco).
    public var glifoSobreBlanco: TLSColor {
        TLSColor.fijo("\(rawValue).sobreBlanco", tinta.claro.hex)
    }

    /// «2 · Ventas».
    public var etiquetaNumerada: String { "\(numero) · \(nombre)" }
}

public extension TLSTokens.RGBA {
    /// Desde un literal hexadecimal de la paleta. Un literal mal escrito da magenta puro, que las
    /// pruebas detectan (ningún token de la paleta lo es).
    static func h(_ hex: String) -> TLSTokens.RGBA {
        TLSTokens.RGBA(hex: hex) ?? TLSTokens.RGBA(r: 1, g: 0, b: 1)
    }

    /// El mismo color con otra opacidad.
    init(_ base: TLSTokens.RGBA, a: Double) {
        self.init(r: base.r, g: base.g, b: base.b, a: a)
    }
}
