// Procedencia: datos del estándar de Programa v0.5 (Manu, único autor): spec/capacidades.yaml (Apache-2.0, con su
// LICENSE), core/sql/02-semillas.sql, 10-tlb.sql, 13-estructura.sql y 14-calibracion.sql, convertidos a
// Recursos/Programa/*.json. El código Swift es nuevo. Ver docs/PROCEDENCIA.md.
import Foundation
import Yams

/// Nivel de una capacidad del estándar.
public enum NivelCapacidad: String, Sendable, Codable, Hashable, CaseIterable {
    case esencial, recomendable, opcional
}

/// Quién ejecuta una capacidad. La escalera solo se baja: persona → asistente → automatización → regla fija.
public enum Ejecutor: String, Sendable, Codable, Hashable, CaseIterable {
    case humano, agente, automatizacion, script

    /// Acepta las letras de Programa (H, IA, A, S) y las palabras con o sin tilde.
    public init?(leyendo texto: String) {
        switch TextFolding.fold(texto.trimmingCharacters(in: .whitespaces)) {
        case "h", "humano", "persona", "manu", "yo": self = .humano
        case "ia", "agente", "asistente": self = .agente
        case "a", "automatizacion", "automatico": self = .automatizacion
        case "s", "script", "regla": self = .script
        default: return nil
        }
    }

    /// Funciona sin nadie delante (automatización o regla fija).
    public var esAutomatico: Bool { self == .automatizacion || self == .script }

    public var etiqueta: String {
        switch self {
        case .humano: "Persona"
        case .agente: "Asistente"
        case .automatizacion: "Automatización"
        case .script: "Regla fija"
        }
    }

    /// El siguiente escalón hacia abajo (`nil` en el último).
    public var siguiente: Ejecutor? {
        switch self {
        case .humano: .agente
        case .agente: .automatizacion
        case .automatizacion: .script
        case .script: nil
        }
    }
}

/// Una de las 78 capacidades de `capacidades.yaml`.
public struct CapacidadStd: Sendable, Hashable, Identifiable, Codable {
    public var id: String { codigo }
    public let codigo: String
    public let area: AreaCode
    public let modulo: String
    public let nombre: String
    public let nivel: NivelCapacidad
    public let ejecutorRecomendado: Ejecutor
    public let disparador: String?
    public let produce: String?

    enum CodingKeys: String, CodingKey {
        case codigo, area, modulo, nombre, nivel, disparador, produce
        case ejecutorRecomendado = "ejecutor_recomendado"
    }
}

/// Un sistema del estándar TLB (`sistemas-std.json`): qué necesita un área para estar montada.
public struct SistemaStd: Sendable, Hashable, Identifiable, Codable {
    public var id: String { codigo }
    public let codigo: String
    public let area: AreaCode
    public let nombre: String
    /// Qué contesta el sistema.
    public let pregunta: String
    /// `E` (esencial) o `R` (recomendable).
    public let nivel: String
    /// A partir de qué etapa hace falta.
    public let desdeEtapa: Int
    public let orden: Int
    /// Palabras con las que se reconoce en tus fichas.
    public let claves: [String]
    /// Capacidades que lo forman.
    public let capacidades: [String]

    public var esEsencial: Bool { nivel == "E" }

    enum CodingKeys: String, CodingKey {
        case codigo, area, nombre, pregunta, nivel, orden, claves, capacidades
        case desdeEtapa = "desde_etapa"
    }
}

/// Una de las seis etapas de madurez.
public struct EtapaStd: Sendable, Hashable, Codable, Identifiable {
    public var id: Int { num }
    public let num: Int
    public let nombre: String
    public let verbo: String
    public let queToca: String
    public let senal: String?

    enum CodingKeys: String, CodingKey {
        case num, nombre, verbo, senal
        case queToca = "que_toca"
    }
}

