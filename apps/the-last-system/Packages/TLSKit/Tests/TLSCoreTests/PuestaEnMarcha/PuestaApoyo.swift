import Foundation
import Testing
@testable import TLSCore

/// Ayudas de las pruebas de la puesta en marcha (F3 · rol motor). Todo en temporales: Ribera y la fixture se copian.
enum PuestaApoyo {
    static let manu = Autor.persona("Manu")
    static var relojRibera: Reloj { relojDePrueba(2026, 10, 19) }

    /// Estado de la app (Application Support) en un temporal.
    static func appSupport() -> URL { Apoyo.tempDir("asup-puesta") }

    /// Copia de Ribera registrada como copia (la puesta en marcha se hace sobre una copia).
    static func ribera() -> EntornoCarpeta { EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .copia) }

    /// Copia de la fixture con formato G3 (sin propiedades en `Área.md`, «Privado» como carpeta privada).
    static func g3() -> EntornoCarpeta {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima, nombre: "Estudio", clase: .copia)
        return env
    }

    static func entradaG3(_ env: EntornoCarpeta) -> VaultEntry {
        var e = env.entry
        e.exclusionesCopia = ["Privado"]
        return e
    }

    static func contexto(_ env: EntornoCarpeta, entrada: VaultEntry? = nil, reloj: Reloj? = nil) -> ContextoCarpeta {
        ContextoCarpeta.leer(env.root, entrada: entrada ?? env.entry, reloj: reloj ?? relojRibera)
    }

    static func motor(_ contexto: ContextoCarpeta, vaultID: UUID = UUID(), asup: URL,
                      entrevista: InterviewEngine = InterviewEngine()) -> OnboardingEngine {
        OnboardingEngine.abrir(vaultID: vaultID, contexto: contexto, almacen: AlmacenPuesta(vaultID: vaultID, appSupport: asup),
                               entrevista: entrevista)
    }

    /// Respuesta de serie para una pregunta (el «peor caso» para contar pantallas: todas las áreas activas).
    static func porDefecto(_ q: Pregunta, raiz: URL? = nil) -> ValorRespuesta {
        switch q.id {
        case .como: return .opcion("cero")
        case .modo: return .opcion("copia")
        case .privadas: return .opcion("no")
        case .origen: return .rutas([raiz?.path ?? "/private/tmp"])
        case .privadasCuales: return .rutas(["Privado"])
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
        case .rutinaHora: return .texto("09:00")
        default: break
        }
        let s = q.id.rawValue
        if s.hasSuffix(".estado") { return .opcion("activa") }
        if s.hasPrefix("organizar.sistema.") { return .opcion("montado") }
        if s.hasSuffix(".montado") { return .opcion("si") }
        if s.hasPrefix("conectar.") && q.tipo != .siNo { return .opcion("ahora-no") }
        if s.hasSuffix(".meta") && s.hasPrefix("numeros.") { return .numero(100) }
        if s.hasSuffix(".alerta") { return .numero(50) }
        switch q.tipo {
        case .eleccion(let o): return .opcion(o.first?.id ?? "")
        case .escala(let a, let b, _, _): return .escala((a + b) / 2)
        case .siNo: return .siNo(s.contains(".etapa.") ? (Int(s.suffix(1)) ?? 9) < 3 : false)
        case .textoCorto: return .texto("respuesta concreta de prueba para \(s.split(separator: ".").last ?? "")")
        case .textoLibre: return .texto("Cada mes pasa lo mismo con los encargos de los clientes nuevos")
        case .cifra(let u, _): return .numero(u == "€" ? 150 : u == "min" ? 30 : u == "h" ? 4 : 3)
        case .hora: return .texto("09:00")
        case .rutas: return .rutas([])
        }
    }

    /// Recorre la puesta en marcha de principio a fin. Contesta con `respuesta` (si da `nil`, lo premarcado se da
    /// por bueno; si no hay premarcado, la respuesta de serie). En cada «Aplicar» llama a `aplicar`. Devuelve las
    /// pantallas que se vieron, en orden.
    @discardableResult
    static func recorrer(_ m: inout OnboardingEngine, raiz: URL? = nil,
                         respuesta: (Pregunta) -> ValorRespuesta? = { _ in nil },
                         aplicar: (inout OnboardingEngine, PasoPuesta) async throws -> Void) async throws -> [Pantalla] {
        var vistas: [Pantalla] = []
        for _ in 0..<300 {
            guard let p = m.pantallaActual else { break }
            if vistas.last?.id != p.id { vistas.append(p) }
            // Dos pasadas: al contestar aparecen las preguntas condicionadas.
            for _ in 0..<7 {
                var algo = false
                for q in m.preguntas(de: p) where m.estado.respuesta(q.id) == nil {
                    if let v = respuesta(q) { await m.responder(q.id, v); algo = true }
                    else if q.premarcada == nil, !q.esOpcional { await m.responder(q.id, porDefecto(q, raiz: raiz)); algo = true }
                }
                if !algo { break }
            }
            switch m.siguiente() {
            case .pantalla: continue
            case .terminada: return vistas
            case .faltan(let f): Issue.record("Faltan respuestas en \(p.id): \(f)"); return vistas
            case .faltaAplicar(let paso): try await aplicar(&m, paso)
            }
        }
        Issue.record("El recorrido no terminó")
        return vistas
    }

    /// «Aplicar» sin escribir (para contar pantallas): el paso queda hecho.
    static func aplicarSinEscribir(_ m: inout OnboardingEngine, _ paso: PasoPuesta) {
        if paso == .ordenar {
            let n = m.ruta == .copiaG3 ? 3 : 7
            m.registrarOrdenar(ResumenOrdenar(pantallas: n, texto: "Prueba"), aplicado: true)
        } else {
            m.marcarAplicado(paso, plan: nil, resumen: "Prueba")
        }
    }

    /// Ficheros de la carpeta con su huella, tamaño y fecha (también los ocultos): cualquier escritura la cambia.
    static func huella(_ root: URL) -> [String] { Apoyo.huellaDeArbol(root) }
}

/// Lanzador falso del entrevistador (nunca se lanza Claude en las pruebas).
final class LanzadorFalso: LanzadorEntrevista, @unchecked Sendable {
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

/// Vigilante de escrituras (criterio F3-1): FSEvents sobre la carpeta, contando lo que llega.
final class VigilanteEscrituras: @unchecked Sendable {
    private let lock = NSLock()
    private var _eventos: [VaultWatcher.Event] = []
    private var watcher: VaultWatcher!

    var eventos: [VaultWatcher.Event] { lock.withLock { _eventos } }

    init(_ root: URL) {
        watcher = VaultWatcher(root: root, latency: 0.1, settle: 0.2) { [weak self] e in
            guard let self else { return }
            self.lock.withLock { self._eventos.append(e) }
        }
    }

    func empezar() { watcher.start() }
    func parar() { watcher.stop() }

    /// Espera a que FSEvents entregue lo pendiente.
    static func esperar(_ s: Double = 1.5) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
}
