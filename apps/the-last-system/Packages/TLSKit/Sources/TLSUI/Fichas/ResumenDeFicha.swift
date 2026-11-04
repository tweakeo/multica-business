import Foundation
import TLSCore
import TLSDesign

/// El dato protagonista de una ficha (§3.4): va en el destacado violeta de la ficha y, sin violeta, en su
/// vista previa.
struct DatoProtagonista: Hashable, Sendable {
    /// Rótulo («Siguiente paso», «Total», «Avance»).
    let rotulo: String
    /// La cifra o la frase («Emitir factura y confirmar cobro», «181,50 €», «0 de 6»).
    let valor: String
    /// Debajo, en pequeño («mañana · Jorge Martín · Trimestrales»).
    let contexto: String?
    /// `true` si `valor` es una cifra (se pinta en Space Grotesk grande).
    let esCifra: Bool
    /// Avance de 0 a 1 para el anillo del proyecto.
    var avance: Double? = nil
    /// Texto del destacado vacío cuando no hay dato: explica por qué y qué hacer.
    var vacio: String? = nil
    /// Un segundo dato debajo, tras una raya («Cobrado 25 %» · «150 € de 600 €, sin IVA»; «Pendiente de cobro»).
    var segundo: String? = nil
    var segundoDetalle: String? = nil
}

/// Una línea de la franja «Ahora» (§3.1): lo que pide algo ya, en orden de urgencia.
struct LineaAhora: Hashable, Sendable, Identifiable {
    enum Clase: Int, Sendable, Comparable {
        case decision = 0, vencido, hoy, falta, siguiente
        static func < (a: Clase, b: Clase) -> Bool { a.rawValue < b.rawValue }
    }
    var id: String { texto }
    let clase: Clase
    let texto: String
    /// Ficha a la que lleva el botón.
    let destino: VaultPath?
    let boton: String?

    /// La palabra de lo que es, delante de la frase.
    var rotulo: String {
        switch clase {
        case .decision: "Pide tu decisión"
        case .vencido: "Vencido"
        case .hoy: "Hoy"
        case .falta: "Falta un dato"
        case .siguiente: "Siguiente"
        }
    }

    var estado: TLSEstado {
        switch clase {
        case .decision: .atencion
        case .vencido: .mal
        case .hoy: .atencion
        case .falta: .atencion
        case .siguiente: .sinDato
        }
    }
}

/// Un chip de «Conectado con» (§3.1): una relación de uno a uno de esta ficha, guardada aquí o calculada.
struct ChipConectado: Hashable, Sendable, Identifiable {
    var id: String { propiedad + "·" + (destino?.raw ?? "falta") }
    /// Rótulo («Empresa», «Recomendado por», «Servicio»).
    let rotulo: String
    /// Propiedad canónica que lo guarda.
    let propiedad: String
    let destino: VaultPath?
    let nombre: String
    let tipo: NoteKind?
    let estado: String?
    /// Dónde se guarda: en esta ficha o en otra (calculado).
    let guardaEn: VaultPath
    /// Calculado desde otras fichas (no se escribe aquí).
    let calculado: Bool
    /// Motivo por el que no se puede quitar (obligatoria), si lo hay.
    let motivoNoQuitar: String?
    /// Relación obligatoria vacía («Falta empresa»).
    var falta: Bool { destino == nil }
}

/// Lo esencial de una ficha, calculado del grafo (sin leer el fichero): cabecera, destacado, datos, «Ahora» y
/// «Conectado con». Lo usan la ficha y su vista previa.
struct ResumenDeFicha: Sendable {
    let ficha: FichaGrafo
    let rotulo: String
    let codigo: String?
    let estado: String?
    let protagonista: DatoProtagonista?
    let datos: [DatoClave]
    let ahora: [LineaAhora]
    let conectado: [ChipConectado]

    init(ficha f: FichaGrafo, grafo g: GrafoRelaciones, hoy: LocalDate) {
        ficha = f
        let area = ResumenDeFicha.area(f)
        rotulo = [f.tipo.etiqueta, area?.etiquetaNumerada].compactMap { $0 }.joined(separator: " · ")
        codigo = f.numero ?? f.texto("codigo")
        estado = f.estado.map(FormatoFicha.capital)
        let rel = g.relacionados(de: f.ruta)
        protagonista = Self.protagonista(f, g: g, rel: rel, hoy: hoy)
        datos = Self.datos(f, g: g, rel: rel, hoy: hoy)
        conectado = Self.conectado(f, g: g)
        var ahora = Self.ahora(f, g: g, rel: rel, hoy: hoy, conectado: conectado)
        ahora = Self.quitandoLoDelDestacado(ahora, protagonista: protagonista)
        self.ahora = Array(ahora.prefix(3))
    }

