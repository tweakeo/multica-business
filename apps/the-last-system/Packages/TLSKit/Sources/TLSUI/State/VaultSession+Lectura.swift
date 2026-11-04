import Foundation
import TLSCore
import TLSDesign

/// Lectura para las pantallas (F1). Nada de esto escribe ni descarga de iCloud salvo `leer`, que es abrir
/// (acción explícita de la persona) y pide la descarga de una nota de texto.
public extension VaultSession {
    /// Lee una ruta para enseñarla: contenido, ficha del índice, «Enlazan aquí» y estilo del Markdown.
    /// No cambia el estado de la sesión (cada pantalla guarda su propia lectura; ver `LectorNota`).
    func leer(_ path: VaultPath) async -> NoteSnapshot? {
        guard let service else { return nil }
        // El número va por orden de empezar a leer: una lectura que empezó antes y llega tarde se reconoce.
        lecturas += 1
        let numero = lecturas
        let result = await Task.detached(priority: .userInitiated) { () -> (NoteContent, NoteSummary?, [NoteSummary], [MarkdownSpan]?) in
            let content = service.read(path)
            var spans: [MarkdownSpan]?
            if case .markdown(_, _, let body, _, _) = content { spans = MarkdownStyler.spans(forMarkdown: body) }
            return (content, service.summary(of: path), service.backlinks(to: path), spans)
        }.value
        return NoteSnapshot(path: path, content: result.0, summary: result.1, backlinks: result.2,
                            lectura: numero, spans: result.3)
    }

    /// Ficha del índice de una ruta (título, tipo, área, privado…). Instantáneo.
    func resumen(de path: VaultPath) -> NoteSummary? {
        service?.summary(of: path)
    }

