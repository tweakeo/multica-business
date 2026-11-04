import Dispatch
import Foundation

/// El único que escribe en la carpeta de una empresa (PLAN §4.8).
///
/// Es un actor con su propia cola serie como ejecutor: cada plan se aplica entero en esa cola,
/// sin ningún `await` entre leer las huellas y `replaceItemAt`. Cada plan:
/// 1. calcula los pasos en memoria (si algo no cuadra, no escribe nada);
/// 2. guarda la copia previa de lo que cambia en `<estado>/copias/AAAA-MM-DD/<plan>/` y los bytes nuevos;
/// 3. apunta en `diario.jsonl` el plan con `base_hashes` y `hash_resultante` (pendiente);
/// 4. escribe coordinado (temporal → `F_FULLFSYNC` → `replaceItemAt`), vuelve a leer y comprueba;
///    si algo falla, deja todo como estaba;
/// 5. marca `hecho`, actualiza `hash_app` y avisa para reindexar (fuera de la sección crítica).
///
/// Al abrir revisa lo pendiente: si el fichero ya tiene la huella resultante, el paso estaba
/// hecho; si tiene la de antes, lo aplica; si no tiene ninguna, crea una tarjeta de conflicto.
///
/// Escribe en copias y en la demo; en la carpeta real, solo durante «Pasar a mi carpeta real» y después, con el relevo hecho
/// (`WritePolicy`). Si no, `open` lanza `WriteError.carpetaReal`.
public actor VaultWriter {
    public struct Options: Sendable {
        /// Estado de la carpeta (diario, copias, conflictos). Por defecto `AppLocations.vaultState(id)`.
        public var stateDirectory: URL?
        /// Para los cerrojos (`locks/`) y la identidad de la instalación. Por defecto `AppLocations.appSupport`.
        public var appSupport: URL?
        /// Nombre y versión de la app para `.tls/escritor.json`.
        public var app: String
        /// Reloj (la demo lo fija).
        public var now: @Sendable () -> Date
        /// Días que se guardan las copias previas.
        public var diasDeCopias: Int
        /// F6 · integración: **solo `AplicadorDeRelevo`** (y su «Deshacer»). Deja escribir la carpeta real mientras dura
        /// el relevo, ya confirmado y con el cerrojo del escritor anterior tomado (`WritePolicy`).
        public var relevo: Bool
        /// F6 · integración: dónde mirar la marca del relevo (`relevo.json`) de una real. Por defecto, `appSupport`.
        public var registroDeRelevo: URL?

        public init(stateDirectory: URL? = nil, appSupport: URL? = nil, app: String = VaultWriter.defaultAppName,
                    now: @escaping @Sendable () -> Date = { Date() }, diasDeCopias: Int = 30, relevo: Bool = false,
                    registroDeRelevo: URL? = nil) {
            self.stateDirectory = stateDirectory; self.appSupport = appSupport; self.app = app
            self.now = now; self.diasDeCopias = diasDeCopias; self.relevo = relevo; self.registroDeRelevo = registroDeRelevo
        }
    }

    public static var defaultAppName: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "The Last System " + (v ?? "0.2")
    }

    /// Lo que encontró la recuperación al abrir.
    public struct RecoveryReport: Sendable {
        /// Planes que ya estaban escritos del todo.
        public var completados: Int = 0
        /// Planes que se terminaron de aplicar al abrir.
        public var aplicados: Int = 0
        /// Planes de los que no quedaba nada que hacer ni con qué hacerlo.
        public var abandonados: Int = 0
        public var conflictos: [ConflictRecord] = []
    }

    public nonisolated let entry: VaultEntry
    public nonisolated let root: URL
    public nonisolated let stateDirectory: URL
    /// Para que la vigilancia distinga lo que escribe la app de lo que cambia fuera.
    public nonisolated let recentWrites = RecentWrites()
    /// Tarjetas de conflicto y duplicados de esta carpeta.
    public nonisolated let conflicts: ConflictRegistry

    private nonisolated let queue: DispatchSerialQueue
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let appSupport: URL
    private let app: String
    private let now: @Sendable () -> Date
    private let diasDeCopias: Int
    /// F6 · integración: escritor del relevo (puede escribir la real mientras dura) y dónde está su marca.
    private let relevo: Bool
    private let registroDeRelevo: URL
    private let journal: WriteJournal
    private var claim: WriterClaim?
    /// Huella de cada fichero tal como lo dejó la app la última vez.
    private var hashApp: [VaultPath: String] = [:]
    private var onApplied: (@Sendable ([VaultPath]) -> Void)?
    /// Pruebas: punto donde simular que el proceso muere.
    private var fault: FaultPoint?
    /// Tras una muerte simulada, este escritor ya no hace nada (como un proceso que no existe).
    private var dead = false
    /// Pruebas: se llama antes de cada paso físico (para simular un cambio de fuera a mitad).
    private var beforeStep: (@Sendable (Int) -> Void)?

    enum FaultPoint: Sendable, Equatable {
        /// Tras escribir el temporal del paso n, antes de sustituir el fichero.
        case trasTemporal(Int)
        /// Tras completar el paso n.
        case trasPaso(Int)
        /// Con todo escrito, antes de marcar el plan como hecho.
        case antesDeHecho
    }

    private init(entry: VaultEntry, root: URL, options: Options) {
        self.entry = entry
        self.root = root.standardizedFileURL
        let state = options.stateDirectory ?? AppLocations.vaultState(entry.id)
        self.stateDirectory = state
        self.appSupport = options.appSupport ?? AppLocations.appSupport
        self.app = options.app
        self.now = options.now
        self.diasDeCopias = options.diasDeCopias
        self.relevo = options.relevo
        self.registroDeRelevo = options.registroDeRelevo ?? options.appSupport ?? AppLocations.appSupport
        self.journal = WriteJournal(directory: state)
        self.conflicts = ConflictRegistry(stateDirectory: state)
        self.queue = DispatchSerialQueue(label: "es.thelast.system.escritor")
    }

    /// Abre el escritor de una carpeta y termina lo que quedara a medias.
    /// Lanza si la carpeta es la real, está en solo lectura o el estado iría dentro de ella.
    public static func open(entry: VaultEntry, root: URL, options: Options = Options()) async throws -> VaultWriter {
        try WritePolicy.comprobar(entry, root: root, appSupport: options.registroDeRelevo ?? options.appSupport ?? AppLocations.appSupport,
                                  relevo: options.relevo)
        let state = options.stateDirectory ?? AppLocations.vaultState(entry.id)
        if VaultService.isForbiddenStateDirectory(state, realRoot: PathGuard.realPath(root) ?? root.path) {
            throw VaultServiceError.estadoNoPermitido(state.path)
        }
        let writer = VaultWriter(entry: entry, root: root, options: options)
        try await writer.start()
        return writer
    }

    private func start() throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        lastRecovery = try recover()
        purgeOldCopies()
    }

    /// Lo que encontró la recuperación al abrir (sus conflictos ya están en `conflicts`).
    public private(set) var lastRecovery = RecoveryReport()

    /// Avisa con las rutas cambiadas tras cada plan (para reindexar). Se llama en la cola del escritor.
    public func setOnApplied(_ handler: (@Sendable ([VaultPath]) -> Void)?) {
        onApplied = handler
    }

    /// Huella con la que la app dejó un fichero (`nil` si la app no lo ha escrito).
    public func appHash(_ path: VaultPath) -> String? { hashApp[path] }

    func setFault(_ f: FaultPoint?) { fault = f }

    func setBeforeStep(_ h: (@Sendable (Int) -> Void)?) { beforeStep = h }

    private func checkpoint(_ f: FaultPoint) throws {
        if fault == f { throw WriteError.interrumpido }
    }

    /// `WritePolicy` en cada plan (la real, solo durante el relevo o con el relevo hecho: «Deshacer» lo cierra).
    private func comprobarPolitica() throws {
        try WritePolicy.comprobar(entry, root: root, appSupport: registroDeRelevo, relevo: relevo)
    }

    private func checkAlive() throws {
        if dead { throw WriteError.interrumpido }
    }

    /// Suelta la carpeta (el cerrojo) para que otro proceso pueda escribirla.
    public func close() {
        claim?.release()
        claim = nil
    }

    // MARK: Escritor único

    private func ensureClaim() throws {
        if claim != nil { return }
        let installation = VaultRegistry(directory: appSupport).installationID()
        claim = try WriterClaim.acquire(root: root, entry: entry, installation: installation,
                                        appSupport: appSupport, app: app, now: now())
    }

    private func currentLayout() -> VaultLayout {
        UbiquityInspector.withoutMaterializing { VaultLayout.load(root: root).layout }
    }

    /// Lo excluido de la copia no se escribe. `Archivo/` no se copia por tamaño (no por privado):
    /// retirar, deshacer y apartar duplicados o conflictos siguen escribiendo ahí.
    private func exclusionRules(_ layout: VaultLayout) -> ExclusionRules {
        let archivo = TextFolding.pathKey(layout.archivo)
        return ExclusionRules(paths: entry.exclusionesCopia.map { VaultPath($0) }
            .filter { TextFolding.pathKey($0.raw) != archivo })
    }

    /// Las reglas de rutas de `PlanCompiler` (enlaces simbólicos, ocultos, excluido y, para un
    /// asistente, lo privado) para lo que no pasa por él: deshacer y recuperar.
    private func reglasDeRuta(_ autor: Autor) -> PlanCompiler {
        let layout = currentLayout()
        return PlanCompiler(root: root, layout: layout, rules: exclusionRules(layout), autor: autor, hashApp: hashApp)
    }

    // MARK: Aplicar

    /// Aplica un plan entero o nada. Solo se llama desde `CommandBus`.
    func apply(_ plan: WritePlan) throws -> WriteResult {
        try checkAlive()
        try comprobarPolitica()
        let layout = currentLayout()
        var compiler = PlanCompiler(root: root, layout: layout, rules: exclusionRules(layout),
                                    autor: plan.autor, hashApp: hashApp)
        let outcome = try UbiquityInspector.withoutMaterializing { try compiler.compile(plan.ops) }
        switch outcome {
        case .conflict(let path, let mine, let theirs):
            let record = try registerEditConflict(path: path, mine: mine, theirs: theirs, plan: plan.id)
            return WriteResult(planID: plan.id, estado: .conflicto(record), cambiadas: [], creadas: [], movidas: [], hashes: [:])
        case .steps(let steps, let created, let moved):
            guard !steps.isEmpty else {
                return WriteResult(planID: plan.id, estado: .sinCambios, cambiadas: [], creadas: [], movidas: [], hashes: [:])
            }
            try ensureClaim()
            return try execute(steps, planID: plan.id, autor: plan.autor, descripcion: plan.descripcion,
                               ops: plan.ops.map(\.resumen), deshace: nil, created: created, moved: moved)
        }
    }

    private func execute(_ steps: [PhysicalStep], planID: UUID, autor: Autor, descripcion: String, ops: [String],
                         deshace: UUID?, created: [VaultPath], moved: [Movimiento]) throws -> WriteResult {
        let date = now()
        let id = planID.uuidString.lowercased()
        let copiesRel = "copias/\(LocalDate(date: date))/\(id)"
        let copiesDir = stateDirectory.appendingPathComponent(copiesRel, isDirectory: true)

        // 1. Copia previa (en disco antes de tocar nada) de todo lo que se va a cambiar. Lo que solo se mueve o se
        //    renombra no la necesita: su contenido no cambia y se deshace moviéndolo de vuelta, comprobado por su huella
        //    (F3: así una importación con muchos PDF no dobla el espacio durante 30 días).
        for step in steps where step.kind == .escribir {
            guard let data = step.originalData, let origin = step.originPath else { continue }
            let url = origin.url(in: copiesDir)
            if !FileManager.default.fileExists(atPath: url.path) { try AtomicFiles.writeDurable(data, to: url) }
        }

        // 2. Bytes nuevos a la espera y 3. diario.
        var jsteps: [JournalStep] = []
        var baseHashes: [String: String] = [:]
        var resultHashes: [String: String] = [:]
        for (n, step) in steps.enumerated() {
            var js = JournalStep(accion: step.kind.rawValue, ruta: step.path.raw, destino: step.destination?.raw,
                                 base: step.base.journalText, resultante: step.resultHash)
            if let data = step.data { js.contenido = try journal.stage(data, plan: planID, step: n) }
            if step.kind == .renombrar {
                js.intermedio = (step.path.parent ?? .root).appending(".tls-renombrar-\(id.prefix(8))-\(n)").raw
            }
            jsteps.append(js)
            if baseHashes[step.path.raw] == nil { baseHashes[step.path.raw] = step.base.journalText ?? "" }
            switch step.kind {
            case .escribir, .crear:
                resultHashes[step.path.raw] = step.resultHash ?? ""
            case .mover, .renombrar:
                if let d = step.destination {
                    if baseHashes[d.raw] == nil { baseHashes[d.raw] = "" }
                    resultHashes[step.path.raw] = ""
                    resultHashes[d.raw] = step.base.journalText ?? ""
                }
            }
        }
        // Carpetas que el plan va a crear (deshacer las quita si quedan vacías).
        var nuevas: [String] = []
        for step in steps where step.kind == .crear || step.kind == .mover {
            var p = (step.kind == .crear ? step.path : step.destination)?.parent
            while let a = p, !a.isRoot, AtomicFiles.state(a.url(in: root)) == .absent {
                if !nuevas.contains(a.raw) { nuevas.append(a.raw) }
                p = a.parent
            }
        }
        let jplan = JournalPlan(id: id, fecha: WriteJournal.stamp(date), autor: autor.etiqueta, descripcion: descripcion,
                                ops: ops, pasos: jsteps, base_hashes: baseHashes, hash_resultante: resultHashes,
                                inverso: Self.inverse(of: steps, journalSteps: jsteps, copiesRel: copiesRel),
                                deshace: deshace?.uuidString.lowercased(), copias: copiesRel,
                                carpetas: nuevas.isEmpty ? nil : nuevas)
        try journal.append(jplan)

        // 4. Escritura, paso a paso.
        var done: [Int] = []
        do {
            try UbiquityInspector.withoutMaterializing {
                for (n, step) in steps.enumerated() {
                    beforeStep?(n)
                    try perform(step, journalStep: jsteps[n], index: n)
                    done.append(n)
                    try verify(step)
                    try checkpoint(.trasPaso(n))
                }
                try checkpoint(.antesDeHecho)
            }
        } catch WriteError.interrumpido {
            // Muerte simulada: nada de limpiar ni de revertir (lo hará la recuperación). Como en un
            // `kill -9`, el sistema suelta el cerrojo.
            dead = true
            claim?.release()
            claim = nil
            throw WriteError.interrumpido
        } catch {
            let failed = UbiquityInspector.withoutMaterializing { revert(done, steps: steps, journalSteps: jsteps, planID: planID) }
            try? journal.mark(planID, failed.isEmpty ? "revertido" : "conflicto", detalle: String(describing: error), now: now())
            journal.removeStaging(planID)
            if case WriteError.cambioExterno(let p) = error, deshace != nil { throw WriteError.noSePuedeDeshacer(p) }
            throw error
        }

        // 5. Hecho.
        try journal.mark(planID, "hecho", now: now())
        journal.removeStaging(planID)
        for js in jsteps { Self.apply(js, to: &hashApp) }
        var changed: [VaultPath] = []
        var hashes: [VaultPath: String] = [:]
        for step in steps {
            for p in step.touched where !changed.contains(p) { changed.append(p) }
            if let h = step.resultHash, step.kind == .escribir || step.kind == .crear { hashes[step.path] = h }
        }
        changed.sort()
        onApplied?(changed)
        return WriteResult(planID: planID, estado: .hecho, cambiadas: changed, creadas: created, movidas: moved, hashes: hashes)
    }

    /// Un paso físico (con su comprobación de huella justo antes).
    private func perform(_ step: PhysicalStep, journalStep js: JournalStep, index n: Int) throws {
        let url = step.path.url(in: root)
        let fault = self.fault
        let afterTemporary: AtomicFiles.Checkpoint = {
            if fault == .trasTemporal(n) { throw WriteError.interrumpido }
        }
        switch step.kind {
        case .escribir:
            guard let data = step.data, case .file(let base) = step.base else { return }
            recentWrites.register(step.path, hash: step.resultHash, now: now())
            try AtomicFiles.replace(url, with: data, expected: base, display: step.path.raw, afterTemporary: afterTemporary)
        case .crear:
            guard let data = step.data else { return }
            recentWrites.register(step.path, hash: step.resultHash, now: now())
            try AtomicFiles.create(url, with: data, display: step.path.raw, afterTemporary: afterTemporary)
        case .mover:
            guard let dst = step.destination else { return }
            recentWrites.register(step.path, hash: nil, now: now())
            recentWrites.register(dst, hash: step.base.journalText, now: now())
            try AtomicFiles.move(url, to: dst.url(in: root), expected: step.base, display: step.path.raw)
        case .renombrar:
            guard let dst = step.destination, let mid = js.intermedio else { return }
            recentWrites.register(dst, hash: step.base.journalText, now: now())
            try AtomicFiles.renameCase(url, to: dst.url(in: root), intermediate: VaultPath(mid).url(in: root),
                                       expected: step.base, display: step.path.raw)
        }
    }

    /// Vuelve a leer lo escrito y comprueba que es exactamente lo previsto y se puede leer.
    private func verify(_ step: PhysicalStep) throws {
        switch step.kind {
        case .escribir, .crear:
            let url = step.path.url(in: root)
            guard let data = try? Data(contentsOf: url, options: [.uncached]),
                  ContentHash.of(data) == step.resultHash else { throw WriteError.verificacionFallida(step.path.raw) }
            try PlanCompiler.validate(step.path, data: data, previous: step.originalData)
        case .mover, .renombrar:
            guard let dst = step.destination, AtomicFiles.state(dst.url(in: root)) == step.base else {
                throw WriteError.verificacionFallida(step.path.raw)
            }
        }
    }

    /// Deshace los pasos ya hechos (en orden inverso). Devuelve los que no se pudieron deshacer.
    private func revert(_ done: [Int], steps: [PhysicalStep], journalSteps: [JournalStep], planID: UUID) -> [VaultPath] {
        var failed: [VaultPath] = []
        let backup = stateDirectory.appendingPathComponent("copias/\(LocalDate(date: now()))/\(planID.uuidString.lowercased())/revertidos",
                                                           isDirectory: true)
        for n in done.reversed() {
            let step = steps[n]
            let url = step.path.url(in: root)
            do {
                switch step.kind {
                case .escribir:
                    // Solo si sigue como lo dejó este paso: si alguien lo cambió después, no se pisa.
                    guard let original = step.originalData, let resultado = step.resultHash else {
                        throw WriteError.cambioExterno(step.path.raw)
                    }
                    recentWrites.register(step.path, hash: ContentHash.of(original), now: now())
                    try AtomicFiles.replace(url, with: original, expected: resultado, display: step.path.raw) {}
                case .crear:
                    // Lo recién creado sale de la carpeta a la copia de la app (no se borra).
                    guard case .file(let h)? = AtomicFiles.state(url), h == step.resultHash else {
                        throw WriteError.cambioExterno(step.path.raw)
                    }
                    let dest = step.path.url(in: backup)
                    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    recentWrites.register(step.path, hash: nil, now: now())
                    try FileManager.default.moveItem(at: url, to: dest)
                case .mover:
                    guard let dst = step.destination else { continue }
                    recentWrites.register(step.path, hash: step.base.journalText, now: now())
                    try AtomicFiles.move(dst.url(in: root), to: url, expected: step.base, display: dst.raw)
                case .renombrar:
                    guard let dst = step.destination else { continue }
                    let mid = (dst.parent ?? .root).appending(".tls-renombrar-vuelta-\(UUID().uuidString.prefix(8))")
                    try AtomicFiles.renameCase(dst.url(in: root), to: url, intermediate: mid.url(in: root),
                                               expected: step.base, display: dst.raw)
                }
            } catch {
                failed.append(step.path)
                let record = ConflictRecord(tipo: .recuperacion, ruta: step.path, fecha: now(),
                                            titulo: "No pude dejar «\(step.path.stem)» como estaba",
                                            detalle: "Un cambio no se pudo completar y, al volver atrás, este fichero ya no estaba como lo dejé. Revisa las dos versiones.",
                                            versiones: [ConflictVersion(etiqueta: "La de ahora", ubicacion: .carpeta(step.path), hash: nil)],
                                            plan: planID)
                _ = try? conflicts.registrar(record)
            }
        }
        return failed
    }

    /// Pasos que deshacen un plan, en orden inverso.
    static func inverse(of steps: [PhysicalStep], journalSteps: [JournalStep], copiesRel: String) -> [JournalStep] {
        var out: [JournalStep] = []
        for (step, js) in zip(steps, journalSteps).reversed() {
            switch step.kind {
            case .escribir:
                out.append(JournalStep(accion: "escribir", ruta: js.ruta, base: js.resultante, resultante: js.base,
                                       contenido: step.originPath.map { copiesRel + "/" + $0.raw }))
            case .crear:
                out.append(JournalStep(accion: "retirar", ruta: js.ruta, base: js.resultante, resultante: js.resultante))
            case .mover:
                out.append(JournalStep(accion: "mover", ruta: js.destino ?? js.ruta, destino: js.ruta,
                                       base: js.base, resultante: js.base))
            case .renombrar:
                out.append(JournalStep(accion: "renombrar", ruta: js.destino ?? js.ruta, destino: js.ruta,
                                       base: js.base, resultante: js.base))
            }
        }
        return out
    }

    /// Efecto de un paso hecho sobre `hash_app`.
    static func apply(_ js: JournalStep, to map: inout [VaultPath: String]) {
        switch js.accion {
        case "escribir", "crear":
            if let h = js.resultante { map[VaultPath(js.ruta)] = h }
        case "mover", "renombrar", "retirar":
            guard let d = js.destino else { return }
            let src = VaultPath(js.ruta), dst = VaultPath(d)
            if js.base == "carpeta" {
                for (p, h) in map where PlanCompiler.isUnder(p, src) {
                    map.removeValue(forKey: p)
                    map[PlanCompiler.rebase(p, from: src, to: dst)] = h
                }
            } else if let h = map.removeValue(forKey: src) {
                map[dst] = h
            }
        default:
            break
        }
    }

    // MARK: Deshacer

    /// El último plan que se puede deshacer (el más reciente hecho y no deshecho).
    public func lastUndoable() -> UndoInfo? {
        guard let e = undoCandidate(journal.read()) else { return nil }
        return UndoInfo(planID: UUID(uuidString: e.plan.id) ?? UUID(), descripcion: e.plan.descripcion,
                        autor: Autor(etiqueta: e.plan.autor),
                        fecha: WriteJournal.date(e.plan.fecha) ?? Date())
    }

    private func undoCandidate(_ c: WriteJournal.Contents) -> WriteJournal.Entry? {
        let undone = Set(c.entries.filter { $0.estado == "hecho" }.compactMap(\.plan.deshace))
        return c.entries.last { $0.estado == "hecho" && $0.plan.deshace == nil && !undone.contains($0.plan.id) }
    }

    /// Deshace el último plan: deja cada fichero como estaba, si nadie lo ha cambiado después.
    /// Lo que el plan creó se retira a `Archivo/` (nunca se borra).
    func undoLast(autor: Autor) throws -> WriteResult {
        try checkAlive()
        try comprobarPolitica()
        guard let target = undoCandidate(journal.read()) else { throw WriteError.nadaQueDeshacer }
        // Un asistente solo deshace lo suyo: ni texto de una persona ni lo de otro asistente.
        if case .agente = autor, Autor(etiqueta: target.plan.autor) != autor {
            throw WriteError.noPermitidoAsistente(target.plan.inverso.first?.ruta ?? target.plan.descripcion)
        }
        let layout = currentLayout()
        let guardia = reglasDeRuta(autor)
        var steps: [PhysicalStep] = []
        var virtual: [String: DiskExpectation] = [:]
        func current(_ p: VaultPath) -> DiskExpectation? {
            virtual[PlanCompiler.key(p)] ?? AtomicFiles.state(p.url(in: root))
        }
        try UbiquityInspector.withoutMaterializing {
            for inv in target.plan.inverso {
                let path = VaultPath(inv.ruta)
                try guardia.checkAllowed(path)
                let base = DiskExpectation(journalText: inv.base)
                guard current(path) == base else { throw WriteError.noSePuedeDeshacer(path.raw) }
                let originalData: Data? = {
                    guard case .file = base, virtual[PlanCompiler.key(path)] == nil else { return nil }
                    return try? Data(contentsOf: path.url(in: root))
                }()
                switch inv.accion {
                case "escribir":
                    guard let rel = inv.contenido,
                          let data = FileManager.default.contents(atPath: stateDirectory.appendingPathComponent(rel).path) else {
                        throw WriteError.noSePuedeDeshacer(path.raw)
                    }
                    steps.append(PhysicalStep(kind: .escribir, path: path, base: base, data: data,
                                              originalData: originalData, originPath: path))
                    virtual[PlanCompiler.key(path)] = .file(ContentHash.of(data))
                case "mover", "renombrar":
                    guard let d = inv.destino else { continue }
                    let dst = VaultPath(d)
                    try guardia.checkAllowed(dst)
                    let isCase = PlanCompiler.key(path) == PlanCompiler.key(dst)
                    if !isCase { guard current(dst) == .absent else { throw WriteError.noSePuedeDeshacer(dst.raw) } }
                    steps.append(PhysicalStep(kind: isCase ? .renombrar : .mover, path: path, destination: dst, base: base,
                                              originalData: originalData, originPath: path))
                    virtual[PlanCompiler.key(path)] = .absent
                    virtual[PlanCompiler.key(dst)] = base
                case "retirar":
                    let archivo = VaultPath(layout.archivo)
                    // Un ajuste creado por la app (`.tls/vistas/…`) se retira a una carpeta visible del Archivo:
                    // dentro de `Archivo/` no puede haber carpetas ocultas.
                    let visibles = Self.componentesVisibles(path)
                    var dst = VaultPath(components: archivo.components + visibles)
                    var n = 2
                    while current(dst) != .absent {
                        let ext = path.ext.isEmpty ? "" : "." + (path.name.split(separator: ".").last.map(String.init) ?? "")
                        dst = VaultPath(components: archivo.components + visibles.dropLast() + ["\(path.stem) (\(n))\(ext)"])
                        n += 1
                    }
                    try guardia.checkAllowed(dst)
                    steps.append(PhysicalStep(kind: .mover, path: path, destination: dst, base: base,
                                              originalData: originalData, originPath: path))
                    virtual[PlanCompiler.key(path)] = .absent
                    virtual[PlanCompiler.key(dst)] = base
                default:
                    throw WriteError.noSePuedeDeshacer(path.raw)
                }
            }
        }
        guard !steps.isEmpty else { throw WriteError.nadaQueDeshacer }
        try ensureClaim()
        let moved = steps.compactMap { s in s.destination.map { Movimiento(de: s.path, a: $0) } }
        let result = try execute(steps, planID: UUID(), autor: autor, descripcion: "Deshacer: " + target.plan.descripcion,
                                 ops: ["deshacer \(target.plan.id)"], deshace: UUID(uuidString: target.plan.id),
                                 created: [], moved: moved)
        // Las carpetas que creó el plan y han quedado vacías (`rmdir` no quita nada que tenga dentro).
        let carpetas = (target.plan.carpetas ?? []).map(VaultPath.init).sorted { $0.components.count > $1.components.count }
        for d in carpetas where (try? guardia.checkAllowed(d)) != nil && AtomicFiles.state(d.url(in: root)) == .directory {
            recentWrites.register(d, hash: nil, now: now())
            _ = d.url(in: root).withUnsafeFileSystemRepresentation { rmdir($0!) }
        }
        return result
    }

    /// Componentes de una ruta para guardarla en `Archivo/`, sin carpetas ocultas: `.tls` → «Ajustes de la app»,
    /// `.obsidian` → «Ajustes de Obsidian» (el resto, sin el punto).
    static func componentesVisibles(_ p: VaultPath) -> [String] {
        p.components.map { c in
            guard c.hasPrefix(".") else { return c }
            switch c {
            case ".tls": return "Ajustes de la app"
            case ".obsidian": return "Ajustes de Obsidian"
            default: return String(c.drop { $0 == "." })
            }
        }
    }

    // MARK: Recuperación

    /// Termina lo que quedó a medias (al abrir). Lo hecho se marca; lo que estaba como antes se
    /// aplica; lo que no está ni como antes ni como debía quedar va a una tarjeta de conflicto.
    @discardableResult
    public func recover() throws -> RecoveryReport {
        let contents = journal.read()
        var report = RecoveryReport()
        // `hash_app` sale del diario: la foto de la última compactación y los planes hechos.
        var map: [VaultPath: String] = [:]
        for (k, v) in contents.snapshot { map[VaultPath(k)] = v }
        for e in contents.entries where e.estado == "hecho" {
            for js in e.plan.pasos { Self.apply(js, to: &map) }
        }
        hashApp = map
        let pending = contents.entries.filter { $0.estado == "pendiente" }
        if !pending.isEmpty {
            try comprobarPolitica()
            try ensureClaim()
        }
        for e in pending {
            let outcome = try UbiquityInspector.withoutMaterializing { try recoverPlan(e.plan) }
            switch outcome {
            case .completado: report.completados += 1
            case .aplicado: report.aplicados += 1
            case .abandonado: report.abandonados += 1
            case .conflicto(let records): report.conflictos += records
            }
        }
        cleanStaging(keep: [])
        if contents.lineCount > 4000 {
            let keep = Array(journal.read().entries.suffix(200))
            var snapshot: [String: String] = [:]
            for (k, v) in hashApp { snapshot[k.raw] = v }
            try? journal.compact(snapshot: snapshot, keep: keep, now: now())
        }
        return report
    }

    private enum PlanRecovery {
        case completado, aplicado, abandonado
        case conflicto([ConflictRecord])
    }

    private enum StepState { case hecho, pendiente, otro }

    private func evaluate(_ js: JournalStep) -> StepState {
        let path = VaultPath(js.ruta)
        let url = path.url(in: root)
        let base = DiskExpectation(journalText: js.base)
        switch js.accion {
        case "escribir", "crear":
            let now = AtomicFiles.state(url)
            if let r = js.resultante, now == .file(r) { return .hecho }
            if now == base { return .pendiente }
            return .otro
        case "mover":
            // Hecho si el origen ya no está y el destino sí (su contenido lo comprueban los pasos
            // siguientes, que pueden haberlo cambiado después de moverlo).
            guard let d = js.destino else { return .otro }
            let src = AtomicFiles.state(url), dst = AtomicFiles.state(VaultPath(d).url(in: root))
            if src == .absent, let dst, dst != .absent, Self.sameKind(dst, base) { return .hecho }
            if src == base, dst == .absent { return .pendiente }
            return .otro
        case "renombrar":
            guard let d = js.destino else { return .otro }
            let dstURL = VaultPath(d).url(in: root)
            if let mid = js.intermedio, AtomicFiles.existsExactly(VaultPath(mid).url(in: root)) { return .pendiente }
            if AtomicFiles.existsExactly(dstURL), !AtomicFiles.existsExactly(url),
               let dst = AtomicFiles.state(dstURL), Self.sameKind(dst, base) { return .hecho }
            if AtomicFiles.existsExactly(url), AtomicFiles.state(url) == base { return .pendiente }
            return .otro
        default:
            return .otro
        }
    }

    static func sameKind(_ a: DiskExpectation, _ b: DiskExpectation) -> Bool {
        switch (a, b) {
        case (.file, .file), (.directory, .directory), (.absent, .absent): true
        default: false
        }
    }

    private func recoverPlan(_ plan: JournalPlan) throws -> PlanRecovery {
        guard let planID = UUID(uuidString: plan.id) else { return .abandonado }
        // Si el primer paso no está hecho, el plan no llegó a empezar: se aplica como uno nuevo,
        // todo o nada (si un paso no cuadra, se vuelve atrás lo aplicado y queda la tarjeta).
        if let first = plan.pasos.first, evaluate(first) != .hecho {
            return try replay(plan, planID: planID)
        }
        let guardia = reglasDeRuta(Autor(etiqueta: plan.autor))
        var applied = 0
        var missing = 0
        var records: [ConflictRecord] = []
        for (n, js) in plan.pasos.enumerated() {
            switch evaluate(js) {
            case .hecho:
                Self.apply(js, to: &hashApp)
            case .pendiente:
                let data = js.contenido.flatMap { FileManager.default.contents(atPath: stateDirectory.appendingPathComponent($0).path) }
                if (js.accion == "escribir" || js.accion == "crear") && data == nil {
                    // Sin los bytes no se puede terminar: el fichero sigue como estaba.
                    missing += 1
                    continue
                }
                let step = recoveryStep(js, data: data)
                do {
                    try guardia.checkAllowed(step.path)
                    if let d = step.destination { try guardia.checkAllowed(d) }
                    try perform(step, journalStep: js, index: n)
                    try verify(step)
                    Self.apply(js, to: &hashApp)
                    applied += 1
                } catch {
                    records.append(try recoveryConflict(js, plan: planID, intended: data))
                }
            case .otro:
                let data = js.contenido.flatMap { FileManager.default.contents(atPath: stateDirectory.appendingPathComponent($0).path) }
                records.append(try recoveryConflict(js, plan: planID, intended: data))
            }
        }
        if !records.isEmpty {
            try journal.mark(planID, "conflicto", now: now())
            journal.removeStaging(planID)
            return .conflicto(records)
        }
        if missing > 0 {
            // Faltan los bytes de algún paso: no se puede terminar; lo hecho queda (con su copia previa).
            try journal.mark(planID, "abandonado", now: now())
            journal.removeStaging(planID)
            return .abandonado
        }
        try journal.mark(planID, "hecho", now: now())
        journal.removeStaging(planID)
        let paths = plan.pasos.flatMap { [VaultPath($0.ruta)] + ($0.destino.map { [VaultPath($0)] } ?? []) }
        if applied > 0 { onApplied?(Array(Set(paths)).sorted()) }
        return applied == 0 ? .completado : .aplicado
    }

    /// Paso físico de un paso del diario que está como antes: con los bytes de antes, para validar
    /// igual que al escribir (unas propiedades que ya eran ilegibles no son un fallo).
    private func recoveryStep(_ js: JournalStep, data: Data?) -> PhysicalStep {
        let path = VaultPath(js.ruta)
        let original = js.accion == "escribir" ? try? Data(contentsOf: path.url(in: root), options: [.uncached]) : nil
        return PhysicalStep(kind: PhysicalStep.Kind(rawValue: js.accion) ?? .escribir, path: path,
                            destination: js.destino.map(VaultPath.init), base: DiskExpectation(journalText: js.base),
                            data: data, originalData: original)
    }

    /// Un plan que no llegó a empezar: todo o nada, como al escribirlo.
    private func replay(_ plan: JournalPlan, planID: UUID) throws -> PlanRecovery {
        let guardia = reglasDeRuta(Autor(etiqueta: plan.autor))
        var steps: [PhysicalStep] = []
        var done: [Int] = []
        for (n, js) in plan.pasos.enumerated() {
            let data = js.contenido.flatMap { FileManager.default.contents(atPath: stateDirectory.appendingPathComponent($0).path) }
            let step = recoveryStep(js, data: data)
            steps.append(step)
            let sinBytes = (js.accion == "escribir" || js.accion == "crear") && data == nil
            do {
                guard !sinBytes, evaluate(js) == .pendiente else { throw WriteError.cambioExterno(js.ruta) }
                try guardia.checkAllowed(step.path)
                if let d = step.destination { try guardia.checkAllowed(d) }
                try perform(step, journalStep: js, index: n)
                done.append(n)
                try verify(step)
            } catch {
                let failed = revert(done, steps: steps, journalSteps: plan.pasos, planID: planID)
                if sinBytes && failed.isEmpty {
                    try journal.mark(planID, "abandonado", now: now())
                    journal.removeStaging(planID)
                    return .abandonado
                }
                let record = try recoveryConflict(js, plan: planID, intended: data)
                try journal.mark(planID, "conflicto", now: now())
                journal.removeStaging(planID)
                return .conflicto([record])
            }
        }
        try journal.mark(planID, "hecho", now: now())
        journal.removeStaging(planID)
        for js in plan.pasos { Self.apply(js, to: &hashApp) }
        onApplied?(Array(Set(steps.flatMap(\.touched))).sorted())
        return .aplicado
    }

    private func recoveryConflict(_ js: JournalStep, plan: UUID, intended: Data?) throws -> ConflictRecord {
        let path = VaultPath(js.ruta)
        let id = UUID()
        var versiones = [ConflictVersion(etiqueta: "La de ahora", ubicacion: .carpeta(path), hash: nil)]
        if let intended {
            let loc = try conflicts.guardarVersion(intended, conflicto: id,
                                                   nombre: "lo-que-iba-a-guardar" + (path.ext.isEmpty ? "" : "." + path.ext))
            versiones.append(ConflictVersion(etiqueta: "Lo que iba a guardar la app", ubicacion: loc, hash: ContentHash.of(intended)))
        }
        let record = ConflictRecord(id: id, tipo: .recuperacion, ruta: path, fecha: now(),
                                    titulo: "«\(path.stem)» cambió mientras la app la guardaba",
                                    detalle: "La app se cerró a mitad de un cambio y, al volver, este fichero no estaba ni como antes ni como debía quedar. No lo he tocado: elige qué versión se queda.",
                                    versiones: versiones, plan: plan)
        return try conflicts.registrar(record)
    }

    /// Quita los bytes a la espera de planes que ya no están pendientes.
    private func cleanStaging(keep: Set<String>) {
        let pending = Set(journal.read().entries.filter { $0.estado == "pendiente" }.map(\.plan.id))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: journal.stagingRoot.path) else { return }
        for n in names where !pending.contains(n) && !keep.contains(n) {
            try? FileManager.default.removeItem(at: journal.stagingRoot.appendingPathComponent(n))
        }
    }

    /// Las copias previas se guardan `diasDeCopias` días (son de la app, fuera de la carpeta).
    private func purgeOldCopies() {
        let dir = stateDirectory.appendingPathComponent("copias", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let limit = LocalDate(date: now()).adding(days: -diasDeCopias)
        for n in names {
            guard let d = LocalDate(parsing: n), d < limit else { continue }
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }

    // MARK: Conflictos de edición

    private func registerEditConflict(path: VaultPath, mine: Data, theirs: Data, plan: UUID) throws -> ConflictRecord {
        let id = UUID()
        let ext = path.ext.isEmpty ? "" : "." + path.ext
        let mineLoc = try conflicts.guardarVersion(mine, conflicto: id, nombre: "tu-version" + ext)
        let theirsLoc = try conflicts.guardarVersion(theirs, conflicto: id, nombre: "la-de-fuera" + ext)
        let record = ConflictRecord(
            id: id, tipo: .edicion, ruta: path, fecha: now(),
            titulo: "«\(path.stem)» cambió fuera mientras la editabas",
            detalle: "No he guardado nada encima. Están las dos versiones: elige con cuál te quedas o combínalas.",
            versiones: [ConflictVersion(etiqueta: "Tu versión", ubicacion: mineLoc, hash: ContentHash.of(mine)),
                        ConflictVersion(etiqueta: "La de fuera", ubicacion: theirsLoc, hash: ContentHash.of(theirs))],
            plan: plan)
        return try conflicts.registrar(record)
    }
}
