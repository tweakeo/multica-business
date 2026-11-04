import AppKit
import Foundation
import Testing
import TLSCore
@testable import TLSUI

@Suite("Navegación en profundidad")
@MainActor
struct NavegacionTests {
    let nexo = VaultPath("2 · Ventas/Empresas/arquitectura-nexo.md")
    let trimestrales = VaultPath("2 · Ventas/Oportunidades/arquitectura-nexo-trimestrales.md")
    let factura = VaultPath("4 · Finanzas/Fiscal/Borradores/factura-nexo.md")
    let proyecto = VaultPath("3 · Entrega/Proyectos/trimestrales-2026/Proyecto.md")

    @Test("Entrar crece las migas; ⌘[ y ⌘] recorren el historial como Finder")
    func atrasAdelante() {
        let nav = Navegacion()
        nav.nuevaRaiz(.area(.ventas))
        nav.entrar(.ficha(nexo))
        nav.entrar(.ficha(trimestrales))
        #expect(nav.migas == [.area(.ventas), .ficha(nexo), .ficha(trimestrales)])
        nav.irAtras()
        #expect(nav.actual == .ficha(nexo))
        nav.irAtras()
        #expect(nav.actual == .area(.ventas))
        nav.irAtras()
        #expect(nav.actual == .hoy)
        #expect(!nav.puedeIrAtras)
        nav.irAdelante(); nav.irAdelante(); nav.irAdelante()
        #expect(nav.migas == [.area(.ventas), .ficha(nexo), .ficha(trimestrales)])
        #expect(!nav.puedeIrAdelante)
        // Navegar desde un punto del historial borra lo de adelante.
        nav.irAtras()
        nav.entrar(.ficha(factura))
        #expect(!nav.puedeIrAdelante)
        #expect(nav.migas.last == .ficha(factura))
    }

    @Test("Sin bucles: entrar en algo que ya está en las migas las recorta hasta ello")
    func sinBucles() {
        let nav = Navegacion(raiz: .area(.ventas))
        nav.entrar(.ficha(nexo))
        nav.entrar(.ficha(trimestrales))
        nav.entrar(.ficha(nexo, pestana: "Proyectos"))
        #expect(nav.migas == [.area(.ventas), .ficha(nexo, pestana: "Proyectos")])
        // Atrás vuelve a donde se estaba antes del recorte.
        nav.irAtras()
        #expect(nav.migas.count == 3)
    }

    @Test("Cambiar de pestaña dentro de una ficha no es un paso del historial, pero se recuerda")
    func pestanaNoEsPaso() {
        let nav = Navegacion(raiz: .base("empresas"))
        nav.entrar(.ficha(nexo))
        let pasos = nav.atras.count
        nav.cambiarPestana("Proyectos")
        #expect(nav.atras.count == pasos)
        #expect(nav.actual == .ficha(nexo, pestana: "Proyectos"))
        nav.entrar(.ficha(proyecto))
        #expect(nav.pestanasDeOrigen[2] == "Proyectos")
        nav.irAtras()
        #expect(nav.actual == .ficha(nexo, pestana: "Proyectos"))
    }

    /// Criterio §11.1: base Empresas → empresa → pestaña Proyectos → proyecto (3 clics). ⌘[ vuelve a la
    /// empresa en Proyectos y otro, a la base con el mismo desplazamiento y los mismos filtros.
    @Test("Criterio §11.1: volver deja la pestaña, el desplazamiento y los filtros como estaban")
    func criterioVolver() {
        let nav = Navegacion()
        nav.nuevaRaiz(.base("empresas"))
        nav.guardar(RecuerdoPantalla(desplazamiento: 640, filtros: ["estado": "Activo"], seleccion: [nexo.raw]),
                    de: .base("empresas"))
        nav.entrar(.ficha(nexo))
        nav.cambiarPestana("Proyectos")
        nav.entrar(.ficha(proyecto))
        #expect(nav.migas.count == 3)

        nav.irAtras()
        #expect(nav.actual == .ficha(nexo, pestana: "Proyectos"))
        nav.irAtras()
        #expect(nav.actual == .base("empresas"))
        let r = nav.recuerdo(de: nav.actual)
        #expect(r.desplazamiento == 640)
        #expect(r.filtros == ["estado": "Activo"])
        #expect(r.seleccion == [nexo.raw])
    }

    @Test("Clic en una miga: vuelves a ese nivel y lo que quitas queda en Adelante")
    func miga() {
        let nav = Navegacion(raiz: .hoy)
        nav.nuevaRaiz(.area(.ventas))
        nav.entrar(.base("contactos"))
        nav.entrar(.ficha(nexo))
        nav.entrar(.ficha(proyecto))
        nav.volver(a: 1)
        #expect(nav.migas == [.area(.ventas), .base("contactos")])
        #expect(nav.atras.last?.actual == .area(.ventas))
        nav.irAdelante()
        #expect(nav.actual == .ficha(nexo))
        nav.irAdelante()
        #expect(nav.actual == .ficha(proyecto))
        // ⌘↑ sube un nivel.
        nav.subir()
        #expect(nav.actual == .ficha(nexo))
    }

    @Test("Lo que pide el NavigationStack se trata como volver o entrar")
    func ajustarPila() {
        let nav = Navegacion(raiz: .area(.ventas))
        nav.ajustarPila([.ficha(nexo), .ficha(trimestrales)])
        #expect(nav.pila == [.ficha(nexo), .ficha(trimestrales)])
        nav.ajustarPila([.ficha(nexo)])
        #expect(nav.pila == [.ficha(nexo)])
        #expect(nav.puedeIrAdelante)
    }

