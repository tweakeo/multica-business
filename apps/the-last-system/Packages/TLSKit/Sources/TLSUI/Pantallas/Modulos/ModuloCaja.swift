import Charts
import SwiftUI
import TLSCore
import TLSDesign

/// El módulo Caja (DISENO §6 «Gráficas», M2-Hoy): el saldo de hoy, los meses de caja y la gráfica con sus periodos
/// 1S · 1M · 3M · 1A · Todo. Al pasar el puntero (o con ← y →) se ve el saldo de ese día; al arrastrar, la diferencia
/// del tramo. Lo estimado va en línea discontinua y un día sin dato corta la línea (no baja a 0). «Ver como tabla» da
/// lo mismo en filas para quien no ve la gráfica.
struct ModuloCaja: View {
    let caja: DatosCaja
    let tamano: TamanoMosaico
    @State private var rango: RangoCaja = .mes
    @State private var hover: LocalDate?
    @State private var fijado: LocalDate?
    @State private var tramo: (desde: LocalDate, hasta: LocalDate)?
    @State private var tabla = false
    @FocusState private var enfocada: Bool
    @Environment(\.navegar) private var navegar

    /// Un punto de la gráfica (en euros) y el tramo al que pertenece (un corte o un cambio a estimado abre otro).
    struct Punto: Identifiable, Hashable {
        var id: String { "\(dia)-\(tramo)" }
        let dia: LocalDate
        let fecha: Date
        let euros: Double
        let tramo: Int
        let estimado: Bool
    }

    static let utc = TimeZone(identifier: "UTC")!

    var serie: [PuntoCaja] { caja.series[rango] ?? [] }

    /// Los puntos en tramos continuos: un día sin saldo corta; el paso de estimado a real repite el punto de unión.
    static func puntos(_ serie: [PuntoCaja]) -> [Punto] {
        var out: [Punto] = []
        var tramo = 0
        var anterior: PuntoCaja?
        for p in serie {
            guard let s = p.saldo else {
                if anterior?.saldo != nil { tramo += 1 }
                anterior = p
                continue
            }
            let e = Double(s) / 100
            if let a = anterior, let sa = a.saldo, a.estimado != p.estimado {
                tramo += 1
                out.append(Punto(dia: a.fecha, fecha: a.fecha.date(timeZone: utc), euros: Double(sa) / 100, tramo: tramo, estimado: p.estimado))
            }
            out.append(Punto(dia: p.fecha, fecha: p.fecha.date(timeZone: utc), euros: e, tramo: tramo, estimado: p.estimado))
            anterior = p
        }
        return out
    }

    var body: some View {
        if caja.cuentas == 0 || serie.allSatisfy({ $0.saldo == nil }) && caja.saldo == nil {
            sinDatos
        } else {
            VStack(alignment: .leading, spacing: 8) {
                cifra
                if tamano != .mediano { periodos }
                if tabla { tablaSaldos } else { grafica }
                if tamano != .mediano {
                    Button(tabla ? "Ver como gráfica" : "Ver como tabla") { tabla.toggle() }.tlsBoton(.enlace)
                }
            }
        }
    }

