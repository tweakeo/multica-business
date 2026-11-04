import Foundation

/// Lo que se va a escribir al confirmar una o varias conciliaciones.
public struct ConfirmacionConciliacion: Sendable {
    /// Todo en un plan: un solo Deshacer.
    public let plan: WritePlan
    /// Filas nuevas de `pagos.csv` (id → fila).
    public let pagos: [(id: String, fila: [String: String])]
    /// `cobro.confirmado` por cada factura emitida cobrada. Se entregan al dominio cuando el plan quede hecho.
    public let eventos: [EventoFinanzas]
    public let propuestas: [PropuestaConciliacion]

    public var resumen: String {
        propuestas.count == 1
            ? Conciliador.descripcion(propuestas[0])
            : "Confirmar " + Plural.de(propuestas.count, "conciliación", "conciliaciones")
    }
}

public enum ErrorConciliacion: Error, LocalizedError, Sendable, Equatable {
    /// Ninguna regla ni asistente confirma un cobro: lo hace una persona con un clic.
    case soloUnaPersona
    case nadaQueConfirmar
    case movimientoNoEncontrado(String)
    case yaConciliado(String)
    case facturaNoEncontrada(String)
    case importeNoCoincide(String)
    case repetida(String)

    public var errorDescription: String? {
        switch self {
        case .soloUnaPersona: "Confirmar un cobro o un pago lo hace siempre una persona. El asistente solo lo propone."
        case .nadaQueConfirmar: "No hay conciliaciones exactas que confirmar."
        case .movimientoNoEncontrado(let m): "No encuentro el movimiento «\(m)». Puede que el extracto haya cambiado."
        case .yaConciliado(let m): "El movimiento «\(m)» ya está conciliado o ignorado."
        case .facturaNoEncontrada(let f): "No encuentro la factura «\(f)» en los registros."
        case .importeNoCoincide(let f): "A la factura «\(f)» ya no le queda pendiente ese importe. Vuelve a mirar las propuestas."
        case .repetida(let x): "«\(x)» aparece en dos conciliaciones a la vez."
        }
    }
}

/// Confirmar conciliaciones (PLAN §4.6): **solo una persona**. Al confirmar:
/// - el movimiento queda `estado_conciliacion = conciliado`, con `documento_id`, `pago_id` y el motivo;
/// - se añade a `pagos.csv` la fila `PAG-AAAAMMDD-NNN` (fecha del movimiento), con
///   `evidencia = Registros/Bancos/<cuenta>/movimientos.csv#MOV-…` y `verificacion = confirmado`;
/// - si es una factura emitida, `cobro.confirmado` (en `ConfirmacionConciliacion.eventos`).
///
/// También: dejar propuestas escritas (`estado_conciliacion = propuesta`, lo puede hacer un asistente) e
/// ignorar un movimiento que no lleva factura (impuestos, nóminas, traspasos), con su motivo.
public struct Conciliador: Sendable {
    public let registros: RegistrosFinanzas
    public let reloj: Reloj

