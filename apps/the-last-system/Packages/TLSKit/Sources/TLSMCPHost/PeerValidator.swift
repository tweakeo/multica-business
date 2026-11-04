import Darwin
import Foundation
import Security
import TLSMCPShared

/// Quién está al otro lado del socket.
public struct PeerInfo: Sendable, Hashable {
    public let uid: uid_t
    public let pid: pid_t
    /// Identificador de firma (`es.thelast.system.tls-mcp`), si se pudo leer.
    public let identificador: String?
}

/// Por qué se rechaza una conexión (va a la auditoría; al otro lado no se le explica nada).
public enum RechazoDePeer: Error, Sendable, Hashable, CustomStringConvertible {
    case sinCredenciales(String)
    case otroUsuario(uid_t)
    case firmaNoValida(String)
    case sinRequisito

    public var description: String {
        switch self {
        case .sinCredenciales(let s): "sin credenciales del otro proceso (\(s))"
        case .otroUsuario(let u): "otro usuario (uid \(u))"
        case .firmaNoValida(let s): "firma no válida (\(s))"
        case .sinRequisito: "la app no tiene requisito de firma con que comprobar"
        }
    }
}

/// Comprueba el proceso que se conecta al socket (PLAN §5.4):
/// 1. `getpeereid`: mismo usuario;
/// 2. `LOCAL_PEERTOKEN` → `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)` → `SecCodeCheckValidity` con el
///    requisito del equipo de la app e identificador `es.thelast.system.tls-mcp`;
/// 3. el token de la ejecución lo comprueba después `MCPHost` (primer mensaje).
public struct PeerValidator: Sendable {
    public enum Firma: Sendable, Hashable {
        /// Requisito de firma (lenguaje de requisitos de `codesign`).
        case requisito(String)
        /// **Solo pruebas:** no se mira la firma (sí el usuario y el token). La app nunca lo usa.
        case sinComprobarFirma
    }

    public var uid: uid_t
    public var firma: Firma

    public init(uid: uid_t = getuid(), firma: Firma) {
        self.uid = uid; self.firma = firma
    }

    /// Validador de la app: requisito de su equipo (o, firmada ad hoc, la huella exacta del `tls-mcp` de su bundle).
    /// Sin ninguno de los dos no acepta a nadie (`sinRequisito`).
    public static func deLaApp(bundle: URL = Bundle.main.bundleURL) -> PeerValidator {
        let helper = bundle.appendingPathComponent("Contents/Helpers/tls-mcp")
        if let r = requisito(equipo: equipoPropio(), cdhash: cdhash(de: helper)) {
            return PeerValidator(firma: .requisito(r))
        }
        return PeerValidator(firma: .requisito(""))
    }

    /// `identifier "es.thelast.system.tls-mcp" and anchor apple generic and certificate leaf[subject.OU] = "<equipo>"`,
    /// o con firma ad hoc, `identifier … and cdhash H"<huella>"`. `nil` sin equipo ni huella.
    public static func requisito(equipo: String?, cdhash: String?, identificador: String = TLSMCPInfo.helperIdentifier) -> String? {
        let id = "identifier \"\(identificador)\""
        if let e = equipo, !e.isEmpty, e.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return "\(id) and anchor apple generic and certificate leaf[subject.OU] = \"\(e)\""
        }
        if let h = cdhash, !h.isEmpty, h.allSatisfy(\.isHexDigit) {
            return "\(id) and cdhash H\"\(h)\""
        }
        return nil
    }

    /// Equipo con el que está firmada esta app (`nil` si es ad hoc o no está firmada).
    public static func equipoPropio() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return informacion(staticCode)?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Huella (cdhash) de un binario en disco.
    public static func cdhash(de url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              let unique = informacion(staticCode)?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    static func informacion(_ code: SecStaticCode) -> [String: Any]? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return info as? [String: Any]
    }

    // MARK: Comprobar

    /// Valida el proceso al otro lado de un socket aceptado.
    public func validar(descriptor fd: Int32) -> Result<PeerInfo, RechazoDePeer> {
        var euid: uid_t = 0
        var egid: gid_t = 0
        guard getpeereid(fd, &euid, &egid) == 0 else { return .failure(.sinCredenciales("getpeereid")) }
        guard euid == uid else { return .failure(.otroUsuario(euid)) }
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        if getsockopt(fd, Self.solLocal, Self.localPeerPID, &pid, &pidLen) != 0 { pid = 0 }
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, Self.solLocal, Self.localPeerToken, &token, &len) == 0 else {
            return .failure(.sinCredenciales("LOCAL_PEERTOKEN"))
        }
        let tokenData = withUnsafeBytes(of: &token) { Data($0.prefix(Int(len))) }
        switch firma {
        case .sinComprobarFirma:
            return .success(PeerInfo(uid: euid, pid: pid, identificador: Self.identificador(auditToken: tokenData)))
        case .requisito(let texto):
            guard !texto.isEmpty else { return .failure(.sinRequisito) }
            switch Self.comprobarFirma(auditToken: tokenData, requisito: texto) {
            case .success(let id): return .success(PeerInfo(uid: euid, pid: pid, identificador: id))
            case .failure(let r): return .failure(r)
            }
        }
    }

    /// `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)` + `SecCodeCheckValidity`.
    static func comprobarFirma(auditToken: Data, requisito: String) -> Result<String?, RechazoDePeer> {
        guard let code = guestCode(auditToken) else { return .failure(.firmaNoValida("no se pudo identificar el proceso")) }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requisito as CFString, [], &req) == errSecSuccess, let req else {
            return .failure(.firmaNoValida("requisito ilegible"))
        }
        let status = SecCodeCheckValidity(code, [], req)
        guard status == errSecSuccess else { return .failure(.firmaNoValida("OSStatus \(status)")) }
        return .success(identificador(code))
    }

    static func guestCode(_ auditToken: Data) -> SecCode? {
        let attrs = [kSecGuestAttributeAudit: auditToken] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess else { return nil }
        return code
    }

    static func identificador(auditToken: Data) -> String? {
        guestCode(auditToken).flatMap(identificador)
    }

    static func identificador(_ code: SecCode) -> String? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return informacion(staticCode)?[kSecCodeInfoIdentifier as String] as? String
    }

    // `sys/un.h`: SOL_LOCAL 0, LOCAL_PEERPID 0x002, LOCAL_PEERTOKEN 0x006.
    static let solLocal: Int32 = 0
    static let localPeerPID: Int32 = 0x002
    static let localPeerToken: Int32 = 0x006
}
