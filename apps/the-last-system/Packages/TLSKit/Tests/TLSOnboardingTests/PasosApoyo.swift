import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSOnboarding

/// Ayudas de las pruebas de las pantallas de la puesta en marcha (F3 · rol pasos). Todo en temporales propios: Ribera y
/// la fixture G3 se copian; el registro, el Application Support, las empresas y `tutorial.json` son carpetas de prueba.
/// Nunca se abre un panel del sistema, nunca se lanza Claude y nunca se abre la app en pantalla: las vistas se pintan en
/// ventanas que no se enseñan.
@MainActor
enum PasosApoyo {
    static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardizedFileURL
    }

    static var ribera: URL { repo.appendingPathComponent("App/Recursos/Ejemplos/Asesoria-Ribera", isDirectory: true) }
    static var fixtureG3: URL {
        repo.appendingPathComponent("Packages/TLSKit/Tests/TLSCoreTests/Fixtures/EmpresaMinima", isDirectory: true)
    }

    static func temporal(_ nombre: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-pasos-\(nombre)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }
}

/// Un sitio de pruebas: registro, estado de la app, empresas y, si se pide, una carpeta copiada y registrada.
@MainActor
final class Banco {
    let base: URL
    let appSupport: URL
    let empresas: URL
    let registro: VaultRegistry
    let entorno = EntornoPuesta()
    let paneles = PanelesFalsos()
    let detector = DetectorFalso()
    var abiertas: [UUID] = []
    var cerrada = 0
    var selector = 0
    var ajustes = 0
    var acceso: AccesoCarpeta = .ok

    init() {
        base = PasosApoyo.temporal("banco")
        appSupport = base.appendingPathComponent("asup", isDirectory: true)
        empresas = base.appendingPathComponent("Empresas", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        registro = VaultRegistry(directory: appSupport)
        entorno.paneles = paneles
        entorno.detectorClaude = detector
        entorno.tutorialEn(base.appendingPathComponent("tutorial.json"))
        entorno.abrirAjustes = { [unowned self] in self.ajustes += 1 }
        entorno.mostrarEnFinder = { _ in }
        entorno.comprobarAcceso = { [unowned self] _ in await MainActor.run { self.acceso } }
    }

    func limpiar() { try? FileManager.default.removeItem(at: base) }

    /// Copia una carpeta de ejemplo en el banco y la registra (copia de trabajo, con escritura).
    func carpeta(copiando origen: URL, nombre: String, privadas: [String] = []) -> VaultEntry {
        let destino = base.appendingPathComponent(nombre, isDirectory: true)
        try! FileManager.default.copyItem(at: origen, to: destino)
        let e = VaultEntry(nombre: nombre, ruta: destino.path, bookmark: nil, clase: .copia, escritura: .permitida,
                           exclusionesCopia: privadas)
        try! registro.upsert(e)
        return e
    }

    /// El modelo de la ventana, como lo abre la app, con este banco.
    func modelo(_ peticion: PeticionPuestaEnMarcha) -> ModeloPuesta {
        let m = ModeloPuesta(peticion: peticion, registro: registro, appSupport: appSupport, persona: "Manu")
        configurar(m)
        return m
    }

    func configurar(_ m: ModeloPuesta) {
        m.registro = registro
        m.appSupport = appSupport
        m.empresas = empresas
        m.entorno = entorno
        m.ventana = AccionesVentana(abrirEmpresa: { [unowned self] in self.abiertas.append($0) },
                                    abrirSelector: { [unowned self] in self.selector += 1 },
                                    cerrar: { [unowned self] in self.cerrada += 1 })
    }
}

/// Paneles que contestan solos (lo que la prueba deje preparado).
@MainActor
final class PanelesFalsos: PanelesPuesta {
    var carpeta: URL?
    var dentro: [VaultPath] = []
    var fichero: URL?
    var pedidos: [String] = []

