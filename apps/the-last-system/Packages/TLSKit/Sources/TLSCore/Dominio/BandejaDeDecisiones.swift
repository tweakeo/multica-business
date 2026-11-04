import Foundation

// La bandeja de Decisiones (PLAN §5.2 «Qué es una tarjeta de la bandeja», §6.3; SISTEMAS DI1). Las tarjetas no se
// guardan en ningún sitio: salen de una consulta sobre la carpeta y el registro de conflictos cada vez que se piden.
//
// | Tarjeta | De dónde sale |
// |---|---|
// | Para aprobar (F4) | Ficha `draft` en «Pendiente de tu OK» |
// | Pregunta | Tarea `tipo: pregunta` abierta |
// | Propuesta (1-3-1) | Tarea `tipo: decision` abierta, con sus opciones |
// | Archivo en conflicto | `ConflictRegistry.pendientes()` |
//
// Presupuesto de interrupciones (PLAN §5.2): como mucho `avisos.tope_tarjetas_dia` (5) tarjetas nuevas al día que no
// sean rojas; el resto va al resumen semanal, agrupado por tipo. Una tarjeta roja (vencida, vence hoy o 14 días sin
// decidir, DIR-DEC14) siempre se ve. Nada privado entra en la bandeja.

/// Una opción de una propuesta 1-3-1 (como mucho tres).
public struct OpcionDecision: Sendable, Hashable, Identifiable {
    public var id: Int { numero }
    public let numero: Int
    public let texto: String
    public let recomendada: Bool
    public let aFavor: String?
    public let enContra: String?
    public let coste: String?
}

/// Una tarjeta de la bandeja de Decisiones.
public struct TarjetaDecision: Sendable, Hashable, Identifiable {
    public enum Tipo: String, Sendable, Hashable, CaseIterable, Comparable {
        case paraAprobar, pregunta, propuesta, conflicto

        /// Título del grupo en la lista (§6.3).
        public var grupo: String {
            switch self {
            case .paraAprobar: "Para aprobar"
            case .pregunta: "Preguntas"
            // En F2 este grupo son tus fichas `tipo: decision` (revisión final: no son «Propuestas de mejora», que es
            // lo que propone la app; cuando lleguen en F4, irán en su propio grupo).
            case .propuesta: "Por decidir"
            case .conflicto: "Archivos en conflicto"
            }
        }

        var orden: Int { Self.allCases.firstIndex(of: self)! }
        public static func < (a: Tipo, b: Tipo) -> Bool { a.orden < b.orden }
    }

    public enum Prioridad: Int, Sendable, Hashable, Comparable {
        /// Vencida, vence hoy o lleva 14 días sin decidir: siempre se ve.
        case roja = 0
        case alta = 1
        case normal = 2
        public static func < (a: Prioridad, b: Prioridad) -> Bool { a.rawValue < b.rawValue }
    }

    /// `tarea:<ruta>`, `borrador:<ruta>` o `conflicto:<id>`.
    public let id: String
    public let tipo: Tipo
    public let prioridad: Prioridad
    /// Por qué es roja o alta, en palabras («Vence hoy», «Lleva 15 días sin decidir»).
    public let motivo: String?
    public let titulo: String
    /// El problema o la pregunta, en una frase.
    public let problema: String?
    public let opciones: [OpcionDecision]
    /// Por qué se recomienda la opción recomendada (o lo que propone el asistente en una pregunta).
    public let porque: String?
    public let ruta: VaultPath?
    public let conflicto: UUID?
    public let area: AreaCode?
    public let responsable: String?
    public let creada: LocalDate?
    public let vence: LocalDate?
    /// F4 · De dónde sale si es de los asistentes (aprobación, pregunta, propuesta, CRITERIO, permisos). `nil` en las
    /// de F2. Lo rellena `BandejaDeDecisiones.consultar(_:conflictos:persona:gobierno:)` (TLSCore/Gobierno).
    public var gobierno: GobiernoDeTarjeta? = nil

    public var recomendada: OpcionDecision? { opciones.first { $0.recomendada } }
}

/// Lo que enseña la bandeja: las tarjetas que caben hoy y lo que va al resumen semanal.
public struct BandejaDeDecisiones: Sendable, Hashable {
    /// Todas las tarjetas, en orden (rojas primero, después por grupo y fecha).
    public let tarjetas: [TarjetaDecision]
    /// Las que se enseñan (presupuesto aplicado).
    public let visibles: [TarjetaDecision]
    /// Las que pasan al resumen semanal.
    public let alResumen: [TarjetaDecision]
    public let tope: Int

    /// Número de la insignia de Decisiones: lo que pide tu decisión y se ve.
    public var pendientes: Int { visibles.count }
    public var rojas: [TarjetaDecision] { tarjetas.filter { $0.prioridad == .roja } }

