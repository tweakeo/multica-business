import CryptoKit
import Foundation
import PDFKit
import TLSCore

/// Un fichero (o un paquete como `.numbers`) de una fuente.
public struct ElementoInventario: Sendable, Codable, Hashable, Identifiable {
    /// `alias/ruta`: única entre todas las fuentes.
    public let clave: String
    public var id: String { clave }
    /// Alias de su fuente.
    public let fuente: String
    /// Ruta relativa a la raíz de su fuente (NFC).
    public let ruta: VaultPath
    /// Paquete (`.numbers`, `.app`…): una carpeta que macOS trata como un solo documento. Se mueve entero.
    public let esPaquete: Bool
    public let tipo: TipoDocumento
    public let tamano: Int64?
    /// SHA-256 (del contenido; en un paquete, de sus ficheros). `nil` si solo está en iCloud o es sensible.
    public let sha256: String?
    /// Solo en iCloud: no se ha leído; se clasifica por su nombre.
    public let soloEnICloud: Bool
    /// Claves o contraseñas (por el nombre): nunca se lee ni se mueve ni se envía a nadie.
    public let sensible: Bool
    public let modificado: Date?
    /// Primera carpeta dentro de la fuente («» si está suelto en la raíz).
    public let bloque: String
    public internal(set) var herramienta: HerramientaOrigen
    /// Principio del texto (solo de lo que ya está en el Mac y se puede leer sin programas externos, y de los PDF).
    public let extracto: String?
    /// Propiedades sencillas de una nota (`tls_type`, `tipo`, `id`…), en minúsculas.
    public let propiedades: [String: String]
    /// Las propiedades se pudieron leer (una nota con propiedades rotas no se adopta).
    public let propiedadesLegibles: Bool
    /// Fecha que lleva el nombre (`AAAA-MM-DD` o `AAAA-MM`).
    public let fechaEnNombre: String?

    /// Nombre sin el identificador que añade Notion al exportar («Reunión 1a2b…» → «Reunión»).
    public var nombreLimpio: String { InventarioImportacion.sinIdNotion(ruta.name) }
    public var bloqueVisible: String { bloque.isEmpty ? "Sueltos" : InventarioImportacion.sinIdNotion(bloque) }
}

/// Ficheros, bytes y los que están solo en iCloud.
public struct Recuento: Sendable, Hashable, Codable {
    public var ficheros = 0
    public var bytes: Int64 = 0
    public var soloEnICloud = 0
    public init() {}
}

/// Inventario de las fuentes de una importación (paso 2), sin descargar nada de iCloud y sin listar lo privado.
public struct InventarioImportacion: Sendable {
    public struct Opciones: Sendable {
        /// Leer el principio del texto de lo que ya está en el Mac (notas, textos, PDF) para buscar pistas.
        public var leerExtractos: Bool
        public var maxExtracto: Int
        /// Los PDF más grandes no se abren para el extracto.
        public var maxBytesPDF: Int64
        /// Día de hoy (para las fechas del nombre).
        public var hoy: LocalDate

        public init(leerExtractos: Bool = true, maxExtracto: Int = 2_000, maxBytesPDF: Int64 = 20 << 20, hoy: LocalDate) {
            self.leerExtractos = leerExtractos; self.maxExtracto = maxExtracto; self.maxBytesPDF = maxBytesPDF; self.hoy = hoy
        }
    }

    public let fuentes: [FuenteImportacion]
    /// Ordenados por clave.
    public let elementos: [ElementoInventario]
    /// Carpetas (no paquetes) de cada fuente, por alias.
    public let carpetas: [String: [VaultPath]]
    /// Rutas que no se miraron (privadas, excluidas, ocultas): solo el número.
    public let podadas: Int
    /// Herramienta de cada bloque (`alias/bloque`).
    public let herramientas: [String: HerramientaOrigen]

    public var porHerramienta: [HerramientaOrigen: Recuento] { Self.recuento(elementos, por: \.herramienta) }
    public var porTipo: [TipoDocumento: Recuento] { Self.recuento(elementos, por: \.tipo) }
    public var soloEnICloud: Int { elementos.filter(\.soloEnICloud).count }

