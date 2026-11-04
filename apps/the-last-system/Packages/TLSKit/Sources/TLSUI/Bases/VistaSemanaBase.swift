import SwiftUI
import TLSCore
import TLSDesign

/// La semana del calendario (§4.4; Reuniones abre así, §4.2): siete columnas con sus horas (de 7 a 21), arriba
/// lo que no tiene hora («Todo el día») y en el día de hoy la línea «ahora» con su punto magenta. Arrastrar a
/// otro día cambia la fecha (la hora se queda); sin arrastrar, se elige y se mueve con «Mover a», como en el
/// mes. Clic elige, doble clic abre, espacio para la vista previa.
struct SemanaCalendario: View {
    @Bindable var modelo: BaseModelo
    let lunes: LocalDate
    let columna: ColumnaBase
    let filas: [FilaBase]
    @State private var encima: String?
    @Environment(\.navegar) private var navegar

    static let primeraHora = 7
    static let ultimaHora = 21
    static let altoHora: CGFloat = 44
    static let anchoHoras: CGFloat = 48

    private var dias: [LocalDate] { (0..<7).map { lunes.adding(days: $0) } }

    var body: some View {
        let porDia = Dictionary(grouping: filas.compactMap { f in f.fecha(columna).map { ($0, f) } }, by: \.0)
            .mapValues { $0.map(\.1) }
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Color.clear.frame(width: Self.anchoHoras, height: 1).accessibilityHidden(true)
                ForEach(dias, id: \.self) { d in cabeceraDia(d, n: porDia[d]?.count ?? 0) }
            }
            HStack(alignment: .top, spacing: 4) {
                Text("Todo el día")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: Self.anchoHoras, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(dias, id: \.self) { d in
                    todoElDia(d, filas: (porDia[d] ?? []).filter { Self.horaEnRejilla($0) == nil })
                }
            }
            ScrollView {
                HStack(alignment: .top, spacing: 4) {
                    VStack(spacing: 0) {
                        ForEach(Self.primeraHora..<Self.ultimaHora, id: \.self) { h in
                            Text("\(h):00")
                                .tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                                .frame(width: Self.anchoHoras, height: Self.altoHora, alignment: .topLeading)
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(dias, id: \.self) { d in
                        columnaHoras(d, filas: (porDia[d] ?? []).filter { Self.horaEnRejilla($0) != nil })
                    }
                }
            }
            .frame(minHeight: 360)
        }
    }

    // MARK: Partes

    private func cabeceraDia(_ d: LocalDate, n: Int) -> some View {
        let esHoy = d == modelo.hoy
        return HStack(spacing: 5) {
            Text(FormatoBase.diasSemana[d.weekday - 1] + " \(d.day)")
                .tlsTexto(esHoy ? TLSTipo.interfazFuerte : TLSTipo.interfazMedia)
                .foregroundStyle(TLSPaleta.texto.color)
            if esHoy { Text("hoy").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
        }
        .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo)
        .overlay(alignment: .bottom) {
            if esHoy { Rectangle().fill(TLSPaleta.principal.color).frame(height: 2).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FormatoBase.fechaConDia(d))\(esHoy ? ", hoy" : ""), \(FormatoBase.cuenta(n, "ficha", "fichas"))")
        .accessibilityAddTraits(.isHeader)
    }

    private func todoElDia(_ d: LocalDate, filas: [FilaBase]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(filas) { f in evento(f, hora: nil) }
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
            .strokeBorder(encima == "todo:\(d)" ? TLSPaleta.principal.color : TLSPaleta.separador.color,
                          lineWidth: encima == "todo:\(d)" ? 2 : 1))
        .dropDestination(for: String.self) { ids, _ in soltar(ids, en: d) } isTargeted: { marcar($0, "todo:\(d)") }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(FormatoBase.fechaConDia(d)), todo el día")
    }

