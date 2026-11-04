import Foundation
import Testing
import TLSCore
import TLSImport

/// Un caso golden: `Casos/<caso>/{entrada/, operacion.json, esperado/}`.
///
/// `operacion.json`:
/// - `{"operacion": "convertir-g2", "opciones": {"clase": "demo", "hoy": "2026-10-19"}}`: `entrada/` es una carpeta G2
///   y `esperado/` la carpeta v2 que debe salir, byte a byte.
/// - `{"operacion": "ida-y-vuelta", "origen": "fixture:EmpresaMinima"}`: leer y reescribir sin cambios cada `.md` y `.csv`
///   da los mismos bytes. El origen es `entrada/` o una referencia (`fixture:EmpresaMinima`,
///   `ejemplo:Asesoria-Ribera`, `caso:<caso>/esperado`). No lleva `esperado/`: lo esperado es la entrada.
/// - `{"operacion": "lectura", "origen": …}`: lo que lee el núcleo (tipo, propiedades, título, enlaces y su destino,
///   cabeceras de CSV) debe coincidir con `esperado/lectura.json`.
/// - `{"operacion": "escritor", "plan": [ {"op": "mergeFrontmatter", …}, … ]}`: aplica las operaciones del escritor
///   (PLAN §4.8) a una copia de `entrada/` y compara con `esperado/`. Esperan a que exista el escritor
///   (`Ejecutores.escritor`); mientras, solo se comprueba que el caso está bien formado.
///
/// `TLS_ACTUALIZAR_GOLDEN=1` regenera `esperado/` (salvo en `ida-y-vuelta`).
struct Caso: Sendable, CustomTestStringConvertible {
    let nombre: String
    let carpeta: URL
    let operacion: Operacion

    var testDescription: String { nombre }
    var entrada: URL { carpeta.appendingPathComponent("entrada", isDirectory: true) }
    var esperado: URL { carpeta.appendingPathComponent("esperado", isDirectory: true) }

    /// `false` si su operación espera una API que aún no existe.
    var ejecutable: Bool {
        if case .escritor(let plan) = operacion {
            guard let e = Ejecutores.escritor else { return false }
            return plan.allSatisfy { e.soporta($0.op) }
        }
        return true
    }
}

enum Operacion: Sendable {
    case convertirG2(OpcionesConversionG2)
    case idaYVuelta(origen: String?)
    case lectura(origen: String?)
    case escritor([OperacionEscritor])
}

/// Una operación del escritor descrita en JSON (nombres de `WriteOp`, PLAN §4.8).
struct OperacionEscritor: Sendable, Codable, Hashable {
    let op: String
    let ruta: String
    var a: String?
    var set: [String: String]?
    var unset: [String]?
    var seccion: String?
    var texto: String?
    var linea: String?
    var fila: [String: String]?
    var clave: String?
}

/// Ejecuta un plan del escritor sobre una carpeta. Lo registra quien tenga la API del escritor.
protocol EjecutorEscritor: Sendable {
    func soporta(_ op: String) -> Bool
    func aplicar(_ plan: [OperacionEscritor], en raiz: URL) async throws
}

/// Lee y reescribe un fichero «sin cambios». Devuelve `nil` si no sabe tratar ese tipo de fichero.
protocol Reescritor: Sendable {
    func reescribir(_ datos: Data, ruta: VaultPath) throws -> Data?
}

enum Ejecutores {
    /// Escritor de PLAN §4.8 (`VaultWriter`). Un caso con una operación que no sabe hacer queda pendiente.
    static let escritor: (any EjecutorEscritor)? = EjecutorVaultWriter()

    /// Reescritura sin cambios: con lo que lee el núcleo (`NoteDocument`, `CSVTable`) y con los documentos
    /// del escritor (`FrontmatterDocument`, `CSVDocument`). Los dos deben dar los mismos bytes.
    static let reescritores: [any Reescritor] = [ReescritorLectura(), ReescritorEscritor()]
}

