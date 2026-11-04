import Foundation
import Testing
@testable import TLSCore

// Revisión adversarial de datos y privacidad de F3 (motor de la puesta en marcha). Lo que fallaba ya está arreglado
// (corrector final): las pruebas comprueban que no vuelve. Todo en temporales (Ribera copiada); nunca se lanza Claude.

@Suite("Revisión F3 · motor de la puesta en marcha", .serialized)
struct RevisionF3DatosPuestaTests {
    // MARK: onboarding.json

    /// Reescribe `onboarding.json` con `cambio` aplicado al JSON.
    static func tocarJSON(_ url: URL, _ cambio: (inout [String: Any]) -> Void) throws {
        var raiz = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        cambio(&raiz)
        try JSONSerialization.data(withJSONObject: raiz, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    @Test("onboarding.json con una respuesta que no se entiende: se salta esa y se conservan las demás")
    func respuestaIlegibleBorraTodo() async throws {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        let id = UUID()
        var m = PuestaApoyo.motor(.vacio(reloj: PuestaApoyo.relojRibera), vaultID: id, asup: asup)
        await m.responder(.como, .opcion("cero"))
        _ = m.siguiente()
        await m.responder(.nombreEmpresa, .texto("Estudio Prueba"))
        await m.responder(.yo, .texto("Ana"))
        let almacen = AlmacenPuesta(vaultID: id, appSupport: asup)
        #expect(almacen.leer()?.respuestas.count == 3)
        // Una respuesta como la escribiría otra versión de la app (un tipo de respuesta que esta no conoce).
        try Self.tocarJSON(almacen.url) { raiz in
            var respuestas = raiz["respuestas"] as? [String: Any] ?? [:]
            respuestas["conocer.futura"] = ["valor": ["intervalo": ["_0": [1, 5]]],
                                            "origen": ["clase": "persona", "texto": "Lo dijiste tú"],
                                            "confirmada": true, "repreguntada": false, "fecha": "2026-10-19T09:00:00Z"]
            raiz["respuestas"] = respuestas
        }
        let reabierta = OnboardingEngine.abrir(vaultID: id, contexto: .vacio(reloj: PuestaApoyo.relojRibera), almacen: almacen)
        let texto = (try? String(contentsOf: almacen.url, encoding: .utf8)) ?? ""
        #expect(reabierta.valor(.nombreEmpresa)?.texto == "Estudio Prueba")
        #expect(texto.contains("Estudio Prueba"), "El fichero se ha sobrescrito sin las respuestas")
        #expect(reabierta.estado.respuesta(PreguntaID("conocer.futura")) == nil)
    }

    @Test("onboarding.json que no se puede leer: no se pisa, se aparta al lado antes de empezar de cero")
    func ficheroIlegibleSeAparta() async throws {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        let id = UUID()
        let almacen = AlmacenPuesta(vaultID: id, appSupport: asup)
        try FileManager.default.createDirectory(at: almacen.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ esto no es json".utf8).write(to: almacen.url)
        #expect(almacen.ilegible)
        let m = OnboardingEngine.abrir(vaultID: id, contexto: .vacio(reloj: PuestaApoyo.relojRibera), almacen: almacen)
        #expect(m.estado.respuestas.isEmpty)
        let apartados = try FileManager.default.contentsOfDirectory(atPath: almacen.url.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(AlmacenPuesta.nombreFichero + ".ilegible-") }
        #expect(apartados.count == 1, "\(apartados)")
        let guardado = try #require(apartados.first)
        let original = try String(contentsOf: almacen.url.deletingLastPathComponent().appendingPathComponent(guardado), encoding: .utf8)
        #expect(original == "{ esto no es json")
        #expect(almacen.leer() != nil)
    }

    @Test("onboarding.json de antes (respuestas sin «repreguntada»): se conservan todas las respuestas")
    func respuestasDeOtraVersion() async throws {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        let id = UUID()
        var m = PuestaApoyo.motor(.vacio(reloj: PuestaApoyo.relojRibera), vaultID: id, asup: asup)
        await m.responder(.como, .opcion("cero"))
        _ = m.siguiente()
        await m.responder(.nombreEmpresa, .texto("Estudio Prueba"))
        let almacen = AlmacenPuesta(vaultID: id, appSupport: asup)
        try Self.tocarJSON(almacen.url) { raiz in
            var respuestas = raiz["respuestas"] as? [String: Any] ?? [:]
            for (k, v) in respuestas {
                guard var r = v as? [String: Any] else { continue }
                r["repreguntada"] = nil
                respuestas[k] = r
            }
            raiz["respuestas"] = respuestas
        }
        let reabierta = OnboardingEngine.abrir(vaultID: id, contexto: .vacio(reloj: PuestaApoyo.relojRibera), almacen: almacen)
        #expect(reabierta.estado.respuestas.count == 2, "\(reabierta.estado.respuestas.keys.sorted())")
    }

    // MARK: Paso 4 · Qué funciona sin ti

    /// Recorre Ribera con estas respuestas, aplicando de verdad cada paso.
    static func recorrerRibera(_ elegidas: [PreguntaID: ValorRespuesta]) async throws
        -> (config: String, vistas: [PasoPuesta: VistaPreviaPaso], env: EntornoCarpeta, asup: URL) {
        let env = PuestaApoyo.ribera()
        let asup = PuestaApoyo.appSupport()
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        let bus = try await env.bus()
        var vistas: [PasoPuesta: VistaPreviaPaso] = [:]
        try await PuestaApoyo.recorrer(&m, respuesta: { elegidas[$0.id] }) { m, paso in
            try await AplicarPuestaTests.aplicarYComprobar(env, &m, paso, bus: bus, vistas: &vistas)
        }
        await bus.writer.close()
        return (env.texto(".tls/config.yaml") ?? "", vistas, env, asup)
    }

    /// Las líneas de `capacidades:` que escribió la puesta en marcha (las de hoy).
    static func capacidadesNuevas(_ config: String) -> [String] {
        config.components(separatedBy: "\n").filter { $0.hasPrefix("  ") && $0.contains("declarada") && $0.contains("desde: 2026-10-19") }
    }

    @Test("«¿Funciona sin ti?» Sí y «¿Lo dejo a un asistente?» No: no se apunta ningún asistente (IA) sin su «Sí»")
    func asistenteSinConsentimiento() async throws {
        // Por sistema de Organizar: Rumbo y mapa (DIR-1), Oferta (VEN-1 y VEN-4), Facturación y cobros (FIN-1).
        let r = try await Self.recorrerRibera([
            .sinTi("DI3"): .siNo(true), .automatizar("DI3"): .siNo(false),
            .sinTi("VE1"): .siNo(true), .automatizar("VE1"): .siNo(false),
            .sinTi("FI1"): .siNo(true), .automatizar("FI1"): .siNo(false),
        ])
        defer { r.env.limpiar(); Apoyo.limpiar(r.asup) }
        let lineas = Self.capacidadesNuevas(r.config)
        #expect(!lineas.isEmpty, "\(r.config)")
        let sinSupervisar = lineas.filter { $0.contains("ejecutor: IA") && !$0.contains("modo: supervisado") }
        #expect(sinSupervisar.isEmpty, "\(sinSupervisar)")
        let deEstos = lineas.filter { l in ["DIR-02:", "VEN-10:", "FIN-02:"].contains { l.contains($0) } }
        #expect(deEstos.count == 3, "\(lineas)")
        #expect(deEstos.allSatisfy { !$0.contains("ejecutor: IA") && $0.contains("sin_ti: si") }, "\(deEstos)")
    }

    @Test("«No lo sé» en «¿Funciona sin ti?» no se escribe PENDIENTE: queda «ejecutor: H» como si dijera que no")
    func noLoSeEnSinTi() async throws {
        let r = try await Self.recorrerRibera([.sistema("FI1"): .opcion("montado"), .sinTi("FI1"): .noLoSe])
        defer { r.env.limpiar(); Apoyo.limpiar(r.asup) }
        let fin = Self.capacidadesNuevas(r.config).filter { l in ["FIN-02:", "FIN-03:", "FIN-04:", "FIN-10:"].contains { l.contains($0) } }
        #expect(!fin.isEmpty, "\(r.config)")
        #expect(fin.allSatisfy { $0.contains("ejecutor: \(TextoPuesta.pendiente)") }, "\(fin)")
    }

    @Test("«No lo sé» en «¿Qué número miras?» no deja PENDIENTE en ningún sitio (el área se salta)")
    func noLoSeEnNumeroClave() async throws {
        let r = try await Self.recorrerRibera([.numeroClave(.ventas): .noLoSe])
        defer { r.env.limpiar(); Apoyo.limpiar(r.asup) }
        func pendientes(_ s: String?) -> Int { (s ?? "").components(separatedBy: TextoPuesta.pendiente).count - 1 }
        let anade = r.vistas[.numeros]?.cambios.contains { pendientes($0.despues) > pendientes($0.antes) } ?? false
        #expect(anade, "\(r.vistas[.numeros]?.cambios.map(\.ruta.raw) ?? [])")
        #expect(r.env.texto("2 · Ventas/Área.md")?.contains("numero_clave: \(TextoPuesta.pendiente)") == true)
    }
}
