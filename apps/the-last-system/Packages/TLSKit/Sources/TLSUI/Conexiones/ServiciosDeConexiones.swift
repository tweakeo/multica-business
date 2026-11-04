import AppKit
import Foundation
import TLSCore

// F5 · rol conexiones (PLAN §7, §8 «Permisos (TCC)», §6.7 paso 7). Lo que la pantalla Conexiones necesita de Mail, del
// Calendario y de los otros programas, en tipos propios de TLSUI: TLSUI no depende de TLSIntegrations ni de TLSGateway
// (y en la fase de pantallas nadie toca `Package.swift`), así que la integración (`TLSIntegracion`/la app) da, por
// empresa abierta con escritor, un adaptador que cumple `ServiciosDeConexiones` con `PuertaDePermisos`,
// `CuentasDeMail`, `AjustesDeCorreo`, `ConexionDelCartero`, `SincronizadorCalendario` y `Pasarela` (la tabla de
// correspondencias está en docs/F5-CONTRATOS.md › «Cambios pedidos › conexiones»).
//
// Reglas que la pantalla no rompe:
// - El permiso del sistema solo se pide tras enseñar su explicación (`explicar` → `pedir(_:tras:)`); denegado o
//   restringido → pantalla de recuperación, sin volver a preguntar.
// - La clave de otro programa va del campo de la pantalla al Llavero (`anadir`) y no vuelve nunca: ningún tipo de aquí
//   la devuelve, y el modelo la olvida en cuanto la entrega.
// - Nada de aquí envía, invita ni paga: Mail solo lee y abre redacciones al aprobar; el Calendario no pone invitados;
//   lo sensible de otros programas pide siempre tu OK («Siempre con tu OK»).

/// Un permiso del sistema que pide Conexiones (los avisos los lleva `PreferenciasPresencia`, de F4).
public enum PermisoDeConexion: String, Sendable, Hashable, CaseIterable {
    case mail
    case calendario
}

/// Estado de un permiso del sistema (el de `EstadoDePermiso`, TLSIntegrations).
public enum EstadoDePermisoConexion: String, Sendable, Hashable {
    case sinPreguntar, concedido, denegado, restringido, desconocido

    public var necesitaRecuperacion: Bool { self == .denegado || self == .restringido }
}

/// La explicación previa al aviso de macOS (`ExplicacionDePermiso`).
public struct ExplicacionDeConexion: Sendable, Hashable {
    public var titulo: String
    public var para: String
    public var hace: [String]
    public var nunca: [String]
    public var queVeras: String
    public var boton: String

    public init(titulo: String, para: String, hace: [String], nunca: [String], queVeras: String, boton: String = "Continuar") {
        self.titulo = titulo; self.para = para; self.hace = hace; self.nunca = nunca; self.queVeras = queVeras; self.boton = boton
    }
}

/// La pantalla de recuperación de un permiso denegado (`RecuperacionDePermiso` o `TarjetaDePermiso`).
public struct RecuperacionDeConexion: Sendable, Hashable {
    public var titulo: String
    public var texto: String
    public var pasos: [String]
    public var boton: String
    /// Enlace a Ajustes del Sistema (lo abre la app; en pruebas, se apunta).
    public var enlace: URL
    /// Código del error, solo para «Detalle técnico».
    public var detalleTecnico: String?

    public init(titulo: String, texto: String, pasos: [String], boton: String = "Abrir Ajustes del Sistema", enlace: URL,
                detalleTecnico: String? = nil) {
        self.titulo = titulo; self.texto = texto; self.pasos = pasos; self.boton = boton; self.enlace = enlace
        self.detalleTecnico = detalleTecnico
    }
}

/// Qué enseñar de un permiso ahora mismo (`SituacionDePermiso`).
public enum SituacionDeConexion: Sendable, Hashable {
    case listo
    case explicar(ExplicacionDeConexion)
    case recuperar(RecuperacionDeConexion)
    /// No se sabe ahora (Mail cerrado…): se vuelve a mirar sin preguntar.
    case sinComprobar
}

/// Constancia de que la explicación se enseñó: el adaptador la cambia por la `ExplicacionVista` de `PuertaDePermisos`.
/// Sirve una sola vez.
public struct PermisoExplicado: Sendable, Hashable {
    public let permiso: PermisoDeConexion
    public let explicacion: ExplicacionDeConexion
    public let id: UUID

    public init(permiso: PermisoDeConexion, explicacion: ExplicacionDeConexion, id: UUID = UUID()) {
        self.permiso = permiso; self.explicacion = explicacion; self.id = id
    }
}

// MARK: Mail

