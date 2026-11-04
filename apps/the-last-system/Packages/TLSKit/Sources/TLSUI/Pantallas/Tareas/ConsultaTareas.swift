import Foundation
import TLSCore

// F2 · rol tareas. Lo que la pantalla Tareas sabe de cada tarea y cómo la filtra, agrupa y ordena (PLAN §6.4).
// Todo es puro y `Sendable`: se calcula fuera del hilo principal y se prueba sin interfaz.

/// Una tarea tal como la enseña la pantalla Tareas: la ficha de `TaskStore` con lo que hace falta para la fila
/// (estimación, proyecto u oportunidad con su nombre, quién la lleva). Nunca es privada (`LectorTareas` la quita).
struct FilaTarea: Identifiable, Hashable, Sendable {
    var id: VaultPath { tarea.ruta }
    let tarea: Tarea
    /// El estado reconocido; sin estado o con uno que no se reconoce, «Sin programar» (lo que pone la plantilla).
    let estado: EstadoTarea
    /// `estimacion_h` (horas), si está escrita.
    let estimacionH: Double?
    /// Proyecto (el de la propiedad o el de su carpeta) o, si no, la oportunidad.
    let contenedor: VaultPath?
    let contenedorNombre: String?
    let contenedorEsProyecto: Bool

    var ruta: VaultPath { tarea.ruta }
    var titulo: String { tarea.titulo }
    var numero: String { tarea.numero ?? "T-?" }
    var area: AreaCode? { tarea.area }

    /// La lleva un asistente (`agente:*`).
    var esDeAsistente: Bool { tarea.responsable?.lowercased().hasPrefix("agente:") == true }

    /// «Comercial (asistente)», «Manu» o `nil` si nadie.
    var responsableNombre: String? { tarea.responsable.map(Responsables.nombre(de:)) }

    var abierta: Bool { !estado.cerrada }

    /// Vencida: abierta y con `vence` antes de hoy.
    func vencida(hoy: LocalDate) -> Bool {
        guard abierta, let v = tarea.vence else { return false }
        return v < hoy
    }

    /// Es de la persona («Lo mío»): su nombre o su identificador estable en `responsable`.
    func esDe(_ persona: String) -> Bool {
        guard let r = tarea.responsable, !persona.isEmpty else { return false }
        let k = TextFolding.fold(r)
        return k == TextFolding.fold(persona) || k == TextFolding.fold(Responsables.identificador(persona: persona))
    }

    /// Le toca hoy: abierta y planificada para hoy o antes, o que vence hoy.
    func paraHoy(hoy: LocalDate) -> Bool {
        guard abierta else { return false }
        if let p = tarea.planificada, p <= hoy { return true }
        return tarea.vence == hoy
    }

    /// Planificada o con vencimiento de lunes a domingo de la semana de hoy.
    func enLaSemana(hoy: LocalDate) -> Bool {
        guard abierta else { return false }
        let lunes = hoy.adding(days: -(hoy.weekday - 1))
        let domingo = lunes.adding(days: 6)
        return [tarea.planificada, tarea.vence].contains { d in d.map { $0 >= lunes && $0 <= domingo } ?? false }
    }

    /// Sin programar: abierta y sin día para hacerla (`planificada` vacía).
    var sinProgramar: Bool { abierta && tarea.planificada == nil }
}

/// Lee las tareas de la foto de la carpeta para la pantalla Tareas. Nunca enseña lo privado (ni lo retirado al
/// Archivo ni las plantillas, que ya quita `TaskStore`).
enum LectorTareas {
    static func filas(foto: VaultSnapshot, nombre: (VaultPath) -> String? = { _ in nil }) -> [FilaTarea] {
        let store = TaskStore(snapshot: foto)
        let layout = foto.layout
        return store.tareas.filter { !layout.isPrivate($0.ruta) }.map { t in
            let fm = foto.frontmatter(t.ruta)
            let estimacion = fm.text("estimacion_h").flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            let proyecto = t.proyecto ?? t.proyectoPorRuta
            let contenedor = proyecto ?? t.oportunidad
            // Un proyecto u oportunidad privados no se nombran.
            let visible = contenedor.flatMap { layout.isPrivate($0) ? nil : $0 }
            let nombreContenedor = visible.map { c in
                let fmc = foto.frontmatter(c)
                return nombre(c) ?? fmc.text("nombre") ?? fmc.text("titulo")
                    ?? (c.name == "Proyecto.md" ? c.parent?.name ?? c.stem : c.stem)
            }
            return FilaTarea(tarea: t, estado: t.estado ?? .sinProgramar, estimacionH: estimacion, contenedor: visible,
                             contenedorNombre: nombreContenedor, contenedorEsProyecto: visible != nil && proyecto != nil)
        }
    }
}

