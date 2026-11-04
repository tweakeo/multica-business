// Procedencia: port reescrito de Programa v0.5 (Manu): core/sql/03-vistas.sql (`etapa_por_area`, `etapa_negocio`),
// core/sql/14-calibracion.sql (una capacidad cuenta solo si alguien la declaró), core/sql/10-tlb.sql
// (`siguientes_pasos`) y core/madurez.js (`progreso`, objetivo E5) y core/consultoria.js (`loQueFalta`, el porqué de
// la etapa). Ver docs/PROCEDENCIA.md.
import Foundation

/// En qué estado está un sistema del estándar en tu empresa.
public struct EstadoSistemaStd: Sendable, Hashable, Identifiable {
    public var id: String { sistema.codigo }
    public let sistema: SistemaStd
    public let total: Int
    public let encendidas: Int
    public let estado: Estado
    /// Hace falta ya (su etapa es la del área o la siguiente).
    public let haceFalta: Bool

    public enum Estado: String, Sendable, Hashable {
        case montado, aMedias, falta

        public var etiqueta: String {
            switch self {
            case .montado: "Montado"
            case .aMedias: "A medias"
            case .falta: "Falta"
            }
        }
    }
}

/// Lo siguiente que toca construir en un área (y por qué).
public struct PasoSiguiente: Sendable, Hashable {
    public let que: String
    public let porque: String
}

/// La madurez de un área: su etapa (1–6), calculada con lo que declaraste, nunca opinada.
public struct EtapaArea: Sendable, Hashable, Identifiable {
    public var id: AreaCode { area }
    public let area: AreaCode
    public let etapa: Int
    public let esenciales: Int
    public let esencialesOk: Int
    public let activas: Int
    public let automatizadas: Int
    public let manuales: Int
    public let recomendablesSinDeclarar: Int
    /// % de lo esencial declarado (`nil` sin estándar cargado).
    public let cobertura: Int?
    /// % de lo declarado que funciona sin ti (`nil` si no hay nada declarado).
    public let pctAuto: Int?
    public let tieneDueno: Bool
    /// La etapa con su parte hecha (3,4 = a medio camino de la 3 a la 4).
    public let progreso: Double
    /// Etapas que faltan para la 5 (Delegar).
    public let faltanEtapas: Int
    public let sistemas: [EstadoSistemaStd]
    public let paso: PasoSiguiente
    /// Por qué está en esa etapa, dicho con su causa.
    public let porque: String
}

/// La etapa de la empresa: la del área más floja.
public struct EtapaEmpresa: Sendable, Hashable {
    public let etapa: Int
    public let media: Double
    public let masFloja: AreaCode?
    public let porque: String
    public let actual: EtapaStd?
    public let siguiente: EtapaStd?
}

/// Etapa por área con `capacidades.yaml` y lo declarado en `.tls/config.yaml` (`capacidades:`).
///
/// Reglas de Programa: una capacidad cuenta solo si alguien la declaró (`declarada: si`). Cobertura = esenciales
/// declaradas / esenciales; automatizado = declaradas con ejecutor automático o regla fija / declaradas.
/// Etapa: cobertura < 50 → 1; < 100 → 2; automatizado < 40 % → 3; sin dueño distinto de ti → 4; < 80 % → 5; si no, 6.
public struct EtapaCalculador: Sendable {
    /// A dónde se va mientras nadie diga otra cosa: E5 · Delegar.
    public static let objetivo = 5

    public let foto: FotoMetricas
    public let catalogo: CatalogoPrograma

    public init(foto: FotoMetricas, catalogo: CatalogoPrograma = .deSerie) {
        self.foto = foto; self.catalogo = catalogo
    }

    func declarada(_ codigo: String) -> ConfigMetricas.DeclaracionCapacidad? {
        guard let d = foto.config.capacidades[codigo.uppercased()], d.declarada else { return nil }
        // Declarada después de hoy: a día de hoy aún no lo estaba.
        if let desde = d.desde, desde > foto.hoy { return nil }
        return d
    }

    func ejecutor(_ c: CapacidadStd) -> Ejecutor {
        declarada(c.codigo)?.ejecutor ?? c.ejecutorRecomendado
    }

    public func areas() -> [EtapaArea] { AreaCode.allCases.map(area) }

