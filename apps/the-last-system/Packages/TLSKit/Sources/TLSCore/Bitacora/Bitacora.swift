import Foundation

// Bitácora de los asistentes (PLAN §4.4, SISTEMAS EQ2): `6 · Equipo/Bitácora/AAAA-MM.md`, una línea por trabajo y solo
// se añade:
//
//   - 2026-10-21 10:32 · agente:comercial · VEN-08 · Preparó seguimiento para nexo-estudio · pendiente de aprobación · uso 0,04 USD <!-- tls:audit {"run":"r-7f3a","hash":"…"} -->
//
// Las líneas van bajo el día (`## AAAA-MM-DD`). La escribe la app al cerrar cada trabajo (`ActividadDeAsistente`),
// nunca evento a evento, y funciona aunque Equipo esté en reposo.

/// Una línea de la Bitácora.
public struct LineaBitacora: Sendable, Hashable {
    public var fecha: LocalDate
    /// `HH:MM`.
    public var hora: String
    /// `comercial` (se escribe `agente:comercial`).
    public var agente: String
    public var capacidad: String?
    /// Qué hizo, en una frase.
    public var que: String
    /// `hecho`, `pendiente de aprobación`, `esperando respuesta`, `rechazado`, `con error`, `cancelado`.
    public var resultado: String
    /// Uso en dólares que devuelve Claude Code (con suscripción no es un cargo real).
    public var usoUSD: Double?
    /// Ejecución (`r-7f3a`).
    public var ejecucion: String?
    /// Huella de lo que se aprobó o se escribió, si la hay.
    public var hash: String?
    /// Trabajo simulado (el ejemplo): `"simulado":"si"` en su `tls:audit` o «Simulado: …» en el texto.
    public var simulado: Bool {
        TextFolding.fold(que).hasPrefix("simulado:") || marcaSimulado
    }
    /// Lo que dice su `tls:audit` (solo al leer).
    var marcaSimulado = false

    public init(fecha: LocalDate, hora: String, agente: String, capacidad: String? = nil, que: String, resultado: String,
                usoUSD: Double? = nil, ejecucion: String? = nil, hash: String? = nil) {
        self.fecha = fecha; self.hora = hora; self.agente = ConfigAgentes.slug(agente); self.capacidad = capacidad
        self.que = que; self.resultado = resultado; self.usoUSD = usoUSD; self.ejecucion = ejecucion; self.hash = hash
    }

    /// La línea tal como se escribe.
    public var texto: String {
        func limpio(_ s: String) -> String {
            s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: " · ", with: ", ").trimmingCharacters(in: .whitespaces)
        }
        var partes = ["\(fecha) \(hora)", "agente:\(agente)"]
        if let c = capacidad, !c.isEmpty { partes.append(c) }
        partes.append(limpio(que))
        partes.append(limpio(resultado))
        if let u = usoUSD { partes.append("uso " + Self.uso(u) + " USD") }
        var linea = "- " + partes.joined(separator: " · ")
        var audit: [String: String] = [:]
        if let e = ejecucion { audit["run"] = e }
        if let h = hash { audit["hash"] = h }
        if !audit.isEmpty {
            let data = (try? JSONSerialization.data(withJSONObject: audit, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            let json = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "-->", with: "--\\u003e").replacingOccurrences(of: "<!--", with: "\\u003c!--")
            linea += " <!-- tls:audit \(json) -->"
        }
        return linea
    }

    /// `0.04` → «0,04».
    static func uso(_ u: Double) -> String {
        String(format: "%.2f", u).replacingOccurrences(of: ".", with: ",")
    }

