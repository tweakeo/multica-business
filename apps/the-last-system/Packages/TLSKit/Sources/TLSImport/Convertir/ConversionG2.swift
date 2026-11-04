import Foundation
import TLSCore

/// Dónde acaba un registro de G2 en la carpeta v2.
struct DestinoV2: Sendable, Hashable {
    let ruta: VaultPath
    /// Nombre que se ve (texto de los enlaces).
    let nombre: String
}

/// Un área según `Empresa.md` de G2.
struct AreaG2: Sendable {
    let codigo: AreaCode
    /// Carpeta `N · Nombre`.
    let carpeta: String
    let nombre: String
    let convierte: String?
    let rol: String?
}

/// Estado de una conversión. Se usa en un solo hilo: primero asigna rutas a todo (para saber qué enlaces
/// pueden ir por nombre) y después escribe cada nota.
final class ConversionG2 {
    let carpeta: G2Carpeta
    let opciones: OpcionesConversionG2
    let nombreOrigen: String
    let empresa: G2Registro
    /// Fecha de la exportación (`exported_at` en hora de Madrid).
    let fecha: String
    var areas: [AreaCode: AreaG2] = [:]

    /// Lo que se escribirá.
    var salida: [VaultPath: PlanConversionG2.Contenido] = [:]
    /// Rutas ya ocupadas (clave como la compara APFS).
    var ocupadas: [String: VaultPath] = [:]
    /// `id` de G2 (o clave propia, p. ej. `plan:<id>`) → nota v2.
    var destinos: [String: DestinoV2] = [:]
    /// Ruta G2 de una nota convertida → su nota v2 (para reescribir rutas citadas en el texto).
    var notaDeRutaG2: [String: DestinoV2] = [:]
    /// Nombre de nota (sin `.md`, plegado) → cuántas notas lo usan.
    var conteoNombres: [String: Int] = [:]
    /// Rutas G2 tratadas (convertidas o consumidas por otra nota).
    var tratadas: Set<String> = []
    /// Registros de origen convertidos, por `tls_type`.
    var porTipo: [String: Int] = [:]
    /// Identificadores de fila en los CSV: factura emitida (número), recibida (`REC-…`), pago (`PAG-…`), movimiento (`MOV-…`).
    var idCSV: [String: String] = [:]
    /// PDF de un justificante: id de la factura → (ruta v2, sha256).
    var justificantes: [String: (ruta: VaultPath, sha: String?)] = [:]
    var copiados = 0
    var verificados = 0
    var archivados: [String] = []
    var bloques: [String: (ficheros: Int, destino: String)] = [:]
    private var avisos: [String: (fichas: Set<String>, queHacer: String)] = [:]
    private var noConvertidos: [String: (fichas: Set<String>, motivo: String)] = [:]
    /// Tareas creadas (número → nota).
    var tareas: [(numero: String, area: AreaCode, destino: DestinoV2, registro: G2Registro)] = []
    /// Registros por id.
    let porId: [String: G2Registro]

    init(carpeta: G2Carpeta, opciones: OpcionesConversionG2) throws {
        self.carpeta = carpeta
        self.opciones = opciones
        self.nombreOrigen = carpeta.raiz.lastPathComponent.precomposedStringWithCanonicalMapping
        guard let empresa = carpeta.registros("company").first else {
            throw ErrorConversionG2.noEsG2(carpeta.raiz.lastPathComponent)
        }
        self.empresa = empresa
        if let f = empresa.campos.fecha("exported_at") {
            fecha = f
        } else if let f = carpeta.registros.compactMap({ $0.campos.fecha("created_at") }).max() {
            fecha = f
        } else if let hoy = opciones.hoy {
            fecha = hoy
        } else {
            throw ErrorConversionG2.fechaDesconocida
        }
        var ids: [String: G2Registro] = [:]
        for r in carpeta.registros { if let id = r.id, ids[id] == nil { ids[id] = r } }
        porId = ids
        leerAreas()
    }

    // MARK: Ejecución

