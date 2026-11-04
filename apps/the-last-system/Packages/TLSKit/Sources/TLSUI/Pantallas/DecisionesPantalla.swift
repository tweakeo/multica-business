import SwiftUI
import TLSCore
import TLSDesign

// Decisiones (PLAN §6.3; F2 · rol hoy-decisiones). Los `init` son contrato con el enrutador (`Shell/PantallaDestino`:
// `.decisiones` y `.decision(id)`; docs/F2-CONTRATOS.md §2).
//
// La lista sale de la bandeja del dominio (`BandejaDeDecisiones`, con lo de los asistentes desde F4), agrupada: Para
// aprobar · Preguntas · Propuestas de mejora · Por decidir (las tuyas) · Archivos en conflicto. El detalle es 1-3-1:
// el problema en una frase, como mucho 3 opciones con la recomendada y su porqué, las evidencias enlazadas y qué pasa
// si se pospone; teclas 1, 2 y 3, Aprobar (⌘↩), Aprobar con mis cambios, Responder, Posponer y Descartar. Decidir
// deja una línea en `Decisiones.md` con su origen y se deshace.
//
// F4 · rol mika: «Para aprobar» pasa por `SensitiveConfirmSheet` (qué sale, a quién y por cuánto; sin huellas) y
// `Aprobaciones`; las propuestas de mejora enseñan la diferencia; las preguntas de un asistente, al responder, lo
// reanudan; CRITERIO y los permisos cambiados fuera de la app tienen su detalle (`DecisionesGobierno.swift`).

/// Los grupos de la lista, en orden (PLAN §6.3, y «Por decidir» para tus propias decisiones de F2).
enum GrupoDecisiones {
    static let orden = ["Para aprobar", "Preguntas", "Propuestas de mejora", TarjetaDecision.Tipo.propuesta.grupo,
                        TarjetaDecision.Tipo.conflicto.grupo]

    /// Las tarjetas de cada grupo (los vacíos fuera, salvo «Para aprobar», que explica qué esperará ahí).
    static func agrupar(_ tarjetas: [TarjetaDecision]) -> [(grupo: String, tarjetas: [TarjetaDecision])] {
        orden.compactMap { g in
            let l = tarjetas.filter { $0.grupoF4 == g }
            return l.isEmpty && g != "Para aprobar" ? nil : (g, l)
        }
    }
}

/// Decisiones: lo que pide tu OK.
struct DecisionesPantalla: View {
    let sesion: VaultSession
    @State private var verResumen = false
    @Environment(\.navegar) private var navegar

    init(sesion: VaultSession) { self.sesion = sesion }

    private var almacen: AlmacenHoy { AlmacenHoy.de(sesion) }

    var body: some View {
        ContenedorPantalla(destino: .decisiones) {
            if let d = almacen.datos {
                cabecera(d)
                // F5 · buzon-relevo: lo que piden Mail, Calendario y los otros programas (permisos, «¿Actualizo la
                // ficha?», herramientas nuevas por revisar).
                SeccionConexionesDecisiones(sesion: sesion)
                ForEach(GrupoDecisiones.agrupar(d.decisiones), id: \.grupo) { g in grupo(g.grupo, g.tarjetas, datos: d) }
                if !d.bandeja.alResumen.isEmpty { resumenSemanal(d) }
                if !d.pospuestas.isEmpty { pospuestas(d) }
                registro
            } else {
                CabeceraAzulNoche(rotulo: "Lo que espera tu OK", titulo: "Decisiones", subtitulo: "Leyendo tu empresa…",
                                  altoMinimo: TLSAltura.cabeceraBase)
            }
        }
        .task(id: sesion.revision) { await almacen.actualizar() }
        .tlsPantalla("Decisiones")
        .accessibilityIdentifier("pantalla.decisiones")
    }

