import Foundation

/// Lo que dice la nota índice de una colección (SISTEMAS §1.4): vista por defecto, agrupación, pestañas y
/// la frase de su primer párrafo.
public struct NotaIndiceBase: Sendable, Hashable {
    public let ruta: VaultPath
    public let vista: TipoVista?
    public let agruparPor: String?
    public let pestanasPor: String?
    public let frase: String?

    public init(ruta: VaultPath, vista: TipoVista?, agruparPor: String?, pestanasPor: String?, frase: String?) {
        self.ruta = ruta; self.vista = vista; self.agruparPor = agruparPor; self.pestanasPor = pestanasPor; self.frase = frase
    }

    /// Primer párrafo tras el título (`# Oportunidades`). Si lo primero tras el título es una lista, una tabla, una
    /// cita, un bloque de código (una consulta), un comentario o HTML, la nota no tiene frase: nada de eso es una
    /// descripción.
    public static func frase(cuerpo: String) -> String? {
        let lineas = cuerpo.components(separatedBy: .newlines)
        let t = primerParrafo(lineas, desde: 0).parrafo.map { lineas[$0].trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        return t.isEmpty ? nil : LinkParser.plainText(t)
    }

    /// «Editar descripción» (M2-Bases): el texto entero de la nota índice con su frase (el primer párrafo tras
    /// el título, el mismo que lee `frase(cuerpo:)`) cambiada por `nueva`, en una sola línea. Todo lo demás
    /// queda igual, byte a byte (propiedades, título, secciones, listas, consultas, finales de línea). Si la nota
    /// no tiene párrafo (o lo primero es una lista o un bloque), la frase va justo después del título.
    /// `nil` si no hay nada que cambiar.
    public static func cambiandoFrase(_ texto: String, por nueva: String) -> String? {
        let frase = nueva.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !frase.isEmpty else { return nil }
        var lineas = texto.components(separatedBy: "\n")
        let retorno = texto.contains("\r\n") ? "\r" : ""
        func limpia(_ i: Int) -> String { lineas[i].trimmingCharacters(in: .whitespacesAndNewlines) }
        // El cuerpo empieza tras las propiedades (`---` … `---`).
        var inicio = 0
        if !lineas.isEmpty, limpia(0) == "---",
           let fin = lineas.indices.dropFirst().first(where: { ["---", "..."].contains(limpia($0)) }) {
            inicio = fin + 1
        }
        let (titulo, parrafo) = primerParrafo(lineas, desde: inicio)
        if let primera = parrafo.first, let ultima = parrafo.last {
            let actual = parrafo.map(limpia).joined(separator: " ")
            guard actual != frase else { return nil }
            lineas.replaceSubrange(primera...ultima, with: [frase + retorno])
        } else if let titulo {
            lineas.insert(contentsOf: [retorno, frase + retorno], at: titulo + 1)
        } else {
            lineas.insert(contentsOf: [frase + retorno, retorno], at: inicio)
        }
        return lineas.joined(separator: "\n")
    }

    /// Dónde está el título y qué líneas forman el primer párrafo de texto tras él (vacío si lo primero tras el
    /// título no es un párrafo). Antes del título se saltan los bloques enteros (también los de código).
    private static func primerParrafo(_ lineas: [String], desde inicio: Int) -> (titulo: Int?, parrafo: [Int]) {
        var titulo: Int?
        var parrafo: [Int] = []
        var cerca: String?  // dentro de un bloque cercado (``` o ~~~) antes del título
        for i in lineas.indices where i >= inicio {
            let l = lineas[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if let c = cerca {
                if l.hasPrefix(c) { cerca = nil }
                continue
            }
            if l.hasPrefix("# ") {
                if !parrafo.isEmpty { break }
                titulo = i
                continue
            }
            if l.isEmpty || l.hasPrefix("![[") {
                if !parrafo.isEmpty { break }
                continue
            }
            if esBloque(l) {
                if !parrafo.isEmpty { break }
                // Tras el título, lo primero manda: si es un bloque, la nota no tiene frase.
                if titulo != nil { break }
                if l.hasPrefix("```") || l.hasPrefix("~~~") { cerca = String(l.prefix(3)) }
                continue
            }
            if titulo == nil, parrafo.isEmpty, l.hasPrefix("tls_") { continue }
            parrafo.append(i)
        }
        return (titulo, parrafo)
    }

    /// Una línea que empieza algo que no es un párrafo: título, cita, tabla, raya, lista, casilla, bloque de
    /// código, comentario (`%%`), HTML o fórmula.
    private static func esBloque(_ l: String) -> Bool {
        if ["#", ">", "|", "---", "***", "___", "```", "~~~", "%%", "<", "$$"].contains(where: { l.hasPrefix($0) }) {
            return true
        }
        if ["- ", "* ", "+ "].contains(where: { l.hasPrefix($0) }) || ["-", "*", "+"].contains(l) { return true }
        return l.range(of: #"^[0-9]{1,9}[.)](\s|$)"#, options: .regularExpression) != nil
    }
}

/// Una de las tres cifras de la cabecera de una base (§4.3).
public struct CifraBase: Sendable, Hashable, Identifiable {
    public var id: String { etiqueta }
    public let etiqueta: String
    public let valor: String
    public init(_ etiqueta: String, _ valor: String) { self.etiqueta = etiqueta; self.valor = valor }
}

/// Lo urgente de una base en una línea («2 quietas», «1 vence hoy»).
public struct AvisoBase: Sendable, Hashable {
    public enum Nivel: String, Sendable, Hashable { case info, atencion, mal }
    public let texto: String
    public let nivel: Nivel
    public init(_ texto: String, _ nivel: Nivel) { self.texto = texto; self.nivel = nivel }
}

/// Todo lo que enseña una base: sus filas (sin lo privado) y lo que se dice de ella.
public struct DatosBase: Sendable {
    public let coleccion: ColeccionBase
    /// Filas visibles: nunca lo privado.
    public let filas: [FilaBase]
    public let indice: NotaIndiceBase?
    public let hoy: LocalDate
    /// Quien usa la app (para «Lo mío»).
    public let persona: String?
    /// «21 oct · Arquitectura Nexo SLP».
    public let ultimoCambio: String?
    public let urgente: AvisoBase?
    public let abiertas: Int
    public let cifras: [CifraBase]
    /// «Sale de 14 fichas en 2 · Ventas/Oportunidades».
    public let pie: String
    public let apagada: Bool
    /// CSV de los que salen filas.
    public let ficherosCSV: [VaultPath]

    public init(coleccion: ColeccionBase, filas: [FilaBase], indice: NotaIndiceBase?, hoy: LocalDate, persona: String?,
                ultimoCambio: String?, urgente: AvisoBase?, abiertas: Int, cifras: [CifraBase], pie: String,
                apagada: Bool, ficherosCSV: [VaultPath]) {
        self.coleccion = coleccion; self.filas = filas; self.indice = indice; self.hoy = hoy; self.persona = persona
        self.ultimoCambio = ultimoCambio; self.urgente = urgente; self.abiertas = abiertas; self.cifras = cifras
        self.pie = pie; self.apagada = apagada; self.ficherosCSV = ficherosCSV
    }

    /// La vista que dice la nota índice o, si no, la de serie (§4.6).
    public var vistaPorDefecto: TipoVista { indice?.vista ?? coleccion.vista }
    public var agruparPor: String? { indice?.agruparPor ?? coleccion.agruparPor }
    public var frase: String { indice?.frase ?? coleccion.frase }

    /// Pestañas de la base, sin «Todas» (que va siempre la primera): las de serie o, si la nota índice
    /// dice otra propiedad, una por valor en el orden del diccionario; lo archivado al final.
    public var pestanas: [PestanaBase] {
        let porNota = indice?.pestanasPor
        if let clave = porNota ?? coleccion.pestanasPor,
           !coleccion.pestanas.contains(where: { $0.filtro.clave == clave }) {
            return Self.pestanas(por: clave, coleccion: coleccion, filas: filas)
        }
        return coleccion.pestanas
    }

    /// Una pestaña por cada valor de la propiedad (los del diccionario primero, en su orden).
    public static func pestanas(por clave: String, coleccion: ColeccionBase, filas: [FilaBase]) -> [PestanaBase] {
        let col = coleccion.columna(clave)
        var valores = col?.opciones ?? []
        for f in filas {
            let vs = col.map { f.valoresOpcion($0) } ?? (f.texto(clave).map { [$0] } ?? [])
            for v in vs where !valores.contains(where: { TextFolding.fold($0) == TextFolding.fold(v) }) { valores.append(v) }
        }
        let archivados = Set(["archivado", "archivada", "retirado", "retirada"])
        let normales = valores.filter { !archivados.contains(TextFolding.fold($0)) }
        let alFinal = valores.filter { archivados.contains(TextFolding.fold($0)) }
        return normales.map { PestanaBase(FormatoBase.opcionVisible($0), .valores(clave, [$0]), id: $0) }
            + alFinal.map { PestanaBase(FormatoBase.opcionVisible($0), .valores(clave, [$0]), archivada: true, id: $0) }
    }
}

public extension FiltroPestana {
    /// Propiedad que mira (si mira una).
    var clave: String? {
        switch self {
        case .valores(let c, _), .noValores(let c, _), .hoy(let c), .semana(let c), .vencidas(let c): c
        case .mio: "responsable"
        }
    }
}

/// Lee las bases del índice (y los CSV de Finanzas) y calcula lo calculado. No escribe nada; lo privado
/// nunca sale en las filas. Se usa fuera del hilo principal.
public final class LectorBases: @unchecked Sendable {
    let service: VaultService
    public let ajustes: AjustesBases
    public let persona: String?
    private let lock = NSLock()
    private var fichasPorTipo: [NoteKind: [FichaIndexada]] = [:]
    private var csv: [VaultPath: (cabecera: [String], filas: [[String: String]])] = [:]
    private var notasIndice: [FichaIndexada]?
    private var titulos: [VaultPath: String] = [:]

    public init(service: VaultService, ajustes: AjustesBases, persona: String?) {
        self.service = service
        self.ajustes = ajustes
        self.persona = persona
    }

    public var hoy: LocalDate { ajustes.hoy }

    // MARK: Leer

    /// Las filas y el resumen de una base.
    public func leer(_ c: ColeccionBase) -> DatosBase {
        precargar(tipos: Set(c.tipos).union(tiposParaCalcular(c)))
        var filas: [FilaBase] = []
        var csvUsados: [VaultPath] = []
        for fuente in c.fuentes {
            switch fuente {
            case .fichas(let tipos):
                for t in tipos {
                    for f in fichas(t) where !f.resumen.privado { filas.append(fila(de: f)) }
                }
            case .filasCSV(let carpeta, let nombre, let clave, let soloSi):
                let dir = service.layout.expand(carpeta)
                for ruta in service.ficherosCSV(llamados: nombre, bajo: dir) where !service.layout.isPrivate(ruta) {
                    csvUsados.append(ruta)
                    filas += filasCSV(ruta, clave: clave, soloSi: soloSi, coleccion: c)
                }
            }
        }
        calcular(&filas, coleccion: c)
        if c.tipos.contains(.opportunity) { calcularGanada(&filas) }
        return resumir(c, filas: filas, csv: csvUsados)
    }

    /// Todas las bases de una vez (una consulta por tipo, compartida). Para «Todas las bases» y la barra.
    public func leerTodas(_ colecciones: [ColeccionBase] = CatalogoBases.deSerie) -> [String: DatosBase] {
        precargar(tipos: Set(colecciones.flatMap { $0.tipos + tiposParaCalcular($0) }))
        var out: [String: DatosBase] = [:]
        for c in colecciones { out[c.id] = leer(c) }
        return out
    }

    // MARK: Carga

    private func precargar(tipos: Set<NoteKind>) {
        let faltan = lock.withLock { tipos.subtracting(fichasPorTipo.keys) }
        guard !faltan.isEmpty else { return }
        let leidas = service.fichas(deTipos: faltan)
        lock.withLock {
            for t in faltan { fichasPorTipo[t] = [] }
            for f in leidas { fichasPorTipo[f.resumen.kind, default: []].append(f) }
        }
    }

    func fichas(_ tipo: NoteKind) -> [FichaIndexada] {
        precargar(tipos: [tipo])
        return lock.withLock { fichasPorTipo[tipo] ?? [] }
    }

    private func tablaCSV(_ ruta: VaultPath) -> (cabecera: [String], filas: [[String: String]]) {
        if let t = lock.withLock({ csv[ruta] }) { return t }
        var leida: (cabecera: [String], filas: [[String: String]]) = ([], [])
        if case .csv(let cabecera, let filas, _) = service.read(ruta) {
            leida = (cabecera, filas.map { celdas in
                var d: [String: String] = [:]
                for (i, h) in cabecera.enumerated() { d[h] = i < celdas.count ? celdas[i] : "" }
                return d
            })
        }
        lock.withLock { csv[ruta] = leida }
        return leida
    }

    /// Notas índice de la carpeta (`tls_type: index`).
    public func notaIndice(de c: ColeccionBase) -> NotaIndiceBase? {
        let indices: [FichaIndexada] = lock.withLock { notasIndice } ?? {
            let l = service.fichas(deTipos: [.index])
            lock.withLock { notasIndice = l }
            return l
        }()
        let esperada = c.notaIndice.map { TextFolding.pathKey(service.layout.expand($0).raw) }
        let tipo = c.tipos.first?.rawValue
        let candidata = indices.first { esperada != nil && TextFolding.pathKey($0.ruta.raw) == esperada }
            ?? indices.first { f in
                guard let tipo, case .text(let col)? = f.propiedades["coleccion"] else { return false }
                return col.trimmingCharacters(in: .whitespaces) == tipo
            }
        guard let n = candidata, !n.resumen.privado else { return nil }
        var frase: String?
        if case .markdown(_, _, let cuerpo, _, _) = service.read(n.ruta) { frase = NotaIndiceBase.frase(cuerpo: cuerpo) }
        func texto(_ k: String) -> String? {
            guard let v = n.propiedades[k], !v.estaVacio else { return nil }
            return v.displayText
        }
        return NotaIndiceBase(ruta: n.ruta, vista: texto("vista").flatMap(TipoVista.init(leyendo:)),
                              agruparPor: texto("agrupar_por"), pestanasPor: texto("pestanas_por"), frase: frase)
    }

    func titulo(de ruta: VaultPath) -> String {
        if let t = lock.withLock({ titulos[ruta] }) { return t }
        let t = service.summary(of: ruta)?.title ?? ruta.stem
        lock.withLock { titulos[ruta] = t }
        return t
    }

    // MARK: Filas

    func fila(de f: FichaIndexada) -> FilaBase {
        var enlaces: [String: [EnlaceFila]] = [:]
        for (k, v) in f.propiedades {
            let textos: [String]
            switch v {
            case .text(let s) where s.contains("[["): textos = [s]
            case .list(let l) where l.contains(where: { $0.contains("[[") }): textos = l
            default: continue
            }
            enlaces[k] = textos.flatMap { t in
                LinkParser.links(in: t).filter { $0.style == .wiki }.map { link in
                    let destino = f.destino(de: link)
                    let texto = link.label ?? destino.map(titulo(de:)) ?? (link.target.split(separator: "/").last.map(String.init) ?? link.target)
                    return EnlaceFila(texto: texto, ruta: destino)
                }
            }
        }
        return FilaBase(id: f.ruta.raw, origen: .ficha(f.ruta), titulo: f.resumen.title, tipo: f.resumen.kind,
                        area: f.resumen.area, valores: f.propiedades, enlaces: enlaces, modificada: f.resumen.modified,
                        privado: f.resumen.privado, claves: Array(f.propiedades.keys))
    }

    func filasCSV(_ ruta: VaultPath, clave: String, soloSi: [String: String], coleccion: ColeccionBase) -> [FilaBase] {
        let tabla = tablaCSV(ruta)
        let modificada = service.summary(of: ruta)?.modified
        let area = service.layout.area(of: ruta)
        var out: [FilaBase] = []
        for celdas in tabla.filas {
            guard let id = celdas[clave], !id.isEmpty else { continue }
            if soloSi.contains(where: { TextFolding.fold(celdas[$0.key] ?? "") != TextFolding.fold($0.value) }) { continue }
            var valores: [String: PropertyValue] = [:]
            for (k, v) in celdas where !v.isEmpty { valores[k] = .text(v) }
            let titulo = ["concepto", "tercero", "documento_id", "numero_documento"].lazy
                .compactMap { celdas[$0].flatMap { $0.isEmpty ? nil : $0 } }.first ?? id
            var documento: VaultPath?
            if let d = celdas["documento"], !d.isEmpty, let a = area {
                documento = d.hasPrefix(service.layout.areaFolder(a).raw) ? VaultPath(d) : service.layout.areaFolder(a).appending(d)
            }
            out.append(FilaBase(id: "\(ruta.raw)#\(id)", origen: .filaCSV(ruta, columnaClave: clave, valorClave: id),
                                titulo: titulo, tipo: .csv, area: area, valores: valores, modificada: modificada,
                                privado: false, claves: tabla.cabecera, documento: documento))
        }
        return out
    }

    // MARK: Lo calculado

    private func tiposParaCalcular(_ c: ColeccionBase) -> [NoteKind] {
        (c.tipos.contains(.opportunity) ? [.invoice, .receipt] : []) + c.columnas.compactMap(\.calculo).flatMap { calc -> [NoteKind] in
            switch calc {
            case .ultimoContacto: [.meeting, .conversation]
            case .proyectosActivos: [.project]
            case .pendienteDeCobro, .ingresosDelAno, .cobradoProyecto: [.invoice]
            case .clientesActivos: [.opportunity]
            case .sistemasDelRol: [.system]
            default: []
            }
        }
    }

    /// Fichas de esos tipos que enlazan (en sus propiedades) a cada ruta.
    private func enlazanA(_ tipos: [NoteKind]) -> [VaultPath: [FichaIndexada]] {
        var out: [VaultPath: [FichaIndexada]] = [:]
        for t in tipos {
            for f in fichas(t) where !f.resumen.privado {
                for destino in Set(f.enlaces.values) { out[destino, default: []].append(f) }
            }
        }
        return out
    }

    /// Cobros de `pagos.csv` por número de factura: confirmados y por confirmar (con la fecha del primero).
    private func cobrosPorFactura() -> (confirmado: [String: Double], pendiente: [String: Double], fechaPendiente: [String: String]) {
        var conf: [String: Double] = [:], pend: [String: Double] = [:], fechas: [String: String] = [:]
        let dir = service.layout.expand("{finanzas}/Registros")
        for ruta in service.ficherosCSV(llamados: "pagos.csv", bajo: dir) where !service.layout.isPrivate(ruta) {
            for f in tablaCSV(ruta).filas where TextFolding.fold(f["direccion"] ?? "") == "cobro" {
                guard let doc = f["documento_id"], !doc.isEmpty, let n = FormatoBase.numero(f["importe"] ?? "") else { continue }
                let k = TextFolding.fold(doc)
                if TextFolding.fold(f["verificacion"] ?? "") == "confirmado" {
                    conf[k, default: 0] += n
                } else {
                    pend[k, default: 0] += n
                    if fechas[k] == nil, let d = LocalDate(parsing: f["fecha"] ?? "") {
                        fechas[k] = "\(d.day) \(FormatoBase.meses[d.month - 1])"
                    }
                }
            }
        }
        return (conf, pend, fechas)
    }

    /// Motivo de cada oportunidad que no puede pasar a Ganada (`ReglaGanada`).
    private func calcularGanada(_ filas: inout [FilaBase]) {
        let enlazan = enlazanA([.invoice])
        // Recibos que apuntan a cada factura (el «Confirmar el cobro» de F1): cuentan si los confirmó una persona.
        let recibos = enlazanA([.receipt]).mapValues { $0.filter { $0.resumen.kind == .receipt } }
        let cobros = cobrosPorFactura()
        var pendientes: [String: (Double, String)] = [:]
        for (k, v) in cobros.pendiente { pendientes[k] = (v, cobros.fechaPendiente[k] ?? "") }
        for i in filas.indices where filas[i].tipo == .opportunity {
            let facturas = (enlazan[filas[i].ruta] ?? []).filter { $0.resumen.kind == .invoice }
            let contacto = filas[i].enlaces["contacto"]?.first?.texto
            let motivo = ReglaGanada.calcular(facturas: facturas, confirmados: cobros.confirmado, recibos: recibos,
                                              pendientes: pendientes, contacto: contacto)
            filas[i].calculados[ReglaGanada.clave] = ValorCalculado(motivo ?? "", aviso: motivo != nil)
        }
    }

    private func texto(_ f: FichaIndexada, _ k: String) -> String? {
        guard let v = f.propiedades[k], !v.estaVacio else { return nil }
        return FormatoBase.textoVisible(v)
    }

    private func estado(_ f: FichaIndexada) -> String { texto(f, "estado").map(TextFolding.fold) ?? "" }

    private func calcular(_ filas: inout [FilaBase], coleccion c: ColeccionBase) {
        let calcs = c.columnas.filter { $0.calculo != nil }
        guard !calcs.isEmpty else { return }
        let necesitaCobros = calcs.contains { [.cobradoFactura, .pendienteDeCobro, .cobradoProyecto].contains($0.calculo) }
        let cobros: (confirmado: [String: Double], pendiente: [String: Double], fechaPendiente: [String: String]) =
            necesitaCobros ? cobrosPorFactura() : (confirmado: [:], pendiente: [:], fechaPendiente: [:])
        let necesitaEnlaces = calcs.contains { [.ultimoContacto, .proyectosActivos, .pendienteDeCobro, .clientesActivos,
                                                .ingresosDelAno, .cobradoProyecto, .sistemasDelRol].contains($0.calculo) }
        let enlazan = necesitaEnlaces ? enlazanA(Array(Set(calcs.compactMap(\.calculo).flatMap { calc -> [NoteKind] in
            switch calc {
            case .ultimoContacto: [.meeting, .conversation]
            case .proyectosActivos: [.project]
            case .pendienteDeCobro, .ingresosDelAno, .cobradoProyecto: [.invoice]
            case .clientesActivos: [.opportunity]
            case .sistemasDelRol: [.system]
            default: []
            }
        }))) : [:]
        func total(_ factura: FichaIndexada) -> Double { texto(factura, "total").flatMap(FormatoBase.numero) ?? 0 }
        func cobrado(_ factura: FichaIndexada) -> Double {
            guard let n = texto(factura, "numero") else { return 0 }
            return cobros.confirmado[TextFolding.fold(n)] ?? 0
        }
        for i in filas.indices {
            let ruta = filas[i].ruta
            for col in calcs {
                guard let calc = col.calculo else { continue }
                let v: ValorCalculado
                switch calc {
                case .ponderado:
                    if let valor = filas[i].texto("valor").flatMap(FormatoBase.numero),
                       let p = filas[i].texto("probabilidad").flatMap(FormatoBase.numero) {
                        let n = valor * p / 100
                        v = ValorCalculado(FormatoBase.euros(n, redondo: true), numero: n)
                    } else { v = ValorCalculado("—") }
                case .diasEnEtapa:
                    v = diasEnEtapa(filas[i], coleccion: c)
                case .tipoDeFicha:
                    v = ValorCalculado(filas[i].tipo == .quote ? "Presupuesto" : filas[i].tipo == .agreement ? "Contrato" : "Propuesta")
                case .ultimoContacto:
                    let fechas = (enlazan[ruta] ?? []).compactMap { texto($0, "fecha").flatMap { LocalDate(parsing: $0) } }
                        .filter { $0 <= hoy }
                    if let d = fechas.max() {
                        v = ValorCalculado(FormatoBase.fecha(d, hoy: hoy), numero: Double(dias(desde: d, hasta: hoy)))
                    } else { v = ValorCalculado("—") }
                case .proyectosActivos:
                    let n = (enlazan[ruta] ?? []).filter { $0.resumen.kind == .project && !["cerrado", "archivado"].contains(estado($0)) }.count
                    v = ValorCalculado(String(n), numero: Double(n))
                case .pendienteDeCobro:
                    let facturas = (enlazan[ruta] ?? []).filter { $0.resumen.kind == .invoice && ["emitida", "enviada"].contains(estado($0)) }
                    let n = facturas.reduce(0) { $0 + max(0, total($1) - cobrado($1)) }
                    v = ValorCalculado(n == 0 ? "0 €" : FormatoBase.euros(n), numero: n, aviso: n > 0)
                case .clientesActivos:
                    let ops = (enlazan[ruta] ?? []).filter { $0.resumen.kind == .opportunity && ["aceptada", "ganada"].contains(estado($0)) }
                    let clientes = Set(ops.map { o in texto(o, "empresa") ?? texto(o, "contacto") ?? o.ruta.raw })
                    v = ValorCalculado(String(clientes.count), numero: Double(clientes.count))
                case .ingresosDelAno:
                    let n = (enlazan[ruta] ?? []).filter { f in
                        f.resumen.kind == .invoice && ["emitida", "enviada", "cobrada"].contains(estado(f))
                            && (texto(f, "fecha").flatMap { LocalDate(parsing: $0) }?.year == hoy.year)
                    }.reduce(0) { $0 + total($1) }
                    v = ValorCalculado(FormatoBase.euros(n, redondo: true), numero: n)
                case .cobradoFactura:
                    let numero = filas[i].texto("numero").map(TextFolding.fold) ?? ""
                    let conf = cobros.confirmado[numero] ?? 0
                    let pend = cobros.pendiente[numero] ?? 0
                    if conf > 0 {
                        v = ValorCalculado(FormatoBase.euros(conf), numero: conf)
                    } else if pend > 0 {
                        v = ValorCalculado("\(FormatoBase.euros(pend)) por confirmar", numero: 0, aviso: true)
                    } else {
                        let borrador = TextFolding.fold(filas[i].texto("estado") ?? "") == "borrador"
                        v = ValorCalculado(borrador ? "—" : "Sin cobrar", numero: 0)
                    }
                case .avanceProyecto:
                    if let h = filas[i].texto("sesiones_hechas").flatMap(FormatoBase.numero),
                       let t = filas[i].texto("sesiones_incluidas").flatMap(FormatoBase.numero), t > 0 {
                        v = ValorCalculado("\(FormatoBase.cifra(h)) de \(FormatoBase.cifra(t))", numero: h / t)
                    } else if let a = filas[i].texto("avance").flatMap(FormatoBase.numero) {
                        v = ValorCalculado("\(FormatoBase.cifra(a)) %", numero: a / 100)
                    } else { v = ValorCalculado("—") }
                case .cobradoProyecto:
                    let facturas = (enlazan[ruta] ?? []).filter { $0.resumen.kind == .invoice }
                    let cob = facturas.reduce(0) { $0 + cobrado($1) }
                    let t = facturas.reduce(0) { $0 + total($1) }
                    v = t > 0 ? ValorCalculado("\(FormatoBase.euros(cob, redondo: true)) de \(FormatoBase.euros(t, redondo: true))", numero: cob)
                        : ValorCalculado("—")
                case .sistemasDelRol:
                    let n = (enlazan[ruta] ?? []).filter { $0.resumen.kind == .system }.count
                    v = ValorCalculado(String(n), numero: Double(n))
                case .accionesPendientes, .pasosSinTi, .cifraObjetivo, .ritmoObjetivo:
                    v = ValorCalculado("—")
                }
                filas[i].calculados[col.clave] = v
            }
        }
    }

    /// Días en la etapa: desde la fecha de esa etapa (`aceptada: 2026-10-19`) o, si no, desde `creada`.
    func diasEnEtapa(_ f: FilaBase, coleccion c: ColeccionBase) -> ValorCalculado {
        let etapa = f.texto("estado") ?? ""
        let claveEtapa = TextFolding.fold(etapa).replacingOccurrences(of: " ", with: "_")
        let desde = f.fecha(claveEtapa) ?? f.fecha("creada")
        let cerrada = c.cerrados.contains { TextFolding.fold($0) == TextFolding.fold(etapa) }
        guard let desde else { return ValorCalculado("—") }
        if cerrada {
            return ValorCalculado("\(etapa) el \(desde.day) \(FormatoBase.meses[desde.month - 1])", numero: 10_000)
        }
        let n = dias(desde: desde, hasta: hoy)
        let quieta = n > 7
        let texto = n == 0 ? "Desde hoy" : (quieta ? "\(FormatoBase.cuenta(n, "día", "días")) quieta" : FormatoBase.cuenta(n, "día", "días"))
        return ValorCalculado(texto, numero: Double(n), aviso: quieta)
    }

    func dias(desde a: LocalDate, hasta b: LocalDate) -> Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.day], from: a.date(), to: b.date()).day ?? 0
    }

