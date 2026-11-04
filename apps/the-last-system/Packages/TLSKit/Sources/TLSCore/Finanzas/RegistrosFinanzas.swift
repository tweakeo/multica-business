import Foundation

/// Una cuenta del banco: `4 · Finanzas/Registros/Bancos/<carpeta>/Cuenta.md` (`tls_type: account`).
public struct CuentaBancaria: Sendable, Hashable, Identifiable {
    /// `id` de la ficha: entra en el `import_hash` de cada movimiento (PLAN §4.6).
    public let id: String
    public let ficha: VaultPath
    public let carpeta: VaultPath
    public let nombre: String
    public let ibanUltimos4: String?
    public let moneda: String
    /// Céntimos. `nil` si la ficha no lo dice.
    public let saldoInicial: Int?
    public let fechaSaldoInicial: LocalDate?
    /// `nil` si la ficha no lo tiene o está sin rellenar.
    public let formato: FormatoExtracto?

    public var movimientosCSV: VaultPath { carpeta.appending("movimientos.csv") }
    public var extractos: VaultPath { carpeta.appending("Extractos") }
}

/// Estado de conciliación de un movimiento (`estado_conciliacion`).
public enum EstadoConciliacion: String, Sendable, Hashable, CaseIterable {
    case pendiente, propuesta, conciliado, ignorado

    /// Vacío o desconocido = pendiente.
    public init(leyendo texto: String?) {
        let t = TextFolding.fold(texto ?? "").trimmingCharacters(in: .whitespaces)
        switch t {
        case "propuesta", "propuesto": self = .propuesta
        case "conciliado", "conciliada": self = .conciliado
        case "ignorado", "ignorada": self = .ignorado
        default: self = .pendiente
        }
    }

    /// Ni conciliado ni ignorado (FIN-UNREC).
    public var abierto: Bool { self == .pendiente || self == .propuesta }
}

/// Una fila de `movimientos.csv`.
public struct MovimientoBanco: Sendable, Hashable, Identifiable {
    public let id: String
    public let cuentaID: String
    public let fecha: LocalDate
    public let fechaValor: LocalDate?
    public let concepto: String
    /// Céntimos con el signo del banco.
    public let importe: Int
    public let saldo: Int?
    public let naturaleza: String?
    public let categoria: String?
    public let proyectoID: String?
    public let documentoID: String?
    public let pagoID: String?
    public let estado: EstadoConciliacion
    public let motivo: String?
    public let importHash: String?
    public let lote: String?
    /// Posición en el fichero (0 = primera fila de datos): desempata movimientos del mismo día.
    public let orden: Int

    /// Traspaso entre cuentas propias (por su naturaleza).
    public var esTraspasoDeclarado: Bool { TextFolding.fold(naturaleza ?? "").hasPrefix("traspaso") }
}

/// Factura emitida (`emitidas.csv`) o recibida (`recibidas.csv`).
public struct FacturaRegistro: Sendable, Hashable, Identifiable {
    public enum Tipo: String, Sendable, Hashable { case emitida, recibida }

    public let id: String
    public let tipo: Tipo
    public let fecha: LocalDate?
    public let tercero: String?
    public let numero: String?
    public let moneda: String?
    /// Céntimos. `nil` si la fila no lo dice (nunca se toma como 0).
    public let total: Int?
    /// Ruta tal como la escribe la fila (relativa a la carpeta de Finanzas).
    public let documento: String?
    /// Ruta del documento en la carpeta, si existe y no es privada.
    public let rutaDocumento: VaultPath?
    /// El documento está en una carpeta privada: no se enseña su ruta.
    public let documentoPrivado: Bool
    public let proyectoID: String?
    public let estadoRevision: String?
    public let fuente: String?
    /// Base, IVA y retención: de las columnas o, si no las hay, de la ficha de la factura.
    public let base: Int?
    public let iva: Int?
    public let retencion: Int?
    public let categoria: String?
    public let naturaleza: String?
    /// `tipo_fiscal` si la fila lo trae (estandar, extranjero, gasolina…).
    public let tipoFiscal: String?
    /// Vencimiento de la ficha de la factura (`vence`).
    public let vence: LocalDate?
    /// `oportunidad` de la ficha de la factura, tal como está escrita (enlace).
    public let oportunidad: String?

