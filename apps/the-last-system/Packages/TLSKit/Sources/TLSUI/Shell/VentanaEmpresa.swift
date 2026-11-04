import SwiftUI
import TLSCore
import TLSDesign

/// Una ventana (o pestaña de ventana) de empresa: `WindowGroup(id: "vault", for: VentanaRuta.self)`.
///
/// Retiene la sesión compartida de la empresa mientras está abierta y tiene su propia `Navegacion`
/// (camino, historial y recuerdos de esta pestaña), que se guarda en `@SceneStorage`.
struct VentanaEmpresa: View {
    @Binding var ruta: VentanaRuta?
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var sesion: VaultSession?
    @State private var nav = Navegacion()
    @State private var retenida: UUID?
    @SceneStorage("navegacion") private var navegacionGuardada: Data?

    var body: some View {
        Group {
            if let sesion {
                EstadoSesionView(sesion: sesion, nav: nav)
            } else if empresa == nil || empresa.flatMap({ model.entry(id: $0) }) == nil {
                VacioExplicado(icono: "building.2", titulo: "Esta empresa ya no está en la lista",
                               porQue: "Puede que la hayas quitado del selector. Tu carpeta no se ha tocado.",
                               accion: "Abrir el selector", alPulsar: { openWindow(id: SceneID.launcher) })
                    .frame(minWidth: 480, minHeight: 320)
                    .background(TLSPaleta.fondo.color)
            } else {
                ProgressView().frame(minWidth: 480, minHeight: 320)
            }
        }
        .background(AccesoVentana(empresa: empresa, ruta: ruta, nav: nav))
        .onAppear { retener() }
        .onDisappear { soltar() }
        .onChange(of: nav.pasoActual) { _, _ in
            navegacionGuardada = nav.codificado
            sesion?.registrarVisita(nav.actual)
        }
    }

    /// La empresa de esta ventana: la de su valor o, si llega vacía (botón «+» de las pestañas), la última.
    private var empresa: UUID? { ruta?.empresa ?? model.ultimaEmpresa }

    private func retener() {
        guard retenida == nil, let id = empresa, let s = model.retenerSesion(id) else { return }
        retenida = id
        sesion = s
        // Al volver a abrir la app manda lo guardado de esta pestaña; si es nueva, su destino.
        if let datos = navegacionGuardada {
            nav.restaurar(datos)
        } else if let destino = ruta?.destino {
            nav = Navegacion(raiz: destino, pila: ruta?.sembrar ?? [])
        }
        if ruta == nil { ruta = VentanaRuta(empresa: id) }
        s.navegacionActiva = nav
    }

    private func soltar() {
        guard let id = retenida else { return }
        retenida = nil
        if sesion?.navegacionActiva === nav { sesion?.navegacionActiva = nil }
        model.soltarSesion(id)
    }
}

/// Estado de la sesión: abriendo, errores o la ventana lista.
struct EstadoSesionView: View {
    let sesion: VaultSession
    let nav: Navegacion
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch sesion.phase {
            case .lista:
                ContenidoEmpresa(sesion: sesion, nav: nav)
            case .abriendo(let progress):
                AbriendoView(entry: sesion.entry, progress: progress)
            case .sinPermiso:
                PermissionRecoveryView(folderName: sesion.entry.nombre) {
                    Task { await sesion.start(using: model) }
                }
                .frame(minWidth: 520, minHeight: 360)
            case .noEncontrada:
                VacioExplicado(icono: "questionmark.folder", titulo: "No encuentro la carpeta",
                               porQue: "La última vez estaba en \(TLSFormat.rutaCorta(sesion.entry.ruta)). Puede que se haya movido o que el disco no esté conectado.",
                               accion: "Volver a intentarlo", alPulsar: { Task { await sesion.start(using: model) } })
                    .frame(minWidth: 520, minHeight: 360)
            case .exclusionPerdida(let missing):
                PrivadaPerdidaView(missing: missing) {
                    guard let root = sesion.root, let elegidas = FolderPanels.askPrivate(inside: root) else { return }
                    Task { await sesion.replaceMissingPrivate(missing, with: elegidas, using: model) }
                }
            case .error(let message):
                ErrorAlAbrirView(message: message) {
                    Task { await sesion.start(using: model) }
                } onRebuild: {
                    Task { await sesion.rebuildIndex(using: model) }
                }
            }
        }
        .background(TLSPaleta.fondo.color)
        .navigationTitle(sesion.isReady ? sesion.nombre(de: nav.actual) : sesion.entry.nombre)
        .focusedSceneValue(\.vaultSession, sesion)
        .focusedSceneValue(\.navegacion, nav)
        .onChange(of: sesion.isReady, initial: true) { _, lista in
            if lista { UITestHooks.apply(to: sesion, nav: nav) }
        }
    }
}
