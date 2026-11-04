import Foundation
import TLSCore

/// Calcula qué rutinas tocan (PLAN §5.3 y §9 F4): las de `config.yaml › agentes.<slug>.rutinas` (o las de serie del
/// catálogo si el asistente no trae ninguna).
///
/// - Se recalcula al despertar el Mac y cada minuto, nunca con temporizadores que se pierden al dormir.
/// - De las perdidas solo cuenta **la última dentro de su ventana** (`ventana_perdida_h`).
/// - Dos disparos del mismo hueco dan una sola ejecución (la clave `rutina:<slug>.<id>:<hueco>` es UNIQUE).
/// - No dispara con el interruptor apagado, ni para un asistente inactivo, ni para una rutina inactiva o en
///   autopausa, ni en un área en pausa, preparada o en reposo.
public struct RoutineScheduler: Sendable {
    public var zona: TimeZone
    /// Margen mínimo para un hueco recién pasado aunque la ventana sea 0 (el reloj se mira cada minuto).
    public static let margenMinimo: TimeInterval = 15 * 60

    public init(zona: TimeZone) { self.zona = zona }

    var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        return c
    }

    /// El hueco de un día (`nil` si ese día no toca).
    public func hueco(_ r: RutinaDeAsistente, dia: LocalDate) -> Date? {
        guard r.toca(dia) else { return nil }
        var c = DateComponents()
        c.year = dia.year; c.month = dia.month; c.day = dia.day; c.hour = r.hora; c.minute = r.minuto
        return calendario.date(from: c)
    }

    /// El último hueco ≤ `ahora` que aún está dentro de su ventana (`nil` si no hay ninguno).
    public func ultimoHueco(_ r: RutinaDeAsistente, ahora: Date) -> Date? {
        let ventana = max(r.ventanaPerdidaH * 3600, Self.margenMinimo)
        let hoy = LocalDate(date: ahora, timeZone: zona)
        let dias = Int((ventana / 86_400).rounded(.up)) + 1
        for atras in 0...dias {
            let dia = hoy.adding(days: -atras, timeZone: zona)
            guard let h = hueco(r, dia: dia) else { continue }
            if h > ahora { continue }
            return ahora.timeIntervalSince(h) <= ventana ? h : nil
        }
        return nil
    }

    /// El siguiente hueco después de `despues` (como mucho un año y un día).
    public func siguienteHueco(_ r: RutinaDeAsistente, despues: Date) -> Date? {
        let hoy = LocalDate(date: despues, timeZone: zona)
        for adelante in 0...366 {
            if let h = hueco(r, dia: hoy.adding(days: adelante, timeZone: zona)), h > despues { return h }
        }
        return nil
    }

    /// Rutinas de un asistente: las de `config.yaml`, o las de serie si no trae ninguna.
    public static func rutinas(de a: AjustesDeAsistente, catalogo: any CatalogoDeAsistentes) -> [RutinaDeAsistente] {
        a.rutinas.isEmpty ? (catalogo.rol(a.slug)?.rutinasDeSerie ?? []) : a.rutinas
    }

    /// ¿Puede trabajar ahora este asistente? (activo, área sin pausa y activa o sin estado).
    public static func puedeTrabajar(_ a: AjustesDeAsistente, ajustes: AjustesDeAsistentes,
                                     areas: [AreaCode: AreaStatus]) -> Bool {
        guard ajustes.interruptor, a.activo else { return false }
        guard let area = a.areaPropia else { return true }
        if ajustes.pausaAreas.contains(area) { return false }
        if let s = areas[area], s == .preparada || s == .reposo { return false }
        return true
    }

    /// Los disparos de rutina que tocan ahora.
    public func pendientes(ajustes: AjustesDeAsistentes, catalogo: any CatalogoDeAsistentes, ahora: Date,
                           pausadas: Set<String>, areas: [AreaCode: AreaStatus]) -> [Disparo] {
        var out: [Disparo] = []
        for a in ajustes.activos where Self.puedeTrabajar(a, ajustes: ajustes, areas: areas) {
            for r in Self.rutinas(de: a, catalogo: catalogo) where r.activa && !pausadas.contains("\(a.slug).\(r.id)") {
                if let h = ultimoHueco(r, ahora: ahora) {
                    out.append(Disparo.rutina(r, agente: a.slug, hueco: h, zona: zona))
                }
            }
        }
        return out
    }

    /// El próximo hueco de cualquier rutina (para saber cuándo volver a mirar).
    public func proximo(ajustes: AjustesDeAsistentes, catalogo: any CatalogoDeAsistentes, despues: Date) -> Date? {
        var mejor: Date?
        for a in ajustes.activos {
            for r in Self.rutinas(de: a, catalogo: catalogo) where r.activa {
                if let h = siguienteHueco(r, despues: despues), mejor.map({ h < $0 }) ?? true { mejor = h }
            }
        }
        return mejor
    }
}
