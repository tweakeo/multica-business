import Foundation
import Yams

// Escribir la configuración de los asistentes en `.tls/config.yaml` (PLAN §4.5): solo una persona, desde Ajustes o la
// ficha del asistente. Cambia solo su bloque (`agentes:`, `interruptor:`, `pausa_areas:` o el `modo` de una función en
// `capacidades:`); el resto del fichero queda byte a byte. Lo que escribe la app queda confirmado (`CommandBus`).

public enum EditorConfigAgentes {
    public static let ruta = ConfigConfirmada.ruta

    /// Un cambio de la configuración de los asistentes hecho desde la app.
    public enum Cambio: Sendable, Hashable {
        case asistente(AsistenteConfigurado)
        case interruptor(Interruptor)
        case pausaAreas([AreaCode])
        case modo(ModoCapacidad, capacidad: String)

        func aplicar(_ texto: String?) throws -> String {
            switch self {
            case .asistente(let a): try EditorConfigAgentes.texto(poner: a, en: texto)
            case .interruptor(let i): try EditorConfigAgentes.texto(interruptor: i, en: texto)
            case .pausaAreas(let p): try EditorConfigAgentes.texto(pausaAreas: p, en: texto)
            case .modo(let m, let c): try EditorConfigAgentes.texto(modo: m, capacidad: c, en: texto)
            }
        }

        var descripcion: String {
            switch self {
            case .asistente(let a): "Ajustes de \(a.nombre) (asistente)"
            case .interruptor(let i): i == .encendido ? "Encender los asistentes" : "Apagar los asistentes"
            case .pausaAreas: "Pausar áreas para los asistentes"
            case .modo(let m, let c): "\(c.uppercased()): \(m.etiqueta)"
            }
        }
    }

    /// Escribe un cambio como persona y lo deja confirmado. Si había cambios de permisos hechos fuera de la app sin
    /// confirmar, se confirma solo este cambio (aplicado sobre lo confirmado): los de fuera siguen esperando tu OK.
    @discardableResult
    public static func aplicar(_ c: Cambio, bus: CommandBus, autor: Autor) async throws -> WriteResult {
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        let gobierno = bus.autorizador
        let antes = gobierno?.config.leer()
        let plan = try plan(root: bus.writer.root, autor: autor, descripcion: c.descripcion) { try c.aplicar($0) }
        let r = try await bus.ejecutar(plan)
        if r.hecho, let g = gobierno, let antes, antes.cambiadaFuera, !antes.ilegible {
            try g.config.confirmarTexto(try c.aplicar(g.config.textoConfirmado()), por: quien, ahora: g.opciones.ahora())
        }
        return r
    }

    // MARK: Planes (como persona)

    /// Pone (o cambia) la entrada de un asistente en `agentes:`.
    public static func plan(poner a: AsistenteConfigurado, root: URL, autor: Autor) throws -> WritePlan {
        try plan(root: root, autor: autor, descripcion: "Ajustes de \(a.nombre) (asistente)") { try texto(poner: a, en: $0) }
    }

    /// Enciende o apaga a todos los asistentes (DIR-11).
    public static func plan(interruptor i: Interruptor, root: URL, autor: Autor) throws -> WritePlan {
        try plan(root: root, autor: autor,
                 descripcion: i == .encendido ? "Encender los asistentes" : "Apagar los asistentes") { try texto(interruptor: i, en: $0) }
    }

    /// Áreas en pausa (los asistentes no trabajan en ellas).
    public static func plan(pausaAreas: [AreaCode], root: URL, autor: Autor) throws -> WritePlan {
        try plan(root: root, autor: autor, descripcion: "Pausar áreas para los asistentes") { try texto(pausaAreas: pausaAreas, en: $0) }
    }

    /// Modo de una función (permiso). No toca `declarada` (madurez).
    public static func plan(modo: ModoCapacidad, capacidad: String, root: URL, autor: Autor) throws -> WritePlan {
        try plan(root: root, autor: autor, descripcion: "\(capacidad.uppercased()): \(modo.etiqueta)") {
            try texto(modo: modo, capacidad: capacidad, en: $0)
        }
    }

