import Foundation
import Observation
import TLSCore

/// Hojas y paneles flotantes de una pestaña de ventana.
public enum HojaVentana: String, Identifiable, Sendable, Codable {
    /// ⌘K: buscar o hacer en todas las bases (`Busqueda/PaletaBusqueda`).
    case paleta
    /// ⌘O: abrir rápido, solo por nombre.
    case abrirRapido
    /// ⌘N (F2): nueva tarea, con el contexto de la pantalla actual (`Tareas/NuevaTareaHoja`).
    case nuevaTarea
    /// ⇧⌘N (PLAN §6.1): nueva nota en la carpeta de la pantalla actual (`Carpeta/NuevaNotaHoja`).
    case nuevaNota
    /// F3: traer a la copia lo nuevo de la carpeta real (`Importar/ActualizarCopiaHoja`).
    case actualizarCopia
    /// F3: importar las tareas abiertas de Multica (`Importar/ImportarMulticaHoja`).
    case importarMultica
    public var id: String { rawValue }
}

/// Camino y historial de **una pestaña de ventana** (DISENO §2.1, §7.2).
///
/// El camino es `raiz` + `pila` (lo que enseñan las migas y lo que recorre el `NavigationStack`). Cada
/// navegación guarda el camino anterior en `atras`; ⌘[ y ⌘] van por ese historial como Finder y Safari.
/// Cambiar de pestaña dentro de una ficha no es un paso (`cambiarPestana`). Las pantallas guardan aquí su
/// `RecuerdoPantalla` (desplazamiento, filtros, selección) para estar igual al volver.
@Observable @MainActor
public final class Navegacion {
    /// Un sitio del historial: la raíz y los niveles por los que se entró.
    public struct Paso: Hashable, Codable, Sendable {
        public var raiz: Destino
        public var pila: [Destino]
        public init(raiz: Destino, pila: [Destino] = []) { self.raiz = raiz; self.pila = pila }
        public var migas: [Destino] { [raiz] + pila }
        public var actual: Destino { pila.last ?? raiz }

        /// `true` si `otro` es este mismo camino con más niveles detrás.
        func esPrefijo(de otro: Paso) -> Bool {
            otro.raiz == raiz && otro.pila.count >= pila.count && Array(otro.pila.prefix(pila.count)) == pila
        }
    }

    /// Cuántos pasos se guardan hacia atrás y hacia adelante.
    public static let limiteHistorial = 50

    public private(set) var raiz: Destino
    /// Niveles entrados desde la raíz. Lo recorre el `NavigationStack(path:)` de la ventana.
    public private(set) var pila: [Destino]
    /// Historial hacia atrás (el último es el anterior).
    public private(set) var atras: [Paso] = []
    /// Historial hacia adelante (el último es el siguiente).
    public private(set) var adelante: [Paso] = []
    /// Recuerdos por pantalla (el destino sin la pestaña de dentro).
    public private(set) var recuerdos: [Destino: RecuerdoPantalla] = [:]
    /// Pestaña de origen de cada nivel: la pestaña en la que estaba la pantalla anterior al entrar
    /// («Arquitectura Nexo · Oportunidades»). Índice = posición en `migas`.
    public private(set) var pestanasDeOrigen: [Int: String] = [:]
    /// `true` si el último cambio fue hacia atrás (para la dirección de la transición).
    public private(set) var ultimoFueAtras = false

    /// Hoja abierta en esta pestaña de ventana (⌘K, ⌘O, ⌘N).
    public var hoja: HojaVentana?
    /// Ruta que enseña la vista previa flotante de esta pestaña (barra espaciadora o puntero). Solo lectura.
    public var vistaPrevia: VaultPath?
    /// Panel de propiedades (⌥⌘I) abierto en esta pestaña de ventana. Cada pestaña guarda el suyo.
    public var inspector = true
    /// Número de la ventana de AppKit de esta pestaña (para abrir otra «detrás» y volver a esta).
    @ObservationIgnored public var numeroVentana: Int?

