import Foundation

// F3 · rol motor. El motor de la puesta en marcha (PLAN §6.7): qué pantallas tiene cada ruta, qué se pregunta en cada
// una (premarcado con su origen), el contador «Quedan ~N min», «Seguir más tarde» y la vista previa de lo que escribe
// cada paso. Guarda el estado en `onboarding.json` tras cada respuesta. **No escribe nunca en la carpeta**: eso solo
// lo hace `AplicadorPuesta` cuando la persona pulsa «Aplicar».

/// Cómo es una pantalla.
public enum TipoPantalla: String, Codable, Sendable, Hashable {
    /// Elegir entre pocas opciones grandes.
    case eleccion
    /// Varias preguntas cortas.
    case formulario
    /// Un texto libre (siempre en su propia pantalla).
    case textoLibre
    /// Todo premarcado con su origen, para confirmar (ruta de la copia de G3).
    case resumen
    /// La vista previa de lo que se escribirá, con «Aplicar».
    case vistaPrevia
    /// Una pantalla del paso 2 (la lleva el importador).
    case delegada
    /// Sin preguntas (el recorrido).
    case informativa

    /// Lo que se tarda, de media, sin mirar sus preguntas (el motor afina el resumen y los formularios por pregunta:
    /// `OnboardingEngine.minutos(de:)`).
    public var minutos: Double {
        switch self {
        case .eleccion, .informativa: 0.5
        case .formulario: 1.5
        case .textoLibre, .resumen: 2
        case .vistaPrevia: 1
        case .delegada: 3
        }
    }
}

/// Una pantalla de la puesta en marcha.
public struct Pantalla: Sendable, Hashable, Identifiable {
    public let id: String
    public let paso: PasoPuesta
    public let tipo: TipoPantalla
    public let titulo: String
    /// La explicación de arriba: dos o tres líneas.
    public let explicacion: String
    /// Todas las preguntas (las que se ven dependen de las respuestas: `OnboardingEngine.preguntas(de:)`).
    public let preguntas: [PreguntaID]
    public let area: AreaCode?
    /// La vista previa de lo que escribe el paso va en esta pantalla.
    public let conVistaPrevia: Bool
    /// «Aplicar» va en esta pantalla.
    public let aplicaAqui: Bool

    public var minutos: Double { tipo.minutos }
}

/// Lo que pasa al contestar.
public enum ResultadoRespuesta: Sendable, Hashable {
    case guardada
    /// La respuesta es vaga: se repregunta una vez (la respuesta queda guardada igualmente).
    case repreguntar(String)
}

/// Lo que pasa al pulsar «Siguiente».
public enum ResultadoAvance: Sendable, Hashable {
    case pantalla(Pantalla)
    /// Faltan respuestas obligatorias en esta pantalla (se puede contestar «No lo sé»).
    case faltan([PreguntaID])
    /// Hay que aplicar (o descartar) el paso antes de seguir.
    case faltaAplicar(PasoPuesta)
    case terminada
}

/// «Seguir con la puesta en marcha · paso 4 de 9» (para Hoy y el arranque).
public struct ProgresoPuestaEnMarcha: Sendable, Hashable {
    public let paso: PasoPuesta
    public let numero: Int
    public let total: Int
    public let quedanMinutos: Int
    public let terminada: Bool
    public let enPausa: Bool

    public var texto: String {
        terminada ? "Puesta en marcha terminada" : "Seguir con la puesta en marcha · paso \(numero) de \(total)"
    }

    public var textoMinutos: String { "Quedan ~\(quedanMinutos) min" }

    /// Lo que hay guardado para una carpeta (`nil` si no hay puesta en marcha empezada).
    public static func leer(vaultID: UUID, appSupport: URL = AppLocations.appSupport) -> ProgresoPuestaEnMarcha? {
        guard let estado = AlmacenPuesta(vaultID: vaultID, appSupport: appSupport).leer() else { return nil }
        return de(estado)
    }

    /// El de un estado ya leído (las pendientes del arranque). Los minutos, los que guardó la ventana (con la carpeta).
    public static func de(_ estado: EstadoPuestaEnMarcha) -> ProgresoPuestaEnMarcha {
        let p = OnboardingEngine(estado: estado, contexto: .vacio()).progreso
        guard let q = estado.quedan else { return p }
        return ProgresoPuestaEnMarcha(paso: p.paso, numero: p.numero, total: p.total, quedanMinutos: max(1, q),
                                      terminada: p.terminada, enPausa: p.enPausa)
    }
}

/// El motor de la puesta en marcha. Es un valor: cada cambio se guarda en `onboarding.json` (si hay almacén).
public struct OnboardingEngine: Sendable {
    public internal(set) var estado: EstadoPuestaEnMarcha
    public internal(set) var contexto: ContextoCarpeta
    public let almacen: AlmacenPuesta?
    public var entrevista: InterviewEngine
    /// F4: quién escribe los asistentes de serie al aplicar el paso 4 (o el 3 si el 4 no sale). Lo pone TLSOnboarding;
    /// `nil` = la puesta en marcha no escribe asistentes (pruebas de F3).
    public var asistentes: (any ProveedorAsistentesDeSerie)?

    public init(estado: EstadoPuestaEnMarcha, contexto: ContextoCarpeta, almacen: AlmacenPuesta? = nil,
                entrevista: InterviewEngine = InterviewEngine()) {
        self.estado = estado; self.contexto = contexto; self.almacen = almacen; self.entrevista = entrevista
    }

