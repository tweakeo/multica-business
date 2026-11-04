import Foundation

/// Una fila del extracto con su huella y si ya estaba importada.
public struct FilaConHuella: Sendable, Hashable, Identifiable {
    public var id: String { movimientoID }
    public let fila: FilaExtracto
    /// `import_hash` (SHA-256 en hexadecimal).
    public let huella: String
    /// `MOV-<huella[0..11]>`.
    public let movimientoID: String
    public let yaImportada: Bool
    /// Fila repetida dentro del mismo extracto (con saldo): no se escribe dos veces.
    public let repetidaEnElFichero: Bool

    public var nueva: Bool { !yaImportada && !repetidaEnElFichero }
}

/// Lo que va a pasar al importar un extracto, antes de escribir nada.
public struct VistaPreviaExtracto: Sendable {
    public let cuenta: CuentaBancaria
    public let extracto: ExtractoLeido
    public let filas: [FilaConHuella]
    /// Donde se guarda el original: `<cuenta>/Extractos/AAAA-MM-DD <nombre>.csv`.
    public let original: VaultPath
    /// El original ya está guardado con esos mismos bytes (no se vuelve a guardar).
    public let originalYaGuardado: Bool
    /// `lote` de cada movimiento nuevo: el nombre del fichero guardado.
    public let lote: String
    /// Se guardará en `Cuenta.md` el formato adivinado (la cuenta no tenía).
    public let guardaFormato: Bool
    let datos: Data
    let fecha: LocalDate
    /// Texto de `movimientos.csv` en la foto (`nil` si aún no existe).
    let textoMovimientos: String?

    public var nuevas: [FilaConHuella] { filas.filter(\.nueva) }
    public var yaImportadas: [FilaConHuella] { filas.filter { !$0.nueva } }

    /// «34 movimientos · 12 nuevos · 22 ya importados».
    public var resumen: String {
        Plural.de(filas.count, "movimiento", "movimientos") + " · " + Plural.de(nuevas.count, "nuevo", "nuevos")
            + " · " + Plural.de(yaImportadas.count, "ya importado", "ya importados")
    }

    /// Escribir el original, los movimientos nuevos (y el formato de la cuenta si hacía falta): todo o nada,
    /// con un solo Deshacer. `nil` si no hay nada nuevo («0 nuevos»: no se escribe nada).
    public func plan(autor: Autor) -> WritePlan? {
        let nuevas = self.nuevas
        guard !nuevas.isEmpty else { return nil }
        var ops: [WriteOp] = []
        if !originalYaGuardado { ops.append(.create(original, contents: datos)) }
        let filasCSV = nuevas.map(fila)
        if let textoMovimientos {
            ops += CSVEscritura.filasNuevas(filasCSV, en: cuenta.movimientosCSV, texto: textoMovimientos)
        } else {
            ops.append(CommandBus.Comando.crear(cuenta.movimientosCSV,
                                                texto: CSVEscritura.texto(cabecera: RegistrosFinanzas.cabeceraMovimientos, filas: filasCSV)).op)
        }
        if guardaFormato {
            ops.append(CommandBus.Comando.cambiarPropiedades(cuenta.ficha, poner: [extracto.formato.propiedad], quitar: []).op)
        }
        return WritePlan(autor: autor, descripcion: "Importar el extracto «\(lote)» (" + Plural.de(nuevas.count, "movimiento nuevo", "movimientos nuevos") + ")",
                         ops: ops)
    }

    /// `extracto.importado` (solo si hay algo nuevo).
    public func evento(autor: Autor) -> EventoFinanzas? {
        guard !nuevas.isEmpty else { return nil }
        // La misma clave que da el dominio al ver el fichero nuevo en `Extractos/` (`EventDeriver`): entregarlo dos
        // veces no lo procesa dos veces.
        return EventoFinanzas(tipo: .extractoImportado, clave: "extracto.importado:ruta:" + TextFolding.pathKey(original.raw), fecha: fecha,
                              autor: autor.etiqueta,
                              datos: ["cuenta_id": cuenta.id, "cuenta": cuenta.carpeta.raw, "lote": lote,
                                      "nuevos": String(nuevas.count), "ya_importados": String(yaImportadas.count)])
    }

    /// Fila nueva de `movimientos.csv`. La naturaleza sale solo del signo; clasificar es del Contable (F4).
    func fila(_ f: FilaConHuella) -> [String: String] {
        let x = f.fila
        return [
            "id": f.movimientoID,
            "fecha": x.fecha.description,
            "fecha_valor": x.fechaValor?.description ?? "",
            "concepto": x.concepto,
            "importe": DineroExacto.csv(x.importe),
            "saldo": x.saldo.map(DineroExacto.csv) ?? "",
            "naturaleza": x.importe >= 0 ? "ingreso" : "gasto",
            "estado_conciliacion": EstadoConciliacion.pendiente.rawValue,
            "import_hash": f.huella,
            "lote": lote,
        ]
    }
}

