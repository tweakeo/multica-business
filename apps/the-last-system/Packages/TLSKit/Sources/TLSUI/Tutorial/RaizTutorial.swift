import AppKit
import SwiftUI
import TLSCore
import TLSDesign

/// La raíz del tutorial en la ventana de una empresa: `.tutorialAnchor(.raiz, sesion:, nav:)`, una línea en
/// `ContenidoEmpresa`. Pone encima el velo con su hueco y la burbuja, y escucha lo que pasa (navegación, anclas,
/// escrituras) para marcar los hitos.
public enum TutorialRaiz: Sendable { case raiz }

public extension View {
    func tutorialAnchor(_ raiz: TutorialRaiz, sesion: VaultSession, nav: Navegacion) -> some View {
        modifier(RaizTutorialModifier(sesion: sesion, nav: nav))
    }
}

/// Lo que el tutorial puede pedir a la ventana (abrir el manual, reiniciar el ejemplo).
@MainActor
struct AccionesVentanaTutorial {
    var abrirManual: (String) -> Void = { _ in }
    var reiniciarEjemplo: () -> Void = {}
}

struct RaizTutorialModifier: ViewModifier {
    let sesion: VaultSession
    let nav: Navegacion
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model: AppModel?

    func body(content: Content) -> some View {
        let c = ControladorTutorial.de(sesion)
        // Sin recorrido en marcha no se escucha a las anclas (desplazarse no vuelve a pintar nada).
        let activo = c.activo
        let versionAnclas = activo ? TutorialAnclas.compartidas.version : 0
        let _ = c.pulso
        let presentes = activo ? TutorialAnclas.compartidas.presentes(en: c.ventana) : []
        content
            .overlay {
                TutorialCapa(paso: c.pasoVisible(anclasPresentes: presentes, destinoActual: nav.actual)) { id in
                    c.pulsar(id, nav: nav, acciones: acciones(c))
                }
            }
            .background(SondaVentanaTutorial { c.ventana = $0 }.allowsHitTesting(false).accessibilityHidden(true))
            .onChange(of: nav.actual, initial: true) { _, destino in c.navego(a: destino) }
            .onChange(of: sesion.revision) { _, _ in
                let rutas = sesion.ultimasCambiadas
                Task { await c.carpetaCambio(rutas) }
            }
            .onChange(of: versionAnclas) { _, _ in c.anclasCambiaron() }
            .task(id: sesion.isReady) { await c.alAbrir() }
            .onAppear { c.raices += 1 }
            .onDisappear {
                c.raices -= 1
                if c.raices <= 0 { c.pararMonitor() }
            }
    }

    private func acciones(_ c: ControladorTutorial) -> AccionesVentanaTutorial {
        let abrir = openWindow
        let modelo = model
        let empresa = sesion.entry.id
        let almacen = c.almacen
        let appSupport = c.appSupport
        return AccionesVentanaTutorial(
            abrirManual: { seccion in
                ManualNavegacion.compartida.abrir(seccion)
                abrir(id: ManualNavegacion.idVentana)
            },
            reiniciarEjemplo: {
                guard let modelo else { return }
                Task { @MainActor in
                    if let nueva = await EjemploTutorial.reiniciar(empresa: empresa, model: modelo, almacen: almacen,
                                                                   appSupport: appSupport) {
                        abrir.abrirEmpresa(nueva.id)
                    }
                }
            })
    }
}

extension ControladorTutorial {
    /// Lo que enseña la burbuja ahora (`nil` si no va ningún recorrido).
    func pasoVisible(anclasPresentes: Set<TutorialAnclaID>, destinoActual: Destino? = nil) -> TutorialPasoVisible? {
        guard let paso = pasoActual else { return nil }
        let partes = estado.partesHechas
        let hecho = paso.hecho(partes)
        let i = indice
        let n = pasos.count
        let ultimo = i == n - 1
        let marca: TutorialPasoVisible.Marca = paso.llegaConLosAsistentes ? .llegaConLosAsistentes
            : (paso.tieneAccion ? (hecho ? .hecho : .porHacer) : .ninguna)
        let anclaVisible = paso.ancla.map(anclasPresentes.contains) ?? true
        let enDestino: Bool = {
            guard let d = paso.destino, let a = destinoActual else { return false }
            return d.identidad == a.identidad && (d.pestana == nil || d.pestana == a.pestana)
        }()

        var botones: [TutorialBoton] = []
        if ultimo {
            botones.append(.init(id: "terminar", titulo: "Terminar", tipo: .principal))
            if tipo == .ejemplo { botones.append(.init(id: "reiniciar", titulo: "Reiniciar ejemplo")) }
        } else if i == 0, !paso.tieneAccion {
            botones.append(.init(id: "siguiente", titulo: "Empezar", tipo: .principal))
        } else if !paso.tieneAccion || hecho {
            botones.append(.init(id: "siguiente", titulo: "Siguiente", tipo: .principal))
        } else if paso.destino != nil, !anclaVisible, !enDestino {
            botones.append(.init(id: "llevarme", titulo: "Llévame", tipo: .principal))
        }
        if let a = paso.accion, !hecho {
            switch a {
            case .mostrarEnFinder: botones.append(.init(id: "finder", titulo: "Mostrar en Finder"))
            case .extractoDeEjemplo: botones.append(.init(id: "extracto", titulo: "Dame un extracto"))
            }
        }
        if ultimo, tipo == .ejemplo, Self.repasarPuestaEnMarcha != nil {
            botones.append(.init(id: "repasar", titulo: "Repasar la puesta en marcha", tipo: .enlace))
        }
        botones.append(.init(id: "saberMas", titulo: "Saber más", tipo: .enlace))
        if paso.tieneAccion, !hecho { botones.append(.init(id: "saltar", titulo: "Saltar", tipo: .enlace)) }
        if i > 0 { botones.append(.init(id: "anterior", titulo: "Atrás", tipo: .enlace)) }
        botones.append(.init(id: "seguirMasTarde", titulo: "Seguir más tarde", tipo: .enlace))

        let total = pasosConAccion.count
        let progreso = "\(hechos) de \(total) hitos · Quedan ~\(quedanMinutos) min"
        let items: [TutorialItem] = (i == 0 || ultimo) ? listaDeHitos : []
        return TutorialPasoVisible(id: "\(tipo.rawValue).\(paso.id)", ancla: hecho ? nil : paso.ancla,
                                   // Un solo contador, el de los hitos («2 de 8 hitos»): sin «paso N de 12» al lado.
                                   rotulo: tipo.rotulo, titulo: paso.titulo,
                                   texto: hecho ? (paso.textoHecho ?? paso.texto) : paso.texto, marca: marca,
                                   progreso: progreso, botones: botones,
                                   bloquearFuera: paso.tieneAccion && !hecho, items: items)
    }

