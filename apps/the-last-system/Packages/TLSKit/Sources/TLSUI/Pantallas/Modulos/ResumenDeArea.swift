import SwiftUI
import TLSCore
import TLSDesign

// Pestaña Resumen de cada área (F2 · rol hoy-decisiones; DISENO §6, SISTEMAS §4.2 «Resumen: módulos por defecto»). El
// `init` es contrato con `AreaScaffold` (docs/F2-CONTRATOS.md §2). Rejilla de módulos movibles, ocultables y de tamaño
// cambiable (como mucho 8), guardada por empresa y por área fuera de la carpeta. Va dentro del andamio, bajo las
// pestañas: el destacado violeta del área es su número clave, así que aquí no hay otro.

/// Pestaña Resumen de un área: rejilla de módulos movibles y ocultables (como mucho 8).
struct ResumenDeArea: View {
    let contexto: ContextoArea
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav

    init(contexto: ContextoArea, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
    }

    private var almacen: AlmacenHoy { AlmacenHoy.de(sesion) }

    var body: some View {
        let resumen = sesion.area(contexto.area)
        VStack(alignment: .leading, spacing: TLSEspacio.e20) {
            if resumen?.tieneFicha == false {
                VacioExplicado(icono: "doc.badge.plus", titulo: "Esta área aún no tiene ficha",
                               porQue: "La ficha del área dice qué transforma, quién la lleva y con qué sistemas. Puedes verla en su carpeta.",
                               accion: "Ver la carpeta del área", alPulsar: { navegar(.carpeta(contexto.carpeta), modo: .automatico) })
            }
            InicioModulos(inicio: .area(contexto.area), datos: almacen.datos?.modulos, sesion: sesion, titulo: "Resumen",
                          hora: almacen.datos?.hora ?? "", minutosAhora: almacen.datos?.minutosAhora ?? 0)
            enlaces(resumen)
        }
        .task(id: sesion.revision) { await almacen.actualizar() }
        .accessibilityIdentifier("area.resumen")
    }

    private func enlaces(_ resumen: AreaSummary?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let resumen, resumen.tieneFicha {
                FilaLista("Ficha del área", detalle: resumen.estadoTexto.isEmpty ? nil : resumen.estadoTexto, icono: "doc.text") {
                    navegar(.nota(resumen.folder.appending("Área.md")), modo: .automatico)
                }
            }
            FilaLista("Carpeta del área", detalle: contexto.carpeta.raw, icono: "folder") {
                navegar(.carpeta(contexto.carpeta), modo: .automatico)
            }
            if contexto.fase != .reposo {
                FilaLista("Números del área", detalle: TLSFormat.cuenta(contexto.control.count, "número", "números"),
                          icono: "chart.line.uptrend.xyaxis") { nav?.cambiarPestana(PestanaArea.control.rawValue) }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
    }
}
