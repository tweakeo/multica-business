import SwiftUI
import TLSCore
import TLSDesign

/// La ventana de una empresa lista (§7.2): barra lateral y detalle con una pila de pantallas por pestaña de
/// ventana; ‹ › y migas en la barra de la ventana; banner de copia o ejemplo; aviso con «Deshacer».
struct ContenidoEmpresa: View {
    @Bindable var sesion: VaultSession
    @Bindable var nav: Navegacion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reducir
    @Environment(\.undoManager) private var undoManager
    @State private var columnas = NavigationSplitViewVisibility.all
    @State private var anchoDetalle: CGFloat = 1000
    @State private var soltandoFuera = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnas) {
            BarraLateral(sesion: sesion, nav: nav)
                .navigationSplitViewColumnWidth(min: TLSAncho.barraLateralMinima, ideal: TLSAncho.barraLateral,
                                                max: TLSAncho.barraLateralMaxima)
        } detail: {
            detalle
        }
        .frame(minWidth: 760, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: TLSEspacio.e8) {
                    BotonesAtrasAdelante(nav: nav, sesion: sesion)
                    if anchoVentana >= TLSAncho.migasEnBarra {
                        MigasView(nav: nav, sesion: sesion, ancho: PlegadoMigas.anchoParaMigas(anchoDetalle: anchoDetalle))
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                BotonBuscarTodo { nav.hoja = .paleta }
            }
        }
        .sheet(item: $nav.hoja) { hoja in
            switch hoja {
            case .paleta: PaletaBusqueda(sesion: sesion)
            case .abrirRapido: QuickOpenSheet(session: sesion)
            case .nuevaTarea: NuevaTareaHoja(contexto: nav.actual, sesion: sesion)
            case .nuevaNota: NuevaNotaHoja(contexto: nav.actual, sesion: sesion)
            case .actualizarCopia: ActualizarCopiaHoja(sesion: sesion)
            case .importarMultica: ImportarMulticaHoja(sesion: sesion)
            }
        }
        // F4 · rol mika: botón Mika e interruptor en la barra, y el panel de ⌘J (Shell/BarraMenuMika).
        .barraDeMika(sesion: sesion, nav: nav)
        .environment(\.navegar, accionNavegar)
        .environment(\.navegacion, nav)
        .tutorialAnchor(.raiz, sesion: sesion, nav: nav)
        // Números de las bases en la barra lateral desde que la empresa está lista (no solo al abrir una base).
        .tlsContadoresDeBases(sesion)
        .onAppear { sesion.undoManagerActivo = undoManager }
        // Al abrir (y al volver a permitir cambios): el motor del dominio termina lo que quedó a medias y Hoy calcula
        // la insignia de Decisiones aunque la ventana se haya restaurado en otra pantalla.
        .task(id: sesion.puedeEscribir) {
            _ = DominioEmpresa.motor(de: sesion)
            await AlmacenHoy.de(sesion).actualizar()
        }
    }

    /// Ancho aproximado de la ventana (detalle + barra lateral).
    private var anchoVentana: CGFloat {
        anchoDetalle + (columnas == .detailOnly ? 0 : TLSAncho.barraLateral)
    }

    private var detalle: some View {
        NavigationStack(path: Binding(get: { nav.pila }, set: { nav.ajustarPila($0) })) {
            PantallaDestino(destino: nav.raiz, sesion: sesion)
                .id(nav.raiz.identidad)
                .transition(TLSMovimiento.transicionNivel(reducir: reducir, haciaAtras: nav.ultimoFueAtras))
                .navigationDestination(for: Destino.self) { destino in
                    PantallaDestino(destino: destino, sesion: sesion)
                        .navigationBarBackButtonHidden(true)
                }
        }
        .animation(TLSMovimiento.entrarNivel(reducir: reducir), value: nav.raiz.identidad)
        .environment(\.tlsMigasEnFranja, anchoVentana < TLSAncho.migasEnBarra ? anchoDetalle - 32 : nil)
        .background(TLSPaleta.fondo.color)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { anchoDetalle = $0 }
        .overlay(alignment: .top) {
            if soltandoFuera {
                Label("Suelta para ocultarlo de la barra", systemImage: "eye.slash")
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.superficie.color)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .background(Capsule(style: .circular).fill(TLSPaleta.texto.color))
                    .padding(.top, TLSEspacio.e12)
                    .allowsHitTesting(false)
            }
        }
        // Arrastrar una fila de la barra lateral fuera de ella la oculta (§6).
        .dropDestination(for: ArrastreBarra.self) { items, _ in
            for item in items where !item.desdeOcultos { sesion.barraLateral.ocultar(item.elemento, deshacer: undoManager) }
            return !items.isEmpty
        } isTargeted: { soltandoFuera = $0 }
        .overlay(alignment: .topTrailing) {
            if let ruta = nav.vistaPrevia {
                VistaPreviaPopover(ruta: ruta, sesion: sesion)
                    .frame(width: TLSAncho.vistaPrevia)
                    .padding(TLSEspacio.e16)
                    .onExitCommand { nav.vistaPrevia = nil }
            }
        }
        .tlsAviso($sesion.aviso)
        .onKeyPress(.upArrow, phases: .down) { tecla in
            guard tecla.modifiers == .command, nav.puedeSubir else { return .ignored }
            nav.subir()
            return .handled
        }
    }

    private var accionNavegar: NavegarAccion {
        let abrir = openWindow
        return NavegarAccion(nav: nav, empresa: sesion.entry.id) { ruta in
            abrir(id: SceneID.vault, value: ruta)
        }
    }
}

