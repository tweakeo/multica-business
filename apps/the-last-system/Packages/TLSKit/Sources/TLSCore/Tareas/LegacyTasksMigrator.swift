import Foundation

/// Propuesta para pasar un `Tareas.md` heredado a fichas (PLAN §4.7). Se aplica con tu OK.
public struct MigracionTareas: Sendable {
    /// El `Tareas.md` heredado.
    public let fichero: VaultPath
    public let lineas: [LineaChecklist]
    /// Las fichas nuevas, en el orden de las líneas.
    public let fichas: [PlantillaMotor.NotaPreparada]
    /// Crear las fichas, subir el contador y retirar el `Tareas.md` a `Archivo/`. Todo o nada.
    public let plan: WritePlan

    public var resumen: String {
        lineas.isEmpty
            ? "«\(fichero.raw)» no tiene tareas: se retira al Archivo."
            : "Pasar " + Plural.de(lineas.count, "tarea", "tareas") + " de «\(fichero.raw)» a fichas y retirar el fichero al Archivo."
    }
}

/// Convierte los `Tareas.md` heredados (casillas G1/G3) en una ficha por tarea y retira el fichero.
public struct LegacyTasksMigrator: Sendable {
    public let snapshot: VaultSnapshot
    public let reloj: Reloj

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.snapshot = snapshot
        self.reloj = reloj ?? Reloj.deCarpeta(snapshot)
    }

    /// Los `Tareas.md` de la carpeta (fuera del Archivo y de las plantillas).
    public func encontrar() -> [VaultPath] {
        snapshot.notes.filter { p in
            TextFolding.nameKey(p.name) == TextFolding.nameKey(snapshot.layout.tareas + ".md")
                && !snapshot.layout.isArchived(p) && !VaultSnapshot.isTemplatePath(p)
                && !snapshot.layout.isPrivate(p)  // Lo privado no se propone ni se toca (integración F2).
        }
    }

    /// Estados de G1 que no existen en la ficha.
    static func estado(_ l: LineaChecklist) -> EstadoTarea {
        if l.hecho { return .hecha }
        switch l.estado {
        case "En progreso": return .enCurso
        case "Revisar": return .enRevision
        case "Esperando respuesta", "Objeción", "Bloqueado": return .bloqueada
        default: return .porHacer
        }
    }

    public func proponer(_ fichero: VaultPath, autor: Autor = .persona("Manu"), primerNumero: Int? = nil) throws -> MigracionTareas {
        guard let text = snapshot.text(fichero) else { throw TareaError.noEsTarea(fichero.raw) }
        let lineas = ChecklistParser.parse(NoteDocument(text: text).body)
        let store = TaskStore(snapshot: snapshot, reloj: reloj)
        let layout = snapshot.layout
        let carpetaFichero = fichero.parent ?? .root
        let areaFichero = layout.area(of: fichero)
        // En la carpeta de un proyecto (`…/Proyectos/<slug>/Tareas.md`), las fichas son de ese proyecto.
        let proyecto: VaultPath? = {
            let c = carpetaFichero.components
            guard c.count >= 2, TextFolding.nameKey(c[c.count - 2]) == TextFolding.nameKey(layout.proyectos) else { return nil }
            return snapshot.existing(carpetaFichero.appending("Proyecto.md"))
        }()
        let motor = PlantillaMotor(snapshot: snapshot, opciones: .init(yo: "sistema", reloj: reloj))
        let resolver = snapshot.resolver
        let ids = snapshot.idIndex()
        var n = primerNumero ?? store.siguienteNumero()
        var fichas: [PlantillaMotor.NotaPreparada] = []
        for l in lineas {
            let titulo = l.titulo.isEmpty ? "Tarea sin título" : l.titulo
            let area = areaFichero ?? l.area ?? .direccion
            let carpeta = areaFichero != nil ? carpetaFichero.appending(layout.tareas) : store.carpeta(area: area, proyecto: nil)
            let estado = Self.estado(l)
            var poner: [Property] = [
                Property(key: "estado", value: .text(estado.rawValue)),
                Property(key: "origen", value: .text("importacion")),
                Property(key: "creada_por", value: .text("sistema")),
                Property(key: "fecha_corte", value: .text(reloj.hoy.description)),
            ]
            if let p = l.prioridad { poner.append(Property(key: "prioridad", value: .text(p == "Urgente" ? "Urgente" : "Alta"))) }
            if let f = l.fecha.flatMap({ LocalDate(parsing: $0) }) {
                poner.append(Property(key: "planificada", value: .text(Tarea.laborable(f).description)))
            }
            if let v = l.vence { poner.append(Property(key: "vence", value: .text(v))) }
            if let h = l.horas { poner.append(Property(key: "estimacion_h", value: .number(Self.numero(h)))) }
            if let h = l.invertidas, h > 0 { poner.append(Property(key: "dedicadas_h", value: .number(Self.numero(h)))) }
            if estado.cerrada { poner.append(Property(key: "cerrada", value: .text(reloj.hoy.description))) }
            var contexto: [String: VaultPath] = [:]
            if let p = proyecto { contexto["proyecto"] = p }
            var sinResolver: String?
            if let op = l.oportunidad {
                if let destino = ContextoPlantilla.resolve(op, from: fichero, resolver: resolver, ids: { ids[$0.lowercased()] }) {
                    contexto["oportunidad"] = destino
                } else { sinResolver = op }
            }
            var valores: [String: String] = ["titulo": titulo, "numero": String(format: "T-%04d", n),
                                             "slug": NombresDeFicha.slug(titulo, maximo: TareaArchivo.maximoSlug)]
            if let r = l.responsable, r != "titular" { valores["responsable"] = r }
            var detalles = ["Importada de «\(fichero.raw)» (línea \(l.linea))."]
            if let e = l.estado { detalles.append("Estado original: \(e).") }
            if let h = l.horizonte { detalles.append("Horizonte original: \(h).") }
            if let s = sinResolver { detalles.append("Oportunidad sin encontrar: \(s).") }
            if let a = l.areaTexto, l.area == nil { detalles.append("Área sin reconocer: \(a).") }
            var evento = ["tipo": "importacion", "fichero": fichero.raw]
            if let t = l.token { evento["token"] = t }
            let actividad = "<!-- tls:actividad · para comentar, escribe debajo de la última entrada -->\n\n"
                + "### \(reloj.hoy) \(reloj.hora) · sistema\n" + detalles.joined(separator: " ") + "\n"
                + TaskStore.comentarioEvento(evento)
            var secciones = ["Actividad": actividad]
            if let notas = l.notas { secciones["Descripción"] = notas }
            let peticion = PlantillaMotor.Peticion(plantilla: "tarea", contexto: contexto, valores: valores, poner: poner,
                                                   secciones: secciones, area: area, carpeta: carpeta, autor: .sistema)
            fichas.append(try motor.preparar(peticion))
            n += 1
        }
        var ops: [WriteOp] = fichas.flatMap { $0.plan.ops.filter { if case .create = $0 { return true } else { return false } } }
        if !fichas.isEmpty, let op = Secuencias.op(["tarea": n - 1], en: snapshot) { ops.append(op) }
        ops.append(.retire(fichero))
        let desc = lineas.isEmpty ? "Retirar «\(fichero.raw)»" : "Pasar a fichas las tareas de «\(fichero.raw)»"
        return MigracionTareas(fichero: fichero, lineas: lineas, fichas: fichas, plan: WritePlan(autor: autor, descripcion: desc, ops: ops))
    }

    /// Todos los `Tareas.md` en un solo plan (numeración seguida).
    public func proponerTodos(autor: Autor = .persona("Manu")) throws -> (migraciones: [MigracionTareas], plan: WritePlan)? {
        let ficheros = encontrar()
        guard !ficheros.isEmpty else { return nil }
        var n = TaskStore(snapshot: snapshot, reloj: reloj).siguienteNumero()
        var migraciones: [MigracionTareas] = []
        var ops: [WriteOp] = []
        for f in ficheros {
            let m = try proponer(f, autor: autor, primerNumero: n)
            n += m.lineas.count
            migraciones.append(m)
            ops += m.plan.ops.filter { if case .editRanges(let p, _, _) = $0, p == Secuencias.ruta { return false }
                if case .create(let p, _) = $0, p == Secuencias.ruta { return false }
                return true }
        }
        if n > TaskStore(snapshot: snapshot, reloj: reloj).siguienteNumero(), let op = Secuencias.op(["tarea": n - 1], en: snapshot) {
            ops.append(op)
        }
        return (migraciones, WritePlan(autor: autor, descripcion: "Pasar a fichas los Tareas.md heredados", ops: ops))
    }

    static func numero(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
