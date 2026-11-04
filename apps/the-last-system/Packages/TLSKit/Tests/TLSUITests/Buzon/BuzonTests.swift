import Foundation
import Testing
import TLSAgents
import TLSCore
@testable import TLSUI

/// Carpeta › Buzón (F5 · buzon-relevo): el registro del correo del mes leído por día, con la tarea o el borrador que
/// salió de cada correo; lo privado solo como «correo privado de X» (sin asunto, sin enlace a Mail, sin tareas); los
/// informes de importación, las propuestas pendientes y lo que está por ordenar. Ribera en un temporal; nombres neutros.
@Suite("Buzón · el correo del mes, por día", .serialized)
@MainActor
struct BuzonTests {
    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    static func fecha(_ dia: Int, _ hora: Int, _ minuto: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = madrid
        return c.date(from: DateComponents(year: 2026, month: 10, day: dia, hour: hora, minute: minuto))!
    }

    /// Los correos del ejemplo (sintéticos).
    static let renta = MensajeDeCorreo(id: "buzon-1.renta@correo.example", cuenta: "Empresa", fecha: fecha(19, 8, 12),
                                       de: "Persona Interesada <persona@correo.example>", asunto: "Quiero hacer la renta con vosotros")
    static let hacienda = MensajeDeCorreo(id: "buzon-2.requerimiento@agencia.example", cuenta: "Empresa", fecha: fecha(19, 9, 1),
                                          de: "Agencia Tributaria <avisos@agencia.example>", asunto: "Requerimiento de información")
    static let privado = MensajeDeCorreo(id: "buzon-3.secreto@privado.example", cuenta: "Empresa", fecha: fecha(19, 9, 30),
                                         de: "correo privado de Expediente privado", privado: true)
    static let factura = MensajeDeCorreo(id: "buzon-4.factura@proveedor.example", cuenta: "Empresa", fecha: fecha(16, 8, 40),
                                         de: "Proveedor de Prueba <facturas@proveedor.example>", asunto: "Factura de septiembre")

    /// El registro tal como lo escribe `tls_anotar_correo` (mismo código: `RegistroDelCorreo` y `EntradaDeCorreo`).
    static func registro() -> String {
        let d16 = LocalDate(year: 2026, month: 10, day: 16)!
        let d19 = LocalDate(year: 2026, month: 10, day: 19)!
        var t = RegistroDelCorreo.textoNuevo(d19)
        t += "\n## \(d16)\n"
        t += EntradaDeCorreo(mensaje: factura, tipo: .proveedor, destino: "tarea en Finanzas", estado: .hecho).texto(madrid) + "\n"
        t += "\n## \(d19)\n"
        for e in [EntradaDeCorreo(mensaje: renta, tipo: .interesado, destino: "tarea en Ventas y respuesta en borrador"),
                  EntradaDeCorreo(mensaje: hacienda, tipo: .administracion, destino: "tarea en Finanzas",
                                  plazo: LocalDate(year: 2026, month: 10, day: 30)),
                  EntradaDeCorreo(mensaje: privado, tipo: .cliente, destino: "lo miras tú (privado)")] {
            t += e.texto(madrid) + "\n"
        }
        return t
    }