    /// Lo que ya dice el destacado no se repite en «Ahora». Con el destacado vacío no se quita nada
    /// (`hasPrefix("")` es verdad siempre: se borraba la franja entera).
    static func quitandoLoDelDestacado(_ ahora: [LineaAhora], protagonista: DatoProtagonista?) -> [LineaAhora] {
        guard let p = protagonista, !p.valor.isEmpty else { return ahora }
        return ahora.filter { !$0.texto.hasPrefix(p.valor) }
    }

    static func area(_ f: FichaGrafo) -> AreaCode? {
        if let a = f.texto("area"), let code = AreaCode.allCases.first(where: { $0.layoutKey == TextFolding.fold(a) || TextFolding.fold($0.nombre) == TextFolding.fold(a) }) {
            return code
        }
        guard let primera = f.ruta.components.first, let n = Int(primera.prefix(while: \.isNumber)) else { return nil }
        return AreaCode.allCases.first { $0.numero == n }
    }

    // MARK: Destacado

    static func siguientePaso(_ opos: [FichaGrafo], hoy: LocalDate) -> (paso: String, fecha: LocalDate?, de: FichaGrafo)? {
        let abiertas = opos.filter { EstadosDeFicha.abierta(.opportunity, estado: $0.estado) && $0.texto("siguiente_paso") != nil }
        let orden = abiertas.sorted { a, b in
            let fa = a.texto("siguiente_fecha").flatMap { LocalDate(parsing: $0) }
            let fb = b.texto("siguiente_fecha").flatMap { LocalDate(parsing: $0) }
            switch (fa, fb) {
            case (let x?, let y?): return x < y
            case (_?, nil): return true
            default: return false
            }
        }
        guard let o = orden.first, let paso = o.texto("siguiente_paso") else { return nil }
        return (paso, o.texto("siguiente_fecha").flatMap { LocalDate(parsing: $0) }, o)
    }

