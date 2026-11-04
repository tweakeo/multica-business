import Foundation
import TLSCore

/// Lo justo de una nota para saber qué cambió: su tipo, su estado, su responsable y una huella del texto.
struct HuellaNota: Sendable, Hashable {
    var tipo: String?
    var estado: String?
    var responsable: String?
    /// `tipo` de una tarea: tarea, pregunta o decisión.
    var tipoTarea: String?
    /// Líneas del registro de decisiones (solo en `Decisiones.md`).
    var decisiones: Int?
    var contenido: Int

    init(tipo: String? = nil, estado: String? = nil, responsable: String? = nil, tipoTarea: String? = nil,
         decisiones: Int? = nil, contenido: Int) {
        self.tipo = tipo; self.estado = estado; self.responsable = responsable; self.tipoTarea = tipoTarea
        self.decisiones = decisiones; self.contenido = contenido
    }

    init(ruta: VaultPath, texto: String, layout: VaultLayout) {
        var h = Hasher()
        h.combine(texto)
        contenido = h.finalize()
        guard ruta.ext == "md" else { return }
        let fm = NoteDocument(text: texto).frontmatter
        func valor(_ k: String) -> String? {
            fm.properties.first { $0.key == k }?.value.displayText.trimmingCharacters(in: .whitespaces).nilSiVacio
        }
        tipo = valor("tls_type")
        estado = valor("estado")
        responsable = valor("responsable")
        tipoTarea = valor("tipo")
        if TextFolding.pathKey(ruta.raw) == TextFolding.pathKey(RegistroDecisiones.ruta(layout).raw) {
            decisiones = RegistroDecisiones.leer(texto).lineas.count
        }
    }
}

extension String {
    var nilSiVacio: String? { isEmpty ? nil : self }
}

/// De lo que cambió en la carpeta a los eventos del tutorial. Puro: se prueba sin interfaz.
enum DetectorHitos {
    struct Cambio: Sendable {
        let ruta: VaultPath
        let antes: HuellaNota?
        let despues: HuellaNota?
    }

    /// ¿La ruta cuenta? Fuera lo oculto (`.tls/`) y el Archivo.
    static func cuenta(_ ruta: VaultPath, layout: VaultLayout) -> Bool {
        !ruta.isRoot && !ruta.components.contains { $0.hasPrefix(".") } && !layout.isArchived(ruta)
    }

    static func esExtracto(_ ruta: VaultPath) -> Bool {
        ruta.components.dropLast().contains { TextFolding.fold($0) == "extractos" }
    }

    static func esTarea(_ ruta: VaultPath, _ h: HuellaNota, layout: VaultLayout) -> Bool {
        h.tipo == "task" || TaskStore.esRutaDeTarea(ruta, layout: layout)
    }

    static func eventos(_ cambios: [Cambio], layout: VaultLayout) -> [TutorialEvent] {
        var out: [TutorialEvent] = []
        for c in cambios where cuenta(c.ruta, layout: layout) {
            guard let despues = c.despues else { continue }
            guard let antes = c.antes else {
                // Nuevo.
                if esExtracto(c.ruta) { out.append(.extractoImportado); continue }
                if esTarea(c.ruta, despues, layout: layout), despues.responsable != nil {
                    out.append(.tareaCreadaYAsignada(c.ruta))
                }
                continue
            }
            guard antes.contenido != despues.contenido else { continue }
            if let d = despues.decisiones {
                if d > (antes.decisiones ?? 0) { out.append(.decisionRegistrada) }
                continue
            }
            if despues.tipo == "opportunity", antes.estado != despues.estado {
                out.append(.oportunidadMovida(c.ruta))
                continue
            }
            if esTarea(c.ruta, despues, layout: layout) {
                let decision = ["decision", "decisión", "pregunta"].contains((despues.tipoTarea ?? "").lowercased())
                if decision, antes.estado != despues.estado {
                    out.append(.decisionResuelta(c.ruta))
                    continue
                }
                if antes.responsable == nil, despues.responsable != nil {
                    out.append(.tareaCreadaYAsignada(c.ruta))
                    continue
                }
            }
            if c.ruta.ext == "md" { out.append(.fichaEditada(c.ruta)) }
        }
        // Aprobar una decisión también deja su línea en el registro: cuenta como aprobar, no como apuntar otra.
        if out.contains(where: { if case .decisionResuelta = $0 { true } else { false } }) {
            out.removeAll { $0 == .decisionRegistrada }
        }
        return out
    }
}

/// Recuerda cómo estaba cada nota para ver qué cambió tras cada escritura. Lee solo (nunca escribe) y nunca mira
/// lo privado.
@MainActor
final class ObservadorCarpeta {
    private(set) var huellas: [VaultPath: HuellaNota] = [:]
    private(set) var preparado = false
    private var layout: VaultLayout?

    /// Foto de partida (una vez, al empezar un recorrido).
    func preparar(foto: VaultSnapshot) {
        preparar(huellas: Self.huellas(foto), layout: foto.layout)
    }

    /// Con las huellas ya calculadas (en segundo plano).
    func preparar(huellas: [VaultPath: HuellaNota], layout: VaultLayout) {
        self.layout = layout
        self.huellas = huellas
        preparado = true
    }

    nonisolated static func huellas(_ foto: VaultSnapshot) -> [VaultPath: HuellaNota] {
        var out: [VaultPath: HuellaNota] = [:]
        for p in foto.textPaths where DetectorHitos.cuenta(p, layout: foto.layout) && !foto.layout.isPrivate(p) {
            guard let t = foto.text(p) else { continue }
            out[p] = HuellaNota(ruta: p, texto: t, layout: foto.layout)
        }
        // Lo que no es texto (extractos que no se pudieron leer, PDF…): solo se sabe que existe.
        for p in foto.files where out[p] == nil && DetectorHitos.cuenta(p, layout: foto.layout) && !foto.layout.isPrivate(p) {
            out[p] = HuellaNota(contenido: 0)
        }
        return out
    }

    /// Lo que cambió en `rutas` (lee cada una con `leer`; `nil` = ya no está o no se puede leer).
    func cambios(_ rutas: Set<VaultPath>, leer: (VaultPath) -> String?, existe: (VaultPath) -> Bool) -> [TutorialEvent] {
        guard preparado, let layout else { return [] }
        var lista: [DetectorHitos.Cambio] = []
        for r in rutas.sorted() where DetectorHitos.cuenta(r, layout: layout) && !layout.isPrivate(r) {
            let antes = huellas[r]
            let despues: HuellaNota?
            if let t = leer(r) {
                despues = HuellaNota(ruta: r, texto: t, layout: layout)
            } else if existe(r) {
                despues = HuellaNota(contenido: 0)
            } else {
                despues = nil
            }
            huellas[r] = despues
            lista.append(.init(ruta: r, antes: antes, despues: despues))
        }
        return DetectorHitos.eventos(lista, layout: layout)
    }

    /// Todo pudo cambiar (la vigilancia no sabe qué): se compara con una foto nueva.
    func cambios(foto: VaultSnapshot) -> [TutorialEvent] {
        guard preparado else { preparar(foto: foto); return [] }
        let nuevas = Self.huellas(foto)
        let rutas = Set(huellas.keys).union(nuevas.keys)
        let lista = rutas.sorted().compactMap { r -> DetectorHitos.Cambio? in
            huellas[r] == nuevas[r] ? nil : .init(ruta: r, antes: huellas[r], despues: nuevas[r])
        }
        huellas = nuevas
        layout = foto.layout
        return DetectorHitos.eventos(lista, layout: foto.layout)
    }
}
