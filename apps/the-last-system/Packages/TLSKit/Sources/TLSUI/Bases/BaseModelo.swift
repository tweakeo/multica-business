import Foundation
import Observation
import SwiftUI
import TLSCore
import TLSDesign

/// La celda que se está editando (una a la vez).
struct CeldaEnEdicion: Hashable {
    let fila: String
    let columna: String
}

/// Una oportunidad que no puede ir a Ganada: la tarjeta vuelve a su sitio y la columna lo explica.
struct BloqueoMovimiento: Hashable {
    let fila: String
    let etapa: String
    let motivo: String
}

/// «Nueva …» (§4.8): lo que ya se sabe al abrir la hoja (pestaña, filtro, columna del tablero o día).
struct PeticionNueva: Identifiable {
    let id = UUID()
    /// Respuestas ya puestas (`estado` → «Propuesta»).
    var valores: [String: String] = [:]
    /// Relaciones ya puestas (`empresa` → ruta).
    var contexto: [String: VaultPath] = [:]
    /// Propiedades que se ponen después (la columna del tablero, el día del calendario).
    var poner: [String: String] = [:]
}

/// Estado de una base en pantalla (§7.4 `BaseModelo`): datos, configuración de la vista, búsqueda,
/// selección, edición en la celda y vistas guardadas. Escribe solo con `sesion.escribir` (CommandBus).
@Observable @MainActor
final class BaseModelo {
    let coleccion: ColeccionBase
    let sesion: VaultSession
    let destino: Destino
    /// «Facturas de Arquitectura Nexo»: solo las filas que enlazan esa ficha.
    let contexto: VaultPath?
    let vistaPedida: String?

    private(set) var datos: DatosBase?
    private(set) var version = 0
    var config: ConfigVista {
        didSet { if config != oldValue { persistir() } }
    }
    /// La configuración de la vista activa (o la de serie): si `config` es distinta, hay cambios sin guardar.
    private(set) var configBase: ConfigVista?
    /// Las vistas que guardaste tú (las de serie van aparte, en `vistasDeSerie`).
    private(set) var vistas: [VistaGuardada] = []
    private(set) var vistaActiva: String?
    var busqueda = "" {
        didSet { if busqueda != oldValue { buscarEnTexto(); persistir() } }
    }
    private(set) var coincidenPorTexto: Set<String> = []
    var seleccion: Set<String> = [] {
        didSet { if seleccion != oldValue { persistir() } }
    }
    var editando: CeldaEnEdicion?
    var errorEdicion: String?
    var nueva: PeticionNueva?
    var bloqueo: BloqueoMovimiento?
    var nombrandoVista: Bool = false
    private(set) var cargando = true
    /// Mes que enseña el calendario.
    var mesCalendario: (year: Int, month: Int)?
    /// Lunes de la semana que enseña el calendario en semana (`nil` = la de hoy).
    var semanaCalendario: LocalDate?
    /// Ficha elegida en el calendario o en «Sin fecha» (para moverla con el teclado).
    var elegidaCalendario: String?

    @ObservationIgnored weak var nav: Navegacion?
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private var memo: (clave: Int, filas: [FilaBase])?
    @ObservationIgnored private var tareaTexto: Task<Void, Never>?
    @ObservationIgnored private var restaurado = false

    init(coleccion: ColeccionBase, sesion: VaultSession, destino: Destino, contexto: VaultPath?, vista: String?) {
        self.coleccion = coleccion
        self.sesion = sesion
        self.destino = destino
        self.contexto = contexto
        self.vistaPedida = vista
        self.config = ConfigVista(vista: coleccion.vista, columnas: coleccion.columnasDeSerie,
                                  fechaCalendario: coleccion.fechaCalendario, plegados: coleccion.plegadas)
    }

    var almacen: AlmacenBases { AlmacenBases.de(sesion) }

    /// Vistas que trae la app para esta base (Oportunidades: Abiertas · Por cerrar este mes · Ganadas).
    var vistasDeSerie: [VistaGuardada] { CatalogoBases.vistasDeSerie(coleccion) }

