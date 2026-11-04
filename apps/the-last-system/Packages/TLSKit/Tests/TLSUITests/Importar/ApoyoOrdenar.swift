import Foundation
import Synchronization
import Testing
import TLSCore
import TLSImport
@testable import TLSUI

/// Empresa ficticia para las pruebas de «Ordenar lo que tienes» (pantallas): todo en un temporal propio, nombres
/// inventados y una carpeta privada con nombre neutro («Expediente privado»). Nunca se tocan los ficheros del repositorio.
@MainActor
struct EmpresaOrdenar {
    let base: URL
    let raiz: URL
    let asup: URL
    let estado: URL
    let entry: VaultEntry
    static let hoy = LocalDate(year: 2026, month: 10, day: 19)!

    static var paquete: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL
    }
    static var fixtureG3: URL { paquete.appendingPathComponent("Tests/TLSCoreTests/Fixtures/EmpresaMinima") }
    static var ribera: URL { paquete.appendingPathComponent("../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL }

    init(nombre: String = "Empresa Prueba", copiaDe origen: URL? = nil, exclusiones: [String] = [], origenReal: String? = nil) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-ordenar-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        raiz = base.appendingPathComponent(nombre, isDirectory: true)
        asup = base.appendingPathComponent("asup", isDirectory: true)
        try FileManager.default.createDirectory(at: asup, withIntermediateDirectories: true)
        if let origen {
            try FileManager.default.copyItem(at: origen, to: raiz)
        } else {
            try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        }
        entry = VaultEntry(nombre: nombre, ruta: raiz.path, bookmark: nil, clase: .copia, escritura: .permitida,
                           exclusionesCopia: exclusiones, origen: origenReal)
        estado = asup.appendingPathComponent(entry.id.uuidString.lowercased(), isDirectory: true)
    }

    func url(_ rel: String) -> URL { VaultPath(rel).url(in: raiz) }

    @discardableResult
    func escribir(_ rel: String, _ texto: String) throws -> URL { try escribir(rel, datos: Data(texto.utf8)) }

    @discardableResult
    func escribir(_ rel: String, datos: Data) throws -> URL {
        let u = url(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: u)
        return u
    }

    func texto(_ rel: String) -> String? { try? String(contentsOf: url(rel), encoding: .utf8) }
    func existe(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url(rel).path) }
    func limpiar() { try? FileManager.default.removeItem(at: base) }

    /// La copia de trabajo de una empresa con su estructura y un desorden típico.
    static func desordenada() throws -> EmpresaOrdenar {
        let e = try EmpresaOrdenar()
        try e.escribir(".tls/layout.json", "{\"preset\": \"humana\"}")
        try e.escribir(".tls/config.yaml", "version: 1\nid: 6f1d3c2a-0000-4000-8000-0000000000aa\nclase: copia\nhoy: 2026-10-19\nprivado:\n  - Expediente privado\n")
        try e.escribir("Empresa.md", "# Empresa de prueba\n")
        for a in AreaCode.allCases { try e.escribir("\(a.numero) · \(a.nombre)/Área.md", "# \(a.nombre)\n") }
        try e.escribir("2 · Ventas/Contactos/ana-lopez.md", "---\ntls_type: contact\ntls_schema: 1\nid: 11111111-1111-4111-8111-111111111111\n---\n# Ana López (la que ya estaba)\n")
        try e.escribir("Clientes/Ana López.md", "---\ntipo: persona\nempresa: Panadería Sol\n---\n# Ana López\nTrabaja en [Panadería Sol](../Empresas%20sueltas/Panader%C3%ADa%20Sol.md).\n")
        try e.escribir("Empresas sueltas/Panadería Sol.md", "---\ntipo: empresa\n---\n# Panadería Sol\nContacto: [Ana](../Clientes/Ana%20L%C3%B3pez.md)\n")
        try e.escribir("Facturas/Factura 2025-03-15 Proveedor.pdf", datos: Data("%PDF-1.4 factura de prueba".utf8))
        try e.escribir("Notas/Ideas sueltas.md", "Cosas que pensar.\n")
        try e.escribir("Notas/Ideas sueltas (1).md", "Cosas que pensar.\n")
        try e.escribir("Viejo/Acta reunión 2019-05-02.md", "Acta de una reunión antigua.\n")
        try e.escribir("Expediente privado/secreto.md", "contenido privado de prueba\n")
        return e
    }

    /// Acceso con escritor propio (la empresa no está abierta en ninguna ventana).
    var acceso: AccesoEmpresa {
        AccesoEmpresa(entry: entry, raiz: raiz, appSupport: asup, estado: estado, persona: "Manu")
    }

    func modelo(_ ruta: RutaOrdenar = .ordenar) -> ModeloOrdenar {
        let m = ModeloOrdenar(acceso: acceso, ruta: ruta, hoy: Self.hoy)
        m.ocr = nil
        return m
    }

    /// Las carpetas privadas de prueba que hay en esta empresa.
    var privadas: [VaultPath] {
        ["Expediente privado", "Privado"].filter { existe($0) }.map { VaultPath($0) }
    }

    /// Foto completa (también lo oculto y `Archivo/`, sin lo privado): sirve para demostrar que no se escribió nada.
    func fotoCompleta() async throws -> Inventory {
        try await Inventory.make(of: raiz, exclusiones: privadas, completo: true)
    }

    /// Foto como la del criterio 4 (sin `Archivo/`, sin lo privado).
    func foto() async throws -> Inventory {
        try await Inventory.make(of: raiz, exclusiones: privadas)
    }
}

/// Claude falso en memoria (nunca se lanza Claude): apunta lo que recibe y propone «Ventas › Contactos» para todo.
final class ClaudeEnMemoria: EjecutorClasificacion, Sendable {
    let peticiones = Mutex<[String]>([])
    let coleccion: String

    init(coleccion: String = "ventas.contactos") { self.coleccion = coleccion }

    func ejecutar(peticion: String, esquema: String) async throws -> Data {
        peticiones.withLock { $0.append(peticion) }
        let ids = peticion.split(separator: "\n").compactMap { linea -> Int? in
            guard let r = linea.range(of: #""id":"(\d+)""#, options: .regularExpression) else { return nil }
            return Int(linea[r].filter(\.isNumber))
        }
        let elementos = ids.map { #"{"id":\#($0),"coleccion":"\#(coleccion)","confianza":0.8,"motivo":"Parece una persona"}"# }
        return Data(#"{"elementos":[\#(elementos.joined(separator: ","))]}"#.utf8)
    }

    var todo: String { peticiones.withLock { $0.joined(separator: "\n") } }
}

/// Ficheros de una carpeta (relativos), para comparar el estado de la app antes y después.
func ficherosBajo(_ url: URL) -> [String] {
    (FileManager.default.enumerator(atPath: url.path)?.allObjects as? [String] ?? []).sorted()
}

/// Lo que ningún texto para la persona puede decir (PLAN §6.9).
@MainActor
func jergaOrdenar(_ texto: String) -> [String] { GlosarioTests.jerga(texto) }
