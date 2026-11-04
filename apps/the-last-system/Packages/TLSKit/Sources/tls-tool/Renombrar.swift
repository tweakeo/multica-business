import ArgumentParser
import Foundation
import TLSCore
import TLSImport

struct Renombrar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Cambia el nombre de una nota o carpeta y actualiza todos los enlaces que apuntan a ella.",
        discussion: """
        Sin --aplicar solo enseña la vista previa: qué ficheros cambian y cada enlace, antes y después. \
        Con --aplicar lo escribe de una vez (todo o nada, con copia previa fuera de la carpeta) y comprueba \
        que no aparece ningún enlace roto nuevo. Solo escribe en copias y en la demo: la carpeta real no se \
        toca. Se deshace con «tls-tool deshacer <carpeta>».
        """
    )

    @Argument(help: "Carpeta de la empresa (una copia o la demo).")
    var carpeta: String

    @Argument(help: "Nota o carpeta, con su ruta dentro de la empresa (la nota puede ir sin «.md»).")
    var ruta: String

    @Argument(help: "Nombre nuevo. Si no lleva extensión, se conserva la de la nota.")
    var nombre: String

    @Flag(help: "Escribe el cambio. Sin esta opción solo se muestra la vista previa.")
    var aplicar = false

    @Flag(help: "Aplica aunque algún enlace corra peligro (se listan antes).")
    var forzar = false

    @Flag(help: "No añade el nombre anterior a «Otros nombres» (aliases).")
    var sinAlias = false

    @Option(parsing: .upToNextOption, help: "Ruta relativa que no se mira (se puede repetir).")
    var excluir: [String] = []

    @Option(help: "Enlaces que se listan como mucho por fichero en la vista previa (0: solo los ficheros).")
    var detalle = 20

    func run() async throws {
        try CLI.protect()
        let (root, entry) = try await CLI.carpetaEscribible(carpeta, excluir: excluir)
        let excluidas = entry.exclusionesCopia.map { VaultPath($0) }
        let antes = VaultSnapshot.read(root: root, excluded: excluidas)
        let rotosAntes = SaludDeEnlaces(snapshot: antes).revisar()
        let opciones = LinkRefactor.Opciones(autor: CLI.autor, alias: sinAlias ? .nunca : .automatico)
        let previa = try CLI.run {
            try LinkRefactor(snapshot: antes).renombrar(VaultPath(ruta), a: nombre, opciones: opciones)
        }
        CLI.mostrar(previa, detalle: detalle)
        print("Enlaces sin resolver ahora: \(rotosAntes.count)")
        guard aplicar else {
            print("Vista previa: no he escrito nada. Añade --aplicar para hacerlo.")
            return
        }
        if !previa.esSeguro, !forzar {
            CLI.printErr(RefactorError.enlacesEnRiesgo(previa.problemas.count).errorDescription ?? "")
            CLI.printErr("No he escrito nada. Si aun así quieres seguir, añade --forzar.")
            throw ExitCode.failure
        }
        let writer = try await CLI.runAsync { try await VaultWriter.open(entry: entry, root: root) }
        let resultado: WriteResult
        do {
            resultado = try await LinkRefactor.aplicar(previa, con: CommandBus(writer: writer), aunqueHayaProblemas: forzar)
        } catch {
            await writer.close()
            return try CLI.fail(error)
        }
        await writer.close()
        switch resultado.estado {
        case .conflicto(let c):
            CLI.printErr("No he escrito nada: «\(c.ruta.raw)» cambió fuera mientras tanto. Vuelve a probar.")
            throw ExitCode.failure
        case .sinCambios:
            print("No había nada que cambiar.")
            return
        case .hecho:
            print(previa.avisoHecho + ".")
        }

        // Comprobación: ningún enlace que antes resolvía deja de hacerlo.
        let despues = SaludDeEnlaces(snapshot: VaultSnapshot.read(root: root, excluded: excluidas)).revisar()
        let nuevos = CLI.rotosNuevos(antes: rotosAntes, despues: despues, previa: previa)
        print("Enlaces sin resolver: antes \(rotosAntes.count) · después \(despues.count) · rotos nuevos \(nuevos.count)")
        for r in nuevos.prefix(detalle) {
            CLI.printErr("  roto: \(r.origen.raw), línea \(r.linea): \(r.enlace)")
        }
        guard nuevos.isEmpty else {
            CLI.printErr("Han aparecido enlaces rotos. Puedes volver atrás con «tls-tool deshacer».")
            throw ExitCode.failure
        }
        print("Para volver atrás: tls-tool deshacer \"\(root.path)\"")
    }
}

struct Deshacer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deshace el último cambio que hizo la app en una carpeta (si nadie ha tocado esos ficheros después).",
        discussion: """
        Deja cada fichero con los bytes de antes. Lo que el cambio creó se retira a Archivo/ (nunca se borra). \
        Solo en copias y en la demo.
        """
    )

    @Argument(help: "Carpeta de la empresa (una copia o la demo).")
    var carpeta: String

    @Flag(help: "Solo dice qué se desharía, sin hacerlo.")
    var ver = false

    func run() async throws {
        try CLI.protect()
        let (root, entry) = try await CLI.carpetaEscribible(carpeta, excluir: [])
        let writer = try await CLI.runAsync { try await VaultWriter.open(entry: entry, root: root) }
        let bus = CommandBus(writer: writer)
        guard let info = await bus.ultimoDeshacible() else {
            await writer.close()
            print("No hay nada que deshacer.")
            return
        }
        let cuando = info.fecha.formatted(date: .abbreviated, time: .shortened)
        guard !ver else {
            await writer.close()
            print("Se desharía: \(info.descripcion) (\(info.autor.etiqueta), \(cuando)).")
            return
        }
        let resultado: WriteResult
        do {
            resultado = try await bus.deshacer(autor: CLI.autor)
        } catch {
            await writer.close()
            return try CLI.fail(error)
        }
        await writer.close()
        print("Deshecho: \(info.descripcion) (\(cuando)). Ficheros que vuelven a como estaban: \(resultado.cambiadas.count)")
    }
}

