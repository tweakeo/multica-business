import Foundation

// El expediente de una empresa: todo lo que le ha pasado, leído junto (SISTEMAS §4.4, ficha de cliente). Es como se
// mira a un cliente antes de una reunión: cuánto nos ha dado, qué nos debe, qué hemos hablado y cuándo fue la última
// vez que existimos para él. La línea de tiempo se hace con hechos (un cobro, una reunión, un proyecto entregado),
// nunca con el registro de eventos.
//
// Sin dato es «Sin dato» (`nil`), nunca 0: sin facturas no hay «facturado»; sin oportunidades cerradas no hay
// conversión. Nada privado entra.
//
// Procedencia: lógica portada de PROG `core/expediente.js` (Manu): números, línea de tiempo (con la regla de quitar
// el «alta» cuando hay algo anterior) y alertas. Reescrita en Swift sobre las fichas y los CSV de la carpeta en vez de
// SQL. Ver docs/PROCEDENCIA.md.

/// Un hecho de la línea de tiempo de una empresa.
public struct HechoDeExpediente: Sendable, Hashable {
    public enum Clase: String, Sendable, Hashable {
        case alta, contacto, oportunidad, ganada, perdida, reunion, proyecto, entrega, factura, cobro
    }

    public let fecha: LocalDate
    public let clase: Clase
    public let texto: String
    public let detalle: String?
    public let ruta: VaultPath?
}

/// Algo que mirar en un expediente.
public struct AlertaDeExpediente: Sendable, Hashable {
    public enum Nivel: String, Sendable, Hashable { case mal, atencion }
    public let nivel: Nivel
    public let texto: String
    /// Qué hacer, en pocas palabras.
    public let que: String
    public let ruta: VaultPath?
}

/// Los números de un expediente (en céntimos). `nil` = sin dato.
public struct NumerosDeExpediente: Sendable, Hashable {
    public let facturado: Int?
    public let cobrado: Int?
    public let pendiente: Int?
    public let vencido: Int?
    public let ganadas: Int
    public let perdidas: Int
    public let abiertas: Int
    /// Valor de las oportunidades abiertas (las que lo dicen).
    public let valorAbierto: Int?
    /// Ganadas sobre cerradas, en %.
    public let conversion: Int?
    public let proyectosActivos: Int
    public let entregados: Int
    /// Primer hecho conocido.
    public let desde: LocalDate?
    /// Último hecho conocido.
    public let ultimoMovimiento: LocalDate?
    public let diasSinContacto: Int?
}

/// Todo lo de una empresa.
public struct Expediente: Sendable {
    public let empresa: FichaDominio
    public let contactos: [FichaDominio]
    public let oportunidades: [FichaDominio]
    public let proyectos: [FichaDominio]
    public let reuniones: [FichaDominio]
    public let facturas: [FichaDominio]
    public let cobros: [FilaPago]
    /// Tareas abiertas de sus proyectos y oportunidades.
    public let tareas: [FichaDominio]
    public let conversaciones: [FichaDominio]
    public let linea: [HechoDeExpediente]
    public let alertas: [AlertaDeExpediente]
    public let numeros: NumerosDeExpediente

