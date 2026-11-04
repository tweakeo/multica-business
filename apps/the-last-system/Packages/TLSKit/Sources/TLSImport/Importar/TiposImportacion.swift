import Foundation
import TLSCore

// Paso 2 de la puesta en marcha, «Ordenar lo que tienes» (PLAN §6.7 y §9 F3). Tipos comunes.
//
// Reglas que no se rompen (las comprueban las pruebas de `Tests/TLSImportTests/Importar`):
// - Nada se escribe antes de «Aplicar»: inventario, clasificación, zona de preparación y vista previa solo leen.
// - Nunca se borra nada: retirar es mover a `Archivo/`; importar no sobrescribe y se verifica (recuento y SHA-256).
// - Lo privado no se lista, no se lee, no se copia, no se clasifica con IA y no se enseña.
// - Nada se descarga de iCloud al recorrer: lo que solo está en la nube se clasifica por su nombre.

/// De qué programa viene un bloque de ficheros. Se deduce por señales del propio bloque (nombres, extensiones,
/// carpetas de ajustes) sin abrir nada que no esté ya en el Mac.
public enum HerramientaOrigen: String, Sendable, Codable, Hashable, CaseIterable, Comparable {
    /// Ya sigue la estructura de The Last System (áreas `N · Nombre`, `Buzón`, `Empresa.md`).
    case ordenada
    case notion
    case drive
    case obsidian
    case correo
    /// Carpetas y ficheros sueltos, sin un programa reconocible.
    case carpetas

    /// Nombre para la persona.
    public var nombre: String {
        switch self {
        case .ordenada: "Ya ordenado"
        case .notion: "Exportación de Notion"
        case .drive: "Google Drive"
        case .obsidian: "Obsidian"
        case .correo: "Correo exportado"
        case .carpetas: "Carpetas sueltas"
        }
    }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Qué clase de fichero es (por su extensión; nunca se abre para saberlo).
public enum TipoDocumento: String, Sendable, Codable, Hashable, CaseIterable, Comparable {
    case nota, texto, pdf, imagen, hoja, documento, presentacion, correo, audio, video, web, comprimido, paquete, otro

    public var nombre: String {
        switch self {
        case .nota: "Notas"
        case .texto: "Textos"
        case .pdf: "PDF"
        case .imagen: "Imágenes"
        case .hoja: "Hojas de cálculo"
        case .documento: "Documentos"
        case .presentacion: "Presentaciones"
        case .correo: "Correos"
        case .audio: "Audios"
        case .video: "Vídeos"
        case .web: "Páginas web"
        case .comprimido: "Comprimidos"
        case .paquete: "Documentos de Apple y aplicaciones"
        case .otro: "Otros"
        }
    }

    /// Extensiones que macOS trata como un solo documento aunque sean carpetas: se mueven enteras.
    public static let extensionesPaquete: Set<String> = [
        "numbers", "pages", "key", "app", "rtfd", "bundle", "photoslibrary", "band", "logicx", "fcpbundle", "scriv",
    ]

    public init(extension ext: String, esCarpeta: Bool = false) {
        let e = ext.lowercased()
        if esCarpeta { self = Self.extensionesPaquete.contains(e) ? .paquete : .otro; return }
        switch e {
        case "md", "markdown": self = .nota
        case "txt", "rtf", "text": self = .texto
        case "pdf": self = .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "svg", "bmp": self = .imagen
        case "xlsx", "xls", "csv", "tsv", "ods", "numbers", "gsheet": self = .hoja
        case "docx", "doc", "odt", "pages", "gdoc": self = .documento
        case "pptx", "ppt", "odp", "key", "gslides": self = .presentacion
        case "eml", "emlx", "mbox", "msg": self = .correo
        case "mp3", "m4a", "wav", "aac", "aiff", "ogg", "flac": self = .audio
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": self = .video
        case "html", "htm", "webarchive", "url", "webloc": self = .web
        case "zip", "rar", "7z", "gz", "tar", "tgz", "dmg": self = .comprimido
        default: self = .otro
        }
    }

