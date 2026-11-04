import SwiftUI
import TLSCore
import TLSDesign

/// Una base (§4.3–§4.8): cabecera baja con tres cifras, pestañas por estado y vistas guardadas, la barra de la
/// base (vista, buscar ⌘F, Filtrar, Agrupar, Ordenar, Columnas, «+ Nueva …» ⌘N), los filtros como chips, la
/// vista elegida y el pie con de dónde salen las fichas.
struct BasePantalla: View {
    let id: String
    let vista: String?
    let contexto: VaultPath?
    let sesion: VaultSession
    @State private var modelo: BaseModelo?
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager

    init(id: String, vista: String?, contexto: VaultPath?, sesion: VaultSession) {
        self.id = id
        self.vista = vista
        self.contexto = contexto
        self.sesion = sesion
        if let c = CatalogoBases.coleccion(id) {
            _modelo = State(initialValue: BaseModelo(coleccion: c, sesion: sesion,
                                                     destino: .base(id, vista: vista, contexto: contexto),
                                                     contexto: contexto, vista: vista))
        }
    }

    var body: some View {
        if let modelo {
            ContenidoBase(modelo: modelo)
                .task(id: sesion.revision) {
                    modelo.nav = nav
                    modelo.undoManager = undoManager
                    await modelo.cargar()
                }
        } else {
            ContenedorPantalla(destino: .base(id, vista: vista, contexto: contexto)) {
                VacioExplicado(icono: "tablecells", titulo: "No conozco esta base",
                               porQue: "Puede que sea de un módulo que ya no está. Todas las demás siguen en «Todas las bases».")
            }
        }
    }
}

/// El cuerpo de una base, con su modelo ya hecho.
struct ContenidoBase: View {
    @Bindable var modelo: BaseModelo
    @Environment(\.navegar) private var navegar
    @Environment(\.undoManager) private var undoManager
    @FocusState private var buscadorEnfocado: Bool
    @State private var nombreVista = ""
    @State private var panel: PanelBase?
    @State private var ancho: CGFloat = 1000
    /// «Editar descripción»: el texto mientras se edita (`nil` = no se edita).
    @State private var descripcion: String?
    @State private var errorDescripcion: String?
    @State private var guardandoDescripcion = false
    @FocusState private var descripcionEnfocada: Bool

    enum PanelBase: String, Identifiable {
        case filtrar, columnas
        var id: String { rawValue }
    }

