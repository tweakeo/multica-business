import Foundation
import Observation
import SwiftUI
import TLSCore
import TLSDesign

/// El modelo del andamio de un área: lee sus datos (fuera del hilo principal, con la foto compartida de la
/// empresa) cada vez que cambia la carpeta y escribe lo que el andamio deja tocar: Meta y Alerta de `Metas.md`
/// y «Activar». Todo por `CommandBus` como la persona, con Deshacer.
@Observable @MainActor
final class ModeloArea {
    let area: AreaCode
    let sesion: VaultSession
    private(set) var datos: DatosArea?
    private(set) var revisionLeida = -1
    /// El código cuya meta se está escribiendo (Control).
    var editando: String?
    /// Mensaje del último guardado que no se pudo hacer.
    private(set) var errorGuardado: String?
    @ObservationIgnored private var carga: Task<Void, Never>?

    init(area: AreaCode, sesion: VaultSession) {
        self.area = area
        self.sesion = sesion
    }

    /// Relee si la carpeta cambió desde la última vez.
    func cargar() async {
        let revision = sesion.revision
        guard revision != revisionLeida || datos == nil else { return }
        if let carga { await carga.value; if revision == revisionLeida, datos != nil { return } }
        let almacen = AlmacenRelaciones.de(sesion)
        let proveedor = ProveedoresArea.numeros
        let area = self.area
        let tarea = Task { [weak self] in
            await almacen.actualizar()
            guard let self, let foto = almacen.foto else { return }
            let hoy = self.sesion.hoy
            let leidos = await Task.detached(priority: .userInitiated) {
                LectorArea(foto: foto, hoy: hoy, proveedor: proveedor).leer(area)
            }.value
            guard !Task.isCancelled else { return }
            self.datos = leidos
            self.revisionLeida = revision
        }
        carga = tarea
        await tarea.value
        carga = nil
    }

    /// Por qué no se puede escribir ahora (o `nil` si se puede).
    var motivoSoloLectura: String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .soloLectura(let m): m.texto
        case .abriendo: "La carpeta aún se está abriendo"
        }
    }

    // MARK: Meta y alerta

    /// Lo que se puede escribir en una celda de `Metas.md`: una línea, sin barras.
    static func limpiarCelda(_ texto: String) -> String {
        texto.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Escribe Meta y Alerta de un código (solo esas dos celdas de su fila). `meta` vacía = «Sin meta».
    @discardableResult
    func guardarMeta(_ fila: FilaControl, meta: String, alerta: String, deshacer: UndoManager?) async -> Bool {
        errorGuardado = nil
        guard let ruta = datos?.metas else {
            errorGuardado = "No encuentro la nota Metas en Dirección."
            return false
        }
        let m = Self.limpiarCelda(meta)
        let a = Self.limpiarCelda(alerta)
        let celdas = ["Meta": m.isEmpty ? FilaControl.textoSinMeta : m, "Alerta": m.isEmpty ? "" : a]
        let aviso = m.isEmpty ? "\(fila.codigo) queda sin meta" : "Meta de \(fila.codigo): \(m)"
        do {
            let r = try await sesion.escribir(.cambiarCeldas(ruta, tabla: TableSelector(columna: "Código"), columnaClave: "Código",
                                                              valorClave: fila.codigo, celdas: celdas),
                                              aviso: aviso, deshacer: deshacer)
            if case .conflicto = r.estado { errorGuardado = "Metas cambió fuera de la app a la vez. Revísalo en Revisar."; return false }
            editando = nil
            return true
        } catch {
            errorGuardado = error.localizedDescription
            return false
        }
    }

    // MARK: Activar

    /// Pasa el área a activa (`estado: activa` y `activada: <hoy>` en su `Área.md`).
    @discardableResult
    func activar(deshacer: UndoManager?) async -> Bool {
        guard let datos, let ficha = datos.ficha else { return false }
        let poner = [Property(key: "estado", value: .text("activa")),
                     Property(key: "activada", value: .text(datos.hoy.description))]
        do {
            _ = try await sesion.escribir(.cambiarPropiedades(ficha, poner: poner, quitar: []),
                                          aviso: "Activaste \(datos.titulo)", deshacer: deshacer)
            return true
        } catch {
            return false
        }
    }
}
