// Procedencia: lógica portada a Swift desde FORK/server/internal/biz/layout.go
// (autor: Manuel Trigo). Sin código copiado; ver docs/PROCEDENCIA.md.

import Foundation
import Yams

/// Dónde vive cada cosa dentro de la carpeta de la empresa (`.tls/layout.json`).
///
/// - `{"preset":"humana"}`: áreas `N · Nombre` (G3).
/// - Sin fichero: si hay carpetas `1 · …` a `6 · …` se usan; si no, la estructura
///   antigua de la demo (`Dirección/`, `Ventas/`…).
/// - Las rutas privadas vienen SOLO de la configuración (layout.json, config.yaml o la
///   entrada de la carpeta). Nunca se escriben en el código.
public struct VaultLayout: Sendable, Hashable {
    public enum Preset: String, Sendable { case humana, demo }

    public var preset: Preset
    /// Carpeta de cada área (`2 · Ventas`).
    public var areas: [AreaCode: String]
    /// Plantilla de carpeta por tipo (`{ventas}/Contactos`). Vacía = el tipo no tiene ficheros propios.
    public var dirs: [String: String]
    public var archivo: String
    public var buzon: String?
    public var tareas: String
    public var proyectos: String
    /// Nombres de carpeta que no son colecciones de fichas (Sistemas, Recursos…).
    public var skip: [String]
    /// Rutas privadas, ya expandidas (`4 · Finanzas/…`).
    public var privado: [VaultPath]
    /// `true` si las carpetas de área se detectaron por su número.
    public var areasDetectadas: Bool

    // MARK: Presets

    static let defaultDirs: [String: String] = [
        "organization": "{ventas}/Organizaciones", "contact": "{ventas}/Contactos", "opportunity": "{ventas}/Oportunidades",
        "offer": "{ventas}/Ofertas", "service": "{entrega}/Servicios",
        "invoice_draft": "{finanzas}/Borradores", "account": "{finanzas}/Bancos",
        "kpi": "{direccion}/KPI", "objective": "{direccion}/Objetivos", "decision": "{direccion}/Decisiones",
        "routine": "{direccion}/Rutinas", "content": "{marca}/Contenidos", "conversation": "{marca}/Conversaciones",
        "role": "{equipo}/Roles", "document": "Documentos",
    ]

    /// Estructura de la demo antigua (Asesoría Ribera).
    public static var demo: VaultLayout {
        VaultLayout(
            preset: .demo,
            areas: Dictionary(uniqueKeysWithValues: AreaCode.allCases.map { ($0, $0.nombre) }),
            dirs: defaultDirs,
            archivo: "Archivo", buzon: nil, tareas: "Tareas", proyectos: "Proyectos",
            skip: ["Paquete gestoría"], privado: [], areasDetectadas: false)
    }

    /// Estructura humana (G3): áreas numeradas, Registros, Buzón y Archivo.
    public static var humana: VaultLayout {
        var l = demo
        l.preset = .humana
        l.areas = Dictionary(uniqueKeysWithValues: AreaCode.allCases.map { ($0, "\($0.numero) · \($0.nombre)") })
        l.dirs["organization"] = "{ventas}/Empresas"
        l.dirs["offer"] = "{ventas}/Productos/Versiones"
        l.dirs["service"] = "{ventas}/Productos"
        l.dirs["payment"] = ""            // pagos.csv es el registro
        l.dirs["account"] = "{finanzas}/Registros/Bancos"
        l.dirs["invoice_draft"] = "{finanzas}/Fiscal/Borradores"
        l.dirs["kpi"] = ""                // las metas viven en Metas.md
        l.dirs["decision"] = ""           // Decisiones.md es un registro
        l.dirs["delivery_template"] = "{entrega}/Plantillas"
        l.buzon = "Buzón"
        l.skip += ["Buzón", "Sistemas", "Recursos", "Contratos", "Gestoría", "Trámites"]
        return l
    }

    // MARK: Lectura

    public static let layoutFile = ".tls/layout.json"
    public static let configFile = ".tls/config.yaml"

    /// Patrón de carpeta de área: `^[1-6] · ` (U+00B7).
    static func areaNumber(ofFolder name: String) -> Int? {
        let n = name.precomposedStringWithCanonicalMapping
        guard n.count > 4, let first = n.first, let num = first.wholeNumberValue, (1...6).contains(num) else { return nil }
        let rest = n.dropFirst()
        return rest.hasPrefix(" · ") ? num : nil
    }

    /// Aviso para la persona si los ajustes de la carpeta no se pudieron leer (sin jerga).
    public static let avisoIlegible = "No he podido leer cómo está organizada tu carpeta; la muestro tal como está."

