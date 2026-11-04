// Procedencia: lógica portada a Swift desde la unificación de octubre (`fase2_enlaces.py`, autor: Manuel Trigo):
// cada enlace se resuelve en el sitio viejo, se lleva por el registro de movimientos al sitio nuevo y se vuelve a
// escribir relativo a la nota en su sitio nuevo, con el mismo estilo (`%20` o `<…>`), y lo que no resuelve se
// informa. Reescrito sobre `LinkScanner` del núcleo; sin código copiado. Ver docs/PROCEDENCIA.md.

import Foundation
import TLSCore

/// Enlaces de las notas que se traen de una carpeta de fuera.
///
/// Dentro de la carpeta de la empresa los enlaces los actualiza `LinkRefactor` (mismo plan que los movimientos).
/// Lo que se copia de fuera llega con texto nuevo: aquí se reescribe antes de crearlo, para que cada enlace siga
/// apuntando a lo mismo en su sitio nuevo:
/// - Markdown relativo (`../Clientes/Ana.md`, con `%20` o `<…>`) y absoluto dentro de la carpeta de origen
///   (`/Users/…/Origen/Clientes/Ana.md`, típico de exportaciones);
/// - wikilinks (`[[Ana]]`, `[[Clientes/Ana|Ana]]`) cuando la nota cambia de nombre al hacerse ficha.
/// Solo cambia el destino de cada enlace: el resto de bytes no.
struct LinkRewriter {
    /// Ruta en la fuente (clave `pathKey`) → ruta final en la carpeta de la empresa, de todo lo que se trae.
    let destinos: [String: VaultPath]
    /// Raíz de la carpeta de origen (para los enlaces absolutos).
    let raizFuente: String
    /// Ficheros de la fuente por nombre (clave `nameKey` del nombre y del nombre sin `.md`), para los wikilinks.
    let porNombre: [String: [VaultPath]]
    /// Todos los ficheros de la fuente (clave `pathKey`): un enlace a uno que no se trae se queda roto.
    let ficheros: Set<String>

    init(destinos: [VaultPath: VaultPath], raizFuente: URL, ficherosDeLaFuente: [VaultPath]) {
        var d: [String: VaultPath] = [:]
        for (k, v) in destinos { d[TextFolding.pathKey(k.raw)] = v }
        self.destinos = d
        self.raizFuente = CopyJob.canonicalPath(raizFuente).precomposedStringWithCanonicalMapping
        var n: [String: [VaultPath]] = [:]
        for p in ficherosDeLaFuente {
            n[TextFolding.nameKey(p.name), default: []].append(p)
            if p.ext == "md" { n[TextFolding.nameKey(p.stem), default: []].append(p) }
        }
        self.porNombre = n
        self.ficheros = Set(ficherosDeLaFuente.map { TextFolding.pathKey($0.raw) })
    }

    struct Resultado {
        var texto: String
        var cambios = 0
        /// Enlaces que no apuntan a nada de lo que se trae (se dejan como estaban).
        var sinDestino: [String] = []
        /// De esos, los que llevan a un fichero de la fuente que no se trae: en la carpeta quedarán rotos (se avisa).
        var quedanRotos: [(enlace: String, linea: Int, destino: VaultPath)] = []
    }

