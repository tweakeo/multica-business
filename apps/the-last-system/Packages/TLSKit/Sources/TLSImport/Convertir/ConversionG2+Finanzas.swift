import CryptoKit
import Foundation
import TLSCore

/// Cabeceras de los CSV de Finanzas (PLAN §4.6). `recibidas.csv` lleva al final las cinco columnas
/// nuevas de SISTEMAS.md (decisión 12).
enum CabecerasCSV {
    static let documentos = ["id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento",
                             "documento", "ambito", "proyecto_id", "estado_revision", "fuente"]
    static let emitidas = documentos
    static let recibidas = documentos + ["base", "iva", "retencion", "categoria", "naturaleza"]
    static let pagos = ["id", "fecha", "direccion", "importe", "moneda", "documento_id", "proyecto_id", "tercero", "metodo",
                        "evidencia", "verificacion"]
    static let movimientos = ["id", "fecha", "fecha_valor", "concepto", "importe", "saldo", "naturaleza", "categoria",
                              "proyecto_id", "documento_id", "pago_id", "estado_conciliacion", "motivo", "import_hash",
                              "lote", "verificacion"]
    static let fechasDeDocumentos = ["ruta", "fecha", "fuente", "nota"]
}

/// Una fila de un extracto de banco ya leída.
struct FilaExtracto: Sendable {
    let fecha: String
    let concepto: String
    let importe: Int
    let saldo: Int?
}

/// Facturas, cobros y pagos, bancos y paquete trimestral.
extension ConversionG2 {
    var facturas: [G2Registro] { carpeta.registros("invoice") }
    var emitidas: [G2Registro] { facturas.filter { $0.campos.texto("direction") != "received" } }
    var recibidas: [G2Registro] { facturas.filter { $0.campos.texto("direction") == "received" } }

    func diaFactura(_ r: G2Registro) -> String {
        r.campos.fecha("issue_date") ?? r.campos.fecha("created_at") ?? fecha
    }

    /// Ruta de una nota o un fichero respecto a la carpeta de Finanzas (como en `recibidas.csv`).
    func relativaAFinanzas(_ ruta: VaultPath) -> String {
        let base = area(.finanzas).carpeta + "/"
        return ruta.raw.hasPrefix(base) ? String(ruta.raw.dropFirst(base.count)) : ruta.raw
    }

    /// Nombre del tercero de una factura: su empresa o, si no tiene, el contacto de su oportunidad.
    func tercero(_ r: G2Registro) -> String? {
        if let org = r.campos.texto("organization_id").flatMap({ porId[$0] }) { return org.campos.texto("name") }
        if let opp = r.campos.texto("opportunity_id").flatMap({ porId[$0] }),
           let contacto = opp.campos.texto("contact_id").flatMap({ porId[$0] }) {
            return contacto.campos.texto("name")
        }
        return nil
    }

    // MARK: Identificadores de fila

    func asignarIdsCSV() {
        for r in emitidas { if let id = r.id, let n = r.campos.texto("number") { idCSV[id] = n } }
        var porDia: [String: Int] = [:]
        for r in recibidas.sorted(by: { (diaFactura($0), $0.campos.texto("number") ?? "", $0.id ?? "") < (diaFactura($1), $1.campos.texto("number") ?? "", $1.id ?? "") }) {
            let dia = diaFactura(r).replacingOccurrences(of: "-", with: "")
            porDia[dia, default: 0] += 1
            if let id = r.id { idCSV[id] = String(format: "REC-%@-%03d", dia, porDia[dia]!) }
        }
        porDia = [:]
        let pagos = carpeta.registros("payment").sorted {
            ($0.campos.fecha("paid_on") ?? "", idCSV[$0.campos.texto("invoice_id") ?? ""] ?? "", $0.id ?? "")
                < ($1.campos.fecha("paid_on") ?? "", idCSV[$1.campos.texto("invoice_id") ?? ""] ?? "", $1.id ?? "")
        }
        for r in pagos {
            let dia = (r.campos.fecha("paid_on") ?? fecha).replacingOccurrences(of: "-", with: "")
            porDia[dia, default: 0] += 1
            if let id = r.id { idCSV[id] = String(format: "PAG-%@-%03d", dia, porDia[dia]!) }
        }
        for r in carpeta.registros("movement") {
            guard let id = r.id else { continue }
            let hash = r.campos.texto("import_hash") ?? hashDeMovimiento(r)
            if let hash { idCSV[id] = "MOV-" + hash.prefix(12) }
        }
    }

