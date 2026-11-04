import Foundation

/// Un grupo de filas (§4.5): su valor, su título y su subtotal («3 · 450 €»).
public struct GrupoFilas: Identifiable, Sendable, Hashable {
    public let id: String
    public let titulo: String
    public let filas: [FilaBase]
    public let suma: Double?

    public var resumen: String {
        let n = String(filas.count)
        guard let suma else { return n }
        return "\(n) · \(FormatoBase.euros(suma, redondo: true))"
    }
}

/// Una sugerencia de filtro al escribir en el buscador de la base («vencidas» → «Vence antes de hoy»).
public struct SugerenciaFiltro: Sendable, Hashable, Identifiable {
    public var id: String { filtro.id }
    public let filtro: FiltroBase
    public let etiqueta: String
}

/// Lo que se ve de una base con una configuración: pestaña, búsqueda, filtros, orden y grupos. Puro (sin
/// interfaz ni disco), para poder probarlo y usarlo fuera del hilo principal.
public enum MotorVista {
    // MARK: Todo junto

    /// Filas visibles: pestaña + búsqueda + filtros, ordenadas.
    /// `extra`: ids que coinciden con la búsqueda por su texto (cuerpo de la nota, del índice de texto completo).
    public static func filas(_ datos: DatosBase, config: ConfigVista, busqueda: String = "", extra: Set<String> = []) -> [FilaBase] {
        let pestana = datos.pestanas.first { $0.id == config.pestana }
        let archivadas = datos.pestanas.filter(\.archivada)
        let c = datos.coleccion
        let visibles = datos.filas.filter { f in
            if let pestana {
                guard pasa(f, pestana: pestana, datos: datos) else { return false }
            } else if archivadas.contains(where: { pasa(f, pestana: $0, datos: datos) }) {
                return false
            }
            if !busqueda.trimmingCharacters(in: .whitespaces).isEmpty,
               !coincide(f, busqueda: busqueda, coleccion: c), !extra.contains(f.id) { return false }
            return config.filtros.allSatisfy { pasa(f, filtro: $0, coleccion: c, hoy: datos.hoy) }
        }
        return ordenar(visibles, por: config.orden, coleccion: c, hoy: datos.hoy)
    }

    /// Cuántas fichas tiene una pestaña (sin búsqueda ni filtros): el contador de la cápsula.
    public static func cuenta(_ pestana: PestanaBase?, datos: DatosBase) -> Int {
        guard let pestana else {
            let archivadas = datos.pestanas.filter(\.archivada)
            return datos.filas.filter { f in !archivadas.contains { pasa(f, pestana: $0, datos: datos) } }.count
        }
        return datos.filas.filter { pasa($0, pestana: pestana, datos: datos) }.count
    }

    // MARK: Pestañas

    public static func pasa(_ f: FilaBase, pestana: PestanaBase, datos: DatosBase) -> Bool {
        let c = datos.coleccion
        let hoy = datos.hoy
        switch pestana.filtro {
        case .valores(let clave, let valores):
            let vs = valoresDe(f, clave, c).map(TextFolding.fold)
            return valores.contains { v in vs.contains(TextFolding.fold(v)) }
        case .noValores(let clave, let valores):
            let vs = valoresDe(f, clave, c).map(TextFolding.fold)
            return !valores.contains { v in vs.contains(TextFolding.fold(v)) }
        case .mio:
            guard let p = datos.persona, !p.isEmpty, let r = f.texto("responsable") else { return false }
            let rf = TextFolding.fold(r), pf = TextFolding.fold(p)
            return rf == pf || rf == pf.split(separator: " ").first.map(String.init) || pf.hasPrefix(rf + " ")
        case .hoy(let clave):
            guard abierta(f, c) else { return false }
            return f.fecha(clave).map { $0 <= hoy } ?? false || f.fecha("vence") == hoy
        case .semana(let clave):
            guard abierta(f, c), let d = f.fecha(clave) ?? f.fecha("vence") else { return false }
            return d >= hoy && d <= hoy.adding(days: 6)
        case .vencidas(let clave):
            guard abierta(f, c), let d = f.fecha(clave) else { return false }
            return d < hoy
        }
    }

