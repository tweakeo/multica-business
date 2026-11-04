import SwiftUI
import TLSCore
import TLSDesign

/// El cronograma (Gantt propio en `Canvas`, PLAN §6.5): una fila por proyecto con su barra de inicio a fin, las
/// semanas, el fin de semana sombreado y la línea de hoy. Arrastrar la barra la mueve y arrastrar su borde derecho
/// cambia el fin; si una fecha cae en sábado o domingo, se corre al lunes. Todo arrastre tiene alternativa: el menú
/// de la fila, el teclado (← → un día laborable; ⇧← ⇧→ una semana) y las acciones de VoiceOver.
struct CronogramaVista: View {
    let cronograma: Cronograma
    /// Si no se puede escribir, por qué (las barras no se arrastran y el menú lo dice).
    let motivoSoloLectura: String?
    let alMover: (BarraCronograma, LocalDate, LocalDate) -> Void
    let alAbrir: (BarraCronograma) -> Void

    static let anchoDia: CGFloat = 16
    static let altoFila: CGFloat = 44
    static let altoGrupo: CGFloat = 34
    static let altoEscala: CGFloat = 30
    static let anchoEtiqueta: CGFloat = 290

    @FocusState private var enfocada: VaultPath?

    var body: some View {
        let filas = cronograma.grupos.map { g in (g, g.barras.filter(\.conFechas)) }.filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            if filas.isEmpty {
                Text("Ningún proyecto tiene aún inicio y fin. Pónselos en su ficha y aparecerán aquí.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: Self.altoEscala)
                        ForEach(filas, id: \.0.id) { g, barras in
                            cabeceraGrupo(g).frame(height: Self.altoGrupo, alignment: .bottomLeading)
                            ForEach(barras) { b in etiqueta(b, gris: g.gris).frame(height: Self.altoFila) }
                        }
                    }
                    .frame(width: Self.anchoEtiqueta)
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            EscalaCronograma(cronograma: cronograma).frame(height: Self.altoEscala)
                            ForEach(filas, id: \.0.id) { g, barras in
                                FondoCronograma(cronograma: cronograma).frame(height: Self.altoGrupo)
                                ForEach(barras) { b in
                                    PistaCronograma(cronograma: cronograma, barra: b, gris: g.gris,
                                                    activa: motivoSoloLectura == nil) { i, f in alMover(b, i, f) }
                                        .frame(height: Self.altoFila)
                                }
                            }
                        }
                        .frame(width: CGFloat(cronograma.dias) * Self.anchoDia)
                    }
                    .scrollIndicators(.visible)
                    .accessibilityHidden(true)
                }
            }
            if !cronograma.sinFechas.isEmpty {
                sinFechas
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cronograma")
    }

    // MARK: Columna de nombres

    private func cabeceraGrupo(_ g: GrupoCronograma) -> some View {
        HStack(spacing: 6) {
            Image(systemName: g.objetivo == nil ? "circle.dashed" : "target").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
            Text(g.titulo).tlsTexto(TLSTipo.interfazFuerte)
                .foregroundStyle(g.gris ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color).lineLimit(1)
            if let r = g.ritmo { RhythmBadge(OperacionComun.ritmo(r.estado)) }
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func etiqueta(_ b: BarraCronograma, gris: Bool) -> some View {
        let hoy = cronograma.hoy
        return Button { alAbrir(b) } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(b.nombre).tlsTexto(TLSTipo.interfazMedia)
                        .foregroundStyle(gris ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color).lineLimit(1)
                    if b.atencion != nil { PastillaEstado(.atencion, palabra: "Atención") }
                }
                Text([b.detalle, b.textoFechas(hoy: hoy)].compactMap { $0 }.joined(separator: " · "))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloFila(seleccionada: enfocada == b.ruta, alto: Self.altoFila - 4))
        .focusEffectDisabled()
        .focused($enfocada, equals: b.ruta)
        .tlsFocoPropio(radio: TLSRadio.fila)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { tecla in
            guard motivoSoloLectura == nil else { return .ignored }
            let adelante = tecla.key == .rightArrow
            if tecla.modifiers.contains(.shift) { semana(b, adelante: adelante) } else { dia(b, adelante: adelante) }
            return .handled
        }
        .contextMenu { menu(b) }
        .help(motivoSoloLectura.map { "No se puede mover: \($0)" } ?? "← → un día laborable · ⇧← ⇧→ una semana · arrastra la barra")
        .accessibilityLabel(b.etiquetaAccesible(hoy: hoy))
        .accessibilityHint("Abre su ficha")
        .accessibilityActions {
            if motivoSoloLectura == nil {
                Button("Un día antes") { dia(b, adelante: false) }
                Button("Un día después") { dia(b, adelante: true) }
                Button("Una semana antes") { semana(b, adelante: false) }
                Button("Una semana después") { semana(b, adelante: true) }
            }
        }
        .accessibilityIdentifier("cronograma.fila.\(b.ruta.raw)")
    }

    @ViewBuilder
    private func menu(_ b: BarraCronograma) -> some View {
        Button("Abrir") { alAbrir(b) }
        Divider()
        if let m = motivoSoloLectura {
            Text("No se puede mover: \(m)")
        } else {
            Button("Un día antes") { dia(b, adelante: false) }
            Button("Un día después") { dia(b, adelante: true) }
            Button("Una semana antes") { semana(b, adelante: false) }
            Button("Una semana después") { semana(b, adelante: true) }
        }
    }

    private func dia(_ b: BarraCronograma, adelante: Bool) {
        guard let i = b.inicio, let f = b.fin else { return }
        let r = Cronograma.moverUnDia(inicio: i, fin: f, adelante: adelante)
        alMover(b, r.inicio, r.fin)
    }

    private func semana(_ b: BarraCronograma, adelante: Bool) {
        guard let i = b.inicio, let f = b.fin else { return }
        let r = Cronograma.mover(inicio: i, fin: f, dias: adelante ? 7 : -7)
        alMover(b, r.inicio, r.fin)
    }

    private var sinFechas: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sin fechas").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
            ForEach(cronograma.sinFechas) { b in
                FilaLista(b.nombre, detalle: [b.detalle, b.textoEstado, "pon inicio y fin en su ficha"].compactMap { $0 }.joined(separator: " · "),
                          icono: "calendar.badge.exclamationmark", accion: { alAbrir(b) }) {
                    if b.atencion != nil { PastillaEstado(.atencion, palabra: "Atención") }
                }
            }
        }
        .padding(.top, TLSEspacio.e8)
    }
}

