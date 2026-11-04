import AppKit
import SwiftUI
import TLSCore
import TLSDesign

/// Comparador de una columna para la cabecera de la `Table`: solo dice qué columna y en qué sentido; el orden
/// lo hace `MotorVista` (lo vacío siempre al final, las opciones en su orden).
struct ComparadorFila: SortComparator, Hashable {
    var clave: String
    var order: SortOrder = .forward

    func compare(_ a: FilaBase, _ b: FilaBase) -> ComparisonResult {
        let r = a.titulo.localizedStandardCompare(b.titulo)
        return order == .forward ? r : (r == .orderedAscending ? .orderedDescending : (r == .orderedDescending ? .orderedAscending : r))
    }
}

/// Tabla (§4.4, §7.4): columnas del diccionario, clic en la cabecera ordena, se arrastran para reordenar y se
/// ensanchan; grupos plegables con subtotal; densidad compacta. Clic elige, doble clic o ↩ entra, la barra
/// espaciadora abre la vista previa; clic en una celda la edita.
struct VistaTablaBase: View {
    @Bindable var modelo: BaseModelo
    @Environment(\.navegar) private var navegar
    @State private var personalizacion = TableColumnCustomization<FilaBase>()
    @State private var restaurada = false

    var body: some View {
        let columnas = modelo.columnasVisibles
        let grupos = modelo.grupos
        let filas = modelo.filas
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Table(of: FilaBase.self, selection: $modelo.seleccion, sortOrder: orden, columnCustomization: $personalizacion) {
                TableColumnForEach(columnas) { col in
                    TableColumn(col.etiqueta, sortUsing: ComparadorFila(clave: col.clave)) { fila in
                        CeldaBase(fila: fila, columna: col, modelo: modelo)
                    }
                    .width(min: 56, ideal: modelo.config.anchos[col.clave] ?? col.ancho, max: 640)
                    .alignment(col.esCifra ? .trailing : .leading)
                    .customizationID(col.clave)
                }
            } rows: {
                if let grupos {
                    ForEach(grupos) { g in
                        Section {
                            if !modelo.config.plegados.contains(g.id) {
                                ForEach(g.filas) { TableRow($0) }
                            }
                        } header: {
                            CabeceraGrupo(grupo: g, plegado: modelo.config.plegados.contains(g.id), columna: modelo.coleccion.columna(modelo.config.agrupar ?? ""),
                                          coleccion: modelo.coleccion) {
                                modelo.plegar(g.id)
                            }
                        }
                    }
                } else {
                    ForEach(filas) { TableRow($0) }
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            // El fondo de la tabla es la superficie de Mosaico (en oscuro, #10142A; la del sistema es gris neutro).
            .scrollContentBackground(.hidden)
            .background(TLSPaleta.superficie.color)
            .environment(\.defaultMinListRowHeight, modelo.config.densidad == .compacta ? TLSAltura.filaTablaCompacta : TLSAltura.filaTabla)
            .contextMenu(forSelectionType: String.self) { ids in
                MenuFilas(modelo: modelo, ids: ids)
            } primaryAction: { ids in
                guard let id = ids.first, let f = modelo.fila(id) else { return }
                modelo.abrir(f, navegar: navegar)
            }
            .onKeyPress(.space) {
                modelo.vistaPrevia(modelo.elegidas.first)
                return .handled
            }
            .onChange(of: personalizacion) { _, nueva in sincronizar(nueva, columnas: columnas) }
            .onAppear(perform: restaurar)
            .accessibilityLabel("\(modelo.coleccion.nombre): \(FormatoBase.cuenta(filas.count, "ficha", "fichas"))")
            if modelo.coleccion.creaConTitulo, modelo.motivoSinCrear == nil {
                FilaCreacion(modelo: modelo)
            }
            Text("Clic en una fila para elegirla; doble clic o ↩ abre su ficha y la barra espaciadora, su vista previa. Clic en una celda para cambiarla: ↩ guarda, Tab pasa a la siguiente y Esc cierra. Lo que lleva el signo de función o un candado no se escribe aquí: al pasar el puntero dice por qué.")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// El orden de la cabecera, como `config.orden` (lo urgente primero = sin flecha).
    private var orden: Binding<[ComparadorFila]> {
        Binding(get: {
            modelo.config.orden.filter { $0.clave != OrdenBase.urgente.clave }
                .map { ComparadorFila(clave: $0.clave, order: $0.ascendente ? .forward : .reverse) }
        }, set: { nuevos in
            modelo.config.orden = nuevos.isEmpty ? [.urgente] : nuevos.prefix(1).map { OrdenBase($0.clave, ascendente: $0.order == .forward) }
        })
    }

    private func restaurar() {
        guard !restaurada else { return }
        restaurada = true
        if let data = modelo.config.personalizacionTabla,
           let p = try? JSONDecoder().decode(TableColumnCustomization<FilaBase>.self, from: data) {
            personalizacion = p
        }
    }

    /// Lo que se cambia en la cabecera (ocultar, reordenar, ensanchar) se guarda con la vista; ocultar una
    /// columna desde la cabecera es lo mismo que quitarla en «Columnas…».
    private func sincronizar(_ p: TableColumnCustomization<FilaBase>, columnas: [ColumnaBase]) {
        var p = p
        var cambio = false
        for col in columnas where p[visibility: col.clave] == .hidden {
            modelo.mostrarColumna(col.clave, false)
            p[visibility: col.clave] = .automatic
            cambio = true
        }
        if cambio { personalizacion = p }
        modelo.config.personalizacionTabla = try? JSONEncoder().encode(p)
    }
}

/// Cabecera de un grupo: se pliega y dice cuántas hay y cuánto suman («Propuesta · 3 · 450 €»).
struct CabeceraGrupo: View {
    let grupo: GrupoFilas
    let plegado: Bool
    let columna: ColumnaBase?
    var coleccion: ColeccionBase? = nil
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: TLSEspacio.e8) {
                Image(systemName: plegado ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 12)
                if columna?.clave == "estado", EstadoVisible.de(grupo.titulo) != nil {
                    PastillaDeEstado(valor: grupo.titulo, coleccion: coleccion)
                } else {
                    Text(grupo.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                }
                Text(grupo.resumen).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer(minLength: 0)
            }
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tlsFocoPropio(radio: TLSRadio.fila)
        .accessibilityLabel("\(grupo.titulo), \(grupo.resumen)")
        .accessibilityHint(plegado ? "Despliega el grupo" : "Pliega el grupo")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Qué pastilla lleva cada estado: bien lo terminado, atención lo que espera algo de ti o va mal pronto, mal lo
/// que falló; el resto, sin dato (el estado nunca va solo con color: siempre con su palabra). Las etapas
/// abiertas del embudo de Oportunidades no son estados: van con `PastillaEtapa` (M2-Bases).
enum EstadoVisible {
    static func de(_ valor: String) -> TLSEstado? {
        let v = TextFolding.fold(valor)
        guard !v.isEmpty else { return nil }
        if ["ganada", "cobrada", "hecha", "aceptada", "activo", "activa", "publicado", "funciona sin ti", "resuelta",
            "cumplido", "tomada", "conciliado", "confirmado", "enviado", "enviada", "montado", "en uso"].contains(v) { return .bien }
        if ["perdida", "rechazada", "caducada", "bloqueada", "falta", "no cumplido", "grave"].contains(v) { return .mal }
        // «Emitida» y «Propuesta» son el camino normal (como en la cabecera de la ficha): sin dato.
        if ["pendiente de tu ok", "en revision", "borrador", "a medias", "pendiente", "por confirmar",
            "pausada", "pausado"].contains(v) { return .atencion }
        return .sinDato
    }

    /// Paso de una etapa abierta del embudo (0 = Prospecto) si la columna es la etapa de Oportunidades.
    static func etapa(_ valor: String, coleccion: ColeccionBase?) -> Int? {
        guard coleccion?.id == "oportunidades" else { return nil }
        let v = TextFolding.fold(valor)
        return CatalogoBases.etapasAbiertas.firstIndex { TextFolding.fold($0) == v }
    }
}

/// La pastilla de un estado o de una etapa del embudo (Oportunidades: Prospecto → Aceptada con sus puntos;
/// Ganada en Bien; Perdida y Pausada, sin dato), igual en la Tabla, la Lista, la Galería y los grupos.
struct PastillaDeEstado: View {
    let valor: String
    let coleccion: ColeccionBase?

    var body: some View {
        if let paso = EstadoVisible.etapa(valor, coleccion: coleccion) {
            PastillaEtapa(valor, paso: paso, de: CatalogoBases.etapasAbiertas.count)
        } else if coleccion?.id == "oportunidades" {
            PastillaEstado(TextFolding.fold(valor) == "ganada" ? .bien : .sinDato, palabra: valor)
        } else if let e = EstadoVisible.de(valor) {
            PastillaEstado(e, palabra: valor)
        }
    }
}

/// El menú de una o varias filas elegidas (clic derecho): abrir, vista previa, copiar enlace, mover.
struct MenuFilas: View {
    @Bindable var modelo: BaseModelo
    let ids: Set<String>
    @Environment(\.navegar) private var navegar

    var body: some View {
        let filas = ids.compactMap { modelo.fila($0) }
        if let f = filas.first, filas.count == 1 {
            Button("Abrir") { modelo.abrir(f, modo: .entrar, navegar: navegar) }
            Button("Abrir en pestaña nueva") { modelo.abrir(f, modo: .pestanaNueva, navegar: navegar) }
            Button("Abrir en ventana nueva") { modelo.abrir(f, modo: .ventanaNueva, navegar: navegar) }
            Button("Vista previa") { modelo.vistaPrevia(f) }
            let enlazadas = Self.enlazadas(f, modelo: modelo)
            if !enlazadas.isEmpty {
                Menu("Ir a") {
                    ForEach(Array(enlazadas.enumerated()), id: \.offset) { _, x in
                        Button("\(x.etiqueta): \(x.texto)") { navegar(modelo.sesion.destino(para: x.ruta), modo: .entrar) }
                    }
                }
            }
            if let enlace = modelo.sesion.enlaceParaCopiar(.ficha(f.ruta)), !f.esFilaCSV {
                Button("Copiar enlace") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(enlace, forType: .string)
                }
            }
            if let clave = modelo.claveTablero, let col = modelo.coleccion.columna(clave), col.tipo == .opcion,
               modelo.motivoSoloLectura(f, col) == nil {
                Menu("Mover a") {
                    ForEach(EdicionCelda.opciones(col, fila: f), id: \.valor) { o in
                        Button(FormatoBase.opcionVisible(o.valor)) { Task { await modelo.mover(f, a: o.valor) } }
                            .disabled(o.motivo != nil)
                    }
                }
            }
            Divider()
            Button("Mostrar en Finder") { modelo.sesion.revealInFinder(f.ruta) }
        } else {
            Text(FormatoBase.cuenta(filas.count, "ficha elegida", "fichas elegidas"))
        }
    }

    /// Lo enlazado en las columnas de relación visibles (sin lo privado), para «Ir a».
    static func enlazadas(_ f: FilaBase, modelo: BaseModelo) -> [(etiqueta: String, texto: String, ruta: VaultPath)] {
        modelo.columnasVisibles.filter { $0.tipo == .relacion }.flatMap { col in
            f.enlaces(col).compactMap { e in e.ruta.map { (col.etiqueta, e.texto, $0) } }
        }
        .filter { !modelo.sesion.esPrivado($0.2) }
    }
}

/// Fila de creación (§4.8) al final de la Tabla y la Lista: escribes el título y ↩ crea con lo de serie.
struct FilaCreacion: View {
    @Bindable var modelo: BaseModelo
    @State private var texto = ""
    @State private var creando = false

    var body: some View {
        HStack(spacing: TLSEspacio.e8) {
            Image(systemName: "plus").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
            TextField("\(modelo.coleccion.textoNueva): escribe el nombre y pulsa ↩", text: $texto)
                .textFieldStyle(.plain)
                .disabled(creando)
                .onSubmit(crear)
            if creando { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, TLSEspacio.e12)
        .frame(minHeight: TLSAltura.filaLista)
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
            .strokeBorder(TLSPaleta.separador.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityLabel(modelo.coleccion.textoNueva)
    }

    private func crear() {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !creando else { return }
        creando = true
        Task {
            var p = PeticionNueva()
            p.valores["titulo"] = t
            if let id = modelo.config.pestana, let pestana = modelo.datos?.pestanas.first(where: { $0.id == id }),
               case .valores(let clave, let vs) = pestana.filtro, let v = vs.first, !clave.hasPrefix("_") {
                p.poner[clave] = v
            }
            let r = await CreadorFichas.crear(coleccion: modelo.coleccion, peticion: p, sesion: modelo.sesion,
                                              deshacer: modelo.undoManager)
            creando = false
            if r != nil { texto = "" }
        }
    }
}
