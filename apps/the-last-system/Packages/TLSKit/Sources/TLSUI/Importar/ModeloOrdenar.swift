import Foundation
import Observation
import TLSCore
import TLSDesign
import TLSImport

// F3 · rol ordenar. El paso 2 de la puesta en marcha, «Ordenar lo que tienes» (PLAN §6.7 y §9 F3, criterios 1 y 4),
// sobre el importador del núcleo (TLSImport/Importar). Todo lo de aquí **lee** hasta «Aplicar»: el inventario, la
// zona de preparación, la ayuda de Claude y la vista previa. «Aplicar» escribe un solo plan por `CommandBus`, como la
// persona, lo comprueba por recuento y SHA-256 y se deshace de una vez. Lo que la persona decide se guarda en el estado
// de la app (`<estado>/ordenar/borrador.json`, nunca en la carpeta de la empresa) para retomarlo tras «Seguir más tarde».

/// Qué pide la carpeta: completar una ya organizada (G3) u ordenar una que no lo está.
public enum RutaOrdenar: String, Sendable, Codable, Hashable {
    /// Tu carpeta ya está organizada: completar las fichas, los movimientos del banco y la calidad.
    case completar
    /// Tu carpeta, por ordenar: lo que hay, preparar, por programa, repetidos, vista previa, comprobación y calidad.
    case ordenar
}

/// Las pantallas del paso 2. El texto es también el título que guarda la puesta en marcha (`ResumenOrdenar.titulos`).
public enum PantallaOrdenar: String, CaseIterable, Sendable, Hashable {
    case loQueHay = "Lo que hay"
    case preparar = "Preparar"
    case porPrograma = "Por programa"
    case repetidos = "Repetidos"
    case vistaPrevia = "Vista previa"
    case comprobacion = "Comprobación"
    case calidad = "Calidad"
    case completarFichas = "Completar las fichas"
    case banco = "Movimientos del banco"

    public var titulo: String { rawValue }

    /// La explicación de arriba: dos o tres líneas, sin jerga (la misma que enseña la cabecera de la puesta en marcha,
    /// `ResumenOrdenar.explicacionesPorTitulo`).
    public var explicacion: String { ResumenOrdenar.explicacion(rawValue) ?? "" }
}

/// Lo que quedó al aplicar (se guarda para retomarlo y para «Deshacer» tras cerrar la app).
public struct HechoOrdenar: Codable, Sendable, Hashable {
    public var mover: Int
    public var propiedades: Int
    public var archivar: Int
    public var resumen: String
    public var verificados: Int
    public var total: Int
    public var sinDiferencias: Bool
    public var textoVerificacion: String
    public var diferencias: Int
    public var informe: String
    /// Mapa guardado (en el estado de la app), para quitarlo si se deshace.
    public var mapa: String?
    public var fecha: Date
}

/// Una fuente de fuera guardada en el borrador.
struct FuenteGuardada: Codable, Hashable {
    var alias: String
    var ruta: String
}

/// Un cambio de la persona en la zona de preparación. El borrador los guarda en orden y, al retomar, los vuelve a
/// aplicar sobre un inventario nuevo. Lo privado se guarda como huella SHA-256 (nunca su nombre).
enum OperacionZona: Codable, Hashable {
    case coleccion(bloque: String, clave: String)
    case coleccionFichero(clave: String, coleccion: String)
    case privado(huella: String)
    case privadoFichero(huella: String)
    case fuera(bloque: String, Bool)
    case fueraFichero(clave: String, Bool)
    case alcance(HerramientaOrigen, AlcanceImportacion)
    case quedarse(clave: String, grupo: String)
    case ia([String: PropuestaDestino])

    var esPrivado: Bool {
        switch self {
        case .privado, .privadoFichero: true
        default: false
        }
    }
}

/// `<estado>/ordenar/borrador.json`.
struct BorradorOrdenar: Codable {
    var version = 1
    var externas: [FuenteGuardada] = []
    var operaciones: [OperacionZona] = []
    var hecho: HechoOrdenar?
    var planes: [UUID] = []
    var tareasCreadas: [String] = []
    var heredadosCargados = false
}

/// Un bloque de la zona, listo para enseñar: adónde va la mayoría, por qué y cuántos son dudosos.
public struct ResumenBloque: Identifiable, Sendable, Hashable {
    public let bloque: ZonaPreparacion.Bloque
    public var id: String { bloque.id }
    /// Clave de `ColeccionV2` adonde va la mayoría (`nil` si se queda donde está).
    public let coleccion: String?
    public let motivo: String
    public let confianza: Double
    public let dudosos: Int
    public let fuera: Int
    public let elegidoPorTi: Bool
    public let segunClaude: Bool
    /// Todo el bloque está ya en su sitio (no se mueve nada; como mucho se completan fichas).
    public let enSuSitio: Bool

    public var dudoso: Bool { confianza < AIClassifier.umbral }
}

