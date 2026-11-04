import Foundation
import Observation
import TLSCore
import TLSDesign

/// El estado de una ficha abierta: su lectura (`LectorNota`), lo calculado del grafo (cabecera, destacado,
/// «Ahora», «Conectado con», pestañas con contador) y lo que está abierto encima (selector, confirmación,
/// «Nuevo»). Escribe siempre con `VaultSession.escribir` (una línea, con Deshacer).
@Observable @MainActor
final class FichaModelo {
    let ruta: VaultPath
    let sesion: VaultSession
    let lector: LectorNota
    let almacen: AlmacenRelaciones

    /// Selector de relación abierto (§5.2).
    var selector: PeticionSelector?
    /// Cambio que espera tu OK con la línea antes y después.
    var confirmacion: ConfirmacionRelacion?
    /// «Nuevo…» abierto.
    var nuevo: OpcionNuevo?
    /// Tarea elegida en el tablero del proyecto (su panel a la derecha).
    var tareaElegida: VaultPath?

    init(ruta: VaultPath, sesion: VaultSession) {
        self.ruta = ruta
        self.sesion = sesion
        self.lector = LectorNota(ruta: ruta, sesion: sesion)
        self.almacen = AlmacenRelaciones.de(sesion)
    }

    func cargar() async {
        await lector.cargar()
        await almacen.actualizar()
        if let t = texto { almacen.recordarTexto(ruta, t) }
    }

    // MARK: Lectura

    var grafo: GrafoRelaciones? { almacen.grafo }
    var hoy: LocalDate { almacen.hoy }

    /// La ficha del grafo; mientras no hay foto, una hecha de la lectura.
    var ficha: FichaGrafo? {
        if let f = grafo?.ficha(ruta) { return f }
        guard case .markdown(_, let props, _, let titulo, let kind)? = lector.nota?.content else { return nil }
        return FichaGrafo(ruta: ruta, tipo: kind, nombre: titulo, propiedades: Frontmatter(properties: props, isValid: true),
                          privada: sesion.esPrivado(ruta))
    }

    var tipo: NoteKind { ficha?.tipo ?? lector.nota?.summary?.kind ?? sesion.resumen(de: ruta)?.kind ?? .note }

    /// Texto completo de la nota (de la lectura).
    var texto: String? {
        if case .markdown(let t, _, _, _, _)? = lector.nota?.content { return t }
        return nil
    }

    var cuerpo: String? {
        if case .markdown(_, _, let b, _, _)? = lector.nota?.content { return b }
        return nil
    }

    // Lo calculado del grafo se guarda por revisión de la foto: una pantalla lo pide muchas veces al pintarse.
    @ObservationIgnored private var cacheResumen: (Int, ResumenDeFicha)?
    @ObservationIgnored private var cacheRelacionados: (Int, [Relacionado])?

    var resumen: ResumenDeFicha? {
        guard let grafo, let f = grafo.ficha(ruta) else { return nil }
        let rev = almacen.generacion
        if let c = cacheResumen, c.0 == rev { return c.1 }
        let r = ResumenDeFicha(ficha: f, grafo: grafo, hoy: hoy)
        cacheResumen = (rev, r)
        return r
    }

    var relacionados: [Relacionado] {
        guard let grafo else { return [] }
        let rev = almacen.generacion
        if let c = cacheRelacionados, c.0 == rev { return c.1 }
        let r = grafo.relacionados(de: ruta)
        cacheRelacionados = (rev, r)
        return r
    }

    var configuracion: TipoFicha {
        var c = TipoFicha.de(tipo)
        if tipo == .project, conSesiones {
            var p = c.pestanas
            p.insert(DefPestana("Viaje", .seccion("Viaje")), at: 1)
            c = TipoFicha(tipo: c.tipo, pestanas: p, nuevo: c.nuevo)
        }
        return c
    }

    /// El servicio del proyecto tiene sesiones (Viaje).
    var conSesiones: Bool {
        guard let f = ficha else { return false }
        return (FormatoFicha.numero(f.texto("sesiones_incluidas")) ?? 0) > 0
    }

    /// Lo relacionado de unos tipos, ordenado: lo urgente primero y lo cerrado al final.
    func relacionados(_ tipos: Set<NoteKind>) -> [Relacionado] {
        let lista = relacionados.filter { tipos.contains($0.ficha.tipo) }
        let orden = EstadosDeFicha.ordenar(lista.map(\.ficha), hoy: hoy).map(\.ruta)
        let porRuta = Dictionary(uniqueKeysWithValues: lista.map { ($0.ficha.ruta, $0) })
        return orden.compactMap { porRuta[$0] }
    }