public enum ErrorImportacion: Error, LocalizedError, Sendable, Equatable {
    case sinCuenta
    case extracto(ErrorExtracto)

    public var errorDescription: String? {
        switch self {
        case .sinCuenta: "Esa cuenta no tiene ficha (Cuenta.md con su identificador). Crea la cuenta antes de importar."
        case .extracto(let e): e.errorDescription
        }
    }
}

/// Importa extractos del banco sin duplicar (PLAN §4.6, §7.3).
///
/// La huella de cada movimiento es un **contrato**:
/// `import_hash = SHA-256("<cuenta_id>|<AAAA-MM-DD>|<importe en céntimos>|<concepto en minúsculas>|<saldo en céntimos o vacío>")`,
/// con `|#n` detrás para la n-ésima fila idéntica sin saldo del mismo extracto (la primera no lleva nada; la segunda, `|#2`).
/// `id = MOV-<import_hash[0..11]>`. Reproduce los 30 movimientos de Asesoría Ribera.
public struct ImportadorExtracto: Sendable {
    public let registros: RegistrosFinanzas
    public let reloj: Reloj

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.registros = RegistrosFinanzas(snapshot: snapshot)
        self.reloj = reloj ?? Reloj.deCarpeta(snapshot)
    }

    /// Texto del que sale la huella (sin el `|#n`).
    public static func textoHuella(cuentaID: String, fecha: LocalDate, importe: Int, concepto: String, saldo: Int?) -> String {
        let c = concepto.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
        return "\(cuentaID)|\(fecha.description)|\(importe)|\(c)|\(saldo.map(String.init) ?? "")"
    }

    /// `import_hash`. `repeticion` = 1 para la primera fila idéntica, 2 para la segunda…
    public static func huella(cuentaID: String, fecha: LocalDate, importe: Int, concepto: String, saldo: Int?,
                              repeticion: Int = 1) -> String {
        let base = textoHuella(cuentaID: cuentaID, fecha: fecha, importe: importe, concepto: concepto, saldo: saldo)
        return ContentHash.of(repeticion > 1 ? base + "|#\(repeticion)" : base)
    }

    public static func movimientoID(huella: String) -> String { "MOV-" + huella.prefix(12) }

    /// Huellas de todas las filas de un extracto, en orden, con el `|#n` de las repetidas sin saldo.
    public static func huellas(cuentaID: String, filas: [FilaExtracto]) -> [(huella: String, repetidaConSaldo: Bool)] {
        var vistas: [String: Int] = [:]
        return filas.map { f in
            let base = textoHuella(cuentaID: cuentaID, fecha: f.fecha, importe: f.importe, concepto: f.concepto, saldo: f.saldo)
            let n = (vistas[base] ?? 0) + 1
            vistas[base] = n
            if f.saldo == nil {
                return (huella(cuentaID: cuentaID, fecha: f.fecha, importe: f.importe, concepto: f.concepto, saldo: nil, repeticion: n), false)
            }
            return (ContentHash.of(base), n > 1)
        }
    }

    /// Lee el extracto y dice qué hay de nuevo. No escribe nada.
    /// - `nombre`: nombre del fichero que soltó la persona (`cuenta-corriente-2026-07-a-10.csv`).
    /// - `adivinarFormato`: leerlo sin el formato de la cuenta (el banco lo cambió); el adivinado se guarda en la ficha.
    public func vistaPrevia(_ datos: Data, nombre: String, cuenta: CuentaBancaria,
                            adivinarFormato: Bool = false) throws -> VistaPreviaExtracto {
        guard registros.cuentas.contains(where: { $0.id == cuenta.id && $0.ficha == cuenta.ficha }) else { throw ErrorImportacion.sinCuenta }
        let extracto: ExtractoLeido
        do { extracto = try BankStatementParser.leer(datos, formato: adivinarFormato ? nil : cuenta.formato) } catch let e as ErrorExtracto {
            throw ErrorImportacion.extracto(e)
        }
        guard !extracto.filas.isEmpty else { throw ErrorImportacion.extracto(.vacio) }
        let existentes = huellasImportadas(cuenta)
        let calculadas = Self.huellas(cuentaID: cuenta.id, filas: extracto.filas)
        var filas: [FilaConHuella] = []
        for (f, h) in zip(extracto.filas, calculadas) {
            let id = Self.movimientoID(huella: h.huella)
            filas.append(FilaConHuella(fila: f, huella: h.huella, movimientoID: id,
                                       yaImportada: existentes.huellas.contains(h.huella) || existentes.ids.contains(id),
                                       repetidaEnElFichero: h.repetidaConSaldo))
        }
        let (original, yaGuardado) = destino(datos, nombre: nombre, cuenta: cuenta)
        let snapshot = registros.snapshot
        let texto = snapshot.existing(cuenta.movimientosCSV).flatMap { snapshot.text($0) }
        return VistaPreviaExtracto(cuenta: cuenta, extracto: extracto, filas: filas, original: original,
                                   originalYaGuardado: yaGuardado, lote: original.name,
                                   guardaFormato: cuenta.formato == nil || (adivinarFormato && cuenta.formato != extracto.formato),
                                   datos: datos, fecha: reloj.hoy,
                                   textoMovimientos: texto)
    }

    /// Huellas e ids ya escritos en `movimientos.csv` de la cuenta.
    func huellasImportadas(_ cuenta: CuentaBancaria) -> (huellas: Set<String>, ids: Set<String>) {
        let movs = registros.movimientos(de: cuenta)
        return (Set(movs.compactMap(\.importHash).map { $0.lowercased() }), Set(movs.map(\.id)))
    }

    /// `Extractos/AAAA-MM-DD <nombre>.csv`; si ya hay uno con ese nombre y otros bytes, « (2)», « (3)»…
    func destino(_ datos: Data, nombre: String, cuenta: CuentaBancaria) -> (VaultPath, Bool) {
        let snapshot = registros.snapshot
        let base = "\(reloj.hoy.description) \(Self.nombreLimpio(nombre))"
        var n = 1
        while true {
            let candidato = cuenta.extractos.appending(n == 1 ? base + ".csv" : base + " (\(n)).csv")
            guard let real = snapshot.existing(candidato) else { return (candidato, false) }
            let actual = snapshot.data(real) ?? (try? Data(contentsOf: real.url(in: snapshot.root)))
            if actual == datos { return (real, true) }
            n += 1
        }
    }

    /// Nombre del fichero sin extensión ni caracteres que rompen enlaces (`/ : \ # ^ [ ] |`).
    static func nombreLimpio(_ nombre: String) -> String {
        var stem = (nombre as NSString).lastPathComponent
        if stem.lowercased().hasSuffix(".csv") || stem.lowercased().hasSuffix(".txt") { stem = String(stem.dropLast(4)) }
        let prohibidos = Set<Character>(["/", ":", "\\", "#", "^", "[", "]", "|"])
        let limpio = String(stem.map { prohibidos.contains($0) ? " " : $0 })
            .split(whereSeparator: { $0 == " " }).joined(separator: " ")
            .precomposedStringWithCanonicalMapping
        let sinPunto = limpio.hasPrefix(".") ? String(limpio.drop(while: { $0 == "." })) : limpio
        return sinPunto.isEmpty ? "extracto" : String(sinPunto.prefix(80))
    }
}

