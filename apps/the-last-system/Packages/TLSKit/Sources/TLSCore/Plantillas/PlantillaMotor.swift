import Foundation

/// Crea notas desde plantillas (PLANTILLAS.md §1): rellena las variables, pone el nombre estándar
/// del fichero y del título, elige la carpeta según desde qué ficha se crea y deja la nota ya
/// enlazada a su contexto. Nunca escribe: devuelve el plan (crear + contador) para el `CommandBus`.
///
/// Reglas de §1.2 y §1.3:
/// - una propiedad cuya variable no tiene valor no se escribe, y las vacías tampoco;
/// - en el texto, lo que falta se escribe `[falta: variable]` (nunca se inventa);
/// - en la línea de resumen (`> … · …` bajo el título) el tramo sin dato desaparece con su separador;
/// - los comentarios `# …` de las propiedades no se copian; las guías sí (salvo que se apague);
/// - `{{emisor.*}}` nunca se escribe en una nota.
public struct PlantillaMotor: Sendable {
    public struct Opciones: Sendable {
        /// Quién crea (`{{yo}}`).
        public var yo: String
        /// Copiar las líneas `> Guía: …` al crear.
        public var copiarGuias: Bool
        /// Reloj (si no, el de la carpeta: en la demo, su día fijo).
        public var reloj: Reloj?

        public init(yo: String = "Manu", copiarGuias: Bool = true, reloj: Reloj? = nil) {
            self.yo = yo; self.copiarGuias = copiarGuias; self.reloj = reloj
        }
    }

    /// Qué crear.
    public struct Peticion: Sendable {
        /// Identificador de la plantilla (`tarea`, `reunion-de-descubrimiento`…).
        public var plantilla: String
        /// Ficha desde la que se pulsa «Nueva…» (su papel y sus relaciones van al contexto).
        public var desde: VaultPath?
        /// Otras fichas por papel (`servicio` → ruta).
        public var contexto: [String: VaultPath]
        /// Respuestas a las preguntas y valores sueltos (`titulo`, `fecha`, `responsable`…).
        public var valores: [String: String]
        /// Filas que se repiten (`linea` → conceptos de una factura).
        public var listas: [String: [[String: String]]]
        /// Propiedades que se fijan después de rellenar (`.empty` quita la clave).
        public var poner: [Property]
        /// Texto de secciones: sustituye su contenido (la guía).
        public var secciones: [String: String]
        public var area: AreaCode?
        /// Carpeta a la fuerza (si no, la de la plantilla).
        public var carpeta: VaultPath?
        public var autor: Autor

        public init(plantilla: String, desde: VaultPath? = nil, contexto: [String: VaultPath] = [:],
                    valores: [String: String] = [:], listas: [String: [[String: String]]] = [:], poner: [Property] = [],
                    secciones: [String: String] = [:], area: AreaCode? = nil, carpeta: VaultPath? = nil,
                    autor: Autor = .persona("Manu")) {
            self.plantilla = plantilla; self.desde = desde; self.contexto = contexto; self.valores = valores
            self.listas = listas; self.poner = poner; self.secciones = secciones; self.area = area
            self.carpeta = carpeta; self.autor = autor
        }
    }

    /// La nota lista para crear.
    public struct NotaPreparada: Sendable {
        public let ruta: VaultPath
        public let texto: String
        public let titulo: String
        /// Número de su serie (`T-0042`), si lo lleva.
        public let numero: String?
        /// Variables sin valor que quedaron como `[falta: …]` en el texto.
        public let faltan: [String]
        /// Dónde queda el cursor (bytes UTF-8), si la plantilla lo marca con `{{cursor}}`.
        public let cursor: Int?
        /// Crear la nota y, si toca, el contador de `.tls/secuencias.json`. Todo o nada.
        public let plan: WritePlan
    }

    public let snapshot: VaultSnapshot
    public let registro: PlantillaRegistro
    public let opciones: Opciones
    public let reloj: Reloj

    public init(snapshot: VaultSnapshot, registro: PlantillaRegistro? = nil, opciones: Opciones = Opciones()) {
        self.snapshot = snapshot
        self.registro = registro ?? PlantillaRegistro.cargar(snapshot)
        self.opciones = opciones
        self.reloj = opciones.reloj ?? Reloj.deCarpeta(snapshot)
    }

