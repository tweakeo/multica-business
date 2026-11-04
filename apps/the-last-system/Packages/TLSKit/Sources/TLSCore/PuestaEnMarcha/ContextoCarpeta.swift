import Foundation

// F3 · rol motor. Lo que la puesta en marcha sabe ya de la carpeta (solo lee): sirve para elegir la ruta y para
// premarcar cada respuesta con su origen («Lo saqué de Rumbo.md»). Lo privado no se mira.

/// Lo que se lee de la carpeta antes de preguntar.
public struct ContextoCarpeta: Sendable {
    /// Foto de la carpeta (`nil` en «Empiezo de cero»: aún no existe).
    public let foto: VaultSnapshot?
    /// La entrada de `vaults.json`, si ya está registrada.
    public let entrada: VaultEntry?
    public let reloj: Reloj
    public let catalogo: CatalogoPrograma
    /// Tiene la estructura de la app (G3): áreas numeradas con su `Área.md` y `Empresa.md`.
    public let organizada: Bool
    public let areas: [AreaCode: AreaSummary]
    /// Etapa que calcula la app con lo declarado (sin nada declarado, la 1).
    public let etapas: [AreaCode: Int]
    let metricas: FotoMetricas?
    let metas: MetasDocumento?
    /// Lo que cuesta calcular (recorrer todos los ficheros, medir un número) se calcula una vez por foto.
    private let cache = CacheContexto()

    public var hoy: LocalDate { reloj.hoy }
    public var layout: VaultLayout { foto?.layout ?? .humana }

    public init(foto: VaultSnapshot?, entrada: VaultEntry? = nil, reloj: Reloj? = nil, catalogo: CatalogoPrograma = .deSerie) {
        self.foto = foto
        self.entrada = entrada
        let r = reloj ?? foto.map { Reloj.deCarpeta($0) } ?? .sistema()
        self.reloj = r
        self.catalogo = catalogo
        guard let foto else {
            organizada = false; areas = [:]; etapas = [:]; metricas = nil; metas = nil
            return
        }
        var areas: [AreaCode: AreaSummary] = [:]
        for a in AreaCode.allCases {
            let ruta = foto.layout.areaFolder(a).appending(AreaReader.fileName)
            guard let real = foto.existing(ruta), !foto.layout.isPrivate(real), let t = foto.text(real) else { continue }
            areas[a] = AreaReader.parse(markdown: TextoPuesta.limpio(t), code: a, folder: foto.layout.areaFolder(a)) {
                foto.resolver.resolve($0, from: real)
            }
        }
        self.areas = areas
        organizada = foto.existing(VaultPath("Empresa.md")) != nil && areas.count >= 4
        let m = FotoMetricas(snapshot: foto, hoy: r.hoy, ahora: r.ahora)
        metricas = m
        metas = MetasDocumento.leer(foto)
        var etapas: [AreaCode: Int] = [:]
        if !catalogo.sistemas.isEmpty {
            let calc = EtapaCalculador(foto: m, catalogo: catalogo)
            for a in AreaCode.allCases { etapas[a] = calc.area(a).etapa }
        }
        self.etapas = etapas
    }

    /// «Empiezo de cero».
    public static func vacio(reloj: Reloj = .sistema()) -> ContextoCarpeta { ContextoCarpeta(foto: nil, reloj: reloj) }

    /// Un valor que se calcula una vez por foto (lo que depende solo de la carpeta).
    func enCache<T>(_ clave: String, _ calcular: () -> T) -> T { cache.valor(clave, calcular) }

    /// Lee una carpeta.
    public static func leer(_ root: URL, entrada: VaultEntry? = nil, reloj: Reloj? = nil,
                            catalogo: CatalogoPrograma = .deSerie) -> ContextoCarpeta {
        let foto = entrada.map { VaultSnapshot.read(entry: $0, root: root) } ?? VaultSnapshot.read(root: root)
        return ContextoCarpeta(foto: foto, entrada: entrada, reloj: reloj, catalogo: catalogo)
    }

    /// La ruta que toca por lo que hay (sin carpeta, empresa nueva).
    public var rutaDetectada: RutaPuesta {
        guard foto != nil else { return .empresaNueva }
        if entrada?.clase == .demo { return .ejemplo }
        return organizada ? .copiaG3 : .carpetaPorOrdenar
    }

