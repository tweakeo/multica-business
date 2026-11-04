import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Bases en la interfaz con Ribera copiada a un temporal: modelo de la pantalla, edición en la celda por
/// `CommandBus` con Deshacer, Ganada bloqueada, vistas guardadas, crear con plantilla y ⌘K.
@Suite("Bases · pantalla, edición, vistas y ⌘K", .serialized)
@MainActor
struct BasesUITests {
    let pruebas = SesionEscrituraTests()

    func sesionLista() async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        #expect(sesion.isReady)
        #expect(sesion.puedeEscribir)
        return (e, sesion)
    }

    func modelo(_ id: String, _ sesion: VaultSession, nav: Navegacion = Navegacion(raiz: .todasLasBases)) async throws -> BaseModelo {
        let c = try #require(CatalogoBases.coleccion(id))
        let m = BaseModelo(coleccion: c, sesion: sesion, destino: .base(id), contexto: nil, vista: nil)
        m.nav = nav
        await m.cargar()
        return m
    }

    @Test("La pantalla de una base: vista de la nota índice, pestañas con contador y filtros que se recuerdan")
    func pantallaYRecuerdo() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let nav = Navegacion(raiz: .todasLasBases)
        let ops = try await modelo("oportunidades", sesion, nav: nav)
        #expect(ops.config.vista == .tablero)
        #expect(ops.filas.count == 14)
        #expect(ops.claveTablero == "estado")
        ops.anadirFiltro(FiltroBase("estado", .es, ["Propuesta"]))
        ops.busqueda = "nexo"
        let filtradas = ops.filas
        #expect(!filtradas.isEmpty && filtradas.allSatisfy { $0.texto("estado") == "Propuesta" })
        // Al volver a la base (otra pantalla, la misma pestaña de ventana) está igual.
        let otra = try await modelo("oportunidades", sesion, nav: nav)
        #expect(otra.config.filtros == [FiltroBase("estado", .es, ["Propuesta"])])
        #expect(otra.busqueda == "nexo")

        let contactos = try await modelo("contactos", sesion)
        #expect(contactos.config.vista == .tabla)
        let pestanas = try #require(contactos.datos?.pestanas)
        #expect(pestanas.map(\.titulo) == ["Activos", "Interesados", "Antiguos clientes", "Archivados"])
        contactos.elegirPestana("Interesados")
        #expect(contactos.filas.allSatisfy { $0.texto("estado") == "Interesado" })
        // Los números de las bases llegan a la barra lateral.
        await AlmacenBases.de(sesion).cargarTodas(forzar: true)
        #expect(sesion.barraLateral.datos[.base("contactos")]?.derecha == "14")
    }

    @Test("Editar una celda escribe solo esa línea por CommandBus; ⌘Z la deja como estaba")
    func edicionConDeshacer() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let ops = try await modelo("oportunidades", sesion)
        let um = UndoManager()
        um.groupsByEvent = false
        ops.undoManager = um
        let sergio = try #require(ops.datos?.filas.first { $0.ruta.stem == "sergio-nexo-trimestrales" })
        let url = sergio.ruta.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let siguiente = try #require(ops.coleccion.columna("siguiente_paso"))
        um.beginUndoGrouping()
        let error = await ops.guardar(sergio, siguiente, texto: "Llamar el lunes")
        um.endUndoGrouping()
        #expect(error == nil)
        let despues = try String(contentsOf: url, encoding: .utf8)
        let la = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n")
        let ld = despues.components(separatedBy: "\n")
        #expect(la.count == ld.count)
        #expect(zip(la, ld).filter { $0 != $1 }.map(\.1) == ["siguiente_paso: Llamar el lunes"])
        #expect(sesion.aviso?.texto.contains("Siguiente paso pasa a Llamar el lunes") == true)
        #expect(ops.fila(sergio.id)?.texto("siguiente_paso") == "Llamar el lunes")
        #expect(um.canUndo)
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)

        // Lo que no se edita, no se escribe.
        let ponderado = try #require(ops.coleccion.columna("_ponderado"))
        #expect(await ops.guardar(sergio, ponderado, texto: "10")?.hasPrefix("Se calcula") == true)
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("Tablero: Ganada sin cobro confirmado se bloquea con su motivo y la ficha no cambia")
    func ganadaBloqueada() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let ops = try await modelo("oportunidades", sesion)
        let jorge = try #require(ops.datos?.filas.first { $0.ruta.stem == "jorge-martin-trimestrales" })
        let antes = try Data(contentsOf: jorge.ruta.url(in: e.carpeta))
        await ops.mover(jorge, a: "Ganada")
        #expect(ops.bloqueo?.fila == jorge.id)
        #expect(ops.bloqueo?.etapa == "Aceptada")
        #expect(ops.bloqueo?.motivo.hasPrefix(ReglaGanada.base) == true)
        #expect(try Data(contentsOf: jorge.ruta.url(in: e.carpeta)) == antes)
        // A otra columna sí se mueve (y se puede deshacer).
        await ops.mover(jorge, a: "Propuesta")
        #expect(try String(contentsOf: jorge.ruta.url(in: e.carpeta), encoding: .utf8).contains("estado: Propuesta"))
        // ⌘→ desde Propuesta lleva a Aceptada.
        let jorge2 = try #require(ops.fila(jorge.id))
        await ops.moverAlLado(jorge2, 1, columnas: CatalogoBases.etapas)
        #expect(try String(contentsOf: jorge.ruta.url(in: e.carpeta), encoding: .utf8).contains("estado: Aceptada"))
    }

    @Test("Vistas guardadas: en .tls/vistas por CommandBus, cambios sin guardar, descartar y Deshacer (al Archivo, sin borrar)")
    func vistasGuardadas() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let ops = try await modelo("oportunidades", sesion)
        #expect(!ops.hayCambios)
        ops.cambiarVista(.tabla)
        ops.anadirFiltro(FiltroBase("estado", .es, ["Propuesta", "Aceptada"]))
        #expect(ops.hayCambios)
        let fichero = AlmacenVistas.rutaEnCarpeta("oportunidades").url(in: e.carpeta)
        // Se escribe en segundo plano (por CommandBus): cuando acaba, deja su aviso con «Deshacer».
        ops.guardarVistaComo("Por cerrar")
        await pruebas.esperar { sesion.aviso?.texto == "Guardé la vista «Por cerrar»" }
        #expect(sesion.aviso?.accion != nil)
        #expect(!ops.hayCambios)
        #expect(ops.vistas.map(\.nombre) == ["Por cerrar"])
        // En la carpeta de la empresa (pregunta 7 de §10), escrito por el escritor; nada en los datos de la app.
        #expect(FileManager.default.fileExists(atPath: fichero.path))
        #expect(!FileManager.default.fileExists(atPath: e.estado.appendingPathComponent("vistas/oportunidades.json").path))
        #expect(AlmacenVistas.decodificar(try Data(contentsOf: fichero)).first?.nombre == "Por cerrar")
        // Otra pantalla la lee igual.
        let otra = try await modelo("oportunidades", sesion)
        #expect(otra.vistas.first?.config.vista == .tabla)
        // Cambios sin guardar y descartar.
        ops.ordenar(por: "valor", ascendente: false)
        #expect(ops.hayCambios)
        ops.descartarCambios()
        #expect(!ops.hayCambios)
        // Deshacer quita la vista guardada: el fichero va al Archivo (nunca se borra).
        let r = sesion.revision
        let ultimo = try #require(await sesion.bus?.ultimoDeshacible())
        await sesion.deshacer(plan: ultimo.planID)
        await pruebas.esperar { !FileManager.default.fileExists(atPath: fichero.path) }
        #expect(!FileManager.default.fileExists(atPath: fichero.path))
        let archivado = e.carpeta.appendingPathComponent("Archivo/Ajustes de la app/vistas/oportunidades.json")
        #expect(FileManager.default.fileExists(atPath: archivado.path))
        await pruebas.esperar { sesion.revision > r }
        await ops.cargar()
        #expect(ops.vistas.isEmpty)
    }

    @Test("Con la carpeta en solo lectura, las vistas van a los datos de la app (nunca a la carpeta)")
    func vistasEnSoloLectura() async throws {
        let (e, entry) = try pruebas.entorno(clase: .copia, escritura: .bloqueada)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        #expect(!sesion.puedeEscribir)
        let ops = try await modelo("oportunidades", sesion)
        ops.cambiarVista(.tabla)
        ops.guardarVistaComo("Solo mía")
        #expect(AlmacenVistas(directorio: e.estado.appendingPathComponent("vistas")).leer("oportunidades").map(\.nombre) == ["Solo mía"])
        #expect(!FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent(".tls/vistas").path))
    }

    @Test("«Editar descripción» escribe solo el primer párrafo de la nota índice por CommandBus; ⌘Z la deja igual")
    func editarDescripcion() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let ops = try await modelo("oportunidades", sesion)
        let um = UndoManager()
        um.groupsByEvent = false
        ops.undoManager = um
        #expect(ops.motivoSinDescripcion == nil)
        let ruta = try #require(ops.datos?.indice?.ruta)
        let url = ruta.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let revision = sesion.revision
        um.beginUndoGrouping()
        let error = await ops.guardarDescripcion("Lo que puede acabar en venta, de la primera llamada al cobro.")
        um.endUndoGrouping()
        #expect(error == nil)
        let la = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n")
        let ld = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        #expect(la.count == ld.count)
        #expect(zip(la, ld).filter { $0 != $1 }.map(\.1) == ["Lo que puede acabar en venta, de la primera llamada al cobro."])
        #expect(sesion.aviso?.texto == "Guardé la descripción en la nota índice de Oportunidades.")
        // La base la lee de nuevo en cuanto el índice recoge el cambio (como `.task(id: sesion.revision)`).
        await pruebas.esperar { sesion.revision != revision }
        await ops.cargar()
        #expect(ops.datos?.frase == "Lo que puede acabar en venta, de la primera llamada al cobro.")
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
        // Una base sin nota índice lo dice.
        let tareas = try await modelo("tareas", sesion)
        #expect(tareas.motivoSinDescripcion?.contains("nota índice") == true)
    }

    @Test("Celdas de relación: se cambian con el selector salvo lo que no se toca; «Ir a» lleva a lo enlazado")
    func celdasDeRelacion() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let ops = try await modelo("oportunidades", sesion)
        let sergio = try #require(ops.datos?.filas.first { $0.ruta.stem == "sergio-nexo-trimestrales" })
        let empresa = try #require(ops.coleccion.columna("empresa"))
        #expect(ops.motivoSoloLectura(sergio, empresa) == nil)
        #expect(sergio.claveReal(empresa) == "empresa")
        let ir = MenuFilas.enlazadas(sergio, modelo: ops)
        #expect(ir.contains { $0.etiqueta == "Empresa" && $0.texto == "Arquitectura Nexo SLP" && $0.ruta.raw == "2 · Ventas/Empresas/arquitectura-nexo.md" })
        #expect(sergio.rutaPreviaAlPasar == sergio.ruta)
        // Una factura emitida no cambia de empresa desde la celda.
        let facturas = try await modelo("facturas", sesion)
        let f7 = try #require(facturas.datos?.filas.first { $0.texto("numero") == "F-2026-0007" })
        let empresaFactura = try #require(facturas.coleccion.columna("empresa"))
        #expect(facturas.motivoSoloLectura(f7, empresaFactura) == "Una factura emitida no se cambia: se rectifica con otra.")
        // Una fila de un CSV enseña su documento al pasar el puntero, nunca el CSV entero.
        let gastos = try await modelo("gastos", sesion)
        let gasto = try #require(gastos.datos?.filas.first { $0.documento != nil })
        #expect(gasto.rutaPreviaAlPasar == gasto.documento)
    }

    @Test("«Nueva …» con su plantilla: un solo plan, ya rellena con la pestaña, y Deshacer la retira")
    func crearConPlantilla() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let tareas = try await modelo("tareas", sesion)
        var p = PeticionNueva()
        p.valores["titulo"] = "Llamar a la gestoría"
        p.poner["estado"] = "Por hacer"
        let ruta = try #require(await CreadorFichas.crear(coleccion: tareas.coleccion, peticion: p, sesion: sesion, deshacer: nil))
        #expect(ruta.raw.hasPrefix("1 · Dirección/Tareas/t-0003-"))
        let texto = try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("estado: Por hacer"))
        #expect(texto.contains("Llamar a la gestoría"))
        #expect(sesion.aviso?.accion != nil)
        // Deshacer la creación la retira a Archivo/ (nunca se borra).
        let r = try await sesion.bus!.deshacer(autor: sesion.autor)
        #expect(r.hecho)
        #expect(!FileManager.default.fileExists(atPath: ruta.url(in: e.carpeta).path))
        #expect(FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("Archivo/\(ruta.raw)").path))

        // La pestaña y el filtro rellenan la hoja.
        let contactos = try await modelo("contactos", sesion)
        contactos.elegirPestana("Interesados")
        contactos.abrirNueva()
        #expect(contactos.nueva?.poner["estado"] == "Interesado")
        // Gastos no se crean desde aquí y lo dice.
        let gastos = try await modelo("gastos", sesion)
        #expect(gastos.motivoSinCrear?.contains("Incorporar gasto") == true)
    }

    @Test("⌘K: vacío enseña Recientes, Pide tu decisión y Bases fijadas; al escribir, por base, acciones y texto")
    func paleta() async throws {
        let (e, sesion) = try await sesionLista()
        defer { sesion.close(); e.limpiar() }
        let catalogo = await AlmacenBases.de(sesion).catalogoBusqueda()
        sesion.registrarVisita(.ficha(VaultPath("2 · Ventas/Contactos/jorge-martin.md")))
        let fijadas = BaseConocida.fijadasDeSerie
        let vacio = MotorPaleta.secciones("", catalogo: catalogo, texto: [], recientes: sesion.recientes, fijadas: fijadas,
                                          acotar: .todo, puedeCrear: true)
        #expect(vacio.map(\.titulo) == ["Recientes", "Pide tu decisión", "Bases fijadas"])
        #expect(vacio[0].items.first?.titulo == "Jorge Martín")
        #expect(vacio[1].items.contains { $0.titulo.contains("165") })
        #expect(vacio[2].items.count == 6)

        let hits = await sesion.buscar("nexo", limite: 12)
        let s = MotorPaleta.secciones("nexo", catalogo: catalogo, texto: hits, recientes: [], fijadas: fijadas,
                                      acotar: .todo, puedeCrear: true)
        let titulos = s.map(\.titulo)
        #expect(titulos.first == "Mejores resultados")
        #expect(titulos.contains("Acciones"))
        let acciones = s.first { $0.titulo == "Acciones" }?.items.map(\.titulo) ?? []
        #expect(acciones.contains { $0.hasPrefix("Nueva factura para ") })
        // Por número.
        let n = MotorPaleta.secciones("T-0001", catalogo: catalogo, texto: [], recientes: [], fijadas: [], acotar: .todo, puedeCrear: true)
        #expect(n.first?.items.first?.accion == .abrir(VaultPath("1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md"), base: "tareas"))
        // «facturas vencidas»: buscar dentro de Facturas.
        let dentro = MotorPaleta.secciones("facturas vencidas", catalogo: catalogo, texto: [], recientes: [], fijadas: [],
                                           acotar: .acciones, puedeCrear: true)
        #expect(dentro.first?.items.first?.accion == .base("facturas", busqueda: "vencidas"))
        // Acotar a Bases.
        let bases = MotorPaleta.secciones("fact", catalogo: catalogo, texto: [], recientes: [], fijadas: [], acotar: .bases, puedeCrear: true)
        #expect(bases.map(\.titulo) == ["Bases"])
        #expect(bases.first?.items.first?.titulo == "Facturas")
    }
}
