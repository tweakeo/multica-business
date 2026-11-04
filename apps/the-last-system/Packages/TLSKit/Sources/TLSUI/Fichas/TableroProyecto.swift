import SwiftUI
import TLSCore
import TLSDesign
import UniformTypeIdentifiers

/// Pestaña Tareas del proyecto (§3.4): tablero por estado (o por fase) y, a la derecha, el panel de la tarea
/// elegida. Arrastrar una tarjeta a otra columna cambia su estado (una línea); lo mismo con «Mover a…» del menú
/// y, con la tarjeta elegida, ⌘← y ⌘→. Clic elige; doble clic o «Abrir como ficha» entra un nivel. ⌥⌘I cambia el
/// panel por el de propiedades del proyecto.
struct TableroProyecto: View {
    let modelo: FichaModelo
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @State private var porFase = false
    @State private var enLista = false
    /// Tarjeta con el foco del teclado (Tab la alcanza; al enfocarla queda elegida para ⌘← y ⌘→).
    @FocusState private var enfocada: VaultPath?
    @State private var nueva = ""
    @State private var escribiendo = false
    @State private var sobre: String?
    /// Ancho visible del tablero: las columnas lo reparten y, si no caben a 176 pt, se desplaza en horizontal.
    @State private var anchoTablero: CGFloat = 800

    static let columnasBase: [EstadoTarea] = [.porHacer, .enCurso, .enRevision, .hecha]

