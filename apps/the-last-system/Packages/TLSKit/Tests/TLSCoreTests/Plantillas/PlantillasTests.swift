import Foundation
import Testing
@testable import TLSCore

/// Reloj fijo: jueves 22 de octubre de 2026 a las 09:05.
func relojDePrueba(_ y: Int = 2026, _ m: Int = 10, _ d: Int = 22) -> Reloj {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = 9; c.minute = 5
    let ahora = Calendar(identifier: .gregorian).date(from: c)!
    return Reloj(hoy: LocalDate(year: y, month: m, day: d)!, ahora: ahora)
}

@Suite("Plantillas: registro y originales")
struct PlantillaRegistroTests {
    @Test func noventaPlantillasConSuOrigen() throws {
        let serie = PlantillaRegistro.deSerie
        #expect(serie.plantillas.count == 90)
        #expect(Set(serie.plantillas.map(\.id)).count == 90)
        let ficheros = PlantillasDeSerie.ficheros
        #expect(ficheros.count == 90)
        // Cada original está en el registro una vez y su `tls_type` es el del registro.
        var usados = Set<String>()
        for def in serie.plantillas {
            let origen = try #require(def.origen)
            let texto = try #require(PlantillasDeSerie.texto(origen), "\(origen)")
            #expect(usados.insert(origen.precomposedStringWithCanonicalMapping).inserted)
            #expect(NoteDocument(text: texto).frontmatter.text("tls_type") == def.tipo, "\(def.id)")
            #expect(def.fichero.hasSuffix("/Sistemas/Plantillas/" + VaultPath(origen).name), "\(def.id)")
            if !def.esFragmento { #expect(def.nombre != nil, "\(def.id)") }
        }
        #expect(Set(ficheros) == usados)
    }

    @Test func igualesALaPropuesta() throws {
        // Las originales de la app son las de docs/propuesta/plantillas (sin los EJEMPLOS).
        for rel in PlantillasDeSerie.ficheros {
            let doc = try Data(contentsOf: VaultPath(rel).url(in: RutasRepo.plantillasPropuesta))
            #expect(PlantillasDeSerie.datos(rel) == doc, "\(rel)")
        }
    }

    @Test func comunesEnDireccionYCadaUnaEnSuArea() {
        let serie = PlantillaRegistro.deSerie
        #expect(serie["tarea"]?.fichero == "{direccion}/Sistemas/Plantillas/Tarea.md")
        #expect(serie["factura"]?.area == .finanzas)
        #expect(serie["reunion-de-descubrimiento"]?.variantePor == "servicio")
        #expect(serie["tarea"]?.carpetaSi.first?.rol == "proyecto")
        #expect(serie.desde(tipo: "contact").map(\.id).contains("reunion"))
        #expect(serie.desde(tipo: "organization").map(\.id).contains("factura"))
    }

    @Test func leerUnRegistroPropio() throws {
        let r = try PlantillaRegistro.parse("""
        # comentario
        factura:
          fichero: "4 · Finanzas/Sistemas/Plantillas/Factura.md"
          tipo: invoice
          carpeta: "{finanzas}/Fiscal/Borradores"
          nombre: "{{empresa.slug}}-{{fecha}}"
          preguntas: [oportunidad, hito]
          modulo: facturas-y-cobros
        """)
        #expect(r["factura"]?.preguntas == ["oportunidad", "hito"])
        #expect(r["factura"]?.carpeta == "{finanzas}/Fiscal/Borradores")
        #expect(throws: PlantillaError.self) { try PlantillaRegistro.parse("- no\n- es un mapa\n") }
    }
}

@Suite("Plantillas: formatos")
struct FormatosPlantillaTests {
    @Test func importesYPorcentajes() {
        #expect(FormatosPlantilla.aplicar("181.50", formato: "€") == "181,50 €")
        #expect(FormatosPlantilla.aplicar("18400", formato: "€") == "18.400,00 €")
        #expect(FormatosPlantilla.aplicar("-663", formato: "€") == "-663,00 €")
        #expect(FormatosPlantilla.aplicar("21", formato: "%") == "21 %")
        #expect(FormatosPlantilla.aplicar("10.5", formato: "%") == "10,5 %")
    }

