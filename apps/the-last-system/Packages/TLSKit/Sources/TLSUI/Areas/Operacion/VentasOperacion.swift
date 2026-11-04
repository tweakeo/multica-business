import SwiftUI
import TLSCore
import TLSDesign

// Rol areas-a (F2). El `init` es contrato con `AreaScaffold` (docs/F2-CONTRATOS.md §2). PLAN §6.5 y SISTEMAS §4.2:
// CRM en tablero de Prospecto a Ganada con número, euros, conversión y «quieta 9 d» (soltar en Ganada sin cobro se
// bloquea con el mensaje de VEN-07 y se ofrece Aceptada) · Seguimiento a 7, 14, 21 y 30 días («Preparar
// seguimiento» deja el borrador en una tarea; enviar, nunca) · Contactos y Empresas (llevan a sus bases). Arriba,
// VEN-STALE7 y VEN-PIPE.

/// Pestaña Operación de Ventas.
struct VentasOperacion: View {
    let contexto: ContextoArea
    let sesion: VaultSession

    @State private var carga: CargaOperacion<DatosVentas>
    @State private var bloqueo: BloqueoCRM?
    @State private var error: String?
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager

    static let secciones = ["CRM", "Seguimiento", "Contactos y empresas"]
    static let clave = "ventas.vista"

    init(contexto: ContextoArea, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
        _carga = State(initialValue: CargaOperacion(sesion: sesion) { foto, hoy in DatosVentas.calcular(foto: foto, hoy: hoy) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let d = carga.datos {
                contenido(d)
            } else {
                CargandoOperacion(texto: "Leyendo oportunidades y propuestas…")
            }
        }
        .task(id: sesion.revision) { await carga.cargar() }
        .accessibilityIdentifier("area.operacion.ventas")
    }

    @ViewBuilder
    private func contenido(_ d: DatosVentas) -> some View {
        FranjaCifras(cifras: d.cifras)
        if let error { AvisoEnLinea(error, estado: .mal) }
        SeccionesOperacion(area: .ventas, clave: Self.clave, secciones: secciones(d))
        switch SeccionesOperacion.elegida(nav, area: .ventas, clave: Self.clave, secciones: Self.secciones) {
        case "Seguimiento":
            BloqueOperacion("Seguimiento de propuestas", detalle: "A los 7, 14, 21 y 30 días de enviar cada propuesta. Preparar deja el borrador en una tarea; enviarlo es cosa tuya.") {
                SeguimientoVista(seguimientos: d.seguimientos, hoy: d.hoy, motivoSoloLectura: carga.motivoSoloLectura,
                                 alPreparar: { s, dia in
                                     hacer { await AccionesVentas.prepararSeguimiento(s, dia: dia, sesion: sesion, deshacer: undoManager) }
                                 },
                                 alAbrir: { r in navegar(sesion.destino(para: r), modo: .automatico) })
            }
        case "Contactos y empresas":
            DirectorioVentasVista(contactos: d.contactos, empresas: d.empresas)
        default:
            TableroCRMVista(tablero: d.tablero, empresa: sesion.entry.id, motivoSoloLectura: carga.motivoSoloLectura, bloqueo: bloqueo,
                            alMover: mover, alAbrir: { t in navegar(sesion.destino(para: t.ruta), modo: .automatico) },
                            alAlternativa: { b in
                                guard let a = b.alternativa else { return }
                                bloqueo = nil
                                hacer { await AccionesVentas.aplicar(a, nombre: b.tarjeta.nombre, sesion: sesion, deshacer: undoManager) }
                            },
                            alCerrarBloqueo: { bloqueo = nil })
        }
    }

    private func secciones(_ d: DatosVentas) -> [PestanaCapsula] {
        let tocan = d.seguimientos.filter { $0.toca != nil }.count
        let quietas = d.tablero.columnas.flatMap(\.tarjetas).filter(\.quieta).count
        return [
            PestanaCapsula(id: "CRM", titulo: "CRM", contador: d.tablero.columnas.reduce(0) { $0 + $1.numero },
                           urgente: quietas > 0 ? .atencion : nil),
            PestanaCapsula(id: "Seguimiento", titulo: "Seguimiento", contador: tocan > 0 ? tocan : nil, urgente: tocan > 0 ? .atencion : nil),
            PestanaCapsula(id: "Contactos y empresas", titulo: "Contactos y empresas"),
        ]
    }

    private func mover(_ t: TarjetaCRM, _ etapa: EtapaCRM) {
        error = nil
        bloqueo = nil
        Task {
            switch await AccionesVentas.mover(t, a: etapa, sesion: sesion, deshacer: undoManager) {
            case .hecho: break
            case .bloqueado(let m, let a): bloqueo = BloqueoCRM(tarjeta: t, mensaje: m, alternativa: a)
            case .error(let e): error = e
            }
        }
    }

    private func hacer(_ accion: @escaping () async -> String?) {
        error = nil
        Task { error = await accion() }
    }
}
