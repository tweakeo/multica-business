import Foundation

/// Varias fichas de tarea en un solo plan (todo o nada), con números seguidos: las tareas de un plan de entrega al
/// crear el proyecto (ENT-02). Cada ficha sale igual que con `TaskStore.crear` (misma plantilla, mismo orden de
/// propiedades); el contador de `.tls/secuencias.json` sube una vez, al último número.
enum TareasEnLote {
    static func preparar(_ nuevas: [NuevaTarea], snapshot: VaultSnapshot, reloj: Reloj, autor: Autor,
                         descripcion: String) throws -> (plan: WritePlan, rutas: [VaultPath])? {
        guard !nuevas.isEmpty else { return nil }
        let store = TaskStore(snapshot: snapshot, reloj: reloj)
        let primero = store.siguienteNumero()
        var ops: [WriteOp] = []
        var rutas: [VaultPath] = []
        var ocupadas = Set<String>()
        for (i, nueva) in nuevas.enumerated() {
            let titulo = nueva.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !titulo.isEmpty else { throw TareaError.tituloVacio }
            let n = primero + i
            let motor = PlantillaMotor(snapshot: snapshot, opciones: .init(yo: nueva.autor.etiqueta, reloj: reloj))
            let area = nueva.area ?? nueva.proyecto.flatMap { snapshot.layout.area(of: $0) }
                ?? nueva.oportunidad.flatMap { snapshot.layout.area(of: $0) } ?? .direccion
            var valores: [String: String] = ["titulo": titulo, "numero": String(format: "T-%04d", n),
                                             "slug": NombresDeFicha.slug(titulo, maximo: TareaArchivo.maximoSlug)]
            if let r = nueva.responsable { valores["responsable"] = r }
            var contexto: [String: VaultPath] = [:]
            if let p = nueva.proyecto { contexto["proyecto"] = p }
            if let o = nueva.oportunidad { contexto["oportunidad"] = o }
            if let e = nueva.empresa { contexto["empresa"] = e }
            var poner: [Property] = []
            if let e = nueva.estado { poner.append(Property(key: "estado", value: .text(e.rawValue))) }
            if let p = nueva.prioridad { poner.append(Property(key: "prioridad", value: .text(p))) }
            if let t = nueva.tipo { poner.append(Property(key: "tipo", value: .text(t))) }
            if let d = nueva.planificada { poner.append(Property(key: "planificada", value: .text(Tarea.laborable(d).description))) }
            if let d = nueva.vence { poner.append(Property(key: "vence", value: .text(d.description))) }
            if let o = nueva.origen { poner.append(Property(key: "origen", value: .text(o))) }
            poner += nueva.propiedades
            var secciones: [String: String] = [:]
            if let d = nueva.descripcion, !d.isEmpty { secciones["Descripción"] = d }
            let peticion = PlantillaMotor.Peticion(plantilla: nueva.plantilla, contexto: contexto, valores: valores, poner: poner,
                                                   secciones: secciones, area: area,
                                                   carpeta: store.carpeta(area: area, proyecto: nueva.proyecto), autor: nueva.autor)
            let nota = try motor.preparar(peticion)
            // Dos tareas del mismo lote con el mismo título no pueden ir al mismo nombre (el número ya las separa).
            guard ocupadas.insert(TextFolding.pathKey(nota.ruta.raw)).inserted else { throw WriteError.destinoOcupado(nota.ruta.raw) }
            ops += nota.plan.ops.filter { TextFolding.pathKey($0.path.raw) != TextFolding.pathKey(Secuencias.ruta.raw) }
            rutas.append(nota.ruta)
        }
        if let op = Secuencias.op(["tarea": primero + nuevas.count - 1], en: snapshot) { ops.append(op) }
        return (WritePlan(autor: autor, descripcion: descripcion, ops: ops), rutas)
    }
}
