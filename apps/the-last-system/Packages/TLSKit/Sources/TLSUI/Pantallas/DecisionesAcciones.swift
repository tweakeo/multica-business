import Foundation
import TLSCore
import TLSDesign

// Lo que hay detrás de una tarjeta de Decisiones (PLAN §6.3) y lo que escribe decidir. Puro: con la foto de la carpeta
// y el reloj devuelve textos y planes (`WritePlan`, todo o nada, un solo Deshacer) que la pantalla ejecuta como la
// persona y a través del dominio (`escribirConDominio`). Decidir deja **una línea** en `Decisiones.md` con su origen
// (la tarea) y cierra la tarea con su Actividad. Nada sale de la carpeta desde aquí: aprobar lo que preparan los
// asistentes (enviar, publicar, emitir) va por `Aprobaciones` y la hoja que dice qué sale, a quién y por cuánto
// (F4 · `DecisionesAprobacion.swift`); el resto de lo de los asistentes, en `DecisionesGobierno.swift`.

/// Una evidencia enlazada: una ficha, una nota o un fichero de la carpeta (nunca lo privado).
struct EvidenciaDecision: Sendable, Hashable, Identifiable {
    var id: VaultPath { ruta }
    let titulo: String
    let ruta: VaultPath
}

/// El detalle 1-3-1 de una tarjeta: el problema en una frase, como mucho 3 opciones con la recomendada y su porqué, las
/// evidencias y qué pasa si se pospone.
struct DetalleDecision: Sendable, Hashable {
    let tarjeta: TarjetaDecision
    /// «La pide Comercial (asistente)», «La propone la app», «Te la preguntas tú».
    let quien: String
    /// «desde el lun 19 oct», «hoy».
    let desde: String?
    let evidencias: [EvidenciaDecision]
    /// «Qué cambia si se aprueba» de la nota, si lo dice.
    let queCambia: String?
    let siSePospone: String
    /// Lo que no se puede hacer aún y por qué (`nil` = se puede decidir aquí).
    let motivoNoDecidir: String?
    /// F4 · las respuestas que propone un asistente en su pregunta («Lo que propongo»: `1. … (recomendada)`).
    var respuestas: [RespuestaPropuesta] = []
    /// F5 · corrector (P1-1): un correo que preparó un asistente (el Cartero) sin pedir la aprobación: «Revisar y
    /// aprobar…» lo prepara para aprobar aquí y, al aprobar, se abre en Mail.
    var correoParaPreparar = false

    var opciones: [OpcionDecision] { tarjeta.opciones }
    var recomendada: OpcionDecision? { tarjeta.recomendada }

    static func de(_ t: TarjetaDecision, foto: VaultSnapshot, hoy: LocalDate, tareas: TaskStore? = nil,
                   resolver: LinkResolver? = nil) -> DetalleDecision {
        let texto = t.ruta.flatMap { foto.text($0) } ?? ""
        let cuerpo = NoteDocument(text: texto).body
        var evid: [EvidenciaDecision] = []
        let propia = t.tipo == .conflicto ? nil : t.ruta
        func anadir(_ r: VaultPath?) {
            guard let r, r != propia, !foto.layout.isPrivate(r), !evid.contains(where: { $0.ruta == r }),
                  foto.existing(r) != nil else { return }
            evid.append(EvidenciaDecision(titulo: titulo(r, foto: foto), ruta: r))
        }
        if let ruta = t.ruta, t.tipo != .conflicto {
            let resolver = resolver ?? foto.resolver
            for s in ["Problema", "Pregunta", "Datos que hay", "Por qué la hago", "Lo que propongo", "Opciones"] {
                guard let sec = MarkdownSections.content(of: s, in: cuerpo, level: 2) else { continue }
                for l in LinkParser.links(in: sec) where !l.isExternal {
                    anadir(resolver.resolve(l.resolvable, from: ruta))
                }
            }
            if let tarea = (tareas ?? TaskStore(snapshot: foto)).tarea(ruta) {
                anadir(tarea.proyecto)
                anadir(tarea.oportunidad)
                anadir(tarea.empresa)
            }
        }
        if t.tipo == .conflicto { anadir(t.ruta) }
        let queCambia = BandejaPrimeraFrase.de(MarkdownSections.content(of: "Qué cambia si se aprueba", in: cuerpo, level: 2))
        let correo = correoParaPreparar(t, texto: texto, foto: foto)
        return DetalleDecision(tarjeta: t, quien: quien(t), desde: desde(t, hoy: hoy), evidencias: evid,
                               queCambia: queCambia, siSePospone: siSePospone(t, cuerpo: cuerpo, hoy: hoy),
                               motivoNoDecidir: correo ? nil : motivo(t),
                               respuestas: t.tipo == .pregunta ? RespuestaPropuesta.de(cuerpo) : [],
                               correoParaPreparar: correo)
    }

