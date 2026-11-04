import Foundation

// Lo que queda de cada trabajo de un asistente (PLAN §4.2 Actividad, §4.4 Bitácora, §5.3 «Stream»): al CERRAR la
// ejecución (no evento a evento, para no pelear con iCloud), una entrada en la Actividad de la ficha de la tarea
//
//   ### 2026-10-21 10:32 · agente:comercial
//   Estado: Por hacer → En revisión. Preparé el seguimiento del día 7: [borrador](../Borradores/seguimiento-nexo-d7.md). …
//   <!-- tls:evento {"id":"ev-…","tipo":"ejecucion","de":"Por hacer","a":"En revisión","run":"r-7f3a","coste_usd":0.04,"aprobacion":"apr-91c2"} -->
//
// y una línea en la Bitácora del mes. Lo escribe la app (`Autor.sistema`) en un solo plan que se puede deshacer: así
// queda constancia aunque el interruptor se apague a mitad o el trabajo termine con error.

/// Cómo terminó un trabajo.
public enum FinDeTrabajo: Sendable, Hashable {
    case hecho
    case pendienteDeAprobacion
    case esperandoRespuesta
    case propuesta
    case sinCambios
    case cancelado
    case fallido(String)

    /// Como se escribe en la Bitácora.
    public var texto: String {
        switch self {
        case .hecho: "hecho"
        case .pendienteDeAprobacion: "pendiente de aprobación"
        case .esperandoRespuesta: "esperando respuesta"
        case .propuesta: "propuesta para ti"
        case .sinCambios: "sin cambios"
        case .cancelado: "cancelado"
        case .fallido(let m): "con error: " + m
        }
    }
}

/// Resumen de una ejecución que se cierra (lo da el motor de los asistentes).
public struct ResumenDeTrabajo: Sendable, Hashable {
    /// `r-7f3a…`.
    public var ejecucion: String
    /// `comercial`.
    public var agente: String
    /// Tarea en la que trabajó (si la hay): recibe la entrada de Actividad.
    public var tarea: VaultPath?
    public var capacidad: String?
    /// Qué hizo, en lenguaje llano (va a la Actividad y, en una frase, a la Bitácora).
    public var texto: String
    /// Frase corta para la Bitácora (por defecto, la primera de `texto`).
    public var frase: String?
    public var fin: FinDeTrabajo
    /// Estado de la tarea antes y después (si cambió). Nunca Hecha ni Cancelada.
    public var estadoDe: String?
    public var estadoA: EstadoTarea?
    /// Uso que devolvió Claude Code (`total_cost_usd`).
    public var costeUSD: Double?
    /// Aprobación que pidió (`apr-…`).
    public var aprobacion: String?
    /// Huella que se apunta en la Bitácora (la de la aprobación, si la hay).
    public var hash: String?
    /// Detalle técnico para «Detalle técnico» (va en el evento, no en el texto).
    public var detalle: [String: String]

    public init(ejecucion: String, agente: String, tarea: VaultPath? = nil, capacidad: String? = nil, texto: String,
                frase: String? = nil, fin: FinDeTrabajo = .hecho, estadoDe: String? = nil, estadoA: EstadoTarea? = nil,
                costeUSD: Double? = nil, aprobacion: String? = nil, hash: String? = nil, detalle: [String: String] = [:]) {
        self.ejecucion = ejecucion; self.agente = ConfigAgentes.slug(agente); self.tarea = tarea; self.capacidad = capacidad
        self.texto = texto; self.frase = frase; self.fin = fin; self.estadoDe = estadoDe; self.estadoA = estadoA
        self.costeUSD = costeUSD; self.aprobacion = aprobacion; self.hash = hash; self.detalle = detalle
    }
}

