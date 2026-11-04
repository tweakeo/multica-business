import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol areas-b. El `init` es contrato con el enrutador (`Shell/PantallaDestino`, destino `.banco(cuenta)`;
// docs/F2-CONTRATOS.md §2). PLAN §6.5 y §4.6: soltar el extracto (CSV), «34 · 12 nuevos · 22 ya importados»,
// propuestas de conciliación con su motivo, «Confirmar las exactas» (siempre con el clic de una persona: ninguna regla
// confirma un cobro) y los movimientos heredados en preparación. API del núcleo: rol de banco
// (`Sources/TLSCore/Finanzas`).

/// Banco y conciliación de Finanzas: todas las cuentas (`cuenta == nil`) o una (`4 · Finanzas/Registros/Bancos/<cuenta>`).
struct BancoPantalla: View {
    let cuenta: VaultPath?
    let sesion: VaultSession
    @State private var modelo: ModeloFinanzas
    @State private var elegirExtracto = false
    @Environment(\.navegar) private var navegar

    init(cuenta: VaultPath?, sesion: VaultSession) {
        self.cuenta = cuenta
        self.sesion = sesion
        _modelo = State(initialValue: ModeloFinanzas(sesion: sesion, cuenta: cuenta))
    }

    var body: some View {
        ContenedorPantalla(destino: .banco(cuenta)) {
            cabecera
            if let l = modelo.lectura {
                if cuenta != nil, modelo.cuentaFija == nil {
                    VacioExplicado(icono: "building.columns", titulo: "No encuentro esta cuenta",
                                   porQue: "Puede que se haya movido o que esté en una carpeta privada. Abre el Banco con todas las cuentas.",
                                   accion: "Ver todas las cuentas", alPulsar: { navegar(.banco(nil), modo: .automatico) })
                } else {
                    BancoContenido(modelo: modelo, lectura: l, elegirExtracto: { elegirExtracto = true })
                }
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo el banco…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: sesion.revision) { await modelo.cargar() }
        .fileImporter(isPresented: $elegirExtracto, allowedContentTypes: FinanzasOperacion.tiposExtracto) { r in
            guard case .success(let url) = r else { return }
            Task { await modelo.previsualizar(url: url) }
        }
        .accessibilityIdentifier("banco")
    }

    private var cabecera: some View {
        let l = modelo.lectura
        let c = modelo.cuentaFija
        var datos: [DatoClave] = []
        if let l {
            if let c {
                let saldo = l.saldo.cuentas.first { $0.cuenta.id == c.id }
                datos.append(DatoClave("Saldo", TextoFinanzas.euros(saldo?.saldo)))
                datos.append(DatoClave("Sin conciliar", "\(l.movimientos(de: c).filter(\.estado.abierto).count)"))
                if let u = l.movimientos(de: c).map(\.fecha).max() { datos.append(DatoClave("Último movimiento", TextoFinanzas.fecha(u, hoy: l.hoy))) }
            } else {
                datos.append(DatoClave("Caja", TextoFinanzas.euros(l.saldo.total)))
                datos.append(DatoClave("Sin conciliar", l.sinConciliar.map { "\($0)" } ?? TextoFinanzas.sinDato))
                if let u = l.ultimoMovimiento { datos.append(DatoClave("Último movimiento", TextoFinanzas.fecha(u, hoy: l.hoy))) }
            }
        }
        let titulo = c?.nombre ?? (cuenta.map { sesion.nombreF2(de: .banco($0)) } ?? "Banco")
        let subtitulo = c.flatMap { $0.ibanUltimos4.map { "Terminada en \($0) · importar extractos y conciliar cada movimiento con su factura." } }
            ?? "Importar extractos y conciliar cada movimiento con su factura. Ningún cobro se confirma sin tu clic."
        return CabeceraAzulNoche(rotulo: "4 · Finanzas", titulo: titulo, subtitulo: subtitulo, datos: datos,
                                 altoMinimo: TLSAltura.cabeceraFichaMinima) {
            IconoArea(.finanzas, tamano: 44, sobreCabecera: true)
        } acciones: {
            if cuenta != nil {
                Button("Ver todas las cuentas") { navegar(.banco(nil), modo: .automatico) }
                    .tlsBoton(.sobreCabecera)
            }
        }
    }
}
