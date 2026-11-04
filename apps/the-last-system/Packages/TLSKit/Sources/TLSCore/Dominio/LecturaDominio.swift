import Foundation
import Yams

// Lectura del dominio (F2): oportunidades, proyectos, objetivos, servicios, facturas y cobros, sacados de una foto de
// la carpeta (`VaultSnapshot`). La usan las invariantes, las reglas, la bandeja de decisiones y el expediente.
// Nunca escribe. Lo privado se lee para no romper reglas, pero cada ficha dice si lo es y nada privado sale en
// listas, tarjetas ni avisos.

/// Una ficha del dominio tal como está escrita.
public struct FichaDominio: Sendable, Hashable, Identifiable {
    public var id: VaultPath { ruta }
    public let ruta: VaultPath
    public let tipo: NoteKind
    /// `nombre`, `titulo` o el título de la nota.
    public let nombre: String
    public let propiedades: Frontmatter
    public let privada: Bool

    public init(ruta: VaultPath, tipo: NoteKind, nombre: String, propiedades: Frontmatter, privada: Bool) {
        self.ruta = ruta; self.tipo = tipo; self.nombre = nombre; self.propiedades = propiedades; self.privada = privada
    }

    /// Texto de una propiedad tal como se llama, `nil` si falta o está vacía.
    public func texto(_ clave: String) -> String? {
        let k = clave.precomposedStringWithCanonicalMapping
        guard let p = propiedades.properties.first(where: { $0.key.precomposedStringWithCanonicalMapping == k }) else { return nil }
        let s = p.value.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty || s.contains("{{") ? nil : s
    }

    /// `id` de la ficha.
    public var uid: String? { texto("id") }
    public var estado: String? { texto("estado") }
    public func fecha(_ clave: String) -> LocalDate? { texto(clave).flatMap { LocalDate(parsing: $0) } }
    /// Importe en céntimos (`150.00` → 15000). `nil` si no hay dato.
    public func centimos(_ clave: String) -> Int? { texto(clave).flatMap(FormatosPlantilla.centimos) }
    /// Clave estable para eventos e idempotencia: el `id` o, si no lo tiene, la ruta.
    public var clave: String { uid?.lowercased() ?? "ruta:" + TextFolding.pathKey(ruta.raw) }
}

/// Una fila de `pagos.csv` (cabeceras de `Esquema.md`).
public struct FilaPago: Sendable, Hashable, Identifiable {
    public let id: String
    public let fecha: LocalDate?
    /// `cobro` o `pago`.
    public let direccion: String
    public let centimos: Int?
    public let documento: String?
    public let proyecto: String?
    public let tercero: String?
    public let evidencia: String?
    public let verificacion: String?
    /// Fichero del que sale.
    public let fichero: VaultPath

    public var esCobro: Bool { TextFolding.fold(direccion) == "cobro" }
    public var confirmado: Bool { TextFolding.fold(verificacion ?? "") == "confirmado" }
    public var esCobroConfirmado: Bool { esCobro && confirmado }

    /// Fila escrita como diccionario (la que un plan va a guardar con `upsertCSVRow`).
    init?(fila: [String: String], fichero: VaultPath) {
        func v(_ k: String) -> String? {
            let s = fila.first { TextFolding.fold($0.key) == k }?.value.trimmingCharacters(in: .whitespaces) ?? ""
            return s.isEmpty ? nil : s
        }
        guard let id = v("id") else { return nil }
        self.init(id: id, fecha: v("fecha").flatMap { LocalDate(parsing: $0) }, direccion: v("direccion") ?? "",
                  centimos: v("importe").flatMap(FormatosPlantilla.centimos), documento: v("documento_id"),
                  proyecto: v("proyecto_id"), tercero: v("tercero"), evidencia: v("evidencia"),
                  verificacion: v("verificacion"), fichero: fichero)
    }

    init(id: String, fecha: LocalDate?, direccion: String, centimos: Int?, documento: String?, proyecto: String?,
         tercero: String?, evidencia: String?, verificacion: String?, fichero: VaultPath) {
        self.id = id; self.fecha = fecha; self.direccion = direccion; self.centimos = centimos; self.documento = documento
        self.proyecto = proyecto; self.tercero = tercero; self.evidencia = evidencia; self.verificacion = verificacion
        self.fichero = fichero
    }

