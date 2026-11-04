import Foundation
import Testing
import TLSCore
import TLSImport

@Suite("Conformidad · casos golden")
struct CasosGolden {
    static let todos = Arnes.casos()

    @Test("Caso golden", arguments: CasosGolden.todos.filter(\.ejecutable))
    func caso(_ caso: Caso) async throws {
        try await Arnes.ejecutar(caso)
    }

    @Test("Hay casos de cada operación")
    func hayCasos() {
        let nombres = Self.todos.map(\.nombre)
        #expect(nombres.contains("convertir-g2-minimo"))
        #expect(nombres.contains("ida-y-vuelta-empresa-minima"))
        #expect(nombres.contains("ida-y-vuelta-ribera"))
        #expect(nombres.contains("lectura-empresa-minima"))
        #expect(Self.todos.contains { if case .escritor = $0.operacion { true } else { false } })
    }

    /// Los casos del escritor deben estar completos (también los que esperen una API que aún no exista).
    @Test("Casos del escritor bien formados")
    func casosDelEscritor() throws {
        for caso in Self.todos {
            guard case .escritor(let plan) = caso.operacion else { continue }
            #expect(!plan.isEmpty, "\(caso.nombre): plan vacío")
            let entrada = try Arbol.leer(caso.entrada)
            let esperado = try Arbol.leer(caso.esperado)
            #expect(!entrada.isEmpty && !esperado.isEmpty, "\(caso.nombre): falta entrada/ o esperado/")
            for op in plan {
                #expect(["create", "mergeFrontmatter", "appendToSection", "appendLine", "upsertCSVRow", "move", "retire", "renombrar"]
                    .contains(op.op), "\(caso.nombre): operación desconocida \(op.op)")
                if op.op != "create" { #expect(entrada[op.ruta] != nil, "\(caso.nombre): no existe \(op.ruta)") }
            }
            // Ninguna operación borra: lo que había sigue (en su sitio o en Archivo/).
            for ruta in entrada.keys where esperado[ruta] == nil {
                let movido = plan.contains { ["move", "retire", "renombrar"].contains($0.op) && $0.ruta == ruta }
                #expect(movido, "\(caso.nombre): «\(ruta)» desaparece sin moverse")
            }
        }
    }
}

@Suite("Conformidad · empresa de ejemplo")
struct EjemploRibera {
    @Test("El ejemplo versionado pasa el validador y no tiene notas sin tipo")
    func validador() throws {
        let arbol = try Arbol.leer(RutasConformidad.ejemploRibera)
        #expect(arbol.count > 100)
        let problemas = ValidadorV2.validar(arbol)
        #expect(problemas.isEmpty, "\(problemas.prefix(20))")
        #expect(ValidadorV2.tipos(arbol)["(sin tipo)"] == nil)
        let config = FrontmatterReader.read(String(decoding: arbol[".tls/config.yaml"] ?? Data(), as: UTF8.self))
        #expect(config.text("clase") == "demo")
        #expect(config.text("hoy") == "2026-10-19")
    }

    @Test("El núcleo lo abre: seis áreas numeradas y estructura humana")
    func layout() {
        let (layout, aviso) = VaultLayout.load(root: RutasConformidad.ejemploRibera)
        #expect(aviso == nil)
        #expect(layout.preset == .humana)
        #expect(layout.areasDetectadas)
        #expect(layout.areas[.ventas] == "2 · Ventas")
        #expect(layout.privado.isEmpty)
    }

    /// PLAN §4.6: `import_hash = SHA-256("<cuenta_id>|<AAAA-MM-DD>|<importe en céntimos>|<concepto en minúsculas>|<saldo en céntimos o vacío>")`
    /// e `id = MOV-<import_hash[0..11]>`. Los 30 de Ribera.
    @Test("Los 30 import_hash de Ribera siguen el contrato")
    func importHash() throws {
        let arbol = try Arbol.leer(RutasConformidad.ejemploRibera)
        var comprobados = 0
        for (ruta, datos) in arbol where ruta.hasSuffix("/movimientos.csv") && ruta.contains("Registros/Bancos/") {
            let cuentaRuta = VaultPath(ruta).parent!.appending("Cuenta.md").raw
            let cuenta = try #require(arbol[cuentaRuta].map { NoteDocument(data: $0).frontmatter.text("id") } ?? nil)
            let tabla = CSVTable.parse(String(decoding: datos, as: UTF8.self))
            let col = { (n: String) in tabla.header.firstIndex(of: n)! }
            for fila in tabla.rows {
                let centimos = { (s: String) -> String in
                    s.isEmpty ? "" : String(NSDecimalNumber(decimal: Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! * 100).intValue)
                }
                let base = "\(cuenta)|\(fila[col("fecha")])|\(centimos(fila[col("importe")]))|\(fila[col("concepto")].lowercased())|\(centimos(fila[col("saldo")]))"
                let hash = Arbol.sha256(Data(base.utf8))
                #expect(fila[col("import_hash")] == hash, "\(ruta): \(fila[col("id")])")
                #expect(fila[col("id")] == "MOV-" + hash.prefix(12))
                comprobados += 1
            }
        }
        #expect(comprobados == 30)
    }

