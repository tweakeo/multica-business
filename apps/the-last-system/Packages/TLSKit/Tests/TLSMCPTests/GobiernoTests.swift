import Foundation
import MCP
import Testing
import TLSAgents
@testable import TLSCore
@testable import TLSMCPHost
@testable import TLSMCPShared

/// El servidor de herramientas con el gobierno de verdad (`Autorizador`, `Aprobaciones`, `AlmacenPropuestas`,
/// `EscrituraDeAsistente`) sobre la copia de Ribera con asistentes configurados. Sin Claude.
@Suite(.serialized)
struct GobiernoTests {
    /// `config.yaml` de prueba: Mika coordina, Contable en Finanzas, Comercial en Ventas (contactos en asistido).
    static let configAsistentes = """

    interruptor: encendido
    capacidades:
      VEN-02: {modo: asistido}
      VEN-03: {modo: autonomo}
    agentes:
      mika:
        activo: true
        coordinador: true
        areas: [direccion]
        lee_areas: [todas]
        max_tareas_por_ejecucion: 10
      contable:
        activo: true
        areas: [finanzas]
      comercial:
        activo: true
        areas: [ventas]
      marca:
        activo: false
        areas: [marca]
    """

    struct Gobierno {
        let autorizador: Autorizador
        let servidor: ServidorDeHerramientas
    }

    static func gobierno(_ e: ApoyoMCP.Empresa, config extra: String = configAsistentes) throws -> Gobierno {
        let ruta = e.url(".tls/config.yaml")
        // Lo de la carpeta hasta la parte de los asistentes (si el ejemplo ya la trae, se sustituye por la de la prueba).
        let actual = (try? String(contentsOf: ruta, encoding: .utf8)) ?? ""
        let claves = ["# Asistentes", "interruptor:", "pausa_areas:", "avisos:", "uso:", "agentes:", "capacidades:"]
        let lineas = actual.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let corte = lineas.firstIndex { l in claves.contains { l.hasPrefix($0) } } ?? lineas.count
        // Lo privado también marcado en `.tls/` (el Autorizador aún no recibe lo privado de los ajustes de la app).
        let base = lineas[..<corte].map { $0.hasPrefix("privado:") ? "privado: [\"\(ApoyoMCP.privada)\"]" : $0 }
        try (base.joined(separator: "\n") + extra + "\n").write(to: ruta, atomically: true, encoding: .utf8)
        let a = try Autorizador(writer: e.writer, opciones: .init(estadoDeArea: { _ in .activa }))
        e.bus.establecerAutorizador(a)
        let deps = ServidorDeHerramientas.Dependencias.de(
            service: e.service, bus: e.bus, autorizador: AutorizadorDelGobierno(a),
            dominio: DominioDelGobierno(EscrituraDeAsistente(bus: e.bus, autorizador: a)), servicios: e.servicios,
            aprobaciones: AprobacionesDelGobierno(Aprobaciones(bus: e.bus, autorizador: a)),
            propuestas: PropuestasDelGobierno(AlmacenPropuestas(estado: a.estado)), auditoria: e.auditoria)
        return Gobierno(autorizador: a, servidor: ServidorDeHerramientas(deps))
    }

    static func mika(_ ejecucion: String = "r-mika") -> ContextoDelAsistente {
        ContextoDelAsistente(ejecucion: ejecucion, asistente: "mika", coordinador: true, areas: [.direccion],
                             leeAreas: AreaCode.allCases)
    }

    static let contable = ContextoDelAsistente(ejecucion: "r-contable", asistente: "contable", areas: [.finanzas])
    static let comercial = ContextoDelAsistente(ejecucion: "r-comercial", asistente: "comercial", areas: [.ventas])

