import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol areas-b. Las cuatro secciones de Marca › Operación (PLAN §6.5; SISTEMAS MA2 y MA3; PLANTILLAS §4.3):
// calendario editorial (una vista sobre la fecha `publicar`; arrastrar cambia el día), contenido en tablero de Idea a
// Publicado (arrastrar cambia el estado), distribución y seguimiento (canales, alcance, interacciones y conversaciones
// atribuidas, sacado de las fichas) y conversaciones con «Proponer a Ventas». Sin arrastrar: menús y acciones de
// VoiceOver. Lo que falta, «Sin dato».

// MARK: - Calendario editorial

/// Calendario de un mes con las piezas en su día (las publicadas, en el de publicación) y las que aún no tienen fecha.
struct CalendarioMarca: View {
    let lectura: LecturaMarca
    @Bindable var modelo: ModeloMarca
    @State private var mes: LocalDate
    @State private var encima: LocalDate?
    @State private var encimaSinFecha = false
    @Environment(\.undoManager) private var undoManager

    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
                        "noviembre", "diciembre"]
    static let iniciales = ["L", "M", "X", "J", "V", "S", "D"]
    static let diasLargos = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

    init(lectura: LecturaMarca, modelo: ModeloMarca) {
        self.lectura = lectura
        self.modelo = modelo
        _mes = State(initialValue: LocalDate(year: lectura.hoy.year, month: lectura.hoy.month, day: 1) ?? lectura.hoy)
    }

    var body: some View {
        let piezas = lectura.calendario(anio: mes.year, mes: mes.month)
        let semanas = Self.semanas(de: mes)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(spacing: TLSEspacio.e8) {
                Button { mes = Self.otroMes(mes, -1) } label: { Image(systemName: "chevron.left") }
                    .tlsBoton(.discreto).accessibilityLabel("Mes anterior")
                Text("\(FormatoFicha.capital(Self.meses[mes.month - 1])) de \(String(mes.year))")
                    .tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("marca.calendario.mes")
                Button { mes = Self.otroMes(mes, 1) } label: { Image(systemName: "chevron.right") }
                    .tlsBoton(.discreto).accessibilityLabel("Mes siguiente")
                if mes.month != lectura.hoy.month || mes.year != lectura.hoy.year {
                    Button("Este mes") { mes = LocalDate(year: lectura.hoy.year, month: lectura.hoy.month, day: 1) ?? mes }
                        .tlsBoton(.enlace)
                }
                Spacer(minLength: 0)
                Text("Arrastra una pieza a otro día para cambiar cuándo se publica. Lo publicado no se mueve.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .multilineTextAlignment(.trailing)
            }
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(0..<7, id: \.self) { i in
                        Text(Self.iniciales[i]).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(Self.diasLargos[i])
                    }
                }
                ForEach(semanas, id: \.self) { lunes in
                    GridRow {
                        ForEach(0..<7, id: \.self) { i in
                            let dia = lunes.adding(days: i)
                            celda(dia, piezas: piezas[dia] ?? [], delMes: dia.month == mes.month)
                        }
                    }
                }
            }
            sinFecha
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marca.calendario")
    }

    private func celda(_ dia: LocalDate, piezas: [PiezaMarca], delMes: Bool) -> some View {
        let esHoy = dia == lectura.hoy
        let forma = RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(dia.day)")
                .tlsTexto(esHoy ? TLSTipo.interfazFuerte : TLSTipo.secundario)
                .foregroundStyle(esHoy ? TLSPaleta.sobrePrincipal.color : (delMes ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color))
                .frame(minWidth: 22, minHeight: 22)
                .background(Circle().fill(esHoy ? TLSPaleta.principal.color : Color.clear))
            ForEach(piezas.prefix(3)) { p in ChipPiezaCalendario(pieza: p, modelo: modelo, hoy: lectura.hoy) }
            if piezas.count > 3 {
                Text("y \(piezas.count - 3) más").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(forma.fill(delMes ? TLSPaleta.superficie.color : TLSPaleta.bandeja.color))
        .overlay(forma.strokeBorder(encima == dia ? TLSPaleta.principal.color : TLSPaleta.separador.color, lineWidth: encima == dia ? 2 : 1))
        .dropDestination(for: String.self) { rutas, _ in
            guard let r = rutas.first, let p = lectura.piezas.first(where: { $0.ruta.raw == r }), p.movible else { return false }
            Task { await modelo.cambiarDia(p, a: dia, deshacer: undoManager) }
            return true
        } isTargeted: { dentro in
            if dentro { encima = dia } else if encima == dia { encima = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Self.diasLargos[dia.weekday - 1]) \(dia.day)" + (esHoy ? ", hoy" : "")
                            + (piezas.isEmpty ? "" : ", " + FormatoBase.cuenta(piezas.count, "pieza", "piezas")))
    }

    @ViewBuilder
    private var sinFecha: some View {
        let ps = lectura.sinFecha
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: TLSEspacio.e8) {
                Rotulo("Sin fecha")
                Text("\(ps.count)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if ps.isEmpty {
                Text("Todas las piezas tienen día.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                ChipsSinFecha(piezas: ps, modelo: modelo, hoy: lectura.hoy)
            }
        }
        .padding(TLSEspacio.e12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .strokeBorder(encimaSinFecha ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { rutas, _ in
            guard let r = rutas.first, let p = lectura.piezas.first(where: { $0.ruta.raw == r }), p.movible, p.publicar != nil else { return false }
            Task { await modelo.cambiarDia(p, a: nil, deshacer: undoManager) }
            return true
        } isTargeted: { encimaSinFecha = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Piezas sin fecha")
    }

    /// Los lunes de las semanas que tocan el mes.
    static func semanas(de primero: LocalDate) -> [LocalDate] {
        let inicio = primero.adding(days: -(primero.weekday - 1))
        var out: [LocalDate] = []
        var l = inicio
        while (l.year, l.month) <= (primero.year, primero.month) || out.isEmpty {
            out.append(l)
            l = l.adding(days: 7)
            if out.count >= 6 { break }
        }
        return out
    }

    static func otroMes(_ d: LocalDate, _ paso: Int) -> LocalDate {
        var m = d.month + paso, a = d.year
        if m < 1 { m = 12; a -= 1 }
        if m > 12 { m = 1; a += 1 }
        return LocalDate(year: a, month: m, day: 1) ?? d
    }
}

/// Las piezas sin fecha, en filas que se parten.
private struct ChipsSinFecha: View {
    let piezas: [PiezaMarca]
    @Bindable var modelo: ModeloMarca
    let hoy: LocalDate

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(piezas) { p in ChipPiezaCalendario(pieza: p, modelo: modelo, hoy: hoy) }
        }
    }
}

/// Una pieza en el calendario: título con su estado (icono y texto para VoiceOver). Se arrastra a otro día; con el
/// teclado (revisión final de F2, como el tablero de Tareas): Tab la enfoca con su anillo, ↩ la abre y ⌘← ⌘→ la pasan
/// al día anterior o al siguiente.
private struct ChipPiezaCalendario: View {
    let pieza: PiezaMarca
    @Bindable var modelo: ModeloMarca
    let hoy: LocalDate
    @Environment(\.navegar) private var navegar
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let p = pieza
        let forma = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: 4) {
            Image(systemName: p.estado == .publicado ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.estado == .publicado ? TLSPaleta.bien.color : TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            Text(p.titulo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo, alignment: .leading)
        .background(forma.fill(p.estado == .publicado ? TLSEstado.bien.tinte.color : TLSPaleta.principalSuave.color))
        .contentShape(forma)
        .modifier(TecladoPieza(radio: 6, abrir: { navegar(.ficha(p.ruta), modo: .automatico) },
                               mover: p.movible ? { paso in mover((p.publicar ?? hoy).adding(days: paso)) } : nil))
        .onTapGesture { navegar(.ficha(p.ruta), modo: .automatico) }
        .help("\(p.titulo) · \(p.palabraEstado)")
        .modifier(ArrastrablePieza(pieza: p))
        .contextMenu {
            Button("Abrir") { navegar(.ficha(p.ruta), modo: .entrar) }
            if p.movible { menuDia }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.titulo), \(p.palabraEstado)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { navegar(.ficha(p.ruta), modo: .automatico) }
        .accessibilityActions { if p.movible { menuDia } }
    }

    @ViewBuilder
    private var menuDia: some View {
        let base = pieza.publicar ?? hoy
        Button("Un día después") { mover(base.adding(days: 1)) }
        Button("Un día antes") { mover(base.adding(days: -1)) }
        Button("A la semana siguiente") { mover(base.adding(days: 7)) }
        if pieza.publicar != nil { Button("Quitar la fecha") { mover(nil) } }
    }

    private func mover(_ d: LocalDate?) { Task { await modelo.cambiarDia(pieza, a: d, deshacer: undoManager) } }
}

/// Solo lo que se puede mover se arrastra (lo publicado ya tiene su día).
private struct ArrastrablePieza: ViewModifier {
    let pieza: PiezaMarca

    func body(content: Content) -> some View {
        if pieza.movible {
            content.draggable(pieza.ruta.raw) {
                Text(pieza.titulo).tlsTexto(TLSTipo.interfazFuerte).padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(TLSPaleta.superficieElevada.color))
            }
        } else {
            content
        }
    }
}