    /// Fila cargada de un fichero heredado y aún sin revisar (`estado_revision: pendiente`).
    public var sinRevisar: Bool { TextFolding.fold(estadoRevision ?? "") == "pendiente" }

    /// Número con el que se reconoce en un concepto del banco.
    public var numeroVisible: String { numero ?? id }
}

/// Una fila de `pagos.csv` (`importe` positivo y `direccion` cobro o pago).
public struct PagoRegistro: Sendable, Hashable, Identifiable {
    public enum Direccion: String, Sendable, Hashable { case cobro, pago }

    public let id: String
    public let fecha: LocalDate?
    public let direccion: Direccion?
    public let importe: Int?
    public let moneda: String?
    public let documentoID: String?
    public let proyectoID: String?
    public let tercero: String?
    public let metodo: String?
    public let evidencia: String?
    public let verificacion: String?

    /// Solo cuenta lo confirmado por una persona (`verificacion: confirmado`).
    public var confirmado: Bool { TextFolding.fold(verificacion ?? "") == "confirmado" }
}

/// Los registros de Finanzas leídos de una foto de la carpeta: cuentas, movimientos del banco,
/// facturas emitidas y recibidas, y pagos. Nunca escribe.
///
/// Lo privado (`privado` de `.tls/`) no entra: ni cuentas en carpetas privadas, ni registros privados,
/// ni la ruta de un documento privado. Lo retirado a `Archivo/` tampoco.
public struct RegistrosFinanzas: Sendable {
    public let snapshot: VaultSnapshot
    /// `4 · Finanzas`.
    public let carpeta: VaultPath
    public let cuentas: [CuentaBancaria]
    /// Todos los movimientos de todas las cuentas, por fecha (y su orden en el fichero).
    public let movimientos: [MovimientoBanco]
    public let emitidas: [FacturaRegistro]
    public let recibidas: [FacturaRegistro]
    public let pagos: [PagoRegistro]
    /// Lo que no se pudo leer, en castellano.
    public let avisos: [String]

    public var registrosCarpeta: VaultPath { carpeta.appending("Registros") }
    public var emitidasCSV: VaultPath { registrosCarpeta.appending("emitidas.csv") }
    public var recibidasCSV: VaultPath { registrosCarpeta.appending("recibidas.csv") }
    public var pagosCSV: VaultPath { registrosCarpeta.appending("pagos.csv") }

    /// Cabeceras de serie (`Esquema.md`, PLAN §4.6) para crear un registro que no existe.
    public static let cabeceraEmitidas = ["id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento",
                                          "documento", "ambito", "proyecto_id", "estado_revision", "fuente"]
    public static let cabeceraRecibidas = cabeceraEmitidas + ["base", "iva", "retencion", "categoria", "naturaleza"]
    public static let cabeceraPagos = ["id", "fecha", "direccion", "importe", "moneda", "documento_id", "proyecto_id", "tercero",
                                       "metodo", "evidencia", "verificacion"]
    public static let cabeceraMovimientos = ["id", "fecha", "fecha_valor", "concepto", "importe", "saldo", "naturaleza", "categoria",
                                             "proyecto_id", "documento_id", "pago_id", "estado_conciliacion", "motivo",
                                             "import_hash", "lote", "verificacion"]

