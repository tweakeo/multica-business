import Foundation

/// Un cambio en una relación, dicho desde la ficha que la **guarda** (DISEÑO §5.1, §5.3, §5.4). Desde el otro
/// lado, la interfaz traduce primero con `EsquemaRelaciones.quienGuarda`.
public struct CambioDeRelacion: Sendable, Hashable {
    public enum Accion: Sendable, Hashable {
        /// Una sola: pone el valor o lo cambia. En una lista, la deja con solo ese.
        case poner(VaultPath)
        /// Varias: añade a la lista (si ya estaba, no cambia nada).
        case anadir(VaultPath)
        /// Una sola: quita la clave. Varias: quita ese elemento de la lista (`nil` = toda la clave).
        case quitar(VaultPath?)
        /// Varias: el nuevo orden de la lista (§5.5, «el orden se cambia arrastrando»).
        case reordenar([VaultPath])
    }

    /// Ficha que guarda la relación (en la que se escribe).
    public let dueno: VaultPath
    /// Propiedad canónica (`empresa`, `personas`).
    public let propiedad: String
    public let accion: Accion

    public init(dueno: VaultPath, propiedad: String, accion: Accion) {
        self.dueno = dueno; self.propiedad = propiedad; self.accion = accion
    }
}

/// Las líneas de la propiedad antes y después, para la confirmación (§5.3) y para la vista «Ver cómo se guarda».
public struct LineasDelCambio: Sendable, Hashable {
    /// `nil` si la clave no estaba.
    public let antes: String?
    /// `nil` si la clave desaparece.
    public let despues: String?
}

/// Un cambio de relación listo para escribir: **una sola línea** de la ficha que la guarda (§11.4).
public struct RelacionPreparada: Sendable {
    public let cambio: CambioDeRelacion
    /// `cambiarPropiedades` de esa clave (y, si estaba escrita con un nombre heredado, ese nombre fuera).
    public let comando: CommandBus.Comando
    public let lineas: LineasDelCambio
    /// Cambia un valor que ya existía (relación de una): hay que confirmar enseñando la línea antes y después.
    public let pideConfirmacion: Bool
    /// El aviso que sale después, sin «Deshacer» («Enlacé la reunión del 14 oct a Arquitectura Nexo»).
    public let aviso: String
    /// No cambia nada (ya estaba así).
    public let sinCambios: Bool
}

/// Por qué no se puede hacer un cambio de relación, en palabras.
public enum ProblemaDeRelacion: Error, LocalizedError, Sendable, Equatable {
    /// Es obligatoria: no se quita, se cambia.
    case obligatoria(String)
    /// La otra ficha ya tiene una (una oportunidad tiene como mucho un proyecto).
    case unica(existente: VaultPath, mensaje: String)
    /// Esa propiedad no admite ese tipo de ficha.
    case tipoNoAdmitido(String)
    /// No se puede escribir en la ficha que la guarda (iCloud, no es texto…).
    case noEditable(String)
    /// Una factura emitida no se cambia: se rectifica.
    case facturaEmitida(String)
    /// La ficha no existe en la carpeta.
    case noEncontrada(String)

    public var errorDescription: String? {
        switch self {
        case .obligatoria(let m), .tipoNoAdmitido(let m), .noEditable(let m), .facturaEmitida(let m), .noEncontrada(let m): m
        case .unica(_, let m): m
        }
    }
}

/// Prepara los cambios de relaciones sin escribir nada: valida las reglas (§5.4, §5.5), calcula la línea antes
/// y después y devuelve el comando para `VaultSession.escribir`. Todo es puro y se prueba sin interfaz.
public struct EditorDeRelaciones: Sendable {
    public let snapshot: VaultSnapshot
    public let grafo: GrafoRelaciones

    public init(snapshot: VaultSnapshot, grafo: GrafoRelaciones) {
        self.snapshot = snapshot; self.grafo = grafo
    }

    public init(snapshot: VaultSnapshot) {
        self.init(snapshot: snapshot, grafo: GrafoRelaciones(snapshot: snapshot))
    }

