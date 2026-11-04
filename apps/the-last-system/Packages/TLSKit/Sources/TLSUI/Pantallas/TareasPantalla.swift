import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol tareas (antes HUECO del andamio). El `init` es contrato con el enrutador (`Shell/PantallaDestino`,
// `.tareas`; docs/F2-CONTRATOS.md §2). PLAN §6.4 con Mosaico v2: cabecera azul noche con lo de hoy, «Revisar» si
// hay algo, la barra (Lista | Tablero, «Lo mío», fecha, búsqueda y filtros) y la lista agrupable o el tablero.
// Sin destacado violeta (como las bases). El detalle es `Tareas/TareaDetalle` (`.tarea(ruta)`) y ⌘N abre
// `Tareas/NuevaTareaHoja`.

/// Tareas: todas las de la empresa (sin lo privado), en lista o en tablero, como un gestor de tareas.
struct TareasPantalla: View {
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @State private var modelo: ModeloTareas
    @State private var consultaLeida = false

    init(sesion: VaultSession) {
        self.sesion = sesion
        _modelo = State(initialValue: ModeloTareas(sesion: sesion))
    }

    var body: some View {
        ContenedorPantalla(destino: .tareas, espacio: TLSEspacio.e16) {
            cabecera
            RevisarTareas(modelo: modelo)
            BarraTareas(modelo: modelo)
            contenido
        }
        .task(id: sesion.revision) {
            if !consultaLeida, let r = nav?.recuerdo(de: .tareas) {
                modelo.consulta = ConsultaTareas(recuerdo: r)
            }
            consultaLeida = true
            await modelo.cargar()
        }
        .onChange(of: modelo.consulta) { _, c in
            guard consultaLeida else { return }
            nav?.actualizarRecuerdo(de: .tareas) { c.guardar(en: &$0) }
        }
    }

    private var cabecera: some View {
        let r = modelo.resumen
        let datos: [DatoClave] = modelo.filas.isEmpty ? [] : [
            // «Ninguna», como el resto de la app, en vez de un 0 suelto.
            DatoClave("Para hoy", r.paraHoy == 0 ? "Ninguna" : "\(r.paraHoy)"),
            DatoClave("Vencidas", r.vencidas == 0 ? "Ninguna" : "\(r.vencidas)"),
            DatoClave("En revisión", r.enRevision == 0 ? "Ninguna" : "\(r.enRevision)"),
        ]
        return CabeceraAzulNoche(rotulo: "Lo que toca hacer", titulo: "Tareas",
                                 subtitulo: modelo.cargada ? r.frase : "Leyendo las tareas…",
                                 datos: datos, altoMinimo: TLSAltura.cabeceraBase, cifrasALaDerecha: true,
                                 identidad: { EmptyView() },
                                 acciones: {
                                     Button {
                                         nav?.hoja = .nuevaTarea
                                     } label: {
                                         Label("Nueva tarea", systemImage: "plus")
                                     }
                                     .tlsBoton(.sobreCabecera, alto: 36)
                                     .disabled(!sesion.puedeEscribir)
                                     .help(sesion.puedeEscribir ? "Nueva tarea (⌘N)" : "No se puede crear: \(modelo.motivoSoloLectura ?? "solo lectura")")
                                     .tutorialAnchor(.tareasNueva)
                                 },
                                 debajo: { EmptyView() })
    }

    @ViewBuilder
    private var contenido: some View {
        if !modelo.cargada {
            HStack(spacing: TLSEspacio.e8) {
                ProgressView().controlSize(.small)
                Text("Leyendo las tareas…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .padding(.vertical, TLSEspacio.e24)
        } else if modelo.filas.isEmpty {
            VacioExplicado(icono: "checkmark.square", titulo: "Aún no hay tareas",
                           porQue: "Cada tarea es una ficha en la carpeta Tareas de su área o de su proyecto. Crea la primera con ⌘N.",
                           accion: sesion.puedeEscribir ? "Nueva tarea" : nil,
                           alPulsar: sesion.puedeEscribir ? { nav?.hoja = .nuevaTarea } : nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TLSEspacio.e32)
        } else if modelo.visibles.isEmpty {
            VacioExplicado(icono: "line.3.horizontal.decrease.circle", titulo: "Ninguna tarea con estos filtros",
                           porQue: Self.porQueVacio(modelo.consulta),
                           accion: "Quitar filtros", alPulsar: { modelo.consulta.quitarFiltros() })
                .frame(maxWidth: .infinity)
                .padding(.vertical, TLSEspacio.e32)
        } else if modelo.consulta.vista == .lista {
            ListaTareas(modelo: modelo)
        } else {
            TableroTareas(modelo: modelo)
        }
    }

    /// Por qué no sale nada, en palabras.
    static func porQueVacio(_ c: ConsultaTareas) -> String {
        switch c.fecha {
        case .hoy: return "Nada planificado para hoy ni que venza hoy" + (c.loMio ? " entre las tuyas." : ".")
        case .vencidas: return "Ninguna tarea abierta ha pasado su fecha límite" + (c.loMio ? " entre las tuyas." : ".")
        case .semana: return "Nada planificado ni con fecha límite esta semana" + (c.loMio ? " entre las tuyas." : ".")
        case .sinProgramar: return "Todas las abiertas tienen ya un día para hacerlas."
        case .todas: return c.loMio ? "No llevas ninguna tarea con estos filtros." : "Prueba con otra búsqueda o quita algún filtro."
        }
    }
}
