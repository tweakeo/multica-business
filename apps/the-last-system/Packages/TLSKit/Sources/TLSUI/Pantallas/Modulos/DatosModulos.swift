import Foundation
import TLSCore
import TLSDesign

// Lo que enseña cada módulo de inicio, calculado de una vez con la foto de la carpeta (fuera del hilo principal):
// sale de las métricas (`PanelMetricas`), del banco (`Tesoreria`, `Conciliador`) y del calendario fiscal. Nada se
// inventa: sin fuente, el módulo dice «Sin dato» y por qué; con fuente y nada que contar, lo dice con palabras
// («Ninguno»), nunca con un 0 de relleno. Lo privado no entra (las métricas y el banco ya lo dejan fuera).

/// Adónde lleva el enlace de un módulo.
struct EnlaceModulo: Sendable, Hashable {
    let titulo: String
    let destino: Destino
}

/// La cifra de un módulo pequeño o mediano. Si no hay cifra, `vacio` dice por qué.
struct CifraModulo: Sendable, Hashable {
    var cifra: String?
    var linea: String?
    var estado: TLSEstado?
    var palabra: String?
    var vacio: String?
    var enlace: EnlaceModulo?
    /// «Sale de …».
    var fuente: String

    static func sinDato(_ motivo: String, fuente: String, enlace: EnlaceModulo? = nil) -> CifraModulo {
        CifraModulo(cifra: nil, linea: nil, estado: nil, palabra: nil, vacio: motivo, enlace: enlace, fuente: fuente)
    }
}

/// Algo de hoy: una tarea planificada o que vence, una reunión, una rutina, una cita o un cobro previsto.
struct ElementoDia: Sendable, Hashable, Identifiable {
    enum Tipo: String, Sendable, Hashable {
        case tarea, vence, reunion, rutina, cita, cobro

        var texto: String {
            switch self {
            case .tarea: "Tarea"
            case .vence: "Vence hoy"
            case .reunion: "Reunión"
            case .rutina: "Rutina"
            case .cita: "Calendario"
            case .cobro: "Cobro previsto"
            }
        }
    }

    let id: String
    let tipo: Tipo
    /// «9:30», si la tiene.
    let hora: String?
    let minutos: Int?
    let titulo: String
    /// «T-0041».
    let codigo: String?
    let area: AreaCode?
    /// Horas estimadas o duración («0,5 h»); `nil` = sin estimar (no se inventa).
    let horas: Double?
    let ruta: VaultPath?
    /// Además de planificada, vence hoy.
    let venceHoy: Bool

    var textoHoras: String? {
        horas.map { "\(FormatoBase.cifra($0, decimales: $0 == $0.rounded() ? 0 : 1)) h" }
    }
}

/// La caja para su módulo y su gráfica.
struct DatosCaja: Sendable, Hashable {
    let series: [RangoCaja: [PuntoCaja]]
    /// Céntimos; `nil` = Sin dato (falta el saldo de alguna cuenta o no hay cuentas).
    let saldo: Int?
    let runway: Runway
    /// Estado de FIN-RUNWAY frente a su meta y su alerta (del número clave).
    let estadoRunway: EstadoKPI?
    let cuentas: Int
    /// Último día con movimientos.
    let ultimo: LocalDate?
    let motivo: String?

    var saldoTexto: String { saldo.map { DineroExacto.euros($0) } ?? "Sin dato" }

    var runwayTexto: String? {
        runway.meses.map { "\(FormatoBase.cifra($0, decimales: 1)) meses de caja" }
    }

    var fuente: String {
        guard cuentas > 0 else { return "Sale de los extractos del banco" }
        let c = cuentas == 1 ? "1 cuenta" : "\(cuentas) cuentas"
        return "Sale de \(c)" + (ultimo.map { " · último movimiento el \($0.day) \(FormatoBase.meses[$0.month - 1])" } ?? "")
    }
}

