import SwiftUI
import TLSCore
import TLSDesign

/// Una celda de la tabla (§4.7). Se edita según el tipo del diccionario y **escribe solo su clave**: texto en un
/// campo, opción en un menú con su pastilla, fecha con «Hoy», «Mañana» y «+1 semana», dinero con euros, sí/no
/// con una casilla. Lo calculado y lo que no se toca desde aquí va en gris, con su motivo al pasar el puntero.
struct CeldaBase: View {
    let fila: FilaBase
    let columna: ColumnaBase
    @Bindable var modelo: BaseModelo
    @Environment(\.navegar) private var navegar

    var body: some View {
        let hoy = modelo.hoy
        switch columna.tipo {
        case .titulo:
            CeldaTitulo(fila: fila, modelo: modelo)
        case .calculada:
            let v = fila.calculado(columna)
            CeldaFija(texto: v?.texto ?? "—", icono: "function", motivo: modelo.motivoSoloLectura(fila, columna),
                      aviso: v?.aviso ?? false, cifra: columna.esCifra)
        case .relacion:
            CeldaRelacion(fila: fila, columna: columna, modelo: modelo)
        case .siNo:
            if let motivo = modelo.motivoSoloLectura(fila, columna) {
                CeldaFija(texto: fila.textoCelda(columna, hoy: hoy), icono: "lock", motivo: motivo)
            } else {
                Toggle(isOn: Binding(get: { if case .bool(true)? = fila.valor(columna) { return true }; return false },
                                     set: { nuevo in Task { await modelo.guardar(fila, columna, valor: .bool(nuevo)) } })) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("\(columna.etiqueta) de \(fila.titulo)")
            }
        default:
            if let motivo = modelo.motivoSoloLectura(fila, columna) {
                CeldaFija(texto: fila.textoCelda(columna, hoy: hoy), icono: "lock", motivo: motivo, cifra: columna.esCifra)
            } else {
                CeldaEditable(fila: fila, columna: columna, modelo: modelo)
            }
        }
    }
}

/// El título de la fila: con lo buscado resaltado y, si está elegida, «Abrir» para entrar con un clic más.
struct CeldaTitulo: View {
    let fila: FilaBase
    @Bindable var modelo: BaseModelo
    @Environment(\.navegar) private var navegar

    var body: some View {
        HStack(spacing: 6) {
            TextoResaltado(fila.titulo, busqueda: modelo.busqueda)
                .tlsTexto(TLSTipo.interfazFuerte)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(1)
            if let codigo = fila.codigo, !fila.titulo.contains(codigo) {
                Text(codigo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
            Spacer(minLength: 0)
            if modelo.seleccion.contains(fila.id) {
                Button("Abrir") { modelo.abrir(fila, modo: .entrar, navegar: navegar) }
                    .tlsBoton(.enlace)
                    .help("Abre la ficha (también con doble clic o ↩)")
            }
        }
        .help("Clic: elegir · doble clic o ↩: abrir la ficha · espacio: vista previa")
        .vistaPrevia(ruta: fila.rutaPreviaAlPasar, sesion: modelo.sesion)
    }
}

/// Texto con lo buscado resaltado (sin tildes ni mayúsculas).
struct TextoResaltado: View {
    let texto: String
    let busqueda: String
    /// Sobre un fondo de color (fila elegida): solo subrayado y en negrita, sin fondo.
    let sobreColor: Bool

    init(_ texto: String, busqueda: String, sobreColor: Bool = false) {
        self.texto = texto
        self.busqueda = busqueda
        self.sobreColor = sobreColor
    }

    var body: some View {
        Text(atribuido)
    }

    private var atribuido: AttributedString {
        var a = AttributedString(texto)
        guard !busqueda.isEmpty, let r = MotorVista.resaltar(texto, busqueda: busqueda),
              let desde = AttributedString.Index(r.lowerBound, within: a),
              let hasta = AttributedString.Index(r.upperBound, within: a) else { return a }
        if !sobreColor { a[desde..<hasta].backgroundColor = TLSPaleta.principalSuave.color }
        a[desde..<hasta].underlineStyle = .single
        return a
    }
}

/// Celda que no se escribe aquí: en gris, con su icono (función o candado) y el motivo al pasar el puntero.
struct CeldaFija: View {
    let texto: String
    let icono: String
    let motivo: String?
    var aviso: Bool = false
    var cifra: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if cifra { Spacer(minLength: 0) }
            if aviso {
                Image(systemName: TLSEstado.atencion.simbolo)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TLSEstado.atencion.color.color)
                    .accessibilityHidden(true)
            }
            Text(texto)
                .tlsTexto(cifra ? TLSTipo.cifraFila : TLSTipo.interfaz)
                .foregroundStyle(aviso ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
                .lineLimit(1)
            Image(systemName: icono)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            if !cifra { Spacer(minLength: 0) }
        }
        .help(motivo ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texto + (aviso ? ", pide atención" : ""))
        .accessibilityHint(motivo ?? "")
    }
}

