import AppKit
import OSLog
import SwiftUI
import TLSDesign

/// El editor de notas (PLAN §6.6): un `NSTextView` de TextKit 2 con la vista previa en vivo de Obsidian.
///
/// - **Texto**: recibe y devuelve el cuerpo tal cual (`cargar`, `texto`, `sustituir`). No reformatea, no
///   sustituye comillas, guiones ni texto, y el corrector va en español. El frontmatter no entra aquí.
/// - **Vista previa en vivo**: el análisis (swift-markdown + lo de Obsidian) va fuera del hilo principal
///   con 120 ms de espera; al llegar solo se repintan las líneas que cambiaron. Las marcas se esconden con
///   atributos sin cambiar la longitud del párrafo, salvo en la línea del cursor; mover el cursor repinta
///   dos líneas.
/// - **Modos**: «Edición en vivo», «Texto fuente» y «Lectura». A partir de 2 MB, solo texto fuente.
/// - **Proveedores**: autocompletado de `[[` y `](`, resolución de enlaces al ⌘clic e incrustaciones.
///
/// Se crea una vez por pantalla y vive lo que ella (la vista de SwiftUI `EditorMarkdown` solo lo enseña).
@MainActor
public final class ControladorEditor: NSObject {
    // MARK: Vistas

    /// La vista que se pone en pantalla (con el texto dentro).
    public let scroll: NSScrollView
    let vista: VistaTextoMarkdown
    private var storage: NSTextStorage { vista.textStorage ?? NSTextStorage() }
    private let disposicion = DelegadoDisposicion()
    /// Deshacer propio del texto (⌘Z de lo tecleado), separado del de la ventana.
    public let deshacer = UndoManager()

    // MARK: Configuración

    public private(set) var modo: ModoEditor
    /// Modo al que vuelve ⌘E desde «Texto fuente».
    public private(set) var modoAnterior: ModoEditor = .vivo
    /// `true` si la nota pasa de 2 MB: solo texto fuente, sin análisis.
    public private(set) var soloFuente = false
    /// Solo lectura (carpeta real, conflicto pendiente, sin permiso de escritura).
    public var soloLectura = false {
        didSet { if soloLectura != oldValue { actualizarEditable() } }
    }
    /// Tamaño del texto (Ajustes › Visualización, 85–200 %).
    public var escala: CGFloat = 1 {
        didSet { if escala != oldValue { tema = TemaEditor(modo: modo, escala: escala); disposicion.escala = tema.escala; reestilarTodo() } }
    }
    /// Ancho máximo de la columna de texto (la nota se centra).
    public var anchoTexto: CGFloat = 700 {
        didSet { if anchoTexto != oldValue { anchoCambiado() } }
    }

    public weak var autocompletado: AutocompletarEnlaces? {
        didSet { sugerencias.proveedor = autocompletado }
    }
    public weak var resolutor: ResolutorEnlaces?
    public weak var incrustaciones: ProveedorIncrustaciones?

    /// Cada cambio del texto hecho por la persona (para el guardado automático). Barato: se llama al teclear.
    public var alCambiarTexto: (@MainActor () -> Void)?
    public var alCambiarModo: (@MainActor (ModoEditor) -> Void)?
    /// La ventana deja de ser la activa o la app pasa a segundo plano (guardar ya).
    public var alPerderFoco: (@MainActor () -> Void)?
    public var alCambiarTitulos: (@MainActor ([TituloNota]) -> Void)?
    public var alDesplazar: (@MainActor (CGFloat) -> Void)?

    // MARK: Estado del análisis

    private var tema: TemaEditor
    /// Último análisis aplicado (corresponde al texto si `versionAnalizada == versionTexto`).
    public private(set) var analisis: AnalisisMarkdown = .vacio
    private var versionTexto = 0
    private var versionAnalizada = 0
    private var tareaAnalisis: Task<Void, Never>?
    /// Espera tras la última tecla antes de analizar.
    public var esperaAnalisis: Duration = .milliseconds(120)
    private var pendientes = RangosVivos()
    private var parrafoCursor: Int?
    private var rangoCursor: NSRange?
    private var aplicandoTexto = false
    private var titulos: [TituloNota] = []

    /// Para las pruebas y los signposts: cuántas líneas se repintaron la última vez.
    public private(set) var repintadasAlMoverCursor = 0
    public private(set) var repintadasUltimoAnalisis = 0
    /// `true` si alguien pasó la vista a TextKit 1 (no debe pasar nunca).
    public private(set) var pasoATextKit1 = false

    static let log = Logger(subsystem: "es.thelast.system", category: "Editor")
    static let signpost = OSSignposter(subsystem: "es.thelast.system", category: "Editor")

    // MARK: Cabecera, incrustaciones y autocompletado