    /// `import_hash` del contrato de PLAN §4.6 calculado desde el movimiento.
    func hashDeMovimiento(_ r: G2Registro) -> String? {
        let c = r.campos
        guard let cuenta = c.texto("account_id"), let dia = c.fecha("booked_on"), let importe = c.entero("amount_minor") else { return nil }
        return Self.importHash(cuenta: cuenta, fila: FilaExtracto(fecha: dia, concepto: c.texto("description") ?? "",
                                                                  importe: importe, saldo: c.entero("balance_after_minor")))
    }

    static func importHash(cuenta: String, fila f: FilaExtracto, repeticion: Int = 1) -> String {
        var s = "\(cuenta)|\(f.fecha)|\(f.importe)|\(f.concepto.lowercased())|\(f.saldo.map(String.init) ?? "")"
        if repeticion > 1 { s += "|#\(repeticion)" }
        return SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Justificantes

    /// Decide dónde va cada PDF de `Justificantes/` (junto a su gasto o a su factura).
    func asignarJustificantes() {
        for doc in carpeta.registros("document") {
            let c = doc.campos
            guard c.texto("entity_type") == "invoice", let fid = c.texto("entity_id"), let factura = porId[fid],
                  let rel = c.texto("rel_path"), carpeta.ficheros.contains(where: { $0.ruta.raw == VaultPath(rel).raw }) else {
                continue
            }
            let dia = diaFactura(factura)
            let numero = factura.campos.texto("number") ?? "sin número"
            let total = factura.campos.entero("total_minor")
            let quien = Nombres.sinFormaJuridica(nombre: tercero(factura) ?? "Sin nombre")
            let importe = total.map { " \(Dinero.coma($0))€" } ?? ""
            let destino: VaultPath
            if factura.campos.texto("direction") == "received" {
                guard let p = G2Fecha.partes(dia), let t = G2Fecha.trimestre(dia) else { continue }
                let proveedor = factura.campos.texto("organization_id").flatMap { destinos[$0]?.ruta.stem } ?? "sin-proveedor"
                let nombre = Nombres.nombreDeFichero("\(dia) \(quien) \(numero)\(importe)") + ".pdf"
                destino = ruta(.finanzas, "Fiscal/\(p.anio)/T\(t)/Gastos/\(proveedor)/\(nombre)")
            } else {
                guard let nota = destinos[fid]?.ruta.parent else { continue }
                let nombre = Nombres.nombreDeFichero("\(dia) Factura \(numero) \(quien)\(importe)") + ".pdf"
                destino = nota.appending(nombre)
            }
            justificantes[fid] = (reservar(destino), c.texto("sha256"))
        }
    }

    // MARK: Escritura

    func escribirFinanzas() {
        emitidas.forEach(escribirFactura)
        escribirJustificantes()
        escribirRegistros()
        carpeta.registros("account").forEach(escribirCuenta)
        carpeta.registros("period").forEach(escribirPaquete)
    }

    func estadoFactura(_ r: G2Registro) -> String? {
        switch r.campos.texto("status") ?? "" {
        case "draft": return "Borrador"
        case "issued": return "Emitida"
        case "sent": return "Enviada"
        case "paid": return "Cobrada"
        case "rectified": return "Rectificada"
        case "": return nil
        case let s:
            avisar("Estados de factura que no se reconocen", r, queHacer: "Pon el estado a mano.")
            return s
        }
    }

    func pagos(de facturaId: String) -> [G2Registro] {
        carpeta.registros("payment").filter { $0.campos.texto("invoice_id") == facturaId }
            .sorted { (idCSV[$0.id ?? ""] ?? "") < (idCSV[$1.id ?? ""] ?? "") }
    }

    func escribirFactura(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Finanzas/<año>/<trimestre>/Ingresos", destino: area(.finanzas).carpeta + "/Fiscal/<año>/<trimestre>/Ingresos")
        let c = r.campos
        let numero = c.texto("number")
        let estado = estadoFactura(r)
        let base = c.entero("base_minor"), cuota = c.entero("tax_minor"), ret = c.entero("withholding_minor")
        let total = c.entero("total_minor")
        let iva = base.flatMap { b in cuota.flatMap { Dinero.porcentaje(parte: $0, base: b) } }
        let retPct = base.flatMap { b in ret.flatMap { Dinero.porcentaje(parte: $0, base: b) } }
        let oportunidad = c.texto("opportunity_id").flatMap { porId[$0] }
        let contactoId = oportunidad?.campos.texto("contact_id")
        let contacto = contactoId.flatMap { porId[$0] }
        let org = c.texto("organization_id").flatMap { porId[$0] }
        var fm = FrontmatterNuevo(tipo: "invoice", id: id)
        fm.texto("numero", numero)
        fm.texto("serie", numero.flatMap { $0.split(separator: "-").first.map(String.init) })
        fm.texto("estado", estado)
        fm.literal("fecha", c.fecha("issue_date"))
        fm.literal("vence", c.fecha("due_date"))
        fm.poner("empresa", enlace(c.texto("organization_id"), campo: "organization_id", en: r))
        fm.poner("contacto", contactoId.flatMap { destinos[$0] }.map(wikilink))
        fm.poner("oportunidad", enlace(c.texto("opportunity_id"), campo: "opportunity_id", en: r))
        fm.poner("servicio", oportunidad.flatMap { $0.campos.texto("service_id") }.flatMap { destinos[$0] }.map(wikilink))
        fm.poner("oferta_version", oportunidad.flatMap { $0.campos.texto("offer_version_id") }.flatMap { destinos[$0] }.map(wikilink))
        fm.poner("rectifica", enlace(c.texto("rectifies_id"), campo: "rectifies_id", en: r))
        fm.literal("iva_pct", iva)
        fm.literal("retencion_pct", retPct)
        fm.literal("base", base.map(Dinero.texto))
        fm.literal("cuota_iva", cuota.map(Dinero.texto))
        fm.literal("retencion", ret.map(Dinero.texto))
        fm.literal("total", total.map(Dinero.texto))
        fm.texto("categoria", c.texto("category"))
        if let pdf = justificantes[id] {
            fm.texto("pdf", pdf.ruta.name)
            fm.texto("pdf_sha256", pdf.sha)
        }
        fm.literal("origen", "importacion")
        if c.texto("project_id") != nil {
            avisar("Oportunidades y facturas que citan un proyecto que no está en la exportación", r,
                   queHacer: "Crea el proyecto de entrega si hace falta; la referencia no se ha copiado.")
        }
        revisar(r, usados: ["number", "status", "issue_date", "due_date", "organization_id", "opportunity_id", "rectifies_id",
                            "base_minor", "tax_minor", "withholding_minor", "total_minor", "category", "lines", "direction",
                            "document_id", "created_at", "archived_at", "origin"],
                motivos: ["nature": "La naturaleza (fijo, variable o inversión) es solo de los gastos."])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [estado, total.map { Dinero.legible($0) }, c.fecha("due_date").map { "vence el \(G2Fecha.corta($0))" }, tercero(r)]
        let cliente = tercero(r) ?? ""
        let contactoTexto = [contacto?.campos.texto("name"), contacto?.campos.texto("email")].compactMap { $0 }.joined(separator: " · ")
        nota.seccion("Partes", TablaMarkdown.texto(["Dato", "Emisor", "Cliente"], [
            ["Nombre", nombreEmpresa, cliente],
            ["NIF", "En el PDF", org?.campos.texto("tax_id") ?? ""],
            ["Contacto", "", contactoTexto],
        ]))
        var filas: [[String]] = []
        var condiciones: [String] = []
        for linea in c.lista("lines").compactMap(\.mapa) {
            filas.append([linea.texto("concept") ?? "", linea.texto("quantity") ?? "",
                          linea.entero("unit_price_minor").map { Dinero.legible($0) } ?? "", "",
                          iva.map { "\($0) %" } ?? "", linea.entero("base_minor").map { Dinero.legible($0) } ?? ""])
            if let cond = linea.texto("conditions"), !condiciones.contains(cond) { condiciones.append(cond) }
        }
        nota.seccion("Conceptos", filas.isEmpty ? nil : TablaMarkdown.texto(["Concepto", "Cantidad", "Precio", "Dto.", "IVA", "Importe"], filas))
        var totales: [[String]] = []
        if let base { totales.append(["Base imponible", Dinero.legible(base)]) }
        if let cuota { totales.append(["IVA\(iva.map { " \($0) %" } ?? "")", Dinero.legible(cuota)]) }
        if let ret { totales.append(["Retención IRPF\(retPct.map { " \($0) %" } ?? "")", "−" + Dinero.legible(ret)]) }
        if let total { totales.append(["**Total a pagar**", "**\(Dinero.legible(total))**"]) }
        nota.seccion("Totales", totales.isEmpty ? nil : TablaMarkdown.texto(["Concepto", "Importe"], totales))
        nota.seccion("Forma de pago", condiciones.isEmpty ? nil : condiciones.joined(separator: "\n\n"))
        nota.seccion("Notas", r.cuerpoUtil.map { reescribirRutasG2($0, desde: d.ruta) })
        var historial: [String] = []
        if let dia = c.fecha("issue_date"), estado != "Borrador" {
            historial.append("- \(dia) · Emitida\(numero.map { " como \($0)" } ?? "")")
        }
        for p in pagos(de: id) {
            let importe = p.campos.entero("amount_minor").map { " de \(Dinero.legible($0))" } ?? ""
            let metodo = p.campos.texto("method").map { " (\($0))" } ?? ""
            let confirmado = p.campos.texto("status") == "confirmed" ? "Cobro confirmado" : "Cobro sin confirmar"
            historial.append("- \(p.campos.fecha("paid_on") ?? "") · \(confirmado)\(importe)\(metodo)")
        }
        nota.seccion("Historial", historial.isEmpty ? nil : historial.joined(separator: "\n"))
        escribir(d.ruta, nota)
    }

    /// Copia los PDF a su sitio comprobando su SHA-256 y apunta su fecha en `Fechas de documentos.csv`.
    func escribirJustificantes() {
        var filas: [[String]] = []
        for doc in carpeta.registros("document") {
            let c = doc.campos
            guard let fid = c.texto("entity_id"), let destino = justificantes[fid], let rel = c.texto("rel_path"),
                  let fichero = carpeta.ficheros.first(where: { $0.ruta.raw == VaultPath(rel).raw }) else {
                avisar("Justificantes que no se han podido colocar", doc, queHacer: "Están en Archivo/Importación; colócalos a mano.")
                continue
            }
            contar(doc)
            tratadas.insert(fichero.ruta.raw)
            bloque("Justificantes y Documentos", destino: area(.finanzas).carpeta + "/Fiscal/<año>/<trimestre>/Gastos/<proveedor>")
            if let esperado = destino.sha {
                if let real = try? LocalFileSystem().sha256(of: fichero.url), real == esperado {
                    verificados += 1
                } else {
                    avisar("Justificantes cuyo contenido no coincide con su huella en G2", doc,
                           queHacer: "Comprueba el PDF: puede estar dañado o ser otra versión.")
                }
            }
            copiar(fichero.url, a: destino.ruta)
            let factura = porId[fid]
            filas.append([relativaAFinanzas(destino.ruta), factura.map(diaFactura) ?? "", "importacion",
                          factura?.campos.texto("number") ?? ""])
            revisar(doc, usados: ["entity_type", "entity_id", "rel_path", "sha256", "size_bytes", "title", "kind", "created_at", "origin"])
        }
        if !filas.isEmpty {
            filas.sort { ($0[0], $0[1]) < ($1[0], $1[1]) }
            escribir(ruta(.finanzas, "Fechas de documentos.csv"),
                     texto: EscrituraCSV.texto(cabecera: CabecerasCSV.fechasDeDocumentos, filas: filas))
        }
    }

    /// `emitidas.csv`, `recibidas.csv` y `pagos.csv`.
    func escribirRegistros() {
        let carpetaRegistros = "Registros"
        // Emitidas: solo las que tienen número (un borrador no es un documento emitido).
        var filasEmitidas: [[String]] = []
        for r in emitidas.sorted(by: { (diaFactura($0), $0.campos.texto("number") ?? "") < (diaFactura($1), $1.campos.texto("number") ?? "") }) {
            guard let id = r.id, let numero = r.campos.texto("number"), let d = destinos[id] else { continue }
            filasEmitidas.append([numero, diaFactura(r), tercero(r) ?? "", numero, r.campos.texto("currency") ?? "EUR",
                                  r.campos.entero("total_minor").map(Dinero.texto) ?? "", relativaAFinanzas(d.ruta),
                                  nombreEmpresa, "", "", "importacion"])
        }
        escribir(ruta(.finanzas, "\(carpetaRegistros)/emitidas.csv"),
                 texto: EscrituraCSV.texto(cabecera: CabecerasCSV.emitidas, filas: filasEmitidas))

        var filasRecibidas: [[String]] = []
        for r in recibidas.sorted(by: { (idCSV[$0.id ?? ""] ?? "") < (idCSV[$1.id ?? ""] ?? "") }) {
            guard let id = r.id, let fila = idCSV[id] else { continue }
            contar(r)
            bloque("Finanzas/<año>/<trimestre>/Gastos", destino: area(.finanzas).carpeta + "/Registros/recibidas.csv")
            let c = r.campos
            let documento = justificantes[id].map { relativaAFinanzas($0.ruta) } ?? ""
            if justificantes[id] == nil {
                avisar("Gastos sin justificante", r, queHacer: "Busca el original y guárdalo en su carpeta de Gastos.")
            }
            if c.lista("lines").compactMap(\.mapa).count > 1 {
                avisar("Gastos con varias líneas (en recibidas.csv va el total)", r, queHacer: "Nada, salvo que necesites el detalle.")
            }
            filasRecibidas.append([fila, diaFactura(r), tercero(r) ?? "", c.texto("number") ?? "", c.texto("currency") ?? "EUR",
                                   c.entero("total_minor").map(Dinero.texto) ?? "", documento, nombreEmpresa, "", "",
                                   "importacion", c.entero("base_minor").map(Dinero.texto) ?? "",
                                   c.entero("tax_minor").map(Dinero.texto) ?? "", c.entero("withholding_minor").map(Dinero.texto) ?? "",
                                   c.texto("category") ?? "", ""])
            revisar(r, usados: ["number", "issue_date", "organization_id", "currency", "total_minor", "document_id", "base_minor",
                                "tax_minor", "withholding_minor", "category", "direction", "lines", "status", "created_at",
                                "archived_at", "origin", "due_date"],
                    motivos: ["nature": "G2 usa otra clasificación; la naturaleza v2 (fijo, variable o inversión) queda vacía.",
                              "opportunity_id": "Un gasto no tiene oportunidad."])
        }
        escribir(ruta(.finanzas, "\(carpetaRegistros)/recibidas.csv"),
                 texto: EscrituraCSV.texto(cabecera: CabecerasCSV.recibidas, filas: filasRecibidas))

        var filasPagos: [[String]] = []
        let movimientos = Dictionary(carpeta.registros("movement").compactMap { m in m.id.map { ($0, m) } }, uniquingKeysWith: { a, _ in a })
        for r in carpeta.registros("payment").sorted(by: { (idCSV[$0.id ?? ""] ?? "") < (idCSV[$1.id ?? ""] ?? "") }) {
            guard let id = r.id, let fila = idCSV[id] else { continue }
            contar(r)
            bloque("Finanzas/<año>/<trimestre>/Cobros y pagos", destino: area(.finanzas).carpeta + "/Registros/pagos.csv")
            let c = r.campos
            let factura = c.texto("invoice_id").flatMap { porId[$0] }
            let direccion = factura.map { $0.campos.texto("direction") == "received" ? "pago" : "cobro" } ?? ""
            var evidencia = c.texto("evidence") ?? ""
            if let mid = c.texto("movement_id"), let mov = movimientos[mid], let movId = idCSV[mid],
               let cuenta = mov.campos.texto("account_id").flatMap({ destinos[$0] })?.ruta.parent {
                evidencia = relativaAFinanzas(cuenta.appending("movimientos.csv")) + "#" + movId
            } else if c.texto("movement_id") != nil {
                avisar("Pagos que citan un movimiento que no está en la exportación", r, queHacer: "Revisa la evidencia del cobro.")
            }
            if factura == nil, c.texto("invoice_id") != nil {
                avisar("Pagos de facturas que no están en la exportación", r, queHacer: "Revisa a qué documento corresponde.")
            }
            filasPagos.append([fila, c.fecha("paid_on") ?? "", direccion, c.entero("amount_minor").map { Dinero.texto(abs($0)) } ?? "",
                               factura?.campos.texto("currency") ?? "EUR", c.texto("invoice_id").flatMap { idCSV[$0] } ?? "", "",
                               factura.flatMap(tercero) ?? "", c.texto("method") ?? "", evidencia,
                               c.texto("status") == "confirmed" ? "confirmado" : ""])
            revisar(r, usados: ["paid_on", "invoice_id", "amount_minor", "method", "evidence", "movement_id", "status", "created_at"])
        }
        escribir(ruta(.finanzas, "\(carpetaRegistros)/pagos.csv"),
                 texto: EscrituraCSV.texto(cabecera: CabecerasCSV.pagos, filas: filasPagos))
    }

    // MARK: Bancos

    func naturaleza(_ s: String?) -> String {
        switch s ?? "" {
        case "": return ""
        case "operating_expense": return "gasto"
        case "operating_income": return "ingreso"
        case "tax": return "impuestos"
        case "payroll": return "nómina"
        case "internal_transfer": return "traspaso"
        case "owner_withdrawal": return "retirada del titular"
        case "financing": return "financiación"
        case "investment": return "inversión"
        case let x: return x
        }
    }

    func conciliacion(_ s: String?) -> String {
        switch s ?? "" {
        case "reconciled", "matched": "conciliado"
        case "ignored": "ignorado"
        case "proposed", "suggested": "propuesta"
        case "", "unmatched", "pending": "pendiente"
        case let x: x
        }
    }

    /// Extracto de banco del origen ya leído.
    struct Extracto {
        let fichero: G2Fichero
        let delimitador: Character
        let filas: [FilaExtracto]
        /// Columnas del fichero que corresponden a fecha, fecha_valor, concepto, importe y saldo.
        let columnas: [Propiedad]
        let coma: Bool
        let fechaISO: Bool
    }

    /// Extractos de banco del origen (CSV con fecha, concepto e importe).
    func extractos() -> [Extracto] {
        var out: [Extracto] = []
        for f in carpeta.ficheros where f.ruta.ext == "csv" && !f.ruta.raw.contains("Paquete gestoría") {
            guard let data = try? Data(contentsOf: f.url), let texto = TextDecoding.decode(data) else { continue }
            let tabla = CSVTable.parse(texto)
            let cab = tabla.header.map { TextFolding.fold($0).replacingOccurrences(of: " ", with: "_") }
            guard let iFecha = cab.firstIndex(of: "fecha"), let iConcepto = cab.firstIndex(of: "concepto"),
                  let iImporte = cab.firstIndex(of: "importe") else { continue }
            let iSaldo = cab.firstIndex(of: "saldo")
            let coma = tabla.rows.contains { $0.count > iImporte && $0[iImporte].contains(",") }
            let fechaISO = tabla.rows.allSatisfy { $0.count > iFecha && G2Fecha.esDia($0[iFecha].trimmingCharacters(in: .whitespaces)) }
            var filas: [FilaExtracto] = []
            var valido = true
            for fila in tabla.rows {
                guard fila.count > max(iFecha, iConcepto, iImporte), let dia = Self.diaDeExtracto(fila[iFecha]),
                      let importe = Self.centimos(fila[iImporte], coma: coma) else { valido = false; break }
                let saldo = iSaldo.flatMap { $0 < fila.count ? Self.centimos(fila[$0], coma: coma) : nil }
                filas.append(FilaExtracto(fecha: dia, concepto: fila[iConcepto], importe: importe, saldo: saldo))
            }
            guard valido, !filas.isEmpty else { continue }
            var columnas: [Propiedad] = []
            for clave in ["fecha", "fecha_valor", "concepto", "importe", "saldo"] {
                if let i = cab.firstIndex(of: clave) { columnas.append(Propiedad(clave: clave, valor: .texto(tabla.header[i]))) }
            }
            out.append(Extracto(fichero: f, delimitador: tabla.delimiter, filas: filas, columnas: columnas, coma: coma,
                                fechaISO: fechaISO))
        }
        return out
    }

    static func diaDeExtracto(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if G2Fecha.esDia(t) { return t }
        let p = t.split(separator: "/")
        guard p.count == 3, let d = Int(p[0]), let m = Int(p[1]), let y = Int(p[2]) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// `-663,00` (coma decimal, punto de miles) o `-663.00` → céntimos exactos.
    static func centimos(_ s: String, coma: Bool) -> Int? {
        var t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: " ", with: "")
        if coma { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        guard !t.isEmpty, let d = G2Numero.decimal(t) else { return nil }
        return G2Numero.entero("\(d * 100)")
    }

    func escribirCuenta(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id], let carpetaCuenta = d.ruta.parent else { return }
        contar(r)
        bloque("Finanzas/Bancos", destino: area(.finanzas).carpeta + "/Registros/Bancos/<cuenta>")
        let c = r.campos
        let movimientos = carpeta.registros("movement").filter { $0.campos.texto("account_id") == id }
        let hashes = Set(movimientos.compactMap { $0.campos.texto("import_hash") ?? hashDeMovimiento($0) })
        // Un extracto es de esta cuenta si todas sus filas reproducen hashes de sus movimientos.
        var posicion: [String: Int] = [:]
        var lote: String?
        var formato: ValorYAML?
        for e in extractos() where !tratadas.contains(e.fichero.ruta.raw) {
            var repetidas: [String: Int] = [:]
            let hs = e.filas.map { f -> String in
                let base = "\(f.fecha)|\(f.importe)|\(f.concepto.lowercased())"
                if f.saldo == nil { repetidas[base, default: 0] += 1 }
                return Self.importHash(cuenta: id, fila: f, repeticion: f.saldo == nil ? repetidas[base]! : 1)
            }
            guard !hs.isEmpty, hs.allSatisfy(hashes.contains) else { continue }
            for (i, h) in hs.enumerated() where posicion[h] == nil { posicion[h] = i }
            let dias = movimientos.filter { hs.contains($0.campos.texto("import_hash") ?? "") }.compactMap { $0.campos.fecha("created_at") }
            let nombre = "\(dias.min() ?? fecha) \(e.fichero.ruta.name)"
            let destino = reservar(carpetaCuenta.appending("Extractos/\(nombre)"))
            copiar(e.fichero.url, a: destino)
            tratadas.insert(e.fichero.ruta.raw)
            bloque("Finanzas/Bancos/extractos", destino: area(.finanzas).carpeta + "/Registros/Bancos/<cuenta>/Extractos")
            lote = destino.name
            formato = .mapa([Propiedad(clave: "separador", valor: .texto(String(e.delimitador))),
                             Propiedad(clave: "decimal", valor: .texto(e.coma ? "," : ".")),
                             Propiedad(clave: "formato_fecha", valor: .texto(e.fechaISO ? "AAAA-MM-DD" : "DD/MM/AAAA")),
                             Propiedad(clave: "columnas", valor: .mapa(e.columnas))])
        }
        var fm = FrontmatterNuevo(tipo: "account", id: id)
        fm.texto("nombre", c.texto("name"))
        if let iban = c.texto("iban_masked") {
            let digitos = iban.filter(\.isNumber)
            if digitos.count >= 4 { fm.texto("iban_ultimos4", String(digitos.suffix(4))) }
        }
        fm.texto("moneda", c.texto("currency"))
        fm.literal("saldo_inicial", c.entero("opening_balance_minor").map(Dinero.texto))
        fm.literal("fecha_saldo_inicial", c.fecha("opening_on"))
        fm.texto("estado", c.texto("archived_at") == nil ? "Activa" : "Cerrada")
        fm.poner("formato_extracto", formato)
        revisar(r, usados: ["name", "iban_masked", "currency", "opening_balance_minor", "opening_on", "archived_at", "created_at"])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [c.texto("iban_masked").map { "terminada en \(String($0.filter(\.isNumber).suffix(4)))" },
                        c.texto("archived_at") == nil ? "Activa" : "Cerrada"]
        nota.seccion("Para qué se usa")
        nota.seccion("Formato del extracto")
        nota.seccion("Notas", r.cuerpoUtil)
        escribir(d.ruta, nota)

        // movimientos.csv: orden del banco (fecha y posición en el extracto).
        func clave(_ m: G2Registro) -> (String, Int, String) {
            let h = m.campos.texto("import_hash") ?? hashDeMovimiento(m) ?? ""
            return (m.campos.fecha("booked_on") ?? "", posicion[h] ?? Int.max, m.id ?? "")
        }
        var filas: [[String]] = []
        for m in movimientos.sorted(by: { clave($0) < clave($1) }) {
            guard let mid = m.id else { continue }
            contar(m)
            bloque("Finanzas/Bancos/<cuenta>/<trimestre>", destino: area(.finanzas).carpeta + "/Registros/Bancos/<cuenta>/movimientos.csv")
            let mc = m.campos
            let calculado = hashDeMovimiento(m)
            let hash = mc.texto("import_hash") ?? calculado ?? ""
            if let calculado, let guardado = mc.texto("import_hash"), calculado != guardado {
                avisar("Movimientos cuyo import_hash no sigue el contrato de PLAN §4.6", m, queHacer: "Se conserva el de G2; revísalo.")
            }
            let enExtracto = posicion[hash] != nil
            let motivo = [mc.texto("match_reason"), m.cuerpoUtil].compactMap { $0 }.joined(separator: " · ")
            filas.append([idCSV[mid] ?? "", mc.fecha("booked_on") ?? "", mc.fecha("value_on") ?? "", mc.texto("description") ?? "",
                          mc.entero("amount_minor").map(Dinero.texto) ?? "", mc.entero("balance_after_minor").map(Dinero.texto) ?? "",
                          naturaleza(mc.texto("nature")), mc.texto("category") ?? "", "",
                          mc.texto("invoice_id").flatMap { idCSV[$0] } ?? "", mc.texto("payment_id").flatMap { idCSV[$0] } ?? "",
                          conciliacion(mc.texto("status")), motivo, hash,
                          enExtracto ? (lote ?? "") : (mc.texto("import_batch") ?? ""), ""])
            revisar(m, usados: ["account_id", "booked_on", "value_on", "description", "amount_minor", "balance_after_minor", "nature",
                                "category", "invoice_id", "payment_id", "status", "match_reason", "import_hash", "import_batch",
                                "created_at"],
                    motivos: ["counterparty": "movimientos.csv no tiene columna de contraparte; va en el concepto.",
                              "document_id": "El documento se enlaza por la factura (documento_id)."])
        }
        escribir(carpetaCuenta.appending("movimientos.csv"),
                 texto: EscrituraCSV.texto(cabecera: CabecerasCSV.movimientos, filas: filas))
    }

    // MARK: Paquete trimestral

    func escribirPaquete(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id], let carpetaPaquete = d.ruta.parent else { return }
        contar(r)
        bloque("Finanzas/<año>/<trimestre>/Paquete gestoría", destino: area(.finanzas).carpeta + "/Fiscal/<año>/<trimestre>/Modelos/Paquete gestoría")
        let c = r.campos
        let resumen = c.mapa("summary") ?? .vacio
        let estado: String? = switch c.texto("status") ?? "" {
        case "draft", "preparing": "Preparando"
        case "prepared": "Preparado"
        case "sent": "Enviado"
        case "filed", "submitted": "Presentado"
        case "": nil
        case let s: s
        }
        var fm = FrontmatterNuevo(tipo: "period", id: id)
        fm.texto("periodo", c.texto("quarter").flatMap { t in c.texto("year").map { "T\(t) \($0)" } })
        fm.literal("desde", resumen.fecha("from"))
        fm.literal("hasta", resumen.fecha("to"))
        fm.texto("estado", estado)
        fm.poner("listo", resumen.bool("ready").map { .bool($0) })
        fm.literal("origen", "importacion")
        revisar(r, usados: ["quarter", "year", "status", "summary", "package_path", "created_at"],
                motivos: ["history": "Historial interno de G2."])
        // El índice que escribió G2 (sin propiedades) es el cuerpo de la nota nueva.
        let carpetaG2 = c.texto("package_path").map(VaultPath.init) ?? r.ruta.parent?.appending("Paquete gestoría")
        let indiceG2 = carpetaG2.flatMap { cg in carpeta.registros.first { $0.ruta == cg.appending("indice.md") } }
        var nota = NotaNueva(frontmatter: fm)
        if let indiceG2 {
            tratadas.insert(indiceG2.ruta.raw)
            nota.cuerpoLiteral = indiceG2.cuerpo
        } else {
            nota.titulo = d.nombre
        }
        escribir(d.ruta, nota)
        guard let carpetaG2 else { return }
        for f in carpeta.ficheros where f.ruta.parent == carpetaG2 {
            copiar(f.url, a: reservar(carpetaPaquete.appending(f.ruta.name)))
            tratadas.insert(f.ruta.raw)
            if f.ruta.ext == "csv", let data = try? Data(contentsOf: f.url), let texto = TextDecoding.decode(data) {
                let tabla = CSVTable.parse(texto)
                if let i = tabla.header.firstIndex(of: "id"),
                   tabla.rows.contains(where: { $0.count > i && $0[i].range(of: #"^\[[0-9 ]+\]$"#, options: .regularExpression) != nil }) {
                    avisar("CSV del paquete de la gestoría con la columna id mal exportada (lista de números)",
                           ruta: f.ruta.raw, queHacer: "Se copian tal cual; vuelve a generar el paquete desde la app.")
                }
            }
        }
    }
}