    // MARK: Resumen

    private func estaAbierta(_ f: FilaBase, _ c: ColeccionBase) -> Bool {
        guard let col = c.columnaEstado, let e = f.valor(col).map(FormatoBase.textoVisible) else { return true }
        return !c.cerrados.contains { TextFolding.fold($0) == TextFolding.fold(e) }
    }

    private func resumir(_ c: ColeccionBase, filas: [FilaBase], csv: [VaultPath]) -> DatosBase {
        let abiertas = filas.filter { estaAbierta($0, c) }
        var ultimo: String?
        if let f = filas.filter({ $0.modificada != nil }).max(by: { $0.modificada! < $1.modificada! }), let d = f.modificada {
            ultimo = "\(FormatoBase.fecha(d, hoy: hoy)) · \(f.titulo)"
        }
        let pie: String
        if !csv.isEmpty {
            let donde = csv.count == 1 ? csv[0].raw : service.layout.expand(c.hogar).raw
            let filasCSV = filas.filter(\.esFilaCSV).count
            let fichas = filas.count - filasCSV
            pie = "Sale de \(FormatoBase.cuenta(filasCSV, "fila", "filas")) de \(donde)"
                + (fichas > 0 ? " y \(FormatoBase.cuenta(fichas, "ficha", "fichas"))" : "")
        } else {
            let carpetas = Set(filas.compactMap { $0.ruta.parent?.raw })
            let donde = carpetas.count == 1 ? carpetas.first! : service.layout.expand(c.hogar).raw
            pie = "Sale de \(FormatoBase.cuenta(filas.count, "ficha", "fichas")) en \(donde)"
        }
        return DatosBase(coleccion: c, filas: filas, indice: notaIndice(de: c), hoy: hoy, persona: persona,
                         ultimoCambio: ultimo, urgente: urgente(c, filas: filas), abiertas: abiertas.count,
                         cifras: cifras(c, filas: filas, abiertas: abiertas), pie: pie,
                         apagada: ajustes.apagada(c), ficherosCSV: csv)
    }