    @Test("Las líneas del registro se leen con lo que escribe el Cartero (hora, quién, asunto, tipo, destino, estado, plazo y enlace)")
    func lineas() throws {
        let dias = LectorRegistroBuzon.leer(Self.registro())
        #expect(dias.map(\.dia.description) == ["2026-10-16", "2026-10-19"])
        let hoy = try #require(dias.last)
        #expect(hoy.lineas.count == 3 && hoy.privados == 1 && hoy.conPlazo == 1 && hoy.porRevisar == 3)
        let r = hoy.lineas[0]
        #expect(r.hora == "08:12")
        #expect(r.quien == "Persona Interesada" && r.direccion == "persona@correo.example")
        #expect(r.asunto == "Quiero hacer la renta con vosotros")
        #expect(r.tipo == .interesado && r.destino == "tarea en Ventas y respuesta en borrador" && r.estado == .propuesto)
        #expect(r.enlaceMail?.absoluteString == Self.renta.enlace)
        let h = hoy.lineas[1]
        #expect(h.tipo == .administracion && h.plazo == LocalDate(year: 2026, month: 10, day: 30) && h.enRojo)
        // Lo privado: solo «correo privado de X»; ni asunto ni enlace (su referencia es opaca).
        let p = hoy.lineas[2]
        #expect(p.privado && p.quien == "correo privado de Expediente privado")
        #expect(p.asunto == nil && p.direccion == nil && p.enlaceMail == nil)
        #expect(p.referencia?.hasPrefix(EnlaceDeCorreo.prefijoPrivado) == true)
        #expect(!(p.referencia ?? "").contains("privado.example"), "el Message-ID de lo privado no sale")
        #expect(dias.first?.lineas.first?.estado == .hecho)
        // El resumen de un día.
        #expect(ModeloBuzon.resumen(hoy) == "3 correos · 1 privado · 1 con plazo oficial · 3 por revisar")
    }

    @Test("Un registro editado a mano no rompe la lectura: lo que no se entiende se salta")
    func tolerante() {
        let t = """
            # Correo de octubre de 2026
            ## no es una fecha
            - 08:00 · Alguien · Algo · cliente · sin destino · Hecho
            ## 2026-10-20
            texto suelto
            - 10:15 · Cliente Uno <uno@cliente.example> · Hola · cliente · tarea en Ventas · Propuesto
            - solo
            - 11:00 · correo privado de Expediente privado · — · ruido · sin destino · Hecho
            """
        let dias = LectorRegistroBuzon.leer(t)
        #expect(dias.count == 1)
        #expect(dias.first?.lineas.count == 2)
        #expect(dias.first?.lineas.first?.referencia == nil && dias.first?.lineas.first?.enlaceMail == nil)
        #expect(dias.first?.lineas.last?.privado == true && dias.first?.lineas.last?.asunto == nil)
    }

