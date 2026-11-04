import SwiftUI
import TLSCore
import TLSDesign

/// El andamio común de las seis áreas (PLAN §6.5, SISTEMAS §4.2, DISENO §3.1 y §6).
///
/// - **Cabecera azul noche:** nombre, «Convierte X en Y», rol y quien lo ocupa, la pregunta fija y el ritmo del
///   área (`RhythmBadge`); a la derecha, «Pedir a <asistente>» (desactivado hasta F4, «Llega con los
///   asistentes») y «Ver solo lo de este rol».
/// - **Destacado violeta:** la cifra protagonista (`HeroNumber`) del número clave.
/// - **Pestañas:** Resumen · Operación · Control · Sistemas y activos. En reposo, solo Resumen con «Activar»
///   (avisa si otra área se activó hace menos de 30 días); preparada, con «Los asistentes aún no trabajan aquí»;
///   en las etapas 1–2 sin metas, Control dice «Medir esto llega en la etapa 3».
///
/// Operación y Resumen son huecos de la fase de pantallas (`Areas/Operacion/*`, `Pantallas/Modulos/ResumenDeArea`).
struct AreaScaffold: View {
    let area: AreaCode
    let pestana: String?
    let sesion: VaultSession
    @State private var modelo: ModeloArea
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager
    @State private var confirmarActivar = false

    init(area: AreaCode, pestana: String?, sesion: VaultSession) {
        self.area = area
        self.pestana = pestana
        self.sesion = sesion
        _modelo = State(initialValue: ModeloArea(area: area, sesion: sesion))
    }

    var body: some View {
        ContenedorPantalla(destino: .area(area)) {
            if let datos = modelo.datos {
                contenido(datos)
            } else {
                cargando
            }
        }
        .task(id: sesion.revision) { await modelo.cargar() }
        .accessibilityIdentifier("area.\(area.rawValue)")
    }

    // MARK: Partes

