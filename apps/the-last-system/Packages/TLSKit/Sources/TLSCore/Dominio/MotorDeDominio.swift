import Foundation

// El motor del dominio (PLAN §4.7 y §9 F2): envuelve el `CommandBus` para que cada plan pase por las invariantes,
// deje sus eventos en la bandeja de salida (`estado.sqlite`) y las reglas los atiendan como `Autor.sistema`.
//
// 1. `ejecutar(plan)`: invariantes (un bloqueo no escribe nada; ENT-04 se corrige solo) → `CommandBus` → eventos
//    deducidos del antes y el después de cada fichero → outbox (clave única) → reglas.
// 2. Cada regla escribe su plan como sistema; sus eventos llevan un paso más. Una cadena tiene como mucho 3 pasos:
//    lo que salga del tercero queda guardado como «omitido» y no dispara nada.
// 3. En modo importación no se dispara ninguna regla (los eventos quedan «omitidos»).
// 4. Lo que una regla ya hizo se apunta con su clave: repetir el mismo cobro, o que la app se cierre a mitad y se
//    vuelva a procesar, no duplica nada. `procesarPendientes()` termina lo que quedó a medias al abrir.

/// Lo que hizo una regla con un evento.
public struct EjecucionRegla: Sendable, Hashable {
    public enum Resultado: Sendable, Hashable {
        /// Escribió su plan.
        case hecho(resumen: String, plan: UUID)
        /// La función está en manos de una persona: dejó una tarea en su lugar.
        case tareaParaPersona(titulo: String, plan: UUID)
        /// No había nada que hacer.
        case nada(String)
        /// Las invariantes o la guarda no la dejaron escribir.
        case bloqueado(String)
        /// Falló al escribir (se reintenta con `procesarPendientes`).
        case fallido(String)
    }

    public let regla: String
    public let capacidad: String
    public let evento: String
    public let resultado: Resultado

    public var escribio: Bool {
        switch resultado {
        case .hecho, .tareaParaPersona: true
        default: false
        }
    }
}

/// Resultado de escribir un plan a través del dominio.
public struct ResultadoDominio: Sendable {
    public let escritura: WriteResult
    /// Lo que dijeron las invariantes (atenciones y correcciones; los bloqueos no llegan aquí: lanzan).
    public let invariantes: ResultadoInvariante
    /// Eventos que salieron de este plan.
    public let eventos: [EventoDominio]
    /// Lo que hicieron las reglas, en orden (también las de la cadena).
    public let reglas: [EjecucionRegla]
}

public enum DominioError: Error, LocalizedError, Sendable {
    /// Una invariante no deja escribir el plan (VEN-07, ENT-01, precio).
    case bloqueado(ResultadoInvariante)

    public var errorDescription: String? {
        switch self {
        case .bloqueado(let r): r.mensaje ?? "Este cambio no se puede guardar."
        }
    }

    public var resultado: ResultadoInvariante {
        switch self { case .bloqueado(let r): r }
    }
}

