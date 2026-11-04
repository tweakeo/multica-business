import Foundation
import MCP
import TLSAgents
import TLSCore
import TLSMCPShared

/// Error de una herramienta (texto para el asistente).
struct ErrorDeHerramienta: Error, Sendable {
    let mensaje: String
    init(_ m: String) { mensaje = m }
}

/// Las herramientas de `tls-mcp` en la app (PLAN §5.4): traduce cada llamada a lecturas por `AgentView` o a planes
/// de escritura con `Autor.agente(slug)` que pasan por el `Autorizador` y por el `CommandBus` (o por el motor del
/// dominio, que también usa el `CommandBus`).
///
/// Dobles cerrojos que no dependen del `Autorizador`: vetos fijos (§5.2 paso 5), lo privado «no encontrado»,
/// profundidad de delegación ≤ 2, tope de tareas por ejecución, estados Hecha/Cancelada y `vence` imposibles, y
/// `tls_solicitar_accion` que **nunca** ejecuta.
public final class ServidorDeHerramientas: ManejadorIPC, @unchecked Sendable {
    public struct Dependencias: Sendable {
        public var vista: AgentView
        /// `nil` = la empresa está en solo lectura: nada se escribe.
        public var bus: CommandBus?
        /// Motor del dominio (eventos y reglas) para lo que toca fichas del dominio y `Decisiones.md`.
        public var motor: MotorDeDominio?
        public var autorizador: any AutorizadorDeHerramientas
        /// Acciones de dominio por el gobierno (`DominioDelGobierno`); `nil` = las resuelve este servidor.
        public var dominio: (any EscrituraDeDominio)?
        public var servicios: any ServiciosDeEjecucion
        public var aprobaciones: any SolicitudesDeAprobacion
        public var propuestas: any AlmacenDePropuestas
        public var auditoria: any RegistroDeAuditoria
        /// Foto de la carpeta **con la estructura que incluye lo privado de los ajustes** (para filtrarlo).
        public var foto: @Sendable () async -> VaultSnapshot
        public var reloj: @Sendable (VaultSnapshot) -> Reloj
        /// Las seis áreas (de `Área.md`).
        public var areas: @Sendable () -> [AreaSummary]
        /// La persona de la carpeta (responsable de preguntas y propuestas).
        public var persona: String
        /// F5 · calendario: lo ocupado de los **otros** calendarios entre dos días (incluidos), solo bloques «Ocupado»
        /// sin títulos ni asistentes (`SincronizadorCalendario.fuenteDeOcupado`). `nil` = Calendario sin conectar.
        public var ocupado: (@Sendable (LocalDate, LocalDate) async -> [EventoAgenda])? = nil
        /// F5 · pasarela: las herramientas de otros programas (`ext_<servidor>_<herramienta>`) y quién puede usarlas.
        /// `nil` = ninguna conexión: no se ve ninguna `ext_*`.
        public var externas: ExposicionExterna? = nil
        /// F5 · mail: el correo que recoge la app (fuera de la carpeta) para el Cartero. `nil` = Mail sin conectar.
        public var correo: (any FuenteDeCorreo)? = nil

        public init(vista: AgentView, bus: CommandBus?, motor: MotorDeDominio? = nil,
                    autorizador: any AutorizadorDeHerramientas, dominio: (any EscrituraDeDominio)? = nil,
                    servicios: any ServiciosDeEjecucion = ServiciosEnMemoria(),
                    aprobaciones: any SolicitudesDeAprobacion = AprobacionesEnMemoria(),
                    propuestas: any AlmacenDePropuestas = PropuestasEnMemoria(),
                    auditoria: any RegistroDeAuditoria = AuditoriaEnMemoria(),
                    foto: @escaping @Sendable () async -> VaultSnapshot,
                    reloj: @escaping @Sendable (VaultSnapshot) -> Reloj = { Reloj.deCarpeta($0) },
                    areas: @escaping @Sendable () -> [AreaSummary] = { [] }, persona: String = "Manu") {
            self.vista = vista; self.bus = bus; self.motor = motor; self.autorizador = autorizador; self.dominio = dominio
            self.servicios = servicios; self.aprobaciones = aprobaciones; self.propuestas = propuestas
            self.auditoria = auditoria; self.foto = foto; self.reloj = reloj; self.areas = areas; self.persona = persona
        }