    /// «312 ficheros · 310 solo en iCloud: los miro por su nombre».
    public var resumen: String {
        var s = Plural.de(elementos.count, "fichero", "ficheros")
        let n = soloEnICloud
        if n > 0 { s += " · \(n) solo en iCloud: los miro por su nombre" }
        return s
    }

    public func fuente(_ alias: String) -> FuenteImportacion? { fuentes.first { $0.alias == alias } }
    public func elemento(_ clave: String) -> ElementoInventario? { porClave[clave] }
    let porClave: [String: ElementoInventario]
    /// Lo que hay dentro de una fuente y no se puede mover con su carpeta (podado, enlaces, solo en iCloud), por
    /// alias. Solo para decidir si una carpeta entera se puede mover de una vez: no se enseña nunca.
    let bloqueos: [String: [VaultPath]]

    init(fuentes: [FuenteImportacion], elementos: [ElementoInventario], carpetas: [String: [VaultPath]], podadas: Int,
         herramientas: [String: HerramientaOrigen], bloqueos: [String: [VaultPath]] = [:]) {
        self.fuentes = fuentes
        self.elementos = elementos.sorted { $0.clave < $1.clave }
        self.carpetas = carpetas
        self.podadas = podadas
        self.herramientas = herramientas
        self.bloqueos = bloqueos
        self.porClave = Dictionary(elementos.map { ($0.clave, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func recuento<K: Hashable>(_ els: [ElementoInventario], por k: KeyPath<ElementoInventario, K>) -> [K: Recuento] {
        var out: [K: Recuento] = [:]
        for e in els {
            out[e[keyPath: k], default: Recuento()].ficheros += 1
            out[e[keyPath: k], default: Recuento()].bytes += e.tamano ?? 0
            if e.soloEnICloud { out[e[keyPath: k], default: Recuento()].soloEnICloud += 1 }
        }
        return out
    }

    // MARK: Hacer el inventario

    /// Recorre las fuentes en un hilo protegido (nada se descarga de iCloud) y con la misma poda que la copia: lo
    /// privado y lo excluido no se listan nunca. Solo lee: no escribe nada en ningún sitio.
    public static func hacer(_ fuentes: [FuenteImportacion], opciones: Opciones,
                             fileSystem: any FileSystemAccess = LocalFileSystem(),
                             progreso: (@Sendable (Int) -> Void)? = nil) async throws -> InventarioImportacion {
        var vistos = Set<String>()
        for f in fuentes where !vistos.insert(f.alias.lowercased()).inserted { throw ImportError.aliasRepetido(f.alias) }
        // Una carpeta de fuera que esté dentro de la de la empresa se ordenaría dos veces.
        if let empresa = fuentes.first(where: { $0.clase == .carpetaDeLaEmpresa }) {
            let base = ExclusionRules.key(CopyJob.canonicalPath(empresa.raiz))
            for f in fuentes where f.clase == .externa {
                let k = ExclusionRules.key(CopyJob.canonicalPath(f.raiz))
                if k == base || k.hasPrefix(base + "/") { throw ImportError.fuenteDentroDeLaCarpeta(f.raiz.lastPathComponent) }
            }
        }
        return try await DatalessGuard.run("TLSImport.importar.inventario") { cancel in
            var elementos: [ElementoInventario] = []
            var carpetas: [String: [VaultPath]] = [:]
            var podadas = 0
            var herramientas: [String: HerramientaOrigen] = [:]
            var bloqueos: [String: [VaultPath]] = [:]
            for f in fuentes {
                let ya = elementos.count
                let r = try inventariar(f, opciones: opciones, fs: fileSystem, cancel: cancel) { n in
                    progreso?(ya + n)
                }
                elementos += r.elementos
                carpetas[f.alias] = r.carpetas
                podadas += r.podadas
                bloqueos[f.alias] = r.bloqueos
                for (b, h) in r.herramientas { herramientas[f.alias + "/" + b] = h }
            }
            return InventarioImportacion(fuentes: fuentes, elementos: elementos, carpetas: carpetas, podadas: podadas,
                                         herramientas: herramientas, bloqueos: bloqueos)
        }
    }

    /// Nombres ocultos que se podan sin mirar (y dicen de qué programa viene la carpeta).
    static let marcasObsidian = [".obsidian"]

    /// Una fuente. Debe llamarse en el hilo protegido.
    static func inventariar(_ f: FuenteImportacion, opciones: Opciones, fs: any FileSystemAccess, cancel: CancelFlag?,
                            progreso: (Int) -> Void) throws
        -> (elementos: [ElementoInventario], carpetas: [VaultPath], podadas: Int, herramientas: [String: HerramientaOrigen],
            bloqueos: [VaultPath]) {
        let base = f.raiz.standardizedFileURL.resolvingSymlinksInPath()
        guard fs.isDirectory(base) else { throw ImportError.fuenteNoAccesible(f.raiz.lastPathComponent) }
        let esEmpresa = f.clase == .carpetaDeLaEmpresa
        let layout = esEmpresa ? VaultLayout.load(root: base).layout : nil
        // En la carpeta de la empresa (una copia), lo dejado fuera al copiar apunta a la real: no se exige que exista.
        let exclusiones = layout.map { FuenteImportacion.exclusionesDeLaCopia(f.exclusiones, raiz: base, archivo: $0.archivo, fileSystem: fs) }
            ?? f.exclusiones
        // Lo privado de `.tls/` (si lo hay), lo elegido por la persona, lo de siempre y, en la carpeta de la empresa,
        // `Archivo/` (lo retirado no se vuelve a ordenar).
        let plan = try CopyExclusions.make(origen: base, personales: f.privado + exclusiones,
                                           incluirArchivo: !esEmpresa, fs: fs)
        var reglas = plan.rules
        if let layout, !layout.archivo.isEmpty { reglas.add(VaultPath(layout.archivo)) }
        let walker = TreeWalker(fs: fs, rules: reglas)
        var elementos: [ElementoInventario] = []
        var carpetas: [VaultPath] = []
        var skipped: [WalkItem] = []
        var obsidian = Set<String>()
        var ocultasPodadas = 0
        let pruned = try walker.walk(root: base, cancel: cancel, podar: { p in
            let n = p.name
            guard n.hasPrefix(".") else { return false }
            if n.hasSuffix(".icloud") { return false }   // marcador antiguo de «solo en iCloud»: se cuenta por su nombre
            if marcasObsidian.contains(n) { obsidian.insert(p.components.count > 1 ? p.components[0] : "") }
            ocultasPodadas += 1
            return true
        }, opaca: { p in
            TipoDocumento.extensionesPaquete.contains(p.ext)
        }) { item in
            switch item.kind {
            case .dataless, .symlink: skipped.append(item)
            case .directory, .file: break
            }
            let p = item.path
            let bloque = p.components.count > 1 ? p.components[0] : ""
            switch item.kind {
            case .symlink:
                return  // Los enlaces no se siguen ni se mueven (pueden llevar fuera).
            case .directory:
                if TipoDocumento.extensionesPaquete.contains(p.ext) {
                    elementos.append(paquete(item, fuente: f.alias, bloque: bloque, fs: fs))
                } else {
                    carpetas.append(p)
                }
            case .dataless(let isDir):
                if isDir && !TipoDocumento.extensionesPaquete.contains(p.ext) {
                    carpetas.append(p)   // carpeta solo en iCloud: no se abre (ni se lista).
                    return
                }
                elementos.append(ElementoInventario(
                    clave: f.alias + "/" + p.raw, fuente: f.alias, ruta: p, esPaquete: isDir,
                    tipo: TipoDocumento(extension: p.ext, esCarpeta: isDir), tamano: isDir ? nil : fs.fileSize(item.url),
                    sha256: nil, soloEnICloud: true,
                    sensible: FicherosSensibles.esSensible(p, tamano: fs.fileSize(item.url), esCarpeta: isDir),
                    modificado: fs.modificationDate(item.url), bloque: bloque, herramienta: .carpetas, extracto: nil,
                    propiedades: [:], propiedadesLegibles: true,
                    fechaEnNombre: fechaEnNombre(p, hoy: opciones.hoy)))
            case .file:
                elementos.append(try fichero(item, fuente: f.alias, bloque: bloque, opciones: opciones, fs: fs))
            }
            if elementos.count % 100 == 0 { progreso(elementos.count) }
        }
        progreso(elementos.count)
        try plan.checkUnmatched(pruned: pruned, items: skipped)
        // Herramienta de cada bloque.
        var porBloque: [String: [Int]] = [:]
        for (i, e) in elementos.enumerated() { porBloque[e.bloque, default: []].append(i) }
        var herramientas: [String: HerramientaOrigen] = [:]
        for (b, idx) in porBloque {
            let h = detectarHerramienta(bloque: b, elementos: idx.map { elementos[$0] }, obsidian: obsidian.contains(b),
                                        layout: layout)
            herramientas[b] = h
            for i in idx { elementos[i].herramienta = h }
        }
        // `.DS_Store` (de Finder) no impide mover una carpeta: viaja con ella.
        var bloqueos = pruned.filter { $0.name != ".DS_Store" }
        for item in skipped {
            switch item.kind {
            case .symlink: bloqueos.append(item.path)
            case .dataless(let isDir) where isDir && !TipoDocumento.extensionesPaquete.contains(item.path.ext):
                bloqueos.append(item.path)
            default: break
            }
        }
        return (elementos, carpetas.sorted(), pruned.count, herramientas, bloqueos)
    }

    static func fechaEnNombre(_ p: VaultPath, hoy: LocalDate) -> String? {
        DocumentDater(opciones: .init(hoy: hoy, ocr: nil)).fechaEnNombre(p.name, ruta: p.raw)?.fecha
    }

    /// Un fichero que ya está en el Mac.
    static func fichero(_ item: WalkItem, fuente: String, bloque: String, opciones: Opciones,
                        fs: any FileSystemAccess) throws -> ElementoInventario {
        let p = item.path
        var nombre = p
        var enICloud = false
        // Marcador antiguo `.Factura.pdf.icloud`: el fichero de verdad está solo en iCloud.
        if p.name.hasPrefix("."), p.name.hasSuffix(".icloud") {
            let visible = String(p.name.dropFirst().dropLast(".icloud".count))
            nombre = (p.parent ?? .root).appending(visible)
            enICloud = true
        }
        let tamano = fs.fileSize(item.url)
        let sensible = FicherosSensibles.esSensible(nombre, tamano: tamano, esCarpeta: false)
        let tipo = TipoDocumento(extension: nombre.ext)
        let sha = (sensible || enICloud) ? nil : try fs.sha256(of: item.url)
        var extracto: String?
        var props: [String: String] = [:]
        var legibles = true
        if opciones.leerExtractos, !sensible, !enICloud {
            if TipoDocumento.extensionesDeTexto.contains(nombre.ext), let data = try? leerPrincipio(item.url, bytes: 64 * 1024),
               let texto = TextDecoding.decode(data).map(TextDecoding.strippingBOM) {
                if tipo == .nota {
                    let doc = NoteDocument(text: texto)
                    let fm = doc.frontmatter
                    legibles = fm.isValid
                    for prop in fm.properties { props[prop.key.lowercased()] = prop.value.displayText }
                    extracto = String(doc.body.prefix(opciones.maxExtracto))
                } else {
                    extracto = String(texto.prefix(opciones.maxExtracto))
                }
            } else if tipo == .pdf, (tamano ?? 0) <= opciones.maxBytesPDF {
                extracto = DocumentDater.textoPDF(item.url, paginas: 2).map { String($0.prefix(opciones.maxExtracto)) }
            }
        }
        return ElementoInventario(
            clave: fuente + "/" + nombre.raw, fuente: fuente, ruta: nombre, esPaquete: false, tipo: tipo,
            tamano: tamano, sha256: sha, soloEnICloud: enICloud, sensible: sensible, modificado: fs.modificationDate(item.url),
            bloque: bloque, herramienta: .carpetas, extracto: extracto?.isEmpty == true ? nil : extracto,
            propiedades: props, propiedadesLegibles: legibles, fechaEnNombre: fechaEnNombre(nombre, hoy: opciones.hoy))
    }

    /// Un paquete: su huella es la de sus ficheros (ruta relativa y SHA-256 de cada uno).
    static func paquete(_ item: WalkItem, fuente: String, bloque: String, fs: any FileSystemAccess) -> ElementoInventario {
        let (huella, bytes) = (try? huellaDePaquete(item.url, fs: fs)) ?? (nil, nil)
        // Sin huella (algo de dentro solo está en iCloud, o no se pudo leer entero): cuenta como solo en iCloud y no se
        // trae ni se mueve; si no, se copiaría a medias y la comprobación lo daría por bueno (nil con nil).
        return ElementoInventario(
            clave: fuente + "/" + item.path.raw, fuente: fuente, ruta: item.path, esPaquete: true,
            tipo: TipoDocumento(extension: item.path.ext, esCarpeta: true), tamano: bytes, sha256: huella,
            soloEnICloud: huella == nil, sensible: false, modificado: fs.modificationDate(item.url), bloque: bloque,
            herramienta: .carpetas, extracto: nil, propiedades: [:], propiedadesLegibles: true, fechaEnNombre: nil)
    }

    /// Huella de un paquete (o de cualquier carpeta): SHA-256 de las líneas «ruta\tsha» de sus ficheros, en orden.
    /// `nil` si algo de dentro está solo en iCloud. Debe llamarse en el hilo protegido.
    static func huellaDePaquete(_ url: URL, fs: any FileSystemAccess) throws -> (String?, Int64?) {
        var lineas: [String] = []
        var bytes: Int64 = 0
        var incompleto = false
        try TreeWalker(fs: fs, rules: ExclusionRules()).walk(root: url) { item in
            switch item.kind {
            case .file:
                lineas.append(item.path.raw + "\t" + (try fs.sha256(of: item.url)))
                bytes += fs.fileSize(item.url) ?? 0
            case .dataless: incompleto = true
            case .directory, .symlink: break
            }
        }
        guard !incompleto else { return (nil, bytes) }
        var h = SHA256()
        for l in lineas.sorted() { h.update(data: Data((l + "\n").utf8)) }
        return (LocalFileSystem.hex(h.finalize()), bytes)
    }

    static func leerPrincipio(_ url: URL, bytes: Int) throws -> Data {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        return try h.read(upToCount: bytes) ?? Data()
    }

    // MARK: Herramienta de origen

    static let idNotion = try! NSRegularExpression(pattern: #"\s[0-9a-f]{32}(?=(\.[A-Za-z0-9]+)?$)"#)

    /// Quita el identificador de 32 cifras hexadecimales que añade Notion a cada nombre.
    public static func sinIdNotion(_ nombre: String) -> String {
        let ns = nombre as NSString
        return idNotion.stringByReplacingMatches(in: nombre, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    static func tieneIdNotion(_ nombre: String) -> Bool {
        idNotion.firstMatch(in: nombre, range: NSRange(location: 0, length: (nombre as NSString).length)) != nil
    }

    static func detectarHerramienta(bloque: String, elementos: [ElementoInventario], obsidian: Bool,
                                    layout: VaultLayout?) -> HerramientaOrigen {
        if let layout {
            // En la carpeta de la empresa: las áreas, el Buzón y lo de la raíz ya siguen la estructura.
            if bloque.isEmpty || layout.area(of: VaultPath(bloque)) != nil
                || TextFolding.nameKey(bloque) == TextFolding.nameKey(layout.buzon ?? "Buzón") {
                return .ordenada
            }
        }
        let n = max(elementos.count, 1)
        let conIdNotion = elementos.filter { e in e.ruta.components.contains(where: tieneIdNotion) }.count
        if conIdNotion * 10 >= n * 3 { return .notion }
        if obsidian { return .obsidian }
        let gdocs: Set<String> = ["gdoc", "gsheet", "gslides", "gdraw", "gform", "gmap", "gsite"]
        let nb = TextFolding.fold(bloque)
        if elementos.contains(where: { gdocs.contains($0.ruta.ext) }) || ["google drive", "mi unidad", "my drive", "drive"].contains(nb) {
            return .drive
        }
        let correos = elementos.filter { $0.tipo == .correo }.count
        if correos * 10 >= n * 3 || ["correo", "mail", "email", "e-mail", "emails", "correos"].contains(nb) { return .correo }
        let notas = elementos.filter { $0.tipo == .nota }
        let conWiki = notas.filter { ($0.extracto ?? "").contains("[[") }.count
        if notas.count >= 3, conWiki * 2 >= notas.count { return .obsidian }
        return .carpetas
    }
}