    /// Empieza o retoma (si hay `onboarding.json`) la puesta en marcha de una carpeta.
    public static func abrir(vaultID: UUID, contexto: ContextoCarpeta, almacen: AlmacenPuesta?, persona: String = "Manu",
                             entrevista: InterviewEngine = InterviewEngine()) -> OnboardingEngine {
        if var e = almacen?.leer() {
            e.enPausa = false
            var m = OnboardingEngine(estado: e, contexto: contexto, almacen: almacen, entrevista: entrevista)
            m.fijarRutaDeLaCopia()
            m.guardar(conMinutos: true)
            return m
        }
        // Un `onboarding.json` que no se puede leer no se pisa: se aparta al lado antes de empezar de cero.
        almacen?.apartarIlegible()
        var m = OnboardingEngine(estado: EstadoPuestaEnMarcha(vaultID: vaultID, persona: persona), contexto: contexto,
                                 almacen: almacen, entrevista: entrevista)
        m.fijarRutaDeLaCopia()
        m.estado.pantalla = m.pantallas.first?.id
        m.guardar(conMinutos: true)
        return m
    }

    /// Sobre una copia ya hecha (desde el arranque), la ruta sale de cómo está la carpeta y se queda fija: al ordenarla
    /// no cambia de ruta a mitad de camino, y Hoy y el arranque cuentan los pasos como la ventana.
    mutating func fijarRutaDeLaCopia() {
        guard estado.ruta == nil, contexto.foto != nil, contexto.entrada?.clase == .copia else { return }
        estado.ruta = contexto.rutaDetectada
    }

    /// Cambia lo que se sabe de la carpeta (al elegirla, tras copiarla o tras ordenarla).
    public mutating func cambiarContexto(_ c: ContextoCarpeta) {
        contexto = c
        guardar()
    }

    // MARK: Guardar

    /// Guarda `onboarding.json`. `conMinutos` (al cambiar de pantalla o de paso) apunta también «Quedan ~N min» para Hoy
    /// y el arranque, que lo leen sin la carpeta: así dicen lo mismo que la ventana (contarlo en cada respuesta es caro).
    mutating func guardar(conMinutos: Bool = false) {
        estado.actualizado = Date()
        if conMinutos, almacen != nil { estado.quedan = estado.terminada ? 0 : quedanMinutos }
        try? almacen?.guardar(estado)
    }

    /// «Seguir más tarde»: se guarda dónde está y todas las respuestas. Al volver se retoma en la misma pregunta.
    public mutating func seguirMasTarde() {
        estado.enPausa = true
        guardar(conMinutos: true)
    }

    /// Consentimiento para usar Claude Code (repreguntar con el asistente).
    public mutating func usarAsistente(_ si: Bool) {
        estado.usarAsistente = si
        estado.respuestas[PreguntaID.asistente.rawValue] = Respuesta(valor: .siNo(si))
        guardar()
    }

    // MARK: Respuestas

    /// La pregunta con su premarcado y su referencia.
    public func pregunta(_ id: PreguntaID) -> Pregunta? {
        guard var p = CatalogoPreguntas.pregunta(id, contexto: contexto, motor: self) else { return nil }
        p.premarcada = premarca(id)
        p.referencia = contexto.referencia(id)
        return p
    }

    /// Lo que vale una respuesta: la de la persona o, si no hay, la premarcada.
    public func valor(_ id: PreguntaID) -> ValorRespuesta? {
        estado.respuesta(id)?.valor ?? premarca(id)?.valor
    }

    /// La respuesta efectiva (con su origen).
    public func respuesta(_ id: PreguntaID) -> Respuesta? {
        estado.respuesta(id) ?? premarca(id)
    }

    /// Lo premarcado de una pregunta: lo que sabe la ruta, lo de la carpeta o lo que propone el motor.
    func premarca(_ id: PreguntaID) -> Respuesta? {
        // En una empresa nueva la carpeta recién creada ya tiene sus seis áreas: el motivo no es que «ya esté organizada».
        if id == .alcance, ruta == .empresaNueva {
            return Respuesta(valor: .opcion("todo"), origen: .propuesta("Recomendado: tu empresa es nueva y así dejo preparadas sus seis áreas"),
                             confirmada: false)
        }
        return contexto.premarcada(id) ?? premarcadaPorElMotor(id)
    }

    /// Lo que propone el motor con otras respuestas (la meta 1,2 × los últimos 90 días…).
    func premarcadaPorElMotor(_ id: PreguntaID) -> Respuesta? {
        for a in AreaCode.allCases where id == .meta(a) || id == .alerta(a) {
            guard let codigo = valor(.numeroClave(a))?.opcion, let def = contexto.catalogo.kpi(codigo) else { return nil }
            // Si Metas ya lo tiene decidido, eso.
            if let fila = contexto.metas?.fila(codigo) {
                let u = id == .meta(a) ? fila.meta : fila.alerta
                if u.fijado, let n = u.numero {
                    return Respuesta(valor: .numero(n), origen: .carpeta(contexto.rutaMetas), confirmada: false)
                }
                if ["sin meta", "sin alerta"].contains(TextFolding.fold(u.texto)) {
                    return Respuesta(valor: .opcion("sin-meta"), origen: .carpeta(contexto.rutaMetas), confirmada: false)
                }
            }
            guard def.sentido != .rango else { return nil }
            let unidad = def.unidad
            func redondeo(_ n: Double) -> Double { unidad == "€" ? (n / 10).rounded() * 10 : (n * 10).rounded() / 10 }
            // 1,2 × lo de los últimos 90 días (PLAN §6.7, paso 6), si hubo algo; si no, la propuesta de la nota Metas.
            if let base = contexto.base90Dias(codigo), base > 0 {
                if id == .meta(a) {
                    let texto = "Propuesto: 1,2 × lo de los últimos 90 días (\(MetasEscritor.texto(base, unidad: unidad)))"
                    return Respuesta(valor: .numero(redondeo(def.sentido == .menos ? base / 1.2 : base * 1.2)),
                                     origen: .propuesta(texto), confirmada: false)
                }
                let alerta = def.sentido == .menos ? base * 1.2 : base * 0.8
                return Respuesta(valor: .numero(redondeo(alerta)), origen: .propuesta("Propuesto: si se aleja un 20 % de lo de ahora"),
                                 confirmada: false)
            }
            if let p = Self.propuestaDeMetas(contexto.metas?.fila(codigo)?.porQue ?? "", meta: id == .meta(a)) {
                return Respuesta(valor: .numero(p), origen: .propuesta("Lo propone la nota Metas"), confirmada: false)
            }
            return nil
        }
        return nil
    }

