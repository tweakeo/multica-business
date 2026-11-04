import Foundation
import TLSCore

/// Opciones de `tls-tool convertir-g2`.
public struct OpcionesConversionG2: Sendable, Hashable {
    /// Clase de la carpeta nueva: `copia` o `demo` (nunca `real`).
    public var clase: VaultClass
    /// Reloj fijo de la demo (`AAAA-MM-DD`), que se escribe en `.tls/config.yaml › hoy`.
    public var hoy: String?

    public init(clase: VaultClass = .copia, hoy: String? = nil) {
        self.clase = clase; self.hoy = hoy
    }
}

/// Lo que hizo la conversión y lo que se quedó sin convertir (también va en `Buzón/Informe de importación …`).
public struct InformeConversionG2: Sendable, Codable, Hashable {
    public struct Aviso: Sendable, Codable, Hashable {
        public let texto: String
        /// Rutas de origen afectadas (G2), ordenadas.
        public let fichas: [String]
        public let queHacer: String
    }

    public struct CampoNoConvertido: Sendable, Codable, Hashable {
        /// `tipo.campo` de G2 (`opportunity.owner_id`).
        public let campo: String
        public let fichas: Int
        public let motivo: String
    }

    public struct Bloque: Sendable, Codable, Hashable {
        public let origen: String
        public let ficheros: Int
        public let destino: String
    }

    /// Nombre de la carpeta de origen.
    public let origen: String
    /// Fecha de la exportación de G2 (`AAAA-MM-DD`): da nombre al informe y a `Archivo/Importación …`.
    public let fecha: String
    public let ficherosOrigen: Int
    /// Notas `.md` creadas (sin contar `Archivo/`).
    public let notas: Int
    /// Tablas `.csv` creadas.
    public let tablas: Int
    /// PDF y CSV copiados tal cual a su sitio nuevo.
    public let copiados: Int
    /// Justificantes cuyo SHA-256 coincide con el que guardaba G2.
    public let verificados: Int
    /// Rutas de origen que se guardan sin convertir en `Archivo/Importación <fecha>/`.
    public let archivados: [String]
    /// Registros convertidos por `tls_type` de G2.
    public let porTipo: [String: Int]
    /// Fichas de tarea creadas (una por tarea).
    public let tareas: Int
    public let bloques: [Bloque]
    public let avisos: [Aviso]
    public let camposNoConvertidos: [CampoNoConvertido]
    /// Ruta del informe dentro de la carpeta nueva.
    public let informe: String
    /// Hash del árbol escrito (`Inventory`, también ocultos y `Archivo/`). Solo tras escribir.
    public var hashArbol: String?
    public var destino: String?
}

/// Resultado de la conversión en memoria: qué se escribe y dónde. No toca el disco.
public struct PlanConversionG2: Sendable {
    public enum Contenido: Sendable, Hashable {
        /// Texto UTF-8 nuevo.
        case texto(String)
        /// Copia byte a byte de un fichero del origen.
        case copia(URL)
    }

    /// Ficheros ordenados por ruta.
    public let ficheros: [(ruta: VaultPath, contenido: Contenido)]
    public let informe: InformeConversionG2

    /// Bytes de un fichero del plan.
    public func datos(_ ruta: VaultPath) throws -> Data? {
        guard let c = ficheros.first(where: { $0.ruta == ruta })?.contenido else { return nil }
        switch c {
        case .texto(let s): return Data(s.utf8)
        case .copia(let url): return try Data(contentsOf: url)
        }
    }
}

public enum ErrorConversionG2: Error, LocalizedError, Sendable, Equatable {
    case origenNoAccesible(String)
    case noEsG2(String)
    case lectura(String)
    case destinoExiste(String)
    case destinoDentroDelOrigen
    case origenDentroDelDestino
    case enICloud(String)
    case claseNoPermitida
    case fechaDesconocida
    case hoyNoValido(String)
    case escritura(String)

    public var errorDescription: String? {
        switch self {
        case .origenNoAccesible(let p): "No puedo abrir la carpeta de origen: \(p)"
        case .noEsG2(let p): "La carpeta \(p) no parece una exportación de G2: falta Empresa.md con «tls_type: company»."
        case .lectura(let r): "No he podido leer «\(r)» de la carpeta de origen."
        case .destinoExiste(let p): "Ya existe \(p). La conversión nunca escribe encima: elige otra carpeta."
        case .destinoDentroDelOrigen: "La carpeta nueva no puede estar dentro de la de origen."
        case .origenDentroDelDestino: "La carpeta de origen no puede estar dentro de la nueva."
        case .enICloud(let p): "No convierto nada dentro de iCloud Drive (\(p)): usa una carpeta local."
        case .claseNoPermitida: "La carpeta nueva solo puede ser una copia o una demo, nunca la carpeta real."
        case .fechaDesconocida: "No sé la fecha de la exportación (falta exported_at). Indica --hoy AAAA-MM-DD."
        case .hoyNoValido(let s): "«\(s)» no es una fecha AAAA-MM-DD."
        case .escritura(let r): "No he podido escribir «\(r)» en la carpeta nueva."
        }
    }
}

