import SwiftUI
import TLSCore
import TLSDesign

// F5 · rol conexiones. Conexiones en Ajustes: una sección con el estado de cada conexión (texto e icono) y «Abrir
// Conexiones» (la pantalla entera en una hoja), y Ajustes › Avanzado con la matriz técnica de los otros programas y el
// alta de un programa de este Mac. `AjustesPantalla` lo incluye con una línea (`SeccionesConexionesAjustes`).

extension ClaudeEnConexiones {
    /// Claude Code según la comprobación de Ajustes (F4).
    static func deAjustes(_ c: ComprobacionClaude, model: AppModel?) -> ClaudeEnConexiones {
        ClaudeEnConexiones(
            info: {
                let estado: EstadoConexion = switch c.estado {
                case .encontrado(_, let sesion): sesion == false ? .error("Falta iniciar sesión en Claude Code.") : .conectado
                case .probado(let ok): ok ? .conectado : .error(TextosClaude.probado(false))
                default: .ahoraNo
                }
                return InfoClaude(estado: estado, texto: c.texto, consejo: c.consejo,
                                  ocupado: c.estado == .buscando || c.estado == .probando, puedeProbar: c.estado.encontrado,
                                  puedeBuscar: true)
            },
            buscar: { await c.buscar() },
            probar: {
                let negadas = model.map { m in m.entries.compactMap { m.resolveURL($0) } } ?? []
                let dir = (model?.appSupport ?? AppLocations.appSupport).appendingPathComponent("comprobacion", isDirectory: true)
                await c.probar(estado: dir, negadas: negadas)
            })
    }
}

extension ModeloConexiones {
    /// El de una empresa abierta (o sin empresa, en la ventana de Ajustes del Mac).
    static func deAjustes(sesion: VaultSession?, model: AppModel?) -> ModeloConexiones {
        let id = sesion?.entry.id
        return ModeloConexiones(servicios: id.flatMap { ConexionesDeLaApp.servicios($0) }, modo: .ajustes,
                                claude: .deAjustes(.compartida, model: model), presencia: .compartidas, empresa: id,
                                defaults: PreferenciasPresencia.esLaApp ? .standard : nil)
    }
}

/// Las secciones «Conexiones» y «Avanzado» de Ajustes.
struct SeccionesConexionesAjustes: View {
    let sesion: VaultSession?
    @Environment(AppModel.self) private var model
    @Environment(\.navegar) private var navegar
    @State private var modelo: ModeloConexiones?
    @State private var hoja = false
    @State private var avanzado = false

    // F5 · corrector (P2-12): la sección existe siempre (con «Leyendo…» mientras carga). Antes todo colgaba de un `Group`
    // vacío y su `.task` no llegaba a lanzarse: Conexiones y Avanzado no salían en Ajustes.
    var body: some View {
        Section("Conexiones") {
            if let modelo {
                ForEach(ModeloConexiones.orden, id: \.self) { c in
                    LabeledContent {
                        PastillaConexion(estado: modelo.estado(c), palabra: modelo.palabra(c))
                    } label: {
                        Label(c.titulo, systemImage: c.iconoConexion)
                    }
                    .accessibilityIdentifier("ajustes.conexion.\(c.rawValue)")
                }
                Button("Abrir Conexiones") { hoja = true }
                    .accessibilityIdentifier("ajustes.abrirConexiones")
            } else {
                Text("Leyendo tus conexiones…").foregroundStyle(.secondary)
            }
        }
        .task(id: sesion?.entry.id) {
            let m = ModeloConexiones.deAjustes(sesion: sesion, model: model)
            modelo = m
            await m.cargar()
        }
        if let modelo {
            Section("Avanzado") {
                DisclosureGroup("Otros programas: detalle técnico", isExpanded: $avanzado) {
                    MatrizTecnicaVista(modelo: modelo)
                    Divider()
                    Text("Añadir un programa de este Mac").font(.headline)
                    AltaProgramaLocalVista(modelo: modelo)
                }
                .accessibilityIdentifier("ajustes.avanzado.conexiones")
            }
            .sheet(isPresented: $hoja, onDismiss: { Task { await modelo.cargar() } }) {
                HojaConexiones(modelo: modelo, abrirBanco: sesion == nil ? nil : {
                    hoja = false
                    navegar(.banco(), modo: .raiz(sembrar: []))
                })
            }
        }
    }
}

/// La pantalla Conexiones en una hoja (desde Ajustes).
struct HojaConexiones: View {
    @Bindable var modelo: ModeloConexiones
    var abrirBanco: (() -> Void)?
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                ConexionesVista(modelo: modelo, abrirBanco: abrirBanco)
                    .padding(TLSEspacio.e24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Listo") { cerrar() }.keyboardShortcut(.defaultAction).tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
            }
            .padding(TLSEspacio.e16)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 640, idealHeight: 760)
        .background(TLSPaleta.fondo.color)
    }
}
