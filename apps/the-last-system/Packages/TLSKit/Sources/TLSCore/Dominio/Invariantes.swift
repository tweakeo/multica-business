import Foundation

// Invariantes del dominio (PLAN §9 F2 y §4.3; SISTEMAS VE1, VE2, EN1 y §3.6): lo que nunca puede quedar escrito
// en la carpeta, con el mensaje en castellano y lo que se ofrece en su lugar. La interfaz pregunta antes de
// escribir (`comprobar`) y el `MotorDeDominio` lo vuelve a comprobar al ejecutar cada plan.
//
// - VEN-07: una oportunidad solo pasa a Ganada con un cobro confirmado por una persona en `pagos.csv` (o su recibo
//   confirmado por una persona, el «Confirmar el cobro» de la factura de F1); si no,
//   se bloquea y se ofrece Aceptada. Un asistente nunca la pasa a Ganada.
// - ENT-01: un proyecto de entrega cuelga de su oportunidad, y una oportunidad tiene como mucho uno.
// - Precio: el precio que se copia (`precio_congelado`) es el de la Oferta (la única fuente).
// - DIR-03: un proyecto interno en curso sin objetivo se guarda, pero queda en «atención».
// - ENT-04: las fechas planificadas nunca caen en sábado ni domingo: se corren al lunes.

/// Un cambio que la interfaz (o una regla) quiere escribir.
public enum CambioPropuesto: Sendable, Hashable {
    /// Cambiar propiedades de una ficha que ya existe.
    case propiedades(VaultPath, poner: [Property], quitar: [String])
    /// Crear una ficha con este texto.
    case crear(VaultPath, texto: String)
    /// Un plan entero (cada operación se mira).
    case plan(WritePlan)
}

/// Algo que se ofrece en lugar de lo pedido, o para resolver una atención.
public struct AlternativaInvariante: Sendable, Hashable {
    public enum Accion: Sendable, Hashable {
        /// Escribir estas propiedades en la ficha (p. ej. `estado: Aceptada`).
        case poner(VaultPath, [Property])
        /// Elegir un objetivo de la lista y colgar de él el proyecto (`Invariantes.colgar`).
        case elegirObjetivo(VaultPath, opciones: [VaultPath])
        /// Abrir otra ficha (el proyecto que ya tiene la oportunidad).
        case abrir(VaultPath)
    }

    public let titulo: String
    public let accion: Accion
    public let recomendada: Bool

    public init(titulo: String, accion: Accion, recomendada: Bool = false) {
        self.titulo = titulo; self.accion = accion; self.recomendada = recomendada
    }
}

/// Un aviso de una invariante, con su código y lo que se puede hacer.
public struct AvisoInvariante: Sendable, Hashable {
    public enum Nivel: String, Sendable, Hashable, Comparable {
        /// Se corrige solo y se cuenta (ENT-04).
        case informativo
        /// Se guarda, pero queda señalado (DIR-03).
        case atencion
        /// No se escribe.
        case bloqueo

        var orden: Int { self == .informativo ? 0 : self == .atencion ? 1 : 2 }
        public static func < (a: Nivel, b: Nivel) -> Bool { a.orden < b.orden }
    }

    /// `VEN-07`, `ENT-01`, `PRECIO`, `DIR-03`, `ENT-04`.
    public let codigo: String
    public let nivel: Nivel
    public let ruta: VaultPath
    public let mensaje: String
    public let alternativas: [AlternativaInvariante]

    public init(codigo: String, nivel: Nivel, ruta: VaultPath, mensaje: String, alternativas: [AlternativaInvariante] = []) {
        self.codigo = codigo; self.nivel = nivel; self.ruta = ruta; self.mensaje = mensaje; self.alternativas = alternativas
    }
}

/// Una corrección que se aplica sola (la fecha de un sábado pasa al lunes).
public struct AjusteInvariante: Sendable, Hashable {
    public let ruta: VaultPath
    public let propiedad: Property
}

/// Lo que dicen las invariantes de un cambio.
public struct ResultadoInvariante: Sendable, Hashable {
    public enum Veredicto: String, Sendable, Hashable {
        case permitido, atencion, bloqueado
    }

