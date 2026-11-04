import Foundation

/// Una fila heredada y lo que se hará con ella.
public struct FilaHeredada: Sendable, Hashable {
    public enum Destino: String, Sendable, Hashable {
        /// Ingreso con factura → `emitidas.csv`.
        case emitida
        /// Gasto con factura → `recibidas.csv`.
        case recibida
        /// Sin factura (cuota de autónomos, impuestos, nómina…) → solo `pagos.csv`, sin confirmar.
        case pago
    }

    public let fichero: VaultPath
    /// Fila del fichero (2 = la primera tras la cabecera).
    public let fila: Int
    public let destino: Destino
    /// Fila del registro de destino (`emitidas`/`recibidas`/`pagos`).
    public let registro: [String: String]
    /// Fila de `pagos.csv` si el fichero heredado la daba por cobrada o pagada (`verificacion` vacía).
    public let pago: [String: String]?
    /// Ya estaba cargada (no se vuelve a escribir).
    public let yaCargada: Bool
}

/// Lo que se va a cargar en preparación, antes de escribir nada.
public struct PreparacionHeredada: Sendable {
    public let ficheros: [VaultPath]
    public let filas: [FilaHeredada]
    /// Filas que no se pudieron leer, con el motivo.
    public let avisos: [String]
    let rutas: (emitidas: VaultPath, recibidas: VaultPath, pagos: VaultPath)
    /// Texto de cada registro en la foto (`nil` si aún no existe).
    let textos: (emitidas: String?, recibidas: String?, pagos: String?)

    public var nuevas: [FilaHeredada] { filas.filter { !$0.yaCargada } }

    public var resumen: String {
        Plural.de(filas.count, "movimiento heredado", "movimientos heredados") + " · "
            + Plural.de(nuevas.count, "nuevo", "nuevos") + " · "
            + Plural.de(filas.count - nuevas.count, "ya cargado", "ya cargados")
    }

    /// Escribir las filas nuevas en preparación (todo o nada, un solo Deshacer). `nil` si no hay nada nuevo.
    /// Nunca escribe `verificacion: confirmado` ni toca `movimientos.csv` del banco.
    public func plan(autor: Autor) -> WritePlan? {
        let nuevas = self.nuevas
        guard !nuevas.isEmpty else { return nil }
        var ops: [WriteOp] = []
        func escribir(_ filas: [[String: String]], en ruta: VaultPath, texto: String?, deSerie: [String]) {
            guard !filas.isEmpty else { return }
            if let texto {
                // En un registro de antes (G3), cada dato va a su columna equivalente (`fecha`, `cliente`, `importe`).
                let cab = Self.cabecera(texto)
                ops += CSVEscritura.filasNuevas(filas.map { Self.adaptar($0, a: cab) }, en: ruta, texto: texto)
            } else {
                ops.append(CommandBus.Comando.crear(ruta, texto: CSVEscritura.texto(cabecera: deSerie, filas: filas)).op)
            }
        }
        escribir(nuevas.filter { $0.destino == .emitida }.map(\.registro), en: rutas.emitidas, texto: textos.emitidas,
                 deSerie: RegistrosFinanzas.cabeceraEmitidas)
        escribir(nuevas.filter { $0.destino == .recibida }.map(\.registro), en: rutas.recibidas, texto: textos.recibidas,
                 deSerie: RegistrosFinanzas.cabeceraRecibidas)
        let pagos = nuevas.compactMap { $0.destino == .pago ? $0.registro : $0.pago }
        escribir(pagos, en: rutas.pagos, texto: textos.pagos, deSerie: RegistrosFinanzas.cabeceraPagos)
        return WritePlan(autor: autor, descripcion: "Cargar " + Plural.de(nuevas.count, "movimiento heredado", "movimientos heredados")
                         + " en preparación", ops: ops)
    }

