import Foundation
import TLSCore
import TLSDesign

// La Operación de Entrega (PLAN §6.5, SISTEMAS §4.2, EN1–EN3): los expedientes de cliente con su Viaje, sus
// tareas, su portal, sus incidencias con cuenta atrás y sus materiales; el cronograma, la carga de la semana y la
// revisión del viernes. Puro: lo calcula `DatosEntrega.calcular` con la foto de la carpeta, sin nada privado.

/// Un expediente: un proyecto de entrega (de cliente) y lo que cuelga de su carpeta.
struct ExpedienteEntrega: Identifiable, Hashable, Sendable {
    var id: VaultPath { ruta }
    /// `Proyecto.md`.
    let ruta: VaultPath
    let carpeta: VaultPath
    let nombre: String
    let empresa: String?
    let contacto: String?
    let estado: FotoMetricas.EstadoProyecto?
    let fase: String?
    let responsable: String?
    let inicio: LocalDate?
    let fin: LocalDate?
    /// `sesiones_incluidas` de la ficha (si lo dice).
    let sesionesIncluidas: Int?
    /// `Portal.md` (o el Viaje de la propia ficha, si no tiene portal).
    let portal: PortalDocumento?
    /// `Incidencias.md` (si existe).
    let incidencias: RegistroIncidencias?
    /// Dónde está (o iría) `Incidencias.md`.
    let rutaIncidencias: VaultPath
    let tareas: [Tarea]
    /// Ficheros de `Materiales/` (sin lo privado).
    let materiales: [VaultPath]

    var abierto: Bool { estado?.abierto ?? true }

    /// «2 de 4 sesiones» (las del Viaje; si no hay Viaje, `nil`).
    var textoSesiones: String? {
        guard let p = portal, !p.sesiones.isEmpty else { return nil }
        let incluidas = p.incluidas
        return "\(p.hechas) de \(incluidas) \(incluidas == 1 ? "sesión" : "sesiones")"
    }

    var incidenciasAbiertas: [IncidenciaRegistrada] { incidencias?.abiertas ?? [] }

    /// Por qué está en riesgo (o `nil`): incidencia fuera de plazo, fin ya pasado, tareas vencidas o nada agendado.
    func riesgo(hoy: LocalDate, ahora: Date, zona: TimeZone) -> String? {
        guard abierto else { return nil }
        let fuera = incidencias?.fueraDePlazo(ahora: ahora, zona: zona) ?? []
        if !fuera.isEmpty { return fuera.count == 1 ? "1 incidencia fuera de plazo" : "\(fuera.count) incidencias fuera de plazo" }
        if let fin, fin < hoy { return "El fin era el \(OperacionComun.fecha(fin, hoy: hoy))" }
        let vencidas = tareas.filter { t in !(t.estado?.cerrada ?? false) && (t.vence.map { $0 < hoy } ?? false) }
        if !vencidas.isEmpty { return vencidas.count == 1 ? "1 tarea vencida" : "\(vencidas.count) tareas vencidas" }
        if estado == .enCurso, let p = portal, !p.sesiones.isEmpty, p.proxima(hoy: hoy).map({ !($0.estado?.agendada ?? false) }) ?? false {
            return "Ninguna sesión agendada"
        }
        return nil
    }
}

/// Un día de la carga de Entrega.
struct DiaCarga: Identifiable, Hashable, Sendable {
    var id: LocalDate { dia }
    let dia: LocalDate
    let esHoy: Bool
    let tope: Double
    /// Horas de tareas de Entrega planificadas ese día (solo las que tienen estimación).
    let horas: Double
    let tareas: [String]
    let sinEstimar: Int
    /// Sesiones de cliente agendadas ese día («Talleres Martín · S2»).
    let sesiones: [String]

    var pasaDelTope: Bool { tope > 0 && horas > tope }
    /// «2,5 h de 4».
    var textoCarga: String {
        "\(FormatoBase.cifra(horas, decimales: horas == horas.rounded() ? 0 : 1)) h de \(FormatoBase.cifra(tope))"
    }
}