public struct AreaStd: Sendable, Hashable, Codable {
    public let codigo: AreaCode
    public let nombre: String
    public let convierte: String
    public let orden: Int
}

public struct RolStd: Sendable, Hashable, Codable {
    public let codigo: String
    public let area: AreaCode
    public let nombre: String
    public let mision: String
    public let pregunta: String
}

public struct ModuloStd: Sendable, Hashable, Codable {
    public let codigo: String
    public let area: AreaCode
    public let nombre: String
    public let produce: String
}

public struct RutinaStd: Sendable, Hashable, Codable {
    public let codigo: String
    public let area: AreaCode
    public let nombre: String
    public let cadencia: String
    public let pregunta: String
}

/// Hacia dónde es mejor que se mueva un número.
public enum SentidoKPI: String, Sendable, Codable, Hashable {
    case mas, menos, rango

    /// Lee «más es mejor», «menos es mejor», «dentro de un rango» (sección «Cómo se mide» de `Metas.md`).
    public init?(leyendo texto: String) {
        let t = TextFolding.fold(texto)
        if t.contains("menos es mejor") { self = .menos }
        else if t.contains("mas es mejor") { self = .mas }
        else if t.contains("rango") { self = .rango }
        else { return nil }
    }

    public var etiqueta: String {
        switch self {
        case .mas: "más es mejor"
        case .menos: "menos es mejor"
        case .rango: "dentro de un rango"
        }
    }
}

/// Sobre qué fechas se mide un número.
public enum PeriodoKPI: String, Sendable, Codable, Hashable {
    case ahora, mes, trimestre
    case dias30 = "30d"
    case dias90 = "90d"

    /// El rango que cubre a día `hoy` (`ahora` = solo hoy).
    public func rango(hoy: LocalDate) -> RangoFechas {
        switch self {
        case .ahora: RangoFechas(desde: hoy, hasta: hoy)
        case .mes: RangoFechas.mes(de: hoy, hasta: hoy)
        case .trimestre: RangoFechas.trimestre(de: hoy, hasta: hoy)
        case .dias30: RangoFechas(desde: hoy.adding(days: -29), hasta: hoy)
        case .dias90: RangoFechas(desde: hoy.adding(days: -89), hasta: hoy)
        }
    }

    public var etiqueta: String {
        switch self {
        case .ahora: "ahora"
        case .mes: "este mes"
        case .trimestre: "este trimestre"
        case .dias30: "últimos 30 días"
        case .dias90: "últimos 90 días"
        }
    }
}

/// Un número clave del catálogo (`kpi.json`).
public struct KPIDefinicion: Sendable, Hashable, Codable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    /// `nil` para los que no son de un área (BUZ-PEND, el Buzón).
    public let area: AreaCode?
    public let indicador: String
    /// `n`, `%`, `€`, `meses`, `h` o `USD`.
    public let unidad: String
    public let sentido: SentidoKPI
    public let periodo: PeriodoKPI
    /// Se suma a lo largo del periodo (el ritmo compara con la parte del periodo que ya pasó).
    public let acumulable: Bool
    /// `false`: la app aún no tiene de dónde sacarlo y enseña «Sin dato».
    public let calculable: Bool
    public let calculo: String
    public let fuentes: [String]
    /// `ribera` (Metas.md de Asesoría Ribera) o `propuesta-v2`.
    public let origen: String
}

/// Un rango de fechas cerrado (los dos días incluidos).
public struct RangoFechas: Sendable, Hashable, Codable {
    public let desde: LocalDate
    public let hasta: LocalDate

    public init(desde: LocalDate, hasta: LocalDate) {
        self.desde = min(desde, hasta); self.hasta = max(desde, hasta)
    }

    public func contiene(_ d: LocalDate) -> Bool { d >= desde && d <= hasta }

    /// Días del rango (los dos extremos cuentan).
    public var dias: Int { RangoFechas.diasEntre(desde, hasta) + 1 }

