import AppKit
import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSEditor
@testable import TLSUI

/// Revisión adversarial de la interfaz de F1 (seguridad de datos y corrección), 23/10.
///
/// Cada prueba reproduce un fallo encontrado en la revisión y ya corregido (corrector final, 23/10): quedan como
/// pruebas de regresión, sin `withKnownIssue`. Todo corre sobre una copia temporal de Ribera
/// (`SesionEscrituraTests.entorno`), que se borra al acabar.
@Suite("Revisión F1 · interfaz (adversarial)", .serialized)
@MainActor
struct RevisionF1InterfazTests {
    let pruebas = SesionEscrituraTests()
    let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")
    let area = VaultPath("2 · Ventas/Área.md")
    let renta = VaultPath("2 · Ventas/Productos/renta.md")
    let hoy = LocalDate(year: 2026, month: 10, day: 23)!

    func abrir(_ preparar: (URL) throws -> Void = { _ in }) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        try preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        #expect(sesion.isReady)
        #expect(sesion.puedeEscribir)
        return (e, sesion)
    }

    /// El editor de una nota como lo monta la pantalla (lectura + `NSTextView` en una ventana sin enseñar).
    func editor(_ ruta: VaultPath, _ sesion: VaultSession) async throws -> (ModeloNotaEditor, NSWindow) {
        let m = ModeloNotaEditor(ruta: ruta, sesion: sesion)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = m.controlador.scroll
        m.recibir(try #require(await sesion.leer(ruta)))
        return (m, w)
    }

    func escribirAlFinal(_ m: ModeloNotaEditor, _ texto: String) {
        let fin = (m.controlador.texto as NSString).length
        m.controlador.vista.insertText(texto, replacementRange: NSRange(location: fin, length: 0))
    }

    // MARK: 1 · Cierre de la app al editar una celda de número (alta)

    @Test("Celda de número: escribir 100000000000000000000 (o 1e20) no cierra la app")
    func celdaNumeroEnorme() async {
        // Antes, `EdicionCelda.numeroLimpio` hacía `Int64(n)` con cualquier entero finito: con |n| ≥ 2⁶³ el proceso
        // moría. Columnas `.numero`: Meta (objetivos), Versión (servicios), Días y Sesiones (proyectos).
        await #expect(processExitsWith: .success) {
            let col = ColumnaBase("meta", "Meta", .numero)
            let hoy = LocalDate(year: 2026, month: 10, day: 23)!
            _ = try? EdicionCelda.valor("100000000000000000000", para: col, hoy: hoy)
            _ = try? EdicionCelda.valor("1e20", para: col, hoy: hoy)
            _ = try? EdicionCelda.valor("-1e20", para: ColumnaBase("total", "Total", .dinero), hoy: hoy)
        }
        // Y se explica en lugar de escribir una cifra que no cabe.
        let col = ColumnaBase("meta", "Meta", .numero)
        #expect(throws: EdicionError.demasiadoGrande("1e20")) { try EdicionCelda.valor("1e20", para: col, hoy: hoy) }
    }

    // MARK: 2 · Importes que se dividen entre 1.000 al editar la celda (alta)

    @Test("Celda de dinero: lo que enseña el editor («1.234») se vuelve a leer como 1234, no como 1,234")
    func celdaDineroConMillares() throws {
        let col = ColumnaBase("total", "Total", .dinero)
        // `EditorCelda.textoInicial` enseña el valor con `FormatoBase.cifra`: 1234.00 → «1.234».
        let mostrado = FormatoBase.cifra(try #require(FormatoBase.numero("1234.00")))
        #expect(mostrado == "1.234")
        // La persona cambia una cifra («1.235») y guarda: debería ser 1235,00 €; hoy se escribe 1.24.
        let valor = try EdicionCelda.valor("1.235", para: col, hoy: hoy)
        #expect(valor == .number("1235.00"))
        let numero = try EdicionCelda.valor("15.000", para: ColumnaBase("sesiones", "Sesiones", .numero), hoy: hoy)
        #expect(numero == .number("15000"))
        // Lo que no es un grupo de millares sigue siendo decimal; y el editor enseña la cifra sin puntos.
        #expect(try EdicionCelda.valor("1.5", para: col, hoy: hoy) == .number("1.50"))
        #expect(try EdicionCelda.valor("150.00", para: col, hoy: hoy) == .number("150.00"))
        #expect(try EdicionCelda.valor("1.234,56", para: col, hoy: hoy) == .number("1234.56"))
        #expect(FormatoBase.numeroEscrito("0.125") == 0.125)
        #expect(FormatoBase.cifraParaEditar(1234) == "1234")
        #expect(FormatoBase.cifraParaEditar(1234.5) == "1234,50")
        #expect(try EdicionCelda.valor(FormatoBase.cifraParaEditar(1234.5), para: col, hoy: hoy) == .number("1234.50"))
    }

    // MARK: 3 · «Sí» y «No» escritos en una celda de texto de un CSV se guardan como true/false (baja)

    @Test("CSV: escribir «No» en una celda de texto guarda «No», no «false»")
    func csvTextoSiNo() throws {
        let gastos = try #require(CatalogoBases.coleccion("gastos"))
        let categoria = try #require(gastos.columna("categoria"))
        let fila = FilaBase(id: "REC-1", origen: .filaCSV(VaultPath("4 · Finanzas/Registros/recibidas.csv"), columnaClave: "id",
                                                          valorClave: "REC-1"),
                            titulo: "REC-1", tipo: .csv, area: .finanzas, valores: ["categoria": .text("Alquiler")],
                            modificada: nil, privado: false, claves: ["id", "categoria"])
        let valor = try EdicionCelda.valor("No", para: categoria, hoy: hoy)
        let comando = try EdicionCelda.comando(fila, categoria, valor: valor, coleccion: gastos)
        guard case .guardarFila(_, let datos, _) = comando else { Issue.record("No es guardarFila"); return }
        #expect(datos["categoria"] == "No")
        // Un sí/no de verdad sí se escribe como true/false.
        let siNo = ColumnaBase("deducible", "Deducible", .siNo)
        let filaSiNo = FilaBase(id: "REC-1", origen: fila.origen, titulo: "REC-1", tipo: .csv, area: .finanzas,
                                valores: ["deducible": .bool(true)], modificada: nil, privado: false,
                                claves: ["id", "deducible"])
        if case .guardarFila(_, let d, _) = try EdicionCelda.comando(filaSiNo, siNo, valor: .bool(false), coleccion: gastos) {
            #expect(d["deducible"] == "false")
        } else {
            Issue.record("No es guardarFila")
        }
    }

    // MARK: 4 · «Editar descripción» se lleva por delante una lista o un bloque de código (media)

    @Test("Editar la descripción de una base no borra la lista ni la consulta que van tras el título")
    func descripcionNoBorraBloques() {
        let lista = "---\ntls_type: index\ncoleccion: contact\n---\n# Contactos\n\n- [[jorge-martin|Jorge]]\n- [[lucia-ferrer|Lucía]]\n\n## Notas\n"
        let nuevo = NotaIndiceBase.cambiandoFrase(lista, por: "Cada persona es una ficha.") ?? lista
        #expect(nuevo.contains("- [[jorge-martin|Jorge]]"))
        #expect(nuevo.contains("- [[lucia-ferrer|Lucía]]"))
        // La frase va justo después del título, antes de la lista.
        #expect(nuevo.contains("# Contactos\n\nCada persona es una ficha.\n\n- [[jorge-martin|Jorge]]"))
        let consulta = "# Oportunidades\n\n```dataview\nTABLE estado\nFROM \"2 · Ventas\"\n```\n"
        let otro = NotaIndiceBase.cambiandoFrase(consulta, por: "Las oportunidades abiertas.") ?? consulta
        #expect(otro.contains("TABLE estado"))
        #expect(otro.contains("```dataview"))
        // La frase que lee la base ya no es la lista (lo que enseñaba la cabecera como descripción).
        #expect(NotaIndiceBase.frase(cuerpo: "# Contactos\n\n- [[jorge-martin|Jorge]]\n") == nil)
        #expect(NotaIndiceBase.frase(cuerpo: "# Contactos\n\n%% comentario %%\n") == nil)
        // Con un párrafo de verdad, todo sigue como antes.
        #expect(NotaIndiceBase.frase(cuerpo: "# Contactos\n\nCada persona es una ficha.\n\n- [[x]]\n") == "Cada persona es una ficha.")
        let conFrase = "# Contactos\n\nVieja frase.\n\n- [[jorge-martin|Jorge]]\n"
        #expect(NotaIndiceBase.cambiandoFrase(conFrase, por: "Nueva.") == "# Contactos\n\nNueva.\n\n- [[jorge-martin|Jorge]]\n")
    }

    // MARK: 5 · Editar una sección en la ficha pisa lo que se añadió entretanto (alta)

    @Test("Notas de la ficha: guardar lo editado no borra la línea que otra ventana añadió mientras se escribía")
    func seccionNoPisaLoDeFuera() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let m = FichaModelo(ruta: jorge, sesion: sesion)
        await m.cargar()
        // «Editar» en «Notas»: el borrador parte de lo que se ve ahora y se toma la huella (`BloqueSeccion`).
        let contenido = try #require(MarkdownSections.content(of: "Notas", in: m.cuerpo ?? "", level: 2))
        let huella = try #require(m.huellaSeccion("Notas"))
        let borrador = contenido + "- Le interesa el plan trimestral"
        // Mientras escribe, en otra ventana (o en Obsidian) se añade una nota rápida a la misma sección.
        let r0 = sesion.revision
        try await sesion.escribir(.anadirASeccion(jorge, seccion: "Notas", texto: "- 2026-10-23 · Llamó para pedir presupuesto"))
        await pruebas.esperar { sesion.revision > r0 }
        await m.cargar()  // la ficha relee sola con cada revisión
        #expect(m.cuerpo?.contains("Llamó para pedir presupuesto") == true)
        // «Guardar» con la huella de cuando se pulsó «Editar»: el cambio de fuera se detecta y no se pisa.
        let r1 = sesion.revision
        let resultado = await m.guardarSeccion("Notas", texto: borrador, huella: huella)
        #expect(resultado == .cambiadaFuera)
        let final = try String(contentsOf: jorge.url(in: e.carpeta), encoding: .utf8)
        #expect(final.contains("Llamó para pedir presupuesto"))
        #expect(!final.contains("Le interesa el plan trimestral"))
        // Tras ver las diferencias, «Quedarme con lo mío» (o combinar) guarda con la huella de ahora.
        let combinado = try #require(MarkdownSections.content(of: "Notas", in: m.cuerpo ?? "", level: 2))
            + "- Le interesa el plan trimestral"
        #expect(await m.guardarSeccion("Notas", texto: combinado, huella: m.huellaSeccion("Notas")) == .guardada)
        await pruebas.esperar { sesion.revision > r1 }
        let despues = try String(contentsOf: jorge.url(in: e.carpeta), encoding: .utf8)
        #expect(despues.contains("Llamó para pedir presupuesto"))
        #expect(despues.contains("Le interesa el plan trimestral"))
    }

    // MARK: 5b · «Hacer vista por defecto» escribe dos claves y deja la agrupación vieja (baja)

    @Test("«Hacer vista por defecto» con la tabla sin agrupar no deja la agrupación de antes")
    func vistaPorDefectoSinAgrupar() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let c = try #require(CatalogoBases.coleccion("contenidos"))  // su nota índice: vista tablero, agrupar_por estado
        let nav = Navegacion(raiz: .base("contenidos"))
        let m = BaseModelo(coleccion: c, sesion: sesion, destino: .base("contenidos"), contexto: nil, vista: nil)
        m.nav = nav
        await m.cargar()
        #expect(m.datos?.indice?.agruparPor == "estado")
        m.config.vista = .tabla
        m.config.agrupar = nil
        let r0 = sesion.revision
        await m.hacerVistaPorDefecto()
        await pruebas.esperar { sesion.revision > r0 }
        let navOtra = Navegacion(raiz: .base("contenidos"))
        let otra = BaseModelo(coleccion: c, sesion: sesion, destino: .base("contenidos"), contexto: nil, vista: nil)
        otra.nav = navOtra
        await otra.cargar()
        #expect(otra.config.vista == .tabla)
        #expect(otra.config.agrupar == nil)
    }

    // MARK: 6 · Texto sin guardar al pasar a solo lectura (media)

    @Test("Pasar la copia a solo lectura con texto aún sin guardar no lo pierde")
    func soloLecturaConTextoPendiente() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        m.esperaGuardado = .seconds(30)  // dentro de los 800 ms de espera, sin perder el foco
        escribirAlFinal(m, "\n- Revisar el contrato con Nexo")
        #expect(m.estado == .sinGuardar)
        // Pie de la barra lateral: «Ver sin cambiar nada».
        await sesion.pasarASoloLectura(using: e.model)
        // La pantalla se cierra (onDisappear → guardarYa).
        m.guardarYa()
        await m.guardar()
        let texto = try String(contentsOf: area.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("Revisar el contrato con Nexo"))
        #expect(!m.hayCambiosSinGuardar)
        #expect(!GuardadosPendientes.compartido.hayPendientes(de: sesion))
    }

    @Test("Salir de la app (⌘Q) guarda antes lo que el editor tiene pendiente")
    func salirGuardaLoPendiente() {
        // El guardado espera 800 ms tras la última tecla; al salir no hay `applicationShouldTerminate` que lo
        // adelante, y `willResignActive` no llega al cerrar la app con ⌘Q.
        let delegado = TLSAppDelegate()
        #expect(delegado.responds(to: #selector(NSApplicationDelegate.applicationShouldTerminate(_:))))
        // Sin nada pendiente, sale en el acto.
        if !GuardadosPendientes.compartido.hayPendientes() {
            #expect(delegado.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        }
    }

    @Test("Salir con texto pendiente: lo guarda antes de responder")
    func salirConTextoPendiente() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        m.esperaGuardado = .seconds(30)
        escribirAlFinal(m, "\n- Llamar a la gestoría")
        #expect(GuardadosPendientes.compartido.hayPendientes(de: sesion))
        await GuardadosPendientes.compartido.guardarTodo()
        let texto = try String(contentsOf: area.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("Llamar a la gestoría"))
        #expect(!GuardadosPendientes.compartido.hayPendientes(de: sesion))
    }

    // MARK: 7 · Lo privado deja de serlo al retirarlo al Archivo (alta)

    @Test("Retirar una nota privada no la saca en ⌘O ni en la búsqueda")
    func retirarPrivadaSiguePrivada() async throws {
        let privada = VaultPath("4 · Finanzas/Trámites/Expediente privado/documento-privado.md")
        let (e, sesion) = try await abrir { carpeta in
            let config = carpeta.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: config, encoding: .utf8)
                .replacingOccurrences(of: "privado: []", with: "privado: [\"4 · Finanzas/Trámites\"]")
            try Data(t.utf8).write(to: config)
            let url = privada.url(in: carpeta)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# Parte de baja\n\nDiagnóstico zxqconfidencialzxq.\n".utf8).write(to: url)
        }
        defer { sesion.close(); e.limpiar() }
        #expect(sesion.esPrivado(privada))
        #expect(await sesion.abrirRapido("documento-privado").isEmpty)
        #expect(await sesion.buscar("zxqconfidencialzxq").isEmpty)

        let r0 = sesion.revision
        let r = try await sesion.escribir(.retirar(privada))
        await pruebas.esperar { sesion.revision > r0 }
        let archivada = try #require(r.movidas.first?.a)
        #expect(archivada.raw.hasSuffix("Trámites/Expediente privado/documento-privado.md"))
        let rapido = await sesion.abrirRapido("documento-privado")
        #expect(sesion.esPrivado(archivada))
        #expect(rapido.isEmpty)
        // También lo que dejan los conflictos y los duplicados, y sin distinguir mayúsculas.
        let layout = try #require(sesion.estructura)
        #expect(layout.isPrivate(VaultPath("Archivo/Conflictos/4 · Finanzas/Trámites/x (tu versión).md")))
        #expect(layout.isPrivate(VaultPath("archivo/Duplicados/4 · Finanzas/Trámites/x 2.md")))
        #expect(!layout.isPrivate(VaultPath("Archivo/2 · Ventas/Contactos/jorge-martin.md")))
        // El texto de Archivo/ no se indexa (solo el nombre): la búsqueda de texto no lo enseña. Que siga así.
        #expect(await sesion.buscar("zxqconfidencialzxq").isEmpty)
    }

    // MARK: 8 · Renombrar: las otras pestañas y Deshacer se quedan con la ruta vieja (media)

    @Test("Renombrar y deshacer: todas las pestañas de la empresa siguen llevando a la ficha")
    func renombrarOtrasPestanasYDeshacer() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let carpeta = VaultPath("2 · Ventas/Productos")
        let activa = Navegacion(raiz: .carpeta(carpeta))
        activa.entrar(.ficha(renta))
        let otra = Navegacion(raiz: .ficha(renta))  // la misma ficha abierta en otra pestaña o ventana
        sesion.navegacionActiva = otra                // la otra pestaña estuvo delante antes
        sesion.navegacionActiva = activa
        sesion.registrarVisita(.ficha(renta))
        let modelo = CarpetaModelo(carpeta: carpeta, sesion: sesion)
        await modelo.cargar()
        let previa = try await modelo.prepararRenombrar(renta, a: "renta-anual")
        guard case .hecho(let r) = await modelo.aplicar(previa) else { Issue.record("No se renombró"); return }
        let nueva = VaultPath("2 · Ventas/Productos/renta-anual.md")
        #expect(activa.actual == .ficha(nueva))
        #expect(sesion.recientes.first == nueva)
        #expect(otra.actual == .ficha(nueva))
        await sesion.deshacer(plan: r.planID)
        await pruebas.esperar { FileManager.default.fileExists(atPath: renta.url(in: e.carpeta).path) }
        #expect(FileManager.default.fileExists(atPath: renta.url(in: e.carpeta).path))
        #expect(activa.actual == .ficha(renta))
        #expect(otra.actual == .ficha(renta))
        #expect(!sesion.recientes.contains(nueva))
        #expect(sesion.recientes.first == renta)
    }

    // MARK: 9 · Arrastrar filas de la Carpeta entre empresas (media)

    @Test("Lo arrastrado desde la Carpeta dice de qué empresa viene")
    func arrastreConEmpresa() throws {
        // `SoltarEnCarpeta` interpreta las rutas relativas en la empresa donde se suelta: arrastrar
        // «2 · Ventas/Contactos/jorge-martin.md» del ejemplo a la copia propone mover el Jorge de la copia.
        let ejemplo = UUID()
        let copia = UUID()
        let arrastre = ArrastreCarpeta(empresa: ejemplo, rutas: ["2 · Ventas/Contactos/jorge-martin.md"])
        let json = String(decoding: try JSONEncoder().encode(arrastre), as: UTF8.self)
        #expect(json.contains("empresa"))
        let leido = try JSONDecoder().decode(ArrastreCarpeta.self, from: Data(json.utf8))
        #expect(ArrastreCarpeta.rutas([leido], en: ejemplo) == [VaultPath("2 · Ventas/Contactos/jorge-martin.md")])
        #expect(ArrastreCarpeta.rutas([leido], en: copia).isEmpty)
        // Tablero, calendario y semana de una base (y el tablero del proyecto): el id lleva su empresa.
        let texto = ArrastreFila.texto("2 · Ventas/Contactos/jorge-martin.md", empresa: ejemplo)
        #expect(ArrastreFila.id(texto, empresa: ejemplo) == "2 · Ventas/Contactos/jorge-martin.md")
        #expect(ArrastreFila.id(texto, empresa: copia) == nil)
        #expect(ArrastreFila.id("2 · Ventas/Contactos/jorge-martin.md", empresa: ejemplo) == nil)
    }

    // MARK: 10 · Fugas: cada empresa cerrada se queda en memoria (media)

    /// Abre una sesión, deja que `usar` la toque, la cierra y suelta todo; devuelve referencias débiles.
    func cicloDeSesion(_ usar: (VaultSession) async -> AnyObject?) async throws -> (sesion: VaultSession?, objeto: AnyObject?) {
        weak var s: VaultSession?
        weak var o: AnyObject?
        do {
            let (e, sesion) = try await abrir()
            defer { e.limpiar() }
            o = await usar(sesion)
            s = sesion
            sesion.close()
        }
        for _ in 0..<20 { try await Task.sleep(for: .milliseconds(50)) }
        return (s, o)
    }

    @Test("Cerrar una empresa suelta su sesión (control: sin bases ni fichas abiertas)")
    func sesionSeSueltaSinAlmacenes() async throws {
        #expect(try await cicloDeSesion { _ in nil }.sesion == nil)
    }

    @Test("Cerrar una empresa con las bases abiertas suelta la sesión y sus datos")
    func almacenBasesNoRetieneLaSesion() async throws {
        let r = try await cicloDeSesion { sesion in
            let a = AlmacenBases.de(sesion)
            await a.cargarTodas(forzar: true)
            return a
        }
        #expect(r.sesion == nil)
        #expect(r.objeto == nil)
    }

    @Test("Cerrar una empresa con una ficha abierta suelta la foto de la carpeta (con lo privado)")
    func almacenRelacionesSeSuelta() async throws {
        let r = try await cicloDeSesion { sesion in
            let a = AlmacenRelaciones.de(sesion)
            await a.actualizar()
            return a
        }
        #expect(r.sesion == nil)
        #expect(r.objeto == nil)
    }

    // MARK: 11 · Una lectura vieja que llega tarde deshace lo que se ve en el editor (baja)

    @Test("Una lectura anterior que llega después no vuelve atrás el texto del editor")
    func lecturaViejaNoVuelveAtras() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let vieja = try #require(await sesion.leer(area))
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        m.esperaGuardado = .zero
        escribirAlFinal(m, "\n- Línea guardada")
        await m.guardar()
        #expect(m.estado == .guardado)
        let nueva = try #require(await sesion.leer(area))
        m.recibir(nueva)
        // Dos lecturas seguidas pueden llegar al revés (cada una en su `Task.detached`). Llega la de antes de
        // guardar: se reconoce por su número (orden de empezar a leer) y no vuelve atrás el texto.
        m.recibir(vieja)
        #expect(m.controlador.texto.hasSuffix("- Línea guardada"))
        // Tampoco una lectura que empezó antes de guardar y llega después, aunque sea la primera tras guardar.
        let (m2, w2) = try await editor(area, sesion)
        defer { w2.close() }
        m2.esperaGuardado = .zero
        let antes = try #require(await sesion.leer(area))
        escribirAlFinal(m2, "\n- Otra línea")
        await m2.guardar()
        m2.recibir(antes)
        #expect(m2.controlador.texto.hasSuffix("- Otra línea"))
    }
}