    static func leer(_ texto: String, fichero: VaultPath) -> [FilaPago] {
        let t = CSVTable.parse(texto)
        func col(_ n: String) -> Int? { t.header.firstIndex { TextFolding.fold($0) == n } }
        guard let cID = col("id") else { return [] }
        let cF = col("fecha"), cD = col("direccion"), cI = col("importe"), cDoc = col("documento_id"), cP = col("proyecto_id")
        let cT = col("tercero"), cE = col("evidencia"), cV = col("verificacion")
        return t.rows.compactMap { r in
            func v(_ i: Int?) -> String? {
                guard let i, i < r.count else { return nil }
                let s = r[i].trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }
            guard let id = v(cID) else { return nil }
            return FilaPago(id: id, fecha: v(cF).flatMap { LocalDate(parsing: $0) }, direccion: v(cD) ?? "",
                            centimos: v(cI).flatMap(FormatosPlantilla.centimos), documento: v(cDoc), proyecto: v(cP),
                            tercero: v(cT), evidencia: v(cE), verificacion: v(cV), fichero: fichero)
        }
    }
}

/// Una fila de `emitidas.csv`.
public struct FilaEmitida: Sendable, Hashable, Identifiable {
    public let id: String
    public let numero: String?
    public let fecha: LocalDate?
    public let tercero: String?
    public let centimos: Int?
    /// Columna `documento` tal cual (relativa a la carpeta de Finanzas en G3).
    public let documento: String?
    public let proyecto: String?

    static func leer(_ texto: String) -> [FilaEmitida] {
        let t = CSVTable.parse(texto)
        func col(_ n: String) -> Int? { t.header.firstIndex { TextFolding.fold($0) == n } }
        guard let cID = col("id") else { return [] }
        let cN = col("numero_documento"), cF = col("fecha_documento"), cT = col("tercero"), cTot = col("total_documento")
        let cDoc = col("documento"), cP = col("proyecto_id")
        return t.rows.compactMap { r in
            func v(_ i: Int?) -> String? {
                guard let i, i < r.count else { return nil }
                let s = r[i].trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }
            guard let id = v(cID) else { return nil }
            return FilaEmitida(id: id, numero: v(cN), fecha: v(cF).flatMap { LocalDate(parsing: $0) }, tercero: v(cT),
                               centimos: v(cTot).flatMap(FormatosPlantilla.centimos), documento: v(cDoc), proyecto: v(cP))
        }
    }
}

/// Modo de una función (capacidad) en `.tls/config.yaml` (PLAN §5.2).
public enum ModoCapacidad: String, Sendable, Hashable, CaseIterable {
    case off, manual, asistido, supervisado, autonomo

    /// Lo hace una persona: la regla deja una tarea en vez de actuar.
    public var esDePersona: Bool { self == .off || self == .manual }
}

/// Lo que el dominio lee de `.tls/config.yaml`: modos de las funciones y tope de tarjetas.
public struct ConfigDominio: Sendable, Hashable {
    public var modos: [String: ModoCapacidad]
    /// `avisos.tope_tarjetas_dia` (5 si no se dice).
    public var topeTarjetasDia: Int

    public init(modos: [String: ModoCapacidad] = [:], topeTarjetasDia: Int = 5) {
        self.modos = modos; self.topeTarjetasDia = topeTarjetasDia
    }

    /// Modo de una función; `nil` si no está en la configuración (la regla actúa: es de la app).
    public func modo(_ capacidad: String) -> ModoCapacidad? { modos[capacidad.uppercased()] }

    public static func leer(_ snapshot: VaultSnapshot) -> ConfigDominio {
        guard let texto = snapshot.text(VaultPath(VaultLayout.configFile)) else { return ConfigDominio() }
        return leer(yaml: texto)
    }

    public static func leer(yaml texto: String) -> ConfigDominio {
        var out = ConfigDominio()
        guard texto.utf8.count < 512 * 1024, let raiz = (try? Yams.compose(yaml: texto, Resolver.basic)) ?? nil,
              FrontmatterReader.nodeCount(raiz, limit: FrontmatterReader.maxNodes) <= FrontmatterReader.maxNodes,
              let mapa = raiz.mapping else { return out }
        if let caps = mapa["capacidades"]?.mapping {
            for (k, v) in caps {
                guard let codigo = k.string?.uppercased() else { continue }
                let modo = v.mapping?["modo"]?.string ?? v.string
                if let m = modo.flatMap({ ModoCapacidad(rawValue: TextFolding.fold($0).replacingOccurrences(of: " ", with: "")) }) {
                    out.modos[codigo] = m
                }
            }
        }
        if let tope = mapa["avisos"]?.mapping?["tope_tarjetas_dia"]?.string.flatMap({ Int($0) }), tope >= 0 {
            out.topeTarjetasDia = tope
        }
        return out
    }
}