    @Test("En Ribera: el día con su tarea y su borrador enlazados; lo privado sin nada; informes, propuestas y lo que está por ordenar")
    func lecturaEnLaCarpeta() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        try Self.sembrar(e)
        let foto = e.foto()
        let hoy = try #require(LocalDate(parsing: "2026-10-19"))
        let l = LecturaBuzon.leer(foto: foto, hoy: hoy)
        #expect(l.carpeta?.raw == "Buzón")
        #expect(l.meses.map(\.mes) == ["2026-10"] && l.mes?.titulo == "octubre de 2026")
        #expect(l.correosDelMes == 4 && l.propuestosDelMes == 3)
        #expect(l.diaPorDefecto == hoy)
        let d = try #require(l.dia(hoy))
        let renta = d.lineas[0]
        #expect(renta.enlazados.map(\.clase) == [.tarea, .borrador])
        #expect(renta.enlazados.first?.titulo == "Responder a la persona interesada en la renta")
        #expect(renta.enlazados.last?.estado == "Pendiente de tu OK")
        let hacienda = d.lineas[1]
        #expect(hacienda.enlazados.map(\.ruta.raw) == ["4 · Finanzas/Tareas/t-0901-requerimiento.md"])
        // Lo privado: ni tareas ni borradores, aunque alguien escribiera su referencia en una ficha.
        #expect(d.lineas[2].enlazados.isEmpty)
        // Informes, propuestas y lo suelto.
        #expect(l.informes.map(\.ruta.raw) == ["Buzón/Informe de importación 2026-10-19.md"])
        #expect(l.informes.first?.detalle?.contains("no se borró nada") == true)
        #expect(l.propuestas.map(\.ruta.raw) == ["Buzón/Propuestas del relevo 2026-10-18.md"])
        #expect(l.porOrdenar.map(\.ruta.raw) == ["Buzón/factura-escaneada.pdf"])
        // Otro mes elegido que no existe: el de hoy.
        #expect(LecturaBuzon.leer(foto: foto, hoy: hoy, mes: "2026-09").mes?.mes == "2026-10")
        // El enrutador: Carpeta › Buzón es esta pantalla; otra carpeta, no.
        #expect(BuzonPantalla.es(VaultPath("Buzón"), e.sesion))
        #expect(!BuzonPantalla.es(VaultPath("2 · Ventas"), e.sesion) && !BuzonPantalla.es(nil, e.sesion))
        // El modelo de la pantalla.
        let m = ModeloBuzon()
        m.cargar(foto: foto, hoy: hoy)
        #expect(m.diaVisible?.dia == hoy)
        #expect(m.pestanasDias.map(\.titulo) == ["Hoy", "vie 16"])
        #expect(m.pestanasDias.first?.urgente == .mal)
        m.dia = LocalDate(year: 2026, month: 10, day: 16)
        #expect(m.diaVisible?.lineas.first?.quien == "Proveedor de Prueba")
    }

    @Test("Sin registro ni Buzón: la pantalla lo explica y no inventa nada")
    func vacio() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let l = LecturaBuzon.leer(foto: e.foto(), hoy: try #require(LocalDate(parsing: "2026-10-19")))
        #expect(l.mes == nil && l.dias.isEmpty && l.correosDelMes == 0)
        #expect(l.informes.count == 1, "el informe de importación del ejemplo")
    }

    /// El registro, una tarea y un borrador que salieron del correo, una tarea con la referencia de lo privado (no debe
    /// enlazarse), unas propuestas y un fichero suelto. «Desde fuera», como si lo hubiera escrito el Cartero.
    static func sembrar(_ e: MikaApoyo.Empresa) throws {
        e.escribirFuera("Buzón/Correo 2026-10.md", registro())
        e.escribirFuera("2 · Ventas/Tareas/t-0900-renta.md", """
            ---
            tls_type: task
            tls_schema: 1
            id: buzon-tarea-renta
            numero: T-0900
            titulo: Responder a la persona interesada en la renta
            estado: Por hacer
            responsable: Manu
            origen: "\(renta.enlace)"
            creada: 2026-10-19
            ---
            # Responder a la persona interesada en la renta

            """)
        e.escribirFuera("4 · Finanzas/Tareas/t-0901-requerimiento.md", """
            ---
            tls_type: task
            tls_schema: 1
            id: buzon-tarea-hacienda
            numero: T-0901
            titulo: Contestar el requerimiento
            estado: Por hacer
            prioridad: alta
            responsable: Manu
            origen: "\(hacienda.enlace)"
            creada: 2026-10-19
            ---
            # Contestar el requerimiento

            """)
        e.escribirFuera("2 · Ventas/Borradores/respuesta-renta.md", """
            ---
            tls_type: draft
            tls_schema: 1
            id: buzon-borrador-renta
            accion: enviar_correo
            estado: Pendiente de tu OK
            para: [persona@correo.example]
            asunto: "Re: Quiero hacer la renta con vosotros"
            en_respuesta_a: "\(renta.enlace)"
            ---
            # Re: Quiero hacer la renta con vosotros

            """)
        e.escribirFuera("1 · Dirección/Tareas/t-0902-privado.md", """
            ---
            tls_type: task
            tls_schema: 1
            id: buzon-tarea-privado
            titulo: No debe salir
            estado: Por hacer
            origen: "\(privado.referencia)"
            ---
            # No debe salir

            """)
        e.escribirFuera("Buzón/Propuestas del relevo 2026-10-18.md", "# Propuestas del relevo 2026-10-18\n\nNo he aplicado ninguno.\n")
        let pdf = e.url("Buzón/factura-escaneada.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: pdf)
    }
}