    /// «Propuesta: meta 3 meses, alerta 1 mes» (columna «Por qué» de Metas) → la cifra de la meta o de la alerta.
    static func propuestaDeMetas(_ porQue: String, meta: Bool) -> Double? {
        let t = TextFolding.fold(porQue)
        guard t.contains("propuesta") else { return nil }
        let clave = meta ? "meta" : "alerta"
        guard let r = t.range(of: clave + " ") else { return nil }
        // Hasta el siguiente «; », «, » o «. » (la coma decimal de «2,5 meses» no corta).
        var resto = String(t[r.upperBound...])
        for corte in ["; ", ", ", ". ", ";"] { if let c = resto.range(of: corte) { resto = String(resto[..<c.lowerBound]) } }
        return Umbral(texto: resto).numero
    }

    /// Guarda una respuesta y repregunta una vez si es vaga (PLAN §6.7, entrevistador).
    @discardableResult
    public mutating func responder(_ id: PreguntaID, _ valor: ValorRespuesta) async -> ResultadoRespuesta {
        let anterior = estado.respuesta(id)
        var r = Respuesta(valor: valor, origen: .persona, confirmada: true, repreguntada: anterior?.repreguntada ?? false)
        // Si la persona deja lo premarcado tal cual, se conserva su origen (no se reescribe donde ya estaba).
        if let pre = premarca(id), pre.valor == valor {
            r.origen = pre.origen
        }
        var resultado = ResultadoRespuesta.guardada
        if !r.repreguntada, let p = pregunta(id), p.repregunta != nil, case .texto(let t) = valor, r.origen.clase == .persona {
            let usar = estado.usarAsistente == true
            if case .repreguntar(let texto) = await entrevista.valorar(p, respuesta: t, conAsistente: usar,
                                                                          privado: contexto.nombresPrivados) {
                r.repreguntada = true
                resultado = .repreguntar(texto)
            }
        }
        estado.respuestas[id.rawValue] = r
        if id == .asistente, case .siNo(let b) = valor { estado.usarAsistente = b }
        estado.pantalla = pantallaActual?.id ?? estado.pantalla
        guardar()
        return resultado
    }

    /// «No lo sé»: se guarda y se escribirá PENDIENTE (criterio F3-5).
    public mutating func noLoSe(_ id: PreguntaID) {
        estado.respuestas[id.rawValue] = Respuesta(valor: .noLoSe, origen: .persona)
        guardar()
    }

    /// Olvida una respuesta (vuelve a lo premarcado o a preguntarse en blanco). Sirve, por ejemplo, al cambiar la
    /// carpeta de origen: lo privado contestado era de la otra.
    public mutating func olvidar(_ id: PreguntaID) {
        guard estado.respuestas.removeValue(forKey: id.rawValue) != nil else { return }
        guardar()
    }

    /// Las preguntas de una pantalla que no llegan premarcadas (ni de la carpeta ni propuestas). En un resumen van
    /// aparte, plegadas en «Lo que falta», con «Lo contesto luego». Las opcionales se quedan en su sitio, salvo las
    /// ofertas 2 y 3 si tampoco hay oferta 1 (van juntas).
    public func enBlanco(_ p: Pantalla) -> [Pregunta] {
        let qs = preguntas(de: p)
        let sinOferta = qs.contains { $0.id == .ofertaNombre(1) && $0.premarcada == nil }
        return qs.filter { q in
            guard q.premarcada == nil else { return false }
            if q.id.rawValue.hasPrefix("organizar.oferta.") { return sinOferta }
            return !q.esOpcional
        }
    }

    /// «Lo contesto luego»: las que siguen sin respuesta quedan como «No lo sé» (se escribe PENDIENTE, criterio F3-5).
    public mutating func contestarLuego(_ ids: [PreguntaID]) {
        for id in ids where estado.respuesta(id) == nil && pregunta(id)?.admiteNoLoSe != false {
            estado.respuestas[id.rawValue] = Respuesta(valor: .noLoSe, origen: .persona)
        }
        guardar()
    }

    /// Da por buenas las premarcadas de la pantalla actual que la persona no ha tocado.
    public mutating func confirmarPremarcadas() {
        guard let p = pantallaActual else { return }
        for q in preguntas(de: p) where estado.respuesta(q.id) == nil {
            if var pre = q.premarcada { pre.confirmada = true; pre.fecha = Date(); estado.respuestas[q.id.rawValue] = pre }
        }
        guardar()
    }

    // MARK: Ruta y alcance

    /// La ruta: la guardada o la que sale de «¿Cómo empiezas?» y de lo que hay en la carpeta.
    public var ruta: RutaPuesta {
        if let r = estado.ruta { return r }
        switch valor(.como)?.opcion {
        case "cero": return .empresaNueva
        case "ejemplo": return .ejemplo
        case "carpeta": return contexto.foto == nil ? .carpetaPorOrdenar : (contexto.organizada ? .copiaG3 : .carpetaPorOrdenar)
        default: return contexto.rutaDetectada
        }
    }

    /// «Ver sin tocar»: la carpeta real solo se mira; no hay más pasos.
    public var soloMirar: Bool { valor(.modo)?.opcion == "ver" }

    public var alcance: AlcancePuesta { valor(.alcance)?.opcion.flatMap(AlcancePuesta.init(rawValue:)) ?? .todo }

    /// El sistema del estándar elegido en «Un proceso».
    public var procesoElegido: SistemaStd? {
        guard alcance == .proceso, let c = valor(.alcanceProceso)?.opcion else { return nil }
        return contexto.catalogo.sistemas.first { $0.codigo == c }
    }

    /// Las áreas que entran en esta puesta en marcha.
    public var areasDelAlcance: [AreaCode] {
        switch alcance {
        case .todo: return AreaCode.allCases
        case .area: return [valor(.alcanceArea)?.opcion.flatMap(AreaCode.init(rawValue:)) ?? .direccion]
        case .proceso: return [procesoElegido?.area ?? .direccion]
        }
    }