    func elegirCarpeta(mensaje: String) -> URL? { pedidos.append("carpeta"); return carpeta }
    func elegirDentro(de raiz: URL, mensaje: String) -> [VaultPath] { pedidos.append("dentro"); return dentro }
    func elegirFichero(mensaje: String, tipos: [String]) -> URL? { pedidos.append("fichero"); return fichero }
}

/// Claude Code falso: nunca se lanza el de verdad.
final class DetectorFalso: DetectorClaude, @unchecked Sendable {
    var hay = true
    let lanzadorFalso = LanzadorEntrevistaFalso(salida: #"{"vaga":true,"repregunta":"¿Con qué número lo medirás?"}"#)

    func detectar() async -> EstadoClaude { hay ? .encontrado(version: "2.1.307", aviso: nil) : .noEncontrado }
    func probar(estado: URL, negadas: [URL]) async -> EstadoClaude { .probado(ok: hay, texto: hay ? "Funciona." : "No ha contestado.") }
    func lanzador(estado: URL, negadas: [URL]) async -> (any LanzadorEntrevista)? { hay ? lanzadorFalso : nil }
}

final class LanzadorEntrevistaFalso: LanzadorEntrevista, @unchecked Sendable {
    let salida: String
    private let lock = NSLock()
    private var _mensajes: [String] = []
    var mensajes: [String] { lock.withLock { _mensajes } }

    init(salida: String) { self.salida = salida }

    func pedir(_ mensaje: String, esquema: String) async throws -> String {
        lock.withLock { _mensajes.append(mensaje) }
        return salida
    }
}

/// Una ventana que nunca se enseña con el flujo dentro: así se pintan las pantallas de verdad (y sus `.task`).
@MainActor
final class VentanaDePrueba {
    let hosting: NSHostingView<AnyView>
    let ventana: NSWindow

    init(_ modelo: ModeloPuesta, ancho: CGFloat = 920, alto: CGFloat = 1100, oscuro: Bool = false) {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let apariencia = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        hosting = NSHostingView(rootView: AnyView(OnboardingFlujo(modelo: modelo).frame(width: ancho, height: alto)
            .background(TLSPaleta.fondo.color)))
        hosting.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        hosting.appearance = apariencia
        ventana = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        ventana.appearance = apariencia
        ventana.contentView = hosting
        ventana.isReleasedWhenClosed = false
    }

