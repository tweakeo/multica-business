import Charts
import SwiftUI
import TLSCore
import TLSDesign

/// Calendario (§4.4): el mes o la semana (con sus horas) sobre la fecha que elijas (`fecha`, `vence`,
/// `siguiente_fecha`…), con la línea de hoy y una bandeja «Sin fecha (n)». Arrastrar a un día cambia la fecha;
/// sin arrastrar, se elige la ficha y se mueve con «Mover a» (Hoy, Mañana, +1 semana, un día concreto o
/// quitarla), también con el teclado.
struct VistaCalendarioBase: View {
    @Bindable var modelo: BaseModelo
    @Environment(\.navegar) private var navegar
    @State private var diaElegido = Date()
    @State private var encima: String?

    private var clave: String { modelo.config.fechaCalendario ?? modelo.coleccion.fechaCalendario ?? "fecha" }
    private var columna: ColumnaBase { modelo.coleccion.columna(clave) ?? ColumnaBase(clave, clave, .fecha) }

    var body: some View {
        let filas = modelo.filas
        let conFecha = filas.filter { $0.fecha(columna) != nil }
        let sinFecha = filas.filter { $0.fecha(columna) == nil }
        let mes = modelo.mesCalendario ?? (modelo.hoy.year, modelo.hoy.month)
        // La semana elegida o, si se movió el mes, la primera de ese mes; si no, la de hoy.
        let lunes = modelo.semanaCalendario
            ?? modelo.mesCalendario.flatMap { LocalDate(year: $0.year, month: $0.month, day: 1) }.map { FormatoBase.lunes(de: $0) }
            ?? FormatoBase.lunes(de: modelo.hoy)
        let semana = escala == .semana
        HStack(alignment: .top, spacing: TLSEspacio.e16) {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                cabecera(mes, lunes: lunes)
                if semana {
                    SemanaCalendario(modelo: modelo, lunes: lunes, columna: columna, filas: conFecha)
                } else {
                    ScrollView {
                        rejilla(mes, conFecha: conFecha)
                    }
                }
                if let id = modelo.elegidaCalendario, let f = modelo.fila(id) {
                    barraMover(f)
                }
            }
            .frame(maxWidth: .infinity)
            bandeja(sinFecha)
                .frame(width: 240)
        }
    }

    private var escala: EscalaCalendario { modelo.config.escala(en: modelo.coleccion) }

    // MARK: Mes

    private func cabecera(_ mes: (year: Int, month: Int), lunes: LocalDate) -> some View {
        let semana = escala == .semana
        return HStack(spacing: TLSEspacio.e8) {
            Text(semana ? FormatoBase.semana(lunes) : FormatoBase.mes(mes.year, mes.month).capitalizedPrimera)
                .tlsTexto(TLSTipo.tituloSeccion)
                .foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Button { semana ? moverSemana(lunes, -7) : mover(mes, -1) } label: { Image(systemName: "chevron.left") }
                .tlsBoton(.secundario).accessibilityLabel(semana ? "Semana anterior" : "Mes anterior")
            Button("Hoy") { modelo.mesCalendario = nil; modelo.semanaCalendario = nil }.tlsBoton(.secundario)
            Button { semana ? moverSemana(lunes, 7) : mover(mes, 1) } label: { Image(systemName: "chevron.right") }
                .tlsBoton(.secundario).accessibilityLabel(semana ? "Semana siguiente" : "Mes siguiente")
            PestanasCapsula(seleccion: Binding(get: { escala.rawValue },
                                               set: { modelo.config.escalaCalendario = EscalaCalendario(rawValue: $0) }),
                            pestanas: EscalaCalendario.allCases.map { PestanaCapsula(id: $0.rawValue, titulo: $0.nombre) },
                            atajosControl: false)
                .fixedSize()
                .accessibilityLabel("Ver el mes o la semana")
            Spacer(minLength: 0)
            Text("Fecha que se usa: \(columna.etiqueta.lowercased()) · la línea marca hoy")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
        }
    }

    private func moverSemana(_ lunes: LocalDate, _ dias: Int) {
        let nuevo = lunes.adding(days: dias)
        modelo.semanaCalendario = nuevo
        modelo.mesCalendario = (nuevo.year, nuevo.month)
    }

    private func mover(_ mes: (year: Int, month: Int), _ paso: Int) {
        var m = mes.month + paso, y = mes.year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        modelo.mesCalendario = (y, m)
        modelo.semanaCalendario = nil
    }

    private func rejilla(_ mes: (year: Int, month: Int), conFecha: [FilaBase]) -> some View {
        let primero = LocalDate(year: mes.year, month: mes.month, day: 1) ?? modelo.hoy
        let inicio = primero.adding(days: -(primero.weekday - 1))
        let dias = (0..<42).map { inicio.adding(days: $0) }
        let ultimoDelMes = dias.lastIndex { $0.month == mes.month && $0.year == mes.year } ?? 34
        let semanas = (ultimoDelMes + 7) / 7
        var porDia: [LocalDate: [FilaBase]] = [:]
        for f in conFecha { if let d = f.fecha(columna) { porDia[d, default: []].append(f) } }
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(FormatoBase.diasSemana, id: \.self) { d in
                    Text(d).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(0..<semanas, id: \.self) { w in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let dia = dias[w * 7 + d]
                        celdaDia(dia, enMes: dia.month == mes.month, filas: porDia[dia] ?? [])
                    }
                }
            }
        }
    }

    private func celdaDia(_ dia: LocalDate, enMes: Bool, filas: [FilaBase]) -> some View {
        let esHoy = dia == modelo.hoy
        let objetivo = encima == dia.description
        let forma = RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            Text(dia.day == 1 ? "\(dia.day) \(FormatoBase.meses[dia.month - 1])" + (esHoy ? " · hoy" : "")
                 : "\(dia.day)" + (esHoy ? " · hoy" : ""))
                .tlsTexto(esHoy ? TLSTipo.interfazFuerte : TLSTipo.secundario)
                .foregroundStyle(enMes ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
            ForEach(filas.prefix(3)) { f in evento(f) }
            if filas.count > 3 {
                Text("y \(filas.count - 3) más").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(forma.fill(enMes ? TLSPaleta.superficie.color : Color.clear))
        .overlay(alignment: .top) {
            if esHoy { Rectangle().fill(TLSPaleta.principal.color).frame(height: 2).accessibilityHidden(true) }
        }
        .overlay(forma.strokeBorder(objetivo ? TLSPaleta.principal.color : TLSPaleta.separador.color, lineWidth: objetivo ? 2 : 1))
        .dropDestination(for: String.self) { ids, _ in
            guard let f = modelo.filaSoltada(ids) else { return false }
            Task { await modelo.ponerFecha(f, dia) }
            return true
        } isTargeted: { dentro in
            if dentro { encima = dia.description } else if encima == dia.description { encima = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(FormatoBase.fechaConDia(dia))\(esHoy ? ", hoy" : ""), \(FormatoBase.cuenta(filas.count, "ficha", "fichas"))")
    }

    private func evento(_ f: FilaBase) -> some View {
        let elegida = modelo.elegidaCalendario == f.id
        return Button {
            modelo.elegidaCalendario = elegida ? nil : f.id
            modelo.seleccion = [f.id]
        } label: {
            Text(f.titulo)
                .tlsTexto(TLSTipo.secundario.peso(500))
                .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(elegida ? TLSPaleta.principal.color : TLSPaleta.principalSuave.color))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tlsFocoPropio(radio: 6)
        .draggable(modelo.textoArrastre(f))
        .vistaPrevia(ruta: f.rutaPreviaAlPasar, sesion: modelo.sesion)
        .simultaneousGesture(TapGesture(count: 2).onEnded { modelo.abrir(f, navegar: navegar) })
        .onKeyPress(.space) { modelo.vistaPrevia(f); return .handled }
        .contextMenu {
            Button("Abrir") { modelo.abrir(f, modo: .entrar, navegar: navegar) }
            Button("Vista previa") { modelo.vistaPrevia(f) }
            Button("Quitar la fecha") { Task { await modelo.ponerFecha(f, nil) } }
        }
        .accessibilityLabel(f.titulo)
        .accessibilityHint("Elige la ficha para moverla de día")
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    /// «Mover a» la ficha elegida: con el teclado y sin arrastrar.
    private func barraMover(_ f: FilaBase) -> some View {
        HStack(spacing: TLSEspacio.e8) {
            Text("«\(f.titulo)»").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
            Text("Mover a").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            ForEach([("Hoy", 0), ("Mañana", 1), ("+1 semana", 7)], id: \.0) { nombre, dias in
                Button(nombre) { Task { await modelo.ponerFecha(f, modelo.hoy.adding(days: dias)); modelo.elegidaCalendario = nil } }
                    .tlsBoton(.secundario)
            }
            DatePicker("Otro día", selection: $diaElegido, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("Otro día")
            Button("Poner") {
                Task { await modelo.ponerFecha(f, LocalDate(date: diaElegido)); modelo.elegidaCalendario = nil }
            }
            .tlsBoton(.principal, alto: 32)
            Button("Quitar la fecha") { Task { await modelo.ponerFecha(f, nil); modelo.elegidaCalendario = nil } }
                .tlsBoton(.enlace)
            Spacer(minLength: 0)
        }
        .padding(TLSEspacio.e8)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mover \(f.titulo)")
    }

    // MARK: Sin fecha

    private func bandeja(_ sinFecha: [FilaBase]) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Sin fecha (\(sinFecha.count))")
                .tlsTexto(TLSTipo.tituloModulo)
                .foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(sinFecha) { f in
                        let elegida = modelo.elegidaCalendario == f.id
                        Button {
                            modelo.elegidaCalendario = elegida ? nil : f.id
                            modelo.seleccion = [f.id]
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.titulo).tlsTexto(TLSTipo.interfazMedia).lineLimit(2)
                                if let e = modelo.coleccion.columnaEstado.map({ f.textoCelda($0, hoy: modelo.hoy) }), !e.isEmpty {
                                    Text(e).tlsTexto(TLSTipo.secundario)
                                }
                            }
                            .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                                .fill(elegida ? TLSPaleta.principal.color : TLSPaleta.superficie.color))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tlsFocoPropio(radio: TLSRadio.fila)
                        .draggable(modelo.textoArrastre(f))
                        .accessibilityHint("Elige la ficha y ponle fecha con «Mover a»")
                        .accessibilityAddTraits(elegida ? .isSelected : [])
                    }
                }
            }
            Text("Arrastra una ficha a un día, o elígela y pon el día en «Mover a». Soltarla aquí le quita la fecha.")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .dropDestination(for: String.self) { ids, _ in
            guard let f = modelo.filaSoltada(ids), f.fecha(columna) != nil else { return false }
            Task { await modelo.ponerFecha(f, nil) }
            return true
        }
        .accessibilityElement(children: .contain)
    }
}

