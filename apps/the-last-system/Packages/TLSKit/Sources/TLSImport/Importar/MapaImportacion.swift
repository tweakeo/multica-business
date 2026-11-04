// Procedencia: formato de `mapa-migracion.csv` y sus acciones, de la unificación de octubre (`mapa-migracion.py`,
// autor: Manuel Trigo). Solo se toma el esquema (`origen,destino,accion,motivo,conflicto`) y la idea de cada acción;
// sin código copiado. Ver docs/PROCEDENCIA.md.

import Foundation
import TLSCore

/// Qué se hace con cada fichero (columna `accion` del mapa).
public enum AccionMapa: String, Sendable, Codable, Hashable, CaseIterable {
    /// Se lleva a su sitio dentro de la carpeta de la empresa (se puede deshacer).
    case mover = "mover"
    case moverYRenombrar = "mover y renombrar"
    /// Se trae de una carpeta de fuera (el original no cambia).
    case copiar = "copiar"
    case copiarYRenombrar = "copiar y renombrar"
    /// Se queda donde está y se le añaden propiedades (`tls_type`, `tls_schema`, `id`).
    case propiedades = "propiedades"
    /// Se queda donde está, sin cambios.
    case mantener = "mantener"
    /// Va a `Archivo/Importación <fecha>/` (anterior a la fecha de corte).
    case archivar = "retirar a Archivo"
    /// Igual que otro: va a `Archivo/Duplicados/` (o no se trae, si es de fuera).
    case duplicado = "duplicado"
    /// «Nada» para su herramienta, o solo en iCloud y de fuera: no se trae.
    case noMigrar = "no migrar"
    /// Dejado fuera por la persona o con claves: no se toca.
    case fuera = "mantener fuera"

    /// Cambia algo en la carpeta de la empresa.
    public var escribe: Bool {
        switch self {
        case .mover, .moverYRenombrar, .copiar, .copiarYRenombrar, .propiedades, .archivar, .duplicado: true
        case .mantener, .noMigrar, .fuera: false
        }
    }

    /// Lleva a otro sitio (destino obligatorio).
    public var traslada: Bool {
        switch self {
        case .mover, .moverYRenombrar, .copiar, .copiarYRenombrar, .archivar, .duplicado: true
        default: false
        }
    }
}

/// Una fila del mapa.
public struct FilaMapa: Sendable, Hashable, Codable {
    /// `<alias>/<ruta>`; las carpetas acaban en `/`.
    public var origen: String
    /// Ruta en la carpeta de la empresa, o «—».
    public var destino: String
    public var accion: AccionMapa
    public var motivo: String
    public var conflicto: String
    /// SHA-256 del original al ordenarlo (vacío si no se sabe: mapas de antes, paquetes o solo en iCloud). «Actualizar
    /// la copia» lo usa para saber si en la real cambió algo que la copia ya ordenó.
    public var sha256: String

    public init(origen: String, destino: String, accion: AccionMapa, motivo: String, conflicto: String = "", sha256: String = "") {
        self.origen = origen; self.destino = destino; self.accion = accion; self.motivo = motivo; self.conflicto = conflicto
        self.sha256 = sha256
    }

    enum CodingKeys: String, CodingKey { case origen, destino, accion, motivo, conflicto, sha256 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origen = try c.decode(String.self, forKey: .origen)
        destino = try c.decode(String.self, forKey: .destino)
        accion = try c.decode(AccionMapa.self, forKey: .accion)
        motivo = try c.decodeIfPresent(String.self, forKey: .motivo) ?? ""
        conflicto = try c.decodeIfPresent(String.self, forKey: .conflicto) ?? ""
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256) ?? ""
    }

    /// Alias de la fuente y ruta dentro de ella.
    public var partesOrigen: (alias: String, ruta: VaultPath, esCarpeta: Bool) {
        let esCarpeta = origen.hasSuffix("/")
        let comps = origen.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return (comps.first ?? "", VaultPath(components: Array(comps.dropFirst())), esCarpeta)
    }

    public var rutaDestino: VaultPath? {
        destino.isEmpty || destino == "—" ? nil : VaultPath(destino)
    }
}

/// El mapa de una importación, con el formato de `mapa-migracion.csv` (`origen,destino,accion,motivo,conflicto`) y una
/// columna más, `sha256`, opcional al leer (los mapas de antes y los revisados a mano no la llevan).
///
/// Se puede guardar (en el estado de la app, nunca en la carpeta de la empresa), revisar o editar a mano y volver a
/// cargar en la zona de preparación. «Actualizar la copia desde la real» lo usa para saber qué ya se trajo.
public struct MapaImportacion: Sendable, Hashable, Codable {
    public static let cabecera = ["origen", "destino", "accion", "motivo", "conflicto"]

    public var filas: [FilaMapa]

    public init(filas: [FilaMapa]) { self.filas = filas }

    // MARK: CSV

    public var csv: String {
        var out = (Self.cabecera + ["sha256"]).joined(separator: ",") + "\n"
        for f in filas {
            out += [f.origen, f.destino, f.accion.rawValue, f.motivo, f.conflicto, f.sha256].map(Self.campo).joined(separator: ",") + "\n"
        }
        return out
    }

    static func campo(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r")
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Lee un mapa. La cabecera tiene que ser la de `mapa-migracion.csv` (en cualquier orden).
    public init(csv texto: String) throws {
        let tabla = CSVTable.parse(TextDecoding.strippingBOM(texto), delimiter: ",")
        let cab = tabla.header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var indice: [String: Int] = [:]
        for c in Self.cabecera {
            guard let i = cab.firstIndex(of: c) else { throw ImportError.mapaIlegible("falta la columna «\(c)»") }
            indice[c] = i
        }
        let iSha = cab.firstIndex(of: "sha256")
        var filas: [FilaMapa] = []
        for (n, fila) in tabla.rows.enumerated() {
            func v(_ c: String) -> String { let i = indice[c]!; return i < fila.count ? fila[i] : "" }
            if fila.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            guard let accion = AccionMapa(rawValue: v("accion").trimmingCharacters(in: .whitespaces)) else {
                throw ImportError.mapaIlegible("la fila \(n + 2) tiene una acción que no conozco («\(v("accion"))»)")
            }
            let sha = iSha.map { $0 < fila.count ? fila[$0].trimmingCharacters(in: .whitespaces) : "" } ?? ""
            filas.append(FilaMapa(origen: v("origen"), destino: v("destino"), accion: accion, motivo: v("motivo"),
                                  conflicto: v("conflicto"), sha256: sha))
        }
        self.filas = filas
    }

    /// Guarda el mapa en el estado de la app (`<estado>/importaciones/<nombre>.csv`). Nunca en la carpeta de la empresa.
    @discardableResult
    public func guardar(en estado: URL, nombre: String) throws -> URL {
        let dir = estado.appendingPathComponent("importaciones", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(NombresDeFicha.fichero(nombre) + ".csv")
        try Data(csv.utf8).write(to: url, options: [.atomic])
        return url
    }

    /// Mapas guardados de una carpeta, del más antiguo al más reciente.
    public static func guardados(en estado: URL) -> [MapaImportacion] {
        let dir = estado.appendingPathComponent("importaciones", isDirectory: true)
        let nombres = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".csv") }.sorted()
        return nombres.compactMap { n in
            (try? String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8)).flatMap { try? MapaImportacion(csv: $0) }
        }
    }

    /// Fila de un origen (`alias/ruta`).
    public func fila(origen: String) -> FilaMapa? { filas.first { $0.origen == origen } }
}
