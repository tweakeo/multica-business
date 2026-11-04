import Foundation
import Observation
import TLSCore

/// Las relaciones de una empresa abierta, compartidas por todas sus fichas y vistas previas: una foto de la
/// carpeta (`VaultSession.instantanea`) y el `GrafoRelaciones` que sale de ella, rehechos fuera del hilo
/// principal cuando sube `sesion.revision`. Nunca escribe.
@Observable @MainActor
final class AlmacenRelaciones {
    private(set) var foto: VaultSnapshot?
    private(set) var grafo: GrafoRelaciones?
    /// El resolvedor de enlaces de la foto (todas las rutas, también PDF e imágenes), hecho una vez por foto.
    private(set) var resolver: LinkResolver?
    /// La revisión de la sesión con la que se hizo la foto (`-1` = aún no hay).
    private(set) var revisionCargada = -1
    /// Sube cada vez que se rehace la foto (para lo que se calcula de ella y se guarda).
    private(set) var generacion = 0
    /// El día de la carpeta (en el ejemplo, su día fijo).
    private(set) var hoy: LocalDate = LocalDate.today()

    @ObservationIgnored private weak var sesion: VaultSession?
    @ObservationIgnored private var carga: Task<Void, Never>?
    /// Texto de cada ficha la primera vez que se vio en esta sesión: las líneas distintas son las cambiadas hoy.
    @ObservationIgnored private(set) var textoInicial: [VaultPath: String] = [:]

    private static var porEmpresa: [UUID: AlmacenRelaciones] = [:]

    private init(sesion: VaultSession) { self.sesion = sesion }

    /// El almacén de esta sesión (uno por empresa abierta).
    static func de(_ sesion: VaultSession) -> AlmacenRelaciones {
        if let a = porEmpresa[sesion.entry.id], a.sesion === sesion { return a }
        let a = AlmacenRelaciones(sesion: sesion)
        porEmpresa[sesion.entry.id] = a
        return a
    }

    /// Al cerrar la empresa (`VaultSession.close`): suelta la foto de la carpeta (con lo privado) y el grafo.
    /// Una ficha que aún lo tenga sigue con su copia; la próxima apertura empieza de cero.
    static func soltar(_ sesion: VaultSession) {
        if let a = porEmpresa[sesion.entry.id], a.sesion === sesion || a.sesion == nil {
            a.carga?.cancel()
            porEmpresa[sesion.entry.id] = nil
        }
        porEmpresa = porEmpresa.filter { $0.value.sesion != nil }
    }

    var editor: EditorDeRelaciones? {
        guard let foto, let grafo else { return nil }
        return EditorDeRelaciones(snapshot: foto, grafo: grafo)
    }

    /// Rehace la foto si la sesión cambió desde la última vez. Varias llamadas a la vez esperan a la misma.
    func actualizar() async {
        guard let sesion else { return }
        while true {
            let rev = sesion.revision
            if rev == revisionCargada, grafo != nil { return }
            if let carga {
                await carga.value
                continue
            }
            // La propia carga se quita de `carga` al terminar (con foto o sin ella): así, quien esperaba vuelve a
            // mirar con la carga ya fuera y no da vueltas en el hilo principal si la foto no llegó (empresa cerrada).
            let tarea = Task { [weak self] in
                let foto = await sesion.instantanea()
                let resultado = await Task.detached(priority: .userInitiated) {
                    foto.map { (GrafoRelaciones(snapshot: $0), Reloj.deCarpeta($0).hoy, $0.resolver) }
                }.value
                guard let self else { return }
                self.carga = nil
                guard let foto, let resultado else { return }
                self.foto = foto
                self.grafo = resultado.0
                self.hoy = resultado.1
                self.resolver = resultado.2
                self.revisionCargada = rev
                self.generacion += 1
            }
            carga = tarea
            await tarea.value
            // Sin foto (la empresa se cerró o la carpeta no se pudo leer), no se insiste aquí.
            if revisionCargada != rev { return }
            if sesion.revision == rev || sesion.service == nil { return }
        }
    }

    /// Fuerza a rehacer la foto en la próxima `actualizar()` (tras escribir, antes de que llegue la revisión).
    func invalidar() { revisionCargada = -1 }

    /// Apunta el texto de una ficha la primera vez que se ve (para marcar lo cambiado después).
    func recordarTexto(_ ruta: VaultPath, _ texto: String) {
        if textoInicial[ruta] == nil { textoInicial[ruta] = texto }
    }
}