    /// Extensiones cuyo contenido es texto y se puede leer sin programas externos (para buscar pistas).
    public static let extensionesDeTexto: Set<String> = ["md", "markdown", "txt", "text", "csv", "tsv", "html", "htm", "eml", "emlx"]

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Una carpeta de la que se importa.
///
/// - `.carpetaDeLaEmpresa`: la copia de trabajo (o el ejemplo) que se ordena por dentro: lo que se lleva a su
///   sitio se **mueve** con el escritor (y se puede deshacer).
/// - `.externa`: otra carpeta (una exportación de Notion, una carpeta de Drive…): solo se **lee** y lo elegido se
///   **copia** a la carpeta de la empresa. El original no cambia.
public struct FuenteImportacion: Sendable, Hashable, Codable {
    public enum Clase: String, Sendable, Hashable, Codable { case carpetaDeLaEmpresa, externa }

    /// Nombre corto y único (primera parte de `origen` en el mapa: `Carpeta/Clientes/ana.md`).
    public var alias: String
    public var raiz: URL
    public var clase: Clase
    /// Rutas privadas (relativas a `raiz`): no se listan ni se leen. Se suman a `privado` de `.tls/`, si lo hay.
    public var privado: [VaultPath]
    /// Lo que la persona deja fuera antes de empezar (no se lista).
    public var exclusiones: [VaultPath]

    public init(alias: String, raiz: URL, clase: Clase, privado: [VaultPath] = [], exclusiones: [VaultPath] = []) {
        self.alias = NombresDeFicha.fichero(alias).isEmpty ? "Fuente" : NombresDeFicha.fichero(alias)
        self.raiz = raiz; self.clase = clase; self.privado = privado; self.exclusiones = exclusiones
    }

    /// Alias de la carpeta de la empresa en el mapa (`Carpeta/Clientes/ana.md`).
    public static let aliasDeLaEmpresa = "Carpeta"

    /// La carpeta de la empresa: alias «Carpeta».
    public static func carpetaDeLaEmpresa(_ raiz: URL, privado: [VaultPath] = [], exclusiones: [VaultPath] = []) -> FuenteImportacion {
        FuenteImportacion(alias: aliasDeLaEmpresa, raiz: raiz, clase: .carpetaDeLaEmpresa, privado: privado, exclusiones: exclusiones)
    }

    /// Lo que se dejó fuera al hacer la copia (`exclusionesCopia`), visto desde la copia. Esas rutas son de la carpeta
    /// real: en la copia no están (no se copiaron), así que no se exige que existan; solo se siguen dejando fuera las
    /// que existen. `Archivo/` nunca cuenta: no se copió por tamaño y en la copia es el Archivo de verdad (adonde se
    /// retira y se apartan los repetidos). Solo mira con `lstat`: no descarga nada.
    public static func exclusionesDeLaCopia(_ rutas: [VaultPath], raiz: URL, archivo: String = "Archivo",
                                            fileSystem: any FileSystemAccess = LocalFileSystem()) -> [VaultPath] {
        let base = raiz.standardizedFileURL.resolvingSymlinksInPath()
        let kArchivo = TextFolding.pathKey(archivo)
        return rutas.filter { r in
            !r.isRoot && TextFolding.pathKey(r.raw) != kArchivo && fileSystem.fileExists(r.url(in: base))
        }
    }
}

/// «Todo / lo activo / nada» de una herramienta (con fecha de corte para «lo activo»).
public enum AlcanceImportacion: Sendable, Hashable, Codable {
    /// Todo va a su sitio.
    case todo
    /// Lo que tiene fecha (o se modificó) desde ese día va a su sitio; lo anterior, a `Archivo/Importación <fecha>/`.
    case loActivo(desde: LocalDate)
    /// No se toca: en la carpeta de la empresa se queda donde está; de fuera no se trae.
    case nada

    public var nombre: String {
        switch self {
        case .todo: "Todo"
        case .loActivo(let d): "Lo activo (desde el \(FormatoFechaImportacion.corta(d)))"
        case .nada: "Nada"
        }
    }
}

/// Errores del paso 2, con texto para la persona.
public enum ImportError: Error, LocalizedError, Sendable, Equatable {
    case fuenteNoAccesible(String)
    case fuenteDentroDeLaCarpeta(String)
    case aliasRepetido(String)
    case enlacesEnRiesgo(Int)
    case demasiadoGrande(Int64)
    case deshacerNoDisponible
    case cambioDesdeLaVistaPrevia(String)
    case sinNadaQueHacer
    case mapaIlegible(String)
    case verificacionFallida(Int)
    /// Los ajustes de la carpeta no se pueden leer: no se puede apuntar lo que marcaste como privado.
    case ajustesIlegibles

