import Foundation

// Rol areas-a (F2). `Incidencias.md` de un proyecto de entrega (PLAN §4.4, plantilla «Registro de incidencias v1»):
// | ID | Fecha | Quién reporta | Email | Tipo | Severidad | Estado | Descripción | Responsable | Resolución |
// con INC-001 y plazos de respuesta de 24 (grave), 48 (media) y 72 (leve) horas hábiles. Solo se añaden filas.
// Está en TLSCore (carpeta propia del rol) porque ENT-INC («incidencias fuera de plazo») sale de aquí.
//
// Horas hábiles (decisión del rol, PLAN no lo detalla): cuentan las horas de lunes a viernes, enteras; el sábado y el
// domingo no cuentan. Una grave recibida el viernes a las 10:00 vence el lunes a las 10:00. Los festivos no se
// descuentan (aún no hay calendario de festivos). Una fecha sin hora cuenta desde el principio de ese día.

/// Gravedad de una incidencia y su plazo de respuesta.
public enum SeveridadIncidencia: String, Sendable, Hashable, CaseIterable {
    case leve = "Leve"
    case media = "Media"
    case grave = "Grave"

    public init?(leyendo texto: String) {
        switch TextFolding.fold(texto.trimmingCharacters(in: .whitespaces)) {
        case "leve", "baja": self = .leve
        case "media", "normal": self = .media
        case "grave", "alta", "critica", "urgente": self = .grave
        default: return nil
        }
    }

    /// 24 h hábiles la grave, 48 la media y 72 la leve.
    public var horasHabiles: Int {
        switch self {
        case .grave: 24
        case .media: 48
        case .leve: 72
        }
    }
}

/// Estado de una incidencia.
public enum EstadoIncidencia: String, Sendable, Hashable, CaseIterable {
    case recibida = "Recibida"
    case enCurso = "En curso"
    case resuelta = "Resuelta"
    case cerrada = "Cerrada"

    public init?(leyendo texto: String) {
        switch TextFolding.fold(texto.trimmingCharacters(in: .whitespaces)) {
        case "recibida", "nueva", "abierta": self = .recibida
        case "en curso", "en progreso": self = .enCurso
        case "resuelta", "resuelto": self = .resuelta
        case "cerrada", "cerrado": self = .cerrada
        default: return nil
        }
    }

    /// Aún corre el plazo: Recibida o En curso.
    public var abierta: Bool { self == .recibida || self == .enCurso }
}

/// Una fila de `Incidencias.md`.
public struct IncidenciaRegistrada: Sendable, Hashable, Identifiable {
    /// «INC-001».
    public let id: String
    public let ruta: VaultPath?
    public let fechaTexto: String?
    /// Cuándo llegó (con la hora si la dice).
    public let recibida: Date?
    public let quien: String?
    /// Solo para nosotros.
    public let email: String?
    public let tipo: String?
    public let severidad: SeveridadIncidencia?
    public let severidadTexto: String?
    public let estado: EstadoIncidencia?
    public let estadoTexto: String?
    public let descripcion: String?
    /// Solo para nosotros.
    public let responsable: String?
    /// Solo para nosotros.
    public let resolucion: String?

    public init(id: String, ruta: VaultPath?, fechaTexto: String?, recibida: Date?, quien: String?, email: String?, tipo: String?,
                severidad: SeveridadIncidencia?, severidadTexto: String?, estado: EstadoIncidencia?, estadoTexto: String?,
                descripcion: String?, responsable: String?, resolucion: String?) {
        self.id = id; self.ruta = ruta; self.fechaTexto = fechaTexto; self.recibida = recibida; self.quien = quien
        self.email = email; self.tipo = tipo; self.severidad = severidad; self.severidadTexto = severidadTexto
        self.estado = estado; self.estadoTexto = estadoTexto; self.descripcion = descripcion
        self.responsable = responsable; self.resolucion = resolucion
    }

    /// 1 para «INC-001».
    public var numero: Int? {
        guard let r = id.range(of: #"\d+$"#, options: .regularExpression) else { return nil }
        return Int(id[r])
    }

    /// Sigue abierta (o no dice su estado: entonces se trata como recibida).
    public var abierta: Bool { estado?.abierta ?? (estadoTexto == nil) }

    /// Cuándo hay que haber respondido (`nil` sin fecha o sin gravedad).
    public func plazo(zona: TimeZone) -> Date? {
        guard let recibida, let severidad else { return nil }
        return HorasHabiles.sumar(severidad.horasHabiles, a: recibida, zona: zona)
    }

    /// La cuenta atrás (solo si sigue abierta y se sabe su plazo).
    public func cuentaAtras(ahora: Date, zona: TimeZone) -> CuentaAtras? {
        guard abierta, let recibida, let severidad, let plazo = plazo(zona: zona) else { return nil }
        return CuentaAtras(recibida: recibida, plazo: plazo, ahora: ahora, total: severidad.horasHabiles, zona: zona)
    }
}

/// Lo que queda para responder una incidencia, en horas hábiles.
public struct CuentaAtras: Sendable, Hashable {
    public let plazo: Date
    /// Minutos hábiles que quedan (negativo = fuera de plazo desde hace tantos).
    public let minutosRestantes: Int
    /// El plazo entero en horas hábiles (24, 48 o 72).
    public let total: Int
    let zona: TimeZone

