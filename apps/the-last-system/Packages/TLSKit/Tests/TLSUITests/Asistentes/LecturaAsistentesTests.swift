import Foundation
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSUI

/// Lo que enseñan Asistentes y la ficha de cada asistente, leído de una copia de Ribera: quién está activo, cómo está
/// (trabajando, en cola, esperando tu respuesta, en reposo, en pausa o apagado), lo último que hizo, su próxima rutina y
/// el uso del mes como parte de su tope (y «Simulado» en lo del ejemplo).
@Suite("Asistentes · lo que se lee", .serialized)
@MainActor
struct LecturaAsistentesTests {
    @Test("Ribera: los ocho de serie, cinco activos, cada uno con su estado, lo último de la Bitácora (simulado) y su próxima rutina")
    func ribera() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        let l = try await a.leer()
        #expect(l.asistentes.map(\.slug) == ["mika", "comercial", "implementador", "contable", "marca", "equipo", "cartero", "ordenador"])
        #expect(l.asistentes.filter(\.activo).map(\.slug) == ["mika", "comercial", "implementador", "contable", "ordenador"])
        #expect(l.interruptor && l.pausaAreas.isEmpty && l.demo && !l.hayGobierno)
        #expect(l.hoy == LocalDate(parsing: "2026-10-19"))

        let mika = try #require(l.asistente("agente:mika"))
        #expect(mika.coordinador && mika.estadoGuardado == .enReposo)
        // Lunes 9:30: el resumen de la semana ya pasó; lo próximo es «¿Algo rojo?» de mañana.
        #expect(mika.proxima?.nombre == "¿Algo rojo?" && mika.proxima?.soloSiHayRojo == true)
        #expect(mika.proxima.map { FormatoAsistentes.cuando($0.fecha, zona: l.zona, hoy: l.hoy) } == "mañana a las 08:45")

        let comercial = try #require(l.asistente("comercial"))
        #expect(comercial.proxima?.nombre == "Repaso del embudo")
        #expect(comercial.proxima.map { FormatoAsistentes.cuando($0.fecha, zona: l.zona, hoy: l.hoy) } == "hoy a las 10:00")

        // El Contable: «el día 5 de cada mes» y «el día 1 de enero…»: lo próximo, el 5 de noviembre.
        let contable = try #require(l.asistente("contable"))
        #expect(contable.rutinas.map(\.cuando) == ["el día 5 de cada mes a las 09:00", "el día 1 de enero, abril, julio y octubre a las 09:00"])
        #expect(contable.proxima?.nombre == "Cobros pendientes")
        #expect(contable.proxima.map { LocalDate(date: $0.fecha, timeZone: l.zona) } == LocalDate(parsing: "2026-11-05"))
        #expect(contable.ultima?.dia == LocalDate(parsing: "2026-10-14") && contable.ultima?.simulado == true)
        #expect(contable.ultima?.texto.hasPrefix("Preparó el borrador de la factura F-2026-0007") == true)
        // Uso del mes: 0,11 USD simulados de un tope de 15 → 1 % (Simulado); nunca dólares en la frase.
        #expect(contable.uso.simulado && contable.uso.cifra == "1 %")
        #expect(contable.uso.frase == "uso del mes: 1 % de tu tope (Simulado)")
        #expect(!contable.uso.frase.contains("USD"))
        #expect(try #require(l.asistente("ordenador")).uso.cifra == "menos del 1 %")

        // Los apagados dicen por qué: el estado de su área (Marca: preparada) o lo que explica su perfil.
        #expect(l.asistente("marca")?.estadoGuardado == .apagado("Su área está preparada: empieza cuando la actives"))
        #expect(l.asistente("cartero")?.estadoGuardado == .apagado("Empieza cuando conectes Mail."))
        #expect(l.asistente("marca")?.proxima == nil)
        // Los del sistema no tienen área propia.
        #expect(l.asistente("ordenador")?.esDelSistema == true && l.asistente("ordenador")?.simbolo == "tray.full")
        #expect(l.asistente("comercial")?.simbolo == "sparkle")

