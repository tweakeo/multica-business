import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Hoy (PLAN §6.2 y criterio 5 de F2): exactamente un foco; la sección Alertas solo existe si hay algo en rojo
/// (Ribera alternando datos); con los registros vacíos, «Sin dato», nunca 0; lo privado no aparece.
@Suite("Hoy · un foco, alertas solo con rojo, sin ceros inventados", .serialized)
@MainActor
struct HoyTests {
    @Test("Ribera a 19/10: la frase, el único foco (el objetivo de ventas), 2 decisiones y 5 cosas en rojo")
    func ribera() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let d = c.hoy()
        #expect(d.frase == "2 cosas piden tu decisión. Hoy no tienes nada planificado.")
        #expect(d.foco.titulo == "6.000 € de ventas cobradas al mes: vas al 0\u{00A0}% de lo previsto")
        #expect(d.foco.boton.etiqueta == "Decidir el plan")
        #expect(d.panel.mazo.mostradas.filter { $0.id == d.foco.id }.count == 1)
        #expect(d.decisiones.map(\.titulo) == ["¿Dejar que Comercial prepare los recordatorios de propuesta con plantilla?",
                                               "¿Subir Trimestrales a 165 € desde T1 2027?"])
        #expect(d.pendientes == 2)
        #expect(d.alertas.count == 5)
        #expect(d.secciones(hayQueRevisar: false) == [.cabecera, .foco, .decisiones, .alertas, .inicio, .mika])
        #expect(d.secciones(hayQueRevisar: true) == [.cabecera, .foco, .revisar, .decisiones, .alertas, .inicio, .mika])
        #expect(d.lineaMika == "Revisé a las 8:45: 5 cosas en rojo (Finanzas, Marca y Ventas).")
        #expect(d.areasEnRojo == [.finanzas, .marca, .ventas])
        #expect(d.textoDia == "Nada planificado")
        // Los módulos con dato de Ribera.
        #expect(d.modulos.caja.saldoTexto == "26.664,65 €")
        #expect(d.modulos.caja.runwayTexto == "7,9 meses de caja")
        #expect(d.modulos.cifra(.cobros).cifra == "1")
        #expect(d.modulos.cifra(.cobros).linea?.hasPrefix("181,50 € de Talleres Martín") == true)
        #expect(d.modulos.cifra(.sinConciliar).cifra == "1")
        #expect(d.modulos.cifra(.trimestre).cifra == "1 día")
        #expect(d.modulos.ritmo.count == 6)
        // Ningún módulo enseña un 0 suelto.
        for s in HoyApoyo.cifras(d.modulos) { #expect(!Self.esCero(s), "Cifra a cero: «\(s)»") }
    }

    @Test("Siempre exactamente un foco: también en una carpeta sin nada que hacer")
    func unSoloFoco() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        // Una empresa recién empezada (solo su configuración): nada vivo, y el foco es repartir la semana.
        let fm = FileManager.default
        for n in (try? fm.contentsOfDirectory(atPath: c.root.path)) ?? [] where n != ".tls" {
            try? fm.removeItem(at: c.root.appendingPathComponent(n))
        }
        let d = c.hoy()
        #expect(d.foco.titulo == "Nada urgente: reparte la semana")
        #expect(d.foco.boton.etiqueta == "Ver tu semana")
        #expect(d.decisiones.isEmpty)
        #expect(d.frase.hasPrefix("Nada pide tu decisión."))
    }

    @Test("La pantalla pinta un solo destacado violeta (el foco)")
    func unDestacadoEnPantalla() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        defer { s.close() }
        await AlmacenHoy.de(s).actualizar()
        let cuenta = Cuenta()
        let vista = PantallaDestino(destino: .hoy, sesion: s).environment(e.model).environment(\.navegacion, Navegacion(raiz: .hoy))
            .onPreferenceChange(ContadorDestacados.self) { n in MainActor.assumeIsolated { cuenta.n = n } }
        _ = try await HoyApoyo.png(vista, ancho: 1240, alto: 1400, oscuro: false, pasadas: 10)
        #expect(cuenta.n == 1)
    }

    @MainActor final class Cuenta { var n = -1 }

    @Test("Ribera alternando datos: sin rojo no hay sección Alertas; una tarea vencida la trae; hecha, se va")
    func alertasAlternando() async throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        #expect(c.hoy().secciones(hayQueRevisar: false).contains(.alertas))
        try await HoyApoyo.quitarRojos(c)
        let sinRojo = c.hoy()
        #expect(sinRojo.alertas.isEmpty)
        #expect(!sinRojo.secciones(hayQueRevisar: false).contains(.alertas))
        #expect(sinRojo.lineaMika == "Revisé a las 8:45: nada en rojo.")
        #expect(sinRojo.areasEnRojo.isEmpty)

        let ruta = "3 · Entrega/Tareas/t-0003-presentar-la-renta-de-lucia.md"
        c.escribir(ruta, Self.tarea(3, "Presentar la renta de Lucía", estado: "Por hacer", vence: "2026-10-16"))
        let conRojo = c.hoy()
        #expect(conRojo.secciones(hayQueRevisar: false).contains(.alertas))
        #expect(conRojo.alertas.map(\.texto) == ["3 · Entrega · Tareas vencidas: 1 caso"])
        #expect(conRojo.lineaMika == "Revisé a las 8:45: 1 cosa en rojo (Entrega).")

        c.cambiar(ruta, "estado: Por hacer", "estado: Hecha\ncerrada: 2026-10-16")
        #expect(!c.hoy().secciones(hayQueRevisar: false).contains(.alertas))
    }

    @Test("Con los registros vacíos: los módulos dicen «Sin dato» y por qué, nunca 0")
    func registrosVacios() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        HoyApoyo.vaciarRegistros(c)
        let d = c.hoy()
        for m in [ModuloID.cobros, .sinConciliar, .pendientes, .cobrosVencidos] {
            let x = d.modulos.cifra(m)
            #expect(x.cifra == nil, "\(m) enseña «\(x.cifra ?? "")»")
            #expect(x.vacio?.hasPrefix("Sin dato") == true, "\(m)")
        }
        #expect(d.panel.evaluador.evaluar("FIN-AR").medida.numero == nil)
        #expect(d.panel.evaluador.evaluar("FIN-UNREC").medida.numero == nil)
        for s in HoyApoyo.cifras(d.modulos) { #expect(!Self.esCero(s), "Cifra a cero: «\(s)»") }
        // Sin extractos, la caja sale estimada con el saldo inicial de las fichas de cuenta (no es un 0 inventado).
        #expect(d.modulos.caja.series[.mes]?.last?.estimado == true)
        // Y sin cuentas, «Sin datos del banco».
        try? FileManager.default.removeItem(at: c.url("4 · Finanzas/Registros/Bancos"))
        let sinBanco = c.hoy()
        #expect(sinBanco.modulos.caja.saldo == nil)
        #expect(sinBanco.modulos.caja.saldoTexto == "Sin dato")
        #expect(sinBanco.modulos.caja.motivo == "Sin datos del banco: importa un extracto.")
    }

    @Test("Lo privado no sale en Hoy: ni en decisiones, ni en lo que cabe hoy, ni en los detalles")
    func privado() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        c.cambiar(".tls/config.yaml", "privado: []", "privado:\n  - \"4 · Finanzas/Trámites/Expediente privado\"")
        let carpeta = "4 · Finanzas/Trámites/Expediente privado"
        c.escribir("\(carpeta)/t-0009-decidir-el-tramite.md", """
        ---
        tls_type: task
        tls_schema: 1
        id: privada-9
        numero: T-0009
        titulo: Decidir el trámite reservado
        estado: En revisión
        tipo: decision
        planificada: 2026-10-19
        vence: 2026-10-19
        estimacion_h: 2
        creada: 2026-10-19
        ---
        # Decidir el trámite reservado

        ## Problema
        Algo que solo ve la titular.

        """)
        #expect(c.foto().layout.isPrivate(VaultPath("\(carpeta)/t-0009-decidir-el-tramite.md")))
        let d = c.hoy()
        #expect(d.pendientes == 2)
        #expect(!d.decisiones.contains { $0.titulo.contains("reservado") })
        #expect(!d.detalles.values.contains { $0.tarjeta.titulo.contains("reservado") })
        #expect(!d.cabe.contains { $0.titulo.contains("reservado") })
        #expect(d.textoDia == "Nada planificado")
        #expect(!d.foco.titulo.contains("reservado"))
    }

    @Test("Lo que cabe hoy: lo que tiene hora primero, y una tarea que además vence hoy sale una vez")
    func loQueCabeHoy() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        c.escribir("3 · Entrega/Tareas/t-0004-preparar-el-kit.md",
                   Self.tarea(4, "Preparar el kit", estado: "Por hacer", planificada: "2026-10-19", vence: "2026-10-19", estimacion: "1.5"))
        c.escribir("3 · Entrega/Tareas/t-0005-revisar-materiales.md",
                   Self.tarea(5, "Revisar los materiales", estado: "Por hacer", vence: "2026-10-19"))
        c.escribir("2 · Ventas/Reuniones/2026-10-19 diagnostico.md", """
        ---
        tls_type: meeting
        tls_schema: 1
        id: reunion-1
        titulo: Diagnóstico con Sergio Nexo
        fecha: 2026-10-19
        hora: "10:00"
        duracion_min: 45
        estado: Prevista
        ---
        # Diagnóstico con Sergio Nexo

        """)
        let d = c.hoy()
        #expect(d.cabe.map(\.titulo) == ["Diagnóstico con Sergio Nexo", "Preparar el kit", "Revisar los materiales"])
        #expect(d.cabe.map(\.tipo) == [.reunion, .tarea, .vence])
        #expect(d.cabe[0].hora == "10:00")
        #expect(d.cabe[1].venceHoy)
        #expect(d.cabe[1].textoHoras == "1,5 h")
        #expect(d.cabe[1].codigo == "T-0004")
        #expect(d.textoDia == "2,3 h de 4")
        #expect(d.frase == "2 cosas piden tu decisión. Hoy tienes 2,3 h de 4.")
        #expect(d.hora == "9:00")
    }

    @Test("Posponer una decisión la saca de la bandeja (y de la insignia) hasta el día que dices")
    func posponerDecision() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let antes = c.hoy()
        let t = try! #require(antes.decisiones.first)
        var e = EstadoHoy()
        e.pospuestas[t.id] = "2026-10-20"
        let hoy = c.hoy(estado: e)
        #expect(hoy.pendientes == 1)
        #expect(hoy.pospuestas.map(\.id) == [t.id])
        #expect(hoy.frase.hasPrefix("1 cosa pide tu decisión."))
        let manana = c.hoy(estado: e, reloj: HoyApoyo.reloj("2026-10-20"))
        #expect(manana.pendientes == 2)
        #expect(manana.pospuestas.isEmpty)
    }

    @Test("Posponer el foco lo saca hasta el siguiente laborable y sale otro; lo decidido se guarda fuera de la carpeta")
    func posponerFoco() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        defer { s.close() }
        let almacen = AlmacenHoy.de(s)
        await almacen.actualizar()
        let foco = try #require(almacen.datos?.foco)
        let huella = HoyApoyo.Copia(base: e.base, root: e.carpeta).huella()
        almacen.posponer(foco)
        await almacen.actualizar()
        #expect(almacen.datos?.foco.id != foco.id)
        #expect(almacen.estado.estado(foco.id)?.pospuestaHasta == LocalDate(parsing: "2026-10-20"))
        // Se guarda en el estado de la empresa (Application Support), no en la carpeta.
        #expect(FileManager.default.fileExists(atPath: e.estado.appendingPathComponent("hoy.json").path))
        #expect(HoyApoyo.Copia(base: e.base, root: e.carpeta).huella() == huella)
        // «Deshacer» del aviso lo devuelve.
        let aviso = try #require(s.aviso)
        #expect(aviso.texto.hasPrefix("Pospuesto hasta mañana"))
        aviso.accion?()
        await almacen.actualizar(forzar: true)
        #expect(almacen.datos?.foco.id == foco.id)
    }

    @Test("La insignia magenta de Decisiones en la barra lateral: el número de lo que espera tu decisión")
    func insignia() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        defer { s.close() }
        let almacen = AlmacenHoy.de(s)
        await almacen.actualizar()
        #expect(s.barraLateral.datos[.decisiones]?.insignia == 2)
        #expect(s.barraLateral.datos[.decisiones]?.palabraInsignia == "esperan tu decisión")
        let t = try #require(almacen.datos?.decisiones.first)
        almacen.posponer(decision: t, hasta: LocalDate(parsing: "2026-10-26")!)
        await almacen.actualizar()
        #expect(s.barraLateral.datos[.decisiones]?.insignia == 1)
        #expect(s.barraLateral.datos[.decisiones]?.palabraInsignia == "espera tu decisión")
    }

    @Test("Los textos que fabrica Hoy no usan jerga")
    func glosario() {
        let c = HoyApoyo.ribera(), entera = HoyApoyo.ribera()
        defer { c.limpiar(); entera.limpiar() }
        HoyApoyo.vaciarRegistros(c)
        for d in [c.hoy(), entera.hoy()] {
            var textos = [d.frase, d.lineaMika, d.textoDia, d.foco.titulo, d.foco.quePasa, d.foco.recomendacion, d.foco.siNo]
            textos += d.modulos.cifras.values.flatMap { [$0.cifra, $0.linea, $0.vacio, $0.fuente, $0.enlace?.titulo].compactMap { $0 } }
            textos += d.detalles.values.flatMap { [$0.quien, $0.siSePospone, $0.desde, $0.motivoNoDecidir].compactMap { $0 } }
            textos += [d.modulos.caja.fuente, d.modulos.caja.saldoTexto] + d.alertas.map(\.texto)
            for t in textos { #expect(GlosarioTests.jerga(t).isEmpty, "«\(t)»") }
        }
    }

    // MARK: Apoyo

    /// «0», «0 €», «0,00 €», «0 %»: un cero suelto.
    static func esCero(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.allSatisfy { $0 == "0" }
    }

    static func tarea(_ n: Int, _ titulo: String, estado: String, planificada: String? = nil, vence: String? = nil,
                      estimacion: String? = nil) -> String {
        var s = "---\ntls_type: task\ntls_schema: 1\nid: t\(n)-prueba\nnumero: T-\(String(format: "%04d", n))\ntitulo: \(titulo)\nestado: \(estado)\ntipo: tarea\n"
        if let planificada { s += "planificada: \(planificada)\n" }
        if let vence { s += "vence: \(vence)\n" }
        if let estimacion { s += "estimacion_h: \(estimacion)\n" }
        s += "creada: 2026-10-12\n---\n# \(titulo)\n\n## Actividad\n<!-- tls:actividad · para comentar, escribe debajo de la última entrada -->\n"
        return s
    }
}