    /// ⌘O y sugerencias: por nombre y título, sin tildes. Sin lo privado.
    func abrirRapido(_ texto: String, limite: Int = 20) async -> [NoteSummary] {
        guard let service else { return [] }
        let q = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) { service.quickOpen(q, limit: limite) }.value
            .filter { !$0.privado }
    }

    /// Texto completo (FTS5, sin tildes), con el fragmento entre «‹» y «›». Sin lo privado.
    func buscar(_ texto: String, limite: Int = 50) async -> [SearchHit] {
        guard let service else { return [] }
        let q = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) { service.search(q, limit: limite) }.value
            .filter { !$0.note.privado }
    }

    /// Notas que enlazan a una ruta («Enlazan aquí»).
    func enlazanAqui(_ path: VaultPath) -> [NoteSummary] {
        service?.backlinks(to: path) ?? []
    }

    /// Foto completa de la carpeta (texto de cada nota, propiedades, enlaces) para lo que necesita verlo
    /// todo a la vez: bases, relaciones inversas, plantillas, `TaskStore`, `LinkRefactor`. Fuera del hilo
    /// principal; sin lo que la persona dejó fuera. Lo privado **sí** está: filtrarlo con `esPrivado`.
    func instantanea() async -> VaultSnapshot? {
        guard let root else { return nil }
        let entry = self.entry
        let layout = service?.layout
        return await Task.detached(priority: .userInitiated) {
            VaultSnapshot.read(root: root, layout: layout, excluded: entry.exclusionesCopia.map { VaultPath($0) })
        }.value
    }

    /// `true` si la ruta es privada: no se enseña en bases, ⌘K ni vistas previas.
    func esPrivado(_ path: VaultPath) -> Bool {
        if let s = resumen(de: path) { return s.privado }
        return service?.layout.isPrivate(path) ?? false
    }

    /// Estructura de la carpeta (áreas, carpetas de cada tipo, privado).
    var estructura: VaultLayout? { service?.layout }

    // MARK: Nombres para migas, pestañas e historial

    /// Título de una ruta (el del índice o, si no, el nombre del fichero).
    func titulo(de path: VaultPath) -> String {
        if let t = titulos[path] { return t }
        let t = resumen(de: path)?.title ?? (path.isRoot ? entry.nombre : path.stem)
        titulos[path] = t
        return t
    }

    /// Nombre completo de un destino.
    func nombre(de destino: Destino) -> String {
        switch destino {
        case .hoy: "Hoy"
        case .decisiones: "Decisiones"
        case .tareas: "Tareas"
        case .revisar: "Revisar"
        case .area(let code, _): area(code)?.etiquetaNumerada ?? code.etiquetaNumerada
        case .todasLasBases: "Todas las bases"
        case .base(let id, _, let contexto):
            (barraLateral.base(id)?.nombre ?? id.capitalized) + (contexto.map { " de \(titulo(de: $0))" } ?? "")
        case .ficha(let p, _), .nota(let p), .fichero(let p): titulo(de: p)
        case .carpeta(nil): "Carpeta"
        case .carpeta(let p?): p.name
        case .busqueda(let q): "Buscar «\(q)»"
        case .asistentes: "Asistentes"
        case .asistente(let slug): nombreDeAsistente(slug)  // F4: `Asistentes/ComponentesAsistentes.swift`
        case .ajustes: "Ajustes"
        case .tarea, .decision, .banco: nombreF2(de: destino)  // F2: `Navegacion/RutasF2.swift`
        }
    }

    /// Icono del destino: el del tipo de la ficha si se conoce.
    func simbolo(de destino: Destino) -> String {
        switch destino {
        case .ficha(let p, _), .nota(let p):
            resumen(de: p)?.kind.systemImage ?? destino.simbolo
        case .base(let id, _, _):
            barraLateral.base(id)?.icono ?? destino.simbolo
        default:
            destino.simbolo
        }
    }

    /// Las migas de una pestaña, con nombre corto (§2.3).
    func migas(de nav: Navegacion) -> [Miga] {
        var anteriores: [String] = []
        return nav.migas.enumerated().map { i, d in
            let completo = nombre(de: d)
            var codigo: String?
            if case .ficha(let p, _) = d { codigo = PlegadoMigas.codigo(titulo: completo, fichero: p.stem) }
            let corto = PlegadoMigas.nombreCorto(completo, codigo: codigo, anteriores: anteriores)
            anteriores.append(completo)
            var area: AreaCode?
            if case .area(let a, _) = d { area = a }
            // La pestaña de origen va en la miga de la que se salió (M2-Proyecto: «Jorge Martín · Proyectos»): la
            // guarda el nivel siguiente, que es el que se entró desde ella.
            return Miga(id: i, destino: d, nombre: corto, completo: completo, icono: simbolo(de: d), area: area,
                        pestanaOrigen: nav.pestanasDeOrigen[i + 1])
        }
    }

    /// Enlace para pegar en una nota (`[[ruta|Título]]`), si el destino es algo de la carpeta.
    func enlaceParaCopiar(_ destino: Destino) -> String? {
        guard let p = destino.ruta, !p.isRoot else { return nil }
        let sinExtension = p.ext == "md" ? String(p.raw.dropLast(3)) : p.raw
        return "[[\(sinExtension)|\(titulo(de: p))]]"
    }

    // MARK: Navegar desde fuera de las vistas

    /// A dónde lleva abrir una ruta: carpeta, ficha, nota o fichero.
    func destino(para path: VaultPath) -> Destino {
        Destino.para(path, tipo: resumen(de: path)?.kind, esCarpeta: isDirectory(path))
    }

    /// Navega en la pestaña con el foco (las vistas usan `@Environment(\.navegar)`).
    func navegar(a destino: Destino, modo: ModoApertura = .automatico) {
        let accion = NavegarAccion(nav: navegacionActiva, empresa: entry.id) { [weak self] ruta in
            self?.abrirVentana?(ruta)
        }
        accion(destino, modo: modo)
    }

    /// Apunta una visita (Recientes). Lo llama la ventana cuando cambia lo que se ve.
    func registrarVisita(_ destino: Destino) {
        guard let p = destino.ruta, !p.isRoot else { return }
        switch destino {
        case .ficha, .nota, .fichero: break
        default: return
        }
        guard !esPrivado(p) else { return }
        recientes.removeAll { $0 == p }
        recientes.insert(p, at: 0)
        if recientes.count > 12 { recientes.removeLast(recientes.count - 12) }
    }
}