    /// F4 · rol «roles»: el ejemplo es la conversión **más la capa de Ribera** (`CapaRibera`: los asistentes y los
    /// pendientes de F2), y nada más. Con `TLS_ACTUALIZAR_GOLDEN=1` se regenera aplicando la capa a la conversión.
    @Test("Convertir Ribera y aplicar su capa da exactamente el ejemplo versionado (si la carpeta G2 está en este Mac)",
          .enabled(if: RutasConformidad.origenRibera != nil))
    func conversionIgualAlEjemplo() throws {
        let origen = try #require(RutasConformidad.origenRibera)
        let plan = try ConversorG2.planificar(origen: origen, opciones: OpcionesConversionG2(clase: .demo, hoy: "2026-10-19"))
        var arbol: [String: Data] = [:]
        for (ruta, _) in plan.ficheros { arbol[ruta.raw] = try plan.datos(ruta) }
        let ejemplo = try Arbol.leer(RutasConformidad.ejemploRibera)
        if RutasConformidad.actualizarGolden {
            try Arbol.reemplazarGolden(RutasConformidad.ejemploRibera,
                                       con: CapaRibera.ejemploRegenerado(conversion: arbol, ejemplo: ejemplo))
            return
        }
        let difs = CapaRibera.diferencias(conversion: arbol, ejemplo: ejemplo)
        #expect(difs.isEmpty, "\(difs.prefix(20).joined(separator: "\n")) · regenera con scripts/conformidad.sh --regenerar-ribera")
    }

    @Test("La capa de Ribera cuadra con el ejemplo aunque no esté la carpeta G2: lo añadido existe y lo sustituido ya está")
    func capaDeRibera() throws {
        let ejemplo = try Arbol.leer(RutasConformidad.ejemploRibera)
        for r in CapaRibera.anadidos + CapaRibera.ampliados { #expect(ejemplo[r] != nil, "falta \(r)") }
        for (de, a) in CapaRibera.renombrados { #expect(ejemplo[de] == nil && ejemplo[a] != nil, "\(a)") }
        for (ruta, de, por) in CapaRibera.sustituciones {
            let t = String(decoding: try #require(ejemplo[ruta], "falta \(ruta)"), as: UTF8.self)
            #expect(t.contains(por), "\(ruta): no dice «\(por.prefix(60))»")
            #expect(!t.contains(de) || por.contains(de), "\(ruta): aún dice «\(de.prefix(60))»")
        }
        // Las áreas dicen su estado (la maqueta de Ribera) y la configuración trae a sus asistentes.
        let estados = ["1 · Dirección": "activa", "2 · Ventas": "activa", "3 · Entrega": "activa", "4 · Finanzas": "activa",
                       "5 · Marca": "preparada", "6 · Equipo": "en reposo"]
        for (area, estado) in estados {
            #expect(NoteDocument(data: try #require(ejemplo["\(area)/Área.md"])).frontmatter.text("estado") == estado, "\(area)")
        }
        let config = FrontmatterReader.read(String(decoding: try #require(ejemplo[".tls/config.yaml"]), as: UTF8.self))
        #expect(config.isValid && config.text("interruptor") == "encendido" && config.value("agentes") != nil)
    }

    @Test("Convertir Ribera dos veces da el mismo hash de árbol (si la carpeta G2 está en este Mac)",
          .enabled(if: RutasConformidad.origenRibera != nil))
    func dosConversiones() async throws {
        let origen = try #require(RutasConformidad.origenRibera)
        let base = RutasConformidad.temporal("ribera")
        defer { try? FileManager.default.removeItem(at: base) }
        let opciones = OpcionesConversionG2(clase: .demo, hoy: "2026-10-19")
        let a = try await ConversorG2.convertir(origen: origen, destino: base.appendingPathComponent("a"), opciones: opciones)
        let b = try await ConversorG2.convertir(origen: origen, destino: base.appendingPathComponent("b"), opciones: opciones)
        #expect(a.hashArbol != nil)
        #expect(a.hashArbol == b.hashArbol)
        #expect(a.tareas == 2)
        #expect(a.verificados == 9)
    }
}