/// Un fichero de un bloque (para verlo uno a uno si se pide).
public struct FilaFichero: Identifiable, Sendable, Hashable {
    public let elemento: ElementoInventario
    public let propuesta: PropuestaDestino?
    public let fuera: Bool
    public var id: String { elemento.clave }
}

/// El modelo de «Ordenar lo que tienes».
@MainActor
@Observable
public final class ModeloOrdenar {
    /// Lo que está pasando ahora (para el progreso y para no pulsar dos veces).
    public enum Trabajo: Equatable, Sendable {
        case mirando
        case preparando
        case aplicando
        case deshaciendo
        case preguntandoAClaude
        case revisando
        case escribiendo

        public var texto: String {
            switch self {
            case .mirando: "Miro lo que tienes…"
            case .preparando: "Preparo la vista previa…"
            case .aplicando: "Aplico: muevo, completo y vuelvo a comprobar cada fichero…"
            case .deshaciendo: "Lo dejo todo como estaba…"
            case .preguntandoAClaude: "Le pregunto a Claude por los dudosos…"
            case .revisando: "Reviso la calidad…"
            case .escribiendo: "Escribo…"
            }
        }
    }

    public private(set) var acceso: AccesoEmpresa
    public let ruta: RutaOrdenar
    public let hoy: LocalDate
    /// Reconocimiento de texto para fechar escaneos (Vision). En pruebas, `nil` o uno falso.
    @ObservationIgnored public var ocr: (any ReconocedorDeTexto)? = OCRService()
    /// Claude Code para «Ayúdame con los dudosos». `nil`: no hay Claude o la persona no dio su consentimiento.
    public var ejecutorIA: (any EjecutorClasificacion)?

    public private(set) var externas: [FuenteImportacion] = []
    public private(set) var inventario: InventarioImportacion?
    public private(set) var zona: ZonaPreparacion?
    public private(set) var vista: VistaPreviaImportacion?
    public private(set) var hecho: HechoOrdenar?
    public private(set) var verificacion: ResultadoVerificacion?
    public private(set) var calidad: InformeCalidad?
    public private(set) var heredados: PreparacionHeredada?
    public private(set) var heredadosCargados = false
    public private(set) var tareasCreadas: Set<String> = []
    /// Planes escritos en este paso, en orden (la importación, su anotación, los movimientos heredados, las tareas).
    public private(set) var planes: [UUID] = []
    public private(set) var trabajo: Trabajo?
    /// Ficheros mirados hasta ahora (mientras se hace el inventario).
    public private(set) var contador = 0
    public private(set) var puedeDeshacer = false
    /// Lo último que salió bien («Hecho: …»), en llano.
    public private(set) var hechoTexto: String?
    /// Lo último que salió mal, en llano.
    public var error: String?
    /// Lo que contó la ayuda de Claude.
    public private(set) var textoIA: String?
    /// Solo se mira (repasar la puesta en marcha del ejemplo): nada se escribe.
    public var soloMirar = false
    /// La persona acepta que algunos enlaces dejen de apuntar a su nota (los ve en la vista previa).
    public var aceptarEnlacesEnRiesgo = false
    public private(set) var arrancado = false
    /// Se deshizo lo aplicado en esta sesión (la puesta en marcha vuelve a dejar el paso pendiente).
    public private(set) var deshizo = false

    @ObservationIgnored private var operaciones: [OperacionZona] = []
    @ObservationIgnored private var pararEnCurso: (() -> Void)?
    @ObservationIgnored private var cancelado = false

    public init(acceso: AccesoEmpresa, ruta: RutaOrdenar, hoy: LocalDate) {
        self.acceso = acceso
        self.ruta = ruta
        self.hoy = hoy
    }

    /// Pasa a escribir por otra vía (p. ej., la empresa se ha abierto en una ventana: mejor por su sesión).
    public func cambiarAcceso(_ nuevo: AccesoEmpresa) {
        guard nuevo.entry.id == acceso.entry.id else { return }
        acceso = nuevo
    }

    // MARK: Pantallas

    /// Las pantallas del paso en esta carpeta (los repetidos solo si los hay).
    public var pantallas: [PantallaOrdenar] {
        switch ruta {
        case .completar: return [.completarFichas, .banco, .calidad]
        case .ordenar:
            var p: [PantallaOrdenar] = [.loQueHay, .preparar, .porPrograma]
            if zona == nil || !(zona?.duplicados.isEmpty ?? true) { p.append(.repetidos) }
            return p + [.vistaPrevia, .comprobacion, .calidad]
        }
    }

