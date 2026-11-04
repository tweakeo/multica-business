import Foundation

// Permisos del sistema que pide la app en F5 (PLAN §8 «Permisos (TCC)»): la explicación va SIEMPRE antes del aviso de
// macOS, hay una pantalla de recuperación con enlace a Ajustes del Sistema y el estado se ve en Conexiones.
//
// | Permiso | Para qué | Qué nunca hace la app |
// |---|---|---|
// | Automatización de Mail | Leer el correo nuevo de la cuenta que elijas y abrir la redacción rellena al aprobar | Enviar, marcar como leído, mover ni borrar |
// | Calendarios | Poner rituales y sesiones en el calendario «The Last System» y ver tus huecos | Invitar a nadie ni leer los títulos de los demás calendarios |
// | Notificaciones | Avisarte de lo rojo (como mucho 3 avisos no rojos al día) | Avisar de lo que puede esperar al resumen |

/// Un permiso del sistema que usa la app.
public enum PermisoDelSistema: String, Sendable, Hashable, CaseIterable, Codable {
    case automatizacionMail = "automatizacion_mail"
    case calendarios
    case notificaciones

    /// Nombre en pantalla.
    public var titulo: String {
        switch self {
        case .automatizacionMail: "Mail"
        case .calendarios: "Calendario"
        case .notificaciones: "Avisos"
        }
    }

    /// Cómo lo llama macOS en Ajustes del Sistema (para que la persona lo encuentre).
    public var nombreEnAjustes: String {
        switch self {
        case .automatizacionMail: "Privacidad y seguridad › Automatización › The Last System › Mail"
        case .calendarios: "Privacidad y seguridad › Calendarios › The Last System"
        case .notificaciones: "Notificaciones › The Last System"
        }
    }

    /// Enlace directo a su panel de Ajustes del Sistema.
    public var enlaceAjustes: URL {
        switch self {
        case .automatizacionMail: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        case .calendarios: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        case .notificaciones: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        }
    }

    /// La explicación que se enseña **antes** de que macOS pregunte (lenguaje llano, sin jerga).
    public var explicacion: ExplicacionDePermiso {
        switch self {
        case .automatizacionMail:
            ExplicacionDePermiso(
                permiso: self,
                titulo: "Dejar que la app lea tu correo nuevo en Mail",
                para: "Para que el Cartero sepa qué ha llegado: cada 15 minutos, con Mail abierto, la app mira la bandeja de entrada de la cuenta que elijas; cada mañana el Cartero lo clasifica y lo apunta en tu Buzón.",
                hace: [
                    "Lee el remitente, el asunto y el principio de cada correo nuevo (unas pocas líneas).",
                    "De los adjuntos solo ve el nombre y el tamaño.",
                    "Cuando apruebas un correo, abre en Mail la redacción ya rellena.",
                ],
                nunca: [
                    "Enviar nada: el botón Enviar lo pulsas tú.",
                    "Marcar como leído, mover ni borrar ningún correo.",
                    "Leer los correos de los remitentes que marques como privados.",
                ],
                queVeras: "Ahora macOS te preguntará si The Last System puede controlar Mail. Pulsa «Permitir».",
                boton: "Continuar")
        case .calendarios:
            ExplicacionDePermiso(
                permiso: self,
                titulo: "Dejar que la app use tu Calendario",
                para: "Para poner tus rituales y las sesiones con clientes en un calendario propio, «The Last System», y saber qué huecos tienes libres.",
                hace: [
                    "Crea y actualiza eventos solo en el calendario «The Last System».",
                    "De tus otros calendarios solo mira cuándo estás ocupado, sin títulos.",
                ],
                nunca: [
                    "Invitar a nadie: invitar sería enviar.",
                    "Cambiar ni borrar eventos de tus otros calendarios.",
                ],
                queVeras: "Ahora macOS te preguntará si The Last System puede acceder a tus calendarios. Pulsa «Permitir acceso total».",
                boton: "Continuar")
        case .notificaciones:
            ExplicacionDePermiso(
                permiso: self,
                titulo: "Dejar que la app te avise",
                para: "Para avisarte de lo que no puede esperar: lo rojo, siempre; lo demás, como mucho tres avisos al día.",
                hace: ["Te avisa de lo rojo y de lo que espera tu decisión."],
                nunca: ["Avisarte de lo que puede esperar al resumen de la semana."],
                queVeras: "Ahora macOS te preguntará si The Last System puede enviarte notificaciones. Pulsa «Permitir».",
                boton: "Continuar")
        }
    }

