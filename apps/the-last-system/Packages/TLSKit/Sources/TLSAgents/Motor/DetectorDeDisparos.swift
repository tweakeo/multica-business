import Foundation
import TLSCore

/// Busca en la carpeta y en el outbox lo que despierta a un asistente (PLAN §5.3, «Disparadores»):
/// tareas listas (`Tarea.esListaParaAgente`), menciones `@agente:x` en comentarios humanos nuevos, despertares
/// (`despertar:` de una tarea) y eventos del dominio. Solo lee; nunca mira lo privado, lo retirado a `Archivo/` ni
/// las plantillas. La idempotencia la pone la clave de cada disparo (UNIQUE en `disparos`).
public struct DetectorDeDisparos: Sendable {
    public var catalogo: any CatalogoDeAsistentes

    public init(catalogo: any CatalogoDeAsistentes) { self.catalogo = catalogo }

    /// Tareas que puede ver un asistente (sin lo privado, `Archivo/` ni plantillas).
    static func tareas(_ snapshot: VaultSnapshot, reloj: Reloj) -> [Tarea] {
        TaskStore(snapshot: snapshot, reloj: reloj).tareas.filter { t in
            !snapshot.layout.isPrivate(t.ruta) && t.ruta.components.first != "Archivo" && !VaultSnapshot.isTemplatePath(t.ruta)
                && !t.ruta.components.contains(".tls")
        }
    }

    /// `agente:<slug>` → slug.
    static func slug(_ responsable: String?) -> String? {
        guard let r = responsable?.trimmingCharacters(in: .whitespaces), r.hasPrefix("agente:") else { return nil }
        let s = TextFolding.fold(String(r.dropFirst("agente:".count)))
        return s.isEmpty ? nil : s
    }

    // MARK: Tareas listas

    /// Huella de lo que importa de una tarea para dispararla (sin la Actividad: escribir el cierre no la cambia).
    public static func huella(_ t: Tarea, texto: String?) -> String {
        var base = [t.estadoTexto ?? "", t.responsable ?? "", t.planificada?.description ?? "", t.titulo].joined(separator: "|")
        if let texto { base += "|" + Self.cuerpoSinActividad(texto) }
        return Disparo.huella(base)
    }

    static func cuerpoSinActividad(_ texto: String) -> String {
        var lineas = texto.components(separatedBy: "\n")
        // Fuera el frontmatter.
        if lineas.first?.trimmingCharacters(in: .whitespaces) == "---",
           let fin = lineas.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lineas = Array(lineas[(fin + 1)...])
        }
        if let i = lineas.firstIndex(where: { esEncabezadoActividad($0) }) { lineas = Array(lineas[..<i]) }
        return lineas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func esEncabezadoActividad(_ l: String) -> Bool {
        let t = l.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("## ") && TextFolding.fold(String(t.dropFirst(3))).trimmingCharacters(in: .whitespaces) == "actividad"
    }

    public func tareasListas(_ snapshot: VaultSnapshot, reloj: Reloj, ajustes: AjustesDeAsistentes) -> [Disparo] {
        Self.tareas(snapshot, reloj: reloj).compactMap { t in
            guard t.esListaParaAgente(hoy: reloj.hoy), let s = Self.slug(t.responsable), ajustes.agente(s)?.activo == true
            else { return nil }
            // F4 · corrector (R4): lo que un asistente encarga a otro solo cuenta si es una delegación apuntada
            // (`delegacion: n`, la del coordinador). Si no, no despierta a nadie: así dos asistentes no se encargan
            // tareas sin fin.
            let fm = snapshot.frontmatter(t.ruta)
            if let creador = Self.slug(fm.text("creada_por")), creador != s, fm.text("delegacion") == nil { return nil }
            let id = t.uid ?? t.ruta.raw
            return Disparo.tareaLista(id: id, ruta: t.ruta, hash: Self.huella(t, texto: snapshot.text(t.ruta)), agente: s,
                                      titulo: t.titulo)
        }
    }

    // MARK: Despertares

    public func despertares(_ snapshot: VaultSnapshot, reloj: Reloj, ajustes: AjustesDeAsistentes) -> [Disparo] {
        Self.tareas(snapshot, reloj: reloj).compactMap { t in
            guard let d = t.despertar, d <= reloj.hoy, !(t.estado?.cerrada ?? false) else { return nil }
            let s = Self.slug(t.responsable) ?? Self.slug(snapshot.frontmatter(t.ruta).text("creada_por"))
            guard let s, ajustes.agente(s)?.activo == true else { return nil }
            return Disparo.despertar(id: t.uid ?? t.ruta.raw, ruta: t.ruta, fecha: d, agente: s, titulo: t.titulo)
        }
    }

    // MARK: Menciones y comentarios

    /// Una entrada de la Actividad.
    public struct Comentario: Sendable, Hashable {
        /// `Manu`, `agente:comercial`, `sistema` o «Escrito en Obsidian» (texto sin encabezado).
        public var autor: String
        public var cabecera: String
        public var texto: String
        public var menciones: [String]
        public var esHumano: Bool {
            autor != "sistema" && !autor.hasPrefix("agente:")
        }
    }