/// Filtro de fecha de la barra (PLAN §6.4: Hoy / Semana / Vencidas / Sin programar).
enum FiltroFecha: String, CaseIterable, Sendable, Hashable {
    case todas = "Todas"
    case hoy = "Hoy"
    case semana = "Semana"
    case vencidas = "Vencidas"
    case sinProgramar = "Sin programar"
}

enum VistaTareas: String, CaseIterable, Sendable, Hashable {
    case lista = "Lista"
    case tablero = "Tablero"
}

enum AgrupacionTareas: String, CaseIterable, Sendable, Hashable {
    case estado = "Estado"
    case area = "Área"
    case contenedor = "Proyecto u oportunidad"
    case responsable = "Responsable"
    case ninguna = "Sin agrupar"
}

/// Un grupo de la lista (o una columna del tablero).
struct GrupoTareas: Identifiable, Hashable, Sendable {
    let id: String
    let titulo: String
    let estado: EstadoTarea?
    let filas: [FilaTarea]
}

/// Lo que se ve en Tareas: vista, filtros, «Lo mío», búsqueda y agrupación. Se guarda en el recuerdo de la pestaña
/// de ventana (`RecuerdoPantalla`), así que vuelve igual con Atrás y al reabrir la app.
struct ConsultaTareas: Hashable, Sendable {
    var vista: VistaTareas = .lista
    var area: AreaCode?
    /// Proyecto u oportunidad.
    var contenedor: VaultPath?
    /// Identificador de `responsable`; `""` = sin responsable.
    var responsable: String?
    var estado: EstadoTarea?
    var fecha: FiltroFecha = .todas
    var loMio = false
    var busqueda = ""
    var verCanceladas = false
    var agrupar: AgrupacionTareas = .estado

    static let sinResponsable = ""

    init() {}

    // MARK: Recuerdo

    init(recuerdo r: RecuerdoPantalla) {
        vista = r.extra["tareas.vista"].flatMap(VistaTareas.init(rawValue:)) ?? .lista
        area = r.filtros["area"].flatMap(AreaCode.init(rawValue:))
        contenedor = r.filtros["contenedor"].map { VaultPath($0) }
        responsable = r.filtros["responsable"]
        estado = r.filtros["estado"].flatMap(EstadoTarea.init(rawValue:))
        fecha = r.filtros["fecha"].flatMap(FiltroFecha.init(rawValue:)) ?? .todas
        loMio = r.filtros["loMio"] == "1"
        busqueda = r.busqueda ?? ""
        verCanceladas = r.extra["tareas.canceladas"] == "1"
        agrupar = r.extra["tareas.agrupar"].flatMap(AgrupacionTareas.init(rawValue:)) ?? .estado
    }

    func guardar(en r: inout RecuerdoPantalla) {
        r.extra["tareas.vista"] = vista.rawValue
        r.filtros["area"] = area?.rawValue
        r.filtros["contenedor"] = contenedor?.raw
        r.filtros["responsable"] = responsable
        r.filtros["estado"] = estado?.rawValue
        r.filtros["fecha"] = fecha == .todas ? nil : fecha.rawValue
        r.filtros["loMio"] = loMio ? "1" : nil
        r.busqueda = busqueda.isEmpty ? nil : busqueda
        r.extra["tareas.canceladas"] = verCanceladas ? "1" : nil
        r.extra["tareas.agrupar"] = agrupar == .estado ? nil : agrupar.rawValue
    }

    /// Hay algún filtro puesto (aparte de la vista y la agrupación).
    var filtrando: Bool {
        area != nil || contenedor != nil || responsable != nil || estado != nil || fecha != .todas || loMio
            || !busqueda.trimmingCharacters(in: .whitespaces).isEmpty
    }

    mutating func quitarFiltros() {
        area = nil; contenedor = nil; responsable = nil; estado = nil; fecha = .todas; loMio = false; busqueda = ""
    }

    // MARK: Filtrar