    var body: some View {
        let tareas = filtradas
        HStack(alignment: .top, spacing: TLSEspacio.e16) {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                barra
                if escribiendo { nuevaTarea }
                if modelo.relacionados([.task]).isEmpty {
                    VacioExplicado(icono: "checkmark.square", titulo: "Aún no tiene tareas",
                                   porQue: "Crea la primera con «Nueva tarea» o añade una que ya exista: la tarea guarda el proyecto en «proyecto».",
                                   accion: "Nueva tarea", alPulsar: { escribiendo = true }, compacto: true)
                } else if enLista {
                    lista(tareas)
                } else {
                    let cols = columnas(tareas)
                    let anchoColumna = Self.anchoColumna(visible: anchoTablero, columnas: cols.count)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: TLSEspacio.e12) {
                            ForEach(cols, id: \.clave) { c in columna(c, ancho: anchoColumna) }
                        }
                        .padding(.bottom, 4)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { anchoTablero = $0 }
                }
                Text(porFase ? "La fase sale del plan de entrega, así que aquí no se arrastra. «Mover a…» cambia el estado."
                        : "Clic (o Tab) en una tarjeta: se abre en el panel. Arrastra a otra columna, o usa «Mover a…»; con la tarjeta elegida, ⌘← y ⌘→.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            if let t = elegida, !modelo.sesion.showInspector {
                PanelTarea(modelo: modelo, tarea: t) { seleccionar(nil) }
                    .frame(width: 400)
            }
        }
        .background(alignment: .topLeading) { atajos }
        // Con el teclado, la tarjeta enfocada queda elegida (para ⌘← ⌘→ y su panel), como al pulsarla.
        .onChange(of: enfocada) { _, r in if let r, r != elegida { seleccionar(r) } }
    }

    /// La elegida: la del panel, la recordada en esta pestaña de ventana o la que espera tu OK.
    private var elegida: VaultPath? {
        if let t = modelo.tareaElegida, modelo.grafo?.ficha(t) != nil { return t }
        if let s = nav?.recuerdo(de: .ficha(modelo.ruta)).seleccion.first, modelo.grafo?.ficha(VaultPath(s)) != nil { return VaultPath(s) }
        return modelo.relacionados([.task]).first { EstadosDeFicha.esperaTuOK(.task, estado: $0.ficha.estado) }?.ficha.ruta
    }

    private func seleccionar(_ t: VaultPath?) {
        modelo.tareaElegida = t
        nav?.actualizarRecuerdo(de: .ficha(modelo.ruta)) { $0.seleccion = t.map { [$0.raw] } ?? [] }
    }

    // MARK: Datos

    private var faseFiltro: String? { nav?.recuerdo(de: .ficha(modelo.ruta)).filtros["fase"] }

    private var plan: PlanDeEntrega? {
        guard let g = modelo.grafo, let p = g.destinos(de: modelo.ruta, propiedad: "plan").first,
              let t = modelo.almacen.foto?.text(p) else { return nil }
        return PlanDeEntrega.leer(t)
    }

    private var filtradas: [FichaGrafo] {
        let todas = modelo.relacionados([.task]).map(\.ficha)
        guard let f = faseFiltro, let n = Int(f), let plan else { return todas }
        return todas.filter { FasesDelPlan.fase(de: $0, en: plan)?.numero == n }
    }

    struct Columna {
        let clave: String
        let titulo: String
        let estado: EstadoTarea?
        let tareas: [FichaGrafo]
        let vacio: String
    }

    private func columnas(_ tareas: [FichaGrafo]) -> [Columna] {
        let hoy = modelo.hoy
        if porFase, let plan {
            var cols = plan.fases.map { fase in
                Columna(clave: "fase\(fase.numero)", titulo: fase.nombre, estado: nil,
                        tareas: EstadosDeFicha.ordenar(tareas.filter { FasesDelPlan.fase(de: $0, en: plan)?.numero == fase.numero }, hoy: hoy),
                        vacio: faseFiltro == nil ? "Sin tareas en esta fase." : "Filtrado por otra fase.")
            }
            let sueltas = tareas.filter { FasesDelPlan.fase(de: $0, en: plan) == nil }
            if !sueltas.isEmpty { cols.append(Columna(clave: "sinfase", titulo: "Sin fase", estado: nil, tareas: sueltas, vacio: "")) }
            return cols
        }
        func estado(_ f: FichaGrafo) -> EstadoTarea { f.estado.flatMap { EstadoTarea(leyendo: $0) } ?? .sinProgramar }
        let visibles = EstadoTarea.allCases.filter { e in Self.columnasBase.contains(e) || tareas.contains { estado($0) == e } }
        let vacios: [EstadoTarea: String] = [.porHacer: "Nada por hacer.", .enCurso: "Nada en curso ahora.",
                                             .enRevision: "Nada espera tu revisión.", .hecha: "Aún nada hecho."]
        return visibles.map { e in
            Columna(clave: e.rawValue, titulo: e.rawValue, estado: e,
                    tareas: EstadosDeFicha.ordenar(tareas.filter { estado($0) == e }, hoy: hoy), vacio: vacios[e] ?? "Nada.")
        }
    }

    // MARK: Vistas

    private var barra: some View {
        HStack(spacing: TLSEspacio.e8) {
            // Las mismas cápsulas azul noche que el selector de vista de las bases (no el segmentado gris del sistema).
            SelectorCapsula(etiqueta: "Vista", seleccion: $enLista, opciones: [(false, "Tablero", "rectangle.split.3x1"),
                                                                                (true, "Lista", "list.bullet")])
            SelectorCapsula(etiqueta: "Agrupar por", seleccion: $porFase, opciones: [(false, "Estado", nil), (true, "Fase", nil)])
                .disabled(plan == nil)
                .help(plan == nil ? "Sin plan de entrega no hay fases" : "Agrupar por")
            if let f = faseFiltro, let n = Int(f), let nombre = plan?.fases.first(where: { $0.numero == n })?.nombre {
                Chip("Fase es \(nombre)", icono: "line.3.horizontal.decrease", etiquetaQuitar: "Quitar el filtro Fase es \(nombre)") {
                    nav?.actualizarRecuerdo(de: .ficha(modelo.ruta)) { $0.filtros["fase"] = nil }
                }
            }
            Spacer()
            Button("Añadir existente…") { modelo.abrirSelectorInverso(tipos: [.task]) }
                .tlsBoton(.secundario)
                .disabled(!modelo.puedeEscribir)
                .popover(item: Binding(get: { modelo.selector.flatMap { s in if case .inverso = s.modo { return s }; return nil } },
                                       set: { if $0 == nil { modelo.selector = nil } }), arrowEdge: .bottom) { p in
                    SelectorRelacion(peticion: p, sesion: modelo.sesion, almacen: modelo.almacen,
                                     alElegir: { d in Task { await modelo.elegido(d, en: p, navegar: navegar) } },
                                     alQuitar: {}, alCrear: { _ in }, alListo: { _ in })
                }
            Button("Nueva tarea") { escribiendo = true }
                .tlsBoton(.principal, alto: 36)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!modelo.puedeEscribir)
        }
    }

    private var nuevaTarea: some View {
        HStack {
            TextField("Qué hay que hacer", text: $nueva, prompt: Text("Qué hay que hacer"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(crear)
                .onExitCommand { escribiendo = false; nueva = "" }
            Button("Cancelar") { escribiendo = false; nueva = "" }.tlsBoton(.secundario)
            Button("Crear", action: crear).tlsBoton(.principal, alto: 36)
                .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func crear() {
        let titulo = nueva.trimmingCharacters(in: .whitespaces)
        guard !titulo.isEmpty else { return }
        escribiendo = false
        nueva = ""
        Task {
            guard EdicionRelaciones.comprobarEscritura(modelo.sesion) else { return }
            await modelo.almacen.actualizar()
            guard let foto = modelo.almacen.foto else { return }
            let empresa = modelo.grafo?.destinos(de: modelo.ruta, propiedad: "empresa").first
            do {
                let nota = try TaskStore(snapshot: foto).crear(NuevaTarea(titulo: titulo, proyecto: modelo.ruta, empresa: empresa,
                                                                         estado: .porHacer, autor: modelo.sesion.autor))
                try await modelo.sesion.escribir(plan: nota.plan, aviso: "Creé \(nota.numero ?? "la tarea") en \(modelo.ficha?.nombre ?? "el proyecto")")
                modelo.almacen.invalidar()
                seleccionar(nota.ruta)
            } catch let e as TareaError {
                modelo.sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
            } catch {}
        }
    }

    /// Las columnas reparten el ancho visible; como mínimo 176 pt cada una (si no caben, el tablero se desplaza).
    static func anchoColumna(visible: CGFloat, columnas n: Int) -> CGFloat {
        guard n > 0 else { return 176 }
        let espacio = TLSEspacio.e12 * CGFloat(n - 1)
        return max(176, floor((visible - espacio) / CGFloat(n)))
    }

    private func columna(_ c: Columna, ancho: CGFloat) -> some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        let arrastrable = c.estado != nil
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: 6) {
                if let e = c.estado {
                    Image(systemName: FormatoFicha.tlsEstado(.task, e.rawValue, hoy: modelo.hoy).simbolo)
                        .foregroundStyle(FormatoFicha.tlsEstado(.task, e.rawValue, hoy: modelo.hoy).color.color)
                        .accessibilityHidden(true)
                }
                Text(c.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text("\(c.tareas.count)").tlsTexto(TLSTipo.secundario).monospacedDigit().foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Columna \(c.titulo), \(c.tareas.count == 1 ? "1 tarea" : "\(c.tareas.count) tareas")")
            if c.tareas.isEmpty {
                Text(c.vacio).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            }
            ForEach(c.tareas) { t in tarjeta(t, arrastrable: arrastrable) }
        }
        .padding(TLSEspacio.e8)
        .frame(width: ancho, alignment: .topLeading)
        .frame(minHeight: 160, alignment: .top)
        .background(forma.fill(TLSPaleta.bandeja.color))
        .overlay(forma.strokeBorder(sobre == c.clave ? TLSPaleta.principal.color : .clear, style: StrokeStyle(lineWidth: 2, dash: [5])))
        .dropDestination(for: String.self) { items, _ in
            guard let e = c.estado, let raw = items.first.flatMap({ ArrastreFila.id($0, empresa: modelo.sesion.entry.id) })
            else { return false }
            Task { await modelo.cambiarEstado(e.rawValue, de: VaultPath(raw), soloEstado: true) }
            return true
        } isTargeted: { dentro in
            guard arrastrable else { return }
            sobre = dentro ? c.clave : (sobre == c.clave ? nil : sobre)
        }
    }

    private func tarjeta(_ t: FichaGrafo, arrastrable: Bool) -> some View {
        let elegida = self.elegida == t.ruta
        let responsable = t.texto("responsable").map(Responsables.nombre(de:)) ?? "Sin responsable"
        let vence = t.texto("vence").flatMap { LocalDate(parsing: $0) }
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.numero ?? "").tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer()
                if EstadosDeFicha.esperaTuOK(.task, estado: t.estado) { InsigniaAviso(nil, palabra: "Espera tu OK") }
            }
            Text(t.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(responsable).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            // Vencida: no solo por color, también con su icono y su palabra.
            if let vence, vence < modelo.hoy, EstadosDeFicha.abierta(.task, estado: t.estado) {
                Label {
                    Text("Vencida · " + FormatoFicha.fechaConDia(vence, hoy: modelo.hoy)).tlsTexto(TLSTipo.secundario)
                } icon: {
                    Image(systemName: TLSEstado.mal.simbolo).font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(TLSPaleta.mal.color)
            } else {
                Text(vence.map { "vence " + FormatoFicha.fechaConDia($0, hoy: modelo.hoy) } ?? "sin fecha")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay(forma.strokeBorder(elegida ? TLSPaleta.principal.color : TLSPaleta.separador.color, lineWidth: elegida ? 2 : 1))
        .contentShape(forma)
        // Con el teclado como con el ratón: Tab la enfoca (anillo magenta) y la elige; ↩ la abre, la barra
        // espaciadora enseña la vista previa y ⌘← ⌘→ la mueven de columna (§11.9).
        .focusable()
        .focused($enfocada, equals: t.ruta)
        .focusEffectDisabled()
        .tlsAnilloFoco(enfocada == t.ruta, radio: TLSRadio.tarjeta)
        .onKeyPress(.return) { navegar(.tarea(t.ruta)); return .handled }
        .onKeyPress(.space) { nav?.vistaPrevia = t.ruta; return .handled }
        .onTapGesture(count: 2) { navegar(.tarea(t.ruta)) }
        .onTapGesture { seleccionar(t.ruta); enfocada = t.ruta }
        .draggable(ArrastreFila.texto(t.ruta.raw, empresa: modelo.sesion.entry.id)) {
            Text(t.nombre).tlsTexto(TLSTipo.interfazFuerte).padding(8).background(forma.fill(TLSPaleta.superficieElevada.color))
        }
        .vistaPrevia(ruta: t.ruta, sesion: modelo.sesion)
        .contextMenu { menuTarjeta(t) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(t.numero.map { "\($0), " } ?? "")\(t.nombre), \(t.estado ?? "sin estado"), \(vence.map { "vence " + FormatoFicha.fechaConDia($0, hoy: modelo.hoy) } ?? "sin fecha"), \(responsable)")
        .accessibilityAddTraits(elegida ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(.default) { seleccionar(t.ruta) }
        .accessibilityAction(named: "Abrir la tarea") { navegar(.tarea(t.ruta)) }
        .accessibilityAction(named: "Abrir como ficha") { navegar(.ficha(t.ruta)) }
        .accessibilityActions {
            ForEach(EstadoTarea.allCases, id: \.self) { e in
                Button("Mover a \(e.rawValue)") { Task { await modelo.cambiarEstado(e.rawValue, de: t.ruta, soloEstado: true) } }
            }
        }
    }

    @ViewBuilder
    private func menuTarjeta(_ t: FichaGrafo) -> some View {
        // Integración F2: la tarea abre su pantalla de Tareas (Actividad, estado del asistente); la ficha, aparte.
        Button("Abrir la tarea") { navegar(.tarea(t.ruta), modo: .entrar) }
        Button("Abrir como ficha") { navegar(.ficha(t.ruta), modo: .entrar) }
        Button("Abrir en pestaña nueva") { navegar(.tarea(t.ruta), modo: .pestanaNueva) }
        Menu("Mover a…") {
            ForEach(EstadoTarea.allCases, id: \.self) { e in
                Button(e.rawValue) { Task { await modelo.cambiarEstado(e.rawValue, de: t.ruta, soloEstado: true) } }
                    .disabled(EstadoTarea(leyendo: t.estado ?? "") == e)
            }
        }
        .disabled(!modelo.puedeEscribir)
        Divider()
        if modelo.relacionados([.task]).first(where: { $0.ficha.ruta == t.ruta })?.esDirecta == true {
            Button("Quitar de \(modelo.ficha?.nombre ?? "este proyecto")") {
                if let r = modelo.relacionados([.task]).first(where: { $0.ficha.ruta == t.ruta }) { Task { await modelo.quitarRelacionado(r) } }
            }
            .disabled(!modelo.puedeEscribir)
        } else {
            Text("Vive en la carpeta del proyecto: para sacarla, muévela")
        }
    }

    private func lista(_ tareas: [FichaGrafo]) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            ForEach(columnas(tareas).filter { !$0.tareas.isEmpty }, id: \.clave) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Rotulo("\(c.titulo) · \(c.tareas.count)")
                    ForEach(c.tareas) { t in
                        FilaLista(t.nombre, detalle: [t.numero, t.texto("responsable").map(Responsables.nombre(de:))].compactMap { $0 }.joined(separator: " · "),
                                  icono: "checkmark.square", seleccionada: elegida == t.ruta, accion: { seleccionar(t.ruta) })
                            .vistaPrevia(ruta: t.ruta, sesion: modelo.sesion)
                            .contextMenu { menuTarjeta(t) }
                    }
                }
            }
        }
    }

    /// ⌘← y ⌘→ mueven la tarjeta elegida a la columna de al lado (alternativa al arrastre, §11.9).
    @ViewBuilder private var atajos: some View {
        ZStack {
            Button("") { Task { await moverElegida(-1) } }.keyboardShortcut(.leftArrow, modifiers: .command)
            Button("") { Task { await moverElegida(1) } }.keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func moverElegida(_ d: Int) async {
        guard !porFase, let t = elegida, let f = modelo.grafo?.ficha(t) else { return }
        let cols = columnas(filtradas).compactMap(\.estado)
        let actual = EstadoTarea(leyendo: f.estado ?? "") ?? .sinProgramar
        guard let i = cols.firstIndex(of: actual), cols.indices.contains(i + d) else { return }
        await modelo.cambiarEstado(cols[i + d].rawValue, de: t, soloEstado: true)
    }
}

/// Cápsulas para elegir una opción entre pocas (Tablero/Lista, Estado/Fase): la elegida en azul noche, como el
/// selector de vista de las bases. Cada opción es un botón con su nombre para VoiceOver y el anillo propio.
struct SelectorCapsula<Valor: Hashable>: View {
    let etiqueta: String
    @Binding var seleccion: Valor
    let opciones: [(Valor, String, String?)]
    @Environment(\.isEnabled) private var activo

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(opciones.enumerated()), id: \.offset) { _, o in
                let elegida = seleccion == o.0
                Button { seleccion = o.0 } label: {
                    HStack(spacing: 5) {
                        if let icono = o.2 { Image(systemName: icono).font(.system(size: 12, weight: .medium)) }
                        Text(o.1).tlsTexto(TLSTipo.interfazMedia)
                    }
                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color
                                     : (activo ? TLSPaleta.texto.color : TLSPaleta.desactivadoTexto.color))
                    .padding(.horizontal, 10)
                    .frame(minWidth: TLSAltura.objetivoMinimo, minHeight: TLSAltura.objetivoMinimo)
                    .background(Capsule(style: .circular).fill(elegida ? TLSPaleta.principal.color : Color.clear))
                    .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .tlsFocoPropio(radio: 999)
                .accessibilityLabel(o.1)
                .accessibilityAddTraits(elegida ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(etiqueta)
    }
}
