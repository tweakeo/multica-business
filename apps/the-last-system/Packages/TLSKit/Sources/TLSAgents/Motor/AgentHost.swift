import Foundation
import TLSCore

/// El motor de asistentes de una carpeta abierta (PLAN §5.3): arranca y para la cola, el planificador de rutinas y la
/// puerta del servidor de herramientas (`tls-mcp`); mira la carpeta y el outbox en busca de disparos; respeta el
/// interruptor, `pausa_areas` y las áreas preparadas o en reposo (ningún asistente se lanza ahí).
///
/// Uno por carpeta con escritor. Al cerrar la carpeta (o salir de la app) se llama a `parar()`: cancela lo que esté
/// en marcha (SIGTERM al grupo, SIGKILL a los 5 s, token revocado) y para el servidor, así que no queda ningún
/// `tls-mcp` vivo.
public actor AgentHost {
    public struct Configuracion: Sendable {
        /// La carpeta de la empresa.
        public var raiz: URL
        /// `<ASUP>/<vault-id>` (el `stateDirectory` del escritor): `estado.sqlite`, `agentes/`, `ejecuciones/`.
        public var estadoDeCarpeta: URL
        public var runtime: any AgentRuntime
        public var puerta: (any PuertaDeHerramientas)?
        public var registro: (any RegistroDeTrabajo)?
        public var ajustes: any FuenteDeAjustes
        public var catalogo: any CatalogoDeAsistentes
        public var reloj: any RelojDelMotor
        public var foto: @Sendable () async -> VaultSnapshot
        public var enVivo: EstadoEnVivo?
        public var alAvisar: (@Sendable (AvisoDelMotor) -> Void)?
        public var empresa: String?
        /// Cada cuánto se vuelve a mirar aunque no pase nada (rutinas, despertares, reintentos).
        public var intervalo: TimeInterval
        /// Lee el outbox del dominio (`estado.sqlite`) para los disparos por evento.
        public var leerEventos: Bool
        public var tiempoMaximo: TimeInterval
        public var esperasDeReintento: [TimeInterval]
        /// En la app: `{ autorizador.permisoDeLanzamiento($0) }` (el único Autorizador de la carpeta).
        public var permisoDeLanzamiento: (@Sendable (String) async -> PermisoDeLanzamiento)?
        /// F5 · integración: justo antes de lanzar una ejecución (p. ej., leer el correo antes del triaje del Cartero).
        /// No decide si se lanza: eso sigue en la precomprobación y en el gobierno.
        public var antesDeLanzar: (@Sendable (Ejecucion) async -> Void)?

        public init(raiz: URL, estadoDeCarpeta: URL, runtime: any AgentRuntime, puerta: (any PuertaDeHerramientas)? = nil,
                    registro: (any RegistroDeTrabajo)? = nil, ajustes: any FuenteDeAjustes,
                    catalogo: any CatalogoDeAsistentes, reloj: any RelojDelMotor = RelojDelSistema(),
                    foto: @escaping @Sendable () async -> VaultSnapshot, enVivo: EstadoEnVivo? = nil,
                    alAvisar: (@Sendable (AvisoDelMotor) -> Void)? = nil, empresa: String? = nil, intervalo: TimeInterval = 60,
                    leerEventos: Bool = true, tiempoMaximo: TimeInterval = 1200, esperasDeReintento: [TimeInterval] = [60, 300],
                    permisoDeLanzamiento: (@Sendable (String) async -> PermisoDeLanzamiento)? = nil,
                    antesDeLanzar: (@Sendable (Ejecucion) async -> Void)? = nil) {
            self.raiz = raiz; self.estadoDeCarpeta = estadoDeCarpeta; self.runtime = runtime; self.puerta = puerta
            self.registro = registro; self.ajustes = ajustes; self.catalogo = catalogo; self.reloj = reloj; self.foto = foto
            self.enVivo = enVivo; self.alAvisar = alAvisar; self.empresa = empresa; self.intervalo = intervalo
            self.leerEventos = leerEventos; self.tiempoMaximo = tiempoMaximo; self.esperasDeReintento = esperasDeReintento
            self.permisoDeLanzamiento = permisoDeLanzamiento
            self.antesDeLanzar = antesDeLanzar
        }
    }

    public nonisolated let configuracion: Configuracion
    public nonisolated let estado: EstadoDelMotor
    public nonisolated let cola: ColaDeEjecuciones
    let detector: DetectorDeDisparos
    private var bucle: Task<Void, Never>?
    private let despertador = Despertador()
    private var arrancado = false
    private var ultimoInterruptor: Bool?
    private var dominio: EstadoDominio?

    func abrirDominio() -> EstadoDominio? {
        if let dominio { return dominio }
        dominio = try? EstadoDominio(directory: configuracion.estadoDeCarpeta)
        return dominio
    }

    public init(_ c: Configuracion) throws {
        configuracion = c
        let estado = try EstadoDelMotor(directory: c.estadoDeCarpeta)
        self.estado = estado
        detector = DetectorDeDisparos(catalogo: c.catalogo)
        let reloj = c.reloj
        let foto = c.foto
        let ajustesFuente = c.ajustes
        let catalogo = c.catalogo
        let antes = c.antesDeLanzar
        cola = ColaDeEjecuciones(.init(
            estadoDeCarpeta: c.estadoDeCarpeta, raiz: c.raiz, estado: estado, runtime: c.runtime, servidor: c.puerta,
            registro: c.registro, ajustes: c.ajustes, catalogo: c.catalogo, reloj: c.reloj, foto: c.foto,
            antesDeLanzar: { e, a in
                await antes?(e)
                return await Self.precomprobar(e, ajustes: a, ajustesFuente: ajustesFuente, catalogo: catalogo, reloj: reloj, foto: foto)
            },
            permisoDeLanzamiento: c.permisoDeLanzamiento, enVivo: c.enVivo, alAvisar: c.alAvisar, empresa: c.empresa,
            tiempoMaximo: c.tiempoMaximo, esperasDeReintento: c.esperasDeReintento))
    }

    /// «¿Algo rojo?» y cualquier rutina con `solo_si_rojo`: solo se lanza si hay rojo.
    static func precomprobar(_ e: Ejecucion, ajustes a: AjustesDeAsistente, ajustesFuente: any FuenteDeAjustes,
                             catalogo: any CatalogoDeAsistentes, reloj: any RelojDelMotor,
                             foto: @Sendable () async -> VaultSnapshot) async -> Precomprobacion {
        guard e.disparo.tipo == .rutina, let id = e.disparo.rutina else { return .lanzar([:]) }
        let rutina = a.rutina(id) ?? catalogo.rol(a.slug)?.rutinasDeSerie.first { $0.id == id }
        guard rutina?.soloSiHayRojo == true else { return .lanzar([:]) }
        let zona = await ajustesFuente.ajustes().zona
        let ahora = reloj.ahora()
        let r = Reloj(hoy: LocalDate(date: ahora, timeZone: zona), ahora: ahora, zona: zona)
        return ChequeoPrevio.algoRojo(await foto(), reloj: r, hora: ChequeoPrevio.hora(e.disparo.hueco ?? ahora, zona: zona))
    }

    // MARK: Arrancar y parar

    /// Recupera la cola, arranca el servidor de herramientas y el bucle (rutinas, disparos y cola).
    public func arrancar() async throws {
        guard !arrancado else { return }
        arrancado = true
        await cola.reanudar()
        await cola.recuperar()
        limpiarEjecucionesViejas()
        _ = try await configuracion.puerta?.arrancar()
        ultimoInterruptor = await configuracion.ajustes.ajustes().interruptor
        let despertador = self.despertador
        bucle = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.revisar()
                await self.cola.procesar()
                let espera = await self.segundosHastaLaProximaRevision()
                await despertador.esperar(segundos: espera)
            }
        }
    }

    /// Para todo: cancela lo que esté en marcha (lo de la cola se queda para la próxima vez) y el servidor.
    public func parar() async {
        guard arrancado else { return }
        arrancado = false
        let b = bucle
        b?.cancel()
        await cola.detener()
        await despertador.avisar()
        await cola.cancelarEnCurso(nota: "Se cerró la carpeta.")
        await cola.esperarEnCurso()
        await despertador.avisar()
        _ = await b?.value
        bucle = nil
        await configuracion.puerta?.parar()
    }

    /// Hay algo nuevo (la carpeta cambió, el Mac despertó, cambió la configuración): vuelve a mirar ya.
    public func avisar() async { await despertador.avisar() }

    /// El Mac despertó: se recalculan las rutinas (de las perdidas, la última dentro de su ventana).
    public func despertoElMac() async { await despertador.avisar() }

    /// La carpeta cambió (tareas, comentarios, `Área.md`, `config.yaml`).
    public func carpetaCambio() async {
        await ajustesCambiaron()
        await despertador.avisar()
    }

    /// Cambió la configuración: con el interruptor apagado se para lo que esté en marcha (≤ 5 s) y no sale nada de
    /// la cola; lo de un asistente que ya no puede trabajar, también se para.
    public func ajustesCambiaron() async {
        await cola.olvidarDenegaciones()
        let ajustes = await configuracion.ajustes.ajustes()
        defer { ultimoInterruptor = ajustes.interruptor }
        if !ajustes.interruptor {
            await cola.cancelarEnCurso(nota: "Asistentes en pausa.")
            return
        }
        if let id = await cola.idEnCurso, let e = try? estado.ejecucion(id) {
            let a = ajustes.agente(e.agente)
            let areas = await areasActuales()
            if a == nil || !RoutineScheduler.puedeTrabajar(a!, ajustes: ajustes, areas: areas) {
                await cola.cancelarEnCurso(nota: "El asistente ya no puede trabajar ahí.")
            }
        }
        if ultimoInterruptor == false { await despertador.avisar() }
    }

    func areasActuales() async -> [AreaCode: AreaStatus] { LecturaDeAreas.de(await configuracion.foto()) }

    func segundosHastaLaProximaRevision() async -> TimeInterval {
        let ahora = configuracion.reloj.ahora()
        var limite = configuracion.intervalo
        if let r = await cola.proximaRevision() { limite = min(limite, max(0.5, r.timeIntervalSince(ahora))) }
        let ajustes = await configuracion.ajustes.ajustes()
        if let h = RoutineScheduler(zona: ajustes.zona).proximo(ajustes: ajustes, catalogo: configuracion.catalogo, despues: ahora) {
            limite = min(limite, max(0.5, h.timeIntervalSince(ahora) + 1))
        }
        return limite
    }

    // MARK: Buscar disparos

    /// Una pasada: rutinas que tocan, tareas listas, despertares, menciones, eventos y respuestas escritas en la
    /// ficha de una pregunta. La primera vez que se mira una carpeta, las menciones y los eventos que ya había se
    /// apuntan como vistos (no despiertan a nadie).
    @discardableResult
    public func revisar() async -> [Ejecucion] {
        let ajustes = await configuracion.ajustes.ajustes()
        let ahora = configuracion.reloj.ahora()
        let zona = ajustes.zona
        let snapshot = await configuracion.foto()
        let reloj = Reloj(hoy: LocalDate(date: ahora, timeZone: zona), ahora: ahora, zona: zona)
        let areas = LecturaDeAreas.de(snapshot)
        let primeraVez = (try? estado.valor("primera_pasada")) == nil
        var nuevas: [Ejecucion] = []

        func admisible(_ slug: String) -> Bool {
            guard let a = ajustes.agente(slug), a.activo else { return false }
            if let area = a.areaPropia, let s = areas[area], s == .preparada || s == .reposo { return false }
            return true
        }
        let cola = self.cola
        func meter(_ ds: [Disparo]) async -> [Ejecucion] {
            var out: [Ejecucion] = []
            for d in ds where admisible(d.agente) {
                if let e = try? await cola.encolar(d) { out.append(e) }
            }
            return out
        }

        // Rutinas: solo con el interruptor encendido (son de su hueco; al encenderlo cuenta la última en ventana).
        if ajustes.interruptor {
            let pausadas = Set(((try? estado.rutinasPausadas()) ?? []).map(\.rutina))
            nuevas += await meter(RoutineScheduler(zona: zona).pendientes(ajustes: ajustes, catalogo: configuracion.catalogo,
                                                                ahora: ahora, pausadas: pausadas, areas: areas))
        }
        nuevas += await meter(detector.tareasListas(snapshot, reloj: reloj, ajustes: ajustes))
        nuevas += await meter(detector.despertares(snapshot, reloj: reloj, ajustes: ajustes))

        let menciones = detector.menciones(snapshot, reloj: reloj, ajustes: ajustes)
        if primeraVez { try? estado.apuntarVistos(menciones, ahora: ahora) } else { nuevas += await meter(menciones) }

        // Eventos del outbox: el cursor es la hora del último evento visto (la primera vez, todos los de antes cuentan
        // como vistos).
        if configuracion.leerEventos, let dominio = abrirDominio() {
            let guardados = (try? dominio.eventos()) ?? []
            let previo = (try? estado.valor("eventos_desde")).flatMap { Double($0) }
            if let previo {
                nuevas += await meter(detector.eventos(guardados, desde: Date(timeIntervalSince1970: previo), ajustes: ajustes))
            }
            let maximo = guardados.map(\.creado.timeIntervalSince1970).max() ?? 0
            try? estado.poner("eventos_desde", String(max(previo ?? 0, maximo)))
        }

        // Respuestas escritas en la ficha de la pregunta (Obsidian o la ficha): reanudan al asistente.
        for e in (try? estado.ejecuciones(estados: [.esperandoRespuesta])) ?? [] {
            guard let p = e.pregunta, let r = DetectorDeDisparos.respuesta(en: snapshot, pregunta: p),
                  (try? estado.existeDisparo(r.clave)) == false else { continue }
            try? estado.apuntarVistos([Disparo(clave: r.clave, tipo: .respuesta, agente: e.agente, instruccion: "")], ahora: ahora)
            if let n = try? await cola.responder(ejecucion: e.id, texto: r.texto, autor: r.autor) { nuevas.append(n) }
        }
        if primeraVez { try? estado.poner("primera_pasada", "\(ahora.timeIntervalSince1970)") }
        return nuevas
    }

    // MARK: Peticiones de la persona y del servidor de herramientas

    /// Acción rápida («Pedir a Comercial», «Generar borrador de pieza»). `nil` si el asistente no puede trabajar.
    @discardableResult
    /// `accion`: el id de la acción rápida del perfil (`plan-cuello`…), si viene de un botón.
    public func pedir(a slug: String, instruccion: String, tarea: VaultPath? = nil, pantalla: String? = nil,
                      accion: String? = nil) async throws -> Ejecucion? {
        let ajustes = await configuracion.ajustes.ajustes()
        guard let a = ajustes.agente(slug), a.activo else { return nil }
        if let area = a.areaPropia, let s = (await areasActuales())[area], s == .preparada || s == .reposo { return nil }
        var datos: [String: String] = ["peticion": instruccion]
        if let pantalla { datos["pantalla"] = pantalla }
        if let accion { datos["accion"] = accion }
        let e = try await cola.encolar(Disparo.accion(agente: slug, instruccion: "Manu te pide algo desde la app.", tarea: tarea,
                                                      datos: datos))
        await despertador.avisar()
        return e
    }

    /// La persona contesta a una pregunta (por su ruta o id, o por la ejecución): reanuda la misma sesión.
    @discardableResult
    public func responder(pregunta: String, texto: String, autor: String = "Manu") async throws -> Ejecucion? {
        guard let e = try estado.esperando(pregunta: pregunta) ?? estado.ejecucion(pregunta).flatMap({ $0.estado == .esperandoRespuesta ? $0 : nil })
        else { return nil }
        let n = try await cola.responder(ejecucion: e.id, texto: texto, autor: autor)
        await despertador.avisar()
        return n
    }

    public func cancelar(_ ejecucion: String) async {
        await cola.cancelar(ejecucion, nota: "Cancelado por Manu.")
        await despertador.avisar()
    }

    /// La persona reanuda una rutina en autopausa (`<slug>.<id>`).
    public func reanudarRutina(_ rutina: String) async throws {
        try estado.reanudar(rutina: rutina)
        await despertador.avisar()
    }

    /// `tls_preguntar`: la ejecución quedará esperando respuesta a esta pregunta.
    public func esperarRespuesta(ejecucion: String, pregunta: String) async {
        await cola.anotarPregunta(ejecucion: ejecucion, pregunta: pregunta)
    }

    /// `tls_finalizar`: el resumen del cierre.
    public func finalizar(ejecucion: String, resumen: String) async {
        await cola.anotarFin(ejecucion: ejecucion, resumen: resumen)
    }

    /// `tls_delegar`: el coordinador creó una tarea para otro asistente; su trabajo lleva esa profundidad.
    public func delegar(tarea: VaultPath, profundidad: Int) async {
        try? estado.poner("delegacion:\(tarea.raw)", "\(profundidad)")
        await despertador.avisar()
    }

    /// Las carpetas de ejecución (`ejecuciones/<run>/`: perfil, `mcp.json`, `stream.jsonl`…) de hace más de `dias` días
    /// se quitan (PLAN §3.4: desechables a los 90 días). Es estado de la app, fuera de la carpeta de la empresa.
    @discardableResult
    public nonisolated func limpiarEjecucionesViejas(dias: Int = 90, ahora: Date = Date()) -> Int {
        let dir = configuracion.estadoDeCarpeta.appendingPathComponent("ejecuciones", isDirectory: true)
        let fm = FileManager.default
        guard let hijos = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return 0 }
        let limite = ahora.addingTimeInterval(-Double(dias) * 86_400)
        var quitadas = 0
        for h in hijos {
            guard let fecha = (try? h.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  fecha < limite, AgentPaths.isSafeName(h.lastPathComponent) else { continue }
            if let e = try? estado.ejecucion(h.lastPathComponent), e.estado.abierta { continue }
            if (try? fm.removeItem(at: h)) != nil { quitadas += 1 }
        }
        return quitadas
    }

    // MARK: Lectura para la interfaz

    public func ejecuciones(agente: String? = nil, limite: Int = 100) -> [Ejecucion] {
        (try? estado.ejecuciones(agente: agente, limite: limite)) ?? []
    }

    public func rutinasPausadas() -> [RutinaPausada] { (try? estado.rutinasPausadas()) ?? [] }

    /// «uso del mes: 34 % de tu tope».
    public func uso(_ slug: String) async -> String? {
        let ajustes = await configuracion.ajustes.ajustes()
        guard let a = ajustes.agente(slug) else { return nil }
        return CostLedger(estado: estado, reloj: configuracion.reloj, zona: ajustes.zona)
            .frase(a, simulado: configuracion.runtime.simulado)
    }

    /// Última revisión de una rutina (`<slug>.<id>`): cuándo y qué dijo («Revisé a las 8:45: nada en rojo»).
    public func ultimaRevision(_ rutina: String) -> (fecha: Date, resumen: String?)? {
        guard let e = try? estado.ejecuciones(rutina: rutina, desde: .distantPast).last(where: { $0.estado.esFinal }) else { return nil }
        return (e.terminada ?? e.creada, e.resumen)
    }
}

/// Espera hasta un tiempo o hasta que alguien avise (lo que llegue antes).
actor Despertador {
    private var continuacion: CheckedContinuation<Void, Never>?
    private var pendiente = false
    private var turno = 0

    func esperar(segundos: TimeInterval) async {
        if pendiente { pendiente = false; return }
        turno += 1
        let mio = turno
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuacion = c
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0.05, segundos) * 1_000_000_000))
                await self?.soltar(turno: mio)
            }
        }
    }

    func avisar() {
        if let c = continuacion { continuacion = nil; c.resume() } else { pendiente = true }
    }

    private func soltar(turno t: Int) {
        guard t == turno, let c = continuacion else { return }
        continuacion = nil
        c.resume()
    }
}
