import Foundation
import TLSCore

/// ⌘J: hablar con Mika con el contexto de la pantalla (PLAN §5.3 «Chat», §6.1).
///
/// - **Con Claude**: un proceso vivo (lanzado igual que un trabajo: sandbox, solo `mcp__tls`, `InitGuard`, entorno
///   mínimo) con la entrada abierta; cada mensaje es un turno. Tras 10 minutos sin mensajes se cierra la entrada, el
///   proceso termina y se revoca su token. El contexto de la pantalla va en el primer mensaje.
/// - **Sin Claude** (no está instalado, sin sesión, interruptor apagado, tope del mes agotado o si falla): el
///   enrutador determinista de 14 intenciones (`RespuestasSinClaude`). Nunca escribe: propone.
public actor SesionDeChat {
    public struct Configuracion: Sendable {
        public var agente: String
        public var estadoDeCarpeta: URL
        public var raiz: URL
        /// `nil` = sin Claude (enrutador).
        public var claude: ClaudeCodeRuntime?
        /// Demo (Ribera): sin Claude, cada mensaje reproduce la grabación de chat que mejor encaja (marca «Simulado»).
        public var simulacion: SimulatedRuntime?
        public var puerta: (any PuertaDeHerramientas)?
        public var ajustes: any FuenteDeAjustes
        public var catalogo: any CatalogoDeAsistentes
        public var reloj: any RelojDelMotor
        public var foto: @Sendable () async -> VaultSnapshot
        /// Para el uso del mes (sin él, el chat no gasta tope).
        public var estado: EstadoDelMotor?
        public var inactividad: TimeInterval
        public var tiempoPorTurno: TimeInterval
        public var empresa: String?

        public init(agente: String = "mika", estadoDeCarpeta: URL, raiz: URL, claude: ClaudeCodeRuntime?,
                    puerta: (any PuertaDeHerramientas)? = nil, ajustes: any FuenteDeAjustes, catalogo: any CatalogoDeAsistentes,
                    reloj: any RelojDelMotor = RelojDelSistema(), foto: @escaping @Sendable () async -> VaultSnapshot,
                    estado: EstadoDelMotor? = nil, inactividad: TimeInterval = 600, tiempoPorTurno: TimeInterval = 300,
                    empresa: String? = nil, simulacion: SimulatedRuntime? = nil) {
            self.agente = agente; self.estadoDeCarpeta = estadoDeCarpeta; self.raiz = raiz; self.claude = claude
            self.simulacion = simulacion
            self.puerta = puerta; self.ajustes = ajustes; self.catalogo = catalogo; self.reloj = reloj; self.foto = foto
            self.estado = estado; self.inactividad = inactividad; self.tiempoPorTurno = tiempoPorTurno; self.empresa = empresa
        }
    }

    public nonisolated let configuracion: Configuracion
    public nonisolated let id: String
    private var proceso: Task<ProcessOutput?, Never>?
    private var entrada: EntradaViva?
    private var canal: CanalDeTurnos?
    private var credencial: CredencialDeEjecucion?
    private var turnos = 0
    private var ultimoMensaje = Date.distantPast
    private var vigilante: Task<Void, Never>?
    /// Hay un turno esperando respuesta: no se cierra por inactividad.
    private var enTurno = false
    /// La ejecución del chat en `estado.sqlite` (si hay estado).
    private var registro: Ejecucion?
    /// USD de este chat (lo que dice el CLI, acumulado).
    private var costeTotal = 0.0

    public init(_ c: Configuracion) {
        configuracion = c
        id = "chat-" + AgentPaths.newRunID()
    }

    /// `true` mientras el proceso de Claude sigue vivo.
    public var vivo: Bool { proceso != nil && !(entrada?.estaCerrada ?? true) }

    /// Manda un mensaje y espera la respuesta (con Claude) o responde al momento (sin Claude).
    public func enviar(_ texto: String, pantalla: String? = nil) async -> RespuestaDeChat {
        ultimoMensaje = Date()
        let ajustes = await configuracion.ajustes.ajustes()
        if configuracion.claude == nil, let sim = configuracion.simulacion, ajustes.interruptor,
           ajustes.agente(configuracion.agente)?.activo == true, let r = await simulado(texto, pantalla: pantalla, sim, ajustes) {
            return r
        }
        if let motivo = await motivoSinClaude(ajustes) {
            var r = await sinClaude(texto, ajustes: ajustes)
            if !motivo.isEmpty, r.intencion == nil { r.texto = motivo + " " + r.texto }
            return r
        }
        do {
            if !vivo { try await lanzar(ajustes) }
            guard let entrada, let canal else { return await sinClaude(texto, ajustes: ajustes) }
            var mensaje = texto
            if turnos == 0 {
                mensaje = "Manu te escribe desde el chat de la app (⌘J)."
                if let pantalla, !pantalla.isEmpty { mensaje += "\nLo que tiene en pantalla: \(pantalla)" }
                mensaje += "\n\nSu mensaje:\n\(texto)"
            }
            turnos += 1
            let espera = canal.nuevoTurno()
            enTurno = true
            vigilante?.cancel()
            guard entrada.escribir(try RunFiles.userMessage(mensaje)) else {
                enTurno = false
                await cerrar()
                return await sinClaude(texto, ajustes: ajustes)
            }
            let r = await espera.esperar(segundos: configuracion.tiempoPorTurno)
            enTurno = false
            // La inactividad cuenta desde que terminó el último turno.
            ultimoMensaje = Date()
            vigilar()
            costeTotal = canal.costeTotal
            apuntarUso(costeTotal, ajustes: ajustes)
            guard let r, !r.isEmpty else {
                await cerrar()
                return await sinClaude(texto, ajustes: ajustes)
            }
            return RespuestaDeChat(texto: r, modo: .claude)
        } catch {
            await cerrar()
            return await sinClaude(texto, ajustes: ajustes)
        }
    }

    /// Cierra el proceso (si lo hay) y revoca su token.
    public func cerrar() async {
        vigilante?.cancel()
        vigilante = nil
        entrada?.cerrar()
        if let p = proceso {
            // Sin entrada, el proceso termina solo; si no, se para el grupo.
            let parar = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); p.cancel() }
            _ = await p.value
            parar.cancel()
        }
        proceso = nil
        entrada = nil
        canal = nil
        if let c = credencial { await configuracion.puerta?.revocar(c) }
        credencial = nil
        if var r = registro, let estado = configuracion.estado {
            r.estado = .completada
            r.terminada = configuracion.reloj.ahora()
            r.costeUSD = costeTotal
            r.resumen = "Chat con Manu: \(turnos) \(turnos == 1 ? "mensaje" : "mensajes")."
            try? estado.guardar(r)
        }
        registro = nil
        costeTotal = 0
        turnos = 0
    }

    // MARK: Sin Claude

    func motivoSinClaude(_ ajustes: AjustesDeAsistentes) async -> String? {
        guard configuracion.claude != nil else { return "" }
        guard ajustes.interruptor else { return "Los asistentes están en pausa: te contesto con lo que sé mirar." }
        guard let a = ajustes.agente(configuracion.agente), a.activo else { return "" }
        if let estado = configuracion.estado,
           CostLedger(estado: estado, reloj: configuracion.reloj, zona: ajustes.zona).topeDeEjecucion(a) == nil {
            return "\(configuracion.catalogo.rol(a.slug)?.nombre ?? "Mika") ha llegado a su tope de uso del mes: te contesto con lo que sé mirar."
        }
        return nil
    }

    func sinClaude(_ texto: String, ajustes: AjustesDeAsistentes) async -> RespuestaDeChat {
        let ahora = configuracion.reloj.ahora()
        let reloj = Reloj(hoy: LocalDate(date: ahora, timeZone: ajustes.zona), ahora: ahora, zona: ajustes.zona)
        return RespuestasSinClaude(snapshot: await configuracion.foto(), reloj: reloj).responder(texto)
    }

    // MARK: Simulado (demo)

    func simulado(_ texto: String, pantalla: String?, _ sim: SimulatedRuntime, _ ajustes: AjustesDeAsistentes) async -> RespuestaDeChat? {
        guard let a = ajustes.agente(configuracion.agente) else { return nil }
        turnos += 1
        let runID = "\(id)-\(turnos)"
        guard let paths = try? AgentPaths(vaultState: configuracion.estadoDeCarpeta, slug: a.slug, runID: runID) else { return nil }
        let contexto = ContextoDeEjecucion(ejecucion: runID, agente: a.slug, disparo: .chat, coordinador: a.coordinador,
                                           areas: a.areas, leeAreas: a.leeAreas, maxTareasPorEjecucion: a.maxTareasPorEjecucion,
                                           origen: "chat:\(runID)", simulado: true)
        let credencial = try? await configuracion.puerta?.abrir(contexto)
        let ahora = configuracion.reloj.ahora()
        let hoy = LocalDate(date: ahora, timeZone: ajustes.zona)
        let peticion = PeticionDeEjecucion(
            contexto: contexto, paths: paths, sesion: .new(UUID()), maxBudgetUSD: a.presupuestoEjecucionUSD, mensaje: texto,
            credencial: credencial, carpetasNegadas: [configuracion.raiz],
            grabaciones: GrabacionesDeEjemplo.nombres(agente: a.slug, disparo: .chat, texto: texto),
            variables: ["agente": a.slug, "ejecucion": runID, "hoy": hoy.description, "mensaje": texto, "pantalla": pantalla ?? ""])
        let r = await sim.ejecutar(peticion, alEvento: { _ in }, alArrancar: { _ in })
        if let c = credencial { await configuracion.puerta?.revocar(c) }
        guard r.estado == .completada, let t = r.resumen, !t.isEmpty else { return nil }
        return RespuestaDeChat(texto: t, modo: .claude, simulado: true)
    }

    // MARK: Con Claude

    func lanzar(_ ajustes: AjustesDeAsistentes) async throws {
        guard let runtime = configuracion.claude, let a = ajustes.agente(configuracion.agente) else { throw CancellationError() }
        let rol = configuracion.catalogo.rol(a.slug)
        let snapshot = await configuracion.foto()
        let sistemas = (a.areaPropia ?? rol?.area).map { BriefBuilder.sistemas(de: $0, en: snapshot) } ?? []
        let brief = BriefBuilder(empresa: configuracion.empresa).construir(rol: rol, ajustes: a, sistemas: sistemas)
        let paths = try AgentPaths(vaultState: configuracion.estadoDeCarpeta, slug: a.slug, runID: id)
        try paths.create()
        let briefURL = try brief.escribir(en: paths.agentDirectory)
        let contexto = ContextoDeEjecucion(ejecucion: id, agente: a.slug, disparo: .chat, coordinador: a.coordinador,
                                           areas: a.areas, leeAreas: a.leeAreas, maxTareasPorEjecucion: a.maxTareasPorEjecucion,
                                           origen: "chat:\(id)")
        if let puerta = configuracion.puerta { credencial = try await puerta.abrir(contexto) }
        // El chat no pasa por la cola, pero queda en la historia del asistente (y su uso, en el mes).
        let disparo = Disparo(clave: "chat:\(id)", tipo: .chat, agente: a.slug, instruccion: "Chat con Manu (⌘J).")
        registro = try? configuracion.estado?.apuntarFueraDeCola(disparo, id: id, estado: .enCurso,
                                                                  ahora: configuracion.reloj.ahora())
        var tope = a.presupuestoEjecucionUSD
        if let estado = configuracion.estado {
            tope = CostLedger(estado: estado, reloj: configuracion.reloj, zona: ajustes.zona).topeDeEjecucion(a) ?? 0
        }
        let peticion = PeticionDeEjecucion(
            contexto: contexto, paths: paths, sesion: .new(UUID()), brief: briefURL, modelo: a.modelo, esfuerzo: a.esfuerzo,
            maxBudgetUSD: tope, mensaje: "", credencial: credencial, carpetasNegadas: [configuracion.raiz])
        let orden = try runtime.preparar(peticion)
        let entrada = EntradaViva()
        let canal = CanalDeTurnos(guardia: runtime.initGuard, stream: paths.stream)
        self.entrada = entrada
        self.canal = canal
        let spec = ProcessSpec(
            executable: orden.ejecutable, arguments: orden.argumentos,
            environment: AgentEnvironment.minimal(home: runtime.home, tmp: paths.tmp),
            directory: paths.agentDirectory.path, timeout: 6 * 3600, grace: runtime.gracia, entradaViva: entrada)
        proceso = Task {
            let out = try? await ProcessRunner.run(spec) { canal.linea($0) }
            canal.terminado()
            return out
        }
    }

    /// Tras `inactividad` sin mensajes, cierra la entrada: el proceso acaba y se revoca el token.
    func vigilar() {
        vigilante?.cancel()
        let espera = configuracion.inactividad
        vigilante = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(espera * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.cerrarSiInactivo()
        }
    }

    func cerrarSiInactivo() async {
        guard !enTurno, Date().timeIntervalSince(ultimoMensaje) >= configuracion.inactividad * 0.9 else { return }
        await cerrar()
    }

    func apuntarUso(_ usd: Double, ajustes: AjustesDeAsistentes) {
        guard usd > 0, let estado = configuracion.estado else { return }
        try? CostLedger(estado: estado, reloj: configuracion.reloj, zona: ajustes.zona)
            .apuntar(ejecucion: id, agente: configuracion.agente, usd: usd, simulado: false)
    }
}

