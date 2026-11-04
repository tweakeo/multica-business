import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Carpeta (F1 · visores): Nueva…, renombrar y mover con sus enlaces, retirar al Archivo y arreglar lo movido
/// fuera de la app. Siempre sobre una copia temporal de Asesoría Ribera; todo pasa por `CommandBus`.
@Suite("Carpeta · cambios con sus enlaces", .serialized)
@MainActor
struct CarpetaTests {
    let pruebas = SesionEscrituraTests()
    let renta = VaultPath("2 · Ventas/Productos/renta.md")

    /// Sesión con escritura sobre Ribera temporal.
    func abrir(clase: VaultClass = .demo, escritura: WriteAccess = .permitida) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: clase, escritura: escritura)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        return (e, sesion)
    }

    /// Bytes de cada fichero de la carpeta (sin la marca del escritor), para comparar «los mismos bytes».
    static func contenido(_ raiz: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let fm = FileManager.default
        let e = fm.enumerator(at: raiz, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        while let f = e?.nextObject() as? URL {
            guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let rel = VaultPath(url: f, root: raiz), rel.raw != ".tls/escritor.json", rel.name != ".DS_Store" else { continue }
            out[rel.raw] = try Data(contentsOf: f)
        }
        return out
    }

    /// Enlaces que no llevan limpiamente a una sola nota (pendientes, flojos o ambiguos; sin plantillas).
    static func rotos(_ raiz: URL) -> Int {
        SaludDeEnlaces(snapshot: VaultSnapshot.read(root: raiz)).revisar().count
    }

    func esperar(_ condicion: @MainActor () -> Bool) async { await pruebas.esperar(condicion) }

    // MARK: Lista

    @Test("Lista la carpeta con el título de cada nota, las carpetas primero y el icono de área")
    func lista() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let raiz = CarpetaModelo(carpeta: nil, sesion: sesion)
        await raiz.cargar()
        #expect(raiz.titulo == "Carpeta de tu empresa")
        let ventas = try #require(raiz.fila(VaultPath("2 · Ventas")))
        #expect(ventas.esCarpeta && ventas.area == .ventas && ventas.detalle == "Área")
        #expect(raiz.filas.prefix { $0.esCarpeta }.count == raiz.filas.filter(\.esCarpeta).count)
        #expect(raiz.destino(de: ventas) == .carpeta(VaultPath("2 · Ventas")))

        let contactos = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Contactos"), sesion: sesion)
        await contactos.cargar()
        let jorge = try #require(contactos.fila(pruebas.jorge))
        #expect(jorge.titulo == "Jorge Martín")
        #expect(jorge.tipo == .contact)
        #expect(jorge.detalle.hasPrefix("Contacto"))
        #expect(contactos.destino(de: jorge) == .ficha(pruebas.jorge))
        #expect(contactos.motivoSoloLectura == nil)

        let gastos = CarpetaModelo(carpeta: VaultPath("4 · Finanzas/Fiscal/2026/T4/Gastos/software-contable-nube"), sesion: sesion)
        await gastos.cargar()
        let pdf = try #require(gastos.filas.first)
        #expect(pdf.ruta.ext == "pdf" && pdf.detalle.hasPrefix("PDF"))
        #expect(gastos.destino(de: pdf) == .fichero(pdf.ruta))
    }

    // MARK: Renombrar

    @Test("Renombrar desde Carpeta: vista previa con los enlaces, 0 enlaces rotos y deshacer deja los mismos bytes")
    func renombrar() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = try Self.contenido(e.carpeta)
        let rotosAntes = Self.rotos(e.carpeta)
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Productos"), sesion: sesion)
        await modelo.cargar()
        modelo.seleccion = [renta]

        let previa = try await modelo.prepararRenombrar(renta, a: "renta-anual")
        #expect(previa.esSeguro)
        #expect(previa.enlaces >= 20)
        #expect(previa.resumen.contains("actualizará"))
        #expect(previa.cambios.contains { $0.enlaces.contains { $0.antes.contains("Productos/renta") && $0.despues.contains("renta-anual") } })
        // La vista previa no escribe.
        #expect(try Self.contenido(e.carpeta) == antes)

        let r = await modelo.aplicar(previa) { try await modelo.prepararRenombrar(self.renta, a: "renta-anual", fresca: true) }
        guard case .hecho(let resultado) = r else { Issue.record("No se renombró: \(r)"); return }
        let nueva = VaultPath("2 · Ventas/Productos/renta-anual.md")
        #expect(FileManager.default.fileExists(atPath: nueva.url(in: e.carpeta).path))
        #expect(!FileManager.default.fileExists(atPath: renta.url(in: e.carpeta).path))
        #expect(Self.rotos(e.carpeta) == rotosAntes)
        let foto = VaultSnapshot.read(root: e.carpeta)
        #expect(!foto.notes.contains { foto.text($0)?.contains("[[2 · Ventas/Productos/renta|") == true })
        #expect(modelo.seleccion == [nueva])
        #expect(sesion.aviso?.texto.hasPrefix("Actualicé") == true)
        #expect(sesion.aviso?.accion != nil)

        await sesion.deshacer(plan: resultado.planID)
        await esperar { (try? Self.contenido(e.carpeta)) == antes }
        #expect(try Self.contenido(e.carpeta) == antes)
    }

    @Test("Renombrar una carpeta: todos los enlaces con ruta cambian y deshacer la deja igual")
    func renombrarCarpeta() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = try Self.contenido(e.carpeta)
        let rotosAntes = Self.rotos(e.carpeta)
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas"), sesion: sesion)
        await modelo.cargar()
        let previa = try await modelo.prepararRenombrar(VaultPath("2 · Ventas/Productos"), a: "Servicios")
        #expect(previa.enlaces >= 37)
        guard case .hecho(let r) = await modelo.aplicar(previa) else { Issue.record("No se renombró"); return }
        #expect(FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("2 · Ventas/Servicios/renta.md").path))
        #expect(Self.rotos(e.carpeta) == rotosAntes)
        await sesion.deshacer(plan: r.planID)
        await esperar { (try? Self.contenido(e.carpeta)) == antes }
        #expect(try Self.contenido(e.carpeta) == antes)
        #expect(!FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("2 · Ventas/Servicios").path))
    }

    @Test("Un nombre con / o [ ] no vale y no se escribe nada")
    func nombreNoValido() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Productos"), sesion: sesion)
        await #expect(throws: RefactorError.self) { try await modelo.prepararRenombrar(self.renta, a: "renta/anual") }
        await #expect(throws: RefactorError.sinCambios) { try await modelo.prepararRenombrar(self.renta, a: "renta") }
    }

    // MARK: Mover

    @Test("Mover a otra carpeta (lo que hace soltar una fila): enlaces al día y deshacer")
    func mover() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = try Self.contenido(e.carpeta)
        let rotosAntes = Self.rotos(e.carpeta)
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Productos"), sesion: sesion)
        await modelo.cargar()
        let destinos = await modelo.carpetasDestino(moviendo: [renta])
        #expect(destinos.contains(VaultPath("2 · Ventas/Productos/Versiones")))
        #expect(!destinos.contains(VaultPath("2 · Ventas/Productos")))
        #expect(!destinos.contains { $0.raw.hasPrefix(".tls") })
        let previa = try await modelo.prepararMover([renta], a: VaultPath("2 · Ventas/Productos/Versiones"))
        #expect(previa.enlaces >= 20)
        guard case .hecho(let r) = await modelo.aplicar(previa) else { Issue.record("No se movió"); return }
        #expect(FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("2 · Ventas/Productos/Versiones/renta.md").path))
        #expect(Self.rotos(e.carpeta) == rotosAntes)
        await sesion.deshacer(plan: r.planID)
        await esperar { (try? Self.contenido(e.carpeta)) == antes }
        #expect(try Self.contenido(e.carpeta) == antes)
    }

    // MARK: Retirar

    @Test("Retirar mueve al Archivo (nunca borra) y se puede deshacer")
    func retirar() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = try Self.contenido(e.carpeta)
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Contactos"), sesion: sesion)
        await modelo.cargar()
        let lola = VaultPath("2 · Ventas/Contactos/lola-plaza.md")
        let datos = try Data(contentsOf: lola.url(in: e.carpeta))
        #expect(await modelo.retirar(lola))
        #expect(!FileManager.default.fileExists(atPath: lola.url(in: e.carpeta).path))
        let retirada = e.carpeta.appendingPathComponent("Archivo/2 · Ventas/Contactos/lola-plaza.md")
        #expect(try Data(contentsOf: retirada) == datos)
        #expect(modelo.estaRetirada(VaultPath("Archivo/2 · Ventas/Contactos/lola-plaza.md")))
        #expect(sesion.aviso?.texto == "Retiré «lola-plaza» al Archivo")
        sesion.aviso?.accion?()
        await esperar { (try? Self.contenido(e.carpeta)) == antes }
        #expect(try Self.contenido(e.carpeta) == antes)
    }

    // MARK: Nueva…

    @Test("Nueva… ofrece las plantillas de la carpeta, las de la ficha elegida y una nota en blanco")
    func opcionesNueva() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let contactos = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Contactos"), sesion: sesion)
        await contactos.cargar()
        let enCarpeta = await contactos.opcionesNueva(seleccion: nil)
        #expect(enCarpeta.contains { $0.origen == .carpeta && $0.tipo == "contact" })
        #expect(enCarpeta.last?.origen == .notaEnBlanco)
        #expect(!enCarpeta.contains { $0.preguntas.contains("oportunidad") })
        let conJorge = await contactos.opcionesNueva(seleccion: pruebas.jorge)
        let reunion = try #require(conJorge.first { $0.tipo == "meeting" })
        #expect(reunion.desde == pruebas.jorge)
        #expect(reunion.detalle == "Para «Jorge Martín»")
        let valores = await contactos.valoresIniciales(para: reunion)
        #expect(valores["fecha"] == "2026-10-19")   // el día fijo del ejemplo
    }

    @Test("Nueva… crea con la plantilla por CommandBus; una nota en blanco; y «Ya existe» se completa")
    func crear() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let contactos = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Contactos"), sesion: sesion)
        await contactos.cargar()
        let opcion = try #require(await contactos.opcionesNueva(seleccion: nil).first { $0.tipo == "contact" })
        let r = await contactos.crear(opcion, valores: ["titulo": "Nuria Prueba", "email": "nuria@ejemplo.es"])
        guard case .hecho(let ruta, let destino) = r else { Issue.record("No se creó: \(r)"); return }
        #expect(ruta.parent == VaultPath("2 · Ventas/Contactos"))
        #expect(destino == .ficha(ruta))
        let texto = try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("tls_type: contact"))
        #expect(texto.contains("Nuria Prueba"))
        #expect(sesion.aviso?.texto == "Creé «Nuria Prueba»")

        let blanco = try #require(await contactos.opcionesNueva(seleccion: nil).last)
        let b = await contactos.crear(blanco, valores: ["titulo": "Ideas sueltas"])
        guard case .hecho(let rb, let db) = b else { Issue.record("No se creó la nota en blanco"); return }
        #expect(rb == VaultPath("2 · Ventas/Contactos/Ideas sueltas.md"))
        #expect(db == .nota(rb))
        #expect(try String(contentsOf: rb.url(in: e.carpeta), encoding: .utf8) == "# Ideas sueltas\n\n")
        #expect(await contactos.crear(blanco, valores: ["titulo": "Ideas sueltas"]) == .yaExiste(rb))

        let raiz = CarpetaModelo(carpeta: nil, sesion: sesion)
        await raiz.cargar()
        let empresa = try #require(await raiz.opcionesNueva(seleccion: nil).first { $0.tipo == "company" })
        #expect(await raiz.crear(empresa, valores: [:]) == .yaExiste(VaultPath("Empresa.md")))
        #expect(await raiz.completar(VaultPath("Empresa.md"), con: empresa) == nil)
    }

    @Test("Solo lectura: Nueva… no escribe y dice por qué")
    func soloLectura() async throws {
        let (e, sesion) = try await abrir(clase: .copia, escritura: .bloqueada)
        defer { sesion.close(); e.limpiar() }
        let antes = try Self.contenido(e.carpeta)
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Contactos"), sesion: sesion)
        await modelo.cargar()
        #expect(modelo.motivoSoloLectura == "Elegiste verla sin cambiar nada")
        let blanco = try #require(await modelo.opcionesNueva(seleccion: nil).last)
        #expect(await modelo.crear(blanco, valores: ["titulo": "No"]) == .error("Elegiste verla sin cambiar nada"))
        let previa = try await modelo.prepararRenombrar(pruebas.jorge, a: "jorge")
        if case .hecho = await modelo.aplicar(previa) { Issue.record("Escribió en solo lectura") }
        #expect(try Self.contenido(e.carpeta) == antes)
    }

    // MARK: Plantillas por carpeta

    @Test("Qué plantilla nace en cada carpeta")
    func plantillasPorCarpeta() {
        let layout = VaultLayout.demo
        let ventas = layout.areaFolder(.ventas)
        #expect(PlantillasCarpeta.encaja("{ventas}/Contactos", en: ventas.appending("Contactos"), layout: layout))
        #expect(PlantillasCarpeta.encaja("{area}/Tareas", en: ventas.appending("Tareas"), layout: layout))
        #expect(!PlantillasCarpeta.encaja("{area}/Tareas", en: VaultPath("Buzón/Tareas"), layout: layout))
        #expect(PlantillasCarpeta.encaja("{area}/Proyectos/{{slug}}", en: ventas.appending("Proyectos"), layout: layout))
        #expect(!PlantillasCarpeta.encaja("{ventas}/Oportunidades/{{oportunidad.slug}}", en: ventas.appending("Oportunidades"), layout: layout))
        #expect(!PlantillasCarpeta.encaja("{{proyecto.carpeta}}/Tareas", en: ventas.appending("Tareas"), layout: layout))
        #expect(PlantillasCarpeta.encaja("", en: .root, layout: layout))
        #expect(PlantillasCarpeta.encaja("Buzón", en: VaultPath("Buzón"), layout: layout))
        #expect(PlantillasCarpeta.variables(en: "{{fecha}}-{{slug}} {{numero:cifras}}") == ["fecha", "slug", "numero"])
        #expect(PlantillasCarpeta.etiqueta("sistema") == "Función")
    }

    // MARK: Movido fuera de la app

    @Test("Lo movido en Finder: se detecta por la lista de antes y por los enlaces rotos, y se arregla con Deshacer")
    func movidoFuera() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let rotosAntes = Self.rotos(e.carpeta)
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Productos"), sesion: sesion)
        await modelo.cargar()
        await modelo.revisarMovimientosExternos()
        #expect(modelo.arreglo == nil)
        let antes = Set(VaultSnapshot.read(root: e.carpeta).files)

        // Como en Finder (fuera de la app): solo en la carpeta temporal de la prueba. «renta» se llama igual que
        // otra nota (sus enlaces quedan ambiguos); «Oferta» es única y la enlaza un Markdown relativo.
        let nueva = VaultPath("2 · Ventas/Productos/Versiones/renta.md")
        let oferta = VaultPath("2 · Ventas/Productos/Oferta.md")
        let ofertaNueva = VaultPath("2 · Ventas/Productos/Versiones/Oferta.md")
        try FileManager.default.moveItem(at: renta.url(in: e.carpeta), to: nueva.url(in: e.carpeta))
        try FileManager.default.moveItem(at: oferta.url(in: e.carpeta), to: ofertaNueva.url(in: e.carpeta))
        let movida = try Self.contenido(e.carpeta)
        #expect(Self.rotos(e.carpeta) > rotosAntes)

        let foto = VaultSnapshot.read(root: e.carpeta)
        #expect(Set(MovimientosExternos.entre(antes: antes, ahora: foto)) == [Traslado(de: renta, a: nueva), Traslado(de: oferta, a: ofertaNueva)])
        // Sin la lista de antes (al abrir la Carpeta), por los enlaces rotos: solo lo que no es ambiguo.
        #expect(MovimientosExternos.porEnlacesRotos(foto) == [Traslado(de: oferta, a: ofertaNueva)])

        await modelo.revisarMovimientosExternos(fresca: true)
        let arreglo = try #require(modelo.arreglo)
        #expect(Set(arreglo.traslados) == [Traslado(de: renta, a: nueva), Traslado(de: oferta, a: ofertaNueva)])
        #expect(arreglo.enlaces >= 21)
        // Arreglar solo cambia enlaces: no mueve nada.
        #expect(!arreglo.plan.ops.contains { if case .move = $0 { return true }; return false })

        guard case .hecho(let r) = await modelo.arreglarMovimientos() else { Issue.record("No se arregló"); return }
        #expect(Self.rotos(e.carpeta) == rotosAntes)
        #expect(modelo.arreglo == nil)
        #expect(FileManager.default.fileExists(atPath: nueva.url(in: e.carpeta).path))
        #expect(try String(contentsOf: VaultPath("2 · Ventas/Área.md").url(in: e.carpeta), encoding: .utf8)
            .contains("(Productos/Versiones/Oferta.md)"))
        await sesion.deshacer(plan: r.planID)
        await esperar { (try? Self.contenido(e.carpeta)) == movida }
        #expect(try Self.contenido(e.carpeta) == movida)
    }
}