    func pasa(_ f: FilaTarea, hoy: LocalDate, persona: String) -> Bool {
        // Cancelada se oculta salvo con el interruptor o si se pide ese estado.
        if f.estado == .cancelada, !verCanceladas, estado != .cancelada { return false }
        if let area, f.area != area { return false }
        if let contenedor, f.contenedor.map({ TextFolding.pathKey($0.raw) }) != TextFolding.pathKey(contenedor.raw) { return false }
        if let responsable {
            if responsable == Self.sinResponsable {
                if f.tarea.responsable != nil { return false }
            } else if f.tarea.responsable.map(TextFolding.fold) != TextFolding.fold(responsable) {
                return false
            }
        }
        if let estado, f.estado != estado { return false }
        if loMio, !f.esDe(persona) { return false }
        switch fecha {
        case .todas: break
        case .hoy: if !f.paraHoy(hoy: hoy) { return false }
        case .semana: if !f.enLaSemana(hoy: hoy) { return false }
        case .vencidas: if !f.vencida(hoy: hoy) { return false }
        case .sinProgramar: if !f.sinProgramar { return false }
        }
        let q = TextFolding.fold(busqueda.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty {
            let campos = [f.numero, f.titulo, f.contenedorNombre, f.responsableNombre, f.area?.nombre].compactMap { $0 }
            let texto = TextFolding.fold(campos.joined(separator: " "))
            // Todas las palabras de la búsqueda, en cualquier orden.
            if !q.split(separator: " ").allSatisfy({ texto.contains($0) }) { return false }
        }
        return true
    }

    func filtrar(_ filas: [FilaTarea], hoy: LocalDate, persona: String) -> [FilaTarea] {
        Self.ordenar(filas.filter { pasa($0, hoy: hoy, persona: persona) }, hoy: hoy)
    }

    // MARK: Ordenar y agrupar

    /// Lo urgente primero: vencidas, luego por planificada, por vencimiento y por número.
    static func ordenar(_ filas: [FilaTarea], hoy: LocalDate) -> [FilaTarea] {
        let lejos = LocalDate(year: 9999, month: 12, day: 31)!
        return filas.sorted { a, b in
            let va = a.vencida(hoy: hoy), vb = b.vencida(hoy: hoy)
            if va != vb { return va }
            let pa = a.tarea.planificada ?? lejos, pb = b.tarea.planificada ?? lejos
            if pa != pb { return pa < pb }
            let ea = a.tarea.vence ?? lejos, eb = b.tarea.vence ?? lejos
            if ea != eb { return ea < eb }
            let na = a.tarea.numeroEntero ?? Int.max, nb = b.tarea.numeroEntero ?? Int.max
            if na != nb { return na < nb }
            return a.ruta < b.ruta
        }
    }

    /// Los grupos de la lista (vacíos fuera), en el orden de la agrupación elegida.
    func grupos(_ filas: [FilaTarea], persona: String) -> [GrupoTareas] {
        switch agrupar {
        case .estado:
            return EstadoTarea.allCases.compactMap { e in
                let l = filas.filter { $0.estado == e }
                return l.isEmpty ? nil : GrupoTareas(id: e.rawValue, titulo: e.rawValue, estado: e, filas: l)
            }
        case .area:
            var out: [GrupoTareas] = AreaCode.allCases.compactMap { a in
                let l = filas.filter { $0.area == a }
                return l.isEmpty ? nil : GrupoTareas(id: a.rawValue, titulo: "\(a.numero) · \(a.nombre)", estado: nil, filas: l)
            }
            let sin = filas.filter { $0.area == nil }
            if !sin.isEmpty { out.append(GrupoTareas(id: "sin-area", titulo: "Sin área", estado: nil, filas: sin)) }
            return out
        case .contenedor:
            let con = Dictionary(grouping: filas.filter { $0.contenedor != nil }, by: { $0.contenedor! })
            var out = con.map { GrupoTareas(id: $0.key.raw, titulo: $0.value.first?.contenedorNombre ?? $0.key.stem, estado: nil, filas: $0.value) }
                .sorted { TextFolding.fold($0.titulo) < TextFolding.fold($1.titulo) }
            let sueltas = filas.filter { $0.contenedor == nil }
            if !sueltas.isEmpty { out.append(GrupoTareas(id: "sueltas", titulo: "Sin proyecto", estado: nil, filas: sueltas)) }
            return out
        case .responsable:
            let con = Dictionary(grouping: filas.filter { $0.tarea.responsable != nil }, by: { TextFolding.fold($0.tarea.responsable!) })
            var out = con.map { GrupoTareas(id: "r:" + $0.key, titulo: $0.value.first?.responsableNombre ?? $0.key, estado: nil, filas: $0.value) }
                .sorted { a, b in
                    let ma = a.filas.first?.esDe(persona) == true, mb = b.filas.first?.esDe(persona) == true
                    if ma != mb { return ma }
                    return TextFolding.fold(a.titulo) < TextFolding.fold(b.titulo)
                }
            let sin = filas.filter { $0.tarea.responsable == nil }
            if !sin.isEmpty { out.append(GrupoTareas(id: "sin-responsable", titulo: "Sin responsable", estado: nil, filas: sin)) }
            return out
        case .ninguna:
            return filas.isEmpty ? [] : [GrupoTareas(id: "todas", titulo: "Todas", estado: nil, filas: filas)]
        }
    }
}

/// Las columnas del tablero (PLAN §6.4): Sin programar, Por hacer, En curso, En revisión, Bloqueada y Hecha;
/// Cancelada solo con el interruptor.
enum ColumnasTablero {
    static func estados(verCanceladas: Bool) -> [EstadoTarea] {
        let base: [EstadoTarea] = [.sinProgramar, .porHacer, .enCurso, .enRevision, .bloqueada, .hecha]
        return verCanceladas ? base + [.cancelada] : base
    }

