import Charts
import SwiftUI
import TLSCore
import TLSDesign

/// Finanzas › Caja (PLAN §6.5, SISTEMAS FI2; maqueta M2-Hoy, módulo Caja): el saldo de todas las cuentas con su
/// gráfica 1S · 1M · 3M · 1A · Todo (línea discontinua donde la cifra es **estimada** y hueco donde no se sabe), los
/// meses de caja frente a su meta y cada cuenta con de dónde sale su saldo. Sin datos del banco: «Sin datos del banco:
/// importa un extracto». Nunca un 0 de relleno.
struct CajaFinanzas: View {
    let lectura: LecturaFinanzas
    let contexto: ContextoArea
    @Bindable var modelo: ModeloFinanzas
    let importar: () -> Void

    var body: some View {
        if !lectura.hayDatosBanco {
            VacioExplicado(icono: "building.columns", titulo: "Sin datos del banco: importa un extracto",
                           porQue: (lectura.runway.motivo.map { $0 + ". " } ?? "")
                               + "Suelta el extracto en CSV que da tu banco: verás el saldo, su gráfica y los meses que aguanta la caja.",
                           accion: modelo.motivoSoloLectura == nil ? "Importar extracto…" : nil,
                           alPulsar: modelo.motivoSoloLectura == nil ? importar : nil)
                .accessibilityIdentifier("finanzas.caja.vacia")
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                    TarjetaCajaFinanzas(lectura: lectura, modelo: modelo, runway: runwayCorto).frame(minWidth: 560)
                    VStack(spacing: TLSEspacio.entreMosaicos) {
                        TarjetaMesesDeCaja(lectura: lectura, fila: contexto.numero("FIN-RUNWAY"), modelo: modelo)
                        TarjetaCuentasBanco(lectura: lectura)
                    }
                    .frame(width: 320)
                }
                VStack(spacing: TLSEspacio.entreMosaicos) {
                    TarjetaCajaFinanzas(lectura: lectura, modelo: modelo, runway: runwayCorto)
                    TarjetaMesesDeCaja(lectura: lectura, fila: contexto.numero("FIN-RUNWAY"), modelo: modelo)
                    TarjetaCuentasBanco(lectura: lectura)
                }
            }
            .accessibilityIdentifier("finanzas.caja")
        }
    }

    /// «7,9 meses de caja · En ritmo» para el pie de la gráfica (como en la maqueta), o `nil` si aún no se ve.
    private var runwayCorto: (texto: String, ritmo: RitmoNumero)? {
        if let f = contexto.numero("FIN-RUNWAY") {
            guard f.valorVisible, let v = f.lectura.textoValor else { return nil }
            return ("\(v) de caja", f.ritmo)
        }
        guard let m = lectura.runway.meses else { return nil }
        return ("\(TextoFinanzas.meses(m)) de caja", .sinMeta)
    }
}

// MARK: - La gráfica

/// Un punto de la gráfica en euros (la gráfica no necesita céntimos).
struct PuntoCajaFinanzas: Identifiable, Hashable {
    var id: LocalDate { dia }
    let dia: LocalDate
    let fecha: Date
    let euros: Double
    let estimado: Bool
}

/// Un tramo seguido de la línea: real o estimado. Donde el saldo no se sabe, la línea se corta (no baja a 0).
struct TramoCajaFinanzas: Identifiable, Hashable {
    let id: Int
    let estimado: Bool
    let puntos: [PuntoCajaFinanzas]

    /// Parte la serie en tramos: se corta en los huecos y cambia de tramo al pasar de estimado a real (el punto de
    /// unión está en los dos, para que la línea no se interrumpa).
    static func de(_ serie: [PuntoCaja]) -> [TramoCajaFinanzas] {
        var out: [TramoCajaFinanzas] = []
        var actual: [PuntoCajaFinanzas] = []
        var estimado = false
        for p in serie {
            guard let s = p.saldo else {
                if !actual.isEmpty { out.append(TramoCajaFinanzas(id: out.count, estimado: estimado, puntos: actual)) }
                actual = []
                continue
            }
            let g = PuntoCajaFinanzas(dia: p.fecha, fecha: p.fecha.date(), euros: Double(s) / 100, estimado: p.estimado)
            if actual.isEmpty {
                estimado = p.estimado
                actual = [g]
            } else if p.estimado != estimado, let union = actual.last {
                out.append(TramoCajaFinanzas(id: out.count, estimado: estimado, puntos: actual))
                actual = [union, g]
                estimado = p.estimado
            } else {
                actual.append(g)
            }
        }
        if !actual.isEmpty { out.append(TramoCajaFinanzas(id: out.count, estimado: estimado, puntos: actual)) }
        return out
    }
}