/// Las cuentas de Mail (`CuentasDeMail.Resultado`).
public enum CuentasDeMailConexion: Sendable, Hashable {
    case cuentas([String])
    case mailCerrado
    case sinPermiso(RecuperacionDeConexion)
    case fallo(String)
}

/// Un remitente o dominio privado (`RemitentePrivado`): del correo que coincide solo se apunta «correo privado de
/// <etiqueta>».
public struct RemitentePrivadoConexion: Sendable, Hashable, Identifiable {
    public var id: String { patron }
    /// `persona@dominio`, `@dominio` o `dominio` (con sus subdominios).
    public var patron: String
    /// Lo único que verá el Cartero («Expediente privado»).
    public var etiqueta: String

    public init(patron: String, etiqueta: String) { self.patron = patron; self.etiqueta = etiqueta }
}

/// Lo que se guarda de Mail (`AjustesDeCorreo`, en el estado de la app: nunca en la carpeta).
public struct AjustesDeMailConexion: Sendable, Hashable {
    /// La cuenta que mira el Cartero (por su nombre en Mail).
    public var cuenta: String?
    public var privados: [RemitentePrivadoConexion]

    public init(cuenta: String? = nil, privados: [RemitentePrivadoConexion] = []) {
        self.cuenta = cuenta; self.privados = privados
    }
}

// MARK: Calendario

/// Cómo quedó conectar el Calendario (`SincronizadorCalendario.conectar()` y la primera `sincronizar`).
public enum CalendarioConexion: Sendable, Hashable {
    /// Hay permiso y existe el calendario «The Last System». `resumen`: lo que se puso («2 rituales y 3 sesiones»).
    case conectado(resumen: String?)
    case sinConectar
    case sinPermiso(RecuperacionDeConexion)
    case fallo(String)
}

// MARK: Otros programas

/// Una plantilla de conector (`PlantillaDeConector`): lo que pide y qué interruptores enseñará.
public struct PlantillaDeOtroPrograma: Sendable, Hashable, Identifiable {
    public let id: String
    public let nombre: String
    public let explicacion: String
    public let direccionDeEjemplo: String
    /// El campo de la clave (`nil`: no pide clave).
    public let clave: CampoDeClave?
    /// Los interruptores que tendrá, ya en llano («El Comercial puede leer contactos de GoHighLevel»).
    public let permisos: [String]

    public init(id: String, nombre: String, explicacion: String, direccionDeEjemplo: String,
                clave: CampoDeClave? = CampoDeClave(),
                permisos: [String]) {
        self.id = id; self.nombre = nombre; self.explicacion = explicacion; self.direccionDeEjemplo = direccionDeEjemplo
        self.clave = clave; self.permisos = permisos
    }
}

/// El campo de la clave de una plantilla (`CampoDeConexion` con `secreto`).
public struct CampoDeClave: Sendable, Hashable {
    public let etiqueta: String
    public let ayuda: String

    public init(etiqueta: String = "Clave de acceso", ayuda: String = "Se guarda en el Llavero de tu Mac. Ningún asistente la ve.") {
        self.etiqueta = etiqueta; self.ayuda = ayuda
    }
}

/// Cómo se habla con el otro programa.
public enum TransporteDeOtroPrograma: Sendable, Hashable {
    /// Por internet (`https://…` o `http://localhost…`).
    case web(direccion: String)
    /// Un programa de este Mac, en su caja: solo con el aviso aceptado y sin claves (v1).
    case local(ejecutable: String, argumentos: [String], avisoAceptado: Bool)
}

/// Dar de alta un programa (`Pasarela.anadir`). La clave solo viaja aquí, hacia el Llavero.
public struct AltaDeOtroPrograma: Sendable, Hashable {
    public var id: String
    public var nombre: String
    public var plantilla: String
    public var transporte: TransporteDeOtroPrograma
    /// La clave tal cual la pegó la persona (`nil` o vacía: sin clave).
    public var clave: String?

    public init(id: String, nombre: String, plantilla: String, transporte: TransporteDeOtroPrograma, clave: String?) {
        self.id = id; self.nombre = nombre; self.plantilla = plantilla; self.transporte = transporte; self.clave = clave
    }
}

/// Cómo está un programa conectado.
public enum EstadoDeOtroPrograma: Sendable, Hashable {
    case conectado
    /// Aún no se ha probado (sin catálogo).
    case sinProbar
    /// Lo pausaste (`activa: false`).
    case pausado
    case error(String)
}

