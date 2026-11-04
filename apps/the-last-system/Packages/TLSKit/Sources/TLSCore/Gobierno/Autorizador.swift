import Foundation
import Synchronization

// El Autorizador (PLAN §5.2): uno solo, en TLSCore. Lo usan `CommandBus` (todo plan de `Autor.agente`), `tls-mcp`
// (cada herramienta), la pasarela (F5) y las reglas. Comprueba en este orden y se queda con la primera respuesta:
//
//  1. Sin escritor → solo lectura (la intención queda apuntada en la auditoría).
//  2. `Autor.persona` → permitido.
//  3. Interruptor apagado → se deniega a los asistentes (y no se lanzan).
//  4. `Autor.sistema` → permitido; las acciones externas, nunca.
//  5. Vetadas a los asistentes: config, declarar funciones, fijar metas, decidir aprobaciones, escribir en `.tls/`,
//     `6 · Equipo/Roles/`, `AGENTS.md` o `Empresa.md`, mover `vence`, cerrar tareas (y pasar a Ganada o confirmar
//     cobros y conciliaciones, que son de una persona).
//  6. Asistente activo en la configuración confirmada; su área, sin pausa y ni preparada ni en reposo.
//  7. Alcance: escribe en su área (y en sus tareas, la Bitácora y, si le toca, el Buzón); `lee_areas` solo para leer;
//     el coordinador, todas.
//  8. Lo privado (ruta en NFC, sin `..` ni enlaces), `.tls/` y los ficheros de secretos: «no encontrado».
//  9. Topes: `max_tareas_por_ejecucion`, delegación hasta 2 niveles, tamaño.
// 10. Acción externa → aprobación requerida (en cualquier modo, fijo en el código).
// 11. Suelo (`PermisoBase`) → permitido (salvo función en `off`).
// 12. Modo de la función: off → no; manual → tarea para una persona; asistido → propuesta; supervisado → se hace y va
//     al resumen semanal; autónomo → se hace.
//
// Cada decisión queda en `estado.sqlite.auditoria`.

public final class Autorizador: Sendable {
    public struct Opciones: Sendable {
        /// ¿Hay escritor? (`false` en solo lectura o con la carpeta real).
        public var hayEscritor: @Sendable () -> Bool
        public var ahora: @Sendable () -> Date
        /// Estado de cada área (por defecto, leído de su `Área.md`).
        public var estadoDeArea: (@Sendable (AreaCode) -> AreaStatus)?
        /// Rutas que la carpeta deja fuera de la copia (`exclusionesCopia`): para un asistente, no existen.
        public var excluidas: [VaultPath]
        /// Lo privado de los ajustes de la app (`VaultService.Options.privado`), además del de `.tls/`.
        public var privado: [VaultPath]

        public init(hayEscritor: @escaping @Sendable () -> Bool = { true }, ahora: @escaping @Sendable () -> Date = { Date() },
                    estadoDeArea: (@Sendable (AreaCode) -> AreaStatus)? = nil, excluidas: [VaultPath] = [],
                    privado: [VaultPath] = []) {
            self.hayEscritor = hayEscritor; self.ahora = ahora; self.estadoDeArea = estadoDeArea; self.excluidas = excluidas
            self.privado = privado
        }
    }

    public let root: URL
    public let estado: EstadoGobierno
    public let config: ConfigConfirmada
    let opciones: Opciones
    let realRoot: String
    /// Planes ya decididos (permitidos) que `CommandBus` puede escribir sin volver a preguntar (una vez cada uno).
    private let permisos = Mutex<[UUID: WritePlan]>([:])

    public init(root: URL, estado: EstadoGobierno, opciones: Opciones = Opciones()) {
        self.root = root.standardizedFileURL
        self.estado = estado
        self.config = ConfigConfirmada(root: root, estado: estado)
        self.opciones = opciones
        self.realRoot = PathGuard.realPath(root) ?? root.standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }

    /// Autorizador de una carpeta con su estado (`VaultWriter.stateDirectory`).
    public convenience init(root: URL, stateDirectory: URL, opciones: Opciones = Opciones()) throws {
        self.init(root: root, estado: try EstadoGobierno(directory: stateDirectory), opciones: opciones)
    }