    private var cabecera: NSView?
    private var altoCabecera: CGFloat = 0
    private var marcos: [String: MarcoIncrustacion] = [:]
    private var lineaDeIncrustacion: [String: Int] = [:]
    private var ampliadas: Set<String> = []
    private lazy var sugerencias = ControladorSugerencias(vista: vista)
    nonisolated(unsafe) private var observadores: [NSObjectProtocol] = []
    /// El de «la ventana deja de ser la activa» (uno: se cambia si el editor pasa a otra ventana).
    nonisolated(unsafe) private var observadorVentana: NSObjectProtocol?
    private weak var ventanaObservada: NSWindow?

    // MARK: Crear

    public init(modo: ModoEditor = .vivo, escala: CGFloat = 1) {
        self.modo = modo
        self.escala = escala
        self.tema = TemaEditor(modo: modo, escala: escala)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = TLSPaleta.superficie.ns
        scroll.contentView.postsBoundsChangedNotifications = true

        let tv = VistaTextoMarkdown(usingTextLayoutManager: true)
        tv.frame = NSRect(origin: .zero, size: scroll.contentSize)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.drawsBackground = false
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.usesFontPanel = false
        tv.usesRuler = false
        // Fidelidad con Obsidian: nada cambia el texto por su cuenta.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.insertionPointColor = TLSPaleta.texto.ns
        tv.textContainerInset = NSSize(width: 32, height: 24)
        tv.setAccessibilityLabel("Texto de la nota")
        tv.setAccessibilityIdentifier("editor.texto")
        scroll.documentView = tv
        self.scroll = scroll
        self.vista = tv
        super.init()
        tv.controlador = self
        tv.delegate = self
        tv.textStorage?.delegate = self
        disposicion.escala = tema.escala
        tv.textLayoutManager?.delegate = disposicion
        tv.typingAttributes = atributosEscritura(BloqueLinea())
        Self.corregirEnEspanol()
        observadores.append(NotificationCenter.default.addObserver(
            forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: tv, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pasoATextKit1 = true
                Self.log.fault("El editor ha pasado a TextKit 1: alguien ha tocado .layoutManager")
            }
        })
        observadores.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.desplazado() }
        })
        observadores.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.alPerderFoco?() }
        })
        actualizarEditable()
    }

    deinit {
        for o in observadores { NotificationCenter.default.removeObserver(o) }
        if let o = observadorVentana { NotificationCenter.default.removeObserver(o) }
    }

    /// Corrector en español (una vez por proceso). Si el Mac identifica el idioma solo, ya lo hace.
    private static var corrector = false
    static func corregirEnEspanol() {
        guard !corrector else { return }
        corrector = true
        let sc = NSSpellChecker.shared
        if !sc.automaticallyIdentifiesLanguages, sc.availableLanguages.contains(where: { $0.hasPrefix("es") }) {
            _ = sc.setLanguage("es")
        }
    }

    // MARK: Texto

    /// El cuerpo tal como está ahora en el editor.
    public var texto: String { vista.string }

    /// Carga un texto nuevo (al abrir): sin deshacer previo, con el cursor al principio.
    public func cargar(_ texto: String) {
        tareaAnalisis?.cancel()
        sugerencias.cerrar()
        soloFuente = texto.utf8.count >= AnalizadorMarkdown.limiteBytes
        if soloFuente, modo != .fuente { cambiarModoInterno(.fuente) }
        aplicandoTexto = true
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: texto)
        storage.setAttributes(atributosEscritura(BloqueLinea()), range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        aplicandoTexto = false
        deshacer.removeAllActions()
        versionTexto += 1
        pendientes.vaciar()
        parrafoCursor = nil
        rangoCursor = nil
        analisis = .vacio
        vista.setSelectedRange(NSRange(location: 0, length: 0))
        quitarIncrustaciones()
        if soloFuente {
            versionAnalizada = versionTexto
            return
        }
        if texto.utf16.count <= 120_000 {
            aplicar(AnalizadorMarkdown.analizar(texto), version: versionTexto, todo: true)
        } else {
            programarAnalisis(espera: .zero)
        }
    }

    /// Sustituye el texto por otro (lo que llegó de fuera, ya fusionado) cambiando solo lo distinto y
    /// conservando el cursor. Vacía el deshacer del texto (sus rangos ya no valen).
    public func sustituir(con nuevo: String) {
        let viejo = vista.string as NSString
        let otro = nuevo as NSString
        guard viejo != otro else { return }
        var prefijo = 0
        let minimo = min(viejo.length, otro.length)
        while prefijo < minimo, viejo.character(at: prefijo) == otro.character(at: prefijo) { prefijo += 1 }
        var sufijo = 0
        while sufijo < minimo - prefijo,
              viejo.character(at: viejo.length - 1 - sufijo) == otro.character(at: otro.length - 1 - sufijo) { sufijo += 1 }
        let quitado = NSRange(location: prefijo, length: viejo.length - prefijo - sufijo)
        let puesto = otro.substring(with: NSRange(location: prefijo, length: otro.length - prefijo - sufijo))
        var sel = vista.selectedRange()
        let delta = (puesto as NSString).length - quitado.length
        if sel.location >= NSMaxRange(quitado) { sel.location += delta } else if sel.location > quitado.location { sel.location = quitado.location }
        sel.length = 0
        aplicandoTexto = true
        storage.beginEditing()
        storage.replaceCharacters(in: quitado, with: puesto)
        storage.endEditing()
        aplicandoTexto = false
        deshacer.removeAllActions()
        vista.setSelectedRange(NSRange(location: min(sel.location, storage.length), length: 0))
        if soloFuente != (nuevo.utf8.count >= AnalizadorMarkdown.limiteBytes) {
            cargar(nuevo)
        } else {
            programarAnalisis(espera: .zero)
        }
    }

    // MARK: Modos

    /// Cambia de modo (repinta todo).
    public func cambiarModo(_ nuevo: ModoEditor) {
        let destino = soloFuente ? .fuente : nuevo
        guard destino != modo else { return }
        cambiarModoInterno(destino)
        reestilarTodo()
        alCambiarModo?(modo)
    }

    /// ⌘E: «Texto fuente» y vuelta al modo anterior.
    public func alternarFuente() {
        cambiarModo(modo == .fuente ? modoAnterior : .fuente)
    }

    /// ⇧⌘E: «Lectura» y vuelta a la edición.
    public func alternarLectura() {
        cambiarModo(modo == .lectura ? (modoAnterior == .lectura ? .vivo : modoAnterior) : .lectura)
    }

    private func cambiarModoInterno(_ nuevo: ModoEditor) {
        if modo != .fuente { modoAnterior = modo }
        modo = nuevo
        tema = TemaEditor(modo: nuevo, escala: escala)
        disposicion.escala = tema.escala
        actualizarEditable()
        sugerencias.cerrar()
    }

    private func actualizarEditable() {
        vista.isEditable = modo.editable && !soloLectura
        vista.isSelectable = true
        if !vista.isEditable { sugerencias.cerrar() }
    }

    // MARK: Análisis

    /// Analiza ya, sin esperar (pruebas, cambio de modo).
    public func analizarYa() async {
        tareaAnalisis?.cancel()
        await analizar()
    }

    /// `true` si el estilo pintado corresponde al texto actual.
    public var estiloAlDia: Bool { soloFuente || versionAnalizada == versionTexto }

    private func programarAnalisis(espera: Duration? = nil) {
        tareaAnalisis?.cancel()
        guard !soloFuente else { return }
        let pausa = espera ?? esperaAnalisis
        tareaAnalisis = Task { [weak self] in
            if pausa > .zero { try? await Task.sleep(for: pausa) }
            guard !Task.isCancelled, let self else { return }
            await self.analizar()
        }
    }

    private func analizar() async {
        guard !soloFuente else { return }
        let version = versionTexto
        let texto = vista.string
        let id = Self.signpost.makeSignpostID()
        let estado = Self.signpost.beginInterval("Analizar", id: id)
        let resultado = await Task.detached(priority: .userInitiated) { AnalizadorMarkdown.analizar(texto) }.value
        Self.signpost.endInterval("Analizar", estado)
        guard version == versionTexto else { return }
        aplicar(resultado, version: version, todo: false)
    }

    /// Aplica un análisis: repinta las líneas que cambiaron, las editadas y las del cursor.
    private func aplicar(_ nuevo: AnalisisMarkdown, version: Int, todo: Bool) {
        guard version == versionTexto, nuevo.longitud == storage.length else { return }
        let estado = Self.signpost.beginInterval("Repintar")
        defer { Self.signpost.endInterval("Repintar", estado) }
        tareaResto?.cancel()
        tareaResto = nil
        var indices = IndexSet()
        if todo || restoPendiente {
            indices.insert(integersIn: 0..<nuevo.parrafos.count)
        } else {
            indices.insert(integersIn: nuevo.cambiadas(respectoA: analisis))
            for r in pendientes.rangos { insertar(r, de: nuevo, en: &indices) }
            if let r = rangoCursor { insertar(r, de: nuevo, en: &indices) }
        }
        restoPendiente = false
        pendientes.vaciar()
        let cursor = cursorActivo ? nuevo.indice(de: vista.selectedRange().location) : nil
        if let cursor { indices.insert(cursor) }
        let alturas = prepararIncrustaciones(nuevo)
        // Muchas líneas (al abrir una nota grande, al cambiar de modo): primero lo que se ve y el resto a
        // trozos, sin bloquear la ventana.
        var ahora = indices
        var resto = IndexSet()
        if indices.count > Self.loteRepintado {
            let visibles = parrafosVisibles(en: nuevo)
            ahora = indices.intersection(visibles)
            resto = indices.subtracting(ahora)
        }
        pintar(ahora, de: nuevo, cursor: cursor, alturas: alturas)
        repintadasUltimoAnalisis = indices.count
        analisis = nuevo
        versionAnalizada = version
        parrafoCursor = cursor
        rangoCursor = cursor.map { nuevo.parrafos[$0].rangoCompleto }
        ajustarAtributosEscritura()
        avisarTitulos()
        if !marcos.isEmpty { DispatchQueue.main.async { [weak self] in self?.colocarIncrustaciones() } }
        if !resto.isEmpty { pintarResto(resto, version: version, alturas: alturas) }
    }

    /// Líneas por trozo cuando hay que repintar muchas.
    static let loteRepintado = 600
    private var tareaResto: Task<Void, Never>?
    /// Quedan líneas del análisis actual sin pintar (si el texto cambia antes, el próximo análisis las pinta todas).
    private var restoPendiente = false

    private func pintar(_ indices: IndexSet, de a: AnalisisMarkdown, cursor: Int?, alturas: [Int: CGFloat]) {
        guard !indices.isEmpty else { return }
        storage.beginEditing()
        for i in indices where i < a.parrafos.count {
            AplicadorEstilo(tema: tema).aplicar(a.parrafos[i], en: storage,
                                                contexto: contexto(i, cursor: i == cursor, alturas: alturas))
        }
        storage.endEditing()
    }

    private func pintarResto(_ resto: IndexSet, version: Int, alturas: [Int: CGFloat]) {
        restoPendiente = true
        tareaResto = Task { [weak self] in
            var pendientes = Array(resto)
            while !pendientes.isEmpty {
                do { try await Task.sleep(for: .milliseconds(1)) } catch { return }
                // Si el texto cambió, el próximo análisis lo pinta todo (`restoPendiente` sigue en `true`).
                guard let self, self.versionTexto == version, self.versionAnalizada == version else { return }
                let lote = IndexSet(pendientes.prefix(Self.loteRepintado))
                pendientes.removeFirst(min(Self.loteRepintado, pendientes.count))
                self.pintar(lote, de: self.analisis, cursor: self.parrafoCursor, alturas: alturas)
            }
            self?.restoPendiente = false
            self?.tareaResto = nil
        }
    }

    /// Líneas que se ven (y unas cuantas alrededor), para pintarlas primero.
    private func parrafosVisibles(en a: AnalisisMarkdown) -> IndexSet {
        guard !a.parrafos.isEmpty else { return IndexSet() }
        var centro = a.indice(de: vista.selectedRange().location)
        if let tlm = vista.textLayoutManager, let tcs = vista.textContentStorage,
           let vp = tlm.textViewportLayoutController.viewportRange {
            centro = a.indice(de: tcs.offset(from: tcs.documentRange.location, to: vp.location))
        }
        let desde = max(0, centro - 120)
        let hasta = min(a.parrafos.count, centro + 240)
        return IndexSet(integersIn: desde..<hasta)
    }

    /// `true` mientras quedan líneas por pintar a trozos.
    public var pintandoATrozos: Bool { restoPendiente }

    /// Espera a que termine de pintar a trozos (pruebas y capturas), como mucho `maximo`. Sale enseguida si
    /// se cancela la tarea que espera (sin quedarse dando vueltas).
    public func esperarPintado(maximo: Duration = .seconds(10)) async {
        let reloj = ContinuousClock()
        let fin = reloj.now.advanced(by: maximo)
        while restoPendiente || !estiloAlDia, reloj.now < fin {
            do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
        }
    }

    private func insertar(_ r: NSRange, de a: AnalisisMarkdown, en indices: inout IndexSet) {
        guard !a.parrafos.isEmpty else { return }
        let desde = a.indice(de: max(0, r.location))
        let hasta = a.indice(de: max(0, NSMaxRange(r)))
        indices.insert(integersIn: desde...hasta)
    }

    /// Repinta todo con el último análisis (cambio de modo, de escala o de apariencia).
    public func reestilarTodo() {
        if soloFuente {
            storage.beginEditing()
            storage.setAttributes(atributosEscritura(BloqueLinea()), range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
            return
        }
        if versionAnalizada == versionTexto, analisis.longitud == storage.length {
            aplicar(analisis, version: versionTexto, todo: true)
        } else {
            programarAnalisis(espera: .zero)
        }
    }

    private var cursorActivo: Bool {
        modo == .vivo && vista.window?.firstResponder === vista
    }

    private func contexto(_ i: Int, cursor: Bool, alturas: [Int: CGFloat]) -> AplicadorEstilo.Contexto {
        var c = AplicadorEstilo.Contexto()
        c.cursor = cursor
        c.altoIncrustacion = alturas[i]
        if let resolutor {
            c.estadoEnlace = { [unowned resolutor] e in e.esExterno ? .externa : resolutor.estado(de: e) }
        }
        return c
    }

    // MARK: Cursor

    /// La línea del cursor cambió: se repintan esa y la anterior (dos líneas).
    private func actualizarCursor() {
        guard !soloFuente, versionAnalizada == versionTexto, analisis.longitud == storage.length else { return }
        let nuevo = cursorActivo ? analisis.indice(de: vista.selectedRange().location) : nil
        guard nuevo != parrafoCursor else { return }
        var lineas: [Int] = []
        if let v = parrafoCursor, v < analisis.parrafos.count { lineas.append(v) }
        if let n = nuevo { lineas.append(n) }
        let alturas = alturasActuales()
        storage.beginEditing()
        for i in lineas {
            AplicadorEstilo(tema: tema).aplicar(analisis.parrafos[i], en: storage,
                                                contexto: contexto(i, cursor: i == nuevo, alturas: alturas))
        }
        storage.endEditing()
        repintadasAlMoverCursor = lineas.count
        parrafoCursor = nuevo
        rangoCursor = nuevo.map { analisis.parrafos[$0].rangoCompleto }
        if lineas.contains(where: { analisis.parrafos[$0].incrustacion != nil }) {
            DispatchQueue.main.async { [weak self] in self?.colocarIncrustaciones() }
        }
    }

    func focoCambiado(perdido: Bool = false) {
        actualizarCursor()
        if perdido { sugerencias.cerrar() }
    }

    /// Lo que se teclea detrás de una marca no hereda su aspecto (atenuado o escondido).
    private func ajustarAtributosEscritura() {
        let sel = vista.selectedRange()
        guard sel.location > 0, sel.location <= storage.length else {
            vista.typingAttributes = atributosEscritura(bloqueEn(sel.location))
            return
        }
        let previos = storage.attributes(at: sel.location - 1, effectiveRange: nil)
        if previos[.tlsMarcador] != nil || (previos[.font] as? NSFont).map({ $0.pointSize < 1 }) == true {
            vista.typingAttributes = atributosEscritura(bloqueEn(sel.location))
        }
    }

    private func bloqueEn(_ posicion: Int) -> BloqueLinea {
        guard versionAnalizada == versionTexto, !analisis.parrafos.isEmpty else { return BloqueLinea() }
        return analisis.parrafos[analisis.indice(de: posicion)].bloque
    }

    private func atributosEscritura(_ b: BloqueLinea) -> [NSAttributedString.Key: Any] {
        let e = tema.estilo(de: b)
        return [.font: tema.fuente(e), .foregroundColor: tema.texto,
                .paragraphStyle: tema.parrafo(b, sangria: 0, colapsada: false, alto: nil)]
    }

    // MARK: Títulos

    private func avisarTitulos() {
        let ns = storage.mutableString
        let nuevos = analisis.parrafos.compactMap { p -> TituloNota? in
            guard let n = p.bloque.nivelEncabezado else { return nil }
            var t = ns.substring(with: p.rangoContenido)
            // Sin las marcas del título.
            for tramo in p.tramos.reversed() where tramo.clase == .marcador && NSMaxRange(tramo.rango) <= (t as NSString).length {
                t = (t as NSString).replacingCharacters(in: tramo.rango, with: "")
            }
            return TituloNota(nivel: n, texto: t.trimmingCharacters(in: .whitespaces), posicion: p.inicio)
        }
        guard nuevos != titulos else { return }
        titulos = nuevos
        alCambiarTitulos?(nuevos)
    }

    /// Lleva el cursor y la vista a una posición (índice del inspector).
    public func ir(a posicion: Int) {
        let p = min(max(0, posicion), storage.length)
        vista.setSelectedRange(NSRange(location: p, length: 0))
        vista.scrollRangeToVisible(NSRange(location: p, length: 0))
        vista.window?.makeFirstResponder(vista)
    }

    // MARK: Desplazamiento

    /// Desplazamiento vertical de la nota (para recordarlo al volver).
    public var desplazamiento: CGFloat {
        get { scroll.contentView.bounds.origin.y }
        set {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, newValue)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func desplazado() {
        if !marcos.isEmpty { colocarIncrustaciones() }
        alDesplazar?(desplazamiento)
    }

    // MARK: Ventana, tamaño y apariencia

    func ventanaCambiada(_ ventana: NSWindow?) {
        guard ventana !== ventanaObservada else { return }
        ventanaObservada = ventana
        if let o = observadorVentana { NotificationCenter.default.removeObserver(o) }
        observadorVentana = nil
        guard let ventana else { return }
        observadorVentana = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: ventana, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.alPerderFoco?() }
        }
        disposicion.apariencia = vista.effectiveAppearance
        anchoCambiado()
    }

    func aparienciaCambiada() {
        disposicion.apariencia = vista.effectiveAppearance
        scroll.backgroundColor = TLSPaleta.superficie.ns
        reestilarTodo()
    }

    func anchoCambiado() {
        let ancho = scroll.contentSize.width
        let columna = min(anchoTexto * min(tema.escala, 1.4), max(ancho - 48, 200))
        let margen = max(24, ((ancho - columna) / 2).rounded())
        let alto = 24 + (altoCabecera > 0 ? altoCabecera + 20 : 0)
        let inset = NSSize(width: margen, height: alto)
        if vista.textContainerInset != inset { vista.textContainerInset = inset }
        if let cabecera {
            cabecera.frame = NSRect(x: margen, y: 20, width: max(100, ancho - 2 * margen), height: max(altoCabecera, 1))
        }
        colocarIncrustaciones()
    }

    // MARK: Cabecera (las propiedades de la nota)

    /// Pone una vista de SwiftUI encima del texto, dentro del desplazamiento (las propiedades).
    public func ponerCabecera<V: View>(_ contenido: V?) {
        cabecera?.removeFromSuperview()
        cabecera = nil
        guard let contenido else {
            altoCabecera = 0
            anchoCambiado()
            return
        }
        let medida = CabeceraMedida(contenido: AnyView(contenido)) { [weak self] alto in
            guard let self, abs(alto - self.altoCabecera) > 0.5 else { return }
            self.altoCabecera = alto
            self.anchoCambiado()
        }
        let hosting = NSHostingView(rootView: medida)
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 32, y: 20, width: 600, height: 400)
        vista.addSubview(hosting)
        cabecera = hosting
        anchoCambiado()
    }

    // MARK: Incrustaciones

    /// Prepara los marcos de las incrustaciones de un análisis y da su alto por línea.
    private func prepararIncrustaciones(_ a: AnalisisMarkdown) -> [Int: CGFloat] {
        guard modo != .fuente else { quitarIncrustaciones(); return [:] }
        var alturas: [Int: CGFloat] = [:]
        var vivas: [String: Int] = [:]
        var veces: [String: Int] = [:]
        for (i, p) in a.parrafos.enumerated() {
            guard let inc = p.incrustacion else { continue }
            let base = inc.enlace.destino + "#" + (inc.enlace.ancla ?? "")
            let n = veces[base, default: 0]
            veces[base] = n + 1
            let clave = "\(base)·\(n)"
            if let marco = marcos[clave] {
                vivas[clave] = i
                alturas[i] = marco.alto
            } else if let proveedor = incrustaciones, let bloque = proveedor.bloque(para: inc) {
                let marco = MarcoIncrustacion(clave: clave, bloque: bloque, ampliado: ampliadas.contains(clave)) { [weak self] in
                    self?.alternarAmpliado(clave)
                }
                marco.isHidden = true
                vista.addSubview(marco)
                marcos[clave] = marco
                vivas[clave] = i
                alturas[i] = marco.alto
            }
        }
        for (clave, marco) in marcos where vivas[clave] == nil {
            marco.removeFromSuperview()
            marcos[clave] = nil
        }
        lineaDeIncrustacion = vivas
        return alturas
    }

    private func alturasActuales() -> [Int: CGFloat] {
        var a: [Int: CGFloat] = [:]
        for (clave, i) in lineaDeIncrustacion { if let m = marcos[clave] { a[i] = m.alto } }
        return a
    }

    private func quitarIncrustaciones() {
        for m in marcos.values { m.removeFromSuperview() }
        marcos = [:]
        lineaDeIncrustacion = [:]
    }

    private func alternarAmpliado(_ clave: String) {
        guard let marco = marcos[clave], let i = lineaDeIncrustacion[clave], i < analisis.parrafos.count,
              versionAnalizada == versionTexto else { return }
        if ampliadas.contains(clave) { ampliadas.remove(clave) } else { ampliadas.insert(clave) }
        marco.ampliado = ampliadas.contains(clave)
        storage.beginEditing()
        AplicadorEstilo(tema: tema).aplicar(analisis.parrafos[i], en: storage,
                                            contexto: contexto(i, cursor: i == parrafoCursor, alturas: alturasActuales()))
        storage.endEditing()
        DispatchQueue.main.async { [weak self] in self?.colocarIncrustaciones() }
    }

    /// Pone cada marco en el hueco que deja su línea (tras cada disposición y al desplazar).
    func colocarIncrustaciones() {
        guard !marcos.isEmpty, let tlm = vista.textLayoutManager, let tcs = vista.textContentStorage else { return }
        let origen = vista.textContainerOrigin
        let ancho = max(100, (vista.textContainer?.size.width ?? 600))
        for (clave, marco) in marcos {
            guard let i = lineaDeIncrustacion[clave], i < analisis.parrafos.count, versionAnalizada == versionTexto,
                  let loc = tcs.location(tcs.documentRange.location, offsetBy: analisis.parrafos[i].inicio) else {
                marco.isHidden = true
                continue
            }
            var fragmento = tlm.textLayoutFragment(for: loc)
            if fragmento == nil, marco.isHidden == false || analisis.parrafos.count < 2_000 {
                tlm.ensureLayout(for: NSTextRange(location: loc))
                fragmento = tlm.textLayoutFragment(for: loc)
            }
            guard let frag = fragmento else {
                marco.isHidden = true
                continue
            }
            let f = frag.layoutFragmentFrame
            // El hueco es el espacio de después del párrafo (alto del marco + 14): el marco va arriba del hueco.
            let reservado = marco.alto + 14
            let finTexto = frag.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y + 4 } ?? 0
            let y = f.height >= reservado + finTexto - 1 ? f.maxY - reservado + 4 : f.minY + finTexto + 4
            let rect = NSRect(x: origen.x + f.minX, y: origen.y + y, width: min(ancho, 720 * tema.escala), height: marco.alto)
            if marco.frame != rect { marco.frame = rect }
            marco.isHidden = false
        }
    }

    // MARK: Clics, teclas y menú

    /// Carácter bajo un punto de la vista (índice en el texto y sus atributos).
    func caracter(en punto: NSPoint) -> (Int, [NSAttributedString.Key: Any])? {
        guard let tlm = vista.textLayoutManager, let tcs = vista.textContentStorage else { return nil }
        let origen = vista.textContainerOrigin
        let p = CGPoint(x: punto.x - origen.x, y: punto.y - origen.y)
        guard let frag = tlm.textLayoutFragment(for: p) else { return nil }
        let f = frag.layoutFragmentFrame
        let local = CGPoint(x: p.x - f.minX, y: p.y - f.minY)
        guard let linea = frag.textLineFragments.first(where: { local.y >= $0.typographicBounds.minY && local.y < $0.typographicBounds.maxY })
                ?? frag.textLineFragments.last else { return nil }
        let enLinea = CGPoint(x: local.x - linea.typographicBounds.minX, y: local.y - linea.typographicBounds.minY)
        let idx = linea.characterIndex(for: enLinea)
        let inicio = tcs.offset(from: tcs.documentRange.location, to: frag.rangeInElement.location)
        for c in [idx, idx - 1] where NSLocationInRange(c, linea.characterRange) {
            let xa = linea.locationForCharacter(at: c).x
            let xb = linea.locationForCharacter(at: c + 1).x
            if enLinea.x >= min(xa, xb) - 2, enLinea.x <= max(xa, xb) + 2 {
                let absoluto = inicio + c
                guard absoluto < storage.length else { return nil }
                return (absoluto, storage.attributes(at: absoluto, effectiveRange: nil))
            }
        }
        return nil
    }

    /// Clic en una casilla (la marca o desmarca) o en un enlace (⌘clic, o clic en Lectura). `true` si se usó.
    func gestionarClic(_ e: NSEvent) -> Bool {
        let punto = vista.convert(e.locationInWindow, from: nil)
        guard let (indice, atributos) = caracter(en: punto) else { return false }
        if atributos[.tlsCasilla] is Bool {
            var r = NSRange()
            _ = storage.attribute(.tlsCasilla, at: indice, longestEffectiveRange: &r,
                                  in: NSRange(location: max(0, indice - 3), length: min(7, storage.length - max(0, indice - 3))))
            alternarCasilla(en: r.location)
            return true
        }
        if let caja = atributos[.tlsEnlace] as? CajaEnlace {
            let teclas = e.modifierFlags
            if modo == .lectura {
                abrir(caja.enlace, apertura: teclas.contains(.command) ? (teclas.contains(.option) ? .ventanaNueva : .pestanaNueva) : .aqui)
                return true
            }
            if teclas.contains(.command) {
                abrir(caja.enlace, apertura: teclas.contains(.option) ? .ventanaNueva : (teclas.contains(.shift) ? .pestanaNueva : .aqui))
                return true
            }
        }
        return false
    }

    private func abrir(_ enlace: EnlaceMarkdown, apertura: AperturaEnlace) {
        if enlace.esExterno, resolutor == nil {
            let d = enlace.destino.lowercased().hasPrefix("www.") ? "https://" + enlace.destino : enlace.destino
            if let url = URL(string: d) { NSWorkspace.shared.open(url) }
            return
        }
        resolutor?.abrir(enlace, apertura: apertura)
    }

    /// Marca o desmarca la casilla cuyo `[` está en `posicion` (cambia un solo carácter, con Deshacer).
    public func alternarCasilla(en posicion: Int) {
        guard !soloLectura, posicion + 2 < storage.length else { return }
        let ns = storage.mutableString
        guard ns.character(at: posicion) == 0x5B, ns.character(at: posicion + 2) == 0x5D else { return }
        let marcada = ns.character(at: posicion + 1) != 0x20
        reemplazar(NSRange(location: posicion + 1, length: 1), con: marcada ? " " : "x")
    }

    /// Cambia un tramo como si lo hubiera tecleado la persona (Deshacer y guardado), también en Lectura.
    private func reemplazar(_ r: NSRange, con s: String) {
        let estaba = vista.isEditable
        if !estaba { vista.isEditable = true }
        defer { if !estaba { vista.isEditable = false } }
        guard vista.shouldChangeText(in: r, replacementString: s) else { return }
        storage.replaceCharacters(in: r, with: s)
        vista.didChangeText()
    }

    /// ⌘↩ marca o desmarca la casilla de la línea del cursor.
    func gestionarTecla(_ e: NSEvent) -> Bool {
        let teclas = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if teclas == .command, e.keyCode == 36 || e.keyCode == 76 {
            guard estiloAlDia, !analisis.parrafos.isEmpty else { return true }
            let p = analisis.parrafos[analisis.indice(de: vista.selectedRange().location)]
            if let t = p.tramos.first(where: { if case .casilla = $0.clase { return true }; return false }) {
                alternarCasilla(en: p.inicio + t.rango.location)
            }
            return true
        }
        return false
    }

    /// Mano sobre un enlace en Lectura, o con ⌘ en edición.
    func actualizarPuntero(_ e: NSEvent) {
        guard modo == .lectura || e.modifierFlags.contains(.command) else { return }
        let punto = vista.convert(e.locationInWindow, from: nil)
        if let (_, a) = caracter(en: punto), a[.tlsEnlace] != nil || a[.tlsCasilla] != nil {
            NSCursor.pointingHand.set()
        }
    }

    func menuContextual(_ menu: NSMenu?, evento e: NSEvent) -> NSMenu? {
        let punto = vista.convert(e.locationInWindow, from: nil)
        guard let (_, a) = caracter(en: punto), let caja = a[.tlsEnlace] as? CajaEnlace else { return menu }
        let m = menu ?? NSMenu()
        let items: [(String, AperturaEnlace)] = [("Abrir el enlace", .aqui), ("Abrir en pestaña nueva", .pestanaNueva),
                                                 ("Abrir en ventana nueva", .ventanaNueva)]
        for (n, (titulo, apertura)) in items.enumerated() {
            let item = NSMenuItem(title: titulo, action: #selector(abrirDesdeMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = AperturaMenu(enlace: caja.enlace, apertura: apertura)
            m.insertItem(item, at: n)
        }
        m.insertItem(.separator(), at: items.count)
        return m
    }

    @objc private func abrirDesdeMenu(_ item: NSMenuItem) {
        guard let a = item.representedObject as? AperturaMenu else { return }
        abrir(a.enlace, apertura: a.apertura)
    }

    // MARK: Para las pruebas

    var sugerenciasParaPruebas: ControladorSugerencias { sugerencias }
    func alternarAmpliadoParaPruebas(_ clave: String) { alternarAmpliado(clave) }
    /// Repinta todas las líneas con el análisis actual y devuelve cuántas.
    @discardableResult
    func repintarParaPruebas() -> Int {
        let todos = IndexSet(integersIn: 0..<analisis.parrafos.count)
        pintar(todos, de: analisis, cursor: parrafoCursor, alturas: alturasActuales())
        return todos.count
    }
}

