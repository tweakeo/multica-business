import Foundation

// Las tarjetas de los asistentes en Decisiones (PLAN §5.2 «Qué es una tarjeta de la bandeja», §6.3) y el presupuesto
// de interrupciones. Como todas, salen de una consulta (no hay un almacén de tarjetas):
//
// | Tarjeta | De dónde sale |
// |---|---|
// | Aprobación | Ficha `draft` (o factura) y su registro en `ApprovalStore` |
// | Pregunta | Tarea `tipo: pregunta` |
// | Propuesta, mejora o CRITERIO | Tarea `tipo: decision` + el plan guardado en `estado.sqlite.propuestas`; 3 aprobaciones iguales seguidas |
// | Cambio de permisos fuera de la app | `config_confirmada` frente a `.tls/config.yaml` |
//
// Presupuesto: como mucho `avisos.tope_tarjetas_dia` (5) tarjetas nuevas al día que no sean rojas (el resto, al resumen
// semanal agrupado por tipo) y `avisos.tope_notificaciones_no_rojas_dia` (3) avisos al día que no sean rojos.

/// De dónde sale una tarjeta de los asistentes.
public struct GobiernoDeTarjeta: Sendable, Hashable {
    public enum Clase: String, Sendable, Hashable, CaseIterable {
        case aprobacion, pregunta, propuesta, mejora, criterio, cambioDePermisos

        /// Grupo de la lista de Decisiones (§6.3: Para aprobar · Preguntas · Propuestas de mejora · Archivos en conflicto).
        public var grupo: String {
            switch self {
            case .aprobacion, .cambioDePermisos: "Para aprobar"
            case .pregunta: "Preguntas"
            case .propuesta, .mejora, .criterio: "Propuestas de mejora"
            }
        }
    }

    public let clase: Clase
    /// `comercial`.
    public let asistente: String?
    /// `apr-…` (aprobaciones).
    public let aprobacion: String?
    /// `prop-…` (propuestas).
    public let propuesta: String?
    public let accion: AccionExterna?
    /// La aprobación cambió desde que la preparó el asistente: «Aprobar» se desactiva.
    public let cambio: Bool

    public init(clase: Clase, asistente: String? = nil, aprobacion: String? = nil, propuesta: String? = nil,
                accion: AccionExterna? = nil, cambio: Bool = false) {
        self.clase = clase; self.asistente = asistente; self.aprobacion = aprobacion; self.propuesta = propuesta
        self.accion = accion; self.cambio = cambio
    }
}

extension TarjetaDecision {
    /// Grupo en la lista de F4 (las de los asistentes, por su clase; las tuyas, como en F2).
    public var grupoF4: String { gobierno?.clase.grupo ?? tipo.grupo }

    func con(_ g: GobiernoDeTarjeta) -> TarjetaDecision {
        var t = self
        t.gobierno = g
        return t
    }
}

/// Lo que el gobierno aporta a la bandeja (se lee una vez por consulta).
public struct FuenteDeGobierno: Sendable {
    public var aprobaciones: [Aprobacion]
    public var propuestas: [Propuesta]
    public var config: EstadoDeConfig?
    public var repeticiones: [ApprovalStore.Repeticion]
    /// Día en que se vio cada tarjeta por primera vez (para el presupuesto de las que fabrica la app).
    public var primeraVez: [String: LocalDate]
    public var descartadas: Set<String>

    public init(aprobaciones: [Aprobacion] = [], propuestas: [Propuesta] = [], config: EstadoDeConfig? = nil,
                repeticiones: [ApprovalStore.Repeticion] = [], primeraVez: [String: LocalDate] = [:], descartadas: Set<String> = []) {
        self.aprobaciones = aprobaciones; self.propuestas = propuestas; self.config = config; self.repeticiones = repeticiones
        self.primeraVez = primeraVez; self.descartadas = descartadas
    }

