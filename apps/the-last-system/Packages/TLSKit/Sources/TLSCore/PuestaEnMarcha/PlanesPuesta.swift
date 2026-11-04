import Foundation
import Yams

// F3 · rol motor. Qué escribe cada paso al «Aplicar» (PLAN §6.7, columna «Qué escribe al aplicar») y su vista previa
// en diferencias. Se prepara con una foto de la carpeta: **no se escribe nada aquí** (criterio F3-1). Cada fichero se
// escribe de una vez con compare-and-swap sobre los bytes que se leyeron (`WriteOp.replaceText`) o se crea sin pisar
// (`create`); la vista previa enseña exactamente ese texto. «No lo sé» se escribe PENDIENTE (criterio F3-5). Lo que
// llega premarcado de la carpeta y la persona no cambia no se vuelve a escribir donde ya estaba.

/// Un fichero que cambia al aplicar.
public struct CambioPrevisto: Sendable, Hashable, Identifiable {
    public enum Clase: String, Sendable, Hashable {
        case crear, cambiar, copiar
    }

    public var id: VaultPath { ruta }
    public let ruta: VaultPath
    public let clase: Clase
    /// Texto que hay ahora (`nil` si se crea).
    public let antes: String?
    /// Texto que quedará (`nil` en una copia que no es texto, como un logo).
    public let despues: String?
    /// Líneas nuevas o cambiadas de `despues` (desde 0).
    public let lineasCambiadas: Set<Int>
    /// «Nueva», «Cambia» o «Copia de logo.png».
    public let resumen: String
}

/// «Lo que he entendido» del paso 1: la matriz de las áreas, el cuello y las etapas.
public struct LoQueHeEntendido: Sendable, Hashable {
    public struct Fila: Sendable, Hashable {
        public let area: AreaCode
        public let funciona: Int?
        public let depende: Int?
        public let etapa: Int?
        public let dolor: String?
        public let meta: String?
        public let cita: String?
    }

    public let filas: [Fila]
    public let cuello: AreaCode?
    public let porQue: String
    /// La del área más atrasada entre Ventas, Entrega y Finanzas.
    public let etapaGlobal: Int?
}

/// La vista previa de un paso: el plan (todo o nada, un solo «Deshacer») y lo que cambia en cada fichero.
public struct VistaPreviaPaso: Sendable {
    public let paso: PasoPuesta
    /// `nil`: no hay nada que escribir en la carpeta.
    public let plan: WritePlan?
    public let cambios: [CambioPrevisto]
    /// «Crear 9 · Cambiar 2 · No se borra nada».
    public let resumen: String
    public let avisos: [String]
    public let entendido: LoQueHeEntendido?
    /// Lo que se guarda fuera de la carpeta (el estado de la app).
    public let fueraDeLaCarpeta: [String]

    public var nadaQueEscribir: Bool { plan == nil }
}

/// Borrador en memoria de los cambios de un paso.
struct BorradorCarpeta {
    let foto: VaultSnapshot
    let autor: Autor
    private(set) var originales: [VaultPath: (data: Data, texto: String)] = [:]
    private(set) var textos: [VaultPath: String] = [:]
    private(set) var orden: [VaultPath] = []
    private(set) var copias: [VaultPath: (data: Data, origen: String)] = [:]
    var opsExtra: [WriteOp] = []
    var cambiosExtra: [CambioPrevisto] = []
    var avisos: [String] = []

    init(foto: VaultSnapshot, autor: Autor) { self.foto = foto; self.autor = autor }

    /// Ruta real si ya existe (en la foto, sin distinguir mayúsculas) o en el borrador.
    func real(_ p: VaultPath) -> VaultPath {
        if let r = foto.existing(p) { return r }
        let k = TextFolding.pathKey(p.raw)
        return orden.first { TextFolding.pathKey($0.raw) == k } ?? p
    }

    func existe(_ p: VaultPath) -> Bool { foto.existing(p) != nil || textos[real(p)] != nil || copias[real(p)] != nil }

    /// Texto actual (el del borrador o el de la carpeta).
    func texto(_ p: VaultPath) -> String? {
        let r = real(p)
        if let t = textos[r] { return t }
        guard !foto.layout.isPrivate(r) else { return nil }
        return foto.text(r)
    }

    mutating func escribir(_ p: VaultPath, _ texto: String) {
        let r = real(p)
        // Lo privado nunca se toca (ni aunque una ruta de la puesta en marcha caiga dentro).
        guard !foto.layout.isPrivate(r) else { avisos.append("No toco «\(r.name)»: está en una carpeta privada."); return }
        if originales[r] == nil, let d = foto.data(r), let t = foto.text(r) { originales[r] = (d, t) }
        if !orden.contains(r) { orden.append(r) }
        textos[r] = texto
    }

    /// Cambia un fichero que existe (o que ya está en el borrador); `nil` del cambio = no tocar.
    mutating func cambiar(_ p: VaultPath, _ f: (String) -> String?) {
        guard let t = texto(p), let n = f(t), n != t else { return }
        escribir(p, n)
    }

    mutating func copiar(_ data: Data, a p: VaultPath, origen: String) {
        let r = real(p)
        guard !foto.layout.isPrivate(r) else { avisos.append("No copio «\(origen)» en una carpeta privada."); return }
        if !orden.contains(r) { orden.append(r) }
        copias[r] = (data, origen)
    }

    var creadas: [VaultPath] { orden.filter { foto.existing($0) == nil } }

    /// Si un nombre nuevo ya existe en otra carpeta, los enlaces que había se escriben con su ruta (mismo plan).
    mutating func protegerEnlaces() {
        let nuevas = creadas
        guard !nuevas.isEmpty else { return }
        for op in LinkRefactor(snapshot: foto).protegerEnlaces(alCrear: nuevas, opciones: .init(autor: autor)) {
            guard case .editRanges(let p, let edits, _) = op, let base = foto.text(p), textos[p] == nil else {
                opsExtra.insert(op, at: 0)
                continue
            }
            var bytes = Array(base.utf8)
            for e in edits.sorted(by: { $0.offset > $1.offset }) where e.offset + e.length <= bytes.count {
                bytes.replaceSubrange(e.offset..<(e.offset + e.length), with: Array(e.replacement.utf8))
            }
            if let t = String(bytes: bytes, encoding: .utf8) { escribir(p, t) }
        }
    }

    func ops() -> [WriteOp] {
        var out = opsExtra
        for p in orden {
            if let c = copias[p] { out.append(.create(p, contents: c.data)); continue }
            guard let t = textos[p] else { continue }
            if let o = originales[p] {
                guard o.texto != t, let op = WriteOp.replaceText(p, base: o.data, text: t) else { continue }
                out.append(op)
            } else {
                out.append(.create(p, text: t))
            }
        }
        return out
    }

    func cambios() -> [CambioPrevisto] {
        var out: [CambioPrevisto] = []
        for p in orden {
            if let c = copias[p] {
                out.append(CambioPrevisto(ruta: p, clase: .copiar, antes: nil, despues: nil, lineasCambiadas: [],
                                          resumen: "Copia de «\(c.origen)»"))
                continue
            }
            guard let t = textos[p] else { continue }
            if let o = originales[p] {
                guard o.texto != t else { continue }
                out.append(CambioPrevisto(ruta: p, clase: .cambiar, antes: o.texto, despues: t,
                                          lineasCambiadas: DiferenciaDeLineas.cambiadas(antes: o.texto, despues: t), resumen: "Cambia"))
            } else {
                let n = t.components(separatedBy: "\n").count
                out.append(CambioPrevisto(ruta: p, clase: .crear, antes: nil, despues: t, lineasCambiadas: Set(0..<n), resumen: "Nueva"))
            }
        }
        return out + cambiosExtra
    }
}