    /// Un evento en su hora y su sitio de la columna (los que empiezan a la misma hora, uno al lado de otro).
    private func eventoColocado(_ f: FilaBase, porHora: [Int: [FilaBase]], anchoColumna: CGFloat) -> some View {
        let (h, m) = Self.horaEnRejilla(f) ?? (Self.primeraHora, 0)
        let mismas = porHora[h] ?? [f]
        let i = mismas.firstIndex { $0.id == f.id } ?? 0
        let ancho: CGFloat = (anchoColumna - 4) / CGFloat(max(mismas.count, 1))
        let x: CGFloat = 2 + CGFloat(i) * ancho
        let y: CGFloat = (CGFloat(h - Self.primeraHora) + CGFloat(m) / 60) * Self.altoHora + 2
        return evento(f, hora: String(format: "%d:%02d", h, m))
            .frame(width: max(ancho - 2, 20), height: Self.alto(f), alignment: .topLeading)
            .offset(x: x, y: y)
    }

    private func columnaHoras(_ d: LocalDate, filas: [FilaBase]) -> some View {
        let horas = Self.ultimaHora - Self.primeraHora
        let alto = CGFloat(horas) * Self.altoHora
        let esHoy = d == modelo.hoy
        // Las que empiezan a la misma hora van una al lado de otra.
        let porHora = Dictionary(grouping: filas) { Self.horaEnRejilla($0)?.hora ?? Self.primeraHora }
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<horas, id: \.self) { _ in
                        Rectangle().fill(Color.clear)
                            .frame(height: Self.altoHora)
                            .overlay(alignment: .top) { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                    }
                }
                ForEach(filas) { f in
                    eventoColocado(f, porHora: porHora, anchoColumna: geo.size.width)
                }
                if esHoy, let y = Self.posicionAhora(Date()) {
                    MarcaAhora(.horizontal, palabra: "Ahora")
                        .offset(x: -4, y: y - 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: alto)
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
            .fill(esHoy ? TLSPaleta.principalSuave.color.opacity(0.35) : TLSPaleta.superficie.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
            .strokeBorder(encima == "dia:\(d)" ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { ids, _ in soltar(ids, en: d) } isTargeted: { marcar($0, "dia:\(d)") }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(FormatoBase.fechaConDia(d)), \(FormatoBase.cuenta(filas.count, "ficha con hora", "fichas con hora"))")
    }

    private func evento(_ f: FilaBase, hora: String?) -> some View {
        let elegida = modelo.elegidaCalendario == f.id
        return Button {
            modelo.elegidaCalendario = elegida ? nil : f.id
            modelo.seleccion = [f.id]
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let hora {
                    Text(hora).tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                }
                Text(f.titulo)
                    .tlsTexto(TLSTipo.secundario.peso(500))
                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                    .lineLimit(hora == nil ? 1 : 2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: hora == nil ? nil : .infinity, alignment: .topLeading)
            .frame(minHeight: TLSAltura.objetivoMinimo)
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
        .accessibilityLabel([hora, f.titulo].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Elige la ficha para moverla de día")
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    // MARK: Soltar

    private func soltar(_ ids: [String], en d: LocalDate) -> Bool {
        guard let f = modelo.filaSoltada(ids), f.fecha(columna) != d else { return false }
        Task { await modelo.ponerFecha(f, d) }
        return true
    }

    private func marcar(_ dentro: Bool, _ clave: String) {
        if dentro { encima = clave } else if encima == clave { encima = nil }
    }

    // MARK: Cálculo

    /// La hora de la ficha (`hora`), si cae dentro de la rejilla.
    static func horaEnRejilla(_ f: FilaBase) -> (hora: Int, minuto: Int)? {
        guard let t = f.texto("hora"), let h = FormatoBase.hora(t), (primeraHora..<ultimaHora).contains(h.hora) else { return nil }
        return h
    }

    /// Alto del bloque: lo que dura (`duracion_min`, una hora si no lo dice), sin pasar del final del día.
    static func alto(_ f: FilaBase) -> CGFloat {
        let minutos = f.texto("duracion_min").flatMap(FormatoBase.numero) ?? 60
        let (h, m) = horaEnRejilla(f) ?? (primeraHora, 0)
        let quedan = Double((ultimaHora - h) * 60 - m)
        return max(CGFloat(min(minutos, quedan)) / 60 * altoHora - 4, 30)
    }

    /// Altura de la línea «ahora» dentro de la rejilla (`nil` fuera de las horas que se ven).
    static func posicionAhora(_ ahora: Date) -> CGFloat? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: ahora)
        guard let h = c.hour, let m = c.minute, (primeraHora..<ultimaHora).contains(h) else { return nil }
        return (CGFloat(h - primeraHora) + CGFloat(m) / 60) * altoHora
    }
}
