import Foundation
import MCP
import Testing
import TLSCore
@testable import TLSIntegrations
@testable import TLSMCPHost

/// F5 · Calendario (PLAN §7.2, §9 F5 criterio 2) con el doble en memoria: nada de EventKit, TCC ni Calendario real.
@Suite struct CalendarioTests {
    static let claveRutina = "tls://rutina/rutina-semana-prueba"

    func preparar(permiso: PermisoCalendario = .concedido) throws -> (CarpetaCalendario, AlmacenEnMemoria, SincronizadorCalendario) {
        let carpeta = try CarpetaCalendario()
        let almacen = AlmacenEnMemoria(permiso: permiso)
        let sync = SincronizadorCalendario(almacen: almacen, mapa: try MapaCalendario(directory: nil))
        return (carpeta, almacen, sync)
    }

    // MARK: Criterio 2: evento recurrente sin invitados en «The Last System»

    @Test func rutinaCreaEventoRecurrenteSinInvitadosEnNuestroCalendario() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        #expect(informe.estado == .conectado)
        #expect(informe.creados.contains(Self.claveRutina))

        // Nuestro calendario, creado una sola vez.
        let propio = try #require(almacen.calendarios.first { $0.titulo == "The Last System" })
        #expect(almacen.calendariosCreados == 1)

        let ev = try #require(almacen.evento(url: Self.claveRutina))
        #expect(ev.calendario == propio.id)
        #expect(ev.titulo == "Revisión de la semana")
        #expect(ev.repeticion == .semanal(diaSemana: 1))
        #expect(ev.inicio == CarpetaCalendario.fecha(19, 9))
        #expect(ev.minutos == 45)
        #expect(ev.invitados == 0)
        // La app nunca pidió invitados en nada de lo que guardó.
        #expect(almacen.guardados.allSatisfy { $0.invitados == 0 })

