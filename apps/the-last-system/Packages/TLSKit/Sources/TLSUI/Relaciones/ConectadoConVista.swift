import SwiftUI
import TLSCore
import TLSDesign

/// Franja «Conectado con» (§3.1 punto 4, §5): un chip por relación de uno a uno de esta ficha (las que guarda y
/// las calculadas), con «×» al pasar el puntero, su menú (Cambiar… · Quitar · Abrir · Abrir en pestaña nueva) y
/// «+ Relacionar» al final. Una obligatoria vacía sale como «Falta empresa» en Atención. En las de varias se
/// ven 4 chips y «+N»; el orden se cambia con el menú («Mover antes», «Mover después») o con VoiceOver.
struct ConectadoConVista: View {
    let modelo: FichaModelo
    @Environment(\.navegar) private var navegar
    @State private var todos = false

    var body: some View {
        let chips = modelo.resumen?.conectado ?? []
        let visibles = todos ? chips : agrupados(chips)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Rotulo("Conectado con")
            FlujoChips(espacio: TLSEspacio.e8) {
                ForEach(visibles) { c in
                    ChipRelacion(chip: c, modelo: modelo)
                }
                if visibles.count < chips.count {
                    Button("+\(chips.count - visibles.count)") { todos = true }
                        .tlsBoton(.secundario)
                        .accessibilityLabel("Ver las \(chips.count - visibles.count) relaciones más")
                }
                menuRelacionar
            }
            .popover(item: Binding(get: { modelo.selector.flatMap { esDeAqui($0) ? $0 : nil } },
                                   set: { if $0 == nil { modelo.selector = nil } }), arrowEdge: .bottom) { p in
                selector(p)
            }
            if chips.isEmpty, modelo.resumen != nil {
                Text("Aún no está conectada con nada. Usa «Relacionar» para enlazarla.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conectado con")
        .accessibilityRotor(Text("Relacionados"), entries: chips, entryLabel: \.nombre)
    }

    /// Como mucho 4 chips por propiedad de varias (el resto, en «+N»).
    private func agrupados(_ chips: [ChipConectado]) -> [ChipConectado] {
        var cuenta: [String: Int] = [:]
        return chips.filter { c in
            cuenta[c.propiedad, default: 0] += 1
            return cuenta[c.propiedad]! <= 4
        }
    }

    private func esDeAqui(_ p: PeticionSelector) -> Bool {
        if case .directo = p.modo { return p.origen == "chips" }
        return false
    }

    private var menuRelacionar: some View {
        let defs = modelo.ficha.map { EsquemaRelaciones.guardadas(por: $0.tipo) } ?? []
        let llenas = Set((modelo.resumen?.conectado ?? []).filter { !$0.calculado && !$0.falta }.map(\.propiedad))
        return Menu {
            ForEach(defs) { d in
                let ocupada = d.cardinalidad == .una && llenas.contains(d.propiedad)
                Button {
                    modelo.abrirSelector(propiedad: d.propiedad)
                } label: {
                    Text(d.etiqueta)
                    if ocupada { Text("Ya tiene: usa «Cambiar…» en su chip") }
                }
                .disabled(ocupada)
            }
            if defs.isEmpty { Text("Esta ficha no guarda relaciones con otras") }
        } label: {
            Label("Relacionar", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(EstiloAnadirDiscontinuo())
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!modelo.puedeEscribir)
        .help(modelo.motivoSoloLectura.map { "No se puede cambiar: \($0)" } ?? "Enlazar con otra ficha")
    }

    private func selector(_ p: PeticionSelector) -> some View {
        SelectorRelacion(peticion: p, sesion: modelo.sesion, almacen: modelo.almacen,
                         alElegir: { d in Task { await modelo.elegido(d, en: p, navegar: navegar) } },
                         alQuitar: {
                             if case .directo(_, let prop) = p.modo {
                                 Task { await modelo.quitar(propiedad: prop, destino: nil, guardaEn: modelo.ruta) }
                             }
                         },
                         alCrear: { nombre in
                             if case .directo(let dueno, let prop) = p.modo, let c = p.crear {
                                 Task { await EdicionRelaciones.crearYEnlazar(nombre: nombre, tipo: c.tipo, dueno: dueno, propiedad: prop,
                                                                              sesion: modelo.sesion, almacen: modelo.almacen) }
                             }
                         },
                         alListo: { m in Task { await modelo.listo(m, en: p) } })
    }
}

/// Un chip de «Conectado con»: icono del tipo, rótulo, nombre corto y punto de estado. Clic entra en la ficha;
/// «×» al pasar el puntero quita (si se puede); menú contextual con todo.
struct ChipRelacion: View {
    let chip: ChipConectado
    let modelo: FichaModelo
    @Environment(\.navegar) private var navegar
    @State private var encima = false
    @FocusState private var enfocado: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(action: abrir) {
                HStack(spacing: 6) {
                    Image(systemName: chip.falta ? TLSEstado.atencion.simbolo : (chip.tipo?.systemImage ?? "link"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(chip.falta ? TLSPaleta.atencion.color : TLSPaleta.textoSecundario.color)
                    if !chip.falta {
                        Text(chip.rotulo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    Text(chip.nombre).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                    if let e = chip.estado, let t = chip.tipo {
                        let est = FormatoFicha.tlsEstado(t, e, hoy: modelo.hoy)
                        Image(systemName: est.simbolo).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(est.color.color)
                            .accessibilityLabel(FormatoFicha.capital(e))
                    }
                    if chip.calculado {
                        Image(systemName: "function").font(.system(size: 10)).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .accessibilityLabel("calculado")
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, quitable && encima ? 2 : 10)
                .frame(minHeight: TLSAltura.objetivoMinimo + 4)
                .contentShape(Capsule(style: .circular))
            }
            .buttonStyle(.plain)
            .focused($enfocado)
            .focusEffectDisabled()
            .vistaPrevia(ruta: chip.destino, sesion: modelo.sesion)
            if quitable && (encima || enfocado) {
                Button { Task { await quitar() } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityLabel("Quitar \(chip.rotulo.lowercased()) \(chip.nombre)")
                .padding(.leading, -8)
            }
        }
        .background(Capsule(style: .circular).fill(chip.falta ? TLSEstado.atencion.tinte.color : TLSPaleta.bandeja.color))
        .tlsAnilloFoco(enfocado, radio: 999)
        .onHover { encima = $0 }
        .help(ayuda)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chip.falta ? chip.nombre : "\(chip.rotulo): \(chip.nombre)\(chip.calculado ? ", calculado" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { abrir() }
        .accessibilityAction(named: "Cambiar") { if !chip.calculado { modelo.abrirSelector(propiedad: chip.propiedad) } }
        .accessibilityAction(named: "Quitar") { Task { await quitar() } }
        .accessibilityAction(named: "Mover antes") { Task { await mover(-1) } }
        .accessibilityAction(named: "Mover después") { Task { await mover(1) } }
    }

    private var ayuda: String {
        if chip.falta { return chip.motivoNoQuitar ?? "Falta" }
        if chip.calculado {
            let otra = modelo.grafo?.ficha(chip.guardaEn)?.nombre ?? chip.guardaEn.stem
            return chip.motivoNoQuitar ?? "Se guarda en la ficha de \(otra), en «\(chip.propiedad)»"
        }
        return "Se guarda en esta ficha, en «\(chip.propiedad)»"
    }

    private var quitable: Bool {
        guard !chip.falta, chip.motivoNoQuitar == nil, modelo.puedeEscribir else { return false }
        return !chip.calculado || chip.propiedad == "referido_por" || chip.propiedad == "bloqueada_por"
    }

    private var esVarias: Bool {
        guard let t = modelo.ficha?.tipo else { return false }
        return !chip.calculado && EsquemaRelaciones.definicion(tipo: t, propiedad: chip.propiedad)?.cardinalidad == .varias
    }

    @ViewBuilder
    private var menu: some View {
        if let d = chip.destino {
            Button("Abrir") { navegar(modelo.sesion.destino(para: d), modo: .entrar) }
            Button("Abrir en pestaña nueva") { navegar(modelo.sesion.destino(para: d), modo: .pestanaNueva) }
            Button("Vista previa") { modelo.sesion.navegacionActiva?.vistaPrevia = d }
            Divider()
        }
        if !chip.calculado {
            Button("Cambiar…") { modelo.abrirSelector(propiedad: chip.propiedad) }.disabled(!modelo.puedeEscribir)
        }
        if !chip.falta {
            Button(chip.calculado ? "Quitar de \(modelo.grafo?.ficha(chip.guardaEn)?.nombre ?? chip.guardaEn.stem)" : "Quitar") {
                Task { await quitar() }
            }
            .disabled(!quitable)
            if let motivo = chip.motivoNoQuitar { Text(motivo) }
        }
        if esVarias {
            Divider()
            Button("Mover antes") { Task { await mover(-1) } }
            Button("Mover después") { Task { await mover(1) } }
        }
    }

    private func abrir() {
        if chip.falta || chip.destino == nil {
            modelo.abrirSelector(propiedad: chip.propiedad)
        } else if let d = chip.destino {
            navegar(modelo.sesion.destino(para: d))
        }
    }

    private func quitar() async {
        guard quitable else {
            if let m = chip.motivoNoQuitar { modelo.sesion.aviso = Aviso(m, estado: .atencion) }
            return
        }
        if chip.calculado {
            await modelo.quitar(propiedad: chip.propiedad, destino: modelo.ruta, guardaEn: chip.guardaEn)
        } else {
            await modelo.quitar(propiedad: chip.propiedad, destino: chip.destino, guardaEn: modelo.ruta)
        }
    }

    private func mover(_ d: Int) async {
        guard esVarias, let destino = chip.destino else { return }
        await modelo.mover(destino, propiedad: chip.propiedad, desplazamiento: d)
    }
}

/// Coloca vistas en filas que saltan de línea cuando no caben (chips).
struct FlujoChips: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? 800
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            maxX = max(maxX, x - espacio)
            alto = max(alto, t.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + t.width > bounds.maxX { x = bounds.minX; y += alto + espacio; alto = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
    }
}

/// «+ Relacionar» y los demás «añadir» de una franja de chips: cápsula con borde discontinuo, como en las maquetas
/// (lo que aún no está, frente a los chips que sí).
struct EstiloAnadirDiscontinuo: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration)
    }

    private struct Cuerpo: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var activo
        @Environment(\.isFocused) private var enfocado
        @State private var encima = false

        var body: some View {
            configuration.label
                .tlsTexto(TLSTipo.interfazFuerte)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: TLSAltura.objetivoMinimo + 4)
                .foregroundStyle(activo ? TLSPaleta.texto.color : TLSPaleta.desactivadoTexto.color)
                .background(Capsule(style: .circular).fill(configuration.isPressed ? TLSPaleta.principalSuave.color : (encima && activo ? TLSPaleta.bandeja.color : .clear)))
                .overlay(Capsule(style: .circular).strokeBorder(TLSPaleta.bordeControl.color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .contentShape(Capsule(style: .circular))
                .tlsAnilloFoco(enfocado && activo, radio: 999)
                .onHover { encima = $0 }
        }
    }
}
