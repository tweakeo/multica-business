import Foundation

// Eventos de dominio (PLAN §4.7, SISTEMAS §3.3): se deducen de los cambios ya escritos en la carpeta, comparando
// cada fichero antes y después del plan. Cada evento lleva una clave única (`<tipo>:<entidad>`) para que se procese
// una sola vez (outbox en `estado.sqlite`, ver `EstadoDominio`).
//
// Procedencia: catálogo de eventos de PROG `core/reglas.js` (Manu) y PLAN §4.7 / SISTEMAS §3.3. Reescrito en Swift;
// el original los emitía desde cada tabla de Postgres, aquí salen de comparar las fichas. Ver docs/PROCEDENCIA.md.

/// Tipos de evento que la app deduce de la carpeta.
public enum TipoEvento: String, Sendable, Hashable, Codable, CaseIterable {
    case contactoCreado = "contacto.creado"
    case empresaCreada = "empresa.creada"
    case conversacionCualificada = "conversacion.cualificada"
    case oportunidadAceptada = "oportunidad.aceptada"
    case oportunidadGanada = "oportunidad.ganada"
    case oportunidadPerdida = "oportunidad.perdida"
    case cobroConfirmado = "cobro.confirmado"
    case facturaEmitida = "factura.emitida"
    case proyectoCreado = "proyecto.creado"
    case proyectoCerrado = "proyecto.cerrado"
    case extractoImportado = "extracto.importado"
    case decisionRegistrada = "decision.registrada"

    /// Para la persona: «Contacto nuevo», «Cobro confirmado»…
    public var etiqueta: String {
        switch self {
        case .contactoCreado: "Contacto nuevo"
        case .empresaCreada: "Empresa nueva"
        case .conversacionCualificada: "Conversación cualificada"
        case .oportunidadAceptada: "Oportunidad aceptada"
        case .oportunidadGanada: "Oportunidad ganada"
        case .oportunidadPerdida: "Oportunidad perdida"
        case .cobroConfirmado: "Cobro confirmado"
        case .facturaEmitida: "Factura emitida"
        case .proyectoCreado: "Proyecto nuevo"
        case .proyectoCerrado: "Proyecto cerrado"
        case .extractoImportado: "Extracto importado"
        case .decisionRegistrada: "Decisión registrada"
        }
    }
}

/// Un hecho del dominio que ya está escrito en la carpeta.
public struct EventoDominio: Sendable, Hashable, Codable, Identifiable {
    public var id: String { clave }
    public let tipo: TipoEvento
    /// Clave única (`cobro.confirmado:PAG-20261017-001`): un evento con la misma clave no se procesa dos veces.
    public let clave: String
    /// Ficha (o fichero) del que trata.
    public let ruta: VaultPath
    /// `id` de la entidad (o su ruta si no tiene).
    public let entidad: String
    /// Datos del evento (`oportunidad`, `importe`, `documento`…), solo texto.
    public let carga: [String: String]
    /// Quién escribió el cambio del que sale.
    public let autor: Autor
    /// Pasos de regla que llevaron hasta aquí (0: lo escribió una persona o un asistente).
    public let profundidad: Int
    /// Plan que lo escribió.
    public let plan: UUID?

    public init(tipo: TipoEvento, entidad: String, ruta: VaultPath, carga: [String: String] = [:], autor: Autor,
                profundidad: Int = 0, plan: UUID? = nil) {
        self.tipo = tipo; self.entidad = entidad; self.ruta = ruta; self.carga = carga; self.autor = autor
        self.profundidad = profundidad; self.plan = plan
        self.clave = "\(tipo.rawValue):\(entidad)"
    }
}

/// Un fichero antes y después de un plan ya aplicado (`nil`: no existía / ya no está).
public struct CambioAplicado: Sendable, Hashable {
    public let ruta: VaultPath
    public let antes: String?
    public let despues: String?

