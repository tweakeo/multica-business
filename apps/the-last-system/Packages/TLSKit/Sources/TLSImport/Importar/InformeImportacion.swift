import Foundation
import TLSCore

/// Texto de `Buzón/Informe de importación AAAA-MM-DD.md` (plantilla «Informe de importación v1», PLANTILLAS.md):
/// propiedades con los recuentos y el estado, y las secciones Resumen · Por bloques · Lo que se quedó donde estaba ·
/// Duplicados · Calidad de los datos · Comprobación · Cómo deshacer. Nunca nombra nada privado (no está en la zona).
struct InformeImportacion: Sendable {
    let fecha: LocalDate
    let fuentes: [String]
    let corte: LocalDate?
    let ficheros: Int
    let movidos: Int
    let adoptados: Int
    let archivados: Int
    let bloques: [ZonaPreparacion.Bloque]
    let propuestas: [String: PropuestaDestino]
    let previstos: [MovimientoPrevisto]
    let duplicados: [ZonaPreparacion.GrupoDuplicados]
    let inventario: InventarioImportacion
    let enlacesEnRiesgo: Int
    let sinFecha: Int
    let noSeTraen: [String]
    let soloEnICloud: Int
    let carpetasVacias: Int
    let carpetaArchivo: VaultPath

    /// Como mucho tantas líneas por lista (el resto se cuenta).
    static let maxLista = 40

    var texto: String {
        var s = """
        ---
        tls_type: import_report
        tls_schema: 1
        id: \(UUID().uuidString.lowercased())
        fecha: \(fecha.description)
        fuente: \(Self.yaml(fuentes.joined(separator: " · ")))

        """
        if let corte { s += "fecha_corte: \(corte.description)\n" }
        s += """
        ficheros: \(ficheros)
        movidos: \(movidos)
        adoptados: \(adoptados)
        archivados: \(archivados)
        verificados:
        estado: Aplicado
        plantilla: "Informe de importación v1"
        ---
        # Importación del \(FormatoFechaImportacion.corta(fecha))
        > Aplicado · \(Plural.de(ficheros, "fichero revisado", "ficheros revisados")) · no se borró nada

        ## Resumen
        | Qué | Cuántos |
        |---|---|
        | Ficheros revisados | \(ficheros) |
        | Llevados a su sitio | \(movidos) |
        | Con propiedades añadidas | \(adoptados) |
        | Llevados a Archivo | \(archivados) |
        | Solo en iCloud (mirados por su nombre) | \(soloEnICloud) |

        ## Por bloques
        | Bloque | Programa | Ficheros | Destino |
        |---|---|---|---|

        """
        for b in bloques {
            s += "| \(Self.celda(b.nombre)) | \(b.herramienta.nombre) | \(b.claves.count) | \(Self.celda(b.destinoPrincipal)) |\n"
        }
        s += "\n## Lo que se quedó donde estaba\n"
        let quedan = previstos.filter { [.mantener, .noMigrar, .fuera].contains($0.accion) }
        if quedan.isEmpty {
            s += "Nada: todo fue a su sitio.\n"
        } else {
            for p in quedan.prefix(Self.maxLista) {
                s += "- `\(Self.visible(p.clave))`: \(p.motivo)\n"
            }
            if quedan.count > Self.maxLista { s += "- y \(quedan.count - Self.maxLista) más.\n" }
        }
        s += "\n## Duplicados\n"
        let apartados = previstos.filter { $0.accion == .duplicado || $0.conflicto.hasPrefix("Duplicado de") }
        if apartados.isEmpty {
            s += "Ninguno.\n"
        } else {
            for p in apartados.prefix(Self.maxLista) {
                let destino = p.destino.map { " → `\($0.raw)`" } ?? " (no se trajo)"
                s += "- `\(Self.visible(p.clave))`\(destino): \(p.motivo)\n"
            }
            if apartados.count > Self.maxLista { s += "- y \(apartados.count - Self.maxLista) más.\n" }
        }
        if carpetasVacias > 0 {
            s += "\n\(Plural.de(carpetasVacias, "carpeta se quedó vacía", "carpetas se quedaron vacías")) al ordenar: está\(carpetasVacias == 1 ? "" : "n") en `\(carpetaArchivo.raw)/` (no se ha borrado ninguna).\n"
        }
        let parecidos = duplicados.filter { $0.clase == .nombreParecido && $0.seQueda == nil }.count
        if parecidos > 0 {
            s += "\n\(Plural.de(parecidos, "grupo", "grupos")) con nombres que parecen copias pero distinto contenido: se han quedado todos.\n"
        }
        s += """

        ## Calidad de los datos
        | Aviso | Ficheros | Qué hacer |
        |---|---|---|

        """
        var filas = 0
        if sinFecha > 0 {
            s += "| Documentos de Finanzas sin fecha legible | \(sinFecha) | Escríbela en «Fechas de documentos.csv» con fuente «manual». |\n"; filas += 1
        }
        if enlacesEnRiesgo > 0 {
            s += "| Enlaces que no se pudieron mantener | \(enlacesEnRiesgo) | Revísalos en Revisar › Enlaces. |\n"; filas += 1
        }
        if soloEnICloud > 0 {
            s += "| Solo en iCloud (no se movieron) | \(soloEnICloud) | Descárgalos y vuelve a ordenar si los quieres en su sitio. |\n"; filas += 1
        }
        let dudosos = previstos.filter { $0.confianza < AIClassifier.umbral && [.mover, .moverYRenombrar, .copiar, .copiarYRenombrar].contains($0.accion) }.count
        if dudosos > 0 {
            s += "| Llevados a su sitio con poca seguridad | \(dudosos) | Mira si están bien; si no, muévelos. |\n"; filas += 1
        }
        if !noSeTraen.isEmpty {
            s += "| No se pudieron traer | \(noSeTraen.count) | \(Self.celda(noSeTraen.prefix(3).joined(separator: "; "))) |\n"; filas += 1
        }
        if filas == 0 { s += "| Sin avisos | 0 | Nada. |\n" }
        s += """

        ## Comprobación

        ## Cómo deshacer
        Se puede deshacer entera desde Carpeta › Historial de cambios mientras no termine la puesta en marcha (hasta el paso 3).
        Lo que se trajo de fuera sigue también en su carpeta de origen, que no se ha tocado.

        """
        return s
    }