    static func protagonista(_ f: FichaGrafo, g: GrafoRelaciones, rel: [Relacionado], hoy: LocalDate) -> DatoProtagonista? {
        func de(_ tipos: Set<NoteKind>) -> [FichaGrafo] { rel.map(\.ficha).filter { tipos.contains($0.tipo) } }
        switch f.tipo {
        case .organization, .contact:
            let opos = de([.opportunity])
            var pendiente: (String, String)?
            if f.tipo == .organization {
                let sinCobrar = de([.invoice]).filter { EstadosDeFicha.abierta(.invoice, estado: $0.estado) && TextFolding.fold($0.estado ?? "") != "borrador" }
                let total = sinCobrar.compactMap { FormatoFicha.numero($0.texto("total")) }.reduce(0, +)
                if total > 0 {
                    pendiente = ("Pendiente de cobro: " + FormatoFicha.euros(total),
                                 sinCobrar.count == 1 ? "1 factura emitida sin cobrar" : "\(sinCobrar.count) facturas emitidas sin cobrar")
                }
            }
            if let s = siguientePaso(opos, hoy: hoy) {
                let cuando = s.fecha.map { FormatoFicha.capital(FormatoFicha.cuando($0, hoy: hoy)) }
                let contexto = [cuando, s.de.nombre].compactMap { $0 }.joined(separator: " · ")
                return DatoProtagonista(rotulo: "Siguiente paso", valor: s.paso, contexto: contexto, esCifra: false,
                                        segundo: pendiente?.0, segundoDetalle: pendiente?.1)
            }
            return DatoProtagonista(rotulo: "Siguiente paso", valor: "", contexto: pendiente.map { "\($0.0) · \($0.1)" }, esCifra: false,
                                    vacio: opos.isEmpty ? "Aún no hay nada en marcha con \(f.nombre). Crea una oportunidad o una reunión desde «Nuevo»."
                                        : "Sus oportunidades no tienen siguiente paso. Ponlo en la oportunidad para que salga aquí.")
        case .opportunity:
            guard let valor = FormatoFicha.numero(f.texto("valor")) else {
                return DatoProtagonista(rotulo: "Valor ponderado", valor: "", contexto: nil, esCifra: true,
                                        vacio: "Falta el valor: ponlo en Propiedades (⌥⌘I) para ver lo que pesa en el embudo.")
            }
            let prob = FormatoFicha.numero(f.texto("probabilidad")) ?? (TextFolding.fold(f.estado ?? "") == "ganada" ? 100 : 0)
            let ponderado = valor * prob / 100
            return DatoProtagonista(rotulo: "Valor ponderado", valor: FormatoFicha.euros(ponderado),
                                    contexto: "\(FormatoFicha.euros(valor)) al \(prob) %", esCifra: true)
        case .project:
            let tareas = de([.task]).filter { TextFolding.fold($0.estado ?? "") != "cancelada" }
            let hechas = tareas.filter { TextFolding.fold($0.estado ?? "") == "hecha" }.count
            let contexto = tareas.isEmpty ? "Aún no tiene tareas" : (hechas == 0 ? "tareas hechas · el plan acaba de empezar" : "tareas del plan hechas")
            var cobro: (String, String)?
            if let opo = g.destinos(de: f.ruta, propiedad: "oportunidad").first.flatMap(g.ficha), !opo.privada,
               let valor = FormatoFicha.numero(opo.texto("valor")), valor > 0 {
                let cobrado = de([.invoice]).filter { TextFolding.fold($0.estado ?? "") == "cobrada" }
                    .compactMap { FormatoFicha.numero($0.texto("base")) }.reduce(0, +)
                let pct = NSDecimalNumber(decimal: cobrado * 100 / valor).intValue
                cobro = ("Cobrado \(pct) %", "\(FormatoFicha.euros(cobrado)) de \(FormatoFicha.euros(valor)), sin IVA")
            }
            return DatoProtagonista(rotulo: "Avance", valor: "\(hechas) de \(tareas.count)", contexto: contexto, esCifra: true,
                                    avance: tareas.isEmpty ? 0 : Double(hechas) / Double(tareas.count),
                                    segundo: cobro?.0, segundoDetalle: cobro?.1)
        case .task:
            let estado = f.estado ?? "Sin programar"
            let vence = f.texto("vence").flatMap { LocalDate(parsing: $0) }
            let contexto = vence.map { "vence " + FormatoFicha.cuando($0, hoy: hoy) } ?? "sin fecha de vencimiento"
            return DatoProtagonista(rotulo: "Estado", valor: estado, contexto: contexto, esCifra: false)
        case .meeting:
            let fecha = f.texto("fecha").flatMap { LocalDate(parsing: $0) }
            let hora = f.texto("hora")
            if TextFolding.fold(f.estado ?? "") == "hecha" {
                let partes = ["Hecha", fecha.map { FormatoFicha.fechaCorta($0, hoy: hoy) }, f.texto("duracion_min").map { "\($0) min" }]
                return DatoProtagonista(rotulo: "Reunión", valor: partes.compactMap { $0 }.joined(separator: " · "), contexto: nil, esCifra: false)
            }
            guard let fecha else {
                return DatoProtagonista(rotulo: "Cuándo", valor: "", contexto: nil, esCifra: false,
                                        vacio: "Aún no tiene fecha. Ponla en Propiedades (⌥⌘I).")
            }
            let cuando = FormatoFicha.capital(FormatoFicha.cuando(fecha, hoy: hoy)) + (hora.map { " " + $0 } ?? "")
            let faltan = FormatoFicha.dias(de: hoy, a: fecha)
            return DatoProtagonista(rotulo: "Cuándo", valor: cuando,
                                    contexto: faltan > 1 ? "Faltan \(faltan) días" : (faltan < 0 ? "Ya pasó: ¿la marcas como hecha?" : nil), esCifra: false)
        case .invoice, .proposal, .quote, .receipt:
            let total = FormatoFicha.euros(f.texto("total") ?? f.texto("importe"))
            let e = f.estado ?? "Borrador"
            var contexto = e
            if TextFolding.fold(e) == "borrador", f.tipo == .invoice { contexto += " · se numera al emitir" }
            if let v = f.texto("vence").flatMap({ LocalDate(parsing: $0) }) { contexto += " · vence " + FormatoFicha.cuando(v, hoy: hoy) }
            if let v = f.texto("valida_hasta").flatMap({ LocalDate(parsing: $0) }) { contexto += " · válida hasta " + FormatoFicha.cuando(v, hoy: hoy) }
            guard let total else {
                return DatoProtagonista(rotulo: "Total", valor: "", contexto: nil, esCifra: true, vacio: "Aún no tiene importe: añade sus conceptos.")
            }
            return DatoProtagonista(rotulo: "Total", valor: total, contexto: contexto, esCifra: true)
        case .system:
            let codigo = f.texto("numero_clave")
            return DatoProtagonista(rotulo: "Número clave", valor: "", contexto: nil, esCifra: true,
                                    vacio: codigo.map { "\($0) se calcula con sus ejecuciones; lo verás aquí frente a su meta." }
                                        ?? "Aún no tiene número clave. Ponlo en Propiedades para saber si va bien.")
        default:
            return nil
        }
    }