        // Segunda pasada: nada nuevo, nada cambiado, el calendario no se repite.
        let otra = try await sync.sincronizar(foto: carpeta.foto)
        #expect(otra.creados.isEmpty && otra.actualizados.isEmpty && otra.retirados.isEmpty && otra.tarjetas.isEmpty)
        #expect(almacen.calendariosCreados == 1)
        #expect(almacen.calendarios.filter { $0.titulo == "The Last System" }.count == 1)
    }

    @Test func elMapaGuardaLaFichaYElEvento() async throws {
        let (carpeta, almacen, _) = try preparar()
        defer { carpeta.borrar() }
        let dir = carpeta.base.appendingPathComponent("estado", isDirectory: true)
        let mapa = try MapaCalendario(directory: dir)
        let sync = SincronizadorCalendario(almacen: almacen, mapa: mapa)
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let fila = try #require(try mapa.fila(Self.claveRutina))
        #expect(fila.tipo == "rutina")
        #expect(fila.ruta == VaultPath(CarpetaCalendario.rutina))
        #expect(fila.eventoID == almacen.evento(url: Self.claveRutina)?.id)
        #expect(fila.ancla == CarpetaCalendario.hoy)
        #expect(try mapa.calendarioPropio() != nil)
        mapa.cerrar()
        // En `estado.sqlite`, junto a las tablas del dominio y del gobierno.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("estado.sqlite").path))
        let reabierto = try MapaCalendario(directory: dir)
        #expect(try reabierto.fila(Self.claveRutina)?.eventoID == fila.eventoID)
        reabierto.cerrar()
    }

    @Test func soloRutinasQuePidenCalendarioActivasYConHora() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        try carpeta.escribir("1 · Dirección/Rutinas/sin-calendario.md",
                             CarpetaCalendario.textoRutina(calendario: false).replacingOccurrences(of: "rutina-semana-prueba", with: "otra-1"))
        try carpeta.escribir("1 · Dirección/Rutinas/inactiva.md",
                             CarpetaCalendario.textoRutina(activa: false).replacingOccurrences(of: "rutina-semana-prueba", with: "otra-2"))
        try carpeta.escribir("1 · Dirección/Rutinas/sin-hora.md",
                             CarpetaCalendario.textoRutina(hora: "").replacingOccurrences(of: "rutina-semana-prueba", with: "otra-3"))
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let urls = almacen.eventos.compactMap(\.url?.absoluteString)
        #expect(urls.contains(Self.claveRutina))
        #expect(!urls.contains { $0.contains("otra-") })
    }

    // MARK: Retirar y cambiar la ficha

    @Test func retirarLaFichaRetiraElEvento() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let id = try #require(almacen.evento(url: Self.claveRutina)?.id)

        try carpeta.retirar(CarpetaCalendario.rutina)
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        #expect(informe.retirados == [Self.claveRutina])
        #expect(almacen.evento(url: Self.claveRutina) == nil)
        #expect(almacen.retiradas == [id])
        // Una tercera pasada no lo vuelve a crear.
        let otra = try await sync.sincronizar(foto: carpeta.foto)
        #expect(otra.creados.isEmpty && otra.retirados.isEmpty)
    }

    @Test func desactivarLaRutinaTambienLaRetira() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        try carpeta.escribir(CarpetaCalendario.rutina, CarpetaCalendario.textoRutina(activa: false))
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        #expect(informe.retirados == [Self.claveRutina])
        #expect(almacen.evento(url: Self.claveRutina) == nil)
    }

    @Test func cambiarLaFichaActualizaElEvento() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let id = try #require(almacen.evento(url: Self.claveRutina)?.id)

        try carpeta.escribir(CarpetaCalendario.rutina, CarpetaCalendario.textoRutina(dia: "martes", hora: "10:30", duracion: 60))
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        #expect(informe.actualizados == [Self.claveRutina])
        #expect(informe.tarjetas.isEmpty)
        let ev = try #require(almacen.evento(url: Self.claveRutina))
        #expect(ev.id == id)   // el mismo evento, no uno nuevo
        #expect(ev.repeticion == .semanal(diaSemana: 2))
        #expect(ev.inicio == CarpetaCalendario.fecha(20, 10, 30))
        #expect(ev.minutos == 60)
        #expect(ev.invitados == 0)
    }

    // MARK: Editar fuera → tarjeta «¿Actualizo la ficha?»

    @Test func editarFueraDaTarjetaYNoSeEscribeSolo() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let id = try #require(almacen.evento(url: Self.claveRutina)?.id)
        let fichaAntes = carpeta.leer(CarpetaCalendario.rutina)

        // Manu pasa la revisión a las 11:00 en Calendario.
        almacen.editarFuera(id) { e in
            e.inicio = CarpetaCalendario.fecha(19, 11)
            e.fin = CarpetaCalendario.fecha(19, 11, 45)
        }
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        let t = try #require(informe.tarjetas.first)
        #expect(t.tipo == .cambiadoEnCalendario)
        #expect(t.clave == Self.claveRutina)
        #expect(t.titulo.contains("Revisión de la semana"))
        #expect(t.boton == "Actualizar la ficha")
        #expect(t.diferencias == [DiferenciaCalendario(campo: "Hora", enFicha: "9:00", enCalendario: "11:00")])
        // Nada se escribió solo: ni la ficha ni el evento.
        #expect(carpeta.leer(CarpetaCalendario.rutina) == fichaAntes)
        #expect(almacen.evento(url: Self.claveRutina)?.inicio == CarpetaCalendario.fecha(19, 11))
        #expect(informe.actualizados.isEmpty)
        // La tarjeta sigue mientras no decidas (y con el mismo id).
        let otra = try await sync.sincronizar(foto: carpeta.foto)
        #expect(otra.tarjetas.map(\.id) == [t.id])

        // «Actualizar la ficha»: el plan, como la persona, solo con la hora.
        let plan = try #require(try await sync.planParaActualizarFicha(t, foto: carpeta.foto, persona: "Manu"))
        #expect(plan.autor == .persona("Manu"))
        #expect(plan.ops == [.mergeFrontmatter(VaultPath(CarpetaCalendario.rutina), set: [Property(key: "hora", value: .text("11:00"))],
                                               unset: [])])
        // Cuando la ficha ya dice lo mismo (lo aplicó el CommandBus), la tarjeta desaparece sola y no se toca el evento.
        try carpeta.escribir(CarpetaCalendario.rutina, CarpetaCalendario.textoRutina(hora: "11:00"))
        let tras = try await sync.sincronizar(foto: carpeta.foto)
        #expect(tras.tarjetas.isEmpty && tras.actualizados.isEmpty)
        // Y a partir de ahí, un cambio de ficha vuelve a llegar al Calendario.
        try carpeta.escribir(CarpetaCalendario.rutina, CarpetaCalendario.textoRutina(hora: "12:00"))
        let luego = try await sync.sincronizar(foto: carpeta.foto)
        #expect(luego.actualizados == [Self.claveRutina])
        #expect(almacen.evento(url: Self.claveRutina)?.inicio == CarpetaCalendario.fecha(19, 12))
    }

    @Test func dejarLaFichaComoEstaDevuelveElEvento() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let id = try #require(almacen.evento(url: Self.claveRutina)?.id)
        almacen.editarFuera(id) { $0.titulo = "Otra cosa" }
        let t = try #require(try await sync.sincronizar(foto: carpeta.foto).tarjetas.first)
        #expect(t.diferencias.map(\.campo) == ["Nombre"])
        #expect(try await sync.devolverAlaFicha(t, foto: carpeta.foto))
        #expect(almacen.evento(url: Self.claveRutina)?.titulo == "Revisión de la semana")
        let otra = try await sync.sincronizar(foto: carpeta.foto)
        #expect(otra.tarjetas.isEmpty && otra.actualizados.isEmpty)
    }

    @Test func quitarloEnCalendarioPreguntaYNoLoVuelveAPonerSolo() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        almacen.quitarFuera(try #require(almacen.evento(url: Self.claveRutina)?.id))
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        let t = try #require(informe.tarjetas.first)
        #expect(t.tipo == .quitadoEnCalendario)
        #expect(almacen.evento(url: Self.claveRutina) == nil)
        // «Quitarla del Calendario»: la ficha deja de pedirlo (no se retira).
        let plan = try #require(sync.planParaDejarDeApuntar(t, persona: "Manu"))
        #expect(plan.ops == [.mergeFrontmatter(VaultPath(CarpetaCalendario.rutina), set: [Property(key: "calendario", value: .bool(false))],
                                               unset: [])])
        // «Volver a ponerlo»: otra vez en Calendario.
        #expect(try await sync.devolverAlaFicha(t, foto: carpeta.foto))
        #expect(almacen.evento(url: Self.claveRutina) != nil)
        #expect(try await sync.sincronizar(foto: carpeta.foto).tarjetas.isEmpty)
    }

    @Test func conInvitadosPuestosFueraNoSeTocaNada() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let id = try #require(almacen.evento(url: Self.claveRutina)?.id)
        almacen.editarFuera(id) { $0.invitados = 2 }
        let guardadosAntes = almacen.guardados.count
        try carpeta.escribir(CarpetaCalendario.rutina, CarpetaCalendario.textoRutina(hora: "10:00"))
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        #expect(informe.tarjetas.map(\.tipo) == [.conInvitados])
        #expect(almacen.guardados.count == guardadosAntes)
        try carpeta.retirar(CarpetaCalendario.rutina)
        let retirar = try await sync.sincronizar(foto: carpeta.foto)
        #expect(retirar.tarjetas.map(\.tipo) == [.conInvitados])
        #expect(almacen.retiradas.isEmpty)
    }

    // MARK: Sesiones S1–S9

    @Test func sesionesDelViajeConFechaYSinLoPrivado() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let sesiones = almacen.eventos.filter { $0.url?.absoluteString.hasPrefix("tls://sesion/") ?? false }
        #expect(sesiones.count == 2)   // S1 (con hora) y S2 (todo el día); S3 no incluida y S4 sin fecha, fuera
        let s1 = try #require(almacen.evento(url: "tls://sesion/portal-prueba/S1"))
        #expect(s1.titulo == "S1 · Arranque · Cliente de prueba")
        #expect(s1.inicio == CarpetaCalendario.fecha(21, 10))
        #expect(s1.minutos == 60 && !s1.todoElDia && s1.repeticion == nil && s1.invitados == 0)
        let s2 = try #require(almacen.evento(url: "tls://sesion/portal-prueba/S2"))
        #expect(s2.todoElDia)
        // Lo privado nunca llega al Calendario.
        #expect(!almacen.eventos.contains { $0.titulo.contains("Expediente privado") || ($0.notas ?? "").contains("privado") })

        // Cambiar la fecha de S1 en Calendario → la tarjeta y el plan cambian solo la celda «Fecha» de su fila.
        almacen.editarFuera(try #require(s1.id)) { e in
            e.inicio = CarpetaCalendario.fecha(22, 16)
            e.fin = CarpetaCalendario.fecha(22, 17)
        }
        let t = try #require(try await sync.sincronizar(foto: carpeta.foto).tarjetas.first)
        #expect(t.ruta == VaultPath(CarpetaCalendario.portal))
        let plan = try #require(try await sync.planParaActualizarFicha(t, foto: carpeta.foto, persona: "Manu"))
        #expect(plan.ops == [.setTableCells(VaultPath(CarpetaCalendario.portal), table: PortalDocumento.tablaViaje, keyColumn: "Sesión",
                                            keyValue: "S1 · Arranque", cells: ["Fecha": "2026-10-22 16:00"])])
    }

    // MARK: Otros calendarios → solo ocupado

    @Test func otrosCalendariosSoloDanOcupado() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        let trabajo = almacen.anadirCalendarioAjeno("Trabajo")
        let casa = almacen.anadirCalendarioAjeno("Casa")
        let f = CarpetaCalendario.fecha
        almacen.anadirAjeno(.init(calendario: trabajo, titulo: "Expediente privado", asistentes: ["persona@ejemplo.es"],
                                  inicio: f(19, 10, 0, 10), fin: f(19, 11, 0, 10)))
        // Se solapa con el anterior: cuenta una sola vez (de 10:30 a 12:00 → 10:00–12:00).
        almacen.anadirAjeno(.init(calendario: casa, titulo: "Médico", asistentes: [], inicio: f(19, 10, 30, 10), fin: f(19, 12, 0, 10)))
        almacen.anadirAjeno(.init(calendario: casa, titulo: "Comida", asistentes: [], inicio: f(19, 14, 0, 10), fin: f(19, 15, 0, 10)))
        // De todo el día (festivo): no son horas de trabajo.
        almacen.anadirAjeno(.init(calendario: casa, titulo: "Festivo", asistentes: [], inicio: f(20, 0, 0, 10), fin: f(21, 0, 0, 10),
                                  todoElDia: true))
        // Nuestro calendario (con la sesión S1 del miércoles) no cuenta como ocupado ajeno.
        _ = try await sync.sincronizar(foto: carpeta.foto)

        let lunes = CarpetaCalendario.hoy
        let ocupado = await sync.ocupado(desde: lunes, hasta: lunes.adding(days: 6), zona: CarpetaCalendario.zona)
        #expect(ocupado == [
            EventoAgenda(titulo: "Ocupado", dia: lunes, hora: "10:00", horas: 2),
            EventoAgenda(titulo: "Ocupado", dia: lunes, hora: "14:00", horas: 1),
        ])
        let todo = "\(ocupado)"
        #expect(!todo.contains("Expediente privado") && !todo.contains("Médico") && !todo.contains("ejemplo.es"))

        // «Hoy tienes 3 h de 4» y la semana frente al tope.
        let medida = FotoMetricas(snapshot: carpeta.foto, hoy: lunes)
        let sin = Agenda(foto: medida).semana(de: lunes)
        let con = Agenda(foto: medida, eventos: ocupado).semana(de: lunes)
        #expect(con.diaDeHoy?.eventos.count == 2)
        #expect(((con.diaDeHoy?.horas ?? 0) - (sin.diaDeHoy?.horas ?? 0) - 3).magnitude < 0.01)
        #expect(con.fraseHoy.hasPrefix("Hoy tienes ") && con.fraseHoy.contains(" de 4"))
        #expect(con.totalHoras > sin.totalHoras)
    }

    @Test func tlsAgendaSoloVeOcupadoSinTitulos() async throws {
        let (carpeta, almacen, sync) = try preparar()
        defer { carpeta.borrar() }
        let trabajo = almacen.anadirCalendarioAjeno("Trabajo")
        almacen.anadirAjeno(.init(calendario: trabajo, titulo: "Expediente privado", asistentes: ["persona@ejemplo.es"],
                                  inicio: CarpetaCalendario.fecha(19, 10), fin: CarpetaCalendario.fecha(19, 12)))
        _ = try await sync.sincronizar(foto: carpeta.foto)

        let estado = carpeta.base.appendingPathComponent("estado", isDirectory: true)
        let entry = VaultEntry(nombre: "Asesoría Ribera", ruta: carpeta.root.path, bookmark: nil, clase: .demo, escritura: .bloqueada)
        let service = try VaultService(entry: entry, root: carpeta.root, options: .init(stateDirectory: estado, vigilar: false))
        _ = try await service.open { _ in }
        defer { service.close() }
        var deps = ServidorDeHerramientas.Dependencias.de(
            service: service, bus: nil, autorizador: AutorizadorBasico(modoPorDefecto: .autonomo), servicios: ServiciosEnMemoria(),
            aprobaciones: AprobacionesEnMemoria(), propuestas: PropuestasEnMemoria(), auditoria: AuditoriaEnMemoria())
        deps.ocupado = sync.fuenteDeOcupado(zona: CarpetaCalendario.zona)
        let servidor = ServidorDeHerramientas(deps)
        let contexto = ContextoDelAsistente(ejecucion: "r-cal", asistente: "mika", coordinador: true, areas: [.direccion],
                                            leeAreas: AreaCode.allCases)
        let r = await servidor.llamar("tls_agenda", argumentos: [:], contexto: contexto)
        #expect(!r.esError, "\(r.texto)")
        let dias = r.estructurado?.objectValue?["dias"]?.arrayValue ?? []
        let lunes = try #require(dias.first?.objectValue)
        #expect((lunes["ocupado"]?.intValue ?? 0) >= 1)
        #expect(lunes["ocupado_calendario_h"] == .double(2))
        let todo = "\(r.texto) \(String(describing: r.estructurado))"
        #expect(!todo.contains("Expediente privado") && !todo.contains("ejemplo.es") && !todo.contains("Ocupado ·"))
    }

    // MARK: Permiso

    @Test func permisoDenegadoDaTarjetaExplicativaYNoHaceNada() async throws {
        for p in [PermisoCalendario.denegado, .restringido, .soloAnadir] {
            let (carpeta, almacen, sync) = try preparar(permiso: p)
            defer { carpeta.borrar() }
            let informe = try await sync.sincronizar(foto: carpeta.foto)
            let tarjeta = try #require(informe.tarjetaDePermiso)
            #expect(tarjeta.permiso == .calendarios)
            #expect(tarjeta.id == "permiso:calendarios")
            #expect(tarjeta.boton == "Abrir Ajustes del Sistema")
            #expect(tarjeta.enlace.absoluteString.contains("Privacy_Calendars"))
            #expect(!tarjeta.texto.isEmpty)
            #expect(almacen.calendarios.isEmpty && almacen.eventos.isEmpty && almacen.guardados.isEmpty)
            #expect(await sync.ocupado(desde: CarpetaCalendario.hoy, hasta: CarpetaCalendario.hoy, zona: CarpetaCalendario.zona).isEmpty)
            #expect(sync.estadoDelPermiso().necesitaRecuperacion)
        }
    }

    @Test func sinPreguntarNoSeConectaNiPregunta() async throws {
        let (carpeta, almacen, sync) = try preparar(permiso: .sinPreguntar)
        defer { carpeta.borrar() }
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        #expect(informe.estado == .sinConectar)
        #expect(almacen.calendarios.isEmpty && almacen.eventos.isEmpty)
        #expect(sync.estadoDelPermiso() == .sinPreguntar)
        // Al conceder (tras la explicación de Permisos), conectar crea el calendario.
        almacen.ponerPermiso(.concedido)
        #expect(try await sync.conectar().estado == .conectado)
        #expect(almacen.calendarios.map(\.titulo) == ["The Last System"])
    }

    // MARK: Paso 5 de la puesta en marcha

    @Test func rutinaDeLaPuestaSeApuntaSoloConCalendarioConectado() async throws {
        let (carpeta, almacen, sync) = try preparar(permiso: .sinPreguntar)
        defer { carpeta.borrar() }
        // La rutina como la deja el paso 5 (plantilla de serie: `calendario: false`).
        try carpeta.escribir(CarpetaCalendario.rutina, CarpetaCalendario.textoRutina(calendario: false))
        #expect(await sync.planDeLaPuesta(foto: carpeta.foto, persona: "Manu") == nil)

        almacen.ponerPermiso(.concedido)
        try await sync.conectar()
        let plan = try #require(await sync.planDeLaPuesta(foto: carpeta.foto, persona: "Manu"))
        #expect(plan.ops == [.mergeFrontmatter(VaultPath(CarpetaCalendario.rutina), set: [Property(key: "calendario", value: .bool(true))],
                                               unset: [])])
        // Aplicado el plan, la siguiente pasada crea su evento recurrente.
        try carpeta.escribir(CarpetaCalendario.rutina, CarpetaCalendario.textoRutina(calendario: true))
        let informe = try await sync.sincronizar(foto: carpeta.foto)
        #expect(informe.creados.contains(Self.claveRutina))
        #expect(await sync.planDeLaPuesta(foto: carpeta.foto, persona: "Manu") == nil)
    }

    // MARK: Piezas puras

    @Test func repeticionesYHuella() {
        #expect(EventosDeLaCarpeta.repeticion(cadencia: "semanal", dia: "Miércoles") == .semanal(diaSemana: 3))
        #expect(EventosDeLaCarpeta.repeticion(cadencia: nil, dia: "vie") == .semanal(diaSemana: 5))
        #expect(EventosDeLaCarpeta.repeticion(cadencia: "mensual", dia: "5") == .mensual(diaMes: 5, cadaMeses: 1))
        #expect(EventosDeLaCarpeta.repeticion(cadencia: "trimestral", dia: "15") == .mensual(diaMes: 15, cadaMeses: 3))
        #expect(EventosDeLaCarpeta.repeticion(cadencia: "semanal", dia: "") == nil)
        let z = CarpetaCalendario.zona
        let trimestral = EventosDeLaCarpeta.primerDia(.mensual(diaMes: 15, cadaMeses: 3), desde: CarpetaCalendario.hoy, zona: z)
        #expect(trimestral == LocalDate(year: 2027, month: 1, day: 15))
        let e = EventoDelCalendario(titulo: "X", inicio: CarpetaCalendario.fecha(19, 9), fin: CarpetaCalendario.fecha(19, 9, 30),
                                    repeticion: .semanal(diaSemana: 1))
        var otraSemana = e
        otraSemana.inicio = CarpetaCalendario.fecha(26, 9); otraSemana.fin = CarpetaCalendario.fecha(26, 9, 30)
        // La huella de una serie no depende de la semana en que empieza.
        #expect(HuellaEvento.de(e, zona: z) == HuellaEvento.de(otraSemana, zona: z))
        #expect(EventosDeLaCarpeta.url(.sesion, "a b/S1").absoluteString == "tls://sesion/a%20b/S1")
    }
}
