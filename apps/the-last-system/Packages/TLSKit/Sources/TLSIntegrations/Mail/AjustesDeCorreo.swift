import Foundation
import TLSAgents

/// Un remitente o un dominio privado: de él solo se sabe que llegó «correo privado de <etiqueta>».
public struct RemitentePrivado: Sendable, Hashable, Codable {
    /// `persona@dominio.es`, `@dominio.es` o `dominio.es` (todo el dominio y sus subdominios).
    public var patron: String
    /// Nombre neutro que se enseña («Expediente privado», «mi médico»…). Nunca el correo.
    public var etiqueta: String

    public init(patron: String, etiqueta: String) {
        self.patron = patron; self.etiqueta = etiqueta
    }

    /// ¿Es de este remitente o dominio? (`direccion` ya en minúsculas, sin nombre).
    public func coincide(_ direccion: String) -> Bool {
        let p = patron.trimmingCharacters(in: .whitespaces).lowercased()
        guard !p.isEmpty else { return false }
        if p.contains("@") && !p.hasPrefix("@") { return direccion == p }
        let dominio = p.hasPrefix("@") ? String(p.dropFirst()) : p
        guard let at = direccion.lastIndex(of: "@") else { return false }
        let suyo = String(direccion[direccion.index(after: at)...])
        return suyo == dominio || suyo.hasSuffix("." + dominio)
    }
}

/// Lo que eliges al conectar Mail: la cuenta que mira el Cartero y lo privado. Se guarda en Application Support
/// (`<estado>/correo/ajustes.json`), **nunca en la carpeta** (la lista de privados ya es algo privado).
public struct AjustesDeCorreo: Sendable, Hashable, Codable {
    /// Nombre de la cuenta en Mail (`nil` = sin elegir: no se lee nada).
    public var cuenta: String?
    public var privados: [RemitentePrivado]

    public init(cuenta: String? = nil, privados: [RemitentePrivado] = []) {
        self.cuenta = cuenta; self.privados = privados
    }

    public static func ruta(_ estado: URL) -> URL {
        estado.appendingPathComponent("correo", isDirectory: true).appendingPathComponent("ajustes.json")
    }

    public static func leer(_ estado: URL) -> AjustesDeCorreo {
        guard let d = try? Data(contentsOf: ruta(estado)), let a = try? JSONDecoder().decode(AjustesDeCorreo.self, from: d) else {
            return AjustesDeCorreo()
        }
        return a
    }

    public func guardar(_ estado: URL) throws {
        let url = Self.ruta(estado)
        try AlmacenDeCorreo.crearCarpeta(url.deletingLastPathComponent())
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // S3: lo ya recogido de un remitente que ahora es privado se queda solo en metadatos.
        try AlmacenDeCorreo(estado: estado).depurar(con: self)
    }

    /// La regla privada que toca a este remitente, si la hay.
    public func privado(_ remitente: String) -> RemitentePrivado? {
        let d = FiltroDePrivacidad.direccion(remitente)
        return privados.first { $0.coincide(d) }
    }
}

/// Lo privado y los adjuntos, aplicado **otra vez** en la app a lo que devuelve el guion (por si el guion no lo hizo).
public enum FiltroDePrivacidad {
    /// `"Laura Pérez <Laura@Example.com>"` → `laura@example.com`.
    public static func direccion(_ remitente: String) -> String {
        let t = remitente.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = t.lastIndex(of: "<"), let b = t.lastIndex(of: ">"), a < b {
            return String(t[t.index(after: a)..<b]).trimmingCharacters(in: .whitespaces).lowercased()
        }
        return t.lowercased()
    }

    /// «correo privado de X».
    public static func textoPrivado(_ etiqueta: String) -> String {
        "correo privado de " + etiqueta
    }

    /// Deja un correo como puede guardarse: lo privado, solo metadatos (id, cuenta, fecha, leído); el texto, 4 KB como
    /// mucho; los adjuntos, solo nombre y tamaño (ya vienen así).
    public static func aplicar(_ m: MensajeDeCorreo, ajustes: AjustesDeCorreo) -> MensajeDeCorreo {
        if let regla = ajustes.privado(m.de) {
            return MensajeDeCorreo(id: m.id, cuenta: m.cuenta, fecha: m.fecha, de: textoPrivado(regla.etiqueta), leido: m.leido,
                                   privado: true)
        }
        if m.privado {
            // El guion ya lo marcó privado: no se fía de nada más de lo que traiga.
            return MensajeDeCorreo(id: m.id, cuenta: m.cuenta, fecha: m.fecha,
                                   de: m.de.hasPrefix("correo privado de ") ? m.de : textoPrivado("un remitente privado"),
                                   leido: m.leido, privado: true)
        }
        var r = m
        r.texto = DatoNoConfiable.recortar(m.texto, max: MensajeDeCorreo.maxTexto)
        r.adjuntos = m.adjuntos.map { AdjuntoDeCorreo(nombre: String($0.nombre.prefix(255)), bytes: max(0, $0.bytes)) }
        return r
    }
}