    // MARK: Datos de la cabecera

    static func datos(_ f: FichaGrafo, g: GrafoRelaciones, rel: [Relacionado], hoy: LocalDate) -> [DatoClave] {
        func fecha(_ k: String) -> String? { f.texto(k).map { FormatoFicha.fechaLegible($0, hoy: hoy) } }
        var out: [DatoClave] = []
        switch f.tipo {
        case .organization:
            if let r = f.texto("relacion") { out.append(DatoClave("Relación", FormatoFicha.capital(r))) }
            let personas = rel.filter { $0.ficha.tipo == .contact }.count
            out.append(DatoClave("Personas", "\(personas)"))
            if let d = f.texto("cliente_desde") ?? f.texto("creada") { out.append(DatoClave(f.texto("cliente_desde") == nil ? "En la carpeta desde" : "Cliente desde", FormatoFicha.fechaLegible(d, hoy: hoy))) }
        case .contact:
            if let r = f.texto("relacion") { out.append(DatoClave("Relación", FormatoFicha.capital(r))) }
            let verificado = f.texto("verificacion").map { TextFolding.fold($0) == "verificado" } ?? false
            out.append(DatoClave("Verificado", verificado ? "Sí" : "Aún no"))
            // La empresa ya va en la línea de resumen y en «Conectado con»: aquí solo el cargo.
            if let cargo = f.texto("cargo") { out.append(DatoClave("Cargo", cargo)) }
        case .opportunity:
            // La etapa ya es la pastilla de estado de la cabecera: aquí, solo si no tiene.
            if f.estado == nil { out.append(DatoClave("Etapa", "Sin etapa")) }
            let claveEtapa = TextFolding.fold(f.estado ?? "").replacingOccurrences(of: " ", with: "_")
            if let d = (f.texto(claveEtapa) ?? f.texto("creada")).flatMap({ LocalDate(parsing: $0) }) {
                let n = max(0, FormatoFicha.dias(de: d, a: hoy))
                out.append(DatoClave("Días en la etapa", n == 1 ? "1 día" : "\(n) días"))
            }
            out.append(DatoClave("Responsable", f.texto("responsable").map(Responsables.nombre(de:)) ?? "Sin responsable"))
        case .project:
            out.append(DatoClave("Fase", f.texto("fase") ?? "Sin fase"))
            out.append(DatoClave("Responsable", f.texto("responsable").map(Responsables.nombre(de:)) ?? "Sin responsable"))
            let proximas = rel.map(\.ficha).filter { $0.tipo == .task && EstadosDeFicha.abierta(.task, estado: $0.estado) }
                .compactMap { t in t.texto("vence").flatMap { LocalDate(parsing: $0) }.map { ($0, t) } }.sorted { $0.0 < $1.0 }
            if let p = proximas.first {
                out.append(DatoClave("Próximo vencimiento", FormatoFicha.fechaConDia(p.0, hoy: hoy) + (p.1.numero.map { " · \($0)" } ?? "")))
            } else {
                out.append(DatoClave("Próximo vencimiento", "Nada pendiente"))
            }
        case .task:
            out.append(DatoClave("Número", f.numero ?? "Sin número"))
            if let a = area(f) { out.append(DatoClave("Área", a.etiquetaNumerada)) }
            out.append(DatoClave("Responsable", f.texto("responsable").map(Responsables.nombre(de:)) ?? "Sin responsable"))
        case .meeting:
            out.append(DatoClave("Tipo", f.texto("tipo").map(FormatoFicha.capital) ?? "Reunión"))
            if let d = f.texto("duracion_min") { out.append(DatoClave("Duración", "\(d) min")) }
            out.append(DatoClave("Lugar", f.texto("lugar") ?? "Sin lugar"))
        case .invoice:
            out.append(DatoClave("Número", f.numero ?? "Se numera al emitir"))
            if let d = fecha("fecha") ?? fecha("creada") { out.append(DatoClave("Fecha", d)) }
            if let v = fecha("vence") { out.append(DatoClave("Vence", v)) }
        case .system:
            if let r = g.destinos(de: f.ruta, propiedad: "rol").first.flatMap(g.ficha), !r.privada {
                out.append(DatoClave("Quién lo lleva", r.nombre))
            }
            if let d = f.texto("revisado").flatMap({ LocalDate(parsing: $0) }) {
                let n = max(0, FormatoFicha.dias(de: d, a: hoy))
                out.append(DatoClave("Revisado", n == 0 ? "hoy" : "hace \(n) días"))
            }
            if let c = f.texto("codigo") { out.append(DatoClave("Código", c)) }
        default:
            if let d = fecha("fecha") ?? fecha("creada") { out.append(DatoClave("Fecha", d)) }
        }
        return Array(out.prefix(3))
    }

