import Foundation
import Observation
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol mika. ⌘J: la conversación con Mika (PLAN §6.1, §5.3 «Chat»). Una por empresa abierta (sobrevive a cerrar el
// panel y a cambiar de pantalla). Cada mensaje lleva el contexto de la pantalla; la respuesta se va escribiendo en
// pantalla («en streaming») y lo que Mika hizo con sus herramientas aparece debajo como tarjetas enlazadas (sale de
// la auditoría del Autorizador, no del texto).
//
// - Con Claude Code (lo conecta la integración): `SesionDeChat` con su proceso vivo; un turno por mensaje.
// - Sin Claude Code (o en pausa, o sin tope): el enrutador determinista de 14 intenciones (`RespuestasSinClaude`) y
//   **lo dice** en cada respuesta. Nunca escribe: lo que cambia algo vuelve como propuesta con su botón, y lo aplica
//   la persona (como ella, con Deshacer).
// - Acciones rápidas: con el motor, un trabajo en la cola del asistente que toca (`AgentHost.pedir`); sin él, se le
//   pregunta a Mika con el mismo texto.

/// Cómo contesta Mika ahora.
enum ModoMika: Sendable, Hashable {
    /// Con Claude Code.
    case claude
    /// La demo: grabaciones (marca «Simulado»).
    case simulado
    /// Sin Claude Code: lo que sabe mirar la app.
    case sinClaude

    var titulo: String {
        switch self {
        case .claude: "Con Claude Code"
        case .simulado: "Simulado"
        case .sinClaude: "Sin Claude Code"
        }
    }

    var explicacion: String {
        switch self {
        case .claude: "Mika lee tu carpeta con sus herramientas y nunca envía nada sin tu OK."
        case .simulado: "Es el ejemplo: las respuestas están grabadas y lo que hace Mika queda marcado como simulado."
        case .sinClaude: "Te contesto con lo que sé mirar en tu carpeta, sin inventar nada. Para conversar de verdad, conecta Claude Code en Ajustes."
        }
    }
}

@MainActor
@Observable
final class ConversacionMika {
    enum Quien: Sendable, Hashable { case tu, mika }

    struct Mensaje: Identifiable, Hashable {
        let id = UUID()
        let quien: Quien
        /// Lo que ya se ve (se va completando mientras se escribe).
        var texto: String
        /// El texto entero.
        var completo: String
        var filas: [FilaDeRespuesta] = []
        var propuesta: PropuestaDeChat?
        /// «Hecho: …» tras aplicar la propuesta.
        var propuestaHecha: String?
        var ir: Destino?
        var tarjetas: [TarjetaEnlazada] = []
        var modo: ModoMika?
        let hora: Date
        var escribiendo: Bool { texto.count < completo.count }
    }

    private(set) var mensajes: [Mensaje] = []
    /// Esperando la respuesta de Mika.
    private(set) var pensando = false
    /// «Mika está mirando tu carpeta…» (o la frase en vivo de su trabajo).
    private(set) var frase = "Mika está pensando…"
    /// El panel está abierto.
    var abierto = false
    /// Lo que estás escribiendo.
    var borrador = ""
    private(set) var contexto: ContextoPantalla = .general
    /// Cómo contestó la última vez (o cómo contestará, si aún no ha contestado con el chat de ahora).
    var modo: ModoMika { modoRespondido ?? modoPrevisto }
    /// Cómo contestó la última vez con el chat de ahora (`nil` si aún no ha contestado o el chat cambió).
    private(set) var modoRespondido: ModoMika?
    /// F4 · corrector (revisión de experiencia, P2): cómo contestará, mirado en el momento (la integración conecta el
    /// chat después de pintar la ventana): sin chat conectado, sin Claude Code; en el ejemplo, simulado.
    var modoPrevisto: ModoMika {
        guard let sesion else { return .sinClaude }
        guard AsistentesDeLaEmpresa.de(sesion).fabricaDeChat != nil else { return .sinClaude }
        return sesion.entry.clase == .demo ? .simulado : .claude
    }

    /// Ritmo al que aparece la respuesta (`nil` = de golpe: pruebas, «Reducir movimiento»).
    @ObservationIgnored var ritmo: Duration? = .milliseconds(16)
    @ObservationIgnored private weak var sesion: VaultSession?
    @ObservationIgnored private var canal: (any CanalDeMika)?
    /// La `versionDelChat` con la que se abrió `canal`.
    @ObservationIgnored private var versionDelCanal: Int?
    /// Para pruebas: el canal que se usa en vez del de la empresa.
    @ObservationIgnored var canalDePrueba: (any CanalDeMika)?
    @ObservationIgnored private var revelando: Task<Void, Never>?

    private final class Entrada {
        weak var sesion: VaultSession?
        let valor: ConversacionMika
        init(_ s: VaultSession, _ v: ConversacionMika) { sesion = s; valor = v }
    }

    private static var porSesion: [ObjectIdentifier: Entrada] = [:]

    static func de(_ sesion: VaultSession) -> ConversacionMika {
        for (k, e) in porSesion where e.sesion == nil {
            // La empresa se cerró: el chat con Claude se cierra (y se revoca su permiso).
            if let c = e.valor.canal { Task { await c.cerrar() } }
            porSesion[k] = nil
        }
        let k = ObjectIdentifier(sesion)
        if let e = porSesion[k], e.sesion === sesion { return e.valor }
        let v = ConversacionMika(sesion: sesion)
        porSesion[k] = Entrada(sesion, v)
        return v
    }

    init(sesion: VaultSession?) {
        self.sesion = sesion
    }

    var asistentes: AsistentesDeLaEmpresa? { sesion.map(AsistentesDeLaEmpresa.de) }

    // MARK: Abrir y cerrar

    /// ⌘J y el botón de la barra: abre con el contexto de la pantalla (o cierra si ya estaba abierto).
    func alternar(contexto c: ContextoPantalla) {
        if abierto { abierto = false } else { abrir(contexto: c) }
    }

    func abrir(contexto c: ContextoPantalla, para asistente: String? = nil) {
        contexto = c
        abierto = true
        // Desde la ficha de otro asistente: el mensaje empieza dirigido a él (Mika se lo pasa).
        if let a = asistente, a != "mika", borrador.isEmpty {
            borrador = "Para \(AsistenteConfigurado.nombre(de: a)): "
        }
    }

    /// Cierra el chat con Claude (si lo hay); la conversación se queda en pantalla.
    func terminarChat() async {
        if let c = canal { await c.cerrar() }
        canal = nil
        versionDelCanal = nil
        modoRespondido = nil
    }

    // MARK: Hablar

    /// Las acciones rápidas de esta pantalla.
    var accionesRapidas: [AccionRapidaMika] { contexto.accionesRapidas() }

    /// Manda lo escrito.
    func enviar() async {
        let texto = borrador.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, !pensando else { return }
        borrador = ""
        await enviar(texto, mostrar: texto)
    }

    /// Manda un mensaje (lo que se ve como tuyo puede ser más corto que lo que se le pide).
    func enviar(_ texto: String, mostrar: String) async {
        guard !pensando else { return }
        mensajes.append(Mensaje(quien: .tu, texto: mostrar, completo: mostrar, hora: Date()))
        pensando = true
        frase = "Mika está mirando tu carpeta…"
        let desde = Date()
        let canal = canalActual()
        let r = await canal.enviar(texto, pantalla: contexto.paraMika)
        let modo: ModoMika = r.simulado ? .simulado : (r.modo == .claude ? .claude : .sinClaude)
        modoRespondido = modo
        var m = Mensaje(quien: .mika, texto: "", completo: r.texto, filas: r.filas, propuesta: r.propuesta,
                        ir: destino(r.ir), modo: modo, hora: Date())
        m.tarjetas = await tarjetas(ejecucion: canal.id, desde: desde)
        pensando = false
        mensajes.append(m)
        revelar(m.id)
        // Tutorial (F4): «Pregunta al asistente con ⌘J» se marca al recibir la respuesta.
        if let sesion { TutorialEventos.registrar(.asistenteAbierto, empresa: sesion.entry.id) }
    }

    /// Una acción rápida: con el motor, un trabajo para el asistente que toca; sin él, se le pregunta a Mika.
    func pedir(_ a: AccionRapidaMika) async {
        guard !pensando else { return }
        guard let host = asistentes?.host else {
            await enviar(a.peticion, mostrar: a.titulo)
            return
        }
        mensajes.append(Mensaje(quien: .tu, texto: a.titulo, completo: a.titulo, hora: Date()))
        pensando = true
        frase = "Se lo paso a \(a.nombreAsistente)…"
        let e = try? await host.pedir(a: a.asistente, instruccion: a.peticion, tarea: contexto.tarea,
                                      pantalla: contexto.paraMika, accion: a.accion)
        pensando = false
        var m: Mensaje
        if let e {
            let texto = a.asistente == "mika"
                ? "Me pongo con «\(a.titulo)». Te dejo lo que prepare en Decisiones; nada sale sin tu OK."
                : "Se lo he pedido a \(a.nombreAsistente): «\(a.titulo)». Te aviso aquí y en Decisiones cuando lo tenga; nada sale sin tu OK."
            m = Mensaje(quien: .mika, texto: "", completo: texto, modo: modo, hora: Date())
            m.tarjetas = [TarjetaEnlazada(clase: .trabajo, etiqueta: "Trabajo de \(a.nombreAsistente)", titulo: a.titulo,
                                          ruta: contexto.tarea, espera: nil, ejecucion: e.id)]
        } else {
            let perfil = PerfilDeAsistente.deSerie.first { $0.slug == a.asistente }
            let porque = asistentes?.encendidos == false ? "los asistentes están en pausa"
                : (perfil.map { $0.activacion.explicacion.prefix(1).lowercased() + $0.activacion.explicacion.dropFirst() } ?? "no está activo")
            m = Mensaje(quien: .mika, texto: "", completo: "\(a.nombreAsistente) no puede ponerse ahora: \(porque)", modo: modo, hora: Date())
        }
        mensajes.append(m)
        revelar(m.id)
    }

    /// El canal de esta empresa: el que conecta la integración (Claude Code o la demo) o el del enrutador.
    func canalActual() -> any CanalDeMika {
        if let c = canalDePrueba { return c }
        let version = asistentes?.versionDelChat
        if let c = canal {
            if versionDelCanal == version { return c }
            // F4 · corrector (P2): la integración conectó (o quitó) Claude Code después: el chat de antes se cierra.
            Task { await c.cerrar() }
            canal = nil
            modoRespondido = nil
        }
        let c = asistentes?.fabricaDeChat?() ?? Self.canalSinClaude(sesion)
        canal = c
        versionDelCanal = version
        return c
    }

    /// Sin Claude Code: `SesionDeChat` sin proceso (contesta el enrutador con los datos de la carpeta).
    static func canalSinClaude(_ sesion: VaultSession?) -> any CanalDeMika {
        let raiz = sesion?.root ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let estado = sesion?.directorioEstado ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let layout = sesion?.estructura
        let excluidas = (sesion?.entry.exclusionesCopia ?? []).map { VaultPath($0) }
        let ajustes: any FuenteDeAjustes = sesion.flatMap { AsistentesDeLaEmpresa.de($0).autorizador }
            .map { AjustesDeGobierno(autorizador: $0) } ?? AjustesDeLaCarpeta(root: raiz)
        let zona = TimeZone(identifier: "Europe/Madrid") ?? .current
        let reloj: any RelojDelMotor = sesion?.hoyCarpeta.map { RelojDeDemo(hoy: $0, zona: zona) } ?? RelojDelSistema()
        let config = SesionDeChat.Configuracion(
            agente: "mika", estadoDeCarpeta: estado, raiz: raiz, claude: nil, ajustes: ajustes,
            catalogo: CatalogoAsistentesTLS.soloPerfiles, reloj: reloj,
            foto: { VaultSnapshot.read(root: raiz, layout: layout, excluded: excluidas) },
            empresa: sesion?.entry.nombre)
        return SesionDeChat(config)
    }

    /// Lo que dejó Mika en este turno (de la auditoría).
    func tarjetas(ejecucion: String, desde: Date) async -> [TarjetaEnlazada] {
        guard let sesion, let a = asistentes?.autorizador else { return [] }
        let apuntes = await Task.detached(priority: .utility) { (try? a.estado.auditoria()) ?? [] }.value
        // Lo recién creado puede no estar aún en el índice: el título, de la propia ficha.
        let raiz = sesion.root
        return TarjetasEnlazadas.de(apuntes, ejecucion: ejecucion, desde: desde,
                                    titulo: { p in
                                        sesion.resumen(de: p)?.title
                                            ?? raiz.flatMap { try? String(contentsOf: p.url(in: $0), encoding: .utf8) }
                                                .flatMap(DetalleDecision.tituloDeTexto)
                                            ?? p.stem
                                    },
                                    privado: { sesion.esPrivado($0) })
    }

    /// `hoy`, `tareas`, `area:VEN`, `ruta:<…>` → a dónde lleva «Ver».
    func destino(_ ir: String?) -> Destino? {
        guard let ir else { return nil }
        switch ir {
        case "hoy": return .hoy
        case "tareas": return .tareas
        case "decisiones": return .decisiones
        default:
            if ir.hasPrefix("area:"), let a = ConfigAgentes.area(String(ir.dropFirst(5))) { return .area(a) }
            if ir.hasPrefix("ruta:") {
                let p = VaultPath(String(ir.dropFirst(5)))
                guard let sesion, !sesion.esPrivado(p) else { return nil }
                return sesion.destino(para: p)
            }
            return nil
        }
    }

    // MARK: Escribir poco a poco

    /// La respuesta aparece palabra a palabra (como si la escribiera); con «Reducir movimiento», de golpe.
    func revelar(_ id: UUID) {
        guard let ritmo else {
            if let i = mensajes.firstIndex(where: { $0.id == id }) { mensajes[i].texto = mensajes[i].completo }
            return
        }
        revelando?.cancel()
        revelando = Task { [weak self] in
            while let self, !Task.isCancelled, let i = self.mensajes.firstIndex(where: { $0.id == id }), self.mensajes[i].escribiendo {
                let m = self.mensajes[i]
                let resto = m.completo.dropFirst(m.texto.count)
                // Hasta el siguiente espacio (palabra a palabra), de 3 en 3 palabras.
                var n = 0, palabras = 0
                for c in resto {
                    n += 1
                    if c == " " || c == "\n" { palabras += 1; if palabras == 3 { break } }
                }
                self.mensajes[i].texto = String(m.completo.prefix(m.texto.count + max(1, n)))
                try? await Task.sleep(for: ritmo)
            }
        }
    }

    /// Termina de escribir todo lo que estaba a medias (al cerrar el panel o al pulsar).
    func completar() {
        revelando?.cancel()
        for i in mensajes.indices where mensajes[i].escribiendo { mensajes[i].texto = mensajes[i].completo }
    }

    // MARK: Propuestas del enrutador (las aplica la persona)

    /// Aplica la propuesta de una respuesta (crear una tarea, cambiar su día planificado) como la persona, con Deshacer.
    @discardableResult
    func aplicar(_ id: UUID) async -> Bool {
        guard let sesion, let i = mensajes.firstIndex(where: { $0.id == id }), let p = mensajes[i].propuesta,
              mensajes[i].propuestaHecha == nil else { return false }
        if let m = Decidir.motivoSoloLectura(sesion) {
            sesion.aviso = Aviso("Solo lectura: \(m).", estado: .atencion)
            return false
        }
        switch p.accion {
        case .crearTarea(let titulo, let planificada):
            guard let ruta = try? await NuevaTareaHoja.crear(titulo: titulo, area: contexto.area, proyecto: nil, responsable: sesion.persona,
                                                             planificada: planificada, sesion: sesion, deshacer: sesion.undoManagerActivo)
            else { return false }
            mensajes[i].propuestaHecha = "Hecho: tarea creada para el \(FormatoBase.fechaConDia(planificada))."
            mensajes[i].tarjetas.append(TarjetaEnlazada(clase: .tarea, etiqueta: "Tarea creada", titulo: titulo, ruta: ruta, espera: nil))
        case .moverPlanificada(let tarea, let dia):
            let comando = CommandBus.Comando.cambiarPropiedades(tarea, poner: [Property(key: "planificada", value: .text(dia.description))], quitar: [])
            let aviso = "Planificada el \(FormatoBase.fechaConDia(dia))"
            do {
                if DominioEmpresa.motor(de: sesion) != nil {
                    try await sesion.escribirConDominio(comando, aviso: aviso, deshacer: sesion.undoManagerActivo)
                } else {
                    try await sesion.escribir(comando, aviso: aviso, deshacer: sesion.undoManagerActivo)
                }
            } catch { return false }
            mensajes[i].propuestaHecha = "Hecho: planificada el \(FormatoBase.fechaConDia(dia))."
            mensajes[i].tarjetas.append(TarjetaEnlazada(clase: .tarea, etiqueta: "Tarea actualizada", titulo: sesion.titulo(de: tarea),
                                                        ruta: tarea, espera: nil))
        }
        return true
    }

    /// Empieza de cero (cierra el chat con Claude si lo había).
    func nuevaConversacion() async {
        completar()
        mensajes = []
        await terminarChat()
    }
}
