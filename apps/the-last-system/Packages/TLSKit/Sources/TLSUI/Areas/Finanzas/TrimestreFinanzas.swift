import SwiftUI
import TLSCore
import TLSDesign

/// Finanzas › Trimestre (PLAN §6.5, SISTEMAS FI3): el plazo, el 303 **estimado** y los demás modelos (130, 111, 115) con
/// lo que falta, los totales de ingresos y gastos, y «Preparar paquete para la gestoría», que deja el índice y cuatro
/// CSV en su carpeta **sin enviar nada** y sin pisar lo que ya hay. Lo presenta la gestoría.
struct TrimestreFinanzas: View {
    @Bindable var modelo: ModeloFinanzas
    let lectura: LecturaFinanzas
    @Environment(\.undoManager) private var undoManager
    @Environment(\.navegar) private var navegar

    var body: some View {
        let r = lectura.trimestre
        let p = lectura.periodo
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            cabecera(r, p)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: TLSEspacio.entreMosaicos, alignment: .top)],
                      alignment: .leading, spacing: TLSEspacio.entreMosaicos) { modelos(r) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: TLSEspacio.entreMosaicos, alignment: .top)],
                      alignment: .leading, spacing: TLSEspacio.entreMosaicos) { libros(r) }
            faltan(r)
            paquete
        }
        .accessibilityIdentifier("finanzas.trimestre")
    }

    // MARK: Cabecera

    private func cabecera(_ r: ResumenTrimestre, _ p: PeriodoTrimestre) -> some View {
        let hoy = lectura.hoy
        let plazo = r.diasHastaPlazo >= 0
            ? "Se presenta hasta el \(TextoFinanzas.fecha(p.plazo, hoy: hoy)) (\(TextoFinanzas.dias(r.diasHastaPlazo)))"
            : "El plazo acabó el \(TextoFinanzas.fecha(p.plazo, hoy: hoy))"
        return HStack(alignment: .center, spacing: TLSEspacio.e12) {
            Button { Task { await modelo.elegirPeriodo(p.anterior) } } label: { Image(systemName: "chevron.left") }
                .tlsBoton(.discreto)
                .accessibilityLabel("Trimestre anterior")
            Text(p.titulo).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("trimestre.titulo")
            Button { Task { await modelo.elegirPeriodo(p.siguiente) } } label: { Image(systemName: "chevron.right") }
                .tlsBoton(.discreto)
                .disabled(p.desde > hoy)
                .accessibilityLabel("Trimestre siguiente")
            VStack(alignment: .leading, spacing: 2) {
                Text(plazo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text("Todo es estimado: lo revisa y lo presenta la gestoría.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: 0)
            if modelo.periodoElegido != nil, p != PeriodoTrimestre.aPresentar(hoy: hoy) {
                Button("Volver al que toca") { Task { await modelo.elegirPeriodo(nil) } }.tlsBoton(.enlace)
            }
        }
    }

    // MARK: Modelos

    @ViewBuilder
    private func modelos(_ r: ResumenTrimestre) -> some View {
        TarjetaModeloFiscal(titulo: "IVA · 303", estimacion: r.modelo303)
        TarjetaModeloFiscal(titulo: "Alquileres · 115", estimacion: r.modelo115)
        TarjetaModeloFiscal(titulo: "Retenciones · 111", estimacion: r.modelo111)
        TarjetaModeloFiscal(titulo: "Pago fraccionado · 130", estimacion: r.modelo130)
    }

    @ViewBuilder
    private func libros(_ r: ResumenTrimestre) -> some View {
        TarjetaLibroFiscal(titulo: "Ingresos", icono: "arrow.down.circle", totales: r.ingresos)
        TarjetaLibroFiscal(titulo: "Gastos", icono: "arrow.up.circle", totales: r.gastos)
    }

    @ViewBuilder
    private func faltan(_ r: ResumenTrimestre) -> some View {
        if !r.faltan.isEmpty {
            Mosaico("Lo que falta para cerrar el trimestre", icono: "list.bullet.clipboard",
                    pie: r.faltan.count > 6 ? "Y \(r.faltan.count - 6) más en diferencias.csv del paquete" : nil) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(r.faltan.prefix(6).enumerated()), id: \.offset) { _, f in
                        let partes = [FormatoFicha.capital(f.tipo), f.descripcion, f.importe.map(TextoFinanzas.euros)].compactMap { $0 }
                        AvisoEnLinea(partes.joined(separator: " · "), estado: .atencion)
                    }
                }
            }
            .accessibilityIdentifier("trimestre.faltan")
        }
    }

    // MARK: Paquete

    private var paquete: some View {
        let paq = lectura.paquete
        return Mosaico("Paquete para la gestoría", icono: "shippingbox", pie: "No se envía nada: queda en su carpeta y lo mandas tú.") {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                Text(paq.resumen).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trimestre.paquete.resumen")
                if paq.documentosPrivados > 0 {
                    Text("Los originales de carpetas privadas no entran en el paquete.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                HStack(spacing: TLSEspacio.e8) {
                    if paq.ficheros.contains(where: \.yaExiste) {
                        Button("Ver la carpeta del paquete") { navegar(.carpeta(paq.carpeta), modo: .automatico) }
                            .tlsBoton(.secundario)
                    }
                    Spacer(minLength: 0)
                    if !paq.yaExiste {
                        BotonPrincipal("Preparar paquete para la gestoría", icono: "shippingbox",
                                       motivoDesactivado: modelo.motivoSoloLectura ?? (modelo.trabajando ? "Escribiendo…" : nil)) {
                            Task { await modelo.prepararPaquete(deshacer: undoManager) }
                        }
                        .accessibilityIdentifier("trimestre.preparar")
                    }
                }
            }
        }
        .accessibilityIdentifier("trimestre.paquete")
    }
}

