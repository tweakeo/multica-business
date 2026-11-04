import Foundation
import GRDB

/// Una ficha tal como la guarda el índice: su resumen, sus propiedades y los enlaces de sus propiedades ya
/// resueltos. Se lee sin abrir el fichero (vía rápida de §7.2).
public struct FichaIndexada: Sendable, Hashable {
    public let resumen: NoteSummary
    public let propiedades: [String: PropertyValue]
    /// Enlaces de la nota resueltos: destino tal como lo guarda el índice (`[[slug]]`, sin el texto visible)
    /// → ficha a la que lleva.
    public let enlaces: [String: VaultPath]

    public init(resumen: NoteSummary, propiedades: [String: PropertyValue], enlaces: [String: VaultPath]) {
        self.resumen = resumen
        self.propiedades = propiedades
        self.enlaces = enlaces
    }

    public var ruta: VaultPath { resumen.path }

    /// Ficha a la que lleva un enlace escrito en una propiedad (`[[talleres-martin|Talleres Martín]]`).
    public func destino(de enlace: ParsedLink) -> VaultPath? {
        enlaces[enlace.resolvable]
    }
}

extension VaultIndex {
    /// Filas de estos tipos, sin lo que está en `Archivo/` (salvo que se pida).
    func filas(deTipos tipos: [NoteKind], incluirArchivo: Bool = false) -> [NoteRow] {
        guard !tipos.isEmpty else { return [] }
        let marcas = Array(repeating: "?", count: tipos.count).joined(separator: ", ")
        let archivo = incluirArchivo ? "" : " AND archivado = 0"
        return (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT \(Self.columns) FROM notes WHERE kind IN (\(marcas))\(archivo)",
                             arguments: StatementArguments(tipos.map(\.rawValue))).map(Self.row)
        }) ?? []
    }

    /// Enlaces resueltos que salen de las notas de estos tipos: nota → destino escrito → ficha.
    func enlacesResueltos(deTipos tipos: [NoteKind]) -> [VaultPath: [String: VaultPath]] {
        guard !tipos.isEmpty else { return [:] }
        let marcas = Array(repeating: "?", count: tipos.count).joined(separator: ", ")
        let filas = (try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT l."from", l.target_raw, l.resolved FROM links l JOIN notes n ON n.path = l."from"
                WHERE l.resolved IS NOT NULL AND n.kind IN (\(marcas))
                """, arguments: StatementArguments(tipos.map(\.rawValue)))
        }) ?? []
        var out: [VaultPath: [String: VaultPath]] = [:]
        for r in filas {
            let desde = VaultPath(r["from"] as String)
            let destino: String = r["resolved"]
            out[desde, default: [:]][r["target_raw"] as String] = VaultPath(destino)
        }
        return out
    }

    /// Rutas de las notas de un tipo (p. ej. los CSV) que cuelgan de una carpeta.
    func rutas(deTipo tipo: NoteKind, bajo carpeta: VaultPath) -> [VaultPath] {
        let prefijo = carpeta.isRoot ? "%" : IndexBuilder.likePrefix(carpeta)
        return (try? db.read { db in
            try String.fetchAll(db, sql: "SELECT path FROM notes WHERE kind = ? AND archivado = 0 AND path LIKE ? ESCAPE '\\' ORDER BY path",
                                arguments: [tipo.rawValue, prefijo]).map(VaultPath.init)
        }) ?? []
    }
}

public extension VaultService {
    /// Fichas de estos tipos (`tls_type`), en toda la carpeta: sin plantillas (no tienen tipo de ficha) y sin
    /// lo que está en `Archivo/`. **Incluye lo privado**: quien lo enseñe lo filtra con `resumen.privado`.
    func fichas(deTipos tipos: Set<NoteKind>, incluirArchivo: Bool = false) -> [FichaIndexada] {
        guard let index = indiceAbierto else { return [] }
        let lista = Array(tipos)
        let filas = index.filas(deTipos: lista, incluirArchivo: incluirArchivo)
        let enlaces = index.enlacesResueltos(deTipos: lista)
        return filas.map { r in
            FichaIndexada(resumen: r.summary, propiedades: Self.propiedades(json: r.frontmatter), enlaces: enlaces[r.path] ?? [:])
        }
    }

    /// Todas las notas Markdown con su tipo (fichas y notas sueltas), sin `Archivo/`. Para ⌘K.
    /// **Incluye lo privado.**
    func todasLasFichas() -> [FichaIndexada] {
        fichas(deTipos: Set(NoteKind.allCases.filter { $0 != .csv && $0 != .other }))
    }

    /// CSV llamados `nombre` que cuelgan de `carpeta` (a cualquier profundidad), sin `Archivo/`.
    func ficherosCSV(llamados nombre: String, bajo carpeta: VaultPath) -> [VaultPath] {
        guard let index = indiceAbierto else { return [] }
        let clave = TextFolding.nameKey(nombre)
        return index.rutas(deTipo: .csv, bajo: carpeta).filter { TextFolding.nameKey($0.name) == clave }
    }

    /// Propiedades del JSON del índice (`{"estado":"Activo","valor":150.00,…}`).
    internal static func propiedades(json: String?) -> [String: PropertyValue] {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: PropertyValue] = [:]
        for (k, v) in obj { out[k] = valor(v) }
        return out
    }

    private static func valor(_ v: Any) -> PropertyValue {
        switch v {
        case is NSNull: return .empty
        case let s as String: return .text(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.stringValue)
        case let l as [Any]:
            return .list(l.map { e in
                switch e {
                case let s as String: s
                case let n as NSNumber: n.stringValue
                default: "\(e)"
                }
            })
        default:
            return .raw("\(v)")
        }
    }
}
