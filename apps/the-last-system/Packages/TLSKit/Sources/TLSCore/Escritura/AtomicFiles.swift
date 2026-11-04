import Darwin
import Foundation

/// Escrituras físicas seguras en la carpeta: coordinadas con `NSFileCoordinator` (Obsidian,
/// iCloud y Finder se enteran), en un temporal de `itemReplacementDirectory`, con `F_FULLFSYNC`
/// y sustitución atómica (`replaceItemAt`). Nunca sobrescriben algo que no esperaban: antes de
/// sustituir comprueban la huella (compare-and-swap); al crear o mover usan `RENAME_EXCL`.
///
/// Todas se llaman dentro de `UbiquityInspector.withoutMaterializing`.
enum AtomicFiles {
    /// Punto de la escritura en el que una prueba puede simular que el proceso muere.
    typealias Checkpoint = () throws -> Void

    /// Estado actual de una ruta (sin seguir enlaces ni descargar de iCloud).
    static func state(_ url: URL) -> DiskExpectation? {
        guard let info = UbiquityInspector.info(url) else { return .absent }
        if info.isSymlink || info.dataless { return nil }
        if info.isDirectory { return .directory }
        guard let data = try? Data(contentsOf: url, options: [.uncached]) else { return nil }
        return .file(ContentHash.of(data))
    }

