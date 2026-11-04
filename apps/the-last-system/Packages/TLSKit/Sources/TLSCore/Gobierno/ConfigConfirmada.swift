import Foundation
import Synchronization

// Configuración confirmada (PLAN §4.5): los asistentes trabajan con la última versión de `.tls/config.yaml` que aceptó
// una persona (o que escribió la propia app), guardada con su SHA-256 en `estado.sqlite.config_confirmada`. Si el
// fichero cambia fuera de la app (Obsidian, Finder), lo que restringe se aplica ya (apagar, pausar, marcar privado,
// bajar un modo) y lo que amplía espera a que lo confirmes con la tarjeta «Cambiaron los permisos de X fuera de la app».

/// Cómo está la configuración de los asistentes ahora.
public struct EstadoDeConfig: Sendable, Hashable {
    /// La última confirmada.
    public let confirmada: ConfigAgentes
    /// La que hay en el fichero.
    public let actual: ConfigAgentes
    /// La que se aplica: la confirmada, con lo más restrictivo de la actual mientras no se confirme.
    public let efectiva: ConfigAgentes
    public let hashConfirmado: String?
    /// `nil` si el fichero no existe o no se puede leer sin descargarlo.
    public let hashActual: String?
    /// Lo que cambió fuera de la app (`agente:<slug>`, `interruptor`, `pausa`, `privado`, `funciones`, `avisos`).
    /// Vacío si está al día.
    public let cambios: [String]
    /// El fichero existe pero no se entiende: se sigue con la confirmada.
    public let ilegible: Bool

    /// Hay algo que confirmar.
    public var cambiadaFuera: Bool { !cambios.isEmpty || ilegible }

    /// Asistentes cuyos permisos cambiaron fuera de la app.
    public var asistentesCambiados: [String] {
        cambios.filter { $0.hasPrefix("agente:") }.map { String($0.dropFirst("agente:".count)) }
    }

    /// «Cambiaron los permisos de Comercial fuera de la app: confirmar».
    public var tituloTarjeta: String {
        if ilegible { return "No entiendo la configuración de los asistentes: siguen con la última que confirmaste" }
        let nombres = asistentesCambiados.map(AsistenteConfigurado.nombre(de:))
        let quien: String
        switch nombres.count {
        case 0: quien = "los asistentes"
        case 1: quien = nombres[0]
        default: quien = nombres.dropLast().joined(separator: ", ") + " y " + nombres.last!
        }
        return "Cambiaron los permisos de \(quien) fuera de la app: confirmar"
    }
}

/// Lee y confirma la configuración de los asistentes de una carpeta.
public final class ConfigConfirmada: Sendable {
    public static let ruta = VaultPath(VaultLayout.configFile)

    public let root: URL
    public let estado: EstadoGobierno
    /// Último estado calculado, por (huella del fichero, huella confirmada): no se vuelve a leer el YAML si nada cambió.
    private let cache = Mutex<(clave: String, estado: EstadoDeConfig)?>(nil)

    public init(root: URL, estado: EstadoGobierno) {
        self.root = root.standardizedFileURL
        self.estado = estado
    }

    /// Texto del fichero tal como está (sin descargar nada de iCloud). `.ausente` si no existe.
    enum Lectura: Sendable { case ausente, ilegible, texto(String, bruto: String) }

    /// El texto (sin BOM) y la huella de los bytes tal cual (la que apunta el escritor).
    func leerDisco() -> Lectura {
        UbiquityInspector.withoutMaterializing {
            let url = Self.ruta.url(in: root)
            guard let info = UbiquityInspector.info(url) else { return .ausente }
            guard !info.isSymlink, !info.isDirectory, !info.dataless,
                  let data = try? Data(contentsOf: url, options: [.uncached]),
                  let t = String(data: data, encoding: .utf8) else { return .ilegible }
            return .texto(t.hasPrefix("\u{FEFF}") ? String(t.dropFirst()) : t, bruto: ContentHash.of(data))
        }
    }

