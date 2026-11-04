import SwiftUI

/// Pastilla de estado (§1.6): fondo del color del estado al 10 % (18 % en oscuro), icono en el color del
/// estado y **la palabra en `texto`**. Dentro del destacado o de la cabecera va en blanco.
public struct PastillaEstado: View {
    let estado: TLSEstado
    let palabra: String
    let sobreColor: Bool

    public init(_ estado: TLSEstado, palabra: String? = nil, sobreColor: Bool = false) {
        self.estado = estado
        self.palabra = palabra ?? estado.palabra
        self.sobreColor = sobreColor
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: estado.simbolo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(estado.color.valorFijo(sobreColor))
                .accessibilityHidden(true)
            Text(palabra)
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(sobreColor ? Color(red: 15 / 255, green: 20 / 255, blue: 48 / 255) : TLSPaleta.texto.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(Capsule(style: .circular).fill(sobreColor ? TLSPaleta.sobreColor.color : estado.tinte.color))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(palabra)
    }
}

/// Etapa abierta de un embudo (Prospecto · Diagnóstico · Propuesta · Aceptada, M2-Bases): pastilla en `bandeja`
/// con cuatro puntos de avance en azul noche y la palabra. No es un estado bueno ni malo, así que no lleva
/// los colores de estado (§1.6 reserva Atención para lo que va mal pronto).
public struct PastillaEtapa: View {
    let palabra: String
    let paso: Int
    let total: Int

    /// `paso`: 0 para la primera etapa.
    public init(_ palabra: String, paso: Int, de total: Int = 4) {
        self.palabra = palabra; self.paso = paso; self.total = max(1, total)
    }

    public var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i <= paso ? TLSPaleta.principal.color : Color.clear)
                        .overlay(Circle().strokeBorder(i <= paso ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color, lineWidth: 1.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Text(palabra)
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(palabra), etapa \(min(paso, total - 1) + 1) de \(total)")
    }
}

private extension TLSColor {
    /// Sobre blanco (dentro del destacado) se usa el valor claro aunque la app esté en oscuro.
    func valorFijo(_ sobreBlanco: Bool) -> Color {
        sobreBlanco ? Color(nsColor: NSColor(srgbRed: claro.r, green: claro.g, blue: claro.b, alpha: 1)) : color
    }
}

/// Insignia magenta de aviso, «te toca» (§1.5): el número en blanco sobre la chispa y **siempre** una
/// palabra. La palabra puede verse al lado o ir solo para VoiceOver (en la barra lateral, «Decisiones 3»).
/// `enCapsula`: palabra y número juntos en blanco dentro de la cápsula magenta («Por revisar 1»), como en
/// las pestañas de M2-Proyecto y M2-Contacto: se lee igual sobre la pestaña elegida (azul noche) que sobre las otras.
public struct InsigniaAviso: View {
    let numero: Int?
    let palabra: String
    let palabraVisible: Bool
    let enCapsula: Bool

    public init(_ numero: Int?, palabra: String, palabraVisible: Bool = true, enCapsula: Bool = false) {
        self.numero = numero; self.palabra = palabra; self.palabraVisible = palabraVisible; self.enCapsula = enCapsula
    }

    public var body: some View {
        if enCapsula {
            Text(numero.map { "\(palabra) \($0)" } ?? palabra)
                .font(TLSEstiloTexto(.dmSans, peso: 600, tamano: 12, interlinea: 16).font())
                .monospacedDigit()
                .foregroundStyle(TLSPaleta.sobreColor.color)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 22)
                .background(Capsule(style: .circular).fill(TLSPaleta.chispa.color))
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(numero.map { "\($0) \(palabra)" } ?? palabra)
        } else {
            alLado
        }
    }

