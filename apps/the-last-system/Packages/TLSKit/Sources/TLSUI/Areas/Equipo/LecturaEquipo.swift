import Foundation
import Observation
import TLSCore
import TLSDesign

// F2 · rol areas-b. Lo que pinta Equipo › Operación (PLAN §6.5; SISTEMAS EQ1, EQ2 y EQ3): los roles (persona o
// asistente) con quien los ocupa, los asistentes con su bitácora y su uso frente al tope (vacío explicado hasta que
// lleguen, F4) y la rejilla de rutinas ✓ ✕ – por semana, sacada de los registros de `Rutinas/`. Puro y `Sendable`;
// **nunca enseña lo privado**. Nada de aquí escribe.

/// Un rol de `6 · Equipo/Roles/`.
struct RolEquipo: Identifiable, Hashable, Sendable {
    var id: VaultPath { ruta }
    let ruta: VaultPath
    let nombre: String
    /// `clase: agente`.
    let esAsistente: Bool
    let areas: [AreaCode]
    /// Quien lo ocupa («Manu», «Comercial (asistente)»); `nil` = sin ocupante.
    let ocupante: String?
    /// La primera línea de «## Misión».
    let mision: String?
    /// Sus números (`numeros:`).
    let numeros: [String]
}

/// Un asistente de `.tls/config.yaml › agentes` (sin leer nada más de la configuración).
struct AsistenteEquipo: Identifiable, Hashable, Sendable {
    var id: String { slug }
    let slug: String
    let activo: Bool
    /// `presupuesto_mes_usd` (el tope del mes).
    let topeMesUSD: Double?
}

/// Una línea de la bitácora de los asistentes (`6 · Equipo/Bitácora/AAAA-MM.md`).
struct LineaBitacora: Identifiable, Hashable, Sendable {
    let id: String
    let fecha: LocalDate
    let texto: String
}

/// ✓ hecha · ✕ no se hizo · – no tocaba (o aún no toca esta semana).
enum ResultadoRutina: String, Sendable, Hashable {
    case hecha, noHecha, noToca, pendiente

    var simbolo: String {
        switch self {
        case .hecha: "checkmark"
        case .noHecha: "xmark"
        case .noToca, .pendiente: "minus"
        }
    }

    var estado: TLSEstado {
        switch self {
        case .hecha: .bien
        case .noHecha: .mal
        case .noToca, .pendiente: .sinDato
        }
    }

    var palabra: String {
        switch self {
        case .hecha: "Hecha"
        case .noHecha: "No se hizo"
        case .noToca: "No tocaba"
        case .pendiente: "Pendiente"
        }
    }
}

/// Una celda de la rejilla: una rutina en una semana.
struct CeldaRutina: Hashable, Sendable {
    let lunes: LocalDate
    let marca: ResultadoRutina
    /// «Hecha el 12 oct», «1 de 5 días», «Aún no existía»…
    let detalle: String
    /// Para las diarias: «1/5».
    let fraccion: String?
}

/// Cada cuánto toca una rutina.
enum CadenciaRutina: String, Sendable, Hashable {
    case diaria, semanal, mensual, trimestral

    init?(leyendo texto: String?) {
        let t = TextFolding.fold(texto ?? "").replacingOccurrences(of: "-", with: "_")
        if t.isEmpty { return nil }
        if t.hasPrefix("dia") || t == "diario" || t == "diaria" { self = .diaria }
        else if t.contains("seman") || t.contains("inicio_semana") || t.contains("cierre_semana") || t == "semana" { self = .semanal }
        else if t.hasPrefix("mes") || t.contains("mensual") { self = .mensual }
        else if t.contains("trimestr") { self = .trimestral }
        else { return nil }
    }
}

/// Una rutina con sus registros y su fila de la rejilla.
struct FilaRutina: Identifiable, Hashable, Sendable {
    let id: String
    let nombre: String
    let cadencia: CadenciaRutina?
    /// Ficha de la rutina (`Rutinas/<rutina>.md`) o, si no la hay, la carpeta de sus registros.
    let ficha: VaultPath?
    let carpeta: VaultPath?
    let registros: [LocalDate]
    let celdas: [CeldaRutina]

