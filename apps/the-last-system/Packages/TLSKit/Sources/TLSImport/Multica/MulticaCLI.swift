import Foundation

// Importar las tareas abiertas de Multica (PLAN §9 F3, «Si dices sí»). Solo lectura: la app lanza el programa de
// Multica de la persona con órdenes de listar y nunca con ninguna que cambie algo. Las órdenes posibles son un
// `enum` cerrado (`OrdenMultica`): no hay forma de pasarle otros argumentos.

/// El programa de Multica que hay en este Mac (en el PATH o dentro de Multica.app). Encontrarlo no lo ejecuta.
public struct MulticaCLI: Sendable, Hashable {
    public let ejecutable: URL

    public init(ejecutable: URL) { self.ejecutable = ejecutable }

    /// Dentro de la app de escritorio de Multica.
    public static let rutaEnLaApp = "/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica"

    /// Carpetas habituales de programas de línea de órdenes. Una app abierta desde el Finder hereda un PATH
    /// corto, así que se miran también.
    public static let carpetasHabituales = ["/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/bin"]

    /// Busca `multica`: primero en el PATH, luego en las carpetas habituales y por último dentro de Multica.app.
    /// Solo comprueba que el fichero exista y se pueda ejecutar; no lo lanza.
    public static func localizar(path: String? = ProcessInfo.processInfo.environment["PATH"],
                                 extra: [String] = MulticaCLI.carpetasHabituales,
                                 enLaApp: [String] = [MulticaCLI.rutaEnLaApp],
                                 casa: URL = FileManager.default.homeDirectoryForCurrentUser) -> MulticaCLI? {
        var carpetas = (path ?? "").split(separator: ":").map(String.init)
        carpetas += extra
        var vistas = Set<String>()
        var candidatos: [String] = []
        for c in carpetas where !c.isEmpty {
            let dir = c.hasPrefix("~/") ? casa.appendingPathComponent(String(c.dropFirst(2))).path : c
            let ruta = URL(fileURLWithPath: dir).appendingPathComponent("multica").standardizedFileURL.path
            if vistas.insert(ruta).inserted { candidatos.append(ruta) }
        }
        candidatos += enLaApp
        let fm = FileManager.default
        for ruta in candidatos {
            var dir: ObjCBool = false
            if fm.fileExists(atPath: ruta, isDirectory: &dir), !dir.boolValue, fm.isExecutableFile(atPath: ruta) {
                return MulticaCLI(ejecutable: URL(fileURLWithPath: ruta))
            }
        }
        return nil
    }
}

/// Las únicas órdenes que la app le da a Multica. Todas leen; ninguna cambia nada en la cuenta.
public enum OrdenMultica: Sendable, Hashable {
    /// Perfiles configurados.
    case perfiles
    /// Espacios de trabajo de un perfil (`multica --profile <p> workspace list`), en JSON o en texto.
    case espacios(perfil: String, json: Bool)
    /// Una página de tareas de un espacio de trabajo.
    case tareas(perfil: String, espacio: String, desde: Int, limite: Int)

    /// Campos que se piden de cada tarea.
    public static let campos = "identifier,title,description,status,status_category,priority,due_date,created_at"

    public var argumentos: [String] {
        switch self {
        case .perfiles:
            ["profile", "list", "--output", "json"]
        case .espacios(let p, let json):
            ["--profile", p, "workspace", "list"] + (json ? ["--output", "json"] : [])
        case .tareas(let p, let e, let desde, let limite):
            ["--profile", p, "--workspace-id", e, "issue", "list", "--output", "json",
             "--limit", String(limite), "--offset", String(desde), "--fields", Self.campos]
        }
    }
}

/// Quien lanza las órdenes. En pruebas, un programa falso que devuelve JSON inventado.
public protocol EjecutorMultica: Sendable {
    /// Lanza la orden y devuelve lo que escribió en la salida estándar. Lanza `ErrorMultica` si falla.
    func ejecutar(_ orden: OrdenMultica) async throws -> Data
}