    private var alLado: some View {
        HStack(spacing: 6) {
            if let numero {
                Text("\(numero)")
                    .font(TLSEstiloTexto(.dmSans, peso: 600, tamano: 12, interlinea: 16).font())
                    .monospacedDigit()
                    .foregroundStyle(TLSPaleta.sobreColor.color)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Capsule(style: .circular).fill(TLSPaleta.chispa.color))
            } else {
                PuntoNovedad(palabra: palabra)
            }
            if palabraVisible {
                Text(palabra)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(numero.map { "\($0) \(palabra)" } ?? palabra)
    }
}

/// Punto de novedad de 8 pt: algo cambió desde tu última visita.
public struct PuntoNovedad: View {
    let palabra: String
    public init(palabra: String = "Nuevo") { self.palabra = palabra }
    public var body: some View {
        Circle()
            .fill(TLSPaleta.chispa.color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(palabra)
    }
}

/// Marca «ahora» (§1.5): línea de 2 pt en magenta con el punto de novedad al principio. En el calendario por semana y
/// en «Lo que cabe hoy» va en horizontal; en el cronograma y las fases de un plan, en vertical. Es una marca de
/// tiempo, nunca un relleno: no recibe clics y VoiceOver la lee con su palabra («Ahora», «Hoy»).
public struct MarcaAhora: View {
    public enum Eje: Sendable { case horizontal, vertical }
    let eje: Eje
    let palabra: String

    public init(_ eje: Eje = .horizontal, palabra: String = "Ahora") {
        self.eje = eje; self.palabra = palabra
    }

    /// Color y grosor de la línea, para quien la dibuja por su cuenta (la regla «hoy» del cronograma en Charts).
    public static var color: Color { TLSPaleta.chispa.color }
    public static let grosor: CGFloat = 2

