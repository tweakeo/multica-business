import Foundation
import Synchronization

/// Único punto de escritura de la app: traduce órdenes de la interfaz, de las reglas y de los
/// asistentes en planes de escritura y se los pasa al `VaultWriter`.
///
/// F4: todo plan de `Autor.agente` pasa antes por el `Autorizador` (PLAN §5.2) y solo se escribe si lo permite (lo que
/// convierte en propuesta, tarea para una persona o aprobación lo hace `EscrituraDeAsistente`). Sin Autorizador, un
/// asistente no escribe nada que vete el paso 5 (ajustes, roles, `vence`, cerrar tareas…). Lo que la app o una persona
/// escriben en `.tls/config.yaml` queda como configuración confirmada.
public final class CommandBus: Sendable {
    /// Una orden sencilla (un plan de una operación).
    public enum Comando: Sendable, Hashable {
        /// Nota o fichero nuevo; nunca pisa (añade « (2)»).
        case crear(VaultPath, texto: String)
        /// Cambia solo esas propiedades (las demás líneas no se tocan).
        case cambiarPropiedades(VaultPath, poner: [Property], quitar: [String])
        /// Guardado del editor: texto que abrió y texto nuevo.
        case guardarNota(VaultPath, base: String, texto: String)
        case anadirASeccion(VaultPath, seccion: String, texto: String)
        case sustituirSeccion(VaultPath, seccion: String, texto: String, baseHash: String)
        case sustituirCuerpo(VaultPath, cuerpo: String, baseHash: String?)
        case anadirLinea(VaultPath, linea: String)
        case guardarFila(VaultPath, fila: [String: String], clave: String)
        case cambiarCeldas(VaultPath, tabla: TableSelector, columnaClave: String, valorClave: String, celdas: [String: String])
        case anadirFilaATabla(VaultPath, tabla: TableSelector, celdas: [String: String])
        case mover(VaultPath, a: VaultPath)
        /// Mueve a `Archivo/` con la misma ruta. Nunca se borra nada.
        case retirar(VaultPath)

        var op: WriteOp {
            switch self {
            case .crear(let p, let t): .create(p, text: t)
            case .cambiarPropiedades(let p, let poner, let quitar): .mergeFrontmatter(p, set: poner, unset: quitar)
            case .guardarNota(let p, let base, let texto): .saveText(p, base: base, text: texto)
            case .anadirASeccion(let p, let s, let t): .appendToSection(p, section: s, text: t)
            case .sustituirSeccion(let p, let s, let t, let h): .replaceSection(p, section: s, text: t, baseSectionHash: h)
            case .sustituirCuerpo(let p, let c, let h): .replaceBody(p, body: c, baseHash: h)
            case .anadirLinea(let p, let l): .appendLine(p, line: l)
            case .guardarFila(let p, let f, let k): .upsertCSVRow(p, row: f, key: k)
            case .cambiarCeldas(let p, let t, let c, let v, let cells):
                .setTableCells(p, table: t, keyColumn: c, keyValue: v, cells: cells)
            case .anadirFilaATabla(let p, let t, let cells): .appendTableRow(p, table: t, cells: cells)
            case .mover(let a, let b): .move(a, to: b)
            case .retirar(let p): .retire(p)
            }
        }

        /// Texto para «Deshacer».
        var descripcion: String {
            switch self {
            case .crear(let p, _): "Crear «\(p.stem)»"
            case .cambiarPropiedades(let p, _, _): "Cambiar propiedades de «\(p.stem)»"
            case .guardarNota(let p, _, _), .sustituirCuerpo(let p, _, _): "Guardar «\(p.stem)»"
            case .anadirASeccion(let p, let s, _): "Añadir a «\(s)» en «\(p.stem)»"
            case .sustituirSeccion(let p, let s, _, _): "Cambiar «\(s)» en «\(p.stem)»"
            case .anadirLinea(let p, _): "Añadir una línea a «\(p.stem)»"
            case .guardarFila(let p, _, _): "Guardar una fila en «\(p.stem)»"
            case .cambiarCeldas(let p, _, _, _, _): "Cambiar una tabla de «\(p.stem)»"
            case .anadirFilaATabla(let p, _, _): "Añadir una fila a «\(p.stem)»"
            case .mover(let a, let b): a.parent == b.parent ? "Renombrar «\(a.stem)»" : "Mover «\(a.stem)»"
            case .retirar(let p): "Retirar «\(p.stem)»"
            }
        }
    }

