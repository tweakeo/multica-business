import Foundation
import TLSCore

/// Comprobaciones de una carpeta v2 (lo que pide F1: «0 errores del validador y ninguna nota sin tipo»).
///
/// - toda nota fuera de `Archivo/` tiene propiedades legibles con `tls_type`, `tls_schema` e `id`;
/// - todo enlace (wikilink en propiedades, enlaces del cuerpo) resuelve a un fichero que existe;
/// - los CSV de Finanzas tienen la cabecera exacta;
/// - `.tls/layout.json` y `.tls/config.yaml` se leen.
enum ValidadorV2 {
    struct Problema: CustomStringConvertible, Hashable {
        let ruta: String
        let texto: String
        var description: String { "\(ruta): \(texto)" }
    }

    static let cabeceras: [String: [String]] = [
        "emitidas.csv": ["id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento", "documento",
                         "ambito", "proyecto_id", "estado_revision", "fuente"],
        "recibidas.csv": ["id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento", "documento",
                          "ambito", "proyecto_id", "estado_revision", "fuente", "base", "iva", "retencion", "categoria",
                          "naturaleza"],
        "pagos.csv": ["id", "fecha", "direccion", "importe", "moneda", "documento_id", "proyecto_id", "tercero", "metodo",
                      "evidencia", "verificacion"],
        "movimientos.csv": ["id", "fecha", "fecha_valor", "concepto", "importe", "saldo", "naturaleza", "categoria",
                            "proyecto_id", "documento_id", "pago_id", "estado_conciliacion", "motivo", "import_hash", "lote",
                            "verificacion"],
        "Fechas de documentos.csv": ["ruta", "fecha", "fuente", "nota"],
    ]

    static func validar(_ arbol: [String: Data]) -> [Problema] {
        var problemas: [Problema] = []
        let rutas = arbol.keys.map(VaultPath.init)
        let resolver = LinkResolver(paths: rutas)
        for (ruta, datos) in arbol.sorted(by: { $0.key < $1.key }) {
            let p = VaultPath(ruta)
            if p.components.first == "Archivo" { continue }
            if p.ext == "md" {
                problemas += validarNota(p, datos, resolver)
            } else if p.ext == "csv", !p.raw.contains("/Extractos/"), !p.raw.contains("Paquete gestoría"),
                      let esperada = p.raw.hasSuffix("Registros/Bancos/" + (p.parent?.name ?? "") + "/movimientos.csv")
                        ? cabeceras["movimientos.csv"] : cabeceras[p.name] {
                let tabla = CSVTable.parse(TextDecoding.decode(datos) ?? "")
                if tabla.header != esperada { problemas.append(Problema(ruta: ruta, texto: "cabecera distinta: \(tabla.header)")) }
                if tabla.rows.contains(where: { $0.count != tabla.header.count }) {
                    problemas.append(Problema(ruta: ruta, texto: "filas con un número de columnas distinto de la cabecera"))
                }
            }
        }
        if let layout = arbol[".tls/layout.json"] {
            if (try? JSONSerialization.jsonObject(with: layout)) == nil {
                problemas.append(Problema(ruta: ".tls/layout.json", texto: "JSON ilegible"))
            }
        } else {
            problemas.append(Problema(ruta: ".tls/layout.json", texto: "falta"))
        }
        if let config = arbol[".tls/config.yaml"].flatMap(TextDecoding.decode) {
            let fm = FrontmatterReader.read(config)
            if !fm.isValid { problemas.append(Problema(ruta: ".tls/config.yaml", texto: "YAML ilegible")) }
            let clase = fm.text("clase")
            if clase != "demo" && clase != "copia" {
                problemas.append(Problema(ruta: ".tls/config.yaml", texto: "clase «\(clase ?? "")» no es demo ni copia"))
            }
        } else {
            problemas.append(Problema(ruta: ".tls/config.yaml", texto: "falta"))
        }
        return problemas
    }

    static func validarNota(_ p: VaultPath, _ datos: Data, _ resolver: LinkResolver) -> [Problema] {
        var problemas: [Problema] = []
        guard let texto = TextDecoding.decode(datos) else { return [Problema(ruta: p.raw, texto: "no es texto")] }
        let doc = NoteDocument(text: texto)
        guard doc.frontmatterText != nil else { return [Problema(ruta: p.raw, texto: "nota sin propiedades (sin tipo)")] }
        let fm = doc.frontmatter
        guard fm.isValid else { return [Problema(ruta: p.raw, texto: "propiedades ilegibles")] }
        for clave in ["tls_type", "tls_schema", "id"] where fm.text(clave) == nil {
            problemas.append(Problema(ruta: p.raw, texto: "falta «\(clave)»"))
        }
        // Wikilinks en las propiedades.
        for prop in fm.properties {
            let valores: [String] = switch prop.value {
            case .text(let s): [s]
            case .list(let l): l
            default: []
            }
            for v in valores where v.contains("[[") {
                for enlace in LinkParser.links(in: v) where resolver.resolve(enlace.resolvable, from: p) == nil {
                    problemas.append(Problema(ruta: p.raw, texto: "enlace roto en «\(prop.key)»: \(enlace.raw)"))
                }
            }
        }
        // Enlaces del cuerpo.
        for enlace in LinkParser.links(in: doc.body) where !enlace.isExternal {
            if resolver.resolve(enlace.resolvable, from: p) == nil {
                problemas.append(Problema(ruta: p.raw, texto: "enlace roto: \(enlace.raw)"))
            }
        }
        return problemas
    }

    /// Notas fuera de `Archivo/` por `tls_type`.
    static func tipos(_ arbol: [String: Data]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (ruta, datos) in arbol where ruta.hasSuffix(".md") && !ruta.hasPrefix("Archivo/") {
            let fm = NoteDocument(data: datos).frontmatter
            out[fm.text("tls_type") ?? "(sin tipo)", default: 0] += 1
        }
        return out
    }
}
