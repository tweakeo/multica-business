import Foundation

/// Por qué no se puede escribir lo que se ha tecleado en una celda.
public enum EdicionError: Error, LocalizedError, Sendable, Equatable {
    case noEsCifra(String)
    case noEsFecha(String)
    case fueraDeRango(String)
    case demasiadoGrande(String)
    case opcionDesconocida(String, [String])
    case soloLectura(String)

    public var errorDescription: String? {
        switch self {
        case .noEsCifra(let t): "«\(t)» no es una cifra. Escribe, por ejemplo, 150 o 150,50."
        case .noEsFecha(let t): "«\(t)» no es una fecha. Escribe, por ejemplo, 24/10/2026, hoy o mañana."
        case .fueraDeRango(let t): "«\(t)» tiene que estar entre 0 y 100."
        case .demasiadoGrande(let t): "«\(t)» es una cifra demasiado grande."
        case .opcionDesconocida(let t, let ops): "«\(t)» no es una opción. Elige entre: \(ops.joined(separator: ", "))."
        case .soloLectura(let motivo): motivo
        }
    }
}

/// Edición en la celda (§4.7, criterio §11.5): **una celda escribe solo su clave** en la ficha, o solo su fila
/// en un CSV, sin reformatear nada. Aquí se decide qué se puede tocar, se valida lo escrito y se prepara la
/// orden para `CommandBus` (la escribe la interfaz con `sesion.escribir`).
public enum EdicionCelda {
    /// Por qué no se edita esa celda desde la base (`nil` = se puede). Va en gris con este motivo.
    public static func motivoSoloLectura(_ f: FilaBase, _ col: ColumnaBase, coleccion c: ColeccionBase) -> String? {
        switch col.tipo {
        case .calculada:
            return (col.explicacion.map { "Se calcula: " + $0.prefix(1).lowercased() + $0.dropFirst() } ?? "Se calcula; no se escribe.")
        case .titulo:
            return "El nombre se cambia en su ficha: allí cambian a la vez el título y el nombre del fichero."
        default: break
        }
        if col.clave == ColumnaBase.claveArea {
            return "El área sale de la carpeta donde vive. Para cambiarla, mueve la ficha a otra área."
        }
        if case .filaCSV(_, let clave, _) = f.origen {
            guard let real = f.claveReal(col) else { return "Este registro no tiene esa columna." }
            if real == clave { return "Es la clave de la fila: no se cambia." }
            if f.ruta.name == "movimientos.csv", ["fecha", "fecha_valor", "concepto", "importe", "saldo"].contains(real) {
                return "Lo dice el banco: no se cambia aquí."
            }
            return nil
        }
        if c.id == "facturas" || f.tipo == .invoice {
            // Como en su ficha: emitir y cobrar se hacen con su acción (y el cobro lo confirma una persona en Finanzas
            // › Banco o con su recibo); el estado no se elige a mano en la base ni en su tablero (VEN-07).
            if col.clave == "estado" {
                return "La emisión y el cobro se confirman con su acción, no se eligen a mano."
            }
            let estado = TextFolding.fold(f.texto("estado") ?? "")
            let emitida = !estado.isEmpty && estado != "borrador"
            if emitida, ["numero", "serie", "fecha", "total", "base", "empresa", "iva_pct", "cuota_iva"].contains(col.clave) {
                return col.clave == "numero" ? "El número de una factura emitida no se cambia."
                    : "Una factura emitida no se cambia: se rectifica con otra."
            }
            if !emitida, col.clave == "numero" {
                return "El número lo pone la app al emitir la factura."
            }
        }
        if f.tipo == .task, col.clave == "numero" {
            return "El número de la tarea lo pone la app y no se cambia."
        }
        return nil
    }