    public init(snapshot: VaultSnapshot) {
        self.snapshot = snapshot
        let layout = snapshot.layout
        let fin = layout.areaFolder(.finanzas)
        carpeta = snapshot.existing(fin) ?? fin
        var avisos: [String] = []
        var cuentas = Self.leerCuentas(snapshot, avisos: &avisos)
        // Dos fichas con el mismo id darían las mismas huellas: ninguna de las dos se usa hasta que se corrija.
        let repetidos = Dictionary(grouping: cuentas, by: \.id).filter { $0.value.count > 1 }
        for (id, cs) in repetidos.sorted(by: { $0.key < $1.key }) {
            avisos.append("Las cuentas " + Plural.lista(cs.map { "«\($0.carpeta.name)»" }) + " tienen el mismo identificador (\(id)): cambia uno antes de importar.")
        }
        cuentas.removeAll { repetidos[$0.id] != nil }
        self.cuentas = cuentas
        var movs: [MovimientoBanco] = []
        for c in cuentas {
            movs += Self.leerMovimientos(snapshot, cuenta: c, avisos: &avisos)
        }
        movimientos = movs.sorted { ($0.fecha, $0.cuentaID, $0.orden) < ($1.fecha, $1.cuentaID, $1.orden) }
        let registros = carpeta.appending("Registros")
        emitidas = Self.leerFacturas(snapshot, ruta: registros.appending("emitidas.csv"), tipo: .emitida, finanzas: carpeta, avisos: &avisos)
        recibidas = Self.leerFacturas(snapshot, ruta: registros.appending("recibidas.csv"), tipo: .recibida, finanzas: carpeta, avisos: &avisos)
        pagos = Self.leerPagos(snapshot, ruta: registros.appending("pagos.csv"), avisos: &avisos)
        self.avisos = avisos
    }

    // MARK: Consultas

    public func cuenta(id: String) -> CuentaBancaria? { cuentas.first { $0.id == id } }

    public func movimientos(de cuenta: CuentaBancaria) -> [MovimientoBanco] {
        movimientos.filter { $0.cuentaID == cuenta.id }
    }

    public func factura(id: String) -> FacturaRegistro? {
        emitidas.first { $0.id == id } ?? recibidas.first { $0.id == id }
    }

    /// Lo cobrado o pagado de una factura con pagos confirmados por una persona. Una emitida se cobra y una
    /// recibida se paga; si el total es negativo (rectificativa, abono), al revés.
    public func confirmado(de f: FacturaRegistro) -> Int {
        let normal: PagoRegistro.Direccion = f.tipo == .emitida ? .cobro : .pago
        let dir: PagoRegistro.Direccion = (f.total ?? 0) >= 0 ? normal : (normal == .cobro ? .pago : .cobro)
        return pagos.filter { $0.confirmado && $0.documentoID == f.id && ($0.direccion ?? dir) == dir }
            .compactMap(\.importe).reduce(0, +)
    }

    /// Lo que queda: total − pagos confirmados. `nil` si no se sabe el total.
    public func pendiente(de f: FacturaRegistro) -> Int? {
        guard let total = f.total else { return nil }
        // Los pagos van en positivo; una rectificativa (total negativo) se devuelve en positivo.
        return total >= 0 ? total - confirmado(de: f) : total + confirmado(de: f)
    }

    /// Ruta como la escribe `pagos.csv` en `evidencia` (relativa a la carpeta de Finanzas).
    public func rutaRelativa(_ p: VaultPath) -> String {
        p.isDescendant(of: carpeta) ? String(p.raw.dropFirst(carpeta.raw.count + 1)) : p.raw
    }

    /// Ruta de un documento escrito en un registro (`Fiscal/2026/T3/…`, relativo a Finanzas o a la raíz).
    public static func resolverDocumento(_ texto: String, finanzas: VaultPath, snapshot: VaultSnapshot) -> VaultPath? {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("/"), !t.contains("..") else { return nil }
        let sinAncla = t.split(separator: "#", maxSplits: 1).first.map(String.init) ?? t
        return snapshot.existing(finanzas.appending(sinAncla)) ?? snapshot.existing(VaultPath(sinAncla))
    }

    // MARK: Lectura

    static func visible(_ p: VaultPath, _ snapshot: VaultSnapshot) -> Bool {
        !snapshot.layout.isPrivate(p) && !snapshot.layout.isArchived(p)
    }

