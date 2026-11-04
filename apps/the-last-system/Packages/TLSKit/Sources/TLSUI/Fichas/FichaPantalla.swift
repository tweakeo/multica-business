import SwiftUI
import TLSCore
import TLSDesign

/// Ficha de una nota con tipo (contacto, empresa, proyecto, factura…), con el molde de §3.1: cabecera azul
/// noche con estado editable y acciones, el destacado violeta, la franja «Ahora» (si hay algo), «Conectado
/// con», pestañas con contador y, a la derecha, el panel de propiedades (⌥⌘I). El `init` es el contrato con el
/// enrutador (`Shell/PantallaDestino.swift`).
struct FichaPantalla: View {
    let ruta: VaultPath
    /// Pestaña con la que abre (`nil` = la recordada o la que toca por tipo y estado, §3.3).
    let pestana: String?
    let sesion: VaultSession
    @State private var modelo: FichaModelo
    @Environment(\.navegacion) private var nav
    @Environment(\.navegar) private var navegar

    init(ruta: VaultPath, pestana: String?, sesion: VaultSession) {
        self.ruta = ruta
        self.pestana = pestana
        self.sesion = sesion
        self._modelo = State(initialValue: FichaModelo(ruta: ruta, sesion: sesion))
    }

    var body: some View {
        @Bindable var modelo = modelo
        Group {
            switch modelo.lector.nota?.content {
            case nil:
                ProgressView("Abriendo…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .markdown?:
                ficha
            default:
                // Sin texto que leer (iCloud, no es texto): el visor de la nota lo explica.
                VisorNota(sesion: sesion, lector: modelo.lector)
            }
        }
        .task(id: sesion.revision) { await modelo.cargar() }
        .inspector(isPresented: Binding(get: { nav?.inspector ?? sesion.showInspector },
                                        set: { v in if let nav { nav.inspector = v } else { sesion.showInspector = v } })) {
            InspectorFicha(modelo: modelo)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .sheet(item: $modelo.confirmacion) { c in
            ConfirmarRelacion(confirmacion: c, grafo: modelo.grafo) { elegida in
                Task { await EdicionRelaciones.confirmar(elegida, sesion: sesion, almacen: modelo.almacen) }
            }
        }
        .sheet(item: $modelo.nuevo) { opcion in
            NuevoEnlazado(opcion: opcion, desde: ruta, modelo: modelo)
        }
        .environment(\.tlsSesionEmpresa, sesion)
        .accessibilityIdentifier("ficha.\(ruta.stem)")
        .tutorialAnchor(.ficha)
    }

    private var elegida: String { modelo.pestanaElegida(pestana, nav: nav) }

    private func elegir(_ p: String) {
        nav?.cambiarPestana(p)
        nav?.actualizarRecuerdo(de: .ficha(ruta)) { $0.extra["pestana"] = p }
    }

    private var ficha: some View {
        let tabs = modelo.pestanas()
        let elegida = self.elegida
        let def = tabs.defs[elegida] ?? DefPestana("Notas", .notas)
        return ContenedorPantalla(destino: .ficha(ruta), espacio: TLSEspacio.e16) {
            CabeceraFicha(modelo: modelo, verComoTexto: { elegir("Fichero") })
            if modelo.tipo == .opportunity, let f = modelo.ficha {
                LineaEtapas(ficha: f, modelo: modelo)
            }
            if modelo.tipo == .project {
                FranjaFases(modelo: modelo) { elegir("Tareas") }
            }
            if let ahora = modelo.resumen?.ahora, !ahora.isEmpty {
                FranjaAhora(lineas: ahora, sesion: sesion)
            }
            ConectadoConVista(modelo: modelo)
            HStack(alignment: .center, spacing: TLSEspacio.e8) {
                PestanasCapsula(seleccion: Binding(get: { elegida }, set: { elegir($0) }),
                                pestanas: tabs.visibles, mas: tabs.mas)
                    .accessibilityRepresentation {
                        Picker("Lo relacionado con \(modelo.ficha?.nombre ?? ruta.stem)", selection: Binding(get: { elegida }, set: { elegir($0) })) {
                            ForEach(tabs.visibles + tabs.mas) { Text($0.etiquetaAccesible).tag($0.id) }
                        }
                    }
                Spacer(minLength: 0)
                Button(sesion.showInspector ? "Ocultar propiedades" : "Propiedades") { sesion.showInspector.toggle() }
                    .tlsBoton(.secundario)
                    .help("Propiedades · ⌥⌘I")
            }
            contenido(def)
                .id(elegida)
            // ⌘E: «Ver como texto».
            Button("") { elegir("Fichero") }
                .keyboardShortcut("e", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom) {
            if [.invoice, .proposal, .quote, .agreement, .receipt].contains(modelo.tipo) {
                BarraDocumento(modelo: modelo) { elegir("Fichero") }
            }
        }
    }

    @ViewBuilder
    private func contenido(_ def: DefPestana) -> some View {
        switch def.contenido {
        case .resumen:
            switch modelo.tipo {
            case .invoice, .proposal, .quote, .agreement, .receipt: DocumentoFicha(modelo: modelo)
            case .system: ResumenSistema(modelo: modelo)
            case .meeting where TextFolding.fold(modelo.ficha?.estado ?? "") != "hecha": ResumenReunion(modelo: modelo, irA: elegir)
            default: PestanaResumen(modelo: modelo, irA: elegir)
            }
        case .notas:
            if modelo.tipo == .meeting, TextFolding.fold(modelo.ficha?.estado ?? "") == "hecha" {
                AccionesReunion(modelo: modelo)
            }
            PestanaNotas(modelo: modelo)
        case .actividad:
            if modelo.tipo == .task { ActividadTarea(modelo: modelo, tarea: ruta, panelFijo: true) }
            else { PestanaActividad(modelo: modelo) }
        case .fichero:
            PestanaFichero(modelo: modelo)
        case .relacionados(let tipos):
            PestanaRelacionados(modelo: modelo, titulo: def.titulo, tipos: tipos)
        case .tareasProyecto:
            TableroProyecto(modelo: modelo)
        case .subtareas:
            PestanaRelacionados(modelo: modelo, titulo: "Subtareas", tipos: [.task], soloPropiedad: "padre")
        case .materiales:
            PestanaMateriales(modelo: modelo)
        case .seccion(let titulo):
            PestanaSeccion(modelo: modelo, titulo: titulo)
        case .ejecuciones:
            PestanaEjecuciones(modelo: modelo)
        }
    }
}

// MARK: - Cabecera y destacado

/// Cabecera azul noche (3 columnas) y destacado violeta (1), o uno bajo otro por debajo de 900 pt (§3.1).
struct CabeceraFicha: View {
    let modelo: FichaModelo
    let verComoTexto: () -> Void
    @Environment(\.navegar) private var navegar
    @State private var renombrar = false
    @State private var ancho: CGFloat = 1200
    /// Desde este ancho, el destacado va al lado de la cabecera (§3.1: «por debajo de 900 pt pasa bajo la cabecera»).
    static let anchoLadoALado: CGFloat = 900

    /// Ancho del destacado al lado: una de las 4 columnas del mosaico, como mínimo 240 pt.
    static func anchoDestacado(_ ancho: CGFloat) -> CGFloat {
        max(240, (ancho - 3 * TLSEspacio.entreMosaicos) / 4)
    }

    var body: some View {
        Group {
            if ancho >= Self.anchoLadoALado {
                HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                    cabecera.frame(maxHeight: .infinity)
                    destacado.frame(width: Self.anchoDestacado(ancho)).frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: TLSEspacio.entreMosaicos) {
                    cabecera
                    destacado.frame(minHeight: 132)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .sheet(isPresented: $renombrar) { RenombrarFicha(modelo: modelo) }
    }

    private var cabecera: some View {
        let r = modelo.resumen
        let f = modelo.ficha
        let tipo = modelo.tipo
        let subtitulo = FormatoFicha.sinEstado(modelo.cuerpo.flatMap(FormatoFicha.lineaResumen), tipo: tipo)
        let estado: EstadoCabecera? = f.flatMap { f in
            guard let e = f.estado else { return nil }
            let opciones = modelo.opcionesEstado(f)
            return EstadoCabecera(FormatoFicha.capital(e), estado: FormatoFicha.tlsEstado(f.tipo, e, hoy: modelo.hoy),
                                  opciones: opciones) { o in Task { await modelo.cambiarEstado(o.titulo) } }
        }
        return CabeceraDeFicha(rotulo: r?.rotulo ?? tipo.etiqueta, titulo: f?.nombre ?? modelo.ruta.stem,
                               subtitulo: subtitulo,
                               // El código no se repite si ya va en los datos («Número · T-0042»).
                               codigo: r?.codigo.flatMap { c in (r?.datos ?? []).contains { $0.valor == c } ? nil : c },
                               estado: estado, datos: r?.datos ?? []) {
            if [.contact, .organization].contains(tipo) {
                AvatarCabecera(iniciales: Monograma.iniciales(de: f?.nombre ?? modelo.ruta.stem))
            } else {
                AvatarCabecera(simbolo: tipo.systemImage)
            }
        } acciones: {
            if let p = accionPrincipal {
                let motivo = p.motivo ?? (p.escribe && !modelo.puedeEscribir ? modelo.motivoSoloLectura : nil)
                Button(p.titulo, action: p.hacer).tlsBoton(.sobreCabecera, alto: TLSAltura.botonPrincipal)
                    .disabled(motivo != nil)
                    .help(motivo.map { "No se puede: \($0)" } ?? p.titulo)
                    .accessibilityHint(motivo.map { "No se puede: \($0)" } ?? "")
                // Desactivada, dice al lado por qué (§1.3).
                if let motivo {
                    Text(motivo)
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.subtituloCabecera.color)
                        .lineLimit(2)
                        .frame(maxWidth: 180, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
            if !modelo.configuracion.nuevo.isEmpty {
                Menu {
                    Section("Nace ya enlazado con esta ficha") {
                        ForEach(modelo.configuracion.nuevo) { o in
                            Button(o.titulo) { modelo.nuevo = o }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        Text("Nuevo")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Nuevo, ya enlazado")
                }
                .menuStyle(.button)
                .buttonStyle(EstiloContornoCabecera())
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!modelo.puedeEscribir)
                .help(modelo.motivoSoloLectura.map { "No se puede crear: \($0)" } ?? "Nuevo, ya enlazado")
            }
            Menu {
                Button("Ver como texto", action: verComoTexto)
                Button(modelo.sesion.showInspector ? "Ocultar propiedades" : "Propiedades") { modelo.sesion.showInspector.toggle() }
                Button("Abrir en pestaña nueva") { navegar(.ficha(modelo.ruta), modo: .pestanaNueva) }
                Button("Copiar enlace") { copiarEnlace() }
                Button("Mostrar en Finder") { modelo.sesion.revealInFinder(modelo.ruta) }
                Divider()
                Button("Renombrar…") { renombrar = true }.disabled(!modelo.puedeEscribir)
                Button(EstadosDeFicha.posibles(tipo).contains("Archivado") ? "Archivar" : "Retirar a Archivo") {
                    Task { await archivar() }
                }
                .disabled(!modelo.puedeEscribir)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold))
            }
            .menuStyle(.button)
            .buttonStyle(EstiloContornoCabecera())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Más acciones de la ficha")
        }
    }

    private struct Accion {
        let titulo: String
        let escribe: Bool
        /// Por qué no se puede todavía (sale desactivada y con el motivo al lado o en la ayuda).
        var motivo: String? = nil
        let hacer: () -> Void
    }

    /// La acción principal según el tipo y el estado (§3.4).
    private var accionPrincipal: Accion? {
        guard let f = modelo.ficha else { return nil }
        let e = TextFolding.fold(f.estado ?? "")
        switch f.tipo {
        case .contact, .organization:
            return Accion(titulo: "Escribir un correo", escribe: true) {
                modelo.nuevo = OpcionNuevo(titulo: "Correo", plantilla: "mensaje", tipo: .draft)
            }
        case .opportunity:
            switch e {
            case "prospecto", "diagnostico":
                return Accion(titulo: "Preparar la reunión", escribe: true) { modelo.nuevo = OpcionNuevo(titulo: "Reunión", plantilla: "reunion", tipo: .meeting) }
            case "propuesta":
                return Accion(titulo: "Preparar seguimiento", escribe: true) { modelo.nuevo = OpcionNuevo(titulo: "Tarea", plantilla: "tarea", tipo: .task) }
            case "aceptada":
                if let fac = modelo.relacionados([.invoice]).first {
                    return Accion(titulo: "Abrir la factura", escribe: false) { navegar(.ficha(fac.ficha.ruta)) }
                }
                return Accion(titulo: "Nueva factura", escribe: true) { modelo.nuevo = OpcionNuevo(titulo: "Factura", plantilla: "factura", tipo: .invoice) }
            case "ganada":
                if let p = modelo.relacionados([.project]).first {
                    return Accion(titulo: "Abrir el proyecto", escribe: false) { navegar(.ficha(p.ficha.ruta)) }
                }
                return nil
            default:
                return nil
            }
        case .project:
            if let t = modelo.relacionados([.task]).first(where: { EstadosDeFicha.esperaTuOK(.task, estado: $0.ficha.estado) }) {
                return Accion(titulo: "Revisar \(t.ficha.numero ?? "la tarea")", escribe: false) {
                    modelo.tareaElegida = t.ficha.ruta
                    navegar(.ficha(modelo.ruta, pestana: "Tareas"), modo: .entrar)
                }
            }
            return Accion(titulo: "Preparar el seguimiento", escribe: true) {
                modelo.nuevo = OpcionNuevo(titulo: "Seguimiento", plantilla: "reunion-de-seguimiento", tipo: .meeting)
            }
        case .invoice:
            // En la cabecera, la primera de las acciones del documento (la misma que la principal de la barra).
            guard let a = AccionDocumento.de(modelo).first else { return nil }
            return Accion(titulo: a.titulo, escribe: true, motivo: a.motivo, hacer: a.hacer)
        case .task:
            let estado = EstadoTarea(leyendo: f.estado ?? "") ?? .sinProgramar
            switch estado {
            case .sinProgramar, .porHacer:
                return Accion(titulo: "Empezar ahora", escribe: true) { Task { await modelo.cambiarEstado(EstadoTarea.enCurso.rawValue) } }
            case .enCurso, .enRevision, .bloqueada:
                return Accion(titulo: "Marcar como hecha", escribe: true) { Task { await modelo.cambiarEstado(EstadoTarea.hecha.rawValue) } }
            default:
                return nil
            }
        default:
            return nil
        }
    }

    @ViewBuilder
    private var destacado: some View {
        if let p = modelo.resumen?.protagonista {
            if let vacio = p.vacio, p.valor.isEmpty {
                DestacadoVacio(rotulo: p.rotulo, texto: vacio + (p.contexto.map { " \($0)." } ?? ""))
            } else {
                Destacado(rotulo: p.rotulo, accion: accionDestacado?.0, alPulsar: accionDestacado?.1) {
                    VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                        if let avance = p.avance {
                            HStack(alignment: .center, spacing: TLSEspacio.e16) {
                                AnilloAvance(avance: avance)
                                CifraDestacada(p.valor, contexto: p.contexto, estilo: TLSTipo.cifraMedia)
                            }
                        } else if p.esCifra {
                            CifraDestacada(p.valor, contexto: p.contexto)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.valor).tlsTexto(TLSTipo.tituloSeccion).fixedSize(horizontal: false, vertical: true)
                                if let c = p.contexto { Text(c).tlsTexto(TLSTipo.interfazMedia).fixedSize(horizontal: false, vertical: true) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if let segundo = p.segundo {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(segundo).tlsTexto(TLSTipo.tituloModulo.peso(600)).fixedSize(horizontal: false, vertical: true)
                                if let d = p.segundoDetalle {
                                    Text(d).tlsTexto(TLSTipo.secundario).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, TLSEspacio.e12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        } else {
            DestacadoVacio(rotulo: "Lo importante", texto: "Leyendo la ficha…")
        }
    }

    /// La acción del destacado: lleva a lo que pide.
    private var accionDestacado: (String, () -> Void)? {
        guard let f = modelo.ficha, let g = modelo.grafo else { return nil }
        switch f.tipo {
        case .contact, .organization:
            let opos = modelo.relacionados([.opportunity]).map(\.ficha)
            if let s = ResumenDeFicha.siguientePaso(opos, hoy: modelo.hoy) {
                return ("Abrir la oportunidad", { navegar(.ficha(s.de.ruta)) })
            }
        case .opportunity:
            if TextFolding.fold(f.estado ?? "") == "aceptada", !g.cobroConfirmado(oportunidad: f.ruta).confirmado,
               let fac = modelo.relacionados([.invoice]).first {
                return ("Ver la factura", { navegar(.ficha(fac.ficha.ruta)) })
            }
        case .task:
            switch EstadoTarea(leyendo: f.estado ?? "") ?? .sinProgramar {
            case .sinProgramar, .porHacer:
                if modelo.puedeEscribir { return ("Empezar ahora", { Task { await modelo.cambiarEstado(EstadoTarea.enCurso.rawValue) } }) }
            case .enCurso, .enRevision, .bloqueada:
                if modelo.puedeEscribir { return ("Marcar como hecha", { Task { await modelo.cambiarEstado(EstadoTarea.hecha.rawValue) } }) }
            default:
                break
            }
        default:
            break
        }
        return nil
    }

    private func copiarEnlace() {
        guard let enlace = modelo.sesion.enlaceParaCopiar(.ficha(modelo.ruta)) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(enlace, forType: .string)
        modelo.sesion.aviso = Aviso("Copié el enlace a \(modelo.ficha?.nombre ?? modelo.ruta.stem).", estado: .bien)
    }

    private func archivar() async {
        guard let f = modelo.ficha, EdicionRelaciones.comprobarEscritura(modelo.sesion) else { return }
        if EstadosDeFicha.posibles(f.tipo).contains("Archivado") {
            await modelo.cambiarEstado("Archivado")
        } else {
            _ = try? await modelo.sesion.escribir(.retirar(f.ruta), aviso: "Retiré «\(f.nombre)» a Archivo. No se borra nada")
            modelo.almacen.invalidar()
        }
    }
}

/// Anillo de avance blanco sobre el violeta (proyecto: tareas hechas sobre las del plan).
struct AnilloAvance: View {
    let avance: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 9)
            if avance > 0 {
                Circle().trim(from: 0, to: min(1, avance))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(4.5)
        .frame(width: 72, height: 72)
        .accessibilityLabel("Avance \(Int((avance * 100).rounded())) %")
    }
}

// MARK: - Ahora

/// Franja «Ahora» (§3.1): hasta 3 líneas con su icono de estado, una frase y un botón; solo si hay algo.
struct FranjaAhora: View {
    let lineas: [LineaAhora]
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Rotulo("Ahora").padding(.bottom, TLSEspacio.e8)
            ForEach(Array(lineas.enumerated()), id: \.element.id) { i, l in
                if i > 0 { Divider().overlay(TLSPaleta.separador.color) }
                HStack(spacing: TLSEspacio.e12) {
                    // Como en M2-Contacto: el icono en un cuadro de 32 pt con el tinte de su estado y, delante de la
                    // frase, la palabra de lo que es («Pide tu decisión.», «Vencido.»).
                    Image(systemName: l.clase == .decision ? "signpost.right.and.left" : l.estado.simbolo)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(l.clase == .decision ? TLSPaleta.principal.color : l.estado.color.color)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(l.clase == .decision ? TLSPaleta.principalSuave.color : l.estado.tinte.color))
                        .accessibilityHidden(true)
                    Text(Self.frase(l))
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: TLSEspacio.e8)
                    if let b = l.boton, let d = l.destino {
                        Button(b) { navegar(sesion.destino(para: d)) }
                            .tlsBoton(.secundario)
                            .vistaPrevia(ruta: d, sesion: sesion)
                    }
                }
                .padding(.vertical, 6)
                .frame(minHeight: TLSAltura.filaLista)
            }
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ahora")
        .accessibilityRotor(Text("Urgente"), entries: lineas, entryLabel: \.texto)
    }

    /// «**Pide tu decisión.** T-0042 · … espera tu OK» (la palabra en negrita, con la escala de texto del entorno).
    static func frase(_ l: LineaAhora) -> AttributedString {
        var rotulo = AttributedString(l.rotulo + ". ")
        rotulo.inlinePresentationIntent = .stronglyEmphasized
        return rotulo + AttributedString(l.texto)
    }
}

// MARK: - Barra de los documentos

/// Barra fija abajo en los documentos (§3.1 punto 7): la acción principal según el estado (en la factura: Revisar y
/// emitir · Preparar el envío · Confirmar el cobro · Preparar recordatorio), «Vista previa PDF» y «Ver como texto».
struct BarraDocumento: View {
    let modelo: FichaModelo
    let verComoTexto: () -> Void
    @Environment(\.navegar) private var navegar

    var body: some View {
        let acciones = AccionDocumento.de(modelo)
        HStack(spacing: TLSEspacio.e8) {
            if let f = modelo.ficha {
                PastillaEstado(FormatoFicha.tlsEstado(f.tipo, f.estado, hoy: modelo.hoy), palabra: f.estado.map(FormatoFicha.capital) ?? "Sin estado")
                Text(acciones.first?.motivo ?? siguiente(f)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(2)
            }
            Spacer()
            if let pdf = DocumentoFicha.pdf(de: modelo) {
                Button("Vista previa PDF") { navegar(.fichero(pdf)) }.tlsBoton(.secundario)
            }
            Button("Ver como texto", action: verComoTexto).tlsBoton(.secundario).help("⌘E")
            ForEach(Array(acciones.enumerated().reversed()), id: \.element.id) { i, a in
                if i == 0 {
                    Button(a.titulo, action: a.hacer)
                        .tlsBoton(.principal, alto: 36)
                        .disabled(a.motivo != nil || !modelo.puedeEscribir)
                        .help(a.motivo ?? a.titulo)
                } else {
                    Button(a.titulo, action: a.hacer)
                        .tlsBoton(.secundario)
                        .disabled(a.motivo != nil || !modelo.puedeEscribir)
                        .help(a.motivo ?? a.titulo)
                }
            }
        }
        .padding(.horizontal, TLSEspacio.e24)
        .padding(.vertical, TLSEspacio.e8)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
    }

    private func siguiente(_ f: FichaGrafo) -> String {
        switch TextFolding.fold(f.estado ?? "") {
        case "borrador": "Siguiente: revisar y emitir (la emisión oficial la hace tu herramienta de facturación)"
        case "emitida": "Siguiente: preparar el envío"
        case "enviada": "Siguiente: confirmar el cobro cuando llegue"
        case "cobrada": "Cobrada: nada pendiente"
        default: ""
        }
    }
}