    /// Lee `.tls/layout.json` (y `privado` de `.tls/config.yaml`). Nunca escribe.
    /// Si un fichero no se puede leer se usa la detección y se devuelve un aviso.
    public static func load(root: URL, extraPrivado: [VaultPath] = []) -> (layout: VaultLayout, aviso: String?) {
        let settings = readSettings(root: root)
        let layout = build(root: root, settings: settings, extraPrivado: extraPrivado)
        return (layout, settings.problemas.isEmpty ? nil : avisoIlegible)
    }

    /// Rutas que la carpeta declara privadas (`privado` de `.tls/layout.json` y `.tls/config.yaml`),
    /// ya expandidas con las carpetas de área reales.
    ///
    /// Más estricto que `load`: si alguno de esos ficheros existe pero no se puede leer (solo en iCloud,
    /// enlace, dañado…), lanza. Quien copia o recorre debe parar antes que arriesgarse con lo privado.
    public static func declaredPrivado(root: URL) throws -> [VaultPath] {
        let settings = readSettings(root: root)
        if let problema = settings.problemas.first { throw VaultLayoutError.ajustesIlegibles(problema) }
        return build(root: root, settings: settings, extraPrivado: []).privado
    }

    /// Lo leído de `.tls/` sin interpretar: el JSON de la estructura y las plantillas de `privado`.
    struct Settings {
        var json: [String: Any]?
        var privado: [String] = []
        /// Ficheros que existen pero no se han podido leer (ruta relativa).
        var problemas: [String] = []
    }

