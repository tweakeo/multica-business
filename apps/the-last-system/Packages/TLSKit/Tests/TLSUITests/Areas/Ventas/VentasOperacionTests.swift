import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Operación de Ventas (PLAN §6.5): el CRM en tablero con número, euros, conversión y «quieta N d»; soltar en Ganada
/// sin cobro se bloquea con el mensaje de VEN-07 y se ofrece Aceptada (criterio F2-3, desde el tablero); el seguimiento
/// a 7, 14, 21 y 30 días («Preparar seguimiento» deja el borrador en una tarea, nunca envía); contactos y empresas.
@Suite("Áreas · Ventas · Operación", .serialized)
@MainActor
struct VentasOperacionTests {
    let pruebas = SesionEscrituraTests()
    let jorge = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
    let javier = VaultPath("2 · Ventas/Oportunidades/javier-ortega-renta.md")

    @Test("Tablero de Ribera: columnas en orden, número, euros, conversión y quietas; sin dato no es 0")
    func tablero() throws {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        let d = DatosVentas.calcular(foto: ApoyoAreasA.foto(carpeta), hoy: ApoyoAreasA.hoy)
        let t = d.tablero
        #expect(t.columnas.map(\.etapa) == EtapaCRM.allCases)
        let metricas = FotoMetricas(snapshot: ApoyoAreasA.foto(carpeta), hoy: ApoyoAreasA.hoy)
        // Cada oportunidad abierta o recién ganada está en su columna (Perdida y Pausada, aparte).
        for c in t.columnas where c.etapa != .ganada {
            let esperadas = metricas.oportunidades.filter { EtapaCRM($0.estado) == c.etapa }.count
            #expect(c.numero == esperadas, "\(c.etapa.rawValue)")
        }
        // Euros: la suma del valor escrito.
        let propuesta = try #require(t.columna(.propuesta))
        let suma = metricas.oportunidades.filter { $0.estado == .propuesta }.compactMap(\.valor).reduce(0, +)
        #expect(propuesta.total == suma)
        // Conversión: en Ganada, ganadas sobre cerradas; en el resto, el % que pasa a la siguiente.
        let ganadas = metricas.oportunidades.filter { $0.estado == .ganada }.count
        let perdidas = metricas.oportunidades.filter { $0.estado == .perdida }.count
        let g = try #require(t.columna(.ganada))
        if ganadas + perdidas > 0 {
            #expect(g.conversion == Int((Double(ganadas) / Double(ganadas + perdidas) * 100).rounded()))
            #expect(g.textoConversion.hasSuffix("ganadas sobre cerradas"))
        }
        #expect(t.columna(.prospecto)?.textoConversion.contains("pasa a Diagnóstico") == true)
        // Javier Ortega lleva desde el 19 sep sin contacto: quieta 30 d.
        let jo = try #require(t.tarjeta(javier))
        #expect(jo.quieta && jo.textoQuieta == "quieta 30 d")
        // Una columna sin valor dice «Sin dato», nunca 0.
        let vacia = ColumnaCRM(etapa: .diagnostico, tarjetas: [], total: nil, conversion: nil)
        #expect(vacia.textoTotal == "Sin dato" && vacia.textoConversion == "Sin dato de conversión")
        // Cifras de arriba: VEN-STALE7 (no está en Metas.md: sin meta) y VEN-PIPE.
        #expect(d.cifras.map(\.codigo) == ["VEN-STALE7", "VEN-PIPE"])
        #expect(d.cifras.first?.meta == "Sin meta")
        #expect(d.cifras.last?.valor == "870 €" || d.cifras.last?.valor == "870,00 €")
    }