    public func estadoArea(_ a: AreaCode) -> EstadoAreaPuesta? {
        valor(.estadoArea(a))?.opcion.flatMap(EstadoAreaPuesta.init(rawValue:))
    }

    /// Áreas activas o preparadas del alcance (sin contestar cuentan: así «Quedan ~N min» no se queda corto).
    public var areasConDetalle: [AreaCode] {
        areasDelAlcance.filter { estadoArea($0) != .reposo }
    }

    /// Áreas activas del alcance (sin contestar cuentan como activas, por lo mismo).
    public var areasActivas: [AreaCode] {
        areasDelAlcance.filter { let e = estadoArea($0); return e == nil || e == .activa }
    }

    /// Los sistemas de «Qué funciona sin ti»: los mismos de Organizar (con los mismos nombres), de las áreas activas y
    /// con funciones en el estándar. Los que Organizar dio por «Falta» no salen: no hay nada que preguntar.
    public var sistemasSinTi: [SistemaCatalogo] {
        let candidatos: [SistemaCatalogo]
        if let p = procesoElegido {
            candidatos = areasActivas.contains(p.area) ? (SistemaCatalogo.deEstandar(p.codigo).map { [$0] } ?? []) : []
        } else {
            candidatos = areasActivas.flatMap { SistemaCatalogo.de($0) }.filter { !$0.estandar.isEmpty }
        }
        return candidatos.filter { valor(.sistema($0.codigo))?.opcion != "falta" }
    }

    /// Lo que dijo Organizar de un sistema (montado, a medias, falta o «No lo sé»).
    public func montadoEnOrganizar(_ codigo: String) -> ValorRespuesta? { valor(.sistema(codigo)) }

    /// Los pasos que siguen, según la ruta y el alcance.
    public var pasosIncluidos: [PasoPuesta] {
        if ruta == .ejemplo || soloMirar { return [.bienvenida] }
        var p: [PasoPuesta] = [.bienvenida, .alcance]
        if alcance != .proceso { p.append(.conocer) }
        if ruta.conCarpeta, alcance != .proceso { p.append(.ordenar) }
        p.append(.organizar)
        if !sistemasSinTi.isEmpty { p.append(.sinTi) }
        if alcance != .proceso { p.append(.diaADia) }
        p += [.numeros, .conectar, .recorrido]
        return p
    }

    // MARK: Pantallas

    /// Todas las pantallas de esta puesta en marcha, en orden (cambian con las respuestas).
    public var pantallas: [Pantalla] { pasosIncluidos.flatMap(pantallas(de:)) }

    public var pantallaActual: Pantalla? {
        let todas = pantallas
        if let id = estado.pantalla, let p = todas.first(where: { $0.id == id }) { return p }
        return todas.first { !pasoHecho($0.paso) } ?? todas.last
    }

    public var indiceActual: Int { pantallas.firstIndex { $0.id == pantallaActual?.id } ?? 0 }

    func pasoHecho(_ p: PasoPuesta) -> Bool { estado.paso(p).fase != .pendiente }

    /// Las preguntas que se ven en una pantalla (las condicionadas solo si toca).
    public func preguntas(de pantalla: Pantalla) -> [Pregunta] {
        pantalla.preguntas.filter(visible).compactMap(pregunta)
    }

    /// Las preguntas de la pantalla actual.
    public var preguntasActuales: [Pregunta] { pantallaActual.map(preguntas(de:)) ?? [] }

    func visible(_ id: PreguntaID) -> Bool {
        switch id {
        case .privadasCuales: return valor(.privadas)?.opcion == "si"
        case .alcanceArea: return alcance == .area
        case .alcanceProceso: return alcance == .proceso
        case .embudoEtapas: return valor(.embudo)?.opcion == "propio"
        case .logoFichero: return valor(.logo)?.opcion == "tengo"
        case .logoWeb: return valor(.logo)?.opcion == "web"
        case .objetivoCifra: return valor(.objetivo)?.opcion == "facturacion"
        default: break
        }
        let s = id.rawValue
        for a in AreaCode.allCases {
            // Sin número clave («No lo sé») no hay meta ni alerta que fijar.
            if id == .meta(a) || id == .alerta(a) { return valor(.numeroClave(a))?.esNoLoSe != true }
            for n in 2...6 where id == .etapaPregunta(a, n) {
                // Se para en el primer «no» (o «No lo sé»).
                return (1..<n).allSatisfy { valor(.etapaPregunta(a, $0))?.siNo == true }
            }
        }
        // Qué funciona sin ti: solo de lo que Organizar dio por montado (no se vuelve a preguntar si está montado).
        if s.hasPrefix("sinti."), s.hasSuffix(".sinti") || s.hasSuffix(".automatizar") {
            let codigo = String(s.split(separator: ".").dropFirst().first ?? "")
            return montadoEnOrganizar(codigo)?.opcion == "montado"
        }
        if s.hasPrefix("sinti."), s.hasSuffix(".montado") { return false }
        return true
    }