    // MARK: Lectura

    func texto(_ p: VaultPath) -> String? {
        guard let foto, let real = foto.existing(p), !foto.layout.isPrivate(real) else { return nil }
        return TextoPuesta.texto(real, en: foto)
    }

    func existe(_ p: VaultPath) -> VaultPath? {
        guard let foto, let real = foto.existing(p), !foto.layout.isPrivate(real) else { return nil }
        return real
    }

    var rutaEmpresa: VaultPath { VaultPath("Empresa.md") }
    var rutaRumbo: VaultPath { layout.areaFolder(.direccion).appending("Rumbo.md") }
    var rutaDiagnostico: VaultPath { layout.areaFolder(.direccion).appending("Diagnóstico.md") }
    var rutaMetas: VaultPath { MetasDocumento.ruta(layout: layout) }
    var rutaConfig: VaultPath { VaultPath(VaultLayout.configFile) }
    func rutaArea(_ a: AreaCode) -> VaultPath { layout.areaFolder(a).appending(AreaReader.fileName) }

    /// Propiedad de `Empresa.md`.
    func empresa(_ clave: String) -> String? {
        guard let t = texto(rutaEmpresa) else { return nil }
        return TextoPuesta.propiedad(clave, en: t)
    }

    /// Nombre de la empresa: la propiedad `nombre` o el título de `Empresa.md`.
    public var nombreEmpresa: String? {
        if let n = empresa("nombre") { return n }
        guard let t = texto(rutaEmpresa) else { return nil }
        return NoteDocument(text: t).heading
    }

    /// Las rutas declaradas privadas (para que el entrevistador nunca las vea).
    public var nombresPrivados: [String] {
        (foto?.layout.privado ?? []).map(\.name) + (entrada?.exclusionesCopia ?? []).map { VaultPath($0).name }
    }

    /// Sistemas que ya tienen ficha (por su nombre o el que tenían en G3): código → ruta.
    public var sistemasConFicha: [String: VaultPath] {
        cache.valor("sistemas") { () -> [String: VaultPath] in
            guard let foto else { return [:] }
            var out: [String: VaultPath] = [:]
            let porNombre: [String: VaultPath] = Dictionary(
                foto.files.filter { $0.ext == "md" && !foto.layout.isPrivate($0) && !foto.layout.isArchived($0)
                    && $0.components.contains("Sistemas") && !VaultSnapshot.isTemplatePath($0) }
                    .map { (TextFolding.fold($0.stem), $0) },
                uniquingKeysWith: { a, _ in a })
            for s in SistemaCatalogo.todos {
                for n in [s.nombre] + s.alias {
                    if let r = porNombre[TextFolding.fold(n)] { out[s.codigo] = r; break }
                }
                if out[s.codigo] == nil, s.codigo == "CO1", let b = foto.layout.buzon,
                   let r = existe(VaultPath(b).appending("Correspondencia.md")) {
                    out[s.codigo] = r
                }
                if out[s.codigo] == nil, s.codigo == "DI1", let r = existe(layout.areaFolder(.direccion).appending("Decisiones.md")) {
                    out[s.codigo] = r
                }
            }
            return out
        }
    }

    /// Servicios de `2 · Ventas/Productos/` (nombre y precio).
    public var servicios: [(ruta: VaultPath, nombre: String, precio: Double?)] {
        cache.valor("servicios") { () -> [(ruta: VaultPath, nombre: String, precio: Double?)] in
            guard let foto else { return [] }
            let dir = layout.dir(for: "service") ?? layout.areaFolder(.ventas).appending("Productos")
            return foto.notes.filter { $0.parent == dir && !foto.layout.isPrivate($0) }.compactMap { p in
                let fm = foto.frontmatter(p)
                guard fm.text("tls_type") == "service" else { return nil }
                let nombre = fm.text("name") ?? p.stem
                let precio = fm.text("precio").flatMap { FormatoBase.numero($0) }
                return (p, nombre, precio)
            }.sorted { $0.ruta < $1.ruta }
        }
    }

