import Foundation
import MCP
import TLSCore

/// Lo que respondió `tls_registrar_*`.
public struct ResultadoDeRegistro: Sendable, Hashable {
    /// `hecho`, `ya_registrado`, `convertida_en_propuesta`, `tarea_para_persona` o `error`.
    public let estado: String
    public let ruta: String?
    public let mensaje: String

    public init(estado: String, ruta: String?, mensaje: String) {
        self.estado = estado; self.ruta = ruta; self.mensaje = mensaje
    }
}

/// Quién apunta en las fichas lo que llega de otro programa: `tls-mcp` (las cuatro herramientas de dominio, con el
/// asistente de la plantilla y su modo). Lo implementa `RegistradorPorHerramientas` en TLSMCPHost.
public protocol RegistradorDeReflejo: Sendable {
    /// ¿Ese asistente está activo y tiene permiso para leer esa herramienta?
    func puede(asistente: String, expuesta: String) async -> Bool
    func registrar(_ tipo: TipoDeRegistro, argumentos: [String: Value], asistente: String, ejecucion: String) async
        -> ResultadoDeRegistro
}

/// Lo que pasó en una sincronización.
public struct InformeDeSincronizacion: Sendable, Hashable {
    public let conexion: String
    public let ejecucion: String
    public var leidos = 0
    /// Fichas nuevas (rutas).
    public var creadas: [String] = []
    public var repetidos = 0
    public var propuestas = 0
    public var tareas = 0
    public var omitidos = 0
    public var errores: [String] = []
    /// Asistentes en cuyo nombre se apuntó.
    public var asistentes: Set<String> = []

    /// «2 contactos nuevos; 3 ya estaban».
    public var resumen: String {
        var p: [String] = []
        p.append(creadas.count == 1 ? "1 ficha nueva" : "\(creadas.count) fichas nuevas")
        if repetidos > 0 { p.append("\(repetidos) ya estaban") }
        if propuestas > 0 { p.append(propuestas == 1 ? "1 propuesta para ti" : "\(propuestas) propuestas para ti") }
        if tareas > 0 { p.append(tareas == 1 ? "1 tarea para ti" : "\(tareas) tareas para ti") }
        if omitidos > 0 { p.append("\(omitidos) sin datos suficientes") }
        if !errores.isEmpty { p.append(errores.count == 1 ? "1 error" : "\(errores.count) errores") }
        return p.joined(separator: "; ")
    }
}

/// La rutina de sincronización de cada conector (PLAN §7.4: no hay webhooks en v1). Lee con las herramientas de
/// lectura de la plantilla y llama a `tls_registrar_*` con `origen: ext:<servidor>:<id>`; una segunda vuelta no
/// duplica nada (lo comprueba la propia herramienta por el origen). Todo lo que llega es un dato: se toman solo los
/// campos que dice la plantilla, sin saltos de línea y recortados; ninguna instrucción que traiga cambia lo que se hace.
///
/// Deja una línea de Bitácora por ejecución (lecturas) y una entrada de Actividad en cada ficha nueva (escrituras).
public struct Sincronizador: Sendable {
    public let pasarela: Pasarela
    public let registrador: any RegistradorDeReflejo
    public let registro: RegistroEnFicheros
    /// Tope de elementos por herramienta y vuelta.
    public var tope = 200

    public init(pasarela: Pasarela, registrador: any RegistradorDeReflejo, registro: RegistroEnFicheros) {
        self.pasarela = pasarela; self.registrador = registrador; self.registro = registro
    }

    /// ¿Le toca ya a esta conexión? (activa, con reflejos y pasado su intervalo).
    public static func toca(_ c: Conexion, ahora: Date) -> Bool {
        guard c.activa, c.sincronizarCadaMinutos > 0, !PlantillasDeSerie.plantilla(c.plantilla).reflejos.isEmpty else { return false }
        guard let u = c.ultimaSincronizacion else { return true }
        return ahora.timeIntervalSince(u) >= Double(c.sincronizarCadaMinutos) * 60
    }

    /// Las conexiones a las que les toca.
    public func pendientes(ahora: Date = Date()) -> [Conexion] {
        pasarela.conexiones().filter { Self.toca($0, ahora: ahora) }
    }

    public func sincronizar(_ id: String) async throws -> InformeDeSincronizacion {
        guard let c = pasarela.almacen.conexion(id) else { throw ErrorDePasarela.conexionDesconocida(id) }
        guard c.activa else { throw ErrorDePasarela.herramientaDesactivada(c.nombre) }
        let ahora = pasarela.ahora()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        let ejecucion = "sync-\(c.id)-\(f.string(from: ahora))"
        var inf = InformeDeSincronizacion(conexion: c.id, ejecucion: ejecucion)
        let plantilla = PlantillasDeSerie.plantilla(c.plantilla)
        let activas = (c.catalogo?.activas ?? []).filter { $0.clase == .lectura }
        var hechas: Set<String> = []
        for reflejo in plantilla.reflejos {
            for h in activas where Patrones.casa(h.nombre, reflejo.herramientas) && !hechas.contains("\(reflejo.id)|\(h.nombre)") {
                hechas.insert("\(reflejo.id)|\(h.nombre)")
                guard await registrador.puede(asistente: reflejo.asistente, expuesta: h.expuesta) else { continue }
                inf.asistentes.insert(reflejo.asistente)
                await reflejar(reflejo, h, c, ejecucion: ejecucion, en: &inf)
            }
        }
        _ = try? pasarela.almacen.cambiar(id) { $0.ultimaSincronizacion = ahora }
        // Una línea de Bitácora por ejecución (y por asistente) y la Actividad de cada ficha nueva.
        for slug in inf.asistentes.sorted() {
            await registro.anotar(agente: slug, que: "Sincronizó \(c.nombre): \(inf.resumen)",
                                  resultado: inf.errores.isEmpty ? "hecho" : "con error", ejecucion: ejecucion,
                                  masFichas: inf.creadas.map { VaultPath($0) },
                                  actividad: inf.creadas.isEmpty ? nil : "Creada desde \(c.nombre) (sincronización).")
        }
        return inf
    }

