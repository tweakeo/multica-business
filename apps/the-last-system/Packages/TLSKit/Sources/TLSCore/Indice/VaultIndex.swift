import Foundation
import GRDB

/// Índice desechable de una carpeta: `AppLocations.vaultState(id)/index.sqlite`.
///
/// Si el esquema cambia (`PRAGMA user_version`) o el fichero está dañado, se borra y se
/// reconstruye. Nada de aquí es fuente de verdad: la carpeta lo es.
///
/// `secure_delete` está activo: lo borrado (p. ej. lo que acaba de quedar excluido) se sobrescribe
/// con ceros en vez de quedarse en páginas libres, y al cerrar se vacía el diario WAL.
final class VaultIndex: Sendable {
    /// 2 (F1): `NoteKind` con los 47 tipos de las plantillas; un índice de la 1 se rehace solo.
    /// 3 (F2): texto de los PDF ya descargados y no privados en la búsqueda (`pdfs`, `pdfs_fts`; R1).
    static let schemaVersion = 3
    static let fileName = "index.sqlite"

    let url: URL
    let db: DatabasePool
    /// Lee en segundo plano el texto de los PDF pendientes (`TextoPDF.swift`).
    let textoPDF: ColaTextoPDF

    /// Fila de `notes` tal como la guarda el índice.
    struct NoteRow: Sendable, Hashable {
        var path: VaultPath
        var title: String
        var kind: NoteKind
        var area: AreaCode?
        var hash: String
        var size: Int64
        var mtime: Int64
        var dataless: Bool
        var privado: Bool
        var archivado: Bool
        var frontmatter: String?