/// Las semanas de arriba: «19 oct» en cada lunes y el mes cuando cambia.
struct EscalaCronograma: View {
    let cronograma: Cronograma

    var body: some View {
        Canvas { ctx, size in
            let ancho = CronogramaVista.anchoDia
            let linea = TLSPaleta.separador.color
            var mesAnterior = 0
            for lunes in cronograma.semanas {
                let x = CGFloat(cronograma.indice(lunes)) * ancho
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: size.height - 8)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(linea), lineWidth: 1)
                var texto = "\(lunes.day)"
                if lunes.month != mesAnterior {
                    texto += " " + FormatoFicha.meses[lunes.month - 1]
                    mesAnterior = lunes.month
                }
                ctx.draw(Text(texto).font(.system(size: 11, weight: .medium)).foregroundStyle(TLSPaleta.textoSecundario.color),
                         at: CGPoint(x: x + 3, y: size.height - 14), anchor: .leading)
            }
            dibujarHoy(ctx, size: size, cronograma: cronograma, etiqueta: true)
        }
    }
}

/// El fondo de una fila de grupo: semanas, fin de semana y hoy.
struct FondoCronograma: View {
    let cronograma: Cronograma

    var body: some View {
        Canvas { ctx, size in
            dibujarRejilla(ctx, size: size, cronograma: cronograma)
            dibujarHoy(ctx, size: size, cronograma: cronograma, etiqueta: false)
        }
    }
}

/// La pista de un proyecto: rejilla, hoy y su barra (que se arrastra).
struct PistaCronograma: View {
    let cronograma: Cronograma
    let barra: BarraCronograma
    let gris: Bool
    let activa: Bool
    let alSoltar: (LocalDate, LocalDate) -> Void

    @State private var desplazamiento = 0
    @State private var soloFin = false