    /// Lee lo de una carpeta.
    public static func de(_ autorizador: Autorizador) -> FuenteDeGobierno {
        let store = ApprovalStore(estado: autorizador.estado)
        let ahora = autorizador.opciones.ahora()
        return FuenteDeGobierno(aprobaciones: (try? store.abiertas(ahora: ahora)) ?? [],
                                propuestas: (try? AlmacenPropuestas(estado: autorizador.estado).pendientes()) ?? [],
                                config: autorizador.estadoDeConfig(), repeticiones: (try? store.repeticiones()) ?? [],
                                descartadas: (try? autorizador.estado.descartadas()) ?? [])
    }
}

extension BandejaDeDecisiones {
    /// La bandeja de F4: las tarjetas de F2 con lo que dicen de ellas los asistentes, más las aprobaciones de
    /// facturas, las de CRITERIO y la de permisos cambiados fuera de la app. `estado` apunta el día en que se vio
    /// cada tarjeta que fabrica la app (para el presupuesto).
    public static func consultar(_ lectura: LecturaDominio, conflictos: [ConflictRecord] = [], persona: String? = nil,
                                 gobierno g: FuenteDeGobierno, estado: EstadoGobierno? = nil) -> BandejaDeDecisiones {
        let base = consultar(lectura, conflictos: conflictos, persona: persona)
        let hoy = lectura.hoy
        var tarjetas: [TarjetaDecision] = []
        var cubiertas: Set<String> = []
        let porRuta = Dictionary(g.aprobaciones.compactMap { a in a.ruta.map { (TextFolding.pathKey($0.raw), a) } },
                                 uniquingKeysWith: { a, b in a.creada >= b.creada ? a : b })
        for t in base.tarjetas {
            let fm = t.ruta.flatMap { lectura.ficha($0) }
            let creadaPor = fm?.texto("creada_por") ?? fm?.texto("creado_por")
            let asistente = creadaPor.flatMap { $0.lowercased().hasPrefix("agente:") ? ConfigAgentes.slug($0) : nil }
            switch t.tipo {
            case .paraAprobar:
                if let r = t.ruta, let a = porRuta[TextFolding.pathKey(r.raw)] {
                    cubiertas.insert(a.id)
                    tarjetas.append(t.con(GobiernoDeTarjeta(clase: .aprobacion, asistente: a.agente, aprobacion: a.id,
                                                            accion: a.accion, cambio: a.estado == .invalidada)))
                } else {
                    tarjetas.append(t)
                }
            case .pregunta:
                tarjetas.append(asistente.map { t.con(GobiernoDeTarjeta(clase: .pregunta, asistente: $0)) } ?? t)
            case .propuesta:
                let idProp = fm?.texto("propuesta")
                if let p = g.propuestas.first(where: { $0.id == idProp || ($0.tarea.map { TextFolding.pathKey($0.raw) } == t.ruta.map { TextFolding.pathKey($0.raw) }) }) {
                    let clase: GobiernoDeTarjeta.Clase = switch p.clase {
                    case .propuesta: .propuesta
                    case .mejora: .mejora
                    case .criterio: .criterio
                    }
                    tarjetas.append(t.con(GobiernoDeTarjeta(clase: clase, asistente: p.agente, propuesta: p.id)))
                } else {
                    tarjetas.append(t)
                }
            case .conflicto:
                tarjetas.append(t)
            }
        }
        // Aprobaciones sin tarjeta de borrador (facturas, o un borrador cuyo espejo aún no se escribió).
        var fabricadas: [TarjetaDecision] = []
        for a in g.aprobaciones where !cubiertas.contains(a.id) {
            guard let r = a.ruta, !lectura.layout.isPrivate(r) else { continue }
            let id = "aprobacion:" + a.id
            fabricadas.append(TarjetaDecision(
                id: id, tipo: .paraAprobar, prioridad: .normal, motivo: nil, titulo: a.carga.asunto ?? r.stem,
                problema: a.accion.titulo, opciones: [], porque: nil, ruta: r, conflicto: nil, area: lectura.layout.area(of: r),
                responsable: "agente:" + a.agente, creada: LocalDate(date: a.creada, timeZone: lectura.reloj.zona), vence: nil,
                gobierno: GobiernoDeTarjeta(clase: .aprobacion, asistente: a.agente, aprobacion: a.id, accion: a.accion,
                                            cambio: a.estado == .invalidada)))
        }
        // Permisos cambiados fuera de la app.
        if let c = g.config, c.cambiadaFuera {
            let id = "permisos:" + (c.hashActual ?? "ilegible")
            if !g.descartadas.contains(id) {
                let opciones = c.ilegible
                    ? [OpcionDecision(numero: 1, texto: "Volver a la configuración confirmada", recomendada: true, aFavor: nil, enContra: nil, coste: nil)]
                    : [OpcionDecision(numero: 1, texto: "Confirmar los cambios", recomendada: true, aFavor: nil, enContra: nil, coste: nil),
                       OpcionDecision(numero: 2, texto: "Volver a los de antes", recomendada: false, aFavor: nil, enContra: nil, coste: nil)]
                fabricadas.append(TarjetaDecision(
                    id: id, tipo: .propuesta, prioridad: .alta, motivo: "Permisos sin confirmar", titulo: c.tituloTarjeta,
                    problema: "Hasta que lo confirmes, los asistentes siguen con los permisos de antes (y, si ahora son más estrictos, ya con estos).",
                    opciones: opciones, porque: "Solo tú cambias lo que pueden hacer los asistentes.", ruta: nil, conflicto: nil,
                    area: .equipo, responsable: persona, creada: hoy, vence: nil,
                    gobierno: GobiernoDeTarjeta(clase: .cambioDePermisos)))
            }
        }
        // CRITERIO: la misma aprobación 3 veces seguidas.
        for r in g.repeticiones {
            let id = "criterio:\(r.agente):\(r.accion.rawValue):\(r.ultima)"
            guard !g.descartadas.contains(id) else { continue }
            let nombre = AsistenteConfigurado.nombre(de: r.agente)
            let titulo = r.conCambios
                ? "Corriges igual lo que prepara \(nombre) para \(r.accion.enFrase) (\(r.veces) veces)"
                : "Apruebas tal cual lo que prepara \(nombre) para \(r.accion.enFrase) (\(r.veces) veces seguidas)"
            fabricadas.append(TarjetaDecision(
                id: id, tipo: .propuesta, prioridad: .normal, motivo: nil, titulo: titulo,
                problema: r.conCambios ? "¿Lo guardamos como criterio para que lo tenga en cuenta?"
                    : "Esto ya podría ir con menos revisión en lo interno. Lo que sale de la empresa seguirá pidiendo tu OK.",
                opciones: [OpcionDecision(numero: 1, texto: "Escribir el criterio en su sistema", recomendada: true, aFavor: nil, enContra: nil, coste: nil),
                           OpcionDecision(numero: 2, texto: "Seguir como hasta ahora", recomendada: false, aFavor: nil, enContra: nil, coste: nil)],
                porque: "Tres veces igual es un criterio: escrito, no hace falta repetirlo.", ruta: nil, conflicto: nil,
                area: .equipo, responsable: persona, creada: hoy, vence: nil,
                gobierno: GobiernoDeTarjeta(clase: .criterio, asistente: r.agente, accion: r.accion)))
        }
        // El día en que se vio cada tarjeta fabricada cuenta como su día de nacimiento.
        let vistas = (try? estado?.primeraVez(fabricadas.map { ($0.id, $0.prioridad == .roja) }, hoy: hoy)) ?? g.primeraVez
        tarjetas += fabricadas.map { t in
            guard let d = vistas[t.id], d != t.creada else { return t }
            var copia = TarjetaDecision(id: t.id, tipo: t.tipo, prioridad: t.prioridad, motivo: t.motivo, titulo: t.titulo,
                                        problema: t.problema, opciones: t.opciones, porque: t.porque, ruta: t.ruta,
                                        conflicto: t.conflicto, area: t.area, responsable: t.responsable, creada: d, vence: t.vence)
            copia.gobierno = t.gobierno
            return copia
        }
        tarjetas.sort { a, b in
            if a.prioridad != b.prioridad { return a.prioridad < b.prioridad }
            if a.tipo != b.tipo { return a.tipo < b.tipo }
            let fa = a.vence ?? a.creada ?? hoy, fb = b.vence ?? b.creada ?? hoy
            if fa != fb { return fa < fb }
            return a.titulo.localizedStandardCompare(b.titulo) == .orderedAscending
        }
        let tope = min(lectura.config.topeTarjetasDia, g.config?.efectiva.avisos.topeTarjetasDia ?? lectura.config.topeTarjetasDia)
        return presupuesto(tarjetas, tope: tope)
    }