    /// El resumen para la puesta en marcha (contador de pantallas, «Deshacer» y lo que se hizo).
    public func resumenPuesta() -> ResumenOrdenar {
        let p = pantallas
        let texto: String
        if let hecho { texto = hecho.textoVerificacion }
        else if heredadosCargados || !tareasCreadas.isEmpty { texto = "Sin nada que mover; lo demás, hecho" }
        else { texto = "Nada que ordenar: todo estaba en su sitio" }
        return ResumenOrdenar(pantallas: p.count, titulos: p.map(\.titulo), movidos: hecho?.mover ?? 0,
                              completadas: hecho?.propiedades ?? 0, archivados: hecho?.archivar ?? 0,
                              verificados: hecho?.verificados ?? 0, planes: planes, texto: texto,
                              explicaciones: p.map(\.explicacion))
    }

    /// Hay algo escrito por este paso.
    public var aplicado: Bool { !planes.isEmpty }

    /// Cambia cuando cambia algo que la puesta en marcha tiene que saber (pantallas, planes, si hay algo que aplicar).
    public var firmaPuesta: String {
        let v = vista.map { $0.hayCambios ? "cambios" : "nada" } ?? "sin-vista"
        return pantallas.map(\.rawValue).joined(separator: "|") + "#" + planes.map(\.uuidString).joined(separator: ",") + "#" + v
            + (deshizo ? "#deshecho" : "")
    }

    /// Ya no hay vuelta atrás en la zona: se aplicó (para cambiarlo, primero «Deshacer»).
    public var cerrado: Bool { hecho != nil }

    // MARK: Arrancar y retomar

    /// Lee el borrador (si lo hay) y, si aún no se ha aplicado nada, hace el inventario y repite lo que decidió la persona.
    public func arrancar() async {
        guard !arrancado else { return }
        arrancado = true
        if let b = leerBorrador() {
            externas = b.externas.compactMap { f in
                FileManager.default.fileExists(atPath: f.ruta)
                    ? FuenteImportacion(alias: f.alias, raiz: URL(fileURLWithPath: f.ruta, isDirectory: true), clase: .externa) : nil
            }
            operaciones = b.operaciones
            hecho = b.hecho
            planes = b.planes
            tareasCreadas = Set(b.tareasCreadas)
            heredadosCargados = b.heredadosCargados
        }
        if !planes.isEmpty { puedeDeshacer = await acceso.sePuedeDeshacer(planes: planes) }
        if hecho == nil { await mirar() }
    }

    /// Hace (o rehace) el inventario de la carpeta de la empresa y de las de fuera. Solo lee.
    public func mirar() async {
        guard trabajo == nil else { return }
        trabajo = .mirando
        contador = 0
        error = nil
        let fuentes = [fuenteDeLaEmpresa] + (ruta == .ordenar ? externas : [])
        let hoy = self.hoy
        let progreso: @Sendable (Int) -> Void = { [weak self] n in Task { @MainActor in self?.contador = n } }
        let t = Task.detached(priority: .userInitiated) { () -> Result<InventarioImportacion, Error> in
            do {
                return .success(try await InventarioImportacion.hacer(fuentes, opciones: .init(hoy: hoy), progreso: progreso))
            } catch {
                return .failure(error)
            }
        }
        pararEnCurso = { t.cancel() }
        let r = await t.value
        pararEnCurso = nil
        trabajo = nil
        switch r {
        case .success(let inv):
            inventario = inv
            rehacerZona()
        case .failure(let e):
            error = e is CancellationError ? "Lo he parado: no se ha cambiado nada." : Self.texto(e)
        }
    }

    /// La carpeta de la empresa como fuente: se ordena por dentro (se mueve). Lo privado y lo dejado fuera de la copia no
    /// se listan. Lo dejado fuera apunta a la carpeta real: en la copia solo cuenta lo que existe (y nunca `Archivo/`).
    var fuenteDeLaEmpresa: FuenteImportacion {
        let layout = VaultLayout.load(root: acceso.raiz).layout
        return .carpetaDeLaEmpresa(acceso.raiz, privado: layout.privado, exclusiones: exclusionesDeLaCopia(layout))
    }

    func exclusionesDeLaCopia(_ layout: VaultLayout) -> [VaultPath] {
        FuenteImportacion.exclusionesDeLaCopia(acceso.entry.exclusionesCopia.map { VaultPath($0) }, raiz: acceso.raiz,
                                               archivo: layout.archivo)
    }

    /// Para el inventario o la vista previa en curso (nunca a mitad de escribir: eso lo hace `cancelarAplicar`).
    public func parar() {
        pararEnCurso?()
    }

    // MARK: Carpetas de fuera

    /// Añade una carpeta de fuera (una exportación de Notion, una carpeta de Drive…): se lee y lo elegido se copia; el
    /// original no cambia.
    public func anadirFuera(_ url: URL) async {
        let base = NombresDeFicha.fichero(url.lastPathComponent).isEmpty ? "Fuera" : NombresDeFicha.fichero(url.lastPathComponent)
        var alias = base
        var n = 2
        let usados = Set(([FuenteImportacion.aliasDeLaEmpresa] + externas.map(\.alias)).map { $0.lowercased() })
        while usados.contains(alias.lowercased()) { alias = "\(base) \(n)"; n += 1 }
        externas.append(FuenteImportacion(alias: alias, raiz: url.standardizedFileURL, clase: .externa))
        guardarBorrador()
        await mirar()
        if error != nil {
            externas.removeAll { $0.alias == alias }
            guardarBorrador()
        }
    }

