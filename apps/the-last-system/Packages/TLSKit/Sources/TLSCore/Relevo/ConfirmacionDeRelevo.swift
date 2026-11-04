import Foundation

/// Dónde y cuándo aparece «Pasar a mi carpeta real» (PLAN §9 F6): solo en Ajustes › Empresa de una **copia** cuya
/// carpeta de origen está registrada como **real**. Aun así, el botón nace desactivado: se activa al escribir el nombre
/// de la empresa (`ConfirmacionDeRelevo`).
public enum DisponibilidadDelRelevo: Sendable, Equatable {
    case disponible(real: VaultEntry)
    case oculto(motivo: String)

    public var real: VaultEntry? {
        if case .disponible(let r) = self { return r }
        return nil
    }

    /// Decide con lo registrado (`vaults.json`), sin mirar el disco.
    public static func evaluar(_ carpeta: VaultEntry, registradas: [VaultEntry]) -> DisponibilidadDelRelevo {
        guard carpeta.clase == .copia else {
            return .oculto(motivo: "Solo se puede pasar a la carpeta real desde una copia de trabajo.")
        }
        guard let origen = carpeta.origen, !origen.isEmpty else {
            return .oculto(motivo: "Esta copia no recuerda de qué carpeta salió.")
        }
        let clave = claveDeRuta(origen)
        let reales = registradas.filter { $0.clase == .real && $0.id != carpeta.id }
        guard let real = reales.first(where: { claveDeRuta($0.ruta) == clave }) else {
            return .oculto(motivo: "La carpeta de la que salió esta copia no está registrada como tu carpeta real.")
        }
        return .disponible(real: real)
    }

    /// Ruta comparable: estándar, sin `/` final, NFC y sin distinguir mayúsculas (como APFS).
    static func claveDeRuta(_ ruta: String) -> String {
        let std = URL(fileURLWithPath: ruta).standardizedFileURL.path
        let sinBarra = std.count > 1 && std.hasSuffix("/") ? String(std.dropLast()) : std
        return TextFolding.pathKey(sinBarra)
    }
}

/// Confirmación explícita (paso 1): la persona escribe el nombre de la empresa. Sin eso, el botón sigue desactivado y
/// el relevo no empieza.
public struct ConfirmacionDeRelevo: Sendable, Hashable {
    public let nombreEmpresa: String
    public var escrito: String

    public init(nombreEmpresa: String, escrito: String = "") {
        self.nombreEmpresa = nombreEmpresa
        self.escrito = escrito
    }

    /// Igual que el nombre, sin contar espacios de los lados, mayúsculas ni la forma de escribir las tildes.
    public var confirmada: Bool {
        let n = Self.normalizar(nombreEmpresa)
        return !n.isEmpty && Self.normalizar(escrito) == n
    }

    static func normalizar(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// Textos de la pantalla (español de España, sin jerga).
public enum TextosDelRelevo {
    public static let titulo = "Pasar a mi carpeta real"
    public static let explicacion = """
        Lleva a tu carpeta real lo que has hecho en esta copia. Antes verás qué se añade, qué cambia y qué se archiva. \
        No se borra nada: lo que sobra va a Archivo/ y antes se guarda una copia de seguridad en los ajustes de la app. \
        Lo privado de tu carpeta real no se toca.
        """
    public static func pideNombre(_ empresa: String) -> String {
        "Para confirmar, escribe el nombre de tu empresa: «\(empresa)»."
    }

    /// Texto de confirmación con las cifras exactas (paso 1).
    public static func confirmacion(empresa: String, anadir: Int, cambiar: Int, archivar: Int, conflictos: Int,
                                    privado: Int, propuestas: Bool) -> String {
        var s = "Se van a añadir \(ficheros(anadir)), cambiar \(ficheros(cambiar)) y archivar \(ficheros(archivar)) "
            + "en tu carpeta real «\(empresa)». No se borra nada: lo archivado va a Archivo/."
        if conflictos > 0 {
            s += conflictos == 1
                ? " En 1 fichero que cambió en las dos se queda lo que elegiste."
                : " En \(conflictos) ficheros que cambiaron en las dos se queda lo que elegiste."
        }
        if privado > 0 {
            s += privado == 1
                ? " 1 carpeta privada queda marcada como privada en tu carpeta real."
                : " \(privado) carpetas privadas quedan marcadas como privadas en tu carpeta real."
        }
        if propuestas { s += " Te dejo en el Buzón una nota con cambios de texto propuestos (no se aplican)." }
        return s + " Antes se guarda una copia de seguridad de todo lo que se toca, y podrás deshacerlo."
    }

    static func ficheros(_ n: Int) -> String { n == 1 ? "1 fichero" : "\(n) ficheros" }

    /// F6 · corrector (P2-10): cuándo, en llano y en la hora de tu Mac: «hoy a las 03:33», «ayer a las 18:05», «el 24 de
    /// octubre a las 09:10».
    public static func cuando(_ fecha: Date, ahora: Date = Date(), zona: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let hora = String(format: "%02d:%02d", cal.component(.hour, from: fecha), cal.component(.minute, from: fecha))
        if cal.isDate(fecha, inSameDayAs: ahora) { return "hoy a las \(hora)" }
        if let ayer = cal.date(byAdding: .day, value: -1, to: ahora), cal.isDate(fecha, inSameDayAs: ayer) { return "ayer a las \(hora)" }
        let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
                     "noviembre", "diciembre"]
        let d = cal.dateComponents([.day, .month, .year], from: fecha)
        let mismoAno = cal.component(.year, from: ahora) == d.year
        return "el \(d.day ?? 1) de \(meses[max(0, min(11, (d.month ?? 1) - 1))])" + (mismoAno ? "" : " de \(d.year ?? 0)") + " a las \(hora)"
    }

    /// La fecha de la marca (ISO 8601) en llano; si no se entiende, `nil`.
    public static func cuando(iso: String, ahora: Date = Date(), zona: TimeZone = .current) -> String? {
        ISO8601DateFormatter().date(from: iso).map { cuando($0, ahora: ahora, zona: zona) }
    }

    /// «Guardada hoy a las 03:33 en tu Mac (no en tu carpeta)».
    public static func respaldo(iso: String, ahora: Date = Date(), zona: TimeZone = .current) -> String {
        "Guardada " + (cuando(iso: iso, ahora: ahora, zona: zona) ?? "antes de pasar") + " en tu Mac (no en tu carpeta)"
    }
}