    /// Un logo que ya está en Marca (fichero de imagen o PDF con «logo» en el nombre).
    public var logo: VaultPath? {
        cache.valor("logo") { () -> VaultPath? in
            guard let foto else { return nil }
            let marca = layout.areaFolder(.marca)
            return foto.files.filter { p in
                p.isDescendant(of: marca) && !foto.layout.isPrivate(p) && !foto.layout.isArchived(p)
                    && ["png", "jpg", "jpeg", "svg", "pdf", "heic"].contains(p.ext.lowercased())
                    && TextFolding.fold(p.stem).contains("logo")
            }.sorted { $0.components.count == $1.components.count ? $0 < $1 : $0.components.count < $1.components.count }.first
        }
    }

    /// Una rutina semanal que ya existe (ficha `routine`).
    var rutinaSemanal: (ruta: VaultPath, fm: Frontmatter)? {
        cache.valor("rutina") { () -> (ruta: VaultPath, fm: Frontmatter)? in
            guard let foto else { return nil }
            let dir = layout.dir(for: "routine") ?? layout.areaFolder(.direccion).appending("Rutinas")
            for p in foto.notes where p.parent == dir && !foto.layout.isPrivate(p) {
                let fm = foto.frontmatter(p)
                if fm.text("tls_type") == "routine", TextFolding.fold(fm.text("cadencia") ?? "") == "semanal" { return (p, fm) }
            }
            return nil
        }
    }

    var configTexto: String? { texto(rutaConfig) }

    /// El número clave de un área: `numero_clave` de su `Área.md`.
    func numeroClaveDeArea(_ a: AreaCode) -> String? {
        guard let c = texto(rutaArea(a)).flatMap({ TextoPuesta.propiedad("numero_clave", en: $0) })?.uppercased(),
              c != TextoPuesta.pendiente.uppercased() else { return nil }
        return c
    }

    /// El número clave del área quedó PENDIENTE («No lo sé» en una puesta en marcha anterior).
    func numeroClavePendiente(_ a: AreaCode) -> Bool {
        texto(rutaArea(a)).flatMap { TextoPuesta.propiedad("numero_clave", en: $0) }?.uppercased() == TextoPuesta.pendiente.uppercased()
    }

    /// Lo que hizo un número en los últimos 90 días (lo que sirve de base para la propuesta de meta).
    public func base90Dias(_ codigo: String) -> Double? {
        cache.valor("base90." + codigo) { () -> Double? in base90DiasSinCache(codigo) }
    }

    func base90DiasSinCache(_ codigo: String) -> Double? {
        guard let metricas, let def = catalogo.kpi(codigo), def.calculable else { return nil }
        let ev = KPIEvaluador(foto: metricas, catalogo: catalogo, metas: metas)
        let rango = RangoFechas(desde: hoy.adding(days: -89), hasta: hoy)
        if def.acumulable {
            guard let n = ev.medir(codigo, rango: rango).0.numero else { return nil }
            switch def.periodo {
            case .mes, .dias30: return n / 3
            default: return n
            }
        }
        return ev.medir(codigo).0.numero
    }

    // MARK: Premarcar