    /// Reescribe los enlaces de `texto` (sin BOM) de la nota `origen` (en la fuente) que acabará en `destino`.
    func reescribir(_ texto: String, origen: VaultPath, destino: VaultPath) -> Resultado {
        let texto = absolutosConEspacios(texto)
        var bytes = Array(texto.utf8)
        var r = Resultado(texto: texto)
        var cambios: [(Range<Int>, String)] = []
        for occ in LinkScanner.scan(texto) {
            let link = occ.link
            if link.isExternal || link.target.isEmpty || occ.isReference { continue }
            switch link.style {
            case .markdown:
                guard let nuevo = nuevoMarkdown(link.target, angle: occ.angle, origen: origen, destino: destino) else {
                    if !link.target.hasPrefix("#") {
                        r.sinDestino.append(link.target)
                        if let f = enLaFuente(link.target, origen: origen), ficheros.contains(TextFolding.pathKey(f.raw)) {
                            r.quedanRotos.append((link.target, occ.line, f))
                        }
                    }
                    continue
                }
                if nuevo != link.target { cambios.append((occ.targetRange, nuevo)) }
            case .wiki:
                guard let w = nuevoWiki(link.target) else { continue }
                // Si cambia el nombre que se ve y no tenía alias, se pone el de antes como texto visible.
                if occ.labelRange == nil, occ.lugar == .cuerpo, w.1 != nil, link.anchor == nil {
                    cambios.append((occ.targetRange, w.0 + "|" + link.target))
                } else {
                    cambios.append((occ.targetRange, w.0))
                }
            }
        }
        for (rango, nuevo) in cambios.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            bytes.replaceSubrange(rango, with: Array(nuevo.utf8))
            r.cambios += 1
        }
        r.texto = String(decoding: bytes, as: UTF8.self)
        return r
    }

    static let absolutoConEspacios = try! NSRegularExpression(pattern: #"\]\((/[^)<>\n]* [^)<>\n]*)\)"#)

    /// Enlaces absolutos con espacios sin codificar (`](/Users/…/Mi carpeta/x.md)`, que algunas notas tienen aunque
    /// no sean Markdown válido): si llevan dentro del origen, se escriben con `%20` para que se lean como enlace.
    func absolutosConEspacios(_ texto: String) -> String {
        let ns = texto as NSString
        var out = texto
        for m in Self.absolutoConEspacios.matches(in: texto, range: NSRange(location: 0, length: ns.length)).reversed() {
            let ruta = ns.substring(with: m.range(at: 1))
            let abs = CopyJob.canonicalPath(URL(fileURLWithPath: ruta)).precomposedStringWithCanonicalMapping
            guard TextFolding.pathKey(abs).hasPrefix(TextFolding.pathKey(raizFuente) + "/"),
                  let r = Range(m.range(at: 1), in: out) else { continue }
            out.replaceSubrange(r, with: Self.codificar(ruta))
        }
        return out
    }

    /// Adónde lleva un enlace Markdown dentro de la fuente (relativo o absoluto dentro de ella), o `nil`.
    func enLaFuente(_ escrito: String, origen: VaultPath) -> VaultPath? {
        let decodificado = escrito.removingPercentEncoding ?? escrito
        if decodificado.hasPrefix("/") {
            // Con la ruta real (`/tmp` es `/private/tmp`), aunque el destino ya no exista.
            let abs = CopyJob.canonicalPath(URL(fileURLWithPath: decodificado)).precomposedStringWithCanonicalMapping
            guard TextFolding.pathKey(abs).hasPrefix(TextFolding.pathKey(raizFuente) + "/") else { return nil }
            return VaultPath(String(abs.dropFirst(raizFuente.count + 1)))
        }
        return origen.resolvingRelative(escrito)
    }

    /// Destino Markdown nuevo, o `nil` si no apunta a nada de lo que se trae.
    func nuevoMarkdown(_ escrito: String, angle: Bool, origen: VaultPath, destino: VaultPath) -> String? {
        let decodificado = escrito.removingPercentEncoding ?? escrito
        guard let viejo = enLaFuente(escrito, origen: origen), let nuevoDestino = destinos[TextFolding.pathKey(viejo.raw)] else { return nil }
        let rel = Self.relativa(desde: destino, a: nuevoDestino)
        // Sigue resolviendo igual (mismo sitio relativo): no se toca.
        if destino.resolvingRelative(escrito).map({ TextFolding.pathKey($0.raw) }) == TextFolding.pathKey(nuevoDestino.raw),
           !decodificado.hasPrefix("/") {
            return escrito
        }
        return angle ? rel : Self.codificar(rel)
    }

    /// Wikilink a una nota que cambia de nombre: el nombre nuevo (y el viejo para el alias).
    func nuevoWiki(_ escrito: String) -> (String, String?)? {
        let clave = TextFolding.nameKey(VaultPath(escrito).name)
        let candidatos = porNombre[clave] ?? porNombre[TextFolding.nameKey(escrito)] ?? []
        guard candidatos.count == 1, let nuevo = destinos[TextFolding.pathKey(candidatos[0].raw)] else { return nil }
        let viejoNombre = candidatos[0].ext == "md" ? candidatos[0].stem : candidatos[0].name
        let nuevoNombre = nuevo.ext == "md" ? nuevo.stem : nuevo.name
        guard TextFolding.nameKey(viejoNombre) != TextFolding.nameKey(nuevoNombre) || escrito.contains("/") else { return nil }
        return (nuevoNombre, viejoNombre != nuevoNombre ? viejoNombre : nil)
    }

    /// Ruta relativa de la carpeta de `desde` a `a` (`../Empresas/x.md`).
    static func relativa(desde: VaultPath, a: VaultPath) -> String {
        let base = desde.parent?.components ?? []
        let dest = a.components
        var comun = 0
        while comun < base.count, comun < dest.count - 1, base[comun] == dest[comun] { comun += 1 }
        let subir = Array(repeating: "..", count: base.count - comun)
        return (subir + dest[comun...]).joined(separator: "/")
    }

    /// Estilo de G3: los espacios como `%20` y los paréntesis codificados (para no cortar el enlace).
    static func codificar(_ rel: String) -> String {
        rel.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
    }
}
