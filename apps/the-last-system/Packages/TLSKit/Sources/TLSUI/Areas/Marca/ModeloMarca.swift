import Foundation
import Observation
import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol areas-b. Lo que pinta Marca › Operación (PLAN §6.5; SISTEMAS MA2 y MA3; PLANTILLAS §4): las piezas de
// contenido (`tls_type: content`) con su estado, fechas, canales y resultados, y las conversaciones (`conversation`)
// con la pieza que las trajo. Puro y `Sendable`; **nunca enseña lo privado** ni lo retirado a `Archivo/`. Lo que falta
// es «Sin dato», nunca 0.

/// Estados de una pieza (PLANTILLAS §4.1): Idea → Borrador → En revisión → Aprobado → Programado → Publicado, o
/// Descartado.
enum EstadoPieza: String, CaseIterable, Sendable, Hashable {
    case idea = "Idea"
    case borrador = "Borrador"
    case enRevision = "En revisión"
    case aprobado = "Aprobado"
    case programado = "Programado"
    case publicado = "Publicado"
    case descartado = "Descartado"

    init?(leyendo texto: String?) {
        guard let t = texto.map(TextFolding.fold)?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        guard let e = Self.allCases.first(where: { TextFolding.fold($0.rawValue) == t }) else { return nil }
        self = e
    }

    /// Las columnas del tablero (Descartado va aparte).
    static let tablero: [EstadoPieza] = [.idea, .borrador, .enRevision, .aprobado, .programado, .publicado]

    var estado: TLSEstado {
        switch self {
        case .publicado: .bien
        case .programado, .aprobado: .atencion
        default: .sinDato
        }
    }
}

/// Estados de una conversación (plantilla «Conversación»): Nueva · Propuesta a Ventas · Cualificada · No cualifica.
enum EstadoConversacion: String, CaseIterable, Sendable, Hashable {
    case nueva = "Nueva"
    case propuesta = "Propuesta a Ventas"
    case cualificada = "Cualificada"
    case noCualifica = "No cualifica"

    init(leyendo texto: String?) {
        let t = TextFolding.fold(texto ?? "").trimmingCharacters(in: .whitespaces)
        self = Self.allCases.first { TextFolding.fold($0.rawValue) == t } ?? .nueva
    }

    var estado: TLSEstado {
        switch self {
        case .cualificada: .bien
        case .propuesta: .atencion
        case .nueva, .noCualifica: .sinDato
        }
    }
}

/// Una pieza de contenido.
struct PiezaMarca: Identifiable, Hashable, Sendable {
    var id: VaultPath { ruta }
    let ruta: VaultPath
    let titulo: String
    let tipo: String?
    let estado: EstadoPieza?
    /// El estado tal como está escrito (si no es uno de los conocidos).
    let estadoTexto: String?
    let pilar: String?
    let canales: [String]
    /// Cuándo se quiere publicar (se mueve en el calendario).
    let publicar: LocalDate?
    /// Cuándo se publicó (no se mueve).
    let publicado: LocalDate?
    let evidencia: String?
    let alcance: Double?
    let impresiones: Double?
    let interacciones: Double?

    /// Día en el calendario: el de publicación si ya salió; si no, el de publicar.
    var dia: LocalDate? { estado == .publicado ? (publicado ?? publicar) : (publicar ?? publicado) }
    /// Se puede mover en el calendario (lo publicado ya tiene su día).
    var movible: Bool { estado != .publicado && estado != .descartado }
    var palabraEstado: String { estado?.rawValue ?? estadoTexto ?? "Sin estado" }
}

/// Una conversación que vino de lo publicado.
struct ConversacionMarca: Identifiable, Hashable, Sendable {
    var id: VaultPath { ruta }
    let ruta: VaultPath
    /// Quién: el contacto, si ya lo hay; si no, el perfil.
    let quien: String
    let perfil: String?
    let canal: String?
    let fecha: LocalDate?
    let estado: EstadoConversacion
    /// La pieza que la trajo (si se encuentra y no es privada) y su título.
    let pieza: VaultPath?
    let piezaTitulo: String?
    let oportunidad: String?
    let motivo: String?
    /// La primera línea de «## Lo que dijo».
    let loQueDijo: String?
}

/// Lo publicado en un canal y lo que trajo.
struct CanalMarca: Identifiable, Hashable, Sendable {
    var id: String { canal }
    let canal: String
    let publicadas: Int
    /// Suma de las piezas que lo dicen; `nil` si ninguna lo dice («Sin dato»).
    let alcance: Double?
    let interacciones: Double?
    let conversaciones: Int
    let cualificadas: Int
}

