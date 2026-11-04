import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol areas-b. El `init` es contrato con `AreaScaffold` (docs/F2-CONTRATOS.md §2). PLAN §6.5: Roles (persona o
// asistente) · Asistentes con su bitácora y uso frente al tope · Rutinas en rejilla ✓ ✕ –. Acción rápida: Revisar
// asistentes. Se pinta dentro del andamio.

/// Las secciones de Equipo › Operación (recordadas por pestaña de ventana en `"equipo.seccion"`).
enum SeccionEquipo: String, CaseIterable, Sendable {
    case roles = "Roles"
    case asistentes = "Asistentes"
    case rutinas = "Rutinas"
}

/// Pestaña Operación de Equipo.
struct EquipoOperacion: View {
    let contexto: ContextoArea
    let sesion: VaultSession
    @State private var modelo: ModeloEquipo
    @Environment(\.navegacion) private var nav

    init(contexto: ContextoArea, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
        _modelo = State(initialValue: ModeloEquipo(sesion: sesion))
    }

    static let claveSeccion = "equipo.seccion"

    private var seccion: SeccionEquipo {
        nav?.recuerdo(de: .area(.equipo)).extra[Self.claveSeccion].flatMap(SeccionEquipo.init(rawValue:)) ?? .roles
    }

    private func ir(_ s: SeccionEquipo) {
        nav?.actualizarRecuerdo(de: .area(.equipo)) { $0.extra[Self.claveSeccion] = s == .roles ? nil : s.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            barra
            if let l = modelo.lectura {
                switch seccion {
                case .roles: RolesEquipo(lectura: l, contexto: contexto)
                case .asistentes: EquipoAsistentesVista(sesion: sesion, contexto: contexto)  // F4 · rol asistentes
                case .rutinas: RutinasEquipo(lectura: l)
                }
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo el equipo…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: sesion.revision) { await modelo.cargar() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("area.operacion.equipo")
    }

    private var barra: some View {
        let l = modelo.lectura
        let caidas = l?.rutinasCaidas.count ?? 0
        let pestanas = SeccionEquipo.allCases.map { s -> PestanaCapsula in
            switch s {
            case .roles: PestanaCapsula(id: s.rawValue, titulo: s.rawValue, contador: l.map { $0.roles.count })
            case .asistentes: PestanaCapsula(id: s.rawValue, titulo: s.rawValue,
                                             contador: l.map { $0.asistentes.isEmpty ? $0.rolesDeAsistente.count : $0.asistentes.count }.flatMap { $0 > 0 ? $0 : nil })
            case .rutinas: PestanaCapsula(id: s.rawValue, titulo: s.rawValue, contador: l.map { $0.rutinas.count },
                                          urgente: caidas > 0 ? .mal : nil)
            }
        }
        let selector = PestanasCapsula(seleccion: Binding(get: { seccion.rawValue }, set: { ir(SeccionEquipo(rawValue: $0) ?? .roles) }),
                                       pestanas: pestanas, atajosControl: false)
            .accessibilityLabel("Secciones de Equipo")
            .accessibilityIdentifier("equipo.secciones")
        let revisar = Button { ir(.asistentes) } label: { Label("Revisar asistentes", systemImage: "sparkle") }
            .tlsBoton(.secundario)
            .help("Ver qué hace cada asistente y cuánto gasta")
            .accessibilityIdentifier("equipo.accion.revisar")
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                selector
                Spacer(minLength: TLSEspacio.e8)
                revisar
            }
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                selector
                revisar
            }
        }
    }
}