    static let cursorMark = "\u{FFFC}"

    // MARK: Crear

    public func preparar(_ p: Peticion) throws -> NotaPreparada {
        guard let def = registro[p.plantilla] else { throw PlantillaError.noExiste(p.plantilla) }
        guard !def.esFragmento else { throw PlantillaError.esFragmento(def.id) }
        let ctx = ContextoPlantilla.construir(desde: p.desde, extra: p.contexto, snapshot: snapshot)
        let fuente = try textoDePlantilla(def, ctx: ctx)
        var env = Entorno(motor: self, ctx: ctx, valores: p.valores, listas: p.listas)
        env.area = p.area ?? areaDeContexto(p, ctx: ctx) ?? def.area ?? .direccion
        var numero: String?
        var secuencia: [String: Int] = [:]
        if let serie = def.serie {
            if let dado = p.valores["numero"] { numero = dado } else {
                let n = Secuencias.siguiente(serie, año: reloj.hoy.year, en: snapshot)
                numero = Secuencias.formatear(serie, n, año: reloj.hoy.year)
                secuencia[Secuencias.clave(serie, año: reloj.hoy.year)] = n
            }
        }
        env.builtins["numero"] = numero
        // Título: el que se escribe o el patrón de la plantilla; el nombre del fichero sale de él.
        var titulo = p.valores["titulo"]
        if titulo == nil, let patron = def.titulo { titulo = env.expandirOpcional(patron) }
        env.builtins["titulo"] = titulo
        env.builtins["slug"] = p.valores["slug"] ?? titulo.map { NombresDeFicha.slug($0) }
        // Carpeta.
        let carpeta = try carpetaDestino(def, p: p, ctx: ctx, env: &env)
        // Orden entre las de su tipo en esa carpeta (`Seguimiento 2`, `Propuesta v2`).
        var orden = ordenEn(carpeta, tipo: def.tipo, tipoLiteral: tipoLiteral(fuente))
        // Si el nombre lleva la versión (`renta-v{{version}}`, `Propuesta v{{orden}}`): la mayor que ya hay con
        // ese mismo nombre en la carpeta, más uno (no cuenta las de otro servicio ni otros activos). Solo con
        // «v» delante: en `{{fecha}}-seguimiento-{{orden}}` el orden es entre todas las del cliente (PLANTILLAS §1.3).
        if let patron = def.nombre, let marca = ["{{orden}}", "{{version}}"].first(where: { patron.contains($0) }) {
            let partes = patron.components(separatedBy: marca)
            if partes.count == 2, partes[0].lowercased().hasSuffix("v"),
               let antes = try? env.expandirEstricto(partes[0]), let despues = try? env.expandirEstricto(partes[1]) {
                let re = "^" + NSRegularExpression.escapedPattern(for: NombresDeFicha.fichero(antes)) + "(\\d+)"
                    + NSRegularExpression.escapedPattern(for: despues) + "$"
                let clave = TextFolding.pathKey(carpeta.raw)
                let mayor = snapshot.files.filter { $0.ext == "md" && TextFolding.pathKey(($0.parent ?? .root).raw) == clave }
                    .compactMap { Secuencias.captura($0.stem, re) }.max() ?? 0
                orden = mayor + 1
            }
        }
        env.builtins["orden"] = String(orden)
        env.builtins["version"] = p.valores["version"] ?? String(orden)
        if p.valores["titulo"] == nil, let patron = def.titulo, patron.contains("orden") || titulo == nil {
            titulo = env.expandirOpcional(patron)
            env.builtins["titulo"] = titulo
            if p.valores["slug"] == nil { env.builtins["slug"] = titulo.map { NombresDeFicha.slug($0) } }
        }
        // Nombre del fichero.
        let patronNombre = def.nombre ?? "{{slug}}"
        var nombre = NombresDeFicha.fichero(try env.expandirEstricto(patronNombre))
        // §1.7: como mucho 60 caracteres; se recorta el slug (`t-0042-…`), como en `TaskStore`.
        if nombre.count > 60, patronNombre.contains("{{slug}}"), let slug = env.builtins["slug"], slug.count > nombre.count - 60 {
            env.builtins["slug"] = NombresDeFicha.recortar(slug, maximo: slug.count - (nombre.count - 60))
            nombre = NombresDeFicha.fichero(try env.expandirEstricto(patronNombre))
        }
        guard !nombre.isEmpty else { throw PlantillaError.faltaDato("titulo") }
        var ruta = carpeta.appending(nombre + ".md")
        if snapshot.existing(ruta) != nil {
            // Nombre fijo (Área, Empresa, Metas, Marca, el plan de un servicio…): no se crea otra; se completa
            // la que hay con `aplicar` (SISTEMAS §5.6).
            guard patronNombre.contains("{{slug}}"), let slug = env.builtins["slug"] else { throw PlantillaError.yaExiste(ruta.raw) }
            // Con slug, el siguiente libre en kebab (`lucia-ferrer-2`), nunca «lucia-ferrer (2)».
            var n = 2
            repeat {
                env.builtins["slug"] = "\(slug)-\(n)"
                ruta = carpeta.appending(NombresDeFicha.fichero(try env.expandirEstricto(patronNombre)) + ".md")
                n += 1
            } while snapshot.existing(ruta) != nil
        }
        env.destino = ruta
        // Texto.
        var faltan: [String] = []
        var texto = try renderizar(fuente, def: def, p: p, env: &env, faltan: &faltan)
        var cursor: Int?
        if let r = texto.range(of: Self.cursorMark) {
            cursor = texto.utf8.distance(from: texto.startIndex, to: r.lowerBound)
            texto.removeSubrange(r)
        }
        let doc = NoteDocument(text: texto)
        let tituloFinal = doc.title(fileStem: ruta.stem)
        // Si el nombre ya lo lleva otra nota, los enlaces que había siguen yendo a la suya.
        var ops: [WriteOp] = LinkRefactor(snapshot: snapshot).protegerEnlaces(alCrear: [ruta], opciones: .init(autor: p.autor))
        ops.append(.create(ruta, text: texto))
        if let op = Secuencias.op(secuencia, en: snapshot) { ops.append(op) }
        let plan = WritePlan(autor: p.autor, descripcion: "Crear «\(tituloFinal)»", ops: ops)
        var seen = Set<String>()
        return NotaPreparada(ruta: ruta, texto: texto, titulo: tituloFinal, numero: numero,
                             faltan: faltan.filter { seen.insert($0).inserted }, cursor: cursor, plan: plan)
    }

