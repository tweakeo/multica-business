import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Lint del glosario (PLAN §6.9): ninguna cadena que llegue a la pantalla dice vault, frontmatter, YAML, MCP,
/// null, NaN, backlog, issue, run ni hash. Mira tres sitios: los literales de las vistas de los cinco módulos de
/// interfaz (con la puesta en marcha, F3-10) (también los de una sola palabra dentro de `Text`, `Button`, `.help`…), los textos que la app
/// fabrica (catálogo de bases, tipos, estados, errores, cifras) y lo que enseñan las 24 bases con Ribera.
@Suite("Glosario · ninguna cadena visible con jerga", .serialized)
@MainActor
struct GlosarioTests {
    static let prohibidas = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash"]

    /// Palabras prohibidas que contiene un texto (palabra entera, sin distinguir mayúsculas).
    static func jerga(_ texto: String) -> [String] {
        let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return prohibidas.filter { palabras.contains($0) }
    }

    static var fuentes: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Sources").standardizedFileURL
    }

    /// Literales de una línea que acaban en pantalla: frases (con un espacio) y el primer argumento de los
    /// constructores de texto visibles, aunque sea una sola palabra.
    static func literalesVisibles(_ linea: String) -> [String] {
        let l = linea.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("//") || l.hasPrefix("///") || l.contains("Logger(") || l.contains("log.")
            || l.contains("accessibilityIdentifier") || l.contains("SceneStorage") || l.contains("AppStorage") {
            return []
        }
        let ns = l as NSString
        let todo = NSRange(location: 0, length: ns.length)
        var out = literal.matches(in: l, range: todo).map { ns.substring(with: $0.range(at: 1)) }.filter { $0.contains(" ") }
        out += llamadaVisible.matches(in: l, range: todo).map { ns.substring(with: $0.range(at: 1)) }
        return out
    }

    static let literal = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
    static let llamadaVisible = try! NSRegularExpression(pattern:
        #"(?:\bText|\bLabel|\bButton|\bToggle|\bMenu|\bSection|\bPicker|\bTextField|\bTecla|\bChip|\bRotulo|\bAviso|\bPastillaEstado|\bVacioExplicado|\bInfoBanner|\bStatusLabel|\bBotonPrincipal|\bBotonSecundario|\bDatoClave|\bLabeledContent|\bGroupBox|\.help|\.accessibilityLabel|\.accessibilityHint|\.accessibilityValue|\.navigationTitle)\s*\(\s*"((?:[^"\\]|\\.)*)""#)

    @Test("Los textos de las vistas de TLSUI, TLSDesign, TLSEditor, TLSVisores y TLSOnboarding no usan jerga (F3-10)")
    func literalesDeLasVistas() throws {
        // El propio lint: encuentra una palabra suelta en `Text("…")` y no confunde «Ejecutar» con «run».
        #expect(Self.literalesVisibles(#"Text("YAML").font(.body)"#) == ["YAML"])
        #expect(Self.jerga("Tu vault en YAML, sin hash") == ["vault", "yaml", "hash"])
        #expect(Self.jerga("Ejecutar, nano y ruina").isEmpty)
        var revisados = 0
        var fallos: [String] = []
        for modulo in ["TLSUI", "TLSDesign", "TLSEditor", "TLSVisores", "TLSOnboarding"] {
            let dir = Self.fuentes.appendingPathComponent(modulo)
            let ficheros = FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []
            #expect(!ficheros.isEmpty, "No encuentro las fuentes de \(modulo)")
            for f in ficheros where f.hasSuffix(".swift") {
                let texto = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                for (n, linea) in texto.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    for s in Self.literalesVisibles(String(linea)) {
                        revisados += 1
                        let malas = Self.jerga(s)
                        if !malas.isEmpty { fallos.append("\(modulo)/\(f):\(n + 1) «\(s)» → \(malas.joined(separator: ", "))") }
                        if s.contains(".tls/") { fallos.append("\(modulo)/\(f):\(n + 1) «\(s)» enseña una ruta técnica") }
                    }
                }
            }
        }
        #expect(revisados > 1_000)
        #expect(fallos.isEmpty, "Jerga en pantalla:\n\(fallos.joined(separator: "\n"))")
    }

    @Test("Los textos que fabrica la app (bases, tipos, estados, errores y cifras) no usan jerga")
    func textosFabricados() {
        var textos: [String] = []
        for c in CatalogoBases.deSerie {
            textos += [c.nombre, c.frase] + c.columnas.map(\.etiqueta) + c.pestanas.map(\.titulo)
            textos += CatalogoBases.vistasDeSerie(c).map(\.nombre)
            if let m = c.motivoSinCrear { textos.append(m) }
        }
        textos += BaseConocida.deSerie.map(\.nombre)
        textos += NoteKind.allCases.map(\.etiqueta)
        textos += TLSEstado.allCases.map(\.palabra)
        textos += AreaCode.allCases.map(\.nombre)
        textos += ModoVistaPrevia.allCases.map(\.titulo)
        let x = "x.md"
        let errores: [WriteError] = [
            .carpetaReal, .soloLectura, .carpetaDelFork(x), .otroEscritor(equipo: "Mac", desde: "hoy"), .otroProceso,
            .escritorIlegible, .rutaNoPermitida(x), .noExiste(x), .destinoOcupado(x), .sinDescargar(x), .enlaceSimbolico(x),
            .esCarpeta(x), .noEsTexto(x), .cambioExterno(x), .soloAnadidos(x), .listaVacia(x), .filaManual(x),
            .claveDuplicada(x), .filaYaExiste(x), .columnaDesconocida(x), .csvSinCabecera, .tablaNoEncontrada, .filaNoEncontrada(x),
            .seccionNoEncontrada(x), .seccionCambiada(x), .propiedadesIlegibles(x), .contenidoIlegible(x),
            .verificacionFallida(x), .nadaQueDeshacer, .noSePuedeDeshacer(x), .cambiosInvalidos, .yaRetirada(x),
            .noPermitidoAsistente(x), .conflictoNoEncontrado, .versionNoDisponible, .interrumpido,
        ]
        textos += errores.map(\.localizedDescription)
        // Cifras: lo que no es un número nunca se enseña como «NaN» ni «inf» (ni cierra la app).
        for n in [Double.nan, .infinity, -.infinity, 1e300] {
            textos += [FormatoBase.cifra(n), FormatoBase.euros(n), FormatoBase.euros(n, redondo: true)]
        }
        #expect(FormatoBase.cifra(.nan) == "—")
        #expect(FormatoBase.numero("nan") == nil && FormatoBase.numero("inf") == nil)
        #expect(FormatoFicha.euros("NaN") == nil)
        for t in textos {
            #expect(Self.jerga(t).isEmpty, "«\(t)» usa jerga: \(Self.jerga(t))")
            #expect(!t.lowercased().contains("inf "), "«\(t)» enseña un infinito")
        }
        #expect(textos.count > 200)
    }

    @Test("Lo que enseñan las 24 bases con Ribera (títulos, celdas, cifras, pestañas y avisos) no usa jerga")
    func basesConRibera() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let service = try #require(sesion.service)
        let root = try #require(sesion.root)
        let todas = LectorBases(service: service, ajustes: AjustesBases.leer(root: root), persona: "Manu").leerTodas()
        #expect(todas.count == CatalogoBases.deSerie.count)
        var revisados = 0
        for (id, datos) in todas {
            let c = try #require(CatalogoBases.coleccion(id))
            var textos = [datos.frase] + datos.cifras.flatMap { [$0.etiqueta, $0.valor] } + datos.pestanas.map(\.titulo)
            if let u = datos.urgente { textos.append(u.texto) }
            textos.append(datos.pie)
            for f in datos.filas {
                textos.append(f.titulo)
                for col in c.columnas {
                    if let v = f.valor(col) { textos.append(FormatoBase.textoVisible(v)) }
                    if let calc = f.calculado(col) { textos.append(calc.texto) }
                }
                textos += f.enlaces.values.flatMap { $0.map(\.texto) }
            }
            for t in textos {
                revisados += 1
                #expect(Self.jerga(t).isEmpty, "\(id): «\(t)» usa jerga: \(Self.jerga(t))")
            }
        }
        #expect(revisados > 500)
    }
}