    func ejecutar() throws -> PlanConversionG2 {
        asignarRutas()
        asignarIdsCSV()
        escribirFichas()
        escribirFinanzas()
        escribirEstructura()
        archivarLoNoConvertido()
        let informe = componerInforme()
        escribirInforme(informe)
        let ficheros = salida.keys.sorted { $0.raw < $1.raw }.map { ($0, salida[$0]!) }
        return PlanConversionG2(ficheros: ficheros, informe: informe)
    }

    // MARK: Áreas

    func leerAreas() {
        let lista = empresa.campos.lista("areas").compactMap(\.mapa)
        for codigo in AreaCode.allCases {
            let item = lista.first { $0.texto("code") == codigo.layoutKey }
            let nombre = Nombres.nombreDeFichero(item?.texto("name") ?? codigo.nombre)
            areas[codigo] = AreaG2(codigo: codigo, carpeta: "\(codigo.numero) · \(nombre)", nombre: nombre,
                                   convierte: item?.texto("transforms"), rol: item?.texto("role"))
        }
    }

    func area(_ codigo: AreaCode) -> AreaG2 { areas[codigo]! }

    /// `direccion`, `ventas`… → área.
    func area(codigo texto: String?) -> AreaCode? {
        guard let t = texto?.lowercased() else { return nil }
        return AreaCode.allCases.first { $0.layoutKey == t }
    }

    /// Área por el nombre de la carpeta G2 (`Ventas/…`).
    func area(deCarpetaG2 ruta: VaultPath) -> AreaCode? {
        guard let primera = ruta.components.first else { return nil }
        let k = TextFolding.fold(primera)
        return AreaCode.allCases.first { TextFolding.fold($0.nombre) == k || TextFolding.fold(area($0).nombre) == k }
    }

    func ruta(_ codigo: AreaCode, _ resto: String) -> VaultPath {
        VaultPath(area(codigo).carpeta + "/" + resto)
    }

    // MARK: Rutas

    /// Ocupa `ruta`; si ya estaba, prueba `nombre-2`, `nombre-3`… (o `Nombre 2` si lleva espacios).
    @discardableResult
    func reservar(_ ruta: VaultPath) -> VaultPath {
        var candidata = ruta
        var n = 2
        while ocupadas[TextFolding.pathKey(candidata.raw)] != nil {
            let ext = ruta.ext.isEmpty ? "" : "." + ruta.ext
            let sep = ruta.stem.contains(" ") ? " " : "-"
            candidata = (ruta.parent ?? .root).appending("\(ruta.stem)\(sep)\(n)\(ext)")
            n += 1
        }
        ocupadas[TextFolding.pathKey(candidata.raw)] = candidata
        if candidata.ext == "md" {
            conteoNombres[TextFolding.nameKey(candidata.stem), default: 0] += 1
        }
        return candidata
    }

    func registrar(_ clave: String, _ ruta: VaultPath, _ nombre: String, rutaG2: VaultPath? = nil) {
        let d = DestinoV2(ruta: ruta, nombre: nombre)
        destinos[clave] = d
        if let rutaG2 { notaDeRutaG2[rutaG2.raw] = d }
    }