    /// Lo que la app propone para una pregunta, con su origen. `nil`: no hay nada que proponer (se pregunta en blanco).
    public func premarcada(_ id: PreguntaID) -> Respuesta? {
        func carpeta(_ v: ValorRespuesta, _ ruta: VaultPath) -> Respuesta {
            Respuesta(valor: v, origen: .carpeta(ruta), confirmada: false)
        }
        func propuesta(_ v: ValorRespuesta, _ texto: String) -> Respuesta {
            Respuesta(valor: v, origen: .propuesta(texto), confirmada: false)
        }
        let s = id.rawValue
        switch id {
        case .como:
            guard let e = entrada else { return nil }
            if e.clase == .demo { return propuesta(.opcion("ejemplo"), "Ya tienes el ejemplo abierto") }
            return propuesta(.opcion("carpeta"), "Ya trabajas con tu carpeta")
        case .modo:
            // Sin carpeta aún, lo recomendado: trabajar sobre una copia (el original no se toca).
            guard let e = entrada else { return propuesta(.opcion("copia"), "Recomendado: tu carpeta original no se toca") }
            return propuesta(.opcion(e.escritura == .permitida ? "copia" : "ver"),
                             e.clase == .real ? "Así la abriste" : "Ya trabajas sobre una copia")
        case .privadas:
            guard let e = entrada, e.clase == .copia || e.clase == .real else { return nil }
            return propuesta(.opcion(e.carpetasPrivadasDeLaCopia.isEmpty ? "no" : "si"), "Lo elegiste al abrir la carpeta")
        case .privadasCuales:
            guard let e = entrada, !e.carpetasPrivadasDeLaCopia.isEmpty else { return nil }
            return propuesta(.rutas(e.carpetasPrivadasDeLaCopia), "Lo elegiste al abrir la carpeta")
        case .nombreEmpresa:
            return nombreEmpresa.map { carpeta(.texto($0), rutaEmpresa) }
        case .sector, .ciudad:
            return empresa(id == .sector ? "sector" : "ciudad").map { carpeta(.texto($0), rutaEmpresa) }
        case .personas:
            return empresa("personas").flatMap(FormatoBase.numero).map { carpeta(.numero($0), rutaEmpresa) }
        case .yo:
            if let t = empresa("titular"), !t.contains("{{") { return carpeta(.texto(LinkParser.plainText(t)), rutaEmpresa) }
            return nil
        case .alcance:
            return organizada ? propuesta(.opcion("todo"), "Recomendado: tu carpeta ya está organizada") : nil
        case .asistente:
            return propuesta(.siNo(false), "Sin asistente todo funciona igual")
        case .destino:
            return texto(rutaRumbo).flatMap { TextoPuesta.seccion("Adónde vamos", en: $0) }?.nilSiVacio
                .map { carpeta(.texto($0), rutaRumbo) }
        case .embudo:
            if let o = rutaOferta, let t = texto(o), TextoPuesta.seccion("Embudo", en: t)?.nilSiVacio != nil {
                return carpeta(.opcion("propio"), o)
            }
            return propuesta(.opcion("serie"), "Lo de serie: Prospecto, Diagnóstico, Propuesta, Aceptada y Ganada")
        case .embudoEtapas:
            if let o = rutaOferta, let t = texto(o), let e = TextoPuesta.seccion("Embudo", en: t)?.nilSiVacio {
                return carpeta(.texto(e), o)
            }
            return nil
        case .planEntrega:
            if let p = planesDeEntrega.first { return carpeta(.opcion("tengo"), p) }
            return nil
        case .logo:
            if let l = logo { return carpeta(.opcion("tengo"), l) }
            return nil
        case .logoFichero:
            if let l = logo { return carpeta(.rutas([l.raw]), l) }
            return nil
        case .rutinaDia, .rutinaHora, .rutinaDuracion:
            if let r = rutinaSemanal {
                let clave = id == .rutinaDia ? "dia" : id == .rutinaHora ? "hora" : "duracion_min"
                if let v = r.fm.text(clave) {
                    if id == .rutinaDuracion, let n = FormatoBase.numero(v) { return carpeta(.numero(n), r.ruta) }
                    if id == .rutinaDia { return carpeta(.opcion(TextFolding.fold(v)), r.ruta) }
                    return carpeta(.texto(v), r.ruta)
                }
            }
            switch id {
            case .rutinaDia: return propuesta(.opcion("lunes"), "Lo de serie: el lunes")
            case .rutinaHora: return propuesta(.texto("09:00"), "Lo de serie: a las 9:00")
            default: return propuesta(.numero(30), "Lo de serie: 30 minutos")
            }
        case .topeHoras:
            if let c = configTexto, let v = TextoPuesta.valorYAML(["agenda", "tope_horas_dia"], en: c), let n = FormatoBase.numero(v) {
                return carpeta(.numero(n), rutaConfig)
            }
            return propuesta(.numero(4), "Lo de serie: 4 horas al día")
        case .objetivo:
            return propuesta(.opcion("sin-objetivo"), "Recomendado para empezar: sin objetivo de facturación")
        case .recorrido:
            return propuesta(.opcion("ahora"), "Son cinco cosas para probar con tu empresa")
        default:
            break
        }
        // Conectar: cada fila con «Ahora no».
        if s.hasPrefix("conectar.") {
            return propuesta(s == PreguntaID.conexion(.ventanaCerrada).rawValue ? .siNo(false) : .opcion("ahora-no"),
                             s == PreguntaID.conexion(.ventanaCerrada).rawValue ? "Apagado de serie" : "Lo puedes conectar cuando quieras")
        }
        // Frase del negocio: de Rumbo («Qué es la empresa») o de Empresa («Qué hace»).
        if let n = PreguntaID.huecosDeLaFrase.firstIndex(of: id), let (frase, ruta) = fraseDelNegocio,
           let huecos = Self.huecos(de: frase) {
            return carpeta(.texto(huecos[n]), ruta)
        }
        // Por área.
        for a in AreaCode.allCases {
            if id == .estadoArea(a), let sum = areas[a], let e = EstadoAreaPuesta(sum.estado) {
                return carpeta(.opcion(e.rawValue), rutaArea(a))
            }
            if id == .ocupante(a), let o = areas[a]?.lleva { return carpeta(.texto(o), rutaArea(a)) }
            if id == .etapa(a) {
                if let d = filaDiagnostico(a), let n = Int(d["Etapa"] ?? "") { return carpeta(.escala(n), rutaDiagnostico) }
                if organizada, let n = etapas[a] { return propuesta(.escala(n), "Lo calculé con lo que hay en tu carpeta") }
            }
            if id == .funciona(a) || id == .depende(a), let d = filaDiagnostico(a) {
                let col = id == .funciona(a) ? "Funciona (1–5)" : "Depende de ti (1–5)"
                if let n = Int(d[col] ?? "") { return carpeta(.escala(n), rutaDiagnostico) }
            }
            if id == .cita(a), let d = filaDiagnostico(a), let c = d["Lo que dijiste"]?.nilSiVacio, c != TextoPuesta.pendiente {
                return carpeta(.texto(c.trimmingCharacters(in: CharacterSet(charactersIn: "«»\""))), rutaDiagnostico)
            }
            if id == .numeroClave(a) {
                if let c = numeroClaveDeArea(a) { return carpeta(.opcion(c), rutaArea(a)) }
                if numeroClavePendiente(a) { return carpeta(.noLoSe, rutaArea(a)) }
                return propuesta(.opcion(NumerosDeSerie.porDefecto(a)), "Lo de serie para \(a.nombre)")
            }
        }
        for sis in SistemaCatalogo.todos where id == .sistema(sis.codigo) {
            if let r = sistemasConFicha[sis.codigo] {
                let estado = foto.flatMap { TextoPuesta.texto(r, en: $0) }.flatMap { TextoPuesta.propiedad("estado", en: $0) }
                let valor = estado.flatMap { e in TextosPuesta.estadosSistema.first { TextFolding.fold($0.id) == TextFolding.fold(e) }?.id }
                return carpeta(.opcion(valor ?? "montado"), r)
            }
        }
        if s.hasPrefix("organizar.oferta.") {
            let partes = s.split(separator: ".")
            if partes.count == 4, let n = Int(partes[2]), n >= 1, n <= servicios.count {
                let sv = servicios[n - 1]
                if partes[3] == "nombre" { return carpeta(.texto(sv.nombre), sv.ruta) }
                if let p = sv.precio { return carpeta(.numero(p), sv.ruta) }
            }
        }
        if s.hasPrefix("organizar.vocabulario."), let c = configTexto {
            let termino = String(s.dropFirst("organizar.vocabulario.".count))
            if let v = TextoPuesta.valorYAML(["vocabulario", termino], en: c)?.nilSiVacio { return carpeta(.texto(v), rutaConfig) }
        }
        if s.hasPrefix("sinti.") { return premarcaSinTi(id) }
        return nil
    }