private final class AperturaMenu: NSObject {
    let enlace: EnlaceMarkdown
    let apertura: AperturaEnlace
    init(enlace: EnlaceMarkdown, apertura: AperturaEnlace) { self.enlace = enlace; self.apertura = apertura }
}

/// Mide la cabecera de SwiftUI para dejarle sitio encima del texto.
private struct CabeceraMedida: View {
    let contenido: AnyView
    let alCambiarAlto: (CGFloat) -> Void

    var body: some View {
        contenido
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { alCambiarAlto($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Delegados

extension ControladorEditor: NSTextViewDelegate {
    public func undoManager(for view: NSTextView) -> UndoManager? { deshacer }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !aplicandoTexto else { return }
        actualizarCursor()
        ajustarAtributosEscritura()
        sugerencias.actualizar()
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        sugerencias.comando(commandSelector)
    }

    /// El corrector no marca las marcas escondidas, los destinos de los enlaces ni el código.
    public func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range: NSRange) -> Int {
        guard value != 0, range.location < storage.length else { return value }
        var r = NSRange()
        let a = storage.attributes(at: range.location, effectiveRange: &r)
        if a[.tlsMarcador] != nil || a[.tlsFondo] != nil { return 0 }
        if let f = a[.font] as? NSFont, f.isFixedPitch || f.pointSize < 1 { return 0 }
        return value
    }
}

extension ControladorEditor: NSTextStorageDelegate {
    public nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                        range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated { self.textoEditado(editedRange, delta: delta) }
    }

    private func textoEditado(_ r: NSRange, delta: Int) {
        versionTexto += 1
        pendientes.editar(r, delta: delta)
        if var c = rangoCursor {
            var tmp = RangosVivos()
            tmp.anadir(c)
            tmp.editar(r, delta: delta)
            c = tmp.rangos.first ?? c
            rangoCursor = c
        }
        guard !aplicandoTexto else { return }
        programarAnalisis()
        alCambiarTexto?()
    }
}
