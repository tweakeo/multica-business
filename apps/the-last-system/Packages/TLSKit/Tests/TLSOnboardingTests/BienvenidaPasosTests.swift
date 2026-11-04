import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSOnboarding

/// La bienvenida con carpeta (PLAN §6.7, paso 0): la copia sin lo privado y sin tocar el original, «Ver sin tocar»
/// (solo lee), la pantalla de recuperación si macOS deniega el permiso, y que las carpetas privadas son obligatorias.
/// En pruebas, los nombres privados son neutros («Expediente privado») y los paneles contestan solos.
@Suite("Puesta en marcha · bienvenida con carpeta", .serialized)
@MainActor
struct BienvenidaPasosTests {
    /// Una carpeta de origen en el banco (la fixture G3 con una carpeta privada de nombre neutro).
    static func origen(_ b: Banco) -> URL {
        let o = b.base.appendingPathComponent("Original", isDirectory: true)
        try! FileManager.default.copyItem(at: PasosApoyo.fixtureG3, to: o)
        let p = o.appendingPathComponent("Expediente privado", isDirectory: true)
        try! FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        try! Data("# Nota\nNo se copia.\n".utf8).write(to: p.appendingPathComponent("nota.md"))
        return o
    }

    @Test("«Hacer la copia»: lo privado no se copia, el original no cambia y la puesta en marcha sigue en la copia")
    func copiaSinLoPrivado() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let o = Self.origen(b)
        let antes = huellaDeArbol(o)
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        let idInicial = m.motor.estado.vaultID
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        await m.contestar(.como, .opcion("carpeta"))
        await m.pulsarPrincipal()
        await v.pintar()
        #expect(m.pantalla?.id == "bienvenida.carpeta")
        #expect(m.accionPrincipal == .hacerCopia)
        // Sin carpeta ni respuesta a lo privado, el botón dice por qué no.
        #expect(m.motivoSinPrincipal == "Elige la carpeta de tu empresa.")
        b.paneles.carpeta = o
        await m.elegirCarpetaDeOrigen()
        #expect(m.carpetaDeOrigen?.lastPathComponent == "Original")
        // «Trabajar sobre una copia (recomendado)» llega premarcado.
        #expect(m.motor.valor(.modo)?.opcion == "copia")
        #expect(m.motor.respuesta(.modo)?.origen.clase == .propuesta)
        #expect(m.motivoSinPrincipal == "Dime si hay carpetas privadas.")
        b.paneles.dentro = [VaultPath("Expediente privado"), VaultPath("Privado")]
        await m.elegirPrivadas()
        #expect(m.privadasElegidas == ["Expediente privado", "Privado"])
        #expect(m.motivoSinPrincipal == nil)
        await v.pintar()
        await m.pulsarPrincipal()
        guard case .hecha(let resumen) = m.copia else { Issue.record("La copia no terminó: \(String(describing: m.copia)) \(m.error ?? "")"); return }
        #expect(resumen.contains("copiados y comprobados"))
        #expect(resumen.contains("2 carpetas privadas sin copiar"), "\(resumen)")
        // El original, intacto; la copia, sin lo privado.
        #expect(huellaDeArbol(o) == antes)
        let e = try #require(b.registro.load().first { $0.clase == .copia })
        let copia = URL(fileURLWithPath: e.ruta)
        #expect(e.ruta.hasPrefix(b.empresas.path))
        #expect(!FileManager.default.fileExists(atPath: copia.appendingPathComponent("Expediente privado").path))
        #expect(!FileManager.default.fileExists(atPath: copia.appendingPathComponent("Privado").path))
        #expect(FileManager.default.fileExists(atPath: copia.appendingPathComponent("Empresa.md").path))
        #expect(Set(e.exclusionesCopia).isSuperset(of: ["Expediente privado", "Privado"]))
        // La puesta en marcha sigue en la copia: su estado pasa al id nuevo.
        #expect(m.motor.estado.vaultID == e.id)
        #expect(m.motor.estado.vaultID != idInicial)
        #expect(AlmacenPuesta(vaultID: e.id, appSupport: b.appSupport).leer() != nil)
        #expect(AlmacenPuesta(vaultID: idInicial, appSupport: b.appSupport).leer() == nil)
        #expect(m.ruta == .copiaG3)
        #expect(m.aplicado?.paso == .bienvenida)
        // Y sigue.
        await m.pulsarPrincipal()
        #expect(m.pantalla?.paso == .alcance)
    }

    @Test("«Ver sin tocar»: se registra en solo lectura, se abre y la carpeta no cambia ni se copia")
    func verSinTocar() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let o = Self.origen(b)
        let antes = huellaDeArbol(o)
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("carpeta"))
        await m.pulsarPrincipal()
        b.paneles.carpeta = o
        await m.elegirCarpetaDeOrigen()
        await m.contestar(.modo, .opcion("ver"))
        #expect(m.accionPrincipal == .abrirSinTocar)
        #expect(m.motivoSinPrincipal == "Dime si hay carpetas privadas.")
        b.paneles.dentro = [VaultPath("Expediente privado")]
        await m.elegirPrivadas()
        await m.pulsarPrincipal()
        let e = try #require(b.registro.load().first)
        #expect(e.clase == .real)
        #expect(e.escritura == .bloqueada)
        #expect(e.exclusionesCopia == ["Expediente privado"])
        #expect(m.terminada)
        #expect(b.abiertas == [e.id])
        #expect(b.cerrada == 1)
        #expect(huellaDeArbol(o) == antes, "«Ver sin tocar» solo lee")
        #expect(!FileManager.default.fileExists(atPath: b.empresas.path), "No se copia nada")
        #expect(!b.entorno.recorridoEnCurso(empresa: e.id))
    }

    @Test("Si macOS deniega el permiso: pantalla de recuperación con Ajustes del Sistema y «Volver a intentarlo»")
    func recuperacion() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let o = Self.origen(b)
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        await m.contestar(.como, .opcion("carpeta"))
        await m.pulsarPrincipal()
        b.acceso = .sinPermiso
        b.paneles.carpeta = o
        await m.elegirCarpetaDeOrigen()
        await v.pintar()
        #expect(m.pantalla?.id == "bienvenida.recuperacion")
        #expect(m.pintadas.last == "bienvenida.recuperacion")
        #expect(m.motor.estado.permisoDenegado)
        #expect(m.accionPrincipal == .abrirAjustes)
        await m.pulsarPrincipal()
        #expect(b.ajustes == 1)
        await m.reintentarPermiso()
        #expect(m.pantalla?.id == "bienvenida.recuperacion")
        #expect(m.error?.contains("sigue sin dejar leer") == true)
        b.acceso = .ok
        await m.reintentarPermiso()
        #expect(m.pantalla?.id == "bienvenida.carpeta")
        #expect(!m.motor.estado.permisoDenegado)
        #expect(m.error == nil)
    }

    @Test("Otra carpeta de origen: lo privado hay que volver a decirlo")
    func otraCarpeta() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let o = Self.origen(b)
        let otra = b.base.appendingPathComponent("Otra", isDirectory: true)
        try FileManager.default.createDirectory(at: otra, withIntermediateDirectories: true)
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("carpeta"))
        await m.pulsarPrincipal()
        b.paneles.carpeta = o
        await m.elegirCarpetaDeOrigen()
        await m.contestar(.modo, .opcion("copia"))
        await m.noHayPrivadas()
        #expect(m.faltaParaLaCarpeta == nil)
        b.paneles.carpeta = otra
        await m.elegirCarpetaDeOrigen()
        #expect(m.faltaParaLaCarpeta == "Dime si hay carpetas privadas.")
        await m.noHayPrivadas()
        #expect(m.faltaParaLaCarpeta == nil)
    }
}