    /// Texto de la carpeta que se enseña junto a la pregunta (para comparar).
    public func referencia(_ id: PreguntaID) -> String? {
        if PreguntaID.huecosDeLaFrase.contains(id), let (f, ruta) = fraseDelNegocio {
            return "En \(ruta.name) pone: «\(f)»"
        }
        return nil
    }

    var rutaOferta: VaultPath? {
        existe((layout.dir(for: "service") ?? layout.areaFolder(.ventas).appending("Productos")).appending("Oferta.md"))
    }

    var planesDeEntrega: [VaultPath] {
        guard let foto else { return [] }
        let dirs = [layout.areaFolder(.entrega).appending("Planes de entrega"), layout.areaFolder(.entrega).appending("Plantillas")]
        return foto.notes.filter { p in dirs.contains { p.parent == $0 } && !foto.layout.isPrivate(p) }.sorted()
    }

    /// La frase del negocio escrita en la carpeta y dónde.
    var fraseDelNegocio: (String, VaultPath)? {
        if let t = texto(rutaRumbo), let f = TextoPuesta.seccion("Qué es la empresa", en: t)?.nilSiVacio { return (f, rutaRumbo) }
        if let t = texto(rutaEmpresa), let f = TextoPuesta.seccion("Qué hace", en: t)?.nilSiVacio { return (f, rutaEmpresa) }
        return nil
    }