    @Test func importesEnLetra() {
        #expect(FormatosPlantilla.enLetra("181.50") == "ciento ochenta y un euros con cincuenta céntimos")
        #expect(FormatosPlantilla.enLetra("1") == "un euro")
        #expect(FormatosPlantilla.enLetra("21") == "veintiún euros")
        #expect(FormatosPlantilla.enLetra("100") == "cien euros")
        #expect(FormatosPlantilla.enLetra("1000") == "mil euros")
        #expect(FormatosPlantilla.enLetra("21000") == "veintiún mil euros")
        #expect(FormatosPlantilla.enLetra("1000000") == "un millón de euros")
        #expect(FormatosPlantilla.enLetra("2531.01") == "dos mil quinientos treinta y un euros con un céntimo")
    }

    @Test func fechasYPeriodos() {
        let d = LocalDate(year: 2026, month: 10, day: 30)!
        #expect(FormatosPlantilla.aplicar("2026-10-30", formato: "corta") == "30 oct")
        #expect(FormatosPlantilla.aplicar("2026-10-30", formato: "larga") == "30 de octubre de 2026")
        #expect(FormatosPlantilla.aplicar("2026-10", formato: "larga") == "octubre de 2026")
        #expect(FormatosPlantilla.semana(LocalDate(year: 2026, month: 10, day: 22)!) == "2026-S43")
        #expect(FormatosPlantilla.semana(LocalDate(year: 2027, month: 1, day: 1)!) == "2026-S53")
        #expect(FormatosPlantilla.trimestre(d) == "T4 2026")
        #expect(FormatosPlantilla.aplicar("T4 2026", formato: "corto") == "T4")
        // Viernes + 1 laborable = lunes.
        #expect(FormatosPlantilla.sumarLaborables(LocalDate(year: 2026, month: 10, day: 23)!, 1).description == "2026-10-26")
        #expect(FormatosPlantilla.sumarLaborables(LocalDate(year: 2026, month: 10, day: 22)!, 5).description == "2026-10-29")
        #expect(FormatosPlantilla.aplicar("true", formato: "sino") == "sí")
        #expect(FormatosPlantilla.aplicar("T-0031", formato: "cifras") == "0031")
    }

    @Test func secuencias() throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        #expect(Secuencias.op(["tarea": 3], en: env.foto()) == .create(Secuencias.ruta, text: "{\"tarea\":3}\n"))
        env.escribir(".tls/secuencias.json", "{\n  \"tarea\": 12,\n  \"otra\": 1\n}\n")
        let foto = env.foto()
        #expect(Secuencias.leer(foto) == ["tarea": 12, "otra": 1])
        guard case .editRanges(_, let edits, _)? = Secuencias.op(["tarea": 13, "recibo-2026": 1], en: foto) else {
            Issue.record("Debía editar"); return
        }
        var bytes = Array(foto.text(Secuencias.ruta)!.utf8)
        for e in edits.sorted(by: { $0.offset > $1.offset }) {
            bytes.replaceSubrange(e.offset..<(e.offset + e.length), with: Array(e.replacement.utf8))
        }
        #expect(String(decoding: bytes, as: UTF8.self) == "{\n  \"tarea\": 13,\n  \"otra\": 1,\"recibo-2026\":1\n}\n")
    }
}

@Suite("Plantillas: crear notas")
struct PlantillaMotorTests {
    func motor(_ env: EntornoCarpeta, yo: String = "Manu", guias: Bool = true) -> PlantillaMotor {
        PlantillaMotor(snapshot: env.foto(), opciones: .init(yo: yo, copiarGuias: guias, reloj: relojDePrueba()))
    }

