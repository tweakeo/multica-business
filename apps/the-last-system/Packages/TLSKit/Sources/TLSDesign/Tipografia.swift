import AppKit
import CoreText
import OSLog
import SwiftUI

/// Familias de letra de Mosaico v2 (§1.9). Las tres son de Google Fonts con licencia OFL y van dentro del
/// paquete (`Recursos/Fuentes`, con su `OFL.txt`): la app no necesita internet para pintarlas.
public enum TLSFamilia: String, CaseIterable, Sendable, Hashable {
    /// Títulos y cifras grandes (tiene cifras tabulares, `tnum`).
    case spaceGrotesk
    /// Toda la interfaz y el texto.
    case dmSans
    /// Solo códigos y «Ver como texto».
    case jetBrainsMono
    /// Letra del sistema. Solo para `cifraFila`: la DM Sans de Google Fonts no trae cifras tabulares.
    case sistema

    /// Nombre de familia que registra CoreText.
    public var nombreFamilia: String {
        switch self {
        case .spaceGrotesk: "Space Grotesk"
        case .dmSans: "DM Sans"
        case .jetBrainsMono: "JetBrains Mono"
        case .sistema: "System"
        }
    }

    /// Fichero variable (`wght`, y `opsz` en DM Sans) dentro de `Recursos/Fuentes`.
    var fichero: String? {
        switch self {
        case .spaceGrotesk: "SpaceGrotesk/SpaceGrotesk[wght].ttf"
        case .dmSans: "DMSans/DMSans[opsz,wght].ttf"
        case .jetBrainsMono: "JetBrainsMono/JetBrainsMono[wght].ttf"
        case .sistema: nil
        }
    }
}

/// Registro de las letras incluidas. Se hace una vez por proceso (la app al arrancar, las pruebas al
/// pedir la primera letra), con alcance de proceso: no se instala nada en el Mac.
public enum TLSFuentes {
    private static let log = Logger(subsystem: "es.thelast.system", category: "Fuentes")

    /// Los descriptores de CoreText son inmutables: se pueden compartir entre hilos.
    private struct Registro: @unchecked Sendable {
        let descriptores: [TLSFamilia: CTFontDescriptor]
    }

    private static var descriptores: [TLSFamilia: CTFontDescriptor] { registro.descriptores }

