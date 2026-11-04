import Foundation

// F5 · pasarela (PLAN §7.4, §5.2, §5.4 y §8): otros programas conectados por el protocolo de herramientas (MCP).
//
// - Configuración en `conexiones.json` de Application Support, **sin secretos** (`AlmacenDeConexiones`).
// - Secretos en el Llavero (`es.thelast.system.gateway`, cuenta `<id>.<campo>`), detrás de `AlmacenDeSecretos`.
// - Transporte preferente HTTP (`HTTPClientTransport`); stdio con aviso y su propio perfil de sandbox.
// - Catálogo con huella: lectura (`readOnlyHint`) o sensible; nombres con send, publish, pay, charge, refund, invoice,
//   transfer, delete, email, sms o message, siempre sensibles; lo nuevo o cambiado queda desactivado hasta revisarlo.
// - Plantillas por conector con interruptores en lenguaje llano; la matriz técnica, solo en Avanzado.
// - Lo que llega de fuera es un dato (`{"tipo":"dato_no_confiable","origen":…}`, 20 KB como mucho, secretos ocultados).
// - Lo sensible solo sale al aprobar, por `GatewayRouter` y con los argumentos exactos aprobados.
// - Reflejo en ficheros: `Sincronizador` (una rutina por conector, sin webhooks) llama a `tls_registrar_*`.

/// Constantes de la pasarela.
public enum TLSGatewayInfo {
    /// Servicio del Llavero donde viven los secretos de las conexiones (`<id>.<campo>`).
    public static let servicioLlavero = "es.thelast.system.gateway"
    /// Nombre del fichero de configuración (en el directorio que dé la app; sin secretos).
    public static let ficheroConexiones = "conexiones.json"
    /// Prefijo de las herramientas que ven los asistentes: `ext_<servidor>_<herramienta>`.
    public static let prefijo = "ext_"
    /// Tope de lo que llega a un asistente desde otro programa (bytes del JSON).
    public static let topeDato = 20_000
    /// Tope de las descripciones de las herramientas.
    public static let topeDescripcion = 300
    /// Tope de los argumentos de una llamada (bytes del JSON canónico).
    public static let topeArgumentos = 16_000
}

/// Errores de la pasarela, con texto para la persona (sin jerga).
public enum ErrorDePasarela: Error, LocalizedError, Sendable, Hashable {
    case conexionDesconocida(String)
    case identificadorNoValido(String)
    case yaExiste(String)
    case direccionNoValida(String)
    case pareceUnSecreto(String)
    case faltaSecreto(String)
    case avisoSinAceptar
    case stdioConSecretos
    case herramientaDesconocida(String)
    case herramientaDesactivada(String)
    case herramientaCambiada(String)
    case noEsDeLectura(String)
    case noEsSensible(String)
    case argumentosNoValidos(String)
    case sinPermiso(String)
    case soloPersonas
    case programaConError(String)
    case sinRespuesta(String)
    case llavero(Int32)

    public var errorDescription: String? {
        switch self {
        case .conexionDesconocida(let id): "No hay ninguna conexión «\(id)»."
        case .identificadorNoValido(let id): "«\(id)» no vale como nombre corto: usa de 2 a 20 letras o cifras, sin espacios."
        case .yaExiste(let id): "Ya hay una conexión «\(id)»."
        case .direccionNoValida(let m): "La dirección no vale: \(m)"
        case .pareceUnSecreto(let campo): "«\(campo)» parece una clave. Las claves van en su campo y se guardan en el Llavero."
        case .faltaSecreto(let campo): "Falta la clave «\(campo)»: escríbela en la conexión."
        case .avisoSinAceptar:
            "Este programa se ejecutaría en tu Mac. Lee el aviso y acéptalo antes de conectarlo."
        case .stdioConSecretos:
            "Un programa que se ejecuta en tu Mac no puede recibir claves en esta versión. Conéctalo por internet."
        case .herramientaDesconocida(let n): "No conozco «\(n)»."
        case .herramientaDesactivada(let n): "«\(n)» está desactivada hasta que la revises."
        case .herramientaCambiada(let n): "«\(n)» cambió en el otro programa desde que se pidió: no hago nada. Revísala y vuelve a pedirlo."
        case .noEsDeLectura(let n): "«\(n)» cambia cosas en el otro programa: necesita tu aprobación."
        case .noEsSensible(let n): "«\(n)» solo lee: no necesita aprobación."
        case .argumentosNoValidos(let m): "Los datos de la petición no valen: \(m)"
        case .sinPermiso(let m): m
        case .soloPersonas: "Esto solo lo puede hacer una persona."
        case .programaConError(let m): "El otro programa respondió con un error: \(m)"
        case .sinRespuesta(let nombre): "\(nombre) no responde. Prueba más tarde."
        case .llavero(let s): "No he podido usar el Llavero (código \(s))."
        }
    }
}