    /// Los hitos del recorrido con su estado.
    var listaDeHitos: [TutorialItem] {
        switch tipo {
        case .ejemplo:
            HitoTutorial.allCases.map { h in
                TutorialItem(id: h.rawValue, titulo: h.titulo,
                             marca: h.llegaConLosAsistentes ? .llegaConLosAsistentes
                                 : (Set(h.partes).isSubset(of: estado.partesHechas) ? .hecho : .porHacer))
            }
        case .tuEmpresa:
            pasos.filter { !$0.partes.isEmpty }.map { p in
                TutorialItem(id: p.id, titulo: p.titulo,
                             marca: p.llegaConLosAsistentes ? .llegaConLosAsistentes
                                 : (p.hecho(estado.partesHechas) ? .hecho : .porHacer))
            }
        }
    }

    /// Un botón de la burbuja.
    func pulsar(_ id: String, nav: Navegacion?, acciones: AccionesVentanaTutorial) {
        guard let paso = pasoActual else { return }
        switch id {
        case "siguiente", "saltar": irA(indice + 1)
        case "anterior": irA(indice - 1)
        case "seguirMasTarde": seguirMasTarde()
        case "terminar": terminar()
        case "llevarme":
            if let d = paso.destino { nav?.nuevaRaiz(d) }
        case "saberMas": acciones.abrirManual(paso.manual)
        case "finder":
            let ruta = ultimaFicha ?? paso.destino?.ruta ?? contexto.ficha
            if let revelar { revelar(ruta) } else { sesion?.revealInFinder(ruta) }
            registrar(.vistaEnFinder(ruta))
        case "extracto":
            if let url = EjemploTutorial.extractoDeEjemplo() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case "reiniciar": acciones.reiniciarEjemplo()
        case "repasar":
            if let sesion { Self.repasarPuestaEnMarcha?(sesion) }
        default: break
        }
    }
}

/// Lo que cualquier pantalla (o la puesta en marcha) puede decirle al tutorial.
@MainActor
public enum TutorialEventos {
    /// Una acción real que cuenta para el tutorial (⌘J, pausar los asistentes… cuando lleguen).
    public static func registrar(_ evento: TutorialEvent, empresa: UUID) {
        ControladorTutorial.abierto(empresa: empresa)?.registrar(evento)
    }

    /// Empieza un recorrido. Si la empresa no está abierta, empezará al abrirla.
    public static func empezar(_ tipo: TipoRecorrido, empresa: UUID, almacen: AlmacenTutorial = .compartido) async {
        if let c = ControladorTutorial.abierto(empresa: empresa), c.tipo == tipo {
            await c.empezar()
        } else {
            almacen.cambiar(tipo, empresa: empresa) { e in
                if e.fase == .terminado { e.paso = 0 }
                e.fase = .enCurso
            }
        }
    }

    /// Cómo va un recorrido.
    public static func estado(_ tipo: TipoRecorrido, empresa: UUID? = nil, almacen: AlmacenTutorial = .compartido) -> EstadoRecorrido {
        almacen.estado(tipo, empresa: empresa)
    }
}

/// Avisa de la ventana en la que está la raíz (para las anclas y los clics de esa ventana).
struct SondaVentanaTutorial: NSViewRepresentable {
    let alCambiar: (NSWindow?) -> Void

    func makeNSView(context: Context) -> VistaSondaVentana {
        let v = VistaSondaVentana()
        v.alCambiar = alCambiar
        return v
    }

    func updateNSView(_ vista: VistaSondaVentana, context: Context) { vista.alCambiar = alCambiar }
}

final class VistaSondaVentana: NSView {
    var alCambiar: ((NSWindow?) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        alCambiar?(window)
    }
}
