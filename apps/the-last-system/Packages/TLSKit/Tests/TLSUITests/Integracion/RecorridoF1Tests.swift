import Foundation
import PDFKit
import Testing
import TLSCore
import TLSDesign
import TLSEditor
import TLSVisores
@testable import TLSUI

/// Recorrido completo de F1 con Asesoría Ribera copiada a un temporal, sin abrir la app: navegar en profundidad
/// y volver (criterios §11.1 y §11.10), relación desde el lado que no la guarda (§11.4), una celda (§11.5),
/// renombrar desde Carpeta con sus enlaces, abrir un PDF e incrustarlo en una nota (R1). Todo lo que escribe pasa
/// por `CommandBus` y se deshace dejando los mismos bytes.
@Suite("Recorrido F1 con Ribera (sin pantalla)", .serialized)
@MainActor
struct RecorridoF1Tests {
    let pruebas = SesionEscrituraTests()
    let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")
    let andres = VaultPath("2 · Ventas/Contactos/andres-vidal.md")
    let talleres = VaultPath("2 · Ventas/Empresas/talleres-martin-e-hijos.md")
    let proyecto = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md")
    let renta = VaultPath("2 · Ventas/Productos/renta.md")
    let pdf = VaultPath("4 · Finanzas/Fiscal/2026/T3/Gastos/movil-levante/2026-07-10 Movil Levante ML-07-2026 78,65€.pdf")

