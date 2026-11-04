import OSLog
import SwiftUI

/// Cuenta los destacados violeta de una pantalla (criterio §11.3: como mucho uno).
public struct ContadorDestacados: PreferenceKey {
    public static let defaultValue = 0
    public static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

/// **El** destacado violeta de una pantalla (§1.4): lo primero que hay que mirar. Uno como mucho; las
/// bases y las vistas previas no llevan. El texto va en blanco y la acción, en un botón blanco con texto
/// violeta. Nunca sobre `superficieElevada` en oscuro.
public struct Destacado<Contenido: View>: View {
    let rotulo: String
    let accion: String?
    let alPulsar: (() -> Void)?
    let contenido: Contenido

    public init(rotulo: String, accion: String? = nil, alPulsar: (() -> Void)? = nil,
                @ViewBuilder contenido: () -> Contenido) {
        self.rotulo = rotulo; self.accion = accion; self.alPulsar = alPulsar; self.contenido = contenido()
    }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.destacado, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text(rotulo)
                .tlsTexto(TLSTipo.rotulo)
                .foregroundStyle(TLSPaleta.sobreColor.color)
                .accessibilityAddTraits(.isHeader)
            contenido
                .foregroundStyle(TLSPaleta.sobreColor.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if let accion, let alPulsar {
                Button(accion, action: alPulsar).tlsBoton(.sobreDestacado)
            }
        }
        .padding(TLSEspacio.e20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.violeta.color))
        .overlay(forma.strokeBorder(TLSPaleta.violetaBorde.color, lineWidth: 1))
        .tlsSobreColor()
        .accessibilityElement(children: .contain)
        .preference(key: ContadorDestacados.self, value: 1)
    }
}

/// Cifra protagonista dentro del destacado (Space Grotesk tabular) con su línea de contexto.
public struct CifraDestacada: View {
    let cifra: String
    let contexto: String?
    let estilo: TLSEstiloTexto

    public init(_ cifra: String, contexto: String? = nil, estilo: TLSEstiloTexto = TLSTipo.cifraGrande) {
        self.cifra = cifra; self.contexto = contexto; self.estilo = estilo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cifra).tlsTexto(estilo).lineLimit(1).minimumScaleFactor(0.6)
            if let contexto {
                Text(contexto).tlsTexto(TLSTipo.interfaz).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Destacado vacío o en edición (`violetaSuave`): explica qué irá aquí cuando haya dato.
public struct DestacadoVacio: View {
    let rotulo: String
    let texto: String

    public init(rotulo: String, texto: String) { self.rotulo = rotulo; self.texto = texto }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.destacado, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text(rotulo).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.violetaTexto.color)
            Text(texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.violetaSuave.color))
        .accessibilityElement(children: .combine)
    }
}

/// Comprueba en depuración que una pantalla tiene como mucho un destacado (§11.3).
struct PantallaModifier: ViewModifier {
    let nombre: String
    private static let log = Logger(subsystem: "es.thelast.system", category: "Diseño")

    func body(content: Content) -> some View {
        content.onPreferenceChange(ContadorDestacados.self) { n in
            #if DEBUG
            if n > 1 {
                Self.log.fault("La pantalla «\(nombre, privacy: .public)» tiene \(n) destacados violeta; como mucho, uno.")
            }
            #endif
        }
    }
}

public extension View {
    /// Raíz de una pantalla: en depuración avisa si hay más de un destacado violeta.
    func tlsPantalla(_ nombre: String) -> some View {
        modifier(PantallaModifier(nombre: nombre))
    }
}
