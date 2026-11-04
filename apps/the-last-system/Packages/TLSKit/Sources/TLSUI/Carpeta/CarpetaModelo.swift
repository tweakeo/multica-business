import CoreTransferable
import Foundation
import Observation
import TLSCore
import TLSDesign
import TLSVisores
import UniformTypeIdentifiers

/// Una fila de la Carpeta: carpeta, nota o fichero.
struct FilaCarpeta: Identifiable, Hashable, Sendable {
    let ruta: VaultPath
    let esCarpeta: Bool
    /// Título de la nota (del índice) o nombre del fichero.
    let titulo: String
    let detalle: String
    let simbolo: String
    /// Si es la carpeta de un área, su área (icono de app).
    let area: AreaCode?
    let privado: Bool
    let enICloud: Bool
    let tipo: NoteKind?
    var id: VaultPath { ruta }

    var tipoFichero: TipoFichero { TipoFichero.de(extension: ruta.ext) }

    /// Etiqueta de VoiceOver: «jorge-martin, Contacto, privado, en iCloud».
    var etiquetaAccesible: String {
        var partes = [titulo, detalle]
        if privado { partes.append("privado") }
        if enICloud { partes.append("en iCloud, sin descargar") }
        return partes.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Hojas de la Carpeta.
enum HojaCarpeta: Identifiable {
    /// «Nueva…» con lo elegido (una ficha da sus plantillas).
    case nueva(seleccion: VaultPath?)
    case renombrar(VaultPath)
    /// Mover lo elegido; `destino` si se soltó sobre una carpeta.
    case mover([VaultPath], destino: VaultPath?)
    /// Ver lo que cambia al arreglar los enlaces de lo movido fuera de la app.
    case arreglo

    var id: String {
        switch self {
        case .nueva(let s): "nueva:\(s?.raw ?? "")"
        case .renombrar(let p): "renombrar:\(p.raw)"
        case .mover(let ps, let d): "mover:\(ps.map(\.raw).joined(separator: "|"))>\(d?.raw ?? "")"
        case .arreglo: "arreglo"
        }
    }
}

/// Resultado de «Nueva…».
enum ResultadoCrear: Equatable {
    case hecho(VaultPath, destino: Destino)
    /// La nota de nombre fijo ya existe (Área, Empresa, Metas…): se completa la que hay.
    case yaExiste(VaultPath)
    case error(String)
}

/// Resultado de aplicar un cambio en bloque (renombrar, mover, arreglar enlaces).
enum ResultadoCambio: Equatable {
    case hecho(WriteResult)
    /// Hay enlaces que el cambio no puede mantener: no se ha escrito nada.
    case enRiesgo(Int)
    case error(String)

    static func == (a: ResultadoCambio, b: ResultadoCambio) -> Bool {
        switch (a, b) {
        case (.hecho(let x), .hecho(let y)): x.planID == y.planID
        case (.enRiesgo(let x), .enRiesgo(let y)): x == y
        case (.error(let x), .error(let y)): x == y
        default: false
        }
    }
}

/// Lo que se arrastra dentro de la Carpeta: rutas de la carpeta de una empresa, con la empresa de la que salen.
/// Soltarlas en la ventana de otra empresa (con la misma estructura, como el ejemplo y su copia) no hace nada:
/// las rutas son relativas y moverían el fichero de la otra empresa.
struct ArrastreCarpeta: Codable, Transferable, Sendable {
    /// `VaultEntry.id` de la empresa de origen.
    let empresa: UUID
    let rutas: [String]

    /// Las rutas de lo soltado que salen de `empresa` (lo de otra empresa se ignora).
    static func rutas(_ items: [ArrastreCarpeta], en empresa: UUID) -> [VaultPath] {
        items.filter { $0.empresa == empresa }.flatMap(\.rutas).map(VaultPath.init)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tlsRutaCarpeta)
    }
}

extension UTType {
    /// Tipo propio para arrastrar filas de la Carpeta (pedido a cimientos para `Info.plist`).
    static let tlsRutaCarpeta = UTType(exportedAs: "es.thelast.system.ruta-carpeta", conformingTo: .data)
}

/// Estado de una pantalla de Carpeta: lo que hay en la carpeta, lo elegido y las órdenes (Nueva…, Renombrar,
/// Mover, Retirar, arreglar lo movido fuera). **Toda escritura pasa por `CommandBus`** (`sesion.escribir` o
/// `sesion.bus` + `registrarDeshacer`), con Deshacer; nunca se borra (retirar = `Archivo/`).
@Observable @MainActor
final class CarpetaModelo {
    let sesion: VaultSession
    /// Carpeta que se enseña (raíz = toda la carpeta de la empresa).
    let carpeta: VaultPath

