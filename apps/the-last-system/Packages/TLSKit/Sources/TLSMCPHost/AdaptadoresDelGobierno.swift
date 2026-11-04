import Foundation
import TLSCore

// Conexión del servidor de herramientas con el gobierno de TLSCore (`Autorizador`, `Aprobaciones`,
// `AlmacenPropuestas`, `EscrituraDeAsistente`). La app (integración) crea estos adaptadores; las pruebas pueden usar
// los «en memoria» y `AutorizadorBasico`.

/// El `Autorizador` único de TLSCore visto desde las herramientas. Con plan, se decide **ese** plan (y `CommandBus`
/// lo escribe sin volver a preguntar); sin plan, la solicitud (o la lectura de una ruta).
public struct AutorizadorDelGobierno: AutorizadorDeHerramientas {
    public let autorizador: Autorizador

    public init(_ autorizador: Autorizador) {
        self.autorizador = autorizador
    }

    public func autorizar(_ p: PeticionDeAccion) async -> VeredictoDeAccion {
        Self.veredicto(decidir(p))
    }

    public func visibles(_ rutas: [VaultPath], asistente: String) async -> [VaultPath] {
        autorizador.visibles(rutas, asistente: asistente)
    }

    func decidir(_ p: PeticionDeAccion) -> DecisionAutorizacion {
        let s = Self.solicitud(p)
        if let plan = p.plan {
            return autorizador.decidir(plan: plan, solicitud: s, ejecucion: s.ejecucion)
        }
        if s.tipo.clase == .lectura, let r = p.rutas.first {
            return autorizador.decidirLectura(r, asistente: Self.slug(p.autor), ejecucion: s.ejecucion)
        }
        return autorizador.decidir(s)
    }

    /// La solicitud del gobierno para una petición de herramienta.
    static func solicitud(_ p: PeticionDeAccion) -> SolicitudAutorizacion {
        var capacidad: String?
        var externa: AccionExterna?
        switch p.clase {
        case .dominio(let c): capacidad = c
        case .externa(let e):
            externa = AccionExterna(leyendo: e) ?? .externa
            // F4 · corrector (pendiente de la revisión): emitir una factura es FIN-02; con esa función apagada, ni se pide.
            if externa == .emitirFactura { capacidad = "FIN-02" }
        default: break
        }
        return SolicitudAutorizacion(autor: p.autor, tipo: tipo(p), rutas: p.rutas, capacidad: capacidad, externa: externa,
                                     ejecucion: TLSCore.ContextoEjecucion(id: p.ejecucion, profundidad: p.profundidadDeLaEjecucion),
                                     origen: p.origen, profundidadDelegacion: p.profundidad, plan: p.plan?.id)
    }

    static func slug(_ a: Autor) -> String {
        if case .agente(let s) = a { return s }
        return a.etiqueta
    }

    /// El nombre de la acción de la herramienta es el `TipoDeAccion` del gobierno (`tarea.crear`, `comentar`…).
    static func tipo(_ p: PeticionDeAccion) -> TipoDeAccion {
        if case .externa = p.clase { return .externa }
        if let t = TipoDeAccion(rawValue: p.accion) { return t }
        switch p.clase {
        case .lectura: return .leer
        case .decision: return .proponer
        default: return .fichaEditar
        }
    }

    static func veredicto(_ d: DecisionAutorizacion) -> VeredictoDeAccion {
        switch d.resultado {
        case .permitido: .permitido
        case .soloLectura, .denegado: .denegado(d.motivo)
        case .noEncontrado: .noEncontrado
        case .requiereAprobacion: .requiereAprobacion
        case .tareaParaPersona: .tareaParaPersona
        case .propuesta: .propuesta
        }
    }
}

/// `tls_solicitar_accion` por `Aprobaciones` del gobierno: la petición queda atada al hash de lo que saldría
/// (destinatarios, asunto, cuerpo, importe, adjuntos, borrador y su versión) y el borrador pasa a «Pendiente de tu OK».
/// **Nunca ejecuta nada.**
public struct AprobacionesDelGobierno: SolicitudesDeAprobacion {
    public let aprobaciones: Aprobaciones