    public init(recibida: Date, plazo: Date, ahora: Date, total: Int, zona: TimeZone) {
        self.plazo = plazo
        self.total = total
        self.zona = zona
        let s = ahora <= plazo ? HorasHabiles.segundos(desde: ahora, hasta: plazo, zona: zona)
            : -HorasHabiles.segundos(desde: plazo, hasta: ahora, zona: zona)
        minutosRestantes = Int((s / 60).rounded(.down))
    }

    public var fueraDePlazo: Bool { minutosRestantes < 0 }

    /// Queda una cuarta parte del plazo o menos.
    public var apurada: Bool { !fueraDePlazo && minutosRestantes * 4 <= total * 60 }

    /// «Quedan 23 h hábiles», «Quedan 40 min hábiles», «Fuera de plazo hace 3 h hábiles».
    public var texto: String {
        let m = abs(minutosRestantes)
        let duracion = Self.duracion(m)
        return fueraDePlazo ? "Fuera de plazo hace \(duracion) hábiles" : "Quedan \(duracion) hábiles"
    }

    /// «lun 19 oct, 10:00».
    public var textoPlazo: String {
        let cal = Self.calendario(zona)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: plazo)
        let dia = LocalDate(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
        let dias = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
        let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
        let d = dia.map { "\(dias[$0.weekday - 1]) \($0.day) \(meses[$0.month - 1])" } ?? ""
        return d + String(format: ", %d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// «24 h», «5 h 20 min», «40 min».
    static func duracion(_ minutos: Int) -> String {
        let h = minutos / 60, m = minutos % 60
        if h == 0 { return "\(m) min" }
        if m == 0 || h >= 10 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    static func calendario(_ zona: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        return c
    }
}

/// Horas hábiles: las de lunes a viernes (el día entero); el fin de semana no cuenta.
public enum HorasHabiles {
    static func calendario(_ zona: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        return c
    }

    static func esLaborable(_ d: Date, cal: Calendar) -> Bool {
        let w = cal.component(.weekday, from: d)   // 1 = domingo, 7 = sábado
        return w != 1 && w != 7
    }

    /// `inicio` más `horas` hábiles.
    public static func sumar(_ horas: Int, a inicio: Date, zona: TimeZone) -> Date {
        let cal = calendario(zona)
        var t = inicio
        var resto = TimeInterval(horas) * 3_600
        var vueltas = 0
        while vueltas < 400 {
            vueltas += 1
            let finDelDia = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t)) ?? t.addingTimeInterval(86_400)
            guard esLaborable(t, cal: cal) else { t = finDelDia; continue }
            let cabe = finDelDia.timeIntervalSince(t)
            if resto <= cabe { return t.addingTimeInterval(resto) }
            resto -= cabe
            t = finDelDia
        }
        return t
    }

    /// Segundos hábiles entre dos instantes (0 si `hasta` va antes que `desde`).
    public static func segundos(desde: Date, hasta: Date, zona: TimeZone) -> TimeInterval {
        guard hasta > desde else { return 0 }
        let cal = calendario(zona)
        var t = desde
        var total: TimeInterval = 0
        var vueltas = 0
        while t < hasta, vueltas < 4_000 {
            vueltas += 1
            let finDelDia = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t)) ?? t.addingTimeInterval(86_400)
            let tramo = min(finDelDia, hasta)
            if esLaborable(t, cal: cal) { total += tramo.timeIntervalSince(t) }
            t = tramo
        }
        return total
    }
}

/// `Incidencias.md` leído.
public struct RegistroIncidencias: Sendable, Hashable {
    public let ruta: VaultPath?
    public let filas: [IncidenciaRegistrada]

    /// La tabla del registro: la que tiene la columna «Severidad».
    public static let tabla = TableSelector(columna: "Severidad")
    public static let columnas = ["ID", "Fecha", "Quién reporta", "Email", "Tipo", "Severidad", "Estado", "Descripción",
                                  "Responsable", "Resolución"]

    public init(ruta: VaultPath?, filas: [IncidenciaRegistrada]) {
        self.ruta = ruta
        self.filas = filas
    }