    private var sinDatos: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: TLSEstado.sinDato.simbolo).foregroundStyle(TLSPaleta.sinDato.color).accessibilityHidden(true)
                Text(caja.motivo ?? "Sin datos del banco: importa un extracto.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
            }
            Button("Importar extracto") { navegar(.banco(nil), modo: .automatico) }.tlsBoton(.secundario)
        }
    }

    // MARK: Cifra de arriba

    private var seleccion: LocalDate? { hover ?? fijado }

    private var cifra: some View {
        let (rotulo, valor, l1, l2) = textos
        return VStack(alignment: .leading, spacing: 2) {
            Text(rotulo).tlsTexto(TLSTipo.secundario.peso(600)).foregroundStyle(TLSPaleta.textoSecundario.color)
            Text(valor).tlsTexto(tamano == .mediano ? TLSTipo.cifraMedia : TLSTipo.cifraGrande)
                .foregroundStyle(TLSPaleta.texto.color).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 8) {
                if let l1 { Text(l1).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1) }
                if seleccion == nil, tramo == nil, let r = caja.runwayTexto {
                    PastillaEstado(estadoRunway, palabra: r)
                }
            }
            if let l2 { Text(l2).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1) }
        }
        .accessibilityElement(children: .combine)
    }

    private var estadoRunway: TLSEstado {
        switch caja.estadoRunway {
        case .bien: .bien
        case .atencion: .atencion
        case .mal: .mal
        default: .sinDato
        }
    }

    /// Rótulo, cifra y dos líneas, según lo que se mire.
    private var textos: (String, String, String?, String?) {
        let s = serie
        if let t = tramo, let a = s.first(where: { $0.fecha == t.desde }), let b = s.first(where: { $0.fecha == t.hasta }) {
            guard let sa = a.saldo, let sb = b.saldo else {
                return ("Diferencia", "Sin dato", "Algún día del tramo no tiene saldo.", nil)
            }
            guard PuntoCaja.hayMovimientos(s, desde: t.desde, hasta: t.hasta) else {
                return ("Diferencia", "Sin dato", "No hay movimientos del banco en este tramo: falta el extracto.", nil)
            }
            return ("Diferencia", Self.conSigno(sb - sa), "entre el \(Self.corta(t.desde)) y el \(Self.corta(t.hasta))", nil)
        }
        if let d = seleccion, let p = s.first(where: { $0.fecha == d }) {
            let rot = d == s.last?.fecha ? "Hoy · \(FormatoBase.fechaConDia(d))" : FormatoBase.fechaConDia(d)
            return (rot, p.saldo.map(DineroExacto.euros) ?? "Sin dato", p.saldo == nil ? "Ese día falta el saldo de alguna cuenta." : (p.estimado ? "Estimado" : nil), nil)
        }
        let hoy = s.last?.fecha
        let rot = hoy.map { "Hoy · \(FormatoBase.fechaConDia($0))" } ?? "Hoy"
        let linea = Self.variacion(s)
        let estimado = s.last(where: { $0.saldo != nil })?.estimado == true
        return (rot, caja.saldoTexto, linea, caja.motivo ?? (estimado ? "Estimado con el saldo inicial de las cuentas: falta el extracto del banco." : nil))
    }

    /// «+1.234,50 € · 4,9 % desde el 21 jul», «Sin cambios desde…» o, sin ningún movimiento del banco en el tramo,
    /// «Sin dato: falta el extracto de este periodo» (regla 3: nunca un 0 inventado). `nil` con menos de dos días.
    static func variacion(_ s: [PuntoCaja]) -> String? {
        var linea: String?
        if let primero = s.first(where: { $0.saldo != nil }), let ultimo = s.last(where: { $0.saldo != nil }),
           primero.fecha < ultimo.fecha, let a = primero.saldo, let b = ultimo.saldo {
            if !PuntoCaja.hayMovimientos(s, desde: primero.fecha, hasta: ultimo.fecha) {
                // Sin movimientos del banco no se sabe si cambió (regla 3: nunca un 0 inventado).
                linea = "Sin dato: falta el extracto de este periodo"
            } else if a == b {
                linea = "Sin cambios desde el \(Self.corta(primero.fecha))"
            } else {
                let pct = a != 0 ? Double(b - a) / Double(abs(a)) * 100 : nil
                linea = Self.conSigno(b - a) + (pct.map { " · \(FormatoBase.cifra($0, decimales: 1)) %" } ?? "") + " desde el \(Self.corta(primero.fecha))"
            }
        }
        return linea
    }

    static func conSigno(_ c: Int) -> String { (c > 0 ? "+" : "") + DineroExacto.euros(c) }
    static func corta(_ d: LocalDate) -> String { "\(d.day) \(FormatoBase.meses[d.month - 1])" }

    // MARK: Periodos

    private var periodos: some View {
        HStack(spacing: 4) {
            ForEach(RangoCaja.allCases) { r in
                Button(r.rawValue) {
                    rango = r
                    hover = nil; fijado = nil; tramo = nil
                }
                .buttonStyle(.plain)
                .tlsTexto(TLSTipo.interfazMedia)
                .padding(.horizontal, 10)
                .frame(minHeight: TLSAltura.objetivoMinimo)
                .foregroundStyle(r == rango ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                .background(Capsule(style: .circular).fill(r == rango ? TLSPaleta.principal.color : Color.clear))
                .contentShape(Capsule(style: .circular))
                .accessibilityLabel(r.titulo)
                .accessibilityAddTraits(r == rango ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Periodo de la gráfica")
    }

    // MARK: Gráfica

    private var grafica: some View {
        let pts = Self.puntos(serie)
        let valores = pts.map(\.euros)
        let minimo = (valores.min() ?? 0), maximo = (valores.max() ?? 0)
        let margen = max((maximo - minimo) * 0.12, 50)
        let dominio = (minimo - margen)...(maximo + margen)
        let sel = seleccion.flatMap { d in pts.last { $0.dia == d } }
        let azul = TLSPaleta.principal.color
        return Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("Día", p.fecha), yStart: .value("Base", dominio.lowerBound), yEnd: .value("Saldo", p.euros),
                         series: .value("Tramo", p.tramo))
                    .foregroundStyle(LinearGradient(colors: [azul.opacity(0.24), azul.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Día", p.fecha), y: .value("Saldo", p.euros), series: .value("Tramo", p.tramo))
                    .foregroundStyle(azul)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: p.estimado ? [4, 4] : []))
                    .interpolationMethod(.monotone)
            }
            if let t = tramo {
                RectangleMark(xStart: .value("Desde", t.desde.date(timeZone: Self.utc)), xEnd: .value("Hasta", t.hasta.date(timeZone: Self.utc)))
                    .foregroundStyle(TLSPaleta.principalSuave.color.opacity(0.6))
            }
            if let p = sel {
                RuleMark(x: .value("Día", p.fecha)).foregroundStyle(TLSPaleta.textoSecundario.color).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Día", p.fecha), y: .value("Saldo", p.euros))
                    .symbolSize(70).foregroundStyle(azul)
            }
        }
        .chartYScale(domain: dominio)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(TLSPaleta.separador.color)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(FormatoBase.euros(d, redondo: true)).font(TLSTipo.secundario.font()) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: tamano == .mediano ? 2 : 4)) { v in
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        let l = LocalDate(date: d, timeZone: Self.utc)
                        Text(Self.corta(l)).font(TLSTipo.secundario.font())
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { fase in
                        switch fase {
                        case .active(let p): hover = dia(en: p, proxy: proxy, geo: geo, pts: pts)
                        case .ended: hover = nil
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard abs(v.translation.width) > 6,
                                  let a = dia(en: v.startLocation, proxy: proxy, geo: geo, pts: pts),
                                  let b = dia(en: v.location, proxy: proxy, geo: geo, pts: pts), a != b else { return }
                            tramo = (min(a, b), max(a, b))
                        }
                        .onEnded { v in
                            if abs(v.translation.width) <= 6 {
                                tramo = nil
                                let d = dia(en: v.location, proxy: proxy, geo: geo, pts: pts)
                                fijado = fijado == d ? nil : d
                            }
                        })
            }
        }
        .frame(minHeight: tamano == .mediano ? 60 : 110, maxHeight: .infinity)
        .focusable()
        .focused($enfocada)
        .focusEffectDisabled()
        .tlsAnilloFoco(enfocada, radio: 8)
        .onKeyPress(.leftArrow) { moverSeleccion(-1, pts: pts); return .handled }
        .onKeyPress(.rightArrow) { moverSeleccion(1, pts: pts); return .handled }
        .onKeyPress(.escape) { fijado = nil; tramo = nil; return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gráfica de la caja, \(rango.titulo.lowercased())")
        .accessibilityValue(textos.1 + (textos.2.map { ", \($0)" } ?? ""))
        .accessibilityHint("Usa las flechas izquierda y derecha para recorrerla, o «Ver como tabla».")
    }

    private func dia(en punto: CGPoint, proxy: ChartProxy, geo: GeometryProxy, pts: [Punto]) -> LocalDate? {
        guard let plot = proxy.plotFrame else { return nil }
        let x = punto.x - geo[plot].origin.x
        guard let fecha: Date = proxy.value(atX: x) else { return nil }
        return pts.min { abs($0.fecha.timeIntervalSince(fecha)) < abs($1.fecha.timeIntervalSince(fecha)) }?.dia
    }

    private func moverSeleccion(_ paso: Int, pts: [Punto]) {
        let dias = Array(Set(pts.map(\.dia))).sorted()
        guard !dias.isEmpty else { return }
        tramo = nil
        guard let actual = fijado, let i = dias.firstIndex(of: actual) else {
            fijado = dias.last
            return
        }
        fijado = dias[min(max(0, i + paso), dias.count - 1)]
    }

    // MARK: Tabla

    private var tablaSaldos: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(serie.reversed(), id: \.fecha) { p in
                    HStack {
                        Text(FormatoBase.fechaConDia(p.fecha)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        Spacer()
                        if p.estimado { Text("Estimado").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
                        Text(p.saldo.map(DineroExacto.euros) ?? "Sin dato").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    Divider().overlay(TLSPaleta.separador.color)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityLabel("Saldo de la caja, \(rango.titulo.lowercased())")
    }
}