    /// Las de serie y las tuyas, en ese orden (las pestañas de vistas).
    var todasLasVistas: [VistaGuardada] { vistasDeSerie + vistas }

    /// La vista activa es tuya (se puede guardar encima o quitar).
    var vistaActivaEsTuya: Bool { vistaActiva.map { id in vistas.contains { $0.id == id } } ?? false }
    var hoy: LocalDate { datos?.hoy ?? .today() }

    // MARK: Cargar

    /// Lee la base (otra vez si cambió la carpeta) y, la primera vez, recupera cómo se dejó (§11.1).
    func cargar() async {
        guard let d = await almacen.cargar(coleccion.id) else { cargando = false; return }
        datos = d
        version += 1
        if !restaurado {
            restaurado = true
            vistas = leerVistas()
            restaurar(d)
        } else {
            // Deshacer (o un cambio de fuera) puede haber cambiado `.tls/vistas/<base>.json`.
            let leidas = leerVistas()
            if leidas != vistas {
                vistas = leidas
                if let a = vistaActiva, !todasLasVistas.contains(where: { $0.id == a }) { vistaActiva = nil }
            }
        }
        cargando = false
        if !busqueda.isEmpty { buscarEnTexto() }
    }

    private func restaurar(_ d: DatosBase) {
        let deSerie = ConfigVista.deSerie(d)
        let r = nav?.recuerdo(de: destino)
        if let id = r?.extra["vistaGuardada"], let v = todasLasVistas.first(where: { $0.id == id }) {
            vistaActiva = v.id
            configBase = v.config
        } else if let pedida = vistaPedida, let v = todasLasVistas.first(where: { $0.id == pedida || $0.nombre == pedida }) {
            vistaActiva = v.id
            configBase = v.config
        } else {
            configBase = deSerie
        }
        if let json = r?.extra["config"], let data = json.data(using: .utf8),
           let c = try? JSONDecoder().decode(ConfigVista.self, from: data) {
            config = c
        } else {
            config = configBase ?? deSerie
        }
        busqueda = r?.busqueda ?? ""
        seleccion = Set(r?.seleccion ?? [])
        if r?.extra["nueva"] != nil {
            nav?.actualizarRecuerdo(de: destino) { $0.extra["nueva"] = nil }
            abrirNueva()
        }
    }