    /// `true` si `url` existe con ese nombre exacto (NFC) en su carpeta: APFS no distingue
    /// mayúsculas, así que `lstat` no basta para saber si un renombrado de mayúsculas se hizo.
    static func existsExactly(_ url: URL) -> Bool {
        let name = url.lastPathComponent.precomposedStringWithCanonicalMapping
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) else {
            return false
        }
        return names.contains { $0.precomposedStringWithCanonicalMapping == name }
    }

    // MARK: Coordinación

    private static func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions,
                                   _ body: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var inner: Error?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordError) { u in
            do { try body(u) } catch { inner = error }
        }
        if let inner { throw inner }
        if let coordError { throw coordError }
    }

    /// Mover coordinado: el origen `.forMoving` y el destino `.forReplacing` (patrón de Apple).
    private static func coordinateMove(from src: URL, to dst: URL, _ body: (URL, URL, NSFileCoordinator) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var inner: Error?
        coordinator.coordinate(writingItemAt: src, options: .forMoving, writingItemAt: dst, options: .forReplacing,
                               error: &coordError) { a, b in
            do { try body(a, b, coordinator) } catch { inner = error }
        }
        if let inner { throw inner }
        if let coordError { throw coordError }
    }

    // MARK: Temporal

    /// Escribe `data` en un temporal nuevo junto a `near` (mismo volumen) y lo lleva a disco.
    static func writeTemporary(_ data: Data, near url: URL, name: String, mode: mode_t = 0o644) throws -> (dir: URL, file: URL) {
        let fm = FileManager.default
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        let file = dir.appendingPathComponent(name)
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                offset += n
            }
        }
        try fullSync(fd)
        return (dir, file)
    }

    /// `F_FULLFSYNC` (los datos llegan al disco, no solo a su caché); si no se admite, `fsync`.
    static func fullSync(_ fd: Int32) throws {
        if fcntl(fd, F_FULLFSYNC) == 0 { return }
        guard fsync(fd) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    /// Escribe un fichero de la app (fuera de la carpeta de la empresa) y lo lleva a disco.
    static func writeDurable(_ data: Data, to url: URL, mode: mode_t = 0o600) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, mode)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                offset += n
            }
        }
        try fullSync(fd)
    }

    /// Lleva a disco la entrada de directorio (tras renombrar o crear).
    static func syncDirectory(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        _ = fsync(fd)
        close(fd)
    }

    static func renameExclusive(_ src: URL, _ dst: URL) throws {
        let r = src.withUnsafeFileSystemRepresentation { s in
            dst.withUnsafeFileSystemRepresentation { d in
                renamex_np(s!, d!, UInt32(RENAME_EXCL))
            }
        }
        guard r == 0 else {
            let code = errno
            if code == EEXIST { throw WriteError.destinoOcupado(dst.lastPathComponent) }
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
    }

    /// Intercambia dos rutas del mismo volumen de forma atómica (`RENAME_SWAP`).
    static func swap(_ a: URL, _ b: URL) throws {
        let r = a.withUnsafeFileSystemRepresentation { s in
            b.withUnsafeFileSystemRepresentation { d in renamex_np(s!, d!, UInt32(RENAME_SWAP)) }
        }
        guard r == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    // MARK: Operaciones

    /// Sustituye un fichero existente si su huella sigue siendo `expected`.
    static func replace(_ url: URL, with data: Data, expected: String, display: String,
                        afterTemporary: Checkpoint) throws {
        try coordinate(writing: url, options: .forReplacing) { target in
            guard case .file(let current)? = state(target) else { throw WriteError.cambioExterno(display) }
            guard current == expected else { throw WriteError.cambioExterno(display) }
            let tmp = try writeTemporary(data, near: target, name: target.lastPathComponent)
            var conservar = false
            defer { if !conservar { try? FileManager.default.removeItem(at: tmp.dir) } }
            try afterTemporary()
            // Compare-and-swap de verdad: se intercambian los dos ficheros de forma atómica y se
            // comprueba lo que salió. Si no era lo esperado (alguien guardó mientras el temporal iba
            // a disco), se vuelve a intercambiar: lo de fuera se queda en su sitio.
            do {
                try swap(tmp.file, target)
            } catch let e as POSIXError where e.code == .ENOTSUP {
                // Volumen sin intercambio atómico: comprobar otra vez justo antes de sustituir.
                guard case .file(let again)? = state(target), again == expected else { throw WriteError.cambioExterno(display) }
                _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp.file, backupItemName: nil, options: [])
                syncDirectory(target.deletingLastPathComponent())
                return
            }
            guard case .file(let salido)? = state(tmp.file), salido == expected else {
                do { try swap(tmp.file, target) } catch {
                    conservar = true   // lo de fuera está en el temporal: no se borra
                    throw WriteError.cambioExterno(display)
                }
                throw WriteError.cambioExterno(display)
            }
            // Lo que conservaba `replaceItemAt`: permisos, atributos (etiquetas) y fecha de creación.
            // Sin COPYFILE_SECURITY ni STAT: copian también la fecha de modificación (el índice y
            // Obsidian no verían el cambio).
            var st = stat()
            if lstat(tmp.file.path, &st) == 0 { _ = chmod(target.path, st.st_mode & 0o7777) }
            _ = copyfile(tmp.file.path, target.path, nil, copyfile_flags_t(COPYFILE_XATTR))
            if let creada = (try? FileManager.default.attributesOfItem(atPath: tmp.file.path))?[.creationDate] as? Date {
                try? FileManager.default.setAttributes([.creationDate: creada], ofItemAtPath: target.path)
            }
            syncDirectory(target.deletingLastPathComponent())
        }
    }

    /// Crea un fichero nuevo; si el nombre ya existe, falla (nunca pisa).
    static func create(_ url: URL, with data: Data, display: String, mode: mode_t = 0o644,
                       afterTemporary: Checkpoint) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try coordinate(writing: url, options: []) { target in
            guard case .absent? = state(target) else { throw WriteError.destinoOcupado(display) }
            let tmp = try writeTemporary(data, near: parent, name: target.lastPathComponent, mode: mode)
            defer { try? FileManager.default.removeItem(at: tmp.dir) }
            try afterTemporary()
            try renameExclusive(tmp.file, target)
            syncDirectory(target.deletingLastPathComponent())
        }
    }

    /// Mueve sin sobrescribir, si el origen sigue como se esperaba.
    static func move(_ src: URL, to dst: URL, expected: DiskExpectation, display: String) throws {
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinateMove(from: src, to: dst) { a, b, coordinator in
            guard let current = state(a), current == expected else { throw WriteError.cambioExterno(display) }
            guard case .absent? = state(b) else { throw WriteError.destinoOcupado(b.lastPathComponent) }
            try renameExclusive(a, b)
            coordinator.item(at: a, didMoveTo: b)
            syncDirectory(a.deletingLastPathComponent())
            syncDirectory(b.deletingLastPathComponent())
        }
    }

    /// Renombra cambiando solo mayúsculas o tildes, en dos pasos con un nombre intermedio
    /// (`intermediate`, en la misma carpeta). Se puede retomar si se cortó a mitad.
    static func renameCase(_ src: URL, to dst: URL, intermediate: URL, expected: DiskExpectation, display: String) throws {
        if existsExactly(src) {
            guard let current = state(src), current == expected else { throw WriteError.cambioExterno(display) }
            try coordinateMove(from: src, to: intermediate) { a, b, c in
                try renameExclusive(a, b)
                c.item(at: a, didMoveTo: b)
            }
        }
        guard existsExactly(intermediate) else { throw WriteError.cambioExterno(display) }
        try coordinateMove(from: intermediate, to: dst) { a, b, c in
            try renameExclusive(a, b)
            c.item(at: a, didMoveTo: b)
        }
        syncDirectory(dst.deletingLastPathComponent())
    }
}
