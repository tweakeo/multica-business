import Foundation
import Observation
import TLSCore

/// Lectura de una ruta para **una** pantalla (ficha, nota, vista previa): la carga fuera del hilo principal,
/// la vuelve a leer cuando cambia (de fuera o escrita por la app) y, si está solo en iCloud, reintenta cada
/// 2 s durante unos 3 minutos (abrirla ya pidió la descarga).
///
/// Uso: `@State private var lector: LectorNota` creado con la ruta y la sesión, y
/// `.task(id: sesion.revision) { await lector.cargar() }`.
@Observable @MainActor
public final class LectorNota {
    public let ruta: VaultPath
    /// `nil` mientras se lee la primera vez.
    public private(set) var nota: NoteSnapshot?
    /// Sigue solo en iCloud tras esperar: la pantalla lo explica y ofrece «Volver a intentarlo».
    public private(set) var sinLlegarDeICloud = false

    @ObservationIgnored private let sesion: VaultSession
    @ObservationIgnored private var revisionLeida = -1
    @ObservationIgnored private var reintentos: Task<Void, Never>?

    public init(ruta: VaultPath, sesion: VaultSession) {
        self.ruta = ruta
        self.sesion = sesion
    }

    /// Lee si no se ha leído o si el último cambio pudo tocar esta ruta.
    public func cargar() async {
        let rev = sesion.revision
        let afectada = sesion.ultimasCambiadas.isEmpty || sesion.ultimasCambiadas.contains(ruta)
        guard nota == nil || (rev != revisionLeida && afectada) else { revisionLeida = rev; return }
        revisionLeida = rev
        guard let leida = await sesion.leer(ruta) else { return }
        // Una lectura cancelada (la pantalla se fue o llegó otra revisión) o que empezó antes que la que ya
        // se tiene no sustituye a la buena.
        guard !Task.isCancelled, leida.lectura > (nota?.lectura ?? Int.min) else { return }
        nota = leida
        if case .notDownloaded? = leida.content {
            if reintentos == nil, !sinLlegarDeICloud { esperarICloud() }
        } else {
            reintentos?.cancel()
            reintentos = nil
            sinLlegarDeICloud = false
        }
    }

    /// «Volver a intentarlo».
    public func reintentar() {
        sinLlegarDeICloud = false
        reintentos?.cancel()
        reintentos = nil
        nota = nil
        Task { await cargar() }
    }

    private func esperarICloud() {
        reintentos = Task { [weak self] in
            for _ in 0..<VaultSession.downloadAttempts {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                guard let leida = await self.sesion.leer(self.ruta) else { return }
                self.nota = leida
                if case .notDownloaded? = leida.content { continue }
                self.reintentos = nil
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.sinLlegarDeICloud = true
            self.reintentos = nil
        }
    }
}