/// Marca leída de una foto de la carpeta.
struct LecturaMarca: Sendable {
    let hoy: LocalDate
    let piezas: [PiezaMarca]
    let conversaciones: [ConversacionMarca]
    let carpeta: VaultPath

    init(foto: VaultSnapshot, hoy: LocalDate) {
        let layout = foto.layout
        let resolver = foto.resolver
        self.hoy = hoy
        carpeta = layout.areaFolder(.marca)
        var piezas: [PiezaMarca] = []
        var crudas: [(VaultPath, Frontmatter, String)] = []
        for p in foto.notes where !layout.isPrivate(p) && !layout.isArchived(p) && !VaultSnapshot.isTemplatePath(p) {
            guard let texto = foto.text(p) else { continue }
            let doc = NoteDocument(text: texto)
            let fm = doc.frontmatter
            switch NoteKindResolver.kind(of: p, frontmatter: fm, layout: layout) {
            case .content:
                let estadoTexto = fm.text("estado")
                piezas.append(PiezaMarca(
                    ruta: p, titulo: fm.titleText ?? doc.title(fileStem: p.stem, frontmatter: fm), tipo: fm.text("tipo"),
                    estado: EstadoPieza(leyendo: estadoTexto), estadoTexto: estadoTexto, pilar: fm.text("pilar"),
                    canales: Self.lista(fm, "canales"), publicar: Self.fecha(fm, "publicar"), publicado: Self.fecha(fm, "publicado"),
                    evidencia: fm.text("evidencia_url") ?? fm.text("evidencia"), alcance: Self.numero(fm, "alcance"),
                    impresiones: Self.numero(fm, "impresiones"), interacciones: Self.numero(fm, "interacciones")))
            case .conversation:
                crudas.append((p, fm, doc.body))
            default:
                continue
            }
        }
        self.piezas = piezas.sorted { ($0.dia ?? .init(year: 9999, month: 12, day: 31)!, $0.titulo) < ($1.dia ?? .init(year: 9999, month: 12, day: 31)!, $1.titulo) }
        let titulos = Dictionary(piezas.map { ($0.ruta, $0.titulo) }, uniquingKeysWith: { a, _ in a })
        conversaciones = crudas.map { p, fm, body in
            var pieza: VaultPath?
            if let c = fm.text("contenido"), let l = LinkParser.links(in: c).first(where: { !$0.isExternal }),
               let r = resolver.resolve(l.resolvable, from: p), !layout.isPrivate(r) {
                pieza = r
            }
            let contacto = fm.text("contacto").map(LinkParser.plainText)?.trimmingCharacters(in: .whitespaces)
            let perfil = fm.text("perfil")
            let dijo = MarkdownSections.content(of: "Lo que dijo", in: body)?
                .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix(">") }
            return ConversacionMarca(
                ruta: p, quien: (contacto?.isEmpty == false ? contacto : nil) ?? perfil ?? p.stem, perfil: perfil,
                canal: fm.text("canal"), fecha: Self.fecha(fm, "fecha"), estado: EstadoConversacion(leyendo: fm.text("estado")),
                pieza: pieza, piezaTitulo: pieza.flatMap { titulos[$0] } ?? fm.text("contenido").map(LinkParser.plainText),
                oportunidad: fm.text("oportunidad").map(LinkParser.plainText), motivo: fm.text("motivo"), loQueDijo: dijo)
        }.sorted { ($0.fecha ?? hoy, $0.quien) > ($1.fecha ?? hoy, $1.quien) }
    }

    // MARK: Consultas

    func conversaciones(de pieza: PiezaMarca) -> [ConversacionMarca] { conversaciones.filter { $0.pieza == pieza.ruta } }

    var publicadas: [PiezaMarca] { piezas.filter { $0.estado == .publicado } }

    /// Piezas del tablero en un estado (las de estado desconocido, en Idea).
    func piezas(en e: EstadoPieza) -> [PiezaMarca] {
        piezas.filter { ($0.estado ?? .idea) == e }
    }

    /// Piezas de cada día de un mes (las descartadas no salen).
    func calendario(anio: Int, mes: Int) -> [LocalDate: [PiezaMarca]] {
        Dictionary(grouping: piezas.filter { p in
            guard p.estado != .descartado, let d = p.dia else { return false }
            return d.year == anio && d.month == mes
        }, by: { $0.dia! })
    }

    /// Piezas vivas sin fecha (ni de publicar ni de publicación).
    var sinFecha: [PiezaMarca] { piezas.filter { $0.dia == nil && $0.estado != .descartado } }

    /// Lo publicado en cada canal y lo que trajo (conversaciones de sus piezas), del canal con más piezas al que menos.
    var canales: [CanalMarca] {
        var nombres: [String] = []
        for p in publicadas { for c in p.canales where !nombres.contains(c) { nombres.append(c) } }
        for c in conversaciones { if let k = c.canal, !nombres.contains(k) { nombres.append(k) } }
        return nombres.map { canal in
            let ps = publicadas.filter { $0.canales.contains(canal) }
            let cs = conversaciones.filter { $0.canal == canal }
            func suma(_ k: KeyPath<PiezaMarca, Double?>) -> Double? {
                let v = ps.compactMap { $0[keyPath: k] }
                return v.isEmpty ? nil : v.reduce(0, +)
            }
            return CanalMarca(canal: canal, publicadas: ps.count, alcance: suma(\.alcance), interacciones: suma(\.interacciones),
                              conversaciones: cs.count, cualificadas: cs.filter { $0.estado == .cualificada }.count)
        }
        .sorted { ($0.publicadas, $0.conversaciones) > ($1.publicadas, $1.conversaciones) }
    }

    // MARK: Lectura de propiedades

    static func fecha(_ fm: Frontmatter, _ k: String) -> LocalDate? { fm.text(k).flatMap { LocalDate(parsing: $0) } }

    static func numero(_ fm: Frontmatter, _ k: String) -> Double? { fm.text(k).flatMap(FormatoBase.numero) }

    static func lista(_ fm: Frontmatter, _ k: String) -> [String] {
        switch fm.value(k) {
        case .list(let l)?: return l.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case .text(let t)?: return t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        default: return []
        }
    }

    /// «instagram» → «Instagram».
    static func nombreCanal(_ c: String) -> String {
        switch TextFolding.fold(c) {
        case "linkedin": "LinkedIn"
        case "instagram": "Instagram"
        case "newsletter": "Newsletter"
        case "blog": "Blog"
        case "web": "Web"
        case "youtube": "YouTube"
        case "tiktok": "TikTok"
        case "correo", "email": "Correo"
        default: FormatoFicha.capital(c)
        }
    }

    /// El tipo de pieza en palabras: «articulo» → «Artículo», «video» → «Vídeo corto».
    static func nombreTipo(_ t: String) -> String {
        switch TextFolding.fold(t).replacingOccurrences(of: "_", with: " ") {
        case "post": "Post"
        case "carrusel": "Carrusel"
        case "video", "video corto": "Vídeo corto"
        case "newsletter": "Newsletter"
        case "articulo": "Artículo"
        case "caso", "caso de exito": "Caso de éxito"
        case "testimonio": "Testimonio"
        case "anuncio": "Anuncio"
        default: FormatoFicha.capital(t)
        }
    }

    /// «1.250» o «Sin dato».
    static func cifra(_ v: Double?) -> String { v.map { FormatoBase.cifra($0) } ?? "Sin dato" }
}