    /// Las visibles por grupo, en el orden de la lista (Para aprobar · Preguntas · Propuestas · Archivos en conflicto).
    public var grupos: [(tipo: TarjetaDecision.Tipo, tarjetas: [TarjetaDecision])] {
        TarjetaDecision.Tipo.allCases.compactMap { t in
            let l = visibles.filter { $0.tipo == t }
            return l.isEmpty ? nil : (t, l)
        }
    }

    /// Resumen semanal: cuántas de cada tipo quedaron fuera.
    public var resumenPorTipo: [TarjetaDecision.Tipo: Int] {
        Dictionary(grouping: alResumen, by: \.tipo).mapValues(\.count)
    }

    // MARK: Consulta

    /// Junta las tarjetas de la carpeta y del registro de conflictos.
    /// - Parameters:
    ///   - persona: si se da, solo las que te tocan a ti (o sin responsable), nunca las de un asistente.
    public static func consultar(_ lectura: LecturaDominio, conflictos: [ConflictRecord] = [], persona: String? = nil) -> BandejaDeDecisiones {
        let hoy = lectura.hoy
        var tarjetas: [TarjetaDecision] = []
        for f in lectura.fichas.values where !f.privada {
            switch f.tipo {
            case .task:
                guard let t = tarjetaDeTarea(f, lectura: lectura, persona: persona) else { continue }
                tarjetas.append(t)
            case .draft:
                guard TextFolding.fold(f.estado ?? "") == "pendiente de tu ok" else { continue }
                tarjetas.append(tarjetaDeBorrador(f, lectura: lectura))
            default:
                continue
            }
        }
        for c in conflictos where !c.resuelto && !lectura.layout.isPrivate(c.ruta) && !(c.otraRuta.map(lectura.layout.isPrivate) ?? false) {
            tarjetas.append(tarjetaDeConflicto(c, lectura: lectura))
        }
        tarjetas.sort { a, b in
            if a.prioridad != b.prioridad { return a.prioridad < b.prioridad }
            if a.tipo != b.tipo { return a.tipo < b.tipo }
            let fa = a.vence ?? a.creada ?? hoy, fb = b.vence ?? b.creada ?? hoy
            if fa != fb { return fa < fb }
            return a.titulo.localizedStandardCompare(b.titulo) == .orderedAscending
        }
        return presupuesto(tarjetas, tope: lectura.config.topeTarjetasDia)
    }

    /// La bandeja con los conflictos pendientes del escritor (`writer.conflicts`).
    public static func consultar(_ lectura: LecturaDominio, registro: ConflictRegistry, persona: String? = nil) -> BandejaDeDecisiones {
        consultar(lectura, conflictos: registro.pendientes(), persona: persona)
    }

    /// Reparte el presupuesto: las rojas siempre; de las demás, como mucho `tope` por día en que nacieron (en el
    /// orden de prioridad); el resto, al resumen semanal.
    static func presupuesto(_ tarjetas: [TarjetaDecision], tope: Int) -> BandejaDeDecisiones {
        var porDia: [String: Int] = [:]
        var visibles: [TarjetaDecision] = []
        var fuera: [TarjetaDecision] = []
        for t in tarjetas {
            if t.prioridad == .roja { visibles.append(t); continue }
            let dia = t.creada?.description ?? "sin fecha"
            let n = porDia[dia, default: 0]
            if n < tope { visibles.append(t); porDia[dia] = n + 1 } else { fuera.append(t) }
        }
        return BandejaDeDecisiones(tarjetas: tarjetas, visibles: visibles, alResumen: fuera, tope: tope)
    }

    // MARK: Tareas (preguntas y propuestas)

