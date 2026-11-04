import Foundation

/// Quién pide una escritura. Decide qué se le permite (PLAN §4.8).
public enum Autor: Sendable, Hashable, Codable {
    /// Una persona desde la interfaz (`Manu`).
    case persona(String)
    /// La propia app (reglas, migraciones, mantenimiento).
    case sistema
    /// Un asistente (`agente:<slug>`).
    case agente(String)

    /// Como se escribe en el diario y en la Actividad: `Manu`, `sistema`, `agente:comercial`.
    public var etiqueta: String {
        switch self {
        case .persona(let n): n
        case .sistema: "sistema"
        case .agente(let s): "agente:" + s
        }
    }

    public var esPersona: Bool {
        if case .persona = self { return true }
        return false
    }

    public init(etiqueta: String) {
        if etiqueta == "sistema" { self = .sistema }
        else if etiqueta.hasPrefix("agente:") { self = .agente(String(etiqueta.dropFirst("agente:".count))) }
        else { self = .persona(etiqueta) }
    }
}

/// Cambio de un tramo de texto (desplazamientos en bytes UTF-8 del texto, sin el BOM).
public struct TextEdit: Sendable, Hashable, Codable {
    public var offset: Int
    public var length: Int
    public var replacement: String
    public init(offset: Int, length: Int, replacement: String) {
        self.offset = offset; self.length = length; self.replacement = replacement
    }
}

/// Una operación de escritura. Todas son compare-and-swap: se calculan sobre lo que hay en
/// disco dentro de la sección crítica del escritor y no se aplican si algo cambió entre medias.
/// **No existe borrado**: retirar es mover a `Archivo/`.
public enum WriteOp: Sendable, Hashable {
    /// Fichero nuevo. Nunca pisa: si el nombre está ocupado, añade « (2)», « (3)»…
    case create(VaultPath, contents: Data)
    /// Cambia solo las líneas de esas propiedades (`FrontmatterDocument`).
    case mergeFrontmatter(VaultPath, set: [Property], unset: [String])
    /// Añade texto al final de una sección (la crea al final si no existe).
    case appendToSection(VaultPath, section: String, text: String, blankLine: Bool)
    /// Sustituye el contenido de una sección si su huella sigue siendo `baseSectionHash`.
    case replaceSection(VaultPath, section: String, text: String, baseSectionHash: String)
    /// Sustituye el cuerpo (el frontmatter no cambia). Persona: `baseHash` del editor.
    /// Asistentes y sistema: solo si el fichero sigue como lo dejó la app (`hash_app`).
    case replaceBody(VaultPath, body: String, baseHash: String?)
    /// Guardado del editor de una persona: texto completo y el texto del que partió.
    /// Si fuera solo cambiaron propiedades o se añadió Actividad, se fusiona sin aviso.
    case saveText(VaultPath, base: String, text: String)
    /// Añade una línea tras la última con texto.
    case appendLine(VaultPath, line: String)
    /// Inserta o actualiza una fila de un CSV por su clave (`id`).
    case upsertCSVRow(VaultPath, row: [String: String], key: String)
    /// Añade filas nuevas a un CSV (en su separador y su orden de columnas). **Nunca pisa**: si la clave de alguna
    /// ya está (otra ventana, un doble clic, una vista previa vieja), no se escribe nada (`WriteError.filaYaExiste`).
    case insertCSVRows(VaultPath, rows: [[String: String]], key: String)
    /// Cambia celdas de la fila de una tabla Markdown cuya `keyColumn` vale `keyValue`.
    case setTableCells(VaultPath, table: TableSelector, keyColumn: String, keyValue: String, cells: [String: String])
    /// Añade una fila al final de una tabla Markdown.
    case appendTableRow(VaultPath, table: TableSelector, cells: [String: String])
    /// Cambia tramos concretos del texto (enlaces al renombrar) si el fichero sigue en `baseHash`.
    case editRanges(VaultPath, edits: [TextEdit], baseHash: String)
    /// Mueve o renombra (nota o carpeta). Nunca sobrescribe.
    case move(VaultPath, to: VaultPath)
    /// Mueve a `Archivo/<misma ruta>` (o `Archivo/<apartado>/<misma ruta>`: Conflictos, Duplicados).
    case retire(VaultPath, apartado: String?)

    /// Fichero de texto nuevo (UTF-8).
    public static func create(_ path: VaultPath, text: String) -> WriteOp {
        .create(path, contents: Data(text.utf8))
    }

    public static func appendToSection(_ path: VaultPath, section: String, text: String) -> WriteOp {
        .appendToSection(path, section: section, text: text, blankLine: true)
    }

    public static func retire(_ path: VaultPath) -> WriteOp {
        .retire(path, apartado: nil)
    }