extension CLI {
    /// Quién firma en el diario lo que escribe la herramienta.
    static let autor = Autor.persona("tls-tool")

    /// Carpeta en la que la herramienta puede escribir: una copia o la demo (nunca la real), con su
    /// entrada (la de la app si está registrada; si no, la de su `.tls/config.yaml`).
    static func carpetaEscribible(_ path: String, excluir: [String]) async throws -> (URL, VaultEntry) {
        let root = folderURL(path).resolvingSymlinksInPath()
        let peek = try await run { try await CopyConfig.peek(root) }
        let registrada = VaultRegistry().load().first {
            URL(fileURLWithPath: $0.ruta).standardizedFileURL.resolvingSymlinksInPath().path == root.path
        }
        // Sin `.tls/config.yaml` que diga otra cosa, se trata como la carpeta real.
        let clase = registrada?.clase ?? peek.clase ?? .real
        let exclusiones = (registrada?.exclusionesCopia ?? []) + excluir.map { VaultPath($0).raw }
        let entry = VaultEntry(id: registrada?.id ?? peek.id ?? Indexar.stableID(for: root.path),
                               nombre: root.lastPathComponent, ruta: root.path, bookmark: nil, clase: clase,
                               escritura: registrada?.escritura ?? WritePolicy.escrituraInicial(para: clase),
                               exclusionesCopia: Array(Set(exclusiones)).sorted())
        try run { try WritePolicy.comprobar(entry, root: root) }
        return (root, entry)
    }

    /// Escribe el error con su texto para la persona y termina con código 1.
    static func fail<T>(_ error: any Error) throws -> T {
        if let e = error as? LocalizedError, let d = e.errorDescription { printErr(d) } else { printErr("\(error)") }
        throw ExitCode.failure
    }

    /// Vista previa de un renombrado o movimiento, para leer en la terminal.
    static func mostrar(_ previa: RefactorPreview, detalle: Int) {
        print(previa.resumen)
        for t in previa.traslados { print("  \(t.de.raw) → \(t.a.raw)") }
        let conTexto = previa.cambios.filter { !$0.enlaces.isEmpty || $0.alias != nil }
        if !conTexto.isEmpty { print("Ficheros que cambian por dentro (\(conTexto.count)):") }
        for c in conTexto {
            print(c.ruta == c.rutaFinal ? "  \(c.ruta.raw)" : "  \(c.ruta.raw) → \(c.rutaFinal.raw)")
            for e in c.enlaces.prefix(max(detalle, 0)) {
                print("    línea \(e.linea) (\(lugar(e.lugar))): \(e.antes) → \(e.despues)")
            }
            if detalle > 0, c.enlaces.count > detalle { print("    … y \(c.enlaces.count - detalle) más") }
            if let a = c.alias { print("    «\(a)» pasa a «Otros nombres»") }
        }
        let movidos = previa.cambios.filter { $0.ruta != $0.rutaFinal }.count
        if movidos > 1 { print("Ficheros que cambian de ruta: \(movidos)") }
        for p in previa.problemas {
            printErr("  en peligro: \(p.ruta.raw), línea \(p.linea): \(p.enlace) (\(p.motivo))")
        }
        if !previa.sinDescargar.isEmpty {
            printErr("Aviso: \(previa.sinDescargar.count) notas solo están en iCloud y no se han podido revisar.")
        }
        if !previa.enConflicto.isEmpty {
            printErr("Aviso: hay un conflicto pendiente en \(previa.enConflicto.map(\.raw).joined(separator: ", ")).")
        }
        if !previa.noEditables.isEmpty {
            printErr("Aviso: \(previa.noEditables.count) ficheros de texto no se pueden leer como UTF-8 y no se revisan.")
        }
    }

    static func lugar(_ l: CambioDeEnlace.Lugar) -> String {
        switch l {
        case .cuerpo: "texto"
        case .propiedad(let k): "propiedad «\(k)»"
        case .columna(let c): "columna «\(c)»"
        case .ajustes(let f): "ajustes «\(f)»"
        }
    }

    /// Enlaces sin resolver después que no lo estaban antes (los de lo movido se comparan con su ruta de antes).
    static func rotosNuevos(antes: [EnlaceRevisado], despues: [EnlaceRevisado], previa: RefactorPreview) -> [EnlaceRevisado] {
        var deAntes: [VaultPath: VaultPath] = [:]
        for c in previa.cambios where c.ruta != c.rutaFinal { deAntes[c.rutaFinal] = c.ruta }
        var quedan: [String: Int] = [:]
        for r in antes { quedan["\(r.origen.raw)\n\(r.enlace)", default: 0] += 1 }
        var out: [EnlaceRevisado] = []
        for r in despues {
            let k = "\((deAntes[r.origen] ?? r.origen).raw)\n\(r.enlace)"
            if let n = quedan[k], n > 0 { quedan[k] = n - 1 } else { out.append(r) }
        }
        return out
    }
}
