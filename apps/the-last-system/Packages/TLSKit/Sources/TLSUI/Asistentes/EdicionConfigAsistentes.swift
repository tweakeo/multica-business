import Foundation
import TLSAgents
import TLSCore

// F4 · rol asistentes. Lo que la ficha de un asistente cambia en `.tls/config.yaml` (PLAN §4.5): si trabaja, el nivel de
// cada función, sus rutinas (encendida, día y hora) y sus topes. Solo lo escribe una persona, con vista previa y
// Deshacer, por `CommandBus`.
//
// Se cambian **solo las líneas de lo que cambia** dentro de `agentes.<slug>` (o el `modo` de la función, con
// `EditorConfigAgentes.texto(modo:…)` del gobierno): el resto del fichero queda byte a byte. Así se conservan los
// campos que el editor del gobierno aún no sabe escribir (`dia_mes`, `meses`, `solo_si_rojo`, `instruccion`; ver
// «Cambios pedidos › roles» en docs/F4-CONTRATOS.md). Después se comprueba que el fichero se lee exactamente como se
// quería; si no, no se escribe nada.

/// Un cambio en la configuración de un asistente.
enum CambioDeAsistente: Hashable, Sendable {
    case activo(Bool)
    /// El nivel de una función (`capacidades.<código>.modo`).
    case modo(String, ModoCapacidad)
    case rutinaActiva(String, Bool)
    case rutinaHora(String, hora: Int, minuto: Int)
    case rutinaDias(String, Set<DiaSemana>)
    case rutinaDiaDelMes(String, Int)
    case topeMes(Double)
    case topeTrabajo(Double)
    case maxTareas(Int)

    /// Qué toca (dos cambios con la misma clave: vale el último).
    var clave: String {
        switch self {
        case .activo: "activo"
        case .modo(let c, _): "modo:\(c.uppercased())"
        case .rutinaActiva(let r, _): "rutina:\(r):activa"
        case .rutinaHora(let r, _, _): "rutina:\(r):hora"
        case .rutinaDias(let r, _): "rutina:\(r):dias"
        case .rutinaDiaDelMes(let r, _): "rutina:\(r):dia_mes"
        case .topeMes: "tope_mes"
        case .topeTrabajo: "tope_trabajo"
        case .maxTareas: "max_tareas"
        }
    }
}

enum ErrorEdicionConfig: Error, LocalizedError, Equatable {
    /// El fichero tiene una forma que no se puede cambiar sin tocar lo demás.
    case formaDesconocida(String)
    /// Lo escrito no se lee como se quería (no se escribe nada).
    case noCuadra
    case sinRutina(String)

    var errorDescription: String? {
        switch self {
        case .formaDesconocida(let que):
            "La configuración de los asistentes está escrita de una forma que no sé cambiar sin tocar lo demás (\(que)). No he cambiado nada."
        case .noCuadra:
            "No he cambiado nada: el resultado no se leía como querías. Revisa la configuración en la carpeta."
        case .sinRutina(let r):
            "No encuentro la rutina «\(r)» en la configuración. No he cambiado nada."
        }
    }
}

