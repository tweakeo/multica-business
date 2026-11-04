import Foundation
import TLSCore

// F5 · rol calendario: Hoy lee lo ocupado del Calendario del Mac («Lo que cabe hoy», «Hoy tienes 3 h de 4» y la semana
// frente al tope). TLSUI no conoce EventKit: la app le pasa la fuente (`SincronizadorCalendario.fuenteDeOcupado`), que
// solo da bloques «Ocupado» de los **otros** calendarios, sin títulos ni asistentes. Sin fuente, Hoy sigue como en F2.

/// Conecta (o desconecta) el Calendario con Hoy de una empresa abierta.
@MainActor
public enum CalendarioEnHoy {
    /// Pone la fuente de lo ocupado y rehace Hoy. `nil` = Calendario desconectado (o sin permiso).
    public static func conectar(_ sesion: VaultSession,
                                ocupado: (@Sendable (LocalDate, LocalDate) async -> [EventoAgenda])?) async {
        let almacen = AlmacenHoy.de(sesion)
        almacen.ocupado = ocupado
        await almacen.actualizar(forzar: true)
    }

    /// Rehace Hoy porque cambió algo en el Calendario (la app escucha `EKEventStoreChanged`).
    public static func calendarioCambio(_ sesion: VaultSession) async {
        await AlmacenHoy.de(sesion).actualizar(forzar: true)
    }
}

extension AlmacenHoy {
    /// Lo ocupado de la semana de hoy (lunes a domingo), en el día de la carpeta. Sin fuente, nada.
    nonisolated static func ocupadoDeLaSemana(foto: VaultSnapshot,
                                              fuente: (@Sendable (LocalDate, LocalDate) async -> [EventoAgenda])?) async -> [EventoAgenda] {
        guard let fuente else { return [] }
        let config = ConfigMetricas.leer(foto.text(VaultPath(".tls/config.yaml")))
        let zona = TimeZone(identifier: config.zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
        let lunes = FormatoBase.lunes(de: Reloj.deCarpeta(foto, zona: zona).hoy)
        return await fuente(lunes, lunes.adding(days: 6))
    }
}