    /// Asigna su ruta a cada nota antes de escribir ninguna.
    func asignarRutas() {
        reservar(VaultPath("Empresa.md"))
        for codigo in AreaCode.allCases { reservar(ruta(codigo, AreaReader.fileName)) }
        reservar(VaultPath("Buzón/Informe de importación \(fecha).md"))
        reservar(ruta(.direccion, "Metas.md"))
        reservar(ruta(.direccion, "Decisiones.md"))
        for indice in IndiceV2.todos where tieneRegistros(indice) {
            reservar(ruta(indice.area, indice.ruta))
        }

        if let id = empresa.id { registrar(id, VaultPath("Empresa.md"), nombreEmpresa, rutaG2: empresa.ruta) }
        registrar("empresa", VaultPath("Empresa.md"), nombreEmpresa, rutaG2: empresa.ruta)

        for r in carpeta.registros("organization") {
            let base = Nombres.sinFormaJuridica(slug: Nombres.kebab(r.stemLimpio))
            asignarFicha(r, carpeta: ruta(.ventas, "Empresas"), slug: base, nombre: r.campos.texto("name"))
        }
        for r in carpeta.registros("contact") {
            asignarFicha(r, carpeta: ruta(.ventas, "Contactos"), slug: Nombres.kebab(r.stemLimpio), nombre: r.campos.texto("name"))
        }
        for r in carpeta.registros("service") {
            let nombre = r.campos.texto("name") ?? r.stemLimpio
            let slug = Nombres.kebab(nombre)
            let nota = asignarFicha(r, carpeta: ruta(.ventas, "Productos"), slug: slug, nombre: nombre)
            if r.campos.mapa("template") != nil, let id = r.id {
                let plan = reservar(ruta(.entrega, "Planes de entrega/\(nota.ruta.stem).md"))
                registrar("plan:\(id)", plan, "Plan de entrega · \(nombre)")
            }
        }
        for r in carpeta.registros("offer") {
            let servicio = porId[r.campos.texto("service_id") ?? ""]?.campos.texto("name")
            let version = r.campos.texto("version")
            let nombre = [servicio, version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " ")
            asignarFicha(r, carpeta: ruta(.ventas, "Productos/Versiones"), slug: Nombres.kebab(r.stemLimpio),
                         nombre: nombre.isEmpty ? r.stemLimpio : nombre)
        }
        for r in carpeta.registros("opportunity") {
            let nota = asignarFicha(r, carpeta: ruta(.ventas, "Oportunidades"), slug: Nombres.kebab(r.stemLimpio),
                                    nombre: r.campos.texto("title"))
            if let p = r.campos.mapa("proposal"), !G2Valor.mapa(p).vacio, let id = r.id {
                let prop = reservar(ruta(.ventas, "Oportunidades/\(nota.ruta.stem)/Propuesta v1.md"))
                registrar("propuesta:\(id)", prop, "Propuesta v1 · \(nota.nombre)")
            }
        }
        for r in carpeta.registros("account") {
            let carpetaCuenta = Nombres.kebab(r.ruta.parent?.name ?? r.campos.texto("name") ?? "cuenta")
            let nota = reservar(ruta(.finanzas, "Registros/Bancos/\(carpetaCuenta)/Cuenta.md"))
            if let id = r.id { registrar(id, nota, r.campos.texto("name") ?? carpetaCuenta, rutaG2: r.ruta) }
        }
        for r in carpeta.registros("invoice") where r.campos.texto("direction") != "received" {
            let numero = r.campos.texto("number")
            let dia = r.campos.fecha("issue_date") ?? r.campos.fecha("created_at") ?? fecha
            let nota: VaultPath
            if let numero, let p = G2Fecha.partes(dia), let t = G2Fecha.trimestre(dia) {
                nota = reservar(ruta(.finanzas, "Fiscal/\(p.anio)/T\(t)/Ingresos/\(Nombres.kebab(numero)).md"))
            } else {
                let cliente = porId[r.campos.texto("organization_id") ?? ""]?.stemLimpio ?? "factura"
                nota = reservar(ruta(.finanzas, "Fiscal/Borradores/\(Nombres.kebab(Nombres.sinFormaJuridica(slug: cliente)))-\(dia).md"))
            }
            if let id = r.id { registrar(id, nota, numero.map { "Factura \($0)" } ?? "Factura en borrador", rutaG2: r.ruta) }
        }
        for r in carpeta.registros("objective") {
            asignarFicha(r, carpeta: ruta(.direccion, "Objetivos"), slug: Nombres.kebab(r.stemLimpio), nombre: r.campos.texto("title"))
        }
        asignarDecisiones()
        for r in carpeta.registros("routine") {
            let clase = r.campos.texto("kind")
            let clave = r.campos.texto("period_key") ?? ""
            if clase == "week", let lunes = G2Fecha.lunes(semanaISO: clave) {
                let semana = clave.uppercased().replacingOccurrences(of: "-W", with: "-S")
                let nota = reservar(ruta(.direccion, "Rutinas/semana/\(lunes).md"))
                if let id = r.id { registrar(id, nota, "Semana \(semana)", rutaG2: r.ruta) }
            } else if clase == "day", G2Fecha.esDia(clave) {
                let nota = reservar(ruta(.direccion, "Rutinas/dia/\(clave).md"))
                if let id = r.id { registrar(id, nota, "Día \(clave)", rutaG2: r.ruta) }
            }
        }
        for r in carpeta.registros("role") {
            asignarFicha(r, carpeta: ruta(.equipo, "Roles"), slug: Nombres.kebab(r.stemLimpio), nombre: r.campos.texto("name"))
        }
        for r in carpeta.registros("content") {
            asignarFicha(r, carpeta: ruta(.marca, "Contenidos"), slug: Nombres.kebab(r.stemLimpio), nombre: r.campos.texto("title"))
        }
        for r in carpeta.registros("conversation") {
            let canal = r.campos.texto("channel") ?? "conversacion"
            let quien = r.campos.texto("handle") ?? r.stemLimpio
            let nombre = "\(quien) en \(canal)"
            asignarFicha(r, carpeta: ruta(.marca, "Conversaciones"), slug: Nombres.kebab("\(canal) \(quien)"), nombre: nombre)
        }
        if let r = carpeta.registros("brand_identity").first {
            let nota = reservar(ruta(.marca, "Marca.md"))
            registrar(r.id ?? "marca", nota, r.titulo ?? "Marca", rutaG2: r.ruta)
            registrar("marca", nota, r.titulo ?? "Marca")
        }
        for r in carpeta.registros("script") {
            let codigo = area(deCarpetaG2: r.ruta) ?? .ventas
            let nombre = r.titulo ?? r.stemLimpio
            let nota = reservar(ruta(codigo, "Activos/\(Nombres.kebab(nombre)).md"))
            registrar(r.id ?? "script:\(r.ruta.raw)", nota, nombre, rutaG2: r.ruta)
        }
        for r in carpeta.registros("period") {
            let anio = r.campos.texto("year") ?? String(fecha.prefix(4))
            let t = r.campos.texto("quarter") ?? "?"
            let nota = reservar(ruta(.finanzas, "Fiscal/\(anio)/T\(t)/Modelos/Paquete gestoría/indice.md"))
            if let id = r.id { registrar(id, nota, "Paquete para la gestoría · T\(t) \(anio)", rutaG2: r.ruta) }
        }
        asignarJustificantes()
    }