    static func plan(root: URL, autor: Autor, descripcion: String, _ cambio: (String?) throws -> String) throws -> WritePlan {
        guard autor.esPersona else { throw ErrorDeGobierno.soloPersonas }
        let url = ruta.url(in: root)
        let actual = UbiquityInspector.withoutMaterializing { () -> Data? in
            guard let info = UbiquityInspector.info(url), !info.dataless, !info.isSymlink else { return nil }
            return try? Data(contentsOf: url, options: [.uncached])
        }
        if let actual {
            guard let t = String(data: actual, encoding: .utf8) else { throw ErrorDeGobierno.configIlegible }
            let sinBOM = t.hasPrefix("\u{FEFF}") ? String(t.dropFirst()) : t
            let nuevo = try cambio(sinBOM)
            guard let op = WriteOp.replaceText(ruta, base: actual, text: nuevo) else { throw ErrorDeGobierno.configIlegible }
            return WritePlan(autor: autor, descripcion: descripcion, ops: [op])
        }
        return WritePlan(autor: autor, descripcion: descripcion, ops: [.create(ruta, text: try cambio(nil))])
    }

    // MARK: Texto

    static let cabecera = "# Configuración de esta carpeta.\nversion: 1\n"

    /// El texto con la entrada del asistente puesta (las demás entradas, tal cual).
    public static func texto(poner a: AsistenteConfigurado, en texto: String?) throws -> String {
        let base = texto ?? cabecera
        try comprobarLegible(base)
        var entradas = TextoPuesta.entradasYAML("agentes", en: base)
        if entradas.isEmpty, let v = TextoPuesta.valorYAML(["agentes"], en: base), !v.isEmpty, v != "{}" {
            throw ErrorDeGobierno.configIlegible
        }
        var nuevas = lineas(a)
        if let i = entradas.firstIndex(where: { ConfigAgentes.slug($0.clave) == a.slug }) {
            // F4 · integración: las rutinas guardan claves que este editor no conoce (`dia_mes`, `meses`, `solo_si_rojo`,
            // `instruccion`, ventanas decimales). Si no cambian, se dejan sus líneas tal cual; si cambian y llevan alguna de
            // esas claves, no se escribe nada antes que perderlas (la ficha del asistente cambia esas líneas una a una).
            let viejas = entradas[i].lineas
            if let r0 = viejas.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("rutinas:") }),
               let n0 = nuevas.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("rutinas:") }) {
                let bloqueViejo = Array(viejas[r0...].prefix { $0 == viejas[r0] || $0.hasPrefix("      ") })
                let antes = ConfigAgentes.leer(yaml: TextoPuesta.ponerBloqueYAML("agentes", ["agentes:"] + viejas, en: base))
                    .asistente(a.slug)?.rutinas
                if antes == a.rutinas {
                    nuevas.replaceSubrange(n0..., with: bloqueViejo)
                } else if bloqueViejo.contains(where: { l in
                    ["dia_mes", "meses", "solo_si_rojo", "instruccion"].contains { l.contains($0 + ":") } }) {
                    throw ErrorDeGobierno.configIlegible
                }
            }
            entradas[i] = (a.slug, nuevas)
        } else {
            entradas.append((a.slug, nuevas))
        }
        let resultado = TextoPuesta.ponerBloqueYAML("agentes", ["agentes:"] + entradas.flatMap(\.lineas), en: base)
        let leido = ConfigAgentes.leer(yaml: resultado)
        guard !leido.ilegible, leido.asistente(a.slug) == normalizado(a) else { throw ErrorDeGobierno.configIlegible }
        return resultado
    }

    public static func texto(interruptor i: Interruptor, en texto: String?) throws -> String {
        let base = texto ?? cabecera
        try comprobarLegible(base)
        let r = TextoPuesta.ponerBloqueYAML("interruptor", ["interruptor: \(i.rawValue)"], en: base)
        guard ConfigAgentes.leer(yaml: r).interruptor == i else { throw ErrorDeGobierno.configIlegible }
        return r
    }

    public static func texto(pausaAreas: [AreaCode], en texto: String?) throws -> String {
        let base = texto ?? cabecera
        try comprobarLegible(base)
        let lista = pausaAreas.isEmpty ? "[]" : "[" + pausaAreas.map(\.layoutKey).joined(separator: ", ") + "]"
        let r = TextoPuesta.ponerBloqueYAML("pausa_areas", ["pausa_areas: \(lista)"], en: base)
        guard Set(ConfigAgentes.leer(yaml: r).pausaAreas) == Set(pausaAreas) else { throw ErrorDeGobierno.configIlegible }
        return r
    }

    public static func texto(modo: ModoCapacidad, capacidad: String, en texto: String?) throws -> String {
        let base = texto ?? cabecera
        try comprobarLegible(base)
        let codigo = capacidad.uppercased()
        var entradas = TextoPuesta.entradasYAML("capacidades", en: base)
        if entradas.isEmpty, let v = TextoPuesta.valorYAML(["capacidades"], en: base), !v.isEmpty, v != "{}" {
            throw ErrorDeGobierno.configIlegible
        }
        // Las claves de esa función, en su orden, con `modo` cambiado (o añadido).
        var pares: [(String, String)] = []
        if let e = entradas.first(where: { $0.clave.uppercased() == codigo }) {
            let sangria = e.lineas.map { $0.hasPrefix("  ") ? String($0.dropFirst(2)) : $0 }.joined(separator: "\n")
            if let n = (try? Yams.compose(yaml: sangria, Resolver.basic)) ?? nil, let m = n.mapping,
               let v = m.first?.value.mapping {
                for (k, x) in v { if let ks = k.scalar?.string { pares.append((ks, x.scalar?.string ?? "")) } }
            }
        }
        if let i = pares.firstIndex(where: { $0.0 == "modo" }) { pares[i].1 = modo.rawValue } else { pares.append(("modo", modo.rawValue)) }
        let linea = "  \(codigo): {" + pares.map { "\($0.0): \(TextoPuesta.escalarYAML($0.1))" }.joined(separator: ", ") + "}"
        if let i = entradas.firstIndex(where: { $0.clave.uppercased() == codigo }) {
            entradas[i] = (codigo, [linea])
        } else {
            entradas.append((codigo, [linea]))
        }
        let r = TextoPuesta.ponerBloqueYAML("capacidades", ["capacidades:"] + entradas.flatMap(\.lineas), en: base)
        guard ConfigAgentes.leer(yaml: r).modo(codigo) == modo else { throw ErrorDeGobierno.configIlegible }
        return r
    }

    static func comprobarLegible(_ t: String) throws {
        if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ConfigAgentes.leer(yaml: t).ilegible {
            throw ErrorDeGobierno.configIlegible
        }
    }

    /// Como se lee después de escribirla (para comprobar que el fichero dice lo que se quería).
    static func normalizado(_ a: AsistenteConfigurado) -> AsistenteConfigurado? {
        ConfigAgentes.leer(yaml: "agentes:\n" + lineas(a).joined(separator: "\n") + "\n").asistente(a.slug)
    }

    /// Las líneas de la entrada de un asistente (con su sangría dentro de `agentes:`).
    static func lineas(_ a: AsistenteConfigurado) -> [String] {
        func lista(_ l: [String]) -> String { "[" + l.map(TextoPuesta.escalarYAML).joined(separator: ", ") + "]" }
        func num(_ d: Double) -> String {
            d == d.rounded() ? String(Int(d)) : String(d)
        }
        var areas = a.areas.map(\.layoutKey)
        if a.buzon { areas.append("buzon") }
        let lee = a.leeTodas ? ["todas"] : a.leeAreas.map(\.layoutKey)
        var l = ["  \(a.slug):",
                 "    activo: \(a.activo)",
                 "    coordinador: \(a.coordinador)",
                 "    areas: \(lista(areas))",
                 "    lee_areas: \(lista(lee))",
                 "    capacidades: \(lista(a.capacidades))",
                 "    herramientas_externas: \(lista(a.herramientasExternas))"]
        if let m = a.modelo { l.append("    modelo: \(TextoPuesta.escalarYAML(m))") }
        if let e = a.esfuerzo { l.append("    esfuerzo: \(TextoPuesta.escalarYAML(e))") }
        if let t = a.maxTurnos { l.append("    max_turnos: \(t)") }
        l.append("    max_tareas_por_ejecucion: \(a.maxTareasPorEjecucion)")
        if let p = a.presupuestoEjecucionUSD { l.append("    presupuesto_ejecucion_usd: \(num(p))") }
        if let p = a.presupuestoMesUSD { l.append("    presupuesto_mes_usd: \(num(p))") }
        if a.rutinas.isEmpty {
            l.append("    rutinas: []")
        } else {
            l.append("    rutinas:")
            for r in a.rutinas {
                var c = ["id: \(TextoPuesta.escalarYAML(r.id))", "nombre: \"\(r.nombre.replacingOccurrences(of: "\"", with: "\\\""))\"",
                         "dias: \(lista(r.dias))"]
                if let h = r.hora { c.append("hora: \"\(h)\"") }
                if let v = r.ventanaPerdidaH { c.append("ventana_perdida_h: \(v)") }
                c.append("activa: \(r.activa)")
                l.append("      - {" + c.joined(separator: ", ") + "}")
            }
        }
        return l
    }
}