// MARK: - Contenido en tablero

/// De Idea a Publicado: una columna por estado; arrastrar (o «Mover a…») cambia solo el estado de la pieza.
struct TableroMarca: View {
    let lectura: LecturaMarca
    @Bindable var modelo: ModeloMarca
    @State private var encima: EstadoPieza?
    @State private var verDescartadas = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: TLSEspacio.e12) {
                    ForEach(EstadoPieza.tablero, id: \.self) { e in columna(e).frame(width: 232) }
                    descartadas.frame(width: 200)
                }
                .padding(.bottom, 8)
            }
            Text("Arrastra una tarjeta para cambiar su estado. Sin arrastrar: «Mover a…». Publicar fuera lo haces tú: aquí solo queda apuntado.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marca.tablero")
    }

    private func columna(_ e: EstadoPieza) -> some View {
        let ps = lectura.piezas(en: e)
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: 6) {
                Text(e.rawValue).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(ps.count)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(ps) { p in TarjetaPiezaTablero(pieza: p, modelo: modelo, hoy: lectura.hoy, conversaciones: lectura.conversaciones(de: p).count) }
            if ps.isEmpty {
                Text("Ninguna").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .padding(TLSEspacio.e12)
        .frame(minHeight: 220, alignment: .top)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .strokeBorder(encima == e ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { rutas, _ in
            guard let r = rutas.first, let p = lectura.piezas.first(where: { $0.ruta.raw == r }), p.estado != e else { return false }
            Task { await modelo.mover(p, a: e, deshacer: undoManager) }
            return true
        } isTargeted: { dentro in
            if dentro { encima = e } else if encima == e { encima = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(e.rawValue), \(FormatoBase.cuenta(ps.count, "pieza", "piezas"))")
        .accessibilityIdentifier("marca.tablero.\(e.rawValue)")
    }

    private var descartadas: some View {
        let ps = lectura.piezas(en: .descartado)
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Button { verDescartadas.toggle() } label: {
                Label("Descartadas · \(ps.count)", systemImage: verDescartadas ? "chevron.down" : "chevron.right")
            }
            .tlsBoton(.discreto)
            .disabled(ps.isEmpty)
            if verDescartadas {
                ForEach(ps) { p in TarjetaPiezaTablero(pieza: p, modelo: modelo, hoy: lectura.hoy, conversaciones: 0) }
            }
        }
        .padding(.top, 6)
        .dropDestination(for: String.self) { rutas, _ in
            guard let r = rutas.first, let p = lectura.piezas.first(where: { $0.ruta.raw == r }), p.estado != .descartado else { return false }
            Task { await modelo.mover(p, a: .descartado, deshacer: undoManager) }
            return true
        }
    }
}

/// Una tarjeta del tablero: título, tipo y pilar, canales, día y lo que trajo; «Mover a…».
private struct TarjetaPiezaTablero: View {
    let pieza: PiezaMarca
    @Bindable var modelo: ModeloMarca
    let hoy: LocalDate
    let conversaciones: Int
    @Environment(\.navegar) private var navegar
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let p = pieza
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        let otros = EstadoPieza.allCases.filter { $0 != p.estado }
        let datos = [[p.tipo.map(LecturaMarca.nombreTipo), p.pilar].compactMap { $0 }.joined(separator: " · "),
                     p.canales.map(LecturaMarca.nombreCanal).joined(separator: ", "), cuando]
            .filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 6) {
            Text(p.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(datos, id: \.self) { d in
                Text(d).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
            HStack(spacing: 6) {
                if conversaciones > 0 {
                    Label(FormatoBase.cuenta(conversaciones, "conversación", "conversaciones"), systemImage: "bubble.left.and.bubble.right")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                }
                Spacer(minLength: 0)
                Menu {
                    ForEach(otros, id: \.self) { e in Button(e.rawValue) { mover(e) } }
                } label: {
                    Text("Mover a…").tlsTexto(TLSTipo.secundario).underline()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(TLSPaleta.enlace.color)
                .fixedSize()
                .frame(minHeight: TLSAltura.objetivoMinimo)
                .disabled(modelo.motivoSoloLectura != nil)
                .accessibilityLabel("Mover \(p.titulo) a otro estado")
            }
        }
        .padding(TLSEspacio.e12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .contentShape(forma)
        // Con el teclado, como el tablero de Tareas: Tab la enfoca (anillo), ↩ la abre, ⌘← ⌘→ la pasan a la columna
        // de al lado (cambia solo su estado).
        .modifier(TecladoPieza(radio: TLSRadio.tarjeta, abrir: { navegar(.ficha(p.ruta), modo: .entrar) },
                               mover: modelo.motivoSoloLectura == nil ? { paso in moverAlLado(paso) } : nil))
        .onTapGesture(count: 2) { navegar(.ficha(p.ruta), modo: .entrar) }
        .draggable(p.ruta.raw) {
            Text(p.titulo).tlsTexto(TLSTipo.interfazFuerte).padding(10)
                .background(forma.fill(TLSPaleta.superficieElevada.color))
        }
        .contextMenu {
            Button("Abrir") { navegar(.ficha(p.ruta), modo: .entrar) }
            Menu("Mover a") { ForEach(otros, id: \.self) { e in Button(e.rawValue) { mover(e) } } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([p.titulo, p.palabraEstado] + datos).joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { navegar(.ficha(p.ruta), modo: .entrar) }
        .accessibilityActions {
            ForEach(otros, id: \.self) { e in Button("Mover a \(e.rawValue)") { mover(e) } }
        }
    }

    /// «Publicada el 19 oct», «Se publica el 24 oct» o «Sin fecha».
    private var cuando: String {
        if pieza.estado == .publicado, let d = pieza.publicado ?? pieza.publicar { return "Publicada el \(FormatoFicha.fechaCorta(d, hoy: hoy))" }
        if let d = pieza.publicar { return "Se publica el \(FormatoFicha.fechaCorta(d, hoy: hoy))" }
        return "Sin fecha"
    }

    private func mover(_ e: EstadoPieza) { Task { await modelo.mover(pieza, a: e, deshacer: undoManager) } }

    /// ⌘← ⌘→: a la columna de al lado.
    private func moverAlLado(_ paso: Int) {
        let todos = EstadoPieza.allCases
        guard let e = pieza.estado, let i = todos.firstIndex(of: e), todos.indices.contains(i + paso) else { return }
        mover(todos[i + paso])
    }
}

/// El teclado en las piezas de Marca (calendario y tablero), como en el tablero de Tareas: Tab enfoca con el anillo,
/// ↩ abre y ⌘← ⌘→ mueven (al día o a la columna de al lado). Sin `mover`, las flechas no hacen nada.
private struct TecladoPieza: ViewModifier {
    let radio: CGFloat
    let abrir: () -> Void
    let mover: ((Int) -> Void)?
    @FocusState private var enfocada: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($enfocada)
            .focusEffectDisabled()
            .tlsAnilloFoco(enfocada, radio: radio)
            .onKeyPress(.return) { abrir(); return .handled }
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { k in
                guard k.modifiers.contains(.command), let mover else { return .ignored }
                mover(k.key == .leftArrow ? -1 : 1)
                return .handled
            }
    }
}

// MARK: - Distribución y seguimiento

/// Lo publicado por canal y pieza: alcance, interacciones y las conversaciones que trajo (y cuántas cualificó Ventas).
/// Los seguidores no son la meta. Sin dato, «Sin dato».
struct DistribucionMarca: View {
    let lectura: LecturaMarca
    let contexto: ContextoArea
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            Text("Para qué publicamos: para que empiecen conversaciones con quien puede comprar. Los seguidores no son la meta.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: TLSEspacio.entreMosaicos)], spacing: TLSEspacio.entreMosaicos) {
                cifra("MAR-PUB", titulo: "Publicadas este mes", icono: "megaphone")
                cifra("MAR-QCONV", titulo: "Conversaciones cualificadas del mes", icono: "bubble.left.and.bubble.right")
                ForEach(lectura.canales) { c in canal(c) }
            }
            tabla
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marca.distribucion")
    }

    @ViewBuilder
    private func cifra(_ codigo: String, titulo: String, icono: String) -> some View {
        let f = contexto.numero(codigo)
        Mosaico(titulo, icono: icono, pie: f.map { "\(codigo) · " + ($0.tieneMeta ? "meta \($0.textoMeta)" : "sin meta") }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(f?.textoValor ?? "Sin dato").tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let f { RhythmBadge(f.ritmo) }
            }
        }
        .frame(minHeight: 140)
    }

    private func canal(_ c: CanalMarca) -> some View {
        Mosaico(LecturaMarca.nombreCanal(c.canal), icono: "dot.radiowaves.left.and.right",
                pie: FormatoBase.cuenta(c.publicadas, "pieza publicada", "piezas publicadas")) {
            Grid(alignment: .leading, horizontalSpacing: TLSEspacio.e12, verticalSpacing: 3) {
                fila("Alcance", LecturaMarca.cifra(c.alcance))
                fila("Interacciones", LecturaMarca.cifra(c.interacciones))
                fila("Conversaciones", "\(c.conversaciones)")
                fila("Cualificadas", "\(c.cualificadas)")
            }
        }
        .frame(minHeight: 140)
        .accessibilityElement(children: .combine)
    }

    private func fila(_ t: String, _ v: String) -> some View {
        GridRow {
            Text(t).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            Text(v).tlsTexto(TLSTipo.cifraFila).foregroundStyle(v == "Sin dato" ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                .gridColumnAlignment(.trailing)
        }
    }

    private static let anchos: (canales: CGFloat, dia: CGFloat, cifra: CGFloat, conv: CGFloat, ev: CGFloat) = (120, 80, 96, 120, 90)

    private var tabla: some View {
        let a = Self.anchos
        let ps = lectura.publicadas
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TLSEspacio.e12) {
                Text("Pieza").frame(maxWidth: .infinity, alignment: .leading)
                Text("Canales").frame(width: a.canales, alignment: .leading)
                Text("Publicada").frame(width: a.dia, alignment: .leading)
                Text("Alcance").frame(width: a.cifra, alignment: .trailing)
                Text("Interacciones").frame(width: a.cifra, alignment: .trailing)
                Text("Conversaciones").frame(width: a.conv, alignment: .trailing)
                Text("Prueba").frame(width: a.ev, alignment: .leading)
            }
            .tlsTexto(TLSTipo.rotulo)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .padding(.horizontal, TLSEspacio.e16 + 12) // las filas llevan además el margen de `EstiloFila`
            .frame(minHeight: TLSAltura.cabeceraTabla)
            .accessibilityHidden(true)
            if ps.isEmpty {
                Text("Aún no hay piezas publicadas.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(TLSEspacio.e16)
            }
            ForEach(ps) { p in
                let cs = lectura.conversaciones(de: p)
                let cual = cs.filter { $0.estado == .cualificada }.count
                Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
                Button { navegar(.ficha(p.ruta), modo: .automatico) } label: {
                    HStack(spacing: TLSEspacio.e12) {
                        Text(p.titulo).tlsTexto(TLSTipo.interfazFuerte).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(p.canales.map(LecturaMarca.nombreCanal).joined(separator: ", ")).lineLimit(1).frame(width: a.canales, alignment: .leading)
                        Text((p.publicado ?? p.publicar).map { FormatoFicha.fechaCorta($0, hoy: lectura.hoy) } ?? "Sin dato")
                            .frame(width: a.dia, alignment: .leading)
                        Text(LecturaMarca.cifra(p.alcance)).tlsTexto(TLSTipo.cifraFila).frame(width: a.cifra, alignment: .trailing)
                        Text(LecturaMarca.cifra(p.interacciones)).tlsTexto(TLSTipo.cifraFila).frame(width: a.cifra, alignment: .trailing)
                        Text(cs.isEmpty ? "0" : "\(cs.count) · \(cual) cualif.").tlsTexto(TLSTipo.cifraFila).frame(width: a.conv, alignment: .trailing)
                        Text(p.evidencia == nil ? "Sin enlace" : "Con enlace").frame(width: a.ev, alignment: .leading)
                            .foregroundStyle(p.evidencia == nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                    }
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .padding(.horizontal, TLSEspacio.e16)
                    .frame(minHeight: TLSAltura.filaLista)
                    .contentShape(Rectangle())
                }
                .buttonStyle(EstiloFila())
                .accessibilityLabel("\(p.titulo). Canales: \(p.canales.map(LecturaMarca.nombreCanal).joined(separator: ", ")). Alcance: \(LecturaMarca.cifra(p.alcance)). Interacciones: \(LecturaMarca.cifra(p.interacciones)). \(FormatoBase.cuenta(cs.count, "conversación", "conversaciones")), \(cual) cualificadas.")
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Piezas publicadas y lo que trajeron")
    }
}

// MARK: - Conversaciones

/// Lo que vuelve del público, con la pieza que lo trajo. «Proponer a Ventas» deja una tarea en Ventas: Marca no
/// cualifica (lo decide Ventas).
struct ConversacionesMarca: View {
    let lectura: LecturaMarca
    @Bindable var modelo: ModeloMarca
    @Environment(\.undoManager) private var undoManager
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            Text("Lo que vuelve del público, con la pieza que lo trajo. Marca no cualifica: «Proponer a Ventas» le deja una tarea para que decida.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if lectura.conversaciones.isEmpty {
                VacioExplicado(icono: "bubble.left.and.bubble.right", titulo: "Aún no hay conversaciones",
                               porQue: "Cuando alguien responda a algo que publicaste, apúntalo en Marca › Conversaciones con la pieza que lo trajo.",
                               compacto: true)
            }
            ForEach(EstadoConversacion.allCases, id: \.self) { e in
                let cs = lectura.conversaciones.filter { $0.estado == e }
                if !cs.isEmpty {
                    VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                        HStack(spacing: TLSEspacio.e8) {
                            Rotulo(e.rawValue)
                            Text("\(cs.count)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                        VStack(spacing: 0) {
                            ForEach(cs) { c in
                                fila(c)
                                if c.id != cs.last?.id { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                        .tlsSombra(.uno, radio: TLSRadio.mosaico)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(e.rawValue), \(cs.count)")
                }
            }
        }
        .accessibilityIdentifier("marca.conversaciones")
    }

    private func fila(_ c: ConversacionMarca) -> some View {
        let hoy = lectura.hoy
        let detalle = [c.canal.map(LecturaMarca.nombreCanal), c.fecha.map { FormatoFicha.fechaCorta($0, hoy: hoy) }].compactMap { $0 }
        return HStack(alignment: .center, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TLSEspacio.e8) {
                    Text(c.quien).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(detalle.joined(separator: " · ")).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if let d = c.loQueDijo {
                    Text("«\(d)»").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                }
                if let t = c.piezaTitulo {
                    if let p = c.pieza {
                        Button("Viene de «\(t)»") { navegar(.ficha(p), modo: .automatico) }.tlsBoton(.enlace)
                    } else {
                        Text("Viene de «\(t)»").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                if c.estado == .noCualifica, let m = c.motivo {
                    Text("Motivo: \(m)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if c.estado == .cualificada, let o = c.oportunidad {
                    Text("Oportunidad: \(o)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            Spacer(minLength: TLSEspacio.e8)
            PastillaEstado(c.estado.estado, palabra: c.estado.rawValue)
            if c.estado == .nueva {
                Button("Proponer a Ventas") { Task { await modelo.proponerAVentas(c, deshacer: undoManager) } }
                    .tlsBoton(.secundario)
                    .disabled(modelo.motivoSoloLectura != nil)
                    .help(modelo.motivoSoloLectura ?? "Deja una tarea en Ventas para que decida si cualifica")
                    .accessibilityIdentifier("marca.proponer.\(c.ruta.stem)")
            }
            Button { navegar(.ficha(c.ruta), modo: .automatico) } label: { Image(systemName: "arrow.up.right.square") }
                .tlsBoton(.discreto)
                .help("Abrir la conversación")
                .accessibilityLabel("Abrir la conversación con \(c.quien)")
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, TLSEspacio.e12)
        .accessibilityElement(children: .contain)
    }
}
