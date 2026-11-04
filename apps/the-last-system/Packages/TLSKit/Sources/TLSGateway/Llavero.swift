import Foundation
import Security

/// Dónde viven los secretos de las conexiones (PLAN §7.4 y §8): **solo** en el Llavero. Nunca en la carpeta, en
/// `conexiones.json`, en variables de entorno, en registros ni en lo que llega a un asistente.
///
/// Cuenta = `<id>.<campo>` (`ghl.token`). En pruebas, `LlaveroEnMemoria`.
public protocol AlmacenDeSecretos: Sendable {
    func guardar(_ valor: String, id: String, campo: String) throws
    func leer(id: String, campo: String) throws -> String?
    func borrar(id: String, campo: String) throws
}

extension AlmacenDeSecretos {
    /// `<id>.<campo>`.
    public static func cuenta(id: String, campo: String) -> String { "\(id).\(campo)" }

    /// Los secretos de una conexión que estén guardados (campo → valor). Solo para la pasarela, nunca para mostrar.
    func secretos(de c: Conexion) -> [String: String] {
        var out: [String: String] = [:]
        for campo in c.secretos {
            if let v = try? leer(id: c.id, campo: campo), !v.isEmpty { out[campo] = v }
        }
        return out
    }
}

/// El Llavero de inicio de sesión del usuario (`kSecClassGenericPassword`, servicio `es.thelast.system.gateway`).
///
/// ACL: un elemento creado por la app en el Llavero de inicio de sesión solo deja leerlo **sin preguntar** a la propia
/// app que lo creó (lista de aplicaciones de confianza por defecto, atada a su firma). Cualquier otro proceso —un
/// asistente en su sandbox, un programa por stdio— recibe la petición de permiso del sistema o un error. Para no
/// perder esa ACL al cambiar la clave, se actualiza el elemento en vez de borrarlo y crearlo de nuevo.
public struct LlaveroDelSistema: AlmacenDeSecretos {
    public let servicio: String

    public init(servicio: String = TLSGatewayInfo.servicioLlavero) {
        self.servicio = servicio
    }

    func base(_ id: String, _ campo: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servicio,
         kSecAttrAccount as String: Self.cuenta(id: id, campo: campo)]
    }

    public func guardar(_ valor: String, id: String, campo: String) throws {
        let datos = Data(valor.utf8)
        let q = base(id, campo)
        let estado = SecItemUpdate(q as CFDictionary, [kSecValueData as String: datos] as CFDictionary)
        if estado == errSecSuccess { return }
        guard estado == errSecItemNotFound else { throw ErrorDePasarela.llavero(estado) }
        var nuevo = q
        nuevo[kSecValueData as String] = datos
        nuevo[kSecAttrLabel as String] = "The Last System · conexión \(id)"
        nuevo[kSecAttrDescription as String] = "Clave de una conexión con otro programa"
        let alta = SecItemAdd(nuevo as CFDictionary, nil)
        guard alta == errSecSuccess else { throw ErrorDePasarela.llavero(alta) }
    }

    public func leer(id: String, campo: String) throws -> String? {
        var q = base(id, campo)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var salida: CFTypeRef?
        let estado = SecItemCopyMatching(q as CFDictionary, &salida)
        if estado == errSecItemNotFound { return nil }
        guard estado == errSecSuccess, let d = salida as? Data else { throw ErrorDePasarela.llavero(estado) }
        return String(data: d, encoding: .utf8)
    }

    public func borrar(id: String, campo: String) throws {
        let estado = SecItemDelete(base(id, campo) as CFDictionary)
        guard estado == errSecSuccess || estado == errSecItemNotFound else { throw ErrorDePasarela.llavero(estado) }
    }
}

/// Llavero falso para pruebas y vistas previas (en memoria; nada toca el disco).
public final class LlaveroEnMemoria: AlmacenDeSecretos, @unchecked Sendable {
    private let lock = NSLock()
    private var datos: [String: String] = [:]

    public init(_ inicial: [String: String] = [:]) {
        datos = inicial
    }

    public func guardar(_ valor: String, id: String, campo: String) throws {
        lock.withLock { datos[Self.cuenta(id: id, campo: campo)] = valor }
    }

    public func leer(id: String, campo: String) throws -> String? {
        lock.withLock { datos[Self.cuenta(id: id, campo: campo)] }
    }

    public func borrar(id: String, campo: String) throws {
        _ = lock.withLock { datos.removeValue(forKey: Self.cuenta(id: id, campo: campo)) }
    }

    /// Cuentas guardadas (para las pruebas).
    public var cuentas: [String] { lock.withLock { datos.keys.sorted() } }
}
