import Foundation
import TLSCore

// La dirección es de ficheros a calendario (PLAN §7.2): de la foto de la carpeta salen los eventos que **deberían**
// estar en «The Last System». Puro y determinista: se prueba sin Calendario.
//
// - Rituales: rutinas humanas (`tls_type: routine`, en `1 · Dirección/Rutinas/<slug>.md`) con `calendario: true`,
//   activas, con día y hora. Semanales por su día; mensuales y trimestrales por el día del mes. Recurrentes, sin fin.
// - Sesiones S1–S9: filas del Viaje (`## Viaje` de `Portal.md` o de la ficha del proyecto) con fecha y que no estén
//   «No incluida». Con hora («2026-10-22 10:00») duran una hora; sin hora, son de todo el día.
// - Lo privado, lo archivado (`Archivo/`) y las plantillas nunca salen. Retirar la ficha = deja de estar aquí.

/// Un evento que la carpeta pide en nuestro calendario.
public struct EventoDeseado: Sendable, Hashable, Identifiable {
    public enum Tipo: String, Sendable, Hashable, Codable {
        case rutina, sesion
    }

    public var id: String { clave }
    /// `tls://<tipo>/<id>` (también es la `url` del evento y la clave de `mapa_calendario`).
    public let clave: String
    public let tipo: Tipo
    /// La ficha de la que sale: la rutina, o el `Portal.md` (o la ficha del proyecto) con el Viaje.
    public let ruta: VaultPath
    /// Sesión: la celda «Sesión» de su fila (la clave para cambiar la fila).
    public let celdaSesion: String?
    public let evento: EventoDelCalendario

    public init(clave: String, tipo: Tipo, ruta: VaultPath, celdaSesion: String?, evento: EventoDelCalendario) {
        self.clave = clave; self.tipo = tipo; self.ruta = ruta; self.celdaSesion = celdaSesion; self.evento = evento
    }
}

public enum EventosDeLaCarpeta {
    /// El nombre de nuestro calendario.
    public static let nombreCalendario = "The Last System"
    /// Si la rutina no dice cuánto dura (no se inventan horas en la agenda, pero el evento necesita un fin).
    public static let minutosRutinaSinDuracion = 30
    public static let minutosSesion = 60

    /// `tls://rutina/<id>`, `tls://sesion/<id>` (el id, con los caracteres de ruta escapados).
    public static func url(_ tipo: EventoDeseado.Tipo, _ id: String) -> URL {
        var permitidos = CharacterSet.urlPathAllowed
        permitidos.remove(charactersIn: "?#")
        let limpio = id.addingPercentEncoding(withAllowedCharacters: permitidos) ?? id
        return URL(string: "tls://\(tipo.rawValue)/\(limpio)") ?? URL(string: "tls://\(tipo.rawValue)/sin-id")!
    }