enum EdicionConfigAsistentes {
    /// El texto de la configuración con los cambios de un asistente. Si el asistente no estaba (o no tenía sus rutinas
    /// escritas), primero se pone su entrada de serie (`ConfigDeSerie`).
    static func texto(_ cambios: [CambioDeAsistente], slug: String, perfil: PerfilDeAsistente?, en base: String) throws -> String {
        guard !cambios.isEmpty else { return base }
        var texto = base
        // 1. Que exista su entrada y, si hay que tocar una rutina, sus rutinas escritas.
        if try bloqueAsistente(slug, en: lineas(texto)) == nil {
            guard let perfil else { throw ErrorEdicionConfig.formaDesconocida("falta el asistente") }
            texto = try anadirEntrada(perfil, en: texto)
        }
        let tocaRutinas = cambios.contains { if case .modo = $0 { false } else { $0.clave.hasPrefix("rutina:") } }
        if tocaRutinas, try rutinasEscritas(slug, en: texto) == nil {
            guard let perfil, !perfil.rutinas.isEmpty else { throw ErrorEdicionConfig.sinRutina(slug) }
            texto = try ponerClave("rutinas", lineasDeValor: perfil.rutinas.map { "- " + ConfigDeSerie.rutina($0) }, slug: slug, en: texto)
        }
        let intermedio = texto
        // 2. Los cambios, uno a uno.
        for c in cambios {
            switch c {
            case .activo(let v): texto = try ponerClave("activo", valor: v ? "true" : "false", slug: slug, en: texto)
            case .modo(let codigo, let m): texto = try EditorConfigAgentes.texto(modo: m, capacidad: codigo, en: texto)
            case .rutinaActiva(let r, let v): texto = try ponerEnRutina(r, "activa", v ? "true" : "false", slug: slug, en: texto)
            case .rutinaHora(let r, let h, let m):
                texto = try ponerEnRutina(r, "hora", "\"" + String(format: "%02d:%02d", h, m) + "\"", slug: slug, en: texto)
            case .rutinaDias(let r, let dias):
                texto = try ponerEnRutina(r, "dias", "[" + dias.sorted().map(abreviatura).joined(separator: ", ") + "]", slug: slug, en: texto)
            case .rutinaDiaDelMes(let r, let d): texto = try ponerEnRutina(r, "dia_mes", "\(d)", slug: slug, en: texto)
            case .topeMes(let v): texto = try ponerClave("presupuesto_mes_usd", valor: numero(v), slug: slug, en: texto)
            case .topeTrabajo(let v): texto = try ponerClave("presupuesto_ejecucion_usd", valor: numero(v), slug: slug, en: texto)
            case .maxTareas(let n): texto = try ponerClave("max_tareas_por_ejecucion", valor: "\(n)", slug: slug, en: texto)
            }
        }
        try comprobar(antes: base, intermedio: intermedio, despues: texto, slug: slug, cambios: cambios)
        return texto
    }

    // MARK: Comprobar

    /// El resultado se lee como se quería: el asistente cambia justo en lo pedido, los demás y el resto de la
    /// configuración de los asistentes quedan igual, y el gobierno lo entiende.
    static func comprobar(antes: String, intermedio: String, despues: String, slug: String, cambios: [CambioDeAsistente]) throws {
        let gAntes = ConfigAgentes.leer(yaml: antes), gDespues = ConfigAgentes.leer(yaml: despues)
        guard !gDespues.ilegible else { throw ErrorEdicionConfig.noCuadra }
        guard gAntes.interruptor == gDespues.interruptor, Set(gAntes.pausaAreas) == Set(gDespues.pausaAreas),
              gAntes.privado == gDespues.privado, gAntes.avisos == gDespues.avisos else { throw ErrorEdicionConfig.noCuadra }
        for (s, a) in gAntes.agentes where s != slug {
            guard gDespues.agentes[s] == a else { throw ErrorEdicionConfig.noCuadra }
        }
        var esperado = AjustesDeAsistentes.leer(yaml: intermedio)
        let leido = AjustesDeAsistentes.leer(yaml: despues)
        guard var a = esperado.agentes[slug] else { throw ErrorEdicionConfig.noCuadra }
        for c in cambios {
            switch c {
            case .activo(let v): a.activo = v
            case .modo(let codigo, let m):
                guard gDespues.modo(codigo) == m else { throw ErrorEdicionConfig.noCuadra }
            case .rutinaActiva(let r, let v): try cambiar(r, en: &a) { $0.activa = v }
            case .rutinaHora(let r, let h, let m): try cambiar(r, en: &a) { $0.hora = h; $0.minuto = m }
            case .rutinaDias(let r, let d): try cambiar(r, en: &a) { $0.dias = d }
            case .rutinaDiaDelMes(let r, let d): try cambiar(r, en: &a) { $0.diaDelMes = d }
            case .topeMes(let v): a.presupuestoMesUSD = v
            case .topeTrabajo(let v): a.presupuestoEjecucionUSD = v
            case .maxTareas(let n): a.maxTareasPorEjecucion = n
            }
        }
        esperado.agentes[slug] = a
        guard leido == esperado else { throw ErrorEdicionConfig.noCuadra }
        // Las funciones que no se pidieron, igual.
        let pedidas = Set(cambios.compactMap { if case .modo(let c, _) = $0 { c.uppercased() } else { nil } })
        for (c, x) in gAntes.capacidades where !pedidas.contains(c) {
            guard gDespues.capacidades[c] == x else { throw ErrorEdicionConfig.noCuadra }
        }
        if cambios.contains(where: { if case .activo = $0 { true } else { false } }) {
            guard gDespues.asistente(slug)?.activo == a.activo else { throw ErrorEdicionConfig.noCuadra }
        }
    }