        var summary: NoteSummary {
            NoteSummary(path: path, title: title, kind: kind, area: area, dataless: dataless, privado: privado,
                        modified: mtime == 0 ? nil : Date(timeIntervalSince1970: Double(mtime) / 1_000_000_000))
        }
    }

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(Self.fileName)
        if let pool = try? Self.openValid(url) {
            db = pool
        } else {
            Self.deleteFiles(url)
            db = try Self.openValid(url, create: true)
        }
        textoPDF = ColaTextoPDF(db: db)
    }

    /// Abre el índice si su esquema es el actual; si `create`, lo crea en un fichero nuevo.
    private static func openValid(_ url: URL, create: Bool = false) throws -> DatabasePool {
        var config = Configuration()
        config.label = "TLSIndex"
        // Otro proceso (tls-tool) o una apertura anterior aún escribiendo: espera en vez de fallar.
        config.busyMode = .timeout(10)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        let (version, tables) = try pool.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0,
             Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")))
        }
        // Misma versión pero sin todas las tablas (índice de una compilación anterior): se rehace.
        if version == schemaVersion {
            if requiredTables.isSubset(of: tables) { return pool }
            try? pool.close()
            throw IndexError.schemaMismatch
        }
        guard create, version == 0 else {
            try? pool.close()
            throw IndexError.schemaMismatch
        }
        try pool.write { db in
            try db.execute(sql: """
                CREATE TABLE notes(
                    path TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    title TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    area TEXT,
                    hash TEXT NOT NULL DEFAULT '',
                    size INTEGER NOT NULL DEFAULT 0,
                    mtime INTEGER NOT NULL DEFAULT 0,
                    dataless INTEGER NOT NULL DEFAULT 0,
                    privado INTEGER NOT NULL DEFAULT 0,
                    archivado INTEGER NOT NULL DEFAULT 0,
                    frontmatter TEXT
                );
                CREATE INDEX notes_name ON notes(name);
                CREATE TABLE links(
                    "from" TEXT NOT NULL,
                    target_raw TEXT NOT NULL,
                    resolved TEXT,
                    PRIMARY KEY("from", target_raw)
                ) WITHOUT ROWID;
                CREATE INDEX links_resolved ON links(resolved);
                CREATE TABLE meta(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
                CREATE VIRTUAL TABLE notes_fts USING fts5(
                    title, body, tokenize = 'unicode61 remove_diacritics 2'
                );
                CREATE TABLE pdfs(
                    path TEXT PRIMARY KEY NOT NULL,
                    area TEXT,
                    size INTEGER NOT NULL DEFAULT 0,
                    mtime INTEGER NOT NULL DEFAULT 0,
                    dataless INTEGER NOT NULL DEFAULT 0,
                    estado TEXT NOT NULL DEFAULT 'pendiente'
                );
                CREATE INDEX pdfs_estado ON pdfs(estado);
                CREATE VIRTUAL TABLE pdfs_fts USING fts5(
                    title, body, tokenize = 'unicode61 remove_diacritics 2'
                );
                PRAGMA user_version = \(schemaVersion);
                """)
        }
        return pool
    }

    static func deleteFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    enum IndexError: Error { case schemaMismatch }

    /// Tablas que debe tener un índice válido de `schemaVersion`.
    static let requiredTables: Set<String> = ["notes", "links", "meta", "notes_fts", "pdfs", "pdfs_fts"]

    /// Cierra el índice dejando el diario WAL vacío (sin restos de texto en `index.sqlite-wal`).
    func close() {
        // Antes que nada, la lectura de PDF: termina el fichero en curso y ya no vuelve a tocar el índice.
        textoPDF.cerrar()
        try? db.writeWithoutTransaction { db in _ = try db.checkpoint(.truncate) }
        try? db.close()
    }

    /// Huella de configuración con la que se construyó (`nil` si es nuevo).
    func storedConfig() -> String? {
        try? db.read { try Self.meta("config", in: $0) }
    }

    /// Tras quitar muchas notas (nuevas exclusiones): compacta la búsqueda para que no queden
    /// fragmentos de lo borrado y vacía el diario WAL.
    func purgeDeleted() {
        try? db.writeWithoutTransaction { db in
            try db.execute(sql: "INSERT INTO notes_fts(notes_fts) VALUES('optimize')")
            try db.execute(sql: "INSERT INTO pdfs_fts(pdfs_fts) VALUES('optimize')")
            _ = try db.checkpoint(.truncate)
        }
    }

    // MARK: Escritura (solo desde IndexBuilder, en su cola)

    struct NoteWrite {
        var row: NoteRow
        /// `nil` = no tocar el texto indexado (p. ej. solo cambió `dataless`).
        var body: String?
        /// `nil` = no tocar los enlaces.
        var links: [String]?
        /// `false` = la nota no entra en la búsqueda de texto (Archivo).
        var searchable: Bool
    }

    static func upsert(_ w: NoteWrite, in db: Database) throws {
        let r = w.row
        try db.execute(sql: """
            INSERT INTO notes(path, name, title, kind, area, hash, size, mtime, dataless, privado, archivado, frontmatter)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                name = excluded.name, title = excluded.title, kind = excluded.kind, area = excluded.area,
                hash = excluded.hash, size = excluded.size, mtime = excluded.mtime, dataless = excluded.dataless,
                privado = excluded.privado, archivado = excluded.archivado, frontmatter = excluded.frontmatter
            """, arguments: [r.path.raw, TextFolding.nameKey(r.path.stem), r.title, r.kind.rawValue, r.area?.rawValue,
                             r.hash, r.size, r.mtime, r.dataless, r.privado, r.archivado, r.frontmatter])
        guard let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM notes WHERE path = ?", arguments: [r.path.raw]) else { return }
        if let body = w.body {
            try db.execute(sql: "DELETE FROM notes_fts WHERE rowid = ?", arguments: [rowid])
            if w.searchable {
                try db.execute(sql: "INSERT INTO notes_fts(rowid, title, body) VALUES (?, ?, ?)",
                               arguments: [rowid, r.title, body])
            }
        } else if !w.searchable {
            try db.execute(sql: "DELETE FROM notes_fts WHERE rowid = ?", arguments: [rowid])
        }
        if let links = w.links {
            try db.execute(sql: #"DELETE FROM links WHERE "from" = ?"#, arguments: [r.path.raw])
            for t in Set(links) {
                try db.execute(sql: #"INSERT OR IGNORE INTO links("from", target_raw, resolved) VALUES (?, ?, NULL)"#,
                               arguments: [r.path.raw, t])
            }
        }
    }

    /// Solo cambian tamaño, fecha o `dataless` (el contenido es el mismo).
    static func touch(_ path: VaultPath, size: Int64, mtime: Int64, dataless: Bool, in db: Database) throws {
        try db.execute(sql: "UPDATE notes SET size = ?, mtime = ?, dataless = ? WHERE path = ?",
                       arguments: [size, mtime, dataless, path.raw])
    }

    static func delete(_ path: VaultPath, in db: Database) throws {
        if let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM notes WHERE path = ?", arguments: [path.raw]) {
            try db.execute(sql: "DELETE FROM notes_fts WHERE rowid = ?", arguments: [rowid])
        }
        try db.execute(sql: #"DELETE FROM links WHERE "from" = ?"#, arguments: [path.raw])
        try db.execute(sql: "DELETE FROM notes WHERE path = ?", arguments: [path.raw])
    }

    static func meta(_ key: String, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key])
    }

    static func setMeta(_ key: String, _ value: String, in db: Database) throws {
        try db.execute(sql: "INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       arguments: [key, value])
    }

    /// Recalcula `links.resolved` con el resolvedor actual. Devuelve cuántos enlaces cambiaron.
    static func resolveLinks(_ resolver: LinkResolver, in db: Database) throws -> Int {
        let rows = try Row.fetchAll(db, sql: #"SELECT "from", target_raw, resolved FROM links"#)
        var changed = 0
        for row in rows {
            let from = VaultPath(row["from"] as String)
            let raw: String = row["target_raw"]
            let old: String? = row["resolved"]
            let new = resolver.resolve(raw, from: from)?.raw
            if new != old {
                try db.execute(sql: #"UPDATE links SET resolved = ? WHERE "from" = ? AND target_raw = ?"#,
                               arguments: [new, from.raw, raw])
                changed += 1
            }
        }
        return changed
    }

    // MARK: Lectura

    static func row(_ r: Row) -> NoteRow {
        NoteRow(path: VaultPath(r["path"] as String), title: r["title"], kind: NoteKind(rawValue: r["kind"]) ?? .note,
                area: (r["area"] as String?).flatMap(AreaCode.init(rawValue:)), hash: r["hash"], size: r["size"],
                mtime: r["mtime"], dataless: r["dataless"], privado: r["privado"], archivado: r["archivado"],
                frontmatter: r["frontmatter"])
    }

    static let columns = "path, title, kind, area, hash, size, mtime, dataless, privado, archivado, frontmatter"

    func allRows() throws -> [NoteRow] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT \(Self.columns) FROM notes ORDER BY path").map(Self.row)
        }
    }

    func row(for path: VaultPath) -> NoteRow? {
        try? db.read { db in
            try Row.fetchOne(db, sql: "SELECT \(Self.columns) FROM notes WHERE path = ?", arguments: [path.raw]).map(Self.row)
        }
    }

    func counts() -> (notes: Int, dataless: Int) {
        (try? db.read { db in
            let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes") ?? 0
            let d = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE dataless = 1") ?? 0
            return (n, d)
        }) ?? (0, 0)
    }

    func backlinks(to path: VaultPath) -> [NoteRow] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT \(Self.columns.split(separator: ",").map { "n." + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", "))
                FROM notes n
                WHERE n.path IN (SELECT "from" FROM links WHERE resolved = ? AND "from" <> ?)
                ORDER BY n.title COLLATE NOCASE
                """, arguments: [path.raw, path.raw]).map(Self.row)
        }) ?? []
    }

    /// Búsqueda FTS5 en las notas y en el texto de los PDF. `match` ya viene construido (términos con
    /// prefijo). Los dos resultados se mezclan por relevancia (`bm25`, el título pesa 8 veces más).
    func search(match: String, limit: Int) -> [(NoteRow, String)] {
        (try? db.read { db in
            let notas = try Row.fetchAll(db, sql: """
                SELECT \(Self.columns.split(separator: ",").map { "n." + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")),
                       snippet(notes_fts, -1, '‹', '›', '…', 12) AS snip, bm25(notes_fts, 8.0, 1.0) AS rango
                FROM notes_fts JOIN notes n ON n.rowid = notes_fts.rowid
                WHERE notes_fts MATCH ?
                ORDER BY rango
                LIMIT ?
                """, arguments: [match, limit]).map { (Self.row($0), $0["snip"] as String? ?? "", $0["rango"] as Double? ?? 0) }
            let pdfs = try Row.fetchAll(db, sql: """
                SELECT p.path, p.area, p.size, p.mtime, snippet(pdfs_fts, -1, '‹', '›', '…', 12) AS snip,
                       bm25(pdfs_fts, 8.0, 1.0) AS rango
                FROM pdfs_fts JOIN pdfs p ON p.rowid = pdfs_fts.rowid
                WHERE pdfs_fts MATCH ?
                ORDER BY rango
                LIMIT ?
                """, arguments: [match, limit]).map { (Self.filaPDF($0), $0["snip"] as String? ?? "", $0["rango"] as Double? ?? 0) }
            // Orden estable: por relevancia y, a igualdad, las notas antes que los PDF.
            return (notas + pdfs).enumerated()
                .sorted { $0.element.2 != $1.element.2 ? $0.element.2 < $1.element.2 : $0.offset < $1.offset }
                .prefix(limit).map { ($0.element.0, $0.element.1) }
        }) ?? []
    }

    /// Un PDF de la búsqueda como fila de nota: su nombre como título y tipo «otro» (abre en el visor).
    static func filaPDF(_ r: Row) -> NoteRow {
        let path = VaultPath(r["path"] as String)
        return NoteRow(path: path, title: path.stem, kind: .other,
                       area: (r["area"] as String?).flatMap(AreaCode.init(rawValue:)), hash: "", size: r["size"],
                       mtime: r["mtime"], dataless: false, privado: false, archivado: false, frontmatter: nil)
    }

    // MARK: PDF (solo desde IndexBuilder y ColaTextoPDF)

    /// Lo que el índice sabe de un PDF.
    struct PDFRow: Sendable, Hashable {
        var path: VaultPath
        var size: Int64
        var mtime: Int64
        var dataless: Bool
        var estado: String
    }

    static func pdfRows(in db: Database, under folder: VaultPath? = nil) throws -> [VaultPath: PDFRow] {
        let rows: [Row]
        if let folder, !folder.isRoot {
            rows = try Row.fetchAll(db, sql: "SELECT path, size, mtime, dataless, estado FROM pdfs WHERE path = ? OR path LIKE ? ESCAPE '\\'",
                                    arguments: [folder.raw, IndexBuilder.likePrefix(folder)])
        } else {
            rows = try Row.fetchAll(db, sql: "SELECT path, size, mtime, dataless, estado FROM pdfs")
        }
        var out: [VaultPath: PDFRow] = [:]
        for r in rows {
            let p = VaultPath(r["path"] as String)
            out[p] = PDFRow(path: p, size: r["size"], mtime: r["mtime"], dataless: r["dataless"], estado: r["estado"])
        }
        return out
    }

    /// Apunta un PDF nuevo o cambiado. Si solo pasó a estar solo en iCloud (mismo tamaño y fecha), conserva su
    /// texto; si cambió, lo quita hasta volver a leerlo.
    static func registrarPDF(_ path: VaultPath, area: AreaCode?, size: Int64, mtime: Int64, dataless: Bool,
                             existente: PDFRow?, forzar: Bool, in db: Database) throws {
        if let e = existente, !forzar, e.size == size, e.mtime == mtime, e.dataless == dataless { return }
        if let e = existente, !forzar, e.size == size, e.mtime == mtime, dataless {
            // Se evictó de iCloud: lo leído sigue valiendo.
            try db.execute(sql: "UPDATE pdfs SET dataless = 1 WHERE path = ?", arguments: [path.raw])
            if e.estado == EstadoTextoPDF.pendiente.rawValue {
                try db.execute(sql: "UPDATE pdfs SET estado = ? WHERE path = ?",
                               arguments: [EstadoTextoPDF.sinDescargar.rawValue, path.raw])
            }
            return
        }
        let estado = dataless ? EstadoTextoPDF.sinDescargar : .pendiente
        try db.execute(sql: """
            INSERT INTO pdfs(path, area, size, mtime, dataless, estado) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET area = excluded.area, size = excluded.size, mtime = excluded.mtime,
                dataless = excluded.dataless, estado = excluded.estado
            """, arguments: [path.raw, area?.rawValue, size, mtime, dataless, estado.rawValue])
        if let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM pdfs WHERE path = ?", arguments: [path.raw]) {
            try db.execute(sql: "DELETE FROM pdfs_fts WHERE rowid = ?", arguments: [rowid])
        }
    }

    /// Quita un PDF (y su texto) del índice.
    static func borrarPDF(_ path: VaultPath, in db: Database) throws {
        if let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM pdfs WHERE path = ?", arguments: [path.raw]) {
            try db.execute(sql: "DELETE FROM pdfs_fts WHERE rowid = ?", arguments: [rowid])
        }
        try db.execute(sql: "DELETE FROM pdfs WHERE path = ?", arguments: [path.raw])
    }

    /// Estado de cada PDF y si su texto está en la búsqueda (pruebas).
    func estadoPDF() throws -> [VaultPath: (estado: String, conTexto: Bool)] {
        try db.read { db in
            var out: [VaultPath: (String, Bool)] = [:]
            for r in try Row.fetchAll(db, sql: """
                SELECT p.path, p.estado, (SELECT COUNT(*) FROM pdfs_fts f WHERE f.rowid = p.rowid) AS n FROM pdfs p
                """) {
                out[VaultPath(r["path"] as String)] = (r["estado"], (r["n"] as Int) > 0)
            }
            return out
        }
    }

    /// Volcado comparable (para el test «reconstruido = incremental»).
    func dump() throws -> [String] {
        try db.read { db in
            let notes = try Row.fetchAll(db, sql: """
                SELECT path, name, title, kind, area, hash, size, dataless, privado, archivado, frontmatter FROM notes ORDER BY path
                """).map { r in
                    "N|" + (0..<r.count).map { String(describing: r[$0] as DatabaseValue) }.joined(separator: "|")
                }
            let links = try Row.fetchAll(db, sql: #"SELECT "from", target_raw, resolved FROM links ORDER BY "from", target_raw"#)
                .map { r in "L|" + (0..<r.count).map { String(describing: r[$0] as DatabaseValue) }.joined(separator: "|") }
            let fts = try Row.fetchAll(db, sql: """
                SELECT n.path, f.title, f.body FROM notes_fts f JOIN notes n ON n.rowid = f.rowid ORDER BY n.path
                """).map { r in "F|" + (0..<r.count).map { String(describing: r[$0] as DatabaseValue) }.joined(separator: "|") }
            return notes + links + fts
        }
    }
}