    /// Lee una línea de la Bitácora (`nil` si no lo es).
    public static func leer(_ linea: String) -> LineaBitacora? {
        var l = linea.trimmingCharacters(in: .whitespaces)
        guard l.hasPrefix("- ") else { return nil }
        l.removeFirst(2)
        var audit: [String: String] = [:]
        if let r = l.range(of: "<!-- tls:audit ") {
            let resto = l[r.upperBound...]
            if let fin = resto.range(of: " -->") {
                let json = String(resto[..<fin.lowerBound])
                audit = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: String] ?? [:]
            }
            l = String(l[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        let partes = l.components(separatedBy: " · ")
        guard partes.count >= 4 else { return nil }
        let fh = partes[0].split(separator: " ")
        // `agente:comercial` (PLAN §4.4) o, en las de antes, `comercial` a secas.
        guard fh.count == 2, let f = LocalDate(parsing: String(fh[0])), !partes[1].contains(" ") else { return nil }
        var resto = Array(partes.dropFirst(2))
        var uso: Double?
        if let u = resto.last, u.hasPrefix("uso "), u.hasSuffix(" USD") {
            uso = Double(u.dropFirst(4).dropLast(4).replacingOccurrences(of: ",", with: "."))
            resto.removeLast()
        }
        var capacidad: String?
        if resto.count >= 3, resto[0].range(of: #"^[A-Z]{3}-[A-Z0-9]+$"#, options: .regularExpression) != nil {
            capacidad = resto.removeFirst()
        }
        guard resto.count >= 2 else { return nil }
        let resultado = resto.removeLast()
        var linea = LineaBitacora(fecha: f, hora: String(fh[1]), agente: partes[1],
                                  capacidad: capacidad, que: resto.joined(separator: " · "), resultado: resultado, usoUSD: uso,
                                  ejecucion: audit["run"], hash: audit["hash"])
        linea.marcaSimulado = audit["simulado"].map { TextFolding.fold($0) == "si" || $0 == "true" } ?? false
        return linea
    }
}

public enum Bitacora {
    /// `6 · Equipo/Bitácora` (o `bitacora` de `.tls/layout.json`, si lo cambia).
    public static func carpeta(_ layout: VaultLayout) -> VaultPath {
        if let d = layout.dirs["bitacora"], !d.isEmpty { return layout.expand(d) }
        return layout.areaFolder(.equipo).appending("Bitácora")
    }

    /// `6 · Equipo/Bitácora/AAAA-MM.md`.
    public static func ruta(_ fecha: LocalDate, layout: VaultLayout) -> VaultPath {
        carpeta(layout).appending(String(format: "%04d-%02d.md", fecha.year, fecha.month))
    }

    public static func esRutaDeBitacora(_ p: VaultPath, layout: VaultLayout) -> Bool {
        guard let parent = p.parent, TextFolding.pathKey(parent.raw) == TextFolding.pathKey(carpeta(layout).raw) else { return false }
        return p.stem.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil && p.ext == "md"
    }

    /// Texto de una Bitácora nueva (la forma de la plantilla «Bitácora mensual»).
    static func textoNuevo(_ fecha: LocalDate) -> String {
        let mes = String(format: "%04d-%02d", fecha.year, fecha.month)
        let larga = FormatosPlantilla.aplicar(mes, formato: "larga")
        return """
            ---
            tls_type: log
            tls_schema: 1
            id: \(UUID().uuidString.lowercased())
            registro: bitacora
            mes: "\(mes)"
            plantilla: "Bitácora mensual v1"
            ---
            # Bitácora de \(larga)
            > Todo lo que hicieron los asistentes este mes. Solo se añade; nadie la edita.

            """
    }

    /// Operaciones para añadir líneas (crea el mes si no existe; cada línea bajo su día). `existe` dice si el
    /// fichero del mes ya está en la carpeta.
    public static func ops(_ lineas: [LineaBitacora], layout: VaultLayout, existe: (VaultPath) -> Bool) -> [WriteOp] {
        var ops: [WriteOp] = []
        var creados: Set<VaultPath> = []
        for l in lineas {
            let r = ruta(l.fecha, layout: layout)
            if !existe(r), !creados.contains(r) {
                ops.append(.create(r, text: textoNuevo(l.fecha)))
                creados.insert(r)
            }
            ops.append(.appendToSection(r, section: l.fecha.description, text: l.texto, blankLine: false))
        }
        return ops
    }

    /// Las líneas de un mes.
    public static func leer(_ texto: String) -> [LineaBitacora] {
        texto.components(separatedBy: .newlines).compactMap(LineaBitacora.leer)
    }
}