    public func quitarFuera(_ alias: String) async {
        externas.removeAll { $0.alias == alias }
        operaciones.removeAll { op in
            switch op {
            case .coleccion(let b, _), .fuera(let b, _): b.hasPrefix(alias + "/")
            case .coleccionFichero(let c, _), .fueraFichero(let c, _), .quedarse(let c, _): c.hasPrefix(alias + "/")
            default: false
            }
        }
        guardarBorrador()
        await mirar()
    }

    // MARK: Lo que hay

    /// «1.240 ficheros · 310 solo en iCloud: los miro por su nombre».
    public var textoInventario: String {
        guard let inv = inventario else { return "" }
        var s = TLSFormat.cuenta(inv.elementos.count, "fichero", "ficheros")
        if inv.soloEnICloud > 0 { s += " · \(TLSFormat.entero(inv.soloEnICloud)) solo en iCloud: los miro por su nombre" }
        return s
    }

    public var porHerramienta: [(HerramientaOrigen, Recuento)] {
        (inventario?.porHerramienta ?? [:]).sorted { ($0.value.ficheros, $1.key) > ($1.value.ficheros, $0.key) }
            .map { ($0.key, $0.value) }
    }

    public var porTipo: [(TipoDocumento, Recuento)] {
        (inventario?.porTipo ?? [:]).sorted { ($0.value.ficheros, $1.key) > ($1.value.ficheros, $0.key) }
            .map { ($0.key, $0.value) }
    }

    // MARK: Zona de preparación

    /// Los bloques, con su destino principal, su motivo y su confianza.
    public var bloques: [ResumenBloque] {
        guard let zona else { return [] }
        return zona.bloques.map { b in
            var cuenta: [String: Int] = [:]
            var motivos: [String: [String: Int]] = [:]
            var suma = 0.0
            var dudosos = 0
            var fuera = 0
            var tuyo = false
            var claude = false
            var enSitio = zona.inventario.fuente(b.fuente)?.clase == .carpetaDeLaEmpresa
            for c in b.claves {
                let p = zona.propuestas[c]
                if !(p?.enSuSitio == true || p?.destino == nil) { enSitio = false }
                let col = p?.coleccion ?? ""
                cuenta[col, default: 0] += 1
                if let m = p?.motivo { motivos[col, default: [:]][m, default: 0] += 1 }
                suma += p?.confianza ?? 0
                if (p?.confianza ?? 0) < AIClassifier.umbral, p?.enSuSitio != true { dudosos += 1 }
                if zona.ajustes[c]?.fuera == true { fuera += 1 }
                if p?.origen == .persona { tuyo = true }
                if p?.origen == .ia { claude = true }
            }
            let principal = cuenta.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.first?.key ?? ""
            let motivo = motivos[principal]?.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.first?.key ?? ""
            return ResumenBloque(bloque: b, coleccion: principal.isEmpty ? nil : principal, motivo: motivo,
                                 confianza: b.claves.isEmpty ? 0 : suma / Double(b.claves.count), dudosos: dudosos,
                                 fuera: fuera, elegidoPorTi: tuyo, segunClaude: claude, enSuSitio: enSitio && !tuyo)
        }
    }

    /// Los ficheros de un bloque, uno a uno.
    public func ficheros(de bloque: String) -> [FilaFichero] {
        guard let zona, let b = zona.bloques.first(where: { $0.id == bloque }) else { return [] }
        return b.claves.compactMap { c in
            zona.inventario.elemento(c).map { FilaFichero(elemento: $0, propuesta: zona.propuestas[c], fuera: zona.ajustes[c]?.fuera == true) }
        }
    }

    /// Ficheros marcados como privados en esta zona (no se ven; se pueden volver a ver).
    public var privadosEnLaZona: Int {
        guard let zona else { return 0 }
        return zona.inventario.elementos.count - zona.visibles.count
    }

    /// Lo que se le puede preguntar a Claude (poca confianza, nada privado ni con claves).
    public var dudosos: Int { zona?.candidatosIA().count ?? 0 }

    public func cambiarColeccion(bloque: String, a coleccion: String) { cambiar(.coleccion(bloque: bloque, clave: coleccion)) }

    public func cambiarColeccion(fichero clave: String, a coleccion: String) {
        cambiar(.coleccionFichero(clave: clave, coleccion: coleccion))
    }

    public func marcarPrivado(bloque: String) { cambiar(.privado(huella: ContentHash.of(bloque))) }

    public func marcarPrivado(fichero clave: String) { cambiar(.privadoFichero(huella: ContentHash.of(clave))) }

    /// Vuelve a enseñar lo marcado como privado en esta zona.
    public func volverAVerPrivados() {
        operaciones.removeAll(where: \.esPrivado)
        rehacerZona()
        guardarBorrador()
    }

