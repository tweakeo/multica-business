import Foundation
import Observation
import TLSCore
import TLSDesign
import TLSEditor

/// Cómo va el guardado de la nota (lo enseña la barra de la pantalla).
enum EstadoGuardado: Equatable, Sendable {
    case guardado
    case sinGuardar
    case guardando
    /// Cambió fuera mientras se editaba y no se pudo fusionar: hay que elegir.
    case conflicto
    case noSePudo(String)

    var texto: String {
        switch self {
        case .guardado: "Guardado"
        case .sinGuardar: "Sin guardar"
        case .guardando: "Guardando…"
        case .conflicto: "Sin guardar: cambió fuera"
        case .noSePudo: "No se pudo guardar"
        }
    }
}

/// Un guardado que chocó con un cambio hecho fuera de la app.
struct ConflictoNota: Equatable {
    let registro: ConflictRecord
    /// Lo que iba a guardar la app (texto completo).
    let mia: String
    /// Lo que hay ahora en la carpeta (texto completo).
    let deFuera: String

    static func == (a: ConflictoNota, b: ConflictoNota) -> Bool { a.registro.id == b.registro.id }
}

/// Lo que se ve de la nota.
enum ContenidoNota: Equatable {
    case cargando
    /// Markdown (con propiedades fuera del texto) o texto plano: en el editor.
    case editable(markdown: Bool)
    case csv(cabecera: [String], filas: [[String]])
    case noDescargada
    case sinLlegarDeICloud
    case binario(Int64?)
    case ilegible(String)
}

/// Estado de la pantalla de una nota: la lectura, el editor y el guardado (PLAN §6.6).
///
/// **Guardado:** a los 800 ms de la última tecla y al cambiar de ventana, con
/// `guardarNota(base:texto:)` (compare-and-swap con fusión por secciones del núcleo). La base es el texto
/// completo del que parten los cambios (el último leído o el último enviado). Si fuera solo cambiaron
/// propiedades o se añadió Actividad, el núcleo fusiona sin aviso; si no, conflicto: el editor pasa a solo
/// lectura y la pantalla ofrece «Quedarme con lo mío / Usar lo de fuera / Ver diferencias». El guardado de
/// una persona no exige `hash_app`.
@Observable @MainActor
final class ModeloNotaEditor {
    let ruta: VaultPath
    let controlador: ControladorEditor
    @ObservationIgnored let enlaces: EnlacesDeNota
    @ObservationIgnored let incrustaciones: IncrustacionesDeNota
    @ObservationIgnored let adjuntos: ResolutorAdjuntos
    @ObservationIgnored private weak var sesion: VaultSession?

    private(set) var contenido: ContenidoNota = .cargando
    private(set) var propiedades: [Property] = []
    private(set) var titulo: String
    private(set) var tipo: NoteKind?
    private(set) var estado: EstadoGuardado = .guardado
    private(set) var conflicto: ConflictoNota?
    private(set) var titulos: [TituloNota] = []
    private(set) var modo: ModoEditor
    /// No se puede guardar (texto que no es UTF-8): se ve, pero no se cambia.
    private(set) var motivoSinGuardar: String?

    /// Texto completo del que parten los cambios del editor (`nil` hasta la primera lectura).
    @ObservationIgnored private(set) var base: String?
    /// Bloque de propiedades de `base` (todo lo que va antes del cuerpo).
    @ObservationIgnored private var prefijo = ""
    @ObservationIgnored private var tareaGuardado: Task<Void, Never>?
    /// Los guardados automáticos no entran en el ⌘Z de la ventana (el texto tiene el suyo).
    @ObservationIgnored private let deshacerGuardados = UndoManager()
    @ObservationIgnored var esperaGuardado: Duration = .milliseconds(800)
    @ObservationIgnored private(set) var guardadosHechos = 0
    /// Número de la última lectura adoptada (`NoteSnapshot.lectura`, por orden de empezar a leer). Una lectura
    /// anterior que llega tarde no vuelve atrás el texto; tras guardar, tampoco una que empezó antes.
    @ObservationIgnored private var ultimaLectura = 0