    @Test("Renombrar o mover algo que está en las migas o el historial no rompe el camino")
    func movimientos() {
        let nav = Navegacion(raiz: .carpeta(VaultPath("2 · Ventas")))
        nav.entrar(.ficha(nexo))
        nav.guardar(RecuerdoPantalla(desplazamiento: 10), de: .ficha(nexo))
        nav.entrar(.ficha(trimestrales))
        let nuevo = VaultPath("2 · Ventas/Empresas/nexo-arquitectura.md")
        nav.aplicarMovimientos([(de: nexo, a: nuevo), (de: VaultPath("2 · Ventas"), a: VaultPath("2 · Comercial"))])
        #expect(nav.raiz == .carpeta(VaultPath("2 · Comercial")))
        #expect(nav.pila.first == .ficha(VaultPath("2 · Comercial/Empresas/nexo-arquitectura.md")))
        #expect(nav.recuerdo(de: .ficha(VaultPath("2 · Comercial/Empresas/nexo-arquitectura.md"))).desplazamiento == 10)
    }

    @Test("Al cerrar y abrir, cada pestaña vuelve a su camino (estado codificado)")
    func restaurar() throws {
        let nav = Navegacion(raiz: .area(.finanzas, pestana: "Control"))
        nav.entrar(.base("facturas", vista: "Borradores", contexto: nexo))
        nav.entrar(.fichero(VaultPath("4 · Finanzas/factura.pdf")))
        nav.guardar(RecuerdoPantalla(filtros: ["estado": "Borrador"]), de: .base("facturas", vista: "Borradores", contexto: nexo))
        let datos = try #require(nav.codificado)
        let otra = Navegacion()
        otra.restaurar(datos)
        #expect(otra.migas == nav.migas)
        #expect(otra.atras == nav.atras)
        #expect(otra.recuerdo(de: .base("facturas", vista: "Borradores", contexto: nexo)).filtros == ["estado": "Borrador"])
        // Datos que no se pueden leer no cambian nada.
        otra.restaurar(Data("no".utf8))
        #expect(otra.migas == nav.migas)
    }

    @Test("El historial no crece sin límite")
    func limite() {
        let nav = Navegacion()
        for i in 0..<120 { nav.nuevaRaiz(.busqueda("q\(i)")) }
        #expect(nav.atras.count == Navegacion.limiteHistorial)
    }

    @Test("A dónde lleva una ruta: ficha, nota, fichero o carpeta")
    func destinoPara() {
        #expect(Destino.para(nexo, tipo: .organization, esCarpeta: false) == .ficha(nexo))
        #expect(Destino.para(VaultPath("Notas/idea.md"), tipo: .note, esCarpeta: false) == .nota(VaultPath("Notas/idea.md")))
        #expect(Destino.para(VaultPath("x.csv"), tipo: .csv, esCarpeta: false) == .nota(VaultPath("x.csv")))
        #expect(Destino.para(VaultPath("a/factura.pdf"), tipo: .other, esCarpeta: false) == .fichero(VaultPath("a/factura.pdf")))
        #expect(Destino.para(VaultPath("2 · Ventas"), tipo: nil, esCarpeta: true) == .carpeta(VaultPath("2 · Ventas")))
        #expect(Destino.para(.root, tipo: nil, esCarpeta: true) == .carpeta(nil))
        #expect(!Destino.ficha(nexo).puedeSerRaiz && Destino.base("x").puedeSerRaiz)
    }

    @Test("⌘clic, ⇧⌘clic y ⌥⌘clic: pestaña detrás, delante y ventana nueva")
    func teclas() {
        #expect(NavegarAccion.modo(teclas: []) == .entrar)
        #expect(NavegarAccion.modo(teclas: [.command]) == .pestanaNueva)
        #expect(NavegarAccion.modo(teclas: [.command, .shift]) == .pestanaNuevaAlFrente)
        #expect(NavegarAccion.modo(teclas: [.command, .option]) == .ventanaNueva)
    }

    @Test("Abrir en pestaña nueva lleva el camino natural y no toca la pestaña de origen")
    func pestanaNueva() {
        let nav = Navegacion(raiz: .area(.ventas))
        nav.entrar(.ficha(nexo))
        nav.numeroVentana = 42
        @MainActor final class Caja { var rutas: [VentanaRuta] = [] }
        let caja = Caja()
        let accion = NavegarAccion(nav: nav, empresa: UUID()) { caja.rutas.append($0) }
        var abiertas: [VentanaRuta] { caja.rutas }
        accion(.ficha(proyecto), modo: .pestanaNueva)
        #expect(nav.actual == .ficha(nexo))
        let r = abiertas.first
        #expect(r?.destino == .area(.ventas))
        #expect(r?.sembrar == [.ficha(nexo), .ficha(proyecto)])
        #expect(r?.alFrente == false && r?.origen == 42 && r?.nuevaVentana == false)
        accion(.todasLasBases, modo: .ventanaNueva)
        #expect(abiertas.last?.destino == .todasLasBases && abiertas.last?.nuevaVentana == true)
        // Cada apertura es una ventana distinta aunque el destino sea el mismo.
        accion(.todasLasBases, modo: .pestanaNuevaAlFrente)
        #expect(abiertas[1].id != abiertas[2].id)
    }
}