    public init(ruta: VaultPath, antes: String?, despues: String?) {
        self.ruta = ruta; self.antes = antes; self.despues = despues
    }
}

/// Deduce los eventos de dominio de los cambios aplicados. Es puro: no lee ni escribe nada.
public struct EventDeriver: Sendable {
    public let layout: VaultLayout

    public init(layout: VaultLayout) { self.layout = layout }

    /// Eventos de unos cambios ya escritos por `autor` (en orden, sin repetir clave).
    ///
    /// - Una ficha que aparece: `contacto.creado`, `empresa.creada`, `proyecto.creado` (salvo que lleve `fecha_corte`:
    ///   lo importado no dispara nada).
    /// - Un `estado` que cambia: `conversacion.cualificada`, `oportunidad.aceptada|ganada|perdida`, `factura.emitida`,
    ///   `proyecto.cerrado`.
    /// - Una fila de `pagos.csv` que pasa a cobro confirmado, **solo si la escribe una persona**: `cobro.confirmado`.
    /// - Un fichero nuevo en `…/Bancos/<cuenta>/Extractos/`: `extracto.importado`.
    /// - Una línea nueva en `Decisiones.md`: `decision.registrada`.
    public func derivar(_ cambios: [CambioAplicado], autor: Autor, plan: UUID? = nil, profundidad: Int = 0) -> [EventoDominio] {
        var out: [EventoDominio] = []
        var vistas = Set<String>()
        func emitir(_ tipo: TipoEvento, _ entidad: String, _ ruta: VaultPath, _ carga: [String: String] = [:]) {
            let e = EventoDominio(tipo: tipo, entidad: entidad, ruta: ruta, carga: carga, autor: autor, profundidad: profundidad, plan: plan)
            if vistas.insert(e.clave).inserted { out.append(e) }
        }
        for c in cambios {
            // Lo retirado, las plantillas y lo privado no disparan nada (una regla no puede sacar lo privado a la luz).
            if layout.isArchived(c.ruta) || VaultSnapshot.isTemplatePath(c.ruta) || layout.isPrivate(c.ruta) { continue }
            let nombre = TextFolding.nameKey(c.ruta.name)
            if c.ruta.ext == "csv" {
                if nombre == "pagos.csv", autor.esPersona {
                    for fila in cobrosNuevos(c) {
                        var carga: [String: String] = ["pago": fila.id, "fichero": c.ruta.raw]
                        if let d = fila.documento { carga["documento"] = d }
                        if let p = fila.proyecto { carga["proyecto"] = p }
                        if let i = fila.centimos { carga["importe"] = Euros.escrito(i) }
                        if let f = fila.fecha { carga["fecha"] = f.description }
                        emitir(.cobroConfirmado, fila.id, c.ruta, carga)
                    }
                }
                if esExtracto(c.ruta), c.antes == nil, c.despues != nil {
                    emitir(.extractoImportado, "ruta:" + TextFolding.pathKey(c.ruta.raw), c.ruta, ["cuenta": c.ruta.parent?.parent?.name ?? ""])
                }
                continue
            }
            if esExtracto(c.ruta), c.antes == nil, c.despues != nil {
                emitir(.extractoImportado, "ruta:" + TextFolding.pathKey(c.ruta.raw), c.ruta, ["cuenta": c.ruta.parent?.parent?.name ?? ""])
                continue
            }
            guard c.ruta.ext == "md", let despues = c.despues else { continue }
            let docDespues = NoteDocument(text: despues)
            let fm = docDespues.frontmatter
            let antes = c.antes.map { NoteDocument(text: $0).frontmatter }
            let tipo = NoteKindResolver.kind(of: c.ruta, frontmatter: fm, layout: layout)
            let entidad = fm.text("id")?.lowercased() ?? "ruta:" + TextFolding.pathKey(c.ruta.raw)
            let nuevo = c.antes == nil
            let importado = fm.text("fecha_corte") != nil
            func cambio(_ normalizar: (String?) -> String?) -> (de: String?, a: String?) {
                (antes.flatMap { normalizar($0.text("estado")) }, normalizar(fm.text("estado")))
            }
            switch tipo {
            case .contact where nuevo && !importado:
                emitir(.contactoCreado, entidad, c.ruta, ["nombre": nombreDe(fm, docDespues, c.ruta)])
            case .organization where nuevo && !importado:
                emitir(.empresaCreada, entidad, c.ruta, ["nombre": nombreDe(fm, docDespues, c.ruta)])
            case .conversation:
                let (de, a) = cambio { $0.map(TextFolding.fold) }
                if a == "cualificada", de != "cualificada", !importado || !nuevo { emitir(.conversacionCualificada, entidad, c.ruta) }
            case .opportunity:
                let (de, a) = cambio(LecturaDominio.estadoOportunidad)
                guard let a, a != de, !(nuevo && importado) else { break }
                let carga = ["de": de ?? "", "a": a]
                switch a {
                case "Aceptada": emitir(.oportunidadAceptada, entidad, c.ruta, carga)
                case "Ganada": emitir(.oportunidadGanada, entidad, c.ruta, carga)
                case "Perdida": emitir(.oportunidadPerdida, entidad, c.ruta, carga)
                default: break
                }
            case .invoice:
                let (de, a) = cambio { $0.map(TextFolding.fold) }
                if a == "emitida", de != "emitida", !(nuevo && importado) {
                    emitir(.facturaEmitida, entidad, c.ruta, ["numero": fm.text("numero") ?? ""])
                }
            case .project:
                if nuevo && !importado { emitir(.proyectoCreado, entidad, c.ruta) }
                let (de, a) = cambio(LecturaDominio.estadoProyecto)
                if a == "Cerrado", de != "Cerrado", !(nuevo && importado) { emitir(.proyectoCerrado, entidad, c.ruta) }
            default:
                break
            }
            if esRegistroDeDecisiones(c.ruta, fm) {
                let previas = Set((c.antes.map { RegistroDecisiones.leer($0).lineas } ?? []).compactMap(\.id))
                // Solo las decisiones que se registran ahora: no las líneas viejas que reciben su marcador («texto»).
                for d in RegistroDecisiones.leer(despues).lineas
                where d.id.map({ !previas.contains($0) }) ?? false && !d.sustituida && !["texto", "importacion"].contains(d.marcador["origen"] ?? "") {
                    var carga = ["texto": d.decision]
                    if let a = d.area { carga["area"] = a }
                    emitir(.decisionRegistrada, d.id ?? "", c.ruta, carga)
                }
            }
        }
        return out
    }