/// Todo lo de la Operación de Entrega.
struct DatosEntrega: Sendable {
    let hoy: LocalDate
    /// La hora de ahora con el día de la carpeta (en el ejemplo, su día fijo): la de las cuentas atrás.
    let ahora: Date
    let zona: TimeZone
    let expedientes: [ExpedienteEntrega]
    let cronograma: Cronograma
    /// De lunes a viernes de esta semana.
    let carga: [DiaCarga]
    /// ENT-ONTIME (del núcleo) y ENT-INC (incidencias fuera de plazo, contadas aquí con su cuenta atrás).
    let cifras: [CifraOperacion]

    static let codigosCifras = ["ENT-ONTIME", "ENT-INC"]

    static func calcular(foto: VaultSnapshot, hoy: LocalDate, ahora reloj: Date = Date()) -> DatosEntrega {
        let config = ConfigMetricas.leer(foto.text(VaultPath(".tls/config.yaml")))
        let zona = TimeZone(identifier: config.zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
        let r = Reloj.deCarpeta(foto, zona: zona)
        let hoy = r.hoy
        let ahora = Self.ahora(hoy: hoy, reloj: reloj, zona: zona)
        let metricas = FotoMetricas(snapshot: foto, hoy: hoy)
        let expedientes = Self.expedientes(foto: foto, metricas: metricas, zona: zona)
        let evaluador = KPIEvaluador(foto: metricas, metas: MetasDocumento.leer(foto))
        var cifras = [CifraOperacion(evaluador.evaluar("ENT-ONTIME"))]
        cifras.append(Self.entInc(expedientes, evaluador: evaluador, ahora: ahora, zona: zona))
        return DatosEntrega(hoy: hoy, ahora: ahora, zona: zona, expedientes: expedientes,
                            cronograma: Cronograma.deEntrega(expedientes, hoy: hoy),
                            carga: Self.carga(metricas: metricas, expedientes: expedientes, hoy: hoy), cifras: cifras)
    }

    /// El día de la carpeta con la hora de ahora (en una carpeta de verdad, ahora mismo).
    static func ahora(hoy: LocalDate, reloj: Date, zona: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let h = cal.dateComponents([.hour, .minute], from: reloj)
        var c = DateComponents()
        c.year = hoy.year; c.month = hoy.month; c.day = hoy.day; c.hour = h.hour; c.minute = h.minute
        return cal.date(from: c) ?? reloj
    }

    /// Los proyectos de entrega (clase entrega, o en la carpeta de Entrega), con su portal, incidencias, tareas y
    /// materiales. Lo privado y lo archivado no entran.
    static func expedientes(foto: VaultSnapshot, metricas: FotoMetricas, zona: TimeZone) -> [ExpedienteEntrega] {
        let layout = foto.layout
        let entrega = layout.areaFolder(.entrega)
        func visible(_ p: VaultPath) -> Bool { !layout.isPrivate(p) && !layout.isArchived(p) && !VaultSnapshot.isTemplatePath(p) }
        var out: [ExpedienteEntrega] = []
        for p in metricas.proyectos where p.esDeEntrega || p.area == .entrega {
            guard visible(p.ruta), let carpeta = p.ruta.parent else { continue }
            let fm = foto.frontmatter(p.ruta)
            // Portal: en la carpeta del proyecto; si no, en «Portal Cliente/<slug>»; si no, el Viaje de la ficha.
            let candidatos = [carpeta.appending("Portal.md"), entrega.appending("Portal Cliente").appending(carpeta.name).appending("Portal.md")]
            var portal: PortalDocumento?
            for c in candidatos {
                if let real = foto.existing(c), visible(real), let t = foto.text(real) { portal = PortalDocumento.leer(t, ruta: real); break }
            }
            if portal == nil, let t = foto.text(p.ruta), MarkdownSections.content(of: PortalDocumento.seccionViaje, in: NoteDocument(text: t).body) != nil {
                let viaje = PortalDocumento.leer(t, ruta: p.ruta)
                if viaje.tieneViaje { portal = viaje }
            }
            let rutaInc = foto.existing(carpeta.appending("Incidencias.md")) ?? carpeta.appending("Incidencias.md")
            let incidencias = visible(rutaInc) ? foto.text(rutaInc).map { RegistroIncidencias.leer($0, ruta: rutaInc, zona: zona) } : nil
            let tareas = metricas.tareas.map(\.tarea).filter { t in
                t.proyecto == p.ruta || t.proyectoPorRuta == p.ruta
            }.sorted { ($0.numeroEntero ?? 0) < ($1.numeroEntero ?? 0) }
            let prefijo = carpeta.appending("Materiales").raw + "/"
            let materiales = foto.files.filter { $0.raw.hasPrefix(prefijo) && visible($0) && !$0.name.hasPrefix(".") }
                .sorted { $0.raw.localizedStandardCompare($1.raw) == .orderedAscending }
            let incluidas = fm.text("sesiones_incluidas").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            out.append(ExpedienteEntrega(
                ruta: p.ruta, carpeta: carpeta, nombre: p.nombre, empresa: OperacionComun.nombre(p.empresa),
                contacto: OperacionComun.nombre(fm.text("contacto")), estado: p.estado, fase: fm.text("fase"),
                responsable: OperacionComun.nombre(fm.text("responsable")), inicio: p.inicio, fin: p.fin,
                sesionesIncluidas: incluidas, portal: portal, incidencias: incidencias, rutaIncidencias: rutaInc,
                tareas: tareas, materiales: materiales))
        }
        let orden: [FotoMetricas.EstadoProyecto?] = [.enCurso, .sinEmpezar, .pausado, nil, .cerrado, .archivado]
        return out.sorted { a, b in
            let ia = orden.firstIndex(of: a.estado) ?? 9, ib = orden.firstIndex(of: b.estado) ?? 9
            return ia != ib ? ia < ib : a.nombre.localizedStandardCompare(b.nombre) == .orderedAscending
        }
    }

    /// ENT-INC: incidencias abiertas fuera de plazo. «Sin dato» si ningún expediente tiene registro de incidencias.
    static func entInc(_ expedientes: [ExpedienteEntrega], evaluador: KPIEvaluador, ahora: Date, zona: TimeZone) -> CifraOperacion {
        let base = evaluador.evaluar("ENT-INC")
        let registros = expedientes.compactMap(\.incidencias)
        guard !registros.isEmpty else {
            return CifraOperacion(codigo: "ENT-INC", indicador: base.indicador, valor: "Sin dato", meta: base.textoMeta, estado: .sinDato,
                                  palabra: "Sin dato", fuente: "Ningún expediente tiene aún registro de incidencias")
        }
        let n = registros.reduce(0) { $0 + $1.fueraDePlazo(ahora: ahora, zona: zona).count }
        let e = KPIEvaluador.estado(.cifra(Double(n)), meta: base.meta, alerta: base.alerta, sentido: .menos)
        let estado = OperacionComun.estado(e)
        let palabra = e.etiqueta
        let fuente = "Sale de \(registros.count == 1 ? "1 registro" : "\(registros.count) registros") de incidencias, con su cuenta atrás"
        return CifraOperacion(codigo: "ENT-INC", indicador: base.indicador, valor: "\(n)", meta: base.textoMeta, estado: estado,
                              palabra: palabra, fuente: fuente)
    }

    /// La carga de lunes a viernes: tareas de Entrega planificadas (con su estimación; sin ella no se inventan
    /// horas) y sesiones agendadas.
    static func carga(metricas: FotoMetricas, expedientes: [ExpedienteEntrega], hoy: LocalDate) -> [DiaCarga] {
        let semana = Agenda(foto: metricas).semana()
        return semana.dias.filter { !$0.finDeSemana }.map { d in
            let deEntrega = d.tareas.filter { $0.tarea.area == .entrega || metricas.layout.area(of: $0.tarea.ruta) == .entrega }
            let horas = deEntrega.compactMap(\.estimacionH).reduce(0, +)
            var sesiones: [String] = []
            for e in expedientes where e.abierto {
                for s in e.portal?.sesiones ?? [] where s.fecha == d.dia && (s.estado == .programada || s.estado == .kitListo) {
                    sesiones.append("\(e.empresa ?? e.nombre) · \(s.codigo)")
                }
            }
            return DiaCarga(dia: d.dia, esHoy: d.esHoy, tope: d.tope, horas: horas, tareas: deEntrega.map(\.tarea.titulo),
                            sinEstimar: deEntrega.filter { $0.estimacionH == nil }.count, sesiones: sesiones)
        }
    }
}

/// La revisión del viernes de Entrega (EN2): lo que se hizo, lo que viene, lo que se atasca y lo que esperamos del
/// cliente. Solo lee: no escribe nada.
struct RevisionViernes: Sendable {
    struct Linea: Identifiable, Hashable, Sendable {
        let id: String
        let texto: String
        let detalle: String?
        let ruta: VaultPath?
        let estado: TLSEstado
        /// La palabra de la pastilla («Hecha», «Fuera de plazo», «Vencida»…).
        let palabra: String
    }