    @Test("VEN-07 desde el tablero: soltar en Ganada sin cobro se bloquea con su mensaje y ofrece «Dejarla en Aceptada»")
    func ven07Puro() throws {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        let foto = ApoyoAreasA.foto(carpeta)
        let t = DatosVentas.calcular(foto: foto, hoy: ApoyoAreasA.hoy).tablero
        let tarjeta = try #require(t.tarjeta(jorge))
        let r = TableroCRM.soltar(tarjeta, en: .ganada, invariantes: Invariantes(snapshot: foto), autor: .persona("Manu"))
        guard case .bloqueado(let mensaje, let alternativa) = r else {
            Issue.record("Debía bloquearse y dio \(r)")
            return
        }
        #expect(mensaje.hasPrefix("Ganada necesita un cobro confirmado por una persona."))
        #expect(alternativa?.titulo == "Dejarla en Aceptada")
        #expect(alternativa?.comando == .cambiarPropiedades(jorge, poner: [Property(key: "estado", value: .text("Aceptada"))], quitar: []))
        // A otra columna, sin problema (solo cambia `estado`).
        #expect(TableroCRM.soltar(tarjeta, en: .propuesta, invariantes: Invariantes(snapshot: foto), autor: .persona("Manu"))
            == .escribir(.cambiarPropiedades(jorge, poner: [Property(key: "estado", value: .text("Propuesta"))], quitar: [])))
        // Un asistente tampoco puede (ni con cobro).
        guard case .bloqueado = TableroCRM.soltar(tarjeta, en: .ganada, invariantes: Invariantes(snapshot: foto), autor: .agente("comercial")) else {
            Issue.record("Un asistente no puede pasar a Ganada")
            return
        }
    }

    func abrir() async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        try ApoyoAreasA.preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        return (e, sesion)
    }

    func datos(_ sesion: VaultSession) async -> DatosVentas? {
        let carga = CargaOperacion<DatosVentas>(sesion: sesion) { f, h in DatosVentas.calcular(foto: f, hoy: h) }
        await carga.cargar()
        return carga.datos
    }

    @Test("VEN-07 con una sesión de verdad: soltar en Ganada no escribe nada; «Dejarla en Aceptada» cambia solo el estado")
    func ven07Sesion() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let d = try #require(await datos(sesion))
        let tarjeta = try #require(d.tablero.tarjeta(javier))
        let url = javier.url(in: e.carpeta)
        let antes = try String(contentsOf: url, encoding: .utf8)
        let r = await AccionesVentas.mover(tarjeta, a: .ganada, sesion: sesion, deshacer: nil)
        guard case .bloqueado(let mensaje, let alternativa?) = r else {
            Issue.record("Debía bloquearse y dio \(r)")
            return
        }
        #expect(mensaje.contains("cobro confirmado"))
        #expect(try String(contentsOf: url, encoding: .utf8) == antes)
        #expect(await AccionesVentas.aplicar(alternativa, nombre: tarjeta.nombre, sesion: sesion, deshacer: nil) == nil)
        let despues = try String(contentsOf: url, encoding: .utf8)
        #expect(ApoyoAreasA.lineasCambiadas(antes, despues) == ["estado: Aceptada"])
    }

    @Test("Mover a otra columna cambia solo la línea estado y se deshace")
    func moverColumna() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let d = try #require(await datos(sesion))
        let tarjeta = try #require(d.tablero.tarjeta(jorge))
        let url = jorge.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        #expect(await AccionesVentas.mover(tarjeta, a: .propuesta, sesion: sesion, deshacer: um) == .hecho)
        um.endUndoGrouping()
        #expect(ApoyoAreasA.lineasCambiadas(String(decoding: antes, as: UTF8.self), try String(contentsOf: url, encoding: .utf8))
            == ["estado: Propuesta"])
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("Seguimiento: a los 7 días toca; «Preparar seguimiento» crea la tarea con el borrador y nada sale fuera")
    func seguimiento() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let d = try #require(await datos(sesion))
        let s = try #require(d.seguimientos.first { $0.oportunidad == javier })
        #expect(s.dias == 7 && s.toca == 7 && s.preparados.isEmpty)
        #expect(s.proximo?.dia == 14 && s.proximo?.fecha == LocalDate(year: 2026, month: 10, day: 26)!)
        // Las que no están en Propuesta no tienen seguimiento (Jorge está Aceptada).
        #expect(!d.seguimientos.contains { $0.oportunidad == jorge })
        // El resto de propuestas de Ribera se enviaron hoy: aún no toca.
        #expect(d.seguimientos.filter { $0.oportunidad != javier }.allSatisfy { $0.toca == nil })
        let borradores = e.carpeta.appendingPathComponent("2 · Ventas/Borradores")
        #expect(await AccionesVentas.prepararSeguimiento(s, dia: 7, sesion: sesion, deshacer: nil) == nil)
        let tareas = e.carpeta.appendingPathComponent("2 · Ventas/Tareas")
        let nuevas = try FileManager.default.contentsOfDirectory(atPath: tareas.path).filter { $0.contains("seguimiento-dia-7") }
        #expect(nuevas.count == 1)
        let t = try String(contentsOf: tareas.appendingPathComponent(try #require(nuevas.first)), encoding: .utf8)
        #expect(t.contains("Seguimiento día 7 · Javier Ortega · Renta"))
        #expect(t.contains("javier-ortega-renta") && t.contains("capacidad: VEN-08") && t.contains("estado: Por hacer"))
        #expect(t.contains("nunca se envía solo"))
        // Ningún borrador para enviar ni nada en Decisiones: el mensaje lo envía la persona.
        #expect(!FileManager.default.fileExists(atPath: borradores.path))
        // Ya preparado: deja de tocar.
        let rev = sesion.revision
        await pruebas.esperar { sesion.revision > rev }
        let d2 = try #require(await datos(sesion))
        let s2 = try #require(d2.seguimientos.first { $0.oportunidad == javier })
        #expect(s2.toca == nil && s2.preparados == [7])
    }

    @Test("Contactos y empresas por estado, sin lo privado")
    func directorio() throws {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        try ApoyoAreasA.cambiar(".tls/config.yaml", en: carpeta, "privado: []", por: "privado: [\"2 · Ventas/Contactos/Reservado\"]")
        try ApoyoAreasA.escribir("---\ntls_type: contact\nnombre: Persona reservada\nestado: Activo\n---\n# Persona reservada\n",
                                 "2 · Ventas/Contactos/Reservado/persona.md", en: carpeta)
        let d = DatosVentas.calcular(foto: ApoyoAreasA.foto(carpeta), hoy: ApoyoAreasA.hoy)
        #expect(d.contactos.total == 14)
        #expect(d.empresas.total == 10)
        #expect(d.contactos.porEstado.map(\.numero).reduce(0, +) == d.contactos.total)
    }
}