        /// Las de una empresa abierta: su vista, su foto (con lo privado de los ajustes para poder filtrarlo) y sus áreas.
        public static func de(service: VaultService, bus: CommandBus?, motor: MotorDeDominio? = nil,
                              autorizador: any AutorizadorDeHerramientas, dominio: (any EscrituraDeDominio)? = nil,
                              servicios: any ServiciosDeEjecucion,
                              aprobaciones: any SolicitudesDeAprobacion, propuestas: any AlmacenDePropuestas,
                              auditoria: any RegistroDeAuditoria, persona: String = "Manu") -> Dependencias {
            let excluidas = (service.entry.exclusionesCopia.map { VaultPath($0) } + service.options.excluidas).filter { !$0.isRoot }
            return Dependencias(
                vista: AgentView(service: service), bus: bus, motor: motor, autorizador: autorizador, dominio: dominio,
                servicios: servicios,
                aprobaciones: aprobaciones, propuestas: propuestas, auditoria: auditoria,
                foto: { VaultSnapshot.read(root: service.root, layout: service.layout, excluded: excluidas) },
                areas: { service.areas() }, persona: persona)
        }
    }

    let d: Dependencias
    private let lock = NSLock()
    /// Tareas creadas por ejecución (tope `max_tareas_por_ejecucion`).
    private var tareasCreadas: [String: Int] = [:]
    /// Operación del contador de tareas quitada de cada plan (se escribe después, como sistema).
    private var contadores: [UUID: WriteOp] = [:]

    public init(_ dependencias: Dependencias) {
        self.d = dependencias
    }

    // MARK: ManejadorIPC

    public func herramientas(para contexto: ContextoDelAsistente) async -> [ToolSpec] {
        CatalogoTLS.definiciones.filter { $0.visible(contexto) }.map(\.spec) + (await externas(para: contexto))
    }

    public func llamar(_ nombre: String, argumentos: [String: Value], contexto c: ContextoDelAsistente) async -> ToolResult {
        // F5 · pasarela: las de otros programas, con sus propios cerrojos (permiso, lectura como dato, sensible → OK).
        if nombre.hasPrefix("ext_") { return await llamarExterna(nombre, argumentos: argumentos, contexto: c) }
        guard let def = CatalogoTLS.definicion(nombre), def.visible(c) else {
            auditar(c, "herramienta:\(nombre)", veredicto: "denegado", motivo: "herramienta no disponible para este asistente")
            return Respuesta.error("Esa herramienta no está disponible para ti.")
        }
        do {
            let a = try Argumentos(argumentos, permitidas: def.claves)
            switch nombre {
            case "tls_estado": return try await estado(a, c)
            case "tls_buscar": return try await buscar(a, c)
            case "tls_leer": return try await leer(a, c)
            case "tls_listar": return try await listar(a, c)
            case "tls_leer_sistema": return try await leerSistema(a, c)
            case "tls_tareas": return try await tareas(a, c)
            case "tls_agenda": return try await agenda(a, c)
            case "tls_diagnostico": return try await diagnostico(a, c)
            case "tls_expediente": return try await expediente(a, c)
            case "tls_bitacora": return try await bitacora(a, c)
            case "tls_correo_pendiente": return try await correoPendiente(a, c)
            case "tls_anotar_correo": return try await anotarCorreo(a, c)
            case "tls_movimientos": return try await movimientos(a, c)
            case "tls_crear_tarea": return try await crearTarea(a, c)
            case "tls_actualizar_tarea": return try await actualizarTarea(a, c)
            case "tls_comentar": return try await comentar(a, c)
            case "tls_preparar_borrador": return try await prepararBorrador(a, c)
            case "tls_mover_archivo": return try await moverArchivo(a, c)
            case "tls_proponer_conciliacion": return try await proponerConciliacion(a, c)
            case "tls_avisar": return try await avisar(a, c)
            case "tls_programar_seguimiento": return try await programarSeguimiento(a, c)
            case "tls_delegar": return try await delegar(a, c)
            case "tls_finalizar": return try await finalizar(a, c)
            case "tls_registrar_contacto": return try await registrarContacto(a, c)
            case "tls_registrar_oportunidad": return try await registrarOportunidad(a, c)
            case "tls_registrar_metricas_contenido": return try await registrarMetricas(a, c)
            case "tls_registrar_cobro_externo": return try await registrarCobroExterno(a, c)
            case "tls_preguntar": return try await preguntar(a, c)
            case "tls_proponer": return try await proponer(a, c)
            case "tls_registrar_decision": return try await registrarDecision(a, c)
            case "tls_solicitar_accion": return await solicitarAccion(argumentos, c)
            default: return Respuesta.error("Esa herramienta no está disponible para ti.")
            }
        } catch let e as ErrorDeArgumentos {
            return Respuesta.error(e.mensaje)
        } catch let e as ErrorDeHerramienta {
            return Respuesta.error(e.mensaje)
        } catch let e as Denegacion {
            return e.resultado
        } catch let e as LocalizedError {
            return Respuesta.error(e.errorDescription ?? "No se pudo hacer.")
        } catch {
            return Respuesta.error("No se pudo hacer: \(error)")
        }
    }

