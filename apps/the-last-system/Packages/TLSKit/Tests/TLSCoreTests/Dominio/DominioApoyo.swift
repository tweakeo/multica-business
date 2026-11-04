import Foundation
import Testing
@testable import TLSCore

/// Copias de Ribera (ficticia, reloj fijo 2026-10-19) para probar el dominio. Nunca se toca el ejemplo del repositorio.
enum DominioApoyo {
    static var ribera: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    static let opoJorge = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
    static let opoSergio = VaultPath("2 · Ventas/Oportunidades/sergio-nexo-trimestrales.md")
    static let opoAndres = VaultPath("2 · Ventas/Oportunidades/andres-vidal-renta.md")
    static let facturaJorge = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
    static let pagos = VaultPath("4 · Finanzas/Registros/pagos.csv")
    static let movimientos = VaultPath("4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv")
    static let decisiones = VaultPath("1 · Dirección/Decisiones.md")
    static let proyectos = VaultPath("3 · Entrega/Proyectos")

    /// Fila de `pagos.csv` que deja una persona al confirmar la conciliación de la transferencia de Talleres Martín.
    static func filaCobroJorge(id: String = "PAG-20261017-001") -> [String: String] {
        ["id": id, "fecha": "2026-10-17", "direccion": "cobro", "importe": "181.50", "moneda": "EUR",
         "documento_id": "F-2026-0007", "proyecto_id": "", "tercero": "Talleres Martín e Hijos SL", "metodo": "transferencia",
         "evidencia": "Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv#MOV-11e4d44973fd", "verificacion": "confirmado"]
    }

    /// Lo que escribe una persona al confirmar la conciliación (PLAN §4.6): el movimiento conciliado y la fila de pagos.
    static func confirmarCobroJorge(autor: Autor = .persona("Manu"), id: String = "PAG-20261017-001") -> WritePlan {
        WritePlan(autor: autor, descripcion: "Confirmar el cobro de F-2026-0007", ops: [
            .upsertCSVRow(movimientos, row: ["id": "MOV-11e4d44973fd", "estado_conciliacion": "conciliado", "pago_id": id], key: "id"),
            .upsertCSVRow(pagos, row: filaCobroJorge(id: id), key: "id"),
        ])
    }

    /// Copia de Ribera en una carpeta temporal propia, con el estado y los cerrojos aparte.
    struct Copia {
        let base: URL
        let root: URL
        let entry: VaultEntry

        var estado: URL { base.appendingPathComponent("estado") }
        var options: VaultWriter.Options {
            VaultWriter.Options(stateDirectory: estado, appSupport: base.appendingPathComponent("asup"), app: "The Last System pruebas")
        }

        func bus() async throws -> CommandBus {
            CommandBus(writer: try await VaultWriter.open(entry: entry, root: root, options: options))
        }

        func motor(_ opciones: MotorDeDominio.Opciones = .init()) async throws -> MotorDeDominio {
            try MotorDeDominio(bus: try await bus(), opciones: opciones)
        }

        func datos(_ p: VaultPath) -> Data? { try? Data(contentsOf: p.url(in: root)) }
        func texto(_ p: VaultPath) -> String { datos(p).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        func existe(_ p: VaultPath) -> Bool { FileManager.default.fileExists(atPath: p.url(in: root).path) }

        func escribir(_ p: VaultPath, _ texto: String) throws {
            let u = p.url(in: root)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(texto.utf8).write(to: u)
        }

        func foto() -> VaultSnapshot { VaultSnapshot.read(root: root) }
        func lectura() -> LecturaDominio { LecturaDominio(snapshot: foto()) }

        /// Fichas `Proyecto.md` dentro de `3 · Entrega/Proyectos/`.
        func proyectos() -> [VaultPath] {
            foto().files.filter { $0.isDescendant(of: DominioApoyo.proyectos) && $0.name == "Proyecto.md" }
        }

        /// Tareas (fichas) de la carpeta.
        func tareas() -> [Tarea] { TaskStore(snapshot: foto()).tareas }

        /// Huella de todos los ficheros (sin `.tls/escritor.json`).
        func huella() -> [String: String] {
            var out: [String: String] = [:]
            let fm = FileManager.default
            var stack = [root]
            while let dir = stack.popLast() {
                for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                    let u = dir.appendingPathComponent(n)
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: u.path, isDirectory: &isDir)
                    let rel = String(u.path.dropFirst(root.path.count + 1)).precomposedStringWithCanonicalMapping
                    if isDir.boolValue { stack.append(u) } else if rel != ".tls/escritor.json" {
                        out[rel] = ContentHash.of((try? Data(contentsOf: u)) ?? Data())
                    }
                }
            }
            return out
        }

        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    static func copia() throws -> Copia {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-dominio-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Ribera", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: ribera, to: root)
        let entry = VaultEntry(nombre: "Asesoría Ribera", ruta: root.path, bookmark: nil, clase: .demo, escritura: .permitida)
        return Copia(base: base, root: root, entry: entry)
    }

    /// Palabras que nunca salen en pantalla (lint del glosario, PLAN §6.9).
    static let jerga = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash"]

    static func conJerga(_ texto: String) -> [String] {
        let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return jerga.filter { palabras.contains($0) }
    }
}