    /// Texto de la plantilla: la variante del servicio (si la plantilla la usa), la instalada en
    /// la carpeta o, si no está, la original de la app.
    func textoDePlantilla(_ def: PlantillaDef, ctx: ContextoPlantilla) throws -> String {
        if def.variantePor == "servicio", let s = ctx["servicio"], let v = s.valor("descubrimiento"),
           let destino = ContextoPlantilla.resolve(v, from: s.ruta, resolver: snapshot.resolver, ids: { _ in nil }),
           let t = snapshot.text(destino) {
            return t
        }
        if let instalada = snapshot.existing(snapshot.layout.expand(def.fichero)), let t = snapshot.text(instalada) {
            return t
        }
        if let origen = def.origen, let t = PlantillasDeSerie.texto(origen) { return t }
        throw PlantillaError.sinTexto(def.fichero)
    }

    func areaDeContexto(_ p: Peticion, ctx: ContextoPlantilla) -> AreaCode? {
        if let d = p.desde, let a = snapshot.layout.area(of: d) { return a }
        if let a = p.valores["area"].flatMap({ v in AreaCode.allCases.first { $0.layoutKey == v || $0.nombre == v } }) { return a }
        return nil
    }

    func carpetaDestino(_ def: PlantillaDef, p: Peticion, ctx: ContextoPlantilla, env: inout Entorno) throws -> VaultPath {
        if let c = p.carpeta { return c }
        var patron = def.carpeta ?? "{area}"
        if let segun = def.carpetaSi.first(where: { ctx[$0.rol] != nil }) { patron = segun.carpeta }
        let area = snapshot.layout.areaFolder(env.area ?? .direccion).raw
        patron = patron.replacingOccurrences(of: "{area}", with: area)
        let expandido = try env.expandirEstricto(patron)
        return snapshot.layout.expand(expandido)
    }

    /// `tipo:` escrito tal cual en la plantilla (`seguimiento`), para contar el orden.
    func tipoLiteral(_ fuente: String) -> String? {
        let doc = FrontmatterDocument(text: fuente)
        guard case .text(let t)? = doc.value("tipo"), !t.contains("{{") else { return nil }
        return t
    }