/// Prepara lo que escribe cada paso.
struct PlanesPuesta {
    let motor: OnboardingEngine
    var contexto: ContextoCarpeta { motor.contexto }
    var autor: Autor { .persona(motor.estado.persona) }
    var hoy: LocalDate { contexto.hoy }
    var layout: VaultLayout { contexto.layout }

    /// Foto de la carpeta, o una vacía con la estructura de serie («Empiezo de cero»: la carpeta aún no existe).
    var foto: VaultSnapshot {
        contexto.foto ?? VaultSnapshot.read(root: URL(fileURLWithPath: "/private/var/empty/tls-puesta-sin-carpeta"), layout: .humana)
    }

    func valor(_ id: PreguntaID) -> ValorRespuesta? { motor.valor(id) }
    func respuesta(_ id: PreguntaID) -> Respuesta? { motor.respuesta(id) }

    /// La respuesta solo si la dio (o la cambió) la persona: lo que viene de la carpeta sin tocar no se reescribe.
    func nueva(_ id: PreguntaID) -> ValorRespuesta? {
        guard let r = respuesta(id), !r.vieneSinCambiosDeLaCarpeta else { return nil }
        return r.valor
    }

    /// Texto de una respuesta para escribirla (PENDIENTE si «No lo sé»).
    func escrito(_ v: ValorRespuesta?) -> String? {
        guard let v else { return nil }
        switch v {
        case .noLoSe: return TextoPuesta.pendiente
        case .texto(let t): return t.trimmingCharacters(in: .whitespacesAndNewlines).nilSiVacio
        case .opcion(let o): return o
        case .numero(let n): return FormatoBase.cifraParaEditar(n)
        case .escala(let n): return String(n)
        case .siNo(let b): return b ? "sí" : "no"
        case .opciones(let o): return o.joined(separator: ", ")
        case .rutas(let r): return r.joined(separator: ", ")
        }
    }

    func motorPlantillas(_ f: VaultSnapshot) -> PlantillaMotor {
        PlantillaMotor(snapshot: f, opciones: .init(yo: motor.estado.persona, copiarGuias: true, reloj: contexto.reloj))
    }

    var nombreEmpresa: String {
        escrito(valor(.nombreEmpresa)).flatMap { $0 == TextoPuesta.pendiente ? nil : $0 } ?? contexto.nombreEmpresa ?? "Tu empresa"
    }

    /// Una nota de plantilla (solo el texto; el nombre y la carpeta los decide el paso).
    func plantilla(_ id: String, _ f: VaultSnapshot, valores: [String: String] = [:], poner: [Property] = [],
                   secciones: [String: String] = [:], area: AreaCode? = nil, carpeta: VaultPath? = nil) -> String? {
        var v = valores
        v["mi_empresa.nombre"] = v["mi_empresa.nombre"] ?? nombreEmpresa
        let p = PlantillaMotor.Peticion(plantilla: id, valores: v, poner: poner, secciones: secciones, area: area,
                                        carpeta: carpeta, autor: autor)
        return try? motorPlantillas(f).preparar(p).texto
    }

    // MARK: Preparar

    func preparar(_ paso: PasoPuesta) throws -> VistaPreviaPaso {
        let f = foto
        var b = BorradorCarpeta(foto: f, autor: autor)
        var entendido: LoQueHeEntendido?
        var fuera: [String] = []
        switch paso {
        case .bienvenida:
            switch motor.ruta {
            case .empresaNueva:
                try empezarDeCero(&b)
                fuera.append("Registro la carpeta nueva en la app.")
            case .copiaG3, .carpetaPorOrdenar:
                let privadas = valor(.privadasCuales)?.rutas?.count ?? 0
                fuera.append(motor.soloMirar
                             ? "Abro tu carpeta sin tocarla: solo la miro."
                             : "Hago una copia de tu carpeta en The Last System › Empresas" + (privadas > 0 ? ", sin \(privadas == 1 ? "la carpeta privada" : "las \(privadas) carpetas privadas")." : "."))
            case .ejemplo:
                fuera.append("Instalo el ejemplo de Asesoría Ribera.")
            }
        case .alcance, .conectar, .recorrido:
            fuera.append("Guardo tu elección en la app. En tu carpeta no se escribe nada.")
        case .conocer:
            entendido = loQueHeEntendido()
            conocer(&b, entendido: entendido!)
        case .ordenar:
            fuera.append("Lo prepara «Ordenar lo que tienes» con su propia vista previa.")
        case .organizar:
            try organizar(&b)
            // F4: sin paso 4 (ningún sistema que preguntar), los asistentes de serie se dejan listos aquí.
            if !motor.pasosIncluidos.contains(.sinTi) { try asistentes(&b) }
        case .sinTi:
            try sinTi(&b)
            try asistentes(&b)
        case .diaADia:
            try diaADia(&b)
        case .numeros:
            numeros(&b)
        }
        b.protegerEnlaces()
        let ops = b.ops()
        let cambios = b.cambios()
        let plan = ops.isEmpty ? nil : WritePlan(autor: autor, descripcion: "Puesta en marcha · \(paso.titulo)", ops: ops)
        return VistaPreviaPaso(paso: paso, plan: plan, cambios: cambios, resumen: Self.resumen(cambios),
                               avisos: b.avisos, entendido: entendido, fueraDeLaCarpeta: fuera)
    }

    static func resumen(_ c: [CambioPrevisto]) -> String {
        let crear = c.filter { $0.clase == .crear }.count
        let cambiar = c.filter { $0.clase == .cambiar }.count
        let copiar = c.filter { $0.clase == .copiar }.count
        var partes: [String] = []
        // Siempre con lo que se cuenta («Cambiar 7» no decía 7 qué).
        func n(_ x: Int) -> String { x == 1 ? "1 fichero" : "\(x) ficheros" }
        if crear > 0 { partes.append("Crear \(n(crear))") }
        if cambiar > 0 { partes.append("Cambiar \(n(cambiar))") }
        if copiar > 0 { partes.append("Copiar \(n(copiar))") }
        if partes.isEmpty { return "Nada que escribir en tu carpeta" }
        return (partes + ["No se borra nada"]).joined(separator: " · ")
    }

    // MARK: 0 · Empiezo de cero

