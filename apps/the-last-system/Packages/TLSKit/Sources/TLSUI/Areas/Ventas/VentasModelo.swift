import Foundation
import TLSCore
import TLSDesign

// La Operación de Ventas (PLAN §6.5, SISTEMAS §4.2 y VE2): el CRM en tablero de Prospecto a Ganada (número, euros y
// conversión por columna, «quieta 9 d»; soltar en Ganada sin cobro confirmado se bloquea con el mensaje de VEN-07 y
// se ofrece Aceptada), el seguimiento a 7, 14, 21 y 30 días de cada propuesta enviada y los contactos y empresas.
// Puro: lo calcula `DatosVentas.calcular` con la foto de la carpeta, sin nada privado.

/// Las columnas del tablero, en orden. Perdida y Pausada van aparte (no son un paso hacia Ganada).
enum EtapaCRM: String, CaseIterable, Sendable, Hashable {
    case prospecto = "Prospecto"
    case diagnostico = "Diagnóstico"
    case propuesta = "Propuesta"
    case aceptada = "Aceptada"
    case ganada = "Ganada"

    var indice: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var siguiente: EtapaCRM? { indice + 1 < Self.allCases.count ? Self.allCases[indice + 1] : nil }
    var anterior: EtapaCRM? { indice > 0 ? Self.allCases[indice - 1] : nil }

    init?(_ e: FotoMetricas.EstadoOportunidad?) {
        switch e {
        case .prospecto: self = .prospecto
        case .diagnostico: self = .diagnostico
        case .propuesta: self = .propuesta
        case .aceptada: self = .aceptada
        case .ganada: self = .ganada
        default: return nil
        }
    }
}

/// Una oportunidad en el tablero.
struct TarjetaCRM: Identifiable, Hashable, Sendable {
    var id: VaultPath { ruta }
    let ruta: VaultPath
    let nombre: String
    let estado: FotoMetricas.EstadoOportunidad?
    let empresa: String?
    let servicio: String?
    let valor: Double?
    let probabilidad: Double?
    let diasQuieta: Int?
    let responsable: String?

