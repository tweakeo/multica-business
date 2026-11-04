import Foundation
import TLSCore

/// Una nota de la carpeta G2: frontmatter con su árbol completo y cuerpo tal cual.
struct G2Registro: Sendable {
    let ruta: VaultPath
    /// `tls_type`, si lo tiene.
    let tipo: String?
    let campos: G2Mapa
    /// Texto tras el frontmatter (sin tocar).
    let cuerpo: String
    /// Primer `# Título` del cuerpo.
    let titulo: String?
    let tieneFrontmatter: Bool
    /// El frontmatter existe pero no se pudo leer.
    let ilegible: Bool

    var id: String? { campos.texto("id") }

    /// Cuerpo sin espacios ni saltos alrededor; `nil` si está vacío.
    var cuerpoUtil: String? {
        let t = cuerpo.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Nombre del fichero sin la huella `--1a2b3c4d` que añade G2.
    var stemLimpio: String { Nombres.sinHuellaG2(ruta.stem) }
}

/// Fichero que no es una nota (PDF, CSV…).
struct G2Fichero: Sendable {
    let ruta: VaultPath
    let url: URL
    let tamano: Int64
}

/// Lo leído de una carpeta G2 (la «carpeta portable» de la demo antigua).
struct G2Carpeta: Sendable {
    let raiz: URL
    let registros: [G2Registro]
    let ficheros: [G2Fichero]
    /// Ficheros que están solo en iCloud: no se leen ni se convierten.
    let soloEnICloud: [VaultPath]
    /// Enlaces simbólicos: no se siguen.
    let enlaces: [VaultPath]

    var total: Int { registros.count + ficheros.count + soloEnICloud.count + enlaces.count }

    func registros(_ tipo: String) -> [G2Registro] {
        registros.filter { $0.tipo == tipo }
    }

    /// Lee la carpeta sin descargar nada de iCloud (en este hilo) y sin seguir enlaces.
    /// Se saltan los nombres que empiezan por punto (`.DS_Store`, `.obsidian`…).
    static func leer(_ raiz: URL) throws -> G2Carpeta {
        try UbiquityInspector.withoutMaterializing {
            try leerProtegido(raiz.standardizedFileURL.resolvingSymlinksInPath())
        }
    }

    private static func leerProtegido(_ raiz: URL) throws -> G2Carpeta {
        guard let info = UbiquityInspector.info(raiz), info.isDirectory else {
            throw ErrorConversionG2.origenNoAccesible(raiz.path)
        }
        var registros: [G2Registro] = []
        var ficheros: [G2Fichero] = []
        var soloICloud: [VaultPath] = []
        var enlaces: [VaultPath] = []
        var pendientes: [VaultPath] = [.root]
        let fm = FileManager.default
        while let carpeta = pendientes.popLast() {
            let url = carpeta.url(in: raiz)
            let nombres: [String]
            do {
                nombres = try fm.contentsOfDirectory(atPath: url.path)
            } catch {
                throw ErrorConversionG2.lectura(carpeta.isRoot ? "." : carpeta.raw)
            }
            for nombre in nombres.sorted() where !nombre.hasPrefix(".") {
                let ruta = carpeta.appending(nombre)
                let u = ruta.url(in: raiz)
                guard let i = UbiquityInspector.info(u) else { continue }
                if i.isSymlink { enlaces.append(ruta); continue }
                if i.dataless { soloICloud.append(ruta); continue }
                if i.isDirectory { pendientes.append(ruta); continue }
                if ruta.ext == "md" {
                    guard let data = fm.contents(atPath: u.path), let texto = TextDecoding.decode(data) else {
                        throw ErrorConversionG2.lectura(ruta.raw)
                    }
                    registros.append(registro(ruta: ruta, texto: texto))
                } else {
                    ficheros.append(G2Fichero(ruta: ruta, url: u, tamano: i.size))
                }
            }
        }
        return G2Carpeta(raiz: raiz,
                         registros: registros.sorted { $0.ruta.raw < $1.ruta.raw },
                         ficheros: ficheros.sorted { $0.ruta.raw < $1.ruta.raw },
                         soloEnICloud: soloICloud.sorted { $0.raw < $1.raw },
                         enlaces: enlaces.sorted { $0.raw < $1.raw })
    }

    static func registro(ruta: VaultPath, texto: String) -> G2Registro {
        let doc = NoteDocument(text: texto)
        guard let front = doc.frontmatterText else {
            return G2Registro(ruta: ruta, tipo: nil, campos: .vacio, cuerpo: doc.body, titulo: doc.heading,
                              tieneFrontmatter: false, ilegible: false)
        }
        guard let campos = G2YAML.leer(front) else {
            return G2Registro(ruta: ruta, tipo: nil, campos: .vacio, cuerpo: doc.body, titulo: doc.heading,
                              tieneFrontmatter: true, ilegible: true)
        }
        return G2Registro(ruta: ruta, tipo: campos.texto("tls_type"), campos: campos, cuerpo: doc.body,
                          titulo: doc.heading, tieneFrontmatter: true, ilegible: false)
    }
}
