import Foundation
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSUI

/// Lo que la ficha de un asistente cambia en `config.yaml`: solo las líneas de lo que cambia (el resto, byte a byte),
/// sin perder `dia_mes`, `meses` ni `solo_si_rojo` (que el editor del gobierno aún no escribe), y comprobado al leerlo.
@Suite("Asistentes · cambiar su configuración sin tocar lo demás")
struct EdicionConfigAsistentesTests {
    static var ribera: String {
        let u = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera/.tls/config.yaml").standardizedFileURL
        return (try? String(contentsOf: u, encoding: .utf8)) ?? ""
    }

    /// Las líneas que cambian (quitadas y puestas).
    static func diferencias(_ a: String, _ b: String) -> [String] { DescripcionDeCambios.lineasQueCambian(antes: a, despues: b) }

    @Test("La hora de «Cobros pendientes» cambia en su línea y conserva el día 5 (y la otra rutina, sus meses)")
    func horaConDiaDelMes() throws {
        let base = Self.ribera
        #expect(base.contains("dia_mes: 5"))
        let nuevo = try EdicionConfigAsistentes.texto([.rutinaHora("cobros-pendientes", hora: 10, minuto: 0)], slug: "contable",
                                                      perfil: .contable, en: base)
        #expect(Self.diferencias(base, nuevo) == [
            "−       - {id: cobros-pendientes, nombre: \"Cobros pendientes\", dia_mes: 5, hora: \"09:00\", ventana_perdida_h: 72, activa: true}",
            "+       - {id: cobros-pendientes, nombre: \"Cobros pendientes\", dia_mes: 5, hora: \"10:00\", ventana_perdida_h: 72, activa: true}",
        ])
        let r = try #require(AjustesDeAsistentes.leer(yaml: nuevo).agente("contable"))
        #expect(r.rutina("cobros-pendientes")?.diaDelMes == 5 && r.rutina("cobros-pendientes")?.hora == 10)
        #expect(r.rutina("paquete-gestoria")?.meses == [1, 4, 7, 10])
        #expect(!ConfigAgentes.leer(yaml: nuevo).ilegible)
    }

    @Test("Apagar «¿Algo rojo?» conserva «solo si hay rojo»; los días y el día del mes se cambian")
    func rutinas() throws {
        let base = Self.ribera
        var nuevo = try EdicionConfigAsistentes.texto([.rutinaActiva("algo-rojo", false)], slug: "mika", perfil: .mika, en: base)
        var m = try #require(AjustesDeAsistentes.leer(yaml: nuevo).agente("mika")?.rutina("algo-rojo"))
        #expect(!m.activa && m.soloSiHayRojo)
        #expect(nuevo.contains("activa: false, solo_si_rojo: true}"))

        nuevo = try EdicionConfigAsistentes.texto([.rutinaDias("repaso-embudo", [.lunes, .jueves])], slug: "comercial",
                                                  perfil: .comercial, en: base)
        #expect(nuevo.contains("dias: [lun, jue]"))
        #expect(AjustesDeAsistentes.leer(yaml: nuevo).agente("comercial")?.rutina("repaso-embudo")?.dias == [.lunes, .jueves])

        nuevo = try EdicionConfigAsistentes.texto([.rutinaDiaDelMes("cobros-pendientes", 7)], slug: "contable", perfil: .contable, en: base)
        m = try #require(AjustesDeAsistentes.leer(yaml: nuevo).agente("contable")?.rutina("cobros-pendientes"))
        #expect(m.diaDelMes == 7 && m.hora == 9)
        #expect(Self.diferencias(base, nuevo).count == 2)

        #expect(throws: ErrorEdicionConfig.sinRutina("no-existe")) {
            try EdicionConfigAsistentes.texto([.rutinaActiva("no-existe", false)], slug: "contable", perfil: .contable, en: base)
        }
    }

    @Test("Activo, topes y tareas por trabajo: una línea cada uno; el resto del fichero queda igual")
    func escalares() throws {
        let base = Self.ribera
        let nuevo = try EdicionConfigAsistentes.texto([.activo(true), .topeMes(20), .topeTrabajo(0.75), .maxTareas(5)],
                                                      slug: "marca", perfil: .marca, en: base)
        let d = Self.diferencias(base, nuevo)
        #expect(d.count == 8)
        #expect(d.contains("+     activo: true") && d.contains("+     presupuesto_mes_usd: 20")
                && d.contains("+     presupuesto_ejecucion_usd: 0.75") && d.contains("+     max_tareas_por_ejecucion: 5"))
        let g = ConfigAgentes.leer(yaml: nuevo)
        #expect(g.asistente("marca")?.activo == true)
        #expect(g.asistente("comercial") == ConfigAgentes.leer(yaml: base).asistente("comercial"))
        // Fuera del bloque de los asistentes, byte a byte.
        let antesDeAgentes = { (t: String) in t.components(separatedBy: "\nagentes:\n").first }
        #expect(antesDeAgentes(base) == antesDeAgentes(nuevo))
    }

    @Test("El nivel de una función va a `capacidades` (con el editor del gobierno) y no toca a los asistentes")
    func modo() throws {
        let base = Self.ribera
        let nuevo = try EdicionConfigAsistentes.texto([.modo("FIN-05", .supervisado), .rutinaHora("cobros-pendientes", hora: 8, minuto: 30)],
                                                      slug: "contable", perfil: .contable, en: base)
        let g = ConfigAgentes.leer(yaml: nuevo)
        #expect(g.modo("FIN-05") == .supervisado)
        #expect(g.agentes.filter { $0.key != "contable" } == ConfigAgentes.leer(yaml: base).agentes.filter { $0.key != "contable" })
        #expect(AjustesDeAsistentes.leer(yaml: nuevo).agente("contable")?.rutina("cobros-pendientes")?.horaTexto == "08:30")
    }

    @Test("Un asistente que no estaba, o sin rutinas escritas, recibe su entrada de serie antes del cambio")
    func entradaDeSerie() throws {
        // Sin Ordenador en la configuración.
        let base = Self.ribera
        let sin = base.components(separatedBy: "  ordenador:\n").first!
        #expect(!sin.contains("ordenador:"))
        let nuevo = try EdicionConfigAsistentes.texto([.activo(true)], slug: "ordenador", perfil: .ordenador, en: sin)
        let o = try #require(AjustesDeAsistentes.leer(yaml: nuevo).agente("ordenador"))
        #expect(o.activo && o.rutinas.map(\.id) == ["barrido"])
        #expect(nuevo.hasPrefix(sin.trimmingCharacters(in: .newlines)))

        // Con `rutinas: []`: se escriben las de serie y se cambia la pedida.
        let vacias = base.replacingOccurrences(
            of: "    rutinas:\n      - {id: repaso-embudo, nombre: \"Repaso del embudo\", dias: [lun], hora: \"10:00\", ventana_perdida_h: 8, activa: true}\n",
            with: "    rutinas: []\n")
        #expect(vacias != base)
        let otro = try EdicionConfigAsistentes.texto([.rutinaHora("repaso-embudo", hora: 11, minuto: 0)], slug: "comercial",
                                                     perfil: .comercial, en: vacias)
        #expect(AjustesDeAsistentes.leer(yaml: otro).agente("comercial")?.rutina("repaso-embudo")?.horaTexto == "11:00")
    }

    @Test("Mapas en línea con comillas, corchetes y comas dentro")
    func paresEnLinea() throws {
        let p = try EdicionConfigAsistentes.paresEnLinea(#"id: a, nombre: "Uno, dos: tres", dias: [lun, mar], extra: {x: 1, y: 2}"#)
        #expect(p.map(\.clave) == ["id", "nombre", "dias", "extra"])
        #expect(p[1].valor == #""Uno, dos: tres""# && p[2].valor == "[lun, mar]" && p[3].valor == "{x: 1, y: 2}")
        #expect(throws: ErrorEdicionConfig.self) { try EdicionConfigAsistentes.paresEnLinea(#"id: "sin cerrar"#) }
    }

    @Test("Lo que no se sabe cambiar sin tocar lo demás no se cambia")
    func formasDesconocidas() {
        let enLinea = "agentes: {mika: {activo: true}}\n"
        #expect(throws: ErrorEdicionConfig.self) {
            try EdicionConfigAsistentes.texto([.activo(false)], slug: "mika", perfil: .mika, en: enLinea)
        }
        let rutinaEnBloque = """
            agentes:
              mika:
                activo: true
                rutinas:
                  - id: algo-rojo
                    hora: "08:45"
            """
        #expect(throws: ErrorEdicionConfig.self) {
            try EdicionConfigAsistentes.texto([.rutinaHora("algo-rojo", hora: 9, minuto: 0)], slug: "mika", perfil: .mika, en: rutinaEnBloque)
        }
    }

    @Test("La vista previa cuenta los cambios en palabras")
    func vistaPrevia() throws {
        let config = ConfigAgentes.leer(yaml: Self.ribera)
        let ajustes = try #require(AjustesDeAsistentes.leer(yaml: Self.ribera).agente("contable"))
        let a = AsistenteEnLista(slug: "contable", nombre: "Contable", descripcion: "tu asistente de Finanzas", perfil: .contable,
                                 area: .finanzas, esDelSistema: false, coordinador: false, enConfig: true, activo: true, ajustes: ajustes,
                                 rutinas: ajustes.rutinas.map { RutinaVista(rutina: $0, deSerie: false, autopausa: nil, proxima: nil) },
                                 estadoGuardado: .enReposo, ultima: nil, proxima: nil, uso: .cero)
        let c = DescripcionDeCambios.contar([.rutinaHora("cobros-pendientes", hora: 10, minuto: 0), .modo("FIN-05", .supervisado),
                                             .activo(false)], asistente: a, config: config)
        // F4 · corrector: el nombre de la función, sin su código.
        #expect(c.map(\.que) == ["Rutina «Cobros pendientes»", "Meses de caja: cuánto se aguanta si mañana no entra nada",
                                 "Apagar a Contable"])
        #expect(c[0].antes == "el día 5 de cada mes a las 09:00" && c[0].despues == "el día 5 de cada mes a las 10:00")
        #expect(c[1].antes == "Te ayuda" && c[1].despues == "Lo hace y revisas")
        // Preparar y volver a como estaba no deja cambio.
        var x = AjustesConCambios.de(a, config: config, cambios: [])
        let ahora = x
        x.aplicar(.rutinaHora("cobros-pendientes", hora: 9, minuto: 0))
        #expect(x == ahora)
    }
}