/// La tarjeta grande de la caja: cifra, variación del periodo, frase, gráfica interactiva y «Ver como tabla».
private struct TarjetaCajaFinanzas: View {
    let lectura: LecturaFinanzas
    @Bindable var modelo: ModeloFinanzas
    let runway: (texto: String, ritmo: RitmoNumero)?
    @State private var elegida: LocalDate?
    @State private var tabla = false

    var body: some View {
        let serie = lectura.series[modelo.rango] ?? []
        let puntos = serie.compactMap { p in p.saldo.map { PuntoCajaFinanzas(dia: p.fecha, fecha: p.fecha.date(), euros: Double($0) / 100, estimado: p.estimado) } }
        let variacion = VariacionCajaFinanzas(serie)
        let punto = elegida.flatMap { d in serie.first { $0.fecha == d } }
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .center, spacing: TLSEspacio.e8) {
                IconoArea(.finanzas, tamano: 16)
                Rotulo("Caja")
                Spacer(minLength: 0)
                SelectorPeriodoCajaFinanzas(rango: Binding(get: { modelo.rango }, set: { modelo.rango = $0; elegida = nil }))
            }
            cabecera(punto: punto, variacion: variacion)
            if let variacion, punto == nil {
                Text(variacion.frase(modelo.rango))
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if tabla {
                TablaCajaFinanzas(serie: serie, lectura: lectura)
            } else if puntos.count >= 2 {
                GraficaCajaFinanzas(tramos: TramoCajaFinanzas.de(serie), puntos: puntos, elegida: $elegida, hoy: lectura.hoy,
                            descripcion: variacion?.frase(modelo.rango) ?? "")
                    .frame(height: 190)
            } else {
                Text("Hace falta más de un día con saldo para dibujar la gráfica de este periodo.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                if let runway {
                    RhythmBadge(runway.ritmo, palabra: "\(runway.texto) · \(runway.ritmo.palabra)")
                }
                if serie.contains(where: \.estimado) {
                    HStack(spacing: 6) {
                        Capsule(style: .circular).fill(TLSPaleta.principal.color).frame(width: 6, height: 2.5)
                        Capsule(style: .circular).fill(TLSPaleta.principal.color).frame(width: 6, height: 2.5)
                        Text("Estimado: no sale de un extracto").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("La línea discontinua es estimada: no sale de un extracto")
                }
                Spacer(minLength: 0)
                Button {
                    tabla.toggle()
                } label: {
                    Label(tabla ? "Ver como gráfica" : "Ver como tabla", systemImage: tabla ? "chart.xyaxis.line" : "tablecells")
                }
                .tlsBoton(.secundario)
                .accessibilityIdentifier("finanzas.caja.tabla")
            }
        }
        .padding(TLSEspacio.mosaicoGrande)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Caja")
        .accessibilityIdentifier("finanzas.caja.grafica")
    }

    @ViewBuilder
    private func cabecera(punto: PuntoCaja?, variacion: VariacionCajaFinanzas?) -> some View {
        let hoy = lectura.hoy
        VStack(alignment: .leading, spacing: 4) {
            if let punto {
                Text(punto.fecha == hoy ? "Hoy · \(FormatoFicha.fechaConDia(hoy, hoy: hoy))" : FormatoFicha.fechaConDia(punto.fecha, hoy: hoy))
                    .tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.textoSecundario.color)
                Text(TextoFinanzas.euros(punto.saldo))
                    .tlsTexto(TLSTipo.cifraGrande).foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: TLSEspacio.e8) {
                    Text(movimientosDelDia(punto.fecha)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if punto.estimado { PastillaEstimadoFinanzas() }
                }
            } else {
                Text("Hoy · \(FormatoFicha.fechaConDia(hoy, hoy: hoy))")
                    .tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.textoSecundario.color)
                Text(TextoFinanzas.euros(lectura.saldo.total))
                    .tlsTexto(TLSTipo.cifraGrande).foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityLabel("Caja de hoy: \(TextoFinanzas.euros(lectura.saldo.total))")
                    .accessibilityIdentifier("finanzas.caja.total")
                HStack(spacing: TLSEspacio.e8) {
                    if let variacion, !variacion.sinMovimientos {
                        Text(variacion.texto).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text("desde el \(TextoFinanzas.fecha(variacion.desde.fecha, hoy: hoy))")
                            .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    if lectura.saldo.estimado, lectura.saldo.total != nil { PastillaEstimadoFinanzas() }
                }
                if lectura.saldo.total == nil, !lectura.saldo.cuentasSinDato.isEmpty {
                    AvisoEnLinea("La caja es «Sin dato» porque no se sabe el saldo de "
                                 + lectura.saldo.cuentasSinDato.map { "«\($0.nombre)»" }.joined(separator: ", ")
                                 + ". Importa su extracto o escribe su saldo inicial en su ficha.", estado: .atencion)
                }
            }
        }
    }

    /// «Alquiler · −663,00 €; Remesa · +3.400,00 €», o «Sin movimientos ese día».
    private func movimientosDelDia(_ d: LocalDate) -> String {
        let del = lectura.movimientos.filter { $0.fecha == d }
        guard !del.isEmpty else { return "Sin movimientos ese día" }
        let partes = del.prefix(3).map { m in
            let c = m.concepto.count > 34 ? String(m.concepto.prefix(34)) + "…" : m.concepto
            return "\(FormatoFicha.capital(c.lowercased())) · \(TextoFinanzas.eurosConSigno(m.importe))"
        }
        return partes.joined(separator: "; ") + (del.count > 3 ? "; y \(del.count - 3) más" : "")
    }
}