    /// Pantallas de un paso.
    public func pantallas(de paso: PasoPuesta) -> [Pantalla] {
        func p(_ id: String, _ tipo: TipoPantalla, _ titulo: String, _ explicacion: String, _ preguntas: [PreguntaID],
               area: AreaCode? = nil, vista: Bool = false, aplica: Bool = false) -> Pantalla {
            Pantalla(id: id, paso: paso, tipo: tipo, titulo: titulo, explicacion: explicacion, preguntas: preguntas,
                     area: area, conVistaPrevia: vista, aplicaAqui: aplica)
        }
        /// Con una sola pantalla de preguntas, la vista previa y «Aplicar» van en ella; con más, al final, aparte.
        func conVista(_ ps: [Pantalla], titulo: String, explicacion: String) -> [Pantalla] {
            guard ps.count != 1 else {
                let x = ps[0]
                return [Pantalla(id: x.id, paso: x.paso, tipo: x.tipo, titulo: x.titulo, explicacion: x.explicacion,
                                 preguntas: x.preguntas, area: x.area, conVistaPrevia: true, aplicaAqui: true)]
            }
            return ps + [p("\(paso.rawValue).vista", .vistaPrevia, titulo, explicacion, [], vista: true, aplica: true)]
        }
        let organizada = ruta == .copiaG3
        switch paso {
        case .bienvenida:
            var out = [p("bienvenida.como", .eleccion, "¿Cómo empiezas?",
                         "Vamos a poner en marcha tu empresa en la app. Nada se escribe hasta que pulses «Aplicar», y todo se puede deshacer.",
                         [.como])]
            switch valor(.como)?.opcion {
            case "carpeta":
                out.append(p("bienvenida.carpeta", .formulario, "Tu carpeta",
                             "Trabajo sobre una copia: tu carpeta original no se toca. Antes de que macOS te pregunte por el acceso, elige la carpeta y dime qué es privado: eso no se copia ni se mira.",
                             [.origen, .modo, .privadas, .privadasCuales], vista: true, aplica: true))
                if estado.permisoDenegado {
                    out.append(p("bienvenida.recuperacion", .informativa, "Sin permiso para leer tu carpeta",
                                 "macOS no ha dejado leer la carpeta. Abre Ajustes del Sistema › Privacidad y seguridad › Archivos y carpetas, da permiso a The Last System y vuelve a intentarlo.",
                                 []))
                }
            case "cero":
                out.append(p("bienvenida.empresa", .formulario, "Tu empresa",
                             "Con esto creo la carpeta de tu empresa en tu Mac, con sus seis áreas. Lo que no sepas, déjalo para luego.",
                             [.nombreEmpresa, .yo, .sector, .ciudad, .personas]))
                out.append(p("bienvenida.vista", .vistaPrevia, "Lo que voy a crear",
                             "Esta es la carpeta que nacerá. Revísala y pulsa «Crear la carpeta».", [], vista: true, aplica: true))
            default:
                break
            }
            return out
        case .alcance:
            return [p("alcance.cual", .eleccion, "¿Por dónde empezamos?",
                      "Puedes poner en marcha un solo proceso, un área o todo. Cuanto menos abarques, antes acabas.",
                      [.alcance, .alcanceArea, .alcanceProceso, .asistente])]
        case .conocer:
            let areas = areasDelAlcance
            if organizada {
                var qs: [PreguntaID] = [.camino, .metaGeneral] + PreguntaID.huecosDeLaFrase + [.destino]
                for a in areas { qs += [.funciona(a), .depende(a), .etapa(a)] }
                return [p("conocer.resumen", .resumen, "Lo que ya sé de tu negocio",
                          explicacionResumen(qs, cierre: "Confírmalo o cámbialo; lo que no encontré está en «Lo que falta»."),
                          qs, vista: true, aplica: true)]
            }
            var out = [
                p("conocer.encuadre", .eleccion, "Qué buscas",
                  "Dos preguntas para saber hacia dónde tirar.", [.camino, .metaGeneral]),
                p("conocer.frase", .formulario, "La frase de tu negocio",
                  "«Ayudamos a… a conseguir… en… con…, sin…». Rellena los cinco huecos con tus palabras.",
                  PreguntaID.huecosDeLaFrase),
                p("conocer.destino", .textoLibre, "Adónde quieres llegar",
                  "Escríbelo con tus palabras y, si puedes, con un número. Lo copio tal cual.", [.destino]),
            ]
            for a in areas {
                var qs: [PreguntaID] = [.funciona(a), .depende(a), .dolor(a), .metaArea(a)]
                qs += (1...6).map { .etapaPregunta(a, $0) }
                qs.append(.cita(a))
                out.append(p("conocer.area.\(a.rawValue)", .formulario, a.nombre,
                             "Cómo \(TextosPuesta.funciona(a)) hoy \(TextosPuesta.nombreComun(a)) y cuánto depende de ti. Para la etapa, contesta sí o no: en cuanto digas «no», ya la sé.",
                             qs, area: a))
            }
            out.append(p("conocer.entendido", .vistaPrevia, "Lo que he entendido",
                         "La foto de tus áreas, dónde está el cuello y en qué etapa veo cada una. Si estás de acuerdo, «Aplicar» lo escribe en tu Diagnóstico y tu Rumbo.",
                         [], vista: true, aplica: true))
            return out
        case .ordenar:
            let n = estado.ordenar?.pantallas ?? (organizada ? 3 : 7)
            let titulos = estado.ordenar?.titulos ?? (organizada ? Self.titulosOrdenarG3 : Self.titulosOrdenar)
            let explicaciones = estado.ordenar?.explicaciones ?? []
            return (1...max(1, n)).map { i in
                let titulo = i <= titulos.count ? titulos[i - 1] : "Ordenar"
                // La explicación de cada pantalla (la del importador o, si no la trae, la de su título).
                let explicacion = (i <= explicaciones.count ? explicaciones[i - 1] : nil)
                    ?? ResumenOrdenar.explicacion(titulo)
                    ?? "Pongo cada cosa en su sitio sin borrar nada. Verás todo antes de aplicarlo."
                return p("ordenar.\(i)", .delegada, titulo, explicacion, [], vista: i == n, aplica: i == n)
            }
        case .organizar:
            let areas = areasDelAlcance
            let conDetalle = areasConDetalle
            let logo: [PreguntaID] = (areas.contains(.marca) || alcance == .todo) ? [.logo, .logoFichero, .logoWeb] : []
            let vocabulario = TextosPuesta.terminosVocabulario.map { PreguntaID.vocabulario($0.clave) }
            if organizada {
                var qs: [PreguntaID] = []
                for a in areas {
                    qs.append(.estadoArea(a))
                    if conDetalle.contains(a) { qs += preguntasOrganizar(a) }
                }
                qs += logo + vocabulario
                return [p("organizar.resumen", .resumen, "Cómo está organizada tu empresa",
                          explicacionResumen(qs, cierre: "Confírmalo o cámbialo y te preparo lo que falta."),
                          qs, vista: true, aplica: true)]
            }
            var out = [p("organizar.estados", .formulario, "El estado de cada área",
                         "Activa, si trabajas en ella cada semana; preparada, si está escrita pero aún no; en reposo, si por ahora no toca. Si quieres, dime también cómo llamas tú a algunas cosas.",
                         areas.map { .estadoArea($0) } + vocabulario)]
            for a in conDetalle {
                var qs = preguntasOrganizar(a)
                if a == .marca { qs += logo }
                out.append(p("organizar.area.\(a.rawValue)", .formulario, a.nombre,
                             "Quién lleva \(TextosPuesta.nombreComun(a)) y cómo están sus sistemas. Te dejo preparado lo que falta.",
                             qs, area: a))
            }
            if !logo.isEmpty, !conDetalle.contains(.marca) {
                out.append(p("organizar.logo", .formulario, "Tu logo",
                             "Lo usan todos tus documentos. Si no lo tienes a mano, lo apunto para después.", logo, area: .marca))
            }
            return conVista(out, titulo: "Lo que voy a preparar",
                            explicacion: "Fichas de área, roles, oferta y sistemas que faltan. Revísalo y pulsa «Aplicar».")
        case .sinTi:
            let sistemas = sistemasSinTi
            let areas = AreaCode.allCases.filter { a in sistemas.contains { $0.area == a } }
            var grupos: [[AreaCode]] = []
            // En una carpeta organizada, todo en una pantalla para confirmar; si no, dos áreas por pantalla.
            let porPantalla = organizada ? 6 : 2
            for a in areas { if let u = grupos.last, u.count < porPantalla { grupos[grupos.count - 1].append(a) } else { grupos.append([a]) } }
            let ps = grupos.enumerated().map { i, g in
                p("sin-ti.\(i + 1)", .formulario, TextosPuesta.listaDeAreas(g),
                  "Los sistemas que en Organizar dijiste que tienes montados: ¿funcionan sin ti? Si dices que sí a dejar uno a un asistente, lo hará y tú lo revisarás; en 7 días te lo recuerdo.",
                  g.flatMap { a in sistemas.filter { $0.area == a }.flatMap { [PreguntaID.sinTi($0.codigo), .automatizar($0.codigo)] } })
            }
            return conVista(ps, titulo: "Lo que funciona sin ti",
                            explicacion: "Así queda lo que funciona sin ti y lo que revisarás. Revísalo y pulsa «Aplicar».")
        case .diaADia:
            return [p("dia-a-dia.rutina", .formulario, "Tu día a día",
                      "Una sola rutina semanal para mirar la empresa (el lunes, 30 minutos, si te va bien) y cuántas horas al día quieres planificar como mucho.",
                      [.rutinaDia, .rutinaHora, .rutinaDuracion, .topeHoras], vista: true, aplica: true)]
        case .numeros:
            let areas = areasActivas
            var grupos: [[AreaCode]] = []
            let porPantalla = organizada ? 6 : 3
            for a in areas { if let u = grupos.last, u.count < porPantalla { grupos[grupos.count - 1].append(a) } else { grupos.append([a]) } }
            if grupos.isEmpty { grupos = [[]] }
            let ps = grupos.enumerated().map { i, g in
                var qs = g.flatMap { [PreguntaID.numeroClave($0), .meta($0), .alerta($0)] }
                if i == grupos.count - 1 { qs += [.objetivo, .objetivoCifra] }
                return p("numeros.\(i + 1)", .formulario, g.isEmpty ? "Tu objetivo" : "Tus números",
                         "Un número por área. Fija la meta y la alerta antes de ver el dato; si no lo tienes claro, «Sin meta».", qs)
            }
            return conVista(ps, titulo: "Tus metas", explicacion: "Así quedan tus metas. Revísalas y pulsa «Aplicar».")
        case .conectar:
            return [p("conectar", .formulario, "Conectar",
                      "Lo que quieras conectar ahora. Cada fila tiene «Ahora no» y lo puedes cambiar cuando quieras. Lo único que se anota en tu carpeta es quién trabaja (por ejemplo, el Cartero si conectas Mail), como tú y se puede deshacer.",
                      ConexionPuesta.allCases.map { .conexion($0) })]
        case .recorrido:
            return [p("recorrido", .informativa, "Primer recorrido",
                      "Cinco cosas para probar con tu empresa: Hoy, el área del cuello (la que más frena a las demás), la primera propuesta de Mika (tu asistente de Dirección), editar una ficha y verla en Finder.",
                      [.recorrido])]
        }
    }