    /// Las visibles por grupo de F4 (Para aprobar · Preguntas · Propuestas de mejora · Por decidir · Archivos en conflicto).
    public var gruposF4: [(grupo: String, tarjetas: [TarjetaDecision])] {
        let orden = ["Para aprobar", "Preguntas", "Propuestas de mejora", TarjetaDecision.Tipo.propuesta.grupo,
                     TarjetaDecision.Tipo.conflicto.grupo]
        return orden.compactMap { g in
            let l = visibles.filter { $0.grupoF4 == g }
            return l.isEmpty ? nil : (g, l)
        }
    }

    /// Resumen semanal agrupado por clase (lo que no cupo en el día).
    public var resumenPorGrupoF4: [String: Int] {
        Dictionary(grouping: alResumen, by: \.grupoF4).mapValues(\.count)
    }
}

// MARK: Presupuesto de avisos

/// Como mucho `avisos.tope_notificaciones_no_rojas_dia` (3) avisos al día que no sean rojos; los rojos, siempre. Cada
/// tarjeta se avisa una vez.
public struct PresupuestoDeInterrupciones: Sendable {
    public let estado: EstadoGobierno
    public let tope: Int

    public init(estado: EstadoGobierno, tope: Int = AvisosConfig().topeNotificacionesNoRojasDia) {
        self.estado = estado; self.tope = tope
    }

