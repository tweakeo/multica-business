import Foundation
import TLSCore

// F2 · rol tareas. Lo que hay que revisar de las tareas (PLAN §4.2 y §4.7): `Tareas.md` heredados que pasan a fichas
// con tu OK (`LegacyTasksMigrator`), «Adoptar» una carpeta G3 (`Adopter`: identidad y relaciones en una tarjeta),
// números de tarea repetidos (se renumeran y se renombran en la misma operación) y tareas movidas en Finder (la ruta
// manda). Nada se aplica solo: cada tarjeta prepara un plan que se escribe con el clic de una persona. Nunca enseña
// ni toca lo privado.

/// Las tarjetas de revisión de las tareas, calculadas de una foto de la carpeta.
struct RevisionTareas: Sendable, Hashable {
    struct Legado: Sendable, Hashable, Identifiable {
        var id: VaultPath { fichero }
        let fichero: VaultPath
        /// Títulos de las líneas que pasan a fichas (para enseñar qué se crea).
        let titulos: [String]
    }

    struct Adopcion: Sendable, Hashable {
        let identidades: Int
        let relaciones: Int
        let ambiguas: Int
        /// Unas líneas con lo que se escribiría («“t-0007-llamar-a-jorge”: oportunidad → Javier Ortega · Renta»).
        var ejemplos: [String] = []
        var vacia: Bool { identidades == 0 && relaciones == 0 }
    }

    let legados: [Legado]
    let adopcion: Adopcion
    /// Grupos de tareas con el mismo número (la más antigua primero: se queda con el suyo).
    let duplicados: [[Tarea]]
    let correcciones: [CorreccionDeUbicacion]

    static let vacia = RevisionTareas(legados: [], adopcion: Adopcion(identidades: 0, relaciones: 0, ambiguas: 0),
                                      duplicados: [], correcciones: [])

    var hayAlgo: Bool { !legados.isEmpty || !adopcion.vacia || !duplicados.isEmpty || !correcciones.isEmpty }

    /// Cuántas tarjetas hay.
    var cuantas: Int {
        (legados.isEmpty ? 0 : 1) + (adopcion.vacia ? 0 : 1) + (duplicados.isEmpty ? 0 : 1) + (correcciones.isEmpty ? 0 : 1)
    }

    static func de(_ foto: VaultSnapshot) -> RevisionTareas {
        let layout = foto.layout
        let reloj = Reloj.deCarpeta(foto)
        let legados: [Legado] = ficherosHeredados(foto).map { f in
            let lineas = foto.text(f).map { ChecklistParser.parse(NoteDocument(text: $0).body) } ?? []
            return Legado(fichero: f, titulos: lineas.map { $0.titulo.isEmpty ? "Tarea sin título" : $0.titulo })
        }
        let propuesta = Adopter(snapshot: foto).proponer()
        let relaciones = propuesta.relaciones.filter { !layout.isPrivate($0.ruta) && !layout.isPrivate($0.destino) }
        let ambiguas = propuesta.ambiguas.filter { !layout.isPrivate($0.ruta) }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        let identidades = propuesta.identidades.filter { !layout.isPrivate($0.ruta) }
        var ejemplos = relaciones.prefix(3).map { r in
            "«\(r.ruta.stem)»: \(r.clave) → «\(LinkParser.plainText(r.valor))»"
        }
        ejemplos += identidades.prefix(max(0, 3 - ejemplos.count)).map { "«\($0.ruta.stem)»: su tipo y un identificador" }
        return RevisionTareas(legados: legados,
                              adopcion: Adopcion(identidades: identidades.count, relaciones: relaciones.count,
                                                 ambiguas: ambiguas.count, ejemplos: ejemplos),
                              duplicados: duplicados(store, layout: layout),
                              correcciones: store.correccionesDeUbicacion().filter { c in
                                  !layout.isPrivate(c.tarea) && !(c.proyecto.map(layout.isPrivate) ?? false)
                              })
    }

    /// Los `Tareas.md` heredados que no son privados.
    static func ficherosHeredados(_ foto: VaultSnapshot) -> [VaultPath] {
        LegacyTasksMigrator(snapshot: foto).encontrar().filter { !foto.layout.isPrivate($0) }.sorted()
    }

