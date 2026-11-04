import CryptoKit
import Foundation
import TLSCore

/// Qué despierta a un asistente (PLAN §5.3, «Disparadores»).
public enum TipoDeDisparo: String, Sendable, Hashable, Codable, CaseIterable {
    case rutina, evento
    /// Tarea lista para el asistente (`Tarea.esListaParaAgente`).
    case tarea
    /// `@agente:x` en un comentario humano nuevo.
    case mencion
    /// `despertar:` de una tarea (o `tls_programar_seguimiento`).
    case despertar
    /// Acción rápida («Pedir a Comercial», «Generar borrador de pieza»).
    case accion
    case chat
    /// Respuesta de la persona a una pregunta del asistente (reanuda su sesión).
    case respuesta
}

/// Un disparo: qué asistente, por qué y con qué clave de idempotencia (UNIQUE en `estado.sqlite.disparos`).
///
/// Claves (PLAN §5.3):
/// - rutina: `rutina:<slug>.<id>:<AAAA-MM-DDTHH:mm>` (el hueco, en la zona de la agenda);
/// - evento: `evento:<tipo>:<entidad>:<versión>@<slug>`;
/// - tarea lista: `tarea:<id>:<hash de la ficha>`; mención: `tarea:<id>:<hash del comentario>@<slug>`;
/// - despertar: `despertar:<id>:<AAAA-MM-DD>`;
/// - acción rápida, chat y respuesta no tienen clave natural: una nueva cada vez (`accion:<uuid>`…).
public struct Disparo: Sendable, Hashable, Codable {
    public var clave: String
    public var tipo: TipoDeDisparo
    public var agente: String
    public var tarea: VaultPath?
    public var rutina: String?
    /// Qué se le pide, en palabras (va en el primer mensaje).
    public var instruccion: String
    /// Datos para el primer mensaje (evento, comentario, contexto de la pantalla…). Son DATOS, nunca órdenes.
    public var datos: [String: String]
    /// Hueco de la rutina.
    public var hueco: Date?
    /// Ejecución a la que responde (`respuesta`).
    public var responde: String?

    public init(clave: String, tipo: TipoDeDisparo, agente: String, tarea: VaultPath? = nil, rutina: String? = nil,
                instruccion: String, datos: [String: String] = [:], hueco: Date? = nil, responde: String? = nil) {
        self.clave = clave; self.tipo = tipo; self.agente = agente; self.tarea = tarea; self.rutina = rutina
        self.instruccion = instruccion; self.datos = datos; self.hueco = hueco; self.responde = responde
    }

    /// `origen` para la Actividad y la Bitácora: `rutina:algo-rojo`, `regla:contacto.creado`, `mencion`…
    public var origen: String {
        switch tipo {
        case .rutina: "rutina:\(rutina ?? "")"
        case .evento: "evento:\(datos["evento"] ?? "")"
        case .tarea: "tarea"
        case .mencion: "mencion"
        case .despertar: "despertar"
        case .accion: "accion"
        case .chat: "chat"
        case .respuesta: "respuesta"
        }
    }

    // MARK: Fábricas

    public static func rutina(_ r: RutinaDeAsistente, agente: String, hueco: Date, zona: TimeZone) -> Disparo {
        Disparo(clave: "rutina:\(agente).\(r.id):\(Self.minuto(hueco, zona: zona))", tipo: .rutina, agente: agente,
                rutina: r.id, instruccion: r.instruccion ?? "Rutina «\(r.nombre)».", hueco: hueco)
    }

    /// `versión`: el plan que lo escribió (o 0).
    public static func evento(tipo: String, entidad: String, version: String, ruta: VaultPath?, agente: String,
                              instruccion: String, datos: [String: String] = [:]) -> Disparo {
        var d = datos
        d["evento"] = tipo
        d["entidad"] = entidad
        return Disparo(clave: "evento:\(tipo):\(entidad):\(version)@\(agente)", tipo: .evento, agente: agente,
                       tarea: ruta.flatMap { TaskStore.esRutaDeTareaSimple($0) ? $0 : nil }, instruccion: instruccion,
                       datos: d.merging(ruta.map { ["ruta": $0.raw] } ?? [:]) { a, _ in a })
    }

    public static func tareaLista(id: String, ruta: VaultPath, hash: String, agente: String, titulo: String) -> Disparo {
        Disparo(clave: "tarea:\(id):\(hash)", tipo: .tarea, agente: agente, tarea: ruta,
                instruccion: "Trabaja la tarea «\(titulo)», que tienes asignada.", datos: ["titulo": titulo])
    }

