import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSOnboarding

/// Lo que hacen los botones de las pantallas: nada se escribe antes de «Aplicar» (F3-1), «Seguir más tarde» y retomar
/// en la misma pregunta con lo escrito (F3-3), «No lo sé» (F3-5), la repregunta del entrevistador una sola vez,
/// «Deshacer», «Saltar este paso», «Atrás» y Claude Code (con un detector falso: nunca se lanza el de verdad).
@Suite("Puesta en marcha · botones de las pantallas", .serialized)
@MainActor
struct ComportamientoPasosTests {
    @Test("F3-1: recorrer la copia de G3 entera preparando cada vista previa y sin aplicar no escribe nada")
    func nadaAntesDeAplicar() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let e = b.carpeta(copiando: PasosApoyo.fixtureG3, nombre: "Estudio", privadas: ["Privado"])
        let root = URL(fileURLWithPath: e.ruta)
        let antes = huellaDeArbol(root)
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        var previas = 0
        for _ in 0..<60 {
            guard !m.terminada, let p = m.pantalla else { break }
            await v.pintar()
            await Respuestas.contestarPantalla(m) { q in q.id == .destino ? .noLoSe : nil }
            if p.conVistaPrevia, p.paso.escribeEnLaCarpeta, p.paso != .bienvenida, p.paso != .ordenar, !m.pasoHecho(p.paso) {
                m.prepararVistaPrevia()
                if m.vista?.plan != nil { previas += 1 }
            }
            if p.paso.escribeEnLaCarpeta, p.paso != .bienvenida, !m.pasoHecho(p.paso) {
                await m.saltarPaso()
            } else {
                await m.pulsarPrincipal()
            }
        }
        #expect(m.terminada)
        #expect(previas >= 4, "Solo \(previas) vistas previas con algo que escribir")
        #expect(huellaDeArbol(root) == antes, "La carpeta cambió sin pulsar «Aplicar»")
        #expect(m.motor.estado.paso(.organizar).fase == .omitido)
    }

    @Test("F3-3: «Seguir más tarde», cerrar y abrir: misma pantalla y lo escrito (también lo que estaba a medio escribir)")
    func seguirMasTardeYRetomar() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("cero"))
        await m.pulsarPrincipal()
        #expect(m.pantalla?.id == "bienvenida.empresa")
        await m.contestar(.sector, .texto("Asesoría fiscal"))
        m.borradores[.nombreEmpresa] = "Estudio Retomado"
        await m.seguirMasTardeYCerrar()
        #expect(b.cerrada == 1)
        let id = m.motor.estado.vaultID
        #expect(AlmacenPuesta(vaultID: id, appSupport: b.appSupport).leer()?.enPausa == true)
        let otra = b.modelo(PeticionPuestaEnMarcha(modo: .retomar, vaultID: id))
        #expect(otra.pantalla?.id == "bienvenida.empresa")
        #expect(otra.motor.valor(.nombreEmpresa) == .texto("Estudio Retomado"))
        #expect(otra.motor.valor(.sector) == .texto("Asesoría fiscal"))
        #expect(otra.progreso.enPausa == false)
    }

    @Test("F3-5: «No lo sé» se marca, se ve como PENDIENTE y deja seguir")
    func noLoSe() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("cero"))
        await m.pulsarPrincipal()
        await m.pulsarPrincipal()
        #expect(m.faltan.contains(.nombreEmpresa), "Sin nombre no se sigue")
        #expect(m.error?.contains("No lo sé") == true)
        m.noLoSeYGuardar(.yo)
        #expect(m.respuesta(.yo)?.valor == .noLoSe)
        m.borradores[.nombreEmpresa] = "Estudio Prueba"
        await m.pulsarPrincipal()
        #expect(m.pantalla?.id == "bienvenida.vista")
    }

    @Test("La repregunta del entrevistador sale una vez y no deja seguir hasta verla")
    func repregunta() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("cero"))
        m.actualizar { $0.ir(a: "conocer.destino") }
        #expect(m.pantalla?.id == "conocer.destino")
        m.borradores[.destino] = "Crecer mucho y tener más tiempo libre"
        await m.pulsarPrincipal()
        #expect(m.pantalla?.id == "conocer.destino", "Primero se enseña la repregunta")
        #expect(m.repreguntas[.destino] != nil)
        await m.pulsarPrincipal()
        #expect(m.pantalla?.id != "conocer.destino", "La segunda vez sigue")
    }

    @Test("Con consentimiento, el entrevistador usa Claude Code (falso); sin él, nada")
    func claudeConConsentimiento() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.usarAsistenteYConectar(true)
        #expect(m.claude.encontrado)
        #expect(m.motor.entrevista.lanzador != nil)
        await m.contestar(.como, .opcion("cero"))
        m.actualizar { $0.ir(a: "conocer.frase") }
        m.borradores[.fraseCliente] = "autónomos de Valencia que facturan poco"
        await m.guardarBorradores()
        #expect(m.repreguntas[.fraseCliente] == "¿Con qué número lo medirás?")
        #expect(!b.detector.lanzadorFalso.mensajes.isEmpty)
        await m.usarAsistenteYConectar(false)
        #expect(m.motor.entrevista.lanzador == nil)
        // Paso 7: se busca al llegar y se prueba con «Probar».
        let m2 = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m2.contestar(.como, .opcion("cero"))
        m2.actualizar { $0.ir(a: "conectar") }
        await m2.detectarClaude()
        #expect(m2.claude == .encontrado(version: "2.1.307", aviso: nil))
        await m2.probarClaude()
        #expect(m2.claude == .probado(ok: true, texto: "Funciona."))
        b.detector.hay = false
        let m3 = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m3.detectarClaude()
        #expect(m3.claude == .noEncontrado)
    }

    @Test("«Aplicar» y «Deshacer» en Tu día a día (Ribera): lo cambiado vuelve y lo creado va a Archivo")
    func aplicarYDeshacer() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let e = b.carpeta(copiando: PasosApoyo.ribera, nombre: "Ribera")
        let root = URL(fileURLWithPath: e.ruta)
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        func fuera(_ h: [String]) -> [String] { h.filter { !$0.hasPrefix("/Archivo/") && !$0.hasPrefix("/.tls/escritor.json") } }
        let antes = fuera(huellaDeArbol(root))
        m.actualizar { $0.ir(a: "dia-a-dia.rutina") }
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        await v.pintar()
        await m.contestar(.rutinaDia, .opcion("martes"))
        m.borradores[.topeHoras] = "5"
        #expect(m.accionPrincipal == .aplicar)
        await m.pulsarPrincipal()
        #expect(m.pasoHecho(.diaADia), "\(m.error ?? "")")
        #expect(m.aplicado?.sePuedeDeshacer == true)
        #expect(fuera(huellaDeArbol(root)) != antes)
        await v.pintar()
        await m.deshacerPaso(.diaADia)
        #expect(!m.pasoHecho(.diaADia), "\(m.error ?? "")")
        #expect(fuera(huellaDeArbol(root)) == antes, "Deshacer deja lo de fuera de Archivo como estaba")
    }

    @Test("«Atrás» vuelve a la pantalla anterior y «Saltar este paso» lo deja para más tarde sin escribir")
    func atrasYSaltar() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("cero"))
        await m.pulsarPrincipal()
        #expect(m.pantalla?.id == "bienvenida.empresa")
        await m.atras()
        #expect(m.pantalla?.id == "bienvenida.como")
        m.actualizar { $0.ir(a: "organizar.estados") }
        await m.saltarPaso()
        #expect(m.motor.estado.paso(.organizar).fase == .omitido)
        #expect(m.pantalla?.paso == .sinTi || m.pantalla?.paso == .diaADia)
    }
}
