import Foundation

/// Lo que la carpeta dice de sí misma y usan las bases: qué módulos están encendidos (`.tls/modulos.yaml`,
/// SISTEMAS §5.9) y qué día es en la demo (`hoy:` de `.tls/config.yaml`). Solo lee; no descarga nada.
public struct AjustesBases: Sendable, Hashable {
    /// Módulos encendidos o apagados a mano (el resto, como vienen de serie).
    public var modulos: [String: Bool]
    /// Día de la carpeta (la demo fija uno; si no, hoy).
    public var hoy: LocalDate

    /// Módulos apagados de serie (Objetivos está apagado en The Last: decisión A).
    public static let apagadosDeSerie: Set<String> = ["objetivos"]

    public init(modulos: [String: Bool] = [:], hoy: LocalDate = .today()) {
        self.modulos = modulos
        self.hoy = hoy
    }

    public static let ficheroModulos = VaultPath(".tls/modulos.yaml")
    public static let ficheroConfig = VaultPath(".tls/config.yaml")

    /// `true` si el módulo está encendido.
    public func encendido(_ modulo: String?) -> Bool {
        guard let modulo else { return true }
        return modulos[modulo] ?? !Self.apagadosDeSerie.contains(modulo)
    }

    public func apagada(_ c: ColeccionBase) -> Bool { !encendido(c.modulo) }

    /// Lee los ajustes de la carpeta (sin seguir enlaces ni descargar de iCloud).
    public static func leer(root: URL) -> AjustesBases {
        var a = AjustesBases()
        if let texto = leerTexto(ficheroModulos, root: root) { a.modulos = modulos(yaml: texto) }
        if let texto = leerTexto(ficheroConfig, root: root), let d = hoy(config: texto) { a.hoy = d }
        return a
    }

    /// `objetivos: encendido` · `objetivos: true` · `encendidos: [objetivos]` · `apagados: [crm]`. La línea
    /// propia de un módulo manda sobre las listas (es la que escribe «Encender» y «Apagar»; si no, encender un
    /// módulo que estaba en `apagados: […]` no hacía nada).
    public static func modulos(yaml texto: String) -> [String: Bool] {
        var out: [String: Bool] = [:]
        var deListas: [String: Bool] = [:]
        for linea in texto.split(whereSeparator: \.isNewline) {
            let l = linea.trimmingCharacters(in: .whitespaces)
            guard !l.hasPrefix("#"), let kl = FrontmatterDocument.parseKeyLine(String(l)) else { continue }
            let clave = kl.name.trimmingCharacters(in: .whitespaces)
            var valor = kl.value.trimmingCharacters(in: .whitespaces)
            if let i = valor.range(of: " #") { valor = String(valor[..<i.lowerBound]) }
            if clave == "encendidos" || clave == "apagados" {
                let lista = valor.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                    .split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
                for m in lista where !m.isEmpty { deListas[m] = clave == "encendidos" }
                continue
            }
            switch TextFolding.fold(valor.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))) {
            case "true", "si", "encendido", "on": out[clave] = true
            case "false", "no", "apagado", "off": out[clave] = false
            default: break
            }
        }
        return deListas.merging(out) { _, propia in propia }
    }

    /// `hoy: 2026-10-19` de `.tls/config.yaml`.
    public static func hoy(config texto: String) -> LocalDate? {
        guard let linea = texto.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("hoy:") }),
              let kl = FrontmatterDocument.parseKeyLine(String(linea)) else { return nil }
        return LocalDate(parsing: kl.value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")))
    }

    /// Texto que tendrá `.tls/modulos.yaml` con ese módulo encendido o apagado (conserva el resto).
    public static func textoModulos(_ actual: String?, modulo: String, encendido: Bool) -> String {
        let linea = "\(modulo): \(encendido ? "encendido" : "apagado")"
        guard let actual, !actual.isEmpty else {
            return "# Módulos de esta carpeta. Apagar un módulo nunca toca tus fichas.\n\(linea)\n"
        }
        var lineas = actual.components(separatedBy: "\n")
        if let i = lineas.firstIndex(where: { FrontmatterDocument.parseKeyLine($0)?.name == modulo }) {
            lineas[i] = linea
            return lineas.joined(separator: "\n")
        }
        let base = actual.hasSuffix("\n") ? actual : actual + "\n"
        return base + linea + "\n"
    }

    /// Texto de un fichero de ajustes (`nil` si no está, es un enlace o está solo en iCloud).
    public static func leerTexto(_ p: VaultPath, root: URL) -> String? {
        let url = p.url(in: root)
        guard let info = UbiquityInspector.info(url), !info.isSymlink, !info.isDirectory, !info.dataless else { return nil }
        return UbiquityInspector.withoutMaterializing { FileManager.default.contents(atPath: url.path) }.flatMap(TextDecoding.decode)
    }
}
