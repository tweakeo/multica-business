import Foundation
import Testing
import TLSCore
@testable import TLSOnboarding

/// Lint del glosario (PLAN §6.9, criterio F3-10) para la puesta en marcha: ninguna cadena que llegue a la pantalla dice
/// vault, frontmatter, YAML, MCP, null, NaN, backlog, issue, run ni hash, ni enseña una ruta técnica. Mira los literales
/// de las vistas de TLSOnboarding y lo que se fabrica al recorrer las pantallas (títulos, explicaciones, preguntas,
/// opciones, orígenes, botones, vistas previas y avisos) con una empresa nueva y con la copia de G3.
@Suite("Puesta en marcha · glosario en pantalla (F3-10)", .serialized)
@MainActor
struct GlosarioPasosTests {
    static let prohibidas = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash"]

    static func jerga(_ texto: String) -> [String] {
        let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return prohibidas.filter { palabras.contains($0) }
    }

    static let literal = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
    static let llamadaVisible = try! NSRegularExpression(pattern:
        #"(?:\bText|\bLabel|\bButton|\bToggle|\bMenu|\bPicker|\bTextField|\bChip|\bChipOpcion|\bFilaOpcion|\bRotulo|\bPastillaEstado|\bPastillaEtapa|\bAvisoEnLinea|\bNotaPuesta|\bBloquePuesta|\bSeccionPuesta|\bDestacado|\bDestacadoVacio|\.help|\.accessibilityLabel|\.accessibilityHint|\.accessibilityValue)\s*\(\s*(?:rotulo:\s*|titulo:\s*|texto:\s*|estado:\s*\.\w+,\s*texto:\s*)?"((?:[^"\\]|\\.)*)""#)

    static func literalesVisibles(_ linea: String) -> [String] {
        let l = linea.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("//") || l.contains("accessibilityIdentifier") || l.hasPrefix("case ") && l.contains("rawValue") {
            return []
        }
        let ns = l as NSString
        let todo = NSRange(location: 0, length: ns.length)
        var out = literal.matches(in: l, range: todo).map { ns.substring(with: $0.range(at: 1)) }.filter { $0.contains(" ") }
        out += llamadaVisible.matches(in: l, range: todo).map { ns.substring(with: $0.range(at: 1)) }
        return out
    }

    @Test("Los literales de las vistas de TLSOnboarding no usan jerga ni enseñan rutas técnicas")
    func literales() throws {
        #expect(Self.literalesVisibles(#"Text("YAML").font(.body)"#) == ["YAML"])
        #expect(Self.jerga("Ejecutar, nano y ruina").isEmpty)
        let dir = PasosApoyo.repo.appendingPathComponent("Packages/TLSKit/Sources/TLSOnboarding")
        let ficheros = FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []
        #expect(ficheros.contains { $0.hasSuffix("PasoBienvenida.swift") })
        var revisados = 0
        var fallos: [String] = []
        for f in ficheros where f.hasSuffix(".swift") {
            let texto = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            for (n, linea) in texto.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for s in Self.literalesVisibles(String(linea)) {
                    revisados += 1
                    let malas = Self.jerga(s)
                    if !malas.isEmpty { fallos.append("\(f):\(n + 1) «\(s)» → \(malas.joined(separator: ", "))") }
                    if s.contains(".tls/"), !linea.contains("hasPrefix") { fallos.append("\(f):\(n + 1) «\(s)» enseña una ruta técnica") }
                }
            }
        }
        #expect(revisados > 150, "Solo \(revisados) literales revisados")
        #expect(fallos.isEmpty, "Jerga en pantalla:\n\(fallos.joined(separator: "\n"))")
    }

    @Test("Lo que se fabrica al recorrer las pantallas (empresa nueva y copia de G3) no usa jerga")
    func textosFabricados() async throws {
        var textos: [String] = []
        func mirar(_ m: ModeloPuesta) {
            if let p = m.pantalla { textos += [p.titulo, p.explicacion, p.paso.titulo] }
            textos += [m.progreso.texto, m.progreso.textoMinutos, m.accionPrincipal.titulo]
            if let x = m.motivoSinPrincipal { textos.append(x) }
            if let x = m.error { textos.append(x) }
            for q in m.preguntas {
                textos += [q.texto, q.ayuda, q.referencia].compactMap { $0 }
                textos += q.tipo.opciones.flatMap { [$0.texto, $0.detalle].compactMap { $0 } }
                if let r = m.respuesta(q.id) { textos.append(r.origen.texto) }
            }
            if let v = m.vista {
                textos += [v.resumen] + v.avisos + v.fueraDeLaCarpeta
                for c in v.cambios {
                    textos.append(DiferenciaLegible.titulo(c))
                    if let d = DiferenciaLegible.donde(c.ruta) { textos.append(d) }
                    for l in DiferenciaLegible.lineas(c) {
                        switch l {
                        case .resumen(let t), .propiedades(let t): textos.append(t)
                        default: break
                        }
                    }
                }
                if let e = v.entendido { textos.append(e.porQue) }
            }
            if let a = m.aplicado { textos += [a.texto, a.detalle].compactMap { $0 } }
        }
        // Empresa nueva.
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        _ = try await Recorrido.hasta(fin: m, ventana: nil, banco: b, antesDeAplicar: { m in m.prepararVistaPrevia(); mirar(m) },
                                      enPantalla: { m, _ in mirar(m) })
        // Copia de G3.
        let e = b.carpeta(copiando: PasosApoyo.fixtureG3, nombre: "Estudio", privadas: ["Privado"])
        let g3 = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        _ = try await Recorrido.hasta(fin: g3, ventana: nil, banco: b, antesDeAplicar: { m in m.prepararVistaPrevia(); mirar(m) },
                                      enPantalla: { m, _ in mirar(m) })
        // Los nombres del estándar que se enseñan (sistemas y funciones), ya en llano.
        for s in g3.motor.contexto.catalogo.sistemas { textos += [TextoLlano.de(s.nombre), TextoLlano.de(s.pregunta)] }
        for c in g3.motor.contexto.catalogo.capacidades { textos.append(TextoLlano.de(c.nombre)) }
        #expect(textos.count > 300)
        let malos = textos.filter { !Self.jerga($0).isEmpty || $0.contains(".tls/") }
        #expect(malos.isEmpty, "Jerga en pantalla: \(Set(malos))")
    }
}