    @ViewBuilder
    private func contenido(_ datos: DatosArea) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                cabecera(datos)
                destacado(datos).frame(width: 300)
            }
            VStack(spacing: TLSEspacio.entreMosaicos) {
                cabecera(datos)
                destacado(datos)
            }
        }
        switch datos.fase {
        case .reposo: activar(datos)
        case .preparada: preparada(datos)
        case .activa, .sinEstado: EmptyView()
        }
        let elegida = Self.pestanaElegida(pestana, datos: datos)
        PestanasCapsula(seleccion: Binding(get: { elegida.rawValue }, set: { nav?.cambiarPestana($0) }),
                        pestanas: datos.pestanas.map { p in pestanaCapsula(p, datos: datos) })
            .accessibilityIdentifier("area.pestanas")
            .tutorialAnchor(.areaPestanas)
        switch elegida {
        case .resumen:
            ResumenDeArea(contexto: contexto(datos), sesion: sesion)
        case .operacion:
            OperacionDeArea(contexto: contexto(datos), sesion: sesion)
        case .control:
            ControlArea(datos: datos, modelo: modelo)
        case .sistemas:
            SistemasYActivos(datos: datos, sesion: sesion)
        }
    }

    private var cargando: some View {
        let resumen = sesion.area(area)
        return CabeceraAzulNoche(rotulo: "Área", titulo: resumen?.etiquetaNumerada ?? area.etiquetaNumerada,
                                 subtitulo: "Leyendo el área…", altoMinimo: 168) {
            IconoArea(area.tlsArea, tamano: 44, sobreCabecera: true)
        } acciones: { EmptyView() }
    }

    /// La pestaña que se enseña: la pedida si existe en esta fase; si no, Resumen.
    static func pestanaElegida(_ pedida: String?, datos: DatosArea) -> PestanaArea {
        guard let pedida, let p = PestanaArea(rawValue: pedida), datos.pestanas.contains(p) else { return .resumen }
        return p
    }

    private func pestanaCapsula(_ p: PestanaArea, datos: DatosArea) -> PestanaCapsula {
        switch p {
        case .control:
            let enAlerta = datos.control.filter { $0.ritmo == .enAlerta }.count
            return PestanaCapsula(id: p.rawValue, titulo: p.rawValue, contador: datos.control.isEmpty ? nil : datos.control.count,
                                  urgente: enAlerta > 0 ? .mal : nil)
        case .sistemas:
            return PestanaCapsula(id: p.rawValue, titulo: p.rawValue,
                                  contador: datos.sistemasEnUso > 0 ? datos.sistemasEnUso : nil)
        default:
            return PestanaCapsula(id: p.rawValue, titulo: p.rawValue)
        }
    }

    /// Lo que reciben Resumen y Operación, con «Ver solo lo de este rol» de esta pestaña de ventana.
    private func contexto(_ datos: DatosArea) -> ContextoArea {
        var c = datos.contexto
        c.soloRol = soloRol
        return c
    }

    // MARK: Cabecera

    /// «Ver solo lo de este rol», recordado por pestaña de ventana (como los filtros, §11.1).
    private var soloRol: Bool { nav?.recuerdo(de: .area(area)).extra["soloRol"] == "1" }

    private func alternarSoloRol() {
        let nuevo = !soloRol
        nav?.actualizarRecuerdo(de: .area(area)) { $0.extra["soloRol"] = nuevo ? "1" : nil }
    }

    private func cabecera(_ datos: DatosArea) -> some View {
        var claves: [DatoClave] = []
        if let rol = datos.rol { claves.append(DatoClave("Rol", rol)) }
        claves.append(DatoClave("La lleva", datos.ocupante ?? "Sin ocupante"))
        if let etapa = datos.etapa { claves.append(DatoClave("Etapa", "\(etapa)")) }
        return CabeceraAzulNoche(rotulo: "Área", titulo: datos.titulo, subtitulo: datos.fraseConvierte,
                                 // Sin `estado:` en su Área.md no se pinta «Sin estado» (como la barra lateral).
                                 estado: datos.fase == .sinEstado ? nil : EstadoCabecera(datos.fase.palabra, estado: datos.fase.estado),
                                 datos: claves, altoMinimo: 168) {
            IconoArea(area.tlsArea, tamano: 44, sobreCabecera: true)
        } acciones: {
            accionesCabecera(datos)
        } debajo: {
            HStack(alignment: .center, spacing: TLSEspacio.e8) {
                if let pregunta = datos.pregunta {
                    Text(pregunta)
                        .tlsTexto(TLSTipo.interfazFuerte)
                        .foregroundStyle(TLSPaleta.sobreColor.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Pregunta del área: \(pregunta)")
                }
                // En reposo, el estado ya lo dice: sin ritmo.
                if datos.fase != .reposo {
                    Text("Ritmo").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.subtituloCabecera.color)
                        .padding(.leading, datos.pregunta == nil ? 0 : 6)
                        .accessibilityHidden(true)
                    RhythmBadge(area: datos, sobreColor: true)
                }
            }
            .padding(.top, 2)
        }
        .accessibilityIdentifier("area.cabecera")
    }

    private func accionesCabecera(_ datos: DatosArea) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            // F4: abre ⌘J con el asistente del área (o su ficha si ⌘J aún no está).
            BotonPedirAAsistente(sesion: sesion, area: area, nombre: datos.asistente, contexto: "Área \(datos.titulo)")
            Button(soloRol ? "Ver todo el área" : "Ver solo lo de este rol", action: alternarSoloRol)
                .tlsBoton(.enlace)
                .disabled(datos.rol == nil)
                .help(datos.rol.map { "Enseña solo lo que lleva \($0)" } ?? "El área no dice su rol")
                .accessibilityValue(soloRol ? "Encendido" : "Apagado")
                .accessibilityIdentifier("area.soloRol")
        }
        .fixedSize()
    }

    // MARK: Destacado

    @ViewBuilder
    private func destacado(_ datos: DatosArea) -> some View {
        if let fila = datos.filaClave {
            Destacado(rotulo: "Número clave", accion: fila.metaDecidida ? nil : "Fijar la meta",
                      alPulsar: fila.metaDecidida || modelo.motivoSoloLectura != nil ? nil : { fijarMeta(fila) }) {
                HeroNumber(fila: fila)
            }
            .frame(minHeight: 168)
            .accessibilityIdentifier("area.numeroClave")
        } else {
            DestacadoVacio(rotulo: "Número clave",
                           texto: datos.control.isEmpty
                               ? "Esta área aún no tiene números en la nota Metas de Dirección. Cuando tenga uno, aquí verás cómo va."
                               : "Esta área aún no tiene número clave: elígelo en la ficha del área.")
                .frame(minHeight: 168)
                .accessibilityIdentifier("area.numeroClave")
        }
    }

    private func fijarMeta(_ fila: FilaControl) {
        modelo.editando = fila.codigo
        nav?.cambiarPestana(PestanaArea.control.rawValue)
    }

    // MARK: Estados del área

    private func activar(_ datos: DatosArea) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(spacing: TLSEspacio.e12) {
                Image(systemName: "moon.zzz").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Esta área está en reposo").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    Text("Mientras esté en reposo solo ves su resumen y ningún asistente trabaja aquí. Actívala cuando vayas a dedicarle tiempo.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let r = datos.activacionReciente {
                AvisoEnLinea(Self.avisoActivacion(r), estado: .atencion)
                    .accessibilityIdentifier("area.avisoActivar")
            }
            BotonPrincipal("Activar", icono: "power", motivoDesactivado: motivoActivar(datos)) {
                if datos.activacionReciente != nil { confirmarActivar = true } else { hacerActivar() }
            }
            .accessibilityIdentifier("area.activar")
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .confirmationDialog("¿Activar \(datos.titulo) ahora?", isPresented: $confirmarActivar) {
            Button("Activar igualmente") { hacerActivar() }
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text(datos.activacionReciente.map(Self.avisoActivacion) ?? "")
        }
        .accessibilityElement(children: .contain)
    }

    /// «Activaste 2 · Ventas hace 12 días. Lo recomendable es un área nueva cada 30 días.»
    static func avisoActivacion(_ r: ActivacionReciente) -> String {
        let cuando = r.haceDias == 0 ? "hoy" : (r.haceDias == 1 ? "hace 1 día" : "hace \(r.haceDias) días")
        return "Activaste \(r.titulo) \(cuando). Lo recomendable es un área nueva cada 30 días."
    }

    private func motivoActivar(_ datos: DatosArea) -> String? {
        if datos.ficha == nil { return "Esta área aún no tiene ficha" }
        return modelo.motivoSoloLectura
    }

    private func hacerActivar() {
        Task { await modelo.activar(deshacer: undoManager) }
    }

    private func preparada(_ datos: DatosArea) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            Image(systemName: "sparkle").font(.system(size: 18, weight: .medium))
                .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Los asistentes aún no trabajan aquí").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text("El área está preparada: puedes usarla y llevar sus números. \(datos.asistente) empezará cuando la actives.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TLSEspacio.e8)
            if datos.ficha != nil {
                Button("Activar") {
                    if datos.activacionReciente != nil { confirmarActivar = true } else { hacerActivar() }
                }
                .tlsBoton(.secundario)
                .disabled(modelo.motivoSoloLectura != nil)
                .help(modelo.motivoSoloLectura ?? "Pasar el área a activa")
            }
        }
        .padding(TLSEspacio.e16)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.bandeja.color))
        .confirmationDialog("¿Activar \(datos.titulo) ahora?", isPresented: $confirmarActivar) {
            Button("Activar igualmente") { hacerActivar() }
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text(datos.activacionReciente.map(Self.avisoActivacion) ?? "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("area.preparada")
    }

    // MARK: Textos

    /// El estado del área con su color (Hoy y la barra lateral).
    static func estado(_ e: AreaStatus) -> TLSEstado { FaseArea(e).estado }
}

/// Elige la pantalla de Operación de cada área (huecos de la fase de pantallas).
struct OperacionDeArea: View {
    let contexto: ContextoArea
    let sesion: VaultSession

    var body: some View {
        switch contexto.area {
        case .direccion: DireccionOperacion(contexto: contexto, sesion: sesion)
        case .ventas: VentasOperacion(contexto: contexto, sesion: sesion)
        case .entrega: EntregaOperacion(contexto: contexto, sesion: sesion)
        case .finanzas: FinanzasOperacion(contexto: contexto, sesion: sesion)
        case .marca: MarcaOperacion(contexto: contexto, sesion: sesion)
        case .equipo: EquipoOperacion(contexto: contexto, sesion: sesion)
        }
    }
}
