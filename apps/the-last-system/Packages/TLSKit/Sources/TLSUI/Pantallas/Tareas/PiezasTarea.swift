import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol tareas. Piezas pequeñas que comparten la lista, el tablero y la ficha de una tarea (Mosaico v2).

extension EstadoTarea {
    /// Icono y color del estado (la palabra va siempre al lado, §1.6).
    var tlsEstado: TLSEstado {
        switch self {
        case .hecha: .bien
        case .enRevision: .atencion
        case .bloqueada: .mal
        case .sinProgramar, .porHacer, .enCurso, .cancelada: .sinDato
        }
    }

    /// Icono propio de cada columna (en las pastillas de estado manda `tlsEstado`).
    var simboloColumna: String {
        switch self {
        case .sinProgramar: "tray"
        case .porHacer: "circle"
        case .enCurso: "circle.lefthalf.filled"
        case .enRevision: "eye"
        case .bloqueada: "xmark.octagon"
        case .hecha: "checkmark.circle.fill"
        case .cancelada: "slash.circle"
        }
    }
}

/// Quién puede llevar una tarea: tú, las personas y asistentes que ya llevan algo y un asistente por cada rol de
/// Equipo, como `Responsables.opciones` pero **sin mirar lo privado** (un nombre de una ficha privada no sale aquí).
enum ResponsablesTarea {
    static func opciones(grafo: GrafoRelaciones?, persona: String) -> [(id: String, nombre: String)] {
        var ids: [String] = [persona]
        if let grafo {
            for f in grafo.fichas.values.sorted(by: { $0.ruta < $1.ruta }) where !f.privada {
                if let r = f.texto("responsable"), !r.contains("{{") { ids.append(r) }
            }
            for f in grafo.fichas(de: [.role]) where !f.privada { ids.append("agente:" + NombresDeFicha.slug(f.nombre)) }
        }
        var vistos = Set<String>()
        return ids.filter { vistos.insert(TextFolding.fold($0)).inserted }.map { ($0, Responsables.nombre(de: $0)) }
    }

    static func asistentes(grafo: GrafoRelaciones?, persona: String) -> [(id: String, nombre: String)] {
        opciones(grafo: grafo, persona: persona).filter { $0.id.lowercased().hasPrefix("agente:") }
    }
}

/// Quién lleva la tarea: las iniciales de una persona en un círculo o el icono con «IA» de un asistente (§6.4).
/// Sin responsable, un círculo punteado. Siempre con su nombre para VoiceOver y al pasar el puntero.
struct ResponsableTarea: View {
    let identificador: String?
    var tamano: CGFloat = 24

    var body: some View {
        Group {
            if let r = identificador, r.lowercased().hasPrefix("agente:") {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles").font(.system(size: tamano * 0.42, weight: .semibold))
                    Text("IA").tlsTexto(TLSTipo.rotulo)
                }
                .foregroundStyle(TLSPaleta.principal.color)
                .padding(.horizontal, 7)
                .frame(minWidth: tamano, minHeight: tamano)
                .background(Capsule(style: .circular).fill(TLSPaleta.principalSuave.color))
            } else if let r = identificador {
                Text(Monograma.iniciales(de: Responsables.nombre(de: r)))
                    .font(TLSEstiloTexto(.spaceGrotesk, peso: 700, tamano: tamano * 0.42, interlinea: tamano * 0.5).font())
                    .foregroundStyle(TLSPaleta.texto.color)
                    .frame(width: tamano, height: tamano)
                    .background(Circle().fill(TLSPaleta.bandeja.color))
                    .overlay(Circle().strokeBorder(TLSPaleta.separador.color, lineWidth: 1))
            } else {
                Circle().strokeBorder(TLSPaleta.bordeControl.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: tamano, height: tamano)
            }
        }
        .fixedSize()
        .help(nombre)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nombre)
    }

    var nombre: String {
        identificador.map { "La lleva " + Responsables.nombre(de: $0) } ?? "Sin responsable"
    }
}

/// El vencimiento: si venció (y sigue abierta), con el icono de Mal y la palabra «Vencida»; nunca solo por color.
struct VenceTarea: View {
    let vence: LocalDate?
    let abierta: Bool
    let hoy: LocalDate
    var conPalabraVence = false
    /// Sin el día de la semana («vence 21 oct»), para las tarjetas estrechas del tablero.
    var corta = false

    private func fecha(_ d: LocalDate) -> String { corta ? FormatoFicha.fechaCorta(d, hoy: hoy) : FormatoFicha.fechaConDia(d, hoy: hoy) }

    var body: some View {
        if let vence, abierta, vence < hoy {
            Label {
                Text("Vencida · " + FormatoFicha.fechaCorta(vence, hoy: hoy)).tlsTexto(TLSTipo.secundario).lineLimit(1)
            } icon: {
                Image(systemName: TLSEstado.mal.simbolo).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(TLSPaleta.mal.color)
            .accessibilityLabel("Vencida el " + FormatoFicha.fechaConDia(vence, hoy: hoy))
        } else if let vence {
            Text((conPalabraVence ? "vence " : "") + (vence == hoy ? "hoy" : fecha(vence)))
                .tlsTexto(TLSTipo.secundario).lineLimit(1)
                .foregroundStyle(vence == hoy && abierta ? TLSPaleta.atencion.color : TLSPaleta.textoSecundario.color)
                .accessibilityLabel("Vence " + FormatoFicha.cuando(vence, hoy: hoy))
        } else {
            Text(conPalabraVence ? "sin fecha límite" : "—").tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityLabel("Sin fecha límite")
        }
    }
}

/// Menú «Mover a…» con los estados (el actual, desactivado). Lo usan la lista, el tablero y VoiceOver.
struct MenuMoverA: View {
    let actual: EstadoTarea
    let mover: (EstadoTarea) -> Void

    var body: some View {
        Menu("Mover a…") {
            ForEach(EstadoTarea.allCases, id: \.self) { e in
                Button(e.rawValue) { mover(e) }.disabled(e == actual)
            }
        }
    }
}

/// Un control de filtro de la barra: cápsula con borde, la etiqueta y lo elegido («Área: 2 · Ventas ▾»).
struct MenuFiltro<Contenido: View>: View {
    let etiqueta: String
    let valor: String?
    /// En azul noche cuando filtra (por defecto, si hay valor); la agrupación por defecto no se resalta.
    var resaltado: Bool? = nil
    @ViewBuilder let contenido: () -> Contenido

    private var puesto: Bool { resaltado ?? (valor != nil) }

    var body: some View {
        Menu {
            contenido()
        } label: {
            HStack(spacing: 4) {
                Text(valor.map { "\(etiqueta): \($0)" } ?? etiqueta).tlsTexto(TLSTipo.interfazMedia).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(puesto ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
            .padding(.horizontal, 12)
            .frame(minHeight: TLSAltura.objetivoMinimo + 4)
            .background(Capsule(style: .circular).fill(puesto ? TLSPaleta.principal.color : Color.clear))
            .overlay(Capsule(style: .circular).strokeBorder(puesto ? .clear : TLSPaleta.bordeControl.color, lineWidth: 1))
            .contentShape(Capsule(style: .circular))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .tlsFocoPropio(radio: 999)
        .accessibilityLabel(valor.map { "\(etiqueta): \($0). Cambiar" } ?? "Filtrar por \(etiqueta.lowercased())")
    }
}