    /// Las pestañas visibles y las que van a «Más» (vacías y sin «Nuevo» propio), con sus contadores (§3.2).
    func pestanas() -> (visibles: [PestanaCapsula], mas: [PestanaCapsula], defs: [String: DefPestana]) {
        var visibles: [PestanaCapsula] = []
        var mas: [PestanaCapsula] = []
        var defs: [String: DefPestana] = [:]
        for d in configuracion.pestanas {
            defs[d.titulo] = d
            var contador: Int?
            var urgente: TLSEstado?
            var aviso: (Int, String)?
            var vacia = false
            let lista: [FichaGrafo]?
            switch d.contenido {
            case .relacionados(let tipos): lista = relacionados(tipos).map(\.ficha)
            case .tareasProyecto: lista = relacionados([.task]).map(\.ficha)
            case .subtareas: lista = (grafo?.entrantes[ruta] ?? []).filter { $0.propiedad == "padre" }.compactMap { grafo?.ficha($0.origen) }
            default: lista = nil
            }
            if let lista {
                vacia = lista.isEmpty
                let abiertas = lista.filter { EstadosDeFicha.abierta($0.tipo, estado: $0.estado) }
                contador = abiertas.isEmpty ? nil : abiertas.count
                if abiertas.contains(where: { EstadosDeFicha.urgencia($0, hoy: hoy) == 1 }) { urgente = .mal }
                else if abiertas.contains(where: { EstadosDeFicha.urgencia($0, hoy: hoy) == 2 }) { urgente = .atencion }
                let porRevisar = abiertas.filter { EstadosDeFicha.esperaTuOK($0.tipo, estado: $0.estado) }.count
                if porRevisar > 0 { aviso = (porRevisar, "Por revisar") }
            }
            let p = PestanaCapsula(id: d.titulo, titulo: d.titulo, contador: contador, urgente: urgente, aviso: aviso)
            if vacia && !d.siempre { mas.append(p) } else { visibles.append(p) }
        }
        return (visibles, mas, defs)
    }

    /// La pestaña elegida: la de la miga, la recordada en esta pestaña de ventana o la que toca por tipo y estado.
    func pestanaElegida(_ pedida: String?, nav: Navegacion?) -> String {
        let todas = Set(configuracion.pestanas.map(\.titulo))
        if let pedida, todas.contains(pedida) { return pedida }
        if let r = nav?.recuerdo(de: .ficha(ruta)).extra["pestana"], todas.contains(r) { return r }
        let inicial = TipoFicha.pestanaInicial(tipo: tipo, estado: ficha?.estado, conSesiones: conSesiones)
        return todas.contains(inicial) ? inicial : (configuracion.pestanas.first?.titulo ?? "Notas")
    }

    // MARK: Escribir

    var puedeEscribir: Bool { sesion.puedeEscribir }
    var motivoSoloLectura: String? { EdicionRelaciones.motivoSoloLectura(sesion) }

