import Foundation
import Observation
import SwiftUI
import TLSCore
import TLSDesign

/// Lo que las bases y ⌘K leen de una empresa, compartido por todas sus pestañas de ventana: los datos de las
/// 24 bases y el catálogo de ⌘K, que se vuelven a leer (fuera del hilo principal) cuando cambia la carpeta
/// (`sesion.revision`). También pone los números de las bases en la barra lateral.
@Observable @MainActor
final class AlmacenBases {
    let sesion: VaultSession
    /// Datos de cada base (por `id`), de la última lectura.
    private(set) var datos: [String: DatosBase] = [:]
    private(set) var revisionDatos = -1
    /// Revisión con la que se leyó cada base suelta.
    @ObservationIgnored private var revisionPorBase: [String: Int] = [:]
    private(set) var catalogo: CatalogoBusqueda = .vacio
    private(set) var revisionCatalogo = -1
    private(set) var ajustes = AjustesBases()
    @ObservationIgnored private var cargaTodas: Task<Void, Never>?
    @ObservationIgnored private var cargaCatalogo: Task<Void, Never>?

    private init(sesion: VaultSession) {
        self.sesion = sesion
    }

    // MARK: Una por empresa abierta

    private static var porSesion: [ObjectIdentifier: (sesion: WeakSesion, almacen: AlmacenBases)] = [:]

    final class WeakSesion { weak var valor: VaultSession?; init(_ s: VaultSession) { valor = s } }

    static func de(_ sesion: VaultSession) -> AlmacenBases {
        porSesion = porSesion.filter { $0.value.sesion.valor != nil }
        let k = ObjectIdentifier(sesion)
        if let a = porSesion[k], a.sesion.valor === sesion { return a.almacen }
        let a = AlmacenBases(sesion: sesion)
        porSesion[k] = (WeakSesion(sesion), a)
        return a
    }

    /// Al cerrar la empresa (`VaultSession.close`): el almacén guarda la sesión y el diccionario lo guarda a
    /// él, así que sin soltarlo aquí la sesión entera (y sus datos) se quedaba en memoria para siempre.
    static func soltar(_ sesion: VaultSession) {
        let k = ObjectIdentifier(sesion)
        if let a = porSesion[k]?.almacen {
            a.cargaTodas?.cancel()
            a.cargaCatalogo?.cancel()
        }
        porSesion[k] = nil
        porSesion = porSesion.filter { $0.value.sesion.valor != nil }
    }

    // MARK: Leer

    /// Vistas guardadas de esta empresa (fuera de la carpeta, en sus datos de la app).
    var almacenVistas: AlmacenVistas {
        AlmacenVistas(directorio: sesion.directorioEstado.appendingPathComponent("vistas", isDirectory: true))
    }

