import Foundation
import TLSCore

// F5 · rol mail. El registro mensual del correo en el Buzón (PLAN §4.4 y SISTEMAS CO1, plantilla «Registro del Buzón v1»):
// `Buzón/Correo AAAA-MM.md`, solo se añade, una sección `## AAAA-MM-DD` por día de triaje y una línea por correo:
//
//   - 08:12 · Laura Pérez <laura@example.com> · Cambio de domicilio fiscal · cliente · tarea T-0042 · Propuesto <!-- tls:correo {"mensaje":"message://%3C…%3E"} -->
//   - 08:30 · correo privado de Expediente privado · — · ruido · sin destino · Hecho <!-- tls:correo {…} -->
//   - 09:01 · AEAT <notificaciones@aeat.es> · Requerimiento · administración · tarea T-0043 · Propuesto · PLAZO 2026-10-30 <!-- … -->
//
// El remitente, el asunto y la hora salen del correo guardado por la app (nunca del texto del asistente); lo privado,
// solo «correo privado de X».

/// Tipo de correo (la clasificación del Cartero).
public enum TipoDeCorreo: String, Sendable, Hashable, CaseIterable, Codable {
    case cliente, interesado, proveedor
    case administracion = "administración"
    case ruido

    public init?(leyendo t: String) {
        let k = TextFolding.fold(t.trimmingCharacters(in: .whitespaces))
        guard let e = Self.allCases.first(where: { TextFolding.fold($0.rawValue) == k }) else { return nil }
        self = e
    }
}

/// Estado de una entrada del registro.
public enum EstadoEntradaCorreo: String, Sendable, Hashable, CaseIterable, Codable {
    case propuesto = "Propuesto"
    case hecho = "Hecho"
    case deshecho = "Deshecho"

    public init?(leyendo t: String) {
        let k = TextFolding.fold(t.trimmingCharacters(in: .whitespaces))
        guard let e = Self.allCases.first(where: { TextFolding.fold($0.rawValue) == k }) else { return nil }
        self = e
    }
}

/// Una línea del registro.
public struct EntradaDeCorreo: Sendable, Hashable {
    public var mensaje: MensajeDeCorreo
    public var tipo: TipoDeCorreo
    /// Adónde va: «tarea T-0042», «borrador de respuesta», «Finanzas › facturas recibidas», «sin destino»…
    public var destino: String
    public var estado: EstadoEntradaCorreo
    /// Plazo oficial (se escribe «· PLAZO AAAA-MM-DD»).
    public var plazo: LocalDate?

    public init(mensaje: MensajeDeCorreo, tipo: TipoDeCorreo, destino: String, estado: EstadoEntradaCorreo = .propuesto,
                plazo: LocalDate? = nil) {
        self.mensaje = mensaje; self.tipo = tipo; self.destino = destino; self.estado = estado; self.plazo = plazo
    }

    /// La línea tal como se escribe.
    public func texto(_ zona: TimeZone) -> String {
        func limpio(_ s: String, max: Int = 200) -> String {
            let t = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: " · ", with: ", ").replacingOccurrences(of: "<!--", with: "‹!--")
                .replacingOccurrences(of: "-->", with: "--›").trimmingCharacters(in: .whitespaces)
            return t.count > max ? String(t.prefix(max - 1)) + "…" : t
        }
        let asunto = mensaje.privado ? "—" : (mensaje.asunto.isEmpty ? "(sin asunto)" : OcultarSecretos.texto(mensaje.asunto))
        var partes = [mensaje.hora(zona), limpio(mensaje.de), limpio(asunto), tipo.rawValue, limpio(destino, max: 120), estado.rawValue]
        if let p = plazo { partes.append("PLAZO \(p)") }
        let marca = (try? JSONSerialization.data(withJSONObject: ["mensaje": mensaje.referencia], options: [.sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "- " + partes.joined(separator: " · ") + " <!-- tls:correo \(marca) -->"
    }
}

public enum RegistroDelCorreo {
    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                        "octubre", "noviembre", "diciembre"]

    /// `Buzón/Correo AAAA-MM.md` (o `nil` si la carpeta no tiene Buzón).
    public static func ruta(_ fecha: LocalDate, layout: VaultLayout) -> VaultPath? {
        guard let b = layout.buzon, !b.isEmpty else { return nil }
        return VaultPath(b).appending(String(format: "Correo %04d-%02d.md", fecha.year, fecha.month))
    }

    /// Texto de un mes nuevo (la forma de la plantilla «Registro del Buzón v1»).
    public static func textoNuevo(_ fecha: LocalDate) -> String {
        let mes = String(format: "%04d-%02d", fecha.year, fecha.month)
        return """
            ---
            tls_type: log
            tls_schema: 1
            id: \(UUID().uuidString.lowercased())
            registro: correo
            mes: "\(mes)"
            plantilla: "Registro del Buzón v1"
            ---
            # Correo de \(meses[fecha.month - 1]) de \(fecha.year)
            > Lo que entró por el Buzón este mes y adónde fue. Solo se añade.

            """
    }

    /// Operaciones para añadir las entradas bajo el día `dia` (crea el mes si no existe).
    public static func ops(_ entradas: [EntradaDeCorreo], dia: LocalDate, zona: TimeZone, layout: VaultLayout,
                           existe: (VaultPath) -> Bool) -> [WriteOp] {
        guard let r = ruta(dia, layout: layout), !entradas.isEmpty else { return [] }
        var ops: [WriteOp] = []
        if !existe(r) { ops.append(.create(r, text: textoNuevo(dia))) }
        for e in entradas {
            ops.append(.appendToSection(r, section: dia.description, text: e.texto(zona), blankLine: false))
        }
        return ops
    }

    /// Las referencias ya apuntadas en un texto de registro (enlaces `message://` normalizados o `privado:<huella>`).
    public static func idsApuntados(_ texto: String) -> Set<String> {
        var r = Set<String>()
        for linea in texto.components(separatedBy: .newlines) {
            guard let i = linea.range(of: "<!-- tls:correo "), let f = linea.range(of: " -->", range: i.upperBound..<linea.endIndex) else { continue }
            let json = String(linea[i.upperBound..<f.lowerBound])
            if let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
               let m = o["mensaje"] as? String {
                if m.hasPrefix(EnlaceDeCorreo.prefijoPrivado) { r.insert(m) } else if let id = EnlaceDeCorreo.id(m) { r.insert(EnlaceDeCorreo.enlace(id)) }
            }
        }
        return r
    }

    /// Los apuntados en el registro de este mes y del anterior (la ventana del lunes puede cruzar de mes).
    public static func idsApuntados(snapshot: VaultSnapshot, hoy: LocalDate) -> Set<String> {
        var r = Set<String>()
        let anterior = hoy.adding(days: -hoy.day)
        for d in [hoy, anterior] {
            if let p = ruta(d, layout: snapshot.layout), let real = snapshot.existing(p), let t = snapshot.text(real) {
                r.formUnion(idsApuntados(t))
            }
        }
        return r
    }
}
