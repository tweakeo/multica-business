import Foundation

/// Una propuesta de conciliación: este movimiento del banco paga (o cobra) esta factura.
public struct PropuestaConciliacion: Sendable, Hashable, Identifiable {
    /// Por qué se propone.
    public enum Coincidencia: String, Sendable, Hashable {
        /// Importe exacto y el número de la factura en el concepto (la más fuerte).
        case numeroFactura
        /// Importe exacto y la primera palabra de la contraparte en el concepto.
        case contraparte
    }

    public var id: String { movimiento.id }
    public let movimiento: MovimientoBanco
    public let cuenta: CuentaBancaria
    public let factura: FacturaRegistro
    /// Lo que quedaba por cobrar o pagar (céntimos, igual al importe del movimiento sin signo).
    public let pendiente: Int
    public let coincidencia: Coincidencia
    /// Días entre la factura y el movimiento (negativo: el movimiento es anterior a la factura, hasta 3).
    public let dias: Int
    /// Otras facturas igual de probables para este movimiento, o movimientos para esta factura.
    public let empates: Int
    /// En castellano, para la persona («Importe exacto y número de factura en el concepto»).
    public let motivo: String

    /// Sin empates: entra en «Confirmar las exactas». Las demás se revisan una a una.
    public var exacta: Bool { empates == 0 }
}

/// Propone conciliaciones de forma determinista (PLAN §4.6, especificación propia):
/// - importe exacto contra lo pendiente (total − pagos confirmados);
/// - el número de factura en el concepto (más peso) o la primera palabra de la contraparte;
/// - fecha del movimiento mayor o igual que la de la factura menos 3 días; gana la más próxima;
/// - una factura por movimiento (y un movimiento por factura).
///
/// Solo propone: no escribe. Confirmar es siempre de una persona (`Conciliador`).
public struct ConciliationMatcher: Sendable {
    public let registros: RegistrosFinanzas
    /// Días que el movimiento puede ir por delante de la factura.
    public static let margenDias = 3

    public static let motivoNumero = "Importe exacto y número de factura en el concepto"
    public static let motivoContraparte = "Importe exacto, contraparte coincidente y fecha más próxima"

    public init(registros: RegistrosFinanzas) {
        self.registros = registros
    }

    struct Candidato {
        let mov: MovimientoBanco
        let factura: FacturaRegistro
        let pendiente: Int
        let coincidencia: PropuestaConciliacion.Coincidencia
        let dias: Int
        var rango: (Int, Int) { (coincidencia == .numeroFactura ? 0 : 1, abs(dias)) }
    }

    /// Movimientos que se pueden conciliar: ni conciliados ni ignorados, sin pago enlazado.
    public var movimientosAbiertos: [MovimientoBanco] {
        registros.movimientos.filter { $0.estado.abierto && $0.pagoID == nil }
    }