    /// La explicación de un resumen: de dónde salen de verdad sus respuestas premarcadas (los ficheros que se han
    /// leído), o que no se encontró nada.
    func explicacionResumen(_ ids: [PreguntaID], cierre: String) -> String {
        // Solo depende de lo que hay en la carpeta: se calcula una vez por foto.
        contexto.enCache("explicacion." + cierre + "|" + ids.map(\.rawValue).joined(separator: ",")) {
            explicacionResumenSinCache(ids, cierre: cierre)
        }
    }

    func explicacionResumenSinCache(_ ids: [PreguntaID], cierre: String) -> String {
        var nombres: [String] = []
        var areas = false, sistemas = false, calculado = false
        for id in ids {
            guard let r = contexto.premarcada(id) else { continue }
            if r.origen.clase == .propuesta, r.origen.texto.hasPrefix("Lo calculé") { calculado = true }
            guard r.origen.clase == .carpeta, let f = r.origen.fuente else { continue }
            if f.name == AreaReader.fileName { areas = true; continue }
            if f.components.contains("Sistemas") { sistemas = true; continue }
            if !nombres.contains(f.stem) { nombres.append(f.stem) }
        }
        var partes = Array(nombres.prefix(3))
        if nombres.count > 3 { partes.append("\(nombres.count - 3) notas más") }
        if areas { partes.append("la nota de cada área") }
        if sistemas { partes.append("las fichas de tus sistemas") }
        guard !partes.isEmpty else {
            return (calculado ? "Lo he calculado con lo que hay en tu carpeta; no he encontrado nada escrito. " : "No he encontrado nada de esto en tu carpeta. ")
                + cierre
        }
        let lista = partes.count == 1 ? partes[0] : partes.dropLast().joined(separator: ", ") + " y " + partes.last!
        return "Lo he sacado de \(lista). " + cierre
    }