    public let avisos: [AvisoInvariante]
    public let ajustes: [AjusteInvariante]

    public init(avisos: [AvisoInvariante] = [], ajustes: [AjusteInvariante] = []) {
        self.avisos = avisos; self.ajustes = ajustes
    }

    public static let permitido = ResultadoInvariante()

    public var veredicto: Veredicto {
        if avisos.contains(where: { $0.nivel == .bloqueo }) { return .bloqueado }
        if avisos.contains(where: { $0.nivel == .atencion }) { return .atencion }
        return .permitido
    }

    public var puedeGuardar: Bool { veredicto != .bloqueado }
    public var bloqueos: [AvisoInvariante] { avisos.filter { $0.nivel == .bloqueo } }
    public var atenciones: [AvisoInvariante] { avisos.filter { $0.nivel == .atencion } }

    /// La frase que se enseña: el primer bloqueo o, si no hay, la primera atención.
    public var mensaje: String? { (bloqueos.first ?? atenciones.first ?? avisos.first)?.mensaje }

    /// El plan con las correcciones automáticas (ENT-04) ya puestas.
    public func corregir(_ plan: WritePlan) -> WritePlan {
        guard !ajustes.isEmpty else { return plan }
        var out = plan
        out.ops = plan.ops.map { op in
            switch op {
            case .mergeFrontmatter(let p, let set, let unset):
                let mios = ajustes.filter { Invariantes.misma($0.ruta, p) }.map(\.propiedad)
                guard !mios.isEmpty else { return op }
                let claves = Set(mios.map(\.key))
                return .mergeFrontmatter(p, set: set.filter { !claves.contains($0.key) } + mios, unset: unset)
            case .create(let p, let data):
                let mios = ajustes.filter { Invariantes.misma($0.ruta, p) }.map(\.propiedad)
                guard !mios.isEmpty, let e = EditableText(data: data) else { return op }
                var doc = FrontmatterDocument(text: e.text)
                for prop in mios { doc.set(prop.key, prop.value) }
                return .create(p, contents: EditableText(bom: e.bom, text: doc.text).data)
            default:
                return op
            }
        }
        return out
    }

    /// Las propiedades que se iban a poner, con las correcciones de esa ficha.
    public func corregir(_ poner: [Property], en ruta: VaultPath) -> [Property] {
        let mios = ajustes.filter { Invariantes.misma($0.ruta, ruta) }.map(\.propiedad)
        let claves = Set(mios.map(\.key))
        return poner.filter { !claves.contains($0.key) } + mios
    }
}

/// Las invariantes sobre una foto del dominio.
public struct Invariantes: Sendable {
    public let lectura: LecturaDominio