    private static func cambiar(_ id: String, en a: inout AjustesDeAsistente, _ f: (inout TLSAgents.RutinaDeAsistente) -> Void) throws {
        guard let i = a.rutinas.firstIndex(where: { $0.id == id }) else { throw ErrorEdicionConfig.sinRutina(id) }
        f(&a.rutinas[i])
    }

    // MARK: Líneas

    static func lineas(_ t: String) -> [String] { t.components(separatedBy: "\n") }

    static func sangria(_ l: String) -> Int { l.prefix { $0 == " " }.count }

    /// Línea que no cuenta para la estructura (vacía o solo comentario).
    static func esHueca(_ l: String) -> Bool {
        let t = l.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("#")
    }

    /// `clave: resto` de una línea (sin la sangría), con el resto sin comentario.
    static func claveYResto(_ l: String) -> (clave: String, resto: String)? {
        let t = l.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("-"), let i = t.firstIndex(of: ":") else { return nil }
        let clave = t[..<i].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        var resto = String(t[t.index(after: i)...]).trimmingCharacters(in: .whitespaces)
        if resto.hasPrefix("#") { resto = "" }
        return (clave, resto)
    }

    /// Rango de líneas del bloque `agentes:` (sin su cabecera): `(cabecera, fin)` con `fin` excluido.
    static func bloqueAgentes(_ ls: [String]) throws -> (cabecera: Int, fin: Int)? {
        guard let i = ls.firstIndex(where: { l in
            sangria(l) == 0 && !esHueca(l) && claveYResto(l)?.clave == "agentes"
        }) else { return nil }
        let resto = claveYResto(ls[i])?.resto ?? ""
        guard resto.isEmpty || resto == "{}" || resto == "[]" else {
            throw ErrorEdicionConfig.formaDesconocida("los asistentes van en una sola línea")
        }
        var fin = i + 1
        while fin < ls.count, esHueca(ls[fin]) || sangria(ls[fin]) > 0 { fin += 1 }
        return (i, fin)
    }

    /// Rango de las líneas de un asistente: `(cabecera, fin, sangría de sus claves)`.
    static func bloqueAsistente(_ slug: String, en ls: [String]) throws -> (cabecera: Int, fin: Int, sangria: Int)? {
        guard let (cab, fin) = try bloqueAgentes(ls) else { return nil }
        guard let primera = (cab + 1..<fin).first(where: { !esHueca(ls[$0]) }) else { return nil }
        let hijo = sangria(ls[primera])
        for i in cab + 1..<fin where !esHueca(ls[i]) && sangria(ls[i]) == hijo {
            guard let (k, resto) = claveYResto(ls[i]), ConfigAgentes.slug(k) == slug else { continue }
            guard resto.isEmpty else { throw ErrorEdicionConfig.formaDesconocida("el asistente va en una sola línea") }
            var f = i + 1
            while f < fin, esHueca(ls[f]) || sangria(ls[f]) > hijo { f += 1 }
            // Sin contar las líneas huecas del final (son del siguiente).
            while f > i + 1, esHueca(ls[f - 1]) { f -= 1 }
            let dentro = (i + 1..<f).first(where: { !esHueca(ls[$0]) }).map { sangria(ls[$0]) } ?? hijo + 2
            return (i, f, dentro)
        }
        return nil
    }