    init(ruta: VaultPath, sesion: VaultSession, modo: ModoEditor = .vivo) {
        self.ruta = ruta
        self.sesion = sesion
        self.titulo = sesion.titulo(de: ruta)
        self.modo = modo
        self.controlador = ControladorEditor(modo: modo)
        let adjuntos = ResolutorAdjuntos(sesion: sesion)
        self.adjuntos = adjuntos
        self.enlaces = EnlacesDeNota(ruta: ruta, sesion: sesion, adjuntos: adjuntos)
        self.incrustaciones = IncrustacionesDeNota(ruta: ruta, sesion: sesion, adjuntos: adjuntos)
        deshacerGuardados.levelsOfUndo = 1
        controlador.autocompletado = enlaces
        controlador.resolutor = enlaces
        controlador.incrustaciones = incrustaciones
        controlador.alCambiarTexto = { [weak self] in
            self?.reintentosSeguidos = 0
            self?.textoCambiado()
        }
        controlador.alPerderFoco = { [weak self] in self?.guardarYa() }
        controlador.alCambiarModo = { [weak self] m in self?.modo = m }
        controlador.alCambiarTitulos = { [weak self] t in self?.titulos = t }
        adjuntos.alCargar = { [weak self] in self?.controlador.reestilarTodo() }
        actualizarSoloLectura()
        GuardadosPendientes.compartido.registrar(self, sesion: sesion)
    }

    var esMarkdown: Bool { contenido == .editable(markdown: true) }

    /// La carpeta no deja escribir (real, solo lectura elegida, escritor sin abrir).
    var motivoSoloLectura: String? {
        guard let sesion else { return nil }
        if case .soloLectura(let m) = sesion.modoEscritura { return m.texto }
        if sesion.modoEscritura == .abriendo { return "Abriendo…" }
        return motivoSinGuardar
    }

    /// Bloquea o desbloquea el editor según la carpeta y el conflicto.
    func actualizarSoloLectura() {
        controlador.soloLectura = motivoSoloLectura != nil || conflicto != nil
    }

    // MARK: Leer

    /// Una lectura nueva de la nota (al abrir, tras guardar o tras un cambio de fuera).
    func recibir(_ nota: NoteSnapshot) {
        guard nota.path == ruta, let c = nota.content else { return }
        guard nota.lectura >= ultimaLectura else { return }
        ultimaLectura = nota.lectura
        tipo = nota.summary?.kind ?? tipo
        switch c {
        case .markdown(let texto, let props, let cuerpo, let t, let kind):
            propiedades = props
            titulo = t
            tipo = kind
            recibirTexto(texto, cuerpo: cuerpo, markdown: true)
        case .plain(let texto):
            recibirTexto(texto, cuerpo: texto, markdown: false)
        case .csv(let cabecera, let filas, _):
            contenido = .csv(cabecera: cabecera, filas: filas)
        case .notDownloaded:
            if base == nil { contenido = .noDescargada }
        case .binary(let tamano):
            contenido = .binario(tamano)
        case .unreadable(let m):
            if base == nil { contenido = .ilegible(m) }
        }
    }

    func noLlegaDeICloud() {
        if base == nil { contenido = .sinLlegarDeICloud }
    }

    private func recibirTexto(_ texto: String, cuerpo: String, markdown: Bool) {
        let prefijoNuevo = Self.prefijo(de: texto, cuerpo: cuerpo)
        guard let base else {
            // Primera lectura.
            self.base = texto
            prefijo = prefijoNuevo
            if !markdown, controlador.modo != .fuente { controlador.cambiarModo(.fuente) }
            controlador.cargar(cuerpo)
            contenido = .editable(markdown: markdown)
            estado = .guardado
            return
        }
        guard texto != base else { return }
        let cuerpoBase = Self.cuerpo(de: base, markdown: markdown)
        let editado = controlador.texto != cuerpoBase
        if !editado {
            // Sin cambios propios pendientes: se adopta lo de la carpeta (también lo fusionado al guardar).
            self.base = texto
            prefijo = prefijoNuevo
            if controlador.texto != cuerpo { controlador.sustituir(con: cuerpo) }
            if estado != .guardando { estado = .guardado }
        } else if cuerpo == cuerpoBase {
            // Fuera solo cambiaron las propiedades (p. ej., desde la ficha de propiedades): se cambia la base.
            self.base = texto
            prefijo = prefijoNuevo
        } else {
            // Cambió el cuerpo fuera con cambios propios sin guardar: que decida el núcleo (fusiona o conflicto).
            guardarYa()
        }
    }

    /// Lo que va antes del cuerpo (el bloque de propiedades) en un texto completo.
    static func prefijo(de texto: String, cuerpo: String) -> String {
        guard texto.hasSuffix(cuerpo) else { return "" }
        let fin = texto.utf8.index(texto.utf8.endIndex, offsetBy: -cuerpo.utf8.count)
        return String(texto[..<fin])
    }

