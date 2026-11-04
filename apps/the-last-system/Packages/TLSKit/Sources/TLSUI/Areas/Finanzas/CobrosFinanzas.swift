import SwiftUI
import TLSCore
import TLSDesign

/// Finanzas › Cobros (PLAN §6.5 «Cobros vencidos», SISTEMAS FI1): lo que falta por cobrar de cada factura emitida
/// (total menos los cobros **confirmados por una persona**), vencidas primero. Lo cargado de ficheros heredados y sin
/// revisar no cuenta. Sin registro de emitidas, «Sin dato»; nunca un 0 de relleno.
struct CobrosFinanzas: View {
    let lectura: LecturaFinanzas
    let contexto: ContextoArea
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TLSEspacio.entreMosaicos) { cifras }
                VStack(spacing: TLSEspacio.entreMosaicos) { cifras }
            }
            if !lectura.hayEmitidas {
                VacioExplicado(icono: "doc.text", titulo: "Sin dato de cobros",
                               porQue: "No hay registro de facturas emitidas (Registros/emitidas.csv). Cuando emitas la primera, aquí verás lo que falta por cobrar.",
                               compacto: true)
            } else if lectura.cobrosPendientes.isEmpty {
                VacioExplicado(icono: "checkmark.circle", titulo: "Nada por cobrar",
                               porQue: "Todas las facturas emitidas tienen su cobro confirmado. Los cobros solo cuentan cuando los confirmas en el Banco.",
                               compacto: true)
            } else {
                lista
            }
            if lectura.sinRevisar > 0 {
                AvisoEnLinea(FormatoBase.cuenta(lectura.sinRevisar, "factura heredada", "facturas heredadas")
                             + " sigue en preparación sin revisar: no cuenta aquí hasta que la revises.", estado: .atencion)
            }
        }
        .accessibilityIdentifier("finanzas.cobros")
    }

    @ViewBuilder
    private var cifras: some View {
        let ar = contexto.numero("FIN-AR")
        Mosaico("Vencido sin cobrar", icono: "exclamationmark.circle", pie: ar.map { "FIN-AR · " + metaTexto($0) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lectura.hayEmitidas ? TextoFinanzas.euros(lectura.totalVencido) : TextoFinanzas.sinDato)
                    .tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityIdentifier("finanzas.cobros.vencido")
                Text(lectura.cobrosVencidos.isEmpty ? "Ninguna factura vencida" :
                        FormatoBase.cuenta(lectura.cobrosVencidos.count, "factura vencida", "facturas vencidas"))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .frame(minHeight: 132)
        Mosaico("Por cobrar", icono: "tray.and.arrow.down", pie: "Total de las facturas menos los cobros confirmados") {
            VStack(alignment: .leading, spacing: 6) {
                Text(lectura.hayEmitidas ? TextoFinanzas.euros(lectura.cobrosPendientes.map(\.pendiente).reduce(0, +)) : TextoFinanzas.sinDato)
                    .tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                Text(FormatoBase.cuenta(lectura.cobrosPendientes.count, "factura pendiente", "facturas pendientes"))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .frame(minHeight: 132)
    }

    private func metaTexto(_ f: FilaControl) -> String {
        f.tieneMeta ? "meta \(f.textoMeta)" + (f.alerta.map { " · alerta " + Umbral(texto: $0).textoVisible } ?? "") : "sin meta"
    }

    private var lista: some View {
        let hoy = lectura.hoy
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(lectura.cobrosPendientes) { c in
                let f = c.factura
                let detalle = [f.tercero, cuando(c, hoy: hoy)].compactMap { $0 }.joined(separator: " · ")
                FilaLista(f.numeroVisible, detalle: detalle, icono: "doc.text",
                          etiquetaAccesible: "\(f.numeroVisible), \(detalle), por cobrar \(TextoFinanzas.euros(c.pendiente))",
                          accion: f.rutaDocumento.map { r in { navegar(.ficha(r), modo: .automatico) } }) {
                    HStack(spacing: TLSEspacio.e8) {
                        if c.vencida { PastillaEstado(.mal, palabra: "Vencida") }
                        Text(TextoFinanzas.euros(c.pendiente)).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                    }
                }
                if c.id != lectura.cobrosPendientes.last?.id {
                    Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Facturas por cobrar, vencidas primero")
    }

    /// «Vencida hace 5 días», «Vence el 22 oct (dentro de 3 días)» o «Sin vencimiento».
    private func cuando(_ c: CobroPendiente, hoy: LocalDate) -> String {
        if let d = c.diasVencida { return d == 0 ? "Vence hoy" : (d == 1 ? "Vencida hace 1 día" : "Vencida hace \(d) días") }
        guard let v = c.vence else { return "Sin vencimiento" }
        return "Vence el \(TextoFinanzas.fecha(v, hoy: hoy)) (\(TextoFinanzas.dias(FormatoFicha.dias(de: hoy, a: v))))"
    }
}