    /// Pone `clave: valor` en el asistente (cambia esa línea o la añade al final de su entrada).
    static func ponerClave(_ clave: String, valor: String, slug: String, en texto: String) throws -> String {
        var ls = lineas(texto)
        guard let b = try bloqueAsistente(slug, en: ls) else { throw ErrorEdicionConfig.formaDesconocida("falta el asistente") }
        let nueva = String(repeating: " ", count: b.sangria) + "\(clave): \(valor)"
        if let i = (b.cabecera + 1..<b.fin).first(where: { !esHueca(ls[$0]) && sangria(ls[$0]) == b.sangria && claveYResto(ls[$0])?.clave == clave }) {
            // Una clave con valor en varias líneas no se toca.
            if let r = claveYResto(ls[i])?.resto, r.isEmpty { throw ErrorEdicionConfig.formaDesconocida(clave) }
            ls[i] = nueva
        } else {
            ls.insert(nueva, at: b.fin)
        }
        return ls.joined(separator: "\n")
    }

    /// Pone `clave:` con un valor de varias líneas (las de `lineasDeValor`, con la sangría de dentro) en lugar de lo que
    /// hubiera (`rutinas: []` o nada).
    static func ponerClave(_ clave: String, lineasDeValor: [String], slug: String, en texto: String) throws -> String {
        var ls = lineas(texto)
        guard let b = try bloqueAsistente(slug, en: ls) else { throw ErrorEdicionConfig.formaDesconocida("falta el asistente") }
        let sangria = String(repeating: " ", count: b.sangria)
        let nuevas = [sangria + "\(clave):"] + lineasDeValor.map { sangria + "  " + $0 }
        if let i = (b.cabecera + 1..<b.fin).first(where: { !esHueca(ls[$0]) && Self.sangria(ls[$0]) == b.sangria && claveYResto(ls[$0])?.clave == clave }) {
            var f = i + 1
            while f < b.fin, esHueca(ls[f]) || Self.sangria(ls[f]) > b.sangria || ls[f].trimmingCharacters(in: .whitespaces).hasPrefix("- ") { f += 1 }
            ls.replaceSubrange(i..<f, with: nuevas)
        } else {
            ls.insert(contentsOf: nuevas, at: b.fin)
        }
        return ls.joined(separator: "\n")
    }

    /// Las líneas de las rutinas escritas de un asistente (`nil` si no tiene ninguna escrita).
    static func rutinasEscritas(_ slug: String, en texto: String) throws -> [Int]? {
        let ls = lineas(texto)
        guard let b = try bloqueAsistente(slug, en: ls) else { return nil }
        guard let i = (b.cabecera + 1..<b.fin).first(where: { !esHueca(ls[$0]) && sangria(ls[$0]) == b.sangria && claveYResto(ls[$0])?.clave == "rutinas" })
        else { return nil }
        let resto = claveYResto(ls[i])?.resto ?? ""
        if resto == "[]" { return nil }
        guard resto.isEmpty else { throw ErrorEdicionConfig.formaDesconocida("las rutinas van en una sola línea") }
        var items: [Int] = []
        var f = i + 1
        while f < b.fin {
            let l = ls[f]
            let t = l.trimmingCharacters(in: .whitespaces)
            if esHueca(l) { f += 1; continue }
            guard sangria(l) > b.sangria || (sangria(l) == b.sangria && t.hasPrefix("- ")) else { break }
            guard t.hasPrefix("- {"), t.hasSuffix("}") else { throw ErrorEdicionConfig.formaDesconocida("una rutina en varias líneas") }
            items.append(f)
            f += 1
        }
        return items.isEmpty ? nil : items
    }

