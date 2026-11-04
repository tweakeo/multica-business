import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSOnboarding

/// Criterio F3-2 contado recorriendo el motor **y las vistas**: cada pantalla se pinta en una ventana que no se enseña y
/// se pasa con el botón de verdad (`pulsarPrincipal`, el mismo que ↩). La copia de G3 (fixture y Ribera), 15 o menos; la
/// empresa nueva en el peor caso (todo y las seis áreas activas), 40 o menos. Por el camino, «Aplicar» escribe de
/// verdad en copias temporales, lo escrito es lo que enseñaba la vista previa y «No lo sé» queda PENDIENTE.
@Suite("Puesta en marcha · pantallas por ruta (F3-2)", .serialized)
@MainActor
struct RutasPasosTests {
    @Test("Copia de G3 (fixture): 15 pantallas o menos, pintadas y pasadas con los botones")
    func copiaG3() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let e = b.carpeta(copiando: PasosApoyo.fixtureG3, nombre: "Estudio", privadas: ["Privado"])
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        #expect(m.ruta == .copiaG3)
        #expect(m.yaHayCarpeta)
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        let r = try await Recorrido.hasta(fin: m, ventana: v, banco: b)
        #expect(m.terminada)
        #expect(r.vistas.count <= 15, "La copia de G3 tiene \(r.vistas.count) pantallas: \(r.vistas)")
        #expect(r.vistas.count >= 10)
        // Cada pantalla contada se pintó (la vista llegó a la pantalla, no solo el motor).
        #expect(Set(r.vistas).isSubset(of: Set(r.pintadas)), "Sin pintar: \(Set(r.vistas).subtracting(r.pintadas))")
        #expect(Set(m.motor.pantallas.map(\.paso)) == Set(PasoPuesta.allCases))
        // Se aplicó de verdad (Conocer, Organizar, Qué funciona sin ti, Tu día a día, Tus números).
        #expect(Set(r.aplicados).isSuperset(of: [.conocer, .organizar, .diaADia, .numeros]), "\(r.aplicados)")
        // Lo privado sigue sin tocar.
        let privado = URL(fileURLWithPath: e.ruta).appendingPathComponent("Privado")
        #expect(huellaDeArbol(privado) == huellaDeArbol(PasosApoyo.fixtureG3.appendingPathComponent("Privado")))
        // Al terminar: el recorrido con su empresa empieza y se abre la empresa.
        #expect(b.abiertas == [e.id])
        #expect(b.cerrada == 1)
        #expect(b.entorno.recorridoEnCurso(empresa: e.id))
    }

    @Test("Copia de Ribera: 15 pantallas o menos y lo escrito es lo que enseñó la vista previa")
    func copiaRibera() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let e = b.carpeta(copiando: PasosApoyo.ribera, nombre: "Ribera")
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        #expect(m.ruta == .copiaG3)
        let root = URL(fileURLWithPath: e.ruta)
        var comprobados = 0
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        let r = try await Recorrido.hasta(fin: m, ventana: v, banco: b, alAplicar: { m in
            guard let vp = m.vista, !vp.nadaQueEscribir else { return }
            for c in vp.cambios {
                guard let d = c.despues else { continue }
                let escrito = try? String(contentsOf: c.ruta.url(in: root), encoding: .utf8)
                #expect(escrito == d, "\(vp.paso): \(c.ruta.raw) no es lo que enseñó la vista previa")
            }
            comprobados += 1
        })
        #expect(r.vistas.count <= 15, "\(r.vistas.count): \(r.vistas)")
        #expect(comprobados >= 3, "Solo se comprobaron \(comprobados) pasos")
    }

    @Test("Empresa nueva, peor caso: 40 pantallas o menos, creando la carpeta y aplicando cada paso")
    func empresaNueva() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        #expect(m.ruta == .empresaNueva)
        // Antes de «Crear la carpeta» no existe nada en el disco.
        #expect(!FileManager.default.fileExists(atPath: b.empresas.path))
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        var minutos: [Int] = []
        let r = try await Recorrido.hasta(fin: m, ventana: v, banco: b, usar: { q in
            q.id == .sector ? .noLoSe : nil
        }, enPantalla: { m, _ in
            // Desde que se sabe la ruta (tras «¿Cómo empiezas?»).
            if m.pantalla?.id != "bienvenida.como" { minutos.append(m.progreso.quedanMinutos) }
            if m.pantalla?.id == "bienvenida.vista" {
                #expect(!FileManager.default.fileExists(atPath: b.empresas.path), "Se escribió antes de «Crear la carpeta»")
            }
        })
        #expect(m.terminada)
        #expect(r.vistas.count <= 40, "La empresa nueva tiene \(r.vistas.count) pantallas")
        #expect(r.vistas.count >= 25)
        #expect(Set(r.vistas).isSubset(of: Set(r.pintadas)))
        #expect(!r.vistas.contains { $0.hasPrefix("ordenar.") })
        #expect(minutos == minutos.sorted(by: >), "«Quedan ~N min» solo baja: \(minutos)")
        // La carpeta existe, está registrada y tiene lo de cada paso.
        let e = try #require(b.registro.load().first { $0.id == m.motor.estado.vaultID })
        let root = URL(fileURLWithPath: e.ruta)
        let empresa = try String(contentsOf: root.appendingPathComponent("Empresa.md"), encoding: .utf8)
        #expect(empresa.contains("PENDIENTE · A qué se dedica"), "«No lo sé» se escribe PENDIENTE (F3-5)")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("1 · Dirección/Diagnóstico.md").path))
        // La etapa que se escribe es la de las preguntas de etapa (sí, sí, no → 3), no la que calcula la app al crear.
        let leido = ContextoCarpeta.leer(root, entrada: e)
        for a in AreaCode.allCases {
            #expect(leido.premarcada(.etapa(a))?.valor == .escala(3), "Etapa de \(a.nombre) en el Diagnóstico")
        }
        #expect(Set(r.aplicados).isSuperset(of: [.bienvenida, .conocer, .organizar, .sinTi, .diaADia, .numeros]))
        #expect(b.abiertas == [e.id])
    }

    @Test("Ver un ejemplo: una pantalla y a la empresa de ejemplo (o al selector si la app no lo ha enganchado)")
    func verUnEjemplo() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let ejemplo = VaultEntry(nombre: "Asesoría Ribera", ruta: b.base.path, bookmark: nil, clase: .demo, escritura: .permitida)
        b.entorno.instalarEjemplo = { ejemplo }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        await v.pintar()
        await m.contestar(.como, .opcion("ejemplo"))
        await v.pintar()
        #expect(m.pantallas.count == 1)
        #expect(m.accionPrincipal == .abrirEjemplo)
        #expect(m.progreso.quedanMinutos <= 2)
        await m.pulsarPrincipal()
        #expect(b.abiertas == [ejemplo.id])
        #expect(b.cerrada == 1)
        // Sin el enganche de la app: el selector, que tiene «Ver un ejemplo».
        let b2 = Banco()
        defer { b2.limpiar() }
        let m2 = b2.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m2.contestar(.como, .opcion("ejemplo"))
        await m2.pulsarPrincipal()
        #expect(b2.selector == 1)
        #expect(b2.cerrada == 1)
    }
}
