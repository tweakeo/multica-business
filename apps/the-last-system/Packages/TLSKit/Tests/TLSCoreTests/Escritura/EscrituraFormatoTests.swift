import Foundation
import Testing
@testable import TLSCore

/// Criterios F1 1 y 2: ida y vuelta sin cambiar un byte y `mergeFrontmatter` quirúrgico.
@Suite struct EscrituraFormatoTests {
    // MARK: Criterio 1 · 0 bytes de diferencia

    /// Muestras con todo lo que suele romper una reescritura: BOM, `\r\n`, sin salto final,
    /// comentarios, listas en bloque, comillas, `...` de cierre, CSV con `;`, comillas y saltos dentro.
    static let muestras: [(String, String)] = [
        ("crlf.md", "---\r\ntls_type: task\r\ntitulo: \"Hola: mundo\"\r\n# comentario\r\nlista:\r\n  - a\r\n  - \"[[b|B]]\"\r\n---\r\n\r\n## Descripción\r\nTexto\r\n"),
        ("bom.md", "\u{FEFF}---\nid: 1\n---\n# Título\n\nSin salto final"),
        ("puntos.md", "---\nclave: valor\n...\nCuerpo\n"),
        ("vacio.md", "---\n---\n"),
        ("solo-cuerpo.md", "# Nota\n\n---\n\nUna raya no es frontmatter.\n"),
        ("comentarios.md", "---\nestado: Por hacer          # Sin programar | Por hacer\nproyecto_id:               # obligatorio\n'clave rara': x\n---\n"),
        ("raro.md", "---\nbloque: |\n  línea 1\n\n  línea 3\nmapa:\n  a: 1\n  b: [1, 2]\n---\ncuerpo\r\n"),
        ("cr.md", "---\rid: x\r---\rcuerpo\r"),
        ("dañado.md", "---\nclave: [sin cerrar\n---\ncuerpo\n"),
        ("puntoycoma.csv", "\u{FEFF}fecha;concepto;importe\r\n01/10/2026;\"Pago; con punto y coma\";-12,50\r\n02/10/2026;Otro;3\r\n"),
        ("multilinea.csv", "id,nota,importe\n1,\"línea 1\nlínea 2\",3\n2,\"con \"\"comillas\"\"\",4"),
        ("irregular.csv", "id,a,b\n1,x\n\n2,y,z,extra\n"),
        ("cr.csv", "id,a\r1,x\r2,y\r"),
    ]

    @Test func idaYVueltaSinCambios() throws {
        var revisados = 0
        for url in ficherosDeTexto(Apoyo.empresaMinima) {
            let data = try Data(contentsOf: url)
            try comprobarIdaYVuelta(data, ext: url.pathExtension, nombre: url.lastPathComponent)
            revisados += 1
        }
        for (nombre, texto) in Self.muestras {
            try comprobarIdaYVuelta(Data(texto.utf8), ext: (nombre as NSString).pathExtension, nombre: nombre)
            revisados += 1
        }
        #expect(revisados > 40)
    }

    func comprobarIdaYVuelta(_ data: Data, ext: String, nombre: String) throws {
        switch ext {
        case "md":
            let doc = try #require(FrontmatterDocument(data: data), "\(nombre)")
            #expect(doc.data == data, "\(nombre)")
            // Lee igual que el lector de F0.
            let nd = NoteDocument(data: data)
            #expect(doc.frontmatterText == nd.frontmatterText, "\(nombre)")
            #expect(doc.body == nd.body, "\(nombre)")
            // Reescribir una clave con su mismo valor no cambia nada.
            var again = doc
            for p in doc.frontmatter.properties { again.set(p.key, p.value) }
            #expect(again.data == data, "\(nombre)")
        case "csv":
            let csv = try #require(CSVDocument(data: data), "\(nombre)")
            #expect(csv.data == data, "\(nombre)")
            let table = CSVTable.parse(TextDecoding.decode(data)!)
            #expect(csv.header == table.header, "\(nombre)")
            #expect(csv.rows.count == table.rows.count, "\(nombre)")
        default:
            break
        }
    }