    /// Del día 1 del mes de `d` a `hasta` (por defecto, fin de mes).
    public static func mes(de d: LocalDate, hasta: LocalDate? = nil) -> RangoFechas {
        let inicio = LocalDate(year: d.year, month: d.month, day: 1)!
        let fin = finDeMes(d)
        return RangoFechas(desde: inicio, hasta: hasta.map { min($0, fin) } ?? fin)
    }

    public static func trimestre(de d: LocalDate, hasta: LocalDate? = nil) -> RangoFechas {
        let mes0 = ((d.month - 1) / 3) * 3 + 1
        let inicio = LocalDate(year: d.year, month: mes0, day: 1)!
        let fin = finDeMes(LocalDate(year: d.year, month: mes0 + 2, day: 1)!)
        return RangoFechas(desde: inicio, hasta: hasta.map { min($0, fin) } ?? fin)
    }

    public static func finDeMes(_ d: LocalDate) -> LocalDate {
        var dia = 31
        while dia > 27 {
            if let f = LocalDate(year: d.year, month: d.month, day: dia) { return f }
            dia -= 1
        }
        return LocalDate(year: d.year, month: d.month, day: 28)!
    }

    /// Días de `a` a `b` (negativo si `b` es anterior). Sin horas: no le afectan los cambios de hora.
    public static func diasEntre(_ a: LocalDate, _ b: LocalDate) -> Int {
        numeroDeDia(b) - numeroDeDia(a)
    }

    /// Día juliano civil (algoritmo de Fliegel y Van Flandern): cuenta días sin pasar por `Date`.
    static func numeroDeDia(_ d: LocalDate) -> Int {
        let a = (14 - d.month) / 12
        let y = d.year + 4800 - a
        let m = d.month + 12 * a - 3
        return d.day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }
}

/// El estándar de Programa que viene dentro de la app (`Recursos/Programa/`).
public struct CatalogoPrograma: Sendable {
    public let capacidades: [CapacidadStd]
    public let sistemas: [SistemaStd]
    public let etapas: [EtapaStd]
    public let areas: [AreaStd]
    public let roles: [RolStd]
    public let modulos: [ModuloStd]
    public let rutinas: [RutinaStd]
    public let kpis: [KPIDefinicion]
    /// Códigos de la tabla de `Metas.md` de Asesoría Ribera (contados al hacer el catálogo).
    public let recuentoRibera: Int

    public init(capacidades: [CapacidadStd] = [], sistemas: [SistemaStd] = [], etapas: [EtapaStd] = [],
                areas: [AreaStd] = [], roles: [RolStd] = [], modulos: [ModuloStd] = [], rutinas: [RutinaStd] = [],
                kpis: [KPIDefinicion] = [], recuentoRibera: Int = 0) {
        self.capacidades = capacidades; self.sistemas = sistemas; self.etapas = etapas; self.areas = areas
        self.roles = roles; self.modulos = modulos; self.rutinas = rutinas; self.kpis = kpis
        self.recuentoRibera = recuentoRibera
    }

    /// `false` si no se encontraron los recursos (una herramienta copiada sin ellos): todo sigue funcionando y lo
    /// que depende del estándar sale «Sin dato».
    public var cargado: Bool { !capacidades.isEmpty && !kpis.isEmpty }

    public func kpi(_ codigo: String) -> KPIDefinicion? {
        let c = codigo.uppercased()
        return kpis.first { $0.codigo == c }
    }

    public func capacidades(de area: AreaCode) -> [CapacidadStd] { capacidades.filter { $0.area == area } }
    public func sistemas(de area: AreaCode) -> [SistemaStd] { sistemas.filter { $0.area == area }.sorted { $0.orden < $1.orden } }
    public func etapa(_ num: Int) -> EtapaStd? { etapas.first { $0.num == num } }
    public func area(_ code: AreaCode) -> AreaStd? { areas.first { $0.codigo == code } }