    public func dejarFuera(bloque: String, _ fuera: Bool = true) { cambiar(.fuera(bloque: bloque, fuera)) }

    public func dejarFuera(fichero clave: String, _ fuera: Bool = true) { cambiar(.fueraFichero(clave: clave, fuera)) }

    public func fijarAlcance(_ h: HerramientaOrigen, _ a: AlcanceImportacion) { cambiar(.alcance(h, a)) }

    public func quedarseCon(_ clave: String, enGrupo grupo: String) { cambiar(.quedarse(clave: clave, grupo: grupo)) }

    /// La fecha de corte propuesta para «lo activo»: el 1 de enero del año pasado.
    public var corteSugerido: LocalDate { LocalDate(year: hoy.year - 1, month: 1, day: 1) ?? hoy }

    /// «Ayúdame con los dudosos»: solo si hay Claude y la persona lo acaba de aceptar (`consentimiento`). Nunca lo
    /// privado ni lo que lleva claves; por lotes y con su esquema; la ruta la calcula la app.
    public func ayudaConLosDudosos(consentimiento: Bool) async {
        guard consentimiento, let ejecutorIA, let zona, trabajo == nil, !cerrado else { return }
        trabajo = .preguntandoAClaude
        error = nil
        let r = await AIClassifier(ejecutor: ejecutorIA, consentimiento: true).clasificar(zona)
        trabajo = nil
        if !r.propuestas.isEmpty { cambiar(.ia(r.propuestas)) }
        var t = r.usada ? "Claude ha propuesto sitio para \(TLSFormat.cuenta(r.propuestas.count, "fichero dudoso", "ficheros dudosos"))"
            : "No había nada dudoso que preguntar"
        if r.propuestas.isEmpty, r.usada { t = "Claude no ha propuesto nada mejor: sigo con mis reglas" }
        textoIA = t + "."
        if let a = r.avisos.first { error = a }
    }

    private func cambiar(_ op: OperacionZona) {
        guard zona != nil, !cerrado else { return }
        operaciones.append(op)
        if var z = zona {
            aplicar(op, a: &z)
            zona = z
        }
        vista = nil
        aceptarEnlacesEnRiesgo = false
        guardarBorrador()
    }

    /// Zona nueva sobre el inventario y lo que decidió la persona, en orden.
    private func rehacerZona() {
        guard let inv = inventario else { zona = nil; return }
        let layout = VaultLayout.load(root: acceso.raiz).layout
        var z = ZonaPreparacion(inventario: inv, layout: layout, hoy: hoy)
        for op in operaciones { aplicar(op, a: &z) }
        zona = z
        vista = nil
    }

    private func aplicar(_ op: OperacionZona, a z: inout ZonaPreparacion) {
        switch op {
        case .coleccion(let b, let c):
            z.cambiarColeccion(bloque: b, a: c)
        case .coleccionFichero(let clave, let c):
            guard let e = z.inventario.elemento(clave) else { return }
            let p = z.clasificador.propuesta(e, coleccion: c, confianza: 1, motivo: "Lo has elegido tú", pistaEnCarpeta: nil,
                                             origen: .persona)
            if let d = p.destino { try? z.cambiarDestino(clave, a: d) }
        case .privado(let h):
            for b in z.bloques where ContentHash.of(b.id) == h { z.marcarPrivado(bloque: b.id) }
        case .privadoFichero(let h):
            for e in z.inventario.elementos where ContentHash.of(e.clave) == h { z.marcarPrivado(e.clave) }
        case .fuera(let b, let si):
            z.dejarFuera(bloque: b, si)
        case .fueraFichero(let c, let si):
            z.dejarFuera(c, si)
        case .alcance(let h, let a):
            z.fijarAlcance(h, a)
        case .quedarse(let c, let g):
            z.quedarseCon(c, enGrupo: g)
        case .ia(let p):
            z.incorporar(p)
        }
    }

    // MARK: Vista previa

    /// Prepara la vista previa (solo lee: no escribe nada en ningún sitio).
    public func prepararVista() async {
        guard let zona, trabajo == nil, !cerrado else { return }
        trabajo = .preparando
        error = nil
        let applier = ImportApplier(carpeta: acceso.raiz, opciones: opcionesAplicar)
        let t = Task.detached(priority: .userInitiated) { () -> Result<VistaPreviaImportacion, Error> in
            do { return .success(try await applier.preparar(zona)) } catch { return .failure(error) }
        }
        pararEnCurso = { t.cancel() }
        let r = await t.value
        pararEnCurso = nil
        trabajo = nil
        switch r {
        case .success(let v): vista = v
        case .failure(let e): error = e is CancellationError ? "Lo he parado: no se ha cambiado nada." : Self.texto(e)
        }
    }

    var opcionesAplicar: ImportApplier.Opciones {
        ImportApplier.Opciones(autor: acceso.autor, hoy: hoy, ocr: ocr)
    }