    public var errorDescription: String? {
        switch self {
        case .fuenteNoAccesible(let p):
            "No puedo leer «\(p)». Revisa el permiso en Ajustes del Sistema › Privacidad y seguridad."
        case .fuenteDentroDeLaCarpeta(let p):
            "«\(p)» ya está dentro de la carpeta de tu empresa: la ordeno ahí mismo, no hace falta traerla."
        case .aliasRepetido(let a): "Hay dos carpetas con el nombre «\(a)». Cámbiale el nombre a una."
        case .enlacesEnRiesgo(let n):
            "\(n == 1 ? "Un enlace dejaría" : "\(n) enlaces dejarían") de apuntar a su nota. Revísalos antes de aplicar."
        case .demasiadoGrande(let b):
            "Es demasiado para una sola vez (\(ByteCountFormatter.string(fromByteCount: b, countStyle: .file))). Hazlo por bloques."
        case .deshacerNoDisponible:
            "Después de ordenar se han hecho otros cambios. Para deshacer la importación, deshaz antes esos cambios."
        case .cambioDesdeLaVistaPrevia(let p):
            "«\(p)» ha cambiado desde la vista previa. Vuelve a prepararla: no aplico nada sobre lo que no has visto."
        case .sinNadaQueHacer: "No hay nada que mover, copiar ni archivar."
        case .mapaIlegible(let m): "No puedo leer el mapa de la importación: \(m)"
        case .ajustesIlegibles:
            "No puedo leer los ajustes de tu carpeta para apuntar lo que has marcado como privado. No aplico nada: revísalos antes de seguir."
        case .verificacionFallida(let n):
            "\(n == 1 ? "Un fichero no coincide" : "\(n) ficheros no coinciden") con el original. No se ha borrado nada: revisa el informe."
        }
    }
}

/// Fechas como las escribe la app para la persona.
enum FormatoFechaImportacion {
    static let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]

    /// «19 oct 2026».
    static func corta(_ d: LocalDate) -> String { "\(d.day) \(meses[d.month - 1]) \(d.year)" }

    /// Trimestre `T1`…`T4`.
    static func trimestre(_ mes: Int) -> String { "T\((mes - 1) / 3 + 1)" }
}

/// Patrones que nunca se leen, se copian ni se envían a nadie (PLAN §8: claves y contraseñas).
enum FicherosSensibles {
    static let nombres: Set<String> = ["secrets.env", "cookies.txt", "escritor.json", "id_rsa", "id_ed25519", "credentials.json",
                                       "keychain.json"]
    static let extensiones: Set<String> = ["env", "p12", "pfx", "pem", "kdbx", "keychain", "keychain-db", "ovpn",
                                           "mobileprovision", "cer", "crt"]

    /// Por el nombre, sin abrirlo. `.key` es también Keynote: cuenta como clave solo si es un fichero pequeño
    /// (una presentación ocupa mucho más; las de carpeta son paquetes).
    static func esSensible(_ p: VaultPath, tamano: Int64?, esCarpeta: Bool) -> Bool {
        let n = p.name.lowercased()
        if nombres.contains(n) || n.hasPrefix(".env") { return true }
        if p.ext == "key" { return !esCarpeta && (tamano ?? 0) < 64 * 1024 }
        return !esCarpeta && extensiones.contains(p.ext)
    }
}

/// «1 fichero», «3 ficheros».
enum Plural {
    static func de(_ n: Int, _ uno: String, _ varios: String) -> String { n == 1 ? "1 \(uno)" : "\(n) \(varios)" }

    static func lista(_ partes: [String]) -> String {
        guard partes.count > 1 else { return partes.first ?? "" }
        return partes.dropLast().joined(separator: ", ") + " y " + partes.last!
    }
}
