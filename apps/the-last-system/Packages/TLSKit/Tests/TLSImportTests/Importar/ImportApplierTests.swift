import Foundation
import Testing
import TLSCore
@testable import TLSImport

@Suite("Ordenar lo que tienes · aplicar, comprobar y deshacer", .serialized)
struct ImportApplierTests {
    @Test("Nada se escribe antes de «Aplicar»: inventario, zona, IA y vista previa solo leen (criterio F3-1)")
    func nadaAntesDeAplicar() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let fuera = try CarpetaDeFuera(e.base, nombre: "Drive")
        try fuera.escribir("Contactos/Carla Gil.md", "# Carla Gil\n")
        let antes = try await e.fotoCompleta()
        let antesFuera = try await Inventory.make(of: fuera.raiz, completo: true)
        let estadoAntes = relativeFiles(under: e.estado)
        var zona = try await prepararZona(e, externas: [FuenteImportacion(alias: "Drive", raiz: fuera.raiz, clase: .externa)])
        zona.fijarAlcance(.carpetas, .loActivo(desde: LocalDate(year: 2024, month: 1, day: 1)!))
        let ia = try ClaudeFalso(base: e.base, respuesta: #"{"elementos":[]}"#)
        _ = await AIClassifier(ejecutor: ia, consentimiento: true).clasificar(zona)
        let vista = try await applier(e).preparar(zona)
        #expect(vista.hayCambios)
        #expect(try await e.fotoCompleta().hashArbol == antes.hashArbol)
        #expect(try await Inventory.make(of: fuera.raiz, completo: true).hashArbol == antesFuera.hashArbol)
        #expect(relativeFiles(under: e.estado) == estadoAntes)
    }

    @Test("Una importación termina con 0 ficheros borrados y la comprobación sin diferencias (criterio F3-4)")
    func importacionCompleta() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let fuera = try CarpetaDeFuera(e.base, nombre: "Drive")
        try fuera.escribir("Propuestas/Propuesta Panadería Sol.pdf", datos: pdf("Propuesta\nFecha: 02/09/2026"))
        try fuera.escribir("Contactos/Carla Gil.md", "# Carla Gil\nVer [la propuesta](../Propuestas/Propuesta%20Panader%C3%ADa%20Sol.pdf).\n")
        try fuera.escribir("credenciales.env", "CLAVE=no-es-real\n")
        let drive = FuenteImportacion(alias: "Drive", raiz: fuera.raiz, clase: .externa)
        let antesFuera = try await Inventory.make(of: fuera.raiz, completo: true)
        let zona = try await prepararZona(e, externas: [drive])
        let vista = try await applier(e).preparar(zona)
        #expect(vista.resumen.hasSuffix("No se borra nada"))
        #expect(vista.resumen.hasPrefix("Mover \(vista.mover) · Propiedades a \(vista.propiedades) · Archivar \(vista.archivar)"))
        #expect(vista.enlacesEnRiesgo.isEmpty)
        // Lo privado y lo que parece llevar claves no aparecen ni se tocan.
        #expect(!vista.movimientos.contains { $0.clave.contains("Expediente privado") })
        #expect(!vista.mapa.csv.contains("Expediente privado"))
        let env = try #require(vista.movimientos.first { $0.clave == "Drive/credenciales.env" })
        #expect(env.accion == .fuera)

        let bus = try await e.bus()
        let r = try await applier(e).aplicar(vista, con: bus)
        #expect(r.verificacion.sinDiferencias, "\(r.verificacion.diferencias)")
        #expect(r.verificacion.texto.hasSuffix("(recuento + SHA-256)"))
        #expect(r.verificacion.comprobados == r.verificacion.total)
        #expect(r.verificacion.recuentoDespues == r.verificacion.recuentoAntes + r.escritura.creadas.count)