/// «Buscar o hacer… ⌘K» en la barra de la ventana (§4.9). Abre la paleta de búsqueda.
struct BotonBuscarTodo: View {
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(TLSPaleta.textoSecundario.color)
                Text("Buscar o hacer…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer(minLength: 8)
                Tecla("⌘K")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(minWidth: 220, minHeight: TLSAltura.objetivoMinimo)
            .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .help("Buscar o hacer en todas las bases (⌘K)")
        .accessibilityLabel("Buscar o hacer en todas las bases")
    }
}

extension EnvironmentValues {
    /// Con la ventana estrecha (< 960 pt), ancho para las migas en la franja bajo la barra; si no, `nil`.
    @Entry var tlsMigasEnFranja: CGFloat? = nil
}

/// Encima de cada pantalla de la pila: el banner de la carpeta y, con la ventana estrecha, las migas.
/// Va dentro de cada nivel (no fuera del `NavigationStack`) para que se vea igual en todos.
struct EncimaDePantalla: View {
    let sesion: VaultSession
    @Environment(\.navegacion) private var nav
    @Environment(\.tlsMigasEnFranja) private var anchoMigas

    var body: some View {
        VStack(spacing: 0) {
            BannerCarpeta(sesion: sesion)
            if let anchoMigas, let nav {
                MigasView(nav: nav, sesion: sesion, ancho: anchoMigas)
                    .padding(.horizontal, TLSEspacio.e16)
                    .frame(maxWidth: .infinity, minHeight: TLSAltura.franjaMigas, alignment: .leading)
                    .background(TLSPaleta.superficie.color)
                    .overlay(alignment: .bottom) { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
            }
        }
    }
}

/// Banner permanente de la carpeta (copia, ejemplo o solo lectura) y aviso de estructura ilegible.
struct BannerCarpeta: View {
    let sesion: VaultSession

    var body: some View {
        VStack(spacing: 0) {
            InfoBanner(sesion.entry.bannerText, systemImage: sesion.entry.bannerSystemImage)
                .accessibilityIdentifier("empresa.banner")
            if let warning = sesion.layoutWarning {
                InfoBanner(warning, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("empresa.avisoEstructura")
            }
        }
    }
}