    func ordenEn(_ carpeta: VaultPath, tipo: String, tipoLiteral: String?) -> Int {
        var n = 0
        let key = TextFolding.pathKey(carpeta.raw)
        for f in snapshot.files where f.ext == "md" && TextFolding.pathKey((f.parent ?? .root).raw) == key {
            let fm = snapshot.frontmatter(f)
            guard fm.text("tls_type") == tipo else { continue }
            if let t = tipoLiteral, fm.text("tipo") != t { continue }
            n += 1
        }
        return n + 1
    }

    // MARK: Texto

    func renderizar(_ fuente: String, def: PlantillaDef, p: Peticion, env: inout Entorno, faltan: inout [String]) throws -> String {
        let plantilla = FrontmatterDocument(text: fuente)
        env.clavesPropias = Set(plantilla.keys)
        var lineas: [String] = []
        for key in plantilla.keys {
            if let l = renderPropiedad(plantilla, key: key, env: env) { lineas.append(l) }
        }
        var texto = lineas.isEmpty ? "" : "---\n" + lineas.joined(separator: "\n") + "\n---\n"
        // Relación con la ficha desde la que se crea, si la plantilla la tiene y quedó vacía.
        var doc = FrontmatterDocument(text: texto + "x")
        if let rol = env.ctx.origen, let n = env.ctx[rol] {
            let enlace = NombresDeFicha.wikilink(n.ruta, nombre: n.nombre, en: snapshot)
            if plantilla.keys.contains(rol), doc.value(rol) == nil { doc.set(rol, .text(enlace)) }
            if rol == "contacto", plantilla.keys.contains("personas"), doc.value("personas") == nil {
                doc.set("personas", .list([enlace]))
            }
        }
        for prop in p.poner {
            if prop.value == .empty { doc.unset(prop.key) } else { doc.set(prop.key, prop.value) }
        }
        texto = doc.hasFrontmatter ? doc.frontmatterBlock : ""
        // Propiedades propias: las usan las variables del cuerpo (`{{estado}}`, `{{vence:corta}}`).
        for prop in doc.frontmatter.properties {
            let v = prop.value.displayText
            if !v.isEmpty { env.propias[prop.key] = prop.value == .bool(true) ? "true" : (prop.value == .bool(false) ? "false" : v) }
        }
        var cuerpo = renderCuerpo(plantilla.body, env: env, faltan: &faltan)
        for (seccion, contenido) in p.secciones.sorted(by: { $0.key < $1.key }) {
            if let hash = MarkdownSections.hash(of: seccion, in: cuerpo) {
                cuerpo = try MarkdownSections.replace(seccion, in: cuerpo, with: contenido, baseHash: hash, eol: "\n")
            } else {
                cuerpo = try MarkdownSections.append(to: seccion, in: cuerpo, text: contenido, blankLine: false, create: true, eol: "\n")
            }
        }
        return texto + cuerpo
    }

