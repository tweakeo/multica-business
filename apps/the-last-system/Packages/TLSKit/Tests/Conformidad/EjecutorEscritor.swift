import Foundation
import TLSCore

/// Ejecuta los casos `escritor` con el `VaultWriter` de TLSCore (PLAN §4.8) sobre una copia temporal
/// de `entrada/`. Las operaciones seguidas van en un plan único (todo o nada); «renombrar» va en su
/// propio plan, que prepara `LinkRefactor` con todos los enlaces (SISTEMAS §5.2).
struct EjecutorVaultWriter: EjecutorEscritor {
    static let soportadas: Set<String> = ["create", "mergeFrontmatter", "appendToSection", "appendLine",
                                          "upsertCSVRow", "move", "retire", "renombrar"]

    func soporta(_ op: String) -> Bool { Self.soportadas.contains(op) }

    func aplicar(_ plan: [OperacionEscritor], en raiz: URL) async throws {
        let estado = RutasConformidad.temporal("estado-escritor")
        defer { try? FileManager.default.removeItem(at: estado) }
        let entrada = VaultEntry(nombre: "Conformidad", ruta: raiz.path, bookmark: nil, clase: .copia, escritura: .permitida)
        let writer = try await VaultWriter.open(entry: entrada, root: raiz,
                                                options: .init(stateDirectory: estado.appendingPathComponent("estado"),
                                                               appSupport: estado.appendingPathComponent("app")))
        let bus = CommandBus(writer: writer)
        let autor = Autor.persona("Conformidad")
        var pendientes: [WriteOp] = []
        func vaciar() async throws {
            guard !pendientes.isEmpty else { return }
            let resultado = try await bus.ejecutar(WritePlan(autor: autor, descripcion: "Caso de conformidad", ops: pendientes))
            pendientes = []
            if case .conflicto(let c) = resultado.estado { throw ErrorEjecutor.conflicto(c.ruta.raw) }
        }
        do {
            for o in plan {
                guard o.op == "renombrar" else { pendientes.append(try Self.writeOp(o)); continue }
                try await vaciar()
                // La foto se lee justo antes, con lo ya aplicado.
                let previa = try Self.renombrado(o, en: raiz, autor: autor)
                let resultado = try await LinkRefactor.aplicar(previa, con: bus)
                if case .conflicto(let c) = resultado.estado { throw ErrorEjecutor.conflicto(c.ruta.raw) }
            }
            try await vaciar()
        } catch {
            await writer.close()
            throw error
        }
        await writer.close()
    }

    /// Vista previa de «renombrar» (`a` es la ruta nueva entera; si cambia de carpeta, es mover).
    static func renombrado(_ o: OperacionEscritor, en raiz: URL, autor: Autor) throws -> RefactorPreview {
        let de = VaultPath(o.ruta)
        guard let a = o.a.map(VaultPath.init) else { throw ErrorEjecutor.operacion("renombrar sin «a»") }
        let motor = LinkRefactor(root: raiz)
        let opciones = LinkRefactor.Opciones(autor: autor)
        if a.parent == de.parent { return try motor.renombrar(de, a: a.name, opciones: opciones) }
        return try motor.preparar([Traslado(de: de, a: a)], opciones: opciones)
    }

    enum ErrorEjecutor: Error { case operacion(String), conflicto(String) }

    static func writeOp(_ o: OperacionEscritor) throws -> WriteOp {
        let p = VaultPath(o.ruta)
        switch o.op {
        case "create":
            return .create(p, text: o.texto ?? "")
        case "mergeFrontmatter":
            let set = (o.set ?? [:]).keys.sorted().map { Property(key: $0, value: .text(o.set![$0]!)) }
            return .mergeFrontmatter(p, set: set, unset: o.unset ?? [])
        case "appendToSection":
            return .appendToSection(p, section: o.seccion ?? "", text: o.texto ?? "")
        case "appendLine":
            return .appendLine(p, line: o.linea ?? "")
        case "upsertCSVRow":
            return .upsertCSVRow(p, row: o.fila ?? [:], key: o.clave ?? "id")
        case "move":
            return .move(p, to: VaultPath(o.a ?? ""))
        case "retire":
            return .retire(p)
        default:
            throw ErrorEjecutor.operacion(o.op)
        }
    }
}

/// Leer y reescribir sin cambios con los documentos del escritor (criterio 1 de F1).
struct ReescritorEscritor: Reescritor {
    func reescribir(_ datos: Data, ruta: VaultPath) throws -> Data? {
        switch ruta.ext {
        case "md": FrontmatterDocument(data: datos)?.data
        case "csv": CSVDocument(data: datos)?.data
        default: nil
        }
    }
}