    static let titulosOrdenarG3 = ["Completar las fichas", "Movimientos del banco", "Calidad"]
    static let titulosOrdenar = ["Lo que hay", "Preparar", "Por programa", "Repetidos", "Vista previa", "Comprobación", "Calidad"]

    func preguntasOrganizar(_ a: AreaCode) -> [PreguntaID] {
        var qs: [PreguntaID] = [.ocupante(a)]
        qs += SistemaCatalogo.de(a).map { .sistema($0.codigo) }
        if a == .direccion { qs.append(.sistema("CO1")) }
        switch a {
        case .ventas:
            qs += (1...3).flatMap { [PreguntaID.ofertaNombre($0), .ofertaPrecio($0)] }
            qs += [.embudo, .embudoEtapas]
        case .entrega:
            qs.append(.planEntrega)
        default: break
        }
        return qs
    }

    // MARK: Navegar

    /// Preguntas de la pantalla actual que faltan por contestar (ni respuesta, ni premarcada, ni «No lo sé»).
    public var faltan: [PreguntaID] {
        preguntasActuales.filter { q in
            guard !q.esOpcional else { return false }
            return estado.respuesta(q.id) == nil && q.premarcada == nil
        }.map(\.id)
    }

    /// «Siguiente»: confirma lo premarcado, comprueba lo obligatorio y avanza.
    public mutating func siguiente() -> ResultadoAvance {
        guard let actual = pantallaActual else { return .terminada }
        let f = faltan
        guard f.isEmpty else { return .faltan(f) }
        confirmarPremarcadas()
        if actual.aplicaAqui, actual.paso.escribeEnLaCarpeta, estado.paso(actual.paso).fase == .pendiente {
            return .faltaAplicar(actual.paso)
        }
        // Los pasos que no escriben en la carpeta se dan por hechos al dejarlos.
        if !actual.paso.escribeEnLaCarpeta, estado.paso(actual.paso).fase == .pendiente,
           pantallas(de: actual.paso).last?.id == actual.id {
            estado.ponerPaso(actual.paso, EstadoPaso(fase: .aplicado, aplicado: Date(), resumen: "Guardado (nada en tu carpeta)"))
        }
        let todas = pantallas
        guard let i = todas.firstIndex(where: { $0.id == actual.id }), i + 1 < todas.count else {
            estado.terminado = estado.terminado ?? Date()
            guardar(conMinutos: true)
            return .terminada
        }
        estado.pantalla = todas[i + 1].id
        guardar(conMinutos: true)
        return .pantalla(todas[i + 1])
    }

    /// «Atrás».
    public mutating func anterior() {
        let todas = pantallas
        guard let i = todas.firstIndex(where: { $0.id == pantallaActual?.id }), i > 0 else { return }
        estado.pantalla = todas[i - 1].id
        guardar(conMinutos: true)
    }

    /// Ir a una pantalla concreta (repasar un paso).
    public mutating func ir(a id: String) {
        guard pantallas.contains(where: { $0.id == id }) else { return }
        estado.pantalla = id
        guardar(conMinutos: true)
    }

    /// Omitir un paso que escribe (no se escribe nada; se puede volver a él).
    public mutating func omitir(_ paso: PasoPuesta) {
        estado.ponerPaso(paso, EstadoPaso(fase: .omitido, resumen: "Lo dejaste para más tarde"))
        guardar(conMinutos: true)
    }

    /// Tras «Aplicar»: el paso queda hecho con su plan (para «Deshacer»).
    public mutating func marcarAplicado(_ paso: PasoPuesta, plan: UUID?, resumen: String) {
        estado.ponerPaso(paso, EstadoPaso(fase: .aplicado, plan: plan, aplicado: Date(), resumen: resumen))
        guardar(conMinutos: true)
    }

    /// Tras «Deshacer»: el paso vuelve a estar pendiente (con las mismas respuestas).
    public mutating func marcarDeshecho(_ paso: PasoPuesta) {
        estado.ponerPaso(paso, EstadoPaso())
        estado.terminado = nil
        guardar(conMinutos: true)
    }

    /// Lo que deja el paso 2 (lo llama el importador): sus pantallas y lo que hizo.
    public mutating func registrarOrdenar(_ r: ResumenOrdenar, aplicado: Bool) {
        estado.ordenar = r
        if aplicado { estado.ponerPaso(.ordenar, EstadoPaso(fase: .aplicado, plan: r.planes.last, aplicado: Date(), resumen: r.texto)) }
        guardar(conMinutos: true)
    }

    /// Tras la copia (paso 0 con carpeta): la puesta en marcha sigue en la carpeta nueva.
    public mutating func registrarCopia(_ entrada: VaultEntry, root: URL, appSupport: URL = AppLocations.appSupport) {
        let antes = estado.vaultID
        estado.vaultID = entrada.id
        contexto = ContextoCarpeta.leer(root, entrada: entrada, reloj: contexto.reloj, catalogo: contexto.catalogo)
        estado.ruta = contexto.organizada ? .copiaG3 : .carpetaPorOrdenar
        estado.ponerPaso(.bienvenida, EstadoPaso(fase: .aplicado, aplicado: Date(), resumen: "Copia hecha en «\(entrada.nombre)»"))
        if let a = almacen, antes != entrada.id {
            let nuevo = AlmacenPuesta(vaultID: entrada.id, appSupport: a.appSupport)
            // Solo se quita el de antes si el nuevo quedó guardado (si no, se seguiría guardando en el de antes).
            guard (try? nuevo.guardar(estado)) != nil else { guardar(); return }
            a.retirar()
            self = OnboardingEngine(estado: estado, contexto: contexto, almacen: nuevo, entrevista: entrevista)
        }
        guardar(conMinutos: true)
    }