    /// El expediente de una empresa (`nil` si no es una empresa o es privada).
    public static func de(_ ruta: VaultPath, en l: LecturaDominio) -> Expediente? {
        guard let empresa = l.ficha(ruta), empresa.tipo == .organization, !empresa.privada else { return nil }
        let hoy = l.hoy
        func suyas(_ tipo: NoteKind, _ clave: String = "empresa") -> [FichaDominio] {
            l.que(apuntan: empresa.ruta, por: clave, tipo: tipo).filter { !$0.privada }
        }
        func apunta(_ f: FichaDominio, _ clave: String, a lista: [FichaDominio]) -> Bool {
            guard let d = l.relacion(f, clave) else { return false }
            return lista.contains { Invariantes.misma($0.ruta, d) }
        }
        let contactos = suyas(.contact)
        let oportunidades = suyas(.opportunity)
        var proyectos = suyas(.project)
        for p in l.fichas(.project) where !p.privada && !proyectos.contains(p) && apunta(p, "oportunidad", a: oportunidades) {
            proyectos.append(p)
        }
        let reuniones = l.fichas(.meeting).filter { m in
            !m.privada && (apunta(m, "empresa", a: [empresa]) || apunta(m, "oportunidad", a: oportunidades) || apunta(m, "proyecto", a: proyectos))
        }
        var facturas = suyas(.invoice)
        for f in l.facturas where !f.privada && !facturas.contains(f) && (apunta(f, "oportunidad", a: oportunidades) || apunta(f, "proyecto", a: proyectos)) {
            facturas.append(f)
        }
        let emitidas = facturas.filter { esEmitida($0) }
        // Cobros confirmados de sus facturas o de sus proyectos.
        let cobros = l.pagos.filter { p in
            guard p.esCobroConfirmado else { return false }
            if let d = p.documento, emitidas.contains(where: { f in [f.texto("numero"), f.uid].compactMap { $0 }.contains { TextFolding.fold($0) == TextFolding.fold(d) } }) {
                return true
            }
            if let pr = p.proyecto, let f = l.buscar(pr, tipo: .project), proyectos.contains(f) { return true }
            return false
        }
        let tareas = l.fichas(.task).filter { t in
            guard !t.privada, !(t.estado.flatMap { EstadoTarea(leyendo: $0) }?.cerrada ?? false) else { return false }
            return apunta(t, "proyecto", a: proyectos) || apunta(t, "oportunidad", a: oportunidades) || apunta(t, "empresa", a: [empresa])
                || proyectos.contains { p in p.ruta.parent.map { t.ruta.isDescendant(of: $0) } == true }
        }
        let conversaciones = l.fichas(.conversation).filter { !$0.privada && apunta($0, "contacto", a: contactos) }

        // MARK: Números
        func cobradoDe(_ f: FichaDominio) -> Int {
            let claves = [f.texto("numero"), f.uid].compactMap { $0 }.map(TextFolding.fold)
            return cobros.filter { p in p.documento.map { claves.contains(TextFolding.fold($0)) } ?? false }.compactMap(\.centimos).reduce(0, +)
        }
        func total(_ f: FichaDominio) -> Int? { f.centimos("total") ?? f.centimos("base") }
        var facturado: Int?, cobrado: Int?, pendiente: Int?, vencido: Int?
        if !emitidas.isEmpty {
            facturado = emitidas.compactMap(total).reduce(0, +)
            cobrado = cobros.compactMap(\.centimos).reduce(0, +)
            var pend = 0, venc = 0
            for f in emitidas {
                guard let t = total(f), TextFolding.fold(f.estado ?? "") != "cobrada" else { continue }
                let falta = max(t - cobradoDe(f), 0)
                pend += falta
                if let v = f.fecha("vence"), v < hoy { venc += falta }
            }
            pendiente = pend
            vencido = venc
        }
        let estado = { (f: FichaDominio) in LecturaDominio.estadoOportunidad(f.estado) }
        let ganadas = oportunidades.filter { estado($0) == "Ganada" }
        let perdidas = oportunidades.filter { estado($0) == "Perdida" }
        let abiertas = oportunidades.filter { !["Ganada", "Perdida"].contains(estado($0) ?? "") }
        let valores = abiertas.compactMap { $0.centimos("valor") }
        let cerradas = ganadas.count + perdidas.count
        let estadoP = { (f: FichaDominio) in LecturaDominio.estadoProyecto(f.estado) }

        // MARK: Línea de tiempo
        var linea: [HechoDeExpediente] = []
        func meter(_ d: LocalDate?, _ c: HechoDeExpediente.Clase, _ t: String, _ det: String? = nil, _ r: VaultPath? = nil) {
            guard let d else { return }
            linea.append(HechoDeExpediente(fecha: d, clase: c, texto: t, detalle: det, ruta: r))
        }
        meter(empresa.fecha("creada"), .alta, "Entra en la carpeta", empresa.texto("tipo"))
        for c in contactos { meter(c.fecha("creada"), .contacto, "Contacto · \(c.nombre)", c.texto("cargo"), c.ruta) }
        for o in oportunidades {
            let valor = o.centimos("valor").map(Euros.texto)
            meter(o.fecha("creada") ?? o.fecha("entrada"), .oportunidad, "Oportunidad · \(o.nombre)", valor, o.ruta)
            if let cerrada = o.fecha("cerrada") {
                if estado(o) == "Ganada" { meter(cerrada, .ganada, "Ganada · \(o.nombre)", valor, o.ruta) }
                if estado(o) == "Perdida" { meter(cerrada, .perdida, "Perdida · \(o.texto("motivo_perdida") ?? "sin motivo")", valor, o.ruta) }
            }
        }
        for m in reuniones { meter(m.fecha("fecha"), .reunion, "Reunión · \(m.nombre)", m.texto("tipo"), m.ruta) }
        for p in proyectos {
            meter(p.fecha("inicio") ?? p.fecha("creada"), .proyecto, "Proyecto · \(p.nombre)", nil, p.ruta)
            if estadoP(p) == "Cerrado", let fin = p.fecha("fecha_cierre") ?? p.fecha("fin") {
                meter(fin, .entrega, "Entregado · \(p.nombre)", nil, p.ruta)
            }
        }
        for f in emitidas {
            let cobrada = TextFolding.fold(f.estado ?? "") == "cobrada" || (total(f).map { cobradoDe(f) >= $0 } ?? false)
            meter(f.fecha("fecha"), .factura, "Factura \(f.texto("numero") ?? f.nombre)",
                  [total(f).map(Euros.texto), cobrada ? "cobrada" : nil].compactMap { $0 }.joined(separator: " · "), f.ruta)
        }
        for p in cobros { meter(p.fecha, .cobro, "Cobro · \(p.documento ?? p.id)", p.centimos.map(Euros.texto), nil) }
        linea.sort { $0.fecha > $1.fecha }
        // El alta en la carpeta no es cuándo apareció el cliente (en lo importado es el día de la copia): si hay algo
        // anterior, el alta se cae; si no hay nada más, es lo único que se sabe y se queda.
        if let i = linea.firstIndex(where: { $0.clase == .alta }), i != linea.count - 1 { linea.remove(at: i) }

        // MARK: Alertas
        var alertas: [AlertaDeExpediente] = []
        if let v = vencido, v > 0 {
            alertas.append(AlertaDeExpediente(nivel: .mal, texto: "\(Euros.texto(v)) vencidos sin cobrar", que: "Reclamar hoy", ruta: nil))
        }
        for p in proyectos where !["Cerrado", "Archivado"].contains(estadoP(p) ?? "") {
            if let fin = p.fecha("fin"), fin < hoy {
                alertas.append(AlertaDeExpediente(nivel: .mal, texto: "«\(p.nombre)» está fuera de fecha", que: "Replantear el plazo con el cliente", ruta: p.ruta))
            }
        }
        for o in abiertas where estado(o) != "Pausada" {
            let ultima = ([o.fecha("creada"), o.fecha("aceptada")] + reuniones.filter { apunta($0, "oportunidad", a: [o]) }.map { $0.fecha("fecha") })
                .compactMap { $0 }.filter { $0 <= hoy }.max()
            if let u = ultima {
                let dias = BandejaDeDecisiones.dias(desde: u, hasta: hoy)
                if dias >= 14 {
                    alertas.append(AlertaDeExpediente(nivel: .atencion, texto: "«\(o.nombre)» lleva \(dias) días quieta",
                                                      que: "Un toque de seguimiento o cerrarla", ruta: o.ruta))
                }
            }
        }
        let esCliente = (empresa.propiedades.properties.first { $0.key == "relacion" }?.value.displayText ?? "").lowercased().contains("cliente")
        if contactos.isEmpty && esCliente {
            alertas.append(AlertaDeExpediente(nivel: .atencion, texto: "No hay ningún contacto ligado a esta empresa",
                                              que: "Ligar a la persona con la que se habla", ruta: nil))
        }
        let ultimo = linea.first?.fecha
        let numeros = NumerosDeExpediente(
            facturado: facturado, cobrado: cobrado, pendiente: pendiente, vencido: vencido,
            ganadas: ganadas.count, perdidas: perdidas.count, abiertas: abiertas.count,
            valorAbierto: valores.isEmpty ? nil : valores.reduce(0, +),
            conversion: cerradas > 0 ? Int((Double(ganadas.count) / Double(cerradas) * 100).rounded()) : nil,
            proyectosActivos: proyectos.filter { ["Sin empezar", "En curso"].contains(estadoP($0) ?? "") }.count,
            entregados: proyectos.filter { estadoP($0) == "Cerrado" }.count,
            desde: linea.last?.fecha, ultimoMovimiento: ultimo,
            diasSinContacto: ultimo.map { BandejaDeDecisiones.dias(desde: $0, hasta: hoy) })
        return Expediente(empresa: empresa, contactos: contactos, oportunidades: oportunidades, proyectos: proyectos, reuniones: reuniones,
                          facturas: facturas, cobros: cobros, tareas: tareas, conversaciones: conversaciones, linea: linea,
                          alertas: alertas, numeros: numeros)
    }

    /// Una factura cuenta en los números cuando ya se emitió (tiene número o un estado posterior al borrador).
    static func esEmitida(_ f: FichaDominio) -> Bool {
        let e = TextFolding.fold(f.estado ?? "")
        if ["borrador", "rectificada"].contains(e) { return false }
        return f.texto("numero") != nil || ["emitida", "enviada", "cobrada"].contains(e)
    }
}