    private func estadoDe(_ f: FilaBase) -> String { TextFolding.fold(f.texto("estado") ?? "") }

    func urgente(_ c: ColeccionBase, filas: [FilaBase]) -> AvisoBase? {
        func abierta(_ f: FilaBase) -> Bool { estaAbierta(f, c) }
        switch c.id {
        case "oportunidades":
            let n = filas.filter { abierta($0) && ($0.calculados["_dias"]?.aviso ?? false) }.count
            return n > 0 ? AvisoBase(FormatoBase.cuenta(n, "quieta", "quietas"), .atencion) : nil
        case "tareas", "incidencias":
            let clave = c.id == "tareas" ? "vence" : "plazo"
            let vencidas = filas.filter { abierta($0) && ($0.fecha(clave).map { $0 < hoy } ?? false) }.count
            if vencidas > 0 { return AvisoBase(FormatoBase.cuenta(vencidas, "vencida", "vencidas"), .mal) }
            let hoyN = filas.filter { abierta($0) && $0.fecha(clave) == hoy }.count
            return hoyN > 0 ? AvisoBase("\(hoyN) \(hoyN == 1 ? "vence" : "vencen") hoy", .atencion) : nil
        case "facturas":
            let vencidas = filas.filter { ["emitida", "enviada"].contains(estadoDe($0)) && ($0.fecha("vence").map { $0 < hoy } ?? false) }.count
            if vencidas > 0 { return AvisoBase(FormatoBase.cuenta(vencidas, "vencida", "vencidas"), .mal) }
            let borradores = filas.filter { estadoDe($0) == "borrador" }.count
            return borradores > 0 ? AvisoBase("\(borradores) en borrador", .info) : nil
        case "cobros":
            let n = filas.filter { f in f.texto("verificacion").map { TextFolding.fold($0) != "confirmado" } ?? false }.count
            return n > 0 ? AvisoBase("\(n) por confirmar", .info) : nil
        case "reuniones":
            let proximas = filas.compactMap { f -> LocalDate? in
                guard estadoDe(f) != "cancelada", estadoDe(f) != "hecha", let d = f.fecha("fecha"), d >= hoy else { return nil }
                return d
            }
            return proximas.min().map { AvisoBase("Próxima: \(FormatoBase.fechaConDia($0))", .info) }
        case "borradores":
            let n = filas.filter { estadoDe($0).hasPrefix("pendiente") }.count
            return n > 0 ? AvisoBase("\(n) \(n == 1 ? "espera" : "esperan") tu OK", .info) : nil
        case "movimientos":
            let n = filas.filter { f in !["conciliado", "ignorado"].contains(TextFolding.fold(f.texto("estado_conciliacion") ?? "")) }.count
            return n > 0 ? AvisoBase("\(n) sin conciliar", .atencion) : nil
        case "decisiones":
            let n = filas.filter { abierta($0) && ($0.fecha("revisar").map { $0 <= hoy } ?? false) }.count
            return n > 0 ? AvisoBase("\(n) por revisar", .atencion) : nil
        case "proyectos":
            let n = filas.filter { abierta($0) && $0.fecha("proxima_sesion") == hoy }.count
            return n > 0 ? AvisoBase(FormatoBase.cuenta(n, "sesión hoy", "sesiones hoy"), .atencion) : nil
        default:
            return nil
        }
    }