/// Reescritura canónica con el lector del núcleo: `---`, YAML, `---` y el cuerpo intacto; CSV con su separador,
/// su fin de línea y su BOM, y comillas solo donde hacen falta.
struct ReescritorLectura: Reescritor {
    func reescribir(_ datos: Data, ruta: VaultPath) throws -> Data? {
        // `String(data:encoding:)` quita el BOM: se valida con él y se decodifica sin perderlo.
        guard String(data: datos, encoding: .utf8) != nil else { return nil }
        let texto = String(decoding: datos, as: UTF8.self)
        let bom = texto.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : ""
        let eol = texto.contains("\r\n") ? "\r\n" : "\n"
        switch ruta.ext {
        case "md":
            let doc = NoteDocument(text: texto)
            guard let front = doc.frontmatterText else { return Data((bom + doc.body).utf8) }
            return Data((bom + "---" + eol + front + "---" + eol + doc.body).utf8)
        case "csv":
            let tabla = CSVTable.parse(texto)
            let sep = String(tabla.delimiter)
            let especiales = Set(sep.unicodeScalars).union(["\"", "\n", "\r"])
            func campo(_ s: String) -> String {
                // Por escalares: en Swift «\r\n» es un solo carácter y `contains("\n")` no lo ve.
                let necesita = s.unicodeScalars.contains(where: especiales.contains)
                return necesita ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
            }
            let lineas = ([tabla.header] + tabla.rows).map { $0.map(campo).joined(separator: sep) }
            let final = TextDecoding.strippingBOM(texto).hasSuffix(eol) ? eol : ""
            return Data((bom + lineas.joined(separator: eol) + final).utf8)
        default:
            return nil
        }
    }
}

enum Arnes {
    static func casos() -> [Caso] {
        let fm = FileManager.default
        guard let nombres = try? fm.contentsOfDirectory(atPath: RutasConformidad.casos.path) else { return [] }
        return nombres.sorted().compactMap { nombre in
            let carpeta = RutasConformidad.casos.appendingPathComponent(nombre, isDirectory: true)
            guard let data = fm.contents(atPath: carpeta.appendingPathComponent("operacion.json").path),
                  let op = try? operacion(data) else { return nil }
            return Caso(nombre: nombre, carpeta: carpeta, operacion: op)
        }
    }

    static func operacion(_ data: Data) throws -> Operacion {
        struct JSON: Decodable {
            let operacion: String
            let origen: String?
            let opciones: Opciones?
            let plan: [OperacionEscritor]?
            struct Opciones: Decodable { let clase: String?; let hoy: String? }
        }
        let j = try JSONDecoder().decode(JSON.self, from: data)
        switch j.operacion {
        case "convertir-g2":
            let clase = j.opciones?.clase.flatMap(VaultClass.init(rawValue:)) ?? .copia
            return .convertirG2(OpcionesConversionG2(clase: clase, hoy: j.opciones?.hoy))
        case "ida-y-vuelta": return .idaYVuelta(origen: j.origen)
        case "lectura": return .lectura(origen: j.origen)
        case "escritor": return .escritor(j.plan ?? [])
        default: throw CocoaError(.featureUnsupported)
        }
    }

    /// `fixture:EmpresaMinima`, `ejemplo:Asesoria-Ribera`, `caso:<caso>/<carpeta>` o, sin origen, `entrada/`.
    static func origen(_ referencia: String?, caso: Caso) -> URL {
        guard let r = referencia else { return caso.entrada }
        if r == "fixture:EmpresaMinima" { return RutasConformidad.empresaMinima }
        if r == "ejemplo:Asesoria-Ribera" { return RutasConformidad.ejemploRibera }
        if r.hasPrefix("caso:") { return RutasConformidad.casos.appendingPathComponent(String(r.dropFirst(5)), isDirectory: true) }
        return caso.carpeta.appendingPathComponent(r, isDirectory: true)
    }

    static func ejecutar(_ caso: Caso) async throws {
        switch caso.operacion {
        case .convertirG2(let opciones):
            let plan = try ConversorG2.planificar(origen: caso.entrada, opciones: opciones)
            var arbol: [String: Data] = [:]
            for (ruta, _) in plan.ficheros { arbol[ruta.raw] = try plan.datos(ruta) }
            try comparar(arbol, caso)
            #expect(ValidadorV2.validar(arbol).isEmpty, "\(ValidadorV2.validar(arbol))")
        case .idaYVuelta(let referencia):
            let raiz = origen(referencia, caso: caso)
            let arbol = try Arbol.leer(raiz)
            #expect(!arbol.isEmpty, "Sin ficheros en \(raiz.path)")
            for reescritor in Ejecutores.reescritores {
                var revisados = 0
                for (ruta, datos) in arbol.sorted(by: { $0.key < $1.key }) {
                    guard let reescrito = try reescritor.reescribir(datos, ruta: VaultPath(ruta)) else { continue }
                    revisados += 1
                    #expect(reescrito == datos, "\(caso.nombre): «\(ruta)» cambia al reescribirlo sin cambios (\(type(of: reescritor)))")
                }
                #expect(revisados > 0)
            }
        case .lectura(let referencia):
            let arbol = try Arbol.leer(origen(referencia, caso: caso))
            let json = try Lectura.json(arbol)
            try comparar(["lectura.json": json], caso)
        case .escritor(let plan):
            guard let escritor = Ejecutores.escritor else { return }
            let base = RutasConformidad.temporal("escritor")
            defer { try? FileManager.default.removeItem(at: base) }
            let tmp = base.appendingPathComponent("carpeta", isDirectory: true)
            try Arbol.escribir(try Arbol.leer(caso.entrada), en: tmp)
            try await escritor.aplicar(plan, en: tmp)
            // `.tls/escritor.json` es el cerrojo del escritor (instalación y fecha): no forma parte del resultado.
            var resultado = try Arbol.leer(tmp)
            resultado[".tls/escritor.json"] = nil
            try comparar(resultado, caso)
        }
    }

