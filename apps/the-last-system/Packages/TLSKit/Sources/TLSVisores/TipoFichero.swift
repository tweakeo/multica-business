import Foundation
import UniformTypeIdentifiers

// La clasificación por tipo la usa el enrutador de TLSUI para decidir entre «nota» y «fichero» (cimientos) y
// los visores para elegir cómo enseñar cada fichero (R1). Se amplía sin cambiar los casos. Contrato:
// docs/F1-INTERFAZ-CONTRATOS.md.

/// Qué visor abre un fichero de la carpeta (R1 de REQUISITOS-ADICIONALES).
public enum TipoFichero: String, Sendable, Hashable, CaseIterable {
    /// Markdown, texto y CSV: se abren como nota (editor), no con un visor.
    case texto
    case pdf
    /// png, jpg, heic, gif, webp, tiff, svg…
    case imagen
    case audio
    case video
    /// Todo lo demás: vista previa de Quick Look con «Abrir con…».
    case otro

    /// Por la extensión (sin leer el fichero ni descargarlo de iCloud).
    public static func de(extension ext: String) -> TipoFichero {
        let e = ext.lowercased()
        switch e {
        case "md", "markdown", "txt", "csv", "tsv": return .texto
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp", "svg": return .imagen
        case "mp3", "m4a", "wav", "aif", "aiff", "aac", "flac", "caf": return .audio
        case "mov", "mp4", "m4v", "avi", "mkv": return .video
        default: break
        }
        guard !e.isEmpty, let ut = UTType(filenameExtension: e) else { return .otro }
        if ut.conforms(to: .pdf) { return .pdf }
        if ut.conforms(to: .image) { return .imagen }
        if ut.conforms(to: .audio) { return .audio }
        if ut.conforms(to: .movie) || ut.conforms(to: .video) { return .video }
        if ut.conforms(to: .plainText) { return .texto }
        return .otro
    }

    /// Por el nombre o la ruta del fichero (`acta.pdf`, `Materiales/logo.svg`).
    public static func de(nombre: String) -> TipoFichero {
        let ultimo = nombre.split(separator: "/").last.map(String.init) ?? nombre
        guard let punto = ultimo.lastIndex(of: "."), punto != ultimo.startIndex else { return .otro }
        return de(extension: String(ultimo[ultimo.index(after: punto)...]))
    }

    /// `true` si se abre con un visor (no con el editor de notas).
    public var esVisor: Bool { self != .texto }

    /// `true` si `![[…]]` lo pinta dentro de la nota (PDF, imagen, audio y vídeo). El resto sale como
    /// tarjeta con su nombre y «Abrir».
    public var seIncrusta: Bool {
        switch self {
        case .pdf, .imagen, .audio, .video: true
        case .texto, .otro: false
        }
    }

    /// `true` si tiene miniatura propia (primera página de un PDF, la imagen o un fotograma del vídeo).
    public var tieneMiniatura: Bool {
        switch self {
        case .pdf, .imagen, .video: true
        case .texto, .audio, .otro: false
        }
    }

    /// SF Symbol del tipo.
    public var simbolo: String {
        switch self {
        case .texto: "doc.text"
        case .pdf: "doc.richtext"
        case .imagen: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .otro: "doc"
        }
    }

    /// Nombre para la persona («PDF», «Imagen»…).
    public var nombre: String {
        switch self {
        case .texto: "Nota"
        case .pdf: "PDF"
        case .imagen: "Imagen"
        case .audio: "Audio"
        case .video: "Vídeo"
        case .otro: "Fichero"
        }
    }

    /// Con artículo, para frases («este PDF», «esta imagen»).
    public var conEste: String {
        switch self {
        case .texto: "esta nota"
        case .pdf: "este PDF"
        case .imagen: "esta imagen"
        case .audio: "este audio"
        case .video: "este vídeo"
        case .otro: "este fichero"
        }
    }
}

/// Tamaño de un fichero en texto llano («145 KB», «2,3 MB»).
public enum TamanoFichero {
    public static func texto(_ bytes: Int64?) -> String? {
        guard let bytes, bytes >= 0 else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: bytes)
    }
}
