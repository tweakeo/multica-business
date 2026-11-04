import Foundation
import TLSCore

/// Un sistema del catálogo de la app (SISTEMAS §2.5: los 19 sistemas). Es lo que el área debería tener según
/// su etapa; si no hay ficha, sale como «Falta».
public struct SistemaDeCatalogo: Sendable, Hashable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    public let nombre: String
    /// `nil` = no es de un área (el Buzón).
    public let area: AreaCode?
    /// Otros nombres con los que se reconoce su ficha (los de G3).
    public let otrosNombres: [String]
    /// Etapa en la que se instala (`nil` = de serie, desde el primer día).
    public let etapa: Int?
    public let deSerie: Bool
    /// Código de `Metas.md` que lo mide (si lo hay).
    public let numeroClave: String?
    /// Quién lleva el día a día (texto del catálogo).
    public let lleva: String

    /// Nombres con los que se reconoce (sin tildes ni mayúsculas).
    var claves: Set<String> { Set(([nombre] + otrosNombres).map { TextFolding.fold($0) }) }
}

/// Los 19 sistemas de SISTEMAS §2.5 y el asistente de cada área (PLAN §5.1).
public enum CatalogoSistemas {
    public static let deSerie: [SistemaDeCatalogo] = [
        s("CO1", "Correspondencia", nil, otros: ["El Buzón"], etapa: nil, deSerie: true, numero: nil, lleva: "Cartero y Ordenador"),
        s("DI1", "Decisiones", .direccion, etapa: nil, deSerie: true, numero: "DIR-DEC14", lleva: "Mika"),
        s("DI2", "Revisión y replanificación", .direccion, etapa: nil, deSerie: true, numero: nil, lleva: "Mika"),
        s("DI3", "Rumbo y mapa", .direccion, etapa: nil, deSerie: true, numero: nil, lleva: "Mika"),
        s("EQ2", "Asistentes", .equipo, otros: ["Agentes de IA"], etapa: nil, deSerie: true, numero: "EQU-HEALTH", lleva: "Equipo"),
        s("VE1", "Oferta", .ventas, etapa: 1, deSerie: false, numero: nil, lleva: "Comercial"),
        s("VE2", "Embudo", .ventas, etapa: 1, deSerie: false, numero: "VEN-STALE7", lleva: "Comercial"),
        s("FI1", "Facturación y cobros", .finanzas, etapa: 1, deSerie: false, numero: "FIN-AR", lleva: "Contable"),
        s("FI3", "Control económico", .finanzas, etapa: 1, deSerie: false, numero: "FIN-FISCAL", lleva: "Contable"),
        s("EN1", "Arranque del cliente", .entrega, otros: ["Onboarding"], etapa: 2, deSerie: false, numero: "ENT-ARR48", lleva: "Implementador"),
        s("EN2", "Gestionar encargo", .entrega, etapa: 2, deSerie: false, numero: "ENT-ONTIME", lleva: "Implementador"),
        s("EN3", "Cierre e incidencias", .entrega, etapa: 2, deSerie: false, numero: "ENT-INC", lleva: "Implementador"),
        s("FI2", "Tesorería", .finanzas, etapa: 2, deSerie: false, numero: "FIN-RUNWAY", lleva: "Contable"),
        s("MA1", "Identidad", .marca, otros: ["Identidad y kit de marca"], etapa: 1, deSerie: false, numero: nil, lleva: "Marca"),
        s("VE3", "Referidos y continuidad", .ventas, otros: ["Upsell y fidelización"], etapa: 3, deSerie: false, numero: "VEN-REF", lleva: "Comercial"),
        s("MA2", "Contenido", .marca, otros: ["Contenido y publicación"], etapa: 3, deSerie: false, numero: "MAR-PUB", lleva: "Marca"),
        s("EQ1", "Roles", .equipo, etapa: 3, deSerie: false, numero: "EQU-ROLES", lleva: "Equipo"),
        s("MA3", "Conversaciones y casos", .marca, etapa: 4, deSerie: false, numero: "MAR-QCONV", lleva: "Marca"),
        s("EQ3", "Acordar colaboración", .equipo, etapa: 5, deSerie: false, numero: "EQU-RUT", lleva: "Equipo"),
    ]

    /// Los sistemas de un área, en el orden del catálogo.
    public static func de(_ area: AreaCode) -> [SistemaDeCatalogo] { deSerie.filter { $0.area == area } }

    /// El del catálogo que corresponde a una ficha (por su `codigo` o por su nombre).
    public static func reconocer(codigo: String?, nombre: String, area: AreaCode) -> SistemaDeCatalogo? {
        let candidatos = de(area)
        if let codigo = codigo?.trimmingCharacters(in: .whitespaces).uppercased(), !codigo.isEmpty,
           let s = candidatos.first(where: { $0.codigo == codigo }) { return s }
        let n = TextFolding.fold(nombre)
        return candidatos.first { $0.claves.contains(n) }
    }

    /// El asistente de cada área (PLAN §5.1): Mika coordina desde Dirección.
    public static func asistente(de area: AreaCode) -> String {
        switch area {
        case .direccion: "Mika"
        case .ventas: "Comercial"
        case .entrega: "Implementador"
        case .finanzas: "Contable"
        case .marca: "Marca"
        case .equipo: "Equipo"
        }
    }

    /// Prefijo de los códigos de `Metas.md` de cada área (`FIN-RUNWAY` es de Finanzas).
    public static func prefijo(de area: AreaCode) -> String { area.rawValue + "-" }

    private static func s(_ codigo: String, _ nombre: String, _ area: AreaCode?, otros: [String] = [], etapa: Int?,
                          deSerie: Bool, numero: String?, lleva: String) -> SistemaDeCatalogo {
        SistemaDeCatalogo(codigo: codigo, nombre: nombre, area: area, otrosNombres: otros, etapa: etapa, deSerie: deSerie,
                          numeroClave: numero, lleva: lleva)
    }
}