    // MARK: Autorizar y escribir

    /// Una acción no autorizada, ya con su respuesta para el asistente.
    struct Denegacion: Error {
        let resultado: ToolResult
    }

    /// Vetos fijos, lo privado y después el `Autorizador`. Lo que no es `permitido` queda auditado.
    func autorizar(_ c: ContextoDelAsistente, _ accion: String, _ clase: ClaseDeAccion, rutas: [VaultPath] = [],
                   area: AreaCode? = nil, profundidad: Int? = nil, plan: WritePlan? = nil, origen: String? = nil) async -> VeredictoDeAccion {
        let p = peticion(c, accion, clase, rutas: rutas, area: area, profundidad: profundidad, plan: plan, origen: origen)
        // Cerrojos propios (vetos fijos y lo privado u oculto) y el Autorizador, al que se pregunta siempre (así su
        // auditoría lo apunta todo); lo propio gana.
        let propio: VeredictoDeAccion? = VetosFijos.comprobar(p)
            ?? (rutas.contains { d.vista.motivoOculto($0) != nil } ? .noEncontrado : nil)
        let delAutorizador = await d.autorizador.autorizar(p)
        let veredicto = propio ?? delAutorizador
        if veredicto != .permitido {
            auditar(c, accion, ruta: rutas.first?.raw, veredicto: Self.etiqueta(veredicto), motivo: Self.motivo(veredicto))
        }
        return veredicto
    }

    func peticion(_ c: ContextoDelAsistente, _ accion: String, _ clase: ClaseDeAccion, rutas: [VaultPath] = [],
                  area: AreaCode? = nil, profundidad: Int? = nil, plan: WritePlan? = nil, origen: String? = nil) -> PeticionDeAccion {
        PeticionDeAccion(autor: c.autor, ejecucion: c.ejecucion, accion: accion, clase: clase, rutas: rutas, area: area,
                         profundidad: profundidad, plan: plan, origen: origen, profundidadDeLaEjecucion: c.profundidad)
    }

    /// Exige `permitido` (suelo y decisiones): lo demás se convierte en respuesta.
    func exigir(_ v: VeredictoDeAccion) throws {
        switch v {
        case .permitido: return
        case .denegado(let m): throw Denegacion(resultado: Respuesta.error(m))
        case .noEncontrado: throw Denegacion(resultado: Respuesta.noEncontrado)
        case .requiereAprobacion:
            throw Denegacion(resultado: Respuesta.error("Esto necesita la aprobación de \(d.persona): pídela con tls_solicitar_accion."))
        case .tareaParaPersona, .propuesta:
            throw Denegacion(resultado: Respuesta.error("Esto lo decide \(d.persona): proponlo con tls_proponer."))
        }
    }

