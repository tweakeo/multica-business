import Foundation
import Testing
@testable import TLSCore

/// Una empresa de prueba para el gobierno de los asistentes (nombres neutros; nada real).
///
/// - Áreas: Dirección y Ventas y Finanzas activas; Entrega preparada; Marca y Equipo en reposo.
/// - Asistentes: Mika (coordinadora, Dirección, lee todo), Comercial (Ventas, tope de 2 tareas), Contable (Finanzas),
///   Implementador (Entrega, preparada), Marca (reposo) y Equipo (inactivo).
/// - Funciones: VEN-02 supervisado, VEN-03 asistido, VEN-09 manual, VEN-08 autónomo, VEN-11 off, FIN-04 off.
/// - Privado: `4 · Finanzas/Privado` (con «Expediente privado.md»).
struct EntornoGobierno {
    let base: URL
    let root: URL
    let state: URL
    let appSupport: URL
    let entry: VaultEntry

    static let config = """
        # Configuración de prueba.
        version: 1
        id: 0f0f0f0f-0000-4000-8000-000000000001
        clase: copia
        hoy: 2026-10-19
        interruptor: encendido
        pausa_areas: []
        privado: []
        capacidades:
          VEN-02: {declarada: si, modo: supervisado, ejecutor: IA}
          VEN-03: {declarada: si, modo: asistido}
          VEN-08: {declarada: si, modo: autonomo}
          VEN-09: {modo: manual}
          VEN-11: {modo: off}
          FIN-04: {modo: off}
        agentes:
          mika:
            activo: true
            coordinador: true
            areas: [direccion]
            lee_areas: [todas]
            capacidades: []
            max_tareas_por_ejecucion: 10
          comercial:
            activo: true
            areas: [ventas]
            lee_areas: [direccion]
            capacidades: [VEN-02, VEN-03, VEN-08, VEN-09, VEN-11]
            max_tareas_por_ejecucion: 2
          contable:
            activo: true
            areas: [finanzas]
            capacidades: []
          implementador:
            activo: true
            areas: [entrega]
          marca:
            activo: true
            areas: [marca]
          equipo:
            activo: false
            areas: [equipo]
        avisos: {tope_tarjetas_dia: 5, tope_notificaciones_no_rojas_dia: 3}

        """

    static let tarea = """
        ---
        tls_type: task
        tls_schema: 1
        id: 11111111-2222-4333-8444-555555555555
        numero: T-0001
        titulo: Llamar a Cliente Ejemplo
        estado: Por hacer
        tipo: tarea
        responsable: agente:comercial
        vence: 2026-10-30
        creada: 2026-10-15
        ---
        # Llamar a Cliente Ejemplo

        ## Descripción
        Preparar la llamada.

        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

        """