    func empezarDeCero(_ b: inout BorradorCarpeta) throws {
        let f = b.foto
        guard escrito(valor(.nombreEmpresa)).map({ $0 != TextoPuesta.pendiente }) == true else { throw ErrorPuesta.nombreVacio }
        var pendientes: [String] = []
        var poner: [Property] = []
        for (id, clave, nombre) in [(PreguntaID.sector, "sector", "A qué se dedica"), (.ciudad, "ciudad", "Dónde está"),
                                    (.personas, "personas", "Cuántas personas sois")] {
            guard let v = valor(id) else { continue }
            if v.esNoLoSe { pendientes.append("- \(TextoPuesta.pendiente) · \(nombre)"); continue }
            if let t = escrito(v) { poner.append(Property(key: clave, value: id == .personas ? .number(t) : .text(t))) }
        }
        var empresa = plantilla("tu-empresa", f, valores: ["yo": motor.estado.persona], poner: poner)
            ?? "# \(nombreEmpresa)\n"
        empresa = TextoPuesta.ponerPropiedades([Property(key: "titular", value: .text(motor.estado.persona))], en: empresa)
        for l in pendientes { empresa = TextoPuesta.anadirLinea(l, aSeccion: "Pendiente", en: empresa) }
        b.escribir(VaultPath("Empresa.md"), empresa)
        b.escribir(VaultPath("AGENTS.md"), agentes(estados: nil))
        b.escribir(VaultPath(VaultLayout.layoutFile), "{\"preset\":\"humana\"}\n")
        b.escribir(VaultPath(VaultLayout.configFile), configInicial())
        for a in AreaCode.allCases {
            // Sin estado: se decide en «Organizar» (la plantilla trae «preparada» de serie y se premarcaría como si
            // lo hubieras dicho tú).
            let t = cabeceraDeArea(a, f).map { TextoPuesta.ponerPropiedades([], quitar: ["estado"], en: $0) } ?? "# \(a.nombre)\n"
            b.escribir(layout.areaFolder(a).appending(AreaReader.fileName), t)
        }
    }

    func configInicial() -> String {
        """
        # Configuración de esta carpeta, creada por The Last System en la puesta en marcha.
        version: 1
        id: \(motor.estado.vaultID.uuidString.lowercased())
        clase: copia
        creada: \(hoy)
        privado: []

        """
    }

    func cabeceraDeArea(_ a: AreaCode, _ f: VaultSnapshot) -> String? {
        let std = contexto.catalogo.area(a)
        let rol = contexto.catalogo.roles.first { $0.area == a }
        var valores = ["area.nombre": a.nombre]
        if let c = std?.convierte { valores["area.convierte"] = c }
        if let p = rol?.pregunta { valores["area.pregunta"] = p }
        if let r = rol { valores["rol.enlace"] = "[[\(NombresDeFicha.slug(r.nombre))|\(r.nombre)]]" }
        return plantilla("cabecera-de-area", f, valores: valores, area: a, carpeta: layout.areaFolder(a))
    }

    /// `AGENTS.md`: la entrada de los asistentes (ningún asistente la edita).
    func agentes(estados: [AreaCode: EstadoAreaPuesta]?) -> String {
        """
        # Instrucciones para los asistentes de \(nombreEmpresa)

        Esta carpeta es la empresa de \(motor.estado.persona). Léela antes de trabajar en ella.

        ## Reglas
        - Nada sale de la empresa sin el OK de \(motor.estado.persona).
        - No se borra nada: lo retirado va a Archivo.
        - Lo privado no se lee ni se copia.
        - Cada dato vive en un solo sitio: si dudas, pregunta.

        ## Áreas activas
        \(textoAreas(estados))

        """
    }

    func textoAreas(_ estados: [AreaCode: EstadoAreaPuesta]?) -> String {
        guard let estados, !estados.isEmpty else { return "Aún sin decidir: se decide en la puesta en marcha." }
        func lista(_ e: EstadoAreaPuesta) -> String {
            let n = AreaCode.allCases.filter { estados[$0] == e }.map(\.nombre)
            return n.isEmpty ? "ninguna" : n.joined(separator: ", ")
        }
        return """
        - Activas: \(lista(.activa)).
        - Preparadas: \(lista(.preparada)).
        - En reposo: \(lista(.reposo)).

        Los asistentes solo trabajan en las áreas activas.
        """
    }

    // MARK: 1 · Conocer tu negocio

    func etapaDeArea(_ a: AreaCode) -> Int?? {
        func deValor(_ v: ValorRespuesta) -> Int?? {
            if v.esNoLoSe { return .some(nil) }
            if let n = v.escala { return .some(n) }
            return nil
        }
        // Manda lo que contesta la persona: la etapa elegida directamente y, si no, la cadena de preguntas de etapa.
        // La etapa que calcula la app (premarcada) solo vale si no se ha contestado nada (en una carpeta recién creada
        // sale 1 y no debe tapar lo contestado).
        if let r = motor.estado.respuesta(.etapa(a)), r.origen.clase == .persona, let e = deValor(r.valor) { return e }
        let cadenaContestada = (1...6).contains { motor.estado.respuesta(.etapaPregunta(a, $0)) != nil }
        if !cadenaContestada, let v = valor(.etapa(a)), let e = deValor(v) { return e }
        var algo = false
        for n in 1...6 {
            guard let v = valor(.etapaPregunta(a, n)) else { return algo ? .some(nil) : nil }
            algo = true
            if v.esNoLoSe { return .some(nil) }
            if v.siNo != true { return .some(n) }
        }
        return .some(6)
    }

    func textoOpcion(_ id: PreguntaID, _ opciones: [OpcionPregunta]) -> String? {
        guard let v = valor(id) else { return nil }
        if v.esNoLoSe { return TextoPuesta.pendiente }
        return v.opcion.flatMap { o in opciones.first { $0.id == o }?.texto }
    }

    func loQueHeEntendido() -> LoQueHeEntendido {
        let areas = motor.areasDelAlcance
        let filas = areas.map { a in
            LoQueHeEntendido.Fila(area: a, funciona: valor(.funciona(a))?.escala, depende: valor(.depende(a))?.escala,
                                  etapa: etapaDeArea(a) ?? nil, dolor: textoOpcion(.dolor(a), TextosPuesta.dolores(a)),
                                  meta: textoOpcion(.metaArea(a), TextosPuesta.metas(a)),
                                  cita: valor(.cita(a)).flatMap { $0.esNoLoSe ? nil : $0.texto })
        }
        let porArea = Dictionary(uniqueKeysWithValues: filas.map { ($0.area, $0) })
        let entrega = porArea[.entrega]
        func requisitos(_ a: AreaCode) -> Bool {
            switch a {
            case .marca: return (entrega?.funciona ?? 0) >= 3 || (entrega?.etapa ?? 0) >= 2
            case .equipo: return (entrega?.etapa ?? 0) >= 2
            default: return true
            }
        }
        let ordenTLB: [AreaCode] = [.ventas, .entrega, .finanzas, .marca, .equipo, .direccion]
        let candidatas = filas.filter { ($0.depende ?? 0) >= 4 && requisitos($0.area) }.sorted { x, y in
            if x.depende != y.depende { return (x.depende ?? 0) > (y.depende ?? 0) }
            if x.funciona != y.funciona { return (x.funciona ?? 6) < (y.funciona ?? 6) }
            return (ordenTLB.firstIndex(of: x.area) ?? 9) < (ordenTLB.firstIndex(of: y.area) ?? 9)
        }
        var cuello: AreaCode?
        var porQue: String
        if let c = candidatas.first {
            cuello = c.area
            porQue = "\(c.area.nombre) depende de ti \(c.depende ?? 0) de 5" + (c.funciona.map { " y funciona \($0) de 5" } ?? "") + "."
        } else if let c = filas.filter({ [.ventas, .entrega, .finanzas].contains($0.area) && $0.funciona != nil })
                    .min(by: { ($0.funciona ?? 6, ordenTLB.firstIndex(of: $0.area) ?? 9) < ($1.funciona ?? 6, ordenTLB.firstIndex(of: $1.area) ?? 9) }) {
            cuello = c.area
            let empatadas = filas.filter { [.ventas, .entrega, .finanzas].contains($0.area) && $0.funciona == c.funciona }
            if empatadas.count > 1 {
                // Empate: no se dice «la que peor funciona», se dice por qué se empieza por esa.
                let nombres = TextosPuesta.listaDeAreas(empatadas.map(\.area))
                porQue = "Ninguna área depende mucho de ti y \(nombres) funcionan igual (\(c.funciona ?? 0) de 5): empiezo por \(c.area.nombre), la primera en el orden de trabajo."
            } else {
                porQue = "Ninguna área depende mucho de ti; la que peor funciona es \(c.area.nombre) (\(c.funciona ?? 0) de 5)."
            }
        } else {
            porQue = "Aún no tengo datos para saber dónde está el cuello."
        }
        let fundamentales = filas.filter { [.ventas, .entrega, .finanzas].contains($0.area) }.compactMap(\.etapa)
        return LoQueHeEntendido(filas: filas, cuello: cuello, porQue: porQue, etapaGlobal: fundamentales.min())
    }

