import AppKit
import Foundation
import SwiftUI
import Testing
import TLSAgents
import TLSCore
import TLSDesign
import TLSImport
@testable import TLSOnboarding

/// El andamio de TLSOnboarding (F3 · rol motor): los huecos con su `init`, el modelo y el lanzador de Claude Code del
/// entrevistador con un ejecutable falso dentro del sandbox (nunca se lanza Claude en las pruebas).
@Suite("TLSOnboarding · andamio", .serialized)
@MainActor
struct OnboardingAndamioTests {
    static func tempDir(_ nombre: String) -> URL {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("\(nombre)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func modelo(_ asup: URL) -> ModeloPuesta {
        let id = UUID()
        return ModeloPuesta(motor: OnboardingEngine.abrir(vaultID: id, contexto: .vacio(),
                                                          almacen: AlmacenPuesta(vaultID: id, appSupport: asup)))
    }

    @Test("Cada paso tiene su vista con el init del contrato y se pinta fuera de pantalla")
    func huecos() async throws {
        let asup = Self.tempDir("asup-onb")
        defer { try? FileManager.default.removeItem(at: asup) }
        let m = Self.modelo(asup)
        let vistas: [(String, AnyView)] = [
            ("bienvenida", AnyView(PasoBienvenida(modelo: m))), ("alcance", AnyView(PasoAlcance(modelo: m))),
            ("conocer", AnyView(PasoConocer(modelo: m))), ("ordenar", AnyView(PasoOrdenar(modelo: m))),
            ("organizar", AnyView(PasoOrganizar(modelo: m))), ("sin-ti", AnyView(PasoSinTi(modelo: m))),
            ("dia-a-dia", AnyView(PasoDiaADia(modelo: m))), ("numeros", AnyView(PasoNumeros(modelo: m))),
            ("conectar", AnyView(PasoConectar(modelo: m))), ("recorrido", AnyView(PasoRecorrido(modelo: m))),
            ("flujo", AnyView(OnboardingFlujo(modelo: m))),
        ]
        for (nombre, v) in vistas {
            let r = ImageRenderer(content: v.frame(width: 800, height: 600).background(TLSPaleta.fondo.color))
            r.scale = 1
            let img = try #require(r.nsImage, "No se pinta \(nombre)")
            #expect(img.size.width > 0)
            if let dir = ProcessInfo.processInfo.environment["TLS_CAPTURAS"], !dir.isEmpty, nombre == "flujo" {
                let destino = URL(fileURLWithPath: dir).appendingPathComponent("f3-motor", isDirectory: true)
                try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try png.write(to: destino.appendingPathComponent("puesta-en-marcha-hueco.png"))
                }
            }
        }
        _ = OnboardingVentana(peticion: PeticionPuestaEnMarcha(modo: .empezar))
        _ = OnboardingEscena()
    }

    @Test("El modelo contesta, guarda y avanza; «No lo sé» y «Seguir más tarde»")
    func modelo() async throws {
        let asup = Self.tempDir("asup-onb")
        defer { try? FileManager.default.removeItem(at: asup) }
        let m = Self.modelo(asup)
        #expect(m.pantalla?.id == "bienvenida.como")
        await m.responder(.como, .opcion("cero"))
        if case .pantalla(let p) = m.siguiente() { #expect(p.id == "bienvenida.empresa") } else { Issue.record("No avanzó") }
        // Sin nombre no se sigue (se puede decir «No lo sé»).
        if case .faltan(let f) = m.siguiente() { #expect(f.contains(.nombreEmpresa)) } else { Issue.record("Debía faltar el nombre") }
        m.noLoSe(.yo)
        await m.responder(.nombreEmpresa, .texto("Estudio Prueba"))
        _ = m.siguiente()
        #expect(m.pantalla?.id == "bienvenida.vista")
        m.prepararVistaPrevia()
        #expect(m.vista?.resumen == "Crear 10 ficheros · No se borra nada")
        m.seguirMasTarde()
        #expect(m.motor.almacen?.leer()?.enPausa == true)
        #expect(m.progreso.textoMinutos.hasPrefix("Quedan ~"))
    }

    @Test("Entrevistador con Claude Code: un ejecutable falso dentro del sandbox da la repregunta")
    func lanzadorClaudeCode() async throws {
        let dir = Self.tempDir("tls-claude-falso")
        defer { try? FileManager.default.removeItem(at: dir) }
        let falso = dir.appendingPathComponent("claude")
        let guion = """
        #!/bin/sh
        cat > /dev/null
        echo '{"type":"system","subtype":"init","session_id":"s","tools":["StructuredOutput"],"mcp_servers":[],"permissionMode":"dontAsk","apiKeySource":"none","plugins":[]}'
        echo '{"type":"result","subtype":"success","is_error":false,"result":"","structured_output":{"vaga":true,"repregunta":"¿Cuánto y para cuándo?"}}'
        """
        try Data(guion.utf8).write(to: falso)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: falso.path)
        let flags: Set<String> = ["-p", "--output-format", "--input-format", "--verbose", "--no-session-persistence",
                                  "--restricted", "--tools", "--disable-slash-commands", "--mcp-config", "--strict-mcp-config",
                                  "--allowedTools", "--disallowedTools", "--permission-mode", "--permission-prompts",
                                  "--settings", "--model", "--json-schema", "--max-budget-usd"]
        let empresa = dir.appendingPathComponent("Empresa", isDirectory: true)
        try FileManager.default.createDirectory(at: empresa, withIntermediateDirectories: true)
        let lanzador = LanzadorClaudeCode(probe: ClaudeProbe(claude: falso, help: ClaudeHelp(options: flags)),
                                          estado: dir.appendingPathComponent("estado", isDirectory: true), negadas: [empresa],
                                          tiempo: 20)
        let salida = try await lanzador.pedir("Pregunta de prueba", esquema: InterviewEngine.esquemaJSON)
        #expect(salida.contains("\"vaga\":true"))
        let destino = OnboardingEngine(estado: EstadoPuestaEnMarcha(), contexto: .vacio()).pregunta(.destino)!
        let r = await InterviewEngine(lanzador: lanzador).valorar(destino, respuesta: "Facturar 200.000 € en 2028",
                                                                  conAsistente: true)
        #expect(r == .repreguntar("¿Cuánto y para cuándo?"))
        // El mismo lanzador sirve al clasificador del paso 2 (TLSImport).
        let ejecutor: any EjecutorClasificacion = lanzador
        let datos = try await ejecutor.ejecutar(peticion: "Clasifica", esquema: "{}")
        #expect(String(decoding: datos, as: UTF8.self).contains("\"repregunta\""))
    }
}