    var ultimo: LocalDate? { registros.max() }
}

/// Equipo leído de una foto de la carpeta.
struct LecturaEquipo: Sendable {
    let hoy: LocalDate
    let roles: [RolEquipo]
    /// Los de `.tls/config.yaml › agentes`.
    let asistentes: [AsistenteEquipo]
    /// Hay bitácora (aunque esté vacía).
    let hayBitacora: Bool
    /// Las últimas líneas, de la más reciente a la más antigua.
    let bitacora: [LineaBitacora]
    /// Uso del mes en USD (`nil` = sin bitácora: «Sin dato»).
    let usoMesUSD: Double?
    /// Lunes de las semanas de la rejilla (la última, la de hoy).
    let semanas: [LocalDate]
    let rutinas: [FilaRutina]

    static let semanasRejilla = 6

    init(foto: VaultSnapshot, hoy: LocalDate) {
        let layout = foto.layout
        let resolver = foto.resolver
        self.hoy = hoy
        func visible(_ p: VaultPath) -> Bool { !layout.isPrivate(p) && !layout.isArchived(p) && !VaultSnapshot.isTemplatePath(p) }

        var roles: [RolEquipo] = []
        var fichasRutina: [(VaultPath, Frontmatter)] = []
        var registros: [(VaultPath, Frontmatter)] = []
        for p in foto.notes where visible(p) {
            guard let texto = foto.text(p) else { continue }
            let doc = NoteDocument(text: texto)
            let fm = doc.frontmatter
            switch NoteKindResolver.kind(of: p, frontmatter: fm, layout: layout) {
            case .role:
                let areas: [AreaCode] = {
                    if case .list(let l)? = fm.value("areas") { return l.compactMap(Self.area) }
                    return fm.text("areas").flatMap(Self.area).map { [$0] } ?? []
                }()
                let mision = MarkdownSections.content(of: "Misión", in: doc.body)?
                    .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty && !$0.hasPrefix(">") }
                var numeros: [String] = []
                if case .list(let l)? = fm.value("numeros") { numeros = l.map { $0.trimmingCharacters(in: .whitespaces).uppercased() } }
                roles.append(RolEquipo(ruta: p, nombre: fm.titleText ?? doc.title(fileStem: p.stem, frontmatter: fm),
                                       esAsistente: TextFolding.fold(fm.text("clase") ?? "") == "agente",
                                       areas: areas, ocupante: LectorArea.nombreOcupante(fm.text("ocupante")),
                                       mision: mision, numeros: numeros))
            case .routine: fichasRutina.append((p, fm))
            case .routineLog: registros.append((p, fm))
            default: continue
            }
        }
        self.roles = roles.sorted { ($0.esAsistente ? 1 : 0, $0.nombre) < ($1.esAsistente ? 1 : 0, $1.nombre) }

        // Asistentes de la configuración (solo slug, activo y tope del mes).
        var asistentes: [AsistenteEquipo] = []
        if let texto = foto.text(VaultPath(".tls/config.yaml")) {
            let cfg = FrontmatterReader.read(texto)
            if cfg.isValid, case .raw(let r)? = cfg.value("agentes") {
                let mapa = FrontmatterReader.read(r)
                for prop in mapa.properties {
                    guard case .raw(let det) = prop.value else { continue }
                    let a = FrontmatterReader.read(det)
                    asistentes.append(AsistenteEquipo(slug: prop.key, activo: Self.si(a.value("activo")) ?? true,
                                                      topeMesUSD: a.text("presupuesto_mes_usd").flatMap(FormatoBase.numero)))
                }
            }
        }
        self.asistentes = asistentes