    /// Entradas de la sección Actividad, en orden (lo escrito debajo sin encabezado cuenta como comentario humano).
    public static func comentarios(_ texto: String) -> [Comentario] {
        var out: [Comentario] = []
        var dentro = false
        var actual: (autor: String, cabecera: String, lineas: [String], evento: [String: String])?
        var sueltas: [String] = []
        var trasEvento = false
        func cerrarActual() {
            if let a = actual {
                out.append(Comentario(autor: a.autor, cabecera: a.cabecera,
                                      texto: a.lineas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                                      menciones: (a.evento["menciones"] ?? "").split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
            }
            actual = nil
            let suelto = sueltas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !suelto.isEmpty {
                out.append(Comentario(autor: "Escrito en Obsidian", cabecera: "", texto: suelto, menciones: []))
            }
            sueltas = []
            trasEvento = false
        }
        for linea in texto.components(separatedBy: "\n") {
            let t = linea.trimmingCharacters(in: .whitespaces)
            if !dentro {
                if esEncabezadoActividad(linea) { dentro = true }
                continue
            }
            if t.hasPrefix("## ") || t.hasPrefix("# ") { break }
            if t.hasPrefix("### ") {
                cerrarActual()
                let cab = String(t.dropFirst(4))
                let autor = cab.components(separatedBy: " · ").dropFirst().joined(separator: " · ").trimmingCharacters(in: .whitespaces)
                actual = (autor.isEmpty ? "Escrito en Obsidian" : autor, cab, [], [:])
                continue
            }
            if t.hasPrefix("<!-- tls:evento") {
                if let r = t.range(of: "{"), let f = t.range(of: "}", options: .backwards), r.lowerBound < f.upperBound,
                   let obj = try? JSONSerialization.jsonObject(with: Data(t[r.lowerBound..<f.upperBound].utf8)) as? [String: Any] {
                    var ev: [String: String] = [:]
                    for (k, v) in obj { ev[k] = (v as? String) ?? "\(v)" }
                    actual?.evento = ev
                }
                trasEvento = true
                continue
            }
            if t.hasPrefix("<!--") || t.hasPrefix("> Guía:") { continue }
            if actual == nil || trasEvento {
                if !t.isEmpty || !sueltas.isEmpty { sueltas.append(linea) }
            } else {
                actual?.lineas.append(linea)
            }
        }
        cerrarActual()
        return out
    }

    /// `@agente:comercial`, `@Comercial`, `@mika` → slugs del catálogo.
    public func menciones(en texto: String) -> [String] {
        var out: [String] = []
        let ns = texto as NSString
        for m in Self.patronMencion.matches(in: texto, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: m.range(at: 1))
            if let s = catalogo.slug(deMencion: token), !out.contains(s) { out.append(s) }
        }
        return out
    }

    static let patronMencion = try! NSRegularExpression(pattern: #"@((?:agente:)?[\p{L}0-9_-]+)"#)

    /// Menciones a asistentes activos en comentarios humanos (`tarea:<id>:<huella del comentario>@<slug>`).
    public func menciones(_ snapshot: VaultSnapshot, reloj: Reloj, ajustes: AjustesDeAsistentes) -> [Disparo] {
        var out: [Disparo] = []
        for t in Self.tareas(snapshot, reloj: reloj) {
            guard let texto = snapshot.text(t.ruta), texto.contains("@") else { continue }
            for c in Self.comentarios(texto) where c.esHumano {
                var slugs = menciones(en: c.texto)
                for m in c.menciones { if let s = catalogo.slug(deMencion: m), !slugs.contains(s) { slugs.append(s) } }
                for s in slugs where ajustes.agente(s)?.activo == true {
                    let h = Disparo.huella(c.cabecera + "\n" + c.texto)
                    out.append(Disparo.mencion(id: t.uid ?? t.ruta.raw, ruta: t.ruta, hashComentario: h, agente: s,
                                               titulo: t.titulo, comentario: c.texto,
                                               autor: c.autor == "Escrito en Obsidian" ? "Manu" : c.autor))
                }
            }
        }
        return out
    }

    /// Comentario humano nuevo en la ficha de una pregunta que espera respuesta: es la respuesta (escrita en Obsidian
    /// o desde la ficha). Devuelve el texto y su clave.
    public static func respuesta(en snapshot: VaultSnapshot, pregunta: String) -> (texto: String, autor: String, clave: String)? {
        let ruta = VaultPath(pregunta)
        guard pregunta.hasSuffix(".md"), !snapshot.layout.isPrivate(ruta), let texto = snapshot.text(ruta) else { return nil }
        guard let c = comentarios(texto).last(where: \.esHumano), !c.texto.isEmpty else { return nil }
        return (c.texto, c.autor == "Escrito en Obsidian" ? "Manu" : c.autor,
                "respondida:\(pregunta):\(Disparo.huella(c.cabecera + "\n" + c.texto))")
    }

    // MARK: Eventos del dominio

    /// Eventos del outbox posteriores al cursor, para los asistentes que los atienden.
    public func eventos(_ guardados: [EventoGuardado], desde: Date, ajustes: AjustesDeAsistentes) -> [Disparo] {
        var out: [Disparo] = []
        for g in guardados where g.creado > desde && g.estado != .omitido && g.estado != .deshecho {
            let e = g.evento
            guard e.profundidad < 3 else { continue }
            for rol in catalogo.atienden(evento: e.tipo.rawValue) where ajustes.agente(rol.slug)?.activo == true {
                if case .agente(let quien) = e.autor, quien == rol.slug { continue }
                let instr = rol.instruccionesPorEvento[e.tipo.rawValue] ?? "Ha pasado «\(e.tipo.rawValue)». Mira si te toca hacer algo."
                var datos = e.carga
                datos["autor"] = nil
                out.append(Disparo.evento(tipo: e.tipo.rawValue, entidad: e.entidad,
                                          version: e.plan.map { String($0.uuidString.lowercased().prefix(8)) } ?? "0",
                                          ruta: e.ruta, agente: rol.slug, instruccion: instr, datos: datos))
            }
        }
        return out
    }
}