    /// La zona de la carpeta (`agenda.zona` de `.tls/config.yaml`; Madrid por defecto).
    public static func zona(_ foto: VaultSnapshot) -> TimeZone {
        let c = ConfigMetricas.leer(foto.text(VaultPath(".tls/config.yaml")))
        return TimeZone(identifier: c.zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
    }

    /// Lo que la carpeta pide hoy.
    /// - Parameter anclas: por clave, el día desde el que ya se apuntó cada ritual (`mapa_calendario.ancla`): así el
    ///   inicio de la serie no se mueve cada día. Sin ancla, desde `hoy`.
    public static func deseados(foto: VaultSnapshot, hoy: LocalDate, zona: TimeZone,
                                anclas: [String: LocalDate] = [:]) -> [EventoDeseado] {
        let layout = foto.layout
        var out: [EventoDeseado] = []
        var vistas = Set<String>()
        for p in foto.notes where visible(p, layout: layout) {
            guard let texto = foto.text(p) else { continue }
            let doc = NoteDocument(text: texto)
            let fm = doc.frontmatter
            let kind = NoteKindResolver.kind(of: p, frontmatter: fm, layout: layout)
            switch kind {
            case .routine:
                if let e = rutina(p, fm: fm, titulo: doc.title(fileStem: p.stem, frontmatter: fm), hoy: hoy, zona: zona,
                                  anclas: anclas), vistas.insert(e.clave).inserted {
                    out.append(e)
                }
            case .portal, .project:
                // Como Entrega: si el proyecto tiene `Portal.md`, el Viaje que cuenta es el del portal.
                if kind == .project, tienePortal(p, foto: foto) { continue }
                let portal = PortalDocumento.leer(texto, ruta: p)
                guard portal.tieneViaje else { continue }
                for e in sesiones(portal, ruta: p, fm: fm, zona: zona) where vistas.insert(e.clave).inserted {
                    out.append(e)
                }
            default:
                continue
            }
        }
        return out.sorted { $0.clave < $1.clave }
    }

    static func visible(_ p: VaultPath, layout: VaultLayout) -> Bool {
        !layout.isPrivate(p) && !layout.isArchived(p) && !VaultSnapshot.isTemplatePath(p)
    }

    // MARK: Rituales

    /// `calendario: true` (o «sí»). Lo que no lo dice no va al Calendario.
    static func quiereCalendario(_ fm: Frontmatter) -> Bool {
        switch fm.value("calendario") {
        case .bool(let b)?: return b
        case .text(let s)?, .raw(let s)?: return ["true", "si", "sí", "yes"].contains(TextFolding.fold(s))
        default: return false
        }
    }

    static func activa(_ fm: Frontmatter) -> Bool {
        switch fm.value("activa") {
        case .bool(let b)?: return b
        case .text(let s)?: return !["false", "no"].contains(TextFolding.fold(s))
        default: return true
        }
    }

    static let diasSemana = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
    static let diasCortos = ["lun", "mar", "mie", "jue", "vie", "sab", "dom"]

    /// La repetición de una rutina por su cadencia y su día (`nil` si no se entiende).
    public static func repeticion(cadencia: String?, dia: String?) -> RepeticionEvento? {
        guard let dia = dia?.trimmingCharacters(in: .whitespaces), !dia.isEmpty else { return nil }
        let cad = TextFolding.fold(cadencia ?? "semanal")
        if cad.hasPrefix("mensual") || cad.hasPrefix("trimestral") {
            guard let n = Int(dia), (1...31).contains(n) else { return nil }
            return .mensual(diaMes: n, cadaMeses: cad.hasPrefix("trimestral") ? 3 : 1)
        }
        let f = TextFolding.fold(dia)
        guard let i = diasSemana.firstIndex(of: f) ?? diasCortos.firstIndex(of: f) else { return nil }
        return .semanal(diaSemana: i + 1)
    }

    static func rutina(_ p: VaultPath, fm: Frontmatter, titulo: String, hoy: LocalDate, zona: TimeZone,
                       anclas: [String: LocalDate]) -> EventoDeseado? {
        guard quiereCalendario(fm), activa(fm),
              let rep = repeticion(cadencia: fm.text("cadencia"), dia: fm.text("dia")),
              let h = fm.text("hora").flatMap(FormatoBase.hora) else { return nil }
        let id = fm.text("id").flatMap { $0.isEmpty || $0.contains("{{") ? nil : $0 } ?? TextFolding.pathKey(p.stem)
        let url = url(.rutina, id)
        let clave = url.absoluteString
        let minutos = fm.text("duracion_min").flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            .map { Int($0.rounded()) }.flatMap { $0 > 0 ? $0 : nil } ?? minutosRutinaSinDuracion
        let desde = anclas[clave] ?? hoy
        guard let dia = primerDia(rep, desde: desde, zona: zona),
              let inicio = fecha(dia, hora: h.hora, minuto: h.minuto, zona: zona) else { return nil }
        let nombre = fm.text("nombre").flatMap { $0.isEmpty || $0.contains("{{") ? nil : $0 } ?? titulo
        let ev = EventoDelCalendario(titulo: nombre, inicio: inicio, fin: inicio.addingTimeInterval(Double(minutos) * 60),
                                     repeticion: rep, url: url,
                                     notas: "Rutina de The Last System. Se cambia en su ficha: \(p.raw)")
        return EventoDeseado(clave: clave, tipo: .rutina, ruta: p, celdaSesion: nil, evento: ev)
    }

    /// El primer día desde `desde` (incluido) en que toca.
    static func primerDia(_ r: RepeticionEvento, desde: LocalDate, zona: TimeZone) -> LocalDate? {
        var d = desde
        for _ in 0..<400 {
            switch r {
            case .semanal(let w): if diaSemana(d, zona: zona) == w { return d }
            case .mensual(let n, let cada):
                if d.day == n, cada != 3 || [1, 4, 7, 10].contains(d.month) { return d }
            }
            d = d.adding(days: 1, timeZone: zona)
        }
        return nil
    }

    /// 1 = lunes … 7 = domingo, en la zona de la carpeta.
    static func diaSemana(_ d: LocalDate, zona: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let w = cal.component(.weekday, from: d.date(timeZone: zona))
        return w == 1 ? 7 : w - 1
    }

    static func fecha(_ d: LocalDate, hora: Int, minuto: Int, zona: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day; c.hour = hora; c.minute = minuto
        return cal.date(from: c)
    }

    // MARK: Sesiones S1–S9

    /// El `Portal.md` del proyecto: en su carpeta o en «Portal Cliente/<carpeta>» de Entrega (como `DatosEntrega`).
    static func tienePortal(_ ficha: VaultPath, foto: VaultSnapshot) -> Bool {
        guard let carpeta = ficha.parent else { return false }
        let entrega = foto.layout.areaFolder(.entrega)
        let candidatos = [carpeta.appending("Portal.md"),
                          entrega.appending("Portal Cliente").appending(carpeta.name).appending("Portal.md")]
        return candidatos.contains { c in foto.existing(c).map { visible($0, layout: foto.layout) } ?? false }
    }

    static func sesiones(_ portal: PortalDocumento, ruta: VaultPath, fm: Frontmatter, zona: TimeZone) -> [EventoDeseado] {
        let base = fm.text("id").flatMap { $0.isEmpty || $0.contains("{{") ? nil : $0 } ?? TextFolding.pathKey(ruta.raw)
        let quien = [fm.text("empresa"), fm.text("proyecto"), fm.text("nombre")].compactMap { $0 }
            .map(LinkParser.plainText).first { !$0.isEmpty && !$0.contains("{{") }
            ?? portal.titulo.map { $0.replacingOccurrences(of: "Portal de ", with: "") }
        var out: [EventoDeseado] = []
        for s in portal.sesiones {
            guard let dia = s.fecha, s.estado != .noIncluida else { continue }
            let url = url(.sesion, "\(base)/\(s.codigo)")
            let h = s.fechaTexto.flatMap(horaDeCelda)
            let ev: EventoDelCalendario
            let titulo = quien.map { "\(s.titulo) · \($0)" } ?? s.titulo
            let notas = "Sesión de The Last System. Se cambia en el Viaje: \(ruta.raw)"
            if let h, let inicio = fecha(dia, hora: h.hora, minuto: h.minuto, zona: zona) {
                ev = EventoDelCalendario(titulo: titulo, inicio: inicio, fin: inicio.addingTimeInterval(Double(minutosSesion) * 60),
                                         url: url, notas: notas)
            } else {
                let inicio = dia.date(timeZone: zona)
                ev = EventoDelCalendario(titulo: titulo, inicio: inicio, fin: dia.adding(days: 1, timeZone: zona).date(timeZone: zona),
                                         todoElDia: true, url: url, notas: notas)
            }
            out.append(EventoDeseado(clave: url.absoluteString, tipo: .sesion, ruta: ruta, celdaSesion: s.celdaSesion, evento: ev))
        }
        return out
    }

    /// La hora que va tras la fecha en la celda («2026-10-22 10:00», «2026-10-22 · 9.30»).
    static func horaDeCelda(_ texto: String) -> (hora: Int, minuto: Int)? {
        let resto = texto.trimmingCharacters(in: .whitespaces).dropFirst(10)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ·-–,T"))
        guard !resto.isEmpty else { return nil }
        return FormatoBase.hora(String(resto.prefix(5)))
    }
}

/// La huella de un evento: lo que importa para saber si cambió (título, cuándo, cuánto y cómo se repite), en la zona
/// de la carpeta. Se calcula igual para lo que pide la ficha, lo que se escribió y lo que hay ahora en el Calendario.
public enum HuellaEvento {
    public static func de(_ e: EventoDelCalendario, zona: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: e.inicio)
        let hora = e.todoElDia ? "todo-el-dia" : String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        let cuando: String
        switch e.repeticion {
        case .semanal(let d)?: cuando = "semanal:\(d)"
        case .mensual(let d, let cada)?: cuando = "mensual:\(d)/\(cada)"
        case nil: cuando = String(format: "dia:%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        let minutos = e.todoElDia ? 0 : e.minutos
        return [cuando, hora, "\(minutos)", e.titulo.trimmingCharacters(in: .whitespacesAndNewlines)].joined(separator: "|")
    }
}