    /// Estado de la configuración. La primera vez que se mira una carpeta, la versión del fichero queda confirmada
    /// (la escribió la app al crear la copia o en la puesta en marcha). Si lo único que cambió fuera no toca a los
    /// asistentes (`hoy`, `vocabulario`…), se confirma solo.
    public func leer(ahora: Date = Date()) -> EstadoDeConfig {
        let disco = leerDisco()
        let clave: String? = {
            guard let c = try? estado.configConfirmada() else { return nil }
            switch disco {
            case .ausente: return "ausente|" + c.hash
            case .ilegible: return nil
            case .texto(_, let bruto): return bruto + "|" + c.hash
            }
        }()
        if let clave, let guardado = cache.withLock({ $0 }), guardado.clave == clave { return guardado.estado }
        let r = calcular(disco, ahora: ahora)
        if let clave, r.hashConfirmado.map({ clave.hasSuffix("|" + $0) }) ?? false {
            cache.withLock { $0 = (clave, r) }
        }
        return r
    }

    func calcular(_ disco: Lectura, ahora: Date) -> EstadoDeConfig {
        var confirmada = try? estado.configConfirmada()
        if confirmada == nil {
            let texto: String? = switch disco {
            case .ausente: ""
            case .texto(let t, _): ConfigAgentes.leer(yaml: t).ilegible ? nil : t
            case .ilegible: nil
            }
            if let texto { confirmada = try? estado.confirmarConfig(texto: texto, por: "primera lectura", fecha: ahora) }
        }
        let base = confirmada.map { ConfigAgentes.leer(yaml: $0.texto) } ?? .vacia
        switch disco {
        case .ilegible:
            return EstadoDeConfig(confirmada: base, actual: base, efectiva: base, hashConfirmado: confirmada?.hash,
                                  hashActual: nil, cambios: [], ilegible: true)
        case .ausente, .texto:
            let texto: String = if case .texto(let t, _) = disco { t } else { "" }
            let actual = ConfigAgentes.leer(yaml: texto)
            let hash = ContentHash.of(texto)
            if actual.ilegible {
                return EstadoDeConfig(confirmada: base, actual: actual, efectiva: base, hashConfirmado: confirmada?.hash,
                                      hashActual: hash, cambios: [], ilegible: true)
            }
            if hash == confirmada?.hash {
                return EstadoDeConfig(confirmada: base, actual: actual, efectiva: base, hashConfirmado: hash, hashActual: hash,
                                      cambios: [], ilegible: false)
            }
            let cambios = base.cambios(hacia: actual)
            if cambios.isEmpty {
                // Cambió algo que no es de los asistentes: se acepta tal cual.
                let c = try? estado.confirmarConfig(texto: texto, por: "sin cambios de permisos", fecha: ahora)
                return EstadoDeConfig(confirmada: actual, actual: actual, efectiva: actual, hashConfirmado: c?.hash ?? hash,
                                      hashActual: hash, cambios: [], ilegible: false)
            }
            return EstadoDeConfig(confirmada: base, actual: actual, efectiva: ConfigAgentes.masRestrictiva(base, actual),
                                  hashConfirmado: confirmada?.hash, hashActual: hash, cambios: cambios, ilegible: false)
        }
    }

    /// La configuración que se aplica ahora a los asistentes.
    public func efectiva() -> ConfigAgentes { leer().efectiva }

    /// Una persona confirma la configuración que hay ahora en el fichero («Confirmar los cambios»).
    @discardableResult
    public func confirmar(por autor: Autor, ahora: Date = Date()) throws -> EstadoGobierno.Confirmada {
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        guard case .texto(let t, _) = leerDisco() else {
            if case .ausente = leerDisco() { return try estado.confirmarConfig(texto: "", por: quien, fecha: ahora) }
            throw ErrorDeGobierno.configIlegible
        }
        guard !ConfigAgentes.leer(yaml: t).ilegible else { throw ErrorDeGobierno.configIlegible }
        return try estado.confirmarConfig(texto: t, por: quien, fecha: ahora)
    }