/// Precio de un servicio según la Oferta (la única fuente de precios, SISTEMAS VE1).
public struct PrecioDeOferta: Sendable, Hashable {
    /// Ficha de la que sale (la versión de la oferta o el servicio).
    public let fuente: VaultPath
    public let nombreFuente: String
    /// Precio fijo en céntimos, si lo hay.
    public let centimos: Int?
    /// Servicio a medida: el rango dentro del que fija el precio una persona.
    public let minimo: Int?
    public let maximo: Int?

    /// `true` si el precio dado cuadra con la Oferta.
    public func admite(_ c: Int) -> Bool {
        if let p = centimos { return p == c }
        if let lo = minimo, c < lo { return false }
        if let hi = maximo, c > hi { return false }
        return minimo != nil || maximo != nil
    }

    /// «150,00 €», «de 100,00 € a 300,00 €» o `nil` si la Oferta no tiene precio.
    public var texto: String? {
        if let p = centimos { return Euros.texto(p) }
        switch (minimo, maximo) {
        case (let lo?, let hi?): return "de \(Euros.texto(lo)) a \(Euros.texto(hi))"
        case (let lo?, nil): return "desde \(Euros.texto(lo))"
        case (nil, let hi?): return "hasta \(Euros.texto(hi))"
        default: return nil
        }
    }
}

/// Importes en céntimos, escritos como en la carpeta (`150.00`) o como se leen («150,00 €»).
public enum Euros {
    /// `15000` → «150,00 €».
    public static func texto(_ centimos: Int) -> String {
        FormatosPlantilla.euros(escrito(centimos)) ?? escrito(centimos)
    }

    /// `15000` → `150.00` (como se escribe en las propiedades y los CSV).
    public static func escrito(_ centimos: Int) -> String {
        let signo = centimos < 0 ? "-" : ""
        let a = abs(centimos)
        return "\(signo)\(a / 100).\(String(format: "%02d", a % 100))"
    }
}