    /// Lo que se enseña si el permiso está denegado o restringido (pantalla de recuperación).
    public var recuperacion: RecuperacionDePermiso {
        let pasos = [
            "Pulsa «Abrir Ajustes del Sistema».",
            "Ve a \(nombreEnAjustes).",
            "Activa el interruptor y vuelve a la app.",
        ]
        return switch self {
        case .automatizacionMail:
            RecuperacionDePermiso(
                permiso: self, titulo: "La app no tiene permiso para usar Mail",
                texto: "Sin este permiso, el Cartero no puede ver el correo nuevo y al aprobar un correo no se abre la redacción en Mail. Nada se ha enviado ni se ha tocado en tu correo.",
                pasos: pasos, boton: "Abrir Ajustes del Sistema", enlace: enlaceAjustes)
        case .calendarios:
            RecuperacionDePermiso(
                permiso: self, titulo: "La app no tiene permiso para usar tu Calendario",
                texto: "Sin este permiso, tus rituales y sesiones no aparecen en Calendario. Las fichas siguen igual en tu carpeta.",
                pasos: pasos, boton: "Abrir Ajustes del Sistema", enlace: enlaceAjustes)
        case .notificaciones:
            RecuperacionDePermiso(
                permiso: self, titulo: "La app no puede avisarte",
                texto: "Lo rojo seguirá saliendo en Hoy y en Decisiones, pero no te llegará ningún aviso.",
                pasos: pasos, boton: "Abrir Ajustes del Sistema", enlace: enlaceAjustes)
        }
    }
}

/// Estado de un permiso del sistema.
public enum EstadoDePermiso: String, Sendable, Hashable, Codable {
    /// macOS aún no ha preguntado: se enseña la explicación y luego se pide.
    case sinPreguntar = "sin_preguntar"
    case concedido
    /// La persona dijo que no (o lo quitó en Ajustes): pantalla de recuperación, sin volver a preguntar.
    case denegado
    /// Lo impide una configuración del Mac (perfil de empresa, control parental).
    case restringido
    /// No se puede saber ahora (Mail cerrado, por ejemplo).
    case desconocido

    /// En pantalla (Conexiones).
    public var texto: String {
        switch self {
        case .sinPreguntar: "Sin conectar"
        case .concedido: "Conectado"
        case .denegado: "Sin permiso"
        case .restringido: "Bloqueado en este Mac"
        case .desconocido: "Sin comprobar"
        }
    }

    /// Hay que enseñar la recuperación (no se puede volver a preguntar desde la app).
    public var necesitaRecuperacion: Bool { self == .denegado || self == .restringido }
}

/// La explicación previa de un permiso. Solo existe una «vista» si se ha enseñado (ver `PuertaDePermisos`).
public struct ExplicacionDePermiso: Sendable, Hashable {
    public let permiso: PermisoDelSistema
    public let titulo: String
    /// Para qué sirve, en una frase.
    public let para: String
    /// Qué hace la app con él.
    public let hace: [String]
    /// Qué no hace nunca.
    public let nunca: [String]
    /// Qué va a ver la persona a continuación (el aviso de macOS).
    public let queVeras: String
    /// Texto del botón que lanza la pregunta de macOS.
    public let boton: String
}

/// Pantalla de recuperación de un permiso denegado.
public struct RecuperacionDePermiso: Sendable, Hashable {
    public let permiso: PermisoDelSistema
    public let titulo: String
    public let texto: String
    public let pasos: [String]
    public let boton: String
    /// Enlace a Ajustes del Sistema.
    public let enlace: URL
}
