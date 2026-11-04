import Foundation

// Traduce un plan de escritura de un asistente en lo que pide (una solicitud por operación), mirando la ruta, el tipo
// de ficha y lo que cambia, sin fiarse de lo que diga el plan de sí mismo. Es el control estructural de
// `CommandBus`: aunque quien llama no diga qué hace, un `vence`, un «Hecha», un `.tls/` o una fila confirmada
// se reconocen aquí.

enum ClasificadorDePlan {
    struct Contexto {
        let root: URL
        let layout: VaultLayout

        /// Texto del fichero tal como está (sin descargar nada). `nil` si no existe o no se lee.
        func texto(_ p: VaultPath) -> String? {
            guard !p.components.contains("..") else { return nil }
            return UbiquityInspector.withoutMaterializing {
                let url = p.url(in: root)
                guard let info = UbiquityInspector.info(url), !info.isDirectory, !info.dataless, !info.isSymlink,
                      info.size < 4 * 1024 * 1024 else { return nil }
                guard let d = try? Data(contentsOf: url, options: [.uncached]) else { return nil }
                return String(data: d, encoding: .utf8)
            }
        }

        func frontmatter(_ p: VaultPath) -> Frontmatter? {
            texto(p).map { NoteDocument(text: $0).frontmatter }
        }

        func esTarea(_ p: VaultPath) -> Bool { TaskStore.esRutaDeTarea(p, layout: layout) }

        func enCarpeta(_ p: VaultPath, tipo: String) -> Bool {
            guard let d = layout.dir(for: tipo), let parent = p.parent else { return false }
            return TextFolding.pathKey(parent.raw) == TextFolding.pathKey(d.raw)
        }

        func esOportunidad(_ p: VaultPath) -> Bool {
            if enCarpeta(p, tipo: "opportunity") { return true }
            return frontmatter(p).map { NoteKindResolver.kind(of: p, frontmatter: $0, layout: layout) == .opportunity } ?? false
        }

        func esBorrador(_ p: VaultPath) -> Bool { Borradores.esRutaDeBorrador(p, layout: layout) }

        func esBitacora(_ p: VaultPath) -> Bool { Bitacora.esRutaDeBitacora(p, layout: layout) }

        func esBuzon(_ p: VaultPath) -> Bool {
            guard let b = layout.buzon else { return false }
            return PlanCompiler.isUnder(p, VaultPath(b))
        }

        func esDecisiones(_ p: VaultPath) -> Bool {
            TextFolding.pathKey(p.raw) == TextFolding.pathKey(RegistroDecisiones.ruta(layout).raw)
        }

        func esPlantillaDeEntrega(_ p: VaultPath) -> Bool { enCarpeta(p, tipo: "delivery_template") }

        func esContacto(_ p: VaultPath) -> Bool {
            enCarpeta(p, tipo: "contact") || enCarpeta(p, tipo: "organization")
        }

        func esContenido(_ p: VaultPath) -> Bool { enCarpeta(p, tipo: "content") }

        /// Ficha de factura (`tls_type: invoice`) que ya existe.
        func esFactura(_ p: VaultPath) -> Bool {
            TextFolding.fold(frontmatter(p)?.text("tls_type") ?? "") == "invoice"
        }
    }

    /// F4 · corrector (R9): lo que en una factura solo cambia una aprobación (emitirla, numerarla) o una persona
    /// (cobrarla). `nil` si el cambio no toca nada de eso.
    static func cambioDeFactura(_ p: VaultPath, claves: Set<String>, estado: String?) -> Clase? {
        let e = TextFolding.fold(estado ?? "")
        if claves.contains("aprobacion") { return (.aprobacionDecidir, [p], nil, nil, nil) }
        if ["cobrada", "pagada", "cobrado", "pagado"].contains(e) { return (.cobroConfirmar, [p], nil, nil, nil) }
        if claves.contains("numero") || (claves.contains("estado") && !e.isEmpty && e != "borrador") {
            return (.externa, [p], "FIN-02", .emitirFactura, nil)
        }
        return nil
    }

    /// Ruta vetada a los asistentes por sí misma (paso 5): `.tls/`, `Roles/`, `AGENTS.md`, `Empresa.md`, `Metas.md`.
    static func vetoDeRuta(_ p: VaultPath, layout: VaultLayout) -> TipoDeAccion? {
        let c = p.components
        guard let primero = c.first else { return nil }
        if TextFolding.nameKey(primero) == ".tls" {
            return TextFolding.pathKey(p.raw) == TextFolding.pathKey(VaultLayout.configFile) ? .config : .ajustesEscribir
        }
        if c.count == 1 {
            switch TextFolding.nameKey(primero) {
            case "agents.md": return .agentsEscribir
            case "empresa.md": return .empresaEscribir
            default: break
            }
        }
        let roles = layout.dir(for: "role") ?? layout.areaFolder(.equipo).appending("Roles")
        if PlanCompiler.isUnder(p, roles) { return .rolesEscribir }
        if TextFolding.pathKey(p.raw) == TextFolding.pathKey(MetasDocumento.ruta(layout: layout).raw) { return .metasFijar }
        return nil
    }