    private func cabecera(_ d: DatosHoy) -> some View {
        // F5 · buzon-relevo: también lo que piden las conexiones (permisos, Calendario, otros programas).
        let n = d.pendientes + ConexionesEnDecisiones.de(sesion).pendientes.count
        let porGrupo = Dictionary(grouping: d.decisiones, by: \.grupoF4).mapValues(\.count)
        // F4 · corrector (revisión de experiencia, P2): cada dato cuenta lo mismo que su grupo de abajo (las propuestas de
        // mejora van aparte de «Por decidir»; los conflictos solo salen si los hay).
        var datos = [DatoClave("Para aprobar", Self.cuantas(porGrupo["Para aprobar"])),
                     DatoClave("Preguntas", Self.cuantas(porGrupo["Preguntas"])),
                     DatoClave("Por decidir", Self.cuantas(porGrupo[TarjetaDecision.Tipo.propuesta.grupo])),
                     DatoClave("Mejoras", Self.cuantas(porGrupo["Propuestas de mejora"]))]
        if let c = porGrupo[TarjetaDecision.Tipo.conflicto.grupo], c > 0 { datos.append(DatoClave("En conflicto", Self.cuantas(c))) }
        return CabeceraAzulNoche(rotulo: "Lo que espera tu OK", titulo: "Decisiones",
                                 subtitulo: n == 0 ? "Nada espera tu decisión." : (n == 1 ? "1 cosa espera tu decisión." : "\(n) cosas esperan tu decisión."),
                                 datos: datos,
                                 altoMinimo: TLSAltura.cabeceraBase)
    }

    @ViewBuilder
    private func grupo(_ nombre: String, _ lista: [TarjetaDecision], datos d: DatosHoy) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(spacing: 8) {
                Text(nombre).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                if !lista.isEmpty {
                    InsigniaAviso(lista.count, palabra: lista.count == 1 ? "espera tu decisión" : "esperan tu decisión")
                }
            }
            if lista.isEmpty {
                VacioExplicado(icono: "tray", titulo: "Nada por aprobar",
                               porQue: "Aquí esperarán tu OK los borradores que preparen los asistentes (correos, publicaciones, facturas): qué sale, a quién y por cuánto. Nada sale sin que lo apruebes.",
                               compacto: true)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            } else {
                ForEach(lista) { t in
                    if let det = d.detalles[t.id] { TarjetaDecisionVista(detalle: det, sesion: sesion, hoy: d.hoy) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decisiones.grupo.\(Self.identificador(nombre))")
        .tutorialAnchor(lista.isEmpty ? "decisiones.vacio" : .decisionesGrupo)
    }

    /// `paraAprobar`, `pregunta`, `mejora`, `propuesta`, `conflicto` (para las pruebas y la accesibilidad).
    static func identificador(_ grupo: String) -> String {
        switch grupo {
        case "Para aprobar": "paraAprobar"
        case "Preguntas": "pregunta"
        case "Propuestas de mejora": "mejora"
        case TarjetaDecision.Tipo.conflicto.grupo: "conflicto"
        default: "propuesta"
        }
    }

    private func resumenSemanal(_ d: DatosHoy) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack {
                let n = d.bandeja.alResumen.count
                AvisoEnLinea(n == 1 ? "1 más espera al resumen semanal: hoy ya tienes bastantes." : "\(n) más esperan al resumen semanal: hoy ya tienes bastantes.",
                             estado: .sinDato)
                Spacer()
                Button(verResumen ? "Ocultarlas" : "Verlas ahora") { verResumen.toggle() }.tlsBoton(.enlace)
            }
            if verResumen {
                ForEach(d.bandeja.alResumen) { t in
                    if let det = d.detalles[t.id] { TarjetaDecisionVista(detalle: det, sesion: sesion, hoy: d.hoy) }
                }
            }
        }
    }

    private func pospuestas(_ d: DatosHoy) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Rotulo("Pospuestas")
            VStack(spacing: 2) {
                ForEach(d.pospuestas) { t in
                    let hasta = almacen.estado.fechasPospuestas[t.id]
                    FilaLista(t.titulo, detalle: hasta.map { "Vuelve \(AlmacenHoy.dia($0, hoy: d.hoy))" }, icono: "clock",
                              accion: { navegar(Decidir.destino(t), modo: .automatico) }) {
                        Button("Traer ahora") { almacen.traer(t) }.tlsBoton(.enlace)
                    }
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        }
    }

