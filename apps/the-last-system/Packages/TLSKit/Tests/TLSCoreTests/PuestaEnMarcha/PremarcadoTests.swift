import Foundation
import Testing
@testable import TLSCore

/// Lo premarcado sale de la carpeta con su origen («Lo saqué de Rumbo.md») o es una propuesta de la app (la meta
/// 1,2 × los últimos 90 días); nunca de lo privado.
@Suite("Puesta en marcha · premarcado")
struct PremarcadoTests {
    @Test("La propuesta de la nota Metas («Propuesta: meta 3 meses, alerta 1 mes»)")
    func propuestaDeMetas() {
        #expect(OnboardingEngine.propuestaDeMetas("Propuesta: meta 3 meses, alerta 1 mes", meta: true) == 3)
        #expect(OnboardingEngine.propuestaDeMetas("Propuesta: meta 3 meses, alerta 1 mes", meta: false) == 1)
        #expect(OnboardingEngine.propuestaDeMetas("Propuesta: meta 2,5 meses, alerta 1 mes", meta: true) == 2.5)
        #expect(OnboardingEngine.propuestaDeMetas("Propuesta: meta 0 €; alerta con una sola factura vencida", meta: false) == nil)
        #expect(OnboardingEngine.propuestaDeMetas("Alerta: dos meses seguidos por debajo", meta: true) == nil)
    }

    @Test("Meta propuesta: 1,2 × lo de los últimos 90 días, marcada como propuesta; lo decidido en Metas manda")
    func metaPropuesta() async throws {
        let env = PuestaApoyo.ribera()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        // Con la meta decidida en Metas, eso (de la carpeta).
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        let decidida = try #require(m.pregunta(.meta(.ventas))?.premarcada)
        #expect(decidida.valor == .numero(6000))
        #expect(decidida.origen.clase == .carpeta)
        // Sin meta en Metas: la propuesta con la cuenta de los últimos 90 días.
        let metas = try #require(env.texto("1 · Dirección/Metas.md"))
        env.escribir("1 · Dirección/Metas.md", metas.replacingOccurrences(of: "| VEN-WON | Ventas cobradas del mes | 6000 € | 3000 € |",
                                                                             with: "| VEN-WON | Ventas cobradas del mes |  |  |"))
        m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        let base = try #require(m.contexto.base90Dias("VEN-WON"))
        #expect(base > 0)
        let p = try #require(m.pregunta(.meta(.ventas))?.premarcada)
        #expect(p.origen.clase == .propuesta)
        #expect(p.origen.texto.hasPrefix("Propuesto: 1,2 × lo de los últimos 90 días"))
        #expect(p.valor == .numero(((base * 1.2) / 10).rounded() * 10))
        #expect(m.pregunta(.alerta(.ventas))?.premarcada?.origen.clase == .propuesta)
        // Lo propuesto, aceptado tal cual, sí se escribe (no viene de la carpeta).
        await m.responder(.meta(.ventas), p.valor)
        #expect(m.estado.respuesta(.meta(.ventas))?.origen.clase == .propuesta)
    }

    @Test("De la carpeta: la frase de Rumbo, la oferta, el logo y los sistemas; lo privado no")
    func deLaCarpeta() throws {
        let env = PuestaApoyo.g3()
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Rumbo.md", """
        # Rumbo

        ## Qué es la empresa
        Ayudamos a comercios de barrio a conseguir una web que vende en dos semanas con plantillas probadas, sin tecnicismos.

        ## Adónde vamos
        Llegar a 50 clientes en 2028.
        """)
        env.escribir("5 · Marca/Recursos/logo-estudio.svg", "<svg/>")
        env.escribir("5 · Marca/Secreto/logo-privado.png", "x")
        env.escribir(".tls/config.yaml", "version: 1\nclase: copia\nprivado: [\"5 · Marca/Secreto\"]\n")
        let ctx = PuestaApoyo.contexto(env, entrada: PuestaApoyo.entradaG3(env))
        #expect(ctx.premarcada(.fraseCliente)?.valor == .texto("comercios de barrio"))
        #expect(ctx.premarcada(.frasePlazo)?.valor == .texto("dos semanas"))
        #expect(ctx.premarcada(.fraseDolor)?.valor == .texto("tecnicismos"))
        #expect(ctx.premarcada(.fraseCliente)?.origen.texto == "Lo saqué de Rumbo.md")
        #expect(ctx.premarcada(.destino)?.valor == .texto("Llegar a 50 clientes en 2028."))
        #expect(ctx.referencia(.fraseCliente)?.hasPrefix("En Rumbo.md pone:") == true)
        #expect(ctx.logo?.raw == "5 · Marca/Recursos/logo-estudio.svg")
        #expect(ctx.premarcada(.logo)?.valor == .opcion("tengo"))
        #expect(ctx.sistemasConFicha["VE2"]?.raw == "2 · Ventas/Sistemas/Embudo.md")
        #expect(ctx.sistemasConFicha["EN2"]?.raw == "3 · Entrega/Sistemas/Seguimiento de proyectos.md", "Por su nombre de G3")
        #expect(ctx.nombresPrivados.contains("Privado"))
        #expect(ctx.nombresPrivados.contains("Secreto"))
        // Nada de lo premarcado sale de lo privado.
        #expect(!(ctx.foto?.files.contains { $0.raw.hasPrefix("Privado") } ?? true), "La copia no ve lo privado")
        // Los estados de G3 vienen de la línea «**Estado:**».
        #expect(ctx.premarcada(.estadoArea(.ventas))?.valor == .opcion("preparada"))
        #expect(ctx.premarcada(.ocupante(.finanzas))?.valor == .texto("Ana y el asistente Contable"))
    }

    @Test("Ribera: la oferta y los servicios premarcados con su precio")
    func oferta() {
        let env = PuestaApoyo.ribera()
        defer { env.limpiar() }
        let ctx = PuestaApoyo.contexto(env)
        #expect(ctx.servicios.map(\.nombre) == ["Renta", "Trimestrales"])
        #expect(ctx.premarcada(.ofertaNombre(1))?.valor == .texto("Renta"))
        #expect(ctx.premarcada(.ofertaPrecio(1))?.valor == .numero(90))
        #expect(ctx.premarcada(.planEntrega)?.valor == .opcion("tengo"))
    }
}
