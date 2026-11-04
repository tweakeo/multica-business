import Foundation
import Observation
import TLSCore
import TLSDesign

/// El estado de la ficha de una tarea (`TareaDetalle`): su lectura y la foto compartida (las de `FichaModelo`, que
/// también edita «Descripción» en el sitio con `sustituirSeccion`), y lo que se escribe desde aquí, siempre como la
/// persona, por `CommandBus` y con Deshacer: estado (con su entrada de Actividad), «Empezar ahora», «Marcar como
/// hecha», propiedades (`planificada` pasa por el dominio: ENT-04 la corre al lunes), comentarios con @ y «Mover a…».
@Observable @MainActor
final class ModeloTarea {
    let ruta: VaultPath
    let ficha: FichaModelo
    var sesion: VaultSession { ficha.sesion }

    /// Lo último que dijo el dominio al planificar (ENT-04), para enseñarlo junto al campo.
    var avisoPlanificada: String?

    init(ruta: VaultPath, sesion: VaultSession) {
        self.ruta = ruta
        self.ficha = FichaModelo(ruta: ruta, sesion: sesion)
    }

    func cargar() async { await ficha.cargar() }

    var hoy: LocalDate { ficha.hoy }
    var texto: String { ficha.texto ?? "" }
    var puedeEscribir: Bool { sesion.puedeEscribir }
    var motivoSoloLectura: String? { ficha.motivoSoloLectura }

    /// La tarea leída de la foto compartida (una vez por foto).
    var tarea: Tarea? {
        guard let foto = ficha.almacen.foto else { return nil }
        let g = ficha.almacen.generacion
        if let c = cacheTarea, c.generacion == g { return c.tarea }
        let t = TaskStore(snapshot: foto).tarea(ruta)
        cacheTarea = (g, t)
        return t
    }

    @ObservationIgnored private var cacheTarea: (generacion: Int, tarea: Tarea?)?

    /// Lo privado no se enseña aquí (ni se llega por una ruta guardada).
    var esPrivada: Bool { sesion.esPrivado(ruta) }

    /// Asistentes que se pueden mencionar: «comercial» → `agente:comercial` (los de Equipo y los que ya llevan algo).
    var asistentes: [(id: String, nombre: String)] {
        ResponsablesTarea.asistentes(grafo: ficha.grafo, persona: sesion.persona)
    }

    /// Alias de mención («comercial» y «comercial (asistente)» → `agente:comercial`).
    var alias: [String: String] {
        var a: [String: String] = [:]
        for x in asistentes {
            let slug = String(x.id.dropFirst("agente:".count))
            a[TextFolding.fold(slug)] = x.id
            a[TextFolding.fold(x.nombre.replacingOccurrences(of: " (asistente)", with: ""))] = x.id
        }
        return a
    }

    var entradas: [EntradaDeTarea] { ActividadDeTarea.leer(texto, alias: alias, topes: topesDeUso) }

    /// El tope de uso del mes de cada asistente (para decir lo que usó un trabajo como parte de su tope). Una vez por foto.
    var topesDeUso: [String: Double] {
        let g = ficha.almacen.generacion
        if let c = cacheTopes, c.generacion == g { return c.topes }
        var t: [String: Double] = [:]
        if let cfg = sesion.bus?.autorizador?.estadoDeConfig().efectiva {
            for (slug, a) in cfg.agentes { if let m = a.presupuestoMesUSD { t[slug] = m } }
        }
        cacheTopes = (g, t)
        return t
    }

    @ObservationIgnored private var cacheTopes: (generacion: Int, topes: [String: Double])?

    // MARK: Escribir