    func conocer(_ b: inout BorradorCarpeta, entendido: LoQueHeEntendido) {
        let f = b.foto
        let ruta = contexto.rutaDiagnostico
        // Diagnóstico: el que haya o uno nuevo con la plantilla.
        let base = b.texto(ruta) ?? plantilla("diagnostico", f, carpeta: layout.areaFolder(.direccion)) ?? "# Diagnóstico\n"
        var t = base
        var props: [Property] = []
        if let e = entendido.etapaGlobal { props.append(Property(key: "etapa_global", value: .number(String(e)))) }
        if let c = entendido.cuello {
            props.append(Property(key: "cuello", value: .text("[[\(layout.areaFolder(c).appending("Área").raw)|\(c.nombre)]]")))
        }
        t = TextoPuesta.ponerPropiedades(props, en: t)
        // Encuadre.
        let camino = textoOpcion(.camino, TextosPuesta.caminos)
        let meta = textoOpcion(.metaGeneral, TextosPuesta.metasGenerales)
        if camino != nil || meta != nil {
            t = TextoPuesta.sustituirSeccion("Encuadre", por: "- Camino: \(camino ?? TextoPuesta.pendiente)\n- Meta: \(meta ?? TextoPuesta.pendiente)",
                                             en: t, antesDe: "Frase del negocio")
        }
        if let frase = fraseDelNegocio() { t = TextoPuesta.sustituirSeccion("Frase del negocio", por: frase, en: t) }
        if let d = valor(.destino) {
            t = TextoPuesta.sustituirSeccion("Frase destino", por: d.esNoLoSe ? TextoPuesta.pendiente : "«\(escrito(d) ?? "")»", en: t)
        }
        // La tabla de las seis áreas.
        for fila in entendido.filas {
            var celdas: [String: String] = [:]
            func cel(_ col: String, _ id: PreguntaID, _ n: Int?) {
                if valor(id)?.esNoLoSe == true { celdas[col] = TextoPuesta.pendiente } else if let n { celdas[col] = String(n) }
            }
            cel("Funciona (1–5)", .funciona(fila.area), fila.funciona)
            cel("Depende de ti (1–5)", .depende(fila.area), fila.depende)
            if let e = etapaDeArea(fila.area) { celdas["Etapa"] = e.map(String.init) ?? TextoPuesta.pendiente }
            if let v = valor(.cita(fila.area)) { celdas["Lo que dijiste"] = v.esNoLoSe ? TextoPuesta.pendiente : "«\(escrito(v) ?? "")»" }
            guard !celdas.isEmpty else { continue }
            t = TextoPuesta.ponerCeldas(celdas, columnaClave: "Área", valorClave: layout.areaFolder(fila.area).raw,
                                        seccion: "Las seis áreas", crear: true, en: t) ?? t
        }
        if entendido.cuello != nil || entendido.filas.contains(where: { $0.depende != nil }) {
            let c = entendido.cuello.map { "\(layout.areaFolder($0).raw). " } ?? ""
            t = TextoPuesta.sustituirSeccion("Cuello de botella", por: c + entendido.porQue, en: t)
        }
        for fila in entendido.filas where fila.dolor != nil || fila.meta != nil {
            let causa = fila.etapa.flatMap { contexto.catalogo.etapa($0) }.map { "Etapa \($0.num) · \($0.queToca)" } ?? TextoPuesta.pendiente
            t = TextoPuesta.ponerCeldas(["Síntoma (tu frase)": fila.dolor ?? TextoPuesta.pendiente, "Causa": causa,
                                         "Pieza que falta": fila.meta ?? TextoPuesta.pendiente],
                                        columnaClave: "Área", valorClave: layout.areaFolder(fila.area).raw,
                                        seccion: "Síntoma, causa y pieza que falta", crear: true, en: t) ?? t
        }
        if t != base || b.texto(ruta) == nil { b.escribir(ruta, t) }
        // Rumbo: «Qué es la empresa» y «Adónde vamos», solo si lo dijo la persona.
        let fraseNueva = PreguntaID.huecosDeLaFrase.contains { nueva($0) != nil }
        let destino = nueva(.destino)
        guard fraseNueva || destino != nil else { return }
        let rumbo = contexto.rutaRumbo
        var r = b.texto(rumbo) ?? plantilla("rumbo", f, carpeta: layout.areaFolder(.direccion)) ?? "# Rumbo\n"
        if fraseNueva, let frase = fraseDelNegocio() { r = TextoPuesta.sustituirSeccion("Qué es la empresa", por: frase, en: r) }
        if let d = destino { r = TextoPuesta.sustituirSeccion("Adónde vamos", por: escrito(d) ?? TextoPuesta.pendiente, en: r) }
        b.escribir(rumbo, r)
    }

    func fraseDelNegocio() -> String? {
        let h = PreguntaID.huecosDeLaFrase.map { valor($0) }
        guard h.contains(where: { $0 != nil }) else { return nil }
        let x = h.map { v -> String in
            guard let v, let t = escrito(v) else { return TextoPuesta.pendiente }
            return t.trimmingCharacters(in: CharacterSet(charactersIn: ".,; "))
        }
        return "Ayudamos a \(x[0]) a conseguir \(x[1]) en \(x[2]) con \(x[3]), sin \(x[4])."
    }

    // MARK: 3 · Organizar

    func estados() -> [AreaCode: EstadoAreaPuesta] {
        Dictionary(uniqueKeysWithValues: AreaCode.allCases.compactMap { a in motor.estadoArea(a).map { (a, $0) } })
    }