    static func readSettings(root: URL) -> Settings {
        var s = Settings()
        // `.tls/` solo en iCloud o enlazada: no se puede saber qué es privado sin descargarla.
        switch entryState(root: root, ".tls") {
        case .absent: return s
        case .problem: s.problemas.append(".tls"); return s
        case .present: break
        }
        if let data = readSmallFile(root: root, layoutFile, problemas: &s.problemas) {
            if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                s.json = json
                s.privado += stringList(json["privado"])
            } else {
                s.problemas.append(layoutFile)
            }
        }
        if let data = readSmallFile(root: root, configFile, problemas: &s.problemas) {
            if let list = configPrivado(data) { s.privado += list } else { s.problemas.append(configFile) }
        }
        return s
    }

    private enum EntryState { case absent, present, problem }

    /// `lstat` que distingue «no existe» de «no se puede mirar» (y trata lo dataless y los enlaces como problema).
    private static func entryState(root: URL, _ rel: String) -> EntryState {
        var st = stat()
        let r = VaultPath(rel).url(in: root).withUnsafeFileSystemRepresentation { p -> Int32 in
            guard let p else { return -1 }
            return lstat(p, &st)
        }
        if r != 0 { return errno == ENOENT || errno == ENOTDIR ? .absent : .problem }
        let type = st.st_mode & S_IFMT
        if type == S_IFLNK || (st.st_flags & UbiquityInspector.datalessFlag) != 0 { return .problem }
        return .present
    }

    /// Contenido de un fichero de `.tls/` sin seguir enlaces ni descargar de iCloud.
    /// `nil` si no existe; si existe y no se puede leer, lo apunta en `problemas`.
    private static func readSmallFile(root: URL, _ rel: String, problemas: inout [String]) -> Data? {
        switch entryState(root: root, rel) {
        case .absent: return nil
        case .problem: problemas.append(rel); return nil
        case .present: break
        }
        let url = VaultPath(rel).url(in: root)
        guard let info = UbiquityInspector.info(url), !info.isDirectory,
              let data = UbiquityInspector.withoutMaterializing({ FileManager.default.contents(atPath: url.path) }) else {
            problemas.append(rel)
            return nil
        }
        return data
    }

    /// `privado:` de `.tls/config.yaml`. `nil` si el YAML no se entiende.
    static func configPrivado(_ data: Data) -> [String]? {
        guard let text = TextDecoding.decode(data) else { return nil }
        let node: Node?
        do { node = try Yams.compose(yaml: text, Resolver.basic) } catch { return nil }
        guard let node else { return [] }  // vacío o solo comentarios
        guard case .mapping(let m) = node else { return nil }
        for (k, v) in m where k.string == "privado" {
            switch v {
            case .sequence(let seq): return seq.compactMap { $0.string }
            case .scalar(let s): return s.string.isEmpty || s.string == "~" || s.string == "null" ? [] : [s.string]
            default: return nil
            }
        }
        return []
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let list = value as? [String] { return list }
        if let one = value as? String, !one.isEmpty { return [one] }
        return []
    }

    /// Estructura final: preset, ajustes del JSON, carpetas reales y `privado` expandido con ellas.
    static func build(root: URL, settings: Settings, extraPrivado: [VaultPath]) -> VaultLayout {
        let detected = detectAreaFolders(root: root)
        var layout: VaultLayout
        if let json = settings.json {
            layout = (json["preset"] as? String) == "humana" ? .humana : .demo
            layout.apply(json)
        } else {
            layout = detected.isEmpty ? .demo : .humana
        }
        // Las carpetas reales mandan: «2 · Comercial» sustituye a «2 · Ventas».
        if !detected.isEmpty {
            for (code, name) in detected { layout.areas[code] = name }
            layout.areasDetectadas = true
        }
        // Las plantillas (`{finanzas}/Bancos`) se expanden con las carpetas ya detectadas.
        layout.privado = settings.privado.map { layout.expand($0) }.filter { !$0.isRoot } + extraPrivado
        layout.privado = Array(Set(layout.privado)).sorted()
        return layout
    }

    static func detectAreaFolders(root: URL) -> [AreaCode: String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [:] }
        var out: [AreaCode: String] = [:]
        for name in names.sorted() {
            guard let num = areaNumber(ofFolder: name),
                  let code = AreaCode.allCases.first(where: { $0.numero == num }),
                  out[code] == nil else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            out[code] = name.precomposedStringWithCanonicalMapping
        }
        return out
    }

    mutating func apply(_ json: [String: Any]) {
        if let a = json["areas"] as? [String: String] {
            for (k, v) in a {
                if let code = AreaCode.allCases.first(where: { $0.layoutKey == k }) { areas[code] = v.precomposedStringWithCanonicalMapping }
            }
        }
        if let d = json["dirs"] as? [String: String] {
            for (k, v) in d { dirs[k] = v }
        }
        if let s = json["archivo"] as? String, !s.isEmpty { archivo = s }
        if let s = json["buzon"] as? String, !s.isEmpty { buzon = s }
        if let s = json["tareas"] as? String, !s.isEmpty { tareas = s }
        if let s = json["proyectos"] as? String, !s.isEmpty { proyectos = s }
        if let s = json["skip"] as? [String] { skip += s }
        // `privado` lo trata `build`, después de detectar las carpetas de área.
    }

    /// Texto estable que cambia si cambia cualquier ajuste (para saber si el índice vale).
    public var fingerprint: String {
        var parts = ["preset=\(preset.rawValue)", "archivo=\(archivo)", "buzon=\(buzon ?? "")",
                     "tareas=\(tareas)", "proyectos=\(proyectos)"]
        parts += AreaCode.allCases.map { "area.\($0.rawValue)=\(areas[$0] ?? "")" }
        parts += dirs.keys.sorted().map { "dir.\($0)=\(dirs[$0] ?? "")" }
        parts.append("skip=" + skip.sorted().joined(separator: ","))
        parts.append("privado=" + privado.map(\.raw).sorted().joined(separator: ","))
        return parts.joined(separator: "\n")
    }

    // MARK: Consultas

    /// Sustituye `{direccion}`… por la carpeta del área.
    public func expand(_ template: String) -> VaultPath {
        var t = template
        for code in AreaCode.allCases {
            t = t.replacingOccurrences(of: "{\(code.layoutKey)}", with: areas[code] ?? code.nombre)
        }
        return VaultPath(t)
    }

    public func areaFolder(_ code: AreaCode) -> VaultPath {
        VaultPath(areas[code] ?? code.nombre)
    }

    /// Área a la que pertenece una ruta (por su primera carpeta).
    public func area(of path: VaultPath) -> AreaCode? {
        guard let first = path.components.first else { return nil }
        let key = TextFolding.nameKey(first)
        return AreaCode.allCases.first { TextFolding.nameKey(areas[$0] ?? $0.nombre) == key }
    }

    /// Carpeta de un tipo (`nil` si el tipo no tiene ficheros propios).
    public func dir(for type: String) -> VaultPath? {
        guard let t = dirs[type], !t.isEmpty else { return nil }
        return expand(t)
    }

    /// Sin distinguir mayúsculas (APFS tampoco): «privado/x.md» es privado si lo es «Privado».
    ///
    /// Lo retirado sigue siendo privado: `Archivo/<ruta privada>` y `Archivo/Conflictos|Duplicados/<ruta privada>`
    /// (adonde lo mueven retirar, los conflictos y los duplicados) se miran como la ruta de la que vienen.
    public func isPrivate(_ path: VaultPath) -> Bool {
        guard !path.isRoot, !privado.isEmpty else { return false }
        return Self.origenesEnArchivo(path, archivo: archivo).contains { ruta in
            let k = TextFolding.pathKey(ruta)
            return privado.contains { p in
                guard !p.isRoot else { return false }
                let pk = TextFolding.pathKey(p.raw)
                return k == pk || k.hasPrefix(pk + "/")
            }
        }
    }

    /// Apartados de `Archivo/` que guardan la ruta de origen debajo (`Archivo/Conflictos/<ruta>`).
    static let apartadosArchivo = ["Conflictos", "Duplicados"]

    /// La ruta y, si está en `Archivo/`, las rutas de las que puede venir (sin `Archivo/` y sin su apartado).
    static func origenesEnArchivo(_ path: VaultPath, archivo: String) -> [String] {
        var out = [path.raw]
        let c = path.components
        guard c.count > 1, TextFolding.nameKey(c[0]) == TextFolding.nameKey(archivo) else { return out }
        out.append(c.dropFirst().joined(separator: "/"))
        if c.count > 2, apartadosArchivo.contains(where: { TextFolding.nameKey($0) == TextFolding.nameKey(c[1]) }) {
            out.append(c.dropFirst(2).joined(separator: "/"))
        }
        return out
    }

    public func isArchived(_ path: VaultPath) -> Bool {
        guard let first = path.components.first else { return false }
        return TextFolding.nameKey(first) == TextFolding.nameKey(archivo)
    }

    /// Carpetas que nunca guardan fichas: ocultas y las de `skip`.
    public func isSkipFolder(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let key = TextFolding.nameKey(name)
        return skip.contains { TextFolding.nameKey($0) == key }
    }

    /// `false` para notas índice o plantilla que viven junto a las fichas
    /// (`Contactos/Contactos.md`, `Plantilla persona.md`, `Área.md`, `LEEME.md`).
    public func isRecordNote(_ path: VaultPath) -> Bool {
        let stem = TextFolding.nameKey(path.stem)
        let parentName = TextFolding.nameKey(path.parent?.name ?? "")
        return stem != parentName && !stem.hasPrefix("plantilla") && stem != "área" && stem != "leeme" && stem != "readme"
    }

    /// Tipo por carpeta (solo hijos directos de una carpeta de fichas).
    public func inferType(_ path: VaultPath) -> String? {
        guard isRecordNote(path), let parent = path.parent else { return nil }
        if path.components.contains(where: isSkipFolder) { return nil }
        let parentKey = TextFolding.nameKey(parent.raw)
        for (type, _) in dirs.sorted(by: { $0.key < $1.key }) {
            if let d = dir(for: type), TextFolding.nameKey(d.raw) == parentKey { return type }
        }
        return nil
    }

    /// `.tls/config.yaml` con estas rutas añadidas a `privado:` (lo crea si `texto` es `nil`). Las que ya estaban (o
    /// cuelgan de una que ya estaba) no se repiten. `nil` si el YAML de ahora o el resultante no se leen: no se toca.
    /// Se usa al marcar algo como privado al ordenar (F3): la marca queda en la carpeta, no solo en la app.
    public static func configConPrivado(_ texto: String?, anadir rutas: [VaultPath]) -> String? {
        let actual = texto ?? "# Configuración de esta carpeta.\nversion: 1\nprivado: []\n"
        guard let ya = configPrivado(Data(actual.utf8)) else { return nil }
        var lista = ya
        var claves = ya.map { TextFolding.pathKey($0) }
        for r in rutas where !r.isRoot {
            let k = TextFolding.pathKey(r.raw)
            guard !claves.contains(where: { k == $0 || k.hasPrefix($0 + "/") }) else { continue }
            lista.append(r.raw)
            claves.append(k)
        }
        guard lista.count > ya.count || texto == nil else { return actual }
        let bloque = lista.isEmpty ? ["privado: []"] : ["privado:"] + lista.map { "  - " + TextoPuesta.escalarYAML($0) }
        let nuevo = TextoPuesta.ponerBloqueYAML("privado", bloque, en: actual)
        guard let leidas = configPrivado(Data(nuevo.utf8)),
              leidas.map({ TextFolding.pathKey($0) }) == lista.map({ TextFolding.pathKey($0) }) else { return nil }
        return nuevo
    }
}

public enum VaultLayoutError: Error, LocalizedError, Sendable {
    /// Un fichero de ajustes (`.tls/layout.json` o `.tls/config.yaml`) existe pero no se puede leer.
    case ajustesIlegibles(String)

    public var errorDescription: String? {
        switch self {
        case .ajustesIlegibles:
            "No he podido leer qué carpetas marca como privadas tu carpeta (puede que esa parte esté solo en iCloud o dañada)."
        }
    }
}