    // MARK: Valor escrito

    /// `[[slug|Nombre]]` para una propiedad: el nombre del fichero si es único en la carpeta (contando
    /// `nuevas`, las que aún no existen); si no, la ruta sin `.md`.
    public func enlace(a destino: VaultPath, nombre: String? = nil, nuevas: [VaultPath] = []) -> String {
        let visible = NombresDeFicha.textoDeWikilink(nombre ?? grafo.ficha(destino)?.nombre ?? destino.stem)
        let key = TextFolding.nameKey(destino.stem)
        let repetidos = (snapshot.files + nuevas).filter {
            ($0.ext == "md" || $0.ext == "markdown") && TextFolding.nameKey($0.stem) == key && $0 != destino
        }.count
        let objetivo = repetidos == 0 ? destino.stem
            : ((destino.ext == "md" || destino.ext == "markdown") ? String(destino.raw.dropLast(destino.ext.count + 1)) : destino.raw)
        return visible == objetivo ? "[[\(objetivo)]]" : "[[\(objetivo)|\(visible)]]"
    }

    // MARK: Preparar

    /// Prepara un cambio de relación. Lanza `ProblemaDeRelacion` si no se puede hacer.
    public func preparar(_ c: CambioDeRelacion) throws -> RelacionPreparada {
        guard let dueno = grafo.ficha(c.dueno) else {
            throw ProblemaDeRelacion.noEncontrada("No encuentro «\(c.dueno.stem)» en la carpeta de tu empresa.")
        }
        if snapshot.dataless.contains(c.dueno) {
            throw ProblemaDeRelacion.noEditable("«\(dueno.nombre)» aún se está descargando de iCloud. El cambio espera a que llegue.")
        }
        guard let text = snapshot.text(c.dueno) else {
            throw ProblemaDeRelacion.noEditable("No puedo cambiar «\(dueno.nombre)»: no es un texto que la app sepa escribir.")
        }
        let def = EsquemaRelaciones.definicion(tipo: dueno.tipo, propiedad: c.propiedad)
        if dueno.tipo == .invoice, let e = dueno.estado, TextFolding.fold(e) != "borrador" {
            throw ProblemaDeRelacion.facturaEmitida("Una factura \(e.lowercased()) no se cambia: se rectifica.")
        }
        var doc = FrontmatterDocument(text: text)
        // La clave escrita: la canónica o, si se escribió con un nombre heredado, ese.
        let claves = def?.claves ?? [c.propiedad]
        let escrita = claves.first { doc.keys.contains($0) }
        let antes = escrita.flatMap { doc.rawLines($0) }.map(Self.sinSalto)
        let actuales = grafo.destinos(de: c.dueno, propiedad: def?.propiedad ?? c.propiedad)
        let varias = def?.cardinalidad == .varias
        let etiqueta = (def?.etiqueta ?? c.propiedad).lowercased()

        // Tipo admitido.
        func comprobarTipo(_ destino: VaultPath) throws {
            guard let def, let f = grafo.ficha(destino) else { return }
            if !def.apuntaA.contains(f.tipo) {
                let admite = def.apuntaA.map(\.etiquetaRelacion).sorted().joined(separator: " o ")
                throw ProblemaDeRelacion.tipoNoAdmitido(
                    "«\(def.etiqueta)» de \(dueno.tipo.articuloEtiqueta) se enlaza a \(admite), no a \(f.tipo.etiquetaRelacion).")
            }
        }
        // Única en el destino (una oportunidad, como mucho un proyecto).
        func comprobarUnica(_ destino: VaultPath) throws {
            guard let def, def.unicaEnDestino else { return }
            let otros = grafo.origenes(de: destino, propiedad: def.propiedad, tipo: dueno.tipo).filter { $0 != c.dueno }
            if let otro = otros.first {
                let nombreDestino = grafo.ficha(destino)?.nombre ?? destino.stem
                let nombreOtro = grafo.ficha(otro)?.nombre ?? otro.stem
                throw ProblemaDeRelacion.unica(existente: otro,
                    mensaje: "«\(nombreDestino)» ya tiene \(dueno.tipo.etiquetaRelacion): «\(nombreOtro)». Como mucho, uno.")
            }
        }

        var poner: [Property] = []
        var quitar: [String] = []
        let clave = def?.propiedad ?? c.propiedad
        var aviso = ""
        var pideConfirmacion = false
        let nombreDueno = dueno.nombre

        switch c.accion {
        case .poner(let destino):
            try comprobarTipo(destino)
            try comprobarUnica(destino)
            let nombreDestino = grafo.ficha(destino)?.nombre ?? destino.stem
            if actuales == [destino] {
                return RelacionPreparada(cambio: c, comando: .cambiarPropiedades(c.dueno, poner: [], quitar: []),
                                         lineas: LineasDelCambio(antes: antes, despues: antes), pideConfirmacion: false,
                                         aviso: "", sinCambios: true)
            }
            let valor = enlace(a: destino)
            poner = [Property(key: clave, value: varias ? .list([valor]) : .text(valor))]
            pideConfirmacion = !actuales.isEmpty
            aviso = actuales.isEmpty ? "Enlacé \(nombreDueno) a \(nombreDestino)"
                : "\(nombreDueno): \(etiqueta) pasa a \(nombreDestino)"
        case .anadir(let destino):
            try comprobarTipo(destino)
            try comprobarUnica(destino)
            if actuales.contains(destino) {
                return RelacionPreparada(cambio: c, comando: .cambiarPropiedades(c.dueno, poner: [], quitar: []),
                                         lineas: LineasDelCambio(antes: antes, despues: antes), pideConfirmacion: false,
                                         aviso: "", sinCambios: true)
            }
            let nombreDestino = grafo.ficha(destino)?.nombre ?? destino.stem
            if varias {
                var lista = itemsEscritos(doc, clave: escrita)
                lista.append(enlace(a: destino))
                poner = [Property(key: clave, value: .list(lista))]
                aviso = "Añadí \(nombreDestino) a \(nombreDueno)"
            } else {
                // Una relación de una: «añadir» es poner (y, si había otra, se confirma).
                poner = [Property(key: clave, value: .text(enlace(a: destino)))]
                pideConfirmacion = !actuales.isEmpty
                aviso = actuales.isEmpty ? "Enlacé \(nombreDueno) a \(nombreDestino)"
                    : "\(nombreDueno): \(etiqueta) pasa a \(nombreDestino)"
            }
        case .quitar(let destino):
            if let motivo = def?.motivoObligatoria(dueno.propiedades), !(varias && actuales.count > 1) {
                throw ProblemaDeRelacion.obligatoria(motivo)
            }
            guard escrita != nil else {
                return RelacionPreparada(cambio: c, comando: .cambiarPropiedades(c.dueno, poner: [], quitar: []),
                                         lineas: LineasDelCambio(antes: nil, despues: nil), pideConfirmacion: false,
                                         aviso: "", sinCambios: true)
            }
            let nombreQuitado = destino.flatMap { grafo.ficha($0)?.nombre } ?? actuales.first.flatMap { grafo.ficha($0)?.nombre } ?? etiqueta
            if varias, let destino {
                let enlaces = (grafo.salientes[c.dueno] ?? []).filter { $0.propiedad == clave }
                let posiciones = Set(enlaces.filter { $0.destino == destino }.compactMap(\.posicion))
                guard !posiciones.isEmpty else {
                    return RelacionPreparada(cambio: c, comando: .cambiarPropiedades(c.dueno, poner: [], quitar: []),
                                             lineas: LineasDelCambio(antes: antes, despues: antes), pideConfirmacion: false,
                                             aviso: "", sinCambios: true)
                }
                let lista = itemsEscritos(doc, clave: escrita).enumerated().filter { !posiciones.contains($0.offset) }.map(\.element)
                if lista.isEmpty { quitar = [escrita!] } else { poner = [Property(key: escrita!, value: .list(lista))] }
            } else {
                quitar = [escrita!]
            }
            aviso = "Quité \(nombreQuitado) de \(nombreDueno)"
        case .reordenar(let orden):
            guard varias, let escrita else {
                return RelacionPreparada(cambio: c, comando: .cambiarPropiedades(c.dueno, poner: [], quitar: []),
                                         lineas: LineasDelCambio(antes: antes, despues: antes), pideConfirmacion: false,
                                         aviso: "", sinCambios: true)
            }
            let enlaces = (grafo.salientes[c.dueno] ?? []).filter { $0.propiedad == clave }
            let items = itemsEscritos(doc, clave: escrita)
            var nuevo: [String] = []
            var usados = Set<Int>()
            for d in orden {
                for e in enlaces where e.destino == d { if let p = e.posicion, p < items.count, usados.insert(p).inserted { nuevo.append(items[p]) } }
            }
            for (i, it) in items.enumerated() where !usados.contains(i) { nuevo.append(it) }
            if nuevo == items {
                return RelacionPreparada(cambio: c, comando: .cambiarPropiedades(c.dueno, poner: [], quitar: []),
                                         lineas: LineasDelCambio(antes: antes, despues: antes), pideConfirmacion: false,
                                         aviso: "", sinCambios: true)
            }
            poner = [Property(key: escrita, value: .list(nuevo))]
            aviso = "Cambié el orden de \(etiqueta) en \(nombreDueno)"
        }
        // Escrita con un nombre heredado (`empresa_id`): se escribe la canónica y la heredada sale.
        if let escrita, escrita != clave, !poner.isEmpty, poner.contains(where: { $0.key == clave }) {
            quitar.append(escrita)
        }
        doc.merge(set: poner, unset: quitar)
        let despues = doc.rawLines(clave).map(Self.sinSalto)
        return RelacionPreparada(cambio: c, comando: .cambiarPropiedades(c.dueno, poner: poner, quitar: quitar),
                                 lineas: LineasDelCambio(antes: antes, despues: despues),
                                 pideConfirmacion: pideConfirmacion, aviso: aviso, sinCambios: false)
    }