    /// Números repetidos entre las tareas que no son privadas (la privada no se nombra ni se renumera).
    static func duplicados(_ store: TaskStore, layout: VaultLayout) -> [[Tarea]] {
        let visibles = store.tareas.filter { !layout.isPrivate($0.ruta) && $0.numeroEntero != nil }
        let lejos = LocalDate(year: 9999, month: 1, day: 1)!
        return Dictionary(grouping: visibles, by: { $0.numeroEntero! }).values.filter { $0.count > 1 }
            .map { $0.sorted { ($0.creada ?? lejos, $0.ruta) < ($1.creada ?? lejos, $1.ruta) } }
            .sorted { $0[0].numeroEntero! < $1[0].numeroEntero! }
    }

    // MARK: Planes (se escriben con el clic de una persona)

    /// Pasar a fichas los `Tareas.md` heredados (no privados) y retirarlos a `Archivo/`, en un solo plan con la
    /// numeración seguida y una sola subida del contador.
    static func planHeredados(_ foto: VaultSnapshot, autor: Autor) throws -> WritePlan? {
        let ficheros = ficherosHeredados(foto)
        guard !ficheros.isEmpty else { return nil }
        let reloj = Reloj.deCarpeta(foto)
        let migrador = LegacyTasksMigrator(snapshot: foto, reloj: reloj)
        let primero = TaskStore(snapshot: foto, reloj: reloj).siguienteNumero()
        var n = primero
        var ops: [WriteOp] = []
        for f in ficheros {
            let m = try migrador.proponer(f, autor: autor, primerNumero: n)
            n += m.lineas.count
            ops += m.plan.ops.filter { TextFolding.pathKey($0.path.raw) != TextFolding.pathKey(Secuencias.ruta.raw) }
        }
        if n > primero, let op = Secuencias.op(["tarea": n - 1], en: foto) { ops.append(op) }
        let total = n - primero
        let desc = total == 0 ? "Retirar los Tareas.md vacíos" : "Pasar a fichas " + (total == 1 ? "1 tarea heredada" : "\(total) tareas heredadas")
        return WritePlan(autor: autor, descripcion: desc, ops: ops)
    }

    /// «Adoptar»: identidad mínima (`tls_type`, `tls_schema`, `id`) y las relaciones propuestas, en un solo plan.
    static func planAdoptar(_ foto: VaultSnapshot, autor: Autor) -> WritePlan? {
        let layout = foto.layout
        let p = Adopter(snapshot: foto).proponer()
        let relaciones = p.relaciones.filter { !layout.isPrivate($0.ruta) && !layout.isPrivate($0.destino) }
        var ops = (p.planIdentidad(autor: autor)?.ops ?? []).filter { !layout.isPrivate($0.path) }
        ops += p.planRelaciones(relaciones, autor: autor)?.ops ?? []
        guard !ops.isEmpty else { return nil }
        return WritePlan(autor: autor, descripcion: "Completar las fichas de la carpeta", ops: ops)
    }

    /// Renumera las repetidas (no privadas): número nuevo y fichero renombrado en la misma operación.
    static func renumerar(_ foto: VaultSnapshot, autor: Autor) throws -> RefactorPreview? {
        let store = TaskStore(snapshot: foto)
        let repetidas = duplicados(store, layout: foto.layout).flatMap { $0.dropFirst() }
        return repetidas.isEmpty ? nil : try store.renumerar(repetidas, autor: autor)
    }

    /// Corrige el proyecto de las tareas movidas en Finder (la ruta manda). Solo propiedades.
    static func planCorrecciones(_ foto: VaultSnapshot, autor: Autor) -> WritePlan? {
        let layout = foto.layout
        let store = TaskStore(snapshot: foto)
        let lista = store.correccionesDeUbicacion().filter { c in
            !layout.isPrivate(c.tarea) && !(c.proyecto.map(layout.isPrivate) ?? false)
        }
        return store.corregir(lista, autor: autor)
    }
}
