import Foundation
import Testing
@testable import TLSCore

/// Corrector final de F3: lo que arregló de la revisión de experiencia en el motor de la puesta en marcha. Todo en
/// temporales (Ribera y la fixture copiadas); nunca se lanza Claude.
@Suite("Revisión final F3 · motor", .serialized)
struct RevisionFinalF3MotorTests {
    @Test("P1 · «Qué funciona sin ti» pregunta por los mismos sistemas que Organizar y no vuelve a preguntar si está montado")
    func mismosSistemas() async throws {
        let env = PuestaApoyo.ribera()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        await m.responder(.sistema("VE2"), .opcion("montado"))
        await m.responder(.sistema("VE3"), .opcion("falta"))
        await m.responder(.sistema("FI1"), .opcion("a medias"))
        let codigos = m.sistemasSinTi.map(\.codigo)
        // Los de Organizar (con sus nombres), menos los que faltan.
        #expect(codigos.contains("VE2") && !codigos.contains("VE3"))
        #expect(m.sistemasSinTi.allSatisfy { SistemaCatalogo.codigo($0.codigo) != nil })
        let pantallas = m.pantallas(de: .sinTi).filter { $0.tipo != .vistaPrevia }
        let ids = pantallas.flatMap(\.preguntas)
        #expect(!ids.contains { $0.rawValue.hasSuffix(".montado") }, "«¿Lo tienes montado?» ya se contestó en Organizar")
        #expect(m.visible(.sinTi("VE2")) && m.visible(.automatizar("VE2")))
        #expect(!m.visible(.sinTi("FI1")), "A medias: nada que preguntar")
        // En la copia (organizada), todo en una pantalla: «Tus seis áreas», no «Dirección y Ventas y…».
        #expect(pantallas.count == 1)
        #expect(!(pantallas.first?.titulo.contains(" y Ventas y ") ?? true))
        // El estándar: Embudo cubre VEN-2 y VEN-3.
        #expect(SistemaCatalogo.codigo("VE2")?.estandar == ["VEN-2", "VEN-3"])
        #expect(SistemaCatalogo.deEstandar("FIN-1")?.codigo == "FI1")
    }

    @Test("P1 · «Quedan ~N min» cuenta las preguntas en blanco de un resumen; Hoy dice lo mismo que la ventana")
    func minutosPorPregunta() async throws {
        let env = PuestaApoyo.g3()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        let id = UUID()
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env, entrada: PuestaApoyo.entradaG3(env)), vaultID: id, asup: asup)
        m.ir(a: "conocer.resumen")
        let p = try #require(m.pantallaActual)
        let blancas = m.enBlanco(p).filter { !$0.esOpcional }
        #expect(!blancas.isEmpty)
        let conBlancas = m.minutos(de: p)
        m.contestarLuego(blancas.map(\.id))
        #expect(m.minutos(de: p) < conBlancas)
        m.ir(a: "conocer.resumen")
        let hoy = try #require(ProgresoPuestaEnMarcha.leer(vaultID: id, appSupport: asup))
        #expect(hoy.quedanMinutos == m.quedanMinutos)
    }

    @Test("P2 · El ejemplo, al repasarlo, está completo (PLAN §6.8): ninguna pregunta obligatoria en blanco")
    func ejemploCompleto() async throws {
        let env = PuestaApoyo.ribera()
        defer { env.limpiar() }
        var demo = env.entry
        demo.clase = .demo
        let m = OnboardingEngine.ejemploCompletado(contexto: PuestaApoyo.contexto(env, entrada: demo), vaultID: UUID())
        for p in m.pantallas {
            let vacias = m.preguntas(de: p).filter { !$0.esOpcional && m.estado.respuesta($0.id) == nil }
            #expect(vacias.isEmpty, "\(p.id): \(vacias.map(\.id.rawValue))")
        }
    }

    @Test("P2 · En una empresa nueva, el alcance llega premarcado con un motivo cierto (no «ya está organizada»)")
    func alcanceEmpresaNueva() async throws {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(.vacio(reloj: PuestaApoyo.relojRibera), asup: asup)
        await m.responder(.como, .opcion("cero"))
        let pre = try #require(m.pregunta(.alcance)?.premarcada)
        #expect(pre.valor == .opcion("todo"))
        #expect(!pre.origen.texto.contains("organizada"), "\(pre.origen.texto)")
    }

    @Test("P2 · La alerta se llama «Sin alerta» en Metas y se lee igual que «Sin meta»")
    func sinAlerta() async throws {
        let r = try await RevisionF3DatosPuestaTests.recorrerRibera([.alerta(.ventas): .opcion("sin-meta")])
        defer { r.env.limpiar(); Apoyo.limpiar(r.asup) }
        let metas = try #require(r.env.texto("1 · Dirección/Metas.md"))
        #expect(metas.contains("| Sin alerta |"), "\(metas)")
    }

    @Test("Datos · Lo pendiente de antes de una importación no se marca como importado: se queda pendiente")
    func pendienteDeAntes() async throws {
        let c = try DominioApoyo.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        let ev = EventoDominio(tipo: .contactoCreado, entidad: "contacto-de-antes", ruta: VaultPath("2 · Ventas/Contactos/x.md"),
                               autor: .persona("Manu"))
        _ = try motor.estado.encolar(ev)
        await motor.setModoImportacion(true)
        _ = await motor.procesarPendientes()
        let guardado = try #require(try motor.estado.eventos().first { $0.evento.clave == ev.clave })
        #expect(guardado.estado == EstadoEvento.pendiente, "\(guardado.estado.rawValue) \(guardado.motivo ?? "")")
        await motor.setModoImportacion(false)
    }

    @Test("Lo marcado como privado al ordenar se apunta en `privado:` de los ajustes (sin repetir ni romper el YAML)")
    func configConPrivado() throws {
        let base = "version: 1\nprivado: [Personal]\nhoy: 2026-10-19\n"
        let nuevo = try #require(VaultLayout.configConPrivado(base, anadir: [VaultPath("Otro expediente"), VaultPath("Personal/Salud")]))
        #expect(VaultLayout.configPrivado(Data(nuevo.utf8)) == ["Personal", "Otro expediente"])
        #expect(nuevo.contains("hoy: 2026-10-19"))
        let creado = try #require(VaultLayout.configConPrivado(nil, anadir: [VaultPath("A: con dos puntos")]))
        #expect(VaultLayout.configPrivado(Data(creado.utf8)) == ["A: con dos puntos"])
        #expect(VaultLayout.configConPrivado("privado: [sin cerrar\n", anadir: [VaultPath("X")]) == nil)
    }
}