    /// Qué hacer con un conflicto de edición o de recuperación.
    public enum EleccionConflicto: Sendable, Hashable {
        /// Me quedo con mi versión; la de fuera se guarda en `Archivo/Conflictos/`.
        case mia
        /// Me quedo con la de fuera; la mía se guarda en `Archivo/Conflictos/`.
        case otra
        /// Las combiné yo: este es el texto final (la mía se guarda en `Archivo/Conflictos/`).
        case combinada(String)
    }

    public let writer: VaultWriter
    private let gobierno: Mutex<Autorizador?>

    public init(writer: VaultWriter, autorizador: Autorizador? = nil) {
        self.writer = writer
        self.gobierno = Mutex(autorizador)
    }

    /// El Autorizador de esta carpeta (F4). La app lo pone al abrir la empresa con escritor.
    public var autorizador: Autorizador? { gobierno.withLock { $0 } }

    public func establecerAutorizador(_ a: Autorizador?) {
        gobierno.withLock { $0 = a }
    }

    public func ejecutar(_ comando: Comando, autor: Autor) async throws -> WriteResult {
        try await ejecutar(WritePlan(autor: autor, descripcion: comando.descripcion, ops: [comando.op]))
    }

    /// Plan compuesto (renombrar con sus enlaces, cambios en bloque…): todo o nada.
    public func ejecutar(_ plan: WritePlan) async throws -> WriteResult {
        try comprobarAsistente(plan)
        // Si había cambios de permisos hechos fuera sin confirmar, escribir el fichero no los confirma.
        let pendiente = tocaConfig(plan) ? (autorizador?.config.leer().cambiadaFuera ?? false) : false
        let r = try await writer.apply(plan)
        if !pendiente { confirmarConfigSiToca(plan, r) }
        return r
    }

    func tocaConfig(_ plan: WritePlan) -> Bool {
        guard !plan.autor.esAgente else { return false }
        let k = TextFolding.pathKey(ConfigConfirmada.ruta.raw)
        return plan.ops.contains { TextFolding.pathKey($0.path.raw) == k }
    }

    /// Un plan de un asistente solo se escribe si el Autorizador lo permite (o ya lo permitió para este mismo plan).
    func comprobarAsistente(_ plan: WritePlan) throws {
        guard case .agente = plan.autor else { return }
        if let a = autorizador {
            if a.consumirPermiso(plan) { return }
            let d = a.decidir(plan: plan)
            if d.permitido {
                _ = a.consumirPermiso(plan)
                return
            }
            throw AutorizacionDenegada(decision: d)
        }
        // Sin Autorizador (pruebas de escritura, herramientas): el escritor ya aparta lo privado, `.tls/` y los cuerpos
        // humanos; aquí se cierra lo que solo se ve por el contenido (paso 5).
        let x = ClasificadorDePlan.Contexto(root: writer.root, layout: UbiquityInspector.withoutMaterializing { VaultLayout.load(root: writer.root).layout })
        for op in plan.ops {
            for (tipo, rutas, _, _, _) in ClasificadorDePlan.clasificar(op, contexto: x) where tipo.clase == .vetada {
                // `.tls/` lo rechaza el escritor con su propio aviso.
                if tipo == .config || tipo == .ajustesEscribir { continue }
                throw WriteError.noPermitidoAsistente(rutas.first?.raw ?? op.path.raw)
            }
        }
    }