    /// Cambia una propiedad de esta ficha (una línea). `nil` la quita.
    func cambiar(_ clave: String, a valor: PropertyValue?, aviso: String? = nil, en otra: VaultPath? = nil) async {
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return }
        let destino = otra ?? ruta
        let comando: CommandBus.Comando = valor.map { .cambiarPropiedades(destino, poner: [Property(key: clave, value: $0)], quitar: []) }
            ?? .cambiarPropiedades(destino, poner: [], quitar: [clave])
        let nombre = (otra.flatMap { grafo?.ficha($0)?.nombre }) ?? ficha?.nombre ?? ruta.stem
        let texto = aviso ?? (valor.map { "\(nombre): \(clave.replacingOccurrences(of: "_", with: " ")) pasa a «\($0.displayText)»" }
                              ?? "Quité \(clave.replacingOccurrences(of: "_", with: " ")) de \(nombre)")
        _ = try? await sesion.escribir(comando, aviso: texto)
        almacen.invalidar()
    }

    /// Cambia el estado (en una tarea, con su entrada de Actividad, como hace `TaskStore`).
    func cambiarEstado(_ nuevo: String, de otra: VaultPath? = nil, soloEstado: Bool = false) async {
        let destino = otra ?? ruta
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return }
        let f = (otra == nil ? ficha : grafo?.ficha(destino))
        if f?.tipo == .task, let foto = almacen.foto, let estado = EstadoTarea(leyendo: nuevo) {
            let store = TaskStore(snapshot: foto)
            if let t = store.tarea(destino) {
                do {
                    let plan = try store.cambiarEstado(t, a: estado, autor: sesion.autor, persona: sesion.persona, soloEstado: soloEstado)
                    try await sesion.escribir(plan: plan, aviso: "\(t.numero ?? t.titulo) pasa a \(estado.rawValue)")
                    almacen.invalidar()
                } catch TareaError.sinCambios {
                } catch let e as TareaError {
                    sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
                } catch {}
                return
            }
        }
        let escrito = EstadosDeFicha.escrito(nuevo, como: f?.estado)
        await cambiar("estado", a: .text(escrito), aviso: "\(f?.nombre ?? destino.stem) pasa a \(nuevo)", en: otra)
    }

    /// Opciones del menú de estado de la cabecera, con las que no se pueden elegir desactivadas y su motivo.
    func opcionesEstado(_ f: FichaGrafo) -> [OpcionEstado] {
        let posibles = EstadosDeFicha.posibles(f.tipo)
        let actual = TextFolding.fold(f.estado ?? "")
        return posibles.map { e in
            var motivo: String?
            switch f.tipo {
            case .opportunity where e == "Ganada":
                if let g = grafo { let c = g.cobroConfirmado(oportunidad: f.ruta); if !c.confirmado { motivo = c.motivo } }
            case .invoice:
                motivo = TextFolding.fold(e) == actual ? nil : "La emisión y el cobro se confirman con su acción, no se eligen a mano."
            case .project where e == "Cerrado":
                let abiertas = relacionados([.task]).filter { EstadosDeFicha.abierta(.task, estado: $0.ficha.estado) }.count
                if abiertas > 0 { motivo = "Antes hay que terminar o cancelar sus \(abiertas == 1 ? "1 tarea abierta" : "\(abiertas) tareas abiertas")." }
            case .organization where e == "Antiguo cliente", .contact where e == "Antiguo cliente":
                let vivos = relacionados([.project]).contains { EstadosDeFicha.abierta(.project, estado: $0.ficha.estado) }
                if vivos { motivo = "Tiene un proyecto abierto: pasa a antiguo cliente al cerrarlo." }
            default: break
            }
            if !sesion.puedeEscribir { motivo = motivoSoloLectura.map { "No se puede cambiar: \($0)." } }
            if TextFolding.fold(e) == actual { motivo = nil }
            return OpcionEstado(id: e, titulo: e, estado: FormatoFicha.tlsEstado(f.tipo, e, hoy: hoy), motivoDesactivado: motivo)
        }
    }

    /// Cómo acabó guardar una sección editada en el sitio.
    enum GuardadoSeccion: Equatable {
        case guardada
        /// La sección cambió fuera (otra ventana, Obsidian) desde que se pulsó «Editar»: no se pisa; el
        /// borrador sigue abierto con «Ver diferencias».
        case cambiadaFuera
        /// No se pudo (solo lectura, sección que ya no está, error al escribir): lo dice el aviso.
        case noSePudo
    }

    /// El texto de la nota donde vive una sección (esta ficha u `otra`, leída de la foto de la carpeta).
    func cuerpo(de otra: VaultPath?) -> String? {
        let destino = otra ?? ruta
        return destino == ruta ? cuerpo : almacen.foto?.text(destino).map { NoteDocument(text: $0).body }
    }

    /// Huella de una sección tal como se ve ahora. «Editar» la toma al empezar y la pasa a `guardarSeccion`,
    /// para que lo que cambie fuera mientras se escribe no se pise.
    func huellaSeccion(_ titulo: String, en otra: VaultPath? = nil) -> String? {
        cuerpo(de: otra).flatMap { MarkdownSections.hash(of: titulo, in: $0) }
    }

    /// Sustituye el texto de una sección (Notas editables en el sitio), con la huella de lo que se leyó al
    /// empezar a editar (`huella`, de `huellaSeccion`; sin ella, la de ahora, para quien relee justo antes de
    /// escribir). `en`: otra nota (la tarea elegida en el tablero), leída de la foto de la carpeta.
    @discardableResult
    func guardarSeccion(_ titulo: String, texto nuevo: String, en otra: VaultPath? = nil, huella: String? = nil) async -> GuardadoSeccion {
        let destino = otra ?? ruta
        guard EdicionRelaciones.comprobarEscritura(sesion) else { return .noSePudo }
        guard let base = huella ?? huellaSeccion(titulo, en: otra) else {
            sesion.aviso = Aviso("No encuentro la sección «\(titulo)»: puede que haya cambiado fuera. Vuelve a abrirla.", estado: .atencion)
            return .noSePudo
        }
        var limpio = nuevo
        while limpio.hasSuffix("\n") { limpio.removeLast() }
        let nombre = grafo?.ficha(destino)?.nombre ?? destino.stem
        defer { almacen.invalidar() }
        do {
            try await sesion.escribir(.sustituirSeccion(destino, seccion: titulo, texto: limpio, baseHash: base),
                                      aviso: "Guardé «\(titulo)» en \(nombre)")
            return .guardada
        } catch WriteError.seccionCambiada {
            sesion.aviso = Aviso("«\(titulo)» cambió fuera mientras escribías. Tu texto sigue abierto: mira las diferencias antes de guardar.",
                                 estado: .atencion)
            return .cambiadaFuera
        } catch {
            return .noSePudo
        }
    }

    /// «Añadir nota»: una línea con fecha al final de «## Notas» (`2026-10-22 · …`).
    func anadirNota(_ texto: String) async {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, EdicionRelaciones.comprobarEscritura(sesion) else { return }
        _ = try? await sesion.escribir(.anadirASeccion(ruta, seccion: "Notas", texto: "- \(hoy) · \(t)"),
                                       aviso: "Añadí una nota a \(ficha?.nombre ?? ruta.stem)")
        almacen.invalidar()
    }

    // MARK: Relaciones

    /// Abre el selector para una propiedad que guarda esta ficha («Conectado con», inspector).
    func abrirSelector(propiedad: String, origen: String = "chips", en otra: VaultPath? = nil) {
        guard let f = otra.flatMap({ grafo?.ficha($0) }) ?? ficha else { return }
        let def = EsquemaRelaciones.definicion(tipo: f.tipo, propiedad: propiedad)
        let actuales = Set(grafo?.destinos(de: f.ruta, propiedad: propiedad) ?? [])
        let tipos = def?.apuntaA ?? [.note]
        let crear = tipos.count == 1 ? tipos.first.flatMap { t in EdicionRelaciones.plantillaAlVuelo(t).map { (t, $0.plantilla, $0.nombre) } } : nil
        let quitable = !actuales.isEmpty && def?.motivoObligatoria(f.propiedades) == nil
        let etiqueta = def?.etiqueta ?? FormatoFicha.capital(propiedad)
        selector = PeticionSelector(
            modo: .directo(dueno: f.ruta, propiedad: def?.propiedad ?? propiedad),
            titulo: "\(etiqueta) de \(f.nombre)", placeholder: "Buscar o crear",
            tipos: tipos, varias: def?.cardinalidad == .varias, contexto: contexto(para: tipos), enlazadas: actuales,
            nota: "Se guarda en la ficha de \(f.nombre), en «\(def?.propiedad ?? propiedad)»." + (def?.motivoObligatoria(f.propiedades).map { " \($0)" } ?? " Es opcional."),
            quitar: quitable && def?.cardinalidad != .varias ? "Quitar \(etiqueta.lowercased())" : nil,
            crear: crear, origen: origen)
    }

    /// «Añadir existente…» desde el lado que no la guarda: se elige la ficha de `tipo` que la guardará.
    func abrirSelectorInverso(tipos: Set<NoteKind>) {
        guard let f = ficha else { return }
        // Solo los tipos que de verdad guardan una relación con esta ficha (en Facturas de un proyecto, las facturas;
        // los recibos cuelgan de la factura, no del proyecto).
        let admitidos = Set(tipos.filter { EsquemaRelaciones.quienGuarda(apuntandoA: f.tipo, desde: $0) != nil })
        let elegibles = admitidos.isEmpty ? tipos : admitidos
        let ya = Set(relacionados.filter { elegibles.contains($0.ficha.tipo) }.map(\.ficha.ruta))
        let principal = elegibles.contains(.proposal) ? NoteKind.proposal
            : (elegibles.sorted { $0.rawValue < $1.rawValue }.first ?? .note)
        let def = EsquemaRelaciones.quienGuarda(apuntandoA: f.tipo, desde: principal)
        selector = PeticionSelector(
            modo: .inverso(destino: ruta),
            titulo: "Añadir a \(f.nombre): \(principal.etiquetaRelacion)", placeholder: "Buscar",
            tipos: elegibles, varias: false, contexto: contexto(para: elegibles).filter { !ya.contains($0) }, enlazadas: ya,
            nota: def.map { "Se guarda en la ficha que elijas, en «\($0.propiedad)», no en la de \(f.nombre)." }
                ?? "Estas fichas no guardan una relación con \(f.tipo.etiquetaRelacion).",
            quitar: nil, crear: nil)
    }

    /// Las del contexto primero: las de la empresa de esta ficha y lo que ya cuelga de ella.
    func contexto(para tipos: Set<NoteKind>) -> [VaultPath] {
        guard let grafo else { return [] }
        var out = relacionados.map(\.ficha).filter { tipos.contains($0.tipo) }.map(\.ruta)
        for e in grafo.destinos(de: ruta, propiedad: "empresa") {
            out += grafo.relacionados(de: e).map(\.ficha).filter { tipos.contains($0.tipo) }.map(\.ruta)
            if tipos.contains(.organization) { out.insert(e, at: 0) }
        }
        var vistos = Set<VaultPath>()
        return out.filter { vistos.insert($0).inserted }
    }

    /// Lo elegido en el selector.
    func elegido(_ destino: VaultPath, en p: PeticionSelector, navegar: NavegarAccion?) async {
        switch p.modo {
        case .directo(let dueno, let propiedad):
            let varias = p.varias
            let cambio = CambioDeRelacion(dueno: dueno, propiedad: propiedad, accion: varias ? .anadir(destino) : .poner(destino))
            confirmacion = await EdicionRelaciones.hacer(cambio, sesion: sesion, almacen: almacen, navegar: navegar)
        case .inverso(let aqui):
            guard let otra = grafo?.ficha(destino), let f = ficha,
                  let def = EsquemaRelaciones.quienGuarda(apuntandoA: f.tipo, desde: otra.tipo) else {
                sesion.aviso = Aviso("Esa ficha no se puede enlazar desde aquí.", estado: .atencion)
                return
            }
            let accion: CambioDeRelacion.Accion = def.cardinalidad == .varias ? .anadir(aqui) : .poner(aqui)
            confirmacion = await EdicionRelaciones.hacer(CambioDeRelacion(dueno: destino, propiedad: def.propiedad, accion: accion),
                                                         sesion: sesion, almacen: almacen, navegar: navegar)
        }
    }

    /// «Listo» en un selector de varias: añade las nuevas y quita las desmarcadas (cada una, una línea).
    func listo(_ marcadas: Set<VaultPath>, en p: PeticionSelector) async {
        guard case .directo(let dueno, let propiedad) = p.modo else { return }
        for d in marcadas.subtracting(p.enlazadas).sorted() {
            await EdicionRelaciones.hacer(CambioDeRelacion(dueno: dueno, propiedad: propiedad, accion: .anadir(d)), sesion: sesion, almacen: almacen)
        }
        for d in p.enlazadas.subtracting(marcadas).sorted() {
            await EdicionRelaciones.hacer(CambioDeRelacion(dueno: dueno, propiedad: propiedad, accion: .quitar(d)), sesion: sesion, almacen: almacen)
        }
    }

    /// Quita una relación: la escribe en la ficha que la guarda (aquí o en la otra).
    func quitar(propiedad: String, destino: VaultPath?, guardaEn: VaultPath) async {
        let cambio: CambioDeRelacion
        if guardaEn == ruta {
            cambio = CambioDeRelacion(dueno: ruta, propiedad: propiedad, accion: .quitar(destino))
        } else {
            cambio = CambioDeRelacion(dueno: guardaEn, propiedad: propiedad, accion: .quitar(ruta))
        }
        confirmacion = await EdicionRelaciones.hacer(cambio, sesion: sesion, almacen: almacen)
    }

    /// «Quitar de <esta ficha>» desde una fila de lo relacionado: borra esa clave (o ese elemento) en la otra.
    func quitarRelacionado(_ r: Relacionado) async {
        guard case .directa(let propiedad) = r.via else { return }
        confirmacion = await EdicionRelaciones.hacer(CambioDeRelacion(dueno: r.ficha.ruta, propiedad: propiedad, accion: .quitar(ruta)),
                                                     sesion: sesion, almacen: almacen)
    }

    /// Mueve un elemento de una lista (personas, bloqueada por) un puesto antes o después (alternativa al arrastre).
    func mover(_ destino: VaultPath, propiedad: String, desplazamiento: Int) async {
        guard let grafo else { return }
        var orden = grafo.destinos(de: ruta, propiedad: propiedad)
        guard let i = orden.firstIndex(of: destino) else { return }
        let j = i + desplazamiento
        guard orden.indices.contains(j) else { return }
        orden.swapAt(i, j)
        await EdicionRelaciones.hacer(CambioDeRelacion(dueno: ruta, propiedad: propiedad, accion: .reordenar(orden)),
                                      sesion: sesion, almacen: almacen)
    }
}