    // MARK: Ahora

    static func ahora(_ f: FichaGrafo, g: GrafoRelaciones, rel: [Relacionado], hoy: LocalDate, conectado: [ChipConectado]) -> [LineaAhora] {
        var out: [LineaAhora] = []
        let cosas = rel.map(\.ficha)
        for t in cosas where t.tipo == .task && EstadosDeFicha.esperaTuOK(.task, estado: t.estado) {
            out.append(LineaAhora(clase: .decision, texto: "\(t.numero.map { "\($0) · " } ?? "")\(t.nombre): espera tu OK",
                                  destino: t.ruta, boton: "Revisar"))
        }
        if f.tipo == .opportunity, TextFolding.fold(f.estado ?? "") == "aceptada" {
            let c = g.cobroConfirmado(oportunidad: f.ruta)
            if !c.confirmado, let fac = cosas.first(where: { $0.tipo == .invoice && EstadosDeFicha.abierta(.invoice, estado: $0.estado) }) {
                out.append(LineaAhora(clase: .decision, texto: "Falta confirmar el cobro de \(fac.numero ?? fac.nombre) para pasar a Ganada",
                                      destino: fac.ruta, boton: "Abrir la factura"))
            }
        }
        func vence(_ x: FichaGrafo) -> LocalDate? {
            (x.texto("vence") ?? x.texto("siguiente_fecha")).flatMap { LocalDate(parsing: $0) }
        }
        let propias = [f] + cosas.filter { [.task, .invoice, .opportunity].contains($0.tipo) }
        for x in propias where EstadosDeFicha.abierta(x.tipo, estado: x.estado) {
            guard let v = vence(x) else { continue }
            if x.tipo == .invoice, TextFolding.fold(x.estado ?? "") == "borrador" { continue }
            let quien = x.ruta == f.ruta ? "" : "\(x.numero ?? x.nombre): "
            let que = x.texto("siguiente_paso") ?? (x.tipo == .invoice ? "cobro" : "vence")
            if v < hoy {
                out.append(LineaAhora(clase: .vencido, texto: quien + "\(FormatoFicha.capital(que)) · venció \(FormatoFicha.cuando(v, hoy: hoy))",
                                      destino: x.ruta == f.ruta ? nil : x.ruta, boton: x.ruta == f.ruta ? nil : "Abrir"))
            } else if v == hoy {
                out.append(LineaAhora(clase: .hoy, texto: quien + "\(FormatoFicha.capital(que)) · hoy",
                                      destino: x.ruta == f.ruta ? nil : x.ruta, boton: x.ruta == f.ruta ? nil : "Abrir"))
            }
        }
        for c in conectado where c.falta {
            out.append(LineaAhora(clase: .falta, texto: "Falta \(c.rotulo.lowercased()): \(c.motivoNoQuitar ?? "es obligatoria")",
                                  destino: nil, boton: nil))
        }
        var vistos = Set<String>()
        return out.filter { vistos.insert($0.texto).inserted }.sorted { $0.clase < $1.clase }
    }

    // MARK: Conectado con

