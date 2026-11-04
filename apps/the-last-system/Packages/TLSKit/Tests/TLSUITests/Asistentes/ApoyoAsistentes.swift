import AppKit
import Foundation
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSUI

/// Apoyo de las pruebas de las pantallas de asistentes: una copia de Asesoría Ribera (ficticia, `hoy: 2026-10-19`,
/// lunes) en un temporal propio, abierta con escritor, y el estado del motor de esa copia. Nunca se toca el ejemplo del
/// repositorio ni se lanza Claude.
@MainActor
struct ApoyoAsistentes {
    let entorno: SesionEscrituraTests.Entorno
    let sesion: VaultSession

    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    /// Lunes 19 de octubre de 2026 a la hora dada, en Madrid.
    static func lunes(_ hora: Int = 9, _ minuto: Int = 30) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = madrid
        return c.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hora, minute: minuto))!
    }

    /// Abre la copia. `gobierno`: pone el `Autorizador` de la carpeta en el bus (como hará la integración).
    /// `preparar`: cambia ficheros de la copia antes de abrirla (no es la app escribiendo).
    static func abrir(escritura: WriteAccess = .permitida, gobierno: Bool = false,
                      preparar: ((URL) throws -> Void)? = nil) async throws -> ApoyoAsistentes {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: escritura)
        try preparar?(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        #expect(sesion.isReady)
        if gobierno, let w = sesion.writer {
            sesion.bus?.establecerAutorizador(try Autorizador(writer: w))
        }
        return ApoyoAsistentes(entorno: e, sesion: sesion)
    }

    func cerrar() {
        RegistroDeAsistentes.compartido.desconectar(sesion)
        sesion.close()
        entorno.limpiar()
    }

    var carpeta: URL { entorno.carpeta }
    var config: String { (try? String(contentsOf: carpeta.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)) ?? "" }
    var configDatos: Data { (try? Data(contentsOf: carpeta.appendingPathComponent(".tls/config.yaml"))) ?? Data() }

    /// Cambia la configuración de la copia desde fuera de la app.
    func cambiarConfig(_ de: String, _ a: String) throws {
        let t = config
        precondition(t.contains(de), "«\(de)» no está en la configuración")
        try Data(t.replacingOccurrences(of: de, with: a).utf8).write(to: carpeta.appendingPathComponent(".tls/config.yaml"))
    }

    /// El estado del motor de la copia (lo crea si hace falta, como el motor).
    func motor() throws -> EstadoDelMotor { try EstadoDelMotor(directory: sesion.writer?.stateDirectory ?? entorno.estado) }

    func leer(ahora: Date = ApoyoAsistentes.lunes()) async throws -> LecturaAsistentes {
        try #require(await ModeloAsistentes.leer(sesion, ahora: ahora))
    }

    /// Espera a que la sesión vea lo escrito (el índice va 250 ms por detrás).
    func esperarRevision(_ antes: Int) async {
        await SesionEscrituraTests().esperar({ sesion.revision > antes })
    }

    /// Una ejecución guardada por el motor en el estado pedido.
    @discardableResult
    func ejecucion(_ agente: String, estado: EstadoDeEjecucion, resumen: String? = nil, coste: Double = 0, simulado: Bool = false,
                   tarea: VaultPath? = nil, ahora: Date = ApoyoAsistentes.lunes(9, 0)) throws -> Ejecucion {
        let m = try motor()
        var e = try #require(try m.encolar(Disparo.accion(agente: agente, instruccion: "Prueba", tarea: tarea,
                                                           datos: ["peticion": "Repasa lo pendiente"]),
                                            ahora: ahora, simulado: simulado))
        e.estado = estado
        e.resumen = resumen
        e.costeUSD = coste
        if estado.esFinal { e.terminada = ahora.addingTimeInterval(60) }
        if estado == .enCurso || estado.esFinal { e.empezada = ahora }
        try m.guardar(e)
        return e
    }
}
