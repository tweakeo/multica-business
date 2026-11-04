import SwiftUI

/// Una pestaña en cápsula con su contador (§3.1, §3.2): el contador cuenta lo abierto y nunca va en
/// magenta; si dentro hay algo urgente, lleva delante el icono del estado; si algo espera **tu** OK, la
/// insignia magenta con palabra («Por confirmar 1»).
public struct PestanaCapsula: Identifiable, Hashable, Sendable {
    public let id: String
    public let titulo: String
    public let contador: Int?
    public let urgente: TLSEstado?
    public let aviso: (numero: Int, palabra: String)?

    public init(id: String, titulo: String, contador: Int? = nil, urgente: TLSEstado? = nil,
                aviso: (numero: Int, palabra: String)? = nil) {
        self.id = id; self.titulo = titulo; self.contador = contador; self.urgente = urgente; self.aviso = aviso
    }

    public static func == (a: PestanaCapsula, b: PestanaCapsula) -> Bool {
        a.id == b.id && a.titulo == b.titulo && a.contador == b.contador && a.urgente == b.urgente
            && a.aviso?.numero == b.aviso?.numero && a.aviso?.palabra == b.aviso?.palabra
    }

    public func hash(into h: inout Hasher) {
        h.combine(id); h.combine(titulo); h.combine(contador); h.combine(urgente)
        h.combine(aviso?.numero); h.combine(aviso?.palabra)
    }

    /// Lo que lee VoiceOver: «Facturas, 2, 1 urgente, Por confirmar 1».
    public var etiquetaAccesible: String {
        var partes = [titulo]
        if let contador { partes.append("\(contador)") }
        if let urgente { partes.append(urgente.palabra) }
        if let aviso { partes.append("\(aviso.palabra) \(aviso.numero)") }
        return partes.joined(separator: ", ")
    }
}

/// Pestañas en cápsula con «Más ▾» para las vacías y para las que no caben, y ⌃1–⌃9 (§3.1, §7.3 `PestanasFicha`).
public struct PestanasCapsula: View {
    @Binding var seleccion: String
    let pestanas: [PestanaCapsula]
    let mas: [PestanaCapsula]
    let atajosControl: Bool
    @Environment(\.accessibilityReduceMotion) private var reducir

    public init(seleccion: Binding<String>, pestanas: [PestanaCapsula], mas: [PestanaCapsula] = [],
                atajosControl: Bool = true) {
        self._seleccion = seleccion; self.pestanas = pestanas; self.mas = mas; self.atajosControl = atajosControl
    }

    public var body: some View {
        // Las que no caben pasan a «Más ▾» (como en M2-Contacto), empezando por las últimas; la elegida siempre
        // se ve. Nada queda cortado a medias.
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: pestanas.count, through: min(1, pestanas.count), by: -1)), id: \.self) { k in
                fila(reparto(k))
            }
        }
        .background(alignment: .topLeading) { atajos }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pestañas")
    }

    /// Las `k` primeras pestañas a la vista (con la elegida dentro) y el resto, con las de `mas`, en el menú.
    func reparto(_ k: Int) -> (visibles: [PestanaCapsula], fuera: [PestanaCapsula]) {
        var visibles = Array(pestanas.prefix(k))
        var fuera = Array(pestanas.dropFirst(k))
        if let i = fuera.firstIndex(where: { $0.id == seleccion }), !visibles.isEmpty {
            let elegida = fuera.remove(at: i)
            fuera.insert(visibles.removeLast(), at: 0)
            visibles.append(elegida)
        }
        return (visibles, fuera + mas)
    }

    private func fila(_ r: (visibles: [PestanaCapsula], fuera: [PestanaCapsula])) -> some View {
        HStack(spacing: 6) {
            ForEach(r.visibles) { p in
                Button {
                    withAnimation(TLSMovimiento.si(TLSMovimiento.pestana, reducir: reducir)) { seleccion = p.id }
                } label: {
                    etiqueta(p, elegida: p.id == seleccion)
                }
                .buttonStyle(EstiloPestana(elegida: p.id == seleccion))
                .focusEffectDisabled()
                .accessibilityLabel(p.etiquetaAccesible)
                .accessibilityAddTraits(p.id == seleccion ? .isSelected : [])
            }
            if !r.fuera.isEmpty {
                Menu {
                    ForEach(r.fuera) { p in
                        Button(p.contador.map { "\(p.titulo) · \($0)" } ?? p.titulo) { seleccion = p.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(r.fuera.first { $0.id == seleccion }?.titulo ?? "Más")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .padding(.horizontal, 14)
                    .frame(minHeight: TLSAltura.objetivoMinimo + 4)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Más pestañas")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func etiqueta(_ p: PestanaCapsula, elegida: Bool) -> some View {
        HStack(spacing: 6) {
            Text(p.titulo).tlsTexto(TLSTipo.interfazFuerte)
            if let urgente = p.urgente {
                Image(systemName: urgente.simbolo)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : urgente.color.color)
            }
            if let contador = p.contador {
                Text("\(contador)")
                    .tlsTexto(TLSTipo.secundario)
                    .monospacedDigit()
                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
            }
            if let aviso = p.aviso {
                // Siempre con su palabra, también en la pestaña elegida (§1.5, §2.2).
                InsigniaAviso(aviso.numero, palabra: aviso.palabra, enCapsula: true)
            }
        }
    }

    /// ⌃1–⌃9 saltan a cada pestaña (botones invisibles con atajo).
    @ViewBuilder private var atajos: some View {
        if atajosControl {
            ZStack {
                ForEach(Array((pestanas + mas).prefix(9).enumerated()), id: \.element.id) { i, p in
                    Button("") { seleccion = p.id }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .control)
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}

/// Cápsula de pestaña: elegida en azul noche; al pasar, `bandeja`.
struct EstiloPestana: ButtonStyle {
    let elegida: Bool

    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration, elegida: elegida)
    }

    private struct Cuerpo: View {
        let configuration: Configuration
        let elegida: Bool
        @Environment(\.isFocused) private var enfocado
        @State private var encima = false

        var body: some View {
            configuration.label
                .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                .padding(.horizontal, 14)
                .frame(minHeight: TLSAltura.objetivoMinimo + 4)
                .background(Capsule(style: .circular).fill(relleno))
                .contentShape(Capsule(style: .circular))
                .tlsAnilloFoco(enfocado, radio: 999)
                .onHover { encima = $0 }
        }

        private var relleno: Color {
            if elegida { return TLSPaleta.principal.color }
            if configuration.isPressed { return TLSPaleta.principalSuave.color }
            return encima ? TLSPaleta.bandeja.color : .clear
        }
    }
}