    /// Lo escrito en la celda, ya como valor de la propiedad (`nil` = quitar la clave).
    public static func valor(_ texto: String, para col: ColumnaBase, hoy: LocalDate) throws -> PropertyValue? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        switch col.tipo {
        case .dinero:
            let n = try cifra(t)
            return .number(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), n))
        case .porcentaje:
            let n = try cifra(t)
            guard n >= 0, n <= 100 else { throw EdicionError.fueraDeRango(t) }
            return .number(numeroLimpio(n))
        case .numero:
            return .number(numeroLimpio(try cifra(t)))
        case .fecha:
            guard let d = fecha(t, hoy: hoy) else { throw EdicionError.noEsFecha(t) }
            return .text(d.description)
        case .opcion:
            guard !col.opciones.isEmpty else { return .text(t) }
            guard let o = col.opciones.first(where: { TextFolding.fold($0) == TextFolding.fold(t) }) else {
                throw EdicionError.opcionDesconocida(t, col.opciones.map(FormatoBase.opcionVisible))
            }
            return .text(o)
        case .opciones:
            let partes = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let normalizadas = partes.map { p in col.opciones.first { TextFolding.fold($0) == TextFolding.fold(p) } ?? p }
            return .list(normalizadas)
        case .siNo:
            switch TextFolding.fold(t) {
            case "si", "true", "1", "x": return .bool(true)
            case "no", "false", "0": return .bool(false)
            default: throw EdicionError.opcionDesconocida(t, ["Sí", "No"])
            }
        case .texto, .persona, .relacion, .titulo, .calculada:
            return .text(t)
        }
    }

    /// «24/10/2026», «2026-10-24», «hoy», «mañana», «+1 semana».
    public static func fecha(_ t: String, hoy: LocalDate) -> LocalDate? {
        switch TextFolding.fold(t).trimmingCharacters(in: .whitespaces) {
        case "hoy": return hoy
        case "manana": return hoy.adding(days: 1)
        case "ayer": return hoy.adding(days: -1)
        case "+1 semana", "en una semana", "1 semana": return hoy.adding(days: 7)
        default: return LocalDate(parsing: t)
        }
    }

    /// Lo escrito en una celda de cifra: «1.235» es mil doscientos treinta y cinco (el punto de millares que pone
    /// la propia app al enseñarla), y nada desde mil billones (no cabe sin perder cifras ni se puede escribir bien).
    static func cifra(_ t: String) throws -> Double {
        guard let n = FormatoBase.numeroEscrito(t) else { throw EdicionError.noEsCifra(t) }
        guard abs(n) < FormatoBase.cifraMaxima else { throw EdicionError.demasiadoGrande(t) }
        return n
    }

    /// Sin «.0» en los enteros. Nunca convierte a entero lo que no cabe (`Int64(1e20)` cerraba la app).
    static func numeroLimpio(_ n: Double) -> String {
        guard n.isFinite, abs(n) < FormatoBase.cifraMaxima else { return String(n) }
        return n.rounded() == n ? String(Int64(n)) : String(n)
    }

    /// La orden que escribe solo esa clave en la ficha o solo esa fila del CSV.
    public static func comando(_ f: FilaBase, _ col: ColumnaBase, valor: PropertyValue?,
                               coleccion c: ColeccionBase) throws -> CommandBus.Comando {
        if let motivo = motivoSoloLectura(f, col, coleccion: c) { throw EdicionError.soloLectura(motivo) }
        guard let clave = f.claveReal(col) else { throw EdicionError.soloLectura("Este registro no tiene esa columna.") }
        switch f.origen {
        case .ficha(let ruta):
            if let valor { return .cambiarPropiedades(ruta, poner: [Property(key: clave, value: valor)], quitar: []) }
            return .cambiarPropiedades(ruta, poner: [], quitar: [clave])
        case .filaCSV(let ruta, let columnaClave, let valorClave):
            let texto: String = {
                guard let valor else { return "" }
                // Solo un sí/no de verdad se escribe como true/false; «No» escrito en una celda de texto es «No».
                switch valor {
                case .list(let l): return l.joined(separator: ";")
                case .bool(let b): return b ? "true" : "false"
                default: return valor.displayText
                }
            }()
            return .guardarFila(ruta, fila: [columnaClave: valorClave, clave: texto], clave: columnaClave)
        }
    }

    /// Cómo quedará la línea en la ficha («estado: Propuesta»), para enseñarlo antes de guardar.
    public static func lineaPrevista(_ f: FilaBase, _ col: ColumnaBase, valor: PropertyValue?) -> String {
        let clave = f.claveReal(col) ?? col.clave
        if f.esFilaCSV { return "\(clave) = \(valor?.displayText ?? "")" }
        guard let valor else { return "(se quita «\(clave)»)" }
        return "\(clave): \(YAMLScalar.inline(valor) ?? valor.displayText)"
    }

    /// Las opciones de una columna con las que no se pueden elegir desde aquí y su motivo (Ganada).
    public static func opciones(_ col: ColumnaBase, fila f: FilaBase) -> [(valor: String, motivo: String?)] {
        col.opciones.map { o in
            if col.clave == "estado", f.tipo == .opportunity, TextFolding.fold(o) == "ganada",
               let motivo = f.calculados[ReglaGanada.clave].map(\.texto), !motivo.isEmpty {
                return (o, motivo)
            }
            return (o, nil)
        }
    }
}