    @Test func tareaConNombreEstandar() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        let nota = try motor(env).preparar(.init(plantilla: "tarea", valores: ["titulo": "Preparar propuesta económica para NEXO"],
                                                 area: .ventas))
        #expect(nota.ruta.raw == "2 · Ventas/Tareas/t-0001-preparar-propuesta-economica-para-nexo.md")
        #expect(nota.numero == "T-0001")
        let lineas = nota.texto.components(separatedBy: "\n")
        #expect(lineas[0] == "---")
        #expect(lineas[1] == "tls_type: task")
        #expect(lineas[2] == "tls_schema: 1")
        #expect(lineas[3].hasPrefix("id: "))
        #expect(Array(lineas[4...11]) == [
            "numero: T-0001", "titulo: Preparar propuesta económica para NEXO", "estado: Sin programar", "tipo: tarea",
            "area: ventas", "origen: manual", "creada: 2026-10-22", "creada_por: Manu",
        ])
        #expect(lineas[12] == "plantilla: \"Tarea v1\"")
        #expect(lineas[13] == "---")
        #expect(lineas[14] == "# Preparar propuesta económica para NEXO")
        // Del resumen solo queda el tramo con dato.
        #expect(lineas[15] == "> Sin programar")
        #expect(nota.texto.contains("## Descripción\n> Guía: qué hay que hacer"))
        #expect(nota.faltan.isEmpty)
        // El plan crea la nota y el contador; nada más.
        #expect(nota.plan.ops.count == 2)
        let bus = try await env.bus()
        let antes = env.huella()
        let r = try await bus.ejecutar(nota.plan)
        #expect(r.hecho)
        let despues = env.huella()
        #expect(Set(despues.keys).subtracting(antes.keys) == [nota.ruta.raw, ".tls/secuencias.json"])
        #expect(env.texto(".tls/secuencias.json") == "{\"tarea\":1}\n")
        // La siguiente toma el número 2 y solo cambia el contador.
        let otra = try motor(env).preparar(.init(plantilla: "tarea", valores: ["titulo": "Otra"], area: .ventas))
        #expect(otra.ruta.raw == "2 · Ventas/Tareas/t-0002-otra.md")
        _ = try await bus.ejecutar(otra.plan)
        #expect(env.texto(".tls/secuencias.json") == "{\"tarea\":2}\n")
    }

    @Test func reunionDesdeUnContactoQuedaEnlazada() throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let m = PlantillaMotor(snapshot: env.foto(), opciones: .init(yo: "Elena Castell"))
        // La demo tiene el reloj fijo en 2026-10-19.
        let nota = try m.preparar(.init(plantilla: "reunion", desde: VaultPath("2 · Ventas/Contactos/jorge-martin.md"),
                                        valores: ["titulo": "Llamada de seguimiento", "hora": "10:00"]))
        #expect(nota.ruta.raw == "2 · Ventas/Reuniones/2026-10-19-llamada-de-seguimiento.md")
        let fm = NoteDocument(text: nota.texto).frontmatter
        #expect(fm.text("empresa") == "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]")
        #expect(fm.value("personas") == .list(["[[jorge-martin|Jorge Martín]]"]))
        #expect(fm.text("area") == "ventas")
        #expect(fm.text("fecha") == "2026-10-19")
        #expect(fm.text("oportunidad") == nil)
        #expect(nota.texto.contains("> Prevista · 19 oct 10:00 · 60 min · Talleres Martín e Hijos SL\n"))
    }

    @Test func descubrimientoDesdeLaOportunidad() throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let m = PlantillaMotor(snapshot: env.foto())
        let nota = try m.preparar(.init(plantilla: "reunion-de-descubrimiento",
                                        desde: VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")))
        #expect(nota.ruta.raw == "2 · Ventas/Oportunidades/jorge-martin-trimestrales/Reuniones/2026-10-19-descubrimiento-trimestrales.md")
        #expect(nota.titulo == "Descubrimiento · Trimestrales · Talleres Martín e Hijos SL")
        let fm = NoteDocument(text: nota.texto).frontmatter
        #expect(fm.text("oportunidad") == "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]")
        #expect(fm.text("servicio") == "[[2 · Ventas/Productos/trimestrales|Trimestrales]]")
        #expect(fm.value("personas") == .list(["[[jorge-martin|Jorge Martín]]"]))
        #expect(nota.texto.contains("> Prevista · 19 oct · 45 min · con Jorge Martín\n"))
    }

    @Test func varianteDelServicio() throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let variante = try String(contentsOf: RutasRepo.plantillasPropuesta.appendingPathComponent("EJEMPLOS/Reunión de descubrimiento · Trimestrales.md"), encoding: .utf8)
        env.escribir("2 · Ventas/Sistemas/Plantillas/Reunión de descubrimiento · Trimestrales.md", variante)
        let servicio = env.texto("2 · Ventas/Productos/trimestrales.md")!
        env.escribir("2 · Ventas/Productos/trimestrales.md", servicio.replacingOccurrences(
            of: "recurrencia: trimestral\n", with: "recurrencia: trimestral\ndescubrimiento: \"[[Reunión de descubrimiento · Trimestrales]]\"\n"))
        let nota = try PlantillaMotor(snapshot: env.foto()).preparar(.init(plantilla: "reunion-de-descubrimiento",
                                                                          desde: VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")))
        #expect(nota.texto.contains("plantilla: \"Reunión de descubrimiento · Trimestrales v1\""))
        #expect(nota.texto.contains("### Encaje con Trimestrales"))
        #expect(nota.texto.contains("> Prevista · 19 oct · 30 min · con Jorge Martín\n"))
        #expect(NoteDocument(text: nota.texto).frontmatter.text("duracion_min") == "30")
    }

    @Test func facturaConFilasQueSeRepitenYFaltas() throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let lineas = [["concepto": "Trimestrales T4", "cantidad": "1", "precio": "150.00", "descuento": "0", "iva_pct": "21", "importe": "150.00"],
                      ["concepto": "Alta", "cantidad": "1", "precio": "30", "descuento": "0", "iva_pct": "21", "importe": "30"]]
        let nota = try PlantillaMotor(snapshot: env.foto()).preparar(.init(
            plantilla: "factura", desde: VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md"),
            valores: ["total": "217.80"], listas: ["linea": lineas]))
        #expect(nota.ruta.raw == "4 · Finanzas/Fiscal/Borradores/talleres-martin-e-hijos-2026-10-19.md")
        #expect(nota.texto.contains("| Trimestrales T4 | 1 | 150,00 € | 0 % | 21 % | 150,00 € |\n| Alta | 1 | 30,00 € | 0 % | 21 % | 30,00 € |\n"))
        // Sin número aún (lo pone quien emite): el título lo dice y la propiedad no se escribe.
        #expect(nota.texto.contains("# Factura [falta: numero]"))
        #expect(nota.faltan.contains("numero"))
        #expect(NoteDocument(text: nota.texto).frontmatter.text("numero") == nil)
        // La línea de resumen se queda con lo que hay.
        #expect(nota.texto.contains("> Borrador · 217,80 € · Talleres Martín e Hijos SL\n"))
        #expect(nota.texto.contains("| **Total a pagar** | **217,80 €** |"))
    }

    @Test func elEmisorNuncaSeEscribe() throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let factura = try #require(env.foto().files.first { $0.raw.contains("/Ingresos/f-2026-0007") })
        let nota = try PlantillaMotor(snapshot: env.foto()).preparar(.init(plantilla: "recordatorio-de-cobro", desde: factura))
        #expect(nota.texto.contains("{{emisor.cuenta}}"))
        #expect(!nota.faltan.contains("emisor.cuenta"))
    }

    @Test func sinDatoParaElNombreNoSeInventa() {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        #expect(throws: PlantillaError.faltaDato("contacto.slug")) {
            try motor(env).preparar(.init(plantilla: "oportunidad"))
        }
        #expect(throws: PlantillaError.noExiste("no-existe")) { try motor(env).preparar(.init(plantilla: "no-existe")) }
        #expect(throws: PlantillaError.esFragmento("traspaso")) { try motor(env).preparar(.init(plantilla: "traspaso")) }
    }

    @Test func ordenYVersion() throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        // jorge-martin-trimestrales ya tiene «Propuesta v1»: la siguiente es la v2.
        let nota = try PlantillaMotor(snapshot: env.foto()).preparar(.init(plantilla: "propuesta",
                                                                          desde: VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")))
        #expect(nota.ruta.raw == "2 · Ventas/Oportunidades/jorge-martin-trimestrales/Propuesta v2.md")
    }

    @Test func sinGuiasSiSeApagan() throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        let nota = try motor(env, guias: false).preparar(.init(plantilla: "tarea", valores: ["titulo": "X"]))
        #expect(!nota.texto.contains("> Guía:"))
        #expect(nota.ruta.raw == "1 · Dirección/Tareas/t-0001-x.md")
    }

    @Test func usaLaPlantillaInstaladaSiExiste() throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        var t = PlantillasDeSerie.texto("Comunes/Tarea.md")!
        t = t.replacingOccurrences(of: "## Descripción", with: "## Qué hay que hacer")
        env.escribir("1 · Dirección/Sistemas/Plantillas/Tarea.md", t)
        let nota = try motor(env).preparar(.init(plantilla: "tarea", valores: ["titulo": "X"]))
        #expect(nota.texto.contains("## Qué hay que hacer"))
    }

    @Test func aplicarAUnaNotaQueYaExisteSoloAnade() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let ruta = VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")
        let antes = env.texto(ruta.raw)!
        let plan = try #require(try motor(env).aplicar("contacto", a: ruta))
        _ = try await (try await env.bus()).ejecutar(plan)
        let despues = env.texto(ruta.raw)!
        let doc = FrontmatterDocument(text: despues)
        // Lo que había sigue igual.
        for k in FrontmatterDocument(text: antes).keys { #expect(doc.rawLines(k) == FrontmatterDocument(text: antes).rawLines(k), "\(k)") }
        #expect(doc.value("tls_type") == .text("contact"))
        #expect(doc.value("id") != nil)
        #expect(doc.value("estado") == .text("Interesado"))
        #expect(despues.contains(NoteDocument(text: antes).body.trimmingCharacters(in: .newlines)))
        #expect(MarkdownSections.titles(in: doc.body).contains("Cómo llegó"))
        // Aplicarla otra vez no cambia nada.
        #expect(try motor(env).aplicar("contacto", a: ruta) == nil)
    }

    @Test func fragmentoDeSeccion() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let ruta = VaultPath("3 · Entrega/Proyectos/web-ferreteria/Proyecto.md")
        let plan = try #require(try motor(env).insertarFragmento("traspaso", en: ruta))
        _ = try await (try await env.bus()).ejecutar(plan)
        #expect(env.texto(ruta.raw)!.contains("## Traspaso\n\n| Pieza | Estado | Dónde está |"))
        #expect(try motor(env).insertarFragmento("traspaso", en: ruta) == nil)
        #expect(throws: PlantillaError.noEsFragmento("tarea")) { try motor(env).insertarFragmento("tarea", en: ruta) }
    }

    @Test func rellenarLoQueQuedoSinSustituir() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Tareas/t-0007-de-obsidian.md", "---\ntls_type: task\nid: \"{{id}}\"\nnumero: \"{{numero}}\"\ncreada: \"{{fecha}}\"\n---\n# De Obsidian\n")
        let m = motor(env)
        #expect(m.variablesSinRellenar(VaultPath("1 · Dirección/Tareas/t-0007-de-obsidian.md")) == ["id", "numero", "fecha"])
        let plan = try #require(m.rellenarPendientes(VaultPath("1 · Dirección/Tareas/t-0007-de-obsidian.md")))
        _ = try await (try await env.bus()).ejecutar(plan)
        let fm = NoteDocument(text: env.texto("1 · Dirección/Tareas/t-0007-de-obsidian.md")!).frontmatter
        #expect(fm.text("numero") == "T-0008")
        #expect(fm.text("creada") == "2026-10-22")
        #expect(fm.text("id")?.count == 36)
    }
}