    private var c: ColeccionBase { modelo.coleccion }
    private var sesion: VaultSession { modelo.sesion }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                cabecera
                pestanas
                if modelo.nombrandoVista || modelo.hayCambios { barraGuardar }
                barra
                if !modelo.config.filtros.isEmpty || !modelo.sugerencias.isEmpty { chips }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, margen)
            .padding(.top, TLSEspacio.e24)
            .padding(.bottom, TLSEspacio.e12)
            contenido
                .padding(.horizontal, margen)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            pie
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .background { atajos }
        .sheet(item: $modelo.nueva) { peticion in
            HojaNuevaFicha(modelo: modelo, peticion: peticion)
        }
    }

    private var margen: CGFloat { TLSEspacio.margenPantalla(ancho: ancho) }

    // MARK: Cabecera (§4.3.1)

    private var cabecera: some View {
        let datos = modelo.datos
        let n = datos?.filas.count ?? 0
        let rotulo = ["Base", c.area.map { "\($0.numero) · \(sesion.area($0)?.titulo ?? $0.nombre)" },
                      datos.map { _ in FormatoBase.cuenta(n, "ficha", "fichas") }].compactMap { $0 }.joined(separator: " · ")
        let titulo = c.nombre + (modelo.contexto.map { " de \(sesion.titulo(de: $0))" } ?? "")
        return CabeceraAzulNoche(rotulo: rotulo, titulo: titulo,
                                 subtitulo: descripcion == nil ? (datos?.frase ?? c.frase) : nil,
                                 datos: (datos?.cifras ?? []).map { DatoClave($0.etiqueta, $0.valor) },
                                 altoMinimo: TLSAltura.cabeceraBase, cifrasALaDerecha: true) {
            if let a = c.tlsArea {
                IconoArea(a, tamano: 32, simbolo: c.icono, sobreCabecera: true)
            } else {
                AvatarCabecera(simbolo: c.icono)
            }
        } acciones: {
            Menu {
                if sesion.barraLateral.estaFijada(c.id) {
                    Button("Quitar de la barra lateral") { sesion.barraLateral.desfijarBase(c.id, deshacer: undoManager) }
                } else {
                    Button("Fijar en la barra lateral") { sesion.barraLateral.fijarBase(c.id, deshacer: undoManager) }
                }
                Button("Abrir en pestaña nueva") { navegar(modelo.destino, modo: .pestanaNueva) }
                if let nota = datos?.indice?.ruta {
                    Button("Abrir su nota índice") { navegar(.nota(nota), modo: .entrar) }
                }
                Divider()
                Button("Hacer «\(modelo.config.vista.nombre)» la vista por defecto") {
                    Task { await modelo.hacerVistaPorDefecto() }
                }
                .disabled(modelo.motivoSinPorDefecto != nil)
                if let m = modelo.motivoSinPorDefecto { Text(m) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(TLSPaleta.sobreColor.color)
            .fixedSize()
            .accessibilityLabel("Más acciones de \(c.nombre)")
        } debajo: {
            // M2-Bases: «Editar descripción» es un enlace bajo la frase y el campo se abre dentro de la cabecera.
            if descripcion != nil {
                editorDescripcion
            } else if datos?.indice != nil {
                Button("Editar descripción") {
                    errorDescripcion = nil
                    descripcion = datos?.frase ?? c.frase
                    descripcionEnfocada = true
                }
                .tlsBoton(.enlace)
                .disabled(modelo.motivoSinDescripcion != nil)
                .help(modelo.motivoSinDescripcion ?? "Cambia la frase de esta base; se guarda en su nota índice")
            }
        }
    }

    /// La descripción mientras se edita, dentro de la cabecera (M2-Bases): ↩ guarda en la nota índice (solo su
    /// primer párrafo, con Deshacer) y Esc cancela.
    private var editorDescripcion: some View {
        let blanco = TLSPaleta.sobreColor.color
        let suave = TLSPaleta.subtituloCabecera.color
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Descripción de la base · se guarda en su nota índice")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(suave)
            TextField("", text: Binding(get: { descripcion ?? "" }, set: { descripcion = $0 }),
                      prompt: Text("Qué guarda esta base, en una frase").foregroundStyle(suave))
                .textFieldStyle(.plain)
                .tlsTexto(TLSTipo.lectura)
                .foregroundStyle(blanco)
                .padding(.horizontal, 12)
                .frame(maxWidth: 640, minHeight: TLSAltura.botonPrincipal)
                .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(Color.white.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                    .strokeBorder(Color.white.opacity(descripcionEnfocada ? 1 : 0.55), lineWidth: descripcionEnfocada ? 2 : 1))
                .focused($descripcionEnfocada)
                .focusEffectDisabled()
                .onSubmit { Task { await guardarDescripcion() } }
                .onExitCommand { descripcion = nil }
                .accessibilityLabel("Descripción de \(c.nombre)")
            if let errorDescripcion {
                Label(errorDescripcion, systemImage: TLSEstado.mal.simbolo)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(blanco)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: TLSEspacio.e8) {
                Button("Guardar") { Task { await guardarDescripcion() } }
                    .tlsBoton(.sobreCabecera, alto: 32)
                    .disabled(guardandoDescripcion)
                Button("Cancelar") { descripcion = nil }
                    .tlsBoton(.enlace)
                Text("↩ guarda · Esc cancela").tlsTexto(TLSTipo.secundario).foregroundStyle(suave)
            }
        }
        .padding(.top, TLSEspacio.e4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editar la descripción de \(c.nombre)")
    }

    private func guardarDescripcion() async {
        guard let texto = descripcion, !guardandoDescripcion else { return }
        guardandoDescripcion = true
        defer { guardandoDescripcion = false }
        if let error = await modelo.guardarDescripcion(texto) {
            errorDescripcion = error
        } else {
            descripcion = nil
        }
    }

    // MARK: Pestañas (§4.3.2) y vistas guardadas (§4.6)

    @ViewBuilder private var pestanas: some View {
        let datos = modelo.datos
        let porEstado = datos?.pestanas ?? c.pestanas
        HStack(alignment: .center, spacing: TLSEspacio.e8) {
            if !porEstado.isEmpty {
                PestanasCapsula(seleccion: Binding(get: { modelo.config.pestana ?? PestanaBase.todas },
                                                   set: { modelo.elegirPestana($0) }),
                                pestanas: [PestanaCapsula(id: PestanaBase.todas, titulo: "Todas",
                                                          contador: datos.map { MotorVista.cuenta(nil, datos: $0) })]
                                    + porEstado.map { p in
                                        PestanaCapsula(id: p.id, titulo: p.titulo,
                                                       contador: datos.map { MotorVista.cuenta(p, datos: $0) })
                                    })
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !modelo.todasLasVistas.isEmpty || porEstado.isEmpty {
                if !porEstado.isEmpty {
                    Rectangle().fill(TLSPaleta.separador.color).frame(width: 1, height: 24).accessibilityHidden(true)
                }
                PestanasCapsula(seleccion: Binding(get: { modelo.vistaActiva ?? "" },
                                                   set: { modelo.elegirVistaGuardada($0.isEmpty ? nil : $0) }),
                                pestanas: [PestanaCapsula(id: "", titulo: porEstado.isEmpty ? "Todas" : "De serie",
                                                          contador: porEstado.isEmpty ? datos.map { MotorVista.cuenta(nil, datos: $0) } : nil)]
                                    // Cada vista con cuántas fichas enseña (M2-Bases).
                                    + modelo.todasLasVistas.map { v in
                                        PestanaCapsula(id: v.id, titulo: v.nombre,
                                                       contador: datos.map { MotorVista.filas($0, config: v.config).count })
                                    },
                                atajosControl: porEstado.isEmpty)
                    .fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        if let id = modelo.vistaActiva, modelo.vistaActivaEsTuya {
                            Button("Quitar esta vista") { modelo.quitarVista(id) }
                        }
                    }
            }
            if !modelo.nombrandoVista {
                Button {
                    nombreVista = ""
                    modelo.nombrandoVista = true
                } label: {
                    Label("Guardar vista", systemImage: "plus").padding(.horizontal, 8)
                }
                .tlsBoton(.discreto)
                // Borde discontinuo, como «Relacionar» (M2-Bases): crea algo nuevo, no es una pestaña más.
                .overlay(Capsule(style: .circular)
                    .strokeBorder(TLSPaleta.bordeControl.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .allowsHitTesting(false))
                .help("Guarda la vista actual como pestaña")
            }
            Spacer(minLength: 0)
        }
    }

    /// «Guardar vista» con su nombre, o los cambios sin guardar de la vista activa.
    @ViewBuilder private var barraGuardar: some View {
        HStack(spacing: TLSEspacio.e8) {
            if modelo.nombrandoVista {
                Text("Nombre de la vista").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                TextField("Por ejemplo: Lo de Lucía", text: $nombreVista)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onSubmit { modelo.guardarVistaComo(nombreVista) }
                    .onExitCommand { modelo.nombrandoVista = false }
                Button("Guardar") { modelo.guardarVistaComo(nombreVista) }
                    .tlsBoton(.principal, alto: 32)
                    .disabled(nombreVista.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancelar") { modelo.nombrandoVista = false }.tlsBoton(.secundario)
            } else {
                let nombre = modelo.todasLasVistas.first { $0.id == modelo.vistaActiva }?.nombre
                Image(systemName: "pencil.circle").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                Text(nombre.map { "Has cambiado «\($0)»." } ?? "Has cambiado cómo se ve la base.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                if modelo.vistaActivaEsTuya {
                    Button("Guardar cambios") { modelo.guardarCambiosVista() }.tlsBoton(.principal, alto: 32)
                }
                Button("Guardar como…") { nombreVista = ""; modelo.nombrandoVista = true }.tlsBoton(.secundario)
                Button("Descartar cambios") { modelo.descartarCambios() }.tlsBoton(.enlace)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TLSEspacio.e12)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
    }

    // MARK: Barra de la base (§4.3.3)

    /// Cuánto cabe en la barra (M2-Bases: las palabras se quedan y la barra salta a una segunda línea): todo en
    /// una línea; en dos (vista, buscador y «Nueva» arriba; las herramientas con su nombre debajo); y solo en una
    /// ventana muy estrecha, las herramientas con icono.
    enum NivelBarra { case completa, dosLineas, compacta }

    private var barra: some View {
        ViewThatFits(in: .horizontal) {
            barraContenido(.completa)
            barraContenido(.dosLineas)
            barraContenido(.compacta)
        }
    }

    @ViewBuilder private func barraContenido(_ nivel: NivelBarra) -> some View {
        switch nivel {
        case .completa:
            HStack(spacing: TLSEspacio.e8) {
                selectorVista(compacta: false)
                buscador(corto: false).frame(minWidth: 180, maxWidth: 300)
                herramientas(compacta: false)
                Spacer(minLength: TLSEspacio.e8)
                botonNueva(corto: false)
            }
        case .dosLineas:
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                HStack(spacing: TLSEspacio.e8) {
                    selectorVista(compacta: false)
                    buscador(corto: true).frame(minWidth: 180, maxWidth: 300)
                    Spacer(minLength: TLSEspacio.e8)
                    botonNueva(corto: true)
                }
                HStack(spacing: TLSEspacio.e8) {
                    herramientas(compacta: false)
                    Spacer(minLength: 0)
                }
            }
        case .compacta:
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                HStack(spacing: TLSEspacio.e8) {
                    selectorVista(compacta: true)
                    buscador(corto: true).frame(minWidth: 140, maxWidth: 220)
                    Spacer(minLength: TLSEspacio.e8)
                    botonNueva(corto: true)
                }
                HStack(spacing: TLSEspacio.e8) {
                    herramientas(compacta: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Filtrar, Agrupar, Orden, Columnas (en la Tabla) y Más, con los iconos de §1.11.
    @ViewBuilder private func herramientas(compacta: Bool) -> some View {
        botonHerramienta("Filtrar" + (modelo.config.filtros.isEmpty ? "" : " · \(modelo.config.filtros.count)"),
                         icono: "line.3.horizontal.decrease.circle", compacta: compacta) { panel = .filtrar }
            .popover(item: Binding(get: { panel == .filtrar ? panel : nil }, set: { panel = $0 }), arrowEdge: .bottom) { _ in
                PanelFiltrar(modelo: modelo) { panel = nil }
            }
        menuAgrupar(compacta: compacta)
        menuOrdenar(compacta: compacta)
        if modelo.config.vista == .tabla {
            botonHerramienta("Columnas", icono: "slider.horizontal.3", compacta: compacta) { panel = .columnas }
                .popover(item: Binding(get: { panel == .columnas ? panel : nil }, set: { panel = $0 }), arrowEdge: .bottom) { _ in
                    PanelColumnas(modelo: modelo)
                }
        }
        menuMas(compacta: compacta)
    }

    private func botonNueva(corto: Bool) -> some View {
        BotonPrincipal(corto ? (c.femenino ? "Nueva" : "Nuevo") : c.textoNueva, icono: "plus",
                       motivoDesactivado: modelo.motivoSinCrear) {
            modelo.abrirNueva()
        }
        .fixedSize()
        .help("⌘N dentro de la base")
    }

    private func selectorVista(compacta: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(c.vistas, id: \.self) { v in
                let elegida = modelo.config.vista == v
                Button { modelo.cambiarVista(v) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: v.simbolo).font(.system(size: 12, weight: .medium))
                        if !compacta { Text(v.nombre).tlsTexto(TLSTipo.interfazMedia) }
                    }
                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                    .padding(.horizontal, compacta ? 8 : 10)
                    .frame(minWidth: TLSAltura.objetivoMinimo, minHeight: TLSAltura.objetivoMinimo)
                    .background(Capsule(style: .circular).fill(elegida ? TLSPaleta.principal.color : Color.clear))
                    .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .tlsFocoPropio(radio: 999)
                .help(v.nombre)
                .accessibilityLabel(v.nombre)
                .accessibilityAddTraits(elegida ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vista")
    }

    /// `corto`: con la barra apretada, «Buscar…» (el nombre de la base ya está en la cabecera y no cabría).
    private func buscador(corto: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
            TextField(corto ? "Buscar…" : "Buscar en \(c.nombre)", text: $modelo.busqueda)
                .textFieldStyle(.plain)
                .focused($buscadorEnfocado)
                .onExitCommand { modelo.busqueda = ""; buscadorEnfocado = false }
                .onSubmit {
                    if let s = modelo.sugerencias.first, modelo.filas.isEmpty { modelo.aplicarSugerencia(s) }
                }
            if !modelo.busqueda.isEmpty {
                Button { modelo.busqueda = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityLabel("Borrar la búsqueda")
            } else {
                Tecla("⌘F")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: TLSAltura.objetivoMinimo + 4)
        .background(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous)
            .strokeBorder(buscadorEnfocado ? TLSPaleta.principal.color : TLSPaleta.separador.color, lineWidth: buscadorEnfocado ? 2 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Buscar en \(c.nombre)")
    }

    private func botonHerramienta(_ titulo: String, icono: String, compacta: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                Image(systemName: icono)
                if !compacta { Text(titulo).lineLimit(1) }
            }
        }
        .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
        .fixedSize()
        .help(titulo)
        .accessibilityLabel(titulo)
    }

    private func menuAgrupar(compacta: Bool) -> some View {
        let actual = modelo.config.agrupar.flatMap { c.columna($0)?.etiqueta }
        let titulo = actual.map { "Agrupar: \($0)" } ?? "Agrupar"
        return Menu {
            Button { modelo.config.agrupar = nil } label: { marca("Sin agrupar", modelo.config.agrupar == nil) }
            Divider()
            ForEach(c.columnas.filter { [.opcion, .opciones, .relacion, .persona, .fecha].contains($0.tipo) }) { col in
                Button { modelo.config.agrupar = col.clave } label: { marca(col.etiqueta, modelo.config.agrupar == col.clave) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.3.group")
                if !compacta { Text(titulo).lineLimit(1) }
            }
        }
        .menuStyle(.button)
        .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
        .fixedSize()
        .help(titulo)
        .accessibilityLabel(titulo)
    }

    private func menuOrdenar(compacta: Bool) -> some View {
        let orden = modelo.config.orden.first ?? .urgente
        let nombre = orden.clave == OrdenBase.urgente.clave ? "Lo urgente primero" : (c.columna(orden.clave)?.etiqueta ?? orden.clave)
        return Menu {
            Button { modelo.config.orden = [.urgente] } label: { marca("Lo urgente primero", orden.clave == OrdenBase.urgente.clave) }
            Divider()
            ForEach(c.columnas) { col in
                Menu(col.etiqueta) {
                    Button { modelo.ordenar(por: col.clave, ascendente: true) } label: {
                        marca(Self.textoOrden(col, ascendente: true), orden.clave == col.clave && orden.ascendente)
                    }
                    Button { modelo.ordenar(por: col.clave, ascendente: false) } label: {
                        marca(Self.textoOrden(col, ascendente: false), orden.clave == col.clave && !orden.ascendente)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                if !compacta { Text("Orden: \(nombre)").lineLimit(1) }
            }
        }
        .menuStyle(.button)
        .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
        .fixedSize()
        .help("Orden: \(nombre)")
        .accessibilityLabel("Orden: \(nombre)")
    }

    static func textoOrden(_ col: ColumnaBase, ascendente: Bool) -> String {
        switch col.tipo {
        case .dinero, .porcentaje, .numero, .calculada: ascendente ? "De menor a mayor" : "De mayor a menor"
        case .fecha: ascendente ? "De la más antigua a la más nueva" : "De la más nueva a la más antigua"
        case .opcion: ascendente ? "En su orden" : "Al revés"
        default: ascendente ? "De la A a la Z" : "De la Z a la A"
        }
    }

    private func menuMas(compacta: Bool) -> some View {
        Menu {
            if modelo.config.vista == .tabla {
                Toggle("Filas compactas", isOn: Binding(get: { modelo.config.densidad == .compacta },
                                                        set: { modelo.config.densidad = $0 ? .compacta : .normal }))
            }
            if modelo.config.vista == .galeria {
                Picker("Tamaño de las tarjetas", selection: $modelo.config.tamanoGaleria) {
                    ForEach(TamanoGaleria.allCases, id: \.self) { Text($0.nombre).tag($0) }
                }
            }
            if modelo.config.vista == .calendario || modelo.config.vista == .cronograma {
                Picker("Fecha que se usa", selection: Binding(get: { modelo.config.fechaCalendario ?? c.fechaCalendario ?? "" },
                                                             set: { modelo.config.fechaCalendario = $0 })) {
                    ForEach(c.columnas.filter { $0.tipo == .fecha }) { Text($0.etiqueta).tag($0.clave) }
                }
            }
            Divider()
            Button("Hacer «\(modelo.config.vista.nombre)» la vista por defecto") { Task { await modelo.hacerVistaPorDefecto() } }
                .disabled(modelo.motivoSinPorDefecto != nil)
            Button("Quitar los filtros") { modelo.quitarFiltros() }.disabled(modelo.config.filtros.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
        .fixedSize()
        .help("Más opciones de la vista")
        .accessibilityLabel("Más opciones de la vista")
    }

    @ViewBuilder private func marca(_ texto: String, _ elegida: Bool) -> some View {
        if elegida { Label(texto, systemImage: "checkmark") } else { Text(texto) }
    }

    // MARK: Filtros activos (§4.3.4)

    private var chips: some View {
        FlowChips {
            if !modelo.sugerencias.isEmpty {
                Text("Parece un filtro:").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                ForEach(modelo.sugerencias) { s in
                    Button { modelo.aplicarSugerencia(s) } label: {
                        Label(s.etiqueta, systemImage: "line.3.horizontal.decrease")
                    }
                    .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo)
                }
            }
            ForEach(modelo.config.filtros) { f in
                Chip(f.etiqueta(en: c), icono: "line.3.horizontal.decrease", etiquetaQuitar: "Quitar el filtro \(f.etiqueta(en: c))") {
                    modelo.quitarFiltro(f)
                }
            }
            if modelo.config.filtros.count > 1 {
                Button("Quitar todos") { modelo.quitarFiltros() }.tlsBoton(.enlace)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filtros activos")
    }

    // MARK: Contenido (§4.4)

    @ViewBuilder private var contenido: some View {
        if modelo.cargando && modelo.datos == nil {
            ProgressView("Leyendo \(c.nombre.lowercased())…")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let datos = modelo.datos, datos.apagada {
            VacioExplicado(icono: "power", titulo: "\(c.nombre): módulo apagado",
                           porQue: "Tus fichas se quedan en la carpeta. Enciéndelo en «Todas las bases» para verlas aquí.")
        } else if modelo.filas.isEmpty && modelo.config.vista != .calendario {
            vacio
        } else {
            switch modelo.config.vista {
            case .tabla: VistaTablaBase(modelo: modelo)
            case .tablero: VistaTableroBase(modelo: modelo)
            case .lista: VistaListaBase(modelo: modelo)
            case .galeria: VistaGaleriaBase(modelo: modelo)
            case .calendario: VistaCalendarioBase(modelo: modelo)
            case .cronograma: VistaCronogramaBase(modelo: modelo)
            }
        }
    }

    @ViewBuilder private var vacio: some View {
        if (modelo.datos?.filas.isEmpty ?? true) {
            VacioExplicado(icono: c.icono, titulo: "Aún no hay \(c.nombre.lowercased())",
                           porQue: "Las \(c.nombre.lowercased()) salen de \(sesion.estructura?.expand(c.hogar).raw ?? c.hogar). "
                               + (c.plantilla != nil ? "Crea la primera desde aquí: la app le pone nombre y la guarda en su sitio."
                                                    : (c.motivoSinCrear ?? "")),
                           accion: c.plantilla != nil && modelo.motivoSinCrear == nil ? c.textoNueva : nil,
                           alPulsar: { modelo.abrirNueva() })
        } else {
            VacioExplicado(icono: "line.3.horizontal.decrease", titulo: "Ninguna ficha cumple esto",
                           porQue: "Prueba con otra palabra o quita algún filtro. Hay \(FormatoBase.cuenta(modelo.datos?.filas.count ?? 0, "ficha", "fichas")) en esta base.",
                           accion: modelo.busqueda.isEmpty ? nil : "Borrar la búsqueda", alPulsar: { modelo.busqueda = "" },
                           secundaria: modelo.config.filtros.isEmpty && modelo.config.pestana == nil ? nil : "Quitar los filtros",
                           alPulsarSecundaria: { modelo.quitarFiltros(); modelo.elegirPestana(nil) })
        }
    }

    // MARK: Pie (§4.3.6)

    private var pie: some View {
        HStack(spacing: TLSEspacio.e8) {
            if let datos = modelo.datos {
                Text(datos.pie).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                Text("· \(FormatoBase.cuenta(modelo.filas.count, "se ve", "se ven"))")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if let contexto = modelo.contexto {
                Text("· Solo las que enlazan «\(sesion.titulo(de: contexto))»")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                Button("Ver todas") { navegar(.base(c.id), modo: .entrar) }.tlsBoton(.enlace)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, margen)
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    // MARK: Atajos

    private var atajos: some View {
        ZStack {
            Button("") { buscadorEnfocado = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { modelo.abrirNueva() }.keyboardShortcut("n", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Fila de chips que salta de línea cuando no cabe.
struct FlowChips<Contenido: View>: View {
    @ViewBuilder let contenido: Contenido

    var body: some View {
        FlowLayout(espacio: TLSEspacio.e8) { contenido }
    }
}

/// Coloca sus hijos en filas, saltando de línea cuando no caben.
struct FlowLayout: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? 1000
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            maxX = max(maxX, x - espacio)
            alto = max(alto, t.height)
        }
        return CGSize(width: min(maxX, ancho), height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + t.width > bounds.maxX { x = bounds.minX; y += alto + espacio; alto = 0 }
            s.place(at: CGPoint(x: x, y: y + 0), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
    }
}