    /// La columna de al lado (⌘← = -1, ⌘→ = +1), o `nil` en los extremos.
    static func vecina(de estado: EstadoTarea, paso: Int, verCanceladas: Bool) -> EstadoTarea? {
        let cols = estados(verCanceladas: verCanceladas)
        guard let i = cols.firstIndex(of: estado), cols.indices.contains(i + paso) else { return nil }
        return cols[i + paso]
    }

    static func columnas(_ filas: [FilaTarea], verCanceladas: Bool) -> [GrupoTareas] {
        estados(verCanceladas: verCanceladas).map { e in
            GrupoTareas(id: e.rawValue, titulo: e.rawValue, estado: e, filas: filas.filter { $0.estado == e })
        }
    }

    /// Qué dice una columna vacía.
    static func vacio(_ e: EstadoTarea) -> String {
        switch e {
        case .sinProgramar: "Nada sin programar."
        case .porHacer: "Nada por hacer."
        case .enCurso: "Nada en curso ahora."
        case .enRevision: "Nada espera tu revisión."
        case .bloqueada: "Nada bloqueado."
        case .hecha: "Aún nada hecho."
        case .cancelada: "Nada cancelado."
        }
    }
}

/// Las cifras de la cabecera de Tareas: para hoy, vencidas y las que esperan tu revisión.
struct ResumenTareas: Hashable, Sendable {
    let abiertas: Int
    let paraHoy: Int
    let vencidas: Int
    let enRevision: Int

    init(_ filas: [FilaTarea], hoy: LocalDate) {
        let abiertas = filas.filter(\.abierta)
        self.abiertas = abiertas.count
        paraHoy = abiertas.filter { $0.paraHoy(hoy: hoy) }.count
        vencidas = abiertas.filter { $0.vencida(hoy: hoy) }.count
        enRevision = abiertas.filter { $0.estado == .enRevision }.count
    }

    /// «3 para hoy · 1 vencida · 2 esperan tu revisión», o lo que haya.
    var frase: String {
        guard abiertas > 0 else { return "No hay tareas abiertas." }
        var partes = [paraHoy == 0 ? "Nada para hoy" : (paraHoy == 1 ? "1 para hoy" : "\(paraHoy) para hoy")]
        if vencidas > 0 { partes.append(vencidas == 1 ? "1 vencida" : "\(vencidas) vencidas") }
        if enRevision > 0 { partes.append(enRevision == 1 ? "1 espera tu revisión" : "\(enRevision) esperan tu revisión") }
        partes.append(abiertas == 1 ? "1 abierta en total" : "\(abiertas) abiertas en total")
        return partes.joined(separator: " · ") + "."
    }
}

/// Planes de escritura de la pantalla Tareas (todos por `CommandBus`, como la persona).
enum PlanesTarea {
    /// El tablero (arrastrar, ⌘← ⌘→, «Mover a…» o VoiceOver): cambia **solo** la línea `estado` de las propiedades
    /// (criterio F2-2: ni `cerrada` ni el sitio del fichero) y lo apunta en la Actividad con su evento.
    static func cambiarSoloEstado(_ t: Tarea, a nuevo: EstadoTarea, store: TaskStore, autor: Autor,
                                  persona: String) throws -> WritePlan {
        if case .agente = autor, nuevo.cerrada { throw TareaError.noPermitidoAgente(nuevo.rawValue) }
        guard t.estado != nuevo else { throw TareaError.sinCambios }
        let de = t.estadoTexto ?? "sin estado"
        let actividad = try store.anadirActividad(t, autor: autor, texto: "Estado: \(de) → \(nuevo.rawValue).",
                                                  evento: ["tipo": "estado", "de": de, "a": nuevo.rawValue, "desde": "tablero"],
                                                  persona: persona)
        var ops = actividad.ops
        // Como `TaskStore.cambiarEstado`: la propiedad antes de la entrada que se añade al final.
        ops.insert(.mergeFrontmatter(t.ruta, set: [Property(key: "estado", value: .text(nuevo.rawValue))], unset: []),
                   at: max(0, ops.count - 1))
        return WritePlan(autor: actividad.autor, descripcion: "«\(t.titulo)»: \(nuevo.rawValue)", ops: ops)
    }
}