/// Cronograma (§4.4): barras de inicio a fin por ficha (Swift Charts) y la línea de hoy.
struct VistaCronogramaBase: View {
    @Bindable var modelo: BaseModelo

    var body: some View {
        let (ini, fin) = modelo.coleccion.cronograma ?? ("inicio", "fin")
        let filas = modelo.filas
        let barras: [(FilaBase, Date, Date)] = filas.compactMap { f in
            guard let a = f.fecha(ini) ?? f.fecha(fin) else { return nil }
            let b = f.fecha(fin) ?? a
            return (f, a.date(), max(b, a).adding(days: 1).date())
        }
        let sin = filas.count - barras.count
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            if barras.isEmpty {
                VacioExplicado(icono: "chart.bar.xaxis", titulo: "Ninguna tiene fechas",
                               porQue: "El cronograma pinta cada ficha de su inicio a su fin. Ponles fecha en la tabla o en su ficha.")
            } else {
                Chart {
                    ForEach(barras, id: \.0.id) { f, a, b in
                        BarMark(xStart: .value("Inicio", a), xEnd: .value("Fin", b), y: .value("Ficha", f.titulo))
                            .foregroundStyle(TLSPaleta.principal.color)
                            .cornerRadius(4)
                    }
                    // La línea «ahora» en magenta, 2 pt (§1.5): una de las pocas cosas que lo llevan.
                    RuleMark(x: .value("Hoy", modelo.hoy.date()))
                        .foregroundStyle(MarcaAhora.color)
                        .lineStyle(StrokeStyle(lineWidth: MarcaAhora.grosor))
                        .annotation(position: .top, alignment: .leading) {
                            Text("hoy").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(minHeight: CGFloat(max(160, barras.count * 32)))
                .accessibilityLabel("Cronograma de \(FormatoBase.cuenta(barras.count, "ficha", "fichas"))")
            }
            if sin > 0 {
                Text("\(FormatoBase.cuenta(sin, "ficha no tiene fechas y no sale", "fichas no tienen fechas y no salen")) en el cronograma.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }
}

extension String {
    /// «octubre de 2026» → «Octubre de 2026».
    var capitalizedPrimera: String { prefix(1).uppercased() + dropFirst() }
}
