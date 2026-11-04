import Foundation
import TLSCore

/// Lee de la foto de la carpeta lo que pinta el andamio de un área (PLAN §6.5, SISTEMAS §2.3 y §4.2). Puro y sin
/// interfaz: se usa fuera del hilo principal y en las pruebas. **Nunca enseña lo privado**: los sistemas, activos y
/// roles de rutas privadas se saltan. Lo que falta se dice («Sin dato», «Sin meta», «Falta»), nunca se inventa.
public struct LectorArea: Sendable {
    public let foto: VaultSnapshot
    public let hoy: LocalDate
    public let proveedor: any ProveedorNumerosArea
    public let registro: PlantillaRegistro

    public init(foto: VaultSnapshot, hoy: LocalDate, proveedor: any ProveedorNumerosArea = SinNumeros(),
                registro: PlantillaRegistro = .deSerie) {
        self.foto = foto; self.hoy = hoy; self.proveedor = proveedor; self.registro = registro
    }

    var layout: VaultLayout { foto.layout }

    // MARK: Un área

    public func leer(_ area: AreaCode) -> DatosArea {
        let resolver = foto.resolver
        let carpeta = layout.areaFolder(area)
        let fichaRuta = carpeta.appending(AreaReader.fileName)
        let texto = foto.text(fichaRuta)
        let resumen = texto.map { t in AreaReader.parse(markdown: t, code: area, folder: carpeta) { resolver.resolve($0, from: fichaRuta) } }
            ?? AreaReader.missing(code: area, folder: carpeta)
        let fm = texto == nil ? Frontmatter.empty : foto.frontmatter(fichaRuta)

        // Rol, ocupante y pregunta: lo del área manda; si no, lo de la ficha del rol.
        let rutaRol = rutaDelRol(fm.text("rol"), nombre: resumen.rol, desde: fichaRuta, resolver: resolver)
        let fmRol = rutaRol.map { foto.frontmatter($0) } ?? .empty
        let ocupante = Self.nombreOcupante(Self.texto(fm, "ocupante") ?? resumen.lleva ?? Self.texto(fmRol, "ocupante"))
        let pregunta = Self.texto(fm, "pregunta") ?? Self.texto(fmRol, "pregunta")

        // Números de `Metas.md`.
        let (todas, rutaMetas) = filasDeMetas()
        let contexto = ContextoNumeros(foto: foto, hoy: hoy, metas: todas)
        let prefijo = CatalogoSistemas.prefijo(de: area)
        var control = todas.filter { $0.codigo.hasPrefix(prefijo) }
        let numeros = proveedor.numeros(de: area, codigos: control.map(\.codigo), contexto: contexto)
        for i in control.indices { if let l = numeros.lecturas[control[i].codigo] { control[i].lectura = l } }

        let etapa = Self.entero(fm, "etapa") ?? numeros.etapa
        let numeroClave = Self.numeroClave(area: fm, rol: fmRol, filas: control)

        let (sistemas, sueltos) = sistemasYActivos(area, carpeta: carpeta, resumen: resumen, textoArea: texto,
                                                   resolver: resolver, codigos: todas.map(\.codigo))
        return DatosArea(area: area, carpeta: carpeta, ficha: texto == nil ? nil : fichaRuta,
                         titulo: resumen.etiquetaNumerada, convierte: resumen.transforma, rol: resumen.rol, rutaRol: rutaRol,
                         ocupante: ocupante, pregunta: pregunta, fase: FaseArea(resumen.estado), etapa: etapa,
                         asistente: CatalogoSistemas.asistente(de: area), numeroClave: numeroClave, control: control,
                         metas: rutaMetas, sistemas: sistemas, activosSueltos: sueltos,
                         activadaEl: Self.fecha(fm, "activada"), activacionReciente: activacionReciente(salvo: area),
                         hoy: hoy)
    }

    // MARK: Metas

    /// Todas las filas de `1 · Dirección/Metas.md` (sin lectura) y su ruta. Vacío si no existe o es privada.
    public func filasDeMetas() -> ([FilaControl], VaultPath?) {
        let ruta = layout.areaFolder(.direccion).appending("Metas.md")
        guard !layout.isPrivate(ruta), let texto = foto.text(ruta) else { return ([], nil) }
        let como = Self.comoSeMide(texto)
        let filas = (MarkdownTable.rows(in: texto, selector: TableSelector(columna: "Código")) ?? []).compactMap { r -> FilaControl? in
            func celda(_ nombre: String) -> String? {
                let v = (r[nombre] ?? r.first { TextFolding.fold($0.key) == TextFolding.fold(nombre) }?.value)?
                    .trimmingCharacters(in: .whitespaces)
                return v.flatMap { $0.isEmpty ? nil : $0 }
            }
            guard let codigo = celda("Código")?.replacingOccurrences(of: "`", with: "") else { return nil }
            return FilaControl(codigo: codigo, indicador: celda("Indicador") ?? codigo, meta: celda("Meta"),
                               alerta: celda("Alerta"), porQue: celda("Por qué"), comoSeMide: como[codigo])
        }
        return (filas, ruta)
    }