    @Test func mikaCreaTareaYQuedaAuditado() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try Self.gobierno(e)
            let r = await g.servidor.llamar("tls_crear_tarea", argumentos: ["titulo": "Revisar la semana", "area": "Dirección"],
                                            contexto: Self.mika())
            #expect(!r.esError, "\(r.texto)")
            let auditoria = try g.autorizador.estado.auditoria(ejecucion: "r-mika")
            #expect(auditoria.contains { $0.accion == "tarea.crear" && $0.decision == "permitido" })
            // Sin tarjeta: ni propuesta ni aprobación.
            #expect(try AlmacenPropuestas(estado: g.autorizador.estado).pendientes().isEmpty)
        }
    }

    @Test func privadoNoEncontradoConAuditoriaDelGobierno() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try Self.gobierno(e)
            let r = await g.servidor.llamar("tls_leer", argumentos: ["ruta": .string(ApoyoMCP.notaPrivada)], contexto: Self.contable)
            #expect(r.texto == "No encontrado.")
            let auditoria = try g.autorizador.estado.auditoria(ejecucion: "r-contable")
            #expect(auditoria.contains { $0.decision == "no_encontrado" })
            // Escribir en lo privado, tampoco.
            let c = await g.servidor.llamar("tls_comentar", argumentos: ["tarea": .string(ApoyoMCP.notaPrivada), "texto": "hola"],
                                            contexto: Self.contable)
            #expect(c.texto == "No encontrado.")
        }
    }

    @Test func interruptorApagadoDeniegaLaSiguienteLlamada() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try Self.gobierno(e)
            let antes = await g.servidor.llamar("tls_estado", argumentos: [:], contexto: Self.mika())
            #expect(!antes.esError, "\(antes.texto)")
            // La persona apaga el interruptor (lo escribe la app como persona: queda confirmado).
            let ruta = VaultPath(".tls/config.yaml")
            let texto = try #require(e.texto(ruta.raw))
            _ = try await e.bus.ejecutar(.guardarNota(ruta, base: texto,
                                                      texto: texto.replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado")),
                                         autor: .persona("Manu"))
            let despues = await g.servidor.llamar("tls_crear_tarea", argumentos: ["titulo": "No debería", "area": "Dirección"],
                                                  contexto: Self.mika("r-2"))
            #expect(despues.esError)
            #expect(despues.texto.contains("apagados"))
            let leer = await g.servidor.llamar("tls_estado", argumentos: [:], contexto: Self.mika("r-2"))
            #expect(leer.esError)
        }
    }

    @Test func solicitarAccionPorAprobacionesDelGobierno() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try Self.gobierno(e)
            let b = await g.servidor.llamar("tls_preparar_borrador", argumentos: [
                "accion": "enviar_correo", "asunto": "Recordatorio de cobro", "cuerpo": "Hola, te recuerdo la factura.",
                "para": ["cliente@example.com"],
            ], contexto: Self.contable)
            #expect(!b.esError, "\(b.texto)")
            let ruta = try #require(ApoyoMCP.objeto(b)["ruta"]?.stringValue)
            let r = await g.servidor.llamar("tls_solicitar_accion",
                                            argumentos: ["accion": "enviar_correo", "borrador_id": .string(ruta)], contexto: Self.contable)
            #expect(ApoyoMCP.objeto(r)["estado"]?.stringValue == "aprobacion_requerida", "\(r.texto)")
            let id = try #require(ApoyoMCP.objeto(r)["id"]?.stringValue)
            let ap = try #require(try ApprovalStore(estado: g.autorizador.estado).aprobacion(id))
            #expect(ap.estado == .pendiente)
            #expect(e.texto(ruta)?.contains(id) == true, "el espejo de la ficha apunta la aprobación")
        }
    }

    @Test func dominioAsistidoEsPropuestaDelGobiernoYNoSeRepite() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try Self.gobierno(e)
            let args: [String: Value] = ["nombre": "Contacto Neutro", "origen": "ext:formulario:42"]
            let r = await g.servidor.llamar("tls_registrar_contacto", argumentos: args, contexto: Self.comercial)
            #expect(ApoyoMCP.objeto(r)["estado"]?.stringValue == "convertida_en_propuesta", "\(r.texto)")
            let otra = await g.servidor.llamar("tls_registrar_contacto", argumentos: args, contexto: Self.comercial)
            #expect(ApoyoMCP.objeto(otra)["estado"]?.stringValue == "ya_registrado", "\(otra.texto)")
            #expect(try AlmacenPropuestas(estado: g.autorizador.estado).pendientes().count == 1)
            // VEN-03 en autónomo: la oportunidad se escribe (como Prospecto) y una segunda vez no se repite.
            let o = await g.servidor.llamar("tls_registrar_oportunidad", argumentos: ["nombre": "Oportunidad Neutra", "origen": "ext:web:9"],
                                            contexto: Self.comercial)
            #expect(ApoyoMCP.objeto(o)["estado"]?.stringValue == "hecho", "\(o.texto)")
            let ruta = try #require(ApoyoMCP.objeto(o)["ruta"]?.stringValue)
            #expect(e.texto(ruta)?.contains("estado: Prospecto") == true)
            let o2 = await g.servidor.llamar("tls_registrar_oportunidad", argumentos: ["nombre": "Oportunidad Neutra", "origen": "ext:web:9"],
                                             contexto: Self.comercial)
            #expect(ApoyoMCP.objeto(o2)["estado"]?.stringValue == "ya_registrado")
        }
    }

    @Test func asistenteInactivoNoHaceNada() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try Self.gobierno(e)
            let marca = ContextoDelAsistente(ejecucion: "r-marca", asistente: "marca", areas: [.marca])
            let r = await g.servidor.llamar("tls_crear_tarea", argumentos: ["titulo": "Idea", "area": "Marca"], contexto: marca)
            #expect(r.esError)
            #expect(r.texto.contains("no está activo"))
        }
    }

    /// La puerta del motor: abrir da un token y el `mcp.json` del servidor `tls`; llamar con él pasa por las mismas
    /// herramientas; revocar lo corta al momento.
    @Test func puertaDelMotor() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try Self.gobierno(e)
            let socket = try MCPHost.rutaDelSocket(vaultID: e.service.entry.id.uuidString, appSupport: e.appSupport)
            let host = MCPHost(socket: socket, validador: PeerValidator(firma: .sinComprobarFirma), manejador: g.servidor,
                               auditoria: e.auditoria)
            let puerta = PuertaMCP(host: host, servidor: g.servidor, helper: URL(fileURLWithPath: "/App.app/Contents/Helpers/tls-mcp"))
            let url = try await puerta.arrancar()
            #expect(url == socket)
            let cred = try await puerta.abrir(ContextoDeEjecucion(ejecucion: "r-puerta", agente: "mika", disparo: .chat,
                                                                  coordinador: true, areas: [.direccion], leeAreas: AreaCode.allCases))
            #expect(cred.token.count == 64)
            #expect(cred.servidor.env[TLSMCPInfo.tokenEnvironmentKey] == cred.token)
            #expect(cred.servidor.args == ["--socket", socket.path])
            let r = await puerta.llamar(herramienta: "tls_crear_tarea", argumentos: #"{"titulo":"Desde la puerta","area":"Dirección"}"#,
                                        credencial: cred)
            #expect(!r.esError, "\(r.texto)")
            #expect((try? JSONSerialization.jsonObject(with: Data(r.texto.utf8))) is [String: Any], "la respuesta es JSON")
            await puerta.revocar(cred)
            let tarde = await puerta.llamar(herramienta: "tls_estado", argumentos: "{}", credencial: cred)
            #expect(tarde.esError)
            await puerta.parar()
            #expect(!FileManager.default.fileExists(atPath: socket.path))
        }
    }
}