    /// Ribera en una copia temporal con el proyecto de Jorge y sus tareas (Ribera no trae proyectos: nacen al
    /// confirmar el cobro). Sesión con escritura, firmada por Manu.
    func abrir(conProyecto: Bool = true) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        if conProyecto { try CapturasFichasTests.prepararProyecto(e.carpeta) }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        #expect(sesion.isReady)
        #expect(sesion.puedeEscribir)
        return (e, sesion)
    }

    func ficha(_ ruta: VaultPath, _ sesion: VaultSession) async -> FichaModelo {
        let m = FichaModelo(ruta: ruta, sesion: sesion)
        await m.cargar()
        return m
    }

    func base(_ id: String, _ sesion: VaultSession, nav: Navegacion) async throws -> BaseModelo {
        let c = try #require(CatalogoBases.coleccion(id))
        let m = BaseModelo(coleccion: c, sesion: sesion, destino: .base(id), contexto: nil, vista: nil)
        m.nav = nav
        await m.cargar()
        return m
    }

    static func lineas(_ d: Data) -> [String] { String(decoding: d, as: UTF8.self).components(separatedBy: "\n") }

    // MARK: §11.1 y §11.10

    @Test("Bases › Contactos › Jorge › Proyectos › proyecto › tarea; ⌘[ vuelve al contacto en Proyectos y a la base con sus filtros")
    func navegarEnProfundidad() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = try CarpetaTests.contenido(e.carpeta)
        let nav = Navegacion(raiz: .todasLasBases)
        sesion.navegacionActiva = nav
        let navegar = NavegarAccion(nav: nav, empresa: nil) { _ in }

        // Todas las bases › Contactos (entra un nivel) con un filtro y desplazada.
        navegar(.base("contactos"), modo: .entrar)
        let contactos = try await base("contactos", sesion, nav: nav)
        contactos.anadirFiltro(FiltroBase("estado", .es, ["Activo"]))
        nav.actualizarRecuerdo(de: .base("contactos")) { $0.desplazamiento = 240 }
        let filaJorge = try #require(contactos.filas.first { $0.ruta == jorge })

        // › Jorge (doble clic en la fila): su ficha.
        let reloj = ContinuousClock()
        navegar(filaJorge.destino(en: sesion), modo: .entrar)
        #expect(nav.actual == .ficha(jorge))
        let mJorge = await ficha(jorge, sesion)
        // › pestaña Proyectos (no es un paso del historial).
        nav.cambiarPestana("Proyectos")
        nav.actualizarRecuerdo(de: .ficha(jorge)) { $0.extra["pestana"] = "Proyectos" }
        #expect(mJorge.pestanaElegida(nav.actual.pestana, nav: nav) == "Proyectos")
        let enProyectos = mJorge.relacionados([.project]).map(\.id)
        #expect(enProyectos.contains(proyecto))

        // › el proyecto › una de sus tareas.
        navegar(sesion.destino(para: proyecto), modo: .entrar)
        let inicio = reloj.now
        let mProyecto = await ficha(proyecto, sesion)
        let tProyecto = reloj.now - inicio
        let tarea = try #require(mProyecto.relacionados([.task]).map(\.id).sorted { $0.raw < $1.raw }.first)
        navegar(sesion.destino(para: tarea), modo: .entrar)
        let inicioTarea = reloj.now
        let mTarea = await ficha(tarea, sesion)
        let tTarea = reloj.now - inicioTarea
        #expect(mTarea.ficha?.tipo == .task)
        // F2: una tarea abre su detalle (`.tarea`), no la ficha genérica (docs/F2-CONTRATOS.md §3).
        #expect(nav.migas == [.todasLasBases, .base("contactos"), .ficha(jorge, pestana: "Proyectos"), .ficha(proyecto), .tarea(tarea)])
        // §11.10: entrar un nivel (con lo de la empresa ya leído) tarda menos de 100 ms con Ribera. Se mide lo
        // mejor de seis lecturas de cada ficha; sola, da menos de 1 ms. Con todo el paquete a la vez la máquina va cargada,
        // así que aquí el tope es más ancho (atrapa una regresión gorda) y la cifra se imprime para el informe.
        var mejorProyecto = tProyecto, mejorTarea = tTarea
        for _ in 0..<5 {
            let a = reloj.now; _ = await ficha(proyecto, sesion); mejorProyecto = min(mejorProyecto, reloj.now - a)
            let b = reloj.now; _ = await ficha(tarea, sesion); mejorTarea = min(mejorTarea, reloj.now - b)
        }
        print("LATENCIA-NIVEL Ribera · proyecto \(mejorProyecto) · tarea \(mejorTarea) (mejor de 6)")
        // F5/F6 · integración: con las suites de F5 y F6 en paralelo, lo medido es sobre todo la espera del hilo principal
        // (0,25–0,53 s en la suite entera; sola, < 1 ms): el tope cargado pasa a 1 s; el estricto sigue en 100 ms.
        let tope: Duration = ProcessInfo.processInfo.environment["TLS_LATENCIA_ESTRICTA"] != nil ? .milliseconds(100) : .milliseconds(1000)
        #expect(mejorProyecto < tope, "Entrar en el proyecto tardó \(mejorProyecto)")
        #expect(mejorTarea < tope, "Entrar en la tarea tardó \(mejorTarea)")

        // ⌘[ ⌘[: vuelve al contacto, en la pestaña Proyectos.
        nav.irAtras()
        #expect(nav.actual == .ficha(proyecto))
        nav.irAtras()
        #expect(nav.actual == .ficha(jorge, pestana: "Proyectos"))
        let otraVez = await ficha(jorge, sesion)
        #expect(otraVez.pestanaElegida(nav.actual.pestana, nav: nav) == "Proyectos")
        // Otro ⌘[: la base, con los mismos filtros y el mismo desplazamiento.
        nav.irAtras()
        #expect(nav.actual == .base("contactos"))
        let deVuelta = try await base("contactos", sesion, nav: nav)
        #expect(deVuelta.config.filtros == [FiltroBase("estado", .es, ["Activo"])])
        #expect(deVuelta.filas.contains { $0.ruta == jorge })
        #expect(nav.recuerdo(de: .base("contactos")).desplazamiento == 240)
        // Y ⌘] vuelve a donde estaba.
        nav.irAdelante()
        #expect(nav.actual == .ficha(jorge, pestana: "Proyectos"))
        // Navegar no escribe nada.
        #expect(try CarpetaTests.contenido(e.carpeta) == antes)
    }

    @Test("Guía de Manu con Ribera tal cual: confirmar el cobro de F-2026-0007 y crear el proyecto desde Jorge › Proyectos, ya enlazado")
    func proyectoDesdeElContacto() async throws {
        let (e, sesion) = try await abrir(conProyecto: false)
        defer { sesion.close(); e.limpiar() }
        let factura = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
        let opo = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
        let opcionProyecto = OpcionNuevo(titulo: "Proyecto", plantilla: "proyecto-de-entrega", tipo: .project)
        // Sin cobro confirmado, el proyecto no nace y lo dice (con la factura para abrir).
        let mJorge = await ficha(jorge, sesion)
        var p = PreparadorNuevo(opcion: opcionProyecto, modelo: mJorge)
        p.oportunidad = opo
        guard case .bloqueada(_, let abrirFactura) = p.estado() else { Issue.record("Debería esperar al cobro"); return }
        #expect(abrirFactura == factura)
        // En la factura: «Confirmar el cobro» (recibo + factura Cobrada en un paso).
        let mFactura = await ficha(factura, sesion)
        #expect(AccionDocumento.de(mFactura).map(\.titulo).contains("Confirmar el cobro"))
        let recibo = PreparadorNuevo(opcion: OpcionNuevo(titulo: "Recibo de cobro", plantilla: "recibo-de-cobro", tipo: .receipt), modelo: mFactura)
        let r0 = sesion.revision
        #expect(await recibo.crear() != nil)
        await pruebas.esperar { sesion.revision > r0 }
        // De vuelta en Jorge › Proyectos › «+ Nuevo» › Proyecto: nace enlazado con su oportunidad, empresa y contacto.
        mJorge.almacen.invalidar()
        await mJorge.cargar()
        var q = PreparadorNuevo(opcion: opcionProyecto, modelo: mJorge)
        q.oportunidad = opo
        guard case .lista(let nota) = q.estado() else { Issue.record("El proyecto no se pudo preparar: \(q.estado())"); return }
        let enlaces = PreparadorNuevo.enlaces(nota).map { $0.joined(separator: " · ") }
        #expect(enlaces.contains { $0.contains("Jorge Martín · Trimestrales") })
        let r1 = sesion.revision
        let creado = try #require(await q.crear())
        await pruebas.esperar { sesion.revision > r1 }
        #expect(sesion.destino(para: creado) == .ficha(creado))
        mJorge.almacen.invalidar()
        await mJorge.cargar()
        #expect(mJorge.relacionados([.project]).map(\.id).contains(creado))
    }

    // MARK: §11.4

    @Test("Relación desde el lado que no la guarda: la empresa añade un contacto y se escribe una línea en el contacto; Deshacer deja los bytes")
    func relacionDesdeElOtroLado() async throws {
        let (e, sesion) = try await abrir(conProyecto: false)
        defer { sesion.close(); e.limpiar() }
        let urlAndres = andres.url(in: e.carpeta)
        let antes = try Data(contentsOf: urlAndres)
        let empresaAntes = try Data(contentsOf: talleres.url(in: e.carpeta))
        let m = await ficha(talleres, sesion)
        m.abrirSelectorInverso(tipos: [.contact])
        let p = try #require(m.selector)
        await m.elegido(andres, en: p, navegar: nil)
        if let c = m.confirmacion {
            await EdicionRelaciones.confirmar(c, sesion: sesion, almacen: m.almacen)
        }
        let despues = try Data(contentsOf: urlAndres)
        let la = Self.lineas(antes), ld = Self.lineas(despues)
        // Una línea nueva (`empresa: "[[…]]"`) y nada más cambia; la empresa, que no la guarda, queda igual.
        #expect(ld.count == la.count + 1)
        #expect(la.allSatisfy { ld.contains($0) })
        #expect(ld.filter { !la.contains($0) } == [#"empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]""#])
        #expect(try Data(contentsOf: talleres.url(in: e.carpeta)) == empresaAntes)
        #expect(sesion.aviso?.accion != nil)
        let ultimo = try #require(await sesion.bus?.ultimoDeshacible())
        await sesion.deshacer(plan: ultimo.planID)
        #expect(try Data(contentsOf: urlAndres) == antes)
    }

    // MARK: §11.5

    @Test("Editar una celda de la base escribe solo esa clave; Deshacer deja los bytes")
    func celda() async throws {
        let (e, sesion) = try await abrir(conProyecto: false)
        defer { sesion.close(); e.limpiar() }
        let nav = Navegacion(raiz: .base("contactos"))
        let contactos = try await base("contactos", sesion, nav: nav)
        let fila = try #require(contactos.datos?.filas.first { $0.ruta == jorge })
        let canal = try #require(contactos.coleccion.columna("canal"))
        let url = jorge.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let error = await contactos.guardar(fila, canal, texto: "correo")
        #expect(error == nil)
        let la = Self.lineas(antes), ld = Self.lineas(try Data(contentsOf: url))
        #expect(la.count == ld.count)
        #expect(zip(la, ld).filter { $0 != $1 }.map(\.1) == ["canal: correo"])
        let ultimo = try #require(await sesion.bus?.ultimoDeshacible())
        await sesion.deshacer(plan: ultimo.planID)
        #expect(try Data(contentsOf: url) == antes)
    }

    // MARK: Carpeta

    @Test("Renombrar desde Carpeta actualiza todos los enlaces (0 rotos) y la ficha sigue en las migas; Deshacer deja los bytes")
    func renombrarConEnlaces() async throws {
        let (e, sesion) = try await abrir(conProyecto: false)
        defer { sesion.close(); e.limpiar() }
        let antes = try CarpetaTests.contenido(e.carpeta)
        let rotos = CarpetaTests.rotos(e.carpeta)
        let nav = Navegacion(raiz: .carpeta(VaultPath("2 · Ventas/Productos")))
        nav.entrar(.ficha(renta))
        sesion.navegacionActiva = nav
        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Productos"), sesion: sesion)
        await modelo.cargar()
        let previa = try await modelo.prepararRenombrar(renta, a: "renta-anual")
        #expect(previa.esSeguro)
        #expect(previa.enlaces > 0)
        guard case .hecho(let r) = await modelo.aplicar(previa) else { Issue.record("No se renombró"); return }
        let nueva = VaultPath("2 · Ventas/Productos/renta-anual.md")
        #expect(FileManager.default.fileExists(atPath: nueva.url(in: e.carpeta).path))
        #expect(CarpetaTests.rotos(e.carpeta) == rotos)
        // §2.1 regla 6: las migas siguen llevando a la ficha renombrada.
        #expect(nav.actual == .ficha(nueva))
        await sesion.deshacer(plan: r.planID)
        await pruebas.esperar { (try? CarpetaTests.contenido(e.carpeta)) == antes }
        #expect(try CarpetaTests.contenido(e.carpeta) == antes)
    }

    // MARK: R1 · PDF

    @Test("Abrir un PDF: desde Gastos y desde la Carpeta va a su visor, recuerda la página y no escribe nada")
    func abrirPDF() async throws {
        let (e, sesion) = try await abrir(conProyecto: false)
        defer { sesion.close(); e.limpiar() }
        let antes = try CarpetaTests.contenido(e.carpeta)
        #expect(sesion.destino(para: pdf) == .fichero(pdf))
        // En la base Gastos, la fila del CSV abre su documento.
        let navGastos = Navegacion(raiz: .base("gastos"))
        let gastos = try await base("gastos", sesion, nav: navGastos)
        let conDocumento = try #require(gastos.datos?.filas.first { $0.documento != nil })
        if case .fichero = conDocumento.destino(en: sesion) {} else { Issue.record("La fila de gasto no abre su documento") }
        // Abrir en la página 2: queda en el recuerdo de la pestaña.
        let nav = Navegacion(raiz: .carpeta(pdf.parent))
        VisorFicheroPantalla.abrir(pdf, pagina: 2, nav: nav, navegar: NavegarAccion(nav: nav, empresa: nil) { _ in }, modo: .entrar)
        #expect(nav.actual == .fichero(pdf))
        #expect(nav.recuerdo(de: .fichero(pdf)).extra["pagina"] == "2")
        // El visor (PDFKit) lo carga desde la URL que da la sesión.
        let url = try #require(sesion.url(for: pdf))
        let visor = ControladorPDF()
        #expect(visor.cargar(url: url, pagina: 1))
        #expect(visor.totalPaginas >= 1)
        #expect(try CarpetaTests.contenido(e.carpeta) == antes)
    }

    @Test("Incrustar un PDF en una nota: se guarda por CommandBus, el enlace se resuelve por nombre y se ve con TLSVisores")
    func incrustacion() async throws {
        let (e, sesion) = try await abrir(conProyecto: false)
        defer { sesion.close(); e.limpiar() }
        let nota = VaultPath("1 · Dirección/Metas.md")
        let url = nota.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let base = String(decoding: antes, as: UTF8.self)
        // Al escribir `![[2026-07-10 Movil`, el autocompletado ofrece el PDF (no solo notas) y lo inserta por su nombre.
        let enlaces = EnlacesDeNota(ruta: nota, sesion: sesion)
        let sugerencias = await enlaces.sugerencias("2026-07-10 Movil", disparador: .wiki)
        let sugerencia = try #require(sugerencias.first { $0.id == pdf.raw })
        // Ribera escribe enlaces Markdown (G3): `![[` + elegir deja `![nombre](ruta%20relativa.pdf)`, que también
        // es una incrustación (en una carpeta con wikilinks quedaría `![[nombre.pdf]]`).
        let insertado = "!" + enlaces.insercion(para: sugerencia, disparador: .wiki, textoVisible: nil)
        let alInsertar: [Incrustacion] = AnalizadorMarkdown.analizar(insertado).parrafos.compactMap {
            if case .incrustacion(let i) = $0.bloque.tipo { return i } else { return nil }
        }
        #expect(alInsertar.count == 1)
        if let i = alInsertar.first { #expect(IncrustacionesDeNota(ruta: nota, sesion: sesion).bloque(para: i) != nil) }
        let linea = "![[\(pdf.name)#page=1]]"
        let texto = base + (base.hasSuffix("\n") ? "" : "\n") + "\n" + linea + "\n"
        let r = try await sesion.escribir(.guardarNota(nota, base: base, texto: texto), aviso: "")
        #expect(r.hecho)
        // El resolvedor de la sesión conoce los adjuntos por su nombre, aunque estén en otra carpeta.
        #expect(sesion.resolverEnlace("[[\(pdf.name)]]", desde: nota) == pdf)
        // El editor ve la línea como incrustación y TLSVisores la pinta (PDF compacto en su página).
        let guardado = try String(contentsOf: url, encoding: .utf8)
        let incrustaciones: [Incrustacion] = AnalizadorMarkdown.analizar(guardado).parrafos.compactMap {
            if case .incrustacion(let i) = $0.bloque.tipo { return i } else { return nil }
        }
        let inc = try #require(incrustaciones.first)
        #expect(inc.pagina == 1)
        let proveedor = IncrustacionesDeNota(ruta: nota, sesion: sesion)
        let bloque = try #require(proveedor.bloque(para: inc))
        #expect(bloque.simbolo == TipoFichero.pdf.simbolo)
        #expect(bloque.alto == IncrustacionFichero.altoPorDefecto(.pdf))
        await sesion.deshacer(plan: r.planID)
        #expect(try Data(contentsOf: url) == antes)
    }
}