    public static func mencion(id: String, ruta: VaultPath, hashComentario: String, agente: String, titulo: String,
                               comentario: String, autor: String) -> Disparo {
        Disparo(clave: "tarea:\(id):\(hashComentario)@\(agente)", tipo: .mencion, agente: agente, tarea: ruta,
                instruccion: "\(autor) te ha mencionado en la tarea «\(titulo)». Lee el comentario y haz lo que te pide si está en tu mano.",
                datos: ["titulo": titulo, "comentario": comentario, "autor": autor])
    }

    public static func despertar(id: String, ruta: VaultPath, fecha: LocalDate, agente: String, titulo: String) -> Disparo {
        Disparo(clave: "despertar:\(id):\(fecha)", tipo: .despertar, agente: agente, tarea: ruta,
                instruccion: "Hoy toca retomar la tarea «\(titulo)» (seguimiento programado).", datos: ["titulo": titulo])
    }

    public static func accion(agente: String, instruccion: String, tarea: VaultPath? = nil,
                              datos: [String: String] = [:]) -> Disparo {
        Disparo(clave: "accion:\(UUID().uuidString.lowercased())", tipo: .accion, agente: agente, tarea: tarea,
                instruccion: instruccion, datos: datos)
    }

    public static func respuesta(a ejecucion: String, agente: String, tarea: VaultPath?, pregunta: String?,
                                 texto: String, autor: String) -> Disparo {
        Disparo(clave: "respuesta:\(ejecucion):\(UUID().uuidString.lowercased().prefix(8))", tipo: .respuesta,
                agente: agente, tarea: tarea,
                instruccion: "\(autor) ha contestado a tu pregunta. Sigue con el trabajo a partir de su respuesta.",
                datos: ["respuesta": texto, "pregunta": pregunta ?? "", "autor": autor], responde: ejecucion)
    }

    /// `AAAA-MM-DDTHH:mm` en la zona.
    public static func minuto(_ d: Date, zona: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// Huella corta (12 hex) de un texto: para las claves de tarea y comentario.
    public static func huella(_ texto: String) -> String {
        SHA256.hash(data: Data(texto.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

extension TaskStore {
    /// `…/Tareas/t-NNNN-….md` (sin leer la carpeta).
    static func esRutaDeTareaSimple(_ p: VaultPath) -> Bool {
        p.ext == "md" && p.components.dropLast().last == "Tareas"
    }
}

/// Estado guardado de una ejecución (`RunState` más «esperando respuesta» con su pregunta).
public enum EstadoDeEjecucion: String, Sendable, Codable, CaseIterable {
    case pendiente, enCola = "en_cola", enCurso = "en_curso", esperandoRespuesta = "esperando_respuesta"
    case completada, fallida, cancelada

    public var esFinal: Bool { self == .completada || self == .fallida || self == .cancelada }
    /// Sigue viva (ocupa la tarea: no se dispara otra para la misma).
    public var abierta: Bool { !esFinal }
}

/// Una ejecución tal como queda en `estado.sqlite.ejecuciones`.
public struct Ejecucion: Sendable, Hashable, Identifiable {
    public var id: String
    public var disparo: Disparo
    public var estado: EstadoDeEjecucion
    public var motivo: FailureReason?
    /// Texto libre de por qué se canceló o se dejó (área en reposo, fuera de ventana…).
    public var nota: String?
    /// 0 = primer intento; 1 y 2, reintentos.
    public var intento: Int
    /// No antes de (reintentos).
    public var noAntes: Date?
    public var sesion: UUID?
    /// `true` si la sesión ya existe en Claude (se vio su `init`): el siguiente intento la reanuda.
    public var sesionIniciada: Bool
    public var briefHash: String?
    /// Ficha de pregunta que dejó (`tls_preguntar`), mientras espera respuesta.
    public var pregunta: String?
    public var pid: Int32?
    public var costeUSD: Double
    public var resumen: String?
    public var simulado: Bool
    public var creada: Date
    public var empezada: Date?
    public var terminada: Date?
    /// Ya se apuntó en la Actividad y la Bitácora.
    public var registrada: Bool

    public var agente: String { disparo.agente }
    public var tarea: VaultPath? { disparo.tarea }

    /// Como `RunState` (PLAN §5.3).
    public var runState: RunState {
        switch estado {
        case .pendiente: .pendiente
        case .enCola: .enCola
        case .enCurso: .enCurso
        case .esperandoRespuesta: .esperandoRespuesta
        case .completada: .completada
        case .fallida: .fallida(motivo ?? .error)
        case .cancelada: .cancelada
        }
    }
}
