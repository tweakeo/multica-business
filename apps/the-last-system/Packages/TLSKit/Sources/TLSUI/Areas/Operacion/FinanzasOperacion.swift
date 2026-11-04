import SwiftUI
import TLSCore
import TLSDesign
import UniformTypeIdentifiers

// F2 · rol areas-b. El `init` es contrato con `AreaScaffold` (docs/F2-CONTRATOS.md §2). PLAN §6.5: Caja con saldo,
// meses de caja y gráfica 1S·1M·3M·1A·Todo · Cobros vencidos · Banco (importar extractos y conciliar) · Trimestre con
// el 303 estimado y el paquete para la gestoría. Acciones rápidas: Importar extracto · Preparar paquete. Se pinta dentro
// del andamio (sin cabecera ni destacado propios).

/// Las secciones de Finanzas › Operación (recordadas por pestaña de ventana en `"finanzas.seccion"`).
enum SeccionFinanzas: String, CaseIterable, Sendable {
    case caja = "Caja"
    case cobros = "Cobros"
    case banco = "Banco"
    case trimestre = "Trimestre"
}

/// Pestaña Operación de Finanzas.
struct FinanzasOperacion: View {
    let contexto: ContextoArea
    let sesion: VaultSession
    @State private var modelo: ModeloFinanzas
    @State private var elegirExtracto = false
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager

    init(contexto: ContextoArea, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
        _modelo = State(initialValue: ModeloFinanzas(sesion: sesion))
    }

    static let claveSeccion = "finanzas.seccion"

    private var seccion: SeccionFinanzas {
        nav?.recuerdo(de: .area(.finanzas)).extra[Self.claveSeccion].flatMap(SeccionFinanzas.init(rawValue:)) ?? .caja
    }

    private func ir(_ s: SeccionFinanzas) {
        nav?.actualizarRecuerdo(de: .area(.finanzas)) { $0.extra[Self.claveSeccion] = s == .caja ? nil : s.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            barra
            AvisosFinanzas(modelo: modelo)
            if let l = modelo.lectura {
                switch seccion {
                case .caja:
                    CajaFinanzas(lectura: l, contexto: contexto, modelo: modelo) { abrirImportador() }
                case .cobros:
                    CobrosFinanzas(lectura: l, contexto: contexto)
                case .banco:
                    BancoContenido(modelo: modelo, lectura: l, elegirExtracto: { elegirExtracto = true }, mostrarAvisos: false)
                case .trimestre:
                    TrimestreFinanzas(modelo: modelo, lectura: l)
                }
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo las cuentas…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: sesion.revision) { await modelo.cargar() }
        .fileImporter(isPresented: $elegirExtracto, allowedContentTypes: Self.tiposExtracto) { r in
            guard case .success(let url) = r else { return }
            ir(.banco)
            Task { await modelo.previsualizar(url: url) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("area.operacion.finanzas")
    }

    static let tiposExtracto: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .text]

    private func abrirImportador() {
        ir(.banco)
        elegirExtracto = true
    }

    // MARK: Barra: secciones y acciones rápidas

    private var barra: some View {
        let l = modelo.lectura
        let porConfirmar = l?.propuestas.count ?? 0
        let vencidas = l?.cobrosVencidos.count ?? 0
        let pestanas = SeccionFinanzas.allCases.map { s -> PestanaCapsula in
            switch s {
            case .cobros:
                return PestanaCapsula(id: s.rawValue, titulo: s.rawValue, contador: l.map { $0.cobrosPendientes.count },
                                      urgente: vencidas > 0 ? .mal : nil)
            case .banco:
                return PestanaCapsula(id: s.rawValue, titulo: s.rawValue,
                                      aviso: porConfirmar > 0 ? (numero: porConfirmar, palabra: "Por confirmar") : nil)
            case .trimestre:
                let d = l?.trimestre.diasHastaPlazo
                return PestanaCapsula(id: s.rawValue, titulo: s.rawValue, urgente: d.map { $0 >= 0 && $0 <= 5 } == true ? .atencion : nil)
            case .caja:
                return PestanaCapsula(id: s.rawValue, titulo: s.rawValue)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                selector(pestanas)
                Spacer(minLength: TLSEspacio.e8)
                acciones
            }
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                selector(pestanas)
                acciones
            }
        }
    }

    private func selector(_ pestanas: [PestanaCapsula]) -> some View {
        PestanasCapsula(seleccion: Binding(get: { seccion.rawValue }, set: { ir(SeccionFinanzas(rawValue: $0) ?? .caja) }),
                        pestanas: pestanas, atajosControl: false)
            .accessibilityLabel("Secciones de Finanzas")
            .accessibilityIdentifier("finanzas.secciones")
    }

    private var acciones: some View {
        HStack(spacing: TLSEspacio.e8) {
            Button { abrirImportador() } label: { Label("Importar extracto…", systemImage: "square.and.arrow.down") }
                .tlsBoton(.secundario)
                .disabled(modelo.motivoSoloLectura != nil || modelo.trabajando)
                .help(modelo.motivoSoloLectura ?? "Elegir el extracto del banco en CSV")
                .accessibilityIdentifier("finanzas.accion.importar")
            Button {
                ir(.trimestre)
                Task { await modelo.prepararPaquete(deshacer: undoManager) }
            } label: { Label("Preparar paquete", systemImage: "shippingbox") }
                .tlsBoton(.secundario)
                .disabled(modelo.motivoSoloLectura != nil || modelo.trabajando || modelo.lectura?.paquete.yaExiste == true)
                .help(modelo.motivoSoloLectura ?? (modelo.lectura?.paquete.yaExiste == true
                    ? "El paquete de este trimestre ya está preparado"
                    : "Prepara el paquete del trimestre para la gestoría, sin enviarlo"))
                .accessibilityIdentifier("finanzas.accion.paquete")
        }
    }
}

/// Lo último que se hizo o no se pudo hacer en Finanzas (con su icono y texto: el color nunca va solo).
struct AvisosFinanzas: View {
    @Bindable var modelo: ModeloFinanzas

    var body: some View {
        if let e = modelo.error { AvisoEnLinea(e, estado: .mal).accessibilityIdentifier("finanzas.error") }
        if let h = modelo.hecho { AvisoEnLinea(h, estado: .bien).accessibilityIdentifier("finanzas.hecho") }
    }
}
