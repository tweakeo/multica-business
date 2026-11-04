import Foundation
import Testing
import TLSAgents
import TLSCore
@testable import TLSUI

/// Apoyo de las pruebas de ⌘J, Decisiones de F4, Hoy y la app fuera de la ventana (rol mika): una copia de Asesoría
/// Ribera (ficticia, `hoy: 2026-10-19`) en un temporal propio, abierta con escritor, y su gobierno. **Nunca se lanza
/// Claude**: lo que «hace Mika» lo hace un canal falso que escribe por el gobierno como lo haría `tls-mcp`.
@MainActor
enum MikaApoyo {
    @MainActor
    struct Empresa {
        let entorno: SesionEscrituraTests.Entorno
        let sesion: VaultSession

        var carpeta: URL { entorno.carpeta }
        var asistentes: AsistentesDeLaEmpresa { AsistentesDeLaEmpresa.de(sesion) }

        func url(_ p: String) -> URL { VaultPath(p).url(in: carpeta) }
        func texto(_ p: String) -> String { (try? String(contentsOf: url(p), encoding: .utf8)) ?? "" }
        func existe(_ p: String) -> Bool { FileManager.default.fileExists(atPath: url(p).path) }

        /// Escribe un fichero «desde fuera» (como Obsidian): no es la app.
        func escribirFuera(_ p: String, _ texto: String) {
            let u = url(p)
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(texto.utf8).write(to: u)
        }

        func cambiarFuera(_ p: String, _ de: String, _ a: String) {
            let t = texto(p)
            precondition(t.contains(de), "«\(de)» no está en \(p)")
            escribirFuera(p, t.replacingOccurrences(of: de, with: a))
        }

        func foto() -> VaultSnapshot { VaultSnapshot.read(root: carpeta) }

        /// Rehace Hoy y Decisiones (como tras decidir algo).
        func refrescar() async {
            await asistentes.cambio()
        }

        /// Espera a que se cumpla algo (el índice y el escritor van un poco por detrás).
        func esperar(_ condicion: @MainActor () -> Bool, segundos: Double = 10) async {
            let fin = Date().addingTimeInterval(segundos)
            while !condicion(), Date() < fin {
                await refrescar()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }

        var datos: DatosHoy? { AlmacenHoy.de(sesion).datos }

        func tarjeta(_ cumple: (TarjetaDecision) -> Bool) -> TarjetaDecision? { datos?.bandeja.tarjetas.first(where: cumple) }

        func cerrar() {
            sesion.close()
            entorno.limpiar()
        }
    }

    /// Ribera en un temporal, abierta con escritor y con su gobierno listo.
    static func ribera() async throws -> Empresa {
        let (e, entry) = try SesionEscrituraTests().entorno(clase: .demo, escritura: .permitida)
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        let empresa = Empresa(entorno: e, sesion: s)
        _ = empresa.asistentes.autorizador
        await AlmacenHoy.de(s).actualizar(forzar: true)
        return empresa
    }

