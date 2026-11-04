import Foundation
import Observation
import TLSCore
import TLSDesign

/// El estado de la pantalla Tareas de una pestaña de ventana: las tareas de la empresa (de la foto compartida,
/// `AlmacenRelaciones`, rehecha con cada `sesion.revision`), lo que se ve (`ConsultaTareas`, guardada en el
/// recuerdo de la pestaña), la elegida y lo que hay que revisar. Escribe siempre como la persona, por `CommandBus`.
@Observable @MainActor
final class ModeloTareas {
    let sesion: VaultSession
    let almacen: AlmacenRelaciones

    private(set) var filas: [FilaTarea] = []
    private(set) var revision: RevisionTareas = .vacia
    /// Ya hay una primera lectura (para no enseñar «No hay tareas» mientras se lee).
    private(set) var cargada = false
    /// La generación de la foto con la que se hicieron las filas.
    @ObservationIgnored private var generacionLeida = -1

    var consulta: ConsultaTareas
    /// La tarjeta o fila elegida (para ⌘← ⌘→, ↩ y la vista previa).
    var elegida: VaultPath?

    init(sesion: VaultSession, consulta: ConsultaTareas = ConsultaTareas()) {
        self.sesion = sesion
        self.almacen = AlmacenRelaciones.de(sesion)
        self.consulta = consulta
    }

    var hoy: LocalDate { almacen.hoy }
    var persona: String { sesion.persona }

    func cargar() async {
        await almacen.actualizar()
        guard let foto = almacen.foto, almacen.generacion != generacionLeida else { cargada = cargada || almacen.foto != nil; return }
        let grafo = almacen.grafo
        let generacion = almacen.generacion
        let (filas, revision) = await Task.detached(priority: .userInitiated) {
            (LectorTareas.filas(foto: foto, nombre: { grafo?.ficha($0)?.nombre }), RevisionTareas.de(foto))
        }.value
        self.filas = filas
        self.revision = revision
        generacionLeida = generacion
        cargada = true
    }

    // MARK: Lo que se ve

    var visibles: [FilaTarea] { consulta.filtrar(filas, hoy: hoy, persona: persona) }
    var resumen: ResumenTareas { ResumenTareas(filas, hoy: hoy) }

    func grupos() -> [GrupoTareas] { consulta.grupos(visibles, persona: persona) }
    func columnas() -> [GrupoTareas] { ColumnasTablero.columnas(visibles, verCanceladas: consulta.verCanceladas || consulta.estado == .cancelada) }

    func fila(_ ruta: VaultPath) -> FilaTarea? { filas.first { $0.ruta == ruta } }

    /// Proyectos y oportunidades que tienen tareas (para el filtro), por nombre.
    var contenedores: [(ruta: VaultPath, nombre: String, esProyecto: Bool)] {
        var vistos = Set<VaultPath>()
        return filas.compactMap { f -> (VaultPath, String, Bool)? in
            guard let c = f.contenedor, vistos.insert(c).inserted else { return nil }
            return (c, f.contenedorNombre ?? c.stem, f.contenedorEsProyecto)
        }
        .sorted { TextFolding.fold($0.1) < TextFolding.fold($1.1) }
    }

    /// Quién lleva tareas (tú primero), para el filtro.
    var responsables: [(id: String, nombre: String)] {
        var vistos = Set<String>()
        var out: [(String, String)] = []
        for f in filas {
            guard let r = f.tarea.responsable, vistos.insert(TextFolding.fold(r)).inserted else { continue }
            out.append((r, Responsables.nombre(de: r)))
        }
        return out.sorted { a, b in
            let ma = TextFolding.fold(a.0) == TextFolding.fold(persona), mb = TextFolding.fold(b.0) == TextFolding.fold(persona)
            if ma != mb { return ma }
            return TextFolding.fold(a.1) < TextFolding.fold(b.1)
        }
    }

    // MARK: Escribir

    var motivoSoloLectura: String? { EdicionRelaciones.motivoSoloLectura(sesion) }

    /// Cambia **solo** el estado (tablero: arrastrar, ⌘← ⌘→, «Mover a…» o VoiceOver) y lo apunta en la Actividad.
    @discardableResult
    func mover(_ ruta: VaultPath, a nuevo: EstadoTarea) async -> Bool {
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return false }
        await almacen.actualizar()
        guard let foto = almacen.foto else { return false }
        let store = TaskStore(snapshot: foto)
        guard let t = store.tarea(ruta), !sesion.esPrivado(ruta) else { return false }
        do {
            let plan = try PlanesTarea.cambiarSoloEstado(t, a: nuevo, store: store, autor: sesion.autor, persona: sesion.persona)
            try await sesion.escribir(plan: plan, aviso: "\(t.numero ?? t.titulo) pasa a \(nuevo.rawValue)")
            almacen.invalidar()
            await cargar()
            return true
        } catch TareaError.sinCambios {
            return false
        } catch let e as TareaError {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
            return false
        } catch {
            return false
        }
    }

    /// ⌘← (-1) y ⌘→ (+1): a la columna de al lado.
    @discardableResult
    func moverAlLado(_ ruta: VaultPath, paso: Int) async -> Bool {
        guard let f = fila(ruta),
              let destino = ColumnasTablero.vecina(de: f.estado, paso: paso, verCanceladas: consulta.verCanceladas) else { return false }
        return await mover(ruta, a: destino)
    }

    // MARK: Revisar

    /// Escribe el plan de una tarjeta de revisión (con el clic de la persona) y relee.
    func aplicar(_ preparar: (VaultSnapshot, Autor) throws -> WritePlan?, aviso: String) async {
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return }
        await almacen.actualizar()
        guard let foto = almacen.foto else { return }
        do {
            guard let plan = try preparar(foto, sesion.autor) else { return }
            try await sesion.escribir(plan: plan, aviso: aviso)
            almacen.invalidar()
            await cargar()
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
        }
    }

    /// Renumera las repetidas: número nuevo y fichero renombrado en la misma operación (con sus enlaces).
    func renumerarRepetidas() async {
        await aplicar({ foto, autor in
            guard let p = try RevisionTareas.renumerar(foto, autor: autor) else { return nil }
            return p.esSeguro ? p.plan : nil
        }, aviso: "Renumeré las tareas repetidas")
    }
}
