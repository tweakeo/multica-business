import Foundation

/// Una ficha tal como la busca ⌘K (§4.9): título, otros nombres, número o código y propiedades de texto, ya
/// sin tildes ni mayúsculas para buscar deprisa.
public struct EntradaBusqueda: Sendable, Hashable, Identifiable {
    public var id: String { ruta.raw }
    public let ruta: VaultPath
    public let titulo: String
    public let tipo: NoteKind
    public let area: AreaCode?
    /// Base en la que sale (`contactos`, `facturas`…); `nil` = nota suelta.
    public let base: String?
    /// Número o código (T-0042, F-2026-0014, VE2).
    public let codigos: [String]
    public let otrosNombres: [String]
    /// Estado y relación principal («Interesado · Talleres Martín e Hijos SL»).
    public let detalle: String
    public let modificada: Date?
    /// Espera tu decisión: una tarea de tipo decisión sin cerrar, un borrador pendiente de tu OK o una
    /// decisión propuesta («Pide tu decisión» de ⌘K).
    public let pideDecision: Bool

    let tituloPlegado: String
    let codigosPlegados: [String]
    let nombresPlegados: [String]
    let propiedadesPlegadas: String

    public init(ruta: VaultPath, titulo: String, tipo: NoteKind, area: AreaCode?, base: String?, codigos: [String],
                otrosNombres: [String], propiedades: [String], detalle: String, modificada: Date?, pideDecision: Bool = false) {
        self.ruta = ruta; self.titulo = titulo; self.tipo = tipo; self.area = area; self.base = base
        self.codigos = codigos; self.otrosNombres = otrosNombres; self.detalle = detalle; self.modificada = modificada
        self.pideDecision = pideDecision
        tituloPlegado = TextFolding.fold(titulo)
        codigosPlegados = codigos.map(CatalogoBusqueda.soloLetrasYCifras)
        nombresPlegados = otrosNombres.map(TextFolding.fold)
        propiedadesPlegadas = TextFolding.fold(propiedades.joined(separator: " \u{1F} "))
    }
}

/// Dónde coincidió una búsqueda.
public enum LugarCoincidencia: String, Sendable, Hashable {
    case codigo, titulo, otroNombre, propiedad
}

/// Un resultado de ⌘K: la ficha, su puntuación y qué texto enseñar con lo encontrado resaltado.
public struct ResultadoBusqueda: Sendable, Hashable, Identifiable {
    public var id: String { entrada.id }
    public let entrada: EntradaBusqueda
    public let puntos: Int
    public let lugar: LugarCoincidencia
    /// Lo que coincidió si no es el título (el otro nombre o el número).
    public let coincidencia: String?
}

/// El catálogo de ⌘K: todas las fichas de la carpeta (sin lo privado ni `Archivo/`), listas para buscar en
/// memoria en pocos milisegundos (criterio §11.7: menos de 100 ms con 5.000 fichas). Se construye una vez
/// por cambio de la carpeta, fuera del hilo principal.
public struct CatalogoBusqueda: Sendable {
    public let entradas: [EntradaBusqueda]
    private let porRuta: [VaultPath: Int]

    public init(entradas: [EntradaBusqueda]) {
        self.entradas = entradas
        var m: [VaultPath: Int] = [:]
        for (i, e) in entradas.enumerated() { m[e.ruta] = i }
        porRuta = m
    }

    public static let vacio = CatalogoBusqueda(entradas: [])

    public func entrada(_ ruta: VaultPath) -> EntradaBusqueda? { porRuta[ruta].map { entradas[$0] } }

    /// Construye el catálogo desde el índice: fichas y notas con tipo, nunca lo privado.
    public static func construir(_ fichas: [FichaIndexada]) -> CatalogoBusqueda {
        let tiposBase: [NoteKind: String] = {
            var m: [NoteKind: String] = [:]
            for c in CatalogoBases.deSerie { for t in c.tipos where m[t] == nil { m[t] = c.id } }
            return m
        }()
        var out: [EntradaBusqueda] = []
        out.reserveCapacity(fichas.count)
        for f in fichas where !f.resumen.privado && f.resumen.kind != .index {
            let p = f.propiedades
            func texto(_ k: String) -> String? {
                guard let v = p[k], !v.estaVacio else { return nil }
                return FormatoBase.textoVisible(v)
            }
            let codigos = ["numero", "codigo"].compactMap(texto)
            var nombres: [String] = []
            if case .list(let l)? = p["aliases"] ?? p["alias"] { nombres += l }
            if case .text(let t)? = p["aliases"] ?? p["alias"], !t.isEmpty { nombres.append(t) }
            for k in ["nombre", "titulo", "title", "name"] {
                if let t = texto(k), TextFolding.fold(t) != TextFolding.fold(f.resumen.title), !nombres.contains(t) { nombres.append(t) }
            }
            var props: [String] = []
            for (k, v) in p where !["tls_type", "tls_schema", "id", "aliases", "alias", "plantilla", "origen"].contains(k) {
                let t = FormatoBase.textoVisible(v)
                if !t.isEmpty, t.count < 200 { props.append(t) }
            }
            let detalle = [texto("estado"), texto("empresa") ?? texto("contacto") ?? texto("proyecto")]
                .compactMap { $0 }.joined(separator: " · ")
            let estado = TextFolding.fold(texto("estado") ?? "")
            let pide: Bool = {
                switch f.resumen.kind {
                case .task: TextFolding.fold(texto("tipo") ?? "") == "decision" && !["hecha", "cancelada"].contains(estado)
                case .draft: estado.hasPrefix("pendiente")
                case .decision: estado == "propuesta"
                default: false
                }
            }()
            out.append(EntradaBusqueda(ruta: f.ruta, titulo: f.resumen.title, tipo: f.resumen.kind, area: f.resumen.area,
                                       base: tiposBase[f.resumen.kind], codigos: codigos, otrosNombres: nombres,
                                       propiedades: props, detalle: detalle, modificada: f.resumen.modified, pideDecision: pide))
        }
        return CatalogoBusqueda(entradas: out)
    }