    /// La app (persona o sistema) acaba de escribir `.tls/config.yaml`: esa versión es la confirmada.
    func confirmarConfigSiToca(_ plan: WritePlan, _ r: WriteResult) {
        guard r.hecho, !plan.autor.esAgente, let a = autorizador else { return }
        let ruta = ConfigConfirmada.ruta
        guard let hash = r.hashes.first(where: { TextFolding.pathKey($0.key.raw) == TextFolding.pathKey(ruta.raw) })?.value else { return }
        a.config.confirmarEscritoPorLaApp(hash: hash, por: plan.autor.etiqueta, ahora: a.opciones.ahora())
    }

    /// Lo que deshará `deshacer()`, si hay algo.
    public func ultimoDeshacible() async -> UndoInfo? {
        await writer.lastUndoable()
    }

    /// Deshace el último plan (si nadie ha cambiado esos ficheros después).
    public func deshacer(autor: Autor) async throws -> WriteResult {
        // F4 · integración: deshacer algo que la app escribió en `.tls/config.yaml` deja el fichero como estaba; esa vuelve a
        // ser la versión confirmada (si no, parecería un cambio hecho fuera de la app). Con cambios de fuera pendientes, no.
        let pendiente = autor.esAgente ? true : (autorizador?.config.leer().cambiadaFuera ?? true)
        let r = try await writer.undoLast(autor: autor)
        if !pendiente { confirmarConfigSiToca(WritePlan(autor: autor, descripcion: "Deshacer", ops: []), r) }
        return r
    }

    // MARK: Conflictos y duplicados

    /// Resuelve una tarjeta de conflicto de edición o de recuperación.
    public func resolverConflicto(_ id: UUID, eleccion: EleccionConflicto, autor: Autor) async throws -> WriteResult {
        let registry = writer.conflicts
        guard let record = registry.record(id), !record.resuelto,
              record.tipo == .edicion || record.tipo == .recuperacion else { throw WriteError.conflictoNoEncontrado }
        let root = writer.root
        // «Tu versión» (o lo que iba a guardar la app) es la copia guardada fuera de la carpeta.
        guard let mineVersion = record.versiones.first(where: { if case .copia = $0.ubicacion { return $0.etiqueta != "La de fuera" } else { return false } }),
              let mine = registry.datos(de: mineVersion, root: root) else { throw WriteError.versionNoDisponible }
        let path = record.ruta
        let current = UbiquityInspector.withoutMaterializing { try? Data(contentsOf: path.url(in: root)) }
        let stamp = Self.stamp(record.fecha)
        var ops: [WriteOp] = []
        let resolucion: String
        switch eleccion {
        case .mia:
            guard let current, let mineText = EditableText(data: mine),
                  let replace = WriteOp.replaceText(path, base: current, text: mineText.text) else {
                throw WriteError.versionNoDisponible
            }
            ops.append(.create(Self.archived(path, archivo: archivo, nota: "versión de fuera \(stamp)"), contents: current))
            ops.append(replace)
            resolucion = "mia"
        case .otra:
            ops.append(.create(Self.archived(path, archivo: archivo, nota: "tu versión \(stamp)"), contents: mine))
            resolucion = "otra"
        case .combinada(let text):
            guard let current, let replace = WriteOp.replaceText(path, base: current, text: text) else {
                throw WriteError.versionNoDisponible
            }
            ops.append(.create(Self.archived(path, archivo: archivo, nota: "tu versión \(stamp)"), contents: mine))
            ops.append(replace)
            resolucion = "combinada"
        }
        let result = try await writer.apply(WritePlan(autor: autor, descripcion: "Resolver el conflicto de «\(path.stem)»", ops: ops))
        try registry.marcarResuelto(id, como: resolucion)
        return result
    }

    /// Duplicado «X 2.md»: el repetido va a `Archivo/Duplicados/` (o el original, si se elige quedarse con la copia).
    public func descartarDuplicado(_ id: UUID, quedarmeConElDuplicado: Bool = false, autor: Autor) async throws -> WriteResult {
        let registry = writer.conflicts
        guard let record = registry.record(id), !record.resuelto, record.tipo == .duplicado,
              let otra = record.otraRuta else { throw WriteError.conflictoNoEncontrado }
        let ops: [WriteOp]
        if quedarmeConElDuplicado {
            // El original se aparta y el duplicado ocupa su nombre.
            ops = [.retire(record.ruta, apartado: "Duplicados"), .move(otra, to: record.ruta)]
        } else {
            ops = [.retire(otra, apartado: "Duplicados")]
        }
        let result = try await writer.apply(WritePlan(autor: autor, descripcion: "Apartar el duplicado de «\(record.ruta.stem)»", ops: ops))
        try registry.marcarResuelto(id, como: quedarmeConElDuplicado ? "duplicado" : "original")
        return result
    }

