import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Operación de Entrega (PLAN §6.5 y criterio F2-8): el Viaje S1–S9 de Portal.md, la vista del cliente sin notas,
/// responsable, resolución, correos ni kit, la cuenta atrás de las incidencias en horas hábiles (24/48/72), ENT-INC,
/// los expedientes sin lo privado y las escrituras (estado de una sesión, nueva incidencia) con Deshacer.
@Suite("Áreas · Entrega · Operación", .serialized)
@MainActor
struct EntregaOperacionTests {
    let pruebas = SesionEscrituraTests()
    let madrid = ApoyoAreasA.madrid

    func portal() throws -> (PortalDocumento, RegistroIncidencias, URL) {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        try ApoyoAreasA.preparar(carpeta)
        let p = PortalDocumento.leer(try ApoyoAreasA.texto(ApoyoAreasA.portalTalleres, en: carpeta), ruta: ApoyoAreasA.portalTalleres)
        let i = RegistroIncidencias.leer(try ApoyoAreasA.texto(ApoyoAreasA.incidenciasTalleres, en: carpeta),
                                         ruta: ApoyoAreasA.incidenciasTalleres, zona: madrid)
        return (p, i, base)
    }

    @Test("Viaje: S1–S5 con su estado, fecha, resumen y nota interna; 1 de 4 hechas; la próxima es S2")
    func viaje() throws {
        let (p, _, base) = try portal()
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(p.sesiones.map(\.codigo) == ["S1", "S2", "S3", "S4", "S5"])
        #expect(p.sesiones.map(\.estado) == [.hecha, .kitListo, .programada, .pendiente, .noIncluida])
        #expect(p.sesiones[1].nombre == "Revisión de gastos" && p.sesiones[1].fecha == LocalDate(year: 2026, month: 10, day: 23)!)
        #expect(p.sesiones[0].notaInterna?.contains("@") == true)
        #expect(p.hechas == 1 && p.incluidas == 4)
        #expect(p.proxima(hoy: ApoyoAreasA.hoy)?.codigo == "S2")
        #expect(p.tareasCliente.count == 3 && p.tareasCliente[0].hecha && p.tareasCliente[1].sesion == "S2")
        #expect(p.tareasCliente[1].vence == LocalDate(year: 2026, month: 10, day: 22)!)
        #expect(p.documentos.count == 2 && p.dudas.count == 1)
        // Cambiar el estado de una sesión: solo la celda Estado de su fila.
        let comando = try #require(p.comandoEstado(p.sesiones[3], a: .programada))
        #expect(comando == .cambiarCeldas(ApoyoAreasA.portalTalleres, tabla: PortalDocumento.tablaViaje, columnaClave: "Sesión",
                                          valorClave: "S4 · Cierre del año", celdas: ["Estado": "Programada"]))
    }

    @Test("Vista del cliente: sin notas internas, responsable, resolución, correos ni kit (criterio F2-8)")
    func vistaCliente() throws {
        let (p, i, base) = try portal()
        defer { try? FileManager.default.removeItem(at: base) }
        let c = PortalCliente(portal: p, incidencias: i.filas)
        let texto = c.textoCompleto
        // Nada de las notas internas.
        for s in p.sesiones { if let n = s.notaInterna { #expect(!texto.contains(n), "Se ve la nota interna «\(n)»") } }
        #expect(!texto.contains("dietas de julio: faltan"))
        // Ni correos, ni responsable, ni resolución.
        #expect(!texto.contains("@"))
        #expect(!texto.contains("Manu"))
        for inc in i.filas { if let r = inc.resolucion { #expect(!texto.contains(r)) } }
        // Ni kit: «Kit listo» es Programada para el cliente, y el documento del kit no sale.
        #expect(texto.range(of: #"\bkits?\b"#, options: [.regularExpression, .caseInsensitive]) == nil)
        #expect(c.sesiones.first { $0.codigo == "S2" }?.estado == .programada)
        #expect(c.documentos == ["[Guía para enviar facturas](Materiales/guia-para-enviar-facturas.md)"])
        // Lo suyo sí: el viaje, lo que necesitamos de él, sus dudas e incidencias (sin datos internos).
        #expect(c.sesiones.count == 5 && c.tareas.count == 3 && c.dudas.count == 1)
        #expect(c.sesiones[1].resumen == "Revisaremos juntos los gastos del trimestre")
        #expect(c.incidencias.map(\.id) == ["INC-001", "INC-002"])
        #expect(c.incidencias.first?.descripcion == "No puede entrar en la carpeta compartida de facturas.")
        // `limpiar` quita un correo suelto y una frase sobre el kit.
        #expect(PortalCliente.limpiar("Escríbenos a hola@ejemplo.example si hace falta") == "Escríbenos a si hace falta")
        #expect(PortalCliente.limpiar("Todo listo. El kit está en la carpeta. Nos vemos el martes") == "Todo listo. Nos vemos el martes")
    }

    @Test("Cuenta atrás en horas hábiles: grave 24 h (el fin de semana no cuenta), media 48 h y leve 72 h")
    func horasHabiles() {
        // Grave recibida el viernes 16 a las 10:00: vence el lunes 19 a las 10:00.
        let viernes = ApoyoAreasA.instante(16, 10)
        #expect(HorasHabiles.sumar(24, a: viernes, zona: madrid) == ApoyoAreasA.instante(19, 10))
        let grave = IncidenciaRegistrada(id: "INC-001", ruta: nil, fechaTexto: "2026-10-16 10:00", recibida: viernes, quien: nil, email: nil,
                                         tipo: nil, severidad: .grave, severidadTexto: "Grave", estado: .recibida, estadoTexto: "Recibida",
                                         descripcion: nil, responsable: nil, resolucion: nil)
        #expect(grave.cuentaAtras(ahora: viernes, zona: madrid)?.texto == "Quedan 24 h hábiles")
        // El sábado a mediodía solo han pasado las 14 h del viernes.
        #expect(grave.cuentaAtras(ahora: ApoyoAreasA.instante(17, 12), zona: madrid)?.texto == "Quedan 10 h hábiles")
        let lunes9 = grave.cuentaAtras(ahora: ApoyoAreasA.instante(19, 9), zona: madrid)
        #expect(lunes9?.texto == "Quedan 1 h hábiles" && lunes9?.apurada == true && lunes9?.fueraDePlazo == false)
        let lunes13 = grave.cuentaAtras(ahora: ApoyoAreasA.instante(19, 13), zona: madrid)
        #expect(lunes13?.texto == "Fuera de plazo hace 3 h hábiles" && lunes13?.fueraDePlazo == true)
        #expect(lunes13?.textoPlazo == "lun 19 oct, 10:00" && lunes13?.total == 24)
        // Media el jueves 15 a las 18:00: 30 h hasta el viernes a medianoche y 18 h el lunes → lunes 19 a las 18:00.
        #expect(HorasHabiles.sumar(48, a: ApoyoAreasA.instante(15, 18), zona: madrid) == ApoyoAreasA.instante(19, 18))
        // Leve el sábado 17: empieza a contar el lunes a las 0:00 → jueves 22 a las 0:00.
        #expect(HorasHabiles.sumar(72, a: ApoyoAreasA.instante(17, 11), zona: madrid) == ApoyoAreasA.instante(22, 0))
        // Resuelta: no hay cuenta atrás.
        let resuelta = IncidenciaRegistrada(id: "INC-002", ruta: nil, fechaTexto: nil, recibida: viernes, quien: nil, email: nil, tipo: nil,
                                            severidad: .leve, severidadTexto: nil, estado: .resuelta, estadoTexto: "Resuelta",
                                            descripcion: nil, responsable: nil, resolucion: nil)
        #expect(resuelta.cuentaAtras(ahora: viernes, zona: madrid) == nil)
        // Fechas escritas: con hora, con «T», a la española y solo el día.
        #expect(RegistroIncidencias.instante("2026-10-16 10:00", zona: madrid) == viernes)
        #expect(RegistroIncidencias.instante("2026-10-16T10:00", zona: madrid) == viernes)
        #expect(RegistroIncidencias.instante("16/10/2026 10:00", zona: madrid) == viernes)
        #expect(RegistroIncidencias.instante("2026-10-16", zona: madrid) == ApoyoAreasA.instante(16, 0))
    }

    @Test("Expedientes de la carpeta: sin lo privado, con portal, incidencias, tareas y materiales; ENT-INC con la cuenta atrás")
    func expedientes() throws {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        try ApoyoAreasA.preparar(carpeta)
        let foto = ApoyoAreasA.foto(carpeta)
        // Lunes 19 a las 13:00: INC-001 (grave, del viernes a las 10:00) ya está fuera de plazo.
        let d = DatosEntrega.calcular(foto: foto, hoy: ApoyoAreasA.hoy, ahora: ApoyoAreasA.instante(19, 13))
        #expect(d.expedientes.map(\.ruta) == [ApoyoAreasA.talleres, ApoyoAreasA.clinica])
        let t = try #require(d.expedientes.first)
        #expect(t.portal?.ruta == ApoyoAreasA.portalTalleres && t.textoSesiones == "1 de 4 sesiones")
        #expect(t.incidencias?.filas.count == 2 && t.incidenciasAbiertas.map(\.id) == ["INC-001"])
        #expect(t.tareas.map(\.titulo) == ["Solicitar facturas y extractos del trimestre"])
        #expect(t.materiales.map(\.name) == ["guia-para-enviar-facturas.md", "inventario.csv", "kit-s2-gastos.md"])
        #expect(t.empresa == "Talleres Martín e Hijos SL" && t.contacto == "Jorge Martín" && t.fase == "Recogida")
        #expect(t.riesgo(hoy: d.hoy, ahora: d.ahora, zona: d.zona) == "1 incidencia fuera de plazo")
        let entInc = try #require(d.cifras.first { $0.codigo == "ENT-INC" })
        #expect(entInc.valor == "1")
        // Sin registro de incidencias en ningún expediente: «Sin dato», no 0.
        let sin = DatosEntrega.entInc([d.expedientes[1]], evaluador: KPIEvaluador(foto: FotoMetricas(snapshot: foto, hoy: d.hoy), metas: nil),
                                      ahora: d.ahora, zona: d.zona)
        #expect(sin.valor == "Sin dato")
        // A las 9:00 aún quedaba 1 h: no cuenta como fuera de plazo.
        let antes = DatosEntrega.calcular(foto: foto, hoy: ApoyoAreasA.hoy, ahora: ApoyoAreasA.instante(19, 9))
        #expect(antes.cifras.first { $0.codigo == "ENT-INC" }?.valor == "0")
        // El cronograma de Entrega lleva los dos expedientes abiertos.
        #expect(Set(d.cronograma.barras.map(\.ruta)) == [ApoyoAreasA.talleres, ApoyoAreasA.clinica])
        // Carga: la tarea de 2 h del martes 20 y la sesión S2 del viernes 23.
        let martes = try #require(d.carga.first { $0.dia == LocalDate(year: 2026, month: 10, day: 20)! })
        #expect(martes.horas == 2 && martes.textoCarga == "2 h de 4")
        #expect(d.carga.first { $0.dia == LocalDate(year: 2026, month: 10, day: 23)! }?.sesiones == ["Talleres Martín e Hijos SL · S2"])
        // Revisión del viernes: S1 hecha esta semana y lo que espera del cliente.
        let r = RevisionViernes.de(d)
        #expect(r.hechas.map(\.texto) == ["Talleres Martín e Hijos SL · S1 · Arranque"])
        #expect(r.atascos.contains { $0.texto.contains("INC-001") && $0.estado == .mal })
        #expect(r.delCliente.count == 2)
    }

    func abrir() async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        try ApoyoAreasA.preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        return (e, sesion)
    }

    @Test("Cambiar el estado de una sesión escribe solo esa celda de Portal.md y se deshace")
    func cambiarSesion() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let url = ApoyoAreasA.portalTalleres.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let p = PortalDocumento.leer(String(decoding: antes, as: UTF8.self), ruta: ApoyoAreasA.portalTalleres)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        #expect(await AccionesEntrega.cambiarSesion(p.sesiones[3], a: .programada, en: p, sesion: sesion, deshacer: um) == nil)
        um.endUndoGrouping()
        let despues = try String(contentsOf: url, encoding: .utf8)
        let cambiadas = ApoyoAreasA.lineasCambiadas(String(decoding: antes, as: UTF8.self), despues)
        #expect(cambiadas.count == 1 && cambiadas[0].contains("S4 · Cierre del año") && cambiadas[0].contains("Programada"))
        um.undo()
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("Nueva incidencia: una fila al final con INC-003 y su plazo; si el proyecto no tiene registro, se crea con la plantilla")
    func nuevaIncidencia() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let foto = try #require(await AccionesDireccion.fotoActual(sesion))
        let d = DatosEntrega.calcular(foto: foto, hoy: ApoyoAreasA.hoy, ahora: ApoyoAreasA.instante(19, 11))
        let talleres = try #require(d.expedientes.first { $0.ruta == ApoyoAreasA.talleres })
        let url = ApoyoAreasA.incidenciasTalleres.url(in: e.carpeta)
        let antes = try String(contentsOf: url, encoding: .utf8)
        #expect(await AccionesEntrega.nuevaIncidencia(talleres, quien: "Jorge Martín", email: "jorge@talleresmartin.example", tipo: "Técnica",
                                                      severidad: .grave, descripcion: "El enlace de subida da error.",
                                                      ahora: ApoyoAreasA.instante(19, 11, 30), zona: madrid, sesion: sesion, deshacer: nil) == nil)
        let despues = try String(contentsOf: url, encoding: .utf8)
        let nuevas = despues.components(separatedBy: "\n").filter { !antes.components(separatedBy: "\n").contains($0) }
        #expect(nuevas.count == 1)
        let fila = try #require(nuevas.first)
        #expect(fila.hasPrefix("| INC-003 | 2026-10-19 11:30 | Jorge Martín | jorge@talleresmartin.example | Técnica | Grave | Recibida | El enlace de subida da error. | Manu |"))
        let registro = RegistroIncidencias.leer(despues, ruta: ApoyoAreasA.incidenciasTalleres, zona: madrid)
        let inc = try #require(registro.filas.last)
        #expect(inc.plazo(zona: madrid) == ApoyoAreasA.instante(20, 11, 30))
        // El contador de incidencias sube a 3.
        #expect(Secuencias.leer(ApoyoAreasA.foto(e.carpeta))["incidencia"] == 3)

        // La clínica no tiene registro: se crea con la plantilla y la fila dentro (INC-004).
        let rev = sesion.revision
        await pruebas.esperar { sesion.revision > rev }
        let foto2 = try #require(await AccionesDireccion.fotoActual(sesion))
        let d2 = DatosEntrega.calcular(foto: foto2, hoy: ApoyoAreasA.hoy, ahora: ApoyoAreasA.instante(19, 12))
        let clinica = try #require(d2.expedientes.first { $0.ruta == ApoyoAreasA.clinica })
        #expect(clinica.incidencias == nil)
        #expect(await AccionesEntrega.nuevaIncidencia(clinica, quien: "Dra. Ana Pons", email: "", tipo: "Negocio", severidad: .leve,
                                                      descripcion: "Duda sobre el modelo 130.", ahora: ApoyoAreasA.instante(19, 12),
                                                      zona: madrid, sesion: sesion, deshacer: nil) == nil)
        let creado = try String(contentsOf: clinica.rutaIncidencias.url(in: e.carpeta), encoding: .utf8)
        #expect(creado.contains("tls_type: log") && creado.contains("| INC-004 | 2026-10-19 12:00 | Dra. Ana Pons |"))
        let leido = RegistroIncidencias.leer(creado, ruta: clinica.rutaIncidencias, zona: madrid)
        #expect(leido.filas.map(\.id) == ["INC-004"] && leido.filas.first?.severidad == .leve)
    }
}
