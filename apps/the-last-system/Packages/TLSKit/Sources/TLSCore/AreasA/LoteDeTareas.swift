import Foundation

// Rol areas-a (F2, fase de pantallas). Carpeta propia en TLSCore con lo imprescindible para las pantallas de
// Operación de Dirección, Ventas y Entrega (anotado en docs/F2-CONTRATOS.md, «Cambios pedidos»).

/// Varias tareas en **un solo plan** (todo o nada, un solo Deshacer), con números seguidos: la puerta pública de
/// `TareasEnLote` (rol de dominio), que las pantallas necesitan para «Plan de 4 semanas para el cuello». Cada
/// ficha sale igual que con `TaskStore.crear`; el contador de `.tls/secuencias.json` sube una sola vez.
public enum LoteDeTareas {
    /// - Returns: el plan y las rutas nuevas, o `nil` si no hay ninguna tarea.
    public static func preparar(_ nuevas: [NuevaTarea], snapshot: VaultSnapshot, reloj: Reloj? = nil, autor: Autor,
                                descripcion: String) throws -> (plan: WritePlan, rutas: [VaultPath])? {
        try TareasEnLote.preparar(nuevas, snapshot: snapshot, reloj: reloj ?? Reloj.deCarpeta(snapshot), autor: autor,
                                  descripcion: descripcion)
    }
}