/// Turnos de un chat vivo: junta el texto de cada respuesta hasta su `result` (en el hilo lector).
final class CanalDeTurnos: @unchecked Sendable {
    private let lock = NSLock()
    private let guardia: InitGuard
    private let stream: FileHandle?
    private var actual: Turno?
    private var vistoInit = false
    private var ultimoCoste = 0.0
    private var base = 0.0
    private var cerrado = false

    init(guardia: InitGuard, stream: URL) {
        self.guardia = guardia
        FileManager.default.createFile(atPath: stream.path, contents: nil, attributes: [.posixPermissions: 0o600])
        self.stream = try? FileHandle(forWritingTo: stream)
    }

    final class Turno: @unchecked Sendable {
        private let lock = NSLock()
        private var texto: [String] = []
        private var fin: String?
        private var terminado = false
        private var continuacion: CheckedContinuation<String?, Never>?

        func anadir(_ t: String) { lock.withLock { texto.append(t) } }

        func terminar(_ resultado: String?) {
            let c = lock.withLock { () -> CheckedContinuation<String?, Never>? in
                guard !terminado else { return nil }
                terminado = true
                fin = resultado ?? (texto.isEmpty ? nil : texto.joined(separator: "\n\n"))
                defer { continuacion = nil }
                return continuacion
            }
            c?.resume(returning: lock.withLock { fin })
        }