    /// Línea de la sección «Comprobación» (se añade al aplicar).
    func textoComprobacion(_ v: ResultadoVerificacion) -> String {
        var s = "\(v.texto). "
        s += v.sinDiferencias ? "Todo coincide: no falta nada y no se ha borrado nada."
            : "\(Plural.de(v.diferencias.count, "fichero no coincide", "ficheros no coinciden")); no se ha borrado nada."
        for d in v.diferencias.prefix(Self.maxLista) {
            let que: String
            switch d.tipo {
            case .falta: que = "no está donde debía"
            case .tamano: que = "tiene otro tamaño"
            case .huella: que = "tiene otro contenido"
            }
            s += "\n- `\(d.destino)` \(que)"
        }
        return s
    }

    /// Ruta para la persona: sin el alias de la carpeta de la empresa ni los identificadores de Notion.
    func visible(_ clave: String) -> String { Self.visible(clave) }

    static func visible(_ clave: String) -> String {
        let partes = clave.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let resto = partes.first == FuenteImportacion.aliasDeLaEmpresa ? Array(partes.dropFirst()) : partes
        return resto.map(InventarioImportacion.sinIdNotion).joined(separator: "/").replacingOccurrences(of: "`", with: "'")
    }

    /// Texto YAML entre comillas dobles (los nombres de carpeta pueden llevar «:» o «#»).
    static func yaml(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ") + "\""
    }

    static func celda(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
    }
}