    /// Por qué no se puede escribir nada ahora (repasando o en solo lectura), o `nil`.
    public var motivoNoEscribir: String? {
        if soloMirar { return "Repasando: aquí solo se mira" }
        return acceso.motivoSoloLectura.map { "No se puede escribir: \($0)" }
    }

    /// Lo que se puede decir antes de aplicar: por qué no se puede, o `nil`.
    public var motivoNoAplicar: String? {
        if let m = motivoNoEscribir { return m }
        guard let vista else { return "Falta preparar la vista previa" }
        if !vista.hayCambios { return "No hay nada que mover, completar ni archivar" }
        if !vista.enlacesEnRiesgo.isEmpty, !aceptarEnlacesEnRiesgo {
            return TLSFormat.cuenta(vista.enlacesEnRiesgo.count, "enlace dejaría", "enlaces dejarían") + " de apuntar a su nota: revísalos"
        }
        return nil
    }

    // MARK: Aplicar, cancelar y deshacer

    /// «Aplicar»: un plan, como la persona, con las reglas apagadas; después se comprueba todo (recuento y SHA-256).
    /// Si se cancela antes de escribir, no se escribe nada; si ya se escribió, se deshace entero.
    public func aplicar() async {
        guard let vista, trabajo == nil, motivoNoAplicar == nil else { return }
        trabajo = .aplicando
        cancelado = false
        error = nil
        hechoTexto = nil
        let applier = ImportApplier(carpeta: acceso.raiz, opciones: opcionesAplicar)
        let aceptar = aceptarEnlacesEnRiesgo
        let acceso = self.acceso
        let t = Task { @MainActor () -> Result<ResultadoImportacion, Error> in
            do {
                return .success(try await acceso.conBus { bus, motor in
                    try await applier.aplicar(vista, con: bus, motor: motor, aceptarEnlacesEnRiesgo: aceptar)
                })
            } catch {
                return .failure(error)
            }
        }
        pararEnCurso = { t.cancel() }
        let r = await t.value
        pararEnCurso = nil
        switch r {
        case .success(let res):
            if cancelado {
                trabajo = .deshaciendo
                do {
                    try await acceso.deshacer(planes: res.planes)
                    hechoTexto = "Cancelado: lo he dejado todo como estaba."
                } catch {
                    planes += res.planes
                    registrar(res, vista: vista)
                    self.error = "Ya estaba escrito y no he podido deshacerlo: " + Self.texto(error)
                }
            } else {
                planes += res.planes
                registrar(res, vista: vista)
                acceso.movidos(res.escritura.movidas)
                // La comprobación se enseña en su pantalla («312 de 312»): aquí no se repite.
                hechoTexto = nil
                if !res.verificacion.sinDiferencias { error = ImportError.verificacionFallida(res.verificacion.diferencias.count).errorDescription }
            }
        case .failure(let e):
            if e is CancellationError || cancelado {
                hechoTexto = "Cancelado antes de escribir: no se ha cambiado nada."
            } else {
                error = Self.texto(e)
            }
        }
        trabajo = nil
        puedeDeshacer = await acceso.sePuedeDeshacer(planes: planes)
        guardarBorrador()
    }

    /// «Cancelar» mientras se aplica: seguro (o no se escribe nada, o se deshace lo escrito).
    public func cancelarAplicar() {
        guard trabajo == .aplicando else { return }
        cancelado = true
        pararEnCurso?()
    }

    private func registrar(_ res: ResultadoImportacion, vista: VistaPreviaImportacion) {
        verificacion = res.verificacion
        // El mapa va al estado de la app (lo usa «Actualizar la copia desde la real»), nunca a la carpeta de la empresa.
        let nombre = "importacion-\(hoy.description)-\(res.escritura.planID.uuidString.prefix(8).lowercased())"
        let mapa = try? res.mapa.guardar(en: acceso.estado, nombre: nombre)
        hecho = HechoOrdenar(mover: vista.mover, propiedades: vista.propiedades, archivar: vista.archivar, resumen: vista.resumen,
                             verificados: res.verificacion.comprobados, total: res.verificacion.total,
                             sinDiferencias: res.verificacion.sinDiferencias, textoVerificacion: res.verificacion.texto,
                             diferencias: res.verificacion.diferencias.count, informe: res.informe.raw, mapa: mapa?.path,
                             fecha: Date())
    }

    /// «Deshacer»: todo lo de este paso, de una vez (si nada se ha escrito después). Lo creado va al Archivo.
    public func deshacer() async {
        guard !planes.isEmpty, trabajo == nil, !soloMirar else { return }
        trabajo = .deshaciendo
        error = nil
        hechoTexto = nil
        do {
            try await acceso.deshacer(planes: planes)
            if let m = hecho?.mapa { try? FileManager.default.removeItem(atPath: m) }
            planes = []
            hecho = nil
            verificacion = nil
            vista = nil
            tareasCreadas = []
            heredadosCargados = false
            calidad = nil
            heredados = nil
            hechoTexto = "Deshecho: la carpeta está como antes."
            deshizo = true
            trabajo = nil
            guardarBorrador()
            if inventario == nil || ruta == .completar { await mirar() } else { rehacerZona() }
        } catch {
            trabajo = nil
            self.error = Self.texto(error)
        }
        puedeDeshacer = await acceso.sePuedeDeshacer(planes: planes)
    }