/// Un programa conectado, tal como se enseña (`Conexion` sin secretos ni direcciones con datos).
public struct OtroProgramaConexion: Sendable, Hashable, Identifiable {
    public let id: String
    public var nombre: String
    public var plantilla: String
    public var estado: EstadoDeOtroPrograma
    /// Herramientas activas y por revisar.
    public var activas: Int
    public var porRevisar: Int
    public var ultimaSincronizacion: Date?
    /// «Por internet» o «Programa de este Mac».
    public var local: Bool
    /// F5 · integración: un programa de mentira (el del ejemplo): nada sale de tu Mac.
    public var simulado: Bool

    public init(id: String, nombre: String, plantilla: String, estado: EstadoDeOtroPrograma, activas: Int = 0, porRevisar: Int = 0,
                ultimaSincronizacion: Date? = nil, local: Bool = false, simulado: Bool = false) {
        self.id = id; self.nombre = nombre; self.plantilla = plantilla; self.estado = estado; self.activas = activas
        self.porRevisar = porRevisar; self.ultimaSincronizacion = ultimaSincronizacion; self.local = local
        self.simulado = simulado
    }
}

/// Un interruptor en llano (`FilaDeInterruptor`).
public struct InterruptorDeOtroPrograma: Sendable, Hashable, Identifiable {
    public let id: String
    /// «El Comercial puede leer contactos de GoHighLevel».
    public let texto: String
    public let encendido: Bool
    /// Hay herramientas activas a las que se refiere.
    public let disponible: Bool
    public let asistenteActivo: Bool
    /// Solo lee (si no, lo que haga pide siempre tu OK).
    public let lectura: Bool
    /// Nombres visibles de las herramientas a las que se refiere.
    public let herramientas: [String]

    public init(id: String, texto: String, encendido: Bool, disponible: Bool, asistenteActivo: Bool, lectura: Bool,
                herramientas: [String] = []) {
        self.id = id; self.texto = texto; self.encendido = encendido; self.disponible = disponible
        self.asistenteActivo = asistenteActivo; self.lectura = lectura; self.herramientas = herramientas
    }
}

/// Una herramienta nueva o cambiada por revisar.
public struct HerramientaNueva: Sendable, Hashable, Identifiable {
    public var id: String { nombre }
    public let nombre: String
    public let descripcion: String
    /// `ClaseExterna.texto` («Solo lee» · «Cambia cosas: pide tu OK»).
    public let clase: String
    /// `MotivoDeClase.texto`.
    public let motivo: String
    public let sensible: Bool

    public init(nombre: String, descripcion: String, clase: String, motivo: String, sensible: Bool) {
        self.nombre = nombre; self.descripcion = descripcion; self.clase = clase; self.motivo = motivo; self.sensible = sensible
    }
}

/// La tarjeta «Revisar herramientas nuevas» (`TarjetaDeRevision`).
public struct RevisionDeOtroPrograma: Sendable, Hashable, Identifiable {
    /// `conexion-revisar:<id>:<huella>`.
    public let id: String
    public let conexion: String
    public let nombreConexion: String
    public let titulo: String
    public let herramientas: [HerramientaNueva]

    public init(id: String, conexion: String, nombreConexion: String, titulo: String, herramientas: [HerramientaNueva]) {
        self.id = id; self.conexion = conexion; self.nombreConexion = nombreConexion; self.titulo = titulo
        self.herramientas = herramientas
    }
}

/// Una fila de la matriz técnica (`FilaDeMatriz`), solo en Ajustes › Avanzado.
public struct FilaDeMatrizConexion: Sendable, Hashable, Identifiable {
    public var id: String { expuesta }
    public let expuesta: String
    public let nombre: String
    public let clase: String
    public let motivo: String
    public let estado: String
    public let huellaCorta: String
    /// Asistente → la tiene permitida.
    public let asistentes: [String: Bool]

    public init(expuesta: String, nombre: String, clase: String, motivo: String, estado: String, huellaCorta: String,
                asistentes: [String: Bool]) {
        self.expuesta = expuesta; self.nombre = nombre; self.clase = clase; self.motivo = motivo; self.estado = estado
        self.huellaCorta = huellaCorta; self.asistentes = asistentes
    }
}

/// Error con un texto para la persona (lo que devuelvan las piezas del núcleo, ya en llano).
public struct ErrorDeConexion: Error, Sendable, Hashable, LocalizedError {
    public let texto: String
    public init(_ texto: String) { self.texto = texto }
    public var errorDescription: String? { texto }
}

// MARK: El puerto

