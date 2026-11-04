import SwiftUI
import TLSCore
import TLSDesign

/// «Filtrar» (§4.5): un grupo por cada propiedad de opción, persona o relación con sus valores y cuántas
/// fichas tiene cada uno, y «+ Filtro» con propiedad → condición → valor. Los filtros se suman («y»); dentro de
/// un grupo vale cualquiera («alguna de»).
struct PanelFiltrar: View {
    @Bindable var modelo: BaseModelo
    let cerrar: () -> Void
    @State private var clave = ""
    @State private var condicion: CondicionFiltro = .contiene
    @State private var valor = ""

    private var c: ColeccionBase { modelo.coleccion }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text("Filtrar").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
            ScrollView {
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    ForEach(grupos, id: \.columna.clave) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Rotulo(g.columna.etiqueta)
                            FlowLayout(espacio: 6) {
                                ForEach(g.valores, id: \.valor) { v in
                                    let on = elegidos(g.columna).contains(v.valor)
                                    Button { alternar(g.columna, v.valor) } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: on ? "checkmark.square.fill" : "square").accessibilityHidden(true)
                                            Text(v.texto).tlsTexto(TLSTipo.interfazMedia)
                                            Text("\(v.n)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: TLSAltura.objetivoMinimo)
                                        .background(Capsule(style: .circular).fill(on ? TLSPaleta.principalSuave.color : TLSPaleta.bandeja.color))
                                        .contentShape(Capsule(style: .circular))
                                    }
                                    .buttonStyle(.plain)
                                    .tlsFocoPropio(radio: 999)
                                    .accessibilityLabel("\(g.columna.etiqueta) \(v.texto), \(v.n)")
                                    .accessibilityAddTraits(on ? .isSelected : [])
                                }
                            }
                        }
                    }
                    personalizado
                }
            }
            .frame(maxHeight: 420)
            HStack {
                Text("Los filtros se suman: tienen que cumplirse todos. Dentro de un mismo grupo vale cualquiera.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TLSEspacio.e8)
                Button("Listo", action: cerrar).tlsBoton(.principal, alto: 32).keyboardShortcut(.defaultAction)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(width: 460)
    }

    private struct Grupo {
        let columna: ColumnaBase
        let valores: [(valor: String, texto: String, n: Int)]
    }

    /// Grupos de valores que hay en las fichas, en el orden del diccionario.
    private var grupos: [Grupo] {
        guard let datos = modelo.datos else { return [] }
        return c.columnas.compactMap { col in
            guard [.opcion, .opciones, .persona, .relacion].contains(col.tipo) else { return nil }
            var cuenta: [String: (String, Int)] = [:]
            for f in datos.filas {
                let vs: [(String, String)] = col.tipo == .relacion ? f.enlaces(col).map { ($0.texto, $0.texto) }
                    : f.valoresOpcion(col).map { ($0, col.tipo == .persona ? FormatoBase.persona($0) : FormatoBase.opcionVisible($0)) }
                for (v, t) in vs { cuenta[v, default: (t, 0)].1 += 1 }
            }
            guard !cuenta.isEmpty else { return nil }
            let orden = cuenta.keys.sorted { a, b in
                let ia = col.opciones.firstIndex { TextFolding.fold($0) == TextFolding.fold(a) } ?? Int.max
                let ib = col.opciones.firstIndex { TextFolding.fold($0) == TextFolding.fold(b) } ?? Int.max
                return ia != ib ? ia < ib : a.localizedStandardCompare(b) == .orderedAscending
            }
            return Grupo(columna: col, valores: orden.map { ($0, cuenta[$0]!.0, cuenta[$0]!.1) })
        }
    }

    private func condicionDe(_ col: ColumnaBase) -> CondicionFiltro { col.tipo == .relacion ? .enlazaCon : .es }

    private func elegidos(_ col: ColumnaBase) -> [String] {
        modelo.config.filtros.first { $0.clave == col.clave && $0.condicion == condicionDe(col) }?.valores ?? []
    }

    private func alternar(_ col: ColumnaBase, _ v: String) {
        let cond = condicionDe(col)
        var filtros = modelo.config.filtros
        if let i = filtros.firstIndex(where: { $0.clave == col.clave && $0.condicion == cond }) {
            if filtros[i].valores.contains(v) { filtros[i].valores.removeAll { $0 == v } } else { filtros[i].valores.append(v) }
            if filtros[i].valores.isEmpty { filtros.remove(at: i) }
        } else {
            filtros.append(FiltroBase(col.clave, cond, [v]))
        }
        modelo.config.filtros = filtros
    }

    /// «+ Filtro»: propiedad → condición → valor.
    private var personalizado: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rotulo("+ Filtro")
            HStack(spacing: 6) {
                Picker("Propiedad", selection: $clave) {
                    Text("Elige una propiedad").tag("")
                    ForEach(c.columnas) { Text($0.etiqueta).tag($0.clave) }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: clave) { _, k in
                    if let col = c.columna(k) { condicion = CondicionFiltro.para(col).first ?? .contiene }
                }
                Picker("Condición", selection: $condicion) {
                    ForEach(c.columna(clave).map(CondicionFiltro.para) ?? CondicionFiltro.allCases, id: \.self) {
                        Text($0.texto).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                if !condicion.sinValor {
                    TextField(c.columna(clave)?.tipo == .fecha ? "hoy o 24/10/2026" : "Valor", text: $valor)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onSubmit(anadir)
                }
                Button("Añadir", action: anadir)
                    .tlsBoton(.secundario)
                    .disabled(clave.isEmpty || (!condicion.sinValor && valor.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
    }

    private func anadir() {
        guard !clave.isEmpty else { return }
        var v = valor.trimmingCharacters(in: .whitespaces)
        if c.columna(clave)?.tipo == .fecha {
            if TextFolding.fold(v) == "hoy" { v = FiltroBase.hoy } else if let d = EdicionCelda.fecha(v, hoy: modelo.hoy) { v = d.description }
        }
        modelo.anadirFiltro(FiltroBase(clave, condicion, condicion.sinValor ? [] : [v]))
        valor = ""
    }
}

/// «Columnas…» (§4.7): casillas para enseñar u ocultar, flechas para ordenar (también con VoiceOver), qué tipo
/// es cada una y «Restaurar las de serie». Cada columna se puede agrupar u ordenar desde aquí.
struct PanelColumnas: View {
    @Bindable var modelo: BaseModelo

    private var c: ColeccionBase { modelo.coleccion }

    var body: some View {
        let visibles = modelo.config.columnas
        let todas = visibles.compactMap { c.columna($0) } + c.columnas.filter { !visibles.contains($0.clave) }
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack {
                Text("Columnas · \(visibles.count) de \(c.columnas.count)")
                    .tlsTexto(TLSTipo.tituloModulo)
                    .foregroundStyle(TLSPaleta.texto.color)
                Spacer()
                Button("Restaurar las de serie") { modelo.restaurarColumnas() }.tlsBoton(.enlace)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(todas) { col in fila(col, visible: visibles.contains(col.clave), ultima: visibles.last == col.clave,
                                                 primera: visibles.first == col.clave) }
                }
            }
            .frame(maxHeight: 380)
            Toggle("Filas compactas", isOn: Binding(get: { modelo.config.densidad == .compacta },
                                                    set: { modelo.config.densidad = $0 ? .compacta : .normal }))
                .toggleStyle(.checkbox)
            Text("Las que dicen «Se calcula» no se escriben: salen de otras propiedades. También puedes arrastrar las columnas en la cabecera de la tabla.")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e16)
        .frame(width: 400)
    }

    private func fila(_ col: ColumnaBase, visible: Bool, ultima: Bool, primera: Bool) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(get: { visible }, set: { modelo.mostrarColumna(col.clave, $0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(col.etiqueta).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                    Text(Self.tipo(col)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(visible && modelo.config.columnas.count == 1)
            Spacer(minLength: 0)
            if visible {
                Button { modelo.moverColumna(col.clave, -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain)
                    .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                    .disabled(primera)
                    .accessibilityLabel("Subir \(col.etiqueta)")
                Button { modelo.moverColumna(col.clave, 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain)
                    .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                    .disabled(ultima)
                    .accessibilityLabel("Bajar \(col.etiqueta)")
            }
            Menu {
                if [.opcion, .opciones, .relacion, .persona, .fecha].contains(col.tipo) {
                    Button("Agrupar por esta") { modelo.config.agrupar = col.clave }
                }
                Button("Ordenar de menor a mayor") { modelo.ordenar(por: col.clave, ascendente: true) }
                Button("Ordenar de mayor a menor") { modelo.ordenar(por: col.clave, ascendente: false) }
                if col.tipo != .calculada { Button("Filtrar: no está vacía") { modelo.anadirFiltro(FiltroBase(col.clave, .noEstaVacia)) } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(minWidth: TLSAltura.objetivoMinimo, minHeight: TLSAltura.objetivoMinimo)
            .accessibilityLabel("Más de \(col.etiqueta)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if visible && !primera { Button("Subir \(col.etiqueta)") { modelo.moverColumna(col.clave, -1) } }
            if visible && !ultima { Button("Bajar \(col.etiqueta)") { modelo.moverColumna(col.clave, 1) } }
        }
    }

    /// «Relación con Empresas», «Dinero», «Se calcula».
    static func tipo(_ col: ColumnaBase) -> String {
        switch col.tipo {
        case .titulo: "Nombre · va siempre"
        case .texto: "Texto"
        case .opcion: "Opción"
        case .opciones: "Varias opciones"
        case .fecha: "Fecha"
        case .dinero: "Dinero"
        case .porcentaje: "Porcentaje"
        case .numero: "Número"
        case .relacion: col.relacionCon.flatMap { CatalogoBases.coleccion($0) }.map { "Relación con \($0.nombre)" } ?? "Relación"
        case .persona: "Persona o asistente"
        case .siNo: "Sí o no"
        case .calculada: "Se calcula" + (col.explicacion.map { ": " + $0.prefix(1).lowercased() + $0.dropFirst() } ?? "")
        }
    }
}
