import Darwin
import Foundation
import TLSCore

/// Avisos del motor para la persona (tarjeta o notificación; los convierte la interfaz).
public enum AvisoDelMotor: Sendable, Hashable {
    /// Se acabó el tope del mes de un asistente: no se lanza nada suyo hasta el mes que viene o hasta subirlo.
    case mesAgotado(agente: String)
    /// Autopausa de una rutina (≥5 ejecuciones en 7 días y ≥90 % fallos).
    case rutinaPausada(RutinaPausada)
    /// `InitGuard` paró un trabajo: el asistente tenía a mano más de lo permitido.
    case guardia(ejecucion: String, agente: String, motivos: [String])
    /// Claude no tiene la sesión iniciada en este Mac.
    case sinSesion

    /// Texto para la persona, sin jerga.
    public var texto: String {
        switch self {
        case .mesAgotado(let a): "\(a.capitalized) ha llegado a su tope de uso del mes. No trabajará hasta el mes que viene o hasta que lo subas."
        case .rutinaPausada(let r): "He pausado la rutina «\(r.rutina)»: falla casi siempre. Revísala y reanúdala cuando esté arreglada."
        case .guardia(_, let a, _): "He parado un trabajo de \(a.capitalized) por seguridad: tenía a mano más de lo permitido."
        case .sinSesion: "Claude no tiene la sesión iniciada en este Mac: los asistentes esperan."
        }
    }
}

/// Antes de lanzar: ¿hace falta el asistente? («¿Algo rojo?»: solo si hay rojo).
public enum Precomprobacion: Sendable {
    /// Lanza, con estos datos de más para el primer mensaje.
    case lanzar([String: String])
    /// No hace falta: la ejecución queda completada con este resumen, sin lanzar nada ni escribir en la carpeta.
    case noHaceFalta(String)
}

