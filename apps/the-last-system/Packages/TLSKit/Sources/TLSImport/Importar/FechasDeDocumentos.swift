import Foundation
import TLSCore

/// Una fila de `4 · Finanzas/Fechas de documentos.csv` (`ruta,fecha,fuente,nota`; PLAN §4.6).
public struct FilaFecha: Sendable, Hashable, Codable {
    /// Ruta relativa a la carpeta de Finanzas (`Fiscal/2026/T3/Gastos/…`), como la escriben el ejemplo y el conversor.
    public let ruta: String
    public let fecha: String
    public let fuente: String
    public let nota: String

    public init(ruta: String, fecha: String, fuente: String, nota: String) {
        self.ruta = ruta; self.fecha = fecha; self.fuente = fuente; self.nota = nota
    }

    public var esManual: Bool { CSVDocument.isManual(["fuente": fuente]) }
    public var diccionario: [String: String] { ["ruta": ruta, "fecha": fecha, "fuente": fuente, "nota": nota] }
}

/// Lectura y escritura de `Fechas de documentos.csv`. Las filas `manual` son de una persona y nunca se pisan.
public enum FechasDeDocumentos {
    public static let cabecera = ["ruta", "fecha", "fuente", "nota"]
    public static let nombre = "Fechas de documentos.csv"

    public static func ruta(_ layout: VaultLayout) -> VaultPath { layout.areaFolder(.finanzas).appending(nombre) }

    /// Ruta de la fila (relativa a Finanzas) para un documento de la carpeta.
    public static func relativa(_ p: VaultPath, layout: VaultLayout) -> String {
        let fin = layout.areaFolder(.finanzas)
        guard p.isDescendant(of: fin), p != fin else { return p.raw }
        return VaultPath(components: Array(p.components.dropFirst(fin.components.count))).raw
    }

    /// Documento de la carpeta de una fila (también acepta rutas escritas desde la raíz).
    public static func absoluta(_ ruta: String, layout: VaultLayout) -> VaultPath {
        let p = VaultPath(ruta)
        if layout.area(of: p) != nil { return p }
        return layout.areaFolder(.finanzas).appendingAll(p)
    }

    public static func leer(_ texto: String) -> [FilaFecha] {
        let t = CSVTable.parse(TextDecoding.strippingBOM(texto))
        let cab = t.header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func i(_ c: String) -> Int? { cab.firstIndex(of: c) }
        guard let ir = i("ruta") else { return [] }
        return t.rows.compactMap { f in
            func v(_ k: Int?) -> String { k.map { $0 < f.count ? f[$0] : "" } ?? "" }
            let r = v(ir)
            return r.isEmpty ? nil : FilaFecha(ruta: r, fecha: v(i("fecha")), fuente: v(i("fuente")), nota: v(i("nota")))
        }
    }

    /// Texto de un CSV nuevo (cabecera y filas ordenadas por ruta).
    public static func texto(_ filas: [FilaFecha]) -> String {
        var out = cabecera.joined(separator: ",") + "\n"
        for f in filas.sorted(by: { $0.ruta.localizedStandardCompare($1.ruta) == .orderedAscending }) {
            out += [f.ruta, f.fecha, f.fuente, f.nota].map(MapaImportacion.campo).joined(separator: ",") + "\n"
        }
        return out
    }
}