    func reflejar(_ r: ReflejoDePlantilla, _ h: HerramientaExterna, _ c: Conexion, ejecucion: String,
                  en inf: inout InformeDeSincronizacion) async {
        let resultado: CallTool.Result
        do {
            resultado = try await pasarela.leerParaReflejo(HerramientaDeConexion(conexion: c, herramienta: h),
                                                           argumentos: r.argumentos.mapValues { .string($0) })
        } catch {
            inf.errores.append("\(h.nombreVisible): \(error.localizedDescription)")
            return
        }
        guard resultado.isError != true else {
            inf.errores.append("\(h.nombreVisible): el programa respondió con un error")
            return
        }
        let elementos = Self.elementos(resultado, listas: r.listas).prefix(tope)
        let secretos = Array(pasarela.llavero.secretos(de: c).values)
        for e in elementos {
            inf.leidos += 1
            guard let id = Self.identificador(e, claves: r.identificador, secretos: secretos) else { inf.omitidos += 1; continue }
            var args: [String: Value] = ["origen": .string(c.origen(id))]
            for (destino, fuentes) in r.campos {
                if let v = Self.valor(e, fuentes, numero: destino == "valor" || destino == "importe", secretos: secretos) {
                    args[destino] = v
                }
            }
            guard Self.completo(r.registro, args) else { inf.omitidos += 1; continue }
            let res = await registrador.registrar(r.registro, argumentos: args, asistente: r.asistente, ejecucion: ejecucion)
            switch res.estado {
            case "hecho": if let ruta = res.ruta { inf.creadas.append(ruta) }
            case "ya_registrado": inf.repetidos += 1
            case "convertida_en_propuesta": inf.propuestas += 1
            case "tarea_para_persona": inf.tareas += 1
            default: inf.errores.append(res.mensaje)
            }
        }
    }

    // MARK: Leer lo que llega (como dato)

    /// La lista de elementos: la respuesta estructurada o el texto JSON; la primera clave de `listas` que sea una lista
    /// (o la propia respuesta si ya lo es).
    static func elementos(_ r: CallTool.Result, listas: [String]) -> [[String: Value]] {
        var raiz = r.structuredContent
        if raiz == nil {
            for parte in r.content {
                if case .text(let t, _, _) = parte, let v = try? JSONDecoder().decode(Value.self, from: Data(t.utf8)) {
                    raiz = v
                    break
                }
            }
        }
        guard let raiz else { return [] }
        func objetos(_ v: Value) -> [[String: Value]]? {
            if case .array(let a) = v { return a.compactMap(\.objectValue) }
            return nil
        }
        if let a = objetos(raiz) { return a }
        guard case .object(let o) = raiz else { return [] }
        for k in listas { if let v = o[k], let a = objetos(v) { return a } }
        return []
    }

    /// El identificador en el otro programa, solo con letras, cifras, `-`, `_` y `.` (60 como mucho).
    static func identificador(_ e: [String: Value], claves: [String], secretos: [String] = []) -> String? {
        for k in claves {
            let bruto: String? = switch e[k] {
            case .string(let s)?: s
            case .int(let i)?: String(i)
            // S8: solo enteros representables (ni 1e300, ni infinito, ni NaN: no tumban la app).
            case .double(let d)?: Int(exactly: d).map { String($0) }
            default: nil
            }
            // S7: un identificador que parece una clave no se usa (acabaría en el origen de la ficha).
            guard let b = bruto, Ocultador.ocultar(b, secretos: secretos) == b else { continue }
            let limpio = String(b.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }.prefix(60))
            if !limpio.isEmpty, limpio.contains(where: { $0.isLetter || $0.isNumber }) { return limpio }
        }
        return nil
    }

    /// El primer valor que haya entre las claves, como texto de una línea (400 como mucho) o como número.
    static func valor(_ e: [String: Value], _ claves: [String], numero: Bool, secretos: [String] = []) -> Value? {
        for k in claves {
            guard let v = e[k] else { continue }
            if numero {
                switch v {
                case .int(let i): return .double(Double(i))
                case .double(let d): return .double(d)
                case .string(let s):
                    if let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return .double(d) }
                default: continue
                }
                continue
            }
            let texto: String? = switch v {
            case .string(let s): s
            case .int(let i): String(i)
            case .double(let d): String(d)
            case .bool(let b): b ? "sí" : "no"
            default: nil
            }
            guard let t = texto else { continue }
            let linea = t.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
                .joined().trimmingCharacters(in: .whitespaces)
            // S7: lo que se escribe en las fichas, sin secretos (los de la conexión y los que tengan pinta de clave).
            let limpia = Ocultador.ocultar(linea, secretos: secretos)
            if !limpia.isEmpty { return .string(String(limpia.prefix(400))) }
        }
        return nil
    }

    static func completo(_ t: TipoDeRegistro, _ args: [String: Value]) -> Bool {
        switch t {
        case .contacto, .oportunidad: args["nombre"] != nil
        case .cobro: args["importe"] != nil && args["fecha"] != nil
        case .metricas: args["contenido"] != nil && args["metricas"] != nil
        }
    }
}