    /// Deja que SwiftUI pinte y que corran las tareas de la pantalla.
    func pintar(_ vueltas: Int = 3) async {
        for _ in 0..<vueltas {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    func png() -> Data? {
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    func cerrar() { ventana.close() }
}

/// Respuestas de serie (el peor caso para contar pantallas: todas las áreas activas y todo contestado).
@MainActor
enum Respuestas {
    static func deSerie(_ q: Pregunta) -> ValorRespuesta? {
        switch q.id {
        case .como: return .opcion("cero")
        case .nombreEmpresa: return .texto("Estudio Prueba")
        case .yo: return .texto("Ana Prueba")
        case .alcance: return .opcion("todo")
        case .asistente: return .siNo(false)
        case .embudo: return .opcion("serie")
        case .planEntrega: return .opcion("crear")
        case .logo: return .opcion("aun-no")
        case .objetivo: return .opcion("sin-objetivo")
        case .recorrido: return .opcion("ahora")
        case .destino: return .texto("Facturar 120.000 € en 2028 con tres personas en el equipo")
        default: break
        }
        let s = q.id.rawValue
        if s.hasSuffix(".estado") { return .opcion("activa") }
        if s.hasPrefix("organizar.sistema.") { return .opcion("montado") }
        if s.hasSuffix(".montado") { return .opcion("si") }
        if s.hasPrefix("numeros."), s.hasSuffix(".meta") { return .numero(100) }
        if s.hasSuffix(".alerta") { return .numero(50) }
        switch q.tipo {
        case .eleccion(let o): return o.first.map { .opcion($0.id) }
        case .escala(let a, let b, _, _): return .escala((a + b) / 2)
        case .siNo: return .siNo(s.contains(".etapa.") ? (Int(s.suffix(1)) ?? 9) < 3 : false)
        case .textoCorto: return .texto("respuesta concreta de prueba para \(s.split(separator: ".").last ?? "")")
        case .textoLibre: return .texto("Cada mes pasa lo mismo con los encargos de los clientes nuevos")
        case .cifra(let u, _): return .numero(u == "€" ? 150 : u == "min" ? 30 : u == "h" ? 4 : 3)
        case .hora: return .texto("09:00")
        case .rutas: return nil
        }
    }

    /// Contesta lo que falte en la pantalla actual como lo haría la persona: los textos se escriben en el campo
    /// (borrador) y se guardan al pulsar el botón; lo demás se elige. Lo premarcado se deja.
    static func contestarPantalla(_ m: ModeloPuesta, usar: (Pregunta) -> ValorRespuesta? = { _ in nil }) async {
        for _ in 0..<7 {
            var algo = false
            for q in m.preguntas where m.motor.estado.respuesta(q.id) == nil && m.borradores[q.id] == nil {
                let propio = usar(q)
                guard propio != nil || (q.premarcada == nil && !q.esOpcional) else { continue }
                guard let v = propio ?? deSerie(q) else { continue }
                switch v {
                case .texto(let t): m.borradores[q.id] = t; await m.guardarBorrador(q.id)
                case .numero(let n): m.borradores[q.id] = FormatoBase.cifraParaEditar(n); await m.guardarBorrador(q.id)
                case .noLoSe: m.noLoSeYGuardar(q.id)
                default: await m.contestar(q.id, v)
                }
                algo = true
            }
            if !algo { break }
        }
    }
}

/// El recorrido de las pantallas pulsando los botones de verdad (`pulsarPrincipal`), pintando cada una.
@MainActor
struct Recorrido {
    var vistas: [String] = []
    var pintadas: [String] = []
    var aplicados: [PasoPuesta] = []

    /// Recorre hasta el final. `ordenar` simula el rol de ordenar (registra sus pantallas al llegar a la última).
    static func hasta(fin m: ModeloPuesta, ventana: VentanaDePrueba?, banco: Banco,
                      usar: (Pregunta) -> ValorRespuesta? = { _ in nil },
                      antesDeAplicar: ((ModeloPuesta) async -> Void)? = nil,
                      alAplicar: ((ModeloPuesta) -> Void)? = nil,
                      enPantalla: ((ModeloPuesta, VentanaDePrueba?) async throws -> Void)? = nil) async throws -> Recorrido {
        var r = Recorrido()
        for _ in 0..<200 {
            guard !m.terminada, let p = m.pantalla else { break }
            if r.vistas.last != p.id { r.vistas.append(p.id) }
            if let ventana { await ventana.pintar() } else { m.alPintar(p) }
            try await enPantalla?(m, ventana)
            await Respuestas.contestarPantalla(m, usar: usar)
            // Sin pintar las pantallas de ordenar no hay vista previa: el paso se da por aplicado (como «Aplicar» del pie).
            if p.paso == .ordenar, p.aplicaAqui || m.accionPrincipal == .aplicarOrdenar, !m.pasoHecho(.ordenar) {
                let n = m.motor.pantallas(de: .ordenar).count
                m.actualizar { $0.registrarOrdenar(ResumenOrdenar(pantallas: n, texto: "Ordenado (prueba)"), aplicado: true) }
            }
            if m.accionPrincipal == .aplicar { await antesDeAplicar?(m) }
            let accion = m.accionPrincipal
            await m.pulsarPrincipal()
            if let e = m.error, m.pantalla?.id == p.id, m.aplicado == nil {
                Issue.record("Se quedó en \(p.id) con «\(e)» (faltan: \(m.faltan))")
                break
            }
            if [.aplicar, .crearCarpeta, .hacerCopia].contains(accion), m.pasoHecho(p.paso) {
                r.aplicados.append(p.paso)
                alAplicar?(m)
                // Tras aplicar se queda en la pantalla con el resumen: «Siguiente».
                if !m.terminada, m.pantalla?.id == p.id { await m.pulsarPrincipal() }
            }
        }
        r.pintadas = m.pintadas
        return r
    }
}

/// Huella de un árbol (ruta, tamaño y SHA-256 de cada fichero, también los ocultos): cualquier escritura la cambia.
func huellaDeArbol(_ root: URL) -> [String] {
    let fm = FileManager.default
    let base = root.resolvingSymlinksInPath().path
    guard let e = fm.enumerator(at: root.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return [] }
    var out: [String] = []
    for case let u as URL in e {
        guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
        let rel = String(u.resolvingSymlinksInPath().path.dropFirst(base.count))
        let d = (try? Data(contentsOf: u)) ?? Data()
        out.append("\(rel) \(d.count) \(SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined())")
    }
    return out.sorted()
}
