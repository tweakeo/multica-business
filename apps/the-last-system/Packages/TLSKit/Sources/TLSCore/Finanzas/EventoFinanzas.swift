import Foundation

/// Evento que dejan las operaciones de Finanzas para las reglas del dominio (SISTEMAS §3.3):
/// `extracto.importado` al importar un extracto y `cobro.confirmado` cuando una persona confirma
/// una conciliación de una factura emitida.
///
/// Finanzas no ejecuta reglas: devuelve el evento junto al plan. Quien aplica el plan (la interfaz)
/// lo entrega al `EventDeriver`/outbox del dominio **después** de que el plan quede `hecho`. La `clave`
/// es única por hecho (idempotencia): repetirla no debe volver a disparar nada.
public struct EventoFinanzas: Sendable, Hashable, Codable {
    public enum Tipo: String, Sendable, Hashable, Codable {
        case extractoImportado = "extracto.importado"
        case cobroConfirmado = "cobro.confirmado"
    }

    public let tipo: Tipo
    /// Única por hecho y la misma que `EventoDominio.clave` del `EventDeriver`:
    /// `extracto.importado:ruta:<ruta del original en minúsculas>`, `cobro.confirmado:<pago_id>`.
    public let clave: String
    public let fecha: LocalDate
    /// Etiqueta del autor (`Manu`, `sistema`, `agente:contable`).
    public let autor: String
    /// Datos del hecho: `cuenta_id`, `lote`, `nuevos`; o `documento_id`, `pago_id`, `movimiento_id`,
    /// `importe` (en el formato de los registros), `tercero`, `factura` (ruta de la ficha) y `oportunidad`.
    public let datos: [String: String]

    public init(tipo: Tipo, clave: String, fecha: LocalDate, autor: String, datos: [String: String]) {
        self.tipo = tipo; self.clave = clave; self.fecha = fecha; self.autor = autor; self.datos = datos
    }
}