    func organizar(_ b: inout BorradorCarpeta) throws {
        let f = b.foto
        let alcance = motor.areasDelAlcance
        let est = estados()
        let conFicha = contexto.sistemasConFicha
        var estadosCambiados = false
        for a in alcance {
            let rutaArea = layout.areaFolder(a).appending(AreaReader.fileName)
            if !b.existe(rutaArea), let t = cabeceraDeArea(a, f) { b.escribir(rutaArea, t) }
            var props: [Property] = []
            var pendientes: [String] = []
            if let e = nueva(.estadoArea(a)) {
                estadosCambiados = true
                if e.esNoLoSe { pendientes.append("- \(TextoPuesta.pendiente) · ¿En qué estado está \(a.nombre)?") }
                else if let s = e.opcion { props.append(Property(key: "estado", value: .text(s))) }
            }
            let detalle = est[a] != .reposo
            if detalle {
                if let o = nueva(.ocupante(a)) {
                    if o.esNoLoSe { pendientes.append("- \(TextoPuesta.pendiente) · ¿Quién lleva \(a.nombre)?") }
                    else if let s = escrito(o) { props.append(Property(key: "ocupante", value: .text(s))) }
                }
                // El rol del área: su ficha en Equipo si falta.
                if let rol = contexto.catalogo.roles.first(where: { $0.area == a }) {
                    let slug = NombresDeFicha.slug(rol.nombre)
                    let rutaRol = (layout.dir(for: "role") ?? layout.areaFolder(.equipo).appending("Roles")).appending(slug + ".md")
                    if !b.existe(rutaRol) {
                        var poner: [Property] = [Property(key: "areas", value: .list([a.layoutKey])),
                                                 Property(key: "pregunta", value: .text(rol.pregunta)),
                                                 Property(key: "nivel", value: .text("responsable"))]
                        if let o = valor(.ocupante(a)), !o.esNoLoSe, let s = escrito(o) { poner.append(Property(key: "ocupante", value: .text(s))) }
                        if let t = plantilla("rol", f, valores: ["titulo": rol.nombre, "slug": slug], poner: poner,
                                             secciones: ["Misión": rol.mision], area: .equipo) {
                            b.escribir(rutaRol, t)
                        }
                    }
                    if let t = b.texto(rutaArea), TextoPuesta.propiedad("rol", en: t) == nil {
                        props.append(Property(key: "rol", value: .text("[[\(slug)|\(rol.nombre)]]")))
                    }
                }
            }
            b.cambiar(rutaArea) { t in
                var x = TextoPuesta.ponerPropiedades(props, en: t)
                for l in pendientes { x = TextoPuesta.anadirLinea(l, aSeccion: "Pendiente", en: x) }
                return x
            }
            guard detalle else { continue }
            // Sistemas: esqueleto de los que faltan y su estado en la tabla del área.
            var filas: [(codigo: String, nombre: String, enlace: String, estado: String)] = []
            let sistemas = SistemaCatalogo.de(a) + (a == .direccion ? [SistemaCatalogo.codigo("CO1")!] : [])
            let enlazados = Set(LinkParser.links(in: b.texto(rutaArea) ?? "").map { TextFolding.fold(VaultPath($0.target.removingPercentEncoding ?? $0.target).stem) })
            for s in sistemas {
                let v = valor(.sistema(s.codigo))
                let elegido = v?.opcion
                let estado = v?.esNoLoSe == true ? TextoPuesta.pendiente : (elegido ?? "falta")
                if let r = conFicha[s.codigo] {
                    // Ya tiene ficha: solo se apunta el estado si la persona lo cambió.
                    guard let n = nueva(.sistema(s.codigo)) else { continue }
                    if enlazados.contains(TextFolding.fold(r.stem)) {
                        b.cambiar(r) { TextoPuesta.ponerPropiedades([Property(key: "estado", value: .text(n.esNoLoSe ? TextoPuesta.pendiente : (n.opcion ?? "")))], en: $0) }
                    } else {
                        filas.append((s.codigo, s.nombre, enlaceRelativo(desde: rutaArea, a: r, nombre: s.nombre), estado))
                    }
                    continue
                }
                guard s.seInstala || ["montado", "a medias"].contains(elegido ?? "") else { continue }
                let carpeta = s.area.map { layout.areaFolder($0).appending("Sistemas") } ?? VaultPath(layout.buzon ?? "Buzón")
                let ruta = carpeta.appending(s.nombre + ".md")
                if !b.existe(ruta) {
                    var poner: [Property] = [Property(key: "estado", value: .text(estado == TextoPuesta.pendiente ? "falta" : estado))]
                    if let n = s.numeroClave { poner.append(Property(key: "numero_clave", value: .text(n))) }
                    let texto = plantilla("ficha-de-sistema", f, valores: ["titulo": s.nombre, "codigo": s.codigo], poner: poner,
                                          area: s.area ?? .direccion, carpeta: carpeta)
                    if let texto { b.escribir(ruta, texto) }
                }
                if s.area != nil { filas.append((s.codigo, s.nombre, enlaceRelativo(desde: rutaArea, a: ruta, nombre: s.nombre), estado)) }
            }
            if !filas.isEmpty {
                b.cambiar(rutaArea) { t in self.ponerSistemas(filas, en: t) }
            }
            // Ventas: hasta 3 ofertas y el embudo.
            if a == .ventas { ofertas(&b) }
            if a == .entrega { planDeEntrega(&b) }
        }
        if alcance.contains(.marca) || motor.alcance == .todo { try logo(&b) }
        // Empresa.md, AGENTS.md y el vocabulario.
        let activas = AreaCode.allCases.filter { est[$0] == .activa }
        if estadosCambiados {
            b.cambiar(contexto.rutaEmpresa) { t in
                var x = TextoPuesta.ponerPropiedades([Property(key: "areas_activas", value: .list(activas.map(\.layoutKey)))], en: t)
                for a in AreaCode.allCases {
                    guard let e = est[a] else { continue }
                    x = TextoPuesta.ponerCeldas(["Estado": e.titulo], columnaClave: "Área", valorClave: layout.areaFolder(a).raw,
                                                seccion: "Las seis áreas", en: x) ?? x
                }
                return x
            }
            let rutaAgentes = VaultPath("AGENTS.md")
            if b.texto(rutaAgentes) != nil {
                b.cambiar(rutaAgentes) { TextoPuesta.sustituirSeccion("Áreas activas", por: self.textoAreas(est), en: $0) }
            } else {
                b.escribir(rutaAgentes, agentes(estados: est))
            }
        }
        try vocabulario(&b)
    }

    func enlaceRelativo(desde: VaultPath, a: VaultPath, nombre: String) -> String {
        NombresDeFicha.enlaceMarkdown(nombre, desde: desde, a: a)
    }

    /// La tabla `| Código | Sistema | Estado |` de `## Sistemas` (la crea si no está; las filas que ya están cambian).
    func ponerSistemas(_ filas: [(codigo: String, nombre: String, enlace: String, estado: String)], en texto: String) -> String {
        var t = texto
        if TextoPuesta.tabla(con: "Código", seccion: "Sistemas", en: TextoPuesta.lineas(t)) == nil {
            let actual = TextoPuesta.seccion("Sistemas", en: t) ?? ""
            let tabla = "| Código | Sistema | Estado |\n|---|---|---|\n" + filas.map { "| \($0.codigo) | \($0.enlace) | \($0.estado) |" }.joined(separator: "\n")
            // Lo que había (las listas de G3) se queda; la tabla vacía de la plantilla, no.
            let previo = actual.components(separatedBy: "\n").filter { TextoPuesta.celdas(Substring($0)) == nil }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return TextoPuesta.sustituirSeccion("Sistemas", por: previo.isEmpty ? tabla : previo + "\n\n" + tabla, en: t)
        }
        for f in filas {
            t = TextoPuesta.ponerCeldas(["Sistema": f.enlace, "Estado": f.estado], columnaClave: "Código", valorClave: f.codigo,
                                        seccion: "Sistemas", crear: true, en: t) ?? t
        }
        return t
    }