    static func conectado(_ f: FichaGrafo, g: GrafoRelaciones) -> [ChipConectado] {
        var out: [ChipConectado] = []
        let guardadas = EsquemaRelaciones.guardadas(por: f.tipo)
        let enlaces = g.relacionesGuardadas(por: f.ruta)
        var vistas = Set<String>()
        for def in guardadas {
            let destinos = enlaces.filter { $0.propiedad == def.propiedad }.map(\.destino)
            vistas.insert(def.propiedad)
            if destinos.isEmpty {
                if let motivo = def.motivoObligatoria(f.propiedades) {
                    out.append(ChipConectado(rotulo: def.etiqueta, propiedad: def.propiedad, destino: nil, nombre: "Falta \(def.etiqueta.lowercased())",
                                             tipo: nil, estado: nil, guardaEn: f.ruta, calculado: false, motivoNoQuitar: motivo))
                }
                continue
            }
            for d in destinos {
                guard let df = g.ficha(d), !df.privada else { continue }
                let motivo = destinos.count > 1 && def.cardinalidad == .varias ? nil : def.motivoObligatoria(f.propiedades)
                out.append(ChipConectado(rotulo: def.etiqueta, propiedad: def.propiedad, destino: d, nombre: df.nombre, tipo: df.tipo,
                                         estado: df.estado, guardaEn: f.ruta, calculado: false, motivoNoQuitar: motivo))
            }
        }
        // Otras relaciones escritas aquí que el esquema no conoce (se ven, no se pierden).
        for e in enlaces where !vistas.contains(e.propiedad) {
            guard let df = g.ficha(e.destino), !df.privada else { continue }
            out.append(ChipConectado(rotulo: FormatoFicha.capital(e.propiedad.replacingOccurrences(of: "_", with: " ")),
                                     propiedad: e.propiedad, destino: e.destino, nombre: df.nombre, tipo: df.tipo, estado: df.estado,
                                     guardaEn: f.ruta, calculado: false, motivoNoQuitar: nil))
        }
        // Calculadas: lo que en la otra ficha es de uno a uno con esta.
        switch f.tipo {
        case .organization, .contact:
            let opos = g.relacionados(de: f.ruta).map(\.ficha).filter { $0.tipo == .opportunity }
            var servicios = Set<VaultPath>()
            for o in opos where ["aceptada", "ganada"].contains(TextFolding.fold(o.estado ?? "")) {
                for s in g.destinos(de: o.ruta, propiedad: "servicio") where servicios.insert(s).inserted {
                    guard let sf = g.ficha(s) else { continue }
                    out.append(ChipConectado(rotulo: "Servicio", propiedad: "servicio", destino: s, nombre: sf.nombre, tipo: .service,
                                             estado: o.estado, guardaEn: o.ruta, calculado: true,
                                             motivoNoQuitar: "Sale de la oportunidad «\(o.nombre)»: se cambia allí."))
                }
            }
            if f.tipo == .contact {
                for e in g.entrantes[f.ruta] ?? [] where e.propiedad == "referido_por" {
                    guard let o = g.ficha(e.origen), o.tipo == .contact, !o.privada else { continue }
                    out.append(ChipConectado(rotulo: "Recomendó a", propiedad: "referido_por", destino: o.ruta, nombre: o.nombre, tipo: .contact,
                                             estado: o.estado, guardaEn: o.ruta, calculado: true, motivoNoQuitar: nil))
                }
            }
        case .task:
            for e in g.entrantes[f.ruta] ?? [] where e.propiedad == "bloqueada_por" {
                guard let o = g.ficha(e.origen), !o.privada else { continue }
                out.append(ChipConectado(rotulo: "Bloquea a", propiedad: "bloqueada_por", destino: o.ruta, nombre: o.nombre, tipo: .task,
                                         estado: o.estado, guardaEn: o.ruta, calculado: true, motivoNoQuitar: nil))
            }
        case .opportunity:
            for e in g.entrantes[f.ruta] ?? [] where e.propiedad == "oportunidad" {
                guard let p = g.ficha(e.origen), p.tipo == .project, !p.privada else { continue }
                out.append(ChipConectado(rotulo: "Proyecto", propiedad: "oportunidad", destino: p.ruta, nombre: p.nombre, tipo: .project,
                                         estado: p.estado, guardaEn: p.ruta, calculado: true,
                                         motivoNoQuitar: "El proyecto guarda su oportunidad: se cambia desde el proyecto."))
            }
        default:
            break
        }
        return out
    }
}
