import SwiftUI
import TLSCore
import TLSDesign

// F4 · rol mika. La barra de herramientas de la ventana de empresa (DISENO §7.2: `BotonBuscar(); BotonMika();
// InterruptorAsistentes()`), el panel flotante de ⌘J encima del detalle y el menú «Mika» (⌘J). Lo usa
// `ContenidoEmpresa` con una sola línea: `.barraDeMika(sesion:nav:)`.

extension View {
    /// Botón Mika e interruptor en la barra de la ventana, y el panel de ⌘J.
    func barraDeMika(sesion: VaultSession, nav: Navegacion) -> some View {
        modifier(BarraDeMika(sesion: sesion, nav: nav))
    }
}

struct BarraDeMika: ViewModifier {
    let sesion: VaultSession
    let nav: Navegacion
    @Environment(\.accessibilityReduceMotion) private var reducir
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        let conversacion = ConversacionMika.de(sesion)
        content
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    BotonMika(sesion: sesion, nav: nav)
                    // El interruptor es el del rol asistentes (Asistentes/InterruptorAsistentes).
                    InterruptorGeneralAsistentes(sesion: sesion, estilo: .barraDeHerramientas)
                }
            }
            .overlay(alignment: .topTrailing) {
                if conversacion.abierto {
                    PanelMika(sesion: sesion, conversacion: conversacion) { conversacion.abierto = false }
                        .frame(width: 400)
                        .frame(maxHeight: 720)
                        .padding(TLSEspacio.e16)
                        .transition(reducir ? .opacity : .opacity.combined(with: .offset(x: 16)))
                }
            }
            .animation(reducir ? .easeOut(duration: 0.12) : TLSMovimiento.muelle, value: conversacion.abierto)
            .focusedSceneValue(\.conversacionMika, AccionMika { conversacion.alternar(contexto: .de(nav, sesion: sesion)) })
            .task(id: sesion.puedeEscribir) {
                await AsistentesDeLaEmpresa.de(sesion).actualizar()
                AvisosDeAsistentes.de(sesion).vigilar()
            }
            .task(id: sesion.revision) { await AsistentesDeLaEmpresa.de(sesion).actualizar() }
            // «Pedir algo» desde la ficha de un asistente abre ⌘J: en cuanto la integración conecta el motor (aunque sea
            // con la ventana ya a la vista: el registro es observable).
            .task(id: RegistroDeAsistentes.compartido.conexion(de: sesion).map(ObjectIdentifier.init)) {
                let conversacion = ConversacionMika.de(sesion)
                RegistroDeAsistentes.compartido.conexion(de: sesion)?.abrirChat = { [weak sesion, weak nav] asistente, _ in
                    guard let sesion else { return }
                    conversacion.abrir(contexto: .de(nav, sesion: sesion), para: asistente)
                }
            }
            .onAppear {
                let abrir = openWindow
                PreferenciasPresencia.abrirEmpresa = { id, destino in abrir.abrirEmpresa(id, destino: destino) }
            }
            .onChange(of: nav.pasoActual) { _, _ in
                // El contexto sigue a la pantalla mientras el panel está abierto.
                if conversacion.abierto { conversacion.abrir(contexto: .de(nav, sesion: sesion)) }
            }
    }
}

/// Lo que hace ⌘J en la ventana con el foco.
struct AccionMika {
    let alternar: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var conversacionMika: AccionMika?
}

/// Menú «Mika» con ⌘J (PLAN §6.1: «Mika con el contexto de la pantalla»).
public struct ComandosMika: Commands {
    @FocusedValue(\.conversacionMika) private var mika

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Hablar con Mika") { mika?.alternar() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(mika == nil)
        }
    }
}

/// «Mika ⌘J» en la barra de la ventana.
struct BotonMika: View {
    let sesion: VaultSession
    let nav: Navegacion

    var body: some View {
        let conversacion = ConversacionMika.de(sesion)
        Button { conversacion.alternar(contexto: .de(nav, sesion: sesion)) } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(TLSPaleta.violetaTexto.color)
                Text("Mika").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                Tecla("⌘J")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .background(Capsule(style: .circular).fill(conversacion.abierto ? TLSPaleta.violetaSuave.color : TLSPaleta.bandeja.color))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .help("Hablar con Mika con lo que tienes en pantalla (⌘J)")
        .accessibilityLabel(conversacion.abierto ? "Cerrar Mika" : "Hablar con Mika")
        .accessibilityIdentifier("barra.mika")
    }
}