    static func leerCuentas(_ snapshot: VaultSnapshot, avisos: inout [String]) -> [CuentaBancaria] {
        let layout = snapshot.layout
        guard let bancos = layout.dir(for: "account").flatMap({ snapshot.existing($0) }), visible(bancos, snapshot) else { return [] }
        var out: [CuentaBancaria] = []
        let carpetas = snapshot.directories.filter { $0.parent == bancos && visible($0, snapshot) }
        for dir in carpetas {
            let notas = snapshot.notes.filter { $0.parent == dir }
            let ficha = notas.first { snapshot.frontmatter($0).text("tls_type") == "account" }
                ?? notas.first { TextFolding.nameKey($0.stem) == "cuenta" }
            guard let ficha, let texto = snapshot.text(ficha) else {
                if snapshot.existing(dir.appending("movimientos.csv")) != nil {
                    avisos.append("La cuenta «\(dir.name)» no tiene ficha (Cuenta.md): no puedo leer su saldo ni importar extractos.")
                }
                continue
            }
            let fm = NoteDocument(text: texto).frontmatter
            guard let id = fm.text("id"), !id.contains("{{") else {
                avisos.append("La ficha «\(ficha.raw)» no tiene identificador: no puedo importar extractos en esa cuenta.")
                continue
            }
            let saldo = fm.text("saldo_inicial").flatMap(DineroExacto.centimos)
            out.append(CuentaBancaria(
                id: id, ficha: ficha, carpeta: dir, nombre: fm.text("name") ?? dir.name,
                ibanUltimos4: fm.text("iban_ultimos4"), moneda: fm.text("moneda") ?? "EUR",
                saldoInicial: saldo, fechaSaldoInicial: fm.text("fecha_saldo_inicial").flatMap { LocalDate(parsing: $0) },
                formato: FormatoExtracto.leer(deFicha: texto)))
        }
        return out.sorted { $0.carpeta < $1.carpeta }
    }

    /// Filas de un CSV como diccionarios con las claves en minúsculas y sin espacios.
    static func filas(_ snapshot: VaultSnapshot, _ ruta: VaultPath) -> [[String: String]]? {
        guard let real = snapshot.existing(ruta), visible(real, snapshot), let texto = snapshot.text(real) else { return nil }
        let tabla = CSVTable.parse(texto)
        let cab = tabla.header.map { $0.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping.lowercased() }
        return tabla.rows.map { r in
            var d: [String: String] = [:]
            for (i, h) in cab.enumerated() where d[h] == nil {
                d[h] = i < r.count ? r[i].trimmingCharacters(in: .whitespaces) : ""
            }
            return d
        }
    }

    static func texto(_ d: [String: String], _ k: String) -> String? {
        guard let v = d[k], !v.isEmpty else { return nil }
        return v
    }

    static func leerMovimientos(_ snapshot: VaultSnapshot, cuenta: CuentaBancaria, avisos: inout [String]) -> [MovimientoBanco] {
        guard let filas = filas(snapshot, cuenta.movimientosCSV) else { return [] }
        var out: [MovimientoBanco] = []
        for (i, d) in filas.enumerated() {
            guard let id = texto(d, "id"), let fecha = texto(d, "fecha").flatMap({ LocalDate(parsing: $0) }),
                  let importe = texto(d, "importe").flatMap(DineroExacto.centimos) else {
                avisos.append("Fila \(i + 2) de «\(cuenta.movimientosCSV.raw)»: le falta el identificador, la fecha o el importe.")
                continue
            }
            out.append(MovimientoBanco(
                id: id, cuentaID: cuenta.id, fecha: fecha, fechaValor: texto(d, "fecha_valor").flatMap { LocalDate(parsing: $0) },
                concepto: d["concepto"] ?? "", importe: importe, saldo: texto(d, "saldo").flatMap(DineroExacto.centimos),
                naturaleza: texto(d, "naturaleza"), categoria: texto(d, "categoria"), proyectoID: texto(d, "proyecto_id"),
                documentoID: texto(d, "documento_id"), pagoID: texto(d, "pago_id"),
                estado: EstadoConciliacion(leyendo: d["estado_conciliacion"]), motivo: texto(d, "motivo"),
                importHash: texto(d, "import_hash"), lote: texto(d, "lote"), orden: i))
        }
        return out
    }