    let titulo: String
    let hechas: [Linea]
    let proximas: [Linea]
    let atascos: [Linea]
    let delCliente: [Linea]

    var vacia: Bool { hechas.isEmpty && proximas.isEmpty && atascos.isEmpty && delCliente.isEmpty }

    static func de(_ d: DatosEntrega) -> RevisionViernes {
        let hoy = d.hoy
        let lunes = OperacionComun.lunes(de: hoy)
        let viernes = lunes.adding(days: 4)
        let siguiente = lunes.adding(days: 7)
        let finSiguiente = siguiente.adding(days: 4)
        var hechas: [Linea] = [], proximas: [Linea] = [], atascos: [Linea] = [], cliente: [Linea] = []
        for e in d.expedientes where e.abierto {
            let quien = e.empresa ?? e.nombre
            for s in e.portal?.sesiones ?? [] {
                guard let f = s.fecha else { continue }
                if s.estado == .hecha, f >= lunes, f <= viernes {
                    hechas.append(Linea(id: "\(e.ruta.raw)#\(s.codigo)", texto: "\(quien) · \(s.titulo)", detalle: FormatoFicha.fechaConDia(f, hoy: hoy),
                                        ruta: e.ruta, estado: .bien, palabra: "Hecha"))
                } else if s.estado != .hecha, s.estado != .noIncluida, f > viernes, f <= finSiguiente {
                    proximas.append(Linea(id: "\(e.ruta.raw)#\(s.codigo)", texto: "\(quien) · \(s.titulo)",
                                          detalle: "\(FormatoFicha.fechaConDia(f, hoy: hoy)) · \(s.estado?.rawValue ?? "Sin estado")",
                                          ruta: e.ruta, estado: s.estado == .kitListo ? .bien : .atencion,
                                          palabra: s.estado?.rawValue ?? "Sin estado"))
                }
            }
            for i in e.incidenciasAbiertas {
                let c = i.cuentaAtras(ahora: d.ahora, zona: d.zona)
                atascos.append(Linea(id: "\(e.ruta.raw)#\(i.id)", texto: "\(quien) · \(i.id) · \(i.descripcion ?? "Sin descripción")",
                                     detalle: c?.texto ?? "Sin plazo: falta la fecha o la gravedad", ruta: e.ruta,
                                     estado: c.map { $0.fueraDePlazo ? .mal : ($0.apurada ? .atencion : .bien) } ?? .sinDato,
                                     palabra: c.map { $0.fueraDePlazo ? "Fuera de plazo" : ($0.apurada ? "Apurada" : "En plazo") } ?? "Sin plazo"))
            }
            if let r = e.riesgo(hoy: hoy, ahora: d.ahora, zona: d.zona), !(e.incidencias?.fueraDePlazo(ahora: d.ahora, zona: d.zona).isEmpty == false) {
                atascos.append(Linea(id: "\(e.ruta.raw)#riesgo", texto: "\(quien) · \(e.nombre)", detalle: r, ruta: e.ruta, estado: .atencion,
                                     palabra: "En riesgo"))
            }
            for t in e.portal?.tareasCliente ?? [] where !t.hecha {
                let vencida = t.vence.map { $0 < hoy } ?? false
                cliente.append(Linea(id: "\(e.ruta.raw)#c\(t.linea)", texto: "\(quien) · \(t.texto)",
                                     detalle: t.vence.map { (vencida ? "venció el " : "vence el ") + FormatoFicha.fechaConDia($0, hoy: hoy) },
                                     ruta: e.ruta, estado: vencida ? .mal : .atencion, palabra: vencida ? "Vencida" : "Pendiente"))
            }
        }
        let titulo = "Semana del \(lunes.day) al \(viernes.day) de \(FormatoFicha.meses[viernes.month - 1])"
        return RevisionViernes(titulo: titulo, hechas: hechas, proximas: proximas, atascos: atascos, delCliente: cliente)
    }
}

/// Lo que escribe la Operación de Entrega, como la persona y con Deshacer.
@MainActor
enum AccionesEntrega {
    /// Cambia el estado de una sesión del Viaje (solo esa celda de su fila).
    static func cambiarSesion(_ s: SesionViaje, a nuevo: EstadoSesion, en portal: PortalDocumento, sesion: VaultSession,
                              deshacer: UndoManager?) async -> String? {
        guard let comando = portal.comandoEstado(s, a: nuevo) else { return "No encuentro el Viaje de este expediente." }
        do {
            let r = try await sesion.escribir(comando, aviso: "\(s.codigo) pasa a «\(nuevo.rawValue)»", deshacer: deshacer)
            return AccionesDireccion.conflicto(r, portal.ruta?.name ?? "Portal.md")
        } catch {
            return AccionesDireccion.texto(error)
        }
    }