    public func area(_ a: AreaCode) -> EtapaArea {
        let caps = catalogo.capacidades(de: a)
        let esenciales = caps.filter { $0.nivel == .esencial }
        let activas = caps.filter { declarada($0.codigo) != nil }
        let esencialesOk = esenciales.filter { declarada($0.codigo) != nil }.count
        let automatizadas = activas.filter { ejecutor($0).esAutomatico }.count
        let manuales = activas.filter { ejecutor($0) == .humano }.count
        let recomendables = caps.filter { $0.nivel == .recomendable && declarada($0.codigo) == nil }.count
        let cobertura = esenciales.isEmpty ? nil : Int((100 * Double(esencialesOk) / Double(esenciales.count)).rounded())
        let pctAuto = activas.isEmpty ? nil : Int((100 * Double(automatizadas) / Double(activas.count)).rounded())
        let dueno = foto.tieneDueno(a)
        let etapa: Int
        if let cob = cobertura {
            if cob < 50 { etapa = 1 }
            else if cob < 100 { etapa = 2 }
            else if (pctAuto ?? 0) < 40 { etapa = 3 }
            else if !dueno { etapa = 4 }
            else if (pctAuto ?? 0) < 80 { etapa = 5 }
            else { etapa = 6 }
        } else {
            etapa = 1
        }
        let progreso = Self.progreso(etapa: etapa, cobertura: cobertura ?? 0, pctAuto: pctAuto ?? 0, tieneDueno: dueno)

        let sistemas = catalogo.sistemas(de: a).map { s -> EstadoSistemaStd in
            let total = s.capacidades.count
            let encendidas = s.capacidades.filter { declarada($0) != nil }.count
            let estado: EstadoSistemaStd.Estado = total > 0 && encendidas == total ? .montado : (encendidas > 0 ? .aMedias : .falta)
            return EstadoSistemaStd(sistema: s, total: total, encendidas: encendidas, estado: estado, haceFalta: s.desdeEtapa <= etapa + 1)
        }

        let apagadas = esenciales.count - esencialesOk
        let paso: PasoSiguiente
        if apagadas > 0 {
            paso = PasoSiguiente(que: apagadas == 1 ? "Encender la función esencial que falta" : "Encender las \(apagadas) funciones esenciales que faltan",
                                 porque: "Sin lo esencial encendido, el resto se construye en el aire")
        } else if (cobertura ?? 0) < 100 {
            paso = PasoSiguiente(que: "Completar lo esencial", porque: "Sin lo esencial encendido, el resto se construye en el aire")
        } else if manuales > 2 {
            paso = PasoSiguiente(que: "Bajar de escalón \(manuales) funciones que aún se hacen a mano",
                                 porque: "Cada función a mano es criterio sin escribir, y lo que no está escrito no se delega")
        } else if !dueno {
            paso = PasoSiguiente(que: "Escribir la ficha de rol y buscar un dueño distinto de ti",
                                 porque: "Un área sin dueño distinto de ti no está delegada")
        } else if recomendables > 0 {
            paso = PasoSiguiente(que: recomendables == 1 ? "Valorar la función recomendable que queda" : "Valorar las \(recomendables) funciones recomendables que quedan",
                                 porque: "Es lo siguiente que mueve la etapa")
        } else {
            paso = PasoSiguiente(que: "El área está en su sitio: mantener y vigilar el número", porque: "Nada urgente")
        }

        let porque: String
        if (cobertura ?? 0) < 100 {
            porque = apagadas == 1 ? "le falta 1 función esencial por encender" : "le faltan \(apagadas) funciones esenciales por encender"
        } else if (pctAuto ?? 0) < 40 {
            porque = "lo tiene escrito pero solo el \(pctAuto ?? 0) % funciona sin ti"
        } else if manuales > 0 {
            porque = manuales == 1 ? "todavía hace 1 cosa a mano" : "todavía hace \(manuales) cosas a mano"
        } else {
            porque = "está a la espera de un dueño distinto de ti"
        }

        return EtapaArea(area: a, etapa: etapa, esenciales: esenciales.count, esencialesOk: esencialesOk, activas: activas.count,
                         automatizadas: automatizadas, manuales: manuales, recomendablesSinDeclarar: recomendables,
                         cobertura: cobertura, pctAuto: pctAuto, tieneDueno: dueno, progreso: progreso,
                         faltanEtapas: max(0, Self.objetivo - Int(progreso.rounded(.down))), sistemas: sistemas, paso: paso, porque: porque)
    }

    /// Dónde cae el área dentro de su etapa (madurez.js): la etapa sola no dice si la empiezas o la acabas.
    public static func progreso(etapa e: Int, cobertura cob: Int, pctAuto auto: Int, tieneDueno: Bool) -> Double {
        let f: Double
        switch e {
        case 1: f = Double(cob) / 50
        case 2: f = Double(cob - 50) / 50
        case 3: f = Double(auto) / 40
        case 4: f = tieneDueno ? 1 : 0.5
        case 5: f = Double(auto - 40) / 40
        default: f = 1
        }
        return ((Double(e) + max(0, min(1, f))) * 100).rounded() / 100
    }

    /// La etapa de la empresa es el mínimo de sus áreas: subir la media no sirve mientras la más floja siga donde está.
    public func empresa(_ areas: [EtapaArea]? = nil) -> EtapaEmpresa {
        let filas = areas ?? self.areas()
        let etapa = filas.map(\.etapa).min() ?? 1
        let media = filas.isEmpty ? 0 : (Double(filas.map(\.etapa).reduce(0, +)) / Double(filas.count) * 10).rounded() / 10
        // La más floja: la de menor etapa y, a igualdad, menor cobertura (orden de las áreas para desempatar).
        let floja = filas.min { a, b in
            if a.etapa != b.etapa { return a.etapa < b.etapa }
            if (a.cobertura ?? 0) != (b.cobertura ?? 0) { return (a.cobertura ?? 0) < (b.cobertura ?? 0) }
            return a.area.numero < b.area.numero
        }
        let porque = floja.map { "La empresa está en la etapa \(etapa) porque la etapa es la del área más floja, \($0.area.nombre): \($0.porque)." }
            ?? "Sin áreas que medir."
        return EtapaEmpresa(etapa: etapa, media: media, masFloja: floja?.area, porque: porque,
                            actual: catalogo.etapa(etapa), siguiente: catalogo.etapa(etapa + 1))
    }
}