        // A su sitio, con choque resuelto como en F1 (`-2`, nunca «(2)»).
        #expect(e.existe("2 · Ventas/Contactos/ana-lopez-2.md"))
        #expect(e.texto("2 · Ventas/Contactos/ana-lopez.md")?.contains("la que ya estaba") == true)
        #expect(e.existe("2 · Ventas/Empresas/panaderia-sol.md"))
        #expect(e.existe("4 · Finanzas/Fiscal/2025/T1/Gastos/Factura 2025-03-15 Proveedor.pdf"))
        #expect(e.existe("4 · Finanzas/Fiscal/2025/T1/Gastos/Factura proveedor luz.pdf"))
        #expect(!e.existe("Clientes/Ana López.md"))
        // Las carpetas que se quedan vacías no se borran: van al Archivo de la importación.
        #expect(vista.carpetasVacias >= 3)
        #expect(!e.existe("Clientes") && e.existe("Archivo/Importación 2026-10-19/Clientes"))
        #expect(!e.existe("Notas") && !e.existe("Viejo"))
        // Adoptada: tipo e identificador (y el nombre bonito en `aliases` si cambia lo que se ve).
        let ana = try #require(e.texto("2 · Ventas/Contactos/ana-lopez-2.md"))
        #expect(ana.contains("tls_type: contact"))
        #expect(ana.contains("tls_schema: 1"))
        #expect(ana.range(of: #"id: [0-9a-f-]{36}"#, options: .regularExpression) != nil)
        // Los enlaces siguen apuntando a lo mismo (reescritos con la ruta nueva).
        #expect(ana.contains("(../Empresas/panaderia-sol.md)"))
        let panaderia = try #require(e.texto("2 · Ventas/Empresas/panaderia-sol.md"))
        #expect(panaderia.contains("(../Contactos/ana-lopez-2.md)"))
        // Lo de fuera se copia (el original no cambia) con sus enlaces arreglados; lo que tiene claves no se trae.
        let carla = try #require(e.texto("2 · Ventas/Contactos/carla-gil.md"))
        #expect(carla.contains("tls_type: contact"))
        #expect(carla.contains("[la propuesta](../Oportunidades/Propuesta%20Panadería%20Sol.pdf)"), "\(carla)")
        #expect(e.existe("2 · Ventas/Oportunidades/Propuesta Panadería Sol.pdf"))
        #expect(!relativeFiles(under: e.raiz).contains { $0.hasSuffix("credenciales.env") })
        #expect(try await Inventory.make(of: fuera.raiz, completo: true).hashArbol == antesFuera.hashArbol)
        // Duplicado exacto: a Archivo › Duplicados (no se borra).
        #expect(e.existe("Archivo/Duplicados/Notas/Ideas sueltas (1).md"))
        // Lo privado, intacto y donde estaba.
        #expect(e.texto("Expediente privado/secreto.md") == "contenido privado de prueba\n")
        // Fechas: la fila manual no se toca; las nuevas con su fuente.
        let fechas = try #require(e.texto("4 · Finanzas/Fechas de documentos.csv"))
        #expect(fechas.contains("Fiscal/2026/T1/Gastos/recibo.pdf,2026-01-10,manual,escrita a mano"))
        #expect(fechas.contains("Fiscal/2025/T1/Gastos/Factura proveedor luz.pdf,2025-03-12,documento"))
        #expect(!fechas.contains("Factura 2025-03-15"))   // la fecha ya está en el nombre
        // El informe, en el Buzón, con la comprobación anotada.
        let informe = try #require(e.texto("Buzón/Informe de importación 2026-10-19.md"))
        #expect(informe.contains("tls_type: import_report"))
        #expect(informe.contains("verificados: \(r.verificacion.comprobados)"))
        #expect(informe.contains(r.verificacion.texto))
        for s in ["## Resumen", "## Por bloques", "## Lo que se quedó donde estaba", "## Duplicados", "## Calidad de los datos",
                  "## Comprobación", "## Cómo deshacer"] { #expect(informe.contains(s), "Falta \(s)") }
        #expect(!informe.contains("Expediente privado"))
        #expect(jerga(informe).isEmpty, "\(jerga(informe))")
    }

