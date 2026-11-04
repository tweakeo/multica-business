import Foundation

/// Una tarea del plan de entrega (`| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |`).
public struct TareaDelPlan: Sendable, Hashable {
    public let titulo: String
    /// Día laborable de inicio contado desde el arranque del proyecto (0 = el primero).
    public let dia: Int
    public let dura: Int
    public let quien: String?
    public let seAcepta: String?
}

/// Una fase del plan de entrega (`## Fase 1 · Recogida`).
public struct FaseDelPlan: Sendable, Hashable, Identifiable {
    public var id: Int { numero }
    public let numero: Int
    public let nombre: String
    public let tareas: [TareaDelPlan]

    public var diaInicio: Int { tareas.map(\.dia).min() ?? 0 }
    public var diaFin: Int { tareas.map { $0.dia + max($0.dura, 1) - 1 }.max() ?? diaInicio }
}

/// Lo que dice un plan de entrega (`3 · Entrega/Planes de entrega/<servicio>.md`).
public struct PlanDeEntrega: Sendable, Hashable {
    public let fases: [FaseDelPlan]
    public let terminadoCuando: String?

    /// Lee el cuerpo de un plan: una sección `## Fase N · Nombre` con su tabla por fase.
    public static func leer(_ texto: String) -> PlanDeEntrega {
        let doc = NoteDocument(text: texto)
        var fases: [FaseDelPlan] = []
        var terminado: String?
        for titulo in MarkdownSections.titles(in: doc.body) {
            let contenido = MarkdownSections.content(of: titulo, in: doc.body, level: 2) ?? ""
            if TextFolding.fold(titulo) == "terminado cuando" {
                let t = contenido.trimmingCharacters(in: .whitespacesAndNewlines)
                terminado = t.isEmpty ? nil : t
                continue
            }
            guard let m = titulo.range(of: #"^[Ff]ase\s+(\d+)\s*[·:\-–]\s*(.+)$"#, options: .regularExpression) else { continue }
            let partes = String(titulo[m])
            let numero = Int(partes.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "") ?? fases.count + 1
            let nombre = partes.replacingOccurrences(of: #"^[Ff]ase\s+\d+\s*[·:\-–]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            fases.append(FaseDelPlan(numero: numero, nombre: nombre, tareas: tabla(contenido)))
        }
        return PlanDeEntrega(fases: fases, terminadoCuando: terminado)
    }

    static func tabla(_ contenido: String) -> [TareaDelPlan] {
        let filas = contenido.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("|") }
        guard filas.count >= 2 else { return [] }
        func celdas(_ f: String) -> [String] {
            var s = f
            if s.hasPrefix("|") { s.removeFirst() }
            if s.hasSuffix("|") { s.removeLast() }
            return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let cabecera = celdas(filas[0]).map(TextFolding.fold)
        func col(_ nombres: [String]) -> Int? { cabecera.firstIndex { nombres.contains($0) } }
        let cT = col(["tarea"]) ?? 0, cD = col(["dia"]), cDu = col(["dura"]), cQ = col(["quien"]), cA = col(["se acepta cuando"])
        return filas.dropFirst(2).compactMap { f in
            let c = celdas(f)
            func v(_ i: Int?) -> String? { i.flatMap { $0 < c.count ? c[$0] : nil }.flatMap { $0.isEmpty ? nil : $0 } }
            guard let t = v(cT) else { return nil }
            return TareaDelPlan(titulo: t, dia: Int(v(cD) ?? "") ?? 0, dura: Int(v(cDu) ?? "") ?? 1, quien: v(cQ), seAcepta: v(cA))
        }
    }
}

/// Una fase del plan aplicada a un proyecto: fechas, sus tareas y cómo va (franja «Fases del plan», §3.4).
public struct FaseDelProyecto: Sendable, Hashable, Identifiable {
    public var id: Int { fase.numero }
    public let fase: FaseDelPlan
    public let inicio: LocalDate?
    public let fin: LocalDate?
    /// Tareas del proyecto que son de esta fase.
    public let tareas: [VaultPath]
    public let hechas: Int
    /// Alguna está En curso o En revisión.
    public let enMarcha: Bool
    public let contieneHoy: Bool

    public enum Situacion: Sendable, Hashable { case hecha, enCurso, pendiente }
    public var situacion: Situacion {
        if !tareas.isEmpty && hechas == tareas.count { return .hecha }
        return enMarcha || contieneHoy ? .enCurso : .pendiente
    }
}

public enum FasesDelPlan {
    /// La fase de una tarea: su propiedad `fase` si la lleva; si no, la fase del plan con una tarea del mismo
    /// título (sin tildes ni mayúsculas, o que empiece igual).
    public static func fase(de tarea: FichaGrafo, en plan: PlanDeEntrega) -> FaseDelPlan? {
        if let f = tarea.texto("fase") {
            let k = TextFolding.fold(f)
            if let x = plan.fases.first(where: { TextFolding.fold($0.nombre) == k || "\($0.numero)" == k }) { return x }
        }
        let t = TextFolding.fold(tarea.nombre)
        for fase in plan.fases {
            for p in fase.tareas {
                let k = TextFolding.fold(p.titulo)
                if k == t || t.hasPrefix(k) || k.hasPrefix(t) { return fase }
            }
        }
        return nil
    }

    /// Las fases del plan con las fechas del proyecto (desde `inicio`, en días laborables) y sus tareas.
    public static func delProyecto(plan: PlanDeEntrega, inicio: LocalDate?, tareas: [FichaGrafo], hoy: LocalDate) -> [FaseDelProyecto] {
        plan.fases.map { fase in
            let suyas = tareas.filter { Self.fase(de: $0, en: plan)?.numero == fase.numero }
            let estados = suyas.map { $0.estado.flatMap { EstadoTarea(leyendo: $0) } }
            let hechas = estados.filter { $0 == .hecha }.count
            let vivas = estados.contains { $0 == .enCurso || $0 == .enRevision }
            let ini = inicio.map { FormatosPlantilla.sumarLaborables($0, fase.diaInicio) }
            let fin = inicio.map { FormatosPlantilla.sumarLaborables($0, fase.diaFin) }
            let hoyDentro = ini.map { $0 <= hoy } == true && fin.map { hoy <= $0 } == true
            return FaseDelProyecto(fase: fase, inicio: ini, fin: fin, tareas: suyas.map(\.ruta),
                                   hechas: hechas, enMarcha: vivas, contieneHoy: hoyDentro)
        }
    }
}