    init(config: String = EntornoGobierno.config) {
        base = Apoyo.tempDir("gobierno")
        root = base.appendingPathComponent("Empresa Ejemplo", isDirectory: true)
        state = base.appendingPathComponent("estado", isDirectory: true)
        appSupport = base.appendingPathComponent("asup", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        entry = VaultEntry(nombre: "Empresa Ejemplo", ruta: root.path, bookmark: nil, clase: .copia, escritura: .permitida)
        escribir(".tls/layout.json", #"{"preset":"humana","privado":["4 · Finanzas/Privado"]}"#)
        escribir(".tls/config.yaml", config)
        escribir(".tls/secuencias.json", "{\"tarea\":1}\n")
        escribir("Empresa.md", "# Empresa Ejemplo\n")
        escribir("AGENTS.md", "# Instrucciones\n")
        let estados: [(AreaCode, String)] = [(.direccion, "activa"), (.ventas, "activa"), (.entrega, "preparada"),
                                              (.finanzas, "activa"), (.marca, "en reposo"), (.equipo, "en reposo")]
        for (a, e) in estados {
            escribir("\(a.numero) · \(a.nombre)/Área.md", "# \(a.nombre)\n\n**Estado:** \(e) · **La lleva:** Manu\n\n## Qué transforma\nAlgo.\n")
        }
        escribir("1 · Dirección/Metas.md", "# Metas\n\n| Código | Indicador | Meta | Alerta | Por qué |\n|---|---|---|---|---|\n| FIN-RUNWAY | Meses de caja | 3 | 1 | Aguantar |\n")
        escribir("1 · Dirección/Decisiones.md", "# Decisiones\n\n")
        escribir("6 · Equipo/Roles/comercial.md", "---\ntls_type: role\nnombre: Comercial\nclase: agente\n---\n# Comercial\n")
        escribir("2 · Ventas/Tareas/t-0001-llamar-a-cliente-ejemplo.md", Self.tarea)
        escribir("4 · Finanzas/Privado/Expediente privado.md", "# Expediente privado\n\nNada que ver aquí.\n")
        escribir("4 · Finanzas/Registros/pagos.csv", "id,fecha,direccion,importe,moneda,documento_id,proyecto_id,tercero,metodo,evidencia,verificacion\n")
        escribir("Buzón/Correspondencia.md", "# Correspondencia\n")
    }

    static let tareaPath = VaultPath("2 · Ventas/Tareas/t-0001-llamar-a-cliente-ejemplo.md")
    static let privada = VaultPath("4 · Finanzas/Privado/Expediente privado.md")

    var options: VaultWriter.Options {
        VaultWriter.Options(stateDirectory: state, appSupport: appSupport, app: "The Last System pruebas")
    }

    func writer() async throws -> VaultWriter {
        try await VaultWriter.open(entry: entry, root: root, options: options)
    }

    func autorizador(hayEscritor: Bool = true, ahora: Date = Date()) throws -> Autorizador {
        let reloj = Caja(ahora)
        return try Autorizador(root: root, stateDirectory: state,
                               opciones: .init(hayEscritor: { hayEscritor }, ahora: { reloj.value }))
    }

    /// Escritor, bus con Autorizador y Autorizador.
    func gobierno(ahora: @escaping @Sendable () -> Date = { Date() }) async throws -> (CommandBus, Autorizador) {
        let w = try await writer()
        let a = try Autorizador(writer: w, opciones: .init(ahora: ahora))
        return (CommandBus(writer: w, autorizador: a), a)
    }

    func url(_ p: String) -> URL { VaultPath(p).url(in: root) }
    func datos(_ p: String) -> Data? { try? Data(contentsOf: url(p)) }
    func texto(_ p: String) -> String? { datos(p).flatMap { String(data: $0, encoding: .utf8) } }
    func existe(_ p: String) -> Bool { FileManager.default.fileExists(atPath: url(p).path) }

    func escribir(_ p: String, _ texto: String) {
        let u = url(p)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(texto.utf8).write(to: u)
    }

    func foto() -> VaultSnapshot { VaultSnapshot.read(entry: entry, root: root) }

    func limpiar() { Apoyo.limpiar(base) }
}

extension SolicitudAutorizacion {
    static func de(_ slug: String, _ tipo: TipoDeAccion, _ rutas: [String] = [], capacidad: String? = nil,
                   externa: AccionExterna? = nil, ejecucion: String? = nil, origen: String? = nil,
                   profundidad: Int? = nil, tamano: Int? = nil) -> SolicitudAutorizacion {
        SolicitudAutorizacion(autor: .agente(slug), tipo: tipo, rutas: rutas.map(VaultPath.init), capacidad: capacidad,
                              externa: externa, ejecucion: ejecucion.map { ContextoEjecucion(id: $0) }, tamano: tamano,
                              origen: origen, profundidadDelegacion: profundidad)
    }
}

/// Espera que un bloque falle con un error concreto del gobierno.
func esperaGobierno<T>(_ esperado: ErrorDeGobierno, sourceLocation: SourceLocation = #_sourceLocation,
                       _ body: () async throws -> T) async {
    do {
        _ = try await body()
        Issue.record("Debía fallar con \(esperado)", sourceLocation: sourceLocation)
    } catch let e as ErrorDeGobierno {
        #expect(e == esperado, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Error inesperado: \(error)", sourceLocation: sourceLocation)
    }
}

/// Espera que el bus deniegue un plan de un asistente (con el paso del Autorizador).
func esperaDenegado<T>(paso: Int, _ resultado: DecisionAutorizacion.Resultado = .denegado,
                       sourceLocation: SourceLocation = #_sourceLocation, _ body: () async throws -> T) async {
    do {
        _ = try await body()
        Issue.record("Debía denegarse (paso \(paso))", sourceLocation: sourceLocation)
    } catch let e as AutorizacionDenegada {
        #expect(e.decision.paso == paso, "paso \(e.decision.paso): \(e.decision.motivo)", sourceLocation: sourceLocation)
        #expect(e.decision.resultado == resultado, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Error inesperado: \(error)", sourceLocation: sourceLocation)
    }
}
