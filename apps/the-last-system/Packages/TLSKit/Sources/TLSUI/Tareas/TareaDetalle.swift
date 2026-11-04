import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol tareas (antes HUECO del andamio). El `init` es contrato con el enrutador (`Shell/PantallaDestino`,
// `.tarea(ruta)`; docs/F2-CONTRATOS.md §2). PLAN §6.4 (`TaskDetailView`) y DISENO §3.4 «Tarea»: cabecera azul noche
// con el estado y los datos (número, área, responsable), un destacado violeta (estado y vencimiento con su acción,
// o el estado vivo del asistente), a la izquierda «Descripción» —lo único del cuerpo que se edita, con
// `sustituirSeccion`— y la Actividad como línea de tiempo con la caja de comentario (@ para un asistente); a la
// derecha, el panel fijo de propiedades con el área en solo lectura y «Mover a…». Ningún asistente pone Hecha ni
// Cancelada (`TaskStore`).

/// El detalle de una tarea.
struct TareaDetalle: View {
    let ruta: VaultPath
    let sesion: VaultSession
    @State private var modelo: ModeloTarea
    @State private var ancho: CGFloat = 1100
    @Environment(\.navegar) private var navegar

    init(ruta: VaultPath, sesion: VaultSession) {
        self.ruta = ruta
        self.sesion = sesion
        _modelo = State(initialValue: ModeloTarea(ruta: ruta, sesion: sesion))
    }

    /// Desde este ancho, el panel de propiedades va a la derecha (si no, debajo de la cabecera).
    static let anchoDosColumnas: CGFloat = 900

    var body: some View {
        ContenedorPantalla(destino: .tarea(ruta), espacio: TLSEspacio.e16) {
            if modelo.esPrivada {
                VacioExplicado(icono: "lock", titulo: "Esta tarea es privada",
                               porQue: "Lo privado no sale en Tareas. Ábrela desde su carpeta si la necesitas.")
                    .frame(maxWidth: .infinity)
            } else if let t = modelo.tarea {
                contenido(t)
            } else if modelo.ficha.lector.nota == nil || modelo.ficha.almacen.foto == nil {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Abriendo la tarea…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            } else {
                VacioExplicado(icono: "questionmark.square", titulo: "No encuentro esta tarea",
                               porQue: "Puede que se haya movido o retirado fuera de la app. Búscala en Tareas.",
                               accion: "Ir a Tareas", alPulsar: { navegar(.tareas, modo: .raiz) })
                    .frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task(id: sesion.revision) { await modelo.cargar() }
    }

    @ViewBuilder
    private func contenido(_ t: Tarea) -> some View {
        CabeceraTarea(modelo: modelo, tarea: t)
        if ancho >= Self.anchoDosColumnas {
            HStack(alignment: .top, spacing: TLSEspacio.e16) {
                columnaPrincipal(t).frame(maxWidth: .infinity, alignment: .topLeading)
                PanelPropiedadesTarea(modelo: modelo, tarea: t).frame(width: 300)
            }
        } else {
            DestacadoTarea(modelo: modelo, tarea: t).fixedSize(horizontal: false, vertical: true)
            PanelPropiedadesTarea(modelo: modelo, tarea: t)
            columnaPrincipal(t, conDestacado: false)
        }
    }

    private func columnaPrincipal(_ t: Tarea, conDestacado: Bool = true) -> some View {
        let cuerpo = NoteDocument(text: modelo.texto).body
        let secciones = Self.otrasSecciones(cuerpo)
        return VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if conDestacado { DestacadoTarea(modelo: modelo, tarea: t).fixedSize(horizontal: false, vertical: true) }
            if MarkdownSections.content(of: "Descripción", in: cuerpo, level: 2) != nil {
                BloqueSeccion(modelo: modelo.ficha, titulo: "Descripción", ruta: ruta, cuerpo: cuerpo,
                              guia: "Qué hay que hacer y cómo sabrás que está hecho. Las casillas de aquí son pasos de esta tarea, no tareas nuevas.")
            } else {
                Text("Esta tarea no tiene «Descripción»: su texto se ve abajo tal cual. Para cambiarlo, abre su nota desde Carpeta.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // El resto del cuerpo (Problema, Opciones…) se lee aquí; solo «Descripción» se edita en el sitio.
            ForEach(secciones, id: \.titulo) { s in SeccionLeida(titulo: s.titulo, texto: s.texto) }
            ActividadDeTareaVista(modelo: modelo, tarea: t)
        }
    }

    /// Las secciones `##` del cuerpo que no son «Descripción» ni «Actividad», con su texto.
    static func otrasSecciones(_ cuerpo: String) -> [(titulo: String, texto: String)] {
        MarkdownSections.titles(in: cuerpo, level: 2)
            .filter { !["descripcion", "actividad"].contains(TextFolding.fold($0)) }
            .compactMap { titulo in
                guard let c = MarkdownSections.content(of: titulo, in: cuerpo, level: 2) else { return nil }
                let limpio = c.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("> Guía:") }
                    .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return (titulo, limpio)
            }
    }
}

/// Una sección del cuerpo que se lee y no se edita aquí.
private struct SeccionLeida: View {
    let titulo: String
    let texto: String

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text(titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
            if texto.isEmpty {
                Text("Vacía.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                TextoDeSeccion(texto: texto, guia: nil)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
    }
}

/// Cabecera azul noche de la tarea: número, título, de dónde cuelga, estado (menú) y número · área · responsable.
private struct CabeceraTarea: View {
    let modelo: ModeloTarea
    let tarea: Tarea
    @Environment(\.navegar) private var navegar

    var body: some View {
        let estado = tarea.estado ?? .sinProgramar
        let deAsistente = tarea.responsable?.lowercased().hasPrefix("agente:") == true
        let opciones = EstadoTarea.allCases.map { e -> OpcionEstado in
            var motivo: String?
            if !modelo.puedeEscribir { motivo = "No se puede cambiar: \(modelo.motivoSoloLectura ?? "solo lectura")" }
            return OpcionEstado(id: e.rawValue, titulo: e.rawValue, estado: e.tlsEstado, motivoDesactivado: e == estado ? "Ya está así" : motivo)
        }
        let cabeceraEstado = EstadoCabecera(tarea.estadoTexto.flatMap { EstadoTarea(leyendo: $0) == nil ? $0 : nil } ?? estado.rawValue,
                                            estado: estado.tlsEstado, opciones: opciones) { o in
            guard let e = EstadoTarea(rawValue: o.id) else { return }
            Task { await modelo.cambiarEstado(e) }
        }
        CabeceraAzulNoche(rotulo: tipo, titulo: tarea.titulo, subtitulo: cuelga, estado: cabeceraEstado,
                          datos: [DatoClave("Número", tarea.numero ?? "Sin número"),
                                  DatoClave("Área", tarea.area.map { "\($0.numero) · \($0.nombre)" } ?? "Sin área"),
                                  DatoClave("Responsable", tarea.responsable.map(Responsables.nombre(de:)) ?? "Nadie")],
                          identidad: { AvatarCabecera(simbolo: deAsistente ? "sparkles" : "checkmark.square") },
                          acciones: { acciones })
    }

    private var tipo: String {
        switch tarea.tipo.map(TextFolding.fold) {
        case "decision": "Decisión · \(tarea.numero ?? "")"
        case "pregunta": "Pregunta · \(tarea.numero ?? "")"
        default: "Tarea · \(tarea.numero ?? "")"
        }
    }

    /// El nombre de un proyecto u oportunidad (del grafo; si no, su propiedad `nombre` o su carpeta).
    private func nombre(_ p: VaultPath) -> String {
        if let n = modelo.ficha.grafo?.ficha(p)?.nombre { return n }
        if let n = modelo.ficha.almacen.foto?.frontmatter(p).text("nombre") { return n }
        return p.name == "Proyecto.md" ? (p.parent?.name ?? p.stem) : p.stem
    }

    private var cuelga: String {
        if let p = tarea.proyecto ?? tarea.proyectoPorRuta, !modelo.sesion.esPrivado(p) {
            let n = nombre(p)
            return "Del proyecto «\(n)»"
        }
        if let o = tarea.oportunidad, !modelo.sesion.esPrivado(o) {
            let n = nombre(o)
            return "De la oportunidad «\(n)»"
        }
        return "Sin proyecto" + (tarea.area.map { ", en \($0.numero) · \($0.nombre)" } ?? "")
    }

    @ViewBuilder private var acciones: some View {
        if let c = tarea.proyecto ?? tarea.proyectoPorRuta ?? tarea.oportunidad, !modelo.sesion.esPrivado(c) {
            Button("Abrir \((tarea.proyecto ?? tarea.proyectoPorRuta) != nil ? "el proyecto" : "la oportunidad")") {
                navegar(modelo.sesion.destino(para: c), modo: .entrar)
            }
            .tlsBoton(.sobreCabecera, alto: 36)
        }
        if TextFolding.fold(tarea.tipo ?? "") == "decision" || TextFolding.fold(tarea.tipo ?? "") == "pregunta" {
            Button("Ver en Decisiones") { navegar(.decision(de: tarea.ruta), modo: .entrar) }
                .tlsBoton(.sobreCabecera, alto: 36)
        }
    }
}

/// El destacado violeta (uno por pantalla): el estado vivo del asistente que la lleva, o el estado y el
/// vencimiento con su acción («Empezar ahora», «Marcar como hecha»).
private struct DestacadoTarea: View {
    let modelo: ModeloTarea
    let tarea: Tarea
    @Environment(\.navegar) private var navegar

    /// Una decisión o una pregunta se decide en Decisiones (queda su línea en el registro), no se marca hecha aquí.
    private var esDecision: Bool { ["decision", "pregunta"].contains(TextFolding.fold(tarea.tipo ?? "")) }

    var body: some View {
        let hoy = modelo.hoy
        let estado = tarea.estado ?? .sinProgramar
        let accion = self.accion(estado)
        let activa = modelo.puedeEscribir || (esDecision && estado.cerrada == false)
        Destacado(rotulo: rotulo, accion: activa ? accion?.0 : nil,
                  alPulsar: activa ? accion?.1 : nil) {
            VStack(alignment: .leading, spacing: 6) {
                if EstadoAsistenteTarea.de(tarea, hoy: hoy) != nil {
                    EstadoEnVivoDeTarea(sesion: modelo.sesion, tarea: tarea, hoy: hoy)  // F4 · rol asistentes
                } else {
                    CifraDestacada(cifra(hoy: hoy), contexto: contexto(hoy: hoy), estilo: TLSTipo.cifraMedia)
                }
                if accion != nil, !activa, let m = modelo.motivoSoloLectura {
                    Text("No se puede cambiar: \(m).").tlsTexto(TLSTipo.secundario).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var rotulo: String {
        EstadoAsistenteTarea.de(tarea, hoy: modelo.hoy) != nil ? "La lleva un asistente" : "Siguiente paso"
    }

    private func cifra(hoy: LocalDate) -> String {
        if let c = tarea.cerrada, (tarea.estado?.cerrada ?? false) { return "\(tarea.estado?.rawValue ?? "Cerrada") el \(FormatoFicha.fechaCorta(c, hoy: hoy))" }
        if tarea.estado?.cerrada == true { return tarea.estado?.rawValue ?? "Cerrada" }
        guard let v = tarea.vence else { return "Sin fecha límite" }
        if v < hoy {
            let d = FormatoFicha.dias(de: v, a: hoy)
            return d == 1 ? "Vencida ayer" : "Vencida hace \(d) días"
        }
        if v == hoy { return "Vence hoy" }
        let d = FormatoFicha.dias(de: hoy, a: v)
        return d == 1 ? "Vence mañana" : "Vence en \(d) días"
    }

    private func contexto(hoy: LocalDate) -> String {
        var partes: [String] = []
        if let v = tarea.vence, tarea.estado?.cerrada != true { partes.append("Fecha límite: " + FormatoFicha.fechaConDia(v, hoy: hoy)) }
        if let p = tarea.planificada { partes.append("Planificada " + FormatoFicha.cuando(p, hoy: hoy)) }
        else if tarea.estado?.cerrada != true { partes.append("Sin día para hacerla") }
        return partes.joined(separator: " · ")
    }

    private func accion(_ estado: EstadoTarea) -> (String, () -> Void)? {
        if esDecision, !estado.cerrada {
            let ruta = tarea.ruta
            return ("Decidir en Decisiones", { navegar(.decision(de: ruta), modo: .entrar) })
        }
        switch estado {
        case .sinProgramar, .porHacer:
            if estado == .porHacer, EstadoAsistenteTarea.de(tarea, hoy: modelo.hoy) == .enCola { return nil }
            return ("Empezar ahora", { Task { await modelo.empezarAhora() } })
        case .enCurso, .enRevision, .bloqueada:
            return ("Marcar como hecha", { Task { await modelo.cambiarEstado(.hecha) } })
        case .hecha, .cancelada:
            return nil
        }
    }
}