@Suite("Plantillas: instalación")
struct PlantillaInstaladorTests {
    @Test func instalarTodasYNoPisarNada() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        let informe = PlantillaInstalador(snapshot: env.foto()).preparar()
        #expect(informe.nuevas.count == 90)
        #expect(informe.registro.count == 90)
        let bus = try await env.bus()
        _ = try await bus.ejecutar(try #require(informe.plan))
        #expect(env.existe("1 · Dirección/Sistemas/Plantillas/Tarea.md"))
        #expect(env.existe("4 · Finanzas/Sistemas/Plantillas/Factura.md"))
        #expect(env.existe("6 · Equipo/Sistemas/Plantillas/Conexión.md"))
        // El registro instalado se lee igual que el de serie.
        let foto = env.foto()
        let propio = try PlantillaRegistro.parse(foto.text(PlantillaRegistro.ruta)!)
        #expect(propio.plantillas.map(\.id) == PlantillaRegistro.deSerie.plantillas.map(\.id))
        // Otra vez: nada que hacer.
        #expect(PlantillaInstalador(snapshot: foto).preparar().plan == nil)
        // Una cambiada por ti no se pisa.
        env.escribir("1 · Dirección/Sistemas/Plantillas/Tarea.md", "mía\n")
        let otra = PlantillaInstalador(snapshot: env.foto()).preparar()
        #expect(otra.distintas.map(\.raw) == ["1 · Dirección/Sistemas/Plantillas/Tarea.md"])
        #expect(otra.plan == nil)
        // Las plantillas instaladas no son fichas: no cuentan como tareas.
        #expect(TaskStore(snapshot: env.foto()).tareas.isEmpty)
    }

    @Test func instalarPorSistemaYCompletarElRegistro() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        let bus = try await env.bus()
        let ventas = PlantillaInstalador(snapshot: env.foto()).preparar(sistemas: ["VE1"])
        #expect(ventas.nuevas.contains(VaultPath("2 · Ventas/Sistemas/Plantillas/Servicio.md")))
        #expect(!ventas.nuevas.contains(VaultPath("4 · Finanzas/Sistemas/Plantillas/Factura.md")))
        _ = try await bus.ejecutar(try #require(ventas.plan))
        let registro1 = env.texto(".tls/plantillas.yaml")!
        let finanzas = PlantillaInstalador(snapshot: env.foto()).preparar(areas: [.finanzas])
        _ = try await bus.ejecutar(try #require(finanzas.plan))
        let registro2 = env.texto(".tls/plantillas.yaml")!
        // Lo que había no cambia: solo se añade al final.
        #expect(registro2.hasPrefix(registro1))
        #expect(try PlantillaRegistro.parse(registro2)["factura"] != nil)
    }
}