public actor MotorDeDominio {
    public struct Opciones: Sendable {
        /// La persona de la carpeta (responsable de las tareas que dejan las reglas).
        public var persona: String
        /// Pasos de regla que puede tener una cadena.
        public var profundidadMaxima: Int
        public var reglas: [Regla]
        /// Reloj fijo (pruebas); si no, el de la carpeta (en el ejemplo, su día fijo).
        public var reloj: Reloj?

        public init(persona: String = "Manu", profundidadMaxima: Int = 3, reglas: [Regla] = ReglasDeSerie.todas, reloj: Reloj? = nil) {
            self.persona = persona; self.profundidadMaxima = profundidadMaxima; self.reglas = reglas; self.reloj = reloj
        }
    }

    public nonisolated let bus: CommandBus
    public nonisolated let estado: EstadoDominio
    public let opciones: Opciones
    public private(set) var modoImportacion = false
    private var procesando = false

    /// Motor sobre el escritor de una carpeta. El estado va a `estado.sqlite`, junto al del escritor.
    public init(bus: CommandBus, opciones: Opciones = Opciones()) throws {
        self.bus = bus
        self.opciones = opciones
        self.estado = try EstadoDominio(directory: bus.writer.stateDirectory)
    }

    /// Mientras dura una importación no se dispara ninguna regla (PLAN §4.7; SISTEMAS §3.4.3).
    public func setModoImportacion(_ activo: Bool) { modoImportacion = activo }

    /// Foto del dominio tal como está ahora en disco.
    public nonisolated func lectura() -> LecturaDominio {
        let w = bus.writer
        let snap = VaultSnapshot.read(entry: w.entry, root: w.root)
        return LecturaDominio(snapshot: snap, reloj: opciones.reloj)
    }

    /// Pregunta antes de escribir (la interfaz, al soltar en Ganada o al guardar un proyecto).
    public nonisolated func comprobar(_ cambio: CambioPropuesto, autor: Autor? = nil) -> ResultadoInvariante {
        Invariantes(lectura: lectura()).comprobar(cambio, autor: autor)
    }

    // MARK: Escribir

    public func ejecutar(_ comando: CommandBus.Comando, autor: Autor) async throws -> ResultadoDominio {
        try await ejecutar(WritePlan(autor: autor, descripcion: comando.descripcion, ops: [comando.op]))
    }

    /// Escribe un plan con las invariantes, guarda sus eventos y deja que las reglas los atiendan.
    /// Lanza `DominioError.bloqueado` si una invariante no lo deja (y entonces no se escribe nada).
    public func ejecutar(_ plan: WritePlan) async throws -> ResultadoDominio {
        let inv = Invariantes(lectura: lectura()).comprobar(.plan(plan), autor: plan.autor)
        guard inv.puedeGuardar else { throw DominioError.bloqueado(inv) }
        let (escritura, eventos) = try await aplicar(inv.corregir(plan), profundidad: 0)
        let reglas = await procesarPendientes()
        return ResultadoDominio(escritura: escritura, invariantes: inv, eventos: eventos, reglas: reglas)
    }

    /// Cambios ya escritos por otro camino (p. ej. una herramienta que usa el `CommandBus` directamente): se
    /// deducen sus eventos y se procesan. `antes`/`despues` son los textos de cada fichero.
    @discardableResult
    public func registrar(_ cambios: [CambioAplicado], autor: Autor, plan: UUID? = nil) async throws -> [EjecucionRegla] {
        // Solo hace falta la estructura de la carpeta (no la foto entera) para saber qué es cada ruta.
        let layout = VaultLayout.load(root: bus.writer.root).layout
        try encolar(EventDeriver(layout: layout).derivar(cambios, autor: autor, plan: plan, profundidad: 0))
        return await procesarPendientes()
    }

    /// Lo que escribe la persona fuera de las pantallas del dominio (el editor, las fichas y bases de F1, las
    /// plantillas…): se escribe sin leer la carpeta entera (el editor no puede esperar a eso) y, como todo plan, sus
    /// eventos van a la bandeja de salida y las reglas los atienden como sistema, con su idempotencia (integración F2:
    /// «tras cada plan de una persona»). Revisión final de F2, dos invariantes también aquí:
    /// - ENT-04: las fechas planificadas de las fichas del plan que caen en sábado o domingo pasan al lunes (solo se
    ///   leen esas fichas); el aviso va en `ResultadoDominio.invariantes`.
    /// - VEN-07: si el plan pasa algo a Ganada (una celda o el tablero de una base, una ficha), se mira con la carpeta
    ///   entera y, sin un cobro confirmado por una persona, no se escribe nada (`DominioError.bloqueado`).
    public func escribirYAtender(_ plan: WritePlan) async throws -> ResultadoDominio {
        if Invariantes.pasaAGanada(plan) {
            let ven07 = Invariantes(lectura: lectura()).comprobar(.plan(plan), autor: plan.autor).bloqueos.filter { $0.codigo == "VEN-07" }
            if !ven07.isEmpty { throw DominioError.bloqueado(ResultadoInvariante(avisos: ven07)) }
        }
        let root = bus.writer.root
        let inv = Invariantes.fechasLaborables(plan, layout: VaultLayout.load(root: root).layout) { Self.leerTexto($0, root: root) }
        let (escritura, eventos) = try await aplicar(inv.corregir(plan), profundidad: 0)
        var reglas: [EjecucionRegla] = []
        if !eventos.isEmpty { reglas = await procesarPendientes() }
        return ResultadoDominio(escritura: escritura, invariantes: inv, eventos: eventos, reglas: reglas)
    }

    public func escribirYAtender(_ comando: CommandBus.Comando, autor: Autor) async throws -> ResultadoDominio {
        try await escribirYAtender(WritePlan(autor: autor, descripcion: comando.descripcion, ops: [comando.op]))
    }

    /// La persona deshizo estos planes (el suyo y los de las reglas que lo siguieron): sus eventos y lo que las
    /// reglas hicieron por ellos dejan de contar (`EstadoDominio.olvidar`), para que, si lo repite, vuelvan a salir.
    @discardableResult
    public func olvidar(planes: [UUID]) -> Int {
        (try? estado.olvidar(planes: planes)) ?? 0
    }

    /// Escribe (sin invariantes: ya se miraron) y guarda los eventos con su profundidad.
    func aplicar(_ plan: WritePlan, profundidad: Int) async throws -> (WriteResult, [EventoDominio]) {
        let w = bus.writer
        var rutas: [VaultPath] = []
        for op in plan.ops {
            rutas.append(op.path)
            if case .move(_, let to) = op { rutas.append(to) }
        }
        var antes: [String: String] = [:]
        for p in rutas where antes[TextFolding.pathKey(p.raw)] == nil {
            if let t = Self.leerTexto(p, root: w.root) { antes[TextFolding.pathKey(p.raw)] = t }
        }
        let resultado = try await bus.ejecutar(plan)
        guard resultado.hecho else { return (resultado, []) }
        // Lo movido conserva su «antes» en el destino (renombrar no es crear).
        for m in resultado.movidas {
            if let t = antes[TextFolding.pathKey(m.de.raw)] { antes[TextFolding.pathKey(m.a.raw)] = t }
        }
        var cambios: [CambioAplicado] = []
        var vistas = Set<String>()
        for p in resultado.cambiadas where vistas.insert(TextFolding.pathKey(p.raw)).inserted {
            cambios.append(CambioAplicado(ruta: p, antes: antes[TextFolding.pathKey(p.raw)], despues: Self.leerTexto(p, root: w.root)))
        }
        let eventos = EventDeriver(layout: VaultLayout.load(root: w.root).layout)
            .derivar(cambios, autor: plan.autor, plan: resultado.planID, profundidad: profundidad)
        try encolar(eventos)
        return (resultado, eventos)
    }

    func encolar(_ eventos: [EventoDominio]) throws {
        for e in eventos {
            if modoImportacion {
                try estado.encolar(e, estado: .omitido, motivo: "Importación: lo importado no dispara reglas.")
            } else if e.profundidad >= opciones.profundidadMaxima {
                try estado.encolar(e, estado: .omitido,
                                   motivo: "La cadena ya lleva \(e.profundidad) pasos: como mucho son \(opciones.profundidadMaxima).")
            } else {
                try estado.encolar(e)
            }
        }
    }

    static func leerTexto(_ p: VaultPath, root: URL) -> String? {
        UbiquityInspector.withoutMaterializing {
            let url = p.url(in: root)
            guard let info = UbiquityInspector.info(url), !info.isDirectory, !info.isSymlink, !info.dataless,
                  let data = try? Data(contentsOf: url, options: [.uncached]) else { return nil }
            return TextDecoding.decode(data).map(TextDecoding.strippingBOM)
        }
    }

    // MARK: Reglas

    /// Atiende los eventos pendientes de la bandeja de salida (también los de la cadena que van saliendo).
    /// Si ya se está procesando (otra llamada), no hace nada: la que está en marcha recoge lo nuevo.
    @discardableResult
    public func procesarPendientes() async -> [EjecucionRegla] {
        guard !procesando else { return [] }
        procesando = true
        defer { procesando = false }
        var hechas: [EjecucionRegla] = []
        var intentados = Set<String>()
        while let ev = (try? estado.pendientes())?.first(where: { !intentados.contains($0.clave) }) {
            intentados.insert(ev.clave)
            // Durante una importación no se atiende nada: lo importado ya entra omitido (`encolar`) y lo que estaba
            // pendiente de antes se queda pendiente para cuando acabe (no se pierde como si fuera de la importación).
            if modoImportacion { break }
            if ev.profundidad >= opciones.profundidadMaxima {
                try? estado.marcar(ev.clave, .omitido, motivo: "La cadena ya lleva \(ev.profundidad) pasos.")
                continue
            }
            var fallo: String?
            for regla in opciones.reglas where regla.evento == ev.tipo {
                do {
                    if let r = try await atender(ev, con: regla) { hechas.append(r) }
                } catch {
                    let m = error.localizedDescription
                    fallo = m
                    hechas.append(EjecucionRegla(regla: regla.id, capacidad: regla.capacidad, evento: ev.clave, resultado: .fallido(m)))
                }
            }
            try? estado.marcar(ev.clave, fallo == nil ? .procesado : .fallido, motivo: fallo)
        }
        return hechas
    }

    /// Una regla con un evento: `nil` si ya lo había hecho antes (misma clave).
    func atender(_ ev: EventoDominio, con regla: Regla) async throws -> EjecucionRegla? {
        let l = lectura()
        let clave = regla.clave(ev, l)
        if try estado.yaAplicada(clave) { return nil }
        let modo = l.config.modo(regla.capacidad)
        let ctx = ContextoRegla(evento: ev, lectura: l, persona: opciones.persona, modo: modo)
        func fin(_ r: EjecucionRegla.Resultado, _ texto: String, plan: UUID? = nil) throws -> EjecucionRegla {
            try estado.apuntar(clave, regla: regla.id, evento: ev.clave, resultado: texto, plan: plan)
            return EjecucionRegla(regla: regla.id, capacidad: regla.capacidad, evento: ev.clave, resultado: r)
        }
        let preparado: ResultadoRegla
        var paraPersona: String?
        if let m = modo, m.esDePersona {
            guard let titulo = regla.paraPersona?(ctx) else {
                return try fin(.nada("La función \(regla.capacidad) la lleva una persona."), "nada: la lleva una persona")
            }
            paraPersona = titulo
            preparado = try Self.tareaParaPersona(titulo, regla: regla, ctx: ctx)
        } else {
            preparado = try regla.preparar(ctx)
        }
        switch preparado {
        case .nada(let motivo):
            return try fin(.nada(motivo), "nada: " + motivo)
        case .plan(let plan, let resumen):
            do { try GuardaDeReglas.comprobar(plan, lectura: l) } catch {
                return try fin(.bloqueado(error.localizedDescription), "bloqueado: " + error.localizedDescription)
            }
            let inv = Invariantes(lectura: l).comprobar(.plan(plan), autor: .sistema)
            guard inv.puedeGuardar else {
                let m = inv.mensaje ?? "Las reglas del dominio no lo dejan."
                return try fin(.bloqueado(m), "bloqueado: " + m)
            }
            let (escrito, _) = try await aplicar(inv.corregir(plan), profundidad: ev.profundidad + 1)
            if let t = paraPersona {
                return try fin(.tareaParaPersona(titulo: t, plan: escrito.planID), "tarea para una persona: " + t, plan: escrito.planID)
            }
            return try fin(.hecho(resumen: resumen, plan: escrito.planID), resumen, plan: escrito.planID)
        }
    }

    /// Cuando la función está en «off» o «manual», la regla deja esto: una tarea para la persona, en el área de la función.
    static func tareaParaPersona(_ titulo: String, regla: Regla, ctx: ContextoRegla) throws -> ResultadoRegla {
        let prefijo = String(regla.capacidad.prefix(3)).uppercased()
        let area = AreaCode(rawValue: prefijo) ?? .direccion
        let nueva = NuevaTarea(titulo: titulo, area: area, responsable: ctx.persona, estado: .porHacer, tipo: "tarea",
                               planificada: ctx.hoy, origen: ctx.origen, autor: .sistema,
                               propiedades: [Property(key: "capacidad", value: .text(regla.capacidad))])
        let nota = try TaskStore(snapshot: ctx.lectura.snapshot, reloj: ctx.lectura.reloj).crear(nueva)
        return .plan(nota.plan, resumen: "Tarea para \(ctx.persona): «\(titulo)»")
    }
}