    func ofertas(_ b: inout BorradorCarpeta) {
        let f = b.foto
        let dir = layout.dir(for: "service") ?? layout.areaFolder(.ventas).appending("Productos")
        var lineas: [String] = []
        for n in 1...3 {
            guard let nombreV = nueva(.ofertaNombre(n)), !nombreV.esNoLoSe, let nombre = escrito(nombreV) else { continue }
            let slug = NombresDeFicha.slug(nombre)
            let ruta = dir.appending(slug + ".md")
            var poner: [Property] = []
            let precio = valor(.ofertaPrecio(n))?.numero
            if let p = precio { poner.append(Property(key: "precio", value: .number(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), p)))) }
            if !b.existe(ruta), let t = plantilla("servicio", f, valores: ["titulo": nombre, "slug": slug], poner: poner, area: .ventas, carpeta: dir) {
                b.escribir(ruta, t)
            }
            lineas.append("- [\(nombre)](\(slug).md)" + (precio.map { " · \(MetasEscritor.texto($0, unidad: "€")) sin IVA" } ?? ""))
        }
        let embudo: String? = {
            guard let e = nueva(.embudo) else { return nil }
            if e.esNoLoSe { return TextoPuesta.pendiente }
            if e.opcion == "propio" { return escrito(valor(.embudoEtapas)) ?? TextoPuesta.pendiente }
            return "Prospecto → Diagnóstico → Propuesta → Aceptada → Ganada"
        }()
        guard !lineas.isEmpty || embudo != nil else { return }
        let rutaOferta = dir.appending("Oferta.md")
        var t = b.texto(rutaOferta) ?? """
        ---
        tls_type: index
        tls_schema: 1
        id: \(UUID().uuidString.lowercased())
        coleccion: service
        vista: tabla
        pestanas_por: estado
        ---
        # Oferta

        El catálogo: un servicio, una nota. Los precios solo viven en la ficha de cada servicio.

        """
        for l in lineas { t = TextoPuesta.anadirLinea(l, aSeccion: "Servicios", en: t) }
        if let embudo { t = TextoPuesta.sustituirSeccion("Embudo", por: embudo, en: t) }
        b.escribir(rutaOferta, t)
    }

    func planDeEntrega(_ b: inout BorradorCarpeta) {
        let f = b.foto
        guard let v = nueva(.planEntrega) else { return }
        if v.esNoLoSe {
            b.cambiar(layout.areaFolder(.entrega).appending(AreaReader.fileName)) {
                TextoPuesta.anadirLinea("- \(TextoPuesta.pendiente) · ¿Está escrito cómo se entrega el servicio principal?", aSeccion: "Pendiente", en: $0)
            }
            return
        }
        guard v.opcion == "crear" else { return }
        let dir = layout.dir(for: "service") ?? layout.areaFolder(.ventas).appending("Productos")
        let nombre = escrito(valor(.ofertaNombre(1))).flatMap { $0 == TextoPuesta.pendiente ? nil : $0 } ?? contexto.servicios.first?.nombre ?? "Servicio principal"
        let slug = NombresDeFicha.slug(nombre)
        let servicio = dir.appending(slug + ".md")
        let carpeta = layout.areaFolder(.entrega).appending("Planes de entrega")
        let ruta = carpeta.appending(slug + ".md")
        guard !b.existe(ruta) else { return }
        let enlace = "[[\(servicio.raw.dropLast(3))|\(nombre)]]"
        if let t = plantilla("plan-de-entrega", f, valores: ["servicio.nombre": nombre, "servicio.slug": slug, "servicio.enlace": enlace],
                             area: .entrega, carpeta: carpeta) {
            b.escribir(ruta, t)
            if b.existe(servicio) {
                b.cambiar(servicio) { TextoPuesta.ponerPropiedades([Property(key: "plan", value: .text("[[\(ruta.raw.dropLast(3))|Plan de entrega · \(nombre)]]"))], en: $0) }
            }
        }
    }

    func logo(_ b: inout BorradorCarpeta) throws {
        let f = b.foto
        guard let v = nueva(.logo) else { return }
        let marca = layout.areaFolder(.marca)
        let rutaMarca = marca.appending("Marca.md")
        if v.esNoLoSe {
            b.cambiar(marca.appending(AreaReader.fileName)) {
                TextoPuesta.anadirLinea("- \(TextoPuesta.pendiente) · ¿Tienes logo?", aSeccion: "Pendiente", en: $0)
            }
            return
        }
        switch v.opcion {
        case "tengo":
            guard let elegido = valor(.logoFichero)?.rutas?.first else { return }
            var destino: VaultPath
            let relativo = elegido.hasPrefix("/") ? VaultPath(url: URL(fileURLWithPath: elegido), root: f.root) : VaultPath(elegido)
            if let r = relativo, let enCarpeta = f.existing(r) {
                guard !f.layout.isPrivate(enCarpeta) else { throw ErrorPuesta.logoIlegible(enCarpeta.name) }
                destino = enCarpeta
            } else {
                // Fuera de la carpeta: se copia (10 MB como mucho) a Marca.
                let url = URL(fileURLWithPath: elegido)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? Int else { throw ErrorPuesta.logoIlegible(url.lastPathComponent) }
                guard size <= 10 * 1024 * 1024 else { throw ErrorPuesta.logoDemasiadoGrande(url.lastPathComponent) }
                guard let data = try? Data(contentsOf: url) else { throw ErrorPuesta.logoIlegible(url.lastPathComponent) }
                destino = marca.appending("Activos").appending("Logo").appending("original").appending(url.lastPathComponent)
                var n = 2
                while b.existe(destino) {
                    destino = destino.parent!.appending("\(VaultPath(url.lastPathComponent).stem) (\(n)).\(url.pathExtension)")
                    n += 1
                }
                b.copiar(data, a: destino, origen: url.lastPathComponent)
            }
            let enlace = "[[\(destino.raw)|Logo]]"
            if b.existe(rutaMarca) {
                b.cambiar(rutaMarca) { TextoPuesta.ponerPropiedades([Property(key: "logo", value: .text(enlace))], en: $0) }
            } else if let t = plantilla("manual-de-marca", f, valores: ["marca.logo": enlace], area: .marca, carpeta: marca) {
                b.escribir(rutaMarca, TextoPuesta.ponerPropiedades([Property(key: "logo", value: .text(enlace))], en: t))
            }
        case "web", "aun-no":
            let web = v.opcion == "web" ? escrito(valor(.logoWeb)) : nil
            let titulo = v.opcion == "web" ? "Traer el logo desde la web" : "Conseguir o crear el logo"
            let desc = v.opcion == "web"
                ? "El logo está en \(web ?? TextoPuesta.pendiente). Descárgalo y guárdalo en Marca."
                : "Aún no hay logo. Cuando actives Marca, su asistente puede prepararte un borrador para que lo revises; mientras, los documentos llevan el nombre escrito."
            let nueva = NuevaTarea(titulo: titulo, area: .marca, responsable: motor.estado.persona, estado: .sinProgramar,
                                   descripcion: desc, origen: "manual", autor: autor)
            if let r = try? LoteDeTareas.preparar([nueva], snapshot: f, reloj: contexto.reloj, autor: autor,
                                                    descripcion: "Tarea del logo") {
                b.opsExtra += r.plan.ops
                for case .create(let p, let data) in r.plan.ops where p.ext == "md" {
                    let t = String(decoding: data, as: UTF8.self)
                    b.cambiosExtra.append(CambioPrevisto(ruta: p, clase: .crear, antes: nil, despues: t,
                                                         lineasCambiadas: Set(0..<t.components(separatedBy: "\n").count), resumen: "Nueva"))
                }
            }
        default:
            break
        }
    }

    func vocabulario(_ b: inout BorradorCarpeta) throws {
        var pares: [(String, String)] = []
        for t in TextosPuesta.terminosVocabulario {
            guard let v = nueva(.vocabulario(t.clave)), !v.esNoLoSe, let s = escrito(v) else { continue }
            pares.append((t.clave, s))
        }
        guard !pares.isEmpty else { return }
        try cambiarConfig(&b) { c in
            var actuales = TextoPuesta.entradasYAML("vocabulario", en: c).map { ($0.clave, $0.lineas) }
            for (k, v) in pares {
                let linea = "  \(k): \(TextoPuesta.escalarYAML(v))"
                if let i = actuales.firstIndex(where: { $0.0 == k }) { actuales[i].1 = [linea] } else { actuales.append((k, [linea])) }
            }
            return TextoPuesta.ponerBloqueYAML("vocabulario", ["vocabulario:"] + actuales.flatMap(\.1), en: c)
        }
    }

    /// Cambia `.tls/config.yaml` (lo crea si falta) y comprueba que se sigue leyendo.
    func cambiarConfig(_ b: inout BorradorCarpeta, _ f: (String) -> String) throws {
        let ruta = VaultPath(VaultLayout.configFile)
        let actual = b.texto(ruta) ?? configInicial()
        guard TextoPuesta.yamlValido(actual) else { throw ErrorPuesta.ajustesIlegibles }
        let nuevo = f(actual)
        guard TextoPuesta.yamlValido(nuevo) else { throw ErrorPuesta.ajustesIlegibles }
        if nuevo != actual || b.texto(ruta) == nil { b.escribir(ruta, nuevo) }
    }

    // MARK: 4 · Qué funciona sin ti

    func sinTi(_ b: inout BorradorCarpeta) throws {
        let f = b.foto
        var entradas: [(String, String)] = []
        var revisar: [String] = []
        let quien = motor.estado.persona
        for sis in motor.sistemasSinTi {
            // Si está montado lo dijo Organizar (paso 3): aquí no se vuelve a preguntar.
            guard let montado = motor.montadoEnOrganizar(sis.codigo) else { continue }
            // Lo que viene de la carpeta sin tocar no se reescribe.
            guard nueva(.sistema(sis.codigo)) != nil || nueva(.sinTi(sis.codigo)) != nil || nueva(.automatizar(sis.codigo)) != nil
            else { continue }
            let sinTi = valor(.sinTi(sis.codigo))
            // Un asistente solo con el «Sí» de la persona, y siempre en «Lo hace y revisas» (supervisado).
            let automatizar = valor(.automatizar(sis.codigo))?.siNo == true && montado.opcion == "montado"
            if automatizar { revisar.append(sis.nombre) }
            let capacidades = sis.estandar.compactMap { c in contexto.catalogo.sistemas.first { $0.codigo == c } }.flatMap(\.capacidades)
            for cod in capacidades {
                let recomendado = contexto.catalogo.capacidades.first { $0.codigo == cod }?.ejecutorRecomendado ?? .humano
                var campos: [String] = []
                switch montado {
                case .noLoSe: campos = ["declarada: \(TextoPuesta.pendiente)"]
                case .opcion("montado"):
                    campos = ["declarada: si"]
                    if automatizar {
                        campos += ["modo: supervisado", "ejecutor: \(Self.letra(.agente))"]
                    } else if sinTi == nil || sinTi?.esNoLoSe == true {
                        // «No lo sé» (criterio F3-5): quién lo hace queda PENDIENTE, no se decide por la persona.
                        campos.append("ejecutor: \(TextoPuesta.pendiente)")
                    } else if sinTi?.siNo == true {
                        // Funciona sin ti: lo hace otra persona o algo automático (nunca un asistente sin tu «Sí»).
                        let e: Ejecutor = [.automatizacion, .script].contains(recomendado) ? recomendado : .humano
                        campos += ["ejecutor: \(Self.letra(e))", "sin_ti: si"]
                    } else {
                        campos.append("ejecutor: \(Self.letra(.humano))")
                    }
                    campos += ["declarada_por: \(TextoPuesta.escalarYAML(quien))", "desde: \(hoy)"]
                case .opcion("a medias"):
                    campos = ["declarada: a medias", "declarada_por: \(TextoPuesta.escalarYAML(quien))", "desde: \(hoy)"]
                default:
                    continue
                }
                entradas.append((cod, "  \(cod): {\(campos.joined(separator: ", "))}"))
            }
        }
        if !entradas.isEmpty {
            try cambiarConfig(&b) { c in
                var actuales = TextoPuesta.entradasYAML("capacidades", en: c).map { ($0.clave, $0.lineas) }
                for (k, l) in entradas {
                    if let i = actuales.firstIndex(where: { $0.0 == k }) { actuales[i].1 = [l] } else { actuales.append((k, [l])) }
                }
                return TextoPuesta.ponerBloqueYAML("capacidades", ["capacidades:"] + actuales.flatMap(\.1), en: c)
            }
        }
        // «Sí» a dejarlo a un asistente: una tarea de revisión a los 7 días.
        if !revisar.isEmpty {
            let dia = Tarea.laborable(hoy.adding(days: 7))
            let desc = "Lo pusiste en «Lo hace y revisas» en la puesta en marcha: " + revisar.map(TextosPuesta.llano).joined(separator: ", ")
                + ". Mira cómo ha ido y decide si sigue así, sube o baja de escalón."
            let t = NuevaTarea(titulo: "Revisar lo que dejaste a los asistentes", area: .direccion, responsable: quien,
                               estado: .porHacer, planificada: dia, descripcion: desc, origen: "manual", autor: autor)
            if let r = try? LoteDeTareas.preparar([t], snapshot: f, reloj: contexto.reloj, autor: autor, descripcion: "Revisión a los 7 días") {
                b.opsExtra += r.plan.ops
                for case .create(let p, let data) in r.plan.ops where p.ext == "md" {
                    let s = String(decoding: data, as: UTF8.self)
                    b.cambiosExtra.append(CambioPrevisto(ruta: p, clase: .crear, antes: nil, despues: s,
                                                         lineasCambiadas: Set(0..<s.components(separatedBy: "\n").count), resumen: "Nueva"))
                }
            }
        }
    }

    static func letra(_ e: Ejecutor) -> String {
        switch e {
        case .humano: "H"
        case .agente: "IA"
        case .automatizacion: "A"
        case .script: "S"
        }
    }

    // MARK: 5 · Tu día a día

    func diaADia(_ b: inout BorradorCarpeta) throws {
        let f = b.foto
        let dia = nueva(.rutinaDia), hora = nueva(.rutinaHora), dur = nueva(.rutinaDuracion)
        if dia != nil || hora != nil || dur != nil || contexto.rutinaSemanal == nil {
            var poner: [Property] = []
            if let v = valor(.rutinaDia) { poner.append(Property(key: "dia", value: .text(escrito(v) ?? TextoPuesta.pendiente))) }
            if let v = valor(.rutinaHora) { poner.append(Property(key: "hora", value: .text(escrito(v) ?? TextoPuesta.pendiente))) }
            if let v = valor(.rutinaDuracion) {
                poner.append(Property(key: "duracion_min", value: v.esNoLoSe ? .text(TextoPuesta.pendiente) : .number(escrito(v) ?? "30")))
            }
            if let existente = contexto.rutinaSemanal {
                b.cambiar(existente.ruta) { TextoPuesta.ponerPropiedades(poner, en: $0) }
            } else {
                let semilla = contexto.catalogo.rutinas.first { $0.codigo == "R-DIR-S" }
                let titulo = "Revisión de la semana"
                let pregunta = semilla?.pregunta ?? "¿Qué decidí esta semana, y qué se quedó sin decidir?"
                let dir = layout.dir(for: "routine") ?? layout.areaFolder(.direccion).appending("Rutinas")
                let slug = NombresDeFicha.slug(titulo)
                let ruta = dir.appending(slug + ".md")
                if !b.existe(ruta), let t = plantilla("rutina", f, valores: ["titulo": titulo, "slug": slug, "pregunta": pregunta, "area": "direccion"],
                                                      poner: poner, area: .direccion, carpeta: dir) {
                    b.escribir(ruta, t)
                }
            }
        }
        if let tope = nueva(.topeHoras) {
            let v = tope.esNoLoSe ? TextoPuesta.pendiente : (escrito(tope) ?? "4").replacingOccurrences(of: ",", with: ".")
            try cambiarConfig(&b) { c in
                let ls = TextoPuesta.lineas(c)
                guard let r = TextoPuesta.bloqueYAML("agenda", en: ls) else {
                    return TextoPuesta.ponerBloqueYAML("agenda", ["agenda:", "  tope_horas_dia: \(v)", "  zona: \(self.contexto.reloj.zona.identifier)"], en: c)
                }
                var bloque = ls[r].map(String.init)
                if bloque[0].contains("{") {
                    // Estilo en línea: se reescribe el bloque entero con las mismas claves.
                    var pares: [(String, String)] = []
                    if let n = try? Yams.compose(yaml: bloque.joined(separator: "\n"), Resolver.basic)?.mapping?["agenda"]?.mapping {
                        for (k, x) in n { if let ks = k.string, let xs = x.string { pares.append((ks, xs)) } }
                    }
                    if let i = pares.firstIndex(where: { $0.0 == "tope_horas_dia" }) { pares[i].1 = v } else { pares.insert(("tope_horas_dia", v), at: 0) }
                    bloque = ["agenda:"] + pares.map { "  \($0.0): \($0.1)" }
                } else if let i = bloque.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("tope_horas_dia:") }) {
                    bloque[i] = "  tope_horas_dia: \(v)"
                } else {
                    bloque.insert("  tope_horas_dia: \(v)", at: 1)
                }
                return TextoPuesta.ponerBloqueYAML("agenda", bloque, en: c)
            }
        }
    }

    // MARK: 6 · Tus números

    func numeros(_ b: inout BorradorCarpeta) {
        let f = b.foto
        let ruta = contexto.rutaMetas
        var cambios: [(String, String?, String?)] = []
        for a in motor.areasActivas {
            if valor(.numeroClave(a))?.esNoLoSe == true {
                // «No lo sé» (criterio F3-5): el número clave del área queda PENDIENTE en su `Área.md`.
                if nueva(.numeroClave(a)) != nil {
                    b.cambiar(layout.areaFolder(a).appending(AreaReader.fileName)) {
                        TextoPuesta.ponerPropiedades([Property(key: "numero_clave", value: .text(TextoPuesta.pendiente))], en: $0)
                    }
                }
                continue
            }
            guard let codigo = valor(.numeroClave(a))?.opcion else { continue }
            let meta = nueva(.meta(a)), alerta = nueva(.alerta(a))
            let unidad = contexto.catalogo.kpi(codigo)?.unidad ?? ""
            func celda(_ v: ValorRespuesta?, sinValor: String) -> String? {
                guard let v else { return nil }
                if v.esNoLoSe { return TextoPuesta.pendiente }
                if v.opcion == "sin-meta" { return sinValor }
                return v.numero.map { MetasEscritor.texto($0, unidad: unidad) }
            }
            if meta != nil || alerta != nil || nueva(.numeroClave(a)) != nil {
                cambios.append((codigo, celda(meta ?? valor(.meta(a)), sinValor: "Sin meta"),
                                celda(alerta ?? valor(.alerta(a)), sinValor: "Sin alerta")))
            }
            if nueva(.numeroClave(a)) != nil {
                b.cambiar(layout.areaFolder(a).appending(AreaReader.fileName)) {
                    TextoPuesta.ponerPropiedades([Property(key: "numero_clave", value: .text(codigo))], en: $0)
                }
            }
        }
        if !cambios.isEmpty {
            var t = b.texto(ruta) ?? plantilla("metas", f, carpeta: layout.areaFolder(.direccion)) ?? "# Metas\n\n| Código | Indicador | Meta | Alerta | Por qué |\n|---|---|---|---|---|\n"
            for (codigo, meta, alerta) in cambios {
                var celdas: [String: String] = [:]
                if let meta { celdas["Meta"] = meta }
                if let alerta { celdas["Alerta"] = alerta }
                // Si la fila no está, se añade con su indicador (sin meta hasta que la fijes).
                let existe = TextoPuesta.filas(con: "Código", en: t).contains { TextFolding.fold($0["Código"] ?? "") == TextFolding.fold(codigo) }
                if !existe { celdas["Indicador"] = TextosPuesta.llano(contexto.catalogo.kpi(codigo)?.indicador ?? codigo) }
                t = TextoPuesta.ponerCeldas(celdas, columnaClave: "Código", valorClave: codigo, crear: true, en: t) ?? t
            }
            b.escribir(ruta, t)
        }
        // Objetivo del trimestre (opcional; de serie, sin objetivo de facturación).
        if let o = nueva(.objetivo), o.opcion == "facturacion" {
            let tri = RangoFechas.trimestre(de: hoy)
            let titulo = "Facturación \(FormatosPlantilla.trimestre(hoy))"
            let dir = layout.dir(for: "objective") ?? layout.areaFolder(.direccion).appending("Objetivos")
            let slug = NombresDeFicha.slug(titulo)
            let ruta = dir.appending(slug + ".md")
            var poner: [Property] = [Property(key: "unidad", value: .text("€")), Property(key: "desde", value: .text(tri.desde.description)),
                                     Property(key: "hasta", value: .text(tri.hasta.description)),
                                     Property(key: "medido_por", value: .text("VEN-WON")), Property(key: "acumulado", value: .bool(true))]
            if let c = valor(.objetivoCifra) {
                poner.append(Property(key: "meta", value: c.esNoLoSe ? .text(TextoPuesta.pendiente) : .number(String(format: "%.0f", c.numero ?? 0))))
            }
            if !b.existe(ruta), let t = plantilla("objetivo", f, valores: ["titulo": titulo, "slug": slug], poner: poner, area: .direccion, carpeta: dir) {
                b.escribir(ruta, t)
            }
        }
    }
}