/// Problemas al hablar con Multica, en texto llano.
public enum ErrorMultica: Error, LocalizedError, Sendable, Equatable {
    case noEncontrado
    /// El programa terminó con error. `detalle`: las primeras líneas de su error, para «Detalle técnico».
    case fallo(codigo: Int32, detalle: String)
    case sinRespuesta
    case respuestaIlegible
    case perfilVacio
    case espacioVacio

    public var errorDescription: String? {
        switch self {
        case .noEncontrado:
            "No encuentro Multica en este Mac. Si lo usas, abre su app una vez o instala su programa de línea de órdenes."
        case .fallo:
            "Multica no ha podido darme la lista. Comprueba en su app que la sesión sigue abierta y vuelve a intentarlo."
        case .sinRespuesta:
            "Multica tarda demasiado en responder. Vuelve a intentarlo en un momento."
        case .respuestaIlegible:
            "No entiendo lo que ha devuelto Multica. Puede que su versión sea distinta de la que conozco."
        case .perfilVacio:
            "Escribe el nombre del perfil de Multica."
        case .espacioVacio:
            "Elige un espacio de trabajo de Multica."
        }
    }
}

/// Lanza el programa de Multica de verdad (con la sesión de la persona). Solo con `OrdenMultica`.
public struct ProcesoMultica: EjecutorMultica {
    public let cli: MulticaCLI
    public var tiempoMaximo: Duration

    public init(cli: MulticaCLI, tiempoMaximo: Duration = .seconds(60)) {
        self.cli = cli
        self.tiempoMaximo = tiempoMaximo
    }

    public func ejecutar(_ orden: OrdenMultica) async throws -> Data {
        let resultado = try await Self.lanzar(cli.ejecutable, argumentos: orden.argumentos, tiempoMaximo: tiempoMaximo)
        guard resultado.codigo == 0 else {
            throw ErrorMultica.fallo(codigo: resultado.codigo, detalle: Self.resumen(resultado.error))
        }
        return resultado.salida
    }

    /// Las primeras líneas de un error, sin pasar de 300 caracteres.
    static func resumen(_ datos: Data) -> String {
        let texto = String(decoding: datos, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let lineas = texto.split(whereSeparator: \.isNewline).prefix(3).joined(separator: " · ")
        return lineas.count > 300 ? String(lineas.prefix(297)) + "…" : lineas
    }

    struct Resultado: Sendable {
        let codigo: Int32
        let salida: Data
        let error: Data
    }

    /// Lanza el programa sin entrada, recoge su salida y su error a la vez (sin bloquearse con salidas grandes) y
    /// lo para si pasa del tiempo máximo.
    static func lanzar(_ ejecutable: URL, argumentos: [String], tiempoMaximo: Duration) async throws -> Resultado {
        let proceso = Process()
        proceso.executableURL = ejecutable
        proceso.arguments = argumentos
        proceso.standardInput = FileHandle.nullDevice
        let salida = Pipe()
        let error = Pipe()
        proceso.standardOutput = salida
        proceso.standardError = error
        do {
            try proceso.run()
        } catch {
            throw ErrorMultica.noEncontrado
        }
        async let datosSalida = leerHastaElFinal(salida.fileHandleForReading)
        async let datosError = leerHastaElFinal(error.fileHandleForReading)
        let limite = ContinuousClock.now.advanced(by: tiempoMaximo)
        var aTiempo = true
        while proceso.isRunning {
            if Task.isCancelled || ContinuousClock.now >= limite {
                aTiempo = false
                proceso.terminate()
                break
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        let (s, e) = await (datosSalida, datosError)
        while proceso.isRunning { try? await Task.sleep(for: .milliseconds(10)) }
        guard aTiempo else { throw ErrorMultica.sinRespuesta }
        return Resultado(codigo: proceso.terminationStatus, salida: s, error: e)
    }

    /// Lee una tubería hasta que el programa la cierra, fuera del grupo de hilos de Swift.
    static func leerHastaElFinal(_ h: FileHandle) async -> Data {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                c.resume(returning: (try? h.readToEnd()) ?? Data())
            }
        }
    }
}