    /// Línea de una propiedad ya rellena, o `nil` si queda vacía (no se escribe).
    func renderPropiedad(_ plantilla: FrontmatterDocument, key: String, env: Entorno) -> String? {
        guard let raw = plantilla.rawLines(key) else { return nil }
        let lines = TextLines.split(raw)
        guard let head = lines.first, let kl = FrontmatterDocument.parseKeyLine(head.content) else { return nil }
        if lines.count > 1 {
            // Valor anidado (p. ej. `formato_extracto`): se conserva, sin comentarios.
            var out = [kl.keyPart]
            for l in lines.dropFirst() {
                var c = l.content
                if let r = c.range(of: #"\s+#\s.*$"#, options: .regularExpression) { c.removeSubrange(r) }
                if c.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
                var miss: [String] = []
                out.append(env.sustituir(c, modo: .propiedad, faltan: &miss))
            }
            return out.joined(separator: "\n")
        }
        let v = kl.value
        // Una respuesta a la pregunta de esa propiedad (`hora`, `fecha`…) manda sobre lo escrito en la plantilla.
        if !v.contains("{{"), let dada = env.valores[key], !dada.trimmingCharacters(in: .whitespaces).isEmpty {
            return kl.keyPart + " " + Self.escalar(dada)
        }
        if v.isEmpty || v == "[]" || v == "\"\"" || v == "''" { return nil }
        guard v.contains("{{") else { return kl.keyPart + " " + v }
        switch FrontmatterReader.read("v: " + v).properties.first?.value {
        case .text(let s)?:
            var miss: [String] = []
            let r = env.sustituir(s, modo: .propiedad, faltan: &miss).trimmingCharacters(in: .whitespaces)
            if !miss.isEmpty || r.isEmpty { return nil }
            return kl.keyPart + " " + Self.escalar(r)
        case .list(let items)?:
            let rendered = items.compactMap { item -> String? in
                var miss: [String] = []
                let r = env.sustituir(item, modo: .propiedad, faltan: &miss).trimmingCharacters(in: .whitespaces)
                return miss.isEmpty && !r.isEmpty ? r : nil
            }
            return rendered.isEmpty ? nil : kl.keyPart + " " + YAMLScalar.flowList(rendered)
        default:
            return kl.keyPart + " " + v
        }
    }

    /// Escalar YAML: números, sí/no y fechas sin comillas; enlaces y textos raros entre comillas.
    static func escalar(_ s: String) -> String {
        if FrontmatterReader.isNumber(s) || s == "true" || s == "false" { return s }
        return YAMLScalar.render(text: s)
    }

    static let listasConocidas = ["linea", "pago", "fase", "sesion"]

    func renderCuerpo(_ body: String, env: Entorno, faltan: inout [String]) -> String {
        let lines = TextLines.split(body)
        var out = ""
        var sawH1 = false
        var summaryChecked = false
        var env = env
        for line in lines {
            let c = line.content
            if !opciones.copiarGuias, c.hasPrefix("> Guía:") { continue }
            // Línea de resumen: la primera bajo el título, `> a · b · c`.
            if sawH1, !summaryChecked {
                summaryChecked = true
                if c.hasPrefix("> "), !c.hasPrefix("> Guía:") {
                    // Un tramo sin dato desaparece con su separador. Si el tramo son solo variables
                    // («{{fecha:corta}} {{hora}}»), se queda con las que tienen valor.
                    let tramos = c.dropFirst(2).components(separatedBy: " · ").compactMap { tramo -> String? in
                        var miss: [String] = []
                        let r = env.sustituir(tramo, modo: .texto, faltan: &miss, marcarFaltas: false)
                        if miss.isEmpty { return r.trimmingCharacters(in: .whitespaces).isEmpty ? nil : r }
                        let soloVariables = Entorno.patron.stringByReplacingMatches(
                            in: tramo, range: NSRange(tramo.startIndex..., in: tramo), withTemplate: "")
                            .trimmingCharacters(in: .whitespaces).isEmpty
                        guard soloVariables else { return nil }
                        let compacto = r.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
                        return compacto.isEmpty ? nil : compacto
                    }
                    if !tramos.isEmpty { out += "> " + tramos.joined(separator: " · ") + line.eol }
                    continue
                }
            }
            if c.hasPrefix("# ") { sawH1 = true }
            // Filas que se repiten (`| {{linea.concepto}} | …`).
            if c.hasPrefix("|"), let lista = (Array(env.listas.keys) + Self.listasConocidas).first(where: { c.contains("{{\($0).") }) {
                let items = env.listas[lista] ?? []
                if items.isEmpty {
                    out += env.sustituir(c, modo: .texto, faltan: &faltan) + line.eol
                } else {
                    for item in items {
                        env.item = (lista, item)
                        out += env.sustituir(c, modo: .texto, faltan: &faltan) + line.eol
                    }
                    env.item = nil
                }
                continue
            }
            out += env.sustituir(c, modo: .texto, faltan: &faltan) + line.eol
        }
        return out
    }

    // MARK: Aplicar a una nota que ya existe

    /// «Aplicar plantilla»: añade a una nota las propiedades y secciones que le faltan. Nunca pisa nada.
    /// `nil` si no falta nada.
    public func aplicar(_ id: String, a nota: VaultPath, autor: Autor = .persona("Manu")) throws -> WritePlan? {
        guard let def = registro[id] else { throw PlantillaError.noExiste(id) }
        guard let text = snapshot.text(nota) else { throw PlantillaError.sinTexto(nota.raw) }
        let ctx = ContextoPlantilla.construir(desde: nota, snapshot: snapshot)
        let fuente = try textoDePlantilla(def, ctx: ctx)
        var env = Entorno(motor: self, ctx: ctx, valores: [:], listas: [:])
        env.area = snapshot.layout.area(of: nota) ?? def.area
        env.destino = nota
        let actual = FrontmatterDocument(text: text)
        let fm = actual.frontmatter
        for prop in fm.properties { env.propias[prop.key] = prop.value.displayText }
        env.builtins["titulo"] = fm.text("titulo") ?? fm.text("nombre") ?? NoteDocument(text: text).title(fileStem: nota.stem)
        env.builtins["slug"] = nota.stem
        let plantilla = FrontmatterDocument(text: fuente)
        var poner: [Property] = []
        for key in plantilla.keys where actual.value(key) == nil && key != "id" {
            guard let linea = renderPropiedad(plantilla, key: key, env: env),
                  let prop = FrontmatterReader.read(linea).properties.first, prop.value != .empty else { continue }
            poner.append(prop)
        }
        if actual.value("id") == nil { poner.append(Property(key: "id", value: .text(UUID().uuidString.lowercased()))) }
        var ops: [WriteOp] = []
        if !poner.isEmpty { ops.append(.mergeFrontmatter(nota, set: poner, unset: [])) }
        var faltan: [String] = []
        let cuerpo = renderCuerpo(plantilla.body, env: env, faltan: &faltan)
        let existentes = Set(MarkdownSections.titles(in: actual.body).map(TextFolding.fold))
        let lineas = TextLines.split(cuerpo)
        for s in MarkdownSections.sections(lineas) where s.level == 2 && !existentes.contains(TextFolding.fold(s.title)) {
            let contenido = s.lastContentLine.map { TextLines.join(Array(lineas[s.contentLines.lowerBound...$0])) } ?? ""
            ops.append(.appendToSection(nota, section: s.title, text: contenido.isEmpty ? "" : contenido, blankLine: true))
        }
        guard !ops.isEmpty else { return nil }
        return WritePlan(autor: autor, descripcion: "Aplicar la plantilla «\(def.id)» a «\(nota.stem)»", ops: ops)
    }

    /// Mete un fragmento (una sección) en una nota, si no la tiene ya. `nil` si ya estaba.
    public func insertarFragmento(_ id: String, en nota: VaultPath, valores: [String: String] = [:],
                                  autor: Autor = .persona("Manu")) throws -> WritePlan? {
        guard let def = registro[id] else { throw PlantillaError.noExiste(id) }
        guard def.esFragmento else { throw PlantillaError.noEsFragmento(id) }
        guard def.forma == "seccion" else { throw PlantillaError.noDisponible(id) }
        guard let text = snapshot.text(nota) else { throw PlantillaError.sinTexto(nota.raw) }
        let ctx = ContextoPlantilla.construir(desde: nota, snapshot: snapshot)
        var env = Entorno(motor: self, ctx: ctx, valores: valores, listas: [:])
        env.destino = nota
        var faltan: [String] = []
        let cuerpo = renderCuerpo(FrontmatterDocument(text: try textoDePlantilla(def, ctx: ctx)).body, env: env, faltan: &faltan)
        let lineas = TextLines.split(cuerpo)
        guard let s = MarkdownSections.sections(lineas).first else { return nil }
        let existentes = Set(MarkdownSections.titles(in: FrontmatterDocument(text: text).body).map(TextFolding.fold))
        guard !existentes.contains(TextFolding.fold(s.title)) else { return nil }
        let contenido = s.lastContentLine.map { TextLines.join(Array(lineas[s.contentLines.lowerBound...$0])) } ?? ""
        return WritePlan(autor: autor, descripcion: "Añadir «\(s.title)» a «\(nota.stem)»",
                         ops: [.appendToSection(nota, section: s.title, text: contenido, blankLine: true)])
    }

    // MARK: Notas creadas fuera (Obsidian)

    /// Variables que quedaron sin sustituir en una nota (`{{id}}`, `{{numero}}`…), sin las del emisor.
    public func variablesSinRellenar(_ nota: VaultPath) -> [String] {
        guard let text = snapshot.text(nota) else { return [] }
        var out: [String] = []
        for m in Entorno.patron.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let name = String(text[r]).trimmingCharacters(in: .whitespaces)
            if !name.hasPrefix("emisor."), !out.contains(name) { out.append(name) }
        }
        return out
    }

