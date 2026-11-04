import AppKit
import CoreServices
import EventKit
import Foundation
import UserNotifications

/// Lo real: Apple Events (Automatización de Mail), EventKit (Calendarios) y el centro de notificaciones. **Solo lo crea
/// la app**; las pruebas usan un doble y nunca tocan TCC (PLAN §8: la explicación va antes de cada aviso).
public struct ConsultorDePermisosDelSistema: ConsultorDePermisos {
    /// `com.apple.mail`.
    public static let mail = "com.apple.mail"

    public init() {}

    public func estado(_ p: PermisoDelSistema) async -> EstadoDePermiso {
        switch p {
        case .automatizacionMail: await Self.automatizacion(Self.mail, preguntar: false)
        case .calendarios: Self.calendario(EKEventStore.authorizationStatus(for: .event))
        case .notificaciones: await Self.notificaciones(UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        }
    }

    public func pedir(_ p: PermisoDelSistema) async -> EstadoDePermiso {
        switch p {
        case .automatizacionMail:
            return await Self.automatizacion(Self.mail, preguntar: true)
        case .calendarios:
            _ = try? await EKEventStore().requestFullAccessToEvents()
            return Self.calendario(EKEventStore.authorizationStatus(for: .event))
        case .notificaciones:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return await estado(.notificaciones)
        }
    }

    /// `AEDeterminePermissionToAutomateTarget` fuera del hilo principal (preguntar puede bloquear hasta que contestes).
    static func automatizacion(_ bundleID: String, preguntar: Bool) async -> EstadoDePermiso {
        await Task.detached(priority: .userInitiated) { () -> EstadoDePermiso in
            var desc = AEAddressDesc()
            let creado = bundleID.withCString { p in
                AECreateDesc(DescType(typeApplicationBundleID), p, strlen(p), &desc)
            }
            guard creado == noErr else { return .desconocido }
            defer { AEDisposeDesc(&desc) }
            let r = AEDeterminePermissionToAutomateTarget(&desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), preguntar)
            return Self.automatizacion(status: r)
        }.value
    }

    /// Traducción de los códigos de Apple Events.
    public static func automatizacion(status: OSStatus) -> EstadoDePermiso {
        switch Int(status) {
        case Int(noErr): .concedido
        case Int(errAEEventNotPermitted): .denegado              // -1743
        case Int(errAEEventWouldRequireUserConsent): .sinPreguntar // -1744
        case Int(procNotFound): .desconocido                     // -600: Mail cerrado
        default: .desconocido
        }
    }

    static func calendario(_ s: EKAuthorizationStatus) -> EstadoDePermiso {
        switch s {
        case .fullAccess: .concedido
        case .notDetermined: .sinPreguntar
        case .denied, .writeOnly: .denegado
        case .restricted: .restringido
        @unknown default: .desconocido
        }
    }

    static func notificaciones(_ s: UNAuthorizationStatus) -> EstadoDePermiso {
        switch s {
        case .authorized, .provisional, .ephemeral: .concedido
        case .notDetermined: .sinPreguntar
        case .denied: .denegado
        @unknown default: .desconocido
        }
    }
}

/// Abre Ajustes del Sistema en el panel del permiso (botón de la recuperación).
@MainActor
public enum AjustesDelSistema {
    @discardableResult
    public static func abrir(_ p: PermisoDelSistema) -> Bool {
        NSWorkspace.shared.open(p.enlaceAjustes)
    }
}