    /// La app acaba de escribir el fichero (como persona o como sistema): lo que quedó es lo confirmado.
    /// `hash` es la huella que dejó el escritor; si el fichero ya no la tiene, no se confirma nada.
    func confirmarEscritoPorLaApp(hash: String?, por: String, ahora: Date = Date()) {
        guard case .texto(let t, let bruto) = leerDisco(), !ConfigAgentes.leer(yaml: t).ilegible else {
            if case .ausente = leerDisco() { _ = try? estado.confirmarConfig(texto: "", por: por, fecha: ahora) }
            return
        }
        if let hash, bruto != hash { return }
        _ = try? estado.confirmarConfig(texto: t, por: por, fecha: ahora)
    }

    /// Confirma un texto concreto (el cambio que hizo la app aplicado sobre lo confirmado, cuando hay cambios de
    /// fuera pendientes: esos siguen pendientes).
    func confirmarTexto(_ texto: String, por: String, ahora: Date = Date()) throws {
        guard !ConfigAgentes.leer(yaml: texto).ilegible else { throw ErrorDeGobierno.configIlegible }
        try estado.confirmarConfig(texto: texto, por: por, fecha: ahora)
    }

    /// Texto de la última versión confirmada (`nil` si aún no hay ninguna).
    public func textoConfirmado() -> String? { (try? estado.configConfirmada())?.texto }

    /// «Volver a los de antes»: deja el fichero como la última versión confirmada (como persona). `nil` si ya lo está.
    public func planVolverALaConfirmada(autor: Autor) throws -> WritePlan? {
        guard autor.esPersona else { throw ErrorDeGobierno.soloPersonas }
        guard let c = try estado.configConfirmada() else { return nil }
        let url = Self.ruta.url(in: root)
        let actual = UbiquityInspector.withoutMaterializing { try? Data(contentsOf: url, options: [.uncached]) }
        guard let actual else {
            return WritePlan(autor: autor, descripcion: "Volver a los permisos confirmados", ops: [.create(Self.ruta, text: c.texto)])
        }
        guard ContentHash.of(actual) != ContentHash.of(Data(c.texto.utf8)),
              let op = WriteOp.replaceText(Self.ruta, base: actual, text: c.texto) else { return nil }
        return WritePlan(autor: autor, descripcion: "Volver a los permisos confirmados", ops: [op])
    }
}

/// Errores del gobierno, con texto para la persona.
public enum ErrorDeGobierno: Error, LocalizedError, Sendable, Equatable {
    case soloPersonas
    case configIlegible
    case asistenteDesconocido(String)
    case denegado(String)
    case noEncontrado(String)
    case borradorNoValido(String)
    case aprobacionNoEncontrada
    case aprobacionCerrada(String)
    case cambioDesdeQueLoPreparo
    /// F4 · corrector (R8): el borrador cambió con la hoja abierta: lo que se iba a aprobar no es lo que se vio.
    case cambioMientrasLoMirabas
    case caducada
    case propuestaNoEncontrada
    case propuestaCerrada
    case interruptorApagado
    case sinPermiso(String)

    public var errorDescription: String? {
        switch self {
        case .soloPersonas: "Esto solo lo puede decidir una persona."
        case .configIlegible: "No entiendo la configuración de los asistentes. Revísala antes de confirmarla."
        case .asistenteDesconocido(let s): "No conozco al asistente «\(s)»."
        case .denegado(let m): m
        case .noEncontrado(let p): "No encuentro «\(p)»."
        case .borradorNoValido(let m): m
        case .aprobacionNoEncontrada: "Esa aprobación ya no existe."
        case .aprobacionCerrada(let e): "Esa aprobación ya está \(e)."
        case .cambioDesdeQueLoPreparo: "Cambió desde que lo preparó el asistente."
        case .cambioMientrasLoMirabas: "Cambió mientras lo mirabas. Vuelve a abrirlo para ver lo que sale ahora."
        case .caducada: "Lleva más de 14 días sin decidir y ha caducado. Pide al asistente que lo vuelva a preparar."
        case .propuestaNoEncontrada: "Esa propuesta ya no existe."
        case .propuestaCerrada: "Esa propuesta ya está decidida."
        case .interruptorApagado: "Los asistentes están apagados. Enciéndelos para seguir."
        case .sinPermiso(let m): m
        }
    }
}