    private func store() async -> (TaskStore, Tarea)? {
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return nil }
        await ficha.almacen.actualizar()
        guard let foto = ficha.almacen.foto else { return nil }
        let s = TaskStore(snapshot: foto)
        guard let t = s.tarea(ruta) else {
            sesion.aviso = Aviso("No encuentro la tarea: puede que se haya movido fuera de la app.", estado: .atencion)
            return nil
        }
        return (s, t)
    }

    private func terminar() async {
        ficha.almacen.invalidar()
        await ficha.cargar()
    }

    /// Cambia el estado desde la ficha (con `cerrada` al cerrar y su entrada en la Actividad).
    func cambiarEstado(_ nuevo: EstadoTarea, nota: String? = nil) async {
        guard let (s, t) = await store() else { return }
        do {
            let plan = try s.cambiarEstado(t, a: nuevo, autor: sesion.autor, persona: sesion.persona, nota: nota)
            try await sesion.escribir(plan: plan, aviso: "\(t.numero ?? t.titulo) pasa a \(nuevo.rawValue)")
        } catch TareaError.sinCambios {
        } catch let e as TareaError {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch {}
        await terminar()
    }

    /// «Empezar ahora»: una persona la pasa a En curso; si la lleva un asistente, a Por hacer con `planificada: hoy`
    /// (PLAN §4.2: así la coge en cuanto los asistentes estén encendidos). En un solo plan, con su Actividad.
    func empezarAhora() async {
        guard let (s, t) = await store() else { return }
        let deAsistente = t.responsable?.lowercased().hasPrefix("agente:") == true
        let nuevo: EstadoTarea = deAsistente ? .porHacer : .enCurso
        do {
            var plan = try s.cambiarEstado(t, a: nuevo, autor: sesion.autor, persona: sesion.persona, nota: "Empezada ahora.")
            if t.planificada == nil || (t.planificada ?? hoy) > hoy {
                // En la misma línea de propiedades que el estado (el resto del plan, la Actividad, no cambia).
                let dia = Property(key: "planificada", value: .text(Tarea.laborable(hoy).description))
                plan.ops = plan.ops.map { op in
                    if case .mergeFrontmatter(let p, let set, let unset) = op, p == t.ruta { return .mergeFrontmatter(p, set: set + [dia], unset: unset) }
                    return op
                }
            }
            try await sesion.escribir(plan: plan, aviso: "\(t.numero ?? t.titulo) empieza ahora")
        } catch let e as TareaError {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch {}
        await terminar()
    }

    /// Cambia una propiedad (una línea, con Deshacer). `nil` la quita.
    func cambiar(_ clave: String, a valor: PropertyValue?, aviso: String) async {
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return }
        let comando: CommandBus.Comando = valor.map { .cambiarPropiedades(ruta, poner: [Property(key: clave, value: $0)], quitar: []) }
            ?? .cambiarPropiedades(ruta, poner: [], quitar: [clave])
        _ = try? await sesion.escribir(comando, aviso: aviso)
        await terminar()
    }

    /// `planificada` por el dominio: ENT-04 corre al lunes un sábado o un domingo y lo dice.
    func planificar(_ dia: LocalDate?) async {
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return }
        avisoPlanificada = nil
        guard let dia else {
            await cambiar("planificada", a: nil, aviso: "Sin día planificado")
            return
        }
        let final = Tarea.laborable(dia)
        let aviso = final == dia ? "Planificada " + FormatoFicha.cuando(dia, hoy: hoy)
            : "El \(FormatoFicha.fechaConDia(dia, hoy: hoy)) no se trabaja: la planifiqué el \(FormatoFicha.fechaConDia(final, hoy: hoy))"
        if DominioEmpresa.motor(de: sesion) != nil {
            let comando = CommandBus.Comando.cambiarPropiedades(ruta, poner: [Property(key: "planificada", value: .text(dia.description))], quitar: [])
            if let r = try? await sesion.escribirConDominio(comando, aviso: aviso) {
                avisoPlanificada = r.invariantes.avisos.first { $0.codigo == "ENT-04" }?.mensaje
            }
        } else {
            // Sin motor del dominio: la misma regla, ya corregida aquí.
            _ = try? await sesion.escribir(.cambiarPropiedades(ruta, poner: [Property(key: "planificada", value: .text(final.description))], quitar: []),
                                           aviso: aviso)
            if final != dia { avisoPlanificada = aviso + "." }
        }
        await terminar()
    }

    /// Añade un comentario a la Actividad. Las menciones a asistentes se guardan en su evento (dispararlos es F4).
    @discardableResult
    func comentar(_ texto: String) async -> Bool {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, let (s, t) = await store() else { return false }
        var evento = ["tipo": "comentario"]
        let menciones = ActividadDeTarea.menciones(limpio, alias: alias)
        if !menciones.isEmpty { evento["menciones"] = menciones.joined(separator: ",") }
        do {
            let plan = try s.anadirActividad(t, autor: sesion.autor, texto: limpio, evento: evento, persona: sesion.persona)
            try await sesion.escribir(plan: plan, aviso: "Comentario añadido a \(t.numero ?? t.titulo)")
            await terminar()
            return true
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
    }

    /// «Mover a…»: otra área o un proyecto. Devuelve la ruta nueva (para seguir en ella).
    func mover(a destino: MoverTarea.Destino) async -> VaultPath? {
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return nil }
        await ficha.almacen.actualizar()
        guard let foto = ficha.almacen.foto else { return nil }
        do {
            let p = try MoverTarea.preparar(ruta, a: destino, foto: foto, autor: sesion.autor)
            guard p.esSeguro else {
                sesion.aviso = Aviso("No la muevo: hay enlaces que no puedo actualizar sin riesgo. Revísalos en la pestaña Fichero.", estado: .atencion)
                return nil
            }
            try await sesion.escribir(plan: p.plan, aviso: p.descripcion)
            ficha.almacen.invalidar()
            return p.traslados.first?.a
        } catch let e as MoverTarea.Error {
            if e != .yaEsta { sesion.aviso = Aviso(e.localizedDescription, estado: .atencion) }
            return nil
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return nil
        }
    }

    /// Proyectos a los que se puede mover.
    var proyectos: [(ruta: VaultPath, nombre: String, area: AreaCode?)] {
        guard let foto = ficha.almacen.foto else { return [] }
        return MoverTarea.proyectos(foto, grafo: ficha.grafo)
    }
}
