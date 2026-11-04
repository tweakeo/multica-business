import SwiftUI
import TLSCore
import TLSDesign
import TLSVisores

/// Miniaturas de una empresa (F2, R1): una caché en disco por empresa, en su estado de la app
/// (`<estado>/miniaturas/`, fuera de la carpeta), compartida por todas sus pestañas y ventanas.
@MainActor
enum MiniaturasEmpresa {
    private static var caches: [UUID: CacheMiniaturas] = [:]

    /// La caché de la empresa de `sesion` (`nil` si no se puede crear fuera de su carpeta).
    static func cache(de sesion: VaultSession) -> CacheMiniaturas? {
        if let c = caches[sesion.entry.id] { return c }
        let dir = sesion.directorioEstado.appendingPathComponent("miniaturas", isDirectory: true)
        guard let c = CacheMiniaturas(directorio: dir, carpetaEmpresa: sesion.root) else { return nil }
        caches[sesion.entry.id] = c
        return c
    }

    /// ¿Se puede enseñar la miniatura de esta ruta? Nunca lo privado; solo PDF e imágenes (y vídeo).
    static func sePuedeEnsenar(_ ruta: VaultPath, sesion: VaultSession) -> Bool {
        guard !sesion.esPrivado(ruta) else { return false }
        return TipoFichero.de(extension: ruta.ext).tieneMiniatura
    }
}

/// Miniatura de un fichero de la carpeta (la primera página de un PDF, una imagen reducida) con la caché de la
/// empresa. Lo privado no se pinta nunca: enseña el icono del tipo. Lo que está solo en iCloud tampoco se
/// descarga. Para la Galería de las bases: `MiniaturaDeRuta(ruta: doc, sesion: sesion, lado: 120)`.
struct MiniaturaDeRuta: View {
    let ruta: VaultPath
    let sesion: VaultSession
    let pagina: Int
    let lado: CGFloat

    init(ruta: VaultPath, sesion: VaultSession, pagina: Int = 1, lado: CGFloat = 240) {
        self.ruta = ruta
        self.sesion = sesion
        self.pagina = pagina
        self.lado = lado
    }

    var body: some View {
        if MiniaturasEmpresa.sePuedeEnsenar(ruta, sesion: sesion), let url = sesion.url(for: ruta) {
            MiniaturaConCache(url: url, pagina: pagina, lado: lado, cache: MiniaturasEmpresa.cache(de: sesion))
        } else {
            Image(systemName: TipoFichero.de(extension: ruta.ext).simbolo)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("\(TipoFichero.de(extension: ruta.ext).nombre) \(ruta.name)")
        }
    }
}