    /// Busca por número o código, título, otros nombres y propiedades de texto; sin tildes ni mayúsculas.
    public func buscar(_ consulta: String, limite: Int = 40) -> [ResultadoBusqueda] {
        let q = TextFolding.fold(consulta).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, limite > 0 else { return [] }
        let qc = Self.soloLetrasYCifras(q)
        let palabras = q.split(whereSeparator: { $0 == " " }).map(String.init)
        var res: [ResultadoBusqueda] = []
        for e in entradas {
            var mejor = 0
            var lugar = LugarCoincidencia.titulo
            var coincidencia: String?
            // Número o código: «T-0042», «t0042», «0042», «F-2026-0014».
            if qc.count >= 2 {
                for (i, c) in e.codigosPlegados.enumerated() {
                    let s = c == qc ? 2000 : (c.hasPrefix(qc) ? 1500 : (qc.count >= 3 && c.contains(qc) ? 1200 : 0))
                    if s > mejor { mejor = s; lugar = .codigo; coincidencia = e.codigos[i] }
                }
            }
            let st = Self.puntos(q, en: e.tituloPlegado)
            if st > mejor { mejor = st; lugar = .titulo; coincidencia = nil }
            for (i, n) in e.nombresPlegados.enumerated() {
                let s = max(0, Self.puntos(q, en: n) - 100)
                if s > mejor { mejor = s; lugar = .otroNombre; coincidencia = e.otrosNombres[i] }
            }
            if mejor == 0, palabras.count > 1 {
                // Cada palabra en algún campo (una palabra no lleva espacios: no puede casar a caballo de dos campos).
                // Sin juntar los campos en un texto nuevo por ficha: con 5.000 fichas era lo que más costaba (§11.7).
                let encaja = palabras.allSatisfy { p in
                    e.tituloPlegado.contains(p) || e.nombresPlegados.contains { $0.contains(p) }
                        || e.codigosPlegados.contains { $0.contains(p) } || e.propiedadesPlegadas.contains(p)
                }
                if encaja { mejor = 400; lugar = .propiedad }
            }
            if mejor == 0, q.count >= 3, e.propiedadesPlegadas.contains(q) { mejor = 300; lugar = .propiedad }
            guard mejor > 0 else { continue }
            if e.base != nil { mejor += 10 }
            res.append(ResultadoBusqueda(entrada: e, puntos: mejor, lugar: lugar, coincidencia: coincidencia))
        }
        res.sort { a, b in
            if a.puntos != b.puntos { return a.puntos > b.puntos }
            if a.entrada.titulo.count != b.entrada.titulo.count { return a.entrada.titulo.count < b.entrada.titulo.count }
            return a.entrada.ruta < b.entrada.ruta
        }
        return Array(res.prefix(limite))
    }

    /// 1000 al principio · 800 al principio de una palabra · 600 dentro · 0 nada (sin subsecuencias:
    /// en ⌘K se busca en muchas fichas y dan demasiado ruido).
    static func puntos(_ q: String, en s: String) -> Int {
        guard !q.isEmpty, !s.isEmpty else { return 0 }
        if s.hasPrefix(q) { return 1000 }
        var desde = s.startIndex
        var dentro = false
        while let r = s.range(of: q, range: desde..<s.endIndex) {
            dentro = true
            if r.lowerBound == s.startIndex || !s[s.index(before: r.lowerBound)].isLetterOrDigit { return 800 }
            desde = s.index(after: r.lowerBound)
        }
        return dentro ? 600 : 0
    }

    /// «T-0042» → «t0042».
    static func soloLetrasYCifras(_ s: String) -> String {
        String(TextFolding.fold(s).filter { $0.isLetter || $0.isNumber })
    }
}

/// Vistas guardadas de cada base. En la carpeta van en `.tls/vistas/<base>.json` (`rutaEnCarpeta`) y se
/// escriben **solo** por `CommandBus` (`BaseModelo.guardarVistas`). Este almacén es el de los datos de la app
/// de esa empresa (`<estado>/vistas/<base>.json`): las de antes de F1 integrada y las de una carpeta en solo
/// lectura. Nunca escribe dentro de la carpeta de la empresa.
public struct AlmacenVistas: Sendable {
    public let directorio: URL

    public init(directorio: URL) { self.directorio = directorio }

    /// Dónde van dentro de la carpeta (por `CommandBus`).
    public static func rutaEnCarpeta(_ base: String) -> VaultPath { VaultPath(".tls/vistas/\(base).json") }

    struct Fichero: Codable {
        var version = 1
        var vistas: [VistaGuardada]
    }

    public func url(_ base: String) -> URL { directorio.appendingPathComponent("\(base).json") }

    public func leer(_ base: String) -> [VistaGuardada] {
        guard let data = try? Data(contentsOf: url(base)) else { return [] }
        return Self.decodificar(data)
    }

    public func guardar(_ vistas: [VistaGuardada], de base: String) throws {
        try FileManager.default.createDirectory(at: directorio, withIntermediateDirectories: true)
        try Self.codificar(vistas).write(to: url(base), options: .atomic)
    }

    public static func codificar(_ vistas: [VistaGuardada]) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(Fichero(vistas: vistas))) ?? Data()
    }

    public static func decodificar(_ data: Data) -> [VistaGuardada] {
        (try? JSONDecoder().decode(Fichero.self, from: data))?.vistas ?? []
    }
}