    public init(raiz: Destino = .hoy, pila: [Destino] = []) {
        self.raiz = raiz
        self.pila = pila
    }

    // MARK: Lectura

    public var actual: Destino { pila.last ?? raiz }
    public var migas: [Destino] { [raiz] + pila }
    public var pasoActual: Paso { Paso(raiz: raiz, pila: pila) }
    public var puedeIrAtras: Bool { !atras.isEmpty }
    public var puedeIrAdelante: Bool { !adelante.isEmpty }
    public var puedeSubir: Bool { !pila.isEmpty }

    // MARK: Navegar

    /// Entra un nivel. Si esa pantalla ya está en las migas, se recorta hasta ella (sin bucles, §2.1).
    public func entrar(_ destino: Destino) {
        let todas = migas
        if let i = todas.firstIndex(where: { $0.identidad == destino.identidad }) {
            var nuevas = Array(todas.prefix(i + 1))
            nuevas[i] = destino.pestana == nil ? nuevas[i] : destino
            guard nuevas != todas else { return }
            ir(a: Paso(raiz: nuevas[0], pila: Array(nuevas.dropFirst())))
            return
        }
        let origen = actual.pestana
        ir(a: Paso(raiz: raiz, pila: pila + [destino]))
        if let origen { pestanasDeOrigen[pila.count] = origen }
    }

    /// Raíz nueva (barra lateral, ⌘1–9, ⌘K). Las migas empiezan de nuevo; el historial lo guarda.
    /// `sembrar` pone delante el camino natural (§2.1 regla 3: desde ⌘K, `Facturas › F-2026-0013`).
    public func nuevaRaiz(_ destino: Destino, sembrar niveles: [Destino] = []) {
        let nuevo = Paso(raiz: destino, pila: niveles)
        guard nuevo != pasoActual else { return }
        ir(a: nuevo)
    }

    /// Vuelve a la miga `indice` (0 = la raíz). Lo que se quita queda en Adelante (§2.1).
    public func volver(a indice: Int) {
        guard indice >= 0, indice < migas.count - 1 else { return }
        let objetivo = Paso(raiz: raiz, pila: Array(pila.prefix(indice)))
        let actualPaso = pasoActual
        var quitados = [actualPaso]
        // Los pasos intermedios de este mismo camino también se recorren hacia atrás.
        while let previo = atras.last, previo != objetivo, previo.esPrefijo(de: actualPaso), objetivo.esPrefijo(de: previo) {
            quitados.append(atras.removeLast())
        }
        if atras.last == objetivo { atras.removeLast() }
        adelante.append(contentsOf: quitados)
        recortar(&adelante)
        aplicar(objetivo, haciaAtras: true)
    }

    /// ⌘↑: sube al nivel anterior de las migas.
    public func subir() {
        guard puedeSubir else { return }
        volver(a: migas.count - 2)
    }

    /// ⌘[ o ‹.
    public func irAtras() {
        guard let previo = atras.popLast() else { return }
        adelante.append(pasoActual)
        recortar(&adelante)
        aplicar(previo, haciaAtras: true)
    }

    /// ⌘] o ›.
    public func irAdelante() {
        guard let siguiente = adelante.popLast() else { return }
        atras.append(pasoActual)
        recortar(&atras)
        aplicar(siguiente, haciaAtras: false)
    }

    /// Salta a un paso del historial (menú de ‹ y › al mantener pulsado). `pasos` > 0 hacia atrás.
    public func saltar(atras pasos: Int) {
        for _ in 0..<max(0, pasos) { irAtras() }
    }

    public func saltar(adelante pasos: Int) {
        for _ in 0..<max(0, pasos) { irAdelante() }
    }

    /// Cambia la pestaña de la pantalla actual (área o ficha). No es un paso del historial (§2.1 regla 2).
    public func cambiarPestana(_ pestana: String?) {
        let nuevo = actual.conPestana(pestana)
        guard nuevo != actual else { return }
        if pila.isEmpty { raiz = nuevo } else { pila[pila.count - 1] = nuevo }
    }