/// Todo lo que enseñan los módulos de un inicio.
struct DatosModulos: Sendable {
    let hoy: LocalDate
    let caja: DatosCaja
    let ritmo: [RitmoArea]
    let semana: SemanaAgenda
    let cabe: [ElementoDia]
    let cifras: [ModuloID: CifraModulo]
    /// Texto del cuello («El cuello es 2 · Ventas: …») y su veredicto.
    let cuello: (texto: String, veredicto: String)?

    func cifra(_ m: ModuloID) -> CifraModulo {
        cifras[m] ?? .sinDato("Sin dato: este módulo aún no tiene de dónde leer.", fuente: "Sin fuente")
    }
}

extension DatosModulos {
    /// Calcula todo con la foto de la carpeta. `pendientes` = lo que espera tu decisión (la bandeja).
    static func calcular(foto: VaultSnapshot, panel: PanelMetricas, pendientes: Int, reloj: Reloj) -> DatosModulos {
        let hoy = panel.hoy
        let registros = RegistrosFinanzas(snapshot: foto)
        let tesoreria = Tesoreria(registros: registros, hoy: hoy)
        let caja = cajaDe(tesoreria, registros: registros, panel: panel)
        let cabe = elementosDeHoy(panel.semana, foto: panel.foto)
        var c: [ModuloID: CifraModulo] = [:]
        let banco = EnlaceModulo(titulo: "Ir al banco", destino: .banco(nil))

        // Finanzas
        let conciliador = Conciliador(registros: registros, reloj: Reloj(hoy: hoy, ahora: reloj.ahora, zona: reloj.zona))
        let entrantes = conciliador.propuestas.filter { $0.movimiento.importe > 0 }
        if registros.movimientos.isEmpty {
            c[.cobros] = .sinDato("Sin dato: aún no hay movimientos del banco. Importa un extracto.", fuente: "Sale de los extractos del banco",
                                  enlace: EnlaceModulo(titulo: "Importar extracto", destino: .banco(nil)))
        } else if let p = entrantes.first {
            let otros = entrantes.count - 1
            c[.cobros] = CifraModulo(cifra: "\(entrantes.count)",
                                     linea: "\(DineroExacto.euros(p.movimiento.importe)) de \(p.factura.tercero ?? "un cliente") · llegó el \(corta(p.movimiento.fecha))"
                                        + (otros > 0 ? " · y \(otros) más" : ""),
                                     estado: nil, palabra: nil, vacio: nil,
                                     enlace: EnlaceModulo(titulo: "Revisar", destino: .banco(nil)),
                                     fuente: "Sale de los extractos del banco")
        } else {
            c[.cobros] = CifraModulo(cifra: "Ninguno", linea: "Nada de lo que llegó al banco espera tu confirmación.",
                                     enlace: banco, fuente: "Sale de los extractos del banco")
        }
        if let n = tesoreria.sinConciliar {
            c[.sinConciliar] = CifraModulo(cifra: n == 0 ? "Ninguno" : "\(n)",
                                           linea: n == 0 ? "Todos los movimientos tienen su factura o gasto." : (n == 1 ? "movimiento sin su factura o gasto" : "movimientos sin su factura o gasto"),
                                           enlace: banco, fuente: "Sale de \(registros.movimientos.count) movimientos del banco")
        } else {
            c[.sinConciliar] = .sinDato("Sin dato: aún no hay movimientos del banco.", fuente: "Sale de los extractos del banco",
                                        enlace: EnlaceModulo(titulo: "Importar extracto", destino: .banco(nil)))
        }
        let pend = tesoreria.cobrosPendientes
        if registros.emitidas.isEmpty {
            c[.pendientes] = .sinDato("Sin dato: aún no hay facturas emitidas.", fuente: "Sale de las facturas emitidas")
            c[.cobrosVencidos] = .sinDato("Sin dato: aún no hay facturas emitidas.", fuente: "Sale de las facturas emitidas")
        } else {
            let total = pend.map(\.pendiente).reduce(0, +)
            c[.pendientes] = CifraModulo(cifra: pend.isEmpty ? "Ninguna" : "\(pend.count)",
                                         linea: pend.isEmpty ? "Todo lo emitido está cobrado." : "\(DineroExacto.euros(total)) por cobrar"
                                            + (pend.first.map { " · " + ($0.factura.numero ?? $0.factura.id) + ($0.factura.tercero.map { " · \($0)" } ?? "") } ?? ""),
                                         enlace: EnlaceModulo(titulo: "Ver facturas", destino: .base("facturas")),
                                         fuente: "Sale de \(registros.emitidas.count) facturas emitidas")
            let vencidas = tesoreria.cobrosVencidos
            let kpi = panel.evaluador.evaluar("FIN-AR")
            c[.cobrosVencidos] = CifraModulo(cifra: vencidas.isEmpty ? "Ninguno" : DineroExacto.euros(vencidas.map(\.pendiente).reduce(0, +)),
                                             linea: vencidas.isEmpty ? "Ninguna factura vencida sin cobrar." : (vencidas.count == 1 ? "1 factura vencida" : "\(vencidas.count) facturas vencidas"),
                                             estado: estado(kpi), palabra: palabra(kpi),
                                             enlace: EnlaceModulo(titulo: "Ver facturas", destino: .base("facturas")),
                                             fuente: "Sale de \(registros.emitidas.count) facturas emitidas")
        }
        let periodo = PeriodoTrimestre.aPresentar(hoy: hoy)
        let dias = BandejaDias.entre(hoy, periodo.plazo)
        c[.trimestre] = CifraModulo(cifra: dias == 0 ? "Hoy" : (dias == 1 ? "1 día" : "\(dias) días"),
                                    linea: "para presentar el \(periodo.titulo) · plazo el \(periodo.plazo.day) \(FormatoBase.meses[periodo.plazo.month - 1])",
                                    estado: dias <= 7 ? .atencion : nil, palabra: dias <= 7 ? "Se acerca" : nil,
                                    enlace: EnlaceModulo(titulo: "Ver el trimestre", destino: .area(.finanzas, pestana: PestanaArea.operacion.rawValue)),
                                    fuente: "Sale del calendario fiscal · lo presenta tu gestoría")

        // Ventas
        c[.quietas] = kpiCifra(panel, "VEN-STALE7", enlace: EnlaceModulo(titulo: "Ver en Oportunidades", destino: .base("oportunidades")))
        c[.embudo] = kpiCifra(panel, "VEN-PIPE", linea: { _ in
            let f = panel.evaluador.evaluar("VEN-FCST")
            return f.medida.numero.map { _ in "Ponderado \(f.textoValor)" }
        }, enlace: EnlaceModulo(titulo: "Ver en Oportunidades", destino: .base("oportunidades")))
        c[.ganadas] = kpiCifra(panel, "VEN-CONV")
        let seguimientos = panel.mazo.tarjetas.filter { $0.tipo == .seguimiento }
        let abiertas = panel.foto.oportunidades.filter { $0.abierta && ($0.creada.map { $0 <= hoy } ?? true) }
        if abiertas.isEmpty {
            c[.seguimientos] = .sinDato("Sin dato: no hay oportunidades abiertas.", fuente: "Sale de tus oportunidades")
        } else {
            c[.seguimientos] = CifraModulo(cifra: seguimientos.isEmpty ? "Ninguno" : "\(seguimientos.count)",
                                           linea: seguimientos.isEmpty ? "Nadie lleva 5 días o más sin noticias tuyas." : (seguimientos.first?.titulo),
                                           enlace: EnlaceModulo(titulo: "Ver en Oportunidades", destino: .base("oportunidades")),
                                           fuente: "Sale de \(abiertas.count) oportunidades abiertas")
        }
        c[.diagnosticos] = proximasReuniones(panel.foto, hoy: hoy, area: .ventas)
        c[.sesiones] = proximasReuniones(panel.foto, hoy: hoy, area: nil)

        // Dirección
        c[.decisiones] = CifraModulo(cifra: pendientes == 0 ? "Ninguna" : "\(pendientes)",
                                     linea: pendientes == 0 ? "Nada espera tu decisión." : (pendientes == 1 ? "espera tu decisión" : "esperan tu decisión"),
                                     enlace: EnlaceModulo(titulo: "Ver todas", destino: .decisiones),
                                     fuente: "Sale de tus tareas de decisión y de lo que hay que revisar")
        c[.objetivos] = kpiCifra(panel, "DIR-OBJ", enlace: EnlaceModulo(titulo: "Ver objetivos", destino: .base("objetivos")))
        c[.rutina] = proximaRutina(panel.foto, hoy: hoy)

        // Entrega
        let tarde = panel.mazo.tarjetas.filter { $0.id.hasPrefix("excepcion:proyecto:") }
        let enCurso = panel.foto.proyectos.filter { $0.estado?.abierto ?? true }
        if enCurso.isEmpty {
            c[.proyectosRiesgo] = .sinDato("Sin dato: aún no hay proyectos abiertos.", fuente: "Sale de tus proyectos",
                                           enlace: EnlaceModulo(titulo: "Ver proyectos", destino: .base("proyectos")))
        } else {
            c[.proyectosRiesgo] = CifraModulo(cifra: tarde.isEmpty ? "Ninguno" : "\(tarde.count)",
                                              linea: tarde.first?.titulo ?? "Ningún proyecto fuera de fecha ni justo de plazo.",
                                              estado: tarde.isEmpty ? .bien : .atencion, palabra: tarde.isEmpty ? "En fecha" : "Atención",
                                              enlace: EnlaceModulo(titulo: "Ver proyectos", destino: .base("proyectos")),
                                              fuente: "Sale de \(enCurso.count) proyectos abiertos")
        }
        // Revisión final de F2: lo mismo que Operación (ENT-INC, con su cuenta atrás), no «Sin dato».
        let incAbiertas = panel.foto.incidencias.reduce(0) { $0 + $1.abiertas.count }
        c[.incidencias] = kpiCifra(panel, "ENT-INC", linea: { _ in
            "fuera de plazo · " + (incAbiertas == 0 ? "ninguna abierta" : incAbiertas == 1 ? "1 abierta" : "\(incAbiertas) abiertas")
        }, enlace: EnlaceModulo(titulo: "Ver incidencias", destino: .base("incidencias")))

        // Marca
        c[.publicadas] = kpiCifra(panel, "MAR-PUB", enlace: EnlaceModulo(titulo: "Ver contenidos", destino: .base("contenidos")))
        c[.conversaciones] = kpiCifra(panel, "MAR-QCONV", enlace: EnlaceModulo(titulo: "Ver conversaciones", destino: .base("conversaciones")))
        let contenidos = panel.foto.contenidos
        if contenidos.isEmpty {
            c[.piezas] = .sinDato("Sin dato: aún no hay contenidos.", fuente: "Sale de tus contenidos")
        } else {
            let enCamino = contenidos.filter { !$0.esPublicado && !["descartado", "archivado"].contains(TextFolding.fold($0.estado ?? "")) }
            c[.piezas] = CifraModulo(cifra: enCamino.isEmpty ? "Ninguna" : "\(enCamino.count)",
                                     linea: enCamino.first.map { "«\($0.titulo)»" } ?? "Nada en preparación.",
                                     enlace: EnlaceModulo(titulo: "Ver contenidos", destino: .base("contenidos")),
                                     fuente: "Sale de \(contenidos.count) contenidos")
        }
        c[.casos] = .sinDato("Sin dato: los casos de éxito llegan cuando cierres proyectos.", fuente: "Sale de tus casos de éxito")

        // Equipo
        let rutinas = panel.semana.dias.flatMap(\.rutinas)
        if panel.foto.rutinas.isEmpty {
            c[.rutinasSemana] = .sinDato("Sin dato: aún no hay rutinas con su ficha.", fuente: "Sale de tus rutinas",
                                         enlace: EnlaceModulo(titulo: "Ver rutinas", destino: .base("rutinas")))
        } else {
            c[.rutinasSemana] = CifraModulo(cifra: rutinas.isEmpty ? "Ninguna" : "\(rutinas.count)",
                                            linea: rutinas.isEmpty ? "Ninguna rutina toca esta semana." : (rutinas.count == 1 ? "rutina esta semana" : "rutinas esta semana"),
                                            enlace: EnlaceModulo(titulo: "Ver rutinas", destino: .base("rutinas")),
                                            fuente: "Sale de \(panel.foto.rutinas.count) rutinas")
        }
        // F4 · rol asistentes (`Asistentes/ModulosAsistentes.swift`): quién trabaja y el uso como parte del tope.
        (c[.asistentes], c[.usoTope]) = ModulosAsistentes.cifras(foto: foto, ahora: reloj.ahora)
        if panel.foto.roles.contains(where: \.declaraOcupante) {
            let sin = panel.etapas.filter { !$0.tieneDueno }.map { $0.area }
            c[.areasSinDueno] = CifraModulo(cifra: sin.isEmpty ? "Ninguna" : "\(sin.count)",
                                            linea: sin.isEmpty ? "Cada área tiene una persona al frente." : sin.map(\.nombre).joined(separator: ", "),
                                            estado: sin.isEmpty ? .bien : .atencion, palabra: sin.isEmpty ? "Bien" : "Atención",
                                            enlace: EnlaceModulo(titulo: "Ver roles", destino: .base("roles")),
                                            fuente: "Sale de \(panel.foto.roles.count) roles")
        } else {
            c[.areasSinDueno] = .sinDato("Sin dato: ningún rol dice quién lo ocupa.", fuente: "Sale de tus roles",
                                         enlace: EnlaceModulo(titulo: "Ver roles", destino: .base("roles")))
        }

        let cuello = panel.mapa.cuello == nil ? nil : (panel.mapa.textoCuello, panel.mapa.veredicto)
        return DatosModulos(hoy: hoy, caja: caja, ritmo: panel.ritmoAreas, semana: panel.semana, cabe: cabe, cifras: c,
                            cuello: cuello)
    }