    public init(_ aprobaciones: Aprobaciones) {
        self.aprobaciones = aprobaciones
    }

    public func solicitar(_ s: SolicitudDeAccion) async throws -> String {
        guard let accion = AccionExterna(leyendo: s.accion) else { throw ErrorDeHerramienta("No conozco esa acción.") }
        let r = try await aprobaciones.solicitar(accion: accion, borrador: s.borrador, asistente: AutorizadorDelGobierno.slug(s.autor),
                                                 ejecucion: TLSCore.ContextoEjecucion(id: s.ejecucion),
                                                 capacidad: accion == .emitirFactura ? "FIN-02" : nil, herramienta: s.herramienta)
        guard r.estado == DecisionAutorizacion.Resultado.requiereAprobacion.rawValue, let id = r.id else {
            throw ErrorDeHerramienta(r.motivo ?? "No se pudo apuntar la petición.")
        }
        return id
    }
}

/// `AlmacenPropuestas` (`estado.sqlite.propuestas`): el plan se aplica **como persona** al elegir.
public struct PropuestasDelGobierno: AlmacenDePropuestas {
    public let almacen: AlmacenPropuestas

    public init(_ almacen: AlmacenPropuestas) {
        self.almacen = almacen
    }

    public func guardar(_ p: PropuestaDeAsistente) async throws -> String {
        let plan = p.plan ?? WritePlan(autor: p.autor, descripcion: p.resumen, ops: [])
        let r = try almacen.guardar(plan, agente: AutorizadorDelGobierno.slug(p.autor), ejecucion: p.ejecucion,
                                    capacidad: p.capacidad, descripcion: p.resumen, tarea: p.tarjeta)
        return r.id
    }

    public func pendiente(conOrigen origen: String) async -> VaultPath? {
        ((try? almacen.pendientes()) ?? []).first { $0.plan.llevaOrigen(origen) }?.tarea
    }
}

/// Acciones de dominio por `EscrituraDeAsistente` del gobierno: el Autorizador decide y el plan se escribe, se
/// convierte en propuesta (modo asistido) o en tarea para la persona (modo manual).
public struct DominioDelGobierno: EscrituraDeDominio {
    public let escritura: EscrituraDeAsistente

    public init(_ escritura: EscrituraDeAsistente) {
        self.escritura = escritura
    }

    public func escribir(_ plan: WritePlan, peticion: PeticionDeAccion) async throws -> DesenlaceDeDominio {
        let s = AutorizadorDelGobierno.solicitud(peticion)
        switch try await escritura.escribir(plan, solicitud: s, ejecucion: s.ejecucion) {
        case .escrito(let r, _): return .hecho(r)
        case .propuesta(let p, let tarea, _): return .propuesta(tarea, p.id)
        case .tareaParaPersona(let t, _): return .tareaParaPersona(t)
        case .aprobacionRequerida: return .denegado("Esto necesita tu aprobación: pídela con tls_solicitar_accion.")
        case .denegado(let d): return d.resultado == .noEncontrado ? .noEncontrado : .denegado(d.motivo)
        }
    }
}

extension ContextoDelAsistente {
    /// Contexto de una ejecución a partir de la configuración **confirmada** del asistente.
    public init(ejecucion: String, asistente a: AsistenteConfigurado, profundidad: Int = 0, tarea: VaultPath? = nil,
                origen: String? = nil) {
        self.init(ejecucion: ejecucion, asistente: a.slug, coordinador: a.coordinador, areas: a.areas,
                  leeAreas: a.leeTodas ? AreaCode.allCases : a.leeAreas, profundidad: profundidad, tarea: tarea,
                  origen: origen, maxTareas: a.maxTareasPorEjecucion, buzon: a.buzon)
    }
}