    /// Una incidencia nueva al final de `Incidencias.md` (si no existe, se crea con su plantilla y la fila dentro), con
    /// su número INC-NNN y la fecha y hora de ahora. Responsable: la persona.
    static func nuevaIncidencia(_ e: ExpedienteEntrega, quien: String, email: String, tipo: String, severidad: SeveridadIncidencia,
                                descripcion: String, ahora: Date, zona: TimeZone, sesion: VaultSession,
                                deshacer: UndoManager?) async -> String? {
        guard let foto = await AccionesDireccion.fotoActual(sesion) else { return "No pude leer la carpeta." }
        let hoy = sesion.hoy
        let id = RegistroIncidencias.siguienteID(en: foto, hoy: hoy)
        let celdas = ["ID": id, "Fecha": RegistroIncidencias.textoFecha(ahora, zona: zona), "Quién reporta": quien, "Email": email,
                      "Tipo": tipo, "Severidad": severidad.rawValue, "Estado": EstadoIncidencia.recibida.rawValue,
                      "Descripción": descripcion, "Responsable": sesion.persona, "Resolución": ""]
        let existe = foto.existing(e.rutaIncidencias) != nil
        var ruta = e.rutaIncidencias
        var textoNuevo: String?
        if !existe {
            do {
                let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: sesion.persona, reloj: Reloj.deCarpeta(foto, zona: zona)))
                let nota = try motor.preparar(PlantillaMotor.Peticion(plantilla: "registro-de-incidencias", desde: e.ruta,
                                                                      contexto: ["proyecto": e.ruta], autor: sesion.autor))
                ruta = nota.ruta
                textoNuevo = nota.texto
            } catch {
                return AccionesDireccion.texto(error)
            }
        }
        guard let ops = RegistroIncidencias.operaciones(nueva: celdas, registro: ruta, existe: existe, textoNuevo: textoNuevo,
                                                        id: id, snapshot: foto, hoy: hoy) else {
            return "No encuentro la tabla de incidencias."
        }
        let plan = WritePlan(autor: sesion.autor, descripcion: "Nueva incidencia \(id)", ops: ops)
        do {
            let r = try await sesion.escribir(plan: plan, aviso: "\(id) apuntada · \(severidad.rawValue.lowercased()), responder en \(severidad.horasHabiles) h hábiles",
                                              deshacer: deshacer)
            return AccionesDireccion.conflicto(r, "Incidencias.md")
        } catch {
            return AccionesDireccion.texto(error)
        }
    }
}