    /// Las líneas de «## Cómo se mide»: `- FIN-AR · Σ pendiente… · ahora · menos es mejor` → código → resto.
    static func comoSeMide(_ texto: String) -> [String: String] {
        var out: [String: String] = [:]
        var dentro = false
        for linea in texto.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let t = linea.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") { dentro = TextFolding.fold(String(t.dropFirst(3))).hasPrefix("como se mide"); continue }
            guard dentro, t.hasPrefix("- ") else { continue }
            let partes = t.dropFirst(2).components(separatedBy: " · ")
            guard partes.count >= 2 else { continue }
            let codigo = partes[0].trimmingCharacters(in: .whitespaces)
            out[codigo] = partes.dropFirst().joined(separator: " · ")
        }
        return out
    }

    /// El número clave: `numero_clave` del área, el primero de `numeros` del rol o el primero del área en `Metas.md`.
    static func numeroClave(area fm: Frontmatter, rol fmRol: Frontmatter, filas: [FilaControl]) -> String? {
        let codigos = Set(filas.map(\.codigo))
        if let c = texto(fm, "numero_clave")?.uppercased(), codigos.contains(c) { return c }
        if case .list(let l)? = fmRol.value("numeros"), let c = l.map({ $0.trimmingCharacters(in: .whitespaces).uppercased() })
            .first(where: { codigos.contains($0) }) { return c }
        return filas.first?.codigo
    }

    // MARK: Rol y ocupante

    func rutaDelRol(_ propiedad: String?, nombre: String?, desde: VaultPath, resolver: LinkResolver) -> VaultPath? {
        if let propiedad, let link = LinkParser.links(in: propiedad).first(where: { !$0.isExternal }),
           let r = resolver.resolve(link.resolvable, from: desde), !layout.isPrivate(r) {
            return r
        }
        guard let nombre = nombre.map(TextFolding.fold), !nombre.isEmpty else { return nil }
        return foto.notes.first { p in
            guard !layout.isPrivate(p), !VaultSnapshot.isTemplatePath(p) else { return false }
            let f = foto.frontmatter(p)
            guard f.text("tls_type") == "role" else { return false }
            return TextFolding.fold(f.text("nombre") ?? p.stem) == nombre
        }
    }

    /// «agente:comercial» → «Comercial (asistente)»; un enlace, su texto; vacío → `nil`.
    public static func nombreOcupante(_ crudo: String?) -> String? {
        guard var t = crudo?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        t = LinkParser.plainText(t).trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("agente:") {
            let slug = t.dropFirst("agente:".count).replacingOccurrences(of: "-", with: " ")
            guard !slug.isEmpty else { return nil }
            return slug.prefix(1).uppercased() + slug.dropFirst() + " (asistente)"
        }
        return t.isEmpty ? nil : t
    }

    // MARK: Activación

    /// La otra área activada más reciente, si fue hace menos de 30 días (`activada:` de su `Área.md`).
    func activacionReciente(salvo area: AreaCode) -> ActivacionReciente? {
        var mejor: ActivacionReciente?
        for otra in AreaCode.allCases where otra != area {
            let ruta = layout.areaFolder(otra).appending(AreaReader.fileName)
            guard foto.text(ruta) != nil else { continue }
            let fm = foto.frontmatter(ruta)
            guard AreaReader.status(fm.text("estado") ?? "") == .activa, let dia = Self.fecha(fm, "activada") else { continue }
            let hace = Self.dias(de: dia, a: hoy)
            guard hace >= 0, hace < 30 else { continue }
            if mejor == nil || dia > mejor!.dia {
                mejor = ActivacionReciente(area: otra, titulo: "\(otra.numero) · \(otra.nombre)", dia: dia, haceDias: hace)
            }
        }
        return mejor
    }

    static func dias(de a: LocalDate, a b: LocalDate) -> Int {
        let utc = TimeZone(identifier: "UTC") ?? .current
        return Int((b.date(timeZone: utc).timeIntervalSince(a.date(timeZone: utc)) / 86_400).rounded())
    }

    // MARK: Sistemas y activos

    func sistemasYActivos(_ area: AreaCode, carpeta: VaultPath, resumen: AreaSummary, textoArea: String?,
                          resolver: LinkResolver, codigos: [String] = []) -> ([SistemaDeArea], [ActivoDeArea]) {
        let estadosArea = textoArea.map(Self.estadosDeLaTabla) ?? [:]
        // Fichas de sistema del área (sin lo privado ni las plantillas).
        var fichas: [VaultPath] = foto.notes.filter { p in
            guard p.isDescendant(of: carpeta), !layout.isPrivate(p), !layout.isArchived(p),
                  !VaultSnapshot.isTemplatePath(p) else { return false }
            let tipo = foto.frontmatter(p).text("tls_type")
            return tipo == "system" || (tipo == nil && p.parent?.name == "Sistemas")
        }
        for s in resumen.sistemas {
            if let p = s.path, !fichas.contains(p), !layout.isPrivate(p), foto.text(p) != nil { fichas.append(p) }
        }
        let activos = activos(de: area, carpeta: carpeta, resolver: resolver)
        var usados = Set<VaultPath>()
        var out: [SistemaDeArea] = []
        var vistos = Set<String>()

        func construir(catalogo c: SistemaDeCatalogo?, ficha: VaultPath?, nombreLista: String?) -> SistemaDeArea {
            let fm = ficha.map { foto.frontmatter($0) } ?? .empty
            let texto = ficha.flatMap { foto.text($0) }
            let nombre = Self.texto(fm, "nombre") ?? Self.texto(fm, "titulo")
                ?? texto.flatMap { NoteDocument.firstHeading(in: NoteDocument(text: $0).body) }
                ?? c?.nombre ?? nombreLista ?? ficha?.stem ?? "Sistema"
            let codigo = Self.texto(fm, "codigo")?.uppercased() ?? c?.codigo
            let estado: EstadoSistema = Self.texto(fm, "estado").flatMap(EstadoSistema.init(leyendo:))
                ?? codigo.flatMap { estadosArea[$0] } ?? estadosArea[TextFolding.fold(nombre)]
                ?? (ficha == nil ? .falta : .aMedias)
            let claves = Set([TextFolding.fold(nombre), codigo.map(TextFolding.fold)].compactMap { $0 })
                .union(c?.claves ?? [])
            let suyos = activos.filter { a in
                if let r = a.enlace, let ficha, r == ficha { return true }
                return a.activo.sistema.map { claves.contains(TextFolding.fold($0)) } ?? false
            }
            usados.formUnion(suyos.map(\.activo.ruta))
            let plantillas = codigo.map { cod in
                registro.plantillas.filter { $0.sistemas.contains(cod) }.map { def in
                    URL(fileURLWithPath: def.fichero).deletingPathExtension().lastPathComponent
                }
            } ?? []
            return SistemaDeArea(codigo: codigo, nombre: nombre, estado: estado, ficha: ficha,
                                 numeroClave: Self.texto(fm, "numero_clave")?.uppercased()
                                     ?? c?.numeroClave.flatMap { Self.codigoEnMetas($0, codigos: codigos) },
                                 etapa: Self.entero(fm, "etapa") ?? c?.etapa, deSerie: c?.deSerie ?? false,
                                 funciones: texto.map(Self.funciones) ?? [], activos: suyos.map(\.activo),
                                 plantillas: plantillas, revisado: Self.fecha(fm, "revisado"))
        }

        // Primero los del catálogo, en su orden; con su ficha si la hay.
        for c in CatalogoSistemas.de(area) {
            let ficha = fichas.first { p in
                let fm = foto.frontmatter(p)
                return CatalogoSistemas.reconocer(codigo: fm.text("codigo"), nombre: Self.texto(fm, "nombre") ?? p.stem, area: area)?.codigo == c.codigo
            }
            let enLista = resumen.sistemas.first { CatalogoSistemas.reconocer(codigo: nil, nombre: $0.nombre, area: area)?.codigo == c.codigo }
            out.append(construir(catalogo: c, ficha: ficha ?? enLista?.path, nombreLista: enLista?.nombre))
            vistos.insert(c.codigo)
            if let f = ficha ?? enLista?.path { usados.insert(f) }
        }
        // Después, los propios del área (fichas o nombres en `## Sistemas` que no son del catálogo).
        for p in fichas where !usados.contains(p) {
            out.append(construir(catalogo: nil, ficha: p, nombreLista: nil))
            usados.insert(p)
        }
        for s in resumen.sistemas where s.path == nil {
            guard CatalogoSistemas.reconocer(codigo: nil, nombre: s.nombre, area: area) == nil,
                  !out.contains(where: { TextFolding.fold($0.nombre) == TextFolding.fold(s.nombre) }) else { continue }
            out.append(construir(catalogo: nil, ficha: nil, nombreLista: s.nombre))
        }
        let sueltos = activos.map(\.activo).filter { !usados.contains($0.ruta) }
        return (out, sueltos)
    }

    /// `| Código | Sistema | Estado |` de `## Sistemas` en `Área.md`: código (o nombre) → estado.
    static func estadosDeLaTabla(_ texto: String) -> [String: EstadoSistema] {
        var out: [String: EstadoSistema] = [:]
        for fila in MarkdownTable.rows(in: texto, selector: TableSelector(seccion: "Sistemas", columna: "Estado")) ?? [] {
            func celda(_ n: String) -> String? {
                fila.first { TextFolding.fold($0.key) == TextFolding.fold(n) }?.value.trimmingCharacters(in: .whitespaces)
            }
            guard let e = celda("Estado").flatMap(EstadoSistema.init(leyendo:)) else { continue }
            if let c = celda("Código"), !c.isEmpty { out[c.uppercased()] = e }
            if let n = celda("Sistema").map(LinkParser.plainText), !n.isEmpty { out[TextFolding.fold(n)] = e }
        }
        return out
    }

    /// Los pasos de `## Pasos` (`| # | Paso | Quién | Modo | Deja hecho |`) en lenguaje llano.
    static func funciones(_ texto: String) -> [FuncionDeSistema] {
        let filas = MarkdownTable.rows(in: texto, selector: TableSelector(seccion: "Pasos", columna: "Paso")) ?? []
        var out: [FuncionDeSistema] = []
        for (i, f) in filas.enumerated() {
            func celda(_ n: String) -> String? {
                let v = f.first { TextFolding.fold($0.key) == TextFolding.fold(n) }?.value.trimmingCharacters(in: .whitespaces)
                return v.flatMap { $0.isEmpty ? nil : $0 }
            }
            guard let paso = celda("Paso").map(LinkParser.plainText), !paso.isEmpty else { continue }
            let deja = celda("Deja hecho").map(LinkParser.plainText)
            let numero = celda("#").flatMap { Int($0) } ?? (i + 1)
            out.append(FuncionDeSistema(numero: numero, paso: paso, quien: celda("Quién").map(LinkParser.plainText),
                                        modo: celda("Modo").map(ModoFuncion.init(leyendo:)) ?? .sinDecidir,
                                        sensible: FuncionDeSistema.esSensible(paso + " " + (deja ?? "")), dejaHecho: deja))
        }
        return out
    }

    struct ActivoLeido { let activo: ActivoDeArea; let enlace: VaultPath? }

    /// Activos del área: `Activos/` o `tls_type: asset` dentro de su carpeta. Sin lo privado ni lo archivado.
    func activos(de area: AreaCode, carpeta: VaultPath, resolver: LinkResolver) -> [ActivoLeido] {
        foto.notes.compactMap { p -> ActivoLeido? in
            guard p.isDescendant(of: carpeta), !layout.isPrivate(p), !layout.isArchived(p),
                  !VaultSnapshot.isTemplatePath(p) else { return nil }
            let fm = foto.frontmatter(p)
            let tipo = fm.text("tls_type")
            guard tipo == "asset" || (tipo == nil && p.components.contains("Activos")) else { return nil }
            let titulo = foto.text(p).map { NoteDocument(text: $0).title(fileStem: p.stem, frontmatter: fm) } ?? p.stem
            let crudo = fm.text("sistema")
            let enlace = crudo.flatMap { LinkParser.links(in: $0).first { !$0.isExternal } }.flatMap { resolver.resolve($0.resolvable, from: p) }
            let sistema = crudo.map(LinkParser.plainText).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            let ejemplo: Bool = { if case .bool(let b)? = fm.value("ejemplo_bueno") { return b }; return false }()
            return ActivoLeido(activo: ActivoDeArea(ruta: p, nombre: Self.texto(fm, "nombre") ?? titulo,
                                                    estado: Self.texto(fm, "estado"), sistema: sistema, ejemploBueno: ejemplo),
                               enlace: enlace)
        }
        .sorted { $0.activo.nombre.localizedStandardCompare($1.activo.nombre) == .orderedAscending }
    }

    /// El código del catálogo tal como está en `Metas.md` («DIR-DEC14» del catálogo es «DIR-DEC» en Ribera). `nil` si
    /// la carpeta no lo mide: no se enseña un número que no existe.
    static func codigoEnMetas(_ codigo: String, codigos: [String]) -> String? {
        if codigos.contains(codigo) { return codigo }
        return codigos.filter { $0.count >= 5 && codigo.hasPrefix($0) }.max { $0.count < $1.count }
    }

    // MARK: Apoyo

    static func texto(_ fm: Frontmatter, _ clave: String) -> String? {
        guard let t = fm.text(clave)?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }

    static func entero(_ fm: Frontmatter, _ clave: String) -> Int? {
        switch fm.value(clave) {
        case .number(let s)?, .text(let s)?: Int(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    static func fecha(_ fm: Frontmatter, _ clave: String) -> LocalDate? {
        texto(fm, clave).flatMap { LocalDate(parsing: $0) }
    }
}