    public var body: some View {
        Group {
            switch eje {
            case .horizontal:
                HStack(spacing: 0) {
                    punto
                    Rectangle().fill(TLSPaleta.chispa.color).frame(height: 2)
                }
            case .vertical:
                VStack(spacing: 0) {
                    punto
                    Rectangle().fill(TLSPaleta.chispa.color).frame(width: 2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(palabra)
    }

    private var punto: some View {
        Circle().fill(TLSPaleta.chispa.color).frame(width: 8, height: 8)
    }
}

/// Chip en cápsula (`bandeja`): icono de 13 pt, nombre corto y, si se da, una «×» de 28 pt para quitar.
public struct Chip: View {
    let titulo: String
    let icono: String?
    let area: TLSArea?
    let estado: TLSEstado?
    let quitar: (() -> Void)?
    let etiquetaQuitar: String

    public init(_ titulo: String, icono: String? = nil, area: TLSArea? = nil, estado: TLSEstado? = nil,
                etiquetaQuitar: String? = nil, quitar: (() -> Void)? = nil) {
        self.titulo = titulo; self.icono = icono; self.area = area; self.estado = estado; self.quitar = quitar
        self.etiquetaQuitar = etiquetaQuitar ?? "Quitar \(titulo)"
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let area {
                // Con área, el icono de la base en el color de su área (no el del área: Contactos y Empresas
                // llevarían los dos el de Ventas).
                IconoArea(area, tamano: 16, simbolo: icono)
            } else if let icono {
                Image(systemName: icono)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
            }
            Text(titulo)
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(1)
            if let estado {
                Image(systemName: estado.simbolo)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(estado.color.color)
                    .accessibilityLabel(estado.palabra)
            }
            if let quitar {
                Button(action: quitar) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityLabel(etiquetaQuitar)
                .padding(.trailing, -8)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, quitar == nil ? 10 : 4)
        .frame(minHeight: TLSAltura.objetivoMinimo)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Tecla o atajo: JetBrains Mono de 12 pt con borde (`⌘K`, `⇧⌘B`).
public struct Tecla: View {
    let texto: String
    public init(_ texto: String) { self.texto = texto }
    public var body: some View {
        Text(texto)
            .tlsTexto(TLSTipo.codigo.peso(400))
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: TLSRadio.tecla, style: .continuous)
                .strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(Tecla.leer(texto))
    }

    /// «⇧⌘B» → «mayúsculas comando B», para VoiceOver.
    public nonisolated static func leer(_ atajo: String) -> String {
        var partes: [String] = []
        for ch in atajo {
            switch ch {
            case "⌘": partes.append("comando")
            case "⇧": partes.append("mayúsculas")
            case "⌥": partes.append("opción")
            case "⌃": partes.append("control")
            case "↩": partes.append("retorno")
            default: partes.append(String(ch))
            }
        }
        return partes.joined(separator: " ")
    }
}

/// Rótulo de sección: mayúsculas de 11 pt en `textoSecundario` (barra lateral, cabeceras de columna).
public struct Rotulo: View {
    let texto: String
    public init(_ texto: String) { self.texto = texto }
    public var body: some View {
        Text(texto)
            .tlsTexto(TLSTipo.rotulo)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(texto)
    }
}

/// Icono de app de un área (§1.7): cuadrado de 24 pt (radio 7) o 32 pt (radio 9) con el relleno y el glifo.
/// Elegido en la barra lateral, lleva un borde blanco de 1,5 pt. Sobre la cabecera, cuadrado blanco y
/// glifo en la tinta del área.
public struct IconoArea: View {
    let area: TLSArea
    let tamano: CGFloat
    let simbolo: String?
    let seleccionado: Bool
    let sobreCabecera: Bool
    let atenuado: Bool

    /// `simbolo` cambia el glifo (las bases llevan el icono de su tipo con el color de su área).
    public init(_ area: TLSArea, tamano: CGFloat = 24, simbolo: String? = nil, seleccionado: Bool = false,
                sobreCabecera: Bool = false, atenuado: Bool = false) {
        self.area = area; self.tamano = tamano; self.simbolo = simbolo; self.seleccionado = seleccionado
        self.sobreCabecera = sobreCabecera; self.atenuado = atenuado
    }

    public var body: some View {
        let radio = tamano >= 32 ? TLSRadio.iconoArea32 : (tamano * TLSRadio.iconoArea24 / 24)
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        Image(systemName: simbolo ?? area.simbolo)
            .font(.system(size: tamano * 0.58, weight: .semibold))
            .foregroundStyle(sobreCabecera ? area.glifoSobreBlanco.color : TLSPaleta.glifo.color)
            .frame(width: tamano, height: tamano)
            .background(forma.fill(sobreCabecera ? TLSPaleta.sobreColor.color : area.relleno.color))
            .overlay {
                if seleccionado { forma.strokeBorder(TLSPaleta.sobreColor.color, lineWidth: 1.5) }
            }
            .opacity(atenuado ? 0.5 : 1)
            .accessibilityHidden(true)
    }
}

/// Icono de un tipo que no es un área (en filas y migas): SF Symbol en `textoSecundario`.
public struct IconoTipo: View {
    let simbolo: String
    let tamano: CGFloat
    public init(_ simbolo: String, tamano: CGFloat = 15) { self.simbolo = simbolo; self.tamano = tamano }
    public var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: tamano, weight: .medium))
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .frame(width: tamano + 6, height: tamano + 6)
            .accessibilityHidden(true)
    }
}

/// Monograma de la empresa: cuadrado azul noche de 28 pt (radio 8) con las iniciales.
public struct Monograma: View {
    let iniciales: String
    let tamano: CGFloat

    public init(nombre: String, tamano: CGFloat = 28) {
        self.iniciales = Monograma.iniciales(de: nombre)
        self.tamano = tamano
    }

    public var body: some View {
        Text(iniciales)
            .font(TLSEstiloTexto(.spaceGrotesk, peso: 700, tamano: 12 * tamano / 28, interlinea: 14).font())
            .tracking(0.24)
            .foregroundStyle(TLSPaleta.sobreColor.color)
            .frame(width: tamano, height: tamano)
            .background(RoundedRectangle(cornerRadius: TLSRadio.monograma, style: .continuous).fill(TLSPaleta.cabecera.color))
            .accessibilityHidden(true)
    }

    /// «Asesoría Ribera» → «AR»; «Clínica» → «CL».
    public nonisolated static func iniciales(de nombre: String) -> String {
        let palabras = nombre.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count > 2 || $0.first?.isUppercase == true }
        let primeras = palabras.compactMap(\.first)
        if primeras.count >= 2 { return String(primeras[0...1]).uppercased() }
        if let p = palabras.first { return String(p.prefix(2)).uppercased() }
        return "?"
    }
}