    func cifras(_ c: ColeccionBase, filas: [FilaBase], abiertas: [FilaBase]) -> [CifraBase] {
        func suma(_ fs: [FilaBase], _ clave: String) -> Double { fs.compactMap { $0.texto(clave).flatMap(FormatoBase.numero) }.reduce(0, +) }
        func cuenta(_ valor: String) -> Int { filas.filter { estadoDe($0) == TextFolding.fold(valor) }.count }
        switch c.id {
        case "oportunidades":
            let valor = suma(abiertas, "valor")
            let ponderado = abiertas.compactMap { $0.calculados["_ponderado"]?.numero }.reduce(0, +)
            let desde = hoy.adding(days: -90)
            func cerradaReciente(_ f: FilaBase, _ e: String) -> Bool {
                guard estadoDe(f) == e else { return false }
                let d = f.fecha(e) ?? f.fecha("cerrada") ?? f.modificada.map { LocalDate(date: $0) }
                return d.map { $0 >= desde } ?? true
            }
            let ganadas = filas.filter { cerradaReciente($0, "ganada") }.count
            let perdidas = filas.filter { cerradaReciente($0, "perdida") }.count
            return [CifraBase("Valor abierto", FormatoBase.euros(valor, redondo: true)),
                    CifraBase("Ponderado", FormatoBase.euros(ponderado, redondo: true)),
                    CifraBase("Ganadas sobre cerradas (90 días)", "\(ganadas) de \(ganadas + perdidas)")]
        case "contactos", "empresas":
            let fem = c.id == "empresas"
            let sigHoy = filas.filter { $0.fecha("siguiente_fecha") == hoy }.count
            return [CifraBase(fem ? "Activas" : "Activos", String(cuenta("Activo"))),
                    CifraBase(fem ? "Interesadas" : "Interesados", String(cuenta("Interesado"))),
                    CifraBase("Siguiente paso hoy", String(sigHoy))]
        case "facturas":
            let pendientes = filas.filter { ["emitida", "enviada"].contains(estadoDe($0)) }
            let pendiente = pendientes.reduce(0.0) { acc, f in
                let total = f.texto("total").flatMap(FormatoBase.numero) ?? 0
                return acc + max(0, total - (f.calculados["_cobrado"]?.numero ?? 0))
            }
            let cobradasAno = filas.filter { estadoDe($0) == "cobrada" && $0.fecha("fecha")?.year == hoy.year }.count
            return [CifraBase("Pendiente de cobro", FormatoBase.euros(pendiente)),
                    CifraBase("Borradores", String(cuenta("Borrador"))),
                    CifraBase("Cobradas este año", String(cobradasAno))]
        case "proyectos":
            let venceHoy = filas.filter { $0.fecha("proxima_sesion") == hoy }.count
            return [CifraBase("En curso", String(cuenta("En curso"))), CifraBase("Sin empezar", String(cuenta("Sin empezar"))),
                    CifraBase("Algo vence hoy", String(venceHoy))]
        case "tareas":
            let vencidas = abiertas.filter { $0.fecha("vence").map { $0 < hoy } ?? false }.count
            let hoyN = abiertas.filter { $0.fecha("planificada") == hoy || $0.fecha("vence") == hoy }.count
            return [CifraBase("Abiertas", String(abiertas.count)), CifraBase("Para hoy", String(hoyN)),
                    CifraBase("Vencidas", String(vencidas))]
        case "cobros":
            let importe = suma(filas.filter { $0.fecha("fecha")?.year == hoy.year }, "importe")
            let porConfirmar = filas.filter { f in f.texto("verificacion").map { TextFolding.fold($0) != "confirmado" } ?? false }.count
            return [CifraBase("Cobrado este año", FormatoBase.euros(importe, redondo: true)), CifraBase("Cobros", String(filas.count)),
                    CifraBase("Por confirmar", String(porConfirmar))]
        case "gastos":
            let delAno = filas.filter { $0.fecha("fecha_documento")?.year == hoy.year }
            return [CifraBase("Gastado este año", FormatoBase.euros(suma(delAno, "total_documento"), redondo: true)),
                    CifraBase("IVA soportado", FormatoBase.euros(suma(delAno, "iva"), redondo: true)),
                    CifraBase("Facturas recibidas", String(filas.count))]
        case "movimientos":
            let sinConciliar = filas.filter { !["conciliado", "ignorado"].contains(TextFolding.fold($0.texto("estado_conciliacion") ?? "")) }.count
            let entradas = suma(filas.filter { ($0.texto("importe").flatMap(FormatoBase.numero) ?? 0) > 0 }, "importe")
            return [CifraBase("Movimientos", String(filas.count)), CifraBase("Sin conciliar", String(sinConciliar)),
                    CifraBase("Entradas", FormatoBase.euros(entradas, redondo: true))]
        default:
            var out = [CifraBase("Fichas", String(filas.count))]
            if c.columnaEstado != nil, !c.cerrados.isEmpty { out.append(CifraBase(c.femenino ? "Abiertas" : "Abiertos", String(abiertas.count))) }
            let mes = filas.filter { f in f.modificada.map { LocalDate(date: $0) }.map { $0.year == hoy.year && $0.month == hoy.month } ?? false }.count
            out.append(CifraBase("Cambiadas este mes", String(mes)))
            return out
        }
    }
}

public extension DatosBase {
    /// La misma base con una propiedad de una fila cambiada (para ver el cambio al momento, sin esperar a
    /// que el índice lo relea).
    func cambiando(_ id: String, clave: String, valor: PropertyValue?) -> DatosBase {
        var filas = self.filas
        if let i = filas.firstIndex(where: { $0.id == id }) { filas[i].valores[clave] = valor }
        return DatosBase(coleccion: coleccion, filas: filas, indice: indice, hoy: hoy, persona: persona,
                         ultimoCambio: ultimoCambio, urgente: urgente, abiertas: abiertas, cifras: cifras, pie: pie,
                         apagada: apagada, ficherosCSV: ficherosCSV)
    }
}