    static func solicitudes(_ plan: WritePlan, contexto x: Contexto, ejecucion: ContextoEjecucion?) -> [SolicitudAutorizacion] {
        plan.ops.flatMap { op -> [SolicitudAutorizacion] in
            clasificar(op, contexto: x).map { tipo, rutas, capacidad, externa, tamano in
                SolicitudAutorizacion(autor: plan.autor, tipo: tipo, rutas: rutas, capacidad: capacidad, externa: externa,
                                      ejecucion: ejecucion, tamano: tamano, plan: plan.id)
            }
        }
    }

    typealias Clase = (TipoDeAccion, [VaultPath], String?, AccionExterna?, Int?)

    static func clasificar(_ op: WriteOp, contexto x: Contexto) -> [Clase] {
        let p = op.path
        if let v = vetoDeRuta(p, layout: x.layout) { return [(v, [p], nil, nil, nil)] }
        switch op {
        case .create(_, let contents):
            return [crear(p, texto: String(data: contents, encoding: .utf8) ?? "", tamano: contents.count, x)]
        case .mergeFrontmatter(_, let set, let unset):
            return [propiedades(p, poner: set, quitar: unset, x)]
        case .appendToSection(_, let seccion, let texto, _):
            return [anadido(p, seccion: seccion, tamano: texto.utf8.count, x)]
        case .appendLine(_, let linea):
            return [anadido(p, seccion: nil, tamano: linea.utf8.count, x)]
        case .replaceSection(_, _, let texto, _):
            if x.esTarea(p) || x.esBorrador(p) { return [(x.esTarea(p) ? .tareaMover : .borradorPreparar, [p], nil, nil, texto.utf8.count)] }
            return [(.fichaEditar, [p], nil, nil, texto.utf8.count)]
        case .replaceBody(_, let cuerpo, _):
            if x.esBorrador(p) { return [(.borradorPreparar, [p], nil, nil, cuerpo.utf8.count)] }
            return [(.fichaEditar, [p], nil, nil, cuerpo.utf8.count)]
        case .saveText(_, _, let texto):
            return [(.fichaEditar, [p], nil, nil, texto.utf8.count)]
        case .editRanges(_, let edits, _):
            // El encabezado que la app pone encima de un comentario escrito a mano en la Actividad (solo inserta).
            if x.esTarea(p), edits.allSatisfy({ $0.length == 0 && esEncabezadoDeActividad($0.replacement) }) {
                return [(.comentar, [p], nil, nil, edits.reduce(0) { $0 + $1.replacement.utf8.count })]
            }
            return [(.fichaEditar, [p], nil, nil, edits.reduce(0) { $0 + $1.replacement.utf8.count })]
        case .upsertCSVRow(_, let fila, _):
            return [csv(p, filas: [fila], x)]
        case .insertCSVRows(_, let filas, _):
            return [csv(p, filas: filas, x)]
        case .setTableCells, .appendTableRow:
            return [(.fichaEditar, [p], nil, nil, nil)]
        case .move(let a, let b):
            if let v = vetoDeRuta(b, layout: x.layout) { return [(v, [b], nil, nil, nil)] }
            return [(x.esBuzon(a) ? .buzonMover : .fichaEditar, [a, b], nil, nil, nil)]
        case .retire:
            return [(.fichaEditar, [p], nil, nil, nil)]
        }
    }