    /// Valores de una propiedad en una fila (listas incluidas), por columna si la hay.
    static func valoresDe(_ f: FilaBase, _ clave: String, _ c: ColeccionBase) -> [String] {
        if let col = c.columna(clave) { return f.valoresOpcion(col) }
        return f.texto(clave).map { [$0] } ?? []
    }

    /// Sigue abierta (su estado no está entre los cerrados).
    public static func abierta(_ f: FilaBase, _ c: ColeccionBase) -> Bool {
        guard let col = c.columnaEstado, let e = f.valor(col).map(FormatoBase.textoVisible) else { return true }
        return !c.cerrados.contains { TextFolding.fold($0) == TextFolding.fold(e) }
    }

    // MARK: Búsqueda

    /// Coincide con lo escrito: todas las palabras aparecen en el título, otros nombres, número o código,
    /// o en sus propiedades de texto (sin tildes ni mayúsculas).
    public static func coincide(_ f: FilaBase, busqueda: String, coleccion c: ColeccionBase) -> Bool {
        let palabras = TextFolding.fold(busqueda).split(whereSeparator: { $0 == " " }).map(String.init)
        guard !palabras.isEmpty else { return true }
        let pajar = textoBuscable(f, coleccion: c)
        return palabras.allSatisfy { pajar.contains($0) }
    }

    static func textoBuscable(_ f: FilaBase, coleccion c: ColeccionBase) -> String {
        var partes = [f.titulo] + f.otrosNombres
        for (_, v) in f.valores { partes.append(FormatoBase.textoVisible(v)) }
        for e in f.enlaces.values.flatMap({ $0 }) { partes.append(e.texto) }
        for v in f.calculados.values { partes.append(v.texto) }
        return TextFolding.fold(partes.joined(separator: " \u{1F} "))
    }

    /// Dónde resaltar lo buscado en un texto (sin tildes ni mayúsculas): la frase entera o, si no, la primera
    /// palabra que aparezca.
    public static func resaltar(_ texto: String, busqueda: String) -> Range<String.Index>? {
        let q = TextFolding.fold(busqueda).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !texto.isEmpty else { return nil }
        var plegado: [Character] = []
        var mapa: [String.Index] = []
        for i in texto.indices {
            for ch in TextFolding.fold(String(texto[i])) {
                plegado.append(ch)
                mapa.append(i)
            }
        }
        let candidatos = [q] + q.split(separator: " ").map(String.init)
        for cand in candidatos where !cand.isEmpty {
            let objetivo = Array(cand)
            guard objetivo.count <= plegado.count else { continue }
            for inicio in 0...(plegado.count - objetivo.count) where plegado[inicio] == objetivo[0] {
                if Array(plegado[inicio..<(inicio + objetivo.count)]) == objetivo {
                    let fin = mapa[inicio + objetivo.count - 1]
                    return mapa[inicio]..<texto.index(after: fin)
                }
            }
        }
        return nil
    }

