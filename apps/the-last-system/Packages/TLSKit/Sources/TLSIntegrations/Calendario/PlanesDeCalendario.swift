import Foundation
import TLSCore

// Lo único que el Calendario puede pedir que se escriba en la carpeta, siempre como plan que decide la persona y que
// pasa por el `CommandBus` (Actividad, Bitácora, Deshacer; nunca borra). La app nunca lo aplica sola.

public enum PlanesDeCalendario {
    /// «Actualizar la ficha»: lo que cambiaste en Calendario, a la ficha. Solo lo que cambió y se puede escribir.
    /// - Rutina: `nombre`, `cadencia`/`dia`, `hora`, `duracion_min` (propiedades: `mergeFrontmatter`).
    /// - Sesión: la celda «Fecha» de su fila del Viaje (`AAAA-MM-DD HH:MM`, o solo la fecha si es de todo el día).
    public static func actualizarFicha(_ d: EventoDeseado, con actual: EventoDelCalendario, zona: TimeZone,
                                       persona: String) -> WritePlan? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.hour, .minute], from: actual.inicio)
        let hora = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        switch d.tipo {
        case .rutina:
            var poner: [Property] = []
            let ficha = d.evento
            if actual.titulo.trimmingCharacters(in: .whitespaces) != ficha.titulo.trimmingCharacters(in: .whitespaces),
               !actual.titulo.trimmingCharacters(in: .whitespaces).isEmpty {
                poner.append(Property(key: "nombre", value: .text(actual.titulo.trimmingCharacters(in: .whitespaces))))
            }
            if let rep = actual.repeticion, rep != ficha.repeticion {
                switch rep {
                case .semanal(let w):
                    poner.append(Property(key: "cadencia", value: .text("semanal")))
                    poner.append(Property(key: "dia", value: .text(TextosCalendario.diasConTilde[max(0, min(6, w - 1))])))
                case .mensual(let n, let cada):
                    guard cada == 1 || cada == 3 else { break }
                    poner.append(Property(key: "cadencia", value: .text(cada == 3 ? "trimestral" : "mensual")))
                    poner.append(Property(key: "dia", value: .number("\(n)")))
                }
            }
            if !actual.todoElDia, TextosCalendario.hora(actual, zona: zona) != TextosCalendario.hora(ficha, zona: zona) {
                poner.append(Property(key: "hora", value: .text(hora)))
            }
            if !actual.todoElDia, actual.minutos > 0, actual.minutos != ficha.minutos {
                poner.append(Property(key: "duracion_min", value: .number("\(actual.minutos)")))
            }
            guard !poner.isEmpty else { return nil }
            return WritePlan(autor: .persona(persona), descripcion: "Actualizar la rutina «\(ficha.titulo)» con lo de Calendario",
                             ops: [.mergeFrontmatter(d.ruta, set: poner, unset: [])])
        case .sesion:
            guard let celda = d.celdaSesion else { return nil }
            let dia = LocalDate(date: actual.inicio, timeZone: zona)
            let fecha = actual.todoElDia ? dia.description : "\(dia.description) \(hora)"
            guard HuellaEvento.de(actual, zona: zona).split(separator: "|").prefix(2)
                    != HuellaEvento.de(d.evento, zona: zona).split(separator: "|").prefix(2) else { return nil }
            return WritePlan(autor: .persona(persona), descripcion: "Cambiar la fecha de «\(d.evento.titulo)» en el Viaje",
                             ops: [.setTableCells(d.ruta, table: PortalDocumento.tablaViaje, keyColumn: "Sesión", keyValue: celda,
                                                  cells: ["Fecha": fecha])])
        }
    }

    /// «Quitarla del Calendario»: la rutina deja de pedir evento (`calendario: false`). La ficha se queda.
    public static func dejarDeApuntar(_ ruta: VaultPath, persona: String) -> WritePlan {
        WritePlan(autor: .persona(persona), descripcion: "Dejar de apuntar la rutina en Calendario",
                  ops: [.mergeFrontmatter(ruta, set: [Property(key: "calendario", value: .bool(false))], unset: [])])
    }

    /// Paso 5 de la puesta en marcha: la rutina semanal de Dirección (la que crea o completa ese paso) pasa a
    /// `calendario: true` si tiene día y hora y aún no lo pide. `nil` si no hay nada que marcar.
    public static func apuntarRutinaDeLaPuesta(foto: VaultSnapshot, persona: String) -> WritePlan? {
        let layout = foto.layout
        let dir = layout.dir(for: "routine") ?? layout.areaFolder(.direccion).appending("Rutinas")
        for p in foto.notes.sorted() where p.parent == dir && EventosDeLaCarpeta.visible(p, layout: layout) {
            let fm = foto.frontmatter(p)
            guard fm.text("tls_type") == "routine", TextFolding.fold(fm.text("cadencia") ?? "semanal") == "semanal" else { continue }
            guard !EventosDeLaCarpeta.quiereCalendario(fm), EventosDeLaCarpeta.activa(fm),
                  EventosDeLaCarpeta.repeticion(cadencia: fm.text("cadencia"), dia: fm.text("dia")) != nil,
                  fm.text("hora").flatMap(FormatoBase.hora) != nil else { return nil }
            return WritePlan(autor: .persona(persona), descripcion: "Apuntar la rutina semanal en Calendario",
                             ops: [.mergeFrontmatter(p, set: [Property(key: "calendario", value: .bool(true))], unset: [])])
        }
        return nil
    }
}