/// Escribir campos de CSV con coma (como los registros).
enum CSVEscritura {
    static func campo(_ v: String, separador: Character = ",") -> String {
        let necesita = v.contains(separador) || v.contains("\"") || v.contains(where: { $0.isNewline })
        return necesita ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }

    /// Campo de un CSV con `;` (paquete para la gestoría).
    static func campoPuntoYComa(_ v: String) -> String { campo(v, separador: ";") }

    /// Filas nuevas al final de un CSV que ya existe (`texto`, el de la foto): una sola `insertCSVRows` con todas, en
    /// el separador y el orden de columnas del fichero (se lee una vez, también con un extracto de un año). **Nunca
    /// pisa ni repite**: si alguna ya está escrita (otra ventana, un doble clic, una vista previa vieja), el plan
    /// entero no se escribe (`WriteError.filaYaExiste`). Las columnas que el fichero no tiene no se escriben.
    static func filasNuevas(_ filas: [[String: String]], en ruta: VaultPath, texto: String) -> [WriteOp] {
        guard !filas.isEmpty else { return [] }
        let doc = CSVDocument(text: texto)
        let conocidas = Set(doc.header.map { $0.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping.lowercased() })
        let limpias = filas.map { f in
            f.filter { conocidas.contains($0.key.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping.lowercased()) }
        }
        return [.insertCSVRows(ruta, rows: limpias, key: "id")]
    }

    /// Texto de un CSV nuevo: cabecera y filas.
    static func texto(cabecera: [String], filas: [[String: String]]) -> String {
        let filasTexto: [[String]] = [cabecera] + filas.map { f in cabecera.map { f[$0] ?? "" } }
        let lineas: [String] = filasTexto.map { campos in campos.map { campo($0) }.joined(separator: ",") }
        return lineas.joined(separator: "\n") + "\n"
    }
}