    /// VEN-STALE7: abierta y sin contacto desde hace 7 días o más.
    var quieta: Bool { (estado.map { !$0.cerrada } ?? true) && (diasQuieta ?? 0) >= 7 }
    /// «quieta 9 d».
    var textoQuieta: String? { quieta ? "quieta \(diasQuieta ?? 0) d" : nil }
    /// «150 € · 30 %».
    var cifras: String {
        [valor.map { FormatoBase.euros($0, redondo: $0 == $0.rounded()) } ?? "Sin valor",
         probabilidad.map { "\(FormatoBase.cifra($0, decimales: 0)) %" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Una columna con su número, sus euros y su conversión.
struct ColumnaCRM: Identifiable, Hashable, Sendable {
    var id: String { etapa.rawValue }
    let etapa: EtapaCRM
    let tarjetas: [TarjetaCRM]
    /// Suma del valor (`nil` = ninguna tarjeta tiene valor: «Sin dato», nunca 0).
    let total: Double?
    /// % que pasa a la siguiente columna (en Ganada: ganadas sobre cerradas). `nil` = sin dato.
    let conversion: Int?

    var numero: Int { tarjetas.count }
    var textoTotal: String { total.map { FormatoBase.euros($0, redondo: $0 == $0.rounded()) } ?? "Sin dato" }
    var textoConversion: String {
        let que = etapa == .ganada ? "ganadas sobre cerradas" : "pasa a \(etapa.siguiente?.rawValue ?? "")"
        return conversion.map { "\($0) % \(que)" } ?? "Sin dato de conversión"
    }
    var etiquetaAccesible: String {
        "\(etapa.rawValue): \(numero == 1 ? "1 oportunidad" : "\(numero) oportunidades"), \(textoTotal), \(textoConversion)"
    }
}

/// El tablero entero.
struct TableroCRM: Hashable, Sendable {
    let columnas: [ColumnaCRM]
    let perdidas: [TarjetaCRM]
    let pausadas: [TarjetaCRM]

    func columna(_ e: EtapaCRM) -> ColumnaCRM? { columnas.first { $0.etapa == e } }
    var tarjetas: [TarjetaCRM] { columnas.flatMap(\.tarjetas) + perdidas + pausadas }
    func tarjeta(_ ruta: VaultPath) -> TarjetaCRM? { tarjetas.first { $0.ruta == ruta } }

    /// Las oportunidades de la carpeta (sin lo privado: `FotoMetricas` ya lo quita). Ganadas, solo las de los
    /// últimos 90 días (las antiguas no llenan el tablero, pero sí cuentan para la conversión).
    static func de(_ oportunidades: [FotoMetricas.Oportunidad], hoy: LocalDate, soloResponsable: String? = nil) -> TableroCRM {
        let todas = oportunidades
        let visibles = todas.filter { o in
            guard let r = soloResponsable else { return true }
            return TextFolding.fold(OperacionComun.nombre(o.responsable) ?? "") == TextFolding.fold(r)
        }
        func tarjeta(_ o: FotoMetricas.Oportunidad) -> TarjetaCRM {
            TarjetaCRM(ruta: o.ruta, nombre: o.nombre, estado: o.estado, empresa: OperacionComun.nombre(o.empresa),
                       servicio: OperacionComun.nombre(o.servicio), valor: o.valor, probabilidad: o.probabilidad,
                       diasQuieta: o.abierta ? o.diasQuieta(hoy: hoy) : nil, responsable: OperacionComun.nombre(o.responsable))
        }
        // Hasta qué paso llegó cada una (una perdida o pausada, por lo que dejó escrito).
        func alcanzo(_ o: FotoMetricas.Oportunidad) -> Int {
            if let e = EtapaCRM(o.estado) { return e.indice }
            if o.aceptada != nil { return EtapaCRM.aceptada.indice }
            if o.conPropuesta { return EtapaCRM.propuesta.indice }
            return EtapaCRM.prospecto.indice
        }
        let ganadas = todas.filter { $0.estado == .ganada }.count
        let perdidas = todas.filter { $0.estado == .perdida }.count
        var columnas: [ColumnaCRM] = []
        for e in EtapaCRM.allCases {
            var lista = visibles.filter { EtapaCRM($0.estado) == e }
            if e == .ganada {
                lista = lista.filter { o in (o.cerrada ?? o.aceptada ?? o.creada).map { $0 >= hoy.adding(days: -90) } ?? true }
            }
            let tarjetas = lista.map(tarjeta).sorted { a, b in
                if (a.diasQuieta ?? 0) != (b.diasQuieta ?? 0) { return (a.diasQuieta ?? 0) > (b.diasQuieta ?? 0) }
                return a.nombre.localizedStandardCompare(b.nombre) == .orderedAscending
            }
            let valores = tarjetas.compactMap(\.valor)
            let conversion: Int?
            if e == .ganada {
                conversion = ganadas + perdidas > 0 ? Int((Double(ganadas) / Double(ganadas + perdidas) * 100).rounded()) : nil
            } else {
                let aqui = todas.filter { alcanzo($0) >= e.indice }.count
                let siguen = todas.filter { alcanzo($0) >= e.indice + 1 }.count
                conversion = aqui > 0 ? Int((Double(siguen) / Double(aqui) * 100).rounded()) : nil
            }
            columnas.append(ColumnaCRM(etapa: e, tarjetas: tarjetas, total: valores.isEmpty ? nil : valores.reduce(0, +),
                                       conversion: conversion))
        }
        return TableroCRM(columnas: columnas,
                          perdidas: visibles.filter { $0.estado == .perdida }.map(tarjeta),
                          pausadas: visibles.filter { $0.estado == .pausada }.map(tarjeta))
    }
}

/// Qué pasa al soltar una tarjeta en una columna.
enum ResultadoSoltar: Equatable, Sendable {
    /// Se puede escribir (con el comando que cambia solo `estado`).
    case escribir(CommandBus.Comando)
    /// No se escribe (VEN-07…): el mensaje del dominio y lo que se ofrece en su lugar.
    case bloqueado(mensaje: String, alternativa: AlternativaCRM?)
    /// Ya estaba ahí.
    case nada
}

/// La salida que ofrece un bloqueo («Dejarla en Aceptada»).
struct AlternativaCRM: Equatable, Sendable {
    let titulo: String
    let comando: CommandBus.Comando
}

extension TableroCRM {
    /// Comprueba con las invariantes del dominio si `tarjeta` puede ir a `etapa` (como `autor`). Soltar en Ganada sin
    /// un cobro confirmado por una persona se bloquea (VEN-07) y se ofrece «Dejarla en Aceptada».
    static func soltar(_ tarjeta: TarjetaCRM, en etapa: EtapaCRM, invariantes: Invariantes?, autor: Autor) -> ResultadoSoltar {
        guard EtapaCRM(tarjeta.estado) != etapa else { return .nada }
        let poner = [Property(key: "estado", value: .text(etapa.rawValue))]
        if let invariantes {
            let r = invariantes.comprobar(.propiedades(tarjeta.ruta, poner: poner, quitar: []), autor: autor)
            if r.veredicto == .bloqueado {
                let alt = r.bloqueos.flatMap(\.alternativas).first { $0.recomendada } ?? r.bloqueos.flatMap(\.alternativas).first
                var alternativa: AlternativaCRM?
                if let alt, case .poner(let ruta, let props) = alt.accion {
                    alternativa = AlternativaCRM(titulo: alt.titulo, comando: .cambiarPropiedades(ruta, poner: props, quitar: []))
                }
                return .bloqueado(mensaje: r.mensaje ?? "Este cambio no se puede guardar.", alternativa: alternativa)
            }
        }
        return .escribir(.cambiarPropiedades(tarjeta.ruta, poner: poner, quitar: []))
    }
}

/// El seguimiento de una propuesta enviada (VE2): a los 7, 14, 21 y 30 días.
struct SeguimientoPropuesta: Identifiable, Hashable, Sendable {
    var id: VaultPath { oportunidad }
    let oportunidad: VaultPath
    let nombre: String
    let contacto: String?
    let empresa: VaultPath?
    let servicio: String?
    /// La propuesta y cuándo se envió.
    let propuesta: VaultPath
    let enviada: LocalDate
    let dias: Int
    /// El día de seguimiento que toca hoy o ya pasó y aún no se ha preparado (7, 14, 21 o 30).
    let toca: Int?
    /// El siguiente día y su fecha (si quedan).
    let proximo: (dia: Int, fecha: LocalDate)?
    /// Los días ya preparados como tarea.
    let preparados: [Int]

    static func == (a: SeguimientoPropuesta, b: SeguimientoPropuesta) -> Bool {
        a.oportunidad == b.oportunidad && a.toca == b.toca && a.preparados == b.preparados && a.dias == b.dias
    }
    func hash(into h: inout Hasher) { h.combine(oportunidad); h.combine(toca); h.combine(preparados) }

    static let pasos = [7, 14, 21, 30]

    /// Qué toca cada día (SISTEMAS VE2, plantilla «Seguimiento»).
    static func queToca(_ dia: Int) -> String {
        switch dia {
        case 7: "Recordar la propuesta con una sola pregunta"
        case 14: "Aportar algo útil: un dato, un caso o una respuesta a su duda"
        case 21: "Última pregunta directa: ¿lo dejamos para más adelante?"
        default: "Proponer pasarla a Perdida, con su motivo"
        }
    }

    /// «Seguimiento día 7 · Javier Ortega · Renta».
    func tituloTarea(_ dia: Int) -> String { "Seguimiento día \(dia) · \(nombre)" }

    /// El borrador del mensaje (determinista: los asistentes llegan en F4). **Nunca se envía solo.**
    func borrador(_ dia: Int, hoy: LocalDate) -> String {
        let nombrePila = contacto.map { $0.components(separatedBy: " ").first ?? $0 } ?? "hola"
        let que = servicio.map { "de \($0) " } ?? ""
        let cuando = FormatoFicha.fechaCorta(enviada, hoy: hoy)
        let mensaje: String
        switch dia {
        case 7:
            mensaje = "Hola, \(nombrePila): te escribo por la propuesta \(que)que te envié el \(cuando). ¿Has podido verla? Si te encaja, la dejamos en marcha esta semana."
        case 14:
            mensaje = "Hola, \(nombrePila): por si te ayuda a decidir sobre la propuesta \(que)del \(cuando), te cuento cómo lo hemos resuelto con otros clientes parecidos. Si tienes alguna duda, la vemos en diez minutos."
        case 21:
            mensaje = "Hola, \(nombrePila): no quiero insistir más de la cuenta con la propuesta \(que)del \(cuando). ¿La dejamos para más adelante o la retomamos ahora?"
        default:
            mensaje = "Han pasado 30 días desde la propuesta \(que)del \(cuando) sin respuesta. Propuesta: pasarla a Perdida y apuntar el motivo."
        }
        return """
        Qué toca el día \(dia): \(Self.queToca(dia)).

        Borrador del mensaje (revísalo y envíalo tú; nunca se envía solo):

        > \(mensaje)
        """
    }

    /// La tarea con el borrador (para la persona; enviar es cosa suya).
    func nuevaTarea(_ dia: Int, hoy: LocalDate, persona: String, autor: Autor) -> NuevaTarea {
        NuevaTarea(titulo: tituloTarea(dia), area: .ventas, oportunidad: oportunidad, empresa: empresa, responsable: persona,
                   estado: .porHacer, planificada: hoy, descripcion: borrador(dia, hoy: hoy), origen: "manual", autor: autor,
                   propiedades: [Property(key: "capacidad", value: .text("VEN-08"))])
    }

    /// Las propuestas enviadas de las oportunidades en Propuesta, con lo que toca de su seguimiento.
    static func de(lectura: LecturaDominio, tareas: [Tarea], hoy: LocalDate) -> [SeguimientoPropuesta] {
        let layout = lectura.layout
        var out: [SeguimientoPropuesta] = []
        let propuestas = lectura.fichas(.proposal).filter { !$0.privada && !layout.isArchived($0.ruta) }
        for o in lectura.oportunidades where !o.privada && !layout.isArchived(o.ruta) {
            guard LecturaDominio.estadoOportunidad(o.estado) == "Propuesta" else { continue }
            let k = TextFolding.pathKey(o.ruta.raw)
            let suyas = propuestas.filter { p in
                lectura.relacion(p, "oportunidad").map { TextFolding.pathKey($0.raw) == k } ?? false
            }
            // La última enviada (con fecha y que no sea un borrador).
            let enviadas = suyas.compactMap { p -> (VaultPath, LocalDate)? in
                guard let f = p.fecha("fecha") ?? p.fecha("enviada"), f <= hoy else { return nil }
                if let e = p.estado, ["borrador", "rechazada"].contains(TextFolding.fold(e)) { return nil }
                return (p.ruta, f)
            }
            guard let ultima = enviadas.max(by: { $0.1 < $1.1 }) else { continue }
            let dias = RangoFechas.diasEntre(ultima.1, hoy)
            let deEsta = tareas.filter { $0.oportunidad.map { TextFolding.pathKey($0.raw) == k } ?? false }
            let preparados = pasos.filter { d in deEsta.contains { $0.titulo.hasPrefix("Seguimiento día \(d) ") } }
            let vencidos = pasos.filter { $0 <= dias }
            let toca = vencidos.last.flatMap { preparados.contains($0) ? nil : $0 }
            let siguiente = pasos.first { $0 > dias }.map { ($0, ultima.1.adding(days: $0)) }
            out.append(SeguimientoPropuesta(oportunidad: o.ruta, nombre: o.nombre,
                                            contacto: OperacionComun.nombre(o.texto("contacto")),
                                            empresa: lectura.relacion(o, "empresa"), servicio: OperacionComun.nombre(o.texto("servicio")),
                                            propuesta: ultima.0, enviada: ultima.1, dias: dias, toca: toca, proximo: siguiente,
                                            preparados: preparados))
        }
        return out.sorted { a, b in
            if (a.toca != nil) != (b.toca != nil) { return a.toca != nil }
            return a.dias > b.dias
        }
    }
}

/// Contactos o empresas por estado (para el directorio de Ventas).
struct DirectorioVentas: Hashable, Sendable {
    let total: Int
    /// («Activo», 3), («Interesado», 5)… y «Sin estado».
    let porEstado: [EstadoContado]

    struct EstadoContado: Hashable, Sendable, Identifiable {
        var id: String { estado }
        let estado: String
        let numero: Int
    }

    static func de(_ estados: [String?]) -> DirectorioVentas {
        var cuenta: [String: Int] = [:]
        for e in estados {
            let t = e?.trimmingCharacters(in: .whitespaces)
            cuenta[(t?.isEmpty ?? true) ? "Sin estado" : FormatoFicha.capital(t!), default: 0] += 1
        }
        let lista = cuenta.map { EstadoContado(estado: $0.key, numero: $0.value) }
            .sorted { $0.numero != $1.numero ? $0.numero > $1.numero : $0.estado < $1.estado }
        return DirectorioVentas(total: estados.count, porEstado: lista)
    }
}

/// Todo lo de la Operación de Ventas.
struct DatosVentas: Sendable {
    let hoy: LocalDate
    let tablero: TableroCRM
    let seguimientos: [SeguimientoPropuesta]
    let contactos: DirectorioVentas
    let empresas: DirectorioVentas
    /// VEN-STALE7 y VEN-PIPE (del evaluador del núcleo).
    let cifras: [CifraOperacion]

    static let codigosCifras = ["VEN-STALE7", "VEN-PIPE"]

    static func calcular(foto: VaultSnapshot, hoy: LocalDate) -> DatosVentas {
        let r = Reloj.deCarpeta(foto)
        let hoy = r.hoy
        let metricas = FotoMetricas(snapshot: foto, hoy: hoy)
        let lectura = LecturaDominio(snapshot: foto, reloj: r)
        let evaluador = KPIEvaluador(foto: metricas, metas: MetasDocumento.leer(foto))
        let empresas = lectura.fichas(.organization).filter { !$0.privada && !foto.layout.isArchived($0.ruta) }
        return DatosVentas(hoy: hoy, tablero: TableroCRM.de(metricas.oportunidades, hoy: hoy),
                           seguimientos: SeguimientoPropuesta.de(lectura: lectura, tareas: metricas.tareas.map(\.tarea), hoy: hoy),
                           contactos: DirectorioVentas.de(metricas.contactos.map(\.estado)),
                           empresas: DirectorioVentas.de(empresas.map(\.estado)),
                           cifras: codigosCifras.map { CifraOperacion(evaluador.evaluar($0)) })
    }
}

/// Lo que escribe la Operación de Ventas, como la persona, por el dominio y con Deshacer.
@MainActor
enum AccionesVentas {
    /// Mover una oportunidad de columna. Antes de escribir se pregunta al dominio: si VEN-07 bloquea, no se escribe
    /// nada y se devuelve el bloqueo con «Dejarla en Aceptada».
    static func mover(_ t: TarjetaCRM, a etapa: EtapaCRM, sesion: VaultSession, deshacer: UndoManager?) async -> ResultadoMover {
        guard let foto = await AccionesDireccion.fotoActual(sesion) else { return .error("No pude leer la carpeta.") }
        switch TableroCRM.soltar(t, en: etapa, invariantes: Invariantes(snapshot: foto), autor: sesion.autor) {
        case .nada:
            return .hecho
        case .bloqueado(let mensaje, let alternativa):
            return .bloqueado(mensaje: mensaje, alternativa: alternativa)
        case .escribir(let comando):
            do {
                let r = try await sesion.escribirConDominio(comando, aviso: "«\(t.nombre)» pasa a \(etapa.rawValue)", deshacer: deshacer)
                if let c = AccionesDireccion.conflicto(r.escritura, t.nombre) { return .error(c) }
                return .hecho
            } catch let e as DominioError {
                // Por si la carpeta cambió entre la pregunta y la escritura: el mismo bloqueo.
                let alt = e.resultado.bloqueos.flatMap(\.alternativas).first
                var alternativa: AlternativaCRM?
                if let alt, case .poner(let ruta, let props) = alt.accion {
                    alternativa = AlternativaCRM(titulo: alt.titulo, comando: .cambiarPropiedades(ruta, poner: props, quitar: []))
                }
                return .bloqueado(mensaje: e.localizedDescription, alternativa: alternativa)
            } catch {
                return .error(AccionesDireccion.texto(error))
            }
        }
    }

    /// La salida de un bloqueo («Dejarla en Aceptada»).
    static func aplicar(_ a: AlternativaCRM, nombre: String, sesion: VaultSession, deshacer: UndoManager?) async -> String? {
        do {
            let r = try await sesion.escribirConDominio(a.comando, aviso: "«\(nombre)»: \(a.titulo.lowercased())", deshacer: deshacer)
            return AccionesDireccion.conflicto(r.escritura, nombre)
        } catch {
            return AccionesDireccion.texto(error)
        }
    }

    /// «Preparar seguimiento»: una tarea con el borrador del mensaje del día que toca. Enviar, nunca.
    static func prepararSeguimiento(_ s: SeguimientoPropuesta, dia: Int, sesion: VaultSession, deshacer: UndoManager?) async -> String? {
        guard let foto = await AccionesDireccion.fotoActual(sesion) else { return "No pude leer la carpeta." }
        do {
            let nota = try TaskStore(snapshot: foto).crear(s.nuevaTarea(dia, hoy: sesion.hoy, persona: sesion.persona, autor: sesion.autor))
            let r = try await sesion.escribir(plan: nota.plan, aviso: "Preparé el seguimiento del día \(dia) de «\(s.nombre)»: está en Tareas. Enviarlo es cosa tuya.",
                                              deshacer: deshacer)
            return AccionesDireccion.conflicto(r, s.nombre)
        } catch {
            return AccionesDireccion.texto(error)
        }
    }
}

/// Lo que pasó al mover una tarjeta.
enum ResultadoMover: Equatable {
    case hecho
    case bloqueado(mensaje: String, alternativa: AlternativaCRM?)
    case error(String)
}