        // Bitácora: «- 2026-10-21 10:32 · mika · … · uso 0,04 USD».
        let bitacora = layout.areaFolder(.equipo).appending("Bitácora")
        var lineas: [LineaBitacora] = []
        var hay = false
        var uso: Double = 0
        var conUso = false
        for p in foto.notes where visible(p) && p.parent.map({ TextFolding.pathKey($0.raw) == TextFolding.pathKey(bitacora.raw) }) == true {
            hay = true
            for (n, l) in (foto.text(p) ?? "").split(whereSeparator: \.isNewline).enumerated() {
                let t = l.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("- "), let fecha = LocalDate(parsing: String(t.dropFirst(2).prefix(10))), fecha <= hoy else { continue }
                lineas.append(LineaBitacora(id: "\(p.raw)#\(n)", fecha: fecha, texto: String(t.dropFirst(2))))
                if fecha.year == hoy.year, fecha.month == hoy.month,
                   let r = t.range(of: #"uso\s+([\d.,]+)\s*USD"#, options: [.regularExpression, .caseInsensitive]) {
                    let cifra = t[r].replacingOccurrences(of: "uso", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "USD", with: "", options: .caseInsensitive)
                    if let v = FormatoBase.numero(cifra) { uso += v; conUso = true }
                }
            }
        }
        hayBitacora = hay
        self.bitacora = Array(lineas.sorted { ($0.fecha, $0.id) > ($1.fecha, $1.id) }.prefix(12))
        usoMesUSD = hay ? (conUso ? uso : 0) : nil