    public func proponer() -> [PropuestaConciliacion] {
        let facturas = (registros.emitidas + registros.recibidas).compactMap { f -> (FacturaRegistro, Int)? in
            guard let p = registros.pendiente(de: f), p != 0, f.fecha != nil else { return nil }
            return (f, p)
        }
        var candidatos: [Candidato] = []
        for mov in movimientosAbiertos where mov.importe != 0 {
            let concepto = Self.palabras(mov.concepto)
            for (f, pendiente) in facturas {
                // El banco da el signo: entra dinero por una emitida y sale por una recibida (al revés si es un abono).
                let esperado = f.tipo == .emitida ? pendiente : -pendiente
                guard mov.importe == esperado, let fecha = f.fecha else { continue }
                let dias = Self.dias(de: fecha, a: mov.fecha)
                guard dias >= -Self.margenDias else { continue }
                let coincidencia: PropuestaConciliacion.Coincidencia
                if Self.contieneNumero(concepto, f.numero) || Self.contieneNumero(concepto, f.id) {
                    coincidencia = .numeroFactura
                } else if let palabra = Self.primeraPalabra(f.tercero), concepto.contains(palabra) {
                    coincidencia = .contraparte
                } else { continue }
                candidatos.append(Candidato(mov: mov, factura: f, pendiente: abs(pendiente), coincidencia: coincidencia, dias: dias))
            }
        }
        // El mejor rango primero; a igualdad, por fecha del movimiento, cuenta e id (siempre el mismo orden).
        candidatos.sort { a, b in
            if a.rango != b.rango { return a.rango < b.rango }
            if a.mov.fecha != b.mov.fecha { return a.mov.fecha < b.mov.fecha }
            if a.mov.id != b.mov.id { return a.mov.id < b.mov.id }
            return a.factura.id < b.factura.id
        }
        var usadosMov = Set<String>(), usadasFact = Set<String>()
        var out: [PropuestaConciliacion] = []
        for c in candidatos where !usadosMov.contains(c.mov.id) && !usadasFact.contains(c.factura.id) {
            // Empates: otra factura libre con el mismo rango para este movimiento, u otro movimiento libre para
            // esta factura (lo que ya se llevó una propuesta mejor no compite).
            let empates = candidatos.filter { o in
                guard o.rango == c.rango else { return false }
                if o.mov.id == c.mov.id, o.factura.id != c.factura.id { return !usadasFact.contains(o.factura.id) }
                if o.factura.id == c.factura.id, o.mov.id != c.mov.id { return !usadosMov.contains(o.mov.id) }
                return false
            }.count
            usadosMov.insert(c.mov.id)
            usadasFact.insert(c.factura.id)
            var motivo = c.coincidencia == .numeroFactura ? Self.motivoNumero : Self.motivoContraparte
            if empates > 0 { motivo += ". Hay otra opción igual de probable: revísala antes de confirmar" }
            guard let cuenta = registros.cuenta(id: c.mov.cuentaID) else { continue }
            out.append(PropuestaConciliacion(movimiento: c.mov, cuenta: cuenta, factura: c.factura, pendiente: c.pendiente,
                                             coincidencia: c.coincidencia, dias: c.dias, empates: empates, motivo: motivo))
        }
        return out.sorted { ($0.movimiento.fecha, $0.movimiento.id) < ($1.movimiento.fecha, $1.movimiento.id) }
    }

    // MARK: Comparar textos

    /// Palabras del concepto, plegadas (sin tildes, en minúsculas) y solo con letras y números. El guion y el
    /// punto no separan (son parte de los números de factura); los espacios, «/», «,», «;», «:» y paréntesis, sí.
    static func palabras(_ texto: String) -> [String] {
        TextFolding.fold(texto).split(whereSeparator: { $0.isWhitespace || "/,;:()".contains($0) }).map { w in
            String(w.filter { $0.isLetter || $0.isNumber })
        }.filter { !$0.isEmpty }
    }

    static let palabrasVacias: Set<String> = ["el", "la", "los", "las", "de", "del", "y", "e", "sl", "sa", "slp", "slu", "sll",
                                              "cb", "scp", "sc", "the", "and", "don", "dona"]

    /// Primera palabra con significado de la contraparte («Talleres Martín e Hijos SL» → «talleres»).
    static func primeraPalabra(_ tercero: String?) -> String? {
        guard let tercero else { return nil }
        return palabras(tercero).first { $0.count >= 3 && !palabrasVacias.contains($0) }
    }

    /// El número de factura está en el concepto como palabra (sin separadores: «F-2026-0004» = «f20260004»),
    /// o al final de una palabra pegada a otras letras («FRAF-2026-0004»), sin más cifras alrededor.
    static func contieneNumero(_ concepto: [String], _ numero: String?) -> Bool {
        guard let numero else { return false }
        let n = palabras(numero).joined()
        guard n.count >= 3, n.contains(where: { $0.isNumber }) else { return false }
        for w in concepto {
            if w == n { return true }
            if w.hasSuffix(n), let antes = w.dropLast(n.count).last, !(antes.isNumber && n.first!.isNumber) { return true }
            if w.hasPrefix(n), let despues = w.dropFirst(n.count).first, !(despues.isNumber && n.last!.isNumber) { return true }
        }
        return false
    }

    /// Días de calendario de `a` a `b` (sin horarios de verano por medio).
    static func dias(de a: LocalDate, a b: LocalDate) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return cal.dateComponents([.day], from: a.date(timeZone: .gmt), to: b.date(timeZone: .gmt)).day ?? 0
    }
}
