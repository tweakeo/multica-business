import Foundation
import TLSCore

/// `.tls/config.yaml` de una copia y lectura mínima de `.tls/` del origen.
///
/// Aquí solo se escribe un fichero plano y se leen claves escalares de primer nivel (`id`, `clase`,
/// `origen`, `creada`). `privado` lo interpreta siempre el núcleo (`VaultLayout`, con Yams).
public enum CopyConfig {
    /// Texto de `.tls/config.yaml` para una copia nueva.
    public static func yaml(id: UUID, origen: String, creada: LocalDate) -> String {
        """
        # Configuración de esta copia de trabajo, creada por The Last System.
        # Lo privado no se copió: las carpetas que elegiste dejar fuera no están aquí,
        # por eso «privado» va vacío. Lo que cambies en esta copia no llega a tu carpeta real.
        version: 1
        id: \(id.uuidString.lowercased())
        clase: copia
        origen: \(quoted(origen))
        creada: \(creada.description)
        privado: []

        """
    }

    /// Lo que se sabe de una carpeta por su `.tls/`.
    public struct Peek: Sendable, Hashable {
        public var id: UUID?
        public var clase: VaultClass?
        /// `privado` de `layout.json` y de `config.yaml`, leído con el núcleo y ya expandido.
        public var privado: [String]
        /// Para una copia: carpeta de origen y fecha de creación (de su `config.yaml`).
        public var origen: String?
        public var creada: LocalDate?
    }

    /// Lee `.tls/layout.json` y `.tls/config.yaml` de `root` (si existen y no están solo en iCloud).
    static func peek(_ root: URL, fs: any FileSystemAccess) -> Peek {
        var result = Peek(id: nil, clase: nil, privado: [])
        // `privado` lo interpreta el núcleo (Yams y plantillas `{finanzas}/…`): una sola regla.
        result.privado = VaultLayout.load(root: root).layout.privado.map(\.raw)
        let config = root.appendingPathComponent(".tls", isDirectory: true).appendingPathComponent("config.yaml")
        if fs.fileExists(config), !fs.isDataless(config), !fs.isSymbolicLink(config),
           let data = try? fs.contents(of: config), let text = TextDecoding.decode(data) {
            if let v = topLevelScalar("id", in: text) { result.id = UUID(uuidString: v) }
            if let v = topLevelScalar("clase", in: text) { result.clase = VaultClass(rawValue: v) }
            result.origen = topLevelScalar("origen", in: text)
            result.creada = topLevelScalar("creada", in: text).flatMap { LocalDate(parsing: $0) }
        }
        return result
    }

    /// Versión asíncrona y protegida de `peek` para quien no está ya en el hilo de copia.
    public static func peek(_ root: URL, fileSystem: any FileSystemAccess = LocalFileSystem()) async throws -> Peek {
        try await DatalessGuard.run("TLSImport.peek") { _ in peek(root, fs: fileSystem) }
    }

    // MARK: - YAML mínimo

    /// Cadena YAML entre comillas dobles.
    static func quoted(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if ch.value < 0x20 { out += String(format: "\\x%02X", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }

    /// Valor de una clave de primer nivel (`clave: valor`), sin comillas ni comentario.
    static func topLevelScalar(_ key: String, in text: String) -> String? {
        // `isNewline` corta también en «\r\n» (un solo carácter en Swift) y en «\r».
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            guard line.hasPrefix(key + ":") else { continue }
            let rest = line.dropFirst(key.count + 1)
            let v = unquote(stripComment(String(rest)))
            return v.isEmpty ? nil : v
        }
        return nil
    }

    /// Lista de una clave de primer nivel, en línea (`[a, "b"]`) o en bloque (`- a`).
    static func topLevelList(_ key: String, in text: String) -> [String] {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard let i = lines.firstIndex(where: { $0.hasPrefix(key + ":") }) else { return [] }
        let inline = stripComment(String(lines[i].dropFirst(key.count + 1)))
        if inline.hasPrefix("[") {
            let inner = inline.dropFirst().prefix { $0 != "]" }
            return inner.split(separator: ",").map { unquote(String($0)) }.filter { !$0.isEmpty }
        }
        if !inline.isEmpty { return [unquote(inline)] }
        var out: [String] = []
        for line in lines[(i + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            guard line.first == " " || line.first == "\t" || line.first == "-", t.hasPrefix("-") else { break }
            let v = unquote(stripComment(String(t.dropFirst())))
            if !v.isEmpty { out.append(v) }
        }
        return out
    }

    private static func stripComment(_ s: String) -> String {
        var inSingle = false, inDouble = false
        var prev: Character = " "
        for (idx, ch) in zip(s.indices, s) {
            if ch == "'" && !inDouble { inSingle.toggle() }
            if ch == "\"" && !inSingle && prev != "\\" { inDouble.toggle() }
            if ch == "#" && !inSingle && !inDouble && (prev == " " || prev == "\t") {
                return String(s[..<idx]).trimmingCharacters(in: .whitespaces)
            }
            prev = ch
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, let f = t.first, let l = t.last, f == l, f == "\"" || f == "'" else { return t }
        let inner = String(t.dropFirst().dropLast())
        guard f == "\"" else { return inner.replacingOccurrences(of: "''", with: "'") }
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