    // MARK: Carga

    /// El de la app (vacío si no están los recursos).
    public static let deSerie: CatalogoPrograma = {
        guard let carpeta = RecursosPrograma.carpeta, let c = try? cargar(carpeta: carpeta) else { return CatalogoPrograma() }
        return c
    }()

    public enum ErrorCatalogo: Error, LocalizedError, Sendable {
        case falta(String)
        case ilegible(String, String)

        public var errorDescription: String? {
            switch self {
            case .falta(let f): "Falta «\(f)» en los recursos de la app."
            case .ilegible(let f, let e): "No he podido leer «\(f)»: \(e)"
            }
        }
    }

    public static func cargar(carpeta: URL) throws -> CatalogoPrograma {
        func datos(_ nombre: String) throws -> Data {
            guard let d = try? Data(contentsOf: carpeta.appendingPathComponent(nombre)) else { throw ErrorCatalogo.falta(nombre) }
            return d
        }
        let json = JSONDecoder()
        struct Semillas: Decodable {
            let areas: [AreaStd]; let roles: [RolStd]; let etapas: [EtapaStd]; let modulos: [ModuloStd]; let rutinas: [RutinaStd]
        }
        struct Sistemas: Decodable { let sistemas: [SistemaStd] }
        struct KPIs: Decodable {
            let kpis: [KPIDefinicion]
            let recuentoRibera: Int
            enum CodingKeys: String, CodingKey { case kpis; case recuentoRibera = "recuento_ribera" }
        }
        struct Capacidades: Decodable { let capacidades: [CapacidadStd] }
        do {
            let semillas = try json.decode(Semillas.self, from: try datos("semillas.json"))
            let sistemas = try json.decode(Sistemas.self, from: try datos("sistemas-std.json"))
            let kpis = try json.decode(KPIs.self, from: try datos("kpi.json"))
            guard let yaml = String(data: try datos("capacidades.yaml"), encoding: .utf8) else {
                throw ErrorCatalogo.ilegible("capacidades.yaml", "no es texto UTF-8")
            }
            let caps = try YAMLDecoder().decode(Capacidades.self, from: yaml)
            return CatalogoPrograma(capacidades: caps.capacidades, sistemas: sistemas.sistemas, etapas: semillas.etapas,
                                    areas: semillas.areas, roles: semillas.roles, modulos: semillas.modulos,
                                    rutinas: semillas.rutinas, kpis: kpis.kpis, recuentoRibera: kpis.recuentoRibera)
        } catch let e as ErrorCatalogo {
            throw e
        } catch {
            throw ErrorCatalogo.ilegible(carpeta.lastPathComponent, String(describing: error))
        }
    }
}

/// Dónde están los recursos de Programa dentro de la app o del paquete.
public enum RecursosPrograma {
    /// Carpeta `Programa` del paquete de recursos de TLSCore (sin `Bundle.module`, que pararía el proceso si no
    /// lo encuentra). `nil` si no está.
    public static var carpeta: URL? { carpetaEncontrada }

    private final class Marca {}

    private static let carpetaEncontrada: URL? = {
        let nombre = "TLSKit_TLSCore.bundle"
        let propio = Bundle(for: Marca.self)
        let sitios: [URL?] = [
            Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent(),
            propio.resourceURL, propio.bundleURL.deletingLastPathComponent(), propio.bundleURL,
        ]
        let fm = FileManager.default
        for sitio in sitios.compactMap({ $0 }) {
            let candidato = sitio.appendingPathComponent(nombre)
            guard fm.fileExists(atPath: candidato.path), let b = Bundle(url: candidato) else { continue }
            if let u = b.url(forResource: "Programa", withExtension: nil) { return u }
            let directo = candidato.appendingPathComponent("Programa")
            if fm.fileExists(atPath: directo.path) { return directo }
        }
        return nil
    }()
}