    /// Compara con `esperado/` o lo regenera.
    static func comparar(_ arbol: [String: Data], _ caso: Caso) throws {
        if RutasConformidad.actualizarGolden {
            try Arbol.reemplazarGolden(caso.esperado, con: arbol)
            return
        }
        let esperado = (try? Arbol.leer(caso.esperado)) ?? [:]
        let difs = Arbol.diferencias(arbol, esperado)
        #expect(difs.isEmpty, "\(caso.nombre): \(difs.prefix(20).joined(separator: "\n")) (regenera con TLS_ACTUALIZAR_GOLDEN=1 si el cambio es correcto)")
    }
}

/// Lo que lee el núcleo de una carpeta, en JSON estable.
enum Lectura {
    struct Enlace: Codable { let estilo: String; let destino: String; let resuelve: String? }
    struct Fichero: Codable {
        let ruta: String
        let clase: String
        var tipo: String?
        var titulo: String?
        var propiedades: [[String]]?
        var enlaces: [Enlace]?
        var delimitador: String?
        var cabecera: [String]?
        var filas: Int?
    }

    static func json(_ arbol: [String: Data]) throws -> Data {
        let resolver = LinkResolver(paths: arbol.keys.map(VaultPath.init))
        var ficheros: [Fichero] = []
        for (ruta, datos) in arbol.sorted(by: { $0.key < $1.key }) {
            let p = VaultPath(ruta)
            switch p.ext {
            case "md":
                let doc = NoteDocument(data: datos)
                let fm = doc.frontmatter
                var enlaces: [Enlace] = []
                var textos = [doc.body]
                for prop in fm.properties {
                    switch prop.value {
                    case .text(let s) where s.contains("[["): textos.append(s)
                    case .list(let l): textos += l.filter { $0.contains("[[") }
                    default: break
                    }
                }
                for t in textos {
                    for e in LinkParser.links(in: t) where !e.isExternal {
                        enlaces.append(Enlace(estilo: e.style.rawValue, destino: e.resolvable,
                                              resuelve: resolver.resolve(e.resolvable, from: p)?.raw))
                    }
                }
                ficheros.append(Fichero(ruta: ruta, clase: "nota", tipo: fm.text("tls_type"),
                                        titulo: doc.title(fileStem: p.stem, frontmatter: fm),
                                        propiedades: fm.properties.map { [$0.key, clase($0.value), texto($0.value)] },
                                        enlaces: enlaces))
            case "csv":
                let tabla = CSVTable.parse(TextDecoding.decode(datos) ?? "")
                ficheros.append(Fichero(ruta: ruta, clase: "tabla", delimitador: String(tabla.delimiter),
                                        cabecera: tabla.header, filas: tabla.rows.count))
            default:
                ficheros.append(Fichero(ruta: ruta, clase: "otro"))
            }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try enc.encode(ficheros)
        data.append(0x0A)
        return data
    }

    static func clase(_ v: PropertyValue) -> String {
        switch v {
        case .text: "texto"
        case .number: "numero"
        case .bool: "bool"
        case .list: "lista"
        case .empty: "vacio"
        case .raw: "yaml"
        }
    }

    static func texto(_ v: PropertyValue) -> String {
        switch v {
        case .text(let s), .number(let s), .raw(let s): s
        case .bool(let b): b ? "true" : "false"
        case .list(let l): l.joined(separator: " | ")
        case .empty: ""
        }
    }
}