    /// Elementos de una lista tal como están escritos (texto de cada uno).
    func itemsEscritos(_ doc: FrontmatterDocument, clave: String?) -> [String] {
        guard let clave, let v = doc.value(clave) else { return [] }
        switch v {
        case .list(let l): return l
        case .text(let t): return t.isEmpty ? [] : [t]
        default: return []
        }
    }

    static func sinSalto(_ s: String) -> String {
        var t = s
        while t.hasSuffix("\n") || t.hasSuffix("\r") { t.removeLast() }
        return t
    }

    // MARK: En cadena (§5.4)

    /// Lo que cuelga de `dueno` (por su `oportunidad` o su `proyecto`) y tiene la misma `propiedad` apuntando a
    /// `viejo`: al cambiar la empresa de una oportunidad, sus propuestas y facturas en borrador. Las facturas
    /// emitidas van aparte: nunca se cambian.
    public func colgantes(de dueno: VaultPath, propiedad: String, viejo: VaultPath?) -> (cambiables: [VaultPath], fijas: [VaultPath]) {
        guard let viejo else { return ([], []) }
        var cambiables: [VaultPath] = []
        var fijas: [VaultPath] = []
        for e in grafo.entrantes[dueno] ?? [] where ["oportunidad", "proyecto"].contains(e.propiedad) {
            guard let f = grafo.ficha(e.origen), !f.privada,
                  grafo.destinos(de: f.ruta, propiedad: propiedad).contains(viejo) else { continue }
            if cambiables.contains(f.ruta) || fijas.contains(f.ruta) { continue }
            if f.tipo == .invoice, let estado = f.estado, TextFolding.fold(estado) != "borrador" {
                fijas.append(f.ruta)
            } else {
                cambiables.append(f.ruta)
            }
        }
        return (cambiables.sorted(), fijas.sorted())
    }