    static func cuerpo(de texto: String, markdown: Bool) -> String {
        markdown ? NoteDocument(text: texto).body : texto
    }

    // MARK: Guardar

    private func textoCambiado() {
        guard conflicto == nil else { return }
        estado = .sinGuardar
        tareaGuardado?.cancel()
        let espera = esperaGuardado
        tareaGuardado = Task { [weak self] in
            try? await Task.sleep(for: espera)
            guard !Task.isCancelled else { return }
            await self?.guardar()
        }
    }

    /// Guarda ya lo pendiente (al cambiar de ventana, al salir de la pantalla).
    func guardarYa() {
        tareaGuardado?.cancel()
        tareaGuardado = nil
        Task { await guardar() }
    }

    /// Guarda ya lo pendiente y espera a que esté en la carpeta (pasar a solo lectura, salir de la app).
    func guardarPendiente() async {
        tareaGuardado?.cancel()
        tareaGuardado = nil
        await guardar()
    }

    /// Hay algo que aún no está en la carpeta o se está guardando.
    var tienePendiente: Bool { hayCambiosSinGuardar || estado == .guardando }

    /// `true` si lo que se ve no está aún en la carpeta.
    var hayCambiosSinGuardar: Bool {
        guard let base else { return false }
        return prefijo + controlador.texto != base
    }

    /// Guarda lo que haya pendiente. Los guardados van en fila: cada uno espera al anterior y después mira
    /// lo que queda (sin bucles de espera: si nada cambió, no escribe).
    func guardar() async {
        let anterior = enCurso
        let t = Task { [weak self] in
            await anterior?.value
            await self?.guardarUnaVez()
        }
        enCurso = t
        await t.value
        if enCurso == t { enCurso = nil }
    }

    @ObservationIgnored private var enCurso: Task<Void, Never>?
    /// Guardados seguidos que chocaron con otro guardado a la vez (`cambioExterno`). Se reintenta como mucho
    /// `maximoReintentos` veces; después se espera a la próxima tecla o a la próxima lectura.
    @ObservationIgnored private var reintentosSeguidos = 0
    static let maximoReintentos = 3

    private func guardarUnaVez() async {
        guard let sesion, let base, case .editable = contenido, conflicto == nil, motivoSoloLectura == nil else { return }
        let cuerpo = controlador.texto
        let texto = prefijo + cuerpo
        guard texto != base else {
            if estado != .guardado { estado = .guardado }
            return
        }
        estado = .guardando
        var reintentar = false
        do {
            let r = try await sesion.escribir(.guardarNota(ruta, base: base, texto: texto), aviso: "", deshacer: deshacerGuardados)
            switch r.estado {
            case .hecho, .sinCambios:
                reintentosSeguidos = 0
                // La base es lo enviado: si el núcleo fusionó algo de fuera, la lectura que llega ahora lo trae y,
                // si sigues escribiendo, el próximo guardado vuelve a fusionarlo.
                self.base = texto
                guardadosHechos += 1
                // Lo que se empezó a leer antes de este guardado puede traer el texto de antes.
                ultimaLectura = max(ultimaLectura, sesion.lecturas + 1)
                estado = controlador.texto == cuerpo ? .guardado : .sinGuardar
            case .conflicto(let registro):
                let deFuera = await leerTextoCompleto() ?? ""
                conflicto = ConflictoNota(registro: registro, mia: texto, deFuera: deFuera)
                estado = .conflicto
                actualizarSoloLectura()
                return
            }
        } catch WriteError.noEsTexto {
            motivoSinGuardar = "Esta nota no está guardada como texto UTF-8: se puede ver, pero no cambiar desde aquí."
            estado = .noSePudo(motivoSinGuardar ?? "")
            actualizarSoloLectura()
            return
        } catch WriteError.cambioExterno {
            // Alguien guardó justo a la vez: se vuelve a intentar (el núcleo relee el fichero), pocas veces.
            estado = .sinGuardar
            reintentosSeguidos += 1
            reintentar = reintentosSeguidos <= Self.maximoReintentos
        } catch {
            estado = .noSePudo(error.localizedDescription)
            return
        }
        if reintentar || controlador.texto != cuerpo { textoCambiado() }
    }

    private func leerTextoCompleto() async -> String? {
        guard let sesion, let n = await sesion.leer(ruta) else { return nil }
        switch n.content {
        case .markdown(let t, _, _, _, _)?: return t
        case .plain(let t)?: return t
        default: return nil
        }
    }

