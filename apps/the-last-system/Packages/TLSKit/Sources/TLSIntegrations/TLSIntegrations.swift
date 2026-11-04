import Foundation

// F5 · «Conexiones» (PLAN §7 y §9 F5): lo que la app conecta del Mac, cada pieza en su carpeta.
//
// | Carpeta | Qué hay | Rol |
// |---|---|---|
// | `Permisos/` | Estado de cada permiso del sistema (Automatización de Mail, Calendarios, Notificaciones), la explicación previa en lenguaje llano y la pantalla de recuperación | mail |
// | `Mail/` | `LectorDeCorreo` (JXA lanzado por la app, fuera del sandbox de asistentes), almacén fuera de la carpeta, cursor, filtro de lo privado, `MailComposer` y la conexión del Cartero | mail |
// | `Calendario/` | EventKit, calendario propio y bloques de ocupado | calendario |
//
// Nada de esto se usa de verdad en pruebas: todo lo del sistema va detrás de un protocolo con su doble.

/// Versión de los contratos de este módulo (`docs/F5-CONTRATOS.md`).
public enum TLSIntegrations {
    public static let contratos = "F5"
}
