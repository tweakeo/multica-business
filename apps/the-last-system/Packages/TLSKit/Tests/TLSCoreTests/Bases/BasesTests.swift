import Foundation
import Testing
@testable import TLSCore

@Suite("Bases · catálogo, lectura y vistas (Ribera)", .serialized)
struct BasesTests {
    // MARK: Catálogo

    @Test("Las 24 bases de §4.2, con los id del contrato, agrupadas en Comunes y 1–6")
    func catalogo() {
        let ids = CatalogoBases.deSerie.map(\.id)
        #expect(ids.count == 24)
        #expect(Set(ids).count == 24)
        #expect(Set(ids) == ["contactos", "empresas", "oportunidades", "servicios", "propuestas", "reuniones", "proyectos",
                             "planes-de-entrega", "incidencias", "tareas", "facturas", "cobros", "gastos", "movimientos",
                             "contenidos", "conversaciones", "sistemas", "activos", "roles", "decisiones", "objetivos",
                             "rutinas", "colaboraciones", "borradores"])
        let grupos = CatalogoBases.grupos.map(\.grupo)
        #expect(grupos == [.comunes] + AreaCode.allCases.map(GrupoBase.area))
        let registro = PlantillaRegistro.deSerie
        for c in CatalogoBases.deSerie {
            #expect(!c.columnas.isEmpty, "\(c.id) sin columnas")
            #expect(!c.columnasDeSerie.isEmpty, "\(c.id) sin columnas de serie")
            #expect(c.vistas.contains(c.vista), "\(c.id): su vista no está entre las suyas")
            if let p = c.plantilla {
                #expect(registro[p] != nil, "\(c.id): la plantilla \(p) no existe")
            } else {
                #expect(c.motivoSinCrear != nil, "\(c.id): no se crea y no dice por qué")
            }
            for col in c.columnas where col.tipo == .calculada { #expect(col.calculo != nil && col.explicacion != nil) }
        }
    }

    // MARK: Lectura

    @Test("Cuenta las fichas de Ribera por base, con sus CSV, y nunca enseña plantillas ni lo privado")
    func lecturaRibera() async throws {
        let e = try EntornoBases { root in
            // Una plantilla instalada (lleva tls_type, pero no es una ficha) y un contacto privado.
            let plantilla = VaultPath("2 · Ventas/Sistemas/Plantillas/Contacto.md").url(in: root)
            try FileManager.default.createDirectory(at: plantilla.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("---\ntls_type: contact\nnombre: \"{{titulo}}\"\n---\n# {{titulo}}\n".utf8).write(to: plantilla)
            let privada = VaultPath("4 · Finanzas/Trámites/Expediente privado/documento.md").url(in: root)
            try FileManager.default.createDirectory(at: privada.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("---\ntls_type: contact\nnombre: Doctora Privada\nestado: Activo\n---\n# Doctora Privada\n".utf8).write(to: privada)
        }
        defer { e.limpiar() }
        let s = try await e.servicio(privado: [VaultPath("4 · Finanzas/Trámites")])
        defer { s.close() }
        let lector = e.lector(s)
        #expect(lector.hoy == LocalDate(year: 2026, month: 10, day: 19))
        let todas = lector.leerTodas()
        func n(_ id: String) -> Int { todas[id]?.filas.count ?? -1 }
        #expect(n("contactos") == 14)
        #expect(n("empresas") == 10)
        #expect(n("oportunidades") == 14)
        #expect(n("servicios") == 2)
        #expect(n("propuestas") == 10)
        #expect(n("facturas") == 7)
        #expect(n("contenidos") == 7)
        #expect(n("conversaciones") == 4)
        #expect(n("roles") == 14)            // 6 de las personas y, desde F4, las 8 fichas de los asistentes
        #expect(n("decisiones") == 2)
        #expect(n("objetivos") == 6)
        #expect(n("tareas") == 2)
        #expect(n("planes-de-entrega") == 2)
        #expect(n("gastos") == 11)
        #expect(n("movimientos") == 30)
        #expect(n("cobros") == 6)
        #expect(n("proyectos") == 0)
        #expect(todas["objetivos"]?.apagada == true)
        #expect(todas["contactos"]?.apagada == false)
        // Nada de plantillas ni privado.
        let contactos = try #require(todas["contactos"])
        #expect(!contactos.filas.contains { $0.ruta.raw.contains("Plantillas") })
        #expect(!contactos.filas.contains { $0.titulo == "Doctora Privada" })
        #expect(!todas.values.flatMap(\.filas).contains { $0.privado })
        // Las filas de CSV saben de qué fichero y fila salen.
        let gasto = try #require(todas["gastos"]?.filas.first { $0.id.hasSuffix("#REC-20260701-001") })
        #expect(gasto.origen == .filaCSV(VaultPath("4 · Finanzas/Registros/recibidas.csv"), columnaClave: "id", valorClave: "REC-20260701-001"))
        #expect(gasto.documento?.raw == "4 · Finanzas/Fiscal/2026/T3/Gastos/inmobiliaria-centro/2026-07-01 Inmobiliaria Centro ALQ-2026-07 663,00€.pdf")
    }

    @Test("La nota índice manda: vista, pestañas y frase; las cifras y lo calculado salen de las fichas")
    func notaIndiceYCalculos() async throws {
        let e = try EntornoBases()
        defer { e.limpiar() }
        let s = try await e.servicio()
        defer { s.close() }
        let lector = e.lector(s)
        let ops = lector.leer(try #require(CatalogoBases.coleccion("oportunidades")))
        #expect(ops.indice?.ruta.raw == "2 · Ventas/Oportunidades/Oportunidades.md")
        #expect(ops.vistaPorDefecto == .tablero)
        #expect(ops.frase.hasPrefix("Cada oportunidad es una ficha."))
        #expect(ops.cifras.map(\.etiqueta) == ["Valor abierto", "Ponderado", "Ganadas sobre cerradas (90 días)"])
        let sergio = try #require(ops.filas.first { $0.ruta.stem == "sergio-nexo-trimestrales" })
        #expect(sergio.calculados["_ponderado"]?.numero == 75)
        #expect(sergio.enlaces["empresa"]?.first?.texto == "Arquitectura Nexo SLP")
        #expect(sergio.enlaces["empresa"]?.first?.ruta?.raw == "2 · Ventas/Empresas/arquitectura-nexo.md")
        let col = try #require(ops.coleccion.columna("servicio"))
        #expect(sergio.textoCelda(col, hoy: ops.hoy) == "Trimestrales")
        // Ganada: Jorge tiene su factura emitida pero sin cobro confirmado; Andrés, cobrada.
        let jorge = try #require(ops.filas.first { $0.ruta.stem == "jorge-martin-trimestrales" })
        #expect(ReglaGanada.motivo(jorge)?.hasPrefix(ReglaGanada.base) == true)
        let andres = try #require(ops.filas.first { $0.ruta.stem == "andres-vidal-renta" })
        #expect(ReglaGanada.motivo(andres) == nil)
        let estado = try #require(ops.coleccion.columna("estado"))
        #expect(EdicionCelda.opciones(estado, fila: jorge).first { $0.valor == "Ganada" }?.motivo != nil)

        let contactos = lector.leer(try #require(CatalogoBases.coleccion("contactos")))
        #expect(contactos.vistaPorDefecto == .tabla)
        #expect(contactos.pestanas.map(\.titulo) == ["Activos", "Interesados", "Antiguos clientes", "Archivados"])
        #expect(contactos.pestanas.last?.archivada == true)
        let facturas = lector.leer(try #require(CatalogoBases.coleccion("facturas")))
        let f1 = try #require(facturas.filas.first { $0.texto("numero") == "F-2026-0001" })
        #expect(f1.calculados["_cobrado"]?.numero == 108.9)
        let f7 = try #require(facturas.filas.first { $0.texto("numero") == "F-2026-0007" })
        #expect(f7.calculados["_cobrado"]?.texto == "Sin cobrar")
        #expect(facturas.cifras.first?.valor == "181,50 €")
        let empresas = lector.leer(try #require(CatalogoBases.coleccion("empresas")))
        let talleres = try #require(empresas.filas.first { $0.ruta.stem == "talleres-martin-e-hijos" })
        #expect(talleres.calculados["_pendiente"]?.numero == 181.5)
        let gastos = lector.leer(try #require(CatalogoBases.coleccion("gastos")))
        #expect(gastos.pestanas.map(\.titulo).contains("Alquiler"))
        #expect(gastos.pie.contains("recibidas.csv"))
    }

    // MARK: Vista

    @Test("Pestañas, búsqueda con resaltado, sugerencias de filtro, filtros, orden y grupos con subtotal")
    func motorVista() async throws {
        let e = try EntornoBases()
        defer { e.limpiar() }
        let s = try await e.servicio()
        defer { s.close() }
        let lector = e.lector(s)
        let contactos = lector.leer(try #require(CatalogoBases.coleccion("contactos")))
        let interesados = try #require(contactos.pestanas.first { $0.titulo == "Interesados" })
        let n = MotorVista.cuenta(interesados, datos: contactos)
        #expect(n > 0 && n <= 14)
        var config = ConfigVista.deSerie(contactos)
        config.pestana = interesados.id
        #expect(MotorVista.filas(contactos, config: config).count == n)
        config.pestana = nil
        let nexo = MotorVista.filas(contactos, config: config, busqueda: "nexo")
        #expect(nexo.map(\.titulo) == ["Sergio Nexo"])
        // Sin tildes: «martin» resalta «Martín».
        let texto = "Jorge Martín"
        let r = try #require(MotorVista.resaltar(texto, busqueda: "martin"))
        #expect(String(texto[r]) == "Martín")

        let facturas = lector.leer(try #require(CatalogoBases.coleccion("facturas")))
        let sug = MotorVista.sugerencias("vencidas", datos: facturas)
        #expect(sug.first?.etiqueta == "Filtro: Vence antes de hoy")
        var cf = ConfigVista.deSerie(facturas)
        cf.filtros = [FiltroBase("estado", .es, ["Emitida"])]
        #expect(MotorVista.filas(facturas, config: cf).map { $0.texto("numero") } == ["F-2026-0007"])
        #expect(FiltroBase("estado", .es, ["Emitida"]).etiqueta(en: facturas.coleccion) == "Estado es Emitida")
        cf.filtros = []
        cf.orden = [OrdenBase("total", ascendente: false)]
        let porTotal = MotorVista.filas(facturas, config: cf)
        let total = try #require(facturas.coleccion.columna("total"))
        #expect(porTotal.first?.numero(total) == 181.5)
        #expect(porTotal.first?.textoCelda(total, hoy: facturas.hoy) == "181,50 €")

        let ops = lector.leer(try #require(CatalogoBases.coleccion("oportunidades")))
        let grupos = MotorVista.agrupar(ops.filas, por: "estado", coleccion: ops.coleccion, hoy: ops.hoy, incluirVacios: true)
        #expect(grupos.map(\.titulo) == CatalogoBases.etapas)
        let propuesta = try #require(grupos.first { $0.id == "Propuesta" })
        #expect(propuesta.resumen.contains(" · ") && propuesta.resumen.hasSuffix("€"))
        // Lo urgente primero: lo cerrado (Ganada, Perdida) siempre al final.
        let urgentes = MotorVista.filas(ops, config: ConfigVista.deSerie(ops))
        let primeraCerrada = urgentes.firstIndex { !MotorVista.abierta($0, ops.coleccion) } ?? urgentes.count
        #expect(urgentes[primeraCerrada...].allSatisfy { !MotorVista.abierta($0, ops.coleccion) })
    }

    // MARK: Edición en la celda (criterio §11.5)

    @Test("Editar una celda escribe solo esa clave; en un CSV, solo esa fila; y Deshacer deja los mismos bytes")
    func edicionEnCelda() async throws {
        let e = try EntornoBases()
        defer { e.limpiar() }
        let s = try await e.servicio()
        defer { s.close() }
        let lector = e.lector(s)
        var opciones = VaultWriter.Options()
        opciones.stateDirectory = e.base.appendingPathComponent("estado-escritor", isDirectory: true)
        opciones.appSupport = e.base.appendingPathComponent("asup", isDirectory: true)
        let writer = try await VaultWriter.open(entry: e.entry, root: e.root, options: opciones)
        defer { Task { await writer.close() } }
        let bus = CommandBus(writer: writer)

        // Ficha: la etapa de la oportunidad de Sergio Nexo.
        let ops = lector.leer(try #require(CatalogoBases.coleccion("oportunidades")))
        let sergio = try #require(ops.filas.first { $0.ruta.stem == "sergio-nexo-trimestrales" })
        let etapa = try #require(ops.coleccion.columna("estado"))
        let valor = try #require(try EdicionCelda.valor("aceptada", para: etapa, hoy: ops.hoy))
        #expect(EdicionCelda.lineaPrevista(sergio, etapa, valor: valor) == "estado: Aceptada")
        let comando = try EdicionCelda.comando(sergio, etapa, valor: valor, coleccion: ops.coleccion)
        #expect(comando == .cambiarPropiedades(sergio.ruta, poner: [Property(key: "estado", value: .text("Aceptada"))], quitar: []))
        let antes = try #require(e.datos(sergio.ruta.raw))
        let r = try await bus.ejecutar(comando, autor: .persona("Manu"))
        #expect(r.hecho)
        let despues = try #require(e.datos(sergio.ruta.raw))
        let la = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n")
        let ld = String(decoding: despues, as: UTF8.self).components(separatedBy: "\n")
        #expect(la.count == ld.count)
        #expect(zip(la, ld).filter { $0 != $1 }.map(\.1) == ["estado: Aceptada"])
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(e.datos(sergio.ruta.raw) == antes)

        // Dinero: «200» se escribe «200.00» y solo cambia esa línea.
        let valorCol = try #require(ops.coleccion.columna("valor"))
        let v200 = try EdicionCelda.valor("200", para: valorCol, hoy: ops.hoy)
        #expect(v200 == .number("200.00"))
        #expect(throws: EdicionError.self) { try EdicionCelda.valor("doscientos", para: valorCol, hoy: ops.hoy) }

        // CSV: la categoría de un gasto cambia solo esa fila de recibidas.csv.
        let gastos = lector.leer(try #require(CatalogoBases.coleccion("gastos")))
        let gasto = try #require(gastos.filas.first { $0.id.hasSuffix("#REC-20260705-001") })
        let categoria = try #require(gastos.coleccion.columna("categoria"))
        let cmd = try EdicionCelda.comando(gasto, categoria, valor: .text("Programas"), coleccion: gastos.coleccion)
        #expect(cmd == .guardarFila(VaultPath("4 · Finanzas/Registros/recibidas.csv"),
                                    fila: ["id": "REC-20260705-001", "categoria": "Programas"], clave: "id"))
        let csvAntes = try #require(e.datos("4 · Finanzas/Registros/recibidas.csv"))
        #expect(try await bus.ejecutar(cmd, autor: .persona("Manu")).hecho)
        let csvDespues = try #require(e.datos("4 · Finanzas/Registros/recibidas.csv"))
        let ca = String(decoding: csvAntes, as: UTF8.self).components(separatedBy: "\n")
        let cd = String(decoding: csvDespues, as: UTF8.self).components(separatedBy: "\n")
        #expect(ca.count == cd.count)
        let cambiadas = zip(ca, cd).filter { $0 != $1 }
        #expect(cambiadas.count == 1)
        #expect(cambiadas.first?.1.hasPrefix("REC-20260705-001,") == true)
        #expect(cambiadas.first?.1.contains(",Programas,") == true)
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(e.datos("4 · Finanzas/Registros/recibidas.csv") == csvAntes)

        // Lo que no se edita, con su motivo.
        let facturas = lector.leer(try #require(CatalogoBases.coleccion("facturas")))
        let f7 = try #require(facturas.filas.first { $0.texto("numero") == "F-2026-0007" })
        let numero = try #require(facturas.coleccion.columna("numero"))
        #expect(EdicionCelda.motivoSoloLectura(f7, numero, coleccion: facturas.coleccion) == "El número de una factura emitida no se cambia.")
        let cobrado = try #require(facturas.coleccion.columna("_cobrado"))
        #expect(EdicionCelda.motivoSoloLectura(f7, cobrado, coleccion: facturas.coleccion)?.hasPrefix("Se calcula") == true)
        #expect(throws: EdicionError.self) { try EdicionCelda.comando(f7, numero, valor: .text("X"), coleccion: facturas.coleccion) }
        let movs = lector.leer(try #require(CatalogoBases.coleccion("movimientos")))
        let mov = try #require(movs.filas.first)
        let importe = try #require(movs.coleccion.columna("importe"))
        #expect(EdicionCelda.motivoSoloLectura(mov, importe, coleccion: movs.coleccion) == "Lo dice el banco: no se cambia aquí.")
    }

    // MARK: Vistas guardadas y módulos

    @Test("Las vistas guardadas se guardan y se leen igual; los módulos se leen de la carpeta")
    func vistasYModulos() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tls-vistas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let almacen = AlmacenVistas(directorio: dir)
        #expect(almacen.leer("oportunidades").isEmpty)
        let v = VistaGuardada(nombre: "Lo de Lucía", config: ConfigVista(vista: .tablero, filtros: [FiltroBase("responsable", .es, ["lucia"])],
                                                                         agrupar: "estado", columnas: ["_titulo", "valor"]))
        try almacen.guardar([v], de: "oportunidades")
        #expect(almacen.leer("oportunidades") == [v])
        #expect(AlmacenVistas.rutaEnCarpeta("oportunidades").raw == ".tls/vistas/oportunidades.json")

        #expect(AjustesBases.modulos(yaml: "objetivos: encendido\ncrm: false\n") == ["objetivos": true, "crm": false])
        #expect(AjustesBases.modulos(yaml: "encendidos: [objetivos, rutinas]\n") == ["objetivos": true, "rutinas": true])
        let texto = AjustesBases.textoModulos(nil, modulo: "objetivos", encendido: true)
        #expect(AjustesBases.modulos(yaml: texto) == ["objetivos": true])
        let otro = AjustesBases.textoModulos("crm: encendido\nobjetivos: apagado\n", modulo: "objetivos", encendido: true)
        #expect(otro == "crm: encendido\nobjetivos: encendido\n")
        #expect(AjustesBases(modulos: [:]).apagada(try #require(CatalogoBases.coleccion("objetivos"))))
        #expect(!AjustesBases(modulos: ["objetivos": true]).apagada(try #require(CatalogoBases.coleccion("objetivos"))))
    }

    @Test("«Editar descripción» cambia solo el primer párrafo de la nota índice; sin párrafo, lo pone tras el título")
    func editarDescripcion() throws {
        let nota = "---\ntls_type: index\ncoleccion: opportunity\nvista: tablero\n---\n# Oportunidades\n\nCada oportunidad es una ficha.\nNace junto a su contacto.\n\n## Cómo se usa\n\nTexto de la sección.\n"
        let nueva = try #require(NotaIndiceBase.cambiandoFrase(nota, por: "  Lo que puede acabar en venta.\n"))
        #expect(nueva == "---\ntls_type: index\ncoleccion: opportunity\nvista: tablero\n---\n# Oportunidades\n\nLo que puede acabar en venta.\n\n## Cómo se usa\n\nTexto de la sección.\n")
        #expect(NotaIndiceBase.frase(cuerpo: "# Oportunidades\n\nLo que puede acabar en venta.\n") == "Lo que puede acabar en venta.")
        // Igual que antes o vacía: nada que escribir.
        #expect(NotaIndiceBase.cambiandoFrase(nota, por: "Cada oportunidad es una ficha. Nace junto a su contacto.") == nil)
        #expect(NotaIndiceBase.cambiandoFrase(nota, por: "   ") == nil)
        // Sin párrafo: va tras el título, y lo demás no se mueve.
        let sinFrase = "---\ntls_type: index\n---\n# Gastos\n\n## Notas\n"
        #expect(NotaIndiceBase.cambiandoFrase(sinFrase, por: "Las facturas recibidas.") == "---\ntls_type: index\n---\n# Gastos\n\nLas facturas recibidas.\n\n## Notas\n")
        // Finales de línea de Windows: se conservan.
        let crlf = "---\r\ntls_type: index\r\n---\r\n# Roles\r\n\r\nQuién lleva qué.\r\n"
        #expect(NotaIndiceBase.cambiandoFrase(crlf, por: "Personas y asistentes.") == "---\r\ntls_type: index\r\n---\r\n# Roles\r\n\r\nPersonas y asistentes.\r\n")
    }

    @Test("Formatos: euros, fechas relativas, personas y opciones")
    func formatos() throws {
        #expect(FormatoBase.euros(1234.5) == "1.234,50 €")
        #expect(FormatoBase.euros(3270.4, redondo: true) == "3.270 €")
        #expect(FormatoBase.euros(-663) == "-663,00 €")
        #expect(FormatoBase.numero("1.234,56") == 1234.56)
        #expect(FormatoBase.numero("150.00") == 150)
        let hoy = LocalDate(year: 2026, month: 10, day: 19)!
        #expect(FormatoBase.fecha(hoy, hoy: hoy) == "hoy")
        #expect(FormatoBase.fecha(hoy.adding(days: 1), hoy: hoy) == "mañana")
        #expect(FormatoBase.fecha(LocalDate(year: 2026, month: 10, day: 24)!, hoy: hoy) == "24 oct")
        #expect(FormatoBase.fecha(LocalDate(year: 2025, month: 3, day: 2)!, hoy: hoy) == "2 mar 2025")
        #expect(FormatoBase.fechaConDia(LocalDate(year: 2026, month: 10, day: 23)!) == "vie 23 oct")
        #expect(FormatoBase.persona("agente:comercial") == "Comercial (asistente)")
        #expect(FormatoBase.opcionVisible("ventas") == "Ventas")
        #expect(FormatoBase.textoVisible(.text("[[talleres-martin|Talleres Martín]]")) == "Talleres Martín")
        #expect(EdicionCelda.fecha("mañana", hoy: hoy) == LocalDate(year: 2026, month: 10, day: 20))
        // Semana y horas del calendario.
        #expect(FormatoBase.lunes(de: LocalDate(year: 2026, month: 10, day: 23)!) == hoy)
        #expect(FormatoBase.semana(hoy) == "Semana del 19 al 25 de octubre")
        #expect(FormatoBase.semana(LocalDate(year: 2026, month: 9, day: 28)!) == "Semana del 28 de septiembre al 4 de octubre")
        #expect(FormatoBase.hora("10:00").map { [$0.hora, $0.minuto] } == [10, 0])
        #expect(FormatoBase.hora("9.30").map { [$0.hora, $0.minuto] } == [9, 30])
        #expect(FormatoBase.hora("17h").map { [$0.hora, $0.minuto] } == [17, 0])
        #expect(FormatoBase.hora("mañana") == nil)
        #expect(FormatoBase.hora("25:00") == nil)
        // Reuniones abre el calendario en semana; las vistas guardadas de antes (sin escala) se siguen leyendo.
        let reuniones = try #require(CatalogoBases.coleccion("reuniones"))
        #expect(reuniones.escalaCalendario == .semana)
        #expect(ConfigVista(vista: .calendario, columnas: []).escala(en: reuniones) == .semana)
        let antigua = #"{"vista":"calendario","filtros":[],"orden":[],"columnas":["_titulo"],"anchos":{},"tamanoGaleria":"m","densidad":"normal","plegados":[]}"#
        let leida = try JSONDecoder().decode(ConfigVista.self, from: Data(antigua.utf8))
        #expect(leida.escalaCalendario == nil && leida.vista == .calendario)
    }
}