        // Rutinas: las fichas y los registros (por su enlace `rutina`, por su carpeta o, sin ficha, por la carpeta).
        let lunesHoy = hoy.adding(days: -(hoy.weekday - 1))
        let semanas = (0..<Self.semanasRejilla).reversed().map { lunesHoy.adding(days: -7 * $0) }
        self.semanas = semanas
        struct Grupo { var nombre: String; var cadencia: CadenciaRutina?; var ficha: VaultPath?; var carpeta: VaultPath?
            var dia: String?; var creada: LocalDate?; var activa: Bool; var fechas: [LocalDate] }
        var grupos: [String: Grupo] = [:]
        var orden: [String] = []
        for (p, fm) in fichasRutina {
            let k = TextFolding.pathKey(p.raw)
            grupos[k] = Grupo(nombre: fm.titleText ?? p.stem, cadencia: CadenciaRutina(leyendo: fm.text("cadencia")), ficha: p,
                              carpeta: p.parent?.appending(p.stem), dia: fm.text("dia"), creada: Self.fecha(fm, "creada"),
                              activa: Self.si(fm.value("activa")) ?? true, fechas: [])
            orden.append(k)
        }
        for (p, fm) in registros {
            guard let fecha = Self.fecha(fm, "fecha") ?? LocalDate(parsing: p.stem), fecha <= hoy else { continue }
            var clave: String?
            if let r = fm.text("rutina"), let l = LinkParser.links(in: r).first(where: { !$0.isExternal }),
               let destino = resolver.resolve(l.resolvable, from: p), grupos[TextFolding.pathKey(destino.raw)] != nil {
                clave = TextFolding.pathKey(destino.raw)
            }
            if clave == nil, let dir = p.parent {
                clave = grupos.first { $0.value.carpeta.map { TextFolding.pathKey($0.raw) == TextFolding.pathKey(dir.raw) } == true }?.key
            }
            if clave == nil, let dir = p.parent {
                let k = TextFolding.pathKey(dir.raw)
                if grupos[k] == nil {
                    grupos[k] = Grupo(nombre: Self.nombreImplicito(dir.name),
                                      cadencia: CadenciaRutina(leyendo: fm.text("tipo")) ?? CadenciaRutina(leyendo: dir.name),
                                      ficha: nil, carpeta: dir, dia: nil, creada: nil, activa: true, fechas: [])
                    orden.append(k)
                }
                clave = k
            }
            if let clave { grupos[clave]?.fechas.append(fecha) }
        }
        rutinas = orden.compactMap { k -> FilaRutina? in
            guard let g = grupos[k], g.activa else { return nil }
            let inicio = g.creada ?? g.fechas.min()
            let celdas = semanas.map { Self.celda(lunes: $0, cadencia: g.cadencia, fechas: g.fechas, inicio: inicio, dia: g.dia, hoy: hoy) }
            return FilaRutina(id: k, nombre: g.nombre, cadencia: g.cadencia, ficha: g.ficha, carpeta: g.carpeta,
                              registros: g.fechas.sorted(), celdas: celdas)
        }
    }

    // MARK: Consultas

    var personas: [RolEquipo] { roles.filter { !$0.esAsistente } }
    var rolesDeAsistente: [RolEquipo] { roles.filter(\.esAsistente) }

    /// Tope del mes de todos los asistentes activos (`nil` si ninguno lo dice).
    var topeMesUSD: Double? {
        let t = asistentes.filter(\.activo).compactMap(\.topeMesUSD)
        return t.isEmpty ? nil : t.reduce(0, +)
    }

    /// «34 % de tu tope», «Sin tope», «Sin dato».
    var textoUso: String {
        guard let uso = usoMesUSD else { return "Sin dato" }
        guard let tope = topeMesUSD, tope > 0 else { return "Sin tope" }
        return "\(Int((uso / tope * 100).rounded())) % de tu tope"
    }

    /// Rutinas que llevan dos semanas acabadas seguidas sin hacerse (EQU-RUT).
    var rutinasCaidas: [FilaRutina] {
        rutinas.filter { r in
            let acabadas = r.celdas.filter { $0.lunes.adding(days: 6) < hoy }
            return acabadas.count >= 2 && acabadas.suffix(2).allSatisfy { $0.marca == .noHecha }
        }
    }

    // MARK: Celdas

    static func celda(lunes: LocalDate, cadencia: CadenciaRutina?, fechas: [LocalDate], inicio: LocalDate?, dia: String?,
                      hoy: LocalDate) -> CeldaRutina {
        let domingo = lunes.adding(days: 6)
        let enSemana = fechas.filter { $0 >= lunes && $0 <= domingo }.sorted()
        let acabada = domingo < hoy
        let antes = inicio.map { domingo < $0 } ?? true
        func f(_ d: LocalDate) -> String { FormatoFicha.fechaCorta(d, hoy: hoy) }
        if lunes > hoy { return CeldaRutina(lunes: lunes, marca: .noToca, detalle: "Aún no ha llegado", fraccion: nil) }
        switch cadencia {
        case .diaria?:
            let desde = max(lunes, inicio ?? lunes)
            var debidos: [LocalDate] = []
            var d = desde
            while d <= domingo && d < hoy { if !d.isWeekend { debidos.append(d) }; d = d.adding(days: 1) }
            if enSemana.contains(hoy), !hoy.isWeekend { debidos.append(hoy) }
            if antes || (debidos.isEmpty && enSemana.isEmpty) {
                return CeldaRutina(lunes: lunes, marca: antes ? .noToca : .pendiente,
                                   detalle: antes ? "Aún no existía" : "Pendiente esta semana", fraccion: nil)
            }
            let hechos = Set(enSemana)
            let n = debidos.filter { hechos.contains($0) }.count
            let total = max(debidos.count, n)
            let marca: ResultadoRutina = n >= total && total > 0 ? .hecha : (acabada || n < debidos.count ? .noHecha : .pendiente)
            return CeldaRutina(lunes: lunes, marca: marca, detalle: "\(n) de \(total) \(total == 1 ? "día" : "días")", fraccion: "\(n)/\(total)")
        case .mensual?, .trimestral?:
            if let h = enSemana.last { return CeldaRutina(lunes: lunes, marca: .hecha, detalle: "Hecha el \(f(h))", fraccion: nil) }
            let diaMes = dia.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1
            let toca = (0...6).map { lunes.adding(days: $0) }.first { d in
                d.day == diaMes && (cadencia == .mensual || [1, 4, 7, 10].contains(d.month))
            }
            guard let toca, !(inicio.map { toca < $0 } ?? true) else {
                return CeldaRutina(lunes: lunes, marca: .noToca, detalle: antes ? "Aún no existía" : "No tocaba esta semana", fraccion: nil)
            }
            return toca < hoy && acabada
                ? CeldaRutina(lunes: lunes, marca: .noHecha, detalle: "Tocaba el \(f(toca))", fraccion: nil)
                : CeldaRutina(lunes: lunes, marca: .pendiente, detalle: "Toca el \(f(toca))", fraccion: nil)
        default:
            // Semanal (y lo que no dice su cadencia).
            if let h = enSemana.last { return CeldaRutina(lunes: lunes, marca: .hecha, detalle: "Hecha el \(f(h))", fraccion: nil) }
            if antes { return CeldaRutina(lunes: lunes, marca: .noToca, detalle: "Aún no existía", fraccion: nil) }
            if acabada { return CeldaRutina(lunes: lunes, marca: .noHecha, detalle: "No se hizo", fraccion: nil) }
            if let d = dia.flatMap(Self.diaSemana) {
                let tocaba = lunes.adding(days: d - 1)
                if tocaba < hoy { return CeldaRutina(lunes: lunes, marca: .noHecha, detalle: "Tocaba el \(f(tocaba))", fraccion: nil) }
            }
            return CeldaRutina(lunes: lunes, marca: .pendiente, detalle: "Pendiente esta semana", fraccion: nil)
        }
    }

    // MARK: Ayudas

    static func fecha(_ fm: Frontmatter, _ k: String) -> LocalDate? { fm.text(k).flatMap { LocalDate(parsing: $0) } }

    /// `true`/`false` (o «sí»/«no») de una propiedad; `nil` si no está o no se entiende.
    static func si(_ v: PropertyValue?) -> Bool? {
        switch v {
        case .bool(let b)?: return b
        case .text(let t)?, .raw(let t)?, .number(let t)?:
            switch TextFolding.fold(t).trimmingCharacters(in: .whitespaces) {
            case "true", "si", "yes": return true
            case "false", "no": return false
            default: return nil
            }
        default: return nil
        }
    }

    static func area(_ t: String) -> AreaCode? {
        let k = TextFolding.fold(t).trimmingCharacters(in: .whitespaces)
        return AreaCode.allCases.first { TextFolding.fold($0.rawValue) == k || TextFolding.fold($0.nombre) == k }
    }

    /// «lunes» → 1 … «domingo» → 7.
    static func diaSemana(_ t: String) -> Int? {
        let dias = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
        let k = TextFolding.fold(t).trimmingCharacters(in: .whitespaces)
        return dias.firstIndex { k.hasPrefix($0.prefix(3)) }.map { $0 + 1 }
    }

    /// Nombre de una rutina sin ficha, por la carpeta de sus registros.
    static func nombreImplicito(_ carpeta: String) -> String {
        switch TextFolding.fold(carpeta).replacingOccurrences(of: "_", with: "-") {
        case "dia", "diaria", "diario": "Rutina diaria"
        case "semana", "semanal": "Rutina semanal"
        case "inicio-de-semana", "inicio-semana": "Inicio de semana"
        case "cierre-de-semana", "cierre-semana": "Cierre de semana"
        case "mes", "revision-mensual": "Revisión mensual"
        case "trimestre", "revision-trimestral": "Revisión trimestral"
        default: FormatoFicha.capital(carpeta.replacingOccurrences(of: "-", with: " "))
        }
    }
}

/// El modelo de Equipo › Operación: solo lee (los roles los escribes tú en sus fichas; los asistentes, en F4).
@Observable @MainActor
final class ModeloEquipo {
    let sesion: VaultSession
    private(set) var lectura: LecturaEquipo?
    private(set) var revisionLeida = -1
    @ObservationIgnored private var carga: Task<Void, Never>?

    init(sesion: VaultSession) { self.sesion = sesion }

    func cargar() async {
        let revision = sesion.revision
        guard revision != revisionLeida || lectura == nil else { return }
        if let carga { await carga.value; if revision == revisionLeida, lectura != nil { return } }
        let almacen = AlmacenRelaciones.de(sesion)
        let tarea = Task { [weak self] in
            await almacen.actualizar()
            guard let self, let foto = almacen.foto else { return }
            let hoy = self.sesion.hoy
            let leida = await Task.detached(priority: .userInitiated) { LecturaEquipo(foto: foto, hoy: hoy) }.value
            guard !Task.isCancelled else { return }
            self.lectura = leida
            self.revisionLeida = revision
        }
        carga = tarea
        await tarea.value
        carga = nil
    }
}