/// La cola de trabajos de una carpeta (PLAN §5.3, «Cola»): **una ejecución a la vez por carpeta**, persistente en
/// `estado.sqlite.ejecuciones`.
///
/// - Estados: pendiente → en cola → en curso → esperando respuesta → completada / fallida(motivo) / cancelada.
/// - Reintentos: 2, a 1 y 5 minutos, solo ante límite de uso, red, sobrecarga o salida sin `result` (con límite de
///   uso, además, no antes de que se libere). Nunca ante falta de sesión, presupuesto, guardia, interruptor o
///   cancelación.
/// - Autopausa de una rutina con ≥5 ejecuciones en 7 días y ≥90 % de fallos.
/// - Al arrancar, lo que estaba «en curso» sin proceso vivo pasa a `fallida(.interrumpida)`; lo que quedaba en
///   cola sigue ahí (ni se pierde ni se duplica).
/// - Con el interruptor apagado no sale nada de la cola; con un área en `pausa_areas`, lo suyo espera; un asistente
///   inactivo o de un área preparada o en reposo no se lanza (su trabajo se cancela con el motivo).
public actor ColaDeEjecuciones {
    public struct Entorno: Sendable {
        /// `<ASUP>/<vault-id>` (de ahí cuelgan `agentes/` y `ejecuciones/`).
        public var estadoDeCarpeta: URL
        /// La carpeta de la empresa: el sandbox la niega siempre.
        public var raiz: URL
        public var estado: EstadoDelMotor
        public var runtime: any AgentRuntime
        public var servidor: (any PuertaDeHerramientas)?
        public var registro: (any RegistroDeTrabajo)?
        public var ajustes: any FuenteDeAjustes
        public var catalogo: any CatalogoDeAsistentes
        public var reloj: any RelojDelMotor
        /// Foto de la carpeta (sistemas del área para el brief y estado de las áreas).
        public var foto: (@Sendable () async -> VaultSnapshot)?
        /// Estado de las áreas; sin él, se calcula de `foto`; sin ninguno, todas valen.
        public var estadosDeArea: (@Sendable () async -> [AreaCode: AreaStatus])?
        public var antesDeLanzar: (@Sendable (Ejecucion, AjustesDeAsistente) async -> Precomprobacion)?
        /// La última palabra antes de lanzar (en la app, `Autorizador.permisoDeLanzamiento`). Si no puede, espera.
        public var permisoDeLanzamiento: (@Sendable (String) async -> PermisoDeLanzamiento)?
        public var enVivo: EstadoEnVivo?
        public var alAvisar: (@Sendable (AvisoDelMotor) -> Void)?
        public var empresa: String?
        public var tiempoMaximo: TimeInterval
        /// Esperas antes de cada reintento (PLAN: 1 y 5 minutos).
        public var esperasDeReintento: [TimeInterval]
        /// Días que vive la sesión de un asistente antes de abrir otra (además de cuando cambia el brief).
        public var diasDeSesion: Double

        public init(estadoDeCarpeta: URL, raiz: URL, estado: EstadoDelMotor, runtime: any AgentRuntime,
                    servidor: (any PuertaDeHerramientas)? = nil, registro: (any RegistroDeTrabajo)? = nil,
                    ajustes: any FuenteDeAjustes, catalogo: any CatalogoDeAsistentes, reloj: any RelojDelMotor = RelojDelSistema(),
                    foto: (@Sendable () async -> VaultSnapshot)? = nil,
                    estadosDeArea: (@Sendable () async -> [AreaCode: AreaStatus])? = nil,
                    antesDeLanzar: (@Sendable (Ejecucion, AjustesDeAsistente) async -> Precomprobacion)? = nil,
                    permisoDeLanzamiento: (@Sendable (String) async -> PermisoDeLanzamiento)? = nil,
                    enVivo: EstadoEnVivo? = nil, alAvisar: (@Sendable (AvisoDelMotor) -> Void)? = nil,
                    empresa: String? = nil, tiempoMaximo: TimeInterval = 1200, esperasDeReintento: [TimeInterval] = [60, 300],
                    diasDeSesion: Double = 7) {
            self.estadoDeCarpeta = estadoDeCarpeta; self.raiz = raiz; self.estado = estado; self.runtime = runtime
            self.servidor = servidor; self.registro = registro; self.ajustes = ajustes; self.catalogo = catalogo
            self.reloj = reloj; self.foto = foto; self.estadosDeArea = estadosDeArea; self.antesDeLanzar = antesDeLanzar
            self.permisoDeLanzamiento = permisoDeLanzamiento; self.enVivo = enVivo; self.alAvisar = alAvisar; self.empresa = empresa; self.tiempoMaximo = tiempoMaximo
            self.esperasDeReintento = esperasDeReintento; self.diasDeSesion = diasDeSesion
        }
    }

    public nonisolated let entorno: Entorno
    private var ocupado = false
    private var enCurso: (id: String, tarea: Task<ResultadoDeEjecucion, Never>, credencial: CredencialDeEjecucion?, nota: String?)?
    /// Lo que cuenta el servidor de herramientas durante la ejecución (`tls_preguntar`, `tls_finalizar`).
    private var anotaciones: [String: (pregunta: String?, resumen: String?)] = [:]
    /// Herramientas que usó cada ejecución (para «pendiente de aprobación»).
    private var usadas: [String: [String]] = [:]
    /// La que se está ejecutando (de la preparación al cierre apuntado).
    private var ejecutando: String?
    /// F4 · corrector (R5): se pidió parar la ejecución mientras se preparaba (aún sin proceso): no se lanza.
    private var cancelacionEnPreparacion: String?
    private var detenida = false
    /// Asistentes a los que el gobierno dijo que esperen, hasta cuándo.
    private var denegadoHasta: [String: Date] = [:]

    /// Cambió la configuración: se vuelve a preguntar al gobierno.
    public func olvidarDenegaciones() { denegadoHasta = [:] }

    public init(_ entorno: Entorno) { self.entorno = entorno }

    var estado: EstadoDelMotor { entorno.estado }

    // MARK: Entrar en la cola

    /// Apunta un disparo y crea su ejecución pendiente. `nil` si la clave ya estaba (idempotencia) o si la tarea ya
    /// tiene un trabajo abierto.
    @discardableResult
    public func encolar(_ d: Disparo) async throws -> Ejecucion? {
        if let t = d.tarea, d.tipo != .respuesta, try estado.abierta(tarea: t) != nil {
            return nil
        }
        guard let e = try estado.encolar(d, ahora: entorno.reloj.ahora(), simulado: entorno.runtime.simulado) else { return nil }
        // F4 · integración: la ficha de la tarea dice «En cola» en vivo desde el primer momento (no solo al reintentar).
        await publicarFin(e, fase: .enCola, frase: "En cola")
        return e
    }

    /// Id de la ejecución que está en marcha ahora.
    public var idEnCurso: String? { enCurso?.id }

    // MARK: Procesar

    /// Lanza, uno detrás de otro, todo lo que pueda salir ya de la cola. Vuelve cuando no queda nada lanzable.
    public func procesar() async {
        guard !ocupado, !detenida else { return }
        ocupado = true
        defer { ocupado = false }
        while !Task.isCancelled, !detenida, let s = await siguiente() {
            await ejecutar(s.0, ajustes: s.1)
        }
    }

    /// No saca nada más de la cola (al cerrar la carpeta). Lo que espera se queda para la próxima vez.
    public func detener() { detenida = true }

    /// Vuelve a sacar trabajos de la cola.
    public func reanudar() { detenida = false }

    /// La siguiente lanzable (y cancela de paso lo que ya no se puede lanzar).
    func siguiente() async -> (Ejecucion, AjustesDeAsistente)? {
        let ajustes = await entorno.ajustes.ajustes()
        guard ajustes.interruptor else { return nil }
        guard let espera = try? estado.enEspera(), !espera.isEmpty else { return nil }
        let ahora = entorno.reloj.ahora()
        let areas = await estadosDeArea()
        for var e in espera {
            if let na = e.noAntes, na > ahora { continue }
            guard let a = ajustes.agente(e.agente), a.activo else {
                await cerrar(&e, .cancelada, nota: "El asistente no está activo.")
                continue
            }
            if let area = a.areaPropia, let s = areas[area], s == .preparada || s == .reposo {
                await cerrar(&e, .cancelada, nota: s == .reposo ? "Su área está en reposo." : "Su área está preparada, aún no activa.")
                continue
            }
            if let area = a.areaPropia, ajustes.pausaAreas.contains(area) { continue }
            if let permiso = entorno.permisoDeLanzamiento {
                if let hasta = denegadoHasta[e.agente], hasta > ahora { continue }
                if case .espera(let motivo) = await permiso(e.agente) {
                    // No se vuelve a preguntar (ni a apuntar en la auditoría) hasta dentro de 5 minutos o un cambio.
                    denegadoHasta[e.agente] = ahora.addingTimeInterval(300)
                    if e.nota != motivo { e.nota = motivo; try? estado.guardar(e) }
                    continue
                }
            }
            if e.estado == .pendiente {
                e.estado = .enCola
                try? estado.guardar(e)
            }
            return (e, a)
        }
        return nil
    }

    func estadosDeArea() async -> [AreaCode: AreaStatus] {
        if let f = entorno.estadosDeArea { return await f() }
        guard let foto = entorno.foto else { return [:] }
        return LecturaDeAreas.de(await foto())
    }

    /// Cuándo hay que volver a mirar (el reintento más cercano).
    public func proximaRevision() -> Date? { try? estado.proximoNoAntes() }

    // MARK: Una ejecución

    func ejecutar(_ entrada: Ejecucion, ajustes a: AjustesDeAsistente) async {
        ejecutando = entrada.id
        cancelacionEnPreparacion = nil
        defer { ejecutando = nil; cancelacionEnPreparacion = nil }
        var e = entrada
        let reloj = entorno.reloj
        let ajustesTodos = await entorno.ajustes.ajustes()
        let zona = ajustesTodos.zona
        let simulado = entorno.runtime.simulado
        let rol = entorno.catalogo.rol(e.agente)
        let ledger = CostLedger(estado: estado, reloj: reloj, zona: zona)

        // ¿Hace falta? («¿Algo rojo?»: si no hay rojo, no se lanza nada.)
        var extra: [String: String] = [:]
        if let pre = entorno.antesDeLanzar {
            switch await pre(e, a) {
            case .noHaceFalta(let resumen):
                e.resumen = resumen
                e.registrada = true
                await cerrar(&e, .completada, nota: "Sin lanzar: no hacía falta.", registrar: false)
                await publicarFin(e, fase: .terminado, frase: resumen)
                return
            case .lanzar(let datos): extra = datos
            }
        }

        // Tope de uso: con el mes agotado no se lanza (ni se reintenta) y salta un aviso.
        var tope: Double
        if simulado {
            tope = a.presupuestoEjecucionUSD
        } else if let t = ledger.topeDeEjecucion(a) {
            tope = t
        } else {
            await cerrar(&e, .fallida, motivo: .presupuesto, nota: "Se alcanzó el tope de uso del mes.")
            entorno.alAvisar?(.mesAgotado(agente: e.agente))
            return
        }
        // F4 · corrector (R6): el tope del trabajo es para todos sus intentos, no para cada uno: un reintento solo tiene lo
        // que no gastaron los anteriores.
        if !simulado {
            tope = min(tope, max(0, a.presupuestoEjecucionUSD - e.costeUSD))
            guard tope >= CostLedger.minimoParaLanzarUSD else {
                await cerrar(&e, .fallida, motivo: .presupuesto, nota: "Se gastó el tope de este trabajo en los intentos anteriores.")
                return
            }
        }

        // Brief (estable) y sesión.
        let snapshot = await entorno.foto?()
        let sistemas = (a.areaPropia ?? rol?.area).flatMap { area in snapshot.map { BriefBuilder.sistemas(de: area, en: $0) } } ?? []
        let brief = BriefBuilder(empresa: entorno.empresa).construir(rol: rol, ajustes: a, sistemas: sistemas)
        let paths: AgentPaths
        let briefURL: URL
        do {
            paths = try AgentPaths(vaultState: entorno.estadoDeCarpeta, slug: e.agente, runID: e.id)
            try paths.create()
            briefURL = try brief.escribir(en: paths.agentDirectory)
        } catch {
            await cerrar(&e, .fallida, motivo: .error, nota: "No se pudo preparar el trabajo: \(error)")
            return
        }
        var resumenPrevio: String?
        let (sesion, id) = decidirSesion(&e, ajustes: a, brief: brief, resumenPrevio: &resumenPrevio)
        e.sesion = id
        e.briefHash = brief.huella

        // F4 · corrector (R5): antes de abrir el acceso a la carpeta, se vuelve a mirar si se puede lanzar.
        if await noLanzar(&e) { return }

        let profundidad = e.tarea.flatMap { (try? estado.valor("delegacion:\($0.raw)")).flatMap { Int($0) } } ?? 0
        let origen: String? = switch e.disparo.tipo {
        case .respuesta: "pregunta:" + (e.disparo.datos["pregunta"].flatMap { $0.isEmpty ? nil : $0 } ?? e.disparo.responde ?? e.id)
        case .chat: "chat:" + e.id
        default: nil
        }
        let contexto = ContextoDeEjecucion(
            ejecucion: e.id, agente: e.agente, tarea: e.tarea, disparo: e.disparo.tipo, coordinador: a.coordinador,
            areas: a.areas, leeAreas: a.leeAreas, maxTareasPorEjecucion: a.maxTareasPorEjecucion, profundidad: profundidad,
            origen: origen, simulado: simulado)
        var credencial: CredencialDeEjecucion?
        if let servidor = entorno.servidor {
            do { credencial = try await servidor.abrir(contexto) } catch {
                await cerrar(&e, .fallida, motivo: .error, nota: "No se pudo abrir el acceso a la carpeta: \(error)")
                return
            }
        }

        let ahora = reloj.ahora()
        let mensaje = PrimerMensaje.construir(e, rol: rol, ajustes: a, ahora: ahora, zona: zona, simulado: simulado,
                                              extra: extra, resumenPrevio: resumenPrevio)
        let peticion = PeticionDeEjecucion(
            contexto: contexto, paths: paths, sesion: sesion, brief: briefURL, modelo: a.modelo, esfuerzo: a.esfuerzo,
            maxBudgetUSD: tope, mensaje: mensaje, credencial: credencial, carpetasNegadas: [entorno.raiz],
            grabaciones: Self.grabaciones(e), variables: variables(e, ahora: ahora, zona: zona), timeout: entorno.tiempoMaximo)

        e.estado = .enCurso
        e.empezada = ahora
        try? estado.guardar(e)
        await publicarInicio(e)
        // F4 · corrector (R5): lo último antes de lanzar, sin esperas entre medias: si se canceló o se cerró la carpeta
        // mientras se preparaba, el token se revoca y no sale ningún proceso.
        if let nota = cancelacionEnPreparacion ?? (detenida ? Self.notaCarpetaCerrada : nil) {
            if let credencial, let servidor = entorno.servidor { await servidor.revocar(credencial) }
            await noLanzado(&e, cancelar: cancelacionEnPreparacion != nil, nota: nota)
            return
        }

        let enVivo = entorno.enVivo
        let runID = e.id
        let almacen = estado
        let runtime = entorno.runtime
        let tarea = Task<ResultadoDeEjecucion, Never> {
            await runtime.ejecutar(peticion, alEvento: { ev in
                guard let enVivo, let f = EstadoEnVivo.frase(para: ev) else { return }
                Task { @MainActor in enVivo.frase(runID, f) }
            }, alArrancar: { pid in
                guard pid > 1, var guardada = try? almacen.ejecucion(runID) else { return }
                guardada.pid = pid
                try? almacen.guardar(guardada)
                // F4 · corrector (R10): cuándo empezó ese proceso, para no confundirlo después con otro que reutilice
                // el número.
                if let inicio = Self.inicioDeProceso(pid) { try? almacen.poner(Self.clavePID(runID), inicio) }
            })
        }
        enCurso = (e.id, tarea, credencial, nil)
        var r = await tarea.value
        let notaCancelacion = enCurso?.nota
        enCurso = nil
        if let an = anotaciones.removeValue(forKey: e.id) {
            if let p = an.pregunta, !r.preguntas.contains(p) { r.preguntas.append(p) }
            if let res = an.resumen, !res.isEmpty { r.resumen = res; r.finalizo = true }
        }
        usadas[e.id] = r.herramientas
        if let credencial, let servidor = entorno.servidor { await servidor.revocar(credencial) }
        if let leida = try? estado.ejecucion(e.id) { e.pid = leida.pid }
        try? estado.poner(Self.clavePID(e.id), "")
        // F4 · corrector (R6): un intento en el que el modelo llegó a contestar y que no devolvió su uso (sin `result`: se
        // quedó a medias, se agotó el tiempo o se canceló) cuenta su tope entero en el mes y en el trabajo. Es lo
        // prudente: el tope no se puede pasar por intentos que no dicen cuánto gastaron. Uno que no llegó a contestar
        // (sin red, sobrecarga al empezar) no gastó: no cuenta.
        if !r.simulado, r.result == nil, r.costeUSD == 0, r.respondioElModelo { r.costeUSD = tope }
        await terminar(&e, r, ajustes: a, ledger: ledger, notaCancelacion: notaCancelacion)
    }

    static let notaCarpetaCerrada = "Se cerró la carpeta antes de empezar: queda en la cola."

    /// F4 · corrector (R5): justo antes de abrir el acceso a la carpeta. `true` si no se lanza (y ya quedó apuntado):
    /// se canceló o se cerró la carpeta mientras se preparaba, se apagaron los asistentes, el asistente ya no está
    /// activo o su área se pausó.
    func noLanzar(_ e: inout Ejecucion) async -> Bool {
        if let nota = cancelacionEnPreparacion {
            await noLanzado(&e, cancelar: true, nota: nota)
            return true
        }
        if detenida {
            await noLanzado(&e, cancelar: false, nota: Self.notaCarpetaCerrada)
            return true
        }
        let ajustes = await entorno.ajustes.ajustes()
        if let nota = cancelacionEnPreparacion {
            await noLanzado(&e, cancelar: true, nota: nota)
            return true
        }
        guard ajustes.interruptor else {
            await noLanzado(&e, cancelar: false, nota: "Los asistentes están en pausa: queda en la cola.")
            return true
        }
        guard let a = ajustes.agente(e.agente), a.activo else {
            await noLanzado(&e, cancelar: true, nota: "El asistente no está activo.")
            return true
        }
        if let area = a.areaPropia, ajustes.pausaAreas.contains(area) {
            await noLanzado(&e, cancelar: false, nota: "Su área está en pausa: queda en la cola.")
            return true
        }
        return false
    }

    /// No se lanzó: cancelada (con su nota) o de vuelta a la cola, como estaba (ni se pierde ni se duplica).
    func noLanzado(_ e: inout Ejecucion, cancelar: Bool, nota: String) async {
        if cancelar {
            await cerrar(&e, .cancelada, nota: nota)
            return
        }
        e.estado = .pendiente
        e.empezada = nil
        e.nota = nota
        try? estado.guardar(e)
        await publicarFin(e, fase: .enCola, frase: "En cola")
    }

    /// Sesión de esta ejecución (PLAN §5.3): reintento → la misma (reanudada si ya existe); respuesta → la de la
    /// pregunta; si no, la del asistente mientras no cambie la huella del brief ni pase de `diasDeSesion`.
    func decidirSesion(_ e: inout Ejecucion, ajustes a: AjustesDeAsistente, brief: Brief,
                       resumenPrevio: inout String?) -> (ClaudeSession, UUID) {
        if let s = e.sesion {
            if e.nota == Self.notaSesionNueva { resumenPrevio = resumenDeLaPregunta(e) }
            return (e.sesionIniciada ? .resume(s) : .new(s), s)
        }
        if e.disparo.tipo == .respuesta, let origen = e.disparo.responde, let o = try? estado.ejecucion(origen),
           let s = o.sesion, o.sesionIniciada {
            e.sesionIniciada = true
            return (.resume(s), s)
        }
        if let guardada = try? estado.sesion(agente: e.agente), guardada.briefHash == brief.huella,
           entorno.reloj.ahora().timeIntervalSince(guardada.creada) < entorno.diasDeSesion * 86_400 {
            e.sesionIniciada = true
            return (.resume(guardada.sesion), guardada.sesion)
        }
        let nueva = UUID()
        return (.new(nueva), nueva)
    }

    static let notaSesionNueva = "Sesión nueva: la anterior no se pudo recuperar."

    func resumenDeLaPregunta(_ e: Ejecucion) -> String? {
        guard let origen = e.disparo.responde, let o = try? estado.ejecucion(origen) else { return nil }
        var t = o.resumen ?? ""
        if let p = o.pregunta { t += (t.isEmpty ? "" : " ") + "Dejaste la pregunta \(p)." }
        return t.isEmpty ? nil : t
    }

    func terminar(_ e: inout Ejecucion, _ r: ResultadoDeEjecucion, ajustes a: AjustesDeAsistente, ledger: CostLedger,
                  notaCancelacion: String?) async {
        let ahora = entorno.reloj.ahora()
        e.costeUSD += r.costeUSD
        if e.costeUSD > 0 { try? ledger.apuntar(ejecucion: e.id, agente: e.agente, usd: e.costeUSD, simulado: r.simulado) }
        if r.sesionIniciada {
            e.sesionIniciada = true
            if let s = e.sesion, let h = e.briefHash, e.disparo.tipo != .respuesta {
                let previa = try? estado.sesion(agente: e.agente)
                if previa?.sesion != s { try? estado.guardarSesion(agente: e.agente, sesion: s, briefHash: h, creada: ahora) }
            }
        }
        if let resumen = r.resumen, !resumen.isEmpty { e.resumen = resumen }

        // `--resume` rechazado: una vez, sesión nueva con el resumen de lo anterior (sin contar como reintento).
        if r.reanudacionRechazada, e.nota != Self.notaSesionNueva {
            try? estado.olvidarSesion(agente: e.agente)
            e.sesion = UUID()
            e.sesionIniciada = false
            e.nota = Self.notaSesionNueva
            e.estado = .enCola
            e.noAntes = nil
            try? estado.guardar(e)
            await publicarFin(e, fase: .enCola, frase: "En cola")
            return
        }

        switch r.estado {
        case .completada where !r.preguntas.isEmpty:
            e.pregunta = r.preguntas.last
            await cerrar(&e, .esperandoRespuesta)
        case .completada:
            await cerrar(&e, .completada)
        case .fallida(let motivo):
            if case .bloqueado(let motivos)? = r.veredicto {
                entorno.alAvisar?(.guardia(ejecucion: e.id, agente: e.agente, motivos: motivos.map(\.description)))
            }
            if motivo == .sinSesion { entorno.alAvisar?(.sinSesion) }
            // F4 · corrector (R6): sin tope del trabajo para otro intento, no se reintenta.
            let quedaDelTrabajo = r.simulado || a.presupuestoEjecucionUSD - e.costeUSD >= CostLedger.minimoParaLanzarUSD
            if motivo.retriable, e.intento < entorno.esperasDeReintento.count, quedaDelTrabajo {
                var espera = ahora.addingTimeInterval(entorno.esperasDeReintento[e.intento])
                if motivo == .limiteUso, let hasta = r.limiteHasta, hasta > espera { espera = hasta }
                e.intento += 1
                e.motivo = motivo
                e.noAntes = espera
                e.estado = .pendiente
                e.pid = nil
                try? estado.guardar(e)
                await publicarFin(e, fase: .enCola, frase: "Lo reintentaré en un rato")
                return
            }
            await cerrar(&e, .fallida, motivo: motivo, nota: r.avisos.first)
        case .cancelada:
            await cerrar(&e, .cancelada, nota: notaCancelacion)
        default:
            await cerrar(&e, .fallida, motivo: .error)
        }
    }

    /// Deja la ejecución en un estado final (o esperando respuesta), la apunta en la carpeta y revisa la autopausa.
    func cerrar(_ e: inout Ejecucion, _ nuevo: EstadoDeEjecucion, motivo: FailureReason? = nil, nota: String? = nil,
                registrar: Bool = true) async {
        let ahora = entorno.reloj.ahora()
        e.estado = nuevo
        if nuevo != .fallida { e.motivo = nil } else { e.motivo = motivo ?? e.motivo ?? .error }
        if let nota { e.nota = nota }
        if nuevo.esFinal { e.terminada = ahora; e.noAntes = nil }
        try? estado.guardar(e)
        if registrar && !e.registrada, let registro = entorno.registro {
            let cierre = CierreDeTrabajo(
                ejecucion: e.id, agente: e.agente, nombre: entorno.catalogo.rol(e.agente)?.nombre ?? e.agente.capitalized,
                tarea: e.tarea, estado: nuevo, motivo: e.motivo, nota: e.nota, resumen: e.resumen, costeUSD: e.costeUSD,
                simulado: e.simulado, origen: e.disparo.origen, pregunta: e.pregunta, intento: e.intento,
                pidioAprobacion: usadas[e.id]?.contains("tls_solicitar_accion") ?? false, fecha: ahora)
            do {
                try await registro.registrar(cierre)
                e.registrada = true
                try? estado.guardar(e)
            } catch {
                // Queda sin apuntar: se reintenta al arrancar (`recuperar`).
            }
        }
        if nuevo.esFinal || nuevo == .esperandoRespuesta { usadas[e.id] = nil }
        if nuevo.esFinal, let r = e.disparo.rutina { autopausa(rutina: "\(e.agente).\(r)", agente: e.agente) }
        let fase: TrabajoEnVivo.Fase = switch nuevo {
        case .esperandoRespuesta: .esperandoRespuesta
        case .fallida: .fallido
        case .cancelada: .cancelado
        default: .terminado
        }
        let frase: String = switch nuevo {
        case .esperandoRespuesta: "Esperando tu respuesta"
        case .fallida: (e.motivo ?? .error).explanation
        case .cancelada: "Cancelado"
        default: e.resumen.map { String($0.prefix(160)) } ?? "Terminado"
        }
        await publicarFin(e, fase: fase, frase: frase)
    }

    /// ≥5 ejecuciones en 7 días y ≥90 % fallos → la rutina se pausa (hasta que la persona la reanude).
    func autopausa(rutina: String, agente: String) {
        let ahora = entorno.reloj.ahora()
        guard let lista = try? estado.ejecuciones(rutina: rutina, desde: ahora.addingTimeInterval(-7 * 86_400)) else { return }
        let finales = lista.filter { $0.estado == .completada || $0.estado == .fallida }
        guard finales.count >= 5 else { return }
        let fallos = finales.filter { $0.estado == .fallida }.count
        guard Double(fallos) / Double(finales.count) >= 0.9, (try? estado.estaPausada(rutina: rutina)) == false else { return }
        let motivo = "\(fallos) de \(finales.count) ejecuciones fallaron en 7 días"
        try? estado.pausar(rutina: rutina, agente: agente, motivo: motivo, desde: ahora)
        entorno.alAvisar?(.rutinaPausada(RutinaPausada(rutina: rutina, agente: agente, desde: ahora, motivo: motivo)))
    }

    // MARK: Lo que avisa el servidor de herramientas

    /// `tls_preguntar` (desde el servidor): al terminar, la ejecución queda «esperando respuesta» a esta pregunta.
    public func anotarPregunta(ejecucion: String, pregunta: String) {
        var a = anotaciones[ejecucion] ?? (nil, nil)
        a.pregunta = pregunta
        anotaciones[ejecucion] = a
    }

    /// `tls_finalizar` (desde el servidor): el resumen del cierre.
    public func anotarFin(ejecucion: String, resumen: String) {
        var a = anotaciones[ejecucion] ?? (nil, nil)
        a.resumen = resumen
        anotaciones[ejecucion] = a
    }

    // MARK: Cancelar, responder, recuperar

    /// Cancela una ejecución: si está en marcha, revoca su token **al momento** y para el proceso (SIGTERM al grupo
    /// y SIGKILL a los 5 s); si espera, sale de la cola.
    public func cancelar(_ id: String, nota: String? = nil) async {
        if let c = enCurso, c.id == id {
            enCurso?.nota = nota
            if let cred = c.credencial, let servidor = entorno.servidor { await servidor.revocar(cred) }
            c.tarea.cancel()
            return
        }
        // F4 · corrector (R5): la que se está preparando (aún sin proceso) no se lanzará.
        if ejecutando == id {
            cancelacionEnPreparacion = nota ?? "Cancelado."
            return
        }
        guard var e = try? estado.ejecucion(id), e.estado.abierta, e.estado != .enCurso else { return }
        await cerrar(&e, .cancelada, nota: nota)
    }

    /// Para lo que esté en marcha (interruptor apagado, carpeta cerrada…). Lo de la cola se queda.
    public func cancelarEnCurso(nota: String) async {
        if let id = enCurso?.id {
            await cancelar(id, nota: nota)
        } else if ejecutando != nil {
            // F4 · corrector (R5): también la que se está preparando (el «¿hace falta?», la foto, el brief, el token).
            cancelacionEnPreparacion = nota
        }
    }

    /// Espera a que termine lo que está en marcha (tras cancelar), con su cierre apuntado.
    public func esperarEnCurso(maximo: TimeInterval = 15) async {
        if let t = enCurso?.tarea { _ = await t.value }
        let limite = Date().addingTimeInterval(maximo)
        while ejecutando != nil, Date() < limite { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    /// La persona contesta a la pregunta que dejó una ejecución: la original queda completada y se encola la
    /// respuesta, que reanuda la misma sesión (`--resume`). Devuelve la ejecución nueva.
    @discardableResult
    public func responder(ejecucion id: String, texto: String, autor: String = "Manu") async throws -> Ejecucion? {
        guard var original = try estado.ejecucion(id), original.estado == .esperandoRespuesta else { return nil }
        let d = Disparo.respuesta(a: original.id, agente: original.agente, tarea: original.tarea,
                                  pregunta: original.pregunta, texto: texto, autor: autor)
        let nueva = try estado.encolar(d, ahora: entorno.reloj.ahora(), simulado: entorno.runtime.simulado)
        original.estado = .completada
        original.nota = "Contestada."
        original.terminada = entorno.reloj.ahora()
        try estado.guardar(original)
        await MainActor.run { [enVivo = entorno.enVivo] in enVivo?.quitar(id) }
        return nueva
    }

    /// Al abrir la carpeta: lo «en curso» sin proceso vivo pasa a `fallida(.interrumpida)` (si quedó un proceso
    /// huérfano de esta app, se para); lo terminado sin apuntar se apunta. La cola se queda como estaba.
    public func recuperar() async {
        for var e in (try? estado.ejecuciones(estados: [.enCurso])) ?? [] {
            // F4 · corrector (R10): solo si es el mismo proceso que empezó ese trabajo (no otro con el número reutilizado).
            if let pid = e.pid, pid > 1, Self.esNuestro(pid),
               let inicio = try? estado.valor(Self.clavePID(e.id)), !inicio.isEmpty, Self.inicioDeProceso(pid) == inicio {
                Self.parar(grupo: pid)
            }
            try? estado.poner(Self.clavePID(e.id), "")
            e.pid = nil
            await cerrar(&e, .fallida, motivo: .interrumpida, nota: "Se interrumpió al cerrar la app.")
        }
        for var e in (try? estado.sinRegistrar()) ?? [] {
            await cerrar(&e, e.estado, motivo: e.motivo)
        }
    }

    /// `true` si el proceso es `sandbox-exec` o Claude (un pid viejo puede ser ya de otro programa).
    static func esNuestro(_ pid: Int32) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let ruta = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return ruta.hasSuffix("/sandbox-exec") || ruta.hasSuffix("/claude") || ruta.contains("/claude/")
    }

    static func clavePID(_ run: String) -> String { "pid-inicio:" + run }

    /// Cuándo empezó un proceso (`proc_pidinfo`), como texto exacto; `nil` si ya no existe.
    static func inicioDeProceso(_ pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard n == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        return "\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
    }

    static func parar(grupo pid: Int32) {
        _ = Darwin.kill(-pid, SIGTERM)
        let limite = Date().addingTimeInterval(5)
        while ProcessRunner.groupAlive(pid) && Date() < limite { usleep(50_000) }
        if ProcessRunner.groupAlive(pid) { _ = Darwin.kill(-pid, SIGKILL) }
    }

    // MARK: En vivo

    func publicarInicio(_ e: Ejecucion) async {
        guard let enVivo = entorno.enVivo else { return }
        let t = TrabajoEnVivo(ejecucion: e.id, agente: e.agente, tarea: e.tarea, fase: .trabajando, frase: "Empezando…",
                              desde: e.empezada ?? entorno.reloj.ahora(), simulado: e.simulado)
        await MainActor.run { enVivo.poner(t) }
    }

    func publicarFin(_ e: Ejecucion, fase: TrabajoEnVivo.Fase, frase: String) async {
        guard let enVivo = entorno.enVivo else { return }
        let id = e.id
        let t = TrabajoEnVivo(ejecucion: e.id, agente: e.agente, tarea: e.tarea, fase: fase, frase: frase,
                              desde: entorno.reloj.ahora(), simulado: e.simulado)
        await MainActor.run {
            if fase == .enCola { enVivo.poner(t) } else {
                if enVivo.trabajos[id] == nil { enVivo.poner(t) }
                enVivo.terminar(id, fase: fase, frase: frase)
            }
        }
    }

    // MARK: Grabaciones y variables (simulación)

    /// De la más concreta a la más general.
    static func grabaciones(_ e: Ejecucion) -> [String] {
        let s = e.agente
        let d = e.disparo
        switch d.tipo {
        case .rutina: return ["\(s)-\(d.rutina ?? "rutina")", "\(s)-rutina", s]
        case .evento:
            let ev = (d.datos["evento"] ?? "evento").replacingOccurrences(of: ".", with: "-")
            return ["\(s)-\(ev)", "\(s)-evento", s]
        case .tarea: return ["\(s)-tarea", s]
        case .mencion: return ["\(s)-mencion", "\(s)-tarea", s]
        case .despertar: return ["\(s)-despertar", "\(s)-tarea", s]
        case .accion:
            let id = (d.datos["accion"] ?? "").replacingOccurrences(of: ".", with: "-")
            return (id.isEmpty ? [] : ["\(s)-\(id)"]) + ["\(s)-accion", s]
        case .chat: return ["\(s)-chat", s]
        case .respuesta: return ["\(s)-respuesta", s]
        }
    }

    func variables(_ e: Ejecucion, ahora: Date, zona: TimeZone) -> [String: String] {
        let hoy = LocalDate(date: ahora, timeZone: zona)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let h = cal.dateComponents([.hour, .minute], from: ahora)
        var v: [String: String] = [
            "agente": e.agente, "ejecucion": e.id, "hoy": hoy.description,
            "ahora": "\(hoy) " + String(format: "%02d:%02d", h.hour ?? 0, h.minute ?? 0),
            "manana": hoy.adding(days: 1, timeZone: zona).description,
        ]
        if let t = e.tarea { v["tarea"] = t.raw; v["tarea_titulo"] = e.disparo.datos["titulo"] ?? t.stem }
        if let id = e.disparo.datos["tarea_id"] { v["tarea_id"] = id } else if let t = e.tarea { v["tarea_id"] = t.raw }
        for (k, x) in e.disparo.datos where v[k] == nil { v[k] = x }
        return v
    }
}

/// Estado de cada área según su `Área.md` (lo mismo que leen las métricas).
public enum LecturaDeAreas {
    public static func de(_ snapshot: VaultSnapshot) -> [AreaCode: AreaStatus] {
        var estados: [AreaCode: AreaStatus] = [:]
        let resolver = snapshot.resolver
        for code in AreaCode.allCases {
            let folder = snapshot.layout.areaFolder(code)
            if let real = snapshot.existing(folder.appending(AreaReader.fileName)), let t = snapshot.text(real) {
                estados[code] = AreaReader.parse(markdown: t, code: code, folder: folder,
                                                 resolve: { resolver.resolve($0, from: real) }).estado
            } else {
                estados[code] = .desconocido
            }
        }
        return estados
    }
}
