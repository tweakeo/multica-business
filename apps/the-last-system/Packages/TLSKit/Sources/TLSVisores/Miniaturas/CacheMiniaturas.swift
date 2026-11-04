import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import TLSDesign
import UniformTypeIdentifiers

/// Caché en disco de miniaturas (F2, R1: la primera página de los PDF en la Galería de las bases).
///
/// - Vive **fuera de la carpeta de la empresa**, en su estado de la app (`<estado>/miniaturas/`): `init` se niega
///   si el directorio queda dentro de la carpeta o en iCloud Drive.
/// - **Nunca descarga de iCloud**: lo que no está en el Mac no se pinta (y no se guarda nada). Las fechas y tamaños
///   se leen con `lstat`, que no descarga.
/// - La clave es la ruta, el tamaño, la fecha de modificación, la página y el lado: si el fichero cambia, la
///   miniatura vieja deja de usarse (y se borra con las más antiguas al pasar de `maximo`).
/// - Quien la usa decide qué se puede enseñar: **nunca se le pasa una ruta privada** (en TLSUI,
///   `MiniaturaDeRuta` lo comprueba con la sesión).
public final class CacheMiniaturas: @unchecked Sendable {
    public let directorio: URL
    /// Cuántas miniaturas se guardan como mucho (las más antiguas se borran).
    public let maximo: Int
    private let memoria = NSCache<NSString, CajaImagen>()
    private let lock = NSLock()
    private var escritas = 0

    /// `nil` si `directorio` queda dentro de `carpetaEmpresa` o en iCloud Drive.
    public init?(directorio: URL, carpetaEmpresa: URL?, maximo: Int = 2_000) {
        let dir = directorio.standardizedFileURL
        if Self.dentroDeICloudDrive(dir.path) { return nil }
        if let carpetaEmpresa {
            let raiz = Self.canonica(carpetaEmpresa)
            let d = Self.canonica(dir)
            if d == raiz || d.hasPrefix(raiz + "/") { return nil }
        }
        self.directorio = dir
        self.maximo = maximo
        memoria.countLimit = 300
    }

    /// La miniatura de `url` (de la caché o pintada y guardada). `nil` si no está en el Mac o no se puede pintar.
    public func miniatura(url: URL, tipo: TipoFichero? = nil, pagina: Int = 1, lado: CGFloat = 480,
                          acceso: any AccesoICloud = AccesoICloudSistema()) async -> ImagenMiniatura? {
        guard acceso.estado(de: url) == .local, let clave = Self.clave(url: url, pagina: pagina, lado: lado) else { return nil }
        if let caja = memoria.object(forKey: clave as NSString) { return caja.imagen }
        let fichero = ruta(de: clave)
        if let leida = await Task.detached(priority: .utility, operation: { Self.leerPNG(fichero) }).value {
            memoria.setObject(CajaImagen(leida), forKey: clave as NSString)
            return leida
        }
        guard let nueva = await MiniaturaFichero.generar(url: url, tipo: tipo, pagina: pagina, lado: lado, acceso: acceso) else {
            return nil
        }
        memoria.setObject(CajaImagen(nueva), forKey: clave as NSString)
        let directorio = self.directorio
        let podar = lock.withLock { () -> Bool in
            escritas += 1
            return escritas % 50 == 1
        }
        let maximo = self.maximo
        await Task.detached(priority: .utility) {
            Self.guardarPNG(nueva, en: fichero, directorio: directorio)
            if podar { Self.podar(directorio, maximo: maximo) }
        }.value
        return nueva
    }

    /// Fichero de la caché para una clave (dos niveles para no llenar una sola carpeta).
    func ruta(de clave: String) -> URL {
        directorio.appendingPathComponent(String(clave.prefix(2)), isDirectory: true)
            .appendingPathComponent(clave + ".png")
    }

    /// Borra toda la caché (es desechable).
    public func vaciar() {
        memoria.removeAllObjects()
        try? FileManager.default.removeItem(at: directorio)
    }

    // MARK: Apoyo