    /// Lo que pide el `NavigationStack` (por ejemplo, si el sistema quita un nivel). Se trata como
    /// volver o entrar para que el historial sea el mismo.
    public func ajustarPila(_ nueva: [Destino]) {
        guard nueva != pila else { return }
        if nueva.count < pila.count, Array(pila.prefix(nueva.count)) == nueva {
            volver(a: nueva.count)
        } else if nueva.count > pila.count, Array(nueva.prefix(pila.count)) == pila {
            for d in nueva.dropFirst(pila.count) { entrar(d) }
        } else {
            ir(a: Paso(raiz: raiz, pila: nueva))
        }
    }

    /// Algo de la carpeta se renombró o se movió: las migas y el historial siguen llevando a su sitio
    /// (§2.1 regla 6).
    public func aplicarMovimientos(_ movimientos: [(de: VaultPath, a: VaultPath)]) {
        guard !movimientos.isEmpty else { return }
        func m(_ d: Destino) -> Destino { movimientos.reduce(d) { $0.moviendo(de: $1.de, a: $1.a) } }
        func m(_ p: Paso) -> Paso { Paso(raiz: m(p.raiz), pila: p.pila.map(m)) }
        raiz = m(raiz)
        pila = pila.map(m)
        atras = atras.map(m)
        adelante = adelante.map(m)
        var nuevos: [Destino: RecuerdoPantalla] = [:]
        for (clave, r) in recuerdos { nuevos[m(clave)] = r }
        recuerdos = nuevos
    }

    // MARK: Recuerdos de cada pantalla

    public func recuerdo(de destino: Destino) -> RecuerdoPantalla {
        recuerdos[destino.conPestana(nil)] ?? RecuerdoPantalla()
    }

    public func guardar(_ recuerdo: RecuerdoPantalla, de destino: Destino) {
        let clave = destino.conPestana(nil)
        guard recuerdos[clave] != recuerdo else { return }
        recuerdos[clave] = recuerdo.vacio ? nil : recuerdo
    }

    /// Cambia una parte del recuerdo de una pantalla.
    public func actualizarRecuerdo(de destino: Destino, _ cambio: (inout RecuerdoPantalla) -> Void) {
        var r = recuerdo(de: destino)
        cambio(&r)
        guardar(r, de: destino)
    }

    // MARK: Guardar y restaurar (SceneStorage)

    struct Estado: Codable {
        var raiz: Destino
        var pila: [Destino]
        var atras: [Paso]
        var adelante: [Paso]
        var recuerdos: [Destino: RecuerdoPantalla]
        /// Opcional: lo guardado antes de F1 integrada no lo trae.
        var inspector: Bool?
    }

    /// Estado codificado para `@SceneStorage` (al cerrar y abrir la app, cada pestaña vuelve a su camino).
    public var codificado: Data? {
        try? JSONEncoder().encode(Estado(raiz: raiz, pila: pila, atras: Array(atras.suffix(20)),
                                         adelante: Array(adelante.suffix(20)), recuerdos: recuerdos,
                                         inspector: inspector))
    }

    /// Restaura lo guardado; si no se puede leer, no cambia nada.
    public func restaurar(_ datos: Data) {
        guard let e = try? JSONDecoder().decode(Estado.self, from: datos) else { return }
        raiz = e.raiz; pila = e.pila; atras = e.atras; adelante = e.adelante; recuerdos = e.recuerdos
        inspector = e.inspector ?? true
    }

    // MARK: Interno

    private func ir(a nuevo: Paso) {
        atras.append(pasoActual)
        recortar(&atras)
        adelante.removeAll()
        aplicar(nuevo, haciaAtras: false)
    }

    private func aplicar(_ paso: Paso, haciaAtras: Bool) {
        ultimoFueAtras = haciaAtras
        raiz = paso.raiz
        pila = paso.pila
        pestanasDeOrigen = pestanasDeOrigen.filter { $0.key < migas.count }
    }

    private func recortar(_ lista: inout [Paso]) {
        if lista.count > Self.limiteHistorial { lista.removeFirst(lista.count - Self.limiteHistorial) }
    }
}