/// La foto del dominio de una carpeta.
public struct LecturaDominio: Sendable {
    public let snapshot: VaultSnapshot
    public let fichas: [VaultPath: FichaDominio]
    public let pagos: [FilaPago]
    public let emitidas: [FilaEmitida]
    public let config: ConfigDominio
    public let reloj: Reloj
    let resolver: LinkResolver
    let ids: [String: VaultPath]

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.snapshot = snapshot
        self.reloj = reloj ?? Reloj.deCarpeta(snapshot)
        let layout = snapshot.layout
        var fichas: [VaultPath: FichaDominio] = [:]
        for ruta in snapshot.notes where !VaultSnapshot.isTemplatePath(ruta) && !layout.isArchived(ruta) {
            guard let text = snapshot.text(ruta) else { continue }
            let doc = NoteDocument(text: text)
            let fm = doc.frontmatter
            let tipo = NoteKindResolver.kind(of: ruta, frontmatter: fm, layout: layout)
            fichas[ruta] = FichaDominio(ruta: ruta, tipo: tipo, nombre: GrafoRelaciones.nombre(fm, doc: doc, ruta: ruta),
                                        propiedades: fm, privada: layout.isPrivate(ruta))
        }
        self.fichas = fichas
        var pagos: [FilaPago] = []
        var emitidas: [FilaEmitida] = []
        for p in snapshot.textPaths where p.ext == "csv" && !layout.isArchived(p) && !layout.isPrivate(p) {
            switch TextFolding.nameKey(p.name) {
            case "pagos.csv": pagos += snapshot.text(p).map { FilaPago.leer($0, fichero: p) } ?? []
            case "emitidas.csv": emitidas += snapshot.text(p).map(FilaEmitida.leer) ?? []
            default: break
            }
        }
        self.pagos = pagos
        self.emitidas = emitidas
        self.config = ConfigDominio.leer(snapshot)
        self.resolver = snapshot.resolver
        var ids: [String: VaultPath] = [:]
        for (ruta, f) in fichas.sorted(by: { $0.key < $1.key }) {
            if let id = f.uid?.lowercased(), ids[id] == nil { ids[id] = ruta }
        }
        self.ids = ids
    }

    public var layout: VaultLayout { snapshot.layout }
    public var hoy: LocalDate { reloj.hoy }

    public func ficha(_ ruta: VaultPath) -> FichaDominio? {
        if let f = fichas[ruta] { return f }
        return snapshot.existing(ruta).flatMap { fichas[$0] }
    }

    /// Fichas de un tipo (también las privadas: quien enseña algo las filtra).
    public func fichas(_ tipo: NoteKind) -> [FichaDominio] {
        fichas.values.filter { $0.tipo == tipo }.sorted { $0.ruta < $1.ruta }
    }

    public var oportunidades: [FichaDominio] { fichas(.opportunity) }
    public var proyectos: [FichaDominio] { fichas(.project) }
    public var objetivos: [FichaDominio] { fichas(.objective) }
    public var facturas: [FichaDominio] { fichas(.invoice) }

    // MARK: Relaciones

    /// Destino de una relación escrita en una ficha (`oportunidad` o el heredado `oportunidad_id`).
    public func relacion(_ f: FichaDominio, _ clave: String) -> VaultPath? {
        relacion(f.propiedades, clave, desde: f.ruta)
    }

    func relacion(_ fm: Frontmatter, _ clave: String, desde ruta: VaultPath) -> VaultPath? {
        for k in [clave, clave + "_id"] {
            guard let v = fm.properties.first(where: { $0.key == k })?.value else { continue }
            let texto: String
            switch v {
            case .text(let t), .number(let t): texto = t
            case .list(let l) where l.count == 1: texto = l[0]
            default: continue
            }
            if let r = ContextoPlantilla.resolve(texto, from: ruta, resolver: resolver, ids: { ids[$0.lowercased()] }) {
                return r
            }
        }
        return nil
    }

    /// Ficha por `id` (sin distinguir mayúsculas).
    public func ficha(id: String) -> FichaDominio? {
        ids[id.lowercased()].flatMap { fichas[$0] }
    }

    /// Fichas de un tipo que guardan `clave` apuntando a `destino`.
    public func que(apuntan destino: VaultPath, por clave: String, tipo: NoteKind? = nil) -> [FichaDominio] {
        let d = TextFolding.pathKey(destino.raw)
        return fichas.values.filter { f in
            (tipo == nil || f.tipo == tipo) && relacion(f, clave).map { TextFolding.pathKey($0.raw) == d } == true
        }.sorted { $0.ruta < $1.ruta }
    }

    // MARK: Estados

    /// Estado de una oportunidad leído con los nombres heredados (Ganado, Borrador, Archivada…).
    public static func estadoOportunidad(_ texto: String?) -> String? {
        guard let t = texto else { return nil }
        switch TextFolding.fold(t) {
        case "prospecto", "borrador", "nueva", "nuevo": return "Prospecto"
        case "diagnostico": return "Diagnóstico"
        case "propuesta", "propuesta enviada": return "Propuesta"
        case "aceptada", "aceptado": return "Aceptada"
        case "ganada", "ganado": return "Ganada"
        case "perdida", "perdido", "archivada", "archivado": return "Perdida"
        case "pausada", "pausado": return "Pausada"
        default: return t
        }
    }

    /// Estado de un proyecto con los nombres heredados (En progreso, Completado…).
    public static func estadoProyecto(_ texto: String?) -> String? {
        guard let t = texto else { return nil }
        switch TextFolding.fold(t) {
        case "sin empezar", "pendiente": return "Sin empezar"
        case "en curso", "en progreso", "activo": return "En curso"
        case "pausado", "pausada": return "Pausado"
        case "cerrado", "cerrada", "completado", "terminado", "entregado": return "Cerrado"
        case "archivado", "cancelado": return "Archivado"
        default: return t
        }
    }

    /// Un proyecto es de entrega si lo dice `clase` o, sin `clase`, si vive en Entrega.
    public func esDeEntrega(_ fm: Frontmatter, ruta: VaultPath) -> Bool {
        if let c = fm.text("clase") { return TextFolding.fold(c) == "entrega" }
        return layout.area(of: ruta) == .entrega
    }

    // MARK: Cobros (VEN-07)

    /// Oportunidad a la que va un cobro: por su proyecto (`proyecto_id`) o por su factura (`documento_id`).
    public func oportunidad(de pago: FilaPago) -> VaultPath? {
        if let p = pago.proyecto, let proyecto = buscar(p, tipo: .project), let o = relacion(proyecto, "oportunidad") {
            return o
        }
        if let d = pago.documento, let factura = factura(numero: d), let o = relacion(factura, "oportunidad") {
            return o
        }
        return nil
    }

    /// Factura por su número (`F-2026-0007`), su `id` o la ruta que da `emitidas.csv`.
    public func factura(numero: String) -> FichaDominio? {
        let k = TextFolding.fold(numero)
        if let f = facturas.first(where: { TextFolding.fold($0.texto("numero") ?? "") == k || $0.uid.map(TextFolding.fold) == k }) {
            return f
        }
        guard let fila = emitidas.first(where: { TextFolding.fold($0.id) == k || TextFolding.fold($0.numero ?? "") == k }),
              let doc = fila.documento else { return nil }
        let candidatos = [VaultPath(doc), layout.areaFolder(.finanzas).appending(doc)]
        for c in candidatos {
            if let real = snapshot.existing(c), let f = fichas[real], f.tipo == .invoice { return f }
        }
        return nil
    }

    /// Ficha por `id`, por ruta o por nombre de fichero.
    func buscar(_ valor: String, tipo: NoteKind) -> FichaDominio? {
        if let f = ficha(id: valor), f.tipo == tipo { return f }
        if let real = snapshot.existing(VaultPath(valor)) ?? snapshot.existing(VaultPath(valor + ".md")),
           let f = fichas[real], f.tipo == tipo { return f }
        if let r = resolver.resolve("[[\(valor)]]", from: .root), let f = fichas[r], f.tipo == tipo { return f }
        return nil
    }

    /// Cobros confirmados por una persona en `pagos.csv` que van a esta oportunidad.
    public func cobrosConfirmados(de oportunidad: VaultPath) -> [FilaPago] {
        let k = TextFolding.pathKey(oportunidad.raw)
        return pagos.filter { $0.esCobroConfirmado && self.oportunidad(de: $0).map { TextFolding.pathKey($0.raw) == k } == true }
    }

    /// Recibos (`tls_type: receipt`) de una factura de la oportunidad confirmados por una persona (`confirmado_por` que
    /// no es un asistente): lo que deja «Confirmar el cobro» desde la ficha de la factura (F1). Integración F2: VEN-07
    /// los cuenta igual que un cobro confirmado en `pagos.csv`, como `GrafoRelaciones.cobroConfirmado`.
    public func recibosConfirmados(de oportunidad: VaultPath) -> [FichaDominio] {
        que(apuntan: oportunidad, por: "oportunidad", tipo: .invoice).flatMap { f in
            que(apuntan: f.ruta, por: "factura", tipo: .receipt).filter { r in
                guard let quien = r.texto("confirmado_por")?.trimmingCharacters(in: .whitespaces), !quien.isEmpty else { return false }
                return !quien.lowercased().hasPrefix("agente:")
            }
        }
    }

    /// VEN-07: ¿tiene la oportunidad un cobro confirmado por una persona (en `pagos.csv` o con su recibo)?
    public func tieneCobroConfirmado(_ oportunidad: VaultPath) -> Bool {
        !cobrosConfirmados(de: oportunidad).isEmpty || !recibosConfirmados(de: oportunidad).isEmpty
    }

    /// Proyectos de entrega de una oportunidad (ENT-01: como mucho uno).
    public func proyectosDeEntrega(de oportunidad: VaultPath) -> [FichaDominio] {
        que(apuntan: oportunidad, por: "oportunidad", tipo: .project).filter { esDeEntrega($0.propiedades, ruta: $0.ruta) }
    }

    // MARK: Precio (la Oferta es la única fuente)

    /// Precio de la Oferta para una ficha (oportunidad, propuesta…): su `oferta_version` o, si no, su servicio.
    public func precioDeOferta(_ fm: Frontmatter, desde ruta: VaultPath) -> PrecioDeOferta? {
        if let v = relacion(fm, "oferta_version", desde: ruta), let f = ficha(v), let p = precio(de: f) { return p }
        if let s = relacion(fm, "servicio", desde: ruta) ?? relacion(fm, "producto", desde: ruta), let f = ficha(s) {
            return precio(de: f)
        }
        return nil
    }

    func precio(de f: FichaDominio) -> PrecioDeOferta? {
        let fijo = f.centimos("precio")
        let lo = f.centimos("precio_min"), hi = f.centimos("precio_max")
        guard fijo != nil || lo != nil || hi != nil else { return nil }
        let medida = TextFolding.fold(f.texto("modelo_precio") ?? "") == "a medida"
        return PrecioDeOferta(fuente: f.ruta, nombreFuente: nombreDeOferta(f), centimos: medida && (lo != nil || hi != nil) ? nil : fijo,
                              minimo: lo, maximo: hi)
    }

    func nombreDeOferta(_ f: FichaDominio) -> String {
        guard f.tipo == .offer else { return f.nombre }
        let servicio = relacion(f, "servicio").flatMap { ficha($0) }?.nombre
        let version = f.texto("version").map { "v\($0)" } ?? f.texto("codigo")
        return [servicio, version].compactMap { $0 }.joined(separator: " ")
    }
}