/// «Estimado» con borde discontinuo (maqueta M2-Hoy): la cifra no sale de un extracto.
struct PastillaEstimadoFinanzas: View {
    var body: some View {
        Text("Estimado")
            .tlsTexto(TLSTipo.secundario)
            .foregroundStyle(TLSPaleta.texto.color)
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .overlay(Capsule(style: .circular).strokeBorder(TLSPaleta.textoSecundario.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .accessibilityLabel("Estimado: no sale de un extracto")
    }
}

/// 1S · 1M · 3M · 1A · Todo.
struct SelectorPeriodoCajaFinanzas: View {
    @Binding var rango: RangoCaja

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RangoCaja.allCases) { r in
                let elegido = r == rango
                Button { rango = r } label: {
                    Text(r.rawValue)
                        .tlsTexto(TLSTipo.interfazFuerte)
                        .frame(minWidth: 34, minHeight: TLSAltura.objetivoMinimo)
                        .padding(.horizontal, 6)
                        .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .foregroundStyle(elegido ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                .background(Capsule(style: .circular).fill(elegido ? TLSPaleta.principal.color : Color.clear))
                .accessibilityLabel(TextoFinanzas.nombreLargo(r))
                .accessibilityAddTraits(elegido ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("finanzas.caja.periodo.\(r.rawValue)")
            }
        }
        .padding(2)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Periodo de la gráfica")
    }
}

/// La gráfica (Swift Charts): área degradada y línea; discontinua lo estimado. Al pasar el puntero o con ← → se ve el
/// saldo de un día; Esc vuelve a hoy.
private struct GraficaCajaFinanzas: View {
    let tramos: [TramoCajaFinanzas]
    let puntos: [PuntoCajaFinanzas]
    @Binding var elegida: LocalDate?
    let hoy: LocalDate
    let descripcion: String
    @State private var fechaPuntero: Date?
    @FocusState private var enfocada: Bool

    var body: some View {
        let minimo = puntos.map(\.euros).min() ?? 0
        let maximo = puntos.map(\.euros).max() ?? 0
        let margen = max((maximo - minimo) * 0.12, 50)
        let base = minimo - margen
        let dominio = base...(maximo + margen)
        let marcas = Self.marcas(puntos)
        let marcado = elegida.flatMap { d in puntos.first { $0.dia == d } }
        let ultimo = puntos.last
        Chart {
            ForEach(tramos) { t in
                ForEach(t.puntos) { p in
                    AreaMark(x: .value("Día", p.fecha), yStart: .value("Base", base), yEnd: .value("Saldo", p.euros),
                             series: .value("Tramo", "a\(t.id)"))
                        .foregroundStyle(LinearGradient(colors: [TLSPaleta.principal.color.opacity(0.22), TLSPaleta.principal.color.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Día", p.fecha), y: .value("Saldo", p.euros), series: .value("Tramo", "l\(t.id)"))
                        .foregroundStyle(TLSPaleta.principal.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: t.estimado ? [4, 4] : []))
                }
            }
            if let marcado {
                RuleMark(x: .value("Día", marcado.fecha))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Día", marcado.fecha), y: .value("Saldo", marcado.euros))
                    .foregroundStyle(TLSPaleta.principal.color)
                    .symbolSize(70)
            } else if let ultimo {
                PointMark(x: .value("Día", ultimo.fecha), y: .value("Saldo", ultimo.euros))
                    .foregroundStyle(TLSPaleta.principal.color.opacity(0.18))
                    .symbolSize(320)
                PointMark(x: .value("Día", ultimo.fecha), y: .value("Saldo", ultimo.euros))
                    .foregroundStyle(TLSPaleta.principal.color)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: dominio)
        .chartXAxis {
            AxisMarks(values: marcas.map(\.fecha)) { valor in
                AxisValueLabel {
                    if let d = valor.as(Date.self) {
                        Text(FormatoFicha.fechaCorta(LocalDate(date: d), hoy: hoy))
                            .tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { valor in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(TLSPaleta.separador.color)
                AxisValueLabel {
                    if let v = valor.as(Double.self) {
                        Text(FormatoBase.euros(v, redondo: true))
                            .tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
            }
        }
        .chartPlotStyle { $0.clipped() }
        .chartXSelection(value: $fechaPuntero)
        .onChange(of: fechaPuntero) { _, nuevo in
            guard let nuevo else { return }
            elegida = Self.cercano(nuevo, en: puntos)?.dia
        }
        .focusable()
        .focused($enfocada)
        .tlsFocoPropio(radio: TLSRadio.bloque)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .escape, .home, .end], phases: .down) { tecla in
            mover(tecla.key)
            return .handled
        }
        .onHover { dentro in if !dentro { fechaPuntero = nil; if !enfocada { elegida = nil } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gráfica de la caja. \(descripcion)")
        .accessibilityValue(marcado.map { "\(FormatoFicha.fechaConDia($0.dia, hoy: hoy)): \(FormatoBase.euros($0.euros))" } ?? "Hoy")
        .accessibilityHint("Usa las flechas izquierda y derecha para recorrerla, o «Ver como tabla».")
        .accessibilityAdjustableAction { direccion in
            switch direccion {
            case .increment: mover(.rightArrow)
            case .decrement: mover(.leftArrow)
            @unknown default: break
            }
        }
    }

    private func mover(_ tecla: KeyEquivalent) {
        guard !puntos.isEmpty else { return }
        let actual = elegida.flatMap { d in puntos.firstIndex { $0.dia == d } } ?? puntos.count - 1
        switch tecla {
        case .leftArrow: elegida = puntos[max(0, actual - 1)].dia
        case .rightArrow: elegida = puntos[min(puntos.count - 1, actual + 1)].dia
        case .home: elegida = puntos.first?.dia
        case .end: elegida = puntos.last?.dia
        default: elegida = nil
        }
    }

    /// Cuatro marcas del eje: el primero, a un tercio, a dos tercios y el último.
    static func marcas(_ p: [PuntoCajaFinanzas]) -> [PuntoCajaFinanzas] {
        guard p.count > 3 else { return p }
        let n = p.count - 1
        return [0, n / 3, 2 * n / 3, n].map { p[$0] }
    }

    static func cercano(_ fecha: Date, en p: [PuntoCajaFinanzas]) -> PuntoCajaFinanzas? {
        p.min { abs($0.fecha.timeIntervalSince(fecha)) < abs($1.fecha.timeIntervalSince(fecha)) }
    }
}

/// La misma serie como tabla (Fecha · Saldo · Nota), de lo más reciente a lo más antiguo.
private struct TablaCajaFinanzas: View {
    let serie: [PuntoCaja]
    let lectura: LecturaFinanzas

    var body: some View {
        let hoy = lectura.hoy
        let porDia = Dictionary(grouping: lectura.movimientos, by: \.fecha)
        VStack(spacing: 0) {
            HStack(spacing: TLSEspacio.e12) {
                Text("Fecha").frame(width: 120, alignment: .leading)
                Text("Saldo").frame(width: 120, alignment: .trailing)
                Text("Nota").frame(maxWidth: .infinity, alignment: .leading)
            }
            .tlsTexto(TLSTipo.rotulo)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .padding(.horizontal, TLSEspacio.e12)
            .frame(minHeight: TLSAltura.cabeceraTabla)
            .background(TLSPaleta.bandeja.color)
            .accessibilityHidden(true)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(serie.reversed(), id: \.fecha) { p in
                        let nota = p.estimado ? "Estimado" : (porDia[p.fecha] ?? []).map { m in
                            "\(FormatoFicha.capital(m.concepto.lowercased())) · \(TextoFinanzas.eurosConSigno(m.importe))"
                        }.joined(separator: "; ")
                        HStack(spacing: TLSEspacio.e12) {
                            Text(FormatoFicha.fechaConDia(p.fecha, hoy: hoy)).frame(width: 120, alignment: .leading)
                            Text(TextoFinanzas.euros(p.saldo)).tlsTexto(TLSTipo.cifraFila).frame(width: 120, alignment: .trailing)
                            Text(nota).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .padding(.horizontal, TLSEspacio.e12)
                        .frame(minHeight: TLSAltura.filaTablaCompacta)
                        .overlay(alignment: .top) { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).strokeBorder(TLSPaleta.separador.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saldo de la caja por día")
    }
}

// MARK: - Meses de caja y cuentas

/// Los meses que aguanta la caja frente a su meta (FIN-RUNWAY de `Metas.md`). La primera vez, sin meta decidida, el
/// valor no se enseña (PLAN §6.5): se pide antes la meta en Control.
private struct TarjetaMesesDeCaja: View {
    let lectura: LecturaFinanzas
    let fila: FilaControl?
    @Bindable var modelo: ModeloFinanzas
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Mosaico("Meses de caja", icono: "hourglass", pie: pie) {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                if let fila, !fila.valorVisible {
                    Text("Fija la meta antes de ver el dato")
                        .tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    Button("Fijar la meta") { nav?.cambiarPestana(PestanaArea.control.rawValue) }
                        .tlsBoton(.secundario)
                } else {
                    Text(valor)
                        .tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityIdentifier("finanzas.caja.meses")
                    HStack(spacing: TLSEspacio.e8) {
                        RhythmBadge(fila?.ritmo ?? .sinMeta)
                        Text(metaTexto).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    if lectura.runway.estimado, lectura.runway.meses != nil { PastillaEstimadoFinanzas() }
                    if fila == nil, lectura.metas != nil {
                        Text("No está en tus metas. \(ModeloFinanzas.propuestaRunway): la decides tú en Control.")
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Medirlo en Control") {
                            Task {
                                if await modelo.anadirRunwayAMetas(deshacer: undoManager) { nav?.cambiarPestana(PestanaArea.control.rawValue) }
                            }
                        }
                        .tlsBoton(.secundario)
                        .disabled(modelo.motivoSoloLectura != nil)
                        .help(modelo.motivoSoloLectura ?? "Añade los meses de caja a la nota Metas, aún sin meta: la fijas tú")
                        .accessibilityIdentifier("finanzas.caja.medirRunway")
                    }
                }
            }
        }
        .frame(minHeight: 156)
    }

    private var valor: String {
        if let t = fila?.lectura.textoValor { return t }
        return TextoFinanzas.meses(lectura.runway.meses)
    }

    private var metaTexto: String {
        guard let fila else { return "Sin meta" }
        guard fila.tieneMeta else { return "Sin meta" }
        return "Meta \(fila.textoMeta)" + (fila.alerta.map { " · alerta " + Umbral(texto: $0).textoVisible } ?? "")
    }

    /// De dónde sale: lo mismo que dice el número clave (para que la pantalla no dé dos cifras); sin número clave, la
    /// salida media de Tesorería o por qué no hay dato.
    private var pie: String? {
        let r = lectura.runway
        if let f = fila?.lectura.fuente { return f }
        if r.meses == nil { return r.motivo }
        if let salida = r.salidaMedia, !r.mesesUsados.isEmpty {
            return "Caja ÷ salida media de \(TextoFinanzas.euros(salida)) al mes (\(r.mesesUsados.map(Self.mes).joined(separator: ", ")))"
        }
        return nil
    }

    /// `2026-07` → «jul».
    static func mes(_ m: String) -> String {
        guard let n = Int(m.suffix(2)), (1...12).contains(n) else { return m }
        return FormatoFicha.meses[n - 1]
    }
}

/// Cada cuenta con su saldo y de dónde sale; un clic abre su Banco.
private struct TarjetaCuentasBanco: View {
    let lectura: LecturaFinanzas
    @Environment(\.navegar) private var navegar

    var body: some View {
        let hoy = lectura.hoy
        Mosaico("Cuentas", icono: "building.columns") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lectura.saldo.cuentas, id: \.cuenta.id) { s in
                    Button {
                        navegar(.banco(s.cuenta.carpeta), modo: .automatico)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.cuenta.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                                    .lineLimit(2)
                                Text(TextoFinanzas.fuente(s, hoy: hoy)).tlsTexto(TLSTipo.secundario)
                                    .foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                            }
                            Spacer(minLength: TLSEspacio.e8)
                            Text(TextoFinanzas.euros(s.saldo)).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Abrir el Banco de esta cuenta")
                    .accessibilityLabel("\(s.cuenta.nombre): \(TextoFinanzas.euros(s.saldo)). \(TextoFinanzas.fuente(s, hoy: hoy))")
                    .accessibilityHint("Abre el Banco de esta cuenta")
                }
                if lectura.saldo.cuentas.isEmpty {
                    Text("No hay cuentas del banco en Finanzas.").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
    }
}
