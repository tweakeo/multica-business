import SwiftUI

// Componentes de F0, con la estética de Mosaico v2. Los nuevos están en `Componentes/`.

/// Punto de color de área con su texto («2 · Ventas»). El punto es decorativo para VoiceOver.
public struct AreaDot: View {
    let color: Color
    let text: String
    var size: CGFloat

    public init(color: Color, text: String, size: CGFloat = 8) {
        self.color = color; self.text = text; self.size = size
    }

    public init(hex: String, text: String, size: CGFloat = 8) {
        self.init(color: TLSTokens.area(hex: hex), text: text, size: size)
    }

    public var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Barra vertical de 3 pt con el color de un área (cabeceras).
public struct AreaBar: View {
    let color: Color
    public init(color: Color) { self.color = color }
    public var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: TLSTokens.barraArea)
            .accessibilityHidden(true)
    }
}

/// Estado con icono y texto. El color, si lo hay, solo refuerza.
public struct StatusLabel: View {
    let text: String
    let systemImage: String
    var tint: Color?

    public init(_ text: String, systemImage: String, tint: Color? = nil) {
        self.text = text; self.systemImage = systemImage; self.tint = tint
    }

    public var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? Color.secondary)
                .imageScale(.small)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Tipos de insignia de una carpeta abierta.
public enum BadgeKind: Sendable, Hashable, CaseIterable {
    case copia, ejemplo, soloLectura
    /// F6: tu carpeta real tras «Pasar a mi carpeta real» (la app ya escribe en ella).
    case real

    public var text: String {
        switch self {
        case .copia: "COPIA"
        case .ejemplo: "EJEMPLO"
        case .soloLectura: "SOLO LECTURA"
        case .real: "TU CARPETA"
        }
    }

    public var systemImage: String {
        switch self {
        case .copia: "doc.on.doc"
        case .ejemplo: "graduationcap"
        case .soloLectura: "lock"
        case .real: "folder"
        }
    }

    /// Lo que lee VoiceOver.
    public var accessibilityText: String {
        switch self {
        case .copia: "Copia"
        case .ejemplo: "Ejemplo"
        case .soloLectura: "Solo lectura"
        case .real: "Tu carpeta real"
        }
    }
}

/// Insignia pequeña en mayúsculas: «COPIA», «EJEMPLO», «SOLO LECTURA».
public struct Badge: View {
    let kind: BadgeKind
    public init(_ kind: BadgeKind) { self.kind = kind }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(kind.text)
                .tlsTexto(TLSTipo.rotulo)
                .tracking(0.66)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .foregroundStyle(TLSPaleta.textoSecundario.color)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.accessibilityText)
    }
}

/// Banner permanente de una línea (p. ej. «Copia del 21/10: …»).
public struct InfoBanner: View {
    let text: String
    let systemImage: String

    public init(_ text: String, systemImage: String) {
        self.text = text; self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: TLSTokens.Espacio.s) {
            Image(systemName: systemImage)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            Text(text)
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TLSTokens.Espacio.l)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TLSPaleta.bandeja.color)
        .overlay(alignment: .bottom) { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Fila estándar: icono, título y subtítulo opcional.
public struct RowLabel: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var iconTint: Color?

    public init(_ title: String, subtitle: String? = nil, systemImage: String, iconTint: Color? = nil) {
        self.title = title; self.subtitle = subtitle; self.systemImage = systemImage; self.iconTint = iconTint
    }

    public var body: some View {
        HStack(spacing: TLSTokens.Espacio.s) {
            Image(systemName: systemImage)
                .foregroundStyle(iconTint ?? Color.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(minHeight: TLSTokens.alturaFila - 4, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Título de sección en versalitas discretas.
public struct SectionTitle: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .tlsTexto(TLSTipo.rotulo)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(text)
    }
}

public extension View {
    /// Botón principal (F0): ahora azul noche, como `tlsBoton(.principal)`.
    func tlsPrimaryButton() -> some View {
        tlsBoton(.principal)
    }

    /// Foco de teclado propio en filas a medida (F0): fondo `principalSuave` y anillo magenta.
    func tlsFocusRing(_ focused: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                .fill(focused ? TLSPaleta.principalSuave.color : Color.clear)
        )
        .tlsAnilloFoco(focused, radio: TLSRadio.fila)
    }
}