/// Convierte una carpeta G2 (`tls_type`, `*_id`, importes en céntimos, en inglés) a la estructura v2
/// (SISTEMAS.md §1): áreas `N · Área`, Buzón, Archivo, propiedades del diccionario, relaciones como enlaces
/// legibles, notas índice y CSV de Finanzas. Determinista: la misma entrada da los mismos bytes.
/// No inventa datos: lo que no tiene sitio se apunta en el informe y, si es un fichero entero,
/// se guarda tal cual en `Archivo/Importación <fecha>/`.
public enum ConversorG2 {
    /// `realpath` del tramo que existe más lo que aún no existe.
    static func rutaReal(_ u: URL) -> String {
        var existe = u.standardizedFileURL
        var resto: [String] = []
        while !FileManager.default.fileExists(atPath: existe.path), existe.path != "/" {
            resto.insert(existe.lastPathComponent, at: 0)
            existe.deleteLastPathComponent()
        }
        let base = realpath(existe.path, nil).map { p in defer { free(p) }; return String(cString: p) } ?? existe.path
        return ([base] + resto).joined(separator: "/")
    }

    /// Plan en memoria (para pruebas y para la vista previa). Lee el origen sin descargar nada de iCloud.
    public static func planificar(origen: URL, opciones: OpcionesConversionG2 = .init()) throws -> PlanConversionG2 {
        try comprobar(opciones)
        if AppLocations.isInICloudDrive(origen.standardizedFileURL.path) {
            throw ErrorConversionG2.enICloud(origen.standardizedFileURL.path)
        }
        let carpeta = try G2Carpeta.leer(origen)
        let conversion = try ConversionG2(carpeta: carpeta, opciones: opciones)
        return try conversion.ejecutar()
    }

    /// Convierte `origen` en la carpeta nueva `destino`, que no debe existir. Escribe en una carpeta
    /// temporal junto a `destino` y la renombra al final: o queda entera o no queda nada.
    public static func convertir(origen: URL, destino: URL,
                                 opciones: OpcionesConversionG2 = .init()) async throws -> InformeConversionG2 {
        try comprobar(opciones)
        // Antes de mirar el disco: nada dentro de iCloud Drive, ni para leer ni para escribir.
        if AppLocations.isInICloudDrive(origen.standardizedFileURL.path) {
            throw ErrorConversionG2.enICloud(origen.standardizedFileURL.path)
        }
        if AppLocations.isInICloudDrive(destino.standardizedFileURL.path) {
            throw ErrorConversionG2.enICloud(destino.standardizedFileURL.path)
        }
        let src = origen.standardizedFileURL.resolvingSymlinksInPath()
        let dst = destino.standardizedFileURL
        if AppLocations.isInICloudDrive(src.path) { throw ErrorConversionG2.enICloud(src.path) }
        // Con `realpath` en los dos: `resolvingSymlinksInPath` quita «/private» solo si la ruta existe, y el
        // destino aún no existe (`/private/tmp/x/v2` se colaba dentro de `/tmp/x`).
        let s = TextFolding.pathKey(Self.rutaReal(src)), d = TextFolding.pathKey(Self.rutaReal(dst))
        if d == s || d.hasPrefix(s + "/") { throw ErrorConversionG2.destinoDentroDelOrigen }
        if s.hasPrefix(d + "/") { throw ErrorConversionG2.origenDentroDelDestino }
        if FileManager.default.fileExists(atPath: dst.path) || UbiquityInspector.info(dst) != nil {
            throw ErrorConversionG2.destinoExiste(dst.path)
        }
        var informe = try await DatalessGuard.run("TLSImport.convertir-g2") { _ -> InformeConversionG2 in
            let plan = try planificar(origen: src, opciones: opciones)
            try escribir(plan, en: dst)
            return plan.informe
        }
        let inventario = try await Inventory.make(of: dst, incluirArchivo: true, conHashes: true, completo: true)
        informe.hashArbol = inventario.hashArbol
        informe.destino = dst.path
        return informe
    }

    static func comprobar(_ opciones: OpcionesConversionG2) throws {
        guard opciones.clase != .real else { throw ErrorConversionG2.claseNoPermitida }
        if let hoy = opciones.hoy, !G2Fecha.esDia(hoy) { throw ErrorConversionG2.hoyNoValido(hoy) }
    }

    /// Escribe el plan en una carpeta temporal hermana y la renombra a `destino`.
    static func escribir(_ plan: PlanConversionG2, en destino: URL) throws {
        let fm = FileManager.default
        let padre = destino.deletingLastPathComponent()
        try fm.createDirectory(at: padre, withIntermediateDirectories: true)
        let temporal = padre.appendingPathComponent(".\(destino.lastPathComponent).convirtiendo-\(UUID().uuidString)",
                                                   isDirectory: true)
        try fm.createDirectory(at: temporal, withIntermediateDirectories: false)
        let disco = LocalFileSystem()
        do {
            for (ruta, contenido) in plan.ficheros {
                let url = ruta.url(in: temporal)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch contenido {
                case .texto(let s):
                    guard fm.createFile(atPath: url.path, contents: Data(s.utf8)) else {
                        throw ErrorConversionG2.escritura(ruta.raw)
                    }
                case .copia(let origen):
                    try disco.copyItem(at: origen, to: url)
                }
            }
            // `rename` falla si el destino apareció entretanto: nunca se escribe encima.
            let r = temporal.withUnsafeFileSystemRepresentation { a in
                destino.withUnsafeFileSystemRepresentation { b in renamex_np(a!, b!, UInt32(RENAME_EXCL)) }
            }
            guard r == 0 else { throw ErrorConversionG2.destinoExiste(destino.path) }
        } catch {
            // La carpeta temporal es nuestra y está a medias: se quita para no dejar restos.
            try? fm.removeItem(at: temporal)
            throw error
        }
    }
}