    /// Sustituye todo el texto de un fichero si sigue siendo `base` (los bytes que se leyeron).
    /// El BOM, si lo había, se conserva. `nil` si `base` no es UTF-8.
    public static func replaceText(_ path: VaultPath, base: Data, text: String) -> WriteOp? {
        guard let e = EditableText(data: base) else { return nil }
        return .editRanges(path, edits: [TextEdit(offset: 0, length: e.text.utf8.count, replacement: text)],
                           baseHash: ContentHash.of(base))
    }

    /// Ruta principal de la operación.
    public var path: VaultPath {
        switch self {
        case .create(let p, _), .mergeFrontmatter(let p, _, _), .appendToSection(let p, _, _, _),
             .replaceSection(let p, _, _, _), .replaceBody(let p, _, _), .saveText(let p, _, _),
             .appendLine(let p, _), .upsertCSVRow(let p, _, _), .insertCSVRows(let p, _, _), .setTableCells(let p, _, _, _, _),
             .appendTableRow(let p, _, _), .editRanges(let p, _, _), .move(let p, _), .retire(let p, _):
            p
        }
    }

    /// Resumen para el diario (sin el contenido).
    public var resumen: String {
        switch self {
        case .create(let p, _): "crear \(p.raw)"
        case .mergeFrontmatter(let p, let set, let unset):
            "propiedades \(p.raw): " + (set.map(\.key) + unset.map { "-" + $0 }).joined(separator: ",")
        case .appendToSection(let p, let s, _, _): "añadir a «\(s)» en \(p.raw)"
        case .replaceSection(let p, let s, _, _): "sustituir «\(s)» en \(p.raw)"
        case .replaceBody(let p, _, _): "cuerpo de \(p.raw)"
        case .saveText(let p, _, _): "guardar \(p.raw)"
        case .appendLine(let p, _): "línea en \(p.raw)"
        case .upsertCSVRow(let p, let row, let key): "fila \(row[key] ?? "?") en \(p.raw)"
        case .insertCSVRows(let p, let rows, _): "\(rows.count) filas nuevas en \(p.raw)"
        case .setTableCells(let p, _, _, let v, let cells): "celdas \(cells.keys.sorted().joined(separator: ",")) de \(v) en \(p.raw)"
        case .appendTableRow(let p, _, _): "fila nueva en \(p.raw)"
        case .editRanges(let p, let e, _): "\(e.count) cambios en \(p.raw)"
        case .move(let a, let b): "mover \(a.raw) → \(b.raw)"
        case .retire(let p, let ap): "retirar \(p.raw)" + (ap.map { " (\($0))" } ?? "")
        }
    }
}

/// Varias operaciones que se aplican todas o ninguna.
public struct WritePlan: Sendable, Hashable {
    public var id: UUID
    public var autor: Autor
    /// Texto para la persona («Renombrar Panadería Sol»): sale en «Deshacer».
    public var descripcion: String
    public var ops: [WriteOp]

    public init(id: UUID = UUID(), autor: Autor, descripcion: String, ops: [WriteOp]) {
        self.id = id; self.autor = autor; self.descripcion = descripcion; self.ops = ops
    }
}

/// Un movimiento hecho por un plan.
public struct Movimiento: Sendable, Hashable, Codable {
    public let de: VaultPath
    public let a: VaultPath
}

/// Resultado de aplicar un plan.
public struct WriteResult: Sendable {
    public enum Estado: Sendable {
        case hecho
        /// No había nada que cambiar (los bytes ya eran esos).
        case sinCambios
        /// No se escribió nada: hay una tarjeta de conflicto con las dos versiones.
        case conflicto(ConflictRecord)
    }

    public let planID: UUID
    public let estado: Estado
    /// Rutas que cambiaron (también origen y destino de lo movido): las que hay que reindexar.
    public let cambiadas: [VaultPath]
    /// Rutas reales de lo creado, en el orden de las operaciones (con « (2)» si hizo falta).
    public let creadas: [VaultPath]
    public let movidas: [Movimiento]
    /// Huella final de cada fichero escrito.
    public let hashes: [VaultPath: String]

    public var hecho: Bool {
        if case .hecho = estado { return true }
        return false
    }

    public var conflicto: ConflictRecord? {
        if case .conflicto(let c) = estado { return c }
        return nil
    }
}

/// Lo que se puede deshacer ahora.
public struct UndoInfo: Sendable, Hashable {
    public let planID: UUID
    public let descripcion: String
    public let autor: Autor
    public let fecha: Date
}

