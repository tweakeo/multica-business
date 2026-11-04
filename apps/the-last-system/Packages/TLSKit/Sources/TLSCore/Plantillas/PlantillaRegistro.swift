import Foundation
import Yams

/// Lo que dice `.tls/plantillas.yaml` de una plantilla (PLANTILLAS.md §1.1).
public struct PlantillaDef: Sendable, Hashable {
    /// Carpeta según desde qué ficha se crea (`proyecto` → `{{proyecto.carpeta}}/Tareas`).
    public struct CarpetaSegun: Sendable, Hashable {
        public var rol: String
        public var carpeta: String
    }

    public var id: String
    /// Dónde está instalada en la carpeta (`{direccion}/Sistemas/Plantillas/Tarea.md`).
    public var fichero: String
    /// La original dentro de la app (`Comunes/Tarea.md`).
    public var origen: String?
    /// `tls_type` de la nota que crea.
    public var tipo: String
    /// Carpeta donde nace (`{area}/Tareas`). `nil` para fragmentos o si la elige quien crea.
    public var carpeta: String?
    public var carpetaSi: [CarpetaSegun]
    /// Patrón del nombre del fichero (sin `.md`) y del título que se ve.
    public var nombre: String?
    public var titulo: String?
    public var preguntas: [String]
    /// Tipos de ficha que ofrecen su botón «Nueva…».
    public var desde: [String]
    public var variantePor: String?
    public var modulo: String?
    public var sistemas: [String]
    /// Contador de `.tls/secuencias.json` que da `{{numero}}`.
    public var serie: String?
    /// Fragmentos: `seccion`, `fila` o `linea`, y dónde se meten.
    public var forma: String?
    public var donde: String?

    public init(id: String, fichero: String, origen: String? = nil, tipo: String, carpeta: String? = nil,
                carpetaSi: [CarpetaSegun] = [], nombre: String? = nil, titulo: String? = nil, preguntas: [String] = [],
                desde: [String] = [], variantePor: String? = nil, modulo: String? = nil, sistemas: [String] = [],
                serie: String? = nil, forma: String? = nil, donde: String? = nil) {
        self.id = id; self.fichero = fichero; self.origen = origen; self.tipo = tipo; self.carpeta = carpeta
        self.carpetaSi = carpetaSi; self.nombre = nombre; self.titulo = titulo; self.preguntas = preguntas
        self.desde = desde; self.variantePor = variantePor; self.modulo = modulo; self.sistemas = sistemas
        self.serie = serie; self.forma = forma; self.donde = donde
    }

    /// Área a la que pertenece por su `fichero` (`{finanzas}/…` → Finanzas).
    public var area: AreaCode? {
        AreaCode.allCases.first { fichero.hasPrefix("{\($0.layoutKey)}") }
    }

    public var esFragmento: Bool { tipo == "fragment" }
}

public enum PlantillaError: Error, LocalizedError, Sendable, Equatable {
    case noExiste(String)
    case registroIlegible(String)
    case sinTexto(String)
    /// Falta un dato para poner nombre o carpeta a la nota (no se inventa).
    case faltaDato(String)
    case esFragmento(String)
    case noEsFragmento(String)
    case noDisponible(String)
    /// La nota de nombre fijo ya existe: se completa con `aplicar`, no se duplica.
    case yaExiste(String)

    public var errorDescription: String? {
        switch self {
        case .noExiste(let id): "No encuentro la plantilla «\(id)»."
        case .registroIlegible(let d): "No he podido leer la lista de plantillas (\(d))."
        case .sinTexto(let f): "No encuentro el texto de la plantilla «\(f)»."
        case .faltaDato(let v): "Falta «\(Self.legible(v))» para poner nombre a la nota."
        case .esFragmento(let id): "«\(id)» no crea una nota: se añade dentro de otra."
        case .noEsFragmento(let id): "«\(id)» crea una nota nueva, no se añade dentro de otra."
        case .noDisponible(let id): "La plantilla «\(id)» aún no se puede usar desde aquí."
        case .yaExiste(let p): "Ya existe «\(p)». Puedes completarla con la plantilla: solo se añade lo que le falta."
        }
    }

    static func legible(_ v: String) -> String {
        v.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
    }
}

/// Registro de plantillas: el de la carpeta (`.tls/plantillas.yaml`) sobre el de serie.
public struct PlantillaRegistro: Sendable {
    public private(set) var plantillas: [PlantillaDef]

    public init(plantillas: [PlantillaDef]) { self.plantillas = plantillas }

    public static let ruta = VaultPath(".tls/plantillas.yaml")

    public subscript(_ id: String) -> PlantillaDef? { plantillas.first { $0.id == id } }

    /// Plantillas que ofrecen «Nueva…» desde una ficha de ese tipo (`contact`, `organization`…).
    public func desde(tipo: String) -> [PlantillaDef] {
        plantillas.filter { $0.desde.contains(tipo) }
    }

    /// Plantillas de los sistemas indicados (`VE2`…); `todos` va con cualquiera.
    public func deSistemas(_ codigos: Set<String>) -> [PlantillaDef] {
        plantillas.filter { !Set($0.sistemas).isDisjoint(with: codigos) || $0.sistemas.contains("todos") }
    }

    /// El de serie (dentro de la app).
    public static var deSerie: PlantillaRegistro {
        guard let text = PlantillasDeSerie.registroTexto, let r = try? parse(text) else { return PlantillaRegistro(plantillas: []) }
        return r
    }

