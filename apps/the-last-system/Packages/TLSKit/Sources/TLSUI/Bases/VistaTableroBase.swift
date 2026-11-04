import SwiftUI
import TLSCore
import TLSDesign

/// Tablero (§4.4): una columna por valor de la propiedad de agrupar (estado por defecto), en `bandeja`, con su
/// número y su suma; tarjetas `superficie` de radio 14 con título, tres datos y distintivos. Arrastrar cambia
/// esa propiedad (Ganada bloqueada sin cobro confirmado, con su motivo). Sin arrastrar: «Mover a…», ⌘← y ⌘→,
/// y las acciones de VoiceOver. Clic elige, doble clic o ↩ entra, espacio para la vista previa.
struct VistaTableroBase: View {
    @Bindable var modelo: BaseModelo
    @State private var encima: String?
    @FocusState private var enfocada: String?
    @Environment(\.navegar) private var navegar

    var body: some View {
        if let clave = modelo.claveTablero, let col = modelo.coleccion.columna(clave), col.tipo == .opcion || col.tipo == .persona {
            tablero(col)
        } else {
            VacioExplicado(icono: "rectangle.split.3x1", titulo: "Elige por qué agrupar el tablero",
                           porQue: "Cada columna del tablero es un valor de una propiedad de opción, como el estado. Elígela en «Agrupar».")
        }
    }

    private func tablero(_ col: ColumnaBase) -> some View {
        let grupos = MotorVista.agrupar(modelo.filas, por: col.clave, coleccion: modelo.coleccion, hoy: modelo.hoy,
                                        incluirVacios: modelo.config.filtros.isEmpty && modelo.busqueda.isEmpty)
        let plegadas = modelo.config.plegados
        let visibles = grupos.filter { !plegadas.contains($0.id) }
        let ocultas = grupos.filter { plegadas.contains($0.id) }
        let valores = grupos.map(\.id).filter { !$0.hasPrefix("\u{1F}") }
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: TLSEspacio.e12) {
                        ForEach(visibles) { g in
                            columna(g, col: col, valores: valores)
                                .frame(width: 272)
                                .frame(maxHeight: max(geo.size.height - 8, 240), alignment: .top)
                        }
                        if !ocultas.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Rotulo("Plegadas")
                                ForEach(ocultas) { g in
                                    Button { modelo.plegar(g.id) } label: {
                                        Label("\(g.titulo) · \(g.filas.count)", systemImage: "chevron.right")
                                    }
                                    .tlsBoton(.secundario)
                                    .accessibilityHint("Despliega la columna \(g.titulo)")
                                }
                            }
                            .frame(width: 180, alignment: .leading)
                            .padding(.top, 6)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(minHeight: 320)
            Text("Arrastra una tarjeta para cambiar su \(col.etiqueta.lowercased()). Sin arrastrar: «Mover a…», o ⌘← y ⌘→ con la tarjeta elegida.")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
        }
    }

    private func columna(_ g: GrupoFilas, col: ColumnaBase, valores: [String]) -> some View {
        let esGanada = col.clave == "estado" && TextFolding.fold(g.id) == "ganada" && modelo.coleccion.tipos.contains(.opportunity)
        let filas = esGanada ? g.filas.filter { recienGanada($0) } : g.filas
        let objetivo = encima == g.id
        let bloqueada = esGanada ? modelo.bloqueo : nil
        let dinero = modelo.coleccion.columnaDinero
        let suma = dinero.map { d in filas.compactMap { $0.numero(d) }.reduce(0, +) }
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(g.titulo)
                        .tlsTexto(TLSTipo.interfazFuerte)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if esGanada {
                        Text("Últimos 90 días").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                Spacer(minLength: 0)
                Text(suma.map { "\(filas.count) · \(FormatoBase.euros($0, redondo: true))" } ?? "\(filas.count)")
                    .tlsTexto(TLSTipo.cifraFila)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                if modelo.coleccion.plegadas.contains(g.id) || !g.id.hasPrefix("\u{1F}") {
                    Button { modelo.plegar(g.id) } label: { Image(systemName: "chevron.left.2") }
                        .buttonStyle(.plain)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                        .help("Plegar esta columna")
                        .accessibilityLabel("Plegar \(g.titulo)")
                }
            }
            if let b = bloqueada, let f = modelo.fila(b.fila) {
                AvisoBloqueo(motivo: b.motivo, etapa: b.etapa) {
                    modelo.bloqueo = nil
                    enfocada = f.id
                }
            }
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    ForEach(filas) { f in
                        TarjetaTablero(fila: f, columna: col, valores: valores, modelo: modelo, enfocada: $enfocada)
                    }
                    if !esGanada, !g.id.hasPrefix("\u{1F}"), modelo.motivoSinCrear == nil {
                        Button { modelo.abrirNueva(poner: [col.clave: g.id]) } label: {
                            Label("Nueva en \(g.titulo)", systemImage: "plus")
                        }
                        .tlsBoton(.discreto)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.automatic)
        }
        .padding(TLSEspacio.e12)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .strokeBorder(objetivo ? (esGanada ? TLSPaleta.bordeControl.color : TLSPaleta.principal.color) : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { ids, _ in
            guard let f = modelo.filaSoltada(ids), !g.id.hasPrefix("\u{1F}") else { return false }
            Task { await modelo.mover(f, a: g.id) }
            return true
        } isTargeted: { dentro in
            if dentro { encima = g.id } else if encima == g.id { encima = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(g.titulo), \(FormatoBase.cuenta(filas.count, "tarjeta", "tarjetas"))")
    }

    /// Ganada de los últimos 90 días (las antiguas no llenan el tablero).
    private func recienGanada(_ f: FilaBase) -> Bool {
        let d = f.fecha("ganada") ?? f.fecha("cerrada") ?? f.modificada.map { LocalDate(date: $0) }
        return d.map { $0 >= modelo.hoy.adding(days: -90) } ?? true
    }
}

/// El aviso de Ganada bloqueada: por qué y «Dejar en …».
struct AvisoBloqueo: View {
    let motivo: String
    let etapa: String
    let dejar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Label(motivo, systemImage: "lock")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            Button("Dejar en \(etapa)", action: dejar).tlsBoton(.principal, alto: 32)
        }
        .padding(TLSEspacio.e12)
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(TLSEstado.atencion.tinte.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No se puede mover: \(motivo)")
    }
}

