import Foundation
import Testing
import TLSCore
@testable import TLSUI

@Suite("Barra lateral")
@MainActor
struct BarraLateralTests {
    private func elementos(_ m: BarraLateralModelo) -> [ElementoBarra] { m.filas.map(\.elemento) }

    @Test("Orden de serie: Hoy · Decisiones · Tareas · Áreas · Bases (6 fijadas y «Todas») · Asistentes · Carpeta · Ajustes")
    func deSerie() {
        let m = BarraLateralModelo(archivo: nil)
        let e = elementos(m)
        #expect(Array(e.prefix(4)) == [.hoy, .decisiones, .tareas, .seccion(.areas)])
        #expect(e.filter { if case .area = $0 { return true }; return false }.count == 6)
        #expect(e.filter { if case .base = $0 { return true }; return false }.map(\.id)
                == BaseConocida.fijadasDeSerie.map { "base.\($0)" })
        #expect(Array(e.suffix(4)) == [.todasLasBases, .asistentes, .carpeta, .ajustes])
        #expect(BaseConocida.deSerie.count == 24)
        #expect(Set(BaseConocida.deSerie.map(\.id)).count == 24)
    }

    @Test("Ocultar y mostrar: vuelve a su sitio; Hoy no se oculta; con aviso y Deshacer")
    func ocultarMostrar() {
        let m = BarraLateralModelo(archivo: nil)
        let antes = elementos(m)
        m.ocultar(.area(.equipo))
        #expect(!elementos(m).contains(.area(.equipo)))
        #expect(m.ocultos.map(\.elemento) == [.area(.equipo)])
        #expect(m.aviso?.texto == "Ocultaste 6 · Equipo")
        m.mostrar(.area(.equipo))
        #expect(elementos(m) == antes)
        m.ocultar(.hoy)
        #expect(elementos(m) == antes)
        // «Deshacer» del aviso.
        m.ocultar(.carpeta)
        m.aviso?.accion?()
        #expect(elementos(m) == antes)
    }

    @Test("Meter dentro y sacar: no el primero de su sección; mover con ⌥⌘↑ ⌥⌘↓")
    func sangria() {
        let m = BarraLateralModelo(archivo: nil)
        #expect(!m.sePuedeMeter(.area(.direccion)), "es el primero de Áreas")
        m.meterDentro(.area(.direccion), true)
        #expect(!m.estaDentro(.area(.direccion)))
        m.meterDentro(.area(.ventas), true)
        #expect(m.estaDentro(.area(.ventas)))
        #expect(m.padre(de: .area(.ventas)) == .area(.direccion))
        m.meterDentro(.area(.ventas), false)
        #expect(!m.estaDentro(.area(.ventas)))
        m.desplazar(.tareas, -1)
        #expect(Array(elementos(m).prefix(3)) == [.hoy, .tareas, .decisiones])
        // Al mover algo metido dentro justo después de un rótulo, sale del grupo.
        m.meterDentro(.area(.ventas), true)
        m.mover(.area(.ventas), antesDe: .area(.direccion), dentro: true)
        #expect(!m.estaDentro(.area(.ventas)))
    }

    @Test("Cada cambio se deshace y se rehace con el UndoManager de la ventana")
    func deshacer() {
        let m = BarraLateralModelo(archivo: nil)
        let um = UndoManager()
        um.groupsByEvent = false
        let antes = elementos(m)
        um.beginUndoGrouping()
        m.ocultar(.area(.marca), deshacer: um)
        um.endUndoGrouping()
        #expect(um.canUndo)
        um.undo()
        #expect(elementos(m) == antes)
        #expect(um.canRedo)
        um.redo()
        #expect(!elementos(m).contains(.area(.marca)))
    }

    @Test("Bases: fijar y desfijar desde fuera; «Mostrar en la barra lateral» fija la que falta")
    func bases() {
        let m = BarraLateralModelo(archivo: nil)
        #expect(m.estaFijada("contactos"))
        m.desfijarBase("contactos")
        #expect(!m.estaFijada("contactos"))
        m.fijarBase("gastos")
        let e = elementos(m)
        #expect(e.firstIndex(of: .base("gastos")) == (e.firstIndex(of: .todasLasBases) ?? 0) - 1)
        m.mostrarEnBarra(Destino.base("contactos"))
        #expect(m.estaFijada("contactos"))
        m.describirBase(BaseConocida(id: "mi-base", nombre: "Mi base", icono: "star", area: .marca))
        m.fijarBase("mi-base")
        #expect(m.nombre(.base("mi-base")) == "Mi base")
        #expect(ElementoBarra.para(.base("mi-base")) == .base("mi-base"))
        #expect(ElementoBarra.para(.base("mi-base", vista: "x")) == nil)
    }

    @Test("Se guarda por empresa fuera de la carpeta y se vuelve a leer igual")
    func persistencia() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tls-barra-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let archivo = dir.appendingPathComponent("barra-lateral.json")
        let m = BarraLateralModelo(archivo: archivo)
        m.ocultar(.decisiones)
        m.meterDentro(.area(.entrega), true)
        m.describirBase(BaseConocida(id: "mi-base", nombre: "Mi base", icono: "star", area: nil))
        m.fijarBase("mi-base")
        let otra = BarraLateralModelo(archivo: archivo)
        #expect(otra.filas == m.filas)
        #expect(otra.ocultos == m.ocultos)
        #expect(otra.nombre(.base("mi-base")) == "Mi base")
        m.restaurarOriginal()
        #expect(BarraLateralModelo(archivo: archivo).filas == BarraLateralModelo.filasDeSerie)
    }

    @Test("El elemento elegido sale de la raíz de la pestaña")
    func elegido() {
        #expect(ElementoBarra.para(.area(.ventas, pestana: "Control")) == .area(.ventas))
        #expect(ElementoBarra.para(.carpeta(nil)) == .carpeta)
        #expect(ElementoBarra.para(.carpeta(VaultPath("x"))) == nil)
        #expect(ElementoBarra.para(.ficha(VaultPath("x.md"))) == nil)
        #expect(ElementoBarra.hoy.destino == .hoy && ElementoBarra.seccion(.areas).destino == nil)
    }
}