    static func tarjetaDeTarea(_ f: FichaDominio, lectura: LecturaDominio, persona: String?) -> TarjetaDecision? {
        let tipo: TarjetaDecision.Tipo
        switch TextFolding.fold(f.texto("tipo") ?? "") {
        case "pregunta": tipo = .pregunta
        case "decision": tipo = .propuesta
        default: return nil
        }
        if let e = f.estado.flatMap({ EstadoTarea(leyendo: $0) }), e.cerrada { return nil }
        let responsable = f.texto("responsable")
        if let r = responsable, r.lowercased().hasPrefix("agente:") { return nil }
        if let p = persona, let r = responsable, TextFolding.fold(r) != TextFolding.fold(p) { return nil }
        let texto = lectura.snapshot.text(f.ruta) ?? ""
        let cuerpo = NoteDocument(text: texto).body
        let titulo = f.texto("titulo") ?? f.nombre
        let problema = primeraFrase(MarkdownSections.content(of: tipo == .pregunta ? "Pregunta" : "Problema", in: cuerpo, level: 2))
        let opciones = tipo == .propuesta ? Self.opciones(cuerpo) : []
        var porque: String?
        if tipo == .propuesta, let r = opciones.first(where: \.recomendada) {
            porque = primeraFrase(MarkdownSections.content(of: "Por qué recomiendo la \(r.numero)", in: cuerpo, level: 2))
        } else if tipo == .pregunta {
            porque = primeraFrase(MarkdownSections.content(of: "Lo que propongo", in: cuerpo, level: 2))
        }
        let creada = f.fecha("creada")
        let vence = f.fecha("vence")
        let (prioridad, motivo) = prioridad(vence: vence, creada: creada, prioridad: f.texto("prioridad"), hoy: lectura.hoy)
        return TarjetaDecision(id: "tarea:" + f.ruta.raw, tipo: tipo, prioridad: prioridad, motivo: motivo, titulo: titulo,
                               problema: problema, opciones: opciones, porque: porque, ruta: f.ruta, conflicto: nil,
                               area: lectura.layout.area(of: f.ruta), responsable: responsable, creada: creada, vence: vence)
    }

    static func prioridad(vence: LocalDate?, creada: LocalDate?, prioridad: String?, hoy: LocalDate) -> (TarjetaDecision.Prioridad, String?) {
        if let v = vence {
            if v < hoy { return (.roja, "Venció el \(FormatosPlantilla.aplicar(v.description, formato: "corta"))") }
            if v == hoy { return (.roja, "Vence hoy") }
        }
        if let c = creada {
            let dias = dias(desde: c, hasta: hoy)
            if dias >= 14 { return (.roja, "Lleva \(dias) días sin decidir") }
        }
        switch TextFolding.fold(prioridad ?? "") {
        case "urgente": return (.alta, "Urgente")
        case "alta": return (.alta, nil)
        default: return (.normal, nil)
        }
    }

    static func dias(desde a: LocalDate, hasta b: LocalDate) -> Int {
        let s = a.date(timeZone: TimeZone(identifier: "UTC")!).timeIntervalSince1970
        let e = b.date(timeZone: TimeZone(identifier: "UTC")!).timeIntervalSince1970
        return Int(((e - s) / 86_400).rounded())
    }