    /// Conflicto de iCloud: la versión elegida se queda; las demás van a `Archivo/Conflictos/`.
    /// `version` = nil para quedarse con la actual.
    public func resolverICloud(_ id: UUID, quedarmeCon version: Int?, provider: any ConflictVersionProvider = SystemFileVersions(),
                               autor: Autor) async throws -> WriteResult {
        let registry = writer.conflicts
        guard let record = registry.record(id), !record.resuelto, record.tipo == .icloud else { throw WriteError.conflictoNoEncontrado }
        let root = writer.root
        let path = record.ruta
        let others = record.versiones.filter { if case .copia = $0.ubicacion { return true } else { return false } }
        guard let current = UbiquityInspector.withoutMaterializing({ try? Data(contentsOf: path.url(in: root)) }) else {
            throw WriteError.versionNoDisponible
        }
        // Solo se resuelve si las versiones en conflicto son las que se guardaron al crear la tarjeta
        // (si llega otra, `markResolved` la descartaría sin copia).
        let guardadas = Set(others.compactMap(\.hash))
        func sinCambios() -> Bool {
            provider.unresolvedVersions(of: path.url(in: root)).allSatisfy { v in
                v.data.map { guardadas.contains(ContentHash.of($0)) } ?? false
            }
        }
        guard sinCambios() else { throw WriteError.versionNoDisponible }
        var ops: [WriteOp] = []
        let stamp = Self.stamp(record.fecha)
        if let i = version {
            guard i < others.count, let chosen = registry.datos(de: others[i], root: root),
                  let chosenText = EditableText(data: chosen),
                  let replace = WriteOp.replaceText(path, base: current, text: chosenText.text) else {
                throw WriteError.versionNoDisponible
            }
            ops.append(.create(Self.archived(path, archivo: archivo, nota: "versión anterior \(stamp)"), contents: current))
            for (n, v) in others.enumerated() where n != i {
                if let d = registry.datos(de: v, root: root) { ops.append(.create(Self.archived(path, archivo: archivo, nota: "\(v.etiqueta) \(stamp)"), contents: d)) }
            }
            ops.append(replace)
        } else {
            for v in others {
                if let d = registry.datos(de: v, root: root) { ops.append(.create(Self.archived(path, archivo: archivo, nota: "\(v.etiqueta) \(stamp)"), contents: d)) }
            }
        }
        let result = try await writer.apply(WritePlan(autor: autor, descripcion: "Resolver el conflicto de iCloud de «\(path.stem)»", ops: ops))
        // Si llegó otra versión mientras tanto, no se marca nada: la tarjeta sigue (vuelve a mirarse).
        guard sinCambios() else { return result }
        try provider.markResolved(path.url(in: root))
        try registry.marcarResuelto(id, como: version.map { "version-\($0)" } ?? "actual")
        return result
    }

    /// `Archivo/Conflictos/<misma carpeta>/<nombre> (<nota>).<ext>`.
    static func archived(_ path: VaultPath, archivo: String, nota: String) -> VaultPath {
        let ext = path.ext.isEmpty ? "" : "." + (path.name.split(separator: ".").last.map(String.init) ?? "")
        return VaultPath(components: VaultPath(archivo).components + ["Conflictos"] + (path.parent?.components ?? [])
                         + ["\(path.stem) (\(nota))\(ext)"])
    }

    /// Carpeta de archivo de la empresa (`Archivo`, o la que diga `.tls/layout.json`).
    private var archivo: String {
        UbiquityInspector.withoutMaterializing { VaultLayout.load(root: writer.root).layout.archivo }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f.string(from: date)
    }
}