    /// Columnas que el fichero heredado trae y el registro de destino no tiene (se pierden al cargar).
    public var columnasQueNoCaben: [String] {
        var out = Set<String>()
        for f in nuevas {
            func cabecera(_ texto: String?, _ deSerie: [String]) -> Set<String> {
                texto.map(Self.cabecera) ?? Set(deSerie)
            }
            let cab: Set<String>
            switch f.destino {
            case .emitida: cab = cabecera(textos.emitidas, RegistrosFinanzas.cabeceraEmitidas)
            case .recibida: cab = cabecera(textos.recibidas, RegistrosFinanzas.cabeceraRecibidas)
            case .pago: cab = cabecera(textos.pagos, RegistrosFinanzas.cabeceraPagos)
            }
            for (k, v) in Self.adaptar(f.registro, a: cab) where !v.isEmpty && !cab.contains(k) { out.insert(k) }
        }
        return out.sorted()
    }

    /// Las columnas de un CSV (sin espacios, en minúsculas).
    static func cabecera(_ texto: String) -> Set<String> {
        Set(CSVTable.parse(texto).header.map { $0.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping.lowercased() })
    }

    /// Una fila de la v2 escrita en un registro de antes: lo que no tiene columna propia va a su equivalente
    /// (`RegistrosFinanzas.columnasDeAntes`) si el registro la tiene y está libre.
    static func adaptar(_ fila: [String: String], a cabecera: Set<String>) -> [String: String] {
        var out = fila
        for (clave, valor) in fila where !cabecera.contains(clave) {
            guard let equivalente = RegistrosFinanzas.columnasDeAntes[clave]?.first(where: { cabecera.contains($0) && out[$0] == nil })
            else { continue }
            out[equivalente] = valor
            out[clave] = nil
        }
        return out
    }
}

/// Carga movimientos heredados de `4 · Finanzas/Registros/importar/*.csv` en la **zona de preparación** (PLAN §7.3):
/// filas de emitidas, recibidas y pagos con `estado_revision: pendiente` y `verificacion` vacía.
/// Nunca las confirma ni inventa movimientos del banco: `movimientos.csv` no se toca. Volver a cargar no duplica.
///
/// Columnas que entiende (sin distinguir mayúsculas ni tildes): fecha (de cobro o pago), fecha de factura,
/// concepto, tercero/cliente/proveedor, importe/total, base, IVA, retención, tipo (Ingreso/Gasto o cobro/pago),
/// número de factura, categoría, naturaleza, tipo fiscal, cobrado/pagado, justificante/documento y moneda.
/// Si el fichero trae «importe» e «IVA» pero no «total» ni «base», el importe es la **base** (como en la
/// exportación de Finanzas de Notion) y el total = base + IVA − retención.
public struct LegacyMovementsImporter: Sendable {
    public let registros: RegistrosFinanzas

    public init(snapshot: VaultSnapshot) {
        registros = RegistrosFinanzas(snapshot: snapshot)
    }

    /// `4 · Finanzas/Registros/importar`.
    public var carpeta: VaultPath { registros.registrosCarpeta.appending("importar") }

    /// Los CSV heredados (sin los privados).
    public var ficheros: [VaultPath] {
        let s = registros.snapshot
        guard let dir = s.existing(carpeta), !s.layout.isPrivate(dir) else { return [] }
        return s.files.filter { $0.parent == dir && $0.ext.lowercased() == "csv" && !s.layout.isPrivate($0) }
    }

    static let sinonimos: [String: [String]] = [
        "fecha": ["fecha", "fecha cobro/pago", "fecha cobro", "fecha pago", "fecha de cobro", "fecha de pago", "fecha movimiento"],
        "fecha_factura": ["fecha factura", "fecha de factura", "fecha documento", "fecha del documento"],
        "concepto": ["concepto", "descripcion", "detalle"],
        "tercero": ["tercero", "cliente", "proveedor", "contraparte", "cliente/proveedor", "empresa"],
        "total": ["total", "importe total", "total factura", "total documento"],
        "importe": ["importe", "cantidad"],
        "base": ["base", "base imponible"],
        "iva": ["iva", "cuota iva", "cuota de iva"],
        "retencion": ["retencion", "retencion irpf", "irpf"],
        "tipo": ["tipo", "direccion", "tipo de movimiento"],
        "numero": ["numero factura", "numero de factura", "n factura", "no factura", "num factura", "factura", "numero"],
        "categoria": ["categoria"],
        "naturaleza": ["naturaleza"],
        "tipo_fiscal": ["tipo fiscal"],
        "cobrado": ["cobrado/pagado", "cobrado", "pagado", "cobrada", "pagada", "estado"],
        "documento": ["justificante", "archivo factura", "documento", "archivo"],
        "moneda": ["moneda", "divisa"],
    ]