    /// Plan de un asistente listo para autorizar y escribir: sin el contador de `.tls/secuencias.json` (un asistente
    /// nunca escribe `.tls/`; la numeración ya cuenta las fichas que hay). Se autoriza **este** plan y se escribe tal cual.
    func preparar(_ plan: WritePlan) -> WritePlan {
        var p = plan
        let esContador: (WriteOp) -> Bool = { TextFolding.pathKey($0.path.raw) == TextFolding.pathKey(Secuencias.ruta.raw) }
        p.ops = plan.ops.filter { !esContador($0) }
        if let c = plan.ops.first(where: esContador) { lock.withLock { contadores[p.id] = c } }
        return p
    }

    /// Escribe un plan del asistente ya autorizado (y preparado con `preparar`). Si algo del plan es oculto, privado o
    /// vetado, no se escribe nada.
    func escribir(_ plan: WritePlan, _ c: ContextoDelAsistente, dominio: Bool = false) async throws -> WriteResult {
        guard let bus = d.bus else { throw ErrorDeHerramienta("La carpeta está en solo lectura: no puedo cambiar nada.") }
        let p = plan
        guard !p.ops.isEmpty else { throw ErrorDeHerramienta("No hay nada que escribir.") }
        if p.ops.contains(where: { VetosFijos.rutaVetada($0.path, layout: d.vista.layout) || d.vista.motivoOculto($0.path) != nil }) {
            auditar(c, "escribir", ruta: p.ops.first?.path.raw, veredicto: "denegado", motivo: "ruta vetada o privada en el plan")
            throw ErrorDeHerramienta("Un asistente no puede cambiar ese fichero.")
        }
        // Solo el propio asistente (o la app, para el encabezado de un comentario suelto): nunca una persona.
        guard p.autor == c.autor || p.autor == .sistema else { throw ErrorDeHerramienta("Plan con otro autor.") }
        let r: WriteResult
        if dominio, let motor = d.motor {
            r = try await motor.ejecutar(p).escritura
        } else {
            r = try await bus.ejecutar(p)
        }
        // El contador de `.tls/secuencias.json` lo escribe la app aparte (como sistema), como hace el gobierno.
        if r.hecho, let c = lock.withLock({ contadores.removeValue(forKey: p.id) }) {
            _ = try? await bus.ejecutar(WritePlan(autor: .sistema, descripcion: "Contador de tareas", ops: [c]))
        }
        return r
    }

    func tareasCreadasEn(_ ejecucion: String) -> Int { lock.withLock { tareasCreadas[ejecucion] ?? 0 } }

    func sumarTarea(_ ejecucion: String) {
        lock.withLock { tareasCreadas[ejecucion, default: 0] += 1 }
    }

    /// Tope de tareas por ejecución (PLAN §5.2, paso 9).
    func comprobarTope(_ c: ContextoDelAsistente) throws {
        let n = tareasCreadasEn(c.ejecucion)
        guard n < c.maxTareas else {
            auditar(c, "tarea.crear", veredicto: "denegado", motivo: "tope de \(c.maxTareas) tareas")
            throw ErrorDeHerramienta("Ya has creado \(n) tareas en este trabajo: es tu tope. Cierra con tls_finalizar.")
        }
    }

    func auditar(_ c: ContextoDelAsistente, _ accion: String, ruta: String? = nil, veredicto: String, motivo: String? = nil) {
        d.auditoria.registrar(EventoDeAuditoria(ejecucion: c.ejecucion, asistente: c.asistente, accion: accion, ruta: ruta,
                                                veredicto: veredicto, motivo: motivo))
    }

    static func etiqueta(_ v: VeredictoDeAccion) -> String {
        switch v {
        case .permitido: "permitido"
        case .denegado: "denegado"
        case .noEncontrado: "no_encontrado"
        case .requiereAprobacion: "aprobacion_requerida"
        case .tareaParaPersona: "tarea_para_persona"
        case .propuesta: "propuesta"
        }
    }

    static func motivo(_ v: VeredictoDeAccion) -> String? {
        if case .denegado(let m) = v { return m }
        return nil
    }

    // MARK: Apoyo de lectura

    /// La foto y su reloj.
    func fotoYReloj() async -> (VaultSnapshot, Reloj) {
        let f = await d.foto()
        return (f, d.reloj(f))
    }