    /// Lo escrito parece un filtro (§4.5): «vencidas» → «Vence antes de hoy»; «Lucía» → «Responsable es
    /// Lucía»; «propuesta» → «Etapa es Propuesta»; «nexo» → «Empresa enlaza con Arquitectura Nexo».
    public static func sugerencias(_ busqueda: String, datos: DatosBase, limite: Int = 3) -> [SugerenciaFiltro] {
        let q = TextFolding.fold(busqueda).trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return [] }
        let c = datos.coleccion
        var out: [SugerenciaFiltro] = []
        func anadir(_ f: FiltroBase) {
            guard !out.contains(where: { $0.filtro == f }) else { return }
            out.append(SugerenciaFiltro(filtro: f, etiqueta: "Filtro: " + f.etiqueta(en: c)))
        }
        if ["vencidas", "vencida", "vencidos", "vencido", "atrasadas", "atrasados"].contains(q),
           let col = ["vence", "plazo", "valida_hasta", "siguiente_fecha"].compactMap({ c.columna($0) }).first {
            anadir(FiltroBase(col.clave, .antesDe, [FiltroBase.hoy]))
        }
        if ["quietas", "quieta", "paradas"].contains(q), let col = c.columnas.first(where: { $0.calculo == .diasEnEtapa }) {
            anadir(FiltroBase(col.clave, .pideAtencion))
        }
        for col in c.columnas where col.tipo == .opcion || col.tipo == .opciones {
            for o in col.opciones where TextFolding.fold(o).hasPrefix(q) || TextFolding.fold(FormatoBase.opcionVisible(o)).hasPrefix(q) {
                anadir(FiltroBase(col.clave, .es, [o]))
            }
        }
        for col in c.columnas where col.tipo == .persona {
            let personas = Set(datos.filas.compactMap { $0.texto(col.clave) })
            for p in personas.sorted() where TextFolding.fold(p).hasPrefix(q) || TextFolding.fold(FormatoBase.persona(p)).hasPrefix(q) {
                anadir(FiltroBase(col.clave, .es, [p]))
            }
        }
        for col in c.columnas where col.tipo == .relacion {
            let nombres = Set(datos.filas.flatMap { $0.enlaces(col).map(\.texto) })
            for n in nombres.sorted() where TextFolding.fold(n).split(separator: " ").contains(where: { $0.hasPrefix(q) }) {
                anadir(FiltroBase(col.clave, .enlazaCon, [n]))
            }
        }
        return Array(out.prefix(limite))
    }

    // MARK: Filtros

    public static func pasa(_ f: FilaBase, filtro: FiltroBase, coleccion c: ColeccionBase, hoy: LocalDate) -> Bool {
        let col = c.columna(filtro.clave)
        let texto: String = {
            if let col { return f.textoCelda(col, hoy: hoy) }
            return f.texto(filtro.clave) ?? ""
        }()
        let vacio = texto.trimmingCharacters(in: .whitespaces).isEmpty || texto == "—"
        switch filtro.condicion {
        case .estaVacia: return vacio
        case .noEstaVacia: return !vacio
        case .pideAtencion: return col.flatMap { f.calculado($0)?.aviso } ?? false
        case .contiene:
            let t = TextFolding.fold(texto)
            return filtro.valores.contains { t.contains(TextFolding.fold($0)) }
        case .enlazaCon:
            let nombres = col.map { f.enlaces($0).map { TextFolding.fold($0.texto) } } ?? []
            let rutas = col.map { f.enlaces($0).compactMap { $0.ruta?.raw } } ?? []
            return filtro.valores.contains { v in nombres.contains(TextFolding.fold(v)) || rutas.contains(v) }
        case .es, .noEs:
            let vs: [String]
            if let col, col.tipo == .opcion || col.tipo == .opciones || col.tipo == .persona {
                vs = f.valoresOpcion(col)
            } else if let col, col.tipo == .relacion {
                vs = f.enlaces(col).map(\.texto)
            } else if let col, col.tipo == .fecha {
                vs = f.fecha(col).map { [$0.description] } ?? []
            } else {
                vs = [texto]
            }
            let plegados = Set(vs.map(TextFolding.fold))
            let hay = filtro.valores.contains { v in
                let objetivo = v == FiltroBase.hoy ? hoy.description : v
                return plegados.contains(TextFolding.fold(objetivo))
            }
            return filtro.condicion == .es ? hay : !hay
        case .antesDe, .despuesDe:
            guard let d = col.flatMap({ f.fecha($0) }) ?? f.fecha(filtro.clave),
                  let v = filtro.valores.first,
                  let limite = v == FiltroBase.hoy ? hoy : (v == FiltroBase.finDeMes ? finDeMes(hoy).adding(days: 1)
                                                                                     : LocalDate(parsing: v)) else { return false }
            return filtro.condicion == .antesDe ? d < limite : d > limite
        }
    }

    /// Último día del mes de `hoy`.
    static func finDeMes(_ hoy: LocalDate) -> LocalDate {
        var d = hoy
        while d.adding(days: 1).month == hoy.month { d = d.adding(days: 1) }
        return d
    }

    // MARK: Orden

    /// Nivel de urgencia (menor = antes) y fecha para desempatar (§2.2: pide tu decisión → vencido → vence
    /// hoy o quieto → falta un dato → por fecha; lo cerrado al final).
    public static func urgencia(_ f: FilaBase, coleccion c: ColeccionBase, hoy: LocalDate) -> (Int, LocalDate?) {
        if !abierta(f, c) { return (9, nil) }
        let tipoDecision = TextFolding.fold(f.texto("tipo") ?? "") == "decision"
        let estado = TextFolding.fold(f.texto("estado") ?? "")
        if tipoDecision || estado.hasPrefix("pendiente de tu ok") || estado == "en revision" && f.tipo == .task { return (0, nil) }
        let limite = ["vence", "plazo", "valida_hasta"].compactMap { f.fecha($0) }.min()
        let siguiente = f.fecha("siguiente_fecha") ?? f.fecha("planificada") ?? f.fecha("proxima_sesion") ?? f.fecha("fecha")
        let fecha = [limite, siguiente].compactMap { $0 }.min()
        if let l = limite, l < hoy { return (1, l) }
        if let s = f.fecha("siguiente_fecha"), s < hoy { return (1, s) }
        let quieta = f.calculados.values.contains { $0.aviso }
        if limite == hoy || siguiente == hoy || quieta { return (2, fecha) }
        if c.columna("siguiente_paso") != nil, f.texto("siguiente_paso") == nil { return (3, fecha) }
        if fecha != nil { return (4, fecha) }
        return (5, nil)
    }

    public static func ordenar(_ filas: [FilaBase], por orden: [OrdenBase], coleccion c: ColeccionBase, hoy: LocalDate) -> [FilaBase] {
        let criterios = orden.isEmpty ? [OrdenBase.urgente] : orden
        // Claves precalculadas: ordenar miles de filas sin recalcular en cada comparación.
        let claves: [[ClaveOrden]] = filas.map { f in criterios.map { clave(f, $0.clave, coleccion: c, hoy: hoy) } }
        let indices = filas.indices.sorted { a, b in
            for (k, cr) in criterios.enumerated() {
                let x = claves[a][k], y = claves[b][k]
                if x == y { continue }
                // Lo vacío siempre al final, sea cual sea el sentido.
                if x.vacio != y.vacio { return !x.vacio }
                return cr.ascendente ? x < y : y < x
            }
            return filas[a].titulo.localizedStandardCompare(filas[b].titulo) == .orderedAscending
        }
        return indices.map { filas[$0] }
    }

    /// Clave comparable de una fila para una columna.
    struct ClaveOrden: Comparable {
        var vacio: Bool
        var nivel: Int = 0
        var numero: Double = 0
        var texto: String = ""

        static func < (a: ClaveOrden, b: ClaveOrden) -> Bool {
            if a.nivel != b.nivel { return a.nivel < b.nivel }
            if a.numero != b.numero { return a.numero < b.numero }
            return a.texto.localizedStandardCompare(b.texto) == .orderedAscending
        }
    }

    static func clave(_ f: FilaBase, _ clave: String, coleccion c: ColeccionBase, hoy: LocalDate) -> ClaveOrden {
        if clave == OrdenBase.urgente.clave {
            let (nivel, fecha) = urgencia(f, coleccion: c, hoy: hoy)
            return ClaveOrden(vacio: false, nivel: nivel, numero: fecha.map { Double($0.year * 10_000 + $0.month * 100 + $0.day) } ?? 99_999_999)
        }
        guard let col = c.columna(clave) else {
            let t = f.texto(clave) ?? ""
            return ClaveOrden(vacio: t.isEmpty, texto: t)
        }
        switch col.tipo {
        case .dinero, .porcentaje, .numero, .calculada:
            if let n = f.numero(col) { return ClaveOrden(vacio: false, numero: n) }
            let t = f.textoCelda(col, hoy: hoy)
            return ClaveOrden(vacio: t.isEmpty || t == "—", texto: t)
        case .fecha:
            guard let d = f.fecha(col) else { return ClaveOrden(vacio: true) }
            return ClaveOrden(vacio: false, numero: Double(d.year * 10_000 + d.month * 100 + d.day))
        case .opcion:
            let v = f.valoresOpcion(col).first ?? ""
            let i = col.opciones.firstIndex { TextFolding.fold($0) == TextFolding.fold(v) } ?? col.opciones.count
            return ClaveOrden(vacio: v.isEmpty, numero: Double(i), texto: v)
        default:
            let t = f.textoCelda(col, hoy: hoy)
            return ClaveOrden(vacio: t.isEmpty, texto: t)
        }
    }

    // MARK: Grupos

    /// Agrupa por una propiedad: opción (en su orden), relación, persona, área o fecha (por mes). Lo que no
    /// tiene valor va al final, en «Sin …». Cada grupo lleva su subtotal de la primera columna de dinero.
    public static func agrupar(_ filas: [FilaBase], por clave: String, coleccion c: ColeccionBase, hoy: LocalDate,
                               incluirVacios: Bool = false) -> [GrupoFilas] {
        let col = c.columna(clave)
        var orden: [String] = []
        var titulos: [String: String] = [:]
        var porGrupo: [String: [FilaBase]] = [:]
        let sinValor = "\u{1F}sin"
        for f in filas {
            for (id, titulo) in gruposDe(f, col: col, clave: clave, hoy: hoy) {
                let k = id.isEmpty ? sinValor : id
                if porGrupo[k] == nil { orden.append(k); titulos[k] = id.isEmpty ? "Sin \((col?.etiqueta ?? clave).lowercased())" : titulo }
                porGrupo[k, default: []].append(f)
            }
        }
        if incluirVacios, let col, col.tipo == .opcion {
            for o in col.opciones where porGrupo[o] == nil && !orden.contains(where: { TextFolding.fold($0) == TextFolding.fold(o) }) {
                orden.append(o); titulos[o] = FormatoBase.opcionVisible(o); porGrupo[o] = []
            }
        }
        // Orden de los grupos: el del diccionario en las opciones, por fecha en las fechas y alfabético en el resto.
        orden.sort { a, b in
            if a == sinValor { return false }
            if b == sinValor { return true }
            if let col, col.tipo == .opcion || col.tipo == .opciones {
                let ia = col.opciones.firstIndex { TextFolding.fold($0) == TextFolding.fold(a) } ?? Int.max
                let ib = col.opciones.firstIndex { TextFolding.fold($0) == TextFolding.fold(b) } ?? Int.max
                if ia != ib { return ia < ib }
            }
            if col?.tipo == .fecha { return a < b }
            if clave == ColumnaBase.claveArea {
                let ia = AreaCode.allCases.firstIndex { $0.nombre == a } ?? Int.max
                let ib = AreaCode.allCases.firstIndex { $0.nombre == b } ?? Int.max
                return ia < ib
            }
            return (titulos[a] ?? a).localizedStandardCompare(titulos[b] ?? b) == .orderedAscending
        }
        let dinero = c.columnaDinero
        return orden.map { k in
            let fs = porGrupo[k] ?? []
            let suma = dinero.map { d in fs.compactMap { $0.numero(d) }.reduce(0, +) }
            return GrupoFilas(id: k, titulo: titulos[k] ?? k, filas: fs, suma: suma)
        }
    }

    /// Grupo (id y título) de una fila; una fila con varios valores sale en cada uno.
    static func gruposDe(_ f: FilaBase, col: ColumnaBase?, clave: String, hoy: LocalDate) -> [(String, String)] {
        guard let col else {
            let t = f.texto(clave) ?? ""
            return [(t, t)]
        }
        switch col.tipo {
        case .opcion, .opciones:
            let vs = f.valoresOpcion(col)
            if vs.isEmpty { return [("", "")] }
            return vs.map { v in
                let canonico = col.opciones.first { TextFolding.fold($0) == TextFolding.fold(v) } ?? v
                return (canonico, FormatoBase.opcionVisible(canonico))
            }
        case .relacion:
            let e = f.enlaces(col)
            if e.isEmpty { return [("", "")] }
            return e.map { ($0.ruta?.raw ?? $0.texto, $0.texto) }
        case .persona:
            let v = f.texto(col.clave) ?? ""
            return [(v, FormatoBase.persona(v))]
        case .fecha:
            guard let d = f.fecha(col) else { return [("", "")] }
            return [(String(format: "%04d-%02d", d.year, d.month), FormatoBase.mes(d.year, d.month).capitalizedFirst)]
        default:
            let t = f.textoCelda(col, hoy: hoy)
            return [(t, t)]
        }
    }
}

extension String {
    /// Primera letra en mayúscula («octubre de 2026» → «Octubre de 2026»).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