    /// Guarda en la pestaña de ventana cómo se está viendo (vista, filtros, búsqueda, selección).
    private func persistir() {
        guard restaurado, let nav else { return }
        let json = (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) }
        let seleccion = Array(self.seleccion).sorted()
        let busqueda = self.busqueda
        let activa = vistaActiva
        nav.actualizarRecuerdo(de: destino) { r in
            r.extra["config"] = json
            r.extra["vistaGuardada"] = activa
            r.busqueda = busqueda.isEmpty ? nil : busqueda
            r.seleccion = seleccion
        }
    }

    // MARK: Lo que se ve

    /// Filas visibles: pestaña, contexto, búsqueda (también en el texto de la nota) y filtros, ordenadas.
    var filas: [FilaBase] {
        guard let datos else { return [] }
        var h = Hasher()
        h.combine(version); h.combine(config); h.combine(busqueda); h.combine(coincidenPorTexto)
        let clave = h.finalize()
        if let memo, memo.clave == clave { return memo.filas }
        var r = MotorVista.filas(datos, config: config, busqueda: busqueda, extra: coincidenPorTexto)
        if let contexto {
            r = r.filter { f in f.enlaces.values.contains { $0.contains { $0.ruta == contexto } } }
        }
        memo = (clave, r)
        return r
    }

    /// Columnas visibles, en su orden.
    var columnasVisibles: [ColumnaBase] {
        let visibles = config.columnas.compactMap { coleccion.columna($0) }
        return visibles.isEmpty ? coleccion.columnas.filter(\.deSerie) : visibles
    }

    /// Propiedad del tablero (y de los grupos de la lista).
    var claveTablero: String? { config.agrupar ?? datos?.agruparPor ?? coleccion.agruparPor ?? coleccion.columnaEstado?.clave }

    var grupos: [GrupoFilas]? {
        guard let clave = config.agrupar else { return nil }
        return MotorVista.agrupar(filas, por: clave, coleccion: coleccion, hoy: hoy)
    }

    /// Hay cambios sin guardar respecto a la vista activa (los anchos y el orden que guarda la tabla del
    /// sistema no cuentan: se guardan con la vista, pero no piden «Guardar»).
    var hayCambios: Bool {
        guard var base = configBase else { return false }
        var actual = config
        base.personalizacionTabla = nil
        actual.personalizacionTabla = nil
        return base != actual
    }

    func fila(_ id: String) -> FilaBase? { datos?.filas.first { $0.id == id } }

    /// Lo que lleva una tarjeta o un evento al arrastrarlo (el id de la fila con su empresa).
    func textoArrastre(_ f: FilaBase) -> String { ArrastreFila.texto(f.id, empresa: sesion.entry.id) }

    /// La fila de lo soltado, si viene de esta empresa (lo de otra ventana de otra empresa no se acepta).
    func filaSoltada(_ textos: [String]) -> FilaBase? {
        textos.first.flatMap { ArrastreFila.id($0, empresa: sesion.entry.id) }.flatMap(fila)
    }

    var elegidas: [FilaBase] { filas.filter { seleccion.contains($0.id) } }

    /// Sugerencias de filtro para lo escrito en el buscador (§4.5).
    var sugerencias: [SugerenciaFiltro] {
        guard let datos, !busqueda.isEmpty else { return [] }
        return MotorVista.sugerencias(busqueda, datos: datos).filter { !config.filtros.contains($0.filtro) }
    }

    /// Busca también en el cuerpo de las notas (texto completo), sin bloquear al escribir.
    private func buscarEnTexto() {
        tareaTexto?.cancel()
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { coincidenPorTexto = []; return }
        tareaTexto = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            let hits = await self.sesion.buscar(q, limite: 300)
            guard !Task.isCancelled else { return }
            self.coincidenPorTexto = Set(hits.map(\.note.path.raw))
        }
    }

    // MARK: Pestañas, filtros, orden y grupos

    func elegirPestana(_ id: String?) {
        config.pestana = id == PestanaBase.todas ? nil : id
    }

    func anadirFiltro(_ f: FiltroBase) {
        guard !config.filtros.contains(f) else { return }
        config.filtros.append(f)
    }

    func quitarFiltro(_ f: FiltroBase) { config.filtros.removeAll { $0 == f } }

    func quitarFiltros() { config.filtros = [] }

    func aplicarSugerencia(_ s: SugerenciaFiltro) {
        anadirFiltro(s.filtro)
        busqueda = ""
    }

    func ordenar(por clave: String, ascendente: Bool) {
        config.orden = [OrdenBase(clave, ascendente: ascendente)]
    }

    func plegar(_ grupo: String) {
        if config.plegados.contains(grupo) { config.plegados.removeAll { $0 == grupo } } else { config.plegados.append(grupo) }
    }

    func cambiarVista(_ v: TipoVista) {
        guard v != config.vista else { return }
        config.vista = v
        if v == .tablero, config.agrupar == nil { config.agrupar = claveTablero }
    }

    // MARK: Columnas

    func mostrarColumna(_ clave: String, _ visible: Bool) {
        if visible, !config.columnas.contains(clave) { config.columnas.append(clave) }
        if !visible, config.columnas.count > 1 { config.columnas.removeAll { $0 == clave } }
    }

    func moverColumna(_ clave: String, _ paso: Int) {
        guard let i = config.columnas.firstIndex(of: clave) else { return }
        let j = i + paso
        guard config.columnas.indices.contains(j) else { return }
        config.columnas.swapAt(i, j)
        config.personalizacionTabla = nil
    }

    func restaurarColumnas() {
        config.columnas = coleccion.columnasDeSerie
        config.anchos = [:]
        config.personalizacionTabla = nil
    }

    // MARK: Vistas guardadas (§4.6)

    func elegirVistaGuardada(_ id: String?) {
        if let id, let v = todasLasVistas.first(where: { $0.id == id }) {
            vistaActiva = id
            configBase = v.config
            config = v.config
        } else {
            vistaActiva = nil
            configBase = datos.map(ConfigVista.deSerie)
            if let c = configBase { config = c }
        }
        persistir()
    }

    func guardarVistaComo(_ nombre: String) {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let antes = vistas
        let v = VistaGuardada(nombre: n, config: config)
        vistas.append(v)
        vistaActiva = v.id
        configBase = config
        guardarVistas(antes: antes, aviso: "Guardé la vista «\(n)»")
        nombrandoVista = false
    }

    func guardarCambiosVista() {
        guard let id = vistaActiva, let i = vistas.firstIndex(where: { $0.id == id }) else { return }
        let antes = vistas
        vistas[i].config = config
        configBase = config
        guardarVistas(antes: antes, aviso: "Guardé los cambios de «\(vistas[i].nombre)»")
    }

    func descartarCambios() {
        guard let c = configBase else { return }
        config = c
    }

    func quitarVista(_ id: String) {
        guard let v = vistas.first(where: { $0.id == id }), !v.esDeSerie else { return }
        let antes = vistas
        vistas.removeAll { $0.id == id }
        if vistaActiva == id { elegirVistaGuardada(nil) }
        guardarVistas(antes: antes, aviso: "Quité la vista «\(v.nombre)»")
    }

    // MARK: Vistas guardadas (§4.6, pregunta 7: en `.tls/vistas/<base>.json`)

    /// Las vistas de esta base: las de la carpeta (`.tls/vistas/<base>.json`) y, si aún no hay, las que se
    /// guardaron en los datos de la app antes de poder escribirlas en la carpeta (o con la carpeta en solo
    /// lectura). Leer no cambia nada.
    func leerVistas() -> [VistaGuardada] {
        if let data = datosVistasEnCarpeta() { return AlmacenVistas.decodificar(data) }
        return almacen.almacenVistas.leer(coleccion.id)
    }

    /// Sin seguir enlaces ni descargar de iCloud (como el resto de ajustes de la carpeta).
    private func datosVistasEnCarpeta() -> Data? {
        guard let root = sesion.root else { return nil }
        return AjustesBases.leerTexto(AlmacenVistas.rutaEnCarpeta(coleccion.id), root: root).map { Data($0.utf8) }
    }

    /// Guarda las vistas con Deshacer: en la carpeta, por `CommandBus` (las que hubiera en los datos de la app
    /// pasan con ellas); con la carpeta en solo lectura, en los datos de la app.
    private func guardarVistas(antes: [VistaGuardada], aviso: String) {
        guard sesion.puedeEscribir else { guardarVistasFuera(antes: antes, aviso: aviso); return }
        let ruta = AlmacenVistas.rutaEnCarpeta(coleccion.id)
        let texto = String(decoding: AlmacenVistas.codificar(vistas), as: UTF8.self)
        let comando: CommandBus.Comando
        if let previo = datosVistasEnCarpeta() {
            comando = .guardarNota(ruta, base: String(decoding: previo, as: UTF8.self), texto: texto)
        } else {
            comando = .crear(ruta, texto: texto)
        }
        let um = undoManager
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sesion.escribir(comando, aviso: aviso, deshacer: um)
            } catch {
                // `escribir` ya avisa del error; la lista vuelve a lo que hay en la carpeta.
                self.vistas = antes
            }
        }
    }

    /// Carpeta en solo lectura: las vistas van a los datos de la app de esta empresa (nunca a la carpeta).
    private func guardarVistasFuera(antes: [VistaGuardada], aviso: String) {
        let almacen = self.almacen.almacenVistas
        let id = coleccion.id
        do {
            try almacen.guardar(vistas, de: id)
        } catch {
            sesion.aviso = Aviso("No he podido guardar la vista: \(error.localizedDescription)", estado: .mal)
            return
        }
        let despues = vistas
        let restaurar: @MainActor (BaseModelo, [VistaGuardada]) -> Void = { m, vs in
            m.vistas = vs
            if let a = m.vistaActiva, !vs.contains(where: { $0.id == a }) { m.vistaActiva = nil }
            try? almacen.guardar(vs, de: id)
        }
        if let um = undoManager ?? sesion.undoManagerActivo {
            registrar(um, volverA: antes, rehacer: despues, nombre: aviso, restaurar: restaurar)
        }
        sesion.aviso = Aviso(aviso) { [weak self] in
            guard let self else { return }
            restaurar(self, antes)
        }
    }

    private func registrar(_ um: UndoManager, volverA: [VistaGuardada], rehacer: [VistaGuardada], nombre: String,
                           restaurar: @escaping @MainActor (BaseModelo, [VistaGuardada]) -> Void) {
        um.registerUndo(withTarget: self) { m in
            MainActor.assumeIsolated {
                restaurar(m, volverA)
                m.registrar(um, volverA: rehacer, rehacer: volverA, nombre: nombre, restaurar: restaurar)
            }
        }
        um.setActionName(nombre)
    }

    /// «Hacer vista por defecto»: escribe una línea en la nota índice (`vista: tablero`), con Deshacer.
    var motivoSinPorDefecto: String? {
        if datos?.indice == nil { return "Esta base no tiene nota índice donde guardarlo." }
        if !sesion.puedeEscribir { return sesionMotivoSoloLectura }
        return nil
    }

    func hacerVistaPorDefecto() async {
        guard let nota = datos?.indice?.ruta else { return }
        var poner = [Property(key: "vista", value: .text(config.vista.rawValue))]
        var quitar: [String] = []
        // La agrupación que se ve pasa a ser la de serie; si no se agrupa, se quita la de antes (si no, la
        // tabla de serie seguiría saliendo agrupada).
        if let a = config.agrupar, [.tablero, .lista, .tabla].contains(config.vista) {
            poner.append(Property(key: "agrupar_por", value: .text(a)))
        } else if datos?.indice?.agruparPor != nil {
            quitar.append("agrupar_por")
        }
        _ = try? await sesion.escribir(.cambiarPropiedades(nota, poner: poner, quitar: quitar),
                                       aviso: "\(coleccion.nombre) se abre ahora en \(config.vista.nombre)",
                                       deshacer: undoManager)
    }

    // MARK: Descripción (M2-Bases: «Editar descripción»)

    /// Por qué no se puede cambiar la descripción (`nil` = se puede).
    var motivoSinDescripcion: String? {
        if datos?.indice == nil { return "Esta base no tiene nota índice donde guardar su descripción." }
        if !sesion.puedeEscribir { return sesionMotivoSoloLectura }
        return nil
    }

    /// Guarda la descripción en la nota índice: cambia solo su primer párrafo, por `CommandBus` y con
    /// Deshacer. Devuelve el error para enseñarlo bajo el campo (`nil` = guardada o sin cambios).
    @discardableResult
    func guardarDescripcion(_ texto: String) async -> String? {
        if let motivo = motivoSinDescripcion { return motivo }
        guard let ruta = datos?.indice?.ruta else { return nil }
        guard case .markdown(let actual, _, _, _, _)? = await sesion.leer(ruta)?.content else {
            return "No he podido leer la nota índice. Vuelve a intentarlo en un momento."
        }
        guard let nuevo = NotaIndiceBase.cambiandoFrase(actual, por: texto) else { return nil }
        do {
            _ = try await sesion.escribir(.guardarNota(ruta, base: actual, texto: nuevo),
                                          aviso: "Guardé la descripción en la nota índice de \(coleccion.nombre).",
                                          deshacer: undoManager)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Escribir

    /// Motivo por el que no se puede editar nada (carpeta real o solo lectura).
    var sesionMotivoSoloLectura: String {
        if case .soloLectura(let m) = sesion.modoEscritura { return m.texto + "." }
        return "Esta carpeta aún se está abriendo."
    }

    /// Motivo por el que esa celda no se edita (`nil` = se puede).
    func motivoSoloLectura(_ f: FilaBase, _ col: ColumnaBase) -> String? {
        if let m = EdicionCelda.motivoSoloLectura(f, col, coleccion: coleccion) { return m }
        if !sesion.puedeEscribir { return sesionMotivoSoloLectura }
        return nil
    }

    /// Escribe lo tecleado en una celda. Devuelve el error para enseñarlo bajo el campo (`nil` = guardado).
    @discardableResult
    func guardar(_ f: FilaBase, _ col: ColumnaBase, texto: String) async -> String? {
        do {
            let valor = try EdicionCelda.valor(texto, para: col, hoy: hoy)
            return await guardar(f, col, valor: valor)
        } catch {
            return error.localizedDescription
        }
    }

    /// Escribe solo esa clave (o solo esa fila del CSV), con aviso «Deshacer».
    @discardableResult
    func guardar(_ f: FilaBase, _ col: ColumnaBase, valor: PropertyValue?) async -> String? {
        if col.clave == "estado", f.tipo == .opportunity, case .text(let v)? = valor,
           TextFolding.fold(v) == "ganada", let motivo = ReglaGanada.motivo(f) {
            return motivo
        }
        do {
            let comando = try EdicionCelda.comando(f, col, valor: valor, coleccion: coleccion)
            let texto = valor.map { v -> String in
                switch col.tipo {
                case .fecha: LocalDate(parsing: v.displayText).map { FormatoBase.fecha($0, hoy: hoy) } ?? v.displayText
                case .dinero: FormatoBase.numero(v.displayText).map { FormatoBase.euros($0) } ?? v.displayText
                default: FormatoBase.opcionVisible(FormatoBase.textoVisible(v))
                }
            }
            let aviso = texto.map { "«\(f.titulo)»: \(col.etiqueta) pasa a \($0)" } ?? "«\(f.titulo)»: quité \(col.etiqueta.lowercased())"
            let r = try await sesion.escribir(comando, aviso: aviso, deshacer: undoManager)
            if r.hecho, col.tipo == .fecha, case .text(let t)? = valor, LocalDate(parsing: t)?.isWeekend == true {
                // ENT-04: el dominio la ha corrido al lunes; se relee lo escrito (el aviso ya lo dice).
                await cargar()
            } else if r.hecho, let clave = f.claveReal(col), let d = datos {
                datos = d.cambiando(f.id, clave: clave, valor: valor)
                version += 1
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Tablero: mover una tarjeta a otra columna (cambia esa propiedad). Ganada sin cobro confirmado no.
    func mover(_ f: FilaBase, a valor: String) async {
        guard let clave = claveTablero, let col = coleccion.columna(clave) else { return }
        if f.valoresOpcion(col).contains(where: { TextFolding.fold($0) == TextFolding.fold(valor) }) { return }
        if clave == "estado", f.tipo == .opportunity, TextFolding.fold(valor) == "ganada", let motivo = ReglaGanada.motivo(f) {
            bloqueo = BloqueoMovimiento(fila: f.id, etapa: f.texto("estado") ?? "", motivo: motivo)
            return
        }
        if let motivo = motivoSoloLectura(f, col) {
            sesion.aviso = Aviso(motivo, estado: .atencion)
            return
        }
        bloqueo = nil
        if let error = await guardar(f, col, valor: .text(valor)) {
            sesion.aviso = Aviso(error, estado: .atencion)
        }
    }

    /// ⌘← ⌘→: mueve la tarjeta a la columna de al lado.
    func moverAlLado(_ f: FilaBase, _ paso: Int, columnas: [String]) async {
        guard let clave = claveTablero, let col = coleccion.columna(clave),
              let actual = f.valoresOpcion(col).first,
              let i = columnas.firstIndex(where: { TextFolding.fold($0) == TextFolding.fold(actual) }) else { return }
        let j = i + paso
        guard columnas.indices.contains(j) else { return }
        await mover(f, a: columnas[j])
    }

    /// Calendario: pone (o quita) la fecha de una ficha.
    func ponerFecha(_ f: FilaBase, _ fecha: LocalDate?) async {
        guard let clave = config.fechaCalendario ?? coleccion.fechaCalendario else { return }
        let col = coleccion.columna(clave) ?? ColumnaBase(clave, clave, .fecha)
        if let motivo = motivoSoloLectura(f, col) {
            sesion.aviso = Aviso(motivo, estado: .atencion)
            return
        }
        if let error = await guardar(f, col, valor: fecha.map { .text($0.description) }) {
            sesion.aviso = Aviso(error, estado: .atencion)
        }
    }

    // MARK: Crear (§4.8)

    /// Por qué no se puede crear aquí (`nil` = se puede).
    var motivoSinCrear: String? {
        if coleccion.plantilla == nil { return coleccion.motivoSinCrear ?? "Esta base no se crea desde aquí." }
        if !sesion.puedeEscribir { return sesionMotivoSoloLectura }
        return nil
    }

    /// Abre «Nueva …» ya rellena con la pestaña, los filtros de una opción, el contexto y lo que se pase.
    func abrirNueva(poner extra: [String: String] = [:]) {
        guard motivoSinCrear == nil else {
            if let m = motivoSinCrear { sesion.aviso = Aviso(m, estado: .atencion) }
            return
        }
        var p = PeticionNueva()
        if let id = config.pestana, let pestana = datos?.pestanas.first(where: { $0.id == id }),
           case .valores(let clave, let vs) = pestana.filtro, vs.count >= 1, !clave.hasPrefix("_") {
            p.poner[clave] = vs[0]
        }
        for f in config.filtros where f.condicion == .es && f.valores.count == 1 {
            if let col = coleccion.columna(f.clave), [.opcion, .persona, .texto].contains(col.tipo) { p.poner[f.clave] = f.valores[0] }
        }
        if let contexto, let tipo = sesion.resumen(de: contexto)?.kind,
           let papel = PapelesNueva.papel(de: tipo) {
            p.contexto[papel] = contexto
        }
        for (k, v) in extra { p.poner[k] = v }
        nueva = p
    }

    // MARK: Abrir

    func abrir(_ f: FilaBase, modo: ModoApertura = .automatico, navegar: NavegarAccion) {
        navegar(f.destino(en: sesion), modo: modo)
    }

    func vistaPrevia(_ f: FilaBase?) {
        guard let f, !sesion.esPrivado(f.rutaVistaPrevia) else { nav?.vistaPrevia = nil; return }
        nav?.vistaPrevia = nav?.vistaPrevia == f.rutaVistaPrevia ? nil : f.rutaVistaPrevia
    }
}

/// Papel con el que una ficha entra en la plantilla («empresa», «oportunidad»…).
enum PapelesNueva {
    static func papel(de tipo: NoteKind) -> String? {
        switch tipo {
        case .organization: "empresa"
        case .contact: "contacto"
        case .opportunity: "oportunidad"
        case .project: "proyecto"
        case .service: "servicio"
        case .invoice: "factura"
        case .system: "sistema"
        case .content: "contenido"
        default: nil
        }
    }

    /// Base de la que se elige cada pregunta de relación de una plantilla.
    static let baseDePregunta: [String: String] = [
        "contacto": "contactos", "empresa": "empresas", "servicio": "servicios", "oportunidad": "oportunidades",
        "proyecto": "proyectos", "factura": "facturas", "sistema": "sistemas", "contenido": "contenidos",
    ]
}

/// Lo que se arrastra en el tablero, el calendario y la semana de una base, y en el tablero de un proyecto:
/// «tls-fila:<empresa>:<id>». Al soltar solo se acepta lo de la misma empresa: dos empresas con la misma
/// estructura (el ejemplo y su copia) tienen los mismos ids y se movería la ficha de la otra.
enum ArrastreFila {
    static let prefijo = "tls-fila:"

    static func texto(_ id: String, empresa: UUID) -> String { prefijo + empresa.uuidString + ":" + id }

    /// El id, si `texto` es un arrastre de `empresa`.
    static func id(_ texto: String, empresa: UUID) -> String? {
        let cabeza = prefijo + empresa.uuidString + ":"
        guard texto.hasPrefix(cabeza) else { return nil }
        return String(texto.dropFirst(cabeza.count))
    }
}