    /// Un borrador de correo que prepara Comercial y su petición de aprobación (como `tls_preparar_borrador` y
    /// `tls_solicitar_accion`). Devuelve la ruta del borrador y el id de la aprobación.
    static func borradorPendiente(_ e: Empresa, slug: String = "seguimiento-javier-ortega",
                                  asunto: String = "Seguimiento de la propuesta de la renta",
                                  cuerpo: String = "Hola, Javier:\n\n¿Pudiste mirar la propuesta que te mandamos el día 12?\n\nUn saludo,\nManu") async throws -> (VaultPath, String) {
        let bus = try #require(e.sesion.bus)
        let b = NuevoBorrador(accion: .enviarCorreo, area: .ventas, asunto: asunto, cuerpo: cuerpo,
                              para: ["persona@example.com"], paraTi: "Han pasado 7 días desde la propuesta.", ejecucion: "r-prueba",
                              slug: slug)
        let (ruta, plan) = Borradores.plan(b, layout: e.foto().layout, autor: .agente("comercial"))
        let r = try await bus.ejecutar(plan)
        #expect(r.hecho, "Comercial prepara borradores (suelo)")
        let apr = try #require(e.asistentes.aprobaciones)
        let s = try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial", ejecucion: ContextoEjecucion(id: "r-prueba"))
        #expect(s.estado == "aprobacion_requerida")
        return (ruta, try #require(s.id))
    }

    /// Una pregunta de Contable con dos respuestas propuestas (como `tls_preguntar`).
    static func preguntaDeContable(_ e: Empresa) -> String {
        let ruta = "4 · Finanzas/Tareas/t-0150-la-factura-de-agosto-de-movil-levante.md"
        e.escribirFuera(ruta, """
        ---
        tls_type: task
        tls_schema: 1
        id: pregunta-contable-1
        numero: T-0150
        titulo: ¿La factura de agosto de Móvil Levante va a gastos de oficina?
        estado: En revisión
        tipo: pregunta
        responsable: Manu
        origen: agente:contable
        creada: 2026-10-19
        creada_por: agente:contable
        ejecucion: r-contable
        ---
        # ¿La factura de agosto de Móvil Levante va a gastos de oficina?
        > Pregunta de Contable (asistente) · espera tu respuesta

        ## Pregunta
        ¿La factura de agosto de Móvil Levante va a gastos de oficina o a la línea del móvil de empresa?

        ## Por qué la hago
        El extracto trae un cargo de 39,90 € y no sé a qué cuenta va.

        ## Lo que propongo
        1. A la línea del móvil de empresa (recomendada)
        2. A gastos de oficina

        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

        """)
        return ruta
    }

    /// Una ficha de sistema con su «Aprendido» (Ribera no trae ninguna).
    static func sistema(_ e: Empresa) -> String {
        let ruta = "2 · Ventas/Sistemas/Seguimiento de propuestas.md"
        e.escribirFuera(ruta, """
        ---
        tls_type: system
        tls_schema: 1
        id: sistema-seguimiento
        titulo: Seguimiento de propuestas
        area: Ventas
        ---
        # Seguimiento de propuestas

        ## Para qué
        Que ninguna propuesta se quede sin respuesta.

        ## Aprendido
        - 2026-10-01 · Los lunes contestan más · lo aprobó Manu

        """)
        return ruta
    }
}

/// Un chat falso con Mika: contesta lo que se le diga y, si se le pide, hace algo con sus herramientas **por el
/// gobierno** (como `tls-mcp`: `EscrituraDeAsistente` con la ejecución del chat), para que quede en la auditoría.
final class CanalFalso: CanalDeMika, @unchecked Sendable {
    let id: String
    private let lock = NSLock()
    private var respuestas: [RespuestaDeChat]
    private var acciones: [@Sendable (String) async -> Void]
    private(set) var recibidos: [(texto: String, pantalla: String?)] = []
    private(set) var cerrado = false

    init(id: String = "chat-prueba-\(UUID().uuidString.prefix(8))", respuestas: [RespuestaDeChat],
         acciones: [@Sendable (String) async -> Void] = []) {
        self.id = id
        self.respuestas = respuestas
        self.acciones = acciones
    }

    func enviar(_ texto: String, pantalla: String?) async -> RespuestaDeChat {
        let (accion, r): ((@Sendable (String) async -> Void)?, RespuestaDeChat) = lock.withLock {
            recibidos.append((texto, pantalla))
            let a = acciones.isEmpty ? nil : acciones.removeFirst()
            let r = respuestas.isEmpty ? RespuestaDeChat(texto: "Vale.", modo: .claude) : respuestas.removeFirst()
            return (a, r)
        }
        await accion?(id + "-1")
        return r
    }

    func cerrar() async { lock.withLock { cerrado = true } }

    /// Mika crea una tarea (para Comercial) por el gobierno, con la ejecución del chat.
    static func crearTarea(_ escritura: EscrituraDeAsistente, titulo: String, foto: @escaping @Sendable () -> VaultSnapshot)
        -> @Sendable (String) async -> Void {
        { ejecucion in
            guard let nota = try? TaskStore(snapshot: foto()).crear(NuevaTarea(
                titulo: titulo, area: .ventas, responsable: "agente:comercial", estado: .porHacer,
                planificada: LocalDate(parsing: "2026-10-20"), origen: "agente:mika", autor: .agente("mika"),
                propiedades: [Property(key: "creada_por", value: .text("agente:mika"))])) else { return }
            _ = try? await escritura.escribir(nota.plan, ejecucion: ContextoEjecucion(id: ejecucion))
        }
    }
}