/// Una tarjeta del tablero.
struct TarjetaTablero: View {
    let fila: FilaBase
    let columna: ColumnaBase
    let valores: [String]
    @Bindable var modelo: BaseModelo
    var enfocada: FocusState<String?>.Binding
    @Environment(\.navegar) private var navegar

    var body: some View {
        let elegida = modelo.seleccion.contains(fila.id)
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        let datos = datosTarjeta
        let avisos = fila.calculados.filter { $0.key != ReglaGanada.clave && $0.value.aviso }.map(\.value.texto)
        let opciones = EdicionCelda.opciones(columna, fila: fila).filter { o in
            !fila.valoresOpcion(columna).contains { TextFolding.fold($0) == TextFolding.fold(o.valor) }
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                TextoResaltado(fila.titulo, busqueda: modelo.busqueda)
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let codigo = fila.codigo, !fila.titulo.contains(codigo) {
                    Text(codigo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            ForEach(datos, id: \.0) { etiqueta, valor in
                Text(valor)
                    .tlsTexto(etiqueta == "_cifras" ? TLSTipo.cifraFila : TLSTipo.secundario)
                    .foregroundStyle(etiqueta == "_cifras" ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
                    .lineLimit(etiqueta == "_siguiente" ? 2 : 1)
            }
            HStack(spacing: 6) {
                ForEach(avisos, id: \.self) { a in PastillaEstado(.atencion, palabra: a) }
                Spacer(minLength: 0)
                Menu {
                    ForEach(opciones, id: \.valor) { o in
                        Button(FormatoBase.opcionVisible(o.valor)) { Task { await modelo.mover(fila, a: o.valor) } }
                            .disabled(o.motivo != nil)
                    }
                    if let m = opciones.compactMap(\.motivo).first { Divider(); Text(m) }
                } label: {
                    // Color de enlace, así que subrayado (§1.3: el enlace frente al texto no llega a 3:1).
                    Text("Mover a…").tlsTexto(TLSTipo.secundario).underline()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(TLSPaleta.enlace.color)
                .fixedSize()
                .frame(minHeight: TLSAltura.objetivoMinimo)
                .accessibilityLabel("Mover \(fila.titulo) a otra columna")
            }
        }
        .padding(TLSEspacio.e12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .overlay(forma.strokeBorder(elegida ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .contentShape(forma)
        .focusable()
        .focused(enfocada, equals: fila.id)
        .tlsFocoPropio(radio: TLSRadio.tarjeta)
        .vistaPrevia(ruta: fila.rutaPreviaAlPasar, sesion: modelo.sesion)
        .onTapGesture(count: 2) { modelo.abrir(fila, navegar: navegar) }
        .onTapGesture { modelo.seleccion = [fila.id]; enfocada.wrappedValue = fila.id }
        .onKeyPress(.return) { modelo.abrir(fila, modo: .entrar, navegar: navegar); return .handled }
        .onKeyPress(.space) { modelo.vistaPrevia(fila); return .handled }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { tecla in
            guard tecla.modifiers.contains(.command) else { return .ignored }
            let paso = tecla.key == .leftArrow ? -1 : 1
            Task { await modelo.moverAlLado(fila, paso, columnas: valores) }
            return .handled
        }
        .draggable(modelo.textoArrastre(fila)) {
            Text(fila.titulo)
                .tlsTexto(TLSTipo.interfazFuerte)
                .padding(10)
                .background(forma.fill(TLSPaleta.superficieElevada.color))
        }
        .contextMenu {
            Button("Abrir") { modelo.abrir(fila, modo: .entrar, navegar: navegar) }
            Button("Abrir en pestaña nueva") { modelo.abrir(fila, modo: .pestanaNueva, navegar: navegar) }
            Button("Vista previa") { modelo.vistaPrevia(fila) }
            Menu("Mover a") {
                ForEach(opciones, id: \.valor) { o in
                    Button(FormatoBase.opcionVisible(o.valor)) { Task { await modelo.mover(fila, a: o.valor) } }
                        .disabled(o.motivo != nil)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([fila.titulo, fila.valoresOpcion(columna).first].compactMap { $0 } + datos.map(\.1) + avisos).joined(separator: ", "))
        .accessibilityAddTraits(elegida ? [.isSelected, .isButton] : .isButton)
        .accessibilityActions {
            ForEach(opciones.filter { $0.motivo == nil }, id: \.valor) { o in
                Button("Mover a \(FormatoBase.opcionVisible(o.valor))") { Task { await modelo.mover(fila, a: o.valor) } }
            }
            Button("Vista previa") { modelo.vistaPrevia(fila) }
        }
    }

    /// Los datos de la tarjeta (§4.4: título, tres datos y distintivos): hasta dos textos (empresa, servicio),
    /// las cifras en una línea («150,00 € · 50 %») y el siguiente paso.
    private var datosTarjeta: [(String, String)] {
        let hoy = modelo.hoy
        var textos: [(String, String)] = []
        var cifras: [String] = []
        var siguiente: String?
        for col in modelo.columnasVisibles where col.tipo != .titulo && col.clave != columna.clave {
            if col.tipo == .calculada, fila.calculado(col)?.aviso == true { continue }
            let t = fila.textoCelda(col, hoy: hoy)
            guard !t.isEmpty, t != "—", t != fila.titulo else { continue }
            if col.clave == "siguiente_paso" { siguiente = t; continue }
            if [.dinero, .porcentaje, .numero].contains(col.tipo) { cifras.append(t); continue }
            if col.tipo == .calculada { continue }
            if textos.count < 2 { textos.append((col.etiqueta, t)) }
        }
        var out = textos
        if !cifras.isEmpty { out.append(("_cifras", cifras.prefix(3).joined(separator: " · "))) }
        if let siguiente { out.append(("_siguiente", "Siguiente: \(siguiente)")) }
        return out
    }
}