    /// Las tarjetas visibles que se pueden avisar hoy (y las marca como avisadas). `filtro`: las que de verdad se avisan
    /// (los avisos del Mac, solo lo rojo y lo que espera tu OK); las demás no gastan el tope del día.
    public func avisar(_ bandeja: BandejaDeDecisiones, hoy: LocalDate,
                       filtro: (TarjetaDecision) -> Bool = { _ in true }) -> [TarjetaDecision] {
        var out: [TarjetaDecision] = []
        var usadas = (try? estado.notificadasNoRojas(hoy)) ?? 0
        for t in bandeja.visibles where filtro(t) {
            guard (try? estado.yaNotificada(t.id)) == false else { continue }
            let roja = t.prioridad == .roja
            if !roja, usadas >= tope { continue }
            guard (try? estado.marcarNotificada(t.id, roja: roja, hoy: hoy)) == true else { continue }
            if !roja { usadas += 1 }
            out.append(t)
        }
        return out
    }
}

// MARK: Decidir las tarjetas que fabrica la app

public enum DecisionesDeGobierno {
    /// «Confirmar los cambios» de permisos (solo una persona).
    public static func confirmarPermisos(_ autorizador: Autorizador, autor: Autor) throws {
        try autorizador.config.confirmar(por: autor, ahora: autorizador.opciones.ahora())
    }

    /// «Volver a los de antes»: escribe la versión confirmada en el fichero (como persona). `nil` si ya lo está.
    public static func volverALosDeAntes(_ autorizador: Autorizador, bus: CommandBus, autor: Autor) async throws -> WriteResult? {
        guard let plan = try autorizador.config.planVolverALaConfirmada(autor: autor) else { return nil }
        return try await bus.ejecutar(plan)
    }

    /// «Seguir como hasta ahora» en una tarjeta de CRITERIO o de permisos: no vuelve a salir.
    public static func descartar(_ tarjeta: TarjetaDecision, autorizador: Autorizador, autor: Autor, hoy: LocalDate) throws {
        guard autor.esPersona else { throw ErrorDeGobierno.soloPersonas }
        try autorizador.estado.descartarTarjeta(tarjeta.id, hoy: hoy)
    }
}