    public init(lectura: LecturaDominio) { self.lectura = lectura }
    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) { self.lectura = LecturaDominio(snapshot: snapshot, reloj: reloj) }

    /// Fechas que se planifican (ENT-04). `vence` no: es el límite real y no se mueve. `inicio` y `fin`, solo en
    /// proyectos; `siguiente_fecha`, solo en oportunidades.
    public static let fechasPlanificadas: Set<String> = ["planificada", "inicio", "fin", "siguiente_fecha"]
    /// Propiedad que deja escrito «Seguir sin objetivo» (DIR-03).
    public static let sinObjetivo = "sin_objetivo"

    static func misma(_ a: VaultPath, _ b: VaultPath) -> Bool { TextFolding.pathKey(a.raw) == TextFolding.pathKey(b.raw) }

    // MARK: Comprobar

    /// ¿Se puede escribir esto? Bloqueos (no se escribe), atenciones (se guarda y queda señalado) y
    /// correcciones automáticas (`ResultadoInvariante.corregir`).
    /// - Parameter autor: quién escribe; en un `.plan`, si no se dice, el del plan (si no, una persona).
    public func comprobar(_ cambio: CambioPropuesto, autor: Autor? = nil) -> ResultadoInvariante {
        let autor: Autor = autor ?? {
            if case .plan(let p) = cambio { return p.autor }
            return .persona("Manu")
        }()
        var notas: [String: NotaCambiada] = [:]
        var orden: [String] = []
        var cobrosNuevos: [FilaPago] = []
        func nota(_ p: VaultPath) -> NotaCambiada {
            let k = TextFolding.pathKey(p.raw)
            if let n = notas[k] { return n }
            let actual = lectura.ficha(p)
            orden.append(k)
            return NotaCambiada(ruta: actual?.ruta ?? p, antes: actual?.propiedades, despues: actual?.propiedades ?? .empty,
                                creada: false, tocadas: [])
        }
        func guardar(_ n: NotaCambiada) { notas[TextFolding.pathKey(n.ruta.raw)] = n }
        func propiedades(_ p: VaultPath, poner: [Property], quitar: [String]) {
            var n = nota(p)
            var lista = n.despues.properties.filter { prop in !quitar.contains(prop.key) && !poner.contains { $0.key == prop.key } }
            lista += poner.filter { $0.value != .empty }
            n.despues = Frontmatter(properties: lista, isValid: true)
            n.tocadas.formUnion(poner.map(\.key) + quitar)
            guardar(n)
        }
        func crear(_ p: VaultPath, texto: String) {
            var n = nota(p)
            n.antes = nil
            n.creada = true
            n.despues = NoteDocument(text: texto).frontmatter
            n.tocadas.formUnion(n.despues.properties.map(\.key))
            guardar(n)
        }
        switch cambio {
        case .propiedades(let p, let poner, let quitar): propiedades(p, poner: poner, quitar: quitar)
        case .crear(let p, let texto): crear(p, texto: texto)
        case .plan(let plan):
            for op in plan.ops {
                switch op {
                case .create(let p, let data) where p.ext == "md":
                    if let e = EditableText(data: data) { crear(p, texto: e.text) }
                case .mergeFrontmatter(let p, let set, let unset):
                    propiedades(p, poner: set, quitar: unset)
                case .upsertCSVRow(let p, let row, _) where TextFolding.nameKey(p.name) == "pagos.csv" && autor.esPersona:
                    // Un cobro que una persona confirma en el mismo plan cuenta para VEN-07.
                    if let fila = FilaPago(fila: row, fichero: p) { cobrosNuevos.append(fila) }
                case .insertCSVRows(let p, let rows, _) where TextFolding.nameKey(p.name) == "pagos.csv" && autor.esPersona:
                    cobrosNuevos += rows.compactMap { FilaPago(fila: $0, fichero: p) }
                default:
                    continue
                }
            }
        }
        var avisos: [AvisoInvariante] = []
        var ajustes: [AjusteInvariante] = []
        for k in orden {
            guard let n = notas[k] else { continue }
            let tipo = NoteKindResolver.kind(of: n.ruta, frontmatter: n.despues, layout: lectura.layout)
            switch tipo {
            case .opportunity:
                avisos += ven07(n, autor: autor, cobrosNuevos: cobrosNuevos)
                avisos += precio(n)
            case .project:
                avisos += ent01(n, otras: Array(notas.values))
                avisos += dir03(n)
            default:
                break
            }
            let (a, aj) = Self.ent04(n, tipo: tipo)
            avisos += a
            ajustes += aj
        }
        return ResultadoInvariante(avisos: avisos.sorted { $0.nivel > $1.nivel }, ajustes: ajustes)
    }

    /// Una ficha antes y después del cambio.
    struct NotaCambiada {
        var ruta: VaultPath
        var antes: Frontmatter?
        var despues: Frontmatter
        var creada: Bool
        var tocadas: Set<String>

        func toca(_ claves: String...) -> Bool { creada || claves.contains { tocadas.contains($0) } }
    }

    // MARK: VEN-07

    func ven07(_ n: NotaCambiada, autor: Autor, cobrosNuevos: [FilaPago]) -> [AvisoInvariante] {
        let despues = LecturaDominio.estadoOportunidad(n.despues.text("estado"))
        let antes = LecturaDominio.estadoOportunidad(n.antes?.text("estado"))
        guard despues == "Ganada", antes != "Ganada" else { return [] }
        let nombre = nombre(n)
        let aceptada = AlternativaInvariante(titulo: "Dejarla en Aceptada",
                                             accion: .poner(n.ruta, [Property(key: "estado", value: .text("Aceptada"))]),
                                             recomendada: true)
        if case .agente = autor {
            return [AvisoInvariante(codigo: "VEN-07", nivel: .bloqueo, ruta: n.ruta,
                                    mensaje: "Un asistente nunca pasa una oportunidad a Ganada: llega sola cuando una persona confirma el cobro.",
                                    alternativas: [aceptada])]
        }
        let k = TextFolding.pathKey(n.ruta.raw)
        let nuevos = cobrosNuevos.filter { $0.esCobroConfirmado && lectura.oportunidad(de: $0).map { TextFolding.pathKey($0.raw) == k } == true }
        if lectura.tieneCobroConfirmado(n.ruta) || !nuevos.isEmpty { return [] }
        let facturas = lectura.que(apuntan: n.ruta, por: "oportunidad", tipo: .invoice).filter { !$0.privada }
        var detalle = "«\(nombre)» aún no tiene ningún cobro confirmado."
        if let f = facturas.first {
            let numero = f.texto("numero").map { "La factura \($0)" } ?? "Su factura"
            let estado = (f.estado ?? "sin estado").lowercased()
            detalle = "\(numero) está \(estado) y su cobro aún no se ha confirmado."
        }
        return [AvisoInvariante(codigo: "VEN-07", nivel: .bloqueo, ruta: n.ruta,
                                mensaje: "Ganada necesita un cobro confirmado por una persona. \(detalle) Confírmalo en Finanzas › Banco o déjala en Aceptada.",
                                alternativas: [aceptada])]
    }

    // MARK: Precio

    func precio(_ n: NotaCambiada) -> [AvisoInvariante] {
        guard n.toca("precio_congelado", "oferta_version"), let escrito = n.despues.text("precio_congelado") else { return [] }
        guard let oferta = lectura.precioDeOferta(n.despues, desde: n.ruta) else { return [] }
        guard let c = FormatosPlantilla.centimos(escrito) else {
            return [AvisoInvariante(codigo: "PRECIO", nivel: .bloqueo, ruta: n.ruta,
                                    mensaje: "«\(escrito)» no es un importe. El precio sale de la Oferta.")]
        }
        guard !oferta.admite(c), let texto = oferta.texto else { return [] }
        var alternativas: [AlternativaInvariante] = []
        if let p = oferta.centimos {
            alternativas.append(AlternativaInvariante(titulo: "Usar \(Euros.texto(p)) de la Oferta",
                                                      accion: .poner(n.ruta, [Property(key: "precio_congelado", value: .number(Euros.escrito(p)))]),
                                                      recomendada: true))
        }
        let mensaje = oferta.centimos != nil
            ? "El precio sale de la Oferta: «\(oferta.nombreFuente)» cuesta \(texto), no \(Euros.texto(c)). Se baja de alcance, no de precio."
            : "El precio de «\(oferta.nombreFuente)» va \(texto): \(Euros.texto(c)) se sale de lo que dice la Oferta."
        return [AvisoInvariante(codigo: "PRECIO", nivel: .bloqueo, ruta: n.ruta, mensaje: mensaje, alternativas: alternativas)]
    }

    /// El precio que hay que copiar de la Oferta en una ficha (oportunidad, propuesta, factura). `nil` si la Oferta
    /// no lo dice (se enseña «Sin dato», nunca 0).
    public func precioDeOferta(para ruta: VaultPath) -> PrecioDeOferta? {
        guard let f = lectura.ficha(ruta) else { return nil }
        return lectura.precioDeOferta(f.propiedades, desde: f.ruta)
    }

    // MARK: ENT-01

    func ent01(_ n: NotaCambiada, otras: [NotaCambiada]) -> [AvisoInvariante] {
        guard lectura.esDeEntrega(n.despues, ruta: n.ruta), n.toca("oportunidad", "oportunidad_id", "clase") else { return [] }
        let nombre = nombre(n)
        guard let opo = lectura.relacion(n.despues, "oportunidad", desde: n.ruta) else {
            return [AvisoInvariante(codigo: "ENT-01", nivel: .bloqueo, ruta: n.ruta,
                                    mensaje: "Un proyecto de entrega nace de una oportunidad: elige de cuál sale «\(nombre)».")]
        }
        let opoNombre = lectura.ficha(opo)?.nombre ?? opo.stem
        // Otro proyecto de entrega con la misma oportunidad, en la carpeta o en el mismo cambio.
        let yo = TextFolding.pathKey(n.ruta.raw)
        let k = TextFolding.pathKey(opo.raw)
        var repetidos = lectura.proyectosDeEntrega(de: opo).map(\.ruta).filter { TextFolding.pathKey($0.raw) != yo }
        for o in otras where TextFolding.pathKey(o.ruta.raw) != yo && o.creada && lectura.esDeEntrega(o.despues, ruta: o.ruta)
            && lectura.relacion(o.despues, "oportunidad", desde: o.ruta).map({ TextFolding.pathKey($0.raw) == k }) == true {
            repetidos.append(o.ruta)
        }
        if let otro = repetidos.first {
            let otroNombre = lectura.ficha(otro)?.nombre ?? otro.parent?.name ?? otro.stem
            return [AvisoInvariante(codigo: "ENT-01", nivel: .bloqueo, ruta: n.ruta,
                                    mensaje: "«\(opoNombre)» ya tiene su proyecto de entrega, «\(otroNombre)». Cada oportunidad tiene uno solo.",
                                    alternativas: [AlternativaInvariante(titulo: "Abrir «\(otroNombre)»", accion: .abrir(otro), recomendada: true)])]
        }
        // El proyecto arranca con el cobro (SISTEMAS EN1): sin él, se avisa pero no se impide.
        if n.creada, LecturaDominio.estadoOportunidad(lectura.ficha(opo)?.estado) != "Ganada", !lectura.tieneCobroConfirmado(opo) {
            return [AvisoInvariante(codigo: "ENT-01", nivel: .atencion, ruta: n.ruta,
                                    mensaje: "«\(opoNombre)» aún no tiene un cobro confirmado: el proyecto se guarda, pero lo normal es que arranque con el cobro.")]
        }
        return []
    }

    // MARK: DIR-03

    func dir03(_ n: NotaCambiada) -> [AvisoInvariante] {
        guard n.toca("estado", "objetivo", "objetivo_id", "clase", Self.sinObjetivo) else { return [] }
        return atencionDir03(ruta: n.ruta, fm: n.despues, nombre: nombre(n)).map { [$0] } ?? []
    }

    /// DIR-03 para una ficha de proyecto: interno, en curso, sin objetivo y sin «Seguir sin objetivo», en una
    /// carpeta que usa objetivos.
    func atencionDir03(ruta: VaultPath, fm: Frontmatter, nombre: String) -> AvisoInvariante? {
        guard !lectura.esDeEntrega(fm, ruta: ruta),
              LecturaDominio.estadoProyecto(fm.text("estado")) == "En curso",
              lectura.relacion(fm, "objetivo", desde: ruta) == nil,
              !Self.verdadero(fm.text(Self.sinObjetivo)) else { return nil }
        let objetivos = lectura.objetivos.filter { !$0.privada && !Self.cerrado($0.estado) }
        guard !objetivos.isEmpty else { return nil }
        return AvisoInvariante(
            codigo: "DIR-03", nivel: .atencion, ruta: ruta,
            mensaje: "«\(nombre)» está en curso sin objetivo. Se guarda igual; si lo cuelgas de un objetivo, cuenta en su ritmo.",
            alternativas: [
                AlternativaInvariante(titulo: "Colgar de un objetivo", accion: .elegirObjetivo(ruta, opciones: objetivos.map(\.ruta)),
                                      recomendada: true),
                AlternativaInvariante(titulo: "Seguir sin objetivo",
                                      accion: .poner(ruta, [Property(key: Self.sinObjetivo, value: .bool(true))])),
            ])
    }

    static func verdadero(_ s: String?) -> Bool {
        guard let s else { return false }
        return ["true", "si", "sí", "yes"].contains(TextFolding.fold(s))
    }

    static func cerrado(_ estado: String?) -> Bool {
        ["conseguido", "no conseguido", "cerrado", "archivado"].contains(TextFolding.fold(estado ?? ""))
    }

    /// Propiedades para colgar un proyecto de un objetivo (y quitar «Seguir sin objetivo» si estaba).
    public func colgar(_ proyecto: VaultPath, de objetivo: VaultPath) -> (poner: [Property], quitar: [String]) {
        let nombre = lectura.ficha(objetivo)?.nombre ?? objetivo.stem
        let enlace = NombresDeFicha.wikilink(objetivo, nombre: nombre, en: lectura.snapshot)
        var quitar: [String] = []
        if let f = lectura.ficha(proyecto) {
            quitar = [Self.sinObjetivo, "objetivo_id"].filter { k in f.propiedades.properties.contains { $0.key == k } }
        }
        return ([Property(key: "objetivo", value: .text(enlace))], quitar)
    }

    // MARK: ENT-04

    static func ent04(_ n: NotaCambiada, tipo: NoteKind) -> ([AvisoInvariante], [AjusteInvariante]) {
        var avisos: [AvisoInvariante] = []
        var ajustes: [AjusteInvariante] = []
        // `planificada` en cualquier ficha; `inicio` y `fin` solo en proyectos (las fechas de un contrato o de un
        // periodo son las que son); el siguiente paso, en oportunidades.
        let claves = Self.fechasPlanificadas.filter { k in
            switch k {
            case "inicio", "fin": tipo == .project
            case "siguiente_fecha": tipo == .opportunity
            default: true
            }
        }
        for clave in claves.sorted() where n.toca(clave) {
            guard let texto = n.despues.text(clave), let d = LocalDate(parsing: texto), d.isWeekend else { continue }
            let lunes = Tarea.laborable(d)
            ajustes.append(AjusteInvariante(ruta: n.ruta, propiedad: Property(key: clave, value: .text(lunes.description))))
            avisos.append(AvisoInvariante(codigo: "ENT-04", nivel: .informativo, ruta: n.ruta,
                                          mensaje: "El \(Self.fechaLarga(d)) es \(Self.diaDeLaSemana(d)): «\(Self.etiqueta(clave))» pasa al lunes \(Self.fechaLarga(lunes))."))
        }
        return (avisos, ajustes)
    }

    /// ENT-04 sin leer la carpeta entera (revisión final de F2): solo las fichas que toca el plan, para lo que la
    /// persona escribe por las bases, las fichas de F1 y las plantillas (`MotorDeDominio.escribirYAtender`). `texto`
    /// da el texto actual de una ruta (`nil` si no existe). Los guardados del editor (`saveText`) no se tocan: lo que
    /// teclea la persona no se reescribe por debajo.
    public static func fechasLaborables(_ plan: WritePlan, layout: VaultLayout, texto: (VaultPath) -> String?) -> ResultadoInvariante {
        var avisos: [AvisoInvariante] = []
        var ajustes: [AjusteInvariante] = []
        for op in plan.ops {
            let n: NotaCambiada
            switch op {
            case .mergeFrontmatter(let p, let set, let unset):
                let claves = Set(set.map(\.key)).intersection(fechasPlanificadas)
                guard p.ext == "md", !claves.isEmpty else { continue }
                let antes = texto(p).map { NoteDocument(text: $0).frontmatter }
                var lista = (antes?.properties ?? []).filter { prop in !unset.contains(prop.key) && !set.contains { $0.key == prop.key } }
                lista += set.filter { $0.value != .empty }
                n = NotaCambiada(ruta: p, antes: antes, despues: Frontmatter(properties: lista, isValid: true), creada: false, tocadas: claves)
            case .create(let p, let data) where p.ext == "md":
                guard let e = EditableText(data: data) else { continue }
                n = NotaCambiada(ruta: p, antes: nil, despues: NoteDocument(text: e.text).frontmatter, creada: true, tocadas: [])
            default:
                continue
            }
            let (a, aj) = ent04(n, tipo: NoteKindResolver.kind(of: n.ruta, frontmatter: n.despues, layout: layout))
            avisos += a
            ajustes += aj
        }
        return ResultadoInvariante(avisos: avisos, ajustes: ajustes)
    }

    /// ¿Pasa el plan alguna ficha a `estado: Ganada`? (Solo entonces hace falta mirar VEN-07 con la carpeta entera.)
    public static func pasaAGanada(_ plan: WritePlan) -> Bool {
        func ganada(_ v: PropertyValue?) -> Bool { LecturaDominio.estadoOportunidad(v?.displayText) == "Ganada" }
        return plan.ops.contains { op in
            switch op {
            case .mergeFrontmatter(_, let set, _): return set.contains { $0.key == "estado" && ganada($0.value) }
            case .create(let p, let data) where p.ext == "md":
                guard let e = EditableText(data: data) else { return false }
                return ganada(NoteDocument(text: e.text).frontmatter.value("estado"))
            default: return false
            }
        }
    }

    static func etiqueta(_ clave: String) -> String {
        switch clave {
        case "planificada": "Planificada"
        case "inicio": "Inicio"
        case "fin": "Fin"
        case "siguiente_fecha": "Siguiente paso"
        default: clave
        }
    }

    static func diaDeLaSemana(_ d: LocalDate) -> String {
        ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"][d.weekday - 1]
    }

    /// «25 oct».
    static func fechaLarga(_ d: LocalDate) -> String { FormatosPlantilla.aplicar(d.description, formato: "corta") }

    func nombre(_ n: NotaCambiada) -> String {
        // `nombre`/`titulo` tal como se escriben (`Frontmatter.text` los lee como `name`/`title`).
        for k in ["nombre", "titulo"] {
            if let v = n.despues.properties.first(where: { $0.key == k })?.value.displayText.trimmingCharacters(in: .whitespaces),
               !v.isEmpty, !v.contains("{{") { return v }
        }
        return lectura.ficha(n.ruta)?.nombre ?? (n.ruta.stem == "Proyecto" ? n.ruta.parent?.name ?? n.ruta.stem : n.ruta.stem)
    }

    // MARK: Lo que ya está en la carpeta

    /// Atenciones vigentes (para Hoy, los chequeos y Dirección): proyectos en curso sin objetivo (DIR-03) y
    /// proyectos de entrega sin oportunidad o repetidos (ENT-01). Sin nada privado.
    public func atenciones() -> [AvisoInvariante] {
        var out: [AvisoInvariante] = []
        var vistas = Set<String>()
        for p in lectura.proyectos where !p.privada {
            if let a = atencionDir03(ruta: p.ruta, fm: p.propiedades, nombre: p.nombre) { out.append(a) }
            guard lectura.esDeEntrega(p.propiedades, ruta: p.ruta),
                  !["Cerrado", "Archivado"].contains(LecturaDominio.estadoProyecto(p.estado) ?? "") else { continue }
            guard let opo = lectura.relacion(p, "oportunidad") else {
                out.append(AvisoInvariante(codigo: "ENT-01", nivel: .atencion, ruta: p.ruta,
                                           mensaje: "«\(p.nombre)» es un proyecto de entrega sin oportunidad: dile de cuál sale."))
                continue
            }
            let todos = lectura.proyectosDeEntrega(de: opo).filter { !$0.privada }
            if todos.count > 1, vistas.insert(TextFolding.pathKey(opo.raw)).inserted {
                let nombre = lectura.ficha(opo)?.nombre ?? opo.stem
                out.append(AvisoInvariante(codigo: "ENT-01", nivel: .atencion, ruta: opo,
                                           mensaje: "«\(nombre)» tiene \(todos.count) proyectos de entrega y debería tener uno solo.",
                                           alternativas: todos.map { AlternativaInvariante(titulo: "Abrir «\($0.nombre)»", accion: .abrir($0.ruta)) }))
            }
        }
        return out
    }
}