    @Test("«Deshacer» deja el árbol con su huella de antes (criterio F3-4) y solo si no se escribió nada después")
    func deshacer() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let fuera = try CarpetaDeFuera(e.base, nombre: "Notion")
        try fuera.escribir("Clientes 0123456789abcdef0123456789abcdef/Bruno Ruiz 0123456789abcdef0123456789abcdef.md",
                           "---\ntipo: persona\n---\n# Bruno Ruiz\n")
        let antes = try await e.foto()
        let zona = try await prepararZona(e, externas: [FuenteImportacion(alias: "Notion", raiz: fuera.raiz, clase: .externa)])
        let vista = try await applier(e).preparar(zona)
        let bus = try await e.bus()
        let r = try await applier(e).aplicar(vista, con: bus)
        #expect(r.verificacion.sinDiferencias)
        #expect(e.existe("2 · Ventas/Contactos/bruno-ruiz.md"))   // sin el identificador de Notion
        #expect(r.hashArbolAntes == Verificador.sinArchivo(vista.inventarioAntes).hashArbol)
        #expect(await ImportApplier.sePuedeDeshacer(r, con: bus))
        try await ImportApplier.deshacer(r, con: bus)
        let despues = try await e.foto()
        #expect(despues.hashArbol == antes.hashArbol, "\(antes.diferencias(con: despues))")
        #expect(e.texto("Clientes/Ana López.md")?.contains("tipo: persona") == true)
        #expect(e.existe("Notas/Ideas sueltas (1).md") && e.existe("Viejo/Acta reunión 2019-05-02.md"))
        // Lo creado no se borra: se retira a Archivo.
        #expect(relativeFiles(under: e.url("Archivo")).contains { $0.hasSuffix("Informe de importación 2026-10-19.md") })
    }

    @Test("Si después se escribe otra cosa, «Deshacer» la importación lo explica y no toca nada")
    func deshacerNoDisponible() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let zona = try await prepararZona(e)
        let vista = try await applier(e).preparar(zona)
        let bus = try await e.bus()
        let r = try await applier(e).aplicar(vista, con: bus)
        _ = try await bus.ejecutar(.anadirLinea(VaultPath("Empresa.md"), linea: "Otra cosa."), autor: .persona("Manu"))
        #expect(!(await ImportApplier.sePuedeDeshacer(r, con: bus)))
        await #expect(throws: ImportError.deshacerNoDisponible) { try await ImportApplier.deshacer(r, con: bus) }
        #expect(e.existe("2 · Ventas/Contactos/ana-lopez-2.md"))
    }

    @Test("Si algo cambia entre la vista previa y «Aplicar», no se escribe nada")
    func cambioTrasLaVistaPrevia() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let zona = try await prepararZona(e)
        let vista = try await applier(e).preparar(zona)
        try e.escribir("Clientes/Ana López.md", "Cambiada fuera de la app.\n")
        let antes = try await e.fotoCompleta()
        let bus = try await e.bus()
        await #expect(throws: ImportError.cambioDesdeLaVistaPrevia("Ana López.md")) {
            try await applier(e).aplicar(vista, con: bus)
        }
        let despues = try await e.fotoCompleta()
        #expect(despues.diferencias(con: antes).allSatisfy { $0.hasPrefix(".tls/") })
    }

    @Test("Una carpeta que va entera a otro sitio se mueve de una vez (no quedan carpetas vacías)")
    func carpetaEntera() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        var zona = try await prepararZona(e)
        // «Viejo» es anterior a la fecha de corte: va entera al Archivo de la importación.
        zona.fijarAlcance(.carpetas, .loActivo(desde: LocalDate(year: 2024, month: 1, day: 1)!))
        let vista = try await applier(e).preparar(zona)
        #expect(vista.plan.ops.contains { if case .move(let a, let b) = $0 { a.raw == "Viejo" && b.raw == "Archivo/Importación 2026-10-19/Viejo" } else { false } })
        let r = try await applier(e).aplicar(vista, con: try await e.bus())
        #expect(r.verificacion.sinDiferencias)
        #expect(!e.existe("Viejo"))
        #expect(e.existe("Archivo/Importación 2026-10-19/Viejo/Acta reunión 2019-05-02.md"))
    }

    @Test("Con el motor del dominio, lo importado no dispara reglas (modo importación)")
    func reglasApagadas() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let zona = try await prepararZona(e)
        let vista = try await applier(e).preparar(zona)
        let bus = try await e.bus()
        let motor = try MotorDeDominio(bus: bus, opciones: .init(reloj: Reloj(hoy: EmpresaDePrueba.hoy)))
        let tareasAntes = relativeFiles(under: e.raiz).filter { $0.contains("/Tareas/") }
        let r = try await applier(e).aplicar(vista, con: bus, motor: motor)
        #expect(r.verificacion.sinDiferencias)
        #expect(await motor.modoImportacion == false)
        let eventos = try motor.estado.eventos()
        #expect(eventos.allSatisfy { $0.estado == .omitido })
        #expect(relativeFiles(under: e.raiz).filter { $0.contains("/Tareas/") } == tareasAntes)
    }

    @Test("Notas en otra codificación: se mueven sin tocarlas por dentro; las de fuera llegan en UTF-8")
    func otraCodificacion() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let latin1 = "---\ntipo: persona\n---\n# José Núñez\n".data(using: .isoLatin1)!
        try e.escribir("Clientes/José Núñez.md", datos: latin1)
        let fuera = try CarpetaDeFuera(e.base, nombre: "Viejo PC")
        try fuera.escribir("Contactos/Marta Ibáñez.md", datos: "# Marta Ibáñez\n".data(using: .isoLatin1)!)
        let zona = try await prepararZona(e, externas: [FuenteImportacion(alias: "Viejo PC", raiz: fuera.raiz, clase: .externa)])
        let vista = try await applier(e).preparar(zona)
        let r = try await applier(e).aplicar(vista, con: try await e.bus())
        #expect(r.verificacion.sinDiferencias, "\(r.verificacion.diferencias)")
        // La de dentro se mueve con sus mismos bytes (el escritor no cambia lo que no es UTF-8).
        #expect(try Data(contentsOf: e.url("2 · Ventas/Contactos/jose-nunez.md")) == latin1)
        // La de fuera llega en UTF-8 y adoptada.
        let marta = try #require(e.texto("2 · Ventas/Contactos/marta-ibanez.md"))
        #expect(marta.contains("# Marta Ibáñez") && marta.contains("tls_type: contact"))
    }

    @Test("Enlaces en riesgo: no se aplica sin aceptarlos")
    func enlacesEnRiesgo() async throws {
        let e = try EmpresaDePrueba.desordenada()
        defer { e.limpiar() }
        let zona = try await prepararZona(e)
        let vista = try await applier(e).preparar(zona)
        if !vista.enlacesEnRiesgo.isEmpty {
            await #expect(throws: ImportError.enlacesEnRiesgo(vista.enlacesEnRiesgo.count)) {
                try await applier(e).aplicar(vista, con: try await e.bus())
            }
        }
    }
}
