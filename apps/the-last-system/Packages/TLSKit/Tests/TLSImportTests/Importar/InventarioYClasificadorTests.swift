import Foundation
import Testing
import TLSCore
@testable import TLSImport

@Suite("Ordenar lo que tienes · inventario y clasificador por reglas")
struct InventarioYClasificadorTests {
    @Test("El inventario cuenta por herramienta y por tipo, y lo privado nunca se lista")
    func inventario() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let notion = try CarpetaDeFuera(e.base, nombre: "Notion")
        let id = "0123456789abcdef0123456789abcdef"
        try notion.escribir("Equipo \(id)/Reunión de lunes \(id).md", "# Reunión\n")
        try notion.escribir("Equipo \(id)/Plan \(id).md", "# Plan\n")
        let obs = try CarpetaDeFuera(e.base, nombre: "Boveda")
        try obs.escribir("Notas/.obsidian/app.json", "{}")
        try obs.escribir("Notas/Diario.md", "Hoy [[Otra]].\n")
        let correo = try CarpetaDeFuera(e.base, nombre: "Correo")
        try correo.escribir("Bandeja/hola.eml", "From: x\nSubject: hola\n\ncuerpo\n")
        try correo.escribir("Bandeja/otro.eml", "From: y\n\ncuerpo\n")
        let drive = try CarpetaDeFuera(e.base, nombre: "Drive")
        try drive.escribir("Mi unidad/Hoja.gsheet", "{\"url\": \"x\"}")
        try drive.escribir("Mi unidad/Presentación.numbers/Index.zip", "paquete")
        try drive.escribir("Mi unidad/Presentación.numbers/Data/a.bin", "dato")

        let fs = RecordingFileSystem()
        let fuentes = [e.fuente, FuenteImportacion(alias: "Notion", raiz: notion.raiz, clase: .externa),
                       FuenteImportacion(alias: "Boveda", raiz: obs.raiz, clase: .externa),
                       FuenteImportacion(alias: "Correo", raiz: correo.raiz, clase: .externa),
                       FuenteImportacion(alias: "Drive", raiz: drive.raiz, clase: .externa)]
        let inv = try await InventarioImportacion.hacer(fuentes, opciones: .init(hoy: EmpresaDePrueba.hoy), fileSystem: fs)
        let log = fs.log.withLock { $0 }
        #expect(!log.listed.contains { $0.contains("Expediente privado") })
        #expect(!log.hashed.contains { $0.contains("Expediente privado") })
        #expect(!inv.elementos.contains { $0.clave.contains("Expediente privado") })
        #expect(log.unprotectedCalls.isEmpty, "\(log.unprotectedCalls)")
        #expect(inv.podadas >= 1)