    @ViewBuilder private var registro: some View {
        if let r = rutaRegistro {
            Button("Abrir el registro de decisiones") { navegar(.nota(r), modo: .entrar) }.tlsBoton(.enlace)
        }
    }

    /// «Ninguna» en vez de un 0 suelto.
    static func cuantas(_ n: Int?) -> String { (n ?? 0) == 0 ? "Ninguna" : "\(n!)" }

    /// `1 · Dirección/Decisiones.md`, si existe.
    private var rutaRegistro: VaultPath? {
        guard let layout = sesion.estructura else { return nil }
        let p = RegistroDecisiones.ruta(layout)
        return sesion.resumen(de: p) == nil ? nil : p
    }
}

extension AlmacenHoy {
    /// Devuelve a la bandeja una decisión pospuesta.
    func traer(_ t: TarjetaDecision) {
        posponer(decision: t, hasta: datos?.hoy ?? LocalDate.today())
    }
}

/// Una decisión (se entra desde Hoy, desde Decisiones o desde una ficha). `id` lo decide quien la prepara; las que
/// son una nota llevan su ruta (`Destino.decision(de:)`, `destino.rutaDeDecision`); los conflictos, «conflicto:…»;
/// las que fabrica el gobierno (F4), «permisos:…», «criterio:…» o «aprobacion:…».
struct DecisionDetalle: View {
    let id: String
    let sesion: VaultSession
    @State private var elegida: Int?
    @State private var modo: Modo = .elegir
    @State private var texto = ""
    @State private var porque = ""
    @State private var trabajando = false
    @State private var hecha: String?
    /// F4 · lo que cambia si se aprueba una propuesta de un asistente (su plan frente a la carpeta).
    @State private var diferencia: [BloqueDiferencia]?
    @Environment(\.navegar) private var navegar

    enum Modo: Equatable { case elegir, conCambios, responder, descartar }

    init(id: String, sesion: VaultSession) {
        self.id = id
        self.sesion = sesion
    }

    private var almacen: AlmacenHoy { AlmacenHoy.de(sesion) }

    /// La tarjeta de la bandeja que corresponde a este destino.
    static func buscar(_ id: String, en datos: DatosHoy) -> DetalleDecision? {
        let destino = Destino.decision(id)
        if let r = destino.rutaDeDecision {
            return datos.bandeja.tarjetas.first { $0.ruta == r }.flatMap { datos.detalles[$0.id] }
        }
        return datos.detalles[id]
    }

    var body: some View {
        ContenedorPantalla(destino: .decision(id)) {
            if let d = almacen.datos {
                if let det = Self.buscar(id, en: d) {
                    contenido(det, hoy: d.hoy)
                } else {
                    yaNoEsta
                }
            } else {
                CabeceraAzulNoche(rotulo: "Decisión", titulo: "Leyendo la decisión…", altoMinimo: TLSAltura.cabeceraBase)
            }
        }
        .task(id: sesion.revision) { await almacen.actualizar() }
        .tlsPantalla("Decisión")
        .accessibilityIdentifier("pantalla.decision")
    }

    @ViewBuilder private var yaNoEsta: some View {
        let ruta = Destino.decision(id).rutaDeDecision
        CabeceraAzulNoche(rotulo: "Decisión", titulo: ruta.map { sesion.titulo(de: $0) } ?? "Decisión", altoMinimo: TLSAltura.cabeceraBase)
        if let hecha {
            VacioExplicado(icono: "checkmark.circle", titulo: "Decidido", porQue: "\(hecha). Puedes deshacerlo con ⌘Z o desde el aviso.",
                           accion: "Volver a Decisiones", alPulsar: { navegar(.decisiones, modo: .raiz) })
        } else {
            VacioExplicado(icono: "checkmark.circle", titulo: "Ya no espera tu decisión",
                           porQue: "Se decidió, se descartó o dejó de estar en la bandeja.",
                           accion: ruta == nil ? "Volver a Decisiones" : "Abrir la nota",
                           alPulsar: { if let r = ruta { navegar(sesion.destino(para: r), modo: .entrar) } else { navegar(.decisiones, modo: .raiz) } })
        }
    }