    /// Cambia (o añade) una clave dentro de la rutina `id` (escrita en línea: `- {id: …, hora: "09:00", …}`).
    static func ponerEnRutina(_ id: String, _ clave: String, _ valor: String, slug: String, en texto: String) throws -> String {
        var ls = lineas(texto)
        guard let items = try rutinasEscritas(slug, en: texto) else { throw ErrorEdicionConfig.sinRutina(id) }
        for i in items {
            let l = ls[i]
            let pre = String(l.prefix { $0 == " " })
            let t = l.trimmingCharacters(in: .whitespaces)
            let dentro = String(t.dropFirst(3).dropLast())  // sin «- {» ni «}»
            var pares = try paresEnLinea(dentro)
            guard let idActual = pares.first(where: { $0.clave == "id" })?.valor,
                  TextFolding.fold(sinComillas(idActual)) == TextFolding.fold(id) else { continue }
            if let j = pares.firstIndex(where: { $0.clave == clave }) {
                pares[j].valor = valor
            } else {
                pares.append((clave, valor))
            }
            ls[i] = pre + "- {" + pares.map { "\($0.clave): \($0.valor)" }.joined(separator: ", ") + "}"
            return ls.joined(separator: "\n")
        }
        throw ErrorEdicionConfig.sinRutina(id)
    }

    /// Los pares `clave: valor` de un mapa en línea (sin las llaves), respetando comillas, corchetes y llaves.
    static func paresEnLinea(_ s: String) throws -> [(clave: String, valor: String)] {
        var trozos: [String] = []
        var actual = ""
        var nivel = 0
        var comilla: Character?
        var escapado = false
        for ch in s {
            if let q = comilla {
                actual.append(ch)
                if escapado { escapado = false } else if ch == "\\" && q == "\"" { escapado = true } else if ch == q { comilla = nil }
                continue
            }
            switch ch {
            case "\"", "'": comilla = ch; actual.append(ch)
            case "[", "{": nivel += 1; actual.append(ch)
            case "]", "}": nivel -= 1; actual.append(ch)
            case "," where nivel == 0: trozos.append(actual); actual = ""
            default: actual.append(ch)
            }
        }
        guard comilla == nil, nivel == 0 else { throw ErrorEdicionConfig.formaDesconocida("una rutina mal cerrada") }
        if !actual.trimmingCharacters(in: .whitespaces).isEmpty { trozos.append(actual) }
        return try trozos.map { trozo in
            let t = trozo.trimmingCharacters(in: .whitespaces)
            guard let i = t.firstIndex(of: ":") else { throw ErrorEdicionConfig.formaDesconocida("una rutina sin clave") }
            let k = t[..<i].trimmingCharacters(in: .whitespaces)
            let v = t[t.index(after: i)...].trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty, !k.contains("\""), !k.contains("'") else { throw ErrorEdicionConfig.formaDesconocida("una rutina con claves entre comillas") }
            return (k, v)
        }
    }

    static func sinComillas(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, let f = t.first, let l = t.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") {
            return String(t.dropFirst().dropLast())
        }
        return t
    }

    /// Añade la entrada de serie de un asistente que no estaba (apagado; el cambio decide).
    static func anadirEntrada(_ p: PerfilDeAsistente, en texto: String) throws -> String {
        let entrada = ConfigDeSerie.entrada(p, activo: false)
        var ls = lineas(texto)
        if let (cab, fin) = try bloqueAgentes(ls) {
            let hijo = (cab + 1..<fin).first(where: { !esHueca(ls[$0]) }).map { sangria(ls[$0]) } ?? 2
            var f = fin
            while f > cab + 1, esHueca(ls[f - 1]) { f -= 1 }
            if ["{}", "[]"].contains(claveYResto(ls[cab])?.resto ?? "") { ls[cab] = "agentes:" }
            ls.insert(contentsOf: entrada.map { String(repeating: " ", count: hijo) + $0 }, at: f)
            return ls.joined(separator: "\n")
        }
        var t = texto
        if !t.isEmpty, !t.hasSuffix("\n") { t += "\n" }
        t += "agentes:\n" + entrada.map { "  " + $0 }.joined(separator: "\n") + "\n"
        return t
    }

    // MARK: Formato

    static func abreviatura(_ d: DiaSemana) -> String {
        ["lun", "mar", "mie", "jue", "vie", "sab", "dom"][d.rawValue - 1]
    }

    static func numero(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        return String(format: "%.2f", d).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}
