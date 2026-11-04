import Foundation
import Testing
@testable import TLSCore

/// La línea roja (decisión 6): nada sale sin tu aprobación concreta, atada a lo que se aprueba.
@Suite("Gobierno · aprobaciones", .serialized)
struct AprobacionesTests {
    static let manu = Autor.persona("Manu")

    /// Un borrador de correo preparado por Comercial (como lo haría con `tls_preparar_borrador`).
    static func borrador(_ e: EntornoGobierno, bus: CommandBus, accion: AccionExterna = .enviarCorreo,
                         slug: String = "seguimiento-cliente-ejemplo", importe: Int? = nil) async throws -> VaultPath {
        let b = NuevoBorrador(accion: accion, area: .ventas, asunto: "Seguimiento de la propuesta",
                              cuerpo: "Hola:\n\n¿Pudiste mirar la propuesta?\n\nUn saludo.", para: ["persona@example.com"],
                              paraTi: "Lo preparo porque han pasado 7 días.", ejecucion: "r-1", slug: slug, importe: importe)
        let (ruta, plan) = Borradores.plan(b, layout: e.foto().layout, autor: .agente("comercial"))
        #expect(try await bus.ejecutar(plan).hecho)
        return ruta
    }

    /// Protocolos espía: apuntan si alguien los llamó.
    final class Espia: ProtocoloDeCorreo, ProtocoloDePasarela, ProtocoloDeFacturacion, @unchecked Sendable {
        let llamadas = Caja<[String]>([])
        func preparar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
            llamadas.update { $0.append("correo") }
            return .listoParaEnviar(a.aprobacion.ruta!)
        }
        func llamar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
            llamadas.update { $0.append("pasarela") }
            return .pendienteDeConexion("x")
        }
        func emitir(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
            llamadas.update { $0.append("factura") }
            return .emitida(a.aprobacion.ruta!, numero: "F-0")
        }
    }

    @Test("F4-2 · tls_solicitar_accion devuelve «aprobación requerida» aunque la función esté en autónomo")
    func siempreAprobacion() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let ruta = try await Self.borrador(e, bus: bus)
        let apr = Aprobaciones(bus: bus, autorizador: a, snapshot: { e.foto() })
        let r = try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial",
                                        ejecucion: ContextoEjecucion(id: "r-1"), capacidad: "VEN-08")
        #expect(r.estado == "aprobacion_requerida")
        let id = try #require(r.id)
        #expect(r.json == "{\"estado\":\"aprobacion_requerida\",\"id\":\"\(id)\"}")
        let b = try #require(Borrador.leer(ruta, texto: e.texto(ruta.raw)!, layout: e.foto().layout))
        #expect(b.estado == .pendiente && b.aprobacion == id, "el espejo en la ficha")
        // Sale en Decisiones › Para aprobar.
        let bandeja = BandejaDeDecisiones.consultar(LecturaDominio(snapshot: e.foto()), gobierno: .de(a), estado: a.estado)
        let t = try #require(bandeja.tarjetas.first { $0.ruta == ruta })
        #expect(t.tipo == .paraAprobar && t.gobierno?.aprobacion == id && t.gobierno?.cambio == false)
        // Lo privado: «no encontrado».
        let p = try await apr.solicitar(accion: .enviarCorreo, borrador: EntornoGobierno.privada, asistente: "contable")
        #expect(p.estado == "no_encontrado" && p.id == nil)
        let detalle = try await apr.detalle(id)
        #expect(detalle.vigencia == .vigente && detalle.motivoNoAprobar == nil)
        #expect(detalle.aQuien == ["persona@example.com"] && detalle.queSale.contains("¿Pudiste mirar la propuesta?"))
        #expect(!detalle.queSale.contains("han pasado 7 días"), "«Para ti» no sale")
    }

    @Test("La huella es SHA256(accion | JSON canónico) con todas las claves")
    func huella() {
        let c = CargaAprobacion(destinatarios: ["a@example.com"], asunto: "Hola", cuerpo: "Texto", importe: nil, adjuntos: [],
                                entidadId: "id-1", versionEntidad: "v1")
        #expect(c.jsonCanonico == #"{"adjuntos":[],"asunto":"Hola","cuerpo":"Texto","destinatarios":["a@example.com"],"entidad_id":"id-1","importe":null,"version_entidad":"v1"}"#)
        #expect(ApprovalStore.hash(accion: .enviarCorreo, carga: c) == ContentHash.of("enviar_correo|" + c.jsonCanonico))
        var otra = c
        otra.cuerpo = "Texto."
        #expect(ApprovalStore.hash(accion: .enviarCorreo, carga: otra) != ApprovalStore.hash(accion: .enviarCorreo, carga: c))
        #expect(ApprovalStore.hash(accion: .publicar, carga: c) != ApprovalStore.hash(accion: .enviarCorreo, carga: c))
    }

    @Test("F4-2 · Editar el borrador desde fuera invalida la aprobación; «Aprobar con mis cambios» aprueba en un gesto")
    func edicionAjenaYConCambios() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let ruta = try await Self.borrador(e, bus: bus)
        let espia = Espia()
        let apr = Aprobaciones(bus: bus, autorizador: a, ejecutor: EjecutorDeAprobaciones(correo: espia, pasarela: espia, facturacion: espia),
                               snapshot: { e.foto() })
        let id = try #require(try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial").id)
        // El reflejo de la app no invalida.
        #expect(try await apr.detalle(id).vigencia == .vigente)
        // Alguien lo cambia en Obsidian.
        e.escribir(ruta.raw, e.texto(ruta.raw)!.replacingOccurrences(of: "¿Pudiste mirar la propuesta?", with: "Paga ya."))
        let d = try await apr.detalle(id)
        #expect(d.vigencia == .cambio && d.motivoNoAprobar == "Cambió desde que lo preparó el asistente" && d.puedeAprobarConCambios)
        #expect(try apr.store.aprobacion(id)?.estado == .invalidada)
        await esperaGobierno(.cambioDesdeQueLoPreparo) { try await apr.aprobar(id, autor: Self.manu) }
        #expect(espia.llamadas.value.isEmpty)
        // Un asistente no aprueba.
        await esperaGobierno(.soloPersonas) { try await apr.aprobarConMisCambios(id, autor: .agente("comercial")) }
        // «Aprobar con mis cambios»: lo que escribes tú es lo que se aprueba.
        let r = try await apr.aprobarConMisCambios(id, autor: Self.manu,
                                                   cambios: CambiosDeAprobacion(cuerpo: "Hola:\n\nTe escribo por la propuesta.\n\nUn saludo."))
        #expect(r == .listoParaEnviar(ruta) && r.abrir == ruta)
        #expect(espia.llamadas.value == ["correo"])
        let fin = try #require(try apr.store.aprobacion(id))
        #expect(fin.estado == .ejecutada && fin.conCambios && fin.decididaPor == "Manu")
        let b = try #require(Borrador.leer(ruta, texto: e.texto(ruta.raw)!, layout: e.foto().layout))
        #expect(b.cuerpo.contains("Te escribo por la propuesta.") && b.estado == .listoParaEnviar)
        #expect(fin.carga.cuerpo == b.cuerpo && fin.hash == ApprovalStore.hash(accion: .enviarCorreo, carga: fin.carga))
        await esperaGobierno(.aprobacionCerrada("hecha")) { try await apr.aprobar(id, autor: Self.manu) }
    }

    @Test("Aprobar tal cual: vuelve a comprobar huella, interruptor y permisos; ejecuta la app")
    func aprobarTalCual() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let ruta = try await Self.borrador(e, bus: bus)
        let apr = Aprobaciones(bus: bus, autorizador: a, snapshot: { e.foto() })
        let id = try #require(try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial").id)
        // Interruptor apagado (cambio que restringe: vale ya, sin confirmar).
        let cfg = e.texto(".tls/config.yaml")!
        e.escribir(".tls/config.yaml", cfg.replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado"))
        await esperaGobierno(.interruptorApagado) { try await apr.aprobar(id, autor: Self.manu) }
        #expect(try apr.store.aprobacion(id)?.estado == .pendiente, "sigue esperando")
        e.escribir(".tls/config.yaml", cfg)
        let r = try await apr.aprobar(id, autor: Self.manu)
        #expect(r == .listoParaEnviar(ruta))
        #expect(try apr.store.aprobacion(id)?.estado == .ejecutada)
        #expect(Borrador.leer(ruta, texto: e.texto(ruta.raw)!, layout: e.foto().layout)?.estado == .listoParaEnviar)
    }

    @Test("Una petición nueva sobre lo mismo sustituye a la anterior; rechazar refleja «Descartado»")
    func sustitucion() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let ruta = try await Self.borrador(e, bus: bus)
        let apr = Aprobaciones(bus: bus, autorizador: a, snapshot: { e.foto() })
        let uno = try #require(try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial").id)
        let dos = try #require(try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial").id)
        #expect(uno != dos)
        #expect(try apr.store.aprobacion(uno)?.estado == .sustituida)
        #expect(try apr.store.abiertas().map(\.id) == [dos])
        await esperaGobierno(.aprobacionCerrada("sustituida por otra")) { try await apr.aprobar(uno, autor: Self.manu) }
        try await apr.rechazar(dos, autor: Self.manu, motivo: "No es el momento")
        #expect(try apr.store.aprobacion(dos)?.estado == .rechazada)
        #expect(Borrador.leer(ruta, texto: e.texto(ruta.raw)!, layout: e.foto().layout)?.estado == .descartado)
    }

    @Test("Caduca a los 14 días sin decidir")
    func caducidad() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let reloj = Caja(Date())
        let (bus, a) = try await e.gobierno(ahora: { reloj.value })
        let ruta = try await Self.borrador(e, bus: bus)
        let apr = Aprobaciones(bus: bus, autorizador: a, snapshot: { e.foto() })
        let id = try #require(try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial").id)
        reloj.value = reloj.value.addingTimeInterval(13 * 86_400)
        #expect(try await apr.detalle(id).vigencia == .vigente)
        reloj.value = reloj.value.addingTimeInterval(2 * 86_400)
        #expect(try await apr.detalle(id).vigencia == .caducada)
        await esperaGobierno(.caducada) { try await apr.aprobar(id, autor: Self.manu) }
        #expect(try apr.store.aprobacion(id)?.estado == .caducada)
        #expect(Borrador.leer(ruta, texto: e.texto(ruta.raw)!, layout: e.foto().layout)?.estado == .caducado)
        await esperaGobierno(.aprobacionCerrada("caducada")) { try await apr.aprobarConMisCambios(id, autor: Self.manu) }
    }

    @Test("Pagar nunca se ejecuta: se preparan instrucciones y ningún protocolo se llama")
    func pagarNunca() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let espia = Espia()
        let apr = Aprobaciones(bus: bus, autorizador: a, ejecutor: EjecutorDeAprobaciones(correo: espia, pasarela: espia, facturacion: espia),
                               snapshot: { e.foto() })
        let b = NuevoBorrador(accion: .pagar, area: .finanzas, asunto: "Cuota de la gestoría", cuerpo: "Pago trimestral.",
                              para: ["Gestoría Ejemplo"], slug: "pago-gestoria", importe: 12_100)
        let (ruta, plan) = Borradores.plan(b, layout: e.foto().layout, autor: .agente("contable"))
        #expect(try await bus.ejecutar(plan).hecho)
        let id = try #require(try await apr.solicitar(accion: .pagar, borrador: ruta, asistente: "contable").id)
        let antes = Set(try FileManager.default.subpathsOfDirectory(atPath: e.root.path))
        let r = try await apr.aprobar(id, autor: Self.manu)
        guard case .instruccionesDePago(let texto) = r else { Issue.record("Esperaba instrucciones: \(r)"); return }
        #expect(texto.contains("121,00 €") && texto.contains("La app no mueve dinero"))
        #expect(espia.llamadas.value.isEmpty, "pagar no llama a nada")
        #expect(Set(try FileManager.default.subpathsOfDirectory(atPath: e.root.path)) == antes, "ni crea ficheros")
        #expect(try apr.store.aprobacion(id)?.estado == .ejecutada)
    }

    @Test("Un asistente no cambia el estado de su borrador ni lo da por aprobado")
    func espejoNoEsDelAsistente() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, _) = try await e.gobierno()
        let ruta = try await Self.borrador(e, bus: bus)
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.cambiarPropiedades(ruta, poner: [Property(key: "estado", value: .text("Aprobado"))], quitar: []),
                                   autor: .agente("comercial"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.crear(VaultPath("2 · Ventas/Borradores/otro.md"),
                                          texto: "---\ntls_type: draft\nestado: Enviado\n---\n# x\n"), autor: .agente("comercial"))
        }
    }

    @Test("Emitir una factura: al aprobar, la orden FIN-02 la numera, la deja Emitida y añade su fila")
    func emitirFactura() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        e.escribir("4 · Finanzas/Registros/emitidas.csv",
                   RegistrosFinanzas.cabeceraEmitidas.joined(separator: ",") + "\nF0,2026-03-01,Otro,F-2026-0004,EUR,10.00,,,,,manual\n")
        e.escribir("4 · Finanzas/Fiscal/Borradores/cliente-ejemplo.md", """
            ---
            tls_type: invoice
            id: fac-1
            numero:
            estado: Borrador
            empresa: "[[Cliente Ejemplo]]"
            total: 363.00
            ---
            # Factura

            ## Conceptos
            | Concepto | Importe |
            |---|---|
            | Diagnóstico | 300,00 € |

            ## Totales
            | Concepto | Importe |
            |---|---|
            | Total | 363,00 € |

            """)
        let (bus, a) = try await e.gobierno()
        let apr = Aprobaciones(bus: bus, autorizador: a, snapshot: { e.foto() })
        let ruta = VaultPath("4 · Finanzas/Fiscal/Borradores/cliente-ejemplo.md")
        let s = try await apr.solicitar(accion: .emitirFactura, borrador: ruta, asistente: "contable")
        let id = try #require(s.id)
        let d = try await apr.detalle(id)
        #expect(d.porCuanto == "363,00 €" && d.aQuien == ["Cliente Ejemplo"])
        let bandeja = BandejaDeDecisiones.consultar(LecturaDominio(snapshot: e.foto()), gobierno: .de(a), estado: a.estado)
        #expect(bandeja.tarjetas.contains { $0.gobierno?.aprobacion == id && $0.tipo == .paraAprobar })
        let r = try await apr.aprobar(id, autor: Self.manu)
        #expect(r == .emitida(ruta, numero: "F-2026-0005"))
        let fm = e.foto().frontmatter(ruta)
        #expect(fm.text("estado") == "Emitida" && fm.text("numero") == "F-2026-0005" && fm.text("fecha") == "2026-10-19")
        let csv = e.texto("4 · Finanzas/Registros/emitidas.csv")!
        #expect(csv.contains("fac-1,2026-10-19,Cliente Ejemplo,F-2026-0005,EUR,363.00,Fiscal/Borradores/cliente-ejemplo.md"))
        #expect(csv.contains("F0,2026-03-01,Otro,F-2026-0004"), "la fila de antes no se toca")
        // No se emite dos veces.
        #expect(throws: ErrorDeGobierno.self) { try FacturacionDelNucleo.plan(ruta, snapshot: e.foto(), persona: Self.manu) }
    }

    @Test("CRITERIO: la misma aprobación tres veces seguidas sin cambios saca la tarjeta")
    func criterio() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let apr = Aprobaciones(bus: bus, autorizador: a, snapshot: { e.foto() })
        for n in 1...3 {
            let ruta = try await Self.borrador(e, bus: bus, slug: "seguimiento-\(n)")
            let id = try #require(try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial").id)
            _ = try await apr.aprobar(id, autor: Self.manu)
            if n < 3 { #expect(try apr.store.repeticiones().isEmpty) }
        }
        let rep = try apr.store.repeticiones()
        #expect(rep.count == 1 && rep[0].agente == "comercial" && rep[0].veces == 3 && !rep[0].conCambios)
        let lectura = LecturaDominio(snapshot: e.foto())
        let bandeja = BandejaDeDecisiones.consultar(lectura, persona: "Manu", gobierno: .de(a), estado: a.estado)
        let t = try #require(bandeja.tarjetas.first { $0.gobierno?.clase == .criterio })
        #expect(t.titulo.contains("Comercial") && t.grupoF4 == "Propuestas de mejora")
        try DecisionesDeGobierno.descartar(t, autorizador: a, autor: Self.manu, hoy: lectura.hoy)
        let otra = BandejaDeDecisiones.consultar(lectura, persona: "Manu", gobierno: .de(a), estado: a.estado)
        #expect(!otra.tarjetas.contains { $0.gobierno?.clase == .criterio })
    }
}