    // MARK: Conflicto

    /// «Quedarme con lo mío»: lo de fuera se guarda en `Archivo/Conflictos/` y la nota queda como la tienes.
    func quedarmeConLoMio() async {
        guard let sesion, let c = conflicto else { return }
        await sesion.resolver(c.registro, eleccion: .mia)
        guard !sesion.tarjetas.contains(where: { $0.id == c.registro.id }) else { return }
        base = c.mia
        prefijo = Self.prefijo(de: c.mia, cuerpo: Self.cuerpo(de: c.mia, markdown: esMarkdown))
        conflicto = nil
        estado = .guardado
        actualizarSoloLectura()
    }

    /// «Usar lo de fuera»: lo tuyo se guarda en `Archivo/Conflictos/` y el editor enseña lo de la carpeta.
    func usarLoDeFuera() async {
        guard let sesion, let c = conflicto else { return }
        await sesion.resolver(c.registro, eleccion: .otra)
        guard !sesion.tarjetas.contains(where: { $0.id == c.registro.id }) else { return }
        adoptar(c.deFuera)
    }

    /// «Combinar»: el cuerpo que escribió la persona con las propiedades de fuera.
    func combinar(cuerpo: String) async {
        guard let sesion, let c = conflicto else { return }
        let deFuera = Self.cuerpo(de: c.deFuera, markdown: esMarkdown)
        let texto = Self.prefijo(de: c.deFuera, cuerpo: deFuera) + cuerpo
        await sesion.resolver(c.registro, eleccion: .combinada(texto))
        guard !sesion.tarjetas.contains(where: { $0.id == c.registro.id }) else { return }
        adoptar(texto)
    }

    private func adoptar(_ texto: String) {
        let cuerpo = Self.cuerpo(de: texto, markdown: esMarkdown)
        base = texto
        prefijo = Self.prefijo(de: texto, cuerpo: cuerpo)
        controlador.sustituir(con: cuerpo)
        conflicto = nil
        estado = .guardado
        actualizarSoloLectura()
    }

    // MARK: Propiedades

    /// Cambia una sola propiedad (una línea del fichero), con aviso y Deshacer.
    func cambiarPropiedad(_ clave: String, a valor: PropertyValue, etiqueta: String) async {
        guard let sesion else { return }
        _ = try? await sesion.escribir(.cambiarPropiedades(ruta, poner: [Property(key: clave, value: valor)], quitar: []),
                                       aviso: "«\(etiqueta)» cambiada")
    }

    func quitarPropiedad(_ clave: String, etiqueta: String) async {
        guard let sesion else { return }
        _ = try? await sesion.escribir(.cambiarPropiedades(ruta, poner: [], quitar: [clave]), aviso: "Quitada «\(etiqueta)»")
    }
}

/// Los editores de nota abiertos en la app, con su empresa (referencias débiles). Guardan a los 800 ms de la
/// última tecla; antes de pasar una empresa a solo lectura y antes de salir de la app (⌘Q) se guarda ya lo
/// que tengan pendiente, para que no se pierda.
@MainActor
final class GuardadosPendientes {
    static let compartido = GuardadosPendientes()

    private final class Apunte {
        weak var editor: ModeloNotaEditor?
        weak var sesion: VaultSession?
        init(_ e: ModeloNotaEditor, _ s: VaultSession) { editor = e; sesion = s }
    }

    private var apuntes: [Apunte] = []

    func registrar(_ editor: ModeloNotaEditor, sesion: VaultSession) {
        apuntes.removeAll { $0.editor == nil || $0.sesion == nil }
        apuntes.append(Apunte(editor, sesion))
    }

    private func editores(de sesion: VaultSession?) -> [ModeloNotaEditor] {
        apuntes.removeAll { $0.editor == nil || $0.sesion == nil }
        return apuntes.filter { a in sesion.map { a.sesion === $0 } ?? true }.compactMap(\.editor)
    }

    /// Algún editor (de `sesion`, o de cualquier empresa) tiene texto sin guardar o guardándose.
    func hayPendientes(de sesion: VaultSession? = nil) -> Bool {
        editores(de: sesion).contains { $0.tienePendiente }
    }

    /// Guarda lo pendiente de los editores de `sesion` (o de todos) y espera a que acabe.
    func guardarTodo(de sesion: VaultSession? = nil) async {
        for e in editores(de: sesion) where e.tienePendiente {
            await e.guardarPendiente()
        }
    }
}
