import Foundation
import Observation
import os
import TLSCore

/// Cómo va un recorrido. Se guarda en `tutorial.json` (Application Support, fuera de la carpeta).
public struct EstadoRecorrido: Codable, Sendable, Hashable {
    public enum Fase: String, Codable, Sendable, Hashable {
        case sinEmpezar = "sin-empezar"
        case enCurso = "en-curso"
        /// «Seguir más tarde»: se retoma en el mismo paso.
        case enPausa = "en-pausa"
        case terminado
    }

    public var fase: Fase
    /// Índice del paso en el que está.
    public var paso: Int
    /// Partes hechas («foco», «editar», «finder»…) con su fecha.
    public var partes: [String: Date]
    /// Hitos cumplidos, con su fecha.
    public var hitos: [String: Date]
    public var actualizado: Date

    public init(fase: Fase = .sinEmpezar, paso: Int = 0, partes: [String: Date] = [:], hitos: [String: Date] = [:],
                actualizado: Date = Date()) {
        self.fase = fase; self.paso = paso; self.partes = partes; self.hitos = hitos; self.actualizado = actualizado
    }

    public var partesHechas: Set<String> { Set(partes.keys) }
}

/// `tutorial.json`: un estado por recorrido. El del ejemplo va con la clave `ejemplo` (se reinstala con otro `id`);
/// el de tu empresa, con el `id` de su carpeta.
struct ArchivoTutorial: Codable, Sendable, Hashable {
    static let versionActual = 1
    var version: Int = ArchivoTutorial.versionActual
    var recorridos: [String: EstadoRecorrido] = [:]
}

/// Lee y guarda `tutorial.json` (PLAN §3.4). Si no se puede leer, empieza de cero; si no se puede guardar, lo dice
/// en el registro y sigue (el tutorial nunca impide usar la app).
@MainActor
@Observable
public final class AlmacenTutorial {
    public static let nombreFichero = "tutorial.json"
    private static let log = Logger(subsystem: "es.thelast.system", category: "Tutorial")

    /// El de la app (Application Support de verdad, o el de `TLS_APP_SUPPORT` en pruebas).
    public static let compartido = AlmacenTutorial(archivo: AppLocations.appSupport.appendingPathComponent(nombreFichero))

    public let archivo: URL
    private(set) var contenido: ArchivoTutorial

    public init(archivo: URL) {
        self.archivo = archivo
        if let data = try? Data(contentsOf: archivo),
           let leido = try? Self.decodificador.decode(ArchivoTutorial.self, from: data) {
            contenido = leido
        } else {
            contenido = ArchivoTutorial()
        }
    }

    static func clave(_ tipo: TipoRecorrido, empresa: UUID?) -> String {
        switch tipo {
        case .ejemplo: TipoRecorrido.ejemplo.rawValue
        case .tuEmpresa: (empresa?.uuidString ?? "sin-empresa").lowercased()
        }
    }

    public func estado(_ tipo: TipoRecorrido, empresa: UUID? = nil) -> EstadoRecorrido {
        contenido.recorridos[Self.clave(tipo, empresa: empresa)] ?? EstadoRecorrido()
    }

    public func cambiar(_ tipo: TipoRecorrido, empresa: UUID? = nil, _ cambio: (inout EstadoRecorrido) -> Void) {
        let k = Self.clave(tipo, empresa: empresa)
        var e = contenido.recorridos[k] ?? EstadoRecorrido()
        cambio(&e)
        e.actualizado = Date()
        contenido.recorridos[k] = e
        guardar()
    }

    /// Vuelve a empezar un recorrido (al reiniciar el ejemplo).
    public func reiniciar(_ tipo: TipoRecorrido, empresa: UUID? = nil) {
        contenido.recorridos[Self.clave(tipo, empresa: empresa)] = nil
        guardar()
    }

    private func guardar() {
        do {
            try FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.codificador.encode(contenido)
            try data.write(to: archivo, options: .atomic)
        } catch {
            Self.log.error("No se pudo guardar tutorial.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    static var codificador: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decodificador: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