    /// Con `TLS_RIBERA_DIR` o `TLS_COPIA_DIR`: todos sus .md y .csv dan 0 bytes de diferencia.
    /// Solo lee (en memoria); no escribe nada en esas carpetas ni guarda datos en el repositorio.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TLS_RIBERA_DIR"] != nil
                   || ProcessInfo.processInfo.environment["TLS_COPIA_DIR"] != nil))
    func idaYVueltaEnCarpetasDeVerdad() throws {
        for key in ["TLS_RIBERA_DIR", "TLS_COPIA_DIR"] {
            guard let dir = ProcessInfo.processInfo.environment[key] else { continue }
            let root = URL(fileURLWithPath: dir, isDirectory: true)
            var n = 0, saltados = 0
            try UbiquityInspector.withoutMaterializing {
                for url in ficherosDeTexto(root) {
                    guard let info = UbiquityInspector.info(url), !info.dataless, !info.isSymlink,
                          let data = try? Data(contentsOf: url) else { saltados += 1; continue }
                    guard EditableText(data: data) != nil else { saltados += 1; continue }
                    try comprobarIdaYVuelta(data, ext: url.pathExtension.lowercased(), nombre: url.lastPathComponent)
                    n += 1
                }
            }
            print("\(key): \(n) ficheros con 0 bytes de diferencia (\(saltados) sin leer: no UTF-8 o solo en iCloud)")
            #expect(n > 0)
        }
    }

    // MARK: Criterio 2 · mergeFrontmatter quirúrgico

    static let tarea = """
    ---\r
    tls_type: task\r
    numero: T-0042\r
    titulo: Preparar propuesta económica para NEXO\r
    estado: Por hacer          # Sin programar | Por hacer | En curso\r
    prioridad: Alta            # Urgente | Alta | Media | Baja\r
    x-propia: «se queda tal cual»\r
    bloqueada_por:\r
      - "[[t-0040]]"\r
    proyecto_id:               # obligatorio dentro de Proyectos\r
    plantilla: "Tarea v1"\r
    ---\r
    \r
    ## Descripción\r
    Texto.\r

    """

    @Test func mergeFrontmatterSoloTocaSusLineas() throws {
        var doc = FrontmatterDocument(text: Self.tarea)
        let antes = doc.text.components(separatedBy: "\r\n")
        doc.merge(set: [Property(key: "estado", value: .text("En curso")),
                        Property(key: "id", value: .text("0b7e5c1e-4f0a-4a59-9a43-2f1d6c0e8a11")),
                        Property(key: "bloqueada_por", value: .list(["[[t-0040]]", "[[t-0041|Otra]]"])),
                        Property(key: "responsable", value: .text("agente:comercial")),
                        Property(key: "nota_nueva", value: .text("valor: con dos puntos"))],
                  unset: ["prioridad"])
        let despues = doc.text.components(separatedBy: "\r\n")
        // La línea de estado conserva el comentario en la misma columna.
        #expect(despues.contains("estado: En curso           # Sin programar | Por hacer | En curso"))
        // `id` va detrás de `tls_type` (orden canónico); `responsable` tras `titulo`/`estado`.
        #expect(Array(despues[1...3]) == ["tls_type: task", "id: 0b7e5c1e-4f0a-4a59-9a43-2f1d6c0e8a11", "numero: T-0042"])
        #expect(despues.firstIndex(of: "responsable: agente:comercial")! < despues.firstIndex(of: "x-propia: «se queda tal cual»")!)
        // La desconocida nueva va antes de `plantilla`, que sigue la última.
        #expect(despues.firstIndex(of: "nota_nueva: \"valor: con dos puntos\"")! < despues.firstIndex(of: "plantilla: \"Tarea v1\"")!)
        // Lista en bloque: sigue en bloque y con su sangría.
        #expect(despues.contains("  - \"[[t-0041|Otra]]\""))
        #expect(!despues.contains { $0.hasPrefix("prioridad") })
        // Lo demás, idéntico y en el mismo orden.
        let tocadas: Set<String> = ["estado", "id", "bloqueada_por", "responsable", "nota_nueva", "prioridad"]
        func intactas(_ lines: [String]) -> [String] {
            var out: [String] = []
            var dentro = false
            for l in lines {
                if let k = FrontmatterDocument.parseKeyLine(l)?.name { dentro = tocadas.contains(k) }
                else if !(l.hasPrefix(" ") || l.hasPrefix("\t")) { dentro = false }
                if !dentro { out.append(l) }
            }
            return out
        }
        #expect(intactas(antes) == intactas(despues))
        #expect(doc.body == FrontmatterDocument(text: Self.tarea).body)
        let fm = doc.frontmatter
        #expect(fm.isValid)
        #expect(fm.value("estado") == .text("En curso"))
        #expect(fm.value("bloqueada_por") == .list(["[[t-0040]]", "[[t-0041|Otra]]"]))
        #expect(fm.value("nota_nueva") == .text("valor: con dos puntos"))
        #expect(fm.value("x-propia") == .text("«se queda tal cual»"))
    }

    /// 1.000 casos aleatorios: el 100 % cambia solo las líneas objetivo.
    @Test func mergeFrontmatterAleatorio() throws {
        var g = Semilla(42)
        let claves = ["tls_type", "id", "titulo", "estado", "responsable", "vence", "empresa", "aliases", "x_uno", "Otra clave", "valor", "plantilla"]
        let valores: [PropertyValue] = [
            .text("Por hacer"), .text("2026-10-27"), .text("[[panaderia-sol|Panadería Sol]]"), .text("a: b"), .text("1.0"),
            .text("true"), .text("#etiqueta"), .text(" espacio"), .text("comillas \" y \\ barra"), .text("- guion"),
            .text("línea\nnueva"), .text("agente:comercial"), .number("12"), .number("-3.5"), .bool(true), .bool(false),
            .list([]), .list(["a", "b, c", "[[x]]"]), .list(["solo"]), .empty,
        ]
        for caso in 0..<1000 {
            let eol = Bool.random(using: &g) ? "\n" : "\r\n"
            var lines: [String] = []
            var presentes: [String] = []
            for k in claves where Int.random(in: 0..<3, using: &g) > 0 {
                presentes.append(k)
                if Int.random(in: 0..<6, using: &g) == 0 { lines.append("# comentario \(k)") }
                let v = valores.aleatorio(&g)
                let key = FrontmatterDocument.renderKey(k)
                if case .list(let l) = v, !l.isEmpty, Bool.random(using: &g) {
                    lines.append("\(key):")
                    for i in l { lines.append("  - " + YAMLScalar.render(text: i)) }
                } else {
                    let inline = YAMLScalar.inline(v) ?? ""
                    let comment = Int.random(in: 0..<4, using: &g) == 0 ? "    # nota" : ""
                    lines.append(inline.isEmpty ? "\(key):\(comment)" : "\(key): \(inline)\(comment)")
                }
            }
            let bom = Int.random(in: 0..<5, using: &g) == 0 ? "\u{FEFF}" : ""
            let texto = bom + "---" + eol + lines.map { $0 + eol }.joined() + "---" + eol + "# Cuerpo" + eol + "texto" + eol
            var doc = FrontmatterDocument(text: texto)
            #expect(doc.text == texto)
            let antes = doc.frontmatter
            #expect(antes.isValid, "caso \(caso)")
            // Operaciones: poner existentes, poner nuevas y quitar.
            var set: [Property] = []
            var unset: [String] = []
            for k in claves {
                switch Int.random(in: 0..<5, using: &g) {
                case 0: set.append(Property(key: k, value: valores.aleatorio(&g)))
                case 1 where presentes.contains(k): unset.append(k)
                default: break
                }
            }
            let objetivo = Set(set.map(\.key) + unset)
            doc.merge(set: set, unset: unset)
            let despues = doc.frontmatter
            #expect(despues.isValid, "caso \(caso): \(doc.text)")
            #expect(doc.body == FrontmatterDocument(text: texto).body)
            #expect(doc.text.hasPrefix(bom + "---" + eol))
            // Las claves no tocadas valen lo mismo y aparecen en el mismo orden.
            let keep = { (f: Frontmatter) in f.properties.filter { !objetivo.contains($0.key) } }
            #expect(keep(antes) == keep(despues), "caso \(caso)")
            // Y sus líneas son idénticas, byte a byte.
            func lineasAjenas(_ d: FrontmatterDocument) -> [String] {
                let all = TextLines.split(d.frontmatterText ?? "")
                var owned = Set<Int>()
                for e in d.entries() where objetivo.contains(e.name) { owned.formUnion(e.range) }
                return all.indices.filter { !owned.contains($0) }.map { all[$0].full }
            }
            #expect(lineasAjenas(FrontmatterDocument(text: texto)) == lineasAjenas(doc), "caso \(caso)")
            // Lo pedido está.
            for p in set where !(p.value == .empty && !presentes.contains(p.key) && !unset.contains(p.key)) {
                let v = doc.value(p.key)
                if p.value == .empty && v == nil { continue }
                #expect(v == p.value, "caso \(caso): \(p.key)")
            }
            for k in unset where !set.contains(where: { $0.key == k }) { #expect(doc.value(k) == nil) }
            // Los saltos nuevos son los del fichero.
            if eol == "\r\n" { #expect(!doc.text.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "caso \(caso)") }
        }
    }

    @Test func notaSinPropiedadesRecibeBloque() {
        var doc = FrontmatterDocument(text: "# Rumbo\r\n\r\nTexto.\r\n")
        doc.set("tls_type", .text("strategy"))
        doc.set("id", .text("abc"))
        #expect(doc.text == "---\r\ntls_type: strategy\r\nid: abc\r\n---\r\n# Rumbo\r\n\r\nTexto.\r\n")
        // Vacías no se escriben.
        doc.set("vence", .empty)
        #expect(doc.value("vence") == nil)
    }

    @Test func escalaresSeReleenIgual() {
        var g = Semilla(7)
        let piezas = ["a", "Ñ", " ", ":", "#", "-", "[", "]", ",", "\"", "'", "\\", "1", ".", "{", "|", ">", "@", "`", "\t", "e", "true", "null", "~", "%", "!", "&", "*", "?"]
        for _ in 0..<3000 {
            let s = (0..<Int.random(in: 1...8, using: &g)).map { _ in piezas.aleatorio(&g) }.joined()
            let yaml = "k: " + YAMLScalar.render(text: s) + "\nl: " + YAMLScalar.flowList([s, "x"]) + "\n"
            let fm = FrontmatterReader.read(yaml)
            #expect(fm.value("k") == .text(s), "«\(s)» → \(yaml)")
            #expect(fm.value("l") == .list([s, "x"]), "«\(s)» → \(yaml)")
        }
    }

    // MARK: CSV

    @Test func csvActualizaEnSuSitio() throws {
        let original = try Data(contentsOf: Apoyo.empresaMinima.appendingPathComponent("4 · Finanzas/Registros/emitidas.csv"))
        var csv = try #require(CSVDocument(data: original))
        #expect(csv.bom && csv.eol == "\r\n")
        #expect(try csv.upsert(["id": "F-2026-002", "importe": "95.00"], protectManual: true) == .actualizada)
        let texto = String(decoding: csv.data.dropFirst(3), as: UTF8.self)
        // Solo cambia ese campo; la fila de varias líneas entre comillas sigue igual.
        #expect(texto == "id,fecha,cliente,concepto,importe\r\nF-2026-001,2026-09-15,\"Ferretería Ejemplo, S.L.\",\"Web \"\"básica\"\"\",1200.00\r\nF-2026-002,2026-10-01,Cliente Ficticio,\"Mantenimiento\r\nmensual\",95.00\r\n")
        #expect(try csv.upsert(["id": "F-2026-003", "fecha": "2026-10-20", "cliente": "Asesoría Ribera", "concepto": "Alta, inicial"],
                               protectManual: true) == .insertada)
        #expect(String(decoding: csv.data, as: UTF8.self).hasSuffix("\r\nF-2026-003,2026-10-20,Asesoría Ribera,\"Alta, inicial\",\r\n"))
        #expect(csv.data.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(try csv.upsert(["id": "F-2026-003", "fecha": "2026-10-20"], protectManual: true) == .sinCambios)
        #expect(throws: WriteError.columnaDesconocida("nueva")) { try csv.upsert(["id": "F-2026-003", "nueva": "x"], protectManual: true) }
    }

    @Test func csvRespetaFilasManualesYColumnasDesconocidas() throws {
        let texto = "ruta,fecha,fuente,nota,extra_mia\nA.pdf,2026-01-01,manual,puesta a mano,⚑\nB.pdf,2026-01-02,ocr,,\nB.pdf,2026-01-03,ocr,,\n"
        var csv = CSVDocument(text: texto)
        #expect(throws: WriteError.filaManual("A.pdf")) { try csv.upsert(["ruta": "A.pdf", "fecha": "2026-02-02"], key: "ruta", protectManual: true) }
        #expect(throws: WriteError.claveDuplicada("B.pdf")) { try csv.upsert(["ruta": "B.pdf", "fecha": "2026-02-02"], key: "ruta", protectManual: true) }
        // Una persona sí puede corregir su fila manual; la columna desconocida se conserva.
        #expect(try csv.upsert(["ruta": "A.pdf", "fecha": "2026-02-02"], key: "ruta", protectManual: false) == .actualizada)
        #expect(csv.text == "ruta,fecha,fuente,nota,extra_mia\nA.pdf,2026-02-02,manual,puesta a mano,⚑\nB.pdf,2026-01-02,ocr,,\nB.pdf,2026-01-03,ocr,,\n")
    }

    // MARK: Tablas y secciones

    static let metas = """
    # Metas

    | Código   | Indicador        | Meta | Alerta | Por qué |
    |----------|------------------|-----:|-------:|---------|
    | DIR-DEC14 | Decisiones a tiempo | 90 % | 70 % | Ritmo |
    | VEN-STALE7 | Oportunidades quietas | 0 | 3 | Embudo \\| ventas |

    Texto final.
    """

    @Test func tablaCambiaSoloSusCeldas() throws {
        let nuevo = try MarkdownTable.setCells(in: Self.metas, selector: TableSelector(columna: "Código"), keyColumn: "Código",
                                               keyValue: "VEN-STALE7", cells: ["Meta": "1", "Alerta": "5"], protectManual: true)
        let a = Self.metas.components(separatedBy: "\n"), b = nuevo.components(separatedBy: "\n")
        #expect(a.count == b.count)
        for i in a.indices where i != 5 { #expect(a[i] == b[i]) }
        #expect(b[5] == "| VEN-STALE7 | Oportunidades quietas | 1 | 5 | Embudo \\| ventas |")
        let rows = try #require(MarkdownTable.rows(in: nuevo, selector: TableSelector(columna: "Código")))
        #expect(rows[1]["Por qué"] == "Embudo | ventas")
        let mas = try MarkdownTable.appendRow(in: nuevo, selector: TableSelector(), cells: ["Código": "FIN-CAJA", "Meta": "3 meses"], eol: "\n")
        #expect(mas.components(separatedBy: "\n")[6] == "| FIN-CAJA |  | 3 meses |  |  |")
        #expect(mas.hasSuffix("\n\nTexto final."))
        #expect(throws: WriteError.filaNoEncontrada("NO")) {
            try MarkdownTable.setCells(in: Self.metas, selector: TableSelector(), keyColumn: "Código", keyValue: "NO", cells: [:], protectManual: true)
        }
    }

    static let ficha = "## Descripción\nTexto.\n\n## Actividad\n<!-- tls:actividad -->\n\n### 2026-10-21 10:32 · agente:comercial\nHecho.\n\n## Notas\n- una\n"

    @Test func seccionesAnadirYSustituir() throws {
        let con = try MarkdownSections.append(to: "actividad", in: Self.ficha, text: "### 2026-10-22 09:00 · Manu\nOK.",
                                              blankLine: true, create: true, eol: "\n")
        #expect(con == "## Descripción\nTexto.\n\n## Actividad\n<!-- tls:actividad -->\n\n### 2026-10-21 10:32 · agente:comercial\nHecho.\n\n### 2026-10-22 09:00 · Manu\nOK.\n\n## Notas\n- una\n")
        let nueva = try MarkdownSections.append(to: "Opciones", in: "Texto\n", text: "1. A", blankLine: true, create: true, eol: "\n")
        #expect(nueva == "Texto\n\n## Opciones\n\n1. A\n")
        let h = try #require(MarkdownSections.hash(of: "Descripción", in: Self.ficha))
        let sust = try MarkdownSections.replace("Descripción", in: Self.ficha, with: "Otro texto.\nY más.", baseHash: h, eol: "\n")
        #expect(sust.hasPrefix("## Descripción\nOtro texto.\nY más.\n\n## Actividad\n"))
        #expect(throws: WriteError.seccionCambiada("Descripción")) {
            try MarkdownSections.replace("Descripción", in: sust, with: "x", baseHash: h, eol: "\n")
        }
        #expect(MarkdownSections.appendLine("- 2026-10-22 · Nueva", to: "# D\n\n- 2026-10-01 · Vieja\n\n", eol: "\n")
                == "# D\n\n- 2026-10-01 · Vieja\n- 2026-10-22 · Nueva\n\n")
    }

    // MARK: Fusión del editor

    static let base = "---\nestado: Por hacer\nvence: 2026-10-30\n---\n## Descripción\nA\n\n## Actividad\n### e1\nuno\n"

    @Test func fusionDelEditor() {
        let mia = Self.base.replacingOccurrences(of: "A\n", with: "A cambiada\n")
        // Fuera solo cambian propiedades: se fusiona.
        let fueraFM = Self.base.replacingOccurrences(of: "estado: Por hacer", with: "estado: En curso")
        #expect(EditorMerge.merge(base: Self.base, mine: mia, theirs: fueraFM)
                == .merged("---\nestado: En curso\nvence: 2026-10-30\n---\n## Descripción\nA cambiada\n\n## Actividad\n### e1\nuno\n"))
        // Fuera se añadió Actividad y yo también: lo de fuera primero.
        let fueraAct = Self.base + "\n### e2\ndos\n"
        let miaAct = mia + "\n### e3 · Manu\ntres\n"
        #expect(EditorMerge.merge(base: Self.base, mine: miaAct, theirs: fueraAct)
                == .merged("---\nestado: Por hacer\nvence: 2026-10-30\n---\n## Descripción\nA cambiada\n\n## Actividad\n### e1\nuno\n\n### e2\ndos\n\n### e3 · Manu\ntres\n"))
        // Los dos cambiaron la misma propiedad de forma distinta: conflicto.
        let miaFM = Self.base.replacingOccurrences(of: "vence: 2026-10-30", with: "vence: 2026-11-02")
        let fueraFM2 = Self.base.replacingOccurrences(of: "vence: 2026-10-30", with: "vence: 2026-11-05")
        #expect(EditorMerge.merge(base: Self.base, mine: miaFM, theirs: fueraFM2) == .conflict)
        // Los dos cambiaron la misma sección: conflicto.
        let fueraDesc = Self.base.replacingOccurrences(of: "A\n", with: "A de fuera\n")
        #expect(EditorMerge.merge(base: Self.base, mine: mia, theirs: fueraDesc) == .conflict)
        // Fuera cambió otra sección del cuerpo (no la Actividad) mientras yo editaba: aviso.
        let base3 = "## Descripción\nA\n\n## Notas\nN\n\n## Actividad\n### e1\nuno\n"
        let mia3 = base3.replacingOccurrences(of: "A\n", with: "A mía\n")
        let fuera3 = base3.replacingOccurrences(of: "N\n", with: "N de Obsidian\n")
        #expect(EditorMerge.merge(base: base3, mine: mia3, theirs: fuera3) == .conflict)
        // Si yo solo cambié propiedades, el cuerpo de fuera se queda (no se pierde nada).
        let fueraOtra = Self.base.replacingOccurrences(of: "## Actividad", with: "Párrafo de Obsidian.\n\n## Actividad")
        #expect(EditorMerge.merge(base: Self.base, mine: miaFM, theirs: fueraOtra)
                == .merged(fueraOtra.replacingOccurrences(of: "vence: 2026-10-30", with: "vence: 2026-11-02")))
        // Fuera reescribió la Actividad (no solo añadió): aviso.
        let fueraReescribe = Self.base.replacingOccurrences(of: "uno\n", with: "uno corregido\n")
        #expect(EditorMerge.merge(base: Self.base, mine: mia, theirs: fueraReescribe) == .conflict)
        // Propiedad nueva mía y propiedad cambiada fuera: las dos.
        let miaNueva = Self.base.replacingOccurrences(of: "vence: 2026-10-30\n", with: "vence: 2026-10-30\nprioridad: Alta\n")
        #expect(EditorMerge.merge(base: Self.base, mine: miaNueva, theirs: fueraFM)
                == .merged("---\nestado: En curso\nvence: 2026-10-30\nprioridad: Alta\n---\n## Descripción\nA\n\n## Actividad\n### e1\nuno\n"))
    }
}