    /// Una tarea por ruta o por número (`T-0042`), visible y en las áreas que puede leer.
    func tarea(_ texto: String, en store: TaskStore, _ c: ContextoDelAsistente, paraEscribir: Bool) throws -> Tarea {
        let alcance = paraEscribir ? c.escritura : c.lectura
        let numero = texto.uppercased().trimmingCharacters(in: .whitespaces)
        if numero.range(of: #"^T-\d{1,6}$"#, options: .regularExpression) != nil {
            let n = Int(numero.dropFirst(2)) ?? -1
            let candidatas = store.tareas.filter { $0.numeroEntero == n && d.vista.esVisible($0.ruta) }
            guard let t = candidatas.first else { throw Denegacion(resultado: Respuesta.noEncontrado) }
            guard d.vista.esVisible(t.ruta, alcance: alcance) else {
                throw ErrorDeHerramienta(paraEscribir ? "Esa tarea no es de tus áreas: coméntalo en tu resumen." : "Esa tarea no es de tus áreas.")
            }
            return t
        }
        switch d.vista.resolver(texto, alcance: alcance) {
        case .ok(let p):
            guard let t = store.tarea(p) else { throw ErrorDeHerramienta("Eso no es una ficha de tarea.") }
            return t
        case .no(.fueraDeAlcance):
            throw ErrorDeHerramienta(paraEscribir ? "Esa tarea no es de tus áreas: coméntalo en tu resumen." : "Esa tarea no es de tus áreas.")
        case .no(let m):
            auditar(c, "tarea", ruta: texto, veredicto: "no_encontrado", motivo: m.rawValue)
            throw Denegacion(resultado: Respuesta.noEncontrado)
        }
    }

    /// Ruta de una ficha a la que se enlaza (proyecto, oportunidad…): visible y legible.
    func ficha(_ texto: String?, _ c: ContextoDelAsistente) throws -> VaultPath? {
        guard let texto else { return nil }
        switch d.vista.resolver(texto, alcance: c.lectura) {
        case .ok(let p) where !p.isRoot: return p
        case .no(.fueraDeAlcance): throw ErrorDeHerramienta("«\(texto)» no es de tus áreas.")
        default:
            throw Denegacion(resultado: Respuesta.error("No encuentro «\(texto)»."))
        }
    }

    /// `Manu` (o la persona) o `agente:<slug>`.
    func responsable(_ texto: String?) throws -> String? {
        guard let t = texto else { return nil }
        if t.hasPrefix("agente:") {
            let slug = String(t.dropFirst("agente:".count)).lowercased()
            guard !slug.isEmpty, slug.count <= 40, slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                throw ErrorDeArgumentos("«responsable» no es válido.")
            }
            return "agente:" + slug
        }
        guard TextFolding.fold(t) == TextFolding.fold(d.persona) || TextFolding.fold(t) == "yo" else {
            throw ErrorDeArgumentos("«responsable» tiene que ser «\(d.persona)» o «agente:<nombre>».")
        }
        return d.persona
    }

    /// Lo que se añade a lo que crea una ejecución simulada (`simulado: true`): así se distingue y se puede retirar.
    func propiedadesDeEjecucion(_ c: ContextoDelAsistente) -> [Property] {
        c.simulado ? [Property(key: "simulado", value: .bool(true))] : []
    }

    static func tareaValue(_ t: Tarea) -> Value {
        .object(["ruta": .string(t.ruta.raw), "numero": .opcional(t.numero), "titulo": .string(t.titulo),
                 "estado": .opcional(t.estadoTexto), "responsable": .opcional(t.responsable), "prioridad": .opcional(t.prioridad),
                 "tipo": .opcional(t.tipo), "planificada": .opcional(t.planificada), "vence": .opcional(t.vence),
                 "area": .opcional(t.area?.nombre)])
    }

    /// `id` del frontmatter de un texto.
    static func idDe(_ texto: String) -> String? {
        NoteDocument(text: texto).frontmatter.properties.first { $0.key == "id" }?.value.displayText.nilSiVacio
    }
}

extension String {
    var nilSiVacio: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