    public static func leer(_ texto: String, ruta: VaultPath? = nil, zona: TimeZone) -> RegistroIncidencias {
        var filas: [IncidenciaRegistrada] = []
        for f in MarkdownTable.rows(in: texto, selector: tabla) ?? [] {
            func v(_ c: String) -> String? { PortalDocumento.valor(f, c) }
            guard let id = v("ID"), !id.contains("{{") else { continue }
            let sev = v("Severidad") ?? v("Gravedad")
            let est = v("Estado")
            filas.append(IncidenciaRegistrada(
                id: id, ruta: ruta, fechaTexto: v("Fecha"), recibida: v("Fecha").flatMap { instante($0, zona: zona) },
                quien: v("Quién reporta"), email: v("Email"), tipo: v("Tipo"),
                severidad: sev.flatMap(SeveridadIncidencia.init(leyendo:)), severidadTexto: sev,
                estado: est.flatMap(EstadoIncidencia.init(leyendo:)), estadoTexto: est, descripcion: v("Descripción"),
                responsable: v("Responsable"), resolucion: v("Resolución")))
        }
        return RegistroIncidencias(ruta: ruta, filas: filas)
    }

    public var abiertas: [IncidenciaRegistrada] { filas.filter(\.abierta) }

    /// Abiertas que ya pasaron su plazo (ENT-INC).
    public func fueraDePlazo(ahora: Date, zona: TimeZone) -> [IncidenciaRegistrada] {
        filas.filter { $0.cuentaAtras(ahora: ahora, zona: zona)?.fueraDePlazo == true }
    }

    /// «2026-10-19 10:30», «2026-10-19T10:30», «19/10/2026 10:30» o solo el día.
    public static func instante(_ texto: String, zona: TimeZone) -> Date? {
        let t = texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "T", with: " ")
        let partes = t.split(separator: " ", omittingEmptySubsequences: true)
        guard let primera = partes.first else { return nil }
        var dia = LocalDate(parsing: String(primera))
        if dia == nil {
            let p = primera.split(separator: "/")
            if p.count == 3, let d = Int(p[0]), let m = Int(p[1]), let a = Int(p[2]) { dia = LocalDate(year: a, month: m, day: d) }
        }
        guard let dia else { return nil }
        var c = DateComponents()
        c.year = dia.year; c.month = dia.month; c.day = dia.day
        if partes.count > 1 {
            let hm = partes[1].split(separator: ":")
            c.hour = hm.first.flatMap { Int($0) } ?? 0
            c.minute = hm.count > 1 ? Int(hm[1]) ?? 0 : 0
        } else {
            c.hour = 0; c.minute = 0
        }
        return HorasHabiles.calendario(zona).date(from: c)
    }

    /// «2026-10-19 10:32» (como se escribe una fila nueva).
    public static func textoFecha(_ d: Date, zona: TimeZone) -> String {
        let c = HorasHabiles.calendario(zona).dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// El siguiente «INC-NNN» libre: el mayor de todos los registros y fichas de la carpeta y del contador, más uno.
    public static func siguienteID(en snapshot: VaultSnapshot, hoy: LocalDate) -> String {
        var mayor = Secuencias.siguiente("incidencia", año: hoy.year, en: snapshot) - 1
        for p in snapshot.notes where p.ext == "md" && !VaultSnapshot.isTemplatePath(p) {
            guard let t = snapshot.text(p), t.contains("INC-") else { continue }
            for f in RegistroIncidencias.leer(t, ruta: p, zona: .current).filas { mayor = max(mayor, f.numero ?? 0) }
        }
        return Secuencias.formatear("incidencia", mayor + 1, año: hoy.year)
    }

    /// Las operaciones que añaden una incidencia al registro (y suben el contador). Si el proyecto aún no tiene
    /// `Incidencias.md`, `texto` es el registro entero que hay que crear (con la plantilla) y la fila ya dentro.
    public static func operaciones(nueva celdas: [String: String], registro: VaultPath, existe: Bool, textoNuevo: String?,
                                   id: String, snapshot: VaultSnapshot, hoy: LocalDate) -> [WriteOp]? {
        var ops: [WriteOp] = []
        if existe {
            ops.append(.appendTableRow(registro, table: tabla, cells: celdas))
        } else {
            guard let textoNuevo, let conFila = Self.anadirFila(celdas, a: textoNuevo) else { return nil }
            ops.append(.create(registro, text: conFila))
        }
        if let n = Int(id.dropFirst(4)), let op = Secuencias.op(["incidencia": n], en: snapshot) { ops.append(op) }
        return ops
    }

    /// Mete una fila al final de la tabla del registro (para crear el registro ya con su primera incidencia).
    static func anadirFila(_ celdas: [String: String], a texto: String) -> String? {
        var lineas = texto.components(separatedBy: "\n")
        guard let cabecera = lineas.firstIndex(where: { l in
            l.hasPrefix("|") && TextFolding.fold(l).contains("severidad")
        }), cabecera + 1 < lineas.count else { return nil }
        let nombres = lineas[cabecera].split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let fila = "| " + nombres.map { n in
            (celdas.first { TextFolding.fold($0.key) == TextFolding.fold(n) }?.value ?? "")
                .replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
        }.joined(separator: " | ") + " |"
        var fin = cabecera + 2
        while fin < lineas.count, lineas[fin].hasPrefix("|") { fin += 1 }
        lineas.insert(fila, at: fin)
        return lineas.joined(separator: "\n")
    }
}