    // MARK: Piezas

    static func cajaDe(_ t: Tesoreria, registros: RegistrosFinanzas, panel: PanelMetricas) -> DatosCaja {
        var series: [RangoCaja: [PuntoCaja]] = [:]
        for r in RangoCaja.allCases { series[r] = t.serie(r) }
        let saldo = t.saldo
        let runway = t.runway
        var motivo: String?
        if registros.cuentas.isEmpty {
            motivo = "Sin datos del banco: importa un extracto."
        } else if saldo.total == nil {
            let faltan = saldo.cuentasSinDato.map(\.nombre)
            motivo = "Sin dato: falta el saldo de " + (faltan.isEmpty ? "alguna cuenta" : faltan.joined(separator: ", ")) + "."
        }
        let k = panel.evaluador.evaluar("FIN-RUNWAY")
        return DatosCaja(series: series, saldo: saldo.total, runway: runway,
                         estadoRunway: k.medida.numero == nil ? nil : k.estado, cuentas: registros.cuentas.count,
                         ultimo: registros.movimientos.map(\.fecha).filter { $0 <= panel.hoy }.max(), motivo: motivo)
    }

    /// Hoy, en orden: lo que tiene hora primero (por la hora) y después lo demás. Una tarea planificada que además vence
    /// hoy sale una vez, marcada.
    static func elementosDeHoy(_ semana: SemanaAgenda, foto: FotoMetricas) -> [ElementoDia] {
        guard let d = semana.diaDeHoy else { return [] }
        var out: [ElementoDia] = []
        let planificadas = Set(d.tareas.map(\.tarea.ruta))
        for t in d.tareas {
            let x = t.tarea
            out.append(ElementoDia(id: "tarea:\(x.ruta.raw)", tipo: .tarea, hora: nil, minutos: nil, titulo: x.titulo, codigo: x.numero,
                                   area: x.area ?? foto.layout.area(of: x.ruta), horas: t.estimacionH, ruta: x.ruta,
                                   venceHoy: x.vence == d.dia))
        }
        for t in d.vencimientos where !planificadas.contains(t.tarea.ruta) {
            let x = t.tarea
            out.append(ElementoDia(id: "vence:\(x.ruta.raw)", tipo: .vence, hora: nil, minutos: nil, titulo: x.titulo, codigo: x.numero,
                                   area: x.area ?? foto.layout.area(of: x.ruta), horas: t.estimacionH, ruta: x.ruta, venceHoy: true))
        }
        for r in d.reuniones {
            let h = r.hora.flatMap(FormatoBase.hora)
            out.append(ElementoDia(id: "reunion:\(r.ruta.raw)", tipo: .reunion, hora: h.map(textoHora), minutos: h.map { $0.hora * 60 + $0.minuto },
                                   titulo: r.titulo, codigo: nil, area: foto.layout.area(of: r.ruta), horas: r.duracionMin.map { $0 / 60 },
                                   ruta: r.ruta, venceHoy: false))
        }
        for r in d.rutinas {
            let h = r.hora.flatMap(FormatoBase.hora)
            out.append(ElementoDia(id: "rutina:\(r.ruta.raw)", tipo: .rutina, hora: h.map(textoHora), minutos: h.map { $0.hora * 60 + $0.minuto },
                                   titulo: r.nombre, codigo: nil, area: foto.layout.area(of: r.ruta), horas: r.duracionMin.map { $0 / 60 },
                                   ruta: r.ruta, venceHoy: false))
        }
        for (i, e) in d.eventos.enumerated() {
            let h = e.hora.flatMap(FormatoBase.hora)
            out.append(ElementoDia(id: "cita:\(i):\(e.titulo)", tipo: .cita, hora: h.map(textoHora), minutos: h.map { $0.hora * 60 + $0.minuto },
                                   titulo: e.titulo, codigo: nil, area: nil, horas: e.horas, ruta: nil, venceHoy: false))
        }
        for f in d.cobros {
            out.append(ElementoDia(id: "cobro:\(f.id)", tipo: .cobro, hora: nil, minutos: nil, titulo: "\(f.numero) · \(f.tercero)",
                                   codigo: nil, area: .finanzas, horas: nil, ruta: f.ficha, venceHoy: true))
        }
        return out.enumerated().sorted { a, b in
            switch (a.element.minutos, b.element.minutos) {
            case let (x?, y?): return x != y ? x < y : a.offset < b.offset
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    static func textoHora(_ h: (hora: Int, minuto: Int)) -> String { String(format: "%d:%02d", h.hora, h.minuto) }

    static func corta(_ d: LocalDate) -> String { "\(d.day) \(FormatoBase.meses[d.month - 1])" }

    static func estado(_ k: ValorKPI) -> TLSEstado? {
        switch k.estado {
        case .bien: .bien
        case .atencion: .atencion
        case .mal: .mal
        case .sinMeta: .sinDato
        case .sinDato: nil
        }
    }

    static func palabra(_ k: ValorKPI) -> String? {
        switch k.estado {
        case .bien: "En ritmo"
        case .atencion: "Atención"
        case .mal: "En alerta"
        case .sinMeta: "Sin meta"
        case .sinDato: nil
        }
    }

    /// Un número clave como módulo: su valor (o «Sin dato» y por qué), su estado frente a la meta y su fuente.
    static func kpiCifra(_ panel: PanelMetricas, _ codigo: String, linea: ((ValorKPI) -> String?)? = nil,
                         enlace: EnlaceModulo? = nil) -> CifraModulo {
        let k = panel.evaluador.evaluar(codigo)
        guard k.medida.numero != nil else {
            let motivo = k.medida.motivoSinDato.map { "Sin dato: \(minuscula($0))" } ?? "Sin dato."
            return .sinDato(motivo, fuente: k.fuente.isEmpty ? k.indicador : k.fuente, enlace: enlace)
        }
        let extra = linea?(k)
        // «Sin meta» ya lo dice la pastilla; la meta, si está fijada, va en la línea.
        let meta = k.metaFijada ? "Meta: \(k.textoMeta)" : nil
        let l = [extra, meta].compactMap { $0 }.joined(separator: " · ")
        return CifraModulo(cifra: k.textoValor, linea: l.isEmpty ? nil : l,
                           estado: estado(k), palabra: palabra(k), vacio: nil, enlace: enlace, fuente: k.fuente)
    }

    static func minuscula(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.lowercased() + s.dropFirst()
    }

    static func proximasReuniones(_ foto: FotoMetricas, hoy: LocalDate, area: AreaCode?) -> CifraModulo {
        let todas = foto.reuniones.filter { r in area.map { foto.layout.area(of: r.ruta) == $0 } ?? true }
        let proximas = todas.filter { ($0.fecha ?? .init(year: 1, month: 1, day: 1)!) >= hoy }
            .sorted { ($0.fecha!, $0.hora ?? "") < ($1.fecha!, $1.hora ?? "") }
        let enlace = EnlaceModulo(titulo: "Ver reuniones", destino: .base("reuniones"))
        guard let p = proximas.first, let f = p.fecha else {
            return CifraModulo(cifra: nil, vacio: todas.isEmpty ? "Sin dato: aún no hay reuniones en tus fichas."
                                                                : "No hay reuniones con fecha a partir de hoy.",
                               enlace: enlace, fuente: "Sale de tus reuniones")
        }
        let dia = f == hoy ? "Hoy" : FormatoBase.fechaConDia(f)
        return CifraModulo(cifra: dia + (p.hora.map { " · \($0)" } ?? ""),
                           linea: p.titulo + (proximas.count > 1 ? " · y \(proximas.count - 1) más" : ""),
                           enlace: enlace, fuente: "Sale de \(todas.count) reuniones")
    }

    static func proximaRutina(_ foto: FotoMetricas, hoy: LocalDate) -> CifraModulo {
        let activas = foto.rutinas.filter(\.activa)
        let enlace = EnlaceModulo(titulo: "Ver rutinas", destino: .base("rutinas"))
        guard !activas.isEmpty else {
            return .sinDato("Sin dato: aún no hay rutinas con su ficha.", fuente: "Sale de tus rutinas", enlace: enlace)
        }
        for i in 0..<45 {
            let d = hoy.adding(days: i)
            let tocan = activas.filter { r in
                FotoMetricasAgenda.toca(r, en: d)
            }.sorted { ($0.hora ?? "") < ($1.hora ?? "") }
            if let r = tocan.first {
                let dia = i == 0 ? "Hoy" : (i == 1 ? "Mañana" : FormatoBase.fechaConDia(d))
                return CifraModulo(cifra: dia + (r.hora.map { " · \($0)" } ?? ""), linea: r.nombre, enlace: enlace,
                                   fuente: "Sale de \(activas.count) rutinas")
            }
        }
        return CifraModulo(cifra: nil, vacio: "Ninguna rutina activa dice qué día toca.", enlace: enlace,
                           fuente: "Sale de \(activas.count) rutinas")
    }
}

/// Días entre dos fechas del calendario (sin horas).
enum BandejaDias {
    static func entre(_ a: LocalDate, _ b: LocalDate) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        return Int(((b.date(timeZone: utc).timeIntervalSince1970 - a.date(timeZone: utc).timeIntervalSince1970) / 86_400).rounded())
    }
}

/// Si una rutina toca un día (la misma regla que la agenda de las métricas).
enum FotoMetricasAgenda {
    static func toca(_ r: FotoMetricas.Rutina, en d: LocalDate) -> Bool {
        guard let dia = r.dia?.trimmingCharacters(in: .whitespaces), !dia.isEmpty else { return false }
        let cad = TextFolding.fold(r.cadencia ?? "semanal")
        if cad.hasPrefix("mensual") { return Int(dia) == d.day }
        if cad.hasPrefix("trimestral") { return Int(dia) == d.day && [1, 4, 7, 10].contains(d.month) }
        let nombres = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
        let cortos = ["lun", "mar", "mie", "jue", "vie", "sab", "dom"]
        let f = TextFolding.fold(dia)
        if let i = nombres.firstIndex(of: f) ?? cortos.firstIndex(of: f) { return i + 1 == d.weekday }
        return false
    }
}