    /// Lee las 24 bases si la carpeta cambió desde la última vez (y actualiza la barra lateral).
    func cargarTodas(forzar: Bool = false) async {
        let revision = sesion.revision
        guard forzar || revision != revisionDatos || datos.isEmpty else { return }
        if let cargaTodas { await cargaTodas.value; if revision == revisionDatos, !forzar { return } }
        guard let service = sesion.service, let root = sesion.root else { return }
        let persona = sesion.persona
        let tarea = Task { [weak self] in
            let (leidas, ajustes) = await Task.detached(priority: .userInitiated) { () -> ([String: DatosBase], AjustesBases) in
                let ajustes = AjustesBases.leer(root: root)
                return (LectorBases(service: service, ajustes: ajustes, persona: persona).leerTodas(), ajustes)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.datos = leidas
            self.ajustes = ajustes
            self.revisionDatos = revision
            self.actualizarBarra()
        }
        cargaTodas = tarea
        await tarea.value
    }

    /// Lee una base (más deprisa que todas: solo sus tipos).
    func cargar(_ id: String) async -> DatosBase? {
        guard let c = CatalogoBases.coleccion(id) else { return nil }
        let revision = sesion.revision
        if revisionDatos == revision || revisionPorBase[id] == revision, let d = datos[id] { return d }
        guard let service = sesion.service, let root = sesion.root else { return datos[id] }
        let persona = sesion.persona
        let leida = await Task.detached(priority: .userInitiated) { () -> (DatosBase, AjustesBases) in
            let ajustes = AjustesBases.leer(root: root)
            return (LectorBases(service: service, ajustes: ajustes, persona: persona).leer(c), ajustes)
        }.value
        datos[id] = leida.0
        revisionPorBase[id] = revision
        ajustes = leida.1
        actualizarBarra(id)
        return leida.0
    }

    /// Catálogo de ⌘K al día (se rehace en segundo plano cuando cambia la carpeta).
    func catalogoBusqueda() async -> CatalogoBusqueda {
        let revision = sesion.revision
        if revision == revisionCatalogo, !catalogo.entradas.isEmpty { return catalogo }
        if let cargaCatalogo { await cargaCatalogo.value; if revision == revisionCatalogo { return catalogo } }
        guard let service = sesion.service else { return catalogo }
        let tarea = Task { [weak self] in
            let nuevo = await Task.detached(priority: .userInitiated) { CatalogoBusqueda.construir(service.todasLasFichas()) }.value
            guard let self else { return }
            self.catalogo = nuevo
            self.revisionCatalogo = revision
        }
        cargaCatalogo = tarea
        await tarea.value
        return catalogo
    }

    // MARK: Barra lateral

    /// Número de fichas abiertas a la derecha de cada base fijada y lo urgente debajo (§4.1).
    func actualizarBarra(_ solo: String? = nil) {
        for (id, d) in datos where solo == nil || solo == id {
            var dato = sesion.barraLateral.datos[.base(id)] ?? DatoFilaBarra()
            dato.derecha = d.apagada ? nil : String(d.abiertas)
            dato.atencion = d.urgente.flatMap { $0.nivel == .info ? nil : $0.texto }
            dato.debajo = d.urgente.flatMap { $0.nivel == .info ? $0.texto : nil }
            dato.atenuado = d.apagada
            sesion.barraLateral.datos[.base(id)] = dato
        }
    }
}

/// Pide los números de las bases para la barra lateral en cuanto la empresa está lista y cada vez que cambia
/// la carpeta. Una línea en la ventana (`.tlsContadoresDeBases(sesion)`); mientras no esté puesta, los
/// números se ponen al abrir «Todas las bases» o una base.
struct ContadoresDeBasesModifier: ViewModifier {
    let sesion: VaultSession

    func body(content: Content) -> some View {
        content.task(id: sesion.isReady ? sesion.revision : -1) {
            guard sesion.isReady else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await AlmacenBases.de(sesion).cargarTodas()
        }
    }
}

extension View {
    /// Mantiene los números de las bases de la barra lateral al día.
    func tlsContadoresDeBases(_ sesion: VaultSession) -> some View {
        modifier(ContadoresDeBasesModifier(sesion: sesion))
    }
}

// MARK: Apoyos de presentación

extension ColeccionBase {
    /// Icono de app de su área (las comunes, el azul noche del tipo).
    var tlsArea: TLSArea? { area?.tlsArea }
}

extension AvisoBase.Nivel {
    var estado: TLSEstado {
        switch self {
        case .info: .sinDato
        case .atencion: .atencion
        case .mal: .mal
        }
    }
}

extension FilaBase {
    /// A dónde lleva abrir la fila: su ficha o, en una fila de CSV, su documento o el propio CSV.
    @MainActor func destino(en sesion: VaultSession) -> Destino {
        switch origen {
        case .ficha(let ruta): return sesion.destino(para: ruta)
        case .filaCSV(let ruta, _, _):
            if let doc = documento { return .fichero(doc) }
            return .nota(ruta)
        }
    }

    /// Ruta que se enseña en la vista previa.
    var rutaVistaPrevia: VaultPath { documento ?? ruta }

    /// Ruta de la vista previa al dejar el puntero encima (§2.5): la ficha o, en una fila de CSV, su documento
    /// (el CSV entero no dice nada de la fila).
    var rutaPreviaAlPasar: VaultPath? { esFilaCSV ? documento : ruta }
}