    /// El permiso de macOS para leer la carpeta se denegó: aparece la pantalla de recuperación.
    public mutating func permisoDenegado(_ si: Bool) {
        estado.permisoDenegado = si
        guardar()
    }

    /// Marca un hito del primer recorrido.
    public mutating func marcarHito(_ h: HitoRecorrido, fecha: Date = Date()) {
        if estado.recorrido[h.rawValue] == nil { estado.recorrido[h.rawValue] = fecha }
        guardar()
    }

    // MARK: Contadores

    /// «Quedan ~N min» desde la pantalla actual (incluida), contando las preguntas que de verdad quedan.
    public var quedanMinutos: Int {
        let todas = pantallas
        let i = todas.firstIndex { $0.id == pantallaActual?.id } ?? 0
        let m = todas[i...].reduce(0) { $0 + minutos(de: $1) }
        return max(1, Int(m.rounded(.up)))
    }

    /// Lo que se tarda en una pantalla. Un resumen: un vistazo a lo premarcado y algo más por cada pregunta en blanco
    /// que siga sin contestar (no 2 minutos tenga las que tenga). Un formulario largo, por sus preguntas.
    public func minutos(de p: Pantalla) -> Double {
        switch p.tipo {
        case .resumen:
            let qs = preguntas(de: p)
            let blancas = qs.filter { $0.premarcada == nil && !$0.esOpcional && estado.respuesta($0.id) == nil }.count
            return max(1, 0.5 + 0.05 * Double(qs.count - blancas) + 0.2 * Double(blancas))
        case .formulario:
            return max(p.tipo.minutos, 0.2 * Double(preguntas(de: p).count))
        default:
            return p.tipo.minutos
        }
    }

    /// «Paso N de M» (el alcance cuenta con la bienvenida).
    public var progreso: ProgresoPuestaEnMarcha {
        var grupos: [PasoPuesta] = []
        for p in pasosIncluidos where !grupos.contains(p.grupoVisible) { grupos.append(p.grupoVisible) }
        // Leído sin la carpeta (Hoy, el arranque), puede que la pantalla guardada no esté en la lista: su paso sale de su
        // identificador («organizar.resumen» → Organizar).
        var paso = pantallaActual?.paso ?? .bienvenida
        if let id = estado.pantalla, !pantallas.contains(where: { $0.id == id }),
           let p = PasoPuesta(rawValue: String(id.split(separator: ".").first ?? "")) {
            paso = p
        }
        let n = (grupos.firstIndex(of: paso.grupoVisible) ?? 0) + 1
        return ProgresoPuestaEnMarcha(paso: paso, numero: n, total: grupos.count,
                                      quedanMinutos: quedanMinutos, terminada: estado.terminada, enPausa: estado.enPausa)
    }

    // MARK: Vista previa

    /// Lo que escribirá un paso al aplicar, con su vista previa (lee la carpeta; no escribe nada).
    public func vistaPrevia(_ paso: PasoPuesta) throws -> VistaPreviaPaso {
        try PlanesPuesta(motor: self).preparar(paso)
    }

    // MARK: El ejemplo

    /// Ribera con la puesta en marcha ya hecha (se puede repasar paso a paso). Las respuestas son lo que hay en la
    /// carpeta, todas confirmadas.
    public static func ejemploCompletado(contexto: ContextoCarpeta, vaultID: UUID, persona: String = "Manu",
                                         almacen: AlmacenPuesta? = nil) -> OnboardingEngine {
        var e = EstadoPuestaEnMarcha(vaultID: vaultID, ruta: .copiaG3, persona: persona)
        var m = OnboardingEngine(estado: e, contexto: contexto, almacen: almacen)
        e.respuestas[PreguntaID.como.rawValue] = Respuesta(valor: .opcion("ejemplo"), origen: .propuesta("Es el ejemplo"))
        e.respuestas[PreguntaID.alcance.rawValue] = Respuesta(valor: .opcion("todo"), origen: .propuesta("Es el ejemplo"))
        m.estado = e
        // Lo que dice la carpeta y, lo que no, las respuestas del ejemplo (para que se vea completo al repasarlo). Varias
        // pasadas: al contestar aparecen preguntas que dependen de otras (los sistemas montados del paso 4).
        for _ in 0..<3 {
            for pantalla in m.pantallas {
                for q in m.preguntas(de: pantalla) where e.respuestas[q.id.rawValue] == nil {
                    if var pre = q.premarcada {
                        pre.confirmada = true
                        e.respuestas[q.id.rawValue] = pre
                    } else if let v = RespuestasDelEjemplo.ribera[q.id.rawValue] {
                        e.respuestas[q.id.rawValue] = Respuesta(valor: v, origen: RespuestasDelEjemplo.origen, confirmada: true,
                                                                 fecha: e.creado)
                    }
                }
            }
            m.estado = e
        }
        for paso in PasoPuesta.allCases {
            e.ponerPaso(paso, EstadoPaso(fase: .aplicado, aplicado: e.creado, resumen: "Ya estaba hecho en el ejemplo"))
        }
        e.terminado = e.creado
        e.pantalla = m.pantallas.first?.id
        m.estado = e
        m.guardar()
        return m
    }
}

extension Pregunta {
    /// Se puede dejar en blanco (las ofertas 2 y 3, el vocabulario, la web del logo…).
    public var esOpcional: Bool {
        let s = id.rawValue
        if s.hasPrefix("organizar.vocabulario.") { return true }
        if s.hasPrefix("organizar.oferta.2") || s.hasPrefix("organizar.oferta.3") { return true }
        if s.hasSuffix(".precio") { return true }
        return [.origen, .sector, .ciudad, .personas, .embudoEtapas, .logoWeb, .objetivoCifra].contains(id)
    }
}
