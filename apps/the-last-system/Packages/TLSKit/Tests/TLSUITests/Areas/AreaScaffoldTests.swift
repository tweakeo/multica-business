import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// El andamio de las áreas con una sesión de verdad (Ribera en una carpeta temporal): Meta y Alerta solo cambian esas
/// dos celdas, «Activar» solo esas dos propiedades, todo se deshace y nada se escribe en solo lectura. Y las rutas
/// nuevas de F2 (tarea, decisión, banco, ⌘N).
@Suite("Andamio de las áreas · escritura y rutas", .serialized)
@MainActor
struct AreaScaffoldTests {
    let pruebas = SesionEscrituraTests()
    let metas = VaultPath("1 · Dirección/Metas.md")

    func abrir(clase: VaultClass = .demo, escritura: WriteAccess = .permitida) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: clase, escritura: escritura)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        return (e, sesion)
    }

    func lineasCambiadas(_ antes: String, _ despues: String) -> [String] {
        let a = antes.components(separatedBy: "\n"), d = despues.components(separatedBy: "\n")
        guard a.count == d.count else { return ["(cambia el número de líneas)"] }
        return zip(a, d).filter { $0 != $1 }.map(\.1)
    }

    @Test("Fijar la meta de FIN-CASH cambia solo sus celdas Meta y Alerta; Deshacer deja los mismos bytes")
    func fijarMeta() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloArea(area: .finanzas, sesion: sesion)
        await modelo.cargar()
        let datos = try #require(modelo.datos)
        let caja = try #require(datos.control.first { $0.codigo == "FIN-CASH" })
        #expect(!caja.valorVisible)
        let url = metas.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        #expect(await modelo.guardarMeta(caja, meta: "5000 €", alerta: "2000 | €", deshacer: um))
        um.endUndoGrouping()
        let despues = try String(contentsOf: url, encoding: .utf8)
        #expect(lineasCambiadas(String(decoding: antes, as: UTF8.self), despues) == ["| FIN-CASH | Caja disponible | 5000 € | 2000 / € |  |"])
        #expect(sesion.aviso?.texto == "Meta de FIN-CASH: 5000 €")
        // Al releer, el valor ya se ve: el que calcule el núcleo o «Sin dato» con su motivo, nunca un 0 de relleno.
        await pruebas.esperar { sesion.revision > 0 }
        await modelo.cargar()
        let ahora = try #require(modelo.datos?.control.first { $0.codigo == "FIN-CASH" })
        #expect(ahora.valorVisible && ahora.textoValor != "Oculto hasta fijar la meta")
        #expect(ahora.lectura.valor != nil || ahora.textoValor == "Sin dato")
        #expect(modelo.editando == nil)
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("«Sin meta» escribe esa palabra y vacía la alerta; el dato se ve sin ritmo")
    func sinMeta() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloArea(area: .ventas, sesion: sesion)
        await modelo.cargar()
        let pipe = try #require(modelo.datos?.control.first { $0.codigo == "VEN-PIPE" })
        let antes = try String(contentsOf: metas.url(in: e.carpeta), encoding: .utf8)
        #expect(await modelo.guardarMeta(pipe, meta: "  ", alerta: "algo", deshacer: nil))
        let despues = try String(contentsOf: metas.url(in: e.carpeta), encoding: .utf8)
        #expect(lineasCambiadas(antes, despues) == ["| VEN-PIPE | Cartera abierta | Sin meta |  |  |"])
        await pruebas.esperar { sesion.revision > 0 }
        await modelo.cargar()
        let ahora = try #require(modelo.datos?.control.first { $0.codigo == "VEN-PIPE" })
        #expect(ahora.sinMetaElegida && ahora.valorVisible && ahora.ritmo == .sinMeta)
    }

    @Test("«Activar» pone estado y fecha en Área.md (dos líneas) y se deshace")
    func activar() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let ficha = VaultPath("5 · Marca/Área.md")
        let url = ficha.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let modelo = ModeloArea(area: .marca, sesion: sesion)
        await modelo.cargar()
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        #expect(await modelo.activar(deshacer: um))
        um.endUndoGrouping()
        let despues = try String(contentsOf: url, encoding: .utf8)
        let a = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n")
        let d = despues.components(separatedBy: "\n")
        // Solo dos líneas en las propiedades: `estado` cambia (Ribera trae Marca preparada desde F4) y `activada` es
        // nueva; el resto, igual.
        #expect(d.count == a.count + 1)
        let nuevas = d.filter { !a.contains($0) }
        #expect(nuevas.count == 2)
        #expect(nuevas.contains("estado: activa"))
        #expect(nuevas.contains { $0.hasPrefix("activada:") && $0.contains("2026-10-19") })
        await pruebas.esperar { sesion.revision > 0 }
        await modelo.cargar()
        #expect(modelo.datos?.fase == .activa)
        #expect(sesion.aviso?.texto == "Activaste 5 · Marca")
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("En solo lectura no se escribe: Meta y Activar dicen por qué")
    func soloLectura() async throws {
        let (e, sesion) = try await abrir(clase: .copia, escritura: .bloqueada)
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloArea(area: .finanzas, sesion: sesion)
        await modelo.cargar()
        #expect(modelo.motivoSoloLectura != nil)
        let antes = try Data(contentsOf: metas.url(in: e.carpeta))
        let runway = try #require(modelo.datos?.filaClave)
        #expect(await modelo.guardarMeta(runway, meta: "4 meses", alerta: "1 mes", deshacer: nil) == false)
        #expect(modelo.errorGuardado != nil)
        #expect(try Data(contentsOf: metas.url(in: e.carpeta)) == antes)
    }

    @Test("El andamio se pinta fuera de pantalla en todas sus pestañas sin escribir nada")
    func pinta() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let huella = try Data(contentsOf: metas.url(in: e.carpeta))
        _ = NSApplication.shared
        TLSFuentes.registrar()
        for area in [AreaCode.direccion, .finanzas, .ventas] {
            for p in PestanaArea.allCases {
                let nav = Navegacion(raiz: .area(area, pestana: p.rawValue))
                let vista = PantallaDestino(destino: .area(area, pestana: p.rawValue), sesion: sesion)
                    .environment(e.model).environment(\.navegacion, nav)
                    .frame(width: 1200, height: 900)
                let host = NSHostingView(rootView: vista)
                host.frame = NSRect(x: 0, y: 0, width: 1200, height: 900)
                for _ in 0..<3 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(80)) }
            }
        }
        #expect(try Data(contentsOf: metas.url(in: e.carpeta)) == huella)
    }

    // MARK: Dominio

    @Test("Escribir a través del dominio: Ganada sin cobro se bloquea sin escribir; un cambio normal se deshace")
    func escribirConDominio() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let opo = VaultPath("2 · Ventas/Oportunidades/javier-ortega-renta.md")
        let url = opo.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        await #expect(throws: DominioError.self) {
            try await sesion.escribirConDominio(.cambiarPropiedades(opo, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []))
        }
        #expect(try Data(contentsOf: url) == antes)
        #expect(sesion.aviso?.estado == .atencion)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        let r = try await sesion.escribirConDominio(.cambiarPropiedades(opo, poner: [Property(key: "canal", value: .text("referido"))], quitar: []),
                                                     aviso: "Canal: referido", deshacer: um)
        um.endUndoGrouping()
        #expect(r.escritura.hecho)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("canal: referido"))
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
        // Con escritor, un motor por empresa (el mismo en cada llamada).
        let m = try #require(DominioEmpresa.motor(de: sesion))
        #expect(DominioEmpresa.motor(de: sesion) === m)
    }

    // MARK: Rutas

    @Test("Rutas de F2: identidad, ruta, mover, raíz, nombre en las migas y se guardan con la pestaña")
    func rutas() async throws {
        let t = VaultPath("1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md")
        let cuenta = VaultPath("4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo")
        let destinos: [Destino] = [.tarea(t), .decision("conflicto:1"), .decision(de: t), .banco(nil), .banco(cuenta)]
        for d in destinos {
            let datos = try JSONEncoder().encode(d)
            #expect(try JSONDecoder().decode(Destino.self, from: datos) == d)
            #expect(!d.simbolo.isEmpty)
        }
        #expect(Set(destinos.map(\.identidad)).count == destinos.count)
        #expect(Destino.tarea(t).ruta == t && !Destino.tarea(t).puedeSerRaiz)
        #expect(Destino.decision(de: t).rutaDeDecision == t && Destino.decision("conflicto:1").rutaDeDecision == nil)
        #expect(Destino.banco(nil).puedeSerRaiz && Destino.banco(cuenta).ruta == cuenta)
        let nueva = VaultPath("1 · Dirección/Tareas/t-0001-otra.md")
        #expect(Destino.tarea(t).moviendo(de: t, a: nueva) == .tarea(nueva))
        #expect(Destino.decision(de: t).moviendo(de: t, a: nueva) == .decision(de: nueva))
        #expect(Destino.banco(cuenta).moviendo(de: VaultPath("4 · Finanzas"), a: VaultPath("4 · Dinero"))
                == .banco(VaultPath("4 · Dinero/Registros/Bancos/cuenta-corriente-banco-demo")))
        let h = try JSONEncoder().encode(HojaVentana.nuevaTarea)
        #expect(try JSONDecoder().decode(HojaVentana.self, from: h) == .nuevaTarea)

        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        #expect(sesion.nombre(de: .banco(nil)) == "Banco")
        #expect(sesion.nombre(de: .banco(cuenta)).hasPrefix("Banco · "))
        #expect(sesion.nombre(de: .tarea(t)).contains("Subir Trimestrales"))
        #expect(sesion.nombre(de: .decision(de: t)) == sesion.nombre(de: .tarea(t)))
        #expect(sesion.nombre(de: .decision("conflicto:1")) == "Decisión")
        // ⌘N: la tarea es del área desde la que se abre; desde Banco, de Finanzas.
        #expect(NuevaTareaHoja.areaDe(.area(.marca), sesion: sesion) == .marca)
        #expect(NuevaTareaHoja.areaDe(.banco(nil), sesion: sesion) == .finanzas)
        #expect(NuevaTareaHoja.areaDe(.ficha(t), sesion: sesion) == .direccion)
        #expect(NuevaTareaHoja.areaDe(.hoy, sesion: sesion) == nil)
    }

    @Test("Las pantallas nuevas se pintan con su ruta (tarea, decisión, banco y ⌘N)")
    func huecosSePintan() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let t = VaultPath("1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md")
        let vistas: [AnyView] = [
            AnyView(PantallaDestino(destino: .tarea(t), sesion: sesion)),
            AnyView(PantallaDestino(destino: .decision(de: t), sesion: sesion)),
            AnyView(PantallaDestino(destino: .banco(nil), sesion: sesion)),
            AnyView(PantallaDestino(destino: .decisiones, sesion: sesion)),
            AnyView(PantallaDestino(destino: .tareas, sesion: sesion)),
            AnyView(NuevaTareaHoja(contexto: .area(.finanzas), sesion: sesion)),
        ]
        for v in vistas {
            let host = NSHostingView(rootView: v.environment(e.model).environment(\.navegacion, Navegacion()).frame(width: 1000, height: 700))
            host.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        #expect(Bool(true))
    }
}