    /// El de la carpeta, completado con el de serie (lo de la carpeta manda).
    public static func cargar(_ snapshot: VaultSnapshot) -> PlantillaRegistro {
        var base = deSerie
        if let text = snapshot.text(ruta), let propio = try? parse(text) {
            for def in propio.plantillas {
                if let i = base.plantillas.firstIndex(where: { $0.id == def.id }) {
                    var merged = def
                    // Lo que la carpeta no dice se toma de serie (p. ej. `origen`).
                    if merged.origen == nil { merged.origen = base.plantillas[i].origen }
                    base.plantillas[i] = merged
                } else {
                    base.plantillas.append(def)
                }
            }
        }
        return base
    }

    // MARK: Lectura

    public static func parse(_ yaml: String) throws -> PlantillaRegistro {
        let node: Node?
        do { node = try Yams.compose(yaml: yaml, Resolver.basic) } catch {
            throw PlantillaError.registroIlegible(String(describing: error))
        }
        guard let node else { return PlantillaRegistro(plantillas: []) }
        guard case .mapping(let m) = node else { throw PlantillaError.registroIlegible("no es una lista de plantillas") }
        var out: [PlantillaDef] = []
        for (k, v) in m {
            guard let id = k.string, case .mapping(let e) = v else { continue }
            func s(_ key: String) -> String? {
                guard let n = e[Node(key)], case .scalar(let sc) = n else { return nil }
                let t = sc.string
                return t.isEmpty || t == "~" || t == "null" ? nil : t
            }
            func list(_ key: String) -> [String] {
                guard let n = e[Node(key)] else { return [] }
                switch n {
                case .sequence(let seq): return seq.compactMap(\.string)
                case .scalar(let sc): return sc.string.isEmpty ? [] : [sc.string]
                default: return []
                }
            }
            var carpetaSi: [PlantillaDef.CarpetaSegun] = []
            if let n = e[Node("carpeta_si")], case .mapping(let cm) = n {
                for (rk, rv) in cm { if let r = rk.string, let c = rv.string { carpetaSi.append(.init(rol: r, carpeta: c)) } }
            }
            guard let fichero = s("fichero"), let tipo = s("tipo") else { continue }
            out.append(PlantillaDef(id: id, fichero: fichero, origen: s("origen"), tipo: tipo,
                                    carpeta: e[Node("carpeta")]?.string, carpetaSi: carpetaSi, nombre: s("nombre"),
                                    titulo: s("titulo"), preguntas: list("preguntas"), desde: list("desde"),
                                    variantePor: s("variante_por"), modulo: s("modulo"), sistemas: list("sistemas"),
                                    serie: s("serie"), forma: s("forma"), donde: s("donde")))
        }
        return PlantillaRegistro(plantillas: out)
    }

    /// Bloques de texto de cada plantilla en un `plantillas.yaml` (para añadir solo las que faltan,
    /// sin reescribir lo demás).
    static func bloques(_ yaml: String) -> [(id: String, texto: String)] {
        var out: [(String, String)] = []
        var current: (String, [String])?
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let first = line.first, first != " ", first != "#", first != "\t",
               let kl = FrontmatterDocument.parseKeyLine(line) {
                if let c = current { out.append((c.0, c.1.joined(separator: "\n"))) }
                current = (kl.name, [line])
            } else if line.hasPrefix(" ") || line.hasPrefix("\t") {
                current?.1.append(line)
            }
        }
        if let c = current { out.append((c.0, c.1.joined(separator: "\n"))) }
        return out
    }
}

/// Las plantillas originales que vienen dentro de la app (`Recursos/Plantillas/`).
public enum PlantillasDeSerie {
    /// Carpeta de las originales. Se busca el paquete de recursos sin el `Bundle.module` generado, que
    /// para el proceso si no lo encuentra (p. ej. una herramienta copiada sin sus recursos): aquí no hay
    /// plantillas de serie, pero nada se cae.
    public static var carpeta: URL? { carpetaEncontrada }

    private final class Marca {}

    private static let carpetaEncontrada: URL? = {
        let nombre = "TLSKit_TLSCore.bundle"
        let propio = Bundle(for: Marca.self)
        let sitios: [URL?] = [
            Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent(),
            propio.resourceURL, propio.bundleURL.deletingLastPathComponent(), propio.bundleURL,
        ]
        let fm = FileManager.default
        for sitio in sitios.compactMap({ $0 }) {
            let candidato = sitio.appendingPathComponent(nombre)
            guard fm.fileExists(atPath: candidato.path), let b = Bundle(url: candidato) else { continue }
            if let u = b.url(forResource: "Plantillas", withExtension: nil) { return u }
            let directo = candidato.appendingPathComponent("Plantillas")
            if fm.fileExists(atPath: directo.path) { return directo }
        }
        return nil
    }()

    /// Texto de `plantillas.yaml` de serie.
    public static var registroTexto: String? {
        guard let url = carpeta?.appendingPathComponent("plantillas.yaml") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Bytes de una original (`Comunes/Tarea.md`).
    public static func datos(_ origen: String) -> Data? {
        guard let base = carpeta else { return nil }
        let url = VaultPath(origen).url(in: base)
        if let d = try? Data(contentsOf: url) { return d }
        // El nombre en disco puede estar en otra forma de tildes.
        let wanted = TextFolding.pathKey(VaultPath(origen).raw)
        for rel in ficheros where TextFolding.pathKey(rel) == wanted {
            return try? Data(contentsOf: VaultPath(rel).url(in: base))
        }
        return nil
    }

    public static func texto(_ origen: String) -> String? {
        datos(origen).flatMap { EditableText(data: $0)?.text }
    }

    /// Rutas relativas de todas las originales (`.md`).
    public static var ficheros: [String] {
        guard let base = carpeta, let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var out: [String] = []
        for case let u as URL in e where u.pathExtension == "md" {
            out.append(String(u.standardizedFileURL.path.dropFirst(base.standardizedFileURL.path.count + 1)).precomposedStringWithCanonicalMapping)
        }
        return out.sorted()
    }
}