    /// Al cambiar de pantalla: lo último hecho o fallado ya no viene a cuento.
    public func olvidarAvisos() {
        guard trabajo == nil else { return }
        hechoTexto = nil
        error = nil
    }

    public func comprobarDeshacer() async {
        puedeDeshacer = await acceso.sePuedeDeshacer(planes: planes)
    }

    // MARK: Movimientos del banco (los heredados de `Registros/importar/`)

    public func prepararHeredados() async {
        guard let foto = await acceso.foto() else { return }
        let legado = LegacyMovementsImporter(snapshot: foto)
        heredados = legado.ficheros.isEmpty ? nil : legado.preparar()
    }

    /// Los carga en preparación (ninguno queda confirmado), con las reglas apagadas. Va con «Deshacer» del paso.
    public func cargarHeredados() async {
        guard trabajo == nil, motivoNoEscribir == nil, let foto = await acceso.foto() else { return }
        let prep = LegacyMovementsImporter(snapshot: foto).preparar()
        guard let plan = prep.plan(autor: acceso.autor) else { heredados = prep; return }
        trabajo = .escribiendo
        error = nil
        do {
            let texto = "Cargué " + TLSFormat.cuenta(prep.nuevas.count, "movimiento heredado", "movimientos heredados") + " en preparación"
            let r = try await acceso.escribir(plan: plan, dominio: true, importacion: true, aviso: texto)
            if r.hecho {
                planes.append(r.planID)
                heredadosCargados = true
                hechoTexto = texto + ". Ninguno cuenta como cobrado hasta que lo revises."
            } else {
                error = "Alguien cambió estos registros a la vez. Vuelve a intentarlo."
            }
        } catch {
            self.error = Self.texto(error)
        }
        trabajo = nil
        await prepararHeredados()
        puedeDeshacer = await acceso.sePuedeDeshacer(planes: planes)
        guardarBorrador()
    }

    // MARK: Calidad

    public func revisarCalidad() async {
        guard trabajo == nil else { return }
        trabajo = .revisando
        guard let foto = await acceso.foto() else { trabajo = nil; return }
        let raiz = acceso.raiz
        let privado = foto.layout.privado + exclusionesDeLaCopia(foto.layout)
        let huellas = try? await Inventory.make(of: raiz, exclusiones: privado)
        calidad = InformeCalidad.revisar(snapshot: foto, huellas: huellas, ignorados: InformeCalidad.ignorados(estado: acceso.estado))
        trabajo = nil
    }

    /// «Crear tarea»: una ficha de tarea en el área del aviso, como cualquier tarea nueva.
    public func crearTarea(_ aviso: AvisoCalidad) async {
        guard trabajo == nil, motivoNoEscribir == nil, !tareasCreadas.contains(aviso.id), let foto = await acceso.foto() else { return }
        trabajo = .escribiendo
        error = nil
        do {
            let plan = try InformeCalidad.crearTarea(aviso, snapshot: foto, reloj: Reloj.deCarpeta(foto), autor: acceso.autor)
            let r = try await acceso.escribir(plan: plan, aviso: "Tarea creada para revisarlo")
            if r.hecho {
                planes.append(r.planID)
                tareasCreadas.insert(aviso.id)
                hechoTexto = "Tarea creada: la tienes en Tareas."
            }
        } catch {
            self.error = Self.texto(error)
        }
        trabajo = nil
        puedeDeshacer = await acceso.sePuedeDeshacer(planes: planes)
        guardarBorrador()
    }

    /// «Poner fecha…» de un documento sin fecha: una fila `manual` en «Fechas de documentos» (va con «Deshacer» del paso).
    public func ponerFecha(_ aviso: AvisoCalidad, fecha: LocalDate) async {
        guard trabajo == nil, motivoNoEscribir == nil, aviso.tipo == .sinFecha, let foto = await acceso.foto() else { return }
        trabajo = .escribiendo
        error = nil
        do {
            let plan = try InformeCalidad.ponerFecha(aviso, fecha: fecha, snapshot: foto, autor: acceso.autor)
            let r = try await acceso.escribir(plan: plan, aviso: "Fecha puesta")
            if r.hecho {
                planes.append(r.planID)
                hechoTexto = "Fecha puesta: \(TLSFormat.fecha(fecha.date()))."
                if let c = calidad { calidad = InformeCalidad(avisos: c.avisos.filter { $0.id != aviso.id }) }
            } else {
                error = "Alguien cambió «Fechas de documentos» a la vez. Vuelve a intentarlo."
            }
        } catch {
            self.error = Self.texto(error)
        }
        trabajo = nil
        puedeDeshacer = await acceso.sePuedeDeshacer(planes: planes)
        guardarBorrador()
    }