    /// «Ayudamos a X a conseguir Y en Z con W, sin V» → los cinco huecos.
    static func huecos(de frase: String) -> [String]? {
        let re = try? NSRegularExpression(pattern: #"^ayudamos a (.+?) a conseguir (.+?) en (.+?) con (.+?),? sin (.+?)\.?$"#,
                                          options: [.caseInsensitive])
        let t = frase.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard let m = re?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), m.numberOfRanges == 6 else { return nil }
        return (1...5).compactMap { Range(m.range(at: $0), in: t).map { String(t[$0]) } }
    }

    /// La fila de un área en la tabla de `Diagnóstico.md`.
    func filaDiagnostico(_ a: AreaCode) -> [String: String]? {
        guard let t = texto(rutaDiagnostico) else { return nil }
        let carpeta = TextFolding.fold(layout.areaFolder(a).raw)
        return TextoPuesta.filas(con: "Funciona (1–5)", en: t).first {
            TextFolding.fold(LinkParser.plainText($0["Área"] ?? "")) == carpeta
        }
    }

    /// Lo declarado en `config.yaml` para las funciones de un sistema (de los de Organizar: «FI1»).
    func premarcaSinTi(_ id: PreguntaID) -> Respuesta? {
        let partes = id.rawValue.split(separator: ".")
        guard partes.count == 3, let sis = SistemaCatalogo.codigo(String(partes[1])),
              let decl = metricas?.config.capacidades, !decl.isEmpty else { return nil }
        let capacidades = sis.estandar.compactMap { c in catalogo.sistemas.first { $0.codigo == c } }.flatMap(\.capacidades)
        let suyas = capacidades.compactMap { decl[$0] }
        guard !suyas.isEmpty else { return nil }
        let origen = OrigenRespuesta(clase: .carpeta, fuente: rutaConfig, texto: "Lo dice tu configuración")
        switch partes[2] {
        case "sinti":
            // Sin quién lo hace (PENDIENTE) no hay nada que proponer.
            guard suyas.allSatisfy({ $0.sinTi != nil || $0.ejecutor != nil }) else { return nil }
            return Respuesta(valor: .siNo(suyas.allSatisfy { $0.sinTi == true || ($0.ejecutor.map { $0 != .humano } ?? false) }),
                             origen: origen, confirmada: false)
        case "automatizar":
            let sup = suyas.contains { ["supervisado", "autonomo", "autónomo"].contains(TextFolding.fold($0.modo ?? "")) }
            return Respuesta(valor: .siNo(sup), origen: origen, confirmada: false)
        default:
            return nil
        }
    }
}

/// Valores calculados una vez (la foto no cambia: un contexto nuevo trae su propia caché).
final class CacheContexto: @unchecked Sendable {
    /// Envoltorio: así un `nil` calculado se distingue de «aún sin calcular».
    private struct Caja { let valor: Any }
    private let lock = NSLock()
    private var valores: [String: Caja] = [:]

    func valor<T>(_ clave: String, _ calcular: () -> T) -> T {
        if let c = lock.withLock({ valores[clave] }), let v = c.valor as? T { return v }
        let v = calcular()
        lock.withLock { valores[clave] = Caja(valor: v) }
        return v
    }
}