/// Lo que Conexiones pide a la app, por empresa abierta con escritor. Lo cumple el adaptador de la integración; en
/// pruebas, capturas y el ejemplo, `ServiciosDeConexionesEnMemoria`. Lo que escribe en la carpeta (el Cartero, los
/// interruptores) lo hace **como la persona**, por el `CommandBus`, y se deshace.
public protocol ServiciosDeConexiones: Sendable {
    // Permisos del sistema (`PuertaDePermisos`): nunca se pide sin la explicación.
    func situacion(_ p: PermisoDeConexion) async -> SituacionDeConexion
    func explicar(_ p: PermisoDeConexion) async -> PermisoExplicado
    func pedir(_ p: PermisoDeConexion, tras: PermisoExplicado) async throws -> EstadoDePermisoConexion

    // Mail
    func cuentasDeMail() async -> CuentasDeMailConexion
    func ajustesDeMail() async -> AjustesDeMailConexion
    func guardarAjustesDeMail(_ a: AjustesDeMailConexion) async throws
    func carteroActivo() async -> Bool
    /// `ConexionDelCartero.activar(_:bus:autor: .persona)`.
    func activarCartero(_ activo: Bool) async throws

    // Calendario
    func estadoDelCalendario() async -> CalendarioConexion
    /// Tras el permiso concedido: crea (o recupera) «The Last System» y sincroniza.
    func conectarCalendario() async -> CalendarioConexion
    /// F5 · corrector (P2-7): la app deja de usar el Calendario (no borra nada allí).
    func desconectarCalendario() async throws

    // Otros programas
    func plantillas() -> [PlantillaDeOtroPrograma]
    func otrosProgramas() async -> [OtroProgramaConexion]
    func anadir(_ alta: AltaDeOtroPrograma) async throws
    /// Conecta y lee su catálogo: una frase con lo que trae («4 herramientas: 3 solo leen, 1 pide tu OK»).
    func probar(_ id: String) async throws -> String
    func interruptores(_ id: String) async -> [InterruptorDeOtroPrograma]
    func cambiarInterruptor(_ id: String, permiso: String, encender: Bool) async throws
    func revisiones() async -> [RevisionDeOtroPrograma]
    func revisar(_ r: RevisionDeOtroPrograma, aceptar: Bool) async throws
    /// «Sincronizar ahora»: `InformeDeSincronizacion.resumen`.
    func sincronizarAhora(_ id: String) async throws -> String
    func pausar(_ id: String, _ pausado: Bool) async throws
    func quitar(_ id: String) async throws
    func matriz(_ id: String) async -> [FilaDeMatrizConexion]

    /// F5 · integración: en el ejemplo (Ribera), Mail y Calendario no se conectan. Devuelve por qué (en llano), o `nil`
    /// si se pueden conectar.
    func enEjemplo(_ p: PermisoDeConexion) async -> String?
}

public extension ServiciosDeConexiones {
    func enEjemplo(_ p: PermisoDeConexion) async -> String? { nil }
    func desconectarCalendario() async throws { throw ErrorDeConexion("Aquí no se puede desconectar el Calendario.") }
}

/// Cómo llega el puerto a las pantallas: la integración pone la fábrica al arrancar (por id de empresa). Sin ella,
/// Conexiones enseña Claude Code, Banco, Avisos y «Trabajar con la ventana cerrada», y lo demás como «Ahora no» con
/// su explicación.
@MainActor
public enum ConexionesDeLaApp {
    /// `id` de la empresa → sus servicios (`nil` sin escritor o sin integración). Por defecto, los que la integración
    /// registra al montar las conexiones de cada empresa abierta (`registrar`) y quita al pararlas.
    public static var fabrica: (@MainActor (UUID) -> (any ServiciosDeConexiones)?)? = { registrados[$0] }

    private static var registrados: [UUID: any ServiciosDeConexiones] = [:]

    /// F5 · integración: las conexiones de una empresa quedaron montadas (con su escritor).
    public static func registrar(_ s: any ServiciosDeConexiones, para empresa: UUID) {
        registrados[empresa] = s
    }

    /// F5 · integración: las conexiones de esa empresa se pararon (solo si siguen siendo estas).
    public static func quitar(para empresa: UUID, _ s: (any ServiciosDeConexiones)? = nil) {
        guard let actual = registrados[empresa] else { return }
        if let s, (actual as AnyObject) !== (s as AnyObject) { return }
        registrados[empresa] = nil
    }

    /// Abre un enlace de Ajustes del Sistema (`NSWorkspace` en la app; las pruebas ponen otro).
    public static var abrirEnlace: @MainActor (URL) -> Void = { url in
        guard PreferenciasPresencia.esLaApp else { return }
        NSWorkspace.shared.open(url)
    }

    static func servicios(_ id: UUID) -> (any ServiciosDeConexiones)? { fabrica?(id) }
}