    /// El cambio principal y el mismo en lo que cuelga, en un solo plan (todo o nada, un solo Deshacer).
    public func enCadena(_ principal: RelacionPreparada, colgantes: [VaultPath], autor: Autor) throws -> WritePlan {
        var ops: [WriteOp] = [principal.comando.op]
        for r in colgantes {
            let cambio = CambioDeRelacion(dueno: r, propiedad: principal.cambio.propiedad, accion: principal.cambio.accion)
            let p = try preparar(cambio)
            if !p.sinCambios { ops.append(p.comando.op) }
        }
        let extra = ops.count - 1
        let descripcion = principal.aviso + (extra > 0 ? " y en \(extra == 1 ? "1 ficha" : "\(extra) fichas") que cuelgan de ella" : "")
        return WritePlan(autor: autor, descripcion: descripcion, ops: ops)
    }

    // MARK: Crear al vuelo (§5.2)

    /// Crea una ficha con su plantilla y la enlaza, como **un solo** paso de deshacer: el plan de la plantilla y,
    /// detrás, la línea de la relación en la ficha que la guarda.
    public func crearYEnlazar(_ nota: PlantillaMotor.NotaPreparada, nombre: String, dueno: VaultPath, propiedad: String,
                              autor: Autor) throws -> WritePlan {
        guard let duenoFicha = grafo.ficha(dueno), let text = snapshot.text(dueno) else {
            throw ProblemaDeRelacion.noEncontrada("No encuentro «\(dueno.stem)» en la carpeta de tu empresa.")
        }
        let def = EsquemaRelaciones.definicion(tipo: duenoFicha.tipo, propiedad: propiedad)
        let clave = def?.propiedad ?? propiedad
        let valor = enlace(a: nota.ruta, nombre: nombre, nuevas: [nota.ruta])
        let doc = FrontmatterDocument(text: text)
        let escrita = (def?.claves ?? [clave]).first { doc.keys.contains($0) }
        let poner: Property
        if def?.cardinalidad == .varias {
            poner = Property(key: clave, value: .list(itemsEscritos(doc, clave: escrita) + [valor]))
        } else {
            poner = Property(key: clave, value: .text(valor))
        }
        var quitar: [String] = []
        if let escrita, escrita != clave { quitar.append(escrita) }
        let ops = nota.plan.ops + [.mergeFrontmatter(dueno, set: [poner], unset: quitar)]
        return WritePlan(autor: autor, descripcion: "Crear «\(nombre)» y enlazarla a \(duenoFicha.nombre)", ops: ops)
    }
}