    /// Filas de `pagos.csv` que antes no eran un cobro confirmado y ahora sí.
    func cobrosNuevos(_ c: CambioAplicado) -> [FilaPago] {
        guard let despues = c.despues else { return [] }
        let previas = Dictionary(FilaPago.leer(c.antes ?? "", fichero: c.ruta).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return FilaPago.leer(despues, fichero: c.ruta).filter { f in
            f.esCobroConfirmado && previas[f.id]?.esCobroConfirmado != true
        }
    }

    /// `…/Bancos/<cuenta>/Extractos/<fichero>`.
    func esExtracto(_ p: VaultPath) -> Bool {
        let c = p.components.map(TextFolding.fold)
        guard c.count >= 4 else { return false }
        return c[c.count - 2] == "extractos" && c[c.count - 4] == "bancos"
    }

    func esRegistroDeDecisiones(_ p: VaultPath, _ fm: Frontmatter) -> Bool {
        if TextFolding.fold(fm.text("registro") ?? "") == "decisiones" { return true }
        return TextFolding.nameKey(p.name) == "decisiones.md" && layout.area(of: p) == .direccion
    }

    func nombreDe(_ fm: Frontmatter, _ doc: NoteDocument, _ ruta: VaultPath) -> String {
        GrafoRelaciones.nombre(fm, doc: doc, ruta: ruta)
    }
}
