import Foundation
import GRDB
import PDFKit

// Texto de los PDF para la búsqueda (REQUISITOS-ADICIONALES R1, F2).
//
// - Solo lo que ya está en el Mac: un PDF que está solo en iCloud no se abre (la lectura va dentro de
//   `UbiquityInspector.withoutMaterializing`, así que un acceso por error da error y no descarga nada).
// - Nunca lo privado ni lo excluido: se comprueba al registrarlo y otra vez justo antes de leerlo.
// - Solo en el índice desechable (`index.sqlite`, fuera de la carpeta): tablas `pdfs` y `pdfs_fts`.
// - En segundo plano: el escaneo solo apunta qué PDF hay que leer; una cola propia (prioridad baja) los lee
//   de pocos en pocos, así que abrir la empresa no espera a los PDF.

/// Saca el texto de un PDF ya leído del disco. Se sustituye en las pruebas.
protocol ExtractorTextoPDF: Sendable {
    /// Texto del PDF, `""` si no tiene (escaneado) o `nil` si no se puede leer (dañado o cifrado).
    func texto(de data: Data) -> String?
}

/// Extractor con PDFKit: hasta `maxPaginas` páginas y `maxCaracteres` caracteres por fichero.
struct ExtractorPDFKit: ExtractorTextoPDF {
    var maxPaginas = 300
    var maxCaracteres = 300_000

    func texto(de data: Data) -> String? {
        guard let doc = PDFDocument(data: data), !doc.isLocked else { return nil }
        var partes: [String] = []
        var total = 0
        for i in 0..<min(doc.pageCount, maxPaginas) {
            guard let s = doc.page(at: i)?.string, !s.isEmpty else { continue }
            partes.append(s)
            total += s.count
            if total >= maxCaracteres { break }
        }
        return Self.limpiar(partes.joined(separator: "\n"), maximo: maxCaracteres)
    }

    /// NFC, sin caracteres de control y con los espacios seguidos reducidos a uno.
    static func limpiar(_ texto: String, maximo: Int) -> String {
        var out = ""
        out.reserveCapacity(min(texto.count, maximo))
        var espacio = false
        for ch in texto.precomposedStringWithCanonicalMapping {
            if ch.isWhitespace || ch.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
                espacio = !out.isEmpty
                continue
            }
            if espacio { out.append(" "); espacio = false }
            out.append(ch)
            if out.count >= maximo { break }
        }
        return out
    }
}

/// Estado de un PDF en la tabla `pdfs`.
enum EstadoTextoPDF: String, Sendable {
    /// Hay que leerlo.
    case pendiente
    /// Leído; su texto está en `pdfs_fts`.
    case hecho
    /// Leído, sin texto (escaneado o vacío).
    case sinTexto = "sin_texto"
    /// Solo en iCloud: no se lee hasta que esté en el Mac (lo vuelve a marcar el escaneo).
    case sinDescargar = "sin_descargar"
    /// Demasiado grande para leerlo entero.
    case grande
    /// Dañado, cifrado o ilegible.
    case error
}

/// Lee en segundo plano el texto de los PDF pendientes de un índice. Una por `VaultIndex`.
///
/// `programar` la despierta (lo llama `IndexBuilder` tras cada escaneo); `cerrar` la para y espera a que
/// termine el fichero en curso (lo llama `VaultIndex.close`).
final class ColaTextoPDF: @unchecked Sendable {
    /// Lo que la cola necesita saber de la carpeta (la última configuración que le pasó el escaneo).
    struct Trabajo: Sendable {
        let root: URL
        /// ¿Se puede leer esta ruta ahora? (no privada, no excluida, sin enlaces simbólicos por el camino).
        let permitido: @Sendable (VaultPath) -> Bool
    }

    /// Ficheros por tanda (entre tandas se vuelve a mirar si hay que parar).
    static let tanda = 4
    /// Más grande que esto no se lee (80 MB).
    static let maxBytes: Int64 = 80 * 1024 * 1024

    private let db: DatabasePool
    private let cola = DispatchQueue(label: "es.thelast.system.indice.pdf", qos: .utility)
    private let lock = NSLock()
    // Protegido por `lock`.
    private var cerrada = false
    private var enMarcha = false
    private var peticiones = 0
    private var trabajo: Trabajo?
    private var _extractor: any ExtractorTextoPDF

    init(db: DatabasePool, extractor: any ExtractorTextoPDF = ExtractorPDFKit()) {
        self.db = db
        self._extractor = extractor
    }

    /// El extractor (las pruebas ponen uno propio antes de escanear).
    var extractor: any ExtractorTextoPDF {
        get { lock.withLock { _extractor } }
        set { lock.withLock { _extractor = newValue } }
    }

    /// Despierta la cola con la configuración actual. Si ya está trabajando, seguirá con esta.
    func programar(_ t: Trabajo) {
        let arrancar = lock.withLock { () -> Bool in
            guard !cerrada else { return false }
            trabajo = t
            peticiones += 1
            if enMarcha { return false }
            enMarcha = true
            return true
        }
        if arrancar { cola.async { self.bucle() } }
    }