    /// Opciones de la sección «Opciones»: la tabla de la plantilla 1-3-1 o una lista numerada (`1. … (recomendada)`).
    static func opciones(_ cuerpo: String) -> [OpcionDecision] {
        guard let s = MarkdownSections.content(of: "Opciones", in: cuerpo, level: 2) else { return [] }
        var out: [OpcionDecision] = []
        let lineas = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let filas = lineas.filter { $0.hasPrefix("|") }
        if filas.count >= 3 {
            func celdas(_ f: String) -> [String] {
                var t = f
                if t.hasPrefix("|") { t.removeFirst() }
                if t.hasSuffix("|") { t.removeLast() }
                return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            let cab = celdas(filas[0]).map(TextFolding.fold)
            func col(_ n: String) -> Int? { cab.firstIndex { $0.hasPrefix(n) } }
            let cN = col("#"), cO = col("opcion") ?? 1, cF = col("a favor"), cC = col("en contra"), cR = col("coste")
            for f in filas.dropFirst(2) {
                let c = celdas(f)
                func v(_ i: Int?) -> String? { i.flatMap { $0 < c.count ? c[$0] : nil }.flatMap { $0.isEmpty ? nil : $0 } }
                guard let crudo = v(cO) else { continue }
                let (texto, rec) = limpiarRecomendada(crudo)
                guard !texto.isEmpty else { continue }
                out.append(OpcionDecision(numero: Int(v(cN) ?? "") ?? out.count + 1, texto: texto, recomendada: rec,
                                          aFavor: v(cF), enContra: v(cC), coste: v(cR)))
            }
        } else {
            // Lista: «1. … (recomendada)», o en una línea «1. … · 2. … · 3. …».
            let unidas = lineas.filter { !$0.hasPrefix(">") }.joined(separator: " · ")
            let re = try! NSRegularExpression(pattern: #"(\d)[\.\)]\s+(.+?)(?=\s*(?:·\s*)?\d[\.\)]\s|$)"#)
            let ns = unidas as NSString
            for m in re.matches(in: unidas, range: NSRange(location: 0, length: ns.length)) {
                let crudo = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
                let (texto, rec) = limpiarRecomendada(crudo)
                guard !texto.isEmpty, texto != "…" else { continue }
                out.append(OpcionDecision(numero: Int(ns.substring(with: m.range(at: 1))) ?? out.count + 1, texto: texto,
                                          recomendada: rec, aFavor: nil, enContra: nil, coste: nil))
            }
        }
        out = Array(out.prefix(3))
        // Sin ninguna marcada, la 1 es la recomendada (la plantilla la pone primero).
        if !out.isEmpty, !out.contains(where: \.recomendada) {
            let p = out[0]
            out[0] = OpcionDecision(numero: p.numero, texto: p.texto, recomendada: true, aFavor: p.aFavor, enContra: p.enContra, coste: p.coste)
        }
        return out
    }

    static func limpiarRecomendada(_ s: String) -> (String, Bool) {
        var t = s
        var rec = false
        if let r = t.range(of: "(recomendada)", options: [.caseInsensitive, .diacriticInsensitive]) {
            rec = true
            t.removeSubrange(r)
        }
        return (t.trimmingCharacters(in: .whitespaces), rec)
    }

    /// Primera frase con texto de una sección (sin las guías ni las citas).
    static func primeraFrase(_ s: String?) -> String? {
        guard let s else { return nil }
        for l in s.components(separatedBy: .newlines) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix(">") || t.hasPrefix("|") || t.hasPrefix("<!--") { continue }
            return t
        }
        return nil
    }

    // MARK: Borradores (para aprobar, F4)

    static func tarjetaDeBorrador(_ f: FichaDominio, lectura: LecturaDominio) -> TarjetaDecision {
        let creada = f.fecha("creada") ?? f.fecha("fecha")
        let vence = f.fecha("vence")
        let (prioridad, motivo) = prioridad(vence: vence, creada: nil, prioridad: f.texto("prioridad"), hoy: lectura.hoy)
        let accion: String
        switch TextFolding.fold(f.texto("accion") ?? "") {
        case "enviar_correo": accion = "Enviar un correo"
        case "escribir_cliente": accion = "Escribir a un cliente"
        case "publicar": accion = "Publicar"
        case "emitir_factura": accion = "Emitir una factura"
        case "pagar": accion = "Preparar un pago"
        default: accion = "Revisar un borrador"
        }
        // F4 · corrector (revisión de experiencia, P3): la tarjeta dice a quién y por cuánto, no solo «Enviar un correo».
        var problema = accion
        if let para = f.texto("para"), !para.isEmpty { problema += " a " + para }
        if let c = f.centimos("importe") { problema += " · " + Euros.texto(c) }
        return TarjetaDecision(id: "borrador:" + f.ruta.raw, tipo: .paraAprobar, prioridad: prioridad, motivo: motivo,
                               titulo: f.texto("asunto") ?? f.nombre, problema: problema, opciones: [], porque: nil,
                               ruta: f.ruta, conflicto: nil, area: lectura.layout.area(of: f.ruta),
                               responsable: f.texto("creado_por"), creada: creada, vence: vence)
    }

    // MARK: Conflictos

    static func tarjetaDeConflicto(_ c: ConflictRecord, lectura: LecturaDominio) -> TarjetaDecision {
        let opciones: [OpcionDecision]
        switch c.tipo {
        case .duplicado:
            opciones = [OpcionDecision(numero: 1, texto: "Apartar el repetido al Archivo", recomendada: true, aFavor: nil, enContra: nil, coste: nil),
                        OpcionDecision(numero: 2, texto: "Quedarme con el repetido", recomendada: false, aFavor: nil, enContra: nil, coste: nil)]
        case .icloud:
            opciones = [OpcionDecision(numero: 1, texto: "Quedarme con la que hay ahora", recomendada: true, aFavor: nil, enContra: nil, coste: nil),
                        OpcionDecision(numero: 2, texto: "Elegir otra versión", recomendada: false, aFavor: nil, enContra: nil, coste: nil)]
        case .edicion, .recuperacion:
            opciones = [OpcionDecision(numero: 1, texto: "Combinar las dos", recomendada: true, aFavor: nil, enContra: nil, coste: nil),
                        OpcionDecision(numero: 2, texto: "Quedarme con la mía", recomendada: false, aFavor: nil, enContra: nil, coste: nil),
                        OpcionDecision(numero: 3, texto: "Quedarme con la de fuera", recomendada: false, aFavor: nil, enContra: nil, coste: nil)]
        }
        let dia = LocalDate(date: c.fecha, timeZone: lectura.reloj.zona)
        return TarjetaDecision(id: "conflicto:" + c.id.uuidString.lowercased(), tipo: .conflicto, prioridad: .alta,
                               motivo: nil, titulo: c.titulo, problema: c.detalle,
                               opciones: opciones, porque: nil, ruta: c.ruta, conflicto: c.id,
                               area: lectura.layout.area(of: c.ruta), responsable: nil, creada: dia, vence: nil)
    }
}