    /// Rellena en las propiedades `{{id}}`, `{{fecha}}`, `{{hora}}` y, en una tarea, `{{numero}}`.
    public func rellenarPendientes(_ nota: VaultPath, autor: Autor = .persona("Manu")) -> WritePlan? {
        guard let text = snapshot.text(nota) else { return nil }
        let doc = FrontmatterDocument(text: text)
        var poner: [Property] = []
        var secuencia: [String: Int] = [:]
        for key in doc.keys {
            guard case .text(let v)? = doc.value(key) else { continue }
            switch v.trimmingCharacters(in: .whitespaces) {
            case "{{id}}": poner.append(Property(key: key, value: .text(UUID().uuidString.lowercased())))
            case "{{fecha}}", "{{date}}": poner.append(Property(key: key, value: .text(reloj.hoy.description)))
            case "{{hora}}", "{{time}}": poner.append(Property(key: key, value: .text(reloj.hora)))
            case "{{numero}}" where doc.value("tls_type") == .text("task"):
                let n = Secuencias.siguiente("tarea", año: reloj.hoy.year, en: snapshot)
                poner.append(Property(key: key, value: .text(Secuencias.formatear("tarea", n, año: reloj.hoy.year))))
                secuencia["tarea"] = n
            default: continue
            }
        }
        guard !poner.isEmpty else { return nil }
        var ops: [WriteOp] = [.mergeFrontmatter(nota, set: poner, unset: [])]
        if let op = Secuencias.op(secuencia, en: snapshot) { ops.append(op) }
        return WritePlan(autor: autor, descripcion: "Rellenar «\(nota.stem)»", ops: ops)
    }
}