    /// Autorizador del escritor de una carpeta (con sus exclusiones).
    public convenience init(writer: VaultWriter, opciones: Opciones = Opciones()) throws {
        var o = opciones
        o.excluidas = writer.entry.exclusionesCopia.map { VaultPath($0) }
        self.init(root: writer.root, estado: try EstadoGobierno(directory: writer.stateDirectory), opciones: o)
    }

    // MARK: Contexto de una decisión

    struct Contexto {
        let config: ConfigAgentes
        let layout: VaultLayout
        let estadoDeArea: (AreaCode) -> AreaStatus
        let hayEscritor: Bool
    }

    func contexto() -> Contexto {
        let cfg = config.efectiva()
        var layout = UbiquityInspector.withoutMaterializing { VaultLayout.load(root: root, extraPrivado: opciones.privado).layout }
        // Lo privado confirmado también vale (si alguien lo quitó fuera de la app, sigue siendo privado).
        for p in cfg.privado {
            let r = layout.expand(p)
            if !r.isRoot, !layout.privado.contains(where: { TextFolding.pathKey($0.raw) == TextFolding.pathKey(r.raw) }) {
                layout.privado.append(r)
            }
        }
        let capa = layout
        let leer = opciones.estadoDeArea ?? { [root] area in Self.leerEstado(area, root: root, layout: capa) }
        return Contexto(config: cfg, layout: capa, estadoDeArea: leer, hayEscritor: opciones.hayEscritor())
    }