    /// ¿Es un correo de un asistente, en borrador y sin petición de aprobación?
    static func correoParaPreparar(_ t: TarjetaDecision, texto: String, foto: VaultSnapshot) -> Bool {
        guard t.tipo == .paraAprobar, t.gobierno?.aprobacion == nil, let r = t.ruta,
              let b = Borrador.leer(r, texto: texto, layout: foto.layout), b.asistente != nil else { return false }
        let accion = b.accion ?? .enviarCorreo
        return accion == .enviarCorreo || accion == .escribirCliente
    }

    /// El título de una nota: `titulo`/`title` de sus propiedades o su primer `# …`.
    static func tituloDeTexto(_ texto: String) -> String? {
        let doc = NoteDocument(text: texto)
        for k in ["titulo", "title", "asunto", "name"] {
            if let v = doc.frontmatter.properties.first(where: { $0.key == k })?.value.displayText, !v.isEmpty {
                return LinkParser.plainText(v)
            }
        }
        for l in doc.body.split(separator: "\n", omittingEmptySubsequences: false).prefix(60) where l.hasPrefix("# ") {
            return String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func titulo(_ r: VaultPath, foto: VaultSnapshot) -> String {
        let fm = foto.frontmatter(r)
        for k in ["title", "name", "asunto"] {
            if let v = fm.text(k) { return LinkParser.plainText(v) }
        }
        return r.stem
    }

    static func quien(_ t: TarjetaDecision) -> String {
        // F4 · lo que traen los asistentes dice quién lo trae.
        if let g = t.gobierno {
            let nombre = g.asistente.map { AsistenteConfigurado.nombre(de: $0) + " (asistente)" }
            switch g.clase {
            case .aprobacion: if let n = nombre { return "Lo prepara \(n)" }
            case .pregunta: if let n = nombre { return "Te lo pregunta \(n)" }
            case .propuesta, .mejora: if let n = nombre { return "La propone \(n)" }
            case .criterio: return "La deja la app: tres veces igual con \(nombre ?? "un asistente")"
            case .cambioDePermisos: return "La deja la app: alguien cambió los permisos de los asistentes fuera de ella"
            }
        }
        switch t.tipo {
        case .conflicto: return "La deja la app al ver dos versiones del mismo fichero"
        case .paraAprobar:
            if let r = t.responsable, r.lowercased().hasPrefix("agente:") { return "Lo prepara \(nombreAsistente(r)) (asistente)" }
            return "Borrador por aprobar"
        case .pregunta, .propuesta:
            guard let r = t.responsable, !r.isEmpty else { return t.tipo == .pregunta ? "Una pregunta para ti" : "Una decisión tuya" }
            if r.lowercased().hasPrefix("agente:") { return "La prepara \(nombreAsistente(r)) (asistente)" }
            return "La decide \(LinkParser.plainText(r))"
        }
    }

    static func nombreAsistente(_ r: String) -> String {
        let s = String(r.dropFirst("agente:".count))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    static func desde(_ t: TarjetaDecision, hoy: LocalDate) -> String? {
        guard let c = t.creada else { return nil }
        if c == hoy { return "hoy" }
        if c == hoy.adding(days: -1) { return "desde ayer" }
        return "desde el \(FormatoBase.fechaConDia(c))"
    }

    static func siSePospone(_ t: TarjetaDecision, cuerpo: String, hoy: LocalDate) -> String {
        for s in ["Si se pospone", "Si lo pospones", "Qué pasa si se pospone"] {
            if let f = BandejaPrimeraFrase.de(MarkdownSections.content(of: s, in: cuerpo, level: 2)) { return f }
        }
        switch t.gobierno?.clase {
        case .aprobacion:
            return "No sale nada hasta que lo apruebes. A los 14 días sin decidir caduca y habría que volver a prepararlo."
        case .cambioDePermisos:
            return "Los asistentes siguen con los permisos que confirmaste (y con lo nuevo que sea más estricto)."
        case .criterio:
            return "Sigues revisando como hasta ahora; la tarjeta espera."
        case .pregunta where t.vence == nil:
            return "El asistente se queda esperando tu respuesta; no sigue con ese trabajo."
        default:
            break
        }
        if let v = t.vence {
            if v < hoy { return "Ya venció el \(FormatoBase.fechaConDia(v)): cada día que pasa cuenta como retraso." }
            if v == hoy { return "Vence hoy: mañana ya irá con retraso." }
            return "Vence el \(FormatoBase.fechaConDia(v)). Hasta entonces sigue aquí."
        }
        if let c = t.creada {
            let dias = BandejaDias.entre(c, hoy)
            if dias >= 14 { return "Lleva \(dias) días sin decidir: cuenta en las decisiones atascadas de Dirección." }
            return "Sigue esperando. A los 14 días sin decidir se pone en rojo (le quedan \(14 - dias))."
        }
        switch t.tipo {
        case .conflicto: return "Las dos versiones se quedan como están; nada se pierde."
        case .paraAprobar: return "No sale nada hasta que lo apruebes."
        default: return "Sigue esperando en Decisiones."
        }
    }

    static func motivo(_ t: TarjetaDecision) -> String? {
        switch t.tipo {
        // F4: se aprueba aquí lo que un asistente pidió aprobar (con su registro en las aprobaciones). Un borrador
        // «Pendiente de tu OK» sin petición (escrito a mano, o de otra versión) se revisa en su ficha.
        case .paraAprobar where t.gobierno?.aprobacion == nil:
            "Ningún asistente ha pedido aprobar este borrador: ábrelo para revisarlo."
        default: nil
        }
    }
}

/// Primera frase con texto de una sección (sin guías ni citas).
enum BandejaPrimeraFrase {
    static func de(_ s: String?) -> String? {
        guard let s else { return nil }
        for l in s.components(separatedBy: .newlines) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix(">") || t.hasPrefix("|") || t.hasPrefix("<!--") { continue }
            return LinkParser.plainText(t)
        }
        return nil
    }
}

enum ErrorDecision: Error, LocalizedError, Equatable {
    case sinTarea
    case noSeDecideAqui
    case sinTexto

    var errorDescription: String? {
        switch self {
        case .sinTarea: "No encuentro la tarea de esta decisión. Puede que alguien la haya movido fuera de la app."
        case .noSeDecideAqui: "Esto no se decide aquí: ábrelo para resolverlo."
        case .sinTexto: "Escribe qué decides en una frase."
        }
    }
}

/// Planes de escritura de Decisiones. Siempre como la persona.
enum AccionesDecision {
    /// Decidir una propuesta o una pregunta: añade la línea a `Decisiones.md` (con su origen, la tarea) y cierra la
    /// tarea (Hecha) dejando en su Actividad lo decidido. Un solo plan; deshacer deja los mismos bytes.
    static func planDecidir(_ t: TarjetaDecision, decision: String, porque: String?, opcion: OpcionDecision?,
                            foto: VaultSnapshot, reloj: Reloj, persona: String) throws -> (plan: WritePlan, id: String) {
        guard t.tipo == .propuesta || t.tipo == .pregunta, let ruta = t.ruta else { throw ErrorDecision.noSeDecideAqui }
        let texto = decision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { throw ErrorDecision.sinTexto }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        guard let tarea = store.tarea(ruta) else { throw ErrorDecision.sinTarea }
        let autor = Autor.persona(persona)
        let registro = foto.existing(RegistroDecisiones.ruta(foto.layout)) ?? RegistroDecisiones.ruta(foto.layout)
        // El registro separa los campos con « · »: el nombre del enlace no lo lleva.
        let nombre = tarea.titulo + (tarea.numero.map { " (\($0))" } ?? "")
        let origen = NombresDeFicha.enlaceMarkdown(nombre, desde: registro, a: ruta)
        let area = (t.area ?? tarea.area)?.nombre
        let porqueLimpio = porque?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nueva = NuevaDecision(fecha: reloj.hoy, decision: texto, porque: porqueLimpio?.isEmpty == false ? porqueLimpio : nil,
                                  area: area, origen: origen)
        let (planRegistro, id) = try RegistroDecisiones.anadir(nueva, en: foto, autor: autor)
        let nota = "Decidido" + (opcion.map { " (opción \($0.numero))" } ?? "") + ": \(texto). Queda en el registro de decisiones."
        let planTarea = try store.cambiarEstado(tarea, a: .hecha, autor: autor, persona: persona, nota: nota)
        let plan = WritePlan(autor: autor, descripcion: "Decidir «\(corto(tarea.titulo))»", ops: planRegistro.ops + planTarea.ops)
        return (plan, id)
    }

    /// Responder: una pregunta se contesta y se cierra; en una propuesta, la respuesta queda en su Actividad (sigue abierta).
    static func planResponder(_ t: TarjetaDecision, respuesta: String, foto: VaultSnapshot, reloj: Reloj, persona: String) throws -> WritePlan {
        guard t.tipo == .propuesta || t.tipo == .pregunta, let ruta = t.ruta else { throw ErrorDecision.noSeDecideAqui }
        let texto = respuesta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { throw ErrorDecision.sinTexto }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        guard let tarea = store.tarea(ruta) else { throw ErrorDecision.sinTarea }
        let autor = Autor.persona(persona)
        if t.tipo == .pregunta {
            return try store.cambiarEstado(tarea, a: .hecha, autor: autor, persona: persona, nota: "Respuesta: \(texto)")
        }
        return try store.anadirActividad(tarea, autor: autor, texto: texto, evento: ["tipo": "comentario"], persona: persona)
    }

    /// Descartar: la tarea pasa a Cancelada, con el motivo en su Actividad. No se apunta en el registro.
    static func planDescartar(_ t: TarjetaDecision, motivo: String?, foto: VaultSnapshot, reloj: Reloj, persona: String) throws -> WritePlan {
        guard t.tipo == .propuesta || t.tipo == .pregunta, let ruta = t.ruta else { throw ErrorDecision.noSeDecideAqui }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        guard let tarea = store.tarea(ruta) else { throw ErrorDecision.sinTarea }
        let m = motivo?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try store.cambiarEstado(tarea, a: .cancelada, autor: .persona(persona), persona: persona,
                                       nota: "Descartada" + (m?.isEmpty == false ? ": \(m!)" : "") + ".")
    }

    static func corto(_ s: String) -> String { s.count > 60 ? String(s.prefix(57)) + "…" : s }
}
