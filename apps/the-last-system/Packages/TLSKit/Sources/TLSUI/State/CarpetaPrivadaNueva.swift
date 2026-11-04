import Foundation
import TLSCore
import TLSDesign

// F4 · integración (pendiente de F3). En una copia hecha por la app lo privado se quedó fuera al copiar, así que la copia
// no tiene ninguna carpeta privada: las tareas personales de Multica marcadas no tenían dónde ir. «Crear una carpeta
// privada» (Ajustes › Esta empresa y la hoja de Multica) crea la carpeta con una nota que lo explica y la añade a
// `privado:` de `.tls/config.yaml`, **como la persona y en un solo plan** (un Deshacer). Lo privado no sale en las bases,
// en ⌘K ni en las vistas previas, y ningún asistente lo ve («no encontrado»).

public enum CarpetaPrivadaNueva {
    public static let nombrePorDefecto = "Privado"
    static let nota = "Léeme.md"

    public enum Fallo: Error, LocalizedError, Equatable {
        case nombreVacio
        case yaExiste(String)
        case ajustesIlegibles

        public var errorDescription: String? {
            switch self {
            case .nombreVacio: "Escribe un nombre para la carpeta."
            case .yaExiste(let n): "Ya hay algo que se llama «\(n)» en tu carpeta. Elige otro nombre."
            case .ajustesIlegibles: "No he podido leer la configuración de tu carpeta: no toco nada."
            }
        }
    }

    /// El plan (de la persona) y la ruta de la carpeta nueva. Solo lee la carpeta.
    public static func plan(nombre: String, root: URL, persona: String) throws -> (plan: WritePlan, carpeta: VaultPath) {
        let limpio = NombresDeFicha.fichero(nombre).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, !limpio.hasPrefix(".") else { throw Fallo.nombreVacio }
        let carpeta = VaultPath(limpio)
        var esDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: carpeta.url(in: root).path, isDirectory: &esDir) { throw Fallo.yaExiste(limpio) }
        let ruta = VaultPath(VaultLayout.configFile)
        let actual = AjustesBases.leerTexto(ruta, root: root)
        if actual == nil, FileManager.default.fileExists(atPath: ruta.url(in: root).path) { throw Fallo.ajustesIlegibles }
        guard let nuevo = VaultLayout.configConPrivado(actual, anadir: [carpeta]) else { throw Fallo.ajustesIlegibles }
        var ops: [WriteOp] = [.create(carpeta.appending(nota), text: textoNota(limpio))]
        if let actual {
            guard let op = WriteOp.replaceText(ruta, base: Data(actual.utf8), text: nuevo) else { throw Fallo.ajustesIlegibles }
            ops.append(op)
        } else {
            ops.append(.create(ruta, text: nuevo))
        }
        return (WritePlan(autor: .persona(persona), descripcion: "Crear la carpeta privada «\(limpio)»", ops: ops), carpeta)
    }

    static func textoNota(_ nombre: String) -> String {
        """
        # \(nombre)

        Esta carpeta es **privada**: lo que pongas aquí no sale en las bases, en la búsqueda ni en las vistas previas de
        The Last System, y ningún asistente lo ve.

        Sirve, por ejemplo, para las tareas personales que traigas de Multica (salud, papeles, cosas de casa).

        """
    }
}

public extension VaultSession {
    /// «Crear una carpeta privada»: como la persona, con «Deshacer». Devuelve la carpeta creada o `nil` (con el aviso).
    @discardableResult
    func crearCarpetaPrivada(nombre: String) async -> VaultPath? {
        guard let root else { return nil }
        do {
            let (plan, carpeta) = try CarpetaPrivadaNueva.plan(nombre: nombre, root: root, persona: persona)
            let r = try await escribir(plan: plan, aviso: "Carpeta privada «\(carpeta.name)» creada", deshacer: undoManagerActivo)
            return r.hecho ? carpeta : nil
        } catch {
            aviso = Aviso(error.localizedDescription, estado: .atencion)
            return nil
        }
    }

    /// Las carpetas privadas que marca ahora la carpeta (las de `.tls/config.yaml` y las de los ajustes de la app).
    var carpetasPrivadas: [VaultPath] { estructura?.privado ?? [] }
}