    /// `### AAAA-MM-DD HH:MM · <autor>` y su salto de línea, nada más.
    static func esEncabezadoDeActividad(_ s: String) -> Bool {
        s.range(of: #"^### \d{4}-\d{2}-\d{2} \d{2}:\d{2} · [^\r\n]+(\r\n|\n|\r)?$"#, options: .regularExpression) != nil
    }

    static func crear(_ p: VaultPath, texto: String, tamano: Int, _ x: Contexto) -> Clase {
        let fm = NoteDocument(text: texto).frontmatter
        let estado = fm.text("estado").map { TextFolding.fold($0) } ?? ""
        if x.esTarea(p) || (p.parent.map { TextFolding.nameKey($0.name) == TextFolding.nameKey(x.layout.tareas) } ?? false) {
            if let e = EstadoTarea(leyendo: estado), e.cerrada { return (.tareaCerrar, [p], nil, nil, tamano) }
            return (.tareaCrear, [p], fm.text("capacidad"), nil, tamano)
        }
        if x.esBorrador(p) {
            if !estado.isEmpty, !["borrador", "pendiente de tu ok"].contains(estado) { return (.aprobacionDecidir, [p], nil, nil, tamano) }
            return (.borradorPreparar, [p], nil, nil, tamano)
        }
        if TextFolding.fold(fm.text("tls_type") ?? "") == "invoice",
           let c = cambioDeFactura(p, claves: Set(fm.properties.filter { !$0.value.displayText.trimmingCharacters(in: .whitespaces).isEmpty }
                                                       .map(\.key)).intersection(["numero", "aprobacion"]),
                                   estado: fm.text("estado")) {
            return (c.0, c.1, c.2, c.3, tamano)
        }
        if x.esBitacora(p) { return (.bitacoraRegistrar, [p], nil, nil, tamano) }
        if x.esBuzon(p) { return (.buzonRegistrar, [p], nil, nil, tamano) }
        if x.esDecisiones(p) { return (.decisionRegistrar, [p], nil, nil, tamano) }
        if x.esContacto(p) { return (.contactoRegistrar, [p], nil, nil, tamano) }
        if x.enCarpeta(p, tipo: "opportunity") {
            if estado == "ganada" || estado == "ganado" { return (.oportunidadGanar, [p], nil, nil, tamano) }
            if !estado.isEmpty, estado != "prospecto" { return (.oportunidadEtapa, [p], nil, nil, tamano) }
            return (.oportunidadRegistrar, [p], nil, nil, tamano)
        }
        if x.esPlantillaDeEntrega(p) { return (.plantillaAjustar, [p], nil, nil, tamano) }
        return (.fichaEditar, [p], nil, nil, tamano)
    }

    static func propiedades(_ p: VaultPath, poner: [Property], quitar: [String], _ x: Contexto) -> Clase {
        let claves = Set(poner.map(\.key) + quitar)
        func valor(_ k: String) -> String? { poner.first { $0.key == k }?.value.displayText }
        // `vence` es el límite real: ningún asistente lo pone, lo cambia ni lo quita en una ficha que ya existe.
        if claves.contains("vence") { return (.venceMover, [p], nil, nil, nil) }
        if x.esTarea(p) {
            if let e = valor("estado").flatMap(EstadoTarea.init(leyendo:)), e.cerrada { return (.tareaCerrar, [p], nil, nil, nil) }
            if claves.contains("cerrada") { return (.tareaCerrar, [p], nil, nil, nil) }
            if claves.isSubset(of: PermisoBase.propiedadesDeTarea) { return (.tareaMover, [p], nil, nil, nil) }
            return (.fichaEditar, [p], nil, nil, nil)
        }
        if x.esBorrador(p) {
            // `estado` y `aprobacion` son espejo del registro de aprobaciones: los pone la app, nunca el asistente.
            if claves.contains("estado") || claves.contains("aprobacion") { return (.aprobacionDecidir, [p], nil, nil, nil) }
            return (.borradorPreparar, [p], nil, nil, nil)
        }
        if x.esFactura(p), let c = cambioDeFactura(p, claves: claves, estado: valor("estado")) { return c }
        if x.esOportunidad(p), claves.contains("estado") {
            let e = TextFolding.fold(valor("estado") ?? "")
            if e == "ganada" || e == "ganado" { return (.oportunidadGanar, [p], nil, nil, nil) }
            return (.oportunidadEtapa, [p], nil, nil, nil)
        }
        if x.esContenido(p) { return (.metricasRegistrar, [p], nil, nil, nil) }
        if x.esPlantillaDeEntrega(p) { return (.plantillaAjustar, [p], nil, nil, nil) }
        return (.fichaEditar, [p], nil, nil, nil)
    }

    static func anadido(_ p: VaultPath, seccion: String?, tamano: Int, _ x: Contexto) -> Clase {
        if x.esTarea(p), seccion.map({ TextFolding.fold($0) == "actividad" }) ?? false { return (.comentar, [p], nil, nil, tamano) }
        if x.esBitacora(p) { return (.bitacoraRegistrar, [p], nil, nil, tamano) }
        if x.esBuzon(p) { return (.buzonRegistrar, [p], nil, nil, tamano) }
        if x.esDecisiones(p) { return (.decisionRegistrar, [p], nil, nil, tamano) }
        if x.esBorrador(p) { return (.borradorPreparar, [p], nil, nil, tamano) }
        return (.fichaEditar, [p], nil, nil, tamano)
    }

    static func csv(_ p: VaultPath, filas: [[String: String]], _ x: Contexto) -> Clase {
        func v(_ f: [String: String], _ k: String) -> String {
            TextFolding.fold(f[k]?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        switch TextFolding.nameKey(p.name) {
        case "movimientos.csv":
            if filas.contains(where: { ["conciliado", "confirmado"].contains(v($0, "estado_conciliacion")) || !v($0, "verificacion").isEmpty }) {
                return (.conciliacionConfirmar, [p], nil, nil, nil)
            }
            return (.conciliacionProponer, [p], "FIN-07", nil, nil)
        case "pagos.csv":
            if filas.contains(where: { !v($0, "verificacion").isEmpty }) { return (.cobroConfirmar, [p], nil, nil, nil) }
            return (.cobroExternoRegistrar, [p], nil, nil, nil)
        case "emitidas.csv":
            return (.externa, [p], "FIN-02", .emitirFactura, nil)
        default:
            return (.fichaEditar, [p], nil, nil, nil)
        }
    }
}
