import Foundation

// F3 · rol motor. Texto y forma de cada pregunta por su identificador. Corto, sin jerga y con un ejemplo cuando
// ayuda. El premarcado lo pone el motor (`OnboardingEngine.pregunta(_:)`).

enum CatalogoPreguntas {
    static func pregunta(_ id: PreguntaID, contexto: ContextoCarpeta, motor: OnboardingEngine) -> Pregunta? {
        func q(_ paso: PasoPuesta, _ texto: String, _ tipo: TipoPregunta, area: AreaCode? = nil, ayuda: String? = nil,
               noLoSe: Bool = true, obligatoria: Bool = false, repregunta: String? = nil) -> Pregunta {
            Pregunta(id: id, paso: paso, area: area, texto: texto, ayuda: ayuda, tipo: tipo, admiteNoLoSe: noLoSe,
                     obligatoria: obligatoria, repregunta: repregunta)
        }
        switch id {
        case .como:
            return q(.bienvenida, "¿Cómo empiezas?", .eleccion([
                OpcionPregunta("carpeta", "Tengo una carpeta", detalle: "Trabajo sobre una copia; la tuya no se toca."),
                OpcionPregunta("cero", "Empiezo de cero", detalle: "Creo la carpeta de tu empresa con sus seis áreas."),
                OpcionPregunta("ejemplo", "Ver un ejemplo", detalle: "Asesoría Ribera, una empresa ficticia, ya en marcha."),
            ]), noLoSe: false)
        case .origen:
            return q(.bienvenida, "¿Qué carpeta es la de tu empresa?", .rutas(carpetas: true, varias: false), noLoSe: false)
        case .modo:
            return q(.bienvenida, "¿Cómo quieres trabajar con ella?", .eleccion([
                OpcionPregunta("copia", "Trabajar sobre una copia (recomendado)", detalle: "Tu carpeta original no se toca nunca."),
                OpcionPregunta("ver", "Ver sin tocar", detalle: "Solo miro tu carpeta; no se cambia nada."),
            ]), noLoSe: false)
        case .privadas:
            return q(.bienvenida, "¿Hay carpetas privadas que no deba copiar ni mirar?", .eleccion([
                OpcionPregunta("si", "Sí, las elijo"), OpcionPregunta("no", "No hay"),
            ]), ayuda: "Lo privado nunca se copia, no lo ve ningún asistente y no sale en pantalla.", noLoSe: false,
                     obligatoria: true)
        case .privadasCuales:
            return q(.bienvenida, "Elige las carpetas privadas", .rutas(carpetas: true, varias: true), noLoSe: false,
                     obligatoria: true)
        case .nombreEmpresa:
            return q(.bienvenida, "¿Cómo se llama tu empresa?", .textoCorto(ejemplo: "Estudio Martín"))
        case .yo:
            return q(.bienvenida, "¿Y tú, cómo te llamas?", .textoCorto(ejemplo: "Ana"))
        case .sector:
            return q(.bienvenida, "¿A qué se dedica?", .textoCorto(ejemplo: "Asesoría fiscal y contable"))
        case .ciudad:
            return q(.bienvenida, "¿Dónde está?", .textoCorto(ejemplo: "Valencia"))
        case .personas:
            return q(.bienvenida, "¿Cuántas personas trabajáis?", .cifra(unidad: "personas", sinMeta: false))
        case .alcance:
            return q(.alcance, "¿Qué ponemos en marcha?", .eleccion(AlcancePuesta.allCases.map {
                OpcionPregunta($0.rawValue, $0.titulo, detalle: detalleAlcance($0))
            }))
        case .alcanceArea:
            return q(.alcance, "¿Qué área?", .eleccion(AreaCode.allCases.map { OpcionPregunta($0.rawValue, $0.nombre) }))
        case .alcanceProceso:
            return q(.alcance, "¿Qué proceso?", .eleccion(contexto.catalogo.sistemas.map {
                OpcionPregunta($0.codigo, "\($0.area.nombre) · \(TextosPuesta.llano($0.nombre))", detalle: $0.pregunta)
            }))
        case .asistente:
            return q(.alcance, "Si tienes Claude Code, ¿lo uso para afinar tus respuestas?", .siNo,
                     ayuda: "Solo ve la pregunta y lo que escribas; nunca lo privado. Sin él todo funciona igual.")
        case .camino:
            return q(.conocer, "¿Qué camino quieres?", .eleccion(TextosPuesta.caminos))
        case .metaGeneral:
            return q(.conocer, "¿Qué es lo primero que quieres conseguir?", .eleccion(TextosPuesta.metasGenerales))
        case .fraseCliente:
            return q(.conocer, "Ayudamos a…", .textoCorto(ejemplo: "autónomos de Valencia"),
                     repregunta: "¿A quién exactamente? Por ejemplo, «autónomos que facturan menos de 100.000 € al año».")
        case .fraseResultado:
            return q(.conocer, "…a conseguir…", .textoCorto(ejemplo: "sus impuestos sin sustos"),
                     repregunta: "¿Qué consiguen exactamente? Dilo como lo diría un cliente contento.")
        case .frasePlazo:
            return q(.conocer, "…en…", .textoCorto(ejemplo: "cada trimestre"),
                     repregunta: "¿En cuánto tiempo? Por ejemplo, «en dos semanas» o «cada trimestre».")
        case .fraseMetodo:
            return q(.conocer, "…con…", .textoCorto(ejemplo: "un calendario fiscal y una revisión al mes"),
                     repregunta: "¿Con qué forma de trabajar? Lo que haces distinto a los demás.")
        case .fraseDolor:
            return q(.conocer, "…sin…", .textoCorto(ejemplo: "recargos ni papeles perdidos"),
                     repregunta: "¿Qué se ahorran? El dolor que quitas, con sus palabras.")
        case .destino:
            return q(.conocer, "Dentro de tres años, ¿dónde quieres estar?", .textoLibre(ejemplo: "Facturar 200.000 € con 30 horas a la semana"),
                     repregunta: "¿Le pones un número? Por ejemplo, «facturar 200.000 € en 2028» o «trabajar 30 horas a la semana».")
        case .embudo:
            return q(.organizar, "¿Por qué pasos pasa un cliente hasta que te paga?", .eleccion([
                OpcionPregunta("serie", "Los de serie", detalle: "Prospecto, Diagnóstico, Propuesta, Aceptada y Ganada."),
                OpcionPregunta("propio", "Los míos"),
            ]), area: .ventas)
        case .embudoEtapas:
            return q(.organizar, "Escribe tus pasos, en orden", .textoCorto(ejemplo: "Llamada, Visita, Presupuesto, Firma"),
                     area: .ventas)
        case .planEntrega:
            return q(.organizar, "¿Tienes escrito cómo entregas tu servicio principal?", .eleccion([
                OpcionPregunta("tengo", "Sí, ya lo tengo escrito"),
                OpcionPregunta("crear", "Prepárame un plan de entrega en tres fases"),
                OpcionPregunta("no", "Ahora no"),
            ]), area: .entrega)
        case .logo:
            return q(.organizar, "¿Tienes logo?", .eleccion([
                OpcionPregunta("tengo", "Ya lo tengo", detalle: "Elige el fichero: lo copio en Marca y lo enlazo."),
                OpcionPregunta("web", "Está en mi web", detalle: "Apunto la dirección para traerlo después."),
                OpcionPregunta("aun-no", "Aún no tengo", detalle: "Te dejo una tarea en Marca. El asistente de Marca puede prepararte un borrador cuando actives esa área."),
            ]), area: .marca)
        case .logoFichero:
            return q(.organizar, "El fichero del logo", .rutas(carpetas: false, varias: false), area: .marca,
                     ayuda: "SVG, PDF, PNG o JPG de 10 MB como mucho.")
        case .logoWeb:
            return q(.organizar, "¿En qué dirección está?", .textoCorto(ejemplo: "https://www.tuempresa.es"), area: .marca)
        case .rutinaDia:
            return q(.diaADia, "¿Qué día miras la semana?", .eleccion(TextosPuesta.dias))
        case .rutinaHora:
            return q(.diaADia, "¿A qué hora?", .hora)
        case .rutinaDuracion:
            return q(.diaADia, "¿Cuántos minutos?", .cifra(unidad: "min", sinMeta: false))
        case .topeHoras:
            return q(.diaADia, "¿Cuántas horas al día quieres planificar como mucho?", .cifra(unidad: "h", sinMeta: false),
                     ayuda: "Lo que pase de ahí no cabe en el día: te lo digo.")
        case .objetivo:
            return q(.numeros, "¿Te pones un objetivo de facturación este trimestre?", .eleccion([
                OpcionPregunta("sin-objetivo", "Sin objetivo de facturación"),
                OpcionPregunta("facturacion", "Sí, este trimestre quiero facturar…"),
            ]))
        case .objetivoCifra:
            return q(.numeros, "¿Cuánto?", .cifra(unidad: "€", sinMeta: false))
        case .recorrido:
            return q(.recorrido, "¿Hacemos el recorrido?", .eleccion([
                OpcionPregunta("ahora", "Empezar el recorrido"), OpcionPregunta("mas-tarde", "Más tarde"),
            ]), noLoSe: false)
        default:
            break
        }
        let s = id.rawValue
        for c in ConexionPuesta.allCases where id == .conexion(c) {
            if c == .ventanaCerrada { return q(.conectar, c.titulo, .siNo, ayuda: c.detalle) }
            return q(.conectar, c.titulo, .eleccion([OpcionPregunta("conectar", "Conectar"), OpcionPregunta("ahora-no", "Ahora no")]),
                     ayuda: c.detalle)
        }
        for a in AreaCode.allCases {
            let x = TextosPuesta.nombreComun(a)
            if id == .funciona(a) {
                return q(.conocer, "¿Cómo \(TextosPuesta.funciona(a)) hoy \(x)?", .escala(minimo: 1, maximo: 5, bajo: "Fatal", alto: "Muy bien"), area: a)
            }
            if id == .depende(a) {
                return q(.conocer, "¿Cuánto depende de ti?", .escala(minimo: 1, maximo: 5, bajo: "Nada", alto: "Todo"), area: a,
                         ayuda: "Si paras dos semanas, ¿sigue?")
            }
            if id == .dolor(a) {
                return q(.conocer, "¿Qué es lo que más duele?", .eleccion(TextosPuesta.dolores(a)), area: a)
            }
            if id == .metaArea(a) {
                return q(.conocer, "¿Qué te gustaría tener?", .eleccion(TextosPuesta.metas(a)), area: a)
            }
            if id == .etapa(a) {
                let etapas = contexto.catalogo.etapas
                return q(.conocer, "Etapa de \(x)", .escala(minimo: 1, maximo: 6, bajo: etapas.first?.nombre ?? "Validación",
                                                           alto: etapas.last?.nombre ?? "Empresa"), area: a,
                         ayuda: etapas.map { "\($0.num) · \($0.nombre)" }.joined(separator: " · "))
            }
            if id == .cita(a) {
                return q(.conocer, "Dilo con tus palabras: ¿qué pasa en \(x)?", .textoLibre(ejemplo: "Cada mes me pilla el cierre sin facturar"),
                         area: a, repregunta: "¿Me pones un ejemplo de la última vez que pasó?")
            }
            if id == .estadoArea(a) {
                return q(.organizar, a.nombre, .eleccion(TextosPuesta.estadosArea), area: a)
            }
            if id == .ocupante(a) {
                return q(.organizar, "¿Quién lleva \(x)?", .textoCorto(ejemplo: "Tú, o el nombre de quien la lleve"), area: a)
            }
            if id == .numeroClave(a) {
                return q(.numeros, "\(a.nombre): ¿con qué número lo miras?", .eleccion(opcionesNumero(a, contexto: contexto)), area: a)
            }
            if id == .meta(a) {
                let u = unidad(motor.valor(.numeroClave(a))?.opcion, contexto: contexto)
                return q(.numeros, "Meta", .cifra(unidad: u, sinMeta: true), area: a, ayuda: "Antes de ver el dato.")
            }
            if id == .alerta(a) {
                let u = unidad(motor.valor(.numeroClave(a))?.opcion, contexto: contexto)
                return q(.numeros, "Alerta", .cifra(unidad: u, sinMeta: true), area: a, ayuda: "Si llega aquí, te aviso.")
            }
            for n in 1...6 where id == .etapaPregunta(a, n) {
                return q(.conocer, TextosPuesta.preguntaDeEtapa(a, n), .siNo, area: a)
            }
        }
        if s.hasPrefix("organizar.sistema."), let sis = SistemaCatalogo.codigo(String(s.dropFirst("organizar.sistema.".count))) {
            return q(.organizar, sis.nombre, .eleccion(TextosPuesta.estadosSistema), area: sis.area, ayuda: sis.pregunta)
        }
        if s.hasPrefix("organizar.oferta.") {
            let partes = s.split(separator: ".")
            guard partes.count == 4, let n = Int(partes[2]) else { return nil }
            return partes[3] == "nombre"
                ? q(.organizar, "Oferta \(n): ¿qué vendes?", .textoCorto(ejemplo: n == 1 ? "Declaración de la renta" : "Trimestrales"), area: .ventas)
                : q(.organizar, "Precio sin IVA", .cifra(unidad: "€", sinMeta: false), area: .ventas)
        }
        if s.hasPrefix("organizar.vocabulario.") {
            let k = String(s.dropFirst("organizar.vocabulario.".count))
            guard let t = TextosPuesta.terminosVocabulario.first(where: { $0.clave == k }) else { return nil }
            return q(.organizar, "¿Cómo llamas tú a \(t.texto)?", .textoCorto(ejemplo: t.ejemplo))
        }
        if s.hasPrefix("sinti.") {
            // Por sistema de Organizar (los mismos nombres); si está montado ya lo dijo Organizar.
            let partes = s.split(separator: ".")
            guard partes.count == 3, let sis = SistemaCatalogo.codigo(String(partes[1])), !sis.estandar.isEmpty else { return nil }
            switch partes[2] {
            case "sinti":
                return q(.sinTi, "¿Funciona sin ti?", .siNo, area: sis.area,
                         ayuda: "Si paras dos semanas, ¿sigue haciéndose? Puede hacerlo otra persona o algo automático.")
            case "automatizar":
                return q(.sinTi, "¿Lo dejo a un asistente y tú lo revisas?", .siNo, area: sis.area,
                         ayuda: "Lo hará y te lo enseñará antes de que salga nada. En 7 días te pregunto cómo va.")
            default:
                return nil
            }
        }
        return nil
    }

    static func detalleAlcance(_ a: AlcancePuesta) -> String {
        switch a {
        case .proceso: "Lo más rápido: un solo proceso, de principio a fin."
        case .area: "Un área entera: su diagnóstico, sus sistemas y su número."
        case .todo: "Las seis áreas. Lo recomendado si tu carpeta ya está organizada."
        }
    }

    static func opcionesNumero(_ a: AreaCode, contexto: ContextoCarpeta) -> [OpcionPregunta] {
        var codigos = NumerosDeSerie.opciones(a)
        if let c = contexto.numeroClaveDeArea(a), !codigos.contains(c) { codigos.insert(c, at: 0) }
        return codigos.map { c in OpcionPregunta(c, TextosPuesta.llano(contexto.catalogo.kpi(c)?.indicador ?? c)) }
    }

    static func unidad(_ codigo: String?, contexto: ContextoCarpeta) -> String {
        codigo.flatMap { contexto.catalogo.kpi($0)?.unidad } ?? ""
    }
}