    static func leerEstado(_ area: AreaCode, root: URL, layout: VaultLayout) -> AreaStatus {
        let folder = layout.areaFolder(area)
        let ruta = folder.appending(AreaReader.fileName)
        let texto: String? = UbiquityInspector.withoutMaterializing {
            let url = ruta.url(in: root)
            guard let info = UbiquityInspector.info(url), !info.isDirectory, !info.dataless, !info.isSymlink,
                  let d = try? Data(contentsOf: url, options: [.uncached]) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        guard let texto else { return .desconocido }
        return AreaReader.parse(markdown: texto, code: area, folder: folder, resolve: { _ in nil }).estado
    }

    /// La configuración que se aplica ahora y si hay algo que confirmar.
    public func estadoDeConfig() -> EstadoDeConfig { config.leer(ahora: opciones.ahora()) }

    // MARK: Decidir

    /// Decide una solicitud y la apunta en la auditoría.
    @discardableResult
    public func decidir(_ s: SolicitudAutorizacion) -> DecisionAutorizacion {
        let d = evaluar(s, contexto())
        apuntar(d, rutas: s.rutas)
        return d
    }

    /// Decide un plan entero (todo o nada) y lo apunta una vez. Las operaciones se leen del propio plan; si quien
    /// llama sabe qué es (`tls-mcp` con su herramienta), `solicitud` añade función, origen o acción externa. Si se
    /// permite, `CommandBus` lo escribirá sin volver a preguntar.
    @discardableResult
    public func decidir(plan: WritePlan, solicitud: SolicitudAutorizacion? = nil,
                        ejecucion: ContextoEjecucion? = nil) -> DecisionAutorizacion {
        let ctx = contexto()
        let d = evaluar(plan: plan, solicitud: solicitud, ejecucion: ejecucion ?? solicitud?.ejecucion, ctx)
        apuntar(d, rutas: plan.ops.flatMap { op -> [VaultPath] in
            if case .move(let a, let b) = op { return [a, b] }
            return [op.path]
        })
        // Solo `CommandBus` gasta permisos, y solo de planes de asistente (los de la app no pasan por aquí al escribir).
        if d.permitido, plan.autor.esAgente {
            permisos.withLock { p in
                // Un permiso que nadie gasta no se guarda para siempre.
                if p.count >= 256 { p.removeAll() }
                p[plan.id] = plan
            }
        }
        return d
    }

    /// `true` si este plan (exactamente este) se decidió y se permitió; el permiso se gasta.
    func consumirPermiso(_ plan: WritePlan) -> Bool {
        permisos.withLock { p in
            guard let guardado = p[plan.id], guardado == plan else { return false }
            p[plan.id] = nil
            return true
        }
    }

    /// ¿Puede un asistente leer esta ruta? (`tls_leer`, `tls_listar`…). Lo privado y `.tls/`: «no encontrado».
    @discardableResult
    public func decidirLectura(_ ruta: VaultPath, asistente slug: String, ejecucion: ContextoEjecucion? = nil) -> DecisionAutorizacion {
        decidir(SolicitudAutorizacion(autor: .agente(ConfigAgentes.slug(slug)), tipo: .leer, rutas: [ruta], ejecucion: ejecucion))
    }

    /// Filtro de lectura sin apuntar cada ruta (para listas y búsquedas): lo que un asistente puede ver.
    public func visibles(_ rutas: [VaultPath], asistente slug: String) -> [VaultPath] {
        let ctx = contexto()
        return rutas.filter {
            evaluar(SolicitudAutorizacion(autor: .agente(ConfigAgentes.slug(slug)), tipo: .leer, rutas: [$0]), ctx).permitido
        }
    }

    /// ¿Puede lanzarse este asistente ahora? (interruptor, activo, su área sin pausa y activa). Para la cola.
    public func puedeLanzar(_ slug: String) -> DecisionAutorizacion {
        let s = SolicitudAutorizacion(autor: .agente(ConfigAgentes.slug(slug)), tipo: .finalizar)
        let ctx = contexto()
        let d: DecisionAutorizacion
        if !ctx.config.encendido {
            d = DecisionAutorizacion(resultado: .denegado, paso: 3, motivo: "Los asistentes están apagados.", solicitud: s)
        } else if let r = rol(s, ctx) {
            d = r
        } else {
            d = DecisionAutorizacion(resultado: .permitido, paso: 6, motivo: "Puede trabajar.", solicitud: s)
        }
        apuntar(d, rutas: [])
        return d
    }

    // MARK: Los 12 pasos

    func evaluar(_ s: SolicitudAutorizacion, _ ctx: Contexto) -> DecisionAutorizacion {
        func r(_ res: DecisionAutorizacion.Resultado, _ paso: Int, _ motivo: String, resumen: Bool = false) -> DecisionAutorizacion {
            DecisionAutorizacion(resultado: res, paso: paso, motivo: motivo, alResumenSemanal: resumen, solicitud: s)
        }
        // 1 · Sin escritor.
        if s.tipo.escribe, !ctx.hayEscritor {
            return r(.soloLectura, 1, "Esta carpeta solo se lee: no cambio nada (lo dejo apuntado).")
        }
        // 2 · Persona.
        guard case .agente(let slugCrudo) = s.autor else {
            if s.autor.esPersona { return r(.permitido, 2, "Lo pide una persona.") }
            // 3 no aplica a la app. 4 · Sistema.
            if s.externa != nil || s.tipo == .externa {
                return r(.denegado, 4, "La app nunca hace esto sola: necesita el clic de una persona.")
            }
            return r(.permitido, 4, "Lo hace la app.")
        }
        let slug = ConfigAgentes.slug(slugCrudo)
        // 3 · Interruptor.
        guard ctx.config.encendido else { return r(.denegado, 3, "Los asistentes están apagados.") }
        // 5 · Vetos.
        if let v = veto(s, ctx) { return r(.denegado, 5, v) }
        // 6 · Activo y área.
        if let d = rol(s, ctx) { return d }
        let a = ctx.config.asistente(slug)!
        // 7 · Alcance (y 8 · privado: si además es privado, «no encontrado», nunca «fuera de tu área»).
        for ruta in s.rutas {
            if let nf = privado(ruta, ctx) { return r(.noEncontrado, 8, nf) }
            if let fuera = alcance(ruta, s, a, ctx) { return r(.denegado, 7, fuera) }
        }
        // 9 · Topes.
        if let t = topes(s, a) { return r(.denegado, 9, t) }
        let capacidad = s.capacidadEfectiva
        let modo = capacidad.flatMap { ctx.config.modo($0) }
        // 10 · Externa: aprobación siempre.
        if s.externa != nil || s.tipo == .externa {
            if modo == .off { return r(.denegado, 10, "La función \(capacidad ?? "") está apagada.") }
            return r(.requiereAprobacion, 10, "Sale de la empresa: necesita tu aprobación.")
        }
        // 11 · Suelo.
        if PermisoBase.incluye(s.tipo) {
            if modo == .off { return r(.denegado, 11, "La función \(capacidad ?? "") está apagada.") }
            return r(.permitido, 11, s.tipo.clase == .lectura ? "Puede leerlo." : "Entra en lo que un asistente hace sin pedir permiso.")
        }
        // 12 · Modo de la función.
        if s.tipo == .decisionRegistrar {
            let o = TextFolding.fold(s.origen ?? "")
            if o.hasPrefix("chat:") || o.hasPrefix("pregunta:") { return r(.permitido, 12, "Apunta una decisión que tomaste tú.") }
            return r(.propuesta, 12, "Una decisión sin tu respuesta queda como propuesta.")
        }
        if let c = capacidad, !a.capacidades.isEmpty, !a.capacidades.contains(c) {
            return r(.denegado, 12, "\(a.nombre) no lleva la función \(c).")
        }
        switch modo ?? .asistido {
        case .off: return r(.denegado, 12, "La función \(capacidad ?? "") está apagada.")
        case .manual: return r(.tareaParaPersona, 12, "Esta función la haces tú: queda como tarea para ti.")
        case .asistido: return r(.propuesta, 12, "Te lo propone y decides tú.")
        case .supervisado: return r(.permitido, 12, "Lo hace y lo revisas en el resumen semanal.", resumen: true)
        case .autonomo: return r(.permitido, 12, "Lo hace solo.")
        }
    }

    /// Paso 5: lo que ningún asistente hace nunca.
    func veto(_ s: SolicitudAutorizacion, _ ctx: Contexto) -> String? {
        if s.tipo.clase == .vetada { return Self.textoDeVeto(s.tipo) }
        guard s.tipo.escribe else { return nil }
        for ruta in s.rutas {
            if let v = ClasificadorDePlan.vetoDeRuta(ruta, layout: ctx.layout) { return Self.textoDeVeto(v) }
        }
        return nil
    }

    static func textoDeVeto(_ t: TipoDeAccion) -> String {
        switch t {
        case .config, .ajustesEscribir: "Un asistente no cambia los ajustes ni los permisos."
        case .capacidadDeclarar: "Un asistente no declara funciones: lo haces tú."
        case .metasFijar: "Un asistente no fija metas: lo haces tú."
        case .aprobacionDecidir: "Un asistente no aprueba ni cambia el estado de una aprobación."
        case .rolesEscribir: "Un asistente no cambia los roles."
        case .agentsEscribir: "Un asistente no cambia AGENTS.md."
        case .empresaEscribir: "Un asistente no cambia Empresa.md."
        case .venceMover: "Un asistente no mueve la fecha límite («vence»)."
        case .tareaCerrar: "Un asistente no da una tarea por hecha ni la cancela: la deja en revisión."
        case .oportunidadGanar: "Un asistente no pasa una oportunidad a Ganada."
        case .cobroConfirmar, .conciliacionConfirmar: "Un asistente no confirma cobros: lo propone y confirmas tú."
        default: "Un asistente no puede hacer esto."
        }
    }

    /// Paso 6: activo en la configuración confirmada y su área trabajando.
    func rol(_ s: SolicitudAutorizacion, _ ctx: Contexto) -> DecisionAutorizacion? {
        guard case .agente(let crudo) = s.autor else { return nil }
        let slug = ConfigAgentes.slug(crudo)
        func no(_ m: String) -> DecisionAutorizacion { DecisionAutorizacion(resultado: .denegado, paso: 6, motivo: m, solicitud: s) }
        guard let a = ctx.config.asistente(slug) else { return no("No conozco a este asistente.") }
        guard a.activo else { return no("\(a.nombre) no está activo.") }
        if !a.areas.isEmpty {
            let enMarcha = a.areas.filter { !ctx.config.enPausa($0) && Self.trabaja(ctx.estadoDeArea($0)) }
            if enMarcha.isEmpty {
                if a.areas.contains(where: ctx.config.enPausa) { return no("El área de \(a.nombre) está en pausa.") }
                return no("El área de \(a.nombre) está preparada o en reposo: los asistentes aún no trabajan ahí.")
            }
        }
        // Escribir en un área en pausa, preparada o en reposo (la Bitácora vale siempre: es de los asistentes).
        if s.tipo.escribe {
            for ruta in s.rutas where !ClasificadorDePlan.Contexto(root: root, layout: ctx.layout).esBitacora(ruta) {
                guard let area = ctx.layout.area(of: ruta) else { continue }
                if ctx.config.enPausa(area) { return no("El área \(area.nombre) está en pausa.") }
                if !Self.trabaja(ctx.estadoDeArea(area)) { return no("El área \(area.nombre) está preparada o en reposo.") }
            }
        }
        return nil
    }

    /// Un área preparada o en reposo no tiene asistentes trabajando (sin estado escrito, sí).
    static func trabaja(_ e: AreaStatus) -> Bool { e != .preparada && e != .reposo }

    /// Paso 7: dónde puede leer o escribir.
    func alcance(_ ruta: VaultPath, _ s: SolicitudAutorizacion, _ a: AsistenteConfigurado, _ ctx: Contexto) -> String? {
        let x = ClasificadorDePlan.Contexto(root: root, layout: ctx.layout)
        let area = ctx.layout.area(of: ruta)
        if !s.tipo.escribe {
            if let area { return a.leeEn(area) ? nil : "\(a.nombre) no lee \(area.nombre)." }
            if x.esBuzon(ruta) { return a.buzon || a.coordinador ? nil : "\(a.nombre) no lee el Buzón." }
            return nil
        }
        if s.tipo == .bitacoraRegistrar, x.esBitacora(ruta) { return nil }
        if x.esBuzon(ruta) { return a.buzon || a.coordinador ? nil : "\(a.nombre) no trabaja en el Buzón." }
        if let area {
            if a.escribeEn(area) { return nil }
            // F5 · mail: lo que entra por el Buzón llega a su área (SISTEMAS CO1). El Cartero puede CREAR tareas y borradores
            // nuevos en las áreas que lee (nunca cambiar lo que ya existe); `tls-mcp` exige además el enlace al correo.
            if a.slug == "cartero", a.buzon, a.leeEn(area), s.tipo == .tareaCrear || s.tipo == .borradorPreparar,
               !FileManager.default.fileExists(atPath: ruta.url(in: root).path) { return nil }
            // Sus propias tareas, estén donde estén.
            if x.esTarea(ruta), let r = x.frontmatter(ruta)?.text("responsable"), ConfigAgentes.slug(r) == a.slug,
               r.lowercased().hasPrefix("agente:") { return nil }
            return "\(a.nombre) no trabaja en \(area.nombre): lo propone a quien lleva esa área."
        }
        return "\(a.nombre) no escribe fuera de las áreas."
    }

    /// Paso 8: lo privado, `.tls/`, lo oculto, lo excluido, los secretos y lo que sale de la carpeta por un enlace.
    func privado(_ ruta: VaultPath, _ ctx: Contexto) -> String? {
        let nf = "No encontrado."
        if ruta.isRoot { return nil }
        if ruta.components.contains("..") { return nf }
        if ruta.components.contains(where: { $0.hasPrefix(".") }) { return nf }
        if ctx.layout.isPrivate(ruta) { return nf }
        if PermisoBase.esFicheroVetado(ruta) { return nf }
        if ExclusionRules(paths: opciones.excluidas).excludes(ruta) { return nf }
        let canonica = TextFolding.pathKey(PathGuard.canonicalPath(ruta.url(in: root)))
        if canonica != TextFolding.pathKey(realRoot + "/" + ruta.raw) { return nf }
        return nil
    }

    /// Paso 9: topes de la ejecución.
    func topes(_ s: SolicitudAutorizacion, _ a: AsistenteConfigurado) -> String? {
        if let t = s.tamano, t > PermisoBase.tamanoMaximo { return "Es demasiado largo para escribirlo de una vez." }
        if s.tipo == .delegar {
            guard a.coordinador else { return "Solo el coordinador delega." }
            let p = s.profundidadDelegacion ?? ((s.ejecucion?.profundidad ?? 0) + 1)
            if p > PermisoBase.profundidadMaxima { return "No se delega más de \(PermisoBase.profundidadMaxima) veces seguidas." }
        }
        if s.tipo == .tareaCrear, let e = s.ejecucion {
            let hechas = (try? estado.permitidas(TipoDeAccion.tareaCrear.rawValue, ejecucion: e.id)) ?? 0
            if hechas >= a.maxTareasPorEjecucion {
                return "Ya creó \(hechas) tareas en este trabajo (su tope es \(a.maxTareasPorEjecucion))."
            }
        }
        return nil
    }

    // MARK: Planes

    func evaluar(plan original: WritePlan, solicitud: SolicitudAutorizacion?, ejecucion: ContextoEjecucion?,
                 _ ctx: Contexto) -> DecisionAutorizacion {
        let x = ClasificadorDePlan.Contexto(root: root, layout: ctx.layout)
        // F4 · corrector (R1): si lo pide un asistente, el plan se decide como ese asistente aunque vaya a nombre de la
        // app (`TaskStore` lo pone así cuando inserta el encabezado de un comentario escrito a mano). Un plan «del
        // sistema» nunca cambia el autor de una solicitud de un asistente: ni salta el interruptor, ni su área, ni su
        // alcance, y la auditoría lo apunta a su nombre.
        var plan = original
        if let s = solicitud, s.autor.esAgente { plan.autor = s.autor }
        var partes = ClasificadorDePlan.solicitudes(plan, contexto: x, ejecucion: ejecucion)
        if let s = solicitud {
            // Lo que dice quien llama se suma a lo que dice el plan (nunca lo rebaja: el plan manda).
            partes = partes.map { p in
                var q = p
                if q.capacidad == nil { q.capacidad = s.capacidad }
                if q.externa == nil, let e = s.externa { q.externa = e }
                if q.origen == nil { q.origen = s.origen }
                return q
            }
            var propia = s
            propia.autor = plan.autor
            propia.plan = plan.id
            partes.insert(propia, at: 0)
        }
        // Las tareas que crea el plan cuentan una a una para el tope.
        let combinada = SolicitudAutorizacion(autor: plan.autor, tipo: partes.first?.tipo ?? .fichaEditar,
                                              rutas: partes.flatMap(\.rutas), capacidad: partes.compactMap(\.capacidad).first,
                                              externa: partes.compactMap(\.externa).first, ejecucion: ejecucion, plan: plan.id)
        guard !partes.isEmpty else {
            return DecisionAutorizacion(resultado: .permitido, paso: 2, motivo: "No cambia nada.", solicitud: combinada)
        }
        var decisiones: [DecisionAutorizacion] = []
        var tareasNuevas = 0
        for p in partes {
            var d = evaluar(p, ctx)
            if p.tipo == .tareaCrear, d.permitido, case .agente(let slug) = plan.autor, let e = ejecucion,
               let a = ctx.config.asistente(ConfigAgentes.slug(slug)) {
                tareasNuevas += 1
                let hechas = ((try? estado.permitidas(TipoDeAccion.tareaCrear.rawValue, ejecucion: e.id)) ?? 0) + tareasNuevas
                if hechas > a.maxTareasPorEjecucion {
                    d = DecisionAutorizacion(resultado: .denegado, paso: 9,
                                             motivo: "Serían \(hechas) tareas en este trabajo (su tope es \(a.maxTareasPorEjecucion)).",
                                             solicitud: p)
                }
            }
            decisiones.append(d)
        }
        // Lo más grave decide: no → no encontrado → solo lectura → aprobación → tarea para persona → propuesta → sí.
        let orden: [DecisionAutorizacion.Resultado] = [.noEncontrado, .denegado, .soloLectura, .requiereAprobacion,
                                                        .tareaParaPersona, .propuesta, .permitido]
        let peor = decisiones.min { a, b in
            let ia = orden.firstIndex(of: a.resultado)!, ib = orden.firstIndex(of: b.resultado)!
            return ia != ib ? ia < ib : a.paso < b.paso
        }!
        let resumen = peor.resultado == .permitido && decisiones.contains(where: \.alResumenSemanal)
        var sol = combinada
        // Para la auditoría y el tope, un plan permitido que crea tareas cuenta como tantas tareas nuevas como cree.
        sol.tipo = peor.resultado == .permitido && tareasNuevas > 0 ? .tareaCrear : peor.solicitud.tipo
        sol.capacidad = peor.solicitud.capacidad ?? combinada.capacidad
        if peor.resultado == .permitido, tareasNuevas > 1, let e = ejecucion {
            for _ in 1..<tareasNuevas {
                _ = try? estado.apuntar(fecha: opciones.ahora(), autor: plan.autor, accion: TipoDeAccion.tareaCrear.rawValue,
                                        rutas: [], capacidad: nil, externa: nil, ejecucion: e.id, plan: plan.id, paso: 11,
                                        decision: DecisionAutorizacion.Resultado.permitido.rawValue,
                                        motivo: "Otra tarea del mismo plan.")
            }
        }
        return DecisionAutorizacion(resultado: peor.resultado, paso: peor.paso, motivo: peor.motivo, alResumenSemanal: resumen,
                                    solicitud: sol)
    }

    // MARK: Propuestas

    /// F4 · corrector (R9): lo que un asistente puede dejar como propuesta para aplicarla tú de un clic. Nunca lo que
    /// solo hace una aprobación (emitir o numerar una factura, enviar, pagar, el estado de un borrador) ni lo vetado
    /// (`.tls/`, `Roles/`, `AGENTS.md`, `Empresa.md`, `Metas.md`, `vence`, cerrar tareas, ganar, confirmar cobros):
    /// eso se pide con `tls_solicitar_accion` o lo haces tú. Devuelve el motivo (en palabras de persona) o `nil`.
    public func motivoParaNoProponer(_ plan: WritePlan) -> String? {
        let ctx = contexto()
        for op in plan.ops {
            for p in [op.path] + { if case .move(_, let b) = op { return [b] } else { return [] } }() {
                if privado(p, ctx) != nil { return "No encontrado." }
            }
        }
        return Self.motivoParaNoProponer(plan, root: root, layout: ctx.layout)
    }

    /// Lo mismo, sin mirar lo privado (quien llama ya lo apartó): solo qué hace cada operación.
    public static func motivoParaNoProponer(_ plan: WritePlan, root: URL, layout: VaultLayout) -> String? {
        let x = ClasificadorDePlan.Contexto(root: root, layout: layout)
        for op in plan.ops {
            for (tipo, _, _, externa, _) in ClasificadorDePlan.clasificar(op, contexto: x) {
                if externa != nil || tipo.clase == .externa {
                    return "Eso sale de la empresa o lo emite: se pide con tls_solicitar_accion y lo aprueba la persona."
                }
                if tipo.clase == .vetada { return textoDeVeto(tipo) }
            }
        }
        return nil
    }

    // MARK: Auditoría

    func apuntar(_ d: DecisionAutorizacion, rutas: [VaultPath]) {
        let s = d.solicitud
        _ = try? estado.apuntar(fecha: opciones.ahora(), autor: s.autor, accion: s.tipo.rawValue, rutas: rutas,
                                capacidad: s.capacidadEfectiva, externa: s.externa?.rawValue ?? s.herramienta,
                                ejecucion: s.ejecucion?.id, plan: s.plan, paso: d.paso, decision: d.resultado.rawValue,
                                motivo: d.motivo, resumen: d.alResumenSemanal)
    }
}