extension NoteKind {
    /// Nombre del tipo en minúscula para frases («una empresa», «un proyecto»).
    public var etiquetaRelacion: String {
        switch self {
        case .organization: "empresas"
        case .contact: "personas"
        case .opportunity: "oportunidades"
        case .project: "proyectos"
        case .meeting: "reuniones"
        case .invoice: "facturas"
        case .task: "tareas"
        case .service: "servicios"
        case .offer: "versiones de la oferta"
        case .proposal, .quote, .agreement: "documentos"
        case .deliveryTemplate: "planes de entrega"
        case .system: "sistemas"
        case .role: "roles"
        case .conversation: "conversaciones"
        case .content: "contenidos"
        case .incident: "incidencias"
        case .receipt: "recibos"
        default: "fichas"
        }
    }

    /// «la oportunidad», «el proyecto»… para frases.
    var articuloEtiqueta: String {
        switch self {
        case .organization: "una empresa"
        case .contact: "un contacto"
        case .opportunity: "una oportunidad"
        case .project: "un proyecto"
        case .meeting: "una reunión"
        case .invoice: "una factura"
        case .task: "una tarea"
        case .proposal: "una propuesta"
        case .quote: "un presupuesto"
        case .agreement: "un contrato"
        case .system: "un sistema"
        default: "esta ficha"
        }
    }
}