/// Celda que se edita: clic abre el editor en una ventana flotante pegada a la celda.
struct CeldaEditable: View {
    let fila: FilaBase
    let columna: ColumnaBase
    @Bindable var modelo: BaseModelo

    private var editando: Binding<Bool> {
        Binding(get: { modelo.editando == CeldaEnEdicion(fila: fila.id, columna: columna.clave) },
                set: { if !$0, modelo.editando == CeldaEnEdicion(fila: fila.id, columna: columna.clave) { modelo.editando = nil } })
    }

    var body: some View {
        let texto = fila.textoCelda(columna, hoy: modelo.hoy)
        Button {
            modelo.errorEdicion = nil
            modelo.editando = CeldaEnEdicion(fila: fila.id, columna: columna.clave)
        } label: {
            HStack(spacing: 4) {
                if columna.esCifra { Spacer(minLength: 0) }
                contenido(texto)
                if !columna.esCifra { Spacer(minLength: 0) }
            }
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(texto.isEmpty ? "Clic para escribir \(columna.etiqueta.lowercased())" : "Clic para cambiar")
        .accessibilityLabel("\(columna.etiqueta): \(texto.isEmpty ? "vacío" : texto)")
        .accessibilityHint("Cambia \(columna.etiqueta.lowercased()) de \(fila.titulo)")
        .popover(isPresented: editando, arrowEdge: .bottom) {
            EditorCelda(fila: fila, columna: columna, modelo: modelo)
        }
    }

    @ViewBuilder private func contenido(_ texto: String) -> some View {
        if columna.tipo == .opcion, !texto.isEmpty, columna.clave == "estado" || columna.clave == modelo.claveTablero {
            PastillaDeEstado(valor: texto, coleccion: modelo.coleccion)
        } else if texto.isEmpty {
            Text("—").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
        } else if columna.tipo == .persona {
            HStack(spacing: 5) {
                Monograma(nombre: texto, tamano: 18)
                Text(texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
            }
        } else {
            TextoResaltado(texto, busqueda: modelo.busqueda)
                .tlsTexto(columna.esCifra ? TLSTipo.cifraFila : TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(1)
        }
    }
}

/// Celda de relación (§4.7, §5.2): lo enlazado, y al pulsar, el selector de relación de las fichas
/// (`SelectorDeRelacion`): busca, crea al vuelo, confirma dentro si cambia algo que ya había y escribe **una
/// línea** en esta ficha, con Deshacer. En solo lectura (o en lo que no se toca desde aquí) enseña lo enlazado,
/// para abrirlo, y el motivo. Clic derecho: abrir lo enlazado.
struct CeldaRelacion: View {
    let fila: FilaBase
    let columna: ColumnaBase
    @Bindable var modelo: BaseModelo
    @State private var abierto = false
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav

    /// Por qué no se cambia desde la celda (`nil` = se abre el selector).
    private var motivo: String? {
        if fila.esFilaCSV { return "Este registro no guarda relaciones." }
        if fila.claveReal(columna) == nil { return "Esta ficha no tiene esa propiedad." }
        return modelo.motivoSoloLectura(fila, columna)
    }

    var body: some View {
        let enlaces = fila.enlaces(columna)
        let texto = fila.textoCelda(columna, hoy: modelo.hoy)
        let motivo = self.motivo
        Button { abierto = true } label: {
            HStack(spacing: 4) {
                if texto.isEmpty {
                    Text("—").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else {
                    Image(systemName: icono).font(.system(size: 11)).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .accessibilityHidden(true)
                    TextoResaltado(texto, busqueda: modelo.busqueda)
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(enlaces.contains { $0.ruta == nil } ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if motivo != nil, !texto.isEmpty {
                    Image(systemName: "lock").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                }
            }
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(motivo ?? (texto.isEmpty ? "Clic para enlazar \(columna.etiqueta.lowercased())" : "Clic para cambiar · clic derecho para abrir"))
        .accessibilityLabel("\(columna.etiqueta): \(texto.isEmpty ? "sin enlazar" : texto)")
        .accessibilityHint(motivo ?? "Abre el selector de \(columna.etiqueta.lowercased())")
        .contextMenu {
            ForEach(Array(enlaces.enumerated()), id: \.offset) { _, e in
                if let r = e.ruta, !modelo.sesion.esPrivado(r) {
                    Button("Abrir «\(e.texto)»") { navegar(modelo.sesion.destino(para: r), modo: .entrar) }
                    Button("Abrir «\(e.texto)» en pestaña nueva") { navegar(modelo.sesion.destino(para: r), modo: .pestanaNueva) }
                }
            }
            if motivo == nil { Button("Cambiar \(columna.etiqueta.lowercased())…") { abierto = true } }
        }
        .accessibilityActions {
            ForEach(Array(enlaces.enumerated()), id: \.offset) { _, e in
                if let r = e.ruta, !modelo.sesion.esPrivado(r) {
                    Button("Abrir \(e.texto)") { navegar(modelo.sesion.destino(para: r), modo: .entrar) }
                }
            }
        }
        .popover(isPresented: $abierto, arrowEdge: .bottom) {
            if motivo == nil, let clave = fila.claveReal(columna) {
                SelectorDeRelacion(dueno: fila.ruta, propiedad: clave, sesion: modelo.sesion)
                    .environment(\.navegar, navegar)
                    .environment(\.navegacion, nav)
            } else {
                soloLectura(enlaces, motivo: motivo)
            }
        }
    }

    /// Lo enlazado, para abrirlo, y por qué no se cambia aquí.
    private func soloLectura(_ enlaces: [EnlaceFila], motivo: String?) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text(columna.etiqueta).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
            ForEach(Array(enlaces.enumerated()), id: \.offset) { _, e in
                if let r = e.ruta, !modelo.sesion.esPrivado(r) {
                    Button { abierto = false; navegar(modelo.sesion.destino(para: r), modo: .automatico) } label: {
                        Label(e.texto, systemImage: icono)
                    }
                    .tlsBoton(.enlace)
                } else {
                    Label("\(e.texto) (aún no existe)", systemImage: "questionmark.circle")
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            if let motivo {
                Label(motivo, systemImage: "lock")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(width: 300)
    }

    private var icono: String {
        if let base = columna.relacionCon, let c = CatalogoBases.coleccion(base) { return c.icono }
        return "link"
    }
}

/// El editor de una celda (§4.7), con lo que se escribirá en la ficha («Se escribe en su ficha, solo esta
/// línea: `estado: Aceptada`»). ↩ guarda, Tab guarda y pasa a la siguiente, Esc cierra.
struct EditorCelda: View {
    let fila: FilaBase
    let columna: ColumnaBase
    @Bindable var modelo: BaseModelo
    @State private var texto: String = ""
    @State private var error: String?
    @State private var guardando = false
    @FocusState private var enfocado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text("\(columna.etiqueta) de «\(fila.titulo)»")
                .tlsTexto(TLSTipo.tituloModulo)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(2)
            switch columna.tipo {
            case .opcion:
                opciones
            default:
                campo
            }
            if let error {
                Label(error, systemImage: TLSEstado.mal.simbolo)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isStaticText)
            }
            HStack(spacing: 4) {
                Text(fila.esFilaCSV ? "Se escribe en su registro, solo esta fila:" : "Se escribe en su ficha, solo esta línea:")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                Text(lineaPrevista).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
            }
            HStack(spacing: TLSEspacio.e8) {
                if columna.tipo != .opcion {
                    Button("Guardar") { Task { await guardar(siguiente: false) } }
                        .tlsBoton(.principal, alto: 32)
                        .disabled(guardando)
                }
                Button("Cerrar") { modelo.editando = nil }
                    .tlsBoton(.secundario)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Text(columna.tipo == .opcion ? "Esc cierra" : "↩ guarda · Tab, la siguiente · Esc cierra")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(width: 340)
        .onAppear {
            texto = textoInicial
            enfocado = true
        }
    }

    private var textoInicial: String {
        guard let v = fila.valor(columna) else { return "" }
        switch columna.tipo {
        case .fecha: return fila.fecha(columna).map { String(format: "%02d/%02d/%04d", $0.day, $0.month, $0.year) } ?? v.displayText
        case .dinero, .porcentaje, .numero:
            // Sin puntos de millares: «1.234» se leería como 1,234 al guardarlo.
            return FormatoBase.numero(FormatoBase.textoVisible(v)).map { FormatoBase.cifraParaEditar($0) } ?? v.displayText
        case .opciones: if case .list(let l) = v { return l.joined(separator: ", ") }; return v.displayText
        default: return FormatoBase.textoVisible(v)
        }
    }

    private var lineaPrevista: String {
        let valor = (try? EdicionCelda.valor(texto, para: columna, hoy: modelo.hoy)) ?? nil
        return EdicionCelda.lineaPrevista(fila, columna, valor: valor)
    }

    @ViewBuilder private var campo: some View {
        HStack(spacing: 6) {
            TextField(columna.etiqueta, text: $texto)
                .textFieldStyle(.roundedBorder)
                .focused($enfocado)
                .multilineTextAlignment(columna.esCifra ? .trailing : .leading)
                .onSubmit { Task { await guardar(siguiente: false) } }
                .onKeyPress(.tab) {
                    Task { await guardar(siguiente: true) }
                    return .handled
                }
                .accessibilityLabel(columna.etiqueta)
            if columna.tipo == .dinero { Text("€").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color) }
            if columna.tipo == .porcentaje { Text("%").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color) }
        }
        if columna.tipo == .fecha {
            HStack(spacing: 6) {
                ForEach([("Hoy", 0), ("Mañana", 1), ("+1 semana", 7)], id: \.0) { nombre, dias in
                    Button(nombre) {
                        let d = modelo.hoy.adding(days: dias)
                        texto = String(format: "%02d/%02d/%04d", d.day, d.month, d.year)
                        Task { await guardar(siguiente: false) }
                    }
                    .tlsBoton(.secundario)
                }
                Button("Quitar") { texto = ""; Task { await guardar(siguiente: false) } }.tlsBoton(.enlace)
            }
        }
        if columna.tipo == .opciones, !columna.opciones.isEmpty {
            Text("Separa con comas: \(columna.opciones.map(FormatoBase.opcionVisible).joined(separator: ", "))")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var opciones: some View {
        let ops = EdicionCelda.opciones(columna, fila: fila)
        let actual = fila.valoresOpcion(columna).first.map(TextFolding.fold)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(ops, id: \.valor) { o in
                let elegida = actual == TextFolding.fold(o.valor)
                Button {
                    texto = o.valor
                    Task { await guardar(siguiente: false) }
                } label: {
                    HStack(spacing: TLSEspacio.e8) {
                        if o.motivo != nil {
                            Image(systemName: "lock").font(.system(size: 11)).accessibilityHidden(true)
                        } else if EstadoVisible.etapa(o.valor, coleccion: modelo.coleccion) == nil, let e = EstadoVisible.de(o.valor) {
                            Image(systemName: e.simbolo).foregroundStyle(e.color.color).font(.system(size: 11)).accessibilityHidden(true)
                        }
                        Text(FormatoBase.opcionVisible(o.valor)).tlsTexto(TLSTipo.interfazMedia)
                        Spacer(minLength: 0)
                        if elegida { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                    .foregroundStyle(o.motivo != nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                    .padding(.horizontal, 10)
                    .frame(minHeight: TLSAltura.objetivoMinimo)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                        .fill(elegida ? TLSPaleta.principalSuave.color : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tlsFocoPropio(radio: TLSRadio.fila)
                .disabled(o.motivo != nil || guardando)
                .help(o.motivo ?? "")
                .accessibilityLabel(FormatoBase.opcionVisible(o.valor) + (o.motivo.map { ", no se puede: \($0)" } ?? ""))
                .accessibilityAddTraits(elegida ? .isSelected : [])
            }
            if let motivo = ops.compactMap(\.motivo).first {
                Label(motivo, systemImage: "lock")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func guardar(siguiente: Bool) async {
        guard !guardando else { return }
        guardando = true
        defer { guardando = false }
        if texto == textoInicial, columna.tipo != .opcion {
            if siguiente { pasarALaSiguiente() } else { modelo.editando = nil }
            return
        }
        if let e = await modelo.guardar(fila, columna, texto: texto) {
            error = e
            return
        }
        if siguiente { pasarALaSiguiente() } else { modelo.editando = nil }
    }

    /// Tab: la siguiente celda que se puede escribir de la misma fila.
    private func pasarALaSiguiente() {
        let cols = modelo.columnasVisibles
        guard let i = cols.firstIndex(where: { $0.clave == columna.clave }) else { modelo.editando = nil; return }
        let siguiente = cols[(i + 1)...].first { c in
            ![.titulo, .calculada, .relacion, .siNo].contains(c.tipo) && modelo.motivoSoloLectura(fila, c) == nil
        }
        modelo.editando = siguiente.map { CeldaEnEdicion(fila: fila.id, columna: $0.clave) }
    }
}