    public init(registros: RegistrosFinanzas, reloj: Reloj? = nil) {
        self.registros = registros
        self.reloj = reloj ?? Reloj.deCarpeta(registros.snapshot)
    }

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.init(registros: RegistrosFinanzas(snapshot: snapshot), reloj: reloj)
    }

    /// Propuestas de ahora (las mismas que `ConciliationMatcher`).
    public var propuestas: [PropuestaConciliacion] { ConciliationMatcher(registros: registros).proponer() }

    /// Confirmar una conciliación.
    public func confirmar(_ p: PropuestaConciliacion, autor: Autor) throws -> ConfirmacionConciliacion {
        try confirmar([p], autor: autor)
    }

    /// «Confirmar las exactas»: todas las propuestas sin empates, en un solo plan.
    public func confirmarLasExactas(autor: Autor) throws -> ConfirmacionConciliacion {
        guard autor.esPersona else { throw ErrorConciliacion.soloUnaPersona }
        let exactas = propuestas.filter(\.exacta)
        guard !exactas.isEmpty else { throw ErrorConciliacion.nadaQueConfirmar }
        return try confirmar(exactas, autor: autor)
    }

    /// Confirmar varias en lote: todo o nada, un solo Deshacer.
    public func confirmar(_ ps: [PropuestaConciliacion], autor: Autor) throws -> ConfirmacionConciliacion {
        guard autor.esPersona else { throw ErrorConciliacion.soloUnaPersona }
        guard !ps.isEmpty else { throw ErrorConciliacion.nadaQueConfirmar }
        var movsVistos = Set<String>(), factVistas = Set<String>()
        var siguiente: [String: Int] = [:]
        var ops: [WriteOp] = []
        var pagos: [(id: String, fila: [String: String])] = []
        var eventos: [EventoFinanzas] = []
        for p in ps {
            // Se comprueba contra los registros de ahora, no contra la propuesta (puede ser vieja).
            guard movsVistos.insert(p.movimiento.id).inserted else { throw ErrorConciliacion.repetida(p.movimiento.id) }
            guard factVistas.insert(p.factura.id).inserted else { throw ErrorConciliacion.repetida(p.factura.id) }
            guard let mov = registros.movimientos.first(where: { $0.id == p.movimiento.id && $0.cuentaID == p.cuenta.id }),
                  let cuenta = registros.cuenta(id: mov.cuentaID) else {
                throw ErrorConciliacion.movimientoNoEncontrado(p.movimiento.id)
            }
            guard mov.estado.abierto, mov.pagoID == nil else { throw ErrorConciliacion.yaConciliado(mov.id) }
            guard let f = registros.factura(id: p.factura.id), f.tipo == p.factura.tipo else {
                throw ErrorConciliacion.facturaNoEncontrada(p.factura.id)
            }
            guard let pendiente = registros.pendiente(de: f), mov.importe == (f.tipo == .emitida ? pendiente : -pendiente) else {
                throw ErrorConciliacion.importeNoCoincide(f.numeroVisible)
            }
            let pagoID = siguienteID(fecha: mov.fecha, ya: &siguiente)
            let evidencia = registros.rutaRelativa(cuenta.movimientosCSV) + "#" + mov.id
            // Cobro si entra dinero; pago si sale (también en las rectificativas).
            let direccion: PagoRegistro.Direccion = mov.importe > 0 ? .cobro : .pago
            let importe = DineroExacto.csv(abs(mov.importe))
            let fila: [String: String] = [
                "id": pagoID, "fecha": mov.fecha.description, "direccion": direccion.rawValue, "importe": importe,
                "moneda": f.moneda ?? cuenta.moneda, "documento_id": f.id, "proyecto_id": f.proyectoID ?? "",
                "tercero": f.tercero ?? "", "metodo": Self.metodo(mov.concepto), "evidencia": evidencia,
                "verificacion": "confirmado",
            ]
            pagos.append((pagoID, fila))
            ops.append(CommandBus.Comando.guardarFila(cuenta.movimientosCSV, fila: [
                "id": mov.id, "estado_conciliacion": EstadoConciliacion.conciliado.rawValue, "documento_id": f.id,
                "pago_id": pagoID, "motivo": p.motivo,
            ].filter { columnaExiste($0.key, en: cuenta.movimientosCSV) }, clave: "id").op)
            if f.tipo == .emitida, direccion == .cobro {
                var datos = ["documento_id": f.id, "pago_id": pagoID, "movimiento_id": mov.id, "importe": importe,
                             "fecha_cobro": mov.fecha.description]
                if let t = f.tercero { datos["tercero"] = t }
                if let r = f.rutaDocumento { datos["factura"] = r.raw }
                if let o = f.oportunidad { datos["oportunidad"] = o }
                eventos.append(EventoFinanzas(tipo: .cobroConfirmado, clave: "cobro.confirmado:\(pagoID)", fecha: reloj.hoy,
                                              autor: autor.etiqueta, datos: datos))
            }
        }
        if let texto = registros.snapshot.existing(registros.pagosCSV).flatMap({ registros.snapshot.text($0) }) {
            ops += CSVEscritura.filasNuevas(pagos.map(\.fila), en: registros.pagosCSV, texto: texto)
        } else {
            ops.append(CommandBus.Comando.crear(registros.pagosCSV,
                                                texto: CSVEscritura.texto(cabecera: RegistrosFinanzas.cabeceraPagos, filas: pagos.map(\.fila))).op)
        }
        let descripcion = ps.count == 1
            ? Self.descripcion(ps[0])
            : "Confirmar " + Plural.de(ps.count, "conciliación", "conciliaciones")
        return ConfirmacionConciliacion(plan: WritePlan(autor: autor, descripcion: descripcion, ops: ops),
                                        pagos: pagos, eventos: eventos, propuestas: ps)
    }

    /// Dejar escritas las propuestas (`estado_conciliacion = propuesta`, `documento_id` y motivo).
    /// Lo puede hacer el sistema o un asistente: no confirma nada. `nil` si no hay ninguna que escribir.
    public func planProponer(_ ps: [PropuestaConciliacion], autor: Autor) -> WritePlan? {
        let ops = ps.compactMap { p -> WriteOp? in
            guard let mov = registros.movimientos.first(where: { $0.id == p.movimiento.id }), mov.estado.abierto,
                  !(mov.estado == .propuesta && mov.documentoID == p.factura.id && mov.motivo == p.motivo) else { return nil }
            return CommandBus.Comando.guardarFila(p.cuenta.movimientosCSV, fila: [
                "id": mov.id, "estado_conciliacion": EstadoConciliacion.propuesta.rawValue, "documento_id": p.factura.id,
                "motivo": p.motivo,
            ].filter { columnaExiste($0.key, en: p.cuenta.movimientosCSV) }, clave: "id").op
        }
        guard !ops.isEmpty else { return nil }
        return WritePlan(autor: autor, descripcion: "Proponer " + Plural.de(ops.count, "conciliación", "conciliaciones"), ops: ops)
    }

    /// Marcar un movimiento como sin factura (impuestos, nómina, traspaso…), con el motivo.
    public func planIgnorar(_ movimiento: MovimientoBanco, motivo: String, autor: Autor) throws -> WritePlan {
        guard let mov = registros.movimientos.first(where: { $0.id == movimiento.id && $0.cuentaID == movimiento.cuentaID }),
              let cuenta = registros.cuenta(id: mov.cuentaID) else { throw ErrorConciliacion.movimientoNoEncontrado(movimiento.id) }
        guard mov.estado.abierto, mov.pagoID == nil else { throw ErrorConciliacion.yaConciliado(mov.id) }
        let fila = ["id": mov.id, "estado_conciliacion": EstadoConciliacion.ignorado.rawValue, "motivo": motivo]
        return WritePlan(autor: autor, descripcion: "Dejar sin factura el movimiento «\(mov.concepto)»",
                         ops: [CommandBus.Comando.guardarFila(cuenta.movimientosCSV, fila: fila, clave: "id").op])
    }

    // MARK: Ayudas

    /// «Conciliar «TRANSFERENCIA DE TALLERES MARTIN…» con F-2026-0007» (para Deshacer).
    static func descripcion(_ p: PropuestaConciliacion) -> String {
        let c = p.movimiento.concepto
        let corto = c.count > 40 ? String(c.prefix(40)) + "…" : c
        return "Conciliar «\(corto)» con \(p.factura.numeroVisible)"
    }

    /// `PAG-AAAAMMDD-NNN`: el siguiente número de ese día (los que ya hay y los de este mismo lote).
    func siguienteID(fecha: LocalDate, ya: inout [String: Int]) -> String {
        let dia = fecha.description.replacingOccurrences(of: "-", with: "")
        let prefijo = "PAG-\(dia)-"
        let maximo = ya[dia] ?? registros.pagos.compactMap { p -> Int? in
            guard p.id.hasPrefix(prefijo) else { return nil }
            return Int(p.id.dropFirst(prefijo.count))
        }.max() ?? 0
        ya[dia] = maximo + 1
        return prefijo + String(format: "%03d", maximo + 1)
    }

    /// Cómo se movió el dinero, solo si el concepto lo dice; si no, vacío (nunca se inventa).
    static func metodo(_ concepto: String) -> String {
        let c = TextFolding.fold(concepto)
        if c.hasPrefix("transferencia") || c.hasPrefix("transf") || c.contains("transferencia") { return "transferencia" }
        if c.hasPrefix("recibo") || c.contains("adeudo") || c.contains("domiciliacion") { return "domiciliación" }
        if c.contains("bizum") { return "bizum" }
        if c.contains("tarjeta") || c.contains("tpv") || c.hasPrefix("compra") { return "tarjeta" }
        return ""
    }

    func cabecera(_ ruta: VaultPath) -> [String]? {
        guard let real = registros.snapshot.existing(ruta), let texto = registros.snapshot.text(real) else { return nil }
        return CSVTable.parse(texto).header.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func columnaExiste(_ columna: String, en ruta: VaultPath) -> Bool {
        guard let cab = cabecera(ruta) else { return true }
        return cab.contains { $0.lowercased() == columna }
    }
}