        func esperar(segundos: TimeInterval) async -> String? {
            let limite = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
                self?.terminar(nil)
            }
            defer { limite.cancel() }
            return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
                let listo = lock.withLock { () -> Bool in
                    if terminado { return true }
                    continuacion = c
                    return false
                }
                if listo { c.resume(returning: lock.withLock { fin }) }
            }
        }
    }

    func nuevoTurno() -> Turno {
        lock.withLock {
            let t = Turno()
            actual = t
            if cerrado { t.terminar(nil) }
            return t
        }
    }

    var costeTotal: Double { lock.withLock { base + ultimoCoste } }

    func linea(_ data: Data) -> LineDecision {
        lock.withLock { try? stream?.write(contentsOf: data + Data([0x0A])) }
        for e in StreamJSONParser.events(fromLine: data) {
            switch e {
            case .inicio(let info):
                let permitido = lock.withLock { () -> Bool in
                    vistoInit = true
                    return guardia.evaluate(info).isAllowed
                }
                if !permitido { terminado(); return .terminar }
            case .texto(let t):
                lock.withLock { actual }?.anadir(t)
            case .resultado(let r):
                let turno = lock.withLock { () -> Turno? in
                    if let c = r.totalCostUSD {
                        if c < ultimoCoste { base += ultimoCoste }
                        ultimoCoste = c
                    }
                    return actual
                }
                turno?.terminar(r.isError ? nil : r.text)
            default:
                break
            }
        }
        return .seguir
    }

    /// El proceso terminó: el turno pendiente (si lo hay) acaba sin respuesta.
    func terminado() {
        let t = lock.withLock { () -> Turno? in
            cerrado = true
            try? stream?.close()
            return actual
        }
        t?.terminar(nil)
    }
}
