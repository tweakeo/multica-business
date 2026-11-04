import Foundation
import Testing
import TLSCore
import TLSImport
@testable import TLSUI

/// «Ordenar lo que tienes» desde las pantallas (F3 · rol ordenar): nada se escribe antes de «Aplicar» (F3-1), lo aplicado
/// es lo que enseñaba la vista previa, se comprueba por recuento y SHA-256 y «Deshacer» deja el árbol como estaba (F3-4).
/// Siempre en temporales propios y con un escritor propio o la sesión; nunca se lanza Claude (uno falso en memoria).
@Suite("Ordenar lo que tienes · pantallas", .serialized)
@MainActor
struct OrdenarModeloTests {
    @Test("Nada se escribe antes de «Aplicar»: inventario, decisiones, Claude y vista previa solo leen (F3-1)")
    func nadaAntesDeAplicar() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        let fuera = e.base.appendingPathComponent("Drive", isDirectory: true)
        try FileManager.default.createDirectory(at: fuera.appendingPathComponent("Contactos"), withIntermediateDirectories: true)
        try Data("# Carla Gil\n".utf8).write(to: fuera.appendingPathComponent("Contactos/Carla Gil.md"))
        let antes = try await e.fotoCompleta()
        let antesFuera = try await Inventory.make(of: fuera, completo: true)