    /// Clave estable: SHA-256 de ruta, tamaño, fecha de modificación (ns), página y lado. `nil` si no existe.
    static func clave(url: URL, pagina: Int, lado: CGFloat) -> String? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let mtime = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        let texto = "\(url.standardizedFileURL.path.precomposedStringWithCanonicalMapping)|\(st.st_size)|\(mtime)|\(pagina)|\(Int(lado))"
        return SHA256.hash(data: Data(texto.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func leerPNG(_ url: URL) -> ImagenMiniatura? {
        guard FileManager.default.fileExists(atPath: url.path),
              let fuente = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(fuente, 0, nil) else { return nil }
        // Se toca para que «podar» borre antes las que no se usan.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return ImagenMiniatura(cg: cg)
    }

    static func guardarPNG(_ imagen: ImagenMiniatura, en url: URL, directorio: URL) {
        let fm = FileManager.default
        let carpeta = url.deletingLastPathComponent()
        try? fm.createDirectory(at: directorio, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: carpeta, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let datos = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(datos, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destino, imagen.cg, nil)
        guard CGImageDestinationFinalize(destino) else { return }
        try? (datos as Data).write(to: url, options: [.atomic])
    }

    /// Deja como mucho `maximo` miniaturas: borra las que hace más que no se usan.
    static func podar(_ directorio: URL, maximo: Int) {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: directorio, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return }
        var ficheros: [(URL, Date)] = []
        for case let u as URL in it where u.pathExtension == "png" {
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if v?.isRegularFile == true { ficheros.append((u, v?.contentModificationDate ?? .distantPast)) }
        }
        guard ficheros.count > maximo else { return }
        for (u, _) in ficheros.sorted(by: { $0.1 < $1.1 }).prefix(ficheros.count - maximo) {
            try? fm.removeItem(at: u)
        }
    }

    static func canonica(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func dentroDeICloudDrive(_ path: String) -> Bool {
        path.contains("/Library/Mobile Documents/")
    }
}

/// Envoltorio para `NSCache` (que pide una clase).
final class CajaImagen: @unchecked Sendable {
    let imagen: ImagenMiniatura
    init(_ imagen: ImagenMiniatura) { self.imagen = imagen }
}

/// Miniatura con caché en disco: como `MiniaturaFicheroVista`, pero la pinta una sola vez por versión del fichero.
/// Mientras tanto, o si está solo en iCloud, enseña el icono del tipo. Nunca descarga.
public struct MiniaturaConCache: View {
    let url: URL
    let tipo: TipoFichero
    let pagina: Int
    let lado: CGFloat
    let cache: CacheMiniaturas?
    let acceso: any AccesoICloud
    @State private var imagen: ImagenMiniatura?
    @State private var enICloud = false

    public init(url: URL, tipo: TipoFichero? = nil, pagina: Int = 1, lado: CGFloat = 240, cache: CacheMiniaturas?,
                acceso: any AccesoICloud = AccesoICloudSistema()) {
        self.url = url
        self.tipo = tipo ?? TipoFichero.de(extension: url.pathExtension)
        self.pagina = pagina
        self.lado = lado
        self.cache = cache
        self.acceso = acceso
    }

    public var body: some View {
        ZStack {
            if let imagen {
                Image(decorative: imagen.cg, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: enICloud ? "icloud.and.arrow.down" : tipo.simbolo)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(url.path)#\(pagina)#\(Int(lado))") {
            enICloud = { if case .soloEnICloud = acceso.estado(de: url) { return true }; return false }()
            guard !enICloud else { imagen = nil; return }
            if let cache {
                imagen = await cache.miniatura(url: url, tipo: tipo, pagina: pagina, lado: lado, acceso: acceso)
            } else {
                imagen = await MiniaturaFichero.generar(url: url, tipo: tipo, pagina: pagina, lado: lado, acceso: acceso)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(enICloud ? "\(tipo.nombre) \(url.lastPathComponent), está en iCloud"
                                     : "\(tipo.nombre) \(url.lastPathComponent)" + (tipo == .pdf ? (pagina == 1 ? ", primera página" : ", página \(pagina)") : ""))
    }
}
