import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// PLAN §6.8: Ribera trae sus asistentes (configuración de serie coherente con sus áreas, fichas de rol y una
/// Bitácora de ejemplo del mes, todo marcado «Simulado»). Con `TLS_ACTUALIZAR_GOLDEN=1` se regeneran en su sitio la
/// configuración y las fichas a partir del generador (revisa el diff antes de commitear).
@Suite("Ribera · con sus asistentes", .serialized)
struct RiberaConAsistentesTests {
    let root = ApoyoRoles.ribera

    @Test("Sus áreas: Dirección, Ventas, Entrega y Finanzas activas; Marca preparada; Equipo en reposo")
    func estados() {
        #expect(ConfigDeSerie.estados(en: root) == ApoyoRoles.estadosRibera)
    }

    @Test("Su config.yaml es la de la conversión más los asistentes de serie, tal cual los da el generador")
    func config() throws {
        let url = root.appendingPathComponent(".tls/config.yaml")
        let actual = try #require(ApoyoRoles.texto(url))
        let original = actual.range(of: "\n" + ConfigDeSerie.comentario).map { String(actual[..<$0.lowerBound]) } ?? actual
        #expect(original.contains("clase: demo") && original.contains("hoy: 2026-10-19"))
        let esperado = ConfigDeSerie.completar(original, estados: ConfigDeSerie.estados(en: root))
        if ApoyoRoles.actualizar, actual != esperado { try esperado.write(to: url, atomically: true, encoding: .utf8) }
        #expect(actual == esperado || ApoyoRoles.actualizar, "Regenera con TLS_ACTUALIZAR_GOLDEN=1")
        let c = ConfigAgentes.leer(yaml: esperado)
        #expect(c.activos.map(\.slug) == ["comercial", "contable", "implementador", "mika", "ordenador"])
        #expect(Set(c.agentes.keys) == Set(PerfilDeAsistente.deSerie.map(\.slug)))
        // Criterio F4-10 (lado de los datos): ningún asistente activo trabaja en un área preparada o en reposo.
        for a in c.activos {
            for area in a.areas { #expect(ApoyoRoles.estadosRibera[area] == .activa, "\(a.slug) en \(area.nombre)") }
        }
    }

    @Test("Una ficha de rol por asistente, igual a la del generador y enlazada al rol de la persona del área")
    func fichas() throws {
        let fm = FileManager.default
        for p in PerfilDeAsistente.deSerie {
            let url = FichaDeRolDeAsistente.ruta(p.slug, layout: .humana).url(in: root)
            let humano = p.area.flatMap(FichaDeRolDeAsistente.rolHumanoDeSerie)
            #expect(humano.map { fm.fileExists(atPath: root.appendingPathComponent("6 · Equipo/Roles/\($0).md").path) } ?? true)
            let esperado = FichaDeRolDeAsistente.texto(p, rolHumano: humano)
            let actual = ApoyoRoles.texto(url)
            if ApoyoRoles.actualizar, actual != esperado { try esperado.write(to: url, atomically: true, encoding: .utf8) }
            #expect(actual == esperado || ApoyoRoles.actualizar, "\(p.slug): regenera con TLS_ACTUALIZAR_GOLDEN=1")
        }
        // Nada más que añadir: la puesta en marcha no escribiría nada en Ribera.
        #expect(ApoyoRoles.actualizar || AsistentesDeSerie.cambios(root: root).isEmpty)
    }

    @Test("Abre con sus asistentes: el motor y gobierno ven los mismos cinco activos")
    func abre() async throws {
        let (layout, aviso) = VaultLayout.load(root: root)
        #expect(aviso == nil && layout.areasDetectadas)
        let ajustes = await AjustesDeLaCarpeta(root: root).ajustes()
        #expect(ajustes.interruptor && ajustes.agentes.count == 8)
        #expect(ajustes.activos.map(\.slug) == ["comercial", "contable", "implementador", "mika", "ordenador"])
        #expect(ajustes.hoy == LocalDate(parsing: "2026-10-19") && ajustes.clase == "demo")
        #expect(ajustes.agente("mika")?.rutina("algo-rojo")?.soloSiHayRojo == true)
        // El catálogo completo, con sus instrucciones de la app.
        let cat = CatalogoAsistentesTLS(carpetaInstrucciones: ApoyoRoles.instrucciones)
        for a in ajustes.activos { #expect(cat.rol(a.slug) != nil, "\(a.slug)") }
    }

    @Test("La Bitácora de octubre: once trabajos simulados de los asistentes activos, legibles por gobierno")
    func bitacora() throws {
        let ruta = Bitacora.ruta(try #require(LocalDate(parsing: "2026-10-19")), layout: .humana)
        #expect(ruta.raw == "6 · Equipo/Bitácora/2026-10.md")
        #expect(Bitacora.esRutaDeBitacora(ruta, layout: .humana))
        let texto = try #require(ApoyoRoles.texto(ruta.url(in: root)))
        let doc = NoteDocument(text: texto)
        #expect(doc.frontmatter.text("tls_type") == "log" && doc.frontmatter.text("registro") == "bitacora")
        #expect(doc.frontmatter.text("mes") == "2026-10")
        let lineas = Bitacora.leer(texto)
        #expect(lineas.count == 11)
        let activos = Set(["mika", "comercial", "implementador", "contable", "ordenador"])
        for l in lineas {
            #expect(activos.contains(l.agente), "\(l.agente)")
            #expect(l.que.hasPrefix("Simulado: "), "\(l.texto)")
            #expect(l.ejecucion?.hasPrefix("sim-") == true)
            #expect(l.fecha < LocalDate(parsing: "2026-10-19")!)
            // Cada línea, bajo su día y tal cual la escribiría la app.
            #expect(texto.contains("## \(l.fecha)\n") && texto.contains(l.texto.replacingOccurrences(of: #" <!-- tls:audit \{.*\} -->"#, with: "", options: .regularExpression)))
        }
        let uso = lineas.compactMap(\.usoUSD).reduce(0, +)
        #expect(abs(uso - 0.38) < 0.0001)
        #expect(lineas.map { "\($0.fecha) \($0.hora)" } == lineas.map { "\($0.fecha) \($0.hora)" }.sorted())
    }

    @Test("Pendientes de F2 resueltos: sin «agente» ni «runway» en lo que se lee, y la tarea T-0002 renombrada")
    func glosario() throws {
        let fm = FileManager.default
        let e = try #require(fm.enumerator(atPath: root.path))
        var revisadas = 0
        for case let rel as String in e where rel.hasSuffix(".md") && !rel.hasPrefix("Archivo/") && !rel.hasPrefix("Buzón/") {
            let texto = try #require(ApoyoRoles.texto(root.appendingPathComponent(rel)))
            let cuerpo = NoteDocument(text: texto).body
                .replacingOccurrences(of: #"agente:[a-z0-9-]+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"<!--.*?-->"#, with: "", options: .regularExpression)
                // Los códigos de los números (FIN-RUNWAY) son identificadores, no texto.
                .replacingOccurrences(of: #"\b[A-Z]{3}-[A-Z0-9]+\b"#, with: "", options: .regularExpression)
            let palabras = Set(cuerpo.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            for p in ["agente", "agentes", "runway"] { #expect(!palabras.contains(p), "\(rel): «\(p)»") }
            revisadas += 1
        }
        #expect(revisadas > 100)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("6 · Equipo/Tareas/t-0002-dejar-que-comercial-prepare-los-recordatorios.md").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("6 · Equipo/Tareas/t-0002-dejar-que-el-agente-comercial-envie-recordatorios-de.md").path))
    }
}