        let m = e.modelo()
        await m.arrancar()
        #expect(m.inventario != nil, "\(m.error ?? "")")
        await m.anadirFuera(fuera)
        #expect(m.externas.map(\.alias) == ["Drive"])
        #expect(m.textoInventario.hasPrefix("\(m.inventario?.elementos.count ?? 0) ficheros"))
        // Lo privado no se lista nunca.
        #expect(!(m.inventario?.elementos.contains { $0.clave.contains("Expediente privado") } ?? true))
        let bloques = m.bloques
        #expect(!bloques.isEmpty)
        let viejo = try #require(bloques.first { $0.bloque.nombre.contains("Viejo") })
        m.dejarFuera(bloque: viejo.id)
        m.fijarAlcance(.carpetas, .loActivo(desde: LocalDate(year: 2024, month: 1, day: 1)!))
        m.ejecutorIA = ClaudeEnMemoria()
        await m.ayudaConLosDudosos(consentimiento: true)
        await m.prepararVista()
        let vista = try #require(m.vista, "\(m.error ?? "")")
        #expect(vista.hayCambios)
        #expect(vista.resumen.hasSuffix("No se borra nada"))
        #expect(m.motivoNoAplicar == nil)
        // Ni la carpeta de la empresa ni la de fuera han cambiado (tampoco `.tls/`).
        #expect(try await e.fotoCompleta().hashArbol == antes.hashArbol)
        #expect(try await Inventory.make(of: fuera, completo: true).hashArbol == antesFuera.hashArbol)
        // En el estado de la app solo está el borrador (nunca en la carpeta).
        #expect(ficherosBajo(e.estado).allSatisfy { $0.hasPrefix("ordenar") }, "\(ficherosBajo(e.estado))")
        #expect(!e.existe("ordenar") && !e.existe("borrador.json"))
    }

    @Test("Lo aplicado es lo que enseñaba la vista previa; se comprueba (recuento + SHA-256) y «Deshacer» deja el árbol igual")
    func aplicarYDeshacer() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        let antes = try await e.foto()
        let m = e.modelo()
        await m.arrancar()
        await m.prepararVista()
        let vista = try #require(m.vista, "\(m.error ?? "")")
        let previstos = vista.movimientos
        await m.aplicar()
        #expect(m.error == nil, "\(m.error ?? "")")
        let hecho = try #require(m.hecho)
        #expect(hecho.sinDiferencias)
        #expect(hecho.textoVerificacion == "\(hecho.verificados) de \(hecho.total) (recuento + SHA-256)")
        #expect(hecho.verificados == hecho.total)
        #expect(hecho.resumen == vista.resumen)
        #expect(m.planes.count == 2, "la importación y su anotación")
        #expect(m.hechoTexto == nil, "la comprobación se enseña en su pantalla")
        // Cada fila de la vista previa está donde decía: lo movido, en su destino (y ya no en su origen) y lo completado,
        // con su tipo.
        var movidos = 0
        for p in previstos {
            switch p.accion {
            case .mover, .moverYRenombrar, .archivar, .duplicado:
                guard let d = p.destino else { continue }
                movidos += 1
                #expect(FileManager.default.fileExists(atPath: d.url(in: e.raiz).path), "falta \(d.raw)")
                let origen = String(p.clave.dropFirst(FuenteImportacion.aliasDeLaEmpresa.count + 1))
                #expect(!e.existe(origen), "\(origen) sigue en su sitio")
            case .propiedades:
                let ruta = String(p.clave.dropFirst(FuenteImportacion.aliasDeLaEmpresa.count + 1))
                if p.adopta { #expect(e.texto(ruta)?.contains("tls_type:") == true, "\(ruta) sin su tipo") }
            default:
                break
            }
        }
        #expect(movidos == vista.mover + vista.archivar)
        #expect(e.existe(hecho.informe))
        // Nada se borra: lo de antes más lo creado.
        let despues = try await e.foto()
        #expect(despues.entradas.filter { $0.tipo == .fichero }.count >= antes.entradas.filter { $0.tipo == .fichero }.count - vista.archivar)
        // El mapa se guarda en el estado de la app (lo usa «Actualizar la copia»), nunca en la carpeta.
        #expect(MapaImportacion.guardados(en: e.estado).count == 1)
        #expect(hecho.mapa.map { $0.hasPrefix(e.estado.path) } == true)
        #expect(m.puedeDeshacer)

        await m.deshacer()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(m.hecho == nil && m.planes.isEmpty)
        #expect(m.hechoTexto == "Deshecho: la carpeta está como antes.")
        let tras = try await e.foto()
        #expect(tras.hashArbol == antes.hashArbol, "\(antes.diferencias(con: tras))")
        #expect(MapaImportacion.guardados(en: e.estado).isEmpty)
        #expect(!m.puedeDeshacer)
        // Se puede volver a preparar y aplicar.
        #expect(m.zona != nil)
    }

    @Test("«Cancelar» mientras se aplica es seguro: o no se escribe nada o se deshace entero")
    func cancelarAplicar() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        let antes = try await e.foto()
        let m = e.modelo()
        await m.arrancar()
        await m.prepararVista()
        #expect(m.vista != nil)
        let t = Task { await m.aplicar() }
        while m.trabajo != .aplicando { await Task.yield() }
        m.cancelarAplicar()
        await t.value
        #expect(m.hechoTexto?.hasPrefix("Cancelado") == true, "\(m.hechoTexto ?? "") \(m.error ?? "")")
        #expect(m.planes.isEmpty && m.hecho == nil)
        let tras = try await e.foto()
        #expect(tras.hashArbol == antes.hashArbol, "\(antes.diferencias(con: tras))")
    }

    @Test("«Seguir más tarde»: lo decidido se guarda fuera de la carpeta y se retoma igual (también lo privado, por su huella)")
    func borradorRetoma() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        let m = e.modelo()
        await m.arrancar()
        let bloques = m.bloques
        let notas = try #require(bloques.first { $0.bloque.nombre == "Notas" })
        let facturas = try #require(bloques.first { $0.bloque.nombre == "Facturas" })
        let viejo = try #require(bloques.first { $0.bloque.nombre == "Viejo" })
        m.cambiarColeccion(bloque: notas.id, a: "direccion.reuniones")
        m.dejarFuera(bloque: facturas.id)
        m.marcarPrivado(bloque: viejo.id)
        m.fijarAlcance(.carpetas, .loActivo(desde: LocalDate(year: 2025, month: 1, day: 1)!))
        let mapa = try #require(m.zona?.mapa().csv)
        #expect(m.privadosEnLaZona == 1)
        // Lo privado no sale en el borrador: ni su nombre ni su ruta.
        let borrador = try String(contentsOf: m.urlBorrador, encoding: .utf8)
        #expect(!borrador.contains("Viejo") && !borrador.contains("Acta"))
        #expect(!mapa.contains("Viejo/"))

        let otro = e.modelo()
        await otro.arrancar()
        #expect(otro.zona?.mapa().csv == mapa)
        #expect(otro.zona?.alcance(.carpetas) == .loActivo(desde: LocalDate(year: 2025, month: 1, day: 1)!))
        #expect(otro.privadosEnLaZona == 1)
        #expect(otro.bloques.first { $0.bloque.nombre == "Notas" }?.coleccion == "direccion.reuniones")
        // «Volver a verlos»: lo privado de esta zona vuelve a la lista.
        otro.volverAVerPrivados()
        #expect(otro.privadosEnLaZona == 0)
        #expect(otro.bloques.contains { $0.bloque.nombre == "Viejo" })
    }

    @Test("Claude solo con consentimiento, por los dudosos y nunca con lo privado")
    func claudeConConsentimiento() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        let m = e.modelo()
        await m.arrancar()
        let claude = ClaudeEnMemoria()
        m.ejecutorIA = claude
        let dudosos = m.dudosos
        #expect(dudosos > 0)
        await m.ayudaConLosDudosos(consentimiento: false)
        #expect(claude.peticiones.withLock { $0.isEmpty }, "sin consentimiento no se pregunta nada")
        // Un bloque marcado como privado no se envía nunca.
        let viejo = try #require(m.bloques.first { $0.bloque.nombre == "Viejo" })
        m.marcarPrivado(bloque: viejo.id)
        await m.ayudaConLosDudosos(consentimiento: true)
        let enviado = claude.todo
        #expect(!enviado.isEmpty)
        #expect(!enviado.contains("secreto") && !enviado.contains("Expediente privado"))
        #expect(!enviado.contains("Acta reunión"))
        #expect(m.textoIA?.hasPrefix("Claude ha propuesto sitio para") == true, "\(m.textoIA ?? "")")
        #expect(m.bloques.contains { $0.segunClaude })
    }

    @Test("Calidad: «Crear tarea» la escribe (y se deshace con el paso) e «Ignorar» se apunta fuera de la carpeta")
    func calidad() async throws {
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        // Un documento de Finanzas sin fecha y una nota con un enlace roto.
        try e.escribir("4 · Finanzas/Fiscal/2026/T1/Gastos/recibo sin fecha.pdf", datos: Data("%PDF-1.4 recibo".utf8))
        try e.escribir("1 · Dirección/Notas.md", "Ver [el plan](Plan%20que%20no%20existe.md).\n")
        let antes = try await e.foto()
        let m = e.modelo()
        await m.arrancar()
        await m.revisarCalidad()
        let c = try #require(m.calidad)
        #expect(!c.avisos.isEmpty)
        #expect(c.avisos.allSatisfy { jergaOrdenar($0.detalle + " " + $0.queHacer).isEmpty })
        let primero = c.avisos[0]
        await m.crearTarea(primero)
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(m.tareasCreadas.contains(primero.id))
        #expect(m.planes.count == 1 && m.aplicado)
        let segundo = try #require(c.avisos.dropFirst().first)
        m.ignorar(segundo)
        #expect(!(m.calidad?.avisos.contains { $0.id == segundo.id } ?? true))
        #expect(InformeCalidad.ignorados(estado: e.estado).contains(segundo.id))
        #expect(!e.existe("calidad-ignorados.json"))
        // «Deshacer» del paso quita también la tarea (al Archivo, sin borrar).
        await m.deshacer()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(try await e.foto().hashArbol == antes.hashArbol)
    }

    @Test("Copia de G3 (fixture): 3 pantallas; solo completa fichas, se comprueba y se deshace")
    func rutaG3() async throws {
        let e = try EmpresaOrdenar(copiaDe: EmpresaOrdenar.fixtureG3, exclusiones: ["Privado"])
        defer { e.limpiar() }
        let antes = try await e.foto()
        let m = e.modelo(.completar)
        #expect(m.pantallas == [.completarFichas, .banco, .calidad])
        await m.arrancar()
        #expect(m.externas.isEmpty)
        await m.prepararVista()
        let vista = try #require(m.vista, "\(m.error ?? "")")
        #expect(vista.mover == 0 && vista.archivar == 0 && vista.propiedades > 0)
        #expect(vista.resumen == "Mover 0 · Propiedades a \(vista.propiedades) · Archivar 0 · No se borra nada")
        await m.aplicar()
        let hecho = try #require(m.hecho, "\(m.error ?? "")")
        #expect(hecho.sinDiferencias)
        let r = m.resumenPuesta()
        #expect(r.pantallas == 3 && r.titulos == ["Completar las fichas", "Movimientos del banco", "Calidad"])
        #expect(r.completadas == vista.propiedades && r.movidos == 0 && r.planes == m.planes)
        #expect(r.texto == hecho.textoVerificacion)
        // Lo privado (dejado fuera de la copia) no se toca.
        #expect(try String(contentsOf: EmpresaOrdenar.fixtureG3.appendingPathComponent("Privado/Expediente personal.md"), encoding: .utf8)
                == e.texto("Privado/Expediente personal.md"))
        await m.deshacer()
        #expect(try await e.foto().hashArbol == antes.hashArbol)
    }

    @Test("Movimientos del banco heredados: se cargan en preparación (sin confirmar) y se deshacen con el paso")
    func heredados() async throws {
        // Sobre Ribera (sus registros tienen las columnas de la v2; los de la fixture, las de G3).
        let e = try EmpresaOrdenar(copiaDe: EmpresaOrdenar.ribera)
        defer { e.limpiar() }
        var csv = "fecha,concepto,tercero,total,tipo,numero_factura,cobrado\n"
        for i in 1...5 { csv += "2026-05-0\(i),Consultoría,Cliente \(i),242.00,ingreso,F26010\(i),no\n" }
        try e.escribir("4 · Finanzas/Registros/importar/2026 T2 movimientos.csv", csv)
        let antes = try await e.foto()
        let m = e.modelo(.completar)
        await m.prepararHeredados()
        let h = try #require(m.heredados)
        #expect(h.nuevas.count == 5)
        await m.cargarHeredados()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(m.heredadosCargados && m.planes.count == 1)
        #expect(m.heredados?.nuevas.isEmpty == true, "la segunda vez no hay nada nuevo: \(m.heredados?.resumen ?? "")")
        #expect(m.resumenPuesta().texto == "Sin nada que mover; lo demás, hecho")
        await m.deshacer()
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(try await e.foto().hashArbol == antes.hashArbol)
    }

    @Test("Ribera ya está ordenada: nada que aplicar, y se dice por qué")
    func ribera() async throws {
        let e = try EmpresaOrdenar(copiaDe: EmpresaOrdenar.ribera)
        defer { e.limpiar() }
        let m = e.modelo(.completar)
        await m.arrancar()
        await m.prepararVista()
        let vista = try #require(m.vista, "\(m.error ?? "")")
        #expect(!vista.hayCambios)
        #expect(m.motivoNoAplicar == "No hay nada que mover, completar ni archivar")
        #expect(m.resumenPuesta().texto == "Nada que ordenar: todo estaba en su sitio")
        await m.prepararHeredados()
        await m.revisarCalidad()
        #expect(m.calidad != nil)
    }

    @Test("Los textos que fabrica el paso 2 no usan jerga")
    func glosario() async throws {
        var textos: [String] = PantallaOrdenar.allCases.flatMap { [$0.titulo, $0.explicacion] }
        let trabajos: [ModeloOrdenar.Trabajo] = [.mirando, .preparando, .aplicando, .deshaciendo, .preguntandoAClaude, .revisando, .escribiendo]
        textos += trabajos.map(\.texto)
        textos += ColeccionV2.catalogo.map { ModeloOrdenar.nombreColeccion($0.clave) } + [ModeloOrdenar.nombreColeccion(nil)]
        textos += ["contact", "organization", "project", "task", "x"].map(ModeloOrdenar.nombreDeTipo)
        textos += [ErrorAccesoEmpresa.soloLectura("esta copia está en solo lectura"), .estadoEnICloud].compactMap(\.errorDescription)
        let e = try EmpresaOrdenar.desordenada()
        defer { e.limpiar() }
        let m = e.modelo()
        await m.arrancar()
        textos.append(m.textoInventario)
        textos += m.bloques.flatMap { [$0.bloque.nombre, $0.motivo, $0.bloque.destinoPrincipal] }
        await m.prepararVista()
        if let v = m.vista { textos += [v.resumen] + v.movimientos.map(\.motivo) + v.movimientos.map(\.conflicto) }
        for t in textos {
            #expect(jergaOrdenar(t).isEmpty, "«\(t)» → \(jergaOrdenar(t))")
            #expect(!t.contains(".tls/"))
        }
    }
}