/// Valores para sustituir las variables de una plantilla.
struct Entorno {
    enum Modo { case propiedad, texto, nombre }

    static let patron = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
    static let calculoDeFecha = try! NSRegularExpression(pattern: #"^(fecha|hoy|date)\s*([+-])\s*(\d+)\s*(l?)$"#)

    let motor: PlantillaMotor
    let ctx: ContextoPlantilla
    var valores: [String: String]
    var listas: [String: [[String: String]]]
    var builtins: [String: String] = [:]
    var propias: [String: String] = [:]
    var item: (String, [String: String])?
    /// Claves de las propiedades de la plantilla: en el cuerpo, `{{clave}}` es esa propiedad.
    var clavesPropias: Set<String> = []
    var area: AreaCode?
    var destino: VaultPath?

    init(motor: PlantillaMotor, ctx: ContextoPlantilla, valores: [String: String], listas: [String: [[String: String]]]) {
        self.motor = motor; self.ctx = ctx; self.valores = valores; self.listas = listas
        let r = motor.reloj
        builtins["id"] = UUID().uuidString.lowercased()
        builtins["fecha"] = r.hoy.description
        builtins["hoy"] = r.hoy.description
        builtins["date"] = r.hoy.description
        builtins["hora"] = r.hora
        builtins["time"] = r.hora
        builtins["yo"] = motor.opciones.yo
        builtins["yo.nombre"] = motor.opciones.yo
        builtins["semana"] = FormatosPlantilla.semana(r.hoy)
        builtins["mes"] = FormatosPlantilla.mes(r.hoy)
        builtins["trimestre"] = FormatosPlantilla.trimestre(r.hoy)
        builtins["año"] = String(r.hoy.year)
    }

    /// Sustituye las variables. En una propiedad lo que falta se apunta y se deja vacío; en el texto,
    /// `[falta: x]` (salvo `marcarFaltas: false`).
    func sustituir(_ s: String, modo: Modo, faltan: inout [String], marcarFaltas: Bool = true) -> String {
        guard s.contains("{{") else { return s }
        var out = ""
        var last = s.startIndex
        for m in Self.patron.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s), let inner = Range(m.range(at: 1), in: s) else { continue }
            out += s[last..<whole.lowerBound]
            last = whole.upperBound
            let expr = String(s[inner])
            var name = expr
            var formato: String?
            if let colon = expr.firstIndex(of: ":") {
                name = String(expr[..<colon]).trimmingCharacters(in: .whitespaces)
                formato = String(expr[expr.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            if name == "cursor" { if modo == .texto { out += PlantillaMotor.cursorMark }; continue }
            if name.hasPrefix("emisor.") { out += s[whole]; continue }
            if var v = valor(name, modo: modo) {
                if let f = formato { v = FormatosPlantilla.aplicar(v, formato: f) }
                out += v
            } else {
                faltan.append(name)
                if modo == .texto, marcarFaltas { out += "[falta: \(name)]" }
            }
        }
        out += s[last...]
        return out
    }

    /// Expande un patrón (nombre o carpeta): si falta algo, lanza (nunca se inventa un nombre).
    func expandirEstricto(_ patron: String) throws -> String {
        var faltan: [String] = []
        let r = sustituir(patron, modo: .nombre, faltan: &faltan)
        if let f = faltan.first { throw PlantillaError.faltaDato(f) }
        return r
    }

    func expandirOpcional(_ patron: String) -> String? {
        var faltan: [String] = []
        let r = sustituir(patron, modo: .nombre, faltan: &faltan)
        return faltan.isEmpty && !r.isEmpty ? r : nil
    }

    /// Valor de una variable, o `nil` si no lo hay (o está vacío).
    func valor(_ name: String, modo: Modo) -> String? {
        func noVacio(_ s: String?) -> String? {
            guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        // `{{fecha+14}}`, `{{fecha+5l}}`, `{{hoy-2}}`.
        if let m = Self.calculoDeFecha.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
           let sign = Range(m.range(at: 2), in: name), let num = Range(m.range(at: 3), in: name),
           let lab = Range(m.range(at: 4), in: name), let n = Int(name[num]) {
            let base = LocalDate(parsing: valores["fecha"] ?? "") ?? motor.reloj.hoy
            let k = name[sign] == "-" ? -n : n
            return (name[lab] == "l" ? FormatosPlantilla.sumarLaborables(base, k) : base.adding(days: k)).description
        }
        if let v = noVacio(valores[name]) { return v }
        if let it = item, name.hasPrefix(it.0 + ".") {
            return noVacio(it.1[String(name.dropFirst(it.0.count + 1))])
        }
        if modo == .texto, let v = noVacio(propias[name]) { return v }
        // Propiedad de la plantilla que quedó vacía (`hora` de una reunión): no hay valor, aunque
        // exista una variable general con ese nombre.
        if modo == .texto, clavesPropias.contains(name) { return nil }
        switch name {
        case "area": return area?.layoutKey
        case "area.nombre": return area.map { motor.snapshot.layout.areaFolder($0).raw }
        case "title": return noVacio(builtins["titulo"])
        default: break
        }
        if let v = noVacio(builtins[name]) { return v }
        guard let dot = name.firstIndex(of: ".") else {
            return ctx[name].map(\.nombre)
        }
        let rol = String(name[..<dot])
        let attr = String(name[name.index(after: dot)...])
        guard let nota = notaDe(rol) else { return nil }
        switch attr {
        case "enlace":
            if modo == .propiedad || modo == .nombre { return NombresDeFicha.wikilink(nota.ruta, nombre: nota.nombre, en: motor.snapshot) }
            guard let d = destino else { return NombresDeFicha.wikilink(nota.ruta, nombre: nota.nombre, en: motor.snapshot) }
            return NombresDeFicha.enlaceMarkdown(nota.nombre, desde: d, a: nota.ruta)
        case "nombre", "titulo": return nota.nombre
        case "slug": return nota.slug
        case "carpeta": return nota.carpeta.raw
        case "ruta": return nota.ruta.raw
        case "color" where rol == "marca": return noVacio(nota.valor("color_principal"))
        default: return noVacio(nota.valor(attr))
        }
    }

    /// Ficha de un papel: las del contexto, tu empresa (`Empresa.md`) y el manual de marca.
    func notaDe(_ rol: String) -> NotaDeContexto? {
        if let n = ctx[rol] { return n }
        let snap = motor.snapshot
        switch rol {
        case "mi_empresa":
            return ContextoPlantilla.nota(VaultPath("Empresa.md"), snapshot: snap)
        case "marca":
            return ContextoPlantilla.nota(snap.layout.areaFolder(.marca).appending("Marca.md"), snapshot: snap)
        default:
            return nil
        }
    }
}