        #expect(inv.herramientas["Notion/Equipo \(id)"] == .notion)
        #expect(inv.herramientas["Boveda/Notas"] == .obsidian)
        #expect(inv.herramientas["Correo/Bandeja"] == .correo)
        #expect(inv.herramientas["Drive/Mi unidad"] == .drive)
        #expect(inv.herramientas["Carpeta/2 · Ventas"] == .ordenada)
        #expect(inv.herramientas["Carpeta/Clientes"] == .carpetas)
        // Un paquete es un solo documento: no se lista por dentro como ficheros sueltos.
        let paquete = try #require(inv.elemento("Drive/Mi unidad/Presentación.numbers"))
        #expect(paquete.esPaquete && paquete.tipo == .paquete && paquete.sha256 != nil)
        #expect(!inv.elementos.contains { $0.clave.contains("Presentación.numbers/") })
        #expect(inv.porTipo[.correo]?.ficheros == 2)
        #expect(inv.porHerramienta[.notion]?.ficheros == 2)
        #expect(inv.elemento("Notion/Equipo \(id)/Reunión de lunes \(id).md")?.nombreLimpio == "Reunión de lunes.md")
        #expect(inv.resumen.hasPrefix("\(inv.elementos.count) ficheros"))
    }

    @Test("Lo que solo está en iCloud no se lee ni se descarga: se cuenta y se clasifica por su nombre")
    func soloEnICloud() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let nube = e.url("Facturas/Factura 2025-03-15 Proveedor.pdf").path.precomposedStringWithCanonicalMapping
        let fs = RecordingFileSystem(datalessPaths: [nube])
        let inv = try await InventarioImportacion.hacer([e.fuente], opciones: .init(hoy: EmpresaDePrueba.hoy), fileSystem: fs)
        let el = try #require(inv.elemento("Carpeta/Facturas/Factura 2025-03-15 Proveedor.pdf"))
        #expect(el.soloEnICloud && el.sha256 == nil && el.extracto == nil)
        #expect(!fs.log.withLock { $0.hashed }.contains(nube))
        #expect(inv.soloEnICloud == 1)
        #expect(inv.resumen.contains("1 solo en iCloud: los miro por su nombre"))
        // Se clasifica por el nombre, pero se queda donde está (moverlo obligaría a descargarlo).
        let zona = ZonaPreparacion(inventario: inv, layout: VaultLayout.load(root: e.raiz).layout, hoy: EmpresaDePrueba.hoy)
        #expect(zona.propuestas[el.clave]?.coleccion == "finanzas.gastos")
        let d = try #require(zona.decisiones().first { $0.elemento.clave == el.clave })
        #expect(d.accion == .mantener && d.conflicto == "Solo en iCloud")
    }

    @Test("Claves y contraseñas: nunca se leen ni se resumen")
    func sensibles() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        try e.escribir("Varios/secrets.env", "CLAVE=no-es-real\n")
        try e.escribir("Varios/servidor.key", "-----BEGIN PRIVATE KEY-----\n")
        let fs = RecordingFileSystem()
        let inv = try await InventarioImportacion.hacer([e.fuente], opciones: .init(hoy: EmpresaDePrueba.hoy), fileSystem: fs)
        for c in ["Carpeta/Varios/secrets.env", "Carpeta/Varios/servidor.key"] {
            let el = try #require(inv.elemento(c))
            #expect(el.sensible && el.sha256 == nil && el.extracto == nil)
        }
        #expect(!fs.log.withLock { $0.hashed }.contains { $0.hasSuffix("secrets.env") || $0.hasSuffix("servidor.key") })
    }

    static func elemento(_ ruta: String, extracto: String? = nil, props: [String: String] = [:], fecha: String? = nil,
                         tipo: TipoDocumento? = nil) -> ElementoInventario {
        let p = VaultPath(ruta)
        return ElementoInventario(clave: "X/" + ruta, fuente: "X", ruta: p, esPaquete: false,
                                  tipo: tipo ?? TipoDocumento(extension: p.ext), tamano: 10, sha256: "a", soloEnICloud: false,
                                  sensible: false, modificado: nil, bloque: p.components.first ?? "", herramienta: .carpetas,
                                  extracto: extracto, propiedades: props, propiedadesLegibles: true,
                                  fechaEnNombre: InventarioImportacion.fechaEnNombre(p, hoy: EmpresaDePrueba.hoy))
    }

    @Test("Reglas: destino en la estructura v2, con confianza y motivo en castellano")
    func reglas() {
        let c = HeuristicClassifier(layout: .humana, hoy: EmpresaDePrueba.hoy)
        func p(_ e: ElementoInventario) -> PropuestaDestino { c.proponer(e, clase: .externa) }

        let factura = p(Self.elemento("Papeles/Factura luz 2025-11-03.pdf"))
        #expect(factura.destino?.raw == "4 · Finanzas/Fiscal/2025/T4/Gastos/Factura luz 2025-11-03.pdf")
        #expect(factura.confianza >= 0.6)
        #expect(factura.motivo.contains("factura") && factura.motivo.contains("del nombre"))

        let emitida = p(Self.elemento("Facturas emitidas/F-2026-0007 Cliente.pdf", fecha: nil))
        #expect(emitida.coleccion == "finanzas.ingresos")

        let modelo = p(Self.elemento("Hacienda/Modelo 303 2026-07-20.pdf"))
        #expect(modelo.destino?.raw == "4 · Finanzas/Fiscal/2026/T3/Modelos/Modelo 303 2026-07-20.pdf")
        let anual = p(Self.elemento("Hacienda/Modelo 390 2026-01-25.pdf"))
        #expect(anual.destino?.raw == "4 · Finanzas/Fiscal/2026/Modelos/Modelo 390 2026-01-25.pdf")

        let sinFecha = p(Self.elemento("Gastos/Ticket gasolinera.pdf"))
        #expect(sinFecha.destino?.raw == "4 · Finanzas/Fiscal/Sin fecha/Gastos/Ticket gasolinera.pdf")

        let contacto = p(Self.elemento("Contactos/Lucía Ferrer.md"))
        #expect(contacto.destino?.raw == "2 · Ventas/Contactos/lucia-ferrer.md")
        #expect(contacto.tipoFicha == "contact")

        let conTipo = p(Self.elemento("Cosas/Talleres Martín.md", props: ["tls_type": "organization"]))
        #expect(conTipo.destino?.raw == "2 · Ventas/Empresas/talleres-martin.md")
        #expect(conTipo.confianza >= 0.9)
        #expect(conTipo.motivo == "Sus propiedades dicen que es «empresa»")

        let proyecto = p(Self.elemento("Proyectos/Panadería Sol/briefing.pdf"))
        #expect(proyecto.destino?.raw == "3 · Entrega/Proyectos/panaderia-sol/Materiales/briefing.pdf")

        let logo = p(Self.elemento("Marca/Logos/logo-final.svg"))
        #expect(logo.coleccion == "marca.recursos")

        let correo = p(Self.elemento("Exportado/hola.eml"))
        #expect(correo.coleccion == "buzon.correo")

        let foto = p(Self.elemento("DCIM/IMG_0001.jpg"))
        #expect(foto.coleccion == "marca.recursos" && foto.confianza < 0.6)

        let nada = p(Self.elemento("Varios/xyz.dat"))
        #expect(nada.destino?.raw == "Buzón/Por ordenar/xyz.dat")
        #expect(nada.confianza <= 0.2)

        let porTexto = p(Self.elemento("Varios/documento.txt", extracto: "Contrato de prestación de servicios entre las partes"))
        #expect(porTexto.coleccion == "direccion.contratos")
        #expect(porTexto.confianza < AIClassifier.umbral)
        #expect(porTexto.motivo.hasPrefix("El texto habla de"))

        for x in [factura, emitida, modelo, sinFecha, contacto, conTipo, proyecto, logo, correo, foto, nada, porTexto] {
            #expect(!x.motivo.isEmpty)
            #expect(jerga(x.motivo).isEmpty, "\(x.motivo)")
        }
    }

    @Test("En la carpeta de la empresa, lo que ya está en un área se queda (y se adopta si es ficha sin id)")
    func enSuSitio() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        try e.escribir("2 · Ventas/Contactos/sin-id.md", "---\ntls_type: contact\n---\n# Sin id\n")
        let zona = try await prepararZona(e)
        let ya = try #require(zona.propuestas["Carpeta/2 · Ventas/Contactos/ana-lopez.md"])
        #expect(ya.enSuSitio && ya.destino == nil && ya.motivo == "Ya está en Ventas")
        let d = try #require(zona.decisiones().first { $0.elemento.clave == "Carpeta/2 · Ventas/Contactos/sin-id.md" })
        #expect(d.accion == .propiedades && d.tipoFicha == "contact")
        let raiz = try #require(zona.decisiones().first { $0.elemento.clave == "Carpeta/Empresa.md" })
        #expect(raiz.accion == .mantener)
    }

    @Test("Fechas en el nombre: las formas habituales en España")
    func fechasEnNombre() {
        let d = DocumentDater(opciones: .init(hoy: EmpresaDePrueba.hoy, ocr: nil))
        #expect(d.fechaEnNombre("Factura 17.06.25.pdf", ruta: "x")?.fecha == "2025-06-17")
        #expect(d.fechaEnNombre("Recibo 20 de mayo de 2025.pdf", ruta: "x")?.fecha == "2025-05-20")
        #expect(d.fechaEnNombre("Captura 2025Y-03M-15D.png", ruta: "x")?.fecha == "2025-03-15")
        #expect(d.fechaEnNombre("Invoice May 4, 2026.pdf", ruta: "x")?.fecha == "2026-05-04")
        let mes = d.fechaEnNombre("Gestoría abril25.pdf", ruta: "x")
        #expect(mes?.fecha == "2025-04" && mes?.nota == "solo el mes")
        #expect(d.fechaEnNombre("Libros marzo.pdf", ruta: "Fiscal/2025/Libros marzo.pdf")?.fecha == "2025-03")
        #expect(d.fechaEnNombre("Marketing plan.pdf", ruta: "x") == nil)
        #expect(d.fechaEnNombre("Versión 1.2.10.pdf", ruta: "x") == nil)            // número de versión, no fecha
        #expect(d.fechaEnNombre("Factura 2027-01-01.pdf", ruta: "x") == nil)         // en el futuro
        #expect(DocumentDater.nombreLlevaFecha("2026-07-01 Alquiler.pdf"))
        #expect(DocumentDater.nombreLlevaFecha("Extracto 2026-07.pdf"))
        #expect(!DocumentDater.nombreLlevaFecha("Factura julio.pdf"))
    }
}