    /// Columnas de los registros de facturas de antes (G3) que equivalen a las de la v2, por orden de preferencia. Se
    /// leen si falta la de la v2 y, al cargar movimientos heredados en un registro de antes, se escribe en ellas.
    public static let columnasDeAntes: [String: [String]] = [
        "fecha_documento": ["fecha", "fecha_factura"],
        "tercero": ["cliente", "proveedor"],
        "total_documento": ["importe", "total"],
        "numero_documento": ["numero", "numero_factura"],
    ]

    static func leerFacturas(_ snapshot: VaultSnapshot, ruta: VaultPath, tipo: FacturaRegistro.Tipo, finanzas: VaultPath,
                             avisos: inout [String]) -> [FacturaRegistro] {
        guard let filas = filas(snapshot, ruta) else { return [] }
        var out: [FacturaRegistro] = []
        for (i, d) in filas.enumerated() {
            guard let id = texto(d, "id") else {
                avisos.append("Fila \(i + 2) de «\(ruta.raw)»: no tiene identificador.")
                continue
            }
            let documento = texto(d, "documento")
            var ruta: VaultPath?
            var privado = false
            if let documento, let r = resolverDocumento(documento, finanzas: finanzas, snapshot: snapshot) {
                if snapshot.layout.isPrivate(r) { privado = true } else { ruta = r }
            } else if let documento, snapshot.layout.isPrivate(finanzas.appending(documento)) {
                privado = true
            }
            // La ficha de la factura (si es una nota) completa base, IVA, retención y vencimiento.
            let fm = ruta.flatMap { $0.ext == "md" ? snapshot.frontmatter($0) : nil } ?? .empty
            func cent(_ col: String, _ prop: String) -> Int? {
                texto(d, col).flatMap(DineroExacto.centimos) ?? fm.text(prop).flatMap(DineroExacto.centimos)
            }
            // Las columnas de antes (G3: `fecha`, `cliente`/`proveedor`, `importe`) se leen como las de la v2.
            func columna(_ k: String) -> String? { texto(d, k) ?? columnasDeAntes[k]?.lazy.compactMap { texto(d, $0) }.first }
            out.append(FacturaRegistro(
                id: id, tipo: tipo, fecha: columna("fecha_documento").flatMap { LocalDate(parsing: $0) },
                tercero: columna("tercero"), numero: columna("numero_documento"), moneda: texto(d, "moneda"),
                total: columna("total_documento").flatMap(DineroExacto.centimos) ?? fm.text("total").flatMap(DineroExacto.centimos),
                documento: privado ? nil : documento, rutaDocumento: ruta, documentoPrivado: privado,
                proyectoID: texto(d, "proyecto_id"), estadoRevision: texto(d, "estado_revision"), fuente: texto(d, "fuente"),
                base: cent("base", "base"), iva: cent("iva", "cuota_iva"), retencion: cent("retencion", "retencion"),
                categoria: texto(d, "categoria") ?? fm.text("categoria"), naturaleza: texto(d, "naturaleza"),
                tipoFiscal: texto(d, "tipo_fiscal"), vence: fm.text("vence").flatMap { LocalDate(parsing: $0) },
                oportunidad: fm.text("oportunidad")))
        }
        return out
    }

    static func leerPagos(_ snapshot: VaultSnapshot, ruta: VaultPath, avisos: inout [String]) -> [PagoRegistro] {
        guard let filas = filas(snapshot, ruta) else { return [] }
        var out: [PagoRegistro] = []
        for (i, d) in filas.enumerated() {
            guard let id = texto(d, "id") else {
                avisos.append("Fila \(i + 2) de «\(ruta.raw)»: no tiene identificador.")
                continue
            }
            out.append(PagoRegistro(
                id: id, fecha: texto(d, "fecha").flatMap { LocalDate(parsing: $0) },
                direccion: texto(d, "direccion").flatMap { PagoRegistro.Direccion(rawValue: TextFolding.fold($0)) },
                importe: texto(d, "importe").flatMap(DineroExacto.centimos).map(abs), moneda: texto(d, "moneda"),
                documentoID: texto(d, "documento_id"), proyectoID: texto(d, "proyecto_id"), tercero: texto(d, "tercero"),
                metodo: texto(d, "metodo"), evidencia: texto(d, "evidencia"), verificacion: texto(d, "verificacion")))
        }
        return out
    }
}