    /// Para la cola y espera a que termine el fichero que esté leyendo. Después ya no toca el índice.
    func cerrar() {
        lock.withLock { cerrada = true }
        cola.sync {}
    }

    /// `true` si no queda nada pendiente ni en marcha (pruebas).
    var enReposo: Bool {
        let marcha = lock.withLock { enMarcha }
        guard !marcha else { return false }
        let pendientes = (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pdfs WHERE estado = ?", arguments: [EstadoTextoPDF.pendiente.rawValue])
        }) ?? 0
        return pendientes == 0
    }

    /// Espera (como mucho `segundos`) a que no quede nada pendiente. Para las pruebas.
    @discardableResult
    func esperar(segundos: Double = 20) -> Bool {
        let fin = Date().addingTimeInterval(segundos)
        while Date() < fin {
            if enReposo { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return enReposo
    }

    // MARK: Trabajo (en `cola`)

    private func bucle() {
        // Lo que ya se intentó en esta vuelta: si una escritura falla, no se repite sin fin.
        var intentados = Set<Int64>()
        while true {
            let (t, ext, vista) = lock.withLock { () -> (Trabajo?, any ExtractorTextoPDF, Int) in
                (cerrada ? nil : trabajo, _extractor, peticiones)
            }
            guard let t else {
                lock.withLock { enMarcha = false }
                return
            }
            let leidos = UbiquityInspector.withoutMaterializing { tanda(t, extractor: ext, intentados: &intentados) }
            if leidos == 0 {
                // Nada pendiente: se para, salvo que el escaneo haya pedido más mientras tanto.
                let seguir = lock.withLock { () -> Bool in
                    if !cerrada, peticiones != vista { return true }
                    enMarcha = false
                    return false
                }
                if !seguir { return }
                // Lo nuevo del escaneo puede volver a dejar pendiente algo ya intentado.
                intentados.removeAll()
            }
        }
    }

    private var estaCerrada: Bool { lock.withLock { cerrada } }

    /// Lee hasta `tanda` PDF pendientes. Devuelve cuántos tocó.
    private func tanda(_ t: Trabajo, extractor: any ExtractorTextoPDF, intentados: inout Set<Int64>) -> Int {
        guard !estaCerrada else { return 0 }
        let ya = intentados.map(String.init).joined(separator: ",")
        let filas = (try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT rowid, path, size, mtime FROM pdfs WHERE estado = ? AND rowid NOT IN (\(ya))
                ORDER BY path LIMIT ?
                """, arguments: [EstadoTextoPDF.pendiente.rawValue, Self.tanda])
        }) ?? []
        var tocados = 0
        for fila in filas {
            if estaCerrada { break }
            let rowid: Int64 = fila["rowid"]
            intentados.insert(rowid)
            let path = VaultPath(fila["path"] as String)
            let size: Int64 = fila["size"]
            let mtime: Int64 = fila["mtime"]
            tocados += 1
            guard t.permitido(path) else {
                // Ahora es privado o está excluido: fuera del índice.
                try? db.write { db in try VaultIndex.borrarPDF(path, in: db) }
                continue
            }
            let url = path.url(in: t.root)
            var estado = EstadoTextoPDF.error
            var texto: String?
            var nuevoSize = size, nuevoMtime = mtime
            if let info = UbiquityInspector.info(url), !info.isSymlink, !info.isDirectory {
                nuevoSize = info.size
                nuevoMtime = info.mtimeNanos
                if info.dataless {
                    estado = .sinDescargar
                } else if info.size > Self.maxBytes {
                    estado = .grande
                } else if let data = try? Data(contentsOf: url, options: [.uncached]) {
                    texto = extractor.texto(de: data)
                    if let texto { estado = texto.isEmpty ? .sinTexto : .hecho }
                }
            }
            try? db.write { db in
                // Solo si el escaneo no lo cambió entretanto (si no, lo volverá a dejar pendiente).
                try db.execute(sql: """
                    UPDATE pdfs SET estado = ?, size = ?, mtime = ?
                    WHERE rowid = ? AND path = ? AND size = ? AND mtime = ? AND estado = ?
                    """, arguments: [estado.rawValue, nuevoSize, nuevoMtime, rowid, path.raw, size, mtime,
                                     EstadoTextoPDF.pendiente.rawValue])
                guard db.changesCount == 1 else { return }
                try db.execute(sql: "DELETE FROM pdfs_fts WHERE rowid = ?", arguments: [rowid])
                if let texto, !texto.isEmpty {
                    try db.execute(sql: "INSERT INTO pdfs_fts(rowid, title, body) VALUES (?, ?, ?)",
                                   arguments: [rowid, path.stem, texto])
                }
            }
        }
        return tocados
    }
}