    var body: some View {
        Canvas { ctx, size in
            dibujarRejilla(ctx, size: size, cronograma: cronograma)
            dibujarHoy(ctx, size: size, cronograma: cronograma, etiqueta: false)
            guard let rango = fechas else { return }
            let (i, f) = rango
            let ancho = CronogramaVista.anchoDia
            let x0 = CGFloat(cronograma.indice(i)) * ancho
            let x1 = CGFloat(cronograma.indice(f) + 1) * ancho
            let rect = CGRect(x: x0 + 1, y: 12, width: max(ancho - 2, x1 - x0 - 2), height: size.height - 24)
            let forma = Path(roundedRect: rect, cornerRadius: 6)
            let color = gris ? TLSPaleta.textoSecundario.color.opacity(0.45) : (barra.area?.tlsArea.relleno.color ?? TLSPaleta.principal.color)
            ctx.fill(forma, with: .color(desplazamiento == 0 ? color : color.opacity(0.6)))
            if desplazamiento != 0 {
                ctx.stroke(forma, with: .color(TLSPaleta.texto.color), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if barra.atencion != nil {
                ctx.stroke(forma, with: .color(TLSEstado.atencion.color.color), lineWidth: 2)
            }
            // El asa del borde derecho (cambiar el fin).
            if activa {
                let asa = Path(roundedRect: CGRect(x: rect.maxX - 5, y: rect.midY - 7, width: 3, height: 14), cornerRadius: 1.5)
                ctx.fill(asa, with: .color(TLSPaleta.superficie.color.opacity(0.9)))
            }
            let texto = desplazamiento == 0 ? barra.textoEstado
                : "\(OperacionComun.fecha(i, hoy: cronograma.hoy)) – \(OperacionComun.fecha(f, hoy: cronograma.hoy))"
            ctx.draw(Text(texto).font(.system(size: 11, weight: .medium)).foregroundStyle(TLSPaleta.textoSecundario.color),
                     at: CGPoint(x: rect.maxX + 6, y: rect.midY), anchor: .leading)
        }
        .contentShape(Rectangle())
        .gesture(arrastre, including: activa ? .all : .none)
    }

    /// Las fechas que se pintan (las de la ficha, o las del arrastre en curso).
    private var fechas: (LocalDate, LocalDate)? {
        guard let i = barra.inicio, let f = barra.fin else { return nil }
        guard desplazamiento != 0 else { return (i, f) }
        if soloFin { return (i, Cronograma.cambiarFin(inicio: i, fin: f, dias: desplazamiento)) }
        let r = Cronograma.mover(inicio: i, fin: f, dias: desplazamiento)
        return (r.inicio, r.fin)
    }

    private var arrastre: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                guard let i = barra.inicio, let f = barra.fin else { return }
                let ancho = CronogramaVista.anchoDia
                let x0 = CGFloat(cronograma.indice(i)) * ancho
                let x1 = CGFloat(cronograma.indice(f) + 1) * ancho
                if desplazamiento == 0 {
                    // Solo si empieza encima de la barra; cerca del borde derecho, cambia el fin.
                    guard v.startLocation.x >= x0 - 4, v.startLocation.x <= x1 + 6 else { return }
                    soloFin = v.startLocation.x >= x1 - 10
                }
                desplazamiento = Int((v.translation.width / ancho).rounded())
            }
            .onEnded { _ in
                defer { desplazamiento = 0; soloFin = false }
                guard desplazamiento != 0, let rango = fechas, rango.0 != barra.inicio || rango.1 != barra.fin else { return }
                alSoltar(rango.0, rango.1)
            }
    }
}

/// Semanas (línea en cada lunes) y fin de semana sombreado.
@MainActor
private func dibujarRejilla(_ ctx: GraphicsContext, size: CGSize, cronograma: Cronograma) {
    let ancho = CronogramaVista.anchoDia
    for d in 0..<cronograma.dias {
        let dia = cronograma.desde.adding(days: d)
        let x = CGFloat(d) * ancho
        if dia.isWeekend {
            ctx.fill(Path(CGRect(x: x, y: 0, width: ancho, height: size.height)), with: .color(TLSPaleta.bandeja.color))
        }
        if dia.weekday == 1 {
            ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                       with: .color(TLSPaleta.separador.color), lineWidth: 1)
        }
    }
}

/// La línea de hoy (la marca «ahora» del diseño, §1.5).
@MainActor
private func dibujarHoy(_ ctx: GraphicsContext, size: CGSize, cronograma: Cronograma, etiqueta: Bool) {
    guard cronograma.hoy >= cronograma.desde, cronograma.hoy <= cronograma.hasta else { return }
    let x = (CGFloat(cronograma.indice(cronograma.hoy)) + 0.5) * CronogramaVista.anchoDia
    ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: etiqueta ? size.height - 10 : 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
               with: .color(MarcaAhora.color), lineWidth: MarcaAhora.grosor)
    if etiqueta {
        ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: size.height - 14, width: 8, height: 8)), with: .color(MarcaAhora.color))
    }
}