/// Un modelo del trimestre: resultado estimado («a ingresar» o «a compensar»), si aplica, y lo que falta.
private struct TarjetaModeloFiscal: View {
    let titulo: String
    let estimacion: EstimacionModelo

    var body: some View {
        Mosaico(titulo, icono: "doc.plaintext", pie: pie) {
            VStack(alignment: .leading, spacing: 6) {
                switch estimacion.aplica {
                case .no(let motivo):
                    Text("No aplica").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text(motivo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                case .sinDato(let motivo):
                    Text(TextoFinanzas.sinDato).tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                    Text(motivo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                case .si:
                    Text(TextoFinanzas.euros(estimacion.resultado))
                        .tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("trimestre.modelo.\(estimacion.modelo)")
                    HStack(spacing: 6) {
                        if let r = estimacion.resultado {
                            Text(r > 0 ? "A ingresar" : (r < 0 ? "A compensar" : "Sin cuota"))
                                .tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        } else if let p = estimacion.parcial, p != 0 {
                            Text("Con lo que hay: \(TextoFinanzas.euros(p))").tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                        PastillaEstimadoFinanzas()
                    }
                }
            }
        }
        .frame(minHeight: 170)
        .accessibilityElement(children: .combine)
    }

    private var pie: String? {
        if !estimacion.faltan.isEmpty {
            return "Falta: " + estimacion.faltan.prefix(2).map(\.descripcion).joined(separator: "; ")
                + (estimacion.faltan.count > 2 ? "; y \(estimacion.faltan.count - 2) más" : "")
        }
        return estimacion.notas.first
    }
}

/// Totales de un libro del trimestre (ingresos o gastos). Sin facturas, «Sin dato».
private struct TarjetaLibroFiscal: View {
    let titulo: String
    let icono: String
    let totales: TotalesLibro

    var body: some View {
        Mosaico(titulo, icono: icono, pie: FormatoBase.cuenta(totales.documentos, "factura", "facturas")) {
            Grid(alignment: .leading, horizontalSpacing: TLSEspacio.e16, verticalSpacing: 4) {
                fila("Base", totales.base)
                fila("IVA", totales.iva)
                fila("Retención", totales.retencion)
                fila("Total", totales.total, fuerte: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fila(_ t: String, _ v: Int?, fuerte: Bool = false) -> some View {
        GridRow {
            Text(t).tlsTexto(fuerte ? TLSTipo.interfazFuerte : TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            Text(TextoFinanzas.euros(v)).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                .gridColumnAlignment(.trailing)
        }
    }
}