    // MARK: Contenido

    @ViewBuilder
    private func contenido(_ d: DetalleDecision, hoy: LocalDate) -> some View {
        let t = d.tarjeta
        CabeceraAzulNoche(rotulo: t.grupoF4 + (t.area.map { " · \($0.etiquetaNumerada)" } ?? ""), titulo: t.titulo,
                          subtitulo: [d.quien, d.desde].compactMap { $0 }.joined(separator: " · "),
                          estado: t.prioridad == .roja ? EstadoCabecera(t.motivo ?? "En rojo", estado: .mal)
                              : (t.gobierno?.cambio == true ? EstadoCabecera("Cambió desde que lo preparó el asistente", estado: .atencion) : nil),
                          altoMinimo: TLSAltura.cabeceraFichaMinima) {
            if let r = t.ruta, t.tipo != .conflicto {
                Button(t.tipo == .paraAprobar ? "Abrir el borrador" : "Abrir la nota") {
                    navegar(sesion.destino(para: r), modo: .automatico)
                }
                .tlsBoton(.sobreCabecera)
            }
        }
        seccion("El problema") {
            Text(t.problema.map(LinkParser.plainText) ?? "La nota no lo dice en una frase.").tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        switch t.gobierno?.clase {
        case .aprobacion?:
            DetalleAprobacionVista(detalle: d, sesion: sesion)
            EvidenciasDecision(evidencias: d.evidencias, sesion: sesion)
            siLoPospones(d)
        case .cambioDePermisos?:
            if let p = t.porque { AvisoEnLinea(p, estado: .sinDato) }
            DetallePermisosVista(tarjeta: t, sesion: sesion)
            siLoPospones(d)
        case .criterio?:
            if let p = t.porque { AvisoEnLinea(p, estado: .sinDato) }
            DetalleCriterioVista(tarjeta: t, sesion: sesion)
            siLoPospones(d)
        default:
            general(d)
        }
    }

    /// Lo de F2 (y las propuestas y preguntas de los asistentes): opciones, acciones, evidencias y qué cambia.
    @ViewBuilder
    private func general(_ d: DetalleDecision) -> some View {
        let t = d.tarjeta
        if !t.opciones.isEmpty {
            seccion("Opciones") {
                VStack(spacing: 8) {
                    ForEach(t.opciones) { o in
                        OpcionDecisionVista(opcion: o, porque: o.recomendada ? t.porque : nil, elegida: elegida == o.numero, tecla: true) {
                            elegir(o.numero, d)
                        }
                    }
                }
            }
        } else if !d.respuestas.isEmpty {
            // F4 · corrector (P3): en una pregunta son respuestas, no «lo que propone».
            seccion(t.tipo == .pregunta ? "Respuestas que sugiere" : "Lo que propone") {
                VStack(spacing: 8) {
                    ForEach(d.respuestas) { r in
                        OpcionDecisionVista(datos: .init(numero: r.numero, texto: r.texto, recomendada: r.recomendada), porque: nil,
                                            elegida: elegida == r.numero, tecla: modo == .elegir) {
                            elegir(r.numero, d)
                        }
                    }
                }
            }
        }
        if let m = d.motivoNoDecidir { AvisoEnLinea(m, estado: .sinDato) }
        acciones(d)
        EvidenciasDecision(evidencias: d.evidencias, sesion: sesion)
        if t.gobierno?.propuesta != nil {
            seccion("Qué cambia si eliges la \(t.recomendada?.numero ?? 1)") {
                if let dif = diferencia {
                    if dif.isEmpty {
                        Text("No cambia nada en la carpeta: es una decisión, no una edición.").tlsTexto(TLSTipo.interfaz)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    } else {
                        DiferenciaPropuestaVista(bloques: dif, sesion: sesion)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .task(id: t.gobierno?.propuesta) { diferencia = await cargarDiferencia(t) }
        } else if let c = d.queCambia {
            seccion("Qué cambia si se aprueba") { Text(c).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color) }
        }
        siLoPospones(d)
    }

    private func siLoPospones(_ d: DetalleDecision) -> some View {
        seccion("Si lo pospones") {
            Text(d.siSePospone).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// El plan guardado de la propuesta frente a lo que hay ahora.
    private func cargarDiferencia(_ t: TarjetaDecision) async -> [BloqueDiferencia] {
        guard let id = t.gobierno?.propuesta, let a = AsistentesDeLaEmpresa.de(sesion).autorizador,
              let foto = await sesion.instantanea() else { return [] }
        let plan = await Task.detached(priority: .userInitiated) { (try? AlmacenPropuestas(estado: a.estado).propuesta(id))?.plan }.value
        guard let plan else { return [] }
        return DiferenciaDePropuesta.de(plan, foto: foto)
    }

    private func seccion<C: View>(_ titulo: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rotulo(titulo)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Elegir y escribir

    /// Las opciones de esta tarjeta (número y texto): las de la 1-3-1 o, en una pregunta de un asistente, lo que propone.
    private func opciones(_ d: DetalleDecision) -> [(numero: Int, texto: String)] {
        d.tarjeta.opciones.isEmpty ? d.respuestas.map { ($0.numero, $0.texto) } : d.tarjeta.opciones.map { ($0.numero, $0.texto) }
    }

    /// «1, 2 o 3», «1 o 2» o «1»: las teclas de las opciones que hay de verdad.
    static func teclas(_ d: DetalleDecision) -> String {
        let n = (d.tarjeta.opciones.isEmpty ? d.respuestas.map(\.numero) : d.tarjeta.opciones.map(\.numero)).sorted().map(String.init)
        switch n.count {
        case 0, 1: return n.first ?? "1"
        default: return n.dropLast().joined(separator: ", ") + " o " + n.last!
        }
    }

    private func elegir(_ n: Int, _ d: DetalleDecision) {
        let lista = opciones(d)
        guard let o = lista.first(where: { $0.numero == n }) else { return }
        elegida = n
        if modo == .conCambios || modo == .responder { texto = o.texto }
    }

    private var motivoEscritura: String? { Decidir.motivoSoloLectura(sesion) }

    /// Una pregunta de un asistente con respuestas propuestas: se elige una (1, 2, 3) o se contesta con tus palabras.
    private func conRespuestas(_ d: DetalleDecision) -> Bool { d.tarjeta.tipo == .pregunta && !d.respuestas.isEmpty }

    @ViewBuilder
    private func acciones(_ d: DetalleDecision) -> some View {
        let t = d.tarjeta
        let sinOpciones = opciones(d).isEmpty
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if t.tipo == .propuesta || t.tipo == .pregunta {
                if (sinOpciones && modo != .descartar) || modo == .conCambios {
                    campo(t.tipo == .pregunta && sinOpciones ? "Tu respuesta, en una frase" : "Qué decides, en una frase", $texto)
                    if t.tipo == .propuesta || modo == .conCambios { campo("Por qué (opcional)", $porque) }
                }
                if modo == .responder { campo("Tu respuesta", $texto) }
                if modo == .descartar { campo("Por qué la descartas (opcional)", $porque) }
            }
            FlujoChips(espacio: 8) {
                botonPrincipal(d)
                if t.tipo == .propuesta, !sinOpciones, modo == .elegir {
                    Button("Aprobar con mis cambios") {
                        modo = .conCambios
                        let o = t.opciones.first { $0.numero == elegida } ?? t.recomendada
                        texto = o?.texto ?? ""
                        porque = ""
                        if let o { elegida = o.numero }
                    }
                    .tlsBoton(.secundario)
                    .disabled(motivoEscritura != nil)
                    .help(t.gobierno?.propuesta != nil ? "Decide con tus palabras: queda en el registro y el cambio del asistente no se aplica" : "")
                }
                if (t.tipo == .propuesta || conRespuestas(d)), modo == .elegir {
                    Button(conRespuestas(d) ? "Responder con mis palabras" : "Responder") {
                        modo = .responder
                        texto = ""
                    }
                    .tlsBoton(.secundario)
                    .disabled(motivoEscritura != nil)
                }
                if modo != .elegir {
                    // F4 · corrector (P3): Esc cancela, como en las hojas.
                    Button("Cancelar") { modo = .elegir; texto = ""; porque = "" }.tlsBoton(.secundario)
                        .keyboardShortcut(.cancelAction)
                }
                MenuPosponer(tarjeta: t, sesion: sesion)
                if t.tipo == .propuesta || t.tipo == .pregunta, modo == .elegir {
                    Button("Descartar") { modo = .descartar; porque = "" }.tlsBoton(.secundario).disabled(motivoEscritura != nil)
                }
                if t.tipo == .paraAprobar, let r = t.ruta {
                    Button("Abrir el borrador") { navegar(sesion.destino(para: r), modo: .automatico) }.tlsBoton(.secundario)
                }
            }
            if let m = motivoEscritura, t.tipo != .conflicto {
                AvisoEnLinea("Solo lectura: \(m).", estado: .sinDato)
            } else if !sinOpciones, elegida == nil, modo == .elegir, d.motivoNoDecidir == nil {
                Text(t.tipo == .pregunta ? "Elige una respuesta (\(Self.teclas(d))) y pulsa Responder (⌘↩)."
                                         : "Elige una opción (\(Self.teclas(d))) y pulsa Aprobar (⌘↩).")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            } else if sinOpciones, t.tipo == .propuesta || t.tipo == .pregunta, modo == .elegir,
                      texto.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(t.tipo == .pregunta ? "Escribe tu respuesta y pulsa Responder (⌘↩)." : "Escribe qué decides y pulsa Aprobar (⌘↩): queda en el registro de decisiones.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if t.gobierno?.clase == .pregunta {
                Text("Al responder, \(t.gobierno?.asistente.map(AsistenteConfigurado.nombre(de:)) ?? "el asistente") sigue con lo que estaba haciendo.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .background { teclas(d) }
    }

    /// Teclas 1, 2 y 3 para elegir opción (solo mientras no se escribe: si no, el número iría al texto).
    @ViewBuilder
    private func teclas(_ d: DetalleDecision) -> some View {
        if modo == .elegir {
            ZStack {
                ForEach(opciones(d), id: \.numero) { o in
                    Button("Elegir la opción \(o.numero)") { elegir(o.numero, d) }
                        .keyboardShortcut(KeyEquivalent(Character("\(o.numero)")), modifiers: [])
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func campo(_ titulo: String, _ valor: Binding<String>) -> some View {
        TextField(titulo, text: valor, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .frame(maxWidth: 640)
            .accessibilityLabel(titulo)
    }

    @ViewBuilder
    private func botonPrincipal(_ d: DetalleDecision) -> some View {
        let t = d.tarjeta
        let (titulo, motivo) = principal(d)
        Button(titulo) {
            trabajando = true
            Task {
                await ejecutar(d)
                trabajando = false
            }
        }
        .tlsBoton(.principal)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(motivo != nil || trabajando)
        .help(motivo ?? "\(titulo) (⌘↩)")
        .accessibilityIdentifier("decision.aprobar")
        .accessibilityHint(t.tipo == .conflicto ? "" : (t.gobierno?.clase == .pregunta ? "El asistente sigue con tu respuesta" : "Queda en el registro de decisiones"))
    }

    /// El botón principal y, si no se puede pulsar, por qué.
    private func principal(_ d: DetalleDecision) -> (String, String?) {
        let t = d.tarjeta
        let vacio = texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (t.tipo, modo) {
        case (.paraAprobar, _): return (d.correoParaPreparar ? "Revisar y aprobar…" : "Aprobar", d.motivoNoDecidir)
        case (.conflicto, _): return ("Aprobar", elegida == nil ? "Elige una opción" : nil)
        case (_, .responder): return ("Enviar la respuesta", motivoEscritura ?? (vacio ? "Escribe tu respuesta" : nil))
        case (_, .descartar): return ("Descartar la decisión", motivoEscritura)
        case (_, .conCambios): return ("Aprobar con mis cambios", motivoEscritura ?? (vacio ? "Escribe qué decides" : nil))
        default:
            if conRespuestas(d) { return ("Responder", motivoEscritura ?? (elegida == nil ? "Elige una respuesta" : nil)) }
            if t.opciones.isEmpty {
                return (t.tipo == .pregunta ? "Responder" : "Aprobar", motivoEscritura ?? (vacio ? "Escribe qué decides" : nil))
            }
            return ("Aprobar", motivoEscritura ?? (elegida == nil ? "Elige una opción" : nil))
        }
    }

    private func ejecutar(_ d: DetalleDecision) async {
        let t = d.tarjeta
        let opcion = elegida.flatMap { n in t.opciones.first { $0.numero == n } }
        let respuestaElegida = elegida.flatMap { n in d.respuestas.first { $0.numero == n } }?.texto
        let delAsistente = t.gobierno?.clase == .pregunta
        let propuesta = t.gobierno?.propuesta
        func responder(_ s: String) async -> Bool {
            delAsistente ? await Decidir.responderAlAsistente(t, texto: s, sesion: sesion) : await Decidir.responder(t, texto: s, sesion: sesion)
        }
        switch (t.tipo, modo) {
        case (.paraAprobar, _):
            // F5 · corrector (P1-1): el correo del Cartero se prepara para aprobar aquí; la tarjeta pasa a la hoja de siempre.
            if d.correoParaPreparar { _ = await Decidir.prepararCorreo(t, sesion: sesion) }
        case (.conflicto, _):
            guard let o = opcion else { return }
            await Decidir.resolver(t, opcion: o, sesion: sesion, navegar: navegar)
        case (_, .responder):
            if t.tipo == .pregunta {
                if await responder(texto) { hecha = "Respondida: \(texto)" }
            } else if await Decidir.responder(t, texto: texto, sesion: sesion) {
                modo = .elegir; texto = ""
            }
        case (_, .descartar):
            if let p = propuesta {
                if await Decidir.descartarPropuesta(t, propuesta: p, motivo: porque, sesion: sesion) { hecha = "Descartada: no cambia nada" }
            } else if await Decidir.descartar(t, motivo: porque, sesion: sesion) {
                hecha = "Descartada"
            }
        case (_, .conCambios):
            if let p = propuesta {
                if await Decidir.decidirPropuestaConMisPalabras(t, propuesta: p, texto: texto, porque: porque, sesion: sesion) {
                    hecha = "Decidido: \(texto)"
                }
            } else if await Decidir.decidir(t, opcion: opcion, texto: texto, porque: porque, sesion: sesion) {
                hecha = "Decidido: \(texto)"
            }
        default:
            if t.tipo == .pregunta {
                let respuesta = respuestaElegida ?? opcion?.texto ?? texto
                if await responder(respuesta) { hecha = "Respondida: \(respuesta)" }
            } else if let p = propuesta, let o = opcion {
                if await Decidir.decidirPropuesta(t, propuesta: p, opcion: o, sesion: sesion) {
                    hecha = o.numero == (t.recomendada?.numero ?? 1) ? "Aplicado: \(o.texto)" : "Decidido: \(o.texto)"
                }
            } else if t.opciones.isEmpty {
                if await Decidir.decidir(t, opcion: nil, texto: texto, porque: porque, sesion: sesion) { hecha = "Decidido: \(texto)" }
            } else if let o = opcion {
                if await Decidir.decidir(t, opcion: o, texto: o.texto, porque: o.recomendada ? t.porque : nil, sesion: sesion) {
                    hecha = "Decidido: \(o.texto)"
                }
            }
        }
    }
}