    /// Descriptor base de cada familia (la instancia por defecto del fichero variable).
    private static let registro: Registro = {
        var out: [TLSFamilia: CTFontDescriptor] = [:]
        guard let base = Bundle.module.url(forResource: "Fuentes", withExtension: nil) else {
            log.error("No encuentro las letras en el paquete")
            return Registro(descriptores: out)
        }
        var urls: [URL] = []
        for familia in TLSFamilia.allCases {
            guard let rel = familia.fichero else { continue }
            let url = base.appendingPathComponent(rel)
            urls.append(url)
            if let lista = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let primero = lista.first {
                out[familia] = primero
            }
        }
        // Itálica de DM Sans: para las notas (no tiene estilo propio en §1.9).
        urls.append(base.appendingPathComponent("DMSans/DMSans-Italic[opsz,wght].ttf"))
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Registrar dos veces da error y no es grave (otra copia del paquete ya lo hizo).
                let e = error?.takeRetainedValue()
                let codigo = e.map { CFErrorGetCode($0) } ?? 0
                if codigo != CTFontManagerError.alreadyRegistered.rawValue {
                    log.error("No he podido registrar una letra: \(codigo)")
                }
            }
        }
        return Registro(descriptores: out)
    }()

    /// Carpeta de las letras dentro del paquete (con los `OFL.txt`).
    public static var carpeta: URL? { Bundle.module.url(forResource: "Fuentes", withExtension: nil) }

    /// Registra las letras (idempotente). La app lo llama al arrancar; si no, se hace al pedir la primera.
    public static func registrar() {
        _ = registro
    }

    /// `true` si la familia está disponible (si no, se usa la del sistema con el mismo peso).
    public static func disponible(_ familia: TLSFamilia) -> Bool {
        familia == .sistema || descriptores[familia] != nil
    }

    /// Ejes de variación (`wght`, `opsz`) como identificadores de cuatro letras.
    static let ejePeso = 0x7767_6874 // 'wght'
    static let ejeTamanoOptico = 0x6F70_737A // 'opsz'

    /// Letra de AppKit/CoreText para una familia, peso (100–900) y tamaño.
    public static func ctFont(_ familia: TLSFamilia, peso: Double, tamano: CGFloat, tabulares: Bool = false,
                              italica: Bool = false) -> CTFont {
        guard familia != .sistema, var d = descriptores[familia] else {
            let sistema = NSFont.systemFont(ofSize: tamano, weight: pesoDelSistema(peso))
            if tabulares { return NSFont.monospacedDigitSystemFont(ofSize: tamano, weight: pesoDelSistema(peso)) as CTFont }
            return sistema as CTFont
        }
        if italica, familia == .dmSans {
            let attrs = [kCTFontFamilyNameAttribute: familia.nombreFamilia,
                         kCTFontTraitsAttribute: [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitItalic.rawValue]] as CFDictionary
            d = CTFontDescriptorCreateWithAttributes(attrs)
        }
        d = CTFontDescriptorCreateCopyWithVariation(d, NSNumber(value: ejePeso), CGFloat(peso))
        if familia == .dmSans {
            // Tamaño óptico automático, como `font-optical-sizing: auto` en las maquetas (eje de 9 a 40).
            d = CTFontDescriptorCreateCopyWithVariation(d, NSNumber(value: ejeTamanoOptico), min(max(tamano, 9), 40))
        }
        if tabulares {
            d = CTFontDescriptorCreateCopyWithFeature(d, NSNumber(value: kNumberSpacingType), NSNumber(value: kMonospacedNumbersSelector))
        }
        return CTFontCreateWithFontDescriptor(d, tamano, nil)
    }

    static func pesoDelSistema(_ peso: Double) -> NSFont.Weight {
        switch peso {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }

    /// `true` si la letra trae cifras tabulares (`tnum`): el selector de números monoespaciados.
    public static func tieneCifrasTabulares(_ familia: TLSFamilia) -> Bool {
        let f = ctFont(familia, peso: 500, tamano: 20)
        guard let tipos = CTFontCopyFeatures(f) as? [[String: Any]] else { return false }
        for tipo in tipos where (tipo[kCTFontFeatureTypeIdentifierKey as String] as? Int) == kNumberSpacingType {
            let selectores = tipo[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? []
            if selectores.contains(where: { ($0[kCTFontFeatureSelectorIdentifierKey as String] as? Int) == kMonospacedNumbersSelector }) {
                return true
            }
        }
        return false
    }
}

/// Un estilo de texto de §1.9: familia, peso, tamaño, interlínea y detalles.
public struct TLSEstiloTexto: Sendable, Hashable {
    public var familia: TLSFamilia
    /// Peso de 100 a 900 (eje `wght`).
    public var peso: Double
    public var tamano: CGFloat
    /// Altura de línea en puntos (la interlínea de §1.9).
    public var interlinea: CGFloat
    public var tabulares: Bool
    public var mayusculas: Bool
    /// Espaciado entre letras en em (+0,04 en `rotulo`).
    public var espaciado: CGFloat
    public var italica: Bool

    public init(_ familia: TLSFamilia, peso: Double, tamano: CGFloat, interlinea: CGFloat, tabulares: Bool = false,
                mayusculas: Bool = false, espaciado: CGFloat = 0, italica: Bool = false) {
        self.familia = familia; self.peso = peso; self.tamano = tamano; self.interlinea = interlinea
        self.tabulares = tabulares; self.mayusculas = mayusculas; self.espaciado = espaciado; self.italica = italica
    }

    /// El mismo estilo con otro peso (`interfaz` 400 → 500 en la barra lateral).
    public func peso(_ p: Double) -> TLSEstiloTexto { var c = self; c.peso = p; return c }
    public func tamano(_ t: CGFloat, interlinea l: CGFloat? = nil) -> TLSEstiloTexto {
        var c = self; c.tamano = t; c.interlinea = l ?? (t * interlinea / tamano); return c
    }
    public var conTabulares: TLSEstiloTexto { var c = self; c.tabulares = true; return c }
    public var enItalica: TLSEstiloTexto { var c = self; c.italica = true; return c }

    public func ctFont(escala: CGFloat = 1) -> CTFont {
        TLSFuentes.ctFont(familia, peso: peso, tamano: tamano * escala, tabulares: tabulares, italica: italica)
    }

    public func nsFont(escala: CGFloat = 1) -> NSFont { ctFont(escala: escala) as NSFont }

    public func font(escala: CGFloat = 1) -> Font { Font(ctFont(escala: escala)) }

    /// Espacio extra entre líneas para llegar a la interlínea del estilo.
    public func espacioEntreLineas(escala: CGFloat = 1) -> CGFloat {
        let f = nsFont(escala: escala)
        let natural = f.ascender - f.descender + f.leading
        return max(0, interlinea * escala - natural)
    }
}

/// Los estilos de texto de Mosaico v2 (§1.9). Por debajo de 15 pt, las cifras van en DM Sans o en la del
/// sistema (`cifraFila`); Space Grotesk se reserva para tamaños grandes.
public enum TLSTipo {
    /// Número clave en el destacado de un área.
    public static let cifraHoy = TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 56, interlinea: 60, tabulares: true)
    /// Destacado de ficha, módulo Grande.
    public static let cifraGrande = TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 40, interlinea: 44, tabulares: true)
    /// Módulo Pequeño, totales, dato protagonista en la vista previa.
    public static let cifraMedia = TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 28, interlinea: 32, tabulares: true)
    /// Título de área, base y ficha (en la cabecera).
    public static let tituloPantalla = TLSEstiloTexto(.spaceGrotesk, peso: 700, tamano: 28, interlinea: 34)
    /// Bloques de Resumen y secciones `##` de Notas.
    public static let tituloSeccion = TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 20, interlinea: 26)
    /// Título de mosaico, columna de tablero, vista previa.
    public static let tituloModulo = TLSEstiloTexto(.spaceGrotesk, peso: 500, tamano: 15, interlinea: 20)
    /// Notas, descripciones, actas.
    public static let lectura = TLSEstiloTexto(.dmSans, peso: 400, tamano: 15, interlinea: 23)
    /// Filas, celdas, menús, migas.
    public static let interfaz = TLSEstiloTexto(.dmSans, peso: 400, tamano: 13, interlinea: 18)
    /// Barra lateral y migas (500).
    public static let interfazMedia = TLSEstiloTexto(.dmSans, peso: 500, tamano: 13, interlinea: 18)
    /// Botones, pestañas, título de fila.
    public static let interfazFuerte = TLSEstiloTexto(.dmSans, peso: 600, tamano: 13, interlinea: 18)
    /// Líneas de contexto, «Sale de…», contadores.
    public static let secundario = TLSEstiloTexto(.dmSans, peso: 400, tamano: 12, interlinea: 16)
    /// Secciones de la barra lateral, cabeceras de columna: mayúsculas y +4 % de espaciado.
    public static let rotulo = TLSEstiloTexto(.dmSans, peso: 600, tamano: 11, interlinea: 14, mayusculas: true, espaciado: 0.04)
    /// Importes y fechas en tablas, alineados a la derecha. DM Sans no trae `tnum`: cifras del sistema.
    public static let cifraFila = TLSEstiloTexto(.sistema, peso: 500, tamano: 13, interlinea: 18, tabulares: true)
    /// T-0041, F-2026-0014, FI1, FIN-AR.
    public static let codigo = TLSEstiloTexto(.jetBrainsMono, peso: 500, tamano: 12, interlinea: 16)
    /// «Ver como texto» (⌘E).
    public static let textoPlano = TLSEstiloTexto(.jetBrainsMono, peso: 400, tamano: 13, interlinea: 20)

    public static let todos: [(String, TLSEstiloTexto)] = [
        ("cifraHoy", cifraHoy), ("cifraGrande", cifraGrande), ("cifraMedia", cifraMedia),
        ("tituloPantalla", tituloPantalla), ("tituloSeccion", tituloSeccion), ("tituloModulo", tituloModulo),
        ("lectura", lectura), ("interfaz", interfaz), ("interfazMedia", interfazMedia),
        ("interfazFuerte", interfazFuerte), ("secundario", secundario), ("rotulo", rotulo),
        ("cifraFila", cifraFila), ("codigo", codigo), ("textoPlano", textoPlano),
    ]
}

extension EnvironmentValues {
    /// Tamaño del texto de la app, del 85 al 200 % (Ajustes › Visualización). El Mac no tiene tamaño
    /// dinámico: cada estilo multiplica su tamaño por este factor.
    @Entry public var tlsEscalaTexto: CGFloat = 1
}

/// Aplica un estilo de §1.9 con la escala de texto del entorno.
struct EstiloTextoModifier: ViewModifier {
    let estilo: TLSEstiloTexto
    @Environment(\.tlsEscalaTexto) private var escala

    func body(content: Content) -> some View {
        let e = min(max(escala, 0.85), 2)
        content
            .font(estilo.font(escala: e))
            .lineSpacing(estilo.espacioEntreLineas(escala: e))
            .tracking(estilo.espaciado * estilo.tamano * e)
            .textCase(estilo.mayusculas ? .uppercase : nil)
    }
}

public extension View {
    /// Letra, interlínea, espaciado y mayúsculas de un estilo de Mosaico v2.
    func tlsTexto(_ estilo: TLSEstiloTexto) -> some View {
        modifier(EstiloTextoModifier(estilo: estilo))
    }
}