/// El modelo de Marca › Operación: lee `LecturaMarca` con cada `sesion.revision` y escribe, como la persona y con
/// Deshacer, lo que esta pantalla deja tocar: el estado de una pieza (tablero), su día de publicar (calendario) y
/// «Proponer a Ventas» (crea la tarea en Ventas y deja la conversación en «Propuesta a Ventas», en un solo cambio).
/// Marca no cualifica: lo decide Ventas. Generar borradores llega con los asistentes (F4).
@Observable @MainActor
final class ModeloMarca {
    let sesion: VaultSession
    private(set) var lectura: LecturaMarca?
    private(set) var revisionLeida = -1
    private(set) var error: String?
    private(set) var hecho: String?
    @ObservationIgnored private var carga: Task<Void, Never>?

    init(sesion: VaultSession) { self.sesion = sesion }

    var motivoSoloLectura: String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .soloLectura(let m): m.texto
        case .abriendo: "La carpeta aún se está abriendo"
        }
    }

    func cargar(forzar: Bool = false) async {
        let revision = sesion.revision
        guard forzar || revision != revisionLeida || lectura == nil else { return }
        if let carga { await carga.value; if !forzar, revision == revisionLeida, lectura != nil { return } }
        let almacen = AlmacenRelaciones.de(sesion)
        if forzar { almacen.invalidar() }
        let tarea = Task { [weak self] in
            await almacen.actualizar()
            guard let self, let foto = almacen.foto else { return }
            let hoy = self.sesion.hoy
            let leida = await Task.detached(priority: .userInitiated) { LecturaMarca(foto: foto, hoy: hoy) }.value
            guard !Task.isCancelled else { return }
            self.lectura = leida
            self.revisionLeida = revision
        }
        carga = tarea
        await tarea.value
        carga = nil
    }

    /// Cambia el estado de una pieza (solo esa línea; al pasar a Publicado sin fecha de publicación, también `publicado`).
    @discardableResult
    func mover(_ p: PiezaMarca, a nuevo: EstadoPieza, deshacer: UndoManager?) async -> Bool {
        guard p.estado != nuevo else { return false }
        var poner = [Property(key: "estado", value: .text(nuevo.rawValue))]
        if nuevo == .publicado, p.publicado == nil {
            poner.append(Property(key: "publicado", value: .text(sesion.hoy.description)))
        }
        return await escribir(.cambiarPropiedades(p.ruta, poner: poner, quitar: []), aviso: "«\(p.titulo)»: \(nuevo.rawValue)",
                              deshacer: deshacer)
    }

    /// Cambia el día de publicar de una pieza (o lo quita con `nil`). Lo ya publicado no se mueve.
    @discardableResult
    func cambiarDia(_ p: PiezaMarca, a dia: LocalDate?, deshacer: UndoManager?) async -> Bool {
        guard p.movible, dia != p.publicar else { return false }
        let comando: CommandBus.Comando = dia.map {
            .cambiarPropiedades(p.ruta, poner: [Property(key: "publicar", value: .text($0.description))], quitar: [])
        } ?? .cambiarPropiedades(p.ruta, poner: [], quitar: ["publicar"])
        let hoy = sesion.hoy
        let aviso = dia.map { "«\(p.titulo)» se publicará el \(FormatoFicha.fechaConDia($0, hoy: hoy))" } ?? "«\(p.titulo)» queda sin fecha"
        return await escribir(comando, aviso: aviso, deshacer: deshacer)
    }

    /// «Proponer a Ventas»: una tarea en Ventas para decidir si cualifica y la conversación en «Propuesta a Ventas».
    /// Un solo cambio, un solo Deshacer. Marca no cualifica.
    @discardableResult
    func proponerAVentas(_ c: ConversacionMarca, deshacer: UndoManager?) async -> Bool {
        error = nil; hecho = nil
        guard c.estado == .nueva else { return false }
        if let m = motivoSoloLectura { error = "No se puede escribir: \(m)."; return false }
        let almacen = AlmacenRelaciones.de(sesion)
        await almacen.actualizar()
        guard let foto = almacen.foto else { return false }
        let canal = c.canal.map { " en \(LecturaMarca.nombreCanal($0))" } ?? ""
        var descripcion = "Conversación que vino de Marca\(canal): \(NombresDeFicha.wikilink(c.ruta, nombre: c.quien, en: foto))."
        if let d = c.loQueDijo { descripcion += "\n\nLo que dijo: \(d)" }
        if let t = c.piezaTitulo { descripcion += "\n\nViene de «\(t)»." }
        descripcion += "\n\nDecide si cualifica. Si cualifica, nacen el contacto, la empresa y la oportunidad con esta conversación como origen."
        do {
            let nota = try TaskStore(snapshot: foto, reloj: Reloj(hoy: sesion.hoy)).crear(NuevaTarea(
                titulo: "Decidir si cualifica la conversación con \(c.quien)", area: .ventas, descripcion: descripcion,
                origen: "manual", autor: sesion.autor,
                propiedades: [Property(key: "conversacion", value: .text(NombresDeFicha.wikilink(c.ruta, nombre: c.quien, en: foto)))]))
            var ops = nota.plan.ops
            ops.append(.mergeFrontmatter(c.ruta, set: [Property(key: "estado", value: .text(EstadoConversacion.propuesta.rawValue))], unset: []))
            let plan = WritePlan(autor: sesion.autor, descripcion: "Proponer a Ventas la conversación con \(c.quien)", ops: ops)
            let r = try await sesion.escribirConDominio(plan: plan, aviso: "Propuesta a Ventas: \(c.quien)", deshacer: deshacer)
            if case .conflicto = r.escritura.estado { error = "La conversación cambió fuera a la vez. Revísalo en Revisar."; return false }
            hecho = "Propuesta a Ventas: \(nota.numero ?? "una tarea") para decidir si cualifica."
        } catch {
            self.error = error.localizedDescription
            await cargar(forzar: true)
            return false
        }
        await cargar(forzar: true)
        return true
    }

    private func escribir(_ comando: CommandBus.Comando, aviso: String, deshacer: UndoManager?) async -> Bool {
        error = nil; hecho = nil
        if let m = motivoSoloLectura { error = "No se puede escribir: \(m)."; return false }
        do {
            let r = try await sesion.escribirConDominio(comando, aviso: aviso, deshacer: deshacer)
            if case .conflicto = r.escritura.estado { error = "La pieza cambió fuera a la vez. Revísalo en Revisar."; await cargar(forzar: true); return false }
        } catch {
            self.error = error.localizedDescription
            return false
        }
        await cargar(forzar: true)
        return true
    }
}