    static func clave(_ cabecera: String) -> String? {
        let n = BankStatementParser.normalizar(cabecera).replacingOccurrences(of: "º", with: "").replacingOccurrences(of: "nº", with: "n")
        return sinonimos.first { $0.value.contains(n) }?.key
    }

    /// Sin factura por naturaleza: cuota de autónomos, seguridad social, impuestos, nómina, salario.
    static func sinFactura(tipoFiscal: String?, categoria: String?, naturaleza: String?) -> Bool {
        let tf = TextFolding.fold(tipoFiscal ?? "")
        if ["reta", "salario", "hacienda"].contains(tf) { return true }
        let t = TextFolding.fold((categoria ?? "") + " " + (naturaleza ?? ""))
        return ["seguridad social", "reta", "impuesto", "nomina", "salario", "hacienda", "aeat", "tgss"].contains { t.contains($0) }
    }

    static func siONo(_ s: String?) -> Bool? {
        guard let s else { return nil }
        let t = TextFolding.fold(s)
        if ["si", "sí", "yes", "true", "x", "1", "cobrado", "cobrada", "pagado", "pagada", "conciliado"].contains(t) { return true }
        if ["no", "false", "0", "pendiente", ""].contains(t) { return false }
        return nil
    }

    public func preparar() -> PreparacionHeredada {
        let s = registros.snapshot
        var avisos: [String] = []
        var filas: [FilaHeredada] = []
        // Claves de lo que ya está en los registros (con repeticiones), para no cargar dos veces.
        var existentes: [String: Int] = [:]
        // Un registro que no guarda el número de factura (los de antes, G3) no lo cuenta en la clave: si no, lo cargado
        // volvería a salir como nuevo.
        func guardaNumero(_ ruta: VaultPath) -> Bool {
            guard let t = s.existing(ruta).flatMap({ s.text($0) }) else { return true }
            let cab = PreparacionHeredada.cabecera(t)
            return (["numero_documento"] + (RegistrosFinanzas.columnasDeAntes["numero_documento"] ?? [])).contains { cab.contains($0) }
        }
        let numeroEn: [FilaHeredada.Destino: Bool] = [.emitida: guardaNumero(registros.emitidasCSV),
                                                       .recibida: guardaNumero(registros.recibidasCSV)]
        for f in registros.emitidas {
            existentes[Self.claveRegistro(.emitida, f.fecha, f.total, f.tercero, numeroEn[.emitida]! ? f.numero : nil), default: 0] += 1
        }
        for f in registros.recibidas {
            existentes[Self.claveRegistro(.recibida, f.fecha, f.total, f.tercero, numeroEn[.recibida]! ? f.numero : nil), default: 0] += 1
        }
        for p in registros.pagos where p.documentoID == nil {
            existentes[Self.claveRegistro(.pago, p.fecha, p.importe, p.tercero, nil), default: 0] += 1
        }
        var idsEmitidas = Set(registros.emitidas.map(\.id))
        var secuencias: [String: Int] = [:]
        func siguiente(_ prefijo: String, _ fecha: LocalDate, ids: [String]) -> String {
            let p = "\(prefijo)-\(fecha.description.replacingOccurrences(of: "-", with: ""))-"
            let n = secuencias[p] ?? ids.compactMap { $0.hasPrefix(p) ? Int($0.dropFirst(p.count)) : nil }.max() ?? 0
            secuencias[p] = n + 1
            return p + String(format: "%03d", n + 1)
        }
        var vistas: [String: Int] = [:]
        for fichero in ficheros {
            guard let texto = s.text(fichero) else {
                avisos.append("«\(fichero.name)» no se puede leer como texto.")
                continue
            }
            let tabla = CSVTable.parse(texto)
            let claves = tabla.header.map(Self.clave)
            guard claves.contains("fecha") || claves.contains("fecha_factura"),
                  claves.contains("importe") || claves.contains("total") || claves.contains("base") else {
                avisos.append("«\(fichero.name)» no tiene columnas de fecha e importe: no lo cargo.")
                continue
            }
            let importeEsBase = claves.contains("importe") && claves.contains("iva") && !claves.contains("total") && !claves.contains("base")
            let decimalComa = tabla.delimiter == ";"
            for (i, r) in tabla.rows.enumerated() {
                let n = i + 2
                var d: [String: String] = [:]
                for (j, k) in claves.enumerated() {
                    guard let k, j < r.count, d[k] == nil else { continue }
                    let v = r[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { d[k] = v }
                }
                if d.isEmpty { continue }
                func cent(_ k: String) -> Int?? {
                    guard let v = d[k] else { return .some(nil) }
                    let c = decimalComa ? DineroExacto.centimos(v, decimal: ",") : DineroExacto.centimos(v)
                    return c.map { .some($0) } ?? nil
                }
                guard let fechaPago = (d["fecha"] ?? d["fecha_factura"]).flatMap({ LocalDate(parsing: $0) }) else {
                    avisos.append("«\(fichero.name)», fila \(n): sin fecha que entienda.")
                    continue
                }
                let fechaFactura = d["fecha_factura"].flatMap { LocalDate(parsing: $0) } ?? fechaPago
                guard let importe = cent("importe"), let totalCol = cent("total"), let baseCol = cent("base"),
                      let iva = cent("iva"), let retencion = cent("retencion") else {
                    avisos.append("«\(fichero.name)», fila \(n): un importe que no entiendo.")
                    continue
                }
                let base = importeEsBase ? importe : baseCol
                var total = totalCol
                // Total = base + IVA − retención, con el signo de la base.
                func desdeBase(_ b: Int) -> Int {
                    let t = abs(b) + abs(iva ?? 0) - abs(retencion ?? 0)
                    return b < 0 ? -t : t
                }
                if total == nil {
                    if importeEsBase, let b = importe { total = desdeBase(b) }
                    else if let b = baseCol, iva != nil { total = desdeBase(b) }
                    else { total = importe }
                }
                guard let totalConSigno = total else {
                    avisos.append("«\(fichero.name)», fila \(n): sin importe.")
                    continue
                }
                // Ingreso o gasto: por la columna tipo; si no hay, por el signo.
                let tipo = TextFolding.fold(d["tipo"] ?? "")
                let ingreso: Bool = tipo.hasPrefix("ingreso") || tipo == "cobro" || tipo == "entrada"
                    ? true : tipo.hasPrefix("gasto") || tipo == "pago" || tipo == "salida" ? false : totalConSigno >= 0
                let magnitud = abs(totalConSigno)
                let tercero = d["tercero"] ?? d["concepto"] ?? ""
                let numero = d["numero"]
                let sinFactura = Self.sinFactura(tipoFiscal: d["tipo_fiscal"], categoria: d["categoria"], naturaleza: d["naturaleza"])
                let destino: FilaHeredada.Destino = sinFactura ? .pago : ingreso ? .emitida : .recibida
                let clave = destino == .pago
                    ? Self.claveRegistro(.pago, fechaPago, magnitud, tercero, nil)
                    : Self.claveRegistro(destino, fechaFactura, magnitud, tercero, numeroEn[destino] ?? true ? numero : nil)
                vistas[clave, default: 0] += 1
                let yaCargada = vistas[clave]! <= existentes[clave, default: 0]
                let documento = d["documento"].flatMap { v -> String? in
                    // Solo rutas de la carpeta que existan y no sean privadas (nunca enlaces de fuera).
                    guard let r = RegistrosFinanzas.resolverDocumento(v.removingPercentEncoding ?? v, finanzas: registros.carpeta, snapshot: s),
                          !s.layout.isPrivate(r) else { return nil }
                    return registros.rutaRelativa(r)
                } ?? ""
                func dinero(_ v: Int?) -> String { v.map { DineroExacto.csv(abs($0)) } ?? "" }
                let cobrado = Self.siONo(d["cobrado"]) ?? false
                let evidencia = registros.rutaRelativa(fichero) + "#fila-\(n)"
                var registro: [String: String]
                var pago: [String: String]?
                switch destino {
                case .emitida, .recibida:
                    registro = ["fecha_documento": fechaFactura.description, "tercero": tercero,
                                "numero_documento": numero ?? "", "moneda": d["moneda"] ?? "",
                                "total_documento": DineroExacto.csv(magnitud), "documento": documento,
                                "estado_revision": "pendiente", "fuente": "importacion",
                                "base": dinero(base), "iva": dinero(iva), "retencion": dinero(retencion),
                                "categoria": d["categoria"] ?? "", "naturaleza": d["naturaleza"] ?? "",
                                "tipo_fiscal": d["tipo_fiscal"] ?? ""]
                    if cobrado {
                        pago = ["fecha": fechaPago.description, "direccion": ingreso ? "cobro" : "pago",
                                "importe": DineroExacto.csv(magnitud), "moneda": d["moneda"] ?? "", "tercero": tercero,
                                "evidencia": evidencia, "verificacion": ""]
                    }
                case .pago:
                    registro = ["fecha": fechaPago.description, "direccion": ingreso ? "cobro" : "pago",
                                "importe": DineroExacto.csv(magnitud), "moneda": d["moneda"] ?? "", "documento_id": "",
                                "tercero": tercero, "evidencia": evidencia, "verificacion": ""]
                }
                // Los números (EMI-, REC-, PAG-) solo se dan a lo que se va a escribir.
                if !yaCargada {
                    switch destino {
                    case .emitida:
                        let id: String
                        if let numero, !idsEmitidas.contains(numero) { id = numero } else {
                            id = siguiente("EMI", fechaFactura, ids: Array(idsEmitidas))
                        }
                        idsEmitidas.insert(id)
                        registro["id"] = id
                    case .recibida:
                        registro["id"] = siguiente("REC", fechaFactura, ids: registros.recibidas.map(\.id))
                    case .pago:
                        registro["id"] = siguiente("PAG", fechaPago, ids: registros.pagos.map(\.id))
                    }
                    if pago != nil {
                        pago?["id"] = siguiente("PAG", fechaPago, ids: registros.pagos.map(\.id))
                        pago?["documento_id"] = registro["id"]
                    }
                }
                filas.append(FilaHeredada(fichero: fichero, fila: n, destino: destino, registro: registro, pago: pago,
                                          yaCargada: yaCargada))
            }
        }
        func texto(_ ruta: VaultPath) -> String? { s.existing(ruta).flatMap { s.text($0) } }
        return PreparacionHeredada(ficheros: ficheros, filas: filas, avisos: avisos,
                                   rutas: (registros.emitidasCSV, registros.recibidasCSV, registros.pagosCSV),
                                   textos: (texto(registros.emitidasCSV), texto(registros.recibidasCSV), texto(registros.pagosCSV)))
    }

    /// Clave de contenido para no cargar dos veces: tipo, fecha, importe, tercero y número (plegados).
    static func claveRegistro(_ destino: FilaHeredada.Destino, _ fecha: LocalDate?, _ importe: Int?, _ tercero: String?,
                              _ numero: String?) -> String {
        [destino.rawValue, fecha?.description ?? "", importe.map { String(abs($0)) } ?? "",
         TextFolding.fold(tercero ?? "").filter { $0.isLetter || $0.isNumber },
         TextFolding.fold(numero ?? "").filter { $0.isLetter || $0.isNumber }].joined(separator: "|")
    }
}