    private(set) var filas: [FilaCarpeta] = []
    private(set) var cargada = false
    var seleccion: Set<VaultPath> = []
    var hoja: HojaCarpeta?
    /// Lo que se va a retirar (confirmación).
    var retirando: VaultPath?
    /// Arreglo de enlaces de lo movido fuera de la app (tarjeta), si hay algo que arreglar.
    private(set) var arreglo: RefactorPreview?

    @ObservationIgnored private var antes: Set<VaultPath>?
    @ObservationIgnored private var cache: (revision: Int, foto: VaultSnapshot)?
    @ObservationIgnored private var descartados = Set<String>()
    @ObservationIgnored private var revisando = false

    init(carpeta: VaultPath?, sesion: VaultSession) {
        self.carpeta = carpeta ?? .root
        self.sesion = sesion
    }

    // MARK: Leer

    var titulo: String {
        carpeta.isRoot ? "Carpeta de tu empresa" : carpeta.name
    }

    var areaDeLaCarpeta: AreaCode? {
        guard let layout = sesion.estructura, let a = layout.area(of: carpeta),
              layout.areaFolder(a) == carpeta else { return nil }
        return a
    }

    /// «4 carpetas · 12 ficheros».
    var resumen: String {
        let carpetas = filas.filter(\.esCarpeta).count
        let ficheros = filas.count - carpetas
        if filas.isEmpty { return "Vacía" }
        var partes: [String] = []
        if carpetas > 0 { partes.append(TLSFormat.cuenta(carpetas, "carpeta", "carpetas")) }
        if ficheros > 0 { partes.append(TLSFormat.cuenta(ficheros, "fichero", "ficheros")) }
        return partes.joined(separator: " · ")
    }

