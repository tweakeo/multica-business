import Foundation
import TLSAgents
import TLSCore

// F4 · rol asistentes. Los cambios que se preparan en la ficha de un asistente antes de guardarlos: qué se ve con ellos
// puestos y cómo se cuentan en la vista previa («Rutina «Cobros pendientes»: a las 09:00 → a las 10:00»).

/// Lo que la ficha enseña con los cambios aún sin guardar puestos encima.
struct AjustesConCambios: Hashable {
    var activo: Bool
    var rutinas: [TLSAgents.RutinaDeAsistente]
    var topeMes: Double
    var topeTrabajo: Double
    var maxTareas: Int
    var modos: [String: ModoCapacidad]

    static func de(_ a: AsistenteEnLista, config: ConfigAgentes, cambios: [CambioDeAsistente]) -> AjustesConCambios {
        var x = AjustesConCambios(activo: a.activo, rutinas: a.rutinas.map(\.rutina), topeMes: a.ajustes.presupuestoMesUSD,
                                  topeTrabajo: a.ajustes.presupuestoEjecucionUSD, maxTareas: a.ajustes.maxTareasPorEjecucion,
                                  modos: [:])
        for c in funciones(a) { x.modos[c] = config.modo(c) ?? .asistido }
        for c in cambios { x.aplicar(c) }
        return x
    }

    mutating func aplicar(_ c: CambioDeAsistente) {
        func rutina(_ id: String, _ f: (inout TLSAgents.RutinaDeAsistente) -> Void) {
            if let i = rutinas.firstIndex(where: { $0.id == id }) { f(&rutinas[i]) }
        }
        switch c {
        case .activo(let v): activo = v
        case .modo(let codigo, let m): modos[codigo.uppercased()] = m
        case .rutinaActiva(let r, let v): rutina(r) { $0.activa = v }
        case .rutinaHora(let r, let h, let m): rutina(r) { $0.hora = h; $0.minuto = m }
        case .rutinaDias(let r, let d): rutina(r) { $0.dias = d }
        case .rutinaDiaDelMes(let r, let d): rutina(r) { $0.diaDelMes = d }
        case .topeMes(let v): topeMes = v
        case .topeTrabajo(let v): topeTrabajo = v
        case .maxTareas(let n): maxTareas = n
        }
    }

    func rutina(_ id: String) -> TLSAgents.RutinaDeAsistente? { rutinas.first { $0.id == id } }

    /// Las funciones que lleva: las de su entrada en la configuración o, si no dice, las de su perfil.
    static func funciones(_ a: AsistenteEnLista) -> [String] {
        let c = a.ajustes.capacidades.filter { !$0.isEmpty && $0 != "…" && $0 != "..." }
        return (c.isEmpty ? (a.perfil?.capacidades ?? []) : c).map { $0.uppercased() }
    }
}

/// Un cambio contado para la vista previa.
struct CambioContado: Identifiable, Hashable {
    var id: String { clave }
    let clave: String
    let que: String
    let antes: String
    let despues: String
}

enum DescripcionDeCambios {
    /// Los cambios en palabras, comparando con lo que hay ahora.
    static func contar(_ cambios: [CambioDeAsistente], asistente a: AsistenteEnLista, config: ConfigAgentes) -> [CambioContado] {
        let ahora = AjustesConCambios.de(a, config: config, cambios: [])
        let luego = AjustesConCambios.de(a, config: config, cambios: cambios)
        let catalogo = CatalogoPrograma.deSerie
        return cambios.map { c in
            switch c {
            case .activo(let v):
                return CambioContado(clave: c.clave, que: v ? "Activar a \(a.nombre)" : "Apagar a \(a.nombre)",
                                     antes: ahora.activo ? "Trabaja" : "Apagado",
                                     despues: v ? "Trabaja" : "Apagado: no hace nada hasta que lo actives")
            case .modo(let codigo, let m):
                let nombre = catalogo.capacidades.first { $0.codigo == codigo.uppercased() }?.nombre ?? codigo
                // F4 · corrector (P3): el nombre de la función, sin su código (el código va en «Detalle técnico»).
                return CambioContado(clave: c.clave, que: nombre,
                                     antes: (ahora.modos[codigo.uppercased()] ?? .asistido).etiqueta, despues: m.etiqueta)
            case .rutinaActiva(let r, _), .rutinaHora(let r, _, _), .rutinaDias(let r, _), .rutinaDiaDelMes(let r, _):
                let antes = ahora.rutina(r), despues = luego.rutina(r)
                let nombre = antes?.nombre ?? r
                func texto(_ x: TLSAgents.RutinaDeAsistente?) -> String {
                    guard let x else { return "Sin rutina" }
                    return x.activa ? FichaDeRolDeAsistente.cuando(x) : "Apagada"
                }
                return CambioContado(clave: c.clave, que: "Rutina «\(nombre)»", antes: texto(antes), despues: texto(despues))
            // F4 · corrector (revisión de experiencia, P2): los topes, como parte del tope (las cifras en dólares están en
            // «Detalle técnico», con las líneas que cambian).
            case .topeMes(let v):
                let cambio = ahora.topeMes > 0 ? Int(((v - ahora.topeMes) / ahora.topeMes * 100).rounded()) : 0
                return CambioContado(clave: c.clave, que: "Tope de uso del mes", antes: "El de ahora",
                                     despues: cambio == 0 ? "Casi igual" : (cambio > 0 ? "Un \(cambio) % más alto" : "Un \(-cambio) % más bajo"))
            case .topeTrabajo(let v):
                func parte(_ t: Double, _ mes: Double) -> String {
                    mes > 0 ? "Como mucho el " + UsoDelMes.parte(t, de: mes) + " del mes" : "Sin tope del mes"
                }
                return CambioContado(clave: c.clave, que: "Lo que puede usar cada trabajo",
                                     antes: parte(ahora.topeTrabajo, ahora.topeMes), despues: parte(v, luego.topeMes))
            case .maxTareas(let n):
                return CambioContado(clave: c.clave, que: "Tareas nuevas por trabajo, como mucho",
                                     antes: "\(ahora.maxTareas)", despues: "\(n)")
            }
        }
    }

    /// Las líneas que cambian (para «Detalle técnico»): las que se van con «−» y las que entran con «+».
    static func lineasQueCambian(antes: String, despues: String) -> [String] {
        let a = antes.components(separatedBy: "\n"), b = despues.components(separatedBy: "\n")
        var quedan = Dictionary(b.map { ($0, 1) }, uniquingKeysWith: +)
        var salen: [String] = []
        for l in a {
            if let n = quedan[l], n > 0 { quedan[l] = n - 1 } else { salen.append(l) }
        }
        var siguen = Dictionary(a.map { ($0, 1) }, uniquingKeysWith: +)
        var entran: [String] = []
        for l in b {
            if let n = siguen[l], n > 0 { siguen[l] = n - 1 } else { entran.append(l) }
        }
        return salen.map { "− " + $0 } + entran.map { "+ " + $0 }
    }
}
