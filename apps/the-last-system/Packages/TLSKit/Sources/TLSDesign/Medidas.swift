import SwiftUI

/// Espacios de Mosaico v2: base de 4 pt (§1.10).
public enum TLSEspacio {
    public static let e4: CGFloat = 4
    public static let e8: CGFloat = 8
    public static let e12: CGFloat = 12
    public static let e16: CGFloat = 16
    public static let e20: CGFloat = 20
    public static let e24: CGFloat = 24
    public static let e32: CGFloat = 32
    public static let e48: CGFloat = 48

    /// Margen de pantalla (24 pt; 16 por debajo de 900 pt de ancho).
    public static func margenPantalla(ancho: CGFloat) -> CGFloat { ancho < TLSAncho.estrecho ? 16 : 24 }
    /// Entre mosaicos.
    public static let entreMosaicos: CGFloat = 12
    /// Relleno de un mosaico pequeño y de uno grande.
    public static let mosaicoPequeno: CGFloat = 16
    public static let mosaicoGrande: CGFloat = 20
}

/// Radios (§1.10). Botones, chips, pestañas e insignias van en cápsula.
public enum TLSRadio {
    public static let mosaico: CGFloat = 22
    public static let cabecera: CGFloat = 22
    public static let destacado: CGFloat = 22
    public static let bloque: CGFloat = 14
    public static let tarjeta: CGFloat = 14
    public static let previa: CGFloat = 16
    public static let ventanaFlotante: CGFloat = 16
    public static let hoja: CGFloat = 20
    public static let fila: CGFloat = 10
    public static let campo: CGFloat = 10
    public static let iconoArea24: CGFloat = 7
    public static let iconoArea32: CGFloat = 9
    public static let monograma: CGFloat = 8
    public static let tecla: CGFloat = 7
}

/// Alturas (§1.10) y objetivos mínimos (§11, regla de accesibilidad).
public enum TLSAltura {
    public static let filaBarraLateral: CGFloat = 36
    public static let filaLista: CGFloat = 44
    public static let filaTabla: CGFloat = 32
    public static let filaTablaCompacta: CGFloat = 28
    public static let cabeceraTabla: CGFloat = 28
    /// Nada que se pulse mide menos de 28 × 28 pt (tampoco el «−», las asas o la «×» de un chip).
    public static let objetivoMinimo: CGFloat = 28
    /// Botones principales.
    public static let botonPrincipal: CGFloat = 44
    public static let cabeceraFichaMinima: CGFloat = 132
    public static let cabeceraFichaMaxima: CGFloat = 168
    public static let cabeceraBase: CGFloat = 96
    public static let franjaMigas: CGFloat = 32
}

/// Anchos de referencia (§1.10, §2.3, §2.5, §4.9, §5.2, §6).
public enum TLSAncho {
    public static let barraLateral: CGFloat = 248
    public static let barraLateralMinima: CGFloat = 232
    public static let barraLateralMaxima: CGFloat = 320
    public static let vistaPrevia: CGFloat = 360
    public static let vistaPreviaAltoMaximo: CGFloat = 320
    public static let paleta: CGFloat = 640
    public static let selectorRelacion: CGFloat = 360
    /// Por debajo, las migas bajan a una franja bajo la barra de la ventana.
    public static let migasEnBarra: CGFloat = 960
    /// Por debajo, márgenes de 16 pt y el destacado de la ficha pasa bajo la cabecera.
    public static let estrecho: CGFloat = 900
    /// Ancho máximo del contenido de una pantalla (como las maquetas).
    public static let contenidoMaximo: CGFloat = 1240
}

/// Sombras de nivel 1 (mosaicos) y 2 (vista previa, menús, tarjeta levantada) (§1.10). En oscuro, el
/// nivel 1 no lleva sombra sino borde blanco al 8 %, y el nivel 2 lleva borde al 12 % y sombra negra.
public enum TLSNivel: Sendable {
    case uno, dos
}

struct SombraModifier<S: InsettableShape>: ViewModifier {
    let nivel: TLSNivel
    let forma: S
    @Environment(\.colorScheme) private var esquema
    @Environment(\.colorSchemeContrast) private var contraste

    func body(content: Content) -> some View {
        let oscuro = esquema == .dark
        let tinta = Color(red: 15 / 255, green: 20 / 255, blue: 48 / 255)
        let borde = nivel == .uno ? TLSPaleta.borde1 : TLSPaleta.borde2
        let conBorde = oscuro || contraste == .increased
        content
            .overlay {
                if conBorde { forma.strokeBorder(borde.color, lineWidth: 1).allowsHitTesting(false) }
            }
            .shadow(color: oscuro ? .clear : tinta.opacity(nivel == .uno ? 0.04 : 0.08),
                    radius: nivel == .uno ? 1 : 3, y: nivel == .uno ? 1 : 2)
            .shadow(color: oscuro ? (nivel == .dos ? .black.opacity(0.5) : .clear) : tinta.opacity(nivel == .uno ? 0.06 : 0.14),
                    radius: nivel == .uno ? 8 : 16, y: nivel == .uno ? 6 : 12)
    }
}

public extension View {
    /// Sombra (y borde en oscuro) de un nivel de Mosaico v2. El radio de SwiftUI es la mitad del
    /// desenfoque de CSS.
    func tlsSombra<S: InsettableShape>(_ nivel: TLSNivel, forma: S) -> some View {
        modifier(SombraModifier(nivel: nivel, forma: forma))
    }

    func tlsSombra(_ nivel: TLSNivel, radio: CGFloat) -> some View {
        modifier(SombraModifier(nivel: nivel, forma: RoundedRectangle(cornerRadius: radio, style: .continuous)))
    }
}

/// Movimiento (§1.12). Con «Reducir movimiento», solo fundidos cortos.
public enum TLSMovimiento {
    /// Entrar un nivel: fundido y 12 pt desde la derecha (0,2 s). Reducido: fundido de 0,15 s.
    public static func entrarNivel(reducir: Bool) -> Animation {
        reducir ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2)
    }

    public static func transicionNivel(reducir: Bool, haciaAtras: Bool = false) -> AnyTransition {
        if reducir { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: haciaAtras ? -12 : 12)),
                           removal: .opacity)
    }

    /// Cambiar de pestaña en una ficha: fundido de 0,12 s, sin desplazamiento.
    public static let pestana: Animation = .easeInOut(duration: 0.12)
    /// Muelles de mosaicos, tarjetas y barra lateral.
    public static let muelle: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    /// Vista previa: espera al pasar el puntero, margen al salir y aparición (escala 0,96 → 1 y fundido).
    public static let esperaVistaPrevia: Duration = .milliseconds(600)
    public static let margenSalidaVistaPrevia: Duration = .milliseconds(200)
    public static let aparecerVistaPrevia: Animation = .easeOut(duration: 0.15)
    /// Lo que dura a la vista un aviso con «Deshacer».
    public static let duracionAviso: Duration = .seconds(6)
    /// Mantener pulsado para entrar en el modo edición de la barra lateral.
    public static let pulsacionLarga: Double = 0.4
    /// Temblor del modo edición (±1,5°).
    public static let temblorGrados: Double = 1.5

    /// Animación o nada, según «Reducir movimiento».
    public static func si(_ animacion: Animation, reducir: Bool) -> Animation? {
        reducir ? nil : animacion
    }
}