public enum ActividadDeAsistente {
    /// Plan del cierre: la entrada de Actividad (si hay tarea), el cambio de estado (nunca a Hecha ni Cancelada) y la
    /// línea de la Bitácora. Lo escribe la app.
    public static func plan(_ r: ResumenDeTrabajo, snapshot: VaultSnapshot, reloj: Reloj? = nil,
                            persona: String = "Manu") throws -> WritePlan {
        let reloj = reloj ?? Reloj.deCarpeta(snapshot)
        var ops: [WriteOp] = []
        let autor = Autor.agente(r.agente)
        if let ruta = r.tarea, let real = snapshot.existing(ruta) {
            guard !snapshot.layout.isPrivate(real) else { throw ErrorDeGobierno.noEncontrado(ruta.stem) }
            guard let text = snapshot.text(real), let data = snapshot.data(real) else { throw TareaError.noEsTarea(ruta.raw) }
            let encabezado = "### \(reloj.hoy) \(reloj.hora) · "
            // Un comentario escrito a mano debajo de la última entrada recibe su encabezado (sin tocar su texto).
            if let offset = TaskStore.comentarioSinEncabezado(text) {
                let eol = TextLines.dominantEOL(text)
                ops.append(.editRanges(real, edits: [TextEdit(offset: offset, length: 0, replacement: encabezado + persona + eol)],
                                       baseHash: ContentHash.of(data)))
            }
            // F4 · corrector (R3): el resumen lo escribió el asistente (`tls_finalizar`): sin estructura de la app.
            var cuerpo = TextoDeAsistente.neutralizar(r.texto.trimmingCharacters(in: .whitespacesAndNewlines))
            if let a = r.estadoA, let de = r.estadoDe, TextFolding.fold(de) != TextFolding.fold(a.rawValue) {
                cuerpo = "Estado: \(de) → \(a.rawValue). " + cuerpo
            }
            ops.append(.appendToSection(real, section: "Actividad",
                                        text: encabezado + autor.etiqueta + "\n" + cuerpo + "\n" + evento(r), blankLine: true))
            if let a = r.estadoA {
                guard !a.cerrada else { throw TareaError.noPermitidoAgente(a.rawValue) }
                let actual = snapshot.frontmatter(real).text("estado").flatMap(EstadoTarea.init(leyendo:))
                if actual != a {
                    ops.insert(.mergeFrontmatter(real, set: [Property(key: "estado", value: .text(a.rawValue))], unset: []),
                               at: ops.count - 1)
                }
            }
        }
        let linea = LineaBitacora(fecha: reloj.hoy, hora: reloj.hora, agente: r.agente, capacidad: r.capacidad,
                                  que: TextoDeAsistente.linea(r.frase ?? primeraFrase(r.texto)), resultado: r.fin.texto, usoUSD: r.costeUSD,
                                  ejecucion: r.ejecucion, hash: r.hash)
        ops += Bitacora.ops([linea], layout: snapshot.layout) { snapshot.existing($0) != nil }
        return WritePlan(autor: .sistema, descripcion: "Trabajo de \(AsistenteConfigurado.nombre(de: r.agente)) (asistente)",
                         ops: ops)
    }

    /// `<!-- tls:evento {…} -->` con números de verdad para el uso.
    static func evento(_ r: ResumenDeTrabajo) -> String {
        var c: [String: Any] = ["id": "ev-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(6)),
                                "tipo": "ejecucion", "run": r.ejecucion, "fin": r.fin.texto]
        if let de = r.estadoDe { c["de"] = de }
        if let a = r.estadoA { c["a"] = a.rawValue }
        if let u = r.costeUSD { c["coste_usd"] = (u * 10_000).rounded() / 10_000 }
        if let a = r.aprobacion { c["aprobacion"] = a }
        if let cap = r.capacidad { c["capacidad"] = cap }
        for (k, v) in r.detalle where c[k] == nil { c[k] = v }
        let data = (try? JSONSerialization.data(withJSONObject: c, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "-->", with: "--\\u003e").replacingOccurrences(of: "<!--", with: "\\u003c!--")
        return "<!-- tls:evento \(json) -->"
    }

    static func primeraFrase(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
        if let r = t.range(of: ". ") { return String(t[..<r.lowerBound]) }
        return t.hasSuffix(".") ? String(t.dropLast()) : t
    }
}