        // Bitácora: 11 trabajos simulados en octubre; el uso total también es simulado.
        #expect(l.bitacora.count == 11 && l.bitacora.allSatisfy(\.simulado))
        #expect(l.mesesDeBitacora == ["2026-10"])
        #expect(l.usoTotal.simulado)
    }

    @Test("Interruptor apagado o área en pausa: en pausa y sin próxima rutina; apagar no borra lo que espera")
    func pausas() async throws {
        let a = try await ApoyoAsistentes.abrir { carpeta in
            let u = carpeta.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: u, encoding: .utf8).replacingOccurrences(of: "pausa_areas: []", with: "pausa_areas: [ventas]")
            try Data(t.utf8).write(to: u)
        }
        defer { a.cerrar() }
        var l = try await a.leer()
        #expect(l.asistente("comercial")?.estadoGuardado == .enPausa("Su área está en pausa"))
        #expect(l.asistente("comercial")?.proxima == nil)
        #expect(l.asistente("mika")?.estadoGuardado == .enReposo)

        try a.cambiarConfig("interruptor: encendido", "interruptor: apagado")
        try a.ejecucion("contable", estado: .pendiente)
        l = try await a.leer()
        #expect(!l.interruptor)
        #expect(l.asistentes.filter(\.activo).allSatisfy { $0.estadoGuardado == .enPausa("Todos los asistentes están en pausa") })
        #expect(l.asistentes.allSatisfy { $0.proxima == nil })
        #expect(DestacadoAhora.de(l.asistentes.map { ($0, $0.estadoGuardado) }, lectura: l).cifra == "En pausa")
    }

    @Test("Del motor: en cola, trabajando, esperando tu respuesta; los trabajos con su resumen y su uso real como parte del tope")
    func motor() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        try a.ejecucion("comercial", estado: .pendiente)
        try a.ejecucion("comercial", estado: .enCola)
        try a.ejecucion("implementador", estado: .enCurso)
        let pregunta = try a.ejecucion("contable", estado: .esperandoRespuesta)
        let hecho = try a.ejecucion("mika", estado: .completada, resumen: "Revisé el embudo: nada en rojo", coste: 1.5,
                                    ahora: ApoyoAsistentes.lunes(9, 10))
        try a.motor().apuntarUso(ejecucion: hecho.id, agente: "mika", mes: "2026-10", usd: 1.5, fecha: ApoyoAsistentes.lunes(), simulado: false)
        let l = try await a.leer()
        #expect(l.asistente("comercial")?.estadoGuardado == .enCola(2))
        #expect(l.asistente("implementador")?.estadoGuardado == .trabajando("Trabajando…"))
        #expect(l.asistente("contable")?.estadoGuardado == .esperandoRespuesta)
        // Lo del motor es más reciente que la Bitácora: es «lo último» de Mika, y su uso real manda sobre el simulado.
        let mika = try #require(l.asistente("mika"))
        #expect(mika.ultima?.texto == "Revisé el embudo: nada en rojo" && mika.ultima?.simulado == false)
        #expect(mika.uso.cifra == "10 %" && !mika.uso.simulado && mika.uso.frase == "uso del mes: 10 % de tu tope")
        let t = try #require(l.trabajos(de: "mika").first)
        #expect(t.titulo == "Revisé el embudo: nada en rojo" && t.porQue == "Le pediste: Repasa lo pendiente")
        #expect(t.palabra == "Terminado" && UsoDelMes.parte(t.costeUSD, de: mika.ajustes.presupuestoMesUSD) == "10 % de tu tope")
        #expect(l.trabajos(de: "contable").first?.id == pregunta.id)
        // El destacado: quién trabaja ahora.
        let vivos = l.asistentes.map { ($0, $0.estadoGuardado) }
        #expect(DestacadoAhora.de(vivos, lectura: l).cifra == "Implementador está trabajando")
    }

    @Test("Lo que pasa en vivo manda: «Creando tarea…», esperando tu respuesta, en cola")
    func enVivo() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        let l = try await a.leer()
        let comercial = try #require(l.asistente("comercial"))
        let vivo = TrabajoEnVivo(ejecucion: "r-1", agente: "comercial", tarea: nil, fase: .trabajando, frase: "Creando tarea…",
                                 desde: Date(), simulado: true)
        #expect(comercial.estado(vivo: vivo) == .trabajando("Creando tarea…"))
        var espera = vivo
        espera.fase = .esperandoRespuesta
        #expect(comercial.estado(vivo: espera) == .esperandoRespuesta)
        var cola = vivo
        cola.fase = .enCola
        #expect(comercial.estado(vivo: cola) == .enCola(1))
        // Un asistente apagado sigue apagado aunque haya algo en cola.
        #expect(try #require(l.asistente("marca")).estado(vivo: cola) == .apagado("Su área está preparada: empieza cuando la actives"))

        // Conectado (como hará la integración), el modelo lo ve en vivo y la clave de recarga cambia.
        let enVivo = EstadoEnVivo()
        RegistroDeAsistentes.compartido.conectar(ConexionAsistentes(enVivo: enVivo), a: a.sesion)
        let modelo = ModeloAsistentes(sesion: a.sesion)
        let antes = modelo.claveRecarga
        enVivo.poner(vivo)
        #expect(modelo.vivo("comercial")?.frase == "Creando tarea…")
        #expect(modelo.claveRecarga != antes)
    }

    @Test("Módulos de inicio: quién trabaja y el uso como parte del tope (ya no «aún no trabajan»)")
    func modulos() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        let foto = VaultSnapshot.read(root: a.carpeta)
        var (salud, uso) = ModulosAsistentes.cifras(foto: foto, ahora: ApoyoAsistentes.lunes())
        #expect(salud.cifra == "5 activos" && salud.linea == "Marca, apagado · Equipo, apagado")
        #expect(uso.cifra == "1 %" && uso.linea == "de tu tope este mes (Simulado)" && uso.enlace?.destino == .asistentes)
        try a.cambiarConfig("interruptor: encendido", "interruptor: apagado")
        (salud, uso) = ModulosAsistentes.cifras(foto: foto, ahora: ApoyoAsistentes.lunes())
        #expect(salud.cifra == "En pausa" && salud.palabra == "En pausa")
    }

    @Test("Palabras e iconos de cada estado: nunca solo el color")
    func palabras() {
        let estados: [EstadoDeAsistente] = [.trabajando("Leyendo…"), .enCola(2), .esperandoRespuesta, .enReposo, .enPausa("x"), .apagado("y")]
        #expect(estados.map(\.palabra) == ["Trabajando", "En cola", "Esperando tu respuesta", "Libre", "En pausa", "Apagado"])
        #expect(Set(estados.map(\.simbolo)).count == estados.count)
        #expect(EstadoDeAsistente.enCola(1).detalle == "Un trabajo espera su turno")
        #expect(EstadoDeAsistente.trabajando("Leyendo…").detalle == "Leyendo…")
        #expect(UsoDelMes(usadoUSD: 0, topeUSD: 15, simulado: false).frase == "uso del mes: 0 % de tu tope")
        #expect(UsoDelMes(usadoUSD: 5.1, topeUSD: 15, simulado: false).frase == "uso del mes: 34 % de tu tope")
        #expect(UsoDelMes(usadoUSD: 1, topeUSD: 0, simulado: false).frase == "Sin tope de uso fijado")
        #expect(UsoDelMes.parte(0.04, de: 15) == "menos del 1 % de tu tope")
    }
}