/// Una oportunidad solo pasa a Ganada con un cobro confirmado por una persona (decisión del 19 oct: no se
/// empieza a trabajar sin haber cobrado). Lo calcula el lector y lo dicen la celda, el tablero y el menú.
public enum ReglaGanada {
    /// Clave interna de `FilaBase.calculados` con el motivo («» = puede pasar a Ganada).
    public static let clave = "_motivoGanada"

    public static let base = "Ganada necesita un cobro confirmado por una persona."

    /// Motivo por el que no puede pasar a Ganada (`nil` = puede).
    public static func motivo(_ f: FilaBase) -> String? {
        guard let t = f.calculados[clave]?.texto, !t.isEmpty else { return nil }
        return t
    }

    /// Calcula el motivo con sus facturas (las que la enlazan), los cobros de `pagos.csv` y los recibos de cada factura.
    /// Como VEN-07 del dominio (`LecturaDominio.tieneCobroConfirmado`): solo cuenta un cobro confirmado por una persona
    /// (su fila de `pagos.csv` o su recibo con `confirmado_por` de una persona). Una factura que solo dice «Cobrada» no
    /// basta (revisión final de F2).
    static func calcular(facturas: [FichaIndexada], confirmados: [String: Double], recibos: [VaultPath: [FichaIndexada]] = [:],
                         pendientes: [String: (Double, String)], contacto: String?) -> String? {
        func numero(_ f: FichaIndexada) -> String? {
            guard let v = f.propiedades["numero"], !v.estaVacio else { return nil }
            return TextFolding.fold(v.displayText)
        }
        func estado(_ f: FichaIndexada) -> String { TextFolding.fold(f.propiedades["estado"]?.displayText ?? "") }
        func reciboDePersona(_ f: FichaIndexada) -> Bool {
            (recibos[f.ruta] ?? []).contains { r in
                guard let quien = r.propiedades["confirmado_por"]?.displayText.trimmingCharacters(in: .whitespaces),
                      !quien.isEmpty else { return false }
                return !quien.lowercased().hasPrefix("agente:")
            }
        }
        if facturas.contains(where: { reciboDePersona($0) || (numero($0).map { (confirmados[$0] ?? 0) > 0 } ?? false) }) {
            return nil
        }
        if let pendiente = facturas.compactMap({ numero($0).flatMap { pendientes[$0] } }).first {
            let quien = contacto.map { " o en la ficha de \($0)" } ?? ""
            return base + " El cobro del \(pendiente.1) está sin confirmar: confírmalo en Decisiones\(quien)."
        }
        if let borrador = facturas.first(where: { estado($0) == "borrador" }) {
            return base + " La factura \(borrador.resumen.title) aún está en borrador."
        }
        if let cobrada = facturas.first(where: { estado($0) == "cobrada" }) {
            return base + " La factura \(cobrada.resumen.title) dice «Cobrada», pero nadie ha confirmado su cobro: confírmalo en Finanzas › Banco."
        }
        if !facturas.isEmpty { return base + " Su factura aún no está cobrada." }
        return base + " Aún no hay ninguna factura cobrada."
    }
}