    /// «Ignorar»: se apunta en el estado de la app (nunca en la carpeta) y deja de salir.
    public func ignorar(_ aviso: AvisoCalidad) {
        do {
            try InformeCalidad.ignorar(aviso, estado: try acceso.carpetaEstado())
            if let c = calidad { calidad = InformeCalidad(avisos: c.avisos.filter { $0.id != aviso.id }) }
        } catch {
            self.error = Self.texto(error)
        }
    }

    // MARK: Borrador (estado de la app)

    var urlBorrador: URL { acceso.estado.appendingPathComponent("ordenar", isDirectory: true).appendingPathComponent("borrador.json") }

    private func leerBorrador() -> BorradorOrdenar? {
        guard let d = try? Data(contentsOf: urlBorrador) else { return nil }
        return try? JSONDecoder().decode(BorradorOrdenar.self, from: d)
    }

    private func guardarBorrador() {
        let b = BorradorOrdenar(externas: externas.map { FuenteGuardada(alias: $0.alias, ruta: $0.raiz.path) },
                                operaciones: operaciones, hecho: hecho, planes: planes, tareasCreadas: tareasCreadas.sorted(),
                                heredadosCargados: heredadosCargados)
        do {
            _ = try acceso.carpetaEstado("ordenar")
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(b).write(to: urlBorrador, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: urlBorrador.path)
        } catch {
            // El borrador es una comodidad: si no se puede guardar, todo sigue funcionando (solo no se retoma).
        }
    }

    // MARK: Textos

    static func texto(_ e: Error) -> String {
        (e as? LocalizedError)?.errorDescription ?? "No he podido hacerlo. No se ha cambiado nada."
    }

    /// Nombre de un tipo de ficha para la persona («contacto», «empresa»…).
    public static func nombreDeTipo(_ t: String) -> String {
        let nombres = ["contact": "contacto", "organization": "empresa", "opportunity": "oportunidad", "service": "servicio",
                       "offer": "oferta", "project": "proyecto", "delivery_template": "plan de entrega", "meeting": "reunión",
                       "decision": "decisión", "objective": "objetivo", "content": "contenido", "conversation": "conversación",
                       "role": "rol", "collaboration": "colaboración", "invoice": "factura", "receipt": "recibo",
                       "proposal": "propuesta", "quote": "presupuesto", "agreement": "contrato", "task": "tarea"]
        return nombres[t] ?? "ficha"
    }

    /// El tipo de ficha que tomará un fichero: el de su propuesta o, si se queda donde está, el de la colección de su carpeta.
    public func tipoDeFicha(_ clave: String) -> String? {
        if let t = zona?.propuestas[clave]?.tipoFicha { return t }
        guard let zona, let e = zona.inventario.elemento(clave) else { return nil }
        let k = TextFolding.pathKey(e.ruta.raw)
        for c in ColeccionV2.catalogo where c.tipoFicha != nil {
            guard let carpeta = Self.carpeta(c, layout: zona.layout) else { continue }
            if k.hasPrefix(TextFolding.pathKey(carpeta.raw) + "/") { return c.tipoFicha }
        }
        return nil
    }

    /// La carpeta de una colección en esta estructura (`{ventas}/Contactos` → `2 · Ventas/Contactos`).
    static func carpeta(_ c: ColeccionV2, layout: VaultLayout) -> VaultPath? {
        var partes = c.carpeta.split(separator: "/").map(String.init)
        guard let primera = partes.first, primera.hasPrefix("{"), primera.hasSuffix("}") else { return VaultPath(c.carpeta) }
        let clave = String(primera.dropFirst().dropLast())
        partes.removeFirst()
        let base: VaultPath
        if clave == "buzon" {
            base = VaultPath(layout.buzon ?? "Buzón")
        } else if let a = AreaCode.allCases.first(where: { $0.tlsArea.rawValue == clave }) {
            base = layout.areaFolder(a)
        } else {
            return nil
        }
        return partes.reduce(base) { $0.appending($1) }
    }

    /// Una ruta para la persona: «2 · Ventas › Contactos › Ana López» (sin «.md»).
    public static func rutaLegible(_ p: VaultPath) -> String {
        let comps = p.components
        guard let ultimo = comps.last else { return "Tu carpeta" }
        let nombre = p.ext == "md" ? p.stem : ultimo
        return (comps.dropLast() + [nombre]).joined(separator: " › ")
    }

    /// Nombre de una colección del catálogo («Ventas › Contactos») o «Se queda donde está».
    public static func nombreColeccion(_ clave: String?) -> String {
        clave.flatMap { ColeccionV2.porClave($0)?.nombre } ?? "Se queda donde está"
    }
}