/// Errores de escritura, con texto para la persona (sin jerga).
public enum WriteError: Error, LocalizedError, Sendable, Equatable {
    case carpetaReal
    case soloLectura
    case carpetaDelFork(String)
    case otroEscritor(equipo: String, desde: String)
    case otroProceso
    case escritorIlegible
    case rutaNoPermitida(String)
    case noExiste(String)
    case destinoOcupado(String)
    case sinDescargar(String)
    case enlaceSimbolico(String)
    case esCarpeta(String)
    case noEsTexto(String)
    case cambioExterno(String)
    case soloAnadidos(String)
    case listaVacia(String)
    case filaManual(String)
    case claveDuplicada(String)
    /// `insertCSVRows`: esa fila ya está escrita (no se pisa).
    case filaYaExiste(String)
    case columnaDesconocida(String)
    case csvSinCabecera
    case tablaNoEncontrada
    case filaNoEncontrada(String)
    case seccionNoEncontrada(String)
    case seccionCambiada(String)
    case propiedadesIlegibles(String)
    case contenidoIlegible(String)
    case verificacionFallida(String)
    case nadaQueDeshacer
    case noSePuedeDeshacer(String)
    case cambiosInvalidos
    case yaRetirada(String)
    case noPermitidoAsistente(String)
    case conflictoNoEncontrado
    case versionNoDisponible
    /// Solo en pruebas: simula que el proceso muere en ese punto.
    case interrumpido

    public var errorDescription: String? {
        switch self {
        case .carpetaReal:
            "Esta es tu carpeta original. Hasta que decidas dar el relevo, la app solo la lee: los cambios se hacen en una copia."
        case .soloLectura:
            "Esta carpeta está en modo solo lectura. Quita ese modo para poder guardar cambios."
        case .carpetaDelFork(let e):
            "Esta carpeta la gestiona otra aplicación\(e.isEmpty ? "" : " («\(e)»)"). Aquí solo se puede leer."
        case .otroEscritor(let equipo, let desde):
            "Esta carpeta la escribe The Last System en otro Mac (\(equipo), desde \(desde)). Aquí solo se puede leer."
        case .otroProceso:
            "Otra ventana de The Last System ya está guardando cambios en esta carpeta. Aquí solo se puede leer."
        case .escritorIlegible:
            "No puedo saber quién escribe en esta carpeta (su ficha de escritura está dañada). Por precaución, no guardo nada."
        case .rutaNoPermitida(let p): "No puedo escribir en «\(p)»."
        case .noExiste(let p): "No encuentro «\(p)». Puede que se haya movido."
        case .destinoOcupado(let p): "Ya hay algo llamado «\(p)». No lo piso."
        case .sinDescargar(let p): "«\(p)» aún no se ha descargado de iCloud. Ábrela primero para descargarla."
        case .enlaceSimbolico(let p): "«\(p)» es un acceso directo a otra ubicación: no escribo a través de él."
        case .esCarpeta(let p): "«\(p)» es una carpeta."
        case .noEsTexto(let p): "«\(p)» no es texto que la app sepa cambiar sin estropearlo."
        case .cambioExterno(let p): "«\(p)» cambió fuera de la app mientras tanto. No lo piso: vuelve a intentarlo."
        case .soloAnadidos(let p):
            "«\(p)» la ha cambiado alguien después de la última vez que la escribió la app. Solo se pueden cambiar sus propiedades o añadir texto."
        case .listaVacia(let k): "No dejo vacía «\(k)», que tiene contenido."
        case .filaManual(let k): "La fila «\(k)» está escrita a mano y no se cambia automáticamente."
        case .claveDuplicada(let k): "Hay más de una fila con «\(k)». No sé cuál cambiar."
        case .filaYaExiste(let k):
            "«\(k)» ya estaba guardado (quizá desde otra ventana o con un doble clic). No lo piso ni lo repito: vuelve a mirar."
        case .columnaDesconocida(let c): "No existe la columna «\(c)»."
        case .csvSinCabecera: "La tabla no tiene cabecera."
        case .tablaNoEncontrada: "No encuentro la tabla."
        case .filaNoEncontrada(let k): "No encuentro la fila «\(k)»."
        case .seccionNoEncontrada(let s): "No encuentro la sección «\(s)»."
        case .seccionCambiada(let s): "La sección «\(s)» cambió mientras tanto. No la piso."
        case .propiedadesIlegibles(let p): "El cambio dejaría ilegibles las propiedades de «\(p)». No lo guardo."
        case .contenidoIlegible(let p): "El cambio dejaría «\(p)» en un formato que no se puede leer. No lo guardo."
        case .verificacionFallida(let p): "Al comprobar «\(p)» tras guardarlo no coincidía. He vuelto a dejarlo como estaba."
        case .nadaQueDeshacer: "No hay nada que deshacer."
        case .noSePuedeDeshacer(let p): "No puedo deshacer: «\(p)» ha cambiado después. Deshacer lo pisaría."
        case .cambiosInvalidos: "Los cambios pedidos se solapan o se salen del texto."
        case .yaRetirada(let p): "«\(p)» ya está en el Archivo."
        case .noPermitidoAsistente(let p): "Un asistente no puede hacer esto con «\(p)»: lo propone y decides tú."
        case .conflictoNoEncontrado: "Ese conflicto ya no existe."
        case .versionNoDisponible: "Esa versión ya no está disponible."
        case .interrumpido: "La escritura se interrumpió."
        }
    }
}