    /// Por qué no se puede cambiar nada (o `nil` si se puede).
    var motivoSoloLectura: String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .abriendo: "Aún se está abriendo la carpeta"
        case .soloLectura(let m): m.texto
        }
    }

    /// Lee lo que hay en la carpeta (con el título de cada nota del índice). No descarga nada de iCloud.
    func cargar() async {
        guard let service = sesion.service else { return }
        let c = carpeta
        let layout = sesion.estructura
        let filas = await Task.detached(priority: .userInitiated) { () -> [FilaCarpeta] in
            service.children(of: c).map { Self.fila(de: $0, resumen: $0.isDirectory ? nil : service.summary(of: $0.path), layout: layout) }
        }.value
        self.filas = filas
        let rutas = Set(filas.map(\.ruta))
        seleccion = seleccion.filter { rutas.contains($0) }
        cargada = true
    }

    nonisolated static func fila(de e: FolderEntry, resumen: NoteSummary?, layout: VaultLayout?) -> FilaCarpeta {
        if e.isDirectory {
            var area: AreaCode?
            if let layout, let a = layout.area(of: e.path), layout.areaFolder(a) == e.path { area = a }
            return FilaCarpeta(ruta: e.path, esCarpeta: true, titulo: e.path.name,
                               detalle: area != nil ? "Área" : (e.path.name == layout?.archivo ? "Lo retirado" : "Carpeta"),
                               simbolo: e.privado ? "folder.badge.minus" : "folder", area: area,
                               privado: e.privado, enICloud: e.dataless, tipo: nil)
        }
        let tipoFichero = TipoFichero.de(extension: e.path.ext)
        if let resumen, e.path.ext == "md" || e.path.ext == "markdown" {
            let nombre = resumen.title == e.path.stem ? "" : " · \(e.path.name)"
            return FilaCarpeta(ruta: e.path, esCarpeta: false, titulo: resumen.title, detalle: resumen.kind.etiqueta + nombre,
                               simbolo: resumen.kind.systemImage, area: nil, privado: e.privado || resumen.privado,
                               enICloud: e.dataless, tipo: resumen.kind)
        }
        var detalle = e.path.ext == "csv" ? "Tabla" : (e.path.ext == "md" ? "Nota" : tipoFichero.nombre)
        if let t = TamanoFichero.texto(e.size) { detalle += " · \(t)" }
        return FilaCarpeta(ruta: e.path, esCarpeta: false, titulo: e.path.ext == "md" ? e.path.stem : e.path.name,
                           detalle: detalle, simbolo: FileKindIcon.systemImage(forExtension: e.path.ext), area: nil,
                           privado: e.privado, enICloud: e.dataless, tipo: nil)
    }

    /// A dónde lleva abrir una fila.
    func destino(de fila: FilaCarpeta) -> Destino {
        if fila.esCarpeta { return .carpeta(fila.ruta) }
        return Destino.para(fila.ruta, tipo: fila.tipo, esCarpeta: false)
    }

    func fila(_ ruta: VaultPath) -> FilaCarpeta? { filas.first { $0.ruta == ruta } }

    /// Foto de toda la carpeta (una por cada cambio aplicado), para plantillas y cambios en bloque.
    func instantanea(fresca: Bool = false) async -> VaultSnapshot? {
        if !fresca, let cache, cache.revision == sesion.revision { return cache.foto }
        let revision = sesion.revision
        guard let foto = await sesion.instantanea() else { return nil }
        cache = (revision, foto)
        return foto
    }

    /// Carpetas a las que se puede mover lo elegido (sin `.tls`, sin lo de dentro de lo que se mueve).
    func carpetasDestino(moviendo rutas: [VaultPath]) async -> [VaultPath] {
        guard let foto = await instantanea() else { return [] }
        let archivo = foto.layout.archivo
        return ([VaultPath.root] + foto.directories).filter { d in
            !d.raw.hasPrefix(".") && !d.components.contains(where: { $0.hasPrefix(".") })
                && !rutas.contains(where: { d.isDescendant(of: $0) })
                && !rutas.contains(where: { $0.parent == d })
                && d.components.first != archivo
        }.sorted()
    }

    var opcionesEnlaces: LinkRefactor.Opciones {
        let conflictos = sesion.writer?.conflicts.pendientes().map(\.ruta) ?? sesion.tarjetas.map(\.ruta)
        return LinkRefactor.Opciones(autor: sesion.autor, conflictos: conflictos)
    }

    // MARK: Nueva…

    /// Lo que ofrece «Nueva…»: las plantillas de esta carpeta, las de la ficha elegida y una nota en blanco.
    func opcionesNueva(seleccion: VaultPath?) async -> [OpcionNueva] {
        guard let foto = await instantanea() else { return [] }
        let registro = PlantillaRegistro.cargar(foto)
        var ficha: (ruta: VaultPath, tipo: NoteKind, titulo: String)?
        // La ficha elegida da sus «Nueva … para X» (aunque la lista aún no se haya leído: del índice).
        if let s = seleccion, !sesion.esPrivado(s), let tipo = fila(s)?.tipo ?? sesion.resumen(de: s)?.kind, tipo.abreComoFicha {
            ficha = (s, tipo, fila(s)?.titulo ?? sesion.titulo(de: s))
        }
        return PlantillasCarpeta.opciones(carpeta: carpeta, registro: registro, layout: foto.layout, ficha: ficha)
    }

    /// Valores que se proponen al crear (fecha de hoy de la carpeta, quién la lleva…).
    func valoresIniciales(para opcion: OpcionNueva) async -> [String: String] {
        var v: [String: String] = [:]
        guard let foto = await instantanea() else { return v }
        let reloj = Reloj.deCarpeta(foto)
        for p in opcion.preguntas {
            switch p {
            case "fecha": v[p] = reloj.hoy.description
            case "hora": v[p] = reloj.hora
            case "responsable": v[p] = sesion.persona
            default: break
            }
        }
        return v
    }

    /// Crea la nota (plantilla o en blanco). Si pierde la carrera con otro cambio, la vuelve a preparar con
    /// una foto nueva sin enseñar el error.
    func crear(_ opcion: OpcionNueva, valores: [String: String]) async -> ResultadoCrear {
        if let motivo = motivoSoloLectura { return .error(motivo) }
        let limpios = valores.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.value.isEmpty }
        for intento in 0..<2 {
            guard let foto = await instantanea(fresca: intento > 0) else { return .error("No he podido leer la carpeta.") }
            let preparada: (ruta: VaultPath, titulo: String, plan: WritePlan, destino: Destino)
            do {
                preparada = try preparar(opcion, valores: limpios, foto: foto)
            } catch PlantillaError.yaExiste(let r) {
                return .yaExiste(VaultPath(r))
            } catch {
                return .error((error as? LocalizedError)?.errorDescription ?? "No he podido preparar la nota.")
            }
            switch await escribirSinRuido(preparada.plan, aviso: "Creé «\(preparada.titulo)»", ultimo: intento == 1) {
            case .hecho:
                seleccion = [preparada.ruta]
                return .hecho(preparada.ruta, destino: preparada.destino)
            case .carrera:
                continue
            case .error(let t):
                return .error(t)
            }
        }
        return .error("Alguien cambió la carpeta a la vez. Vuelve a intentarlo.")
    }

    private func preparar(_ opcion: OpcionNueva, valores: [String: String], foto: VaultSnapshot) throws
        -> (ruta: VaultPath, titulo: String, plan: WritePlan, destino: Destino) {
        guard let plantilla = opcion.plantilla else {
            // Nota en blanco: el título es el nombre del fichero.
            let titulo = valores["titulo"] ?? ""
            let nombre = NombresDeFicha.fichero(titulo)
            guard !nombre.isEmpty else { throw PlantillaError.faltaDato("titulo") }
            let ruta = (opcion.carpetaForzada ?? carpeta).appending(nombre + ".md")
            if foto.existing(ruta) != nil { throw PlantillaError.yaExiste(ruta.raw) }
            var ops = LinkRefactor(snapshot: foto).protegerEnlaces(alCrear: [ruta], opciones: .init(autor: sesion.autor))
            ops.append(.create(ruta, text: "# \(titulo)\n\n"))
            return (ruta, titulo, WritePlan(autor: sesion.autor, descripcion: "Crear «\(titulo)»", ops: ops), .nota(ruta))
        }
        let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: sesion.persona))
        let def = motor.registro[plantilla]
        let peticion = PlantillaMotor.Peticion(plantilla: plantilla, desde: opcion.desde, valores: valores,
                                               area: foto.layout.area(of: carpeta),
                                               carpeta: def?.carpeta == nil ? carpeta : opcion.carpetaForzada,
                                               autor: sesion.autor)
        let nota = try motor.preparar(peticion)
        let tipo = (opcion.tipo ?? def?.tipo).flatMap(NoteKind.init(rawValue:))
        return (nota.ruta, nota.titulo, nota.plan, Destino.para(nota.ruta, tipo: tipo, esCarpeta: false))
    }

    /// «Completar la que hay»: añade a una nota de nombre fijo lo que le falta de su plantilla.
    func completar(_ ruta: VaultPath, con opcion: OpcionNueva) async -> String? {
        guard let plantilla = opcion.plantilla, let foto = await instantanea(fresca: true) else { return "No he podido leer la carpeta." }
        let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: sesion.persona))
        do {
            guard let plan = try motor.aplicar(plantilla, a: ruta, autor: sesion.autor) else {
                sesion.aviso = Aviso("«\(ruta.stem)» ya tenía todo lo de la plantilla", estado: .bien, tituloAccion: "")
                return nil
            }
            try await sesion.escribir(plan: plan, aviso: "Completé «\(ruta.stem)» con la plantilla")
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "No he podido completarla."
        }
    }

    // MARK: Renombrar y mover

    /// Vista previa de renombrar (qué enlaces cambian). No escribe.
    func prepararRenombrar(_ ruta: VaultPath, a nombre: String, fresca: Bool = false) async throws -> RefactorPreview {
        guard let foto = await instantanea(fresca: fresca) else { throw RefactorError.noExiste(ruta.raw) }
        let opciones = opcionesEnlaces
        return try await Task.detached(priority: .userInitiated) {
            try LinkRefactor(snapshot: foto).renombrar(ruta, a: nombre, opciones: opciones)
        }.value
    }

    /// Vista previa de mover una o varias rutas a otra carpeta. No escribe.
    func prepararMover(_ rutas: [VaultPath], a destino: VaultPath, fresca: Bool = false) async throws -> RefactorPreview {
        guard let foto = await instantanea(fresca: fresca) else { throw RefactorError.noExiste(rutas.first?.raw ?? "") }
        let opciones = opcionesEnlaces
        return try await Task.detached(priority: .userInitiated) {
            let motor = LinkRefactor(snapshot: foto)
            if rutas.count == 1 { return try motor.mover(rutas[0], a: destino, opciones: opciones) }
            let traslados = rutas.map { Traslado(de: $0, a: destino.appending($0.name)) }
            return try motor.preparar(traslados, descripcion: "Mover \(rutas.count) elementos", opciones: opciones)
        }.value
    }

    /// Aplica un cambio en bloque ya revisado (`LinkRefactor.aplicar` con el bus de la sesión) y lo deja en
    /// Deshacer con su aviso («Actualicé 12 enlaces en 7 ficheros · Deshacer»). Si alguien cambió algo entre
    /// medias, lo vuelve a preparar con `rehacer` una vez sin enseñar el error.
    func aplicar(_ preview: RefactorPreview, rehacer: (() async throws -> RefactorPreview)? = nil) async -> ResultadoCambio {
        var actual = preview
        for intento in 0..<2 {
            guard actual.esSeguro else { return .enRiesgo(actual.problemas.count) }
            let bus: CommandBus
            do { bus = try sesion.busParaEscribir() } catch {
                return .error(motivoSoloLectura ?? error.localizedDescription)
            }
            do {
                let r = try await LinkRefactor.aplicar(actual, con: bus)
                if case .conflicto = r.estado, intento == 0, let rehacer {
                    actual = try await rehacer()
                    continue
                }
                sesion.registrarDeshacer(r, descripcion: actual.descripcion, aviso: actual.avisoHecho)
                if case .hecho = r.estado, !actual.traslados.isEmpty {
                    // Lo renombrado sigue elegido (si se queda en esta carpeta).
                    seleccion = Set(actual.traslados.map(\.a).filter { ($0.parent ?? .root) == carpeta })
                }
                cache = nil
                return .hecho(r)
            } catch let e as WriteError where intento == 0 && rehacer != nil && Self.esCarrera(e) {
                do { actual = try await rehacer!() } catch {
                    return .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
                continue
            } catch {
                let texto = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                sesion.aviso = Aviso(texto, estado: .mal, tituloAccion: "")
                return .error(texto)
            }
        }
        return .error("Alguien cambió la carpeta a la vez. Vuelve a intentarlo.")
    }

    static func esCarrera(_ e: WriteError) -> Bool {
        if case .cambioExterno = e { return true }
        return false
    }

    // MARK: Retirar

    /// Retira a `Archivo/` (nunca se borra), con Deshacer.
    @discardableResult
    func retirar(_ ruta: VaultPath) async -> Bool {
        do {
            let r = try await sesion.escribir(.retirar(ruta), aviso: "Retiré «\(ruta.stem)» al Archivo")
            seleccion.remove(ruta)
            cache = nil
            return r.hecho
        } catch {
            return false
        }
    }

    /// La propia carpeta `Archivo` (ni se mueve ni se renombra: allí va lo retirado).
    func esLaCarpetaArchivo(_ ruta: VaultPath) -> Bool {
        guard let archivo = sesion.estructura?.archivo else { return false }
        return ruta.components.count == 1 && TextFolding.nameKey(ruta.name) == TextFolding.nameKey(archivo)
    }

    /// Si algo de lo que se mueve deja de estar en una carpeta privada, el aviso que lo explica antes de mover.
    func avisoSalePrivado(_ rutas: [VaultPath], a destino: VaultPath) -> String? {
        let salen = rutas.filter { sesion.esPrivado($0) && !sesion.esPrivado(destino.appending($0.name)) }
        guard let primera = salen.first else { return nil }
        let que = salen.count == 1 ? "«\(primera.stem)» está en una carpeta privada" : "\(salen.count) elementos están en una carpeta privada"
        return que + ". Fuera de ella se verá en las bases, en la búsqueda y en las vistas previas."
    }

    /// `true` si ya está en `Archivo/` (no se puede retirar otra vez).
    func estaRetirada(_ ruta: VaultPath) -> Bool {
        guard let archivo = sesion.estructura?.archivo else { return false }
        return ruta.components.first == archivo
    }

    // MARK: Movido fuera de la app

    /// Busca lo que se movió fuera de la app con enlaces pendientes de arreglar (en segundo plano).
    func revisarMovimientosExternos(fresca: Bool = false) async {
        guard sesion.puedeEscribir, !revisando else { return }
        revisando = true
        defer { revisando = false }
        guard let foto = await instantanea(fresca: fresca) else { return }
        let antes = self.antes
        let opciones = opcionesEnlaces
        let descartados = self.descartados
        let previa = await Task.detached(priority: .utility) { () -> RefactorPreview? in
            let traslados = MovimientosExternos.detectar(antes: antes, ahora: foto)
                .filter { !descartados.contains("\($0.de.raw)>\($0.a.raw)") }
            return MovimientosExternos.arreglo(traslados, foto: foto, opciones: opciones)
        }.value
        self.antes = Set(foto.files)
        arreglo = previa
    }

    /// `true` si un lote de cambios puede ser un movimiento (algo aparece o desaparece).
    func cambioDeExistencia(_ rutas: Set<VaultPath>) -> Bool {
        guard let antes else { return true }
        if rutas.isEmpty { return true }
        guard let root = sesion.root else { return false }
        return rutas.contains { antes.contains($0) != FileManager.default.fileExists(atPath: $0.url(in: root).path) }
    }

    /// «Arreglar los enlaces» de lo movido fuera de la app.
    func arreglarMovimientos() async -> ResultadoCambio {
        guard let previa = arreglo else { return .error("No hay nada que arreglar.") }
        let resultado = await aplicar(previa) { [weak self] in
            guard let self, let foto = await self.instantanea(fresca: true),
                  let p = MovimientosExternos.arreglo(previa.traslados, foto: foto, opciones: self.opcionesEnlaces)
            else { throw RefactorError.sinCambios }
            return p
        }
        if case .hecho = resultado { arreglo = nil }
        return resultado
    }

    /// «Ahora no»: no vuelve a proponer estos arreglos en esta pantalla.
    func descartarArreglo() {
        for t in arreglo?.traslados ?? [] { descartados.insert("\(t.de.raw)>\(t.a.raw)") }
        arreglo = nil
    }

    // MARK: Escribir sin ruido

    enum Escritura { case hecho(WriteResult), carrera, error(String) }

    /// Escribe un plan por el bus de la sesión; una carrera (cambio de fuera entre medias) no se enseña si
    /// queda otro intento.
    private func escribirSinRuido(_ plan: WritePlan, aviso: String, ultimo: Bool) async -> Escritura {
        let bus: CommandBus
        do { bus = try sesion.busParaEscribir() } catch { return .error(motivoSoloLectura ?? error.localizedDescription) }
        do {
            let r = try await bus.ejecutar(plan)
            if case .conflicto = r.estado, !ultimo { return .carrera }
            sesion.registrarDeshacer(r, descripcion: plan.descripcion, aviso: aviso)
            cache = nil
            return .hecho(r)
        } catch let e as WriteError where !ultimo && (Self.esCarrera(e) || e.esDestinoOcupado) {
            return .carrera
        } catch {
            let texto = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sesion.aviso = Aviso(texto, estado: .mal, tituloAccion: "")
            return .error(texto)
        }
    }
}

private extension WriteError {
    /// Otra nota con ese nombre apareció entre la foto y la escritura (se prepara otra vez).
    var esDestinoOcupado: Bool {
        if case .destinoOcupado = self { return true }
        return false
    }
}