    var nombreEmpresa: String { empresa.campos.texto("name") ?? nombreOrigen }

    @discardableResult
    func asignarFicha(_ r: G2Registro, carpeta: VaultPath, slug: String, nombre: String?) -> DestinoV2 {
        let base = slug.isEmpty ? Nombres.kebab(r.stemLimpio) : slug
        let nota = reservar(carpeta.appending("\(base.isEmpty ? "ficha" : base).md"))
        let d = DestinoV2(ruta: nota, nombre: nombre ?? nota.stem)
        if let id = r.id { destinos[id] = d }
        notaDeRutaG2[r.ruta.raw] = d
        return d
    }

    /// Decisiones tomadas → ficha y línea en `Decisiones.md`. Decisiones abiertas y tareas de G2 → una ficha
    /// por tarea en `N · Área/Tareas/t-NNNN-slug.md` (PLAN §4.2), numeradas por fecha de creación. Un número
    /// `T-NNNN` que ya traiga la tarea se conserva si no está repetido.
    func asignarDecisiones() {
        let decisiones = carpeta.registros("decision")
        for r in decisiones where !estaAbierta(r) {
            asignarFicha(r, carpeta: ruta(.direccion, "Decisiones"), slug: slugDecision(r), nombre: r.campos.texto("title"))
        }
        let pendientes = (decisiones.filter { estaAbierta($0) } + carpeta.registros("task"))
            .sorted { ($0.campos.texto("created_at") ?? "", $0.id ?? $0.ruta.raw) < ($1.campos.texto("created_at") ?? "", $1.id ?? $1.ruta.raw) }
        func numeroPropio(_ r: G2Registro) -> Int? {
            guard r.tipo == "task", let n = r.campos.texto("number") ?? r.campos.texto("numero"),
                  n.range(of: #"^T-\d{4,}$"#, options: .regularExpression) != nil else { return nil }
            return Int(n.dropFirst(2))
        }
        var usados = Set<Int>()
        var propios: [String: Int] = [:]
        for r in pendientes { if let n = numeroPropio(r), !usados.contains(n) { usados.insert(n); propios[r.ruta.raw] = n } }
        var siguiente = (usados.max() ?? 0) + 1
        for r in pendientes {
            let n: Int
            if let p = propios[r.ruta.raw] { n = p } else { n = siguiente; siguiente += 1 }
            let numero = String(format: "T-%04d", n)
            let codigo = areaDeTarea(r)
            let titulo = r.campos.texto("title") ?? r.campos.texto("titulo") ?? r.titulo ?? numero
            let base = r.tipo == "decision" ? slugDecision(r) : Nombres.kebab(titulo)
            let slug = Nombres.recortar(base.isEmpty ? "tarea" : base, maximo: 60 - 7)
            let nota = reservar(ruta(codigo, "Tareas/t-\(numero.dropFirst(2))-\(slug).md"))
            let d = DestinoV2(ruta: nota, nombre: titulo)
            if let id = r.id { destinos[id] = d }
            notaDeRutaG2[r.ruta.raw] = d
            tareas.append((numero, codigo, d, r))
        }
        tareas.sort { $0.numero < $1.numero }
    }

    /// Área de una tarea: la suya, la de su oportunidad (Ventas) o Dirección.
    func areaDeTarea(_ r: G2Registro) -> AreaCode {
        if let a = area(codigo: r.campos.texto("area")) { return a }
        if let a = area(deCarpetaG2: r.ruta), r.tipo == "task" { return a }
        if r.campos.texto("opportunity_id") != nil { return .ventas }
        return .direccion
    }

    func estaAbierta(_ r: G2Registro) -> Bool {
        let estado = r.campos.texto("status") ?? ""
        return estado == "open" || estado == "pending" || estado == "proposed"
    }

    /// `2026-10-19--precio-renta-2026-90` → `precio-renta-2026-90`.
    func slugDecision(_ r: G2Registro) -> String {
        var s = r.stemLimpio
        if let rango = s.range(of: #"^\d{4}-\d{2}-\d{2}--"#, options: .regularExpression) { s.removeSubrange(rango) }
        let k = Nombres.kebab(s)
        return k.isEmpty ? Nombres.kebab(r.campos.texto("title") ?? "decision") : k
    }

    func tieneRegistros(_ indice: IndiceV2) -> Bool {
        !carpeta.registros(indice.tipoG2).isEmpty
    }

    // MARK: Enlaces

    /// Destino de un wikilink: el nombre si es único en la carpeta; si no, la ruta sin `.md`.
    func objetivoWiki(_ ruta: VaultPath) -> String {
        (conteoNombres[TextFolding.nameKey(ruta.stem)] ?? 0) <= 1 ? ruta.stem : String(ruta.raw.dropLast(3))
    }

    /// `"[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"`.
    func wikilink(_ d: DestinoV2) -> ValorYAML {
        .enlace("[[\(objetivoWiki(d.ruta))|\(Nombres.textoDeWikilink(d.nombre))]]")
    }

    /// Enlace a un registro por su id de G2. Si el id no está en la exportación, lo apunta como aviso.
    func enlace(_ id: String?, campo: String, en r: G2Registro) -> ValorYAML? {
        guard let id, !id.isEmpty, id != "null" else { return nil }
        guard let d = destinos[id] else {
            avisar("Referencias a fichas que no están en la exportación (\(campo))", r,
                   queHacer: "Revisa si falta algo en el origen; la referencia no se ha copiado.")
            return nil
        }
        return wikilink(d)
    }

    // MARK: Informe

    func avisar(_ texto: String, _ r: G2Registro?, queHacer: String) {
        avisar(texto, ruta: r?.ruta.raw, queHacer: queHacer)
    }

    func avisar(_ texto: String, ruta: String?, queHacer: String) {
        var a = avisos[texto] ?? ([], queHacer)
        if let ruta { a.fichas.insert(ruta) }
        avisos[texto] = a
    }

    /// Campos con valor que no se han convertido (todos los que no están en `usados`).
    func revisar(_ r: G2Registro, usados: Set<String>, motivos: [String: String] = [:]) {
        let tipo = r.tipo ?? "nota"
        for par in r.campos.pares where !usados.contains(par.clave) && !par.valor.vacio {
            if ["tls_type", "tls_schema", "id"].contains(par.clave) { continue }
            let motivo = motivos[par.clave] ?? Self.motivosComunes[par.clave] ?? "No tiene sitio en la carpeta v2."
            registrarNoConvertido("\(tipo).\(par.clave)", ruta: r.ruta.raw, motivo: motivo)
        }
    }

    func registrarNoConvertido(_ clave: String, ruta: String, motivo: String) {
        var c = noConvertidos[clave] ?? ([], motivo)
        c.fichas.insert(ruta)
        noConvertidos[clave] = c
    }

    static let motivosComunes: [String: String] = [
        "updated_at": "Fecha interna de G2: la app guarda su propio historial.",
        "version": "Número de revisión interno de G2.",
        "origin": "Se escribe «origen: importacion».",
        "owner_id": "G2 no guarda nombres de personas, solo identificadores.",
        "owner_type": "G2 no guarda nombres de personas, solo identificadores.",
        "author_id": "G2 no guarda nombres de personas, solo identificadores.",
        "author_type": "G2 no guarda nombres de personas, solo identificadores.",
        "occupant_id": "G2 no guarda nombres de personas, solo identificadores.",
        "confirmed_by_id": "G2 no guarda nombres de personas, solo identificadores.",
        "confirmed_by_type": "G2 no guarda nombres de personas, solo identificadores.",
        "confirmed_at": "Momento interno de la confirmación; queda «verificacion: confirmado».",
        "currency": "Todo está en euros (EUR).",
        "workspace_id": "Identificador del espacio de G2; la carpeta nueva tiene su propio id.",
        "last_contact_at": "La app calcula el último contacto.",
        "paid_minor": "La app calcula lo cobrado a partir de pagos.csv.",
        "payment_terms_days": "Queda en la fecha de vencimiento.",
        "project_id": "Los proyectos no están en la exportación.",
        "workflow_id": "Identificador interno de G2.",
    ]

    func contar(_ r: G2Registro) {
        tratadas.insert(r.ruta.raw)
        porTipo[r.tipo ?? "sin tipo", default: 0] += 1
    }

    func bloque(_ origen: String, destino: String) {
        var b = bloques[origen] ?? (0, destino)
        b.ficheros += 1
        bloques[origen] = b
    }

    func componerInforme() -> InformeConversionG2 {
        let rutaInforme = "Buzón/Informe de importación \(fecha).md"
        // +1: el propio informe, que se escribe después.
        let notas = salida.keys.filter { $0.ext == "md" && !$0.raw.hasPrefix("Archivo/") }.count + 1
        let tablas = salida.keys.filter { $0.ext == "csv" && !$0.raw.hasPrefix("Archivo/") }
            .filter { if case .texto = salida[$0]! { return true } else { return false } }.count
        return InformeConversionG2(
            origen: nombreOrigen, fecha: fecha, ficherosOrigen: carpeta.total, notas: notas, tablas: tablas,
            copiados: copiados, verificados: verificados, archivados: archivados.sorted(),
            porTipo: porTipo, tareas: tareas.count,
            bloques: bloques.keys.sorted().map { InformeConversionG2.Bloque(origen: $0, ficheros: bloques[$0]!.ficheros, destino: bloques[$0]!.destino) },
            avisos: listaAvisos, camposNoConvertidos: listaCampos, informe: rutaInforme)
    }

    var listaAvisos: [InformeConversionG2.Aviso] {
        avisos.keys.sorted().map { InformeConversionG2.Aviso(texto: $0, fichas: avisos[$0]!.fichas.sorted(), queHacer: avisos[$0]!.queHacer) }
    }

    var listaCampos: [InformeConversionG2.CampoNoConvertido] {
        noConvertidos.keys.sorted().map {
            InformeConversionG2.CampoNoConvertido(campo: $0, fichas: noConvertidos[$0]!.fichas.count, motivo: noConvertidos[$0]!.motivo)
        }
    }

    // MARK: Salida

    func escribir(_ ruta: VaultPath, _ nota: NotaNueva) {
        salida[ruta] = .texto(nota.texto)
    }

    func escribir(_ ruta: VaultPath, texto: String) {
        salida[ruta] = .texto(texto)
    }

    func copiar(_ origen: URL, a ruta: VaultPath) {
        salida[ruta] = .copia(origen)
        copiados += 1
    }

    /// Sustituye rutas de G2 citadas en un texto (`Ventas/Guiones/diagnostico-v1.md`) por enlaces a su nota nueva.
    func reescribirRutasG2(_ texto: String, desde: VaultPath) -> String {
        var out = texto
        for rutaG2 in notaDeRutaG2.keys.sorted(by: { ($0.count, $0) > ($1.count, $1) }) where out.contains(rutaG2) {
            let d = notaDeRutaG2[rutaG2]!
            out = out.replacingOccurrences(of: rutaG2, with: Nombres.enlaceMarkdown(d.nombre, desde: desde, a: d.ruta))
        }
        return out
    }

    /// Línea `Fuente:` de las fichas importadas.
    var fuente: String { "Fuente: importación desde G2 («\(nombreOrigen)») · \(fecha)" }
}

/// Notas índice de colección (SISTEMAS.md §1.4).
struct IndiceV2: Sendable {
    let tipoG2: String
    let coleccion: String
    let area: AreaCode
    let ruta: String
    let titulo: String
    let vista: String
    let agruparPor: String?
    let pestanasPor: String?
    let texto: String

    static let todos: [IndiceV2] = [
        IndiceV2(tipoG2: "contact", coleccion: "contact", area: .ventas, ruta: "Contactos/Contactos.md", titulo: "Contactos",
                 vista: "tabla", agruparPor: nil, pestanasPor: "estado",
                 texto: "Cada persona es una ficha. Su papel va en «relación» (cliente, proveedor…) y su ciclo de vida en «estado»: Interesado, Activo, Antiguo cliente o Archivado."),
        IndiceV2(tipoG2: "organization", coleccion: "organization", area: .ventas, ruta: "Empresas/Empresas.md", titulo: "Empresas",
                 vista: "tabla", agruparPor: nil, pestanasPor: "estado",
                 texto: "Cada empresa es una ficha: clientes, proveedores, colaboradores y gestoría. Desde su ficha se ve todo lo suyo."),
        IndiceV2(tipoG2: "opportunity", coleccion: "opportunity", area: .ventas, ruta: "Oportunidades/Oportunidades.md", titulo: "Oportunidades",
                 vista: "tablero", agruparPor: "estado", pestanasPor: nil,
                 texto: "Cada oportunidad es una ficha. Nace junto a su contacto y su empresa, y termina en Ganada (con el cobro visto en el banco) o en Perdida con su motivo."),
        IndiceV2(tipoG2: "service", coleccion: "service", area: .ventas, ruta: "Productos/Oferta.md", titulo: "Oferta",
                 vista: "tabla", agruparPor: nil, pestanasPor: "estado",
                 texto: "El catálogo: un servicio, una nota. Los precios solo viven aquí; cada versión aprobada se congela en Versiones."),
        IndiceV2(tipoG2: "content", coleccion: "content", area: .marca, ruta: "Contenidos/Contenidos.md", titulo: "Contenidos",
                 vista: "tablero", agruparPor: "estado", pestanasPor: nil,
                 texto: "Cada pieza es una ficha que pasa por Idea, Borrador, En revisión, Aprobado, Programado y Publicado."),
        IndiceV2(tipoG2: "conversation", coleccion: "conversation", area: .marca, ruta: "Conversaciones/Conversaciones.md", titulo: "Conversaciones",
                 vista: "tabla", agruparPor: nil, pestanasPor: "estado",
                 texto: "Lo que vuelve del público, con la pieza que lo trajo. Ventas decide si cualifica."),
        IndiceV2(tipoG2: "role", coleccion: "role", area: .equipo, ruta: "Roles/Roles.md", titulo: "Roles",
                 vista: "tabla", agruparPor: nil, pestanasPor: nil,
                 texto: "Un rol por ficha, para personas y asistentes. La ficha describe; los permisos de verdad están en la configuración."),
    ]
}
