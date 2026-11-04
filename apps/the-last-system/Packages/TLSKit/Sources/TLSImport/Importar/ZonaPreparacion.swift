import Foundation
import TLSCore

/// Lo que se va a hacer con un fichero, ya decidido (zona de preparación → vista previa).
public struct DecisionImportacion: Sendable, Hashable {
    public let elemento: ElementoInventario
    public let clase: FuenteImportacion.Clase
    public let accion: AccionMapa
    /// Ruta pedida en la carpeta de la empresa (antes de resolver choques de nombre).
    public let destino: VaultPath?
    /// `tls_type` que toma la nota (adoptar), si lo toma.
    public let tipoFicha: String?
    public let motivo: String
    public let conflicto: String
    public let confianza: Double
}

/// Zona de preparación del paso 2: el inventario por bloques con lo que propone el clasificador y lo que cambia la
/// persona (destino, privado, dejar fuera, «todo / lo activo / nada» por herramienta, duplicados).
///
/// No escribe nada: es un valor que la interfaz cambia y del que salen la vista previa y el mapa.
public struct ZonaPreparacion: Sendable {
    /// Cambios de la persona sobre un fichero.
    public struct Ajuste: Sendable, Hashable, Codable {
        public var destino: VaultPath?
        public var privado = false
        public var fuera = false
        public init() {}
    }

    /// Ficheros iguales (mismo SHA-256) o con un nombre que parece una copia («Factura (1).pdf»).
    public struct GrupoDuplicados: Sendable, Hashable, Identifiable {
        public enum Clase: String, Sendable, Hashable { case identicos, nombreParecido }
        public let id: String
        public let clase: Clase
        public let claves: [String]
        /// El que se queda. En «nombre parecido» no se aparta nada hasta que la persona elige.
        public var seQueda: String?
    }

    /// Un bloque de la zona: una carpeta de primer nivel de una fuente (o los sueltos de su raíz).
    public struct Bloque: Sendable, Hashable, Identifiable {
        public let id: String
        public let nombre: String
        public let fuente: String
        public let herramienta: HerramientaOrigen
        public let claves: [String]
        public let soloEnICloud: Int
        /// Adónde va la mayoría («Ventas › Contactos»), o «Se queda donde está».
        public let destinoPrincipal: String
        public let fuera: Bool
    }

    public let inventario: InventarioImportacion
    public let layout: VaultLayout
    public let hoy: LocalDate
    public let clasificador: HeuristicClassifier
    public private(set) var propuestas: [String: PropuestaDestino]
    public private(set) var ajustes: [String: Ajuste] = [:]
    public private(set) var alcances: [HerramientaOrigen: AlcanceImportacion] = [:]
    public private(set) var duplicados: [GrupoDuplicados] = []
    /// SHA-256 → ruta de lo que ya hay en la carpeta de la empresa (para no traer de fuera lo que ya está).
    public let huellasDeLaCarpeta: [String: VaultPath]

    public init(inventario: InventarioImportacion, layout: VaultLayout, hoy: LocalDate,
                clasificador: HeuristicClassifier? = nil, huellasDeLaCarpeta: [String: VaultPath] = [:]) {
        self.inventario = inventario
        self.layout = layout
        self.hoy = hoy
        let c = clasificador ?? HeuristicClassifier(layout: layout, hoy: hoy)
        self.clasificador = c
        self.huellasDeLaCarpeta = huellasDeLaCarpeta
        var p: [String: PropuestaDestino] = [:]
        for e in inventario.elementos {
            p[e.clave] = c.proponer(e, clase: inventario.fuente(e.fuente)?.clase ?? .externa)
        }
        self.propuestas = p
        self.duplicados = Self.buscarDuplicados(inventario.elementos, clase: { inventario.fuente($0.fuente)?.clase ?? .externa })
    }

    // MARK: Lo que se ve

    /// Lo que no es privado.
    public var visibles: [ElementoInventario] {
        inventario.elementos.filter { ajustes[$0.clave]?.privado != true }
    }

    public func clase(_ e: ElementoInventario) -> FuenteImportacion.Clase {
        inventario.fuente(e.fuente)?.clase ?? .externa
    }

    public var bloques: [Bloque] {
        var grupos: [String: [ElementoInventario]] = [:]
        for e in visibles { grupos[e.fuente + "/" + e.bloque, default: []].append(e) }
        let variasFuentes = Set(visibles.map(\.fuente)).count > 1
        return grupos.keys.sorted().map { id in
            let els = grupos[id]!
            let primero = els[0]
            var cuenta: [String: Int] = [:]
            for e in els {
                let col = propuestas[e.clave]?.coleccion.flatMap { ColeccionV2.porClave($0)?.nombre } ?? "Se queda donde está"
                cuenta[col, default: 0] += 1
            }
            let principal = cuenta.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.first?.key ?? ""
            let nombre = variasFuentes ? "\(primero.fuente) › \(primero.bloqueVisible)" : primero.bloqueVisible
            return Bloque(id: id, nombre: nombre, fuente: primero.fuente, herramienta: primero.herramienta,
                          claves: els.map(\.clave), soloEnICloud: els.filter(\.soloEnICloud).count,
                          destinoPrincipal: principal, fuera: els.allSatisfy { ajustes[$0.clave]?.fuera == true })
        }
    }

    /// Herramientas que aparecen (para «todo / lo activo / nada»).
    public var herramientas: [HerramientaOrigen] {
        Array(Set(visibles.map(\.herramienta))).sorted()
    }

    public func alcance(_ h: HerramientaOrigen) -> AlcanceImportacion { alcances[h] ?? .todo }

    // MARK: Cambios de la persona

    /// Destino elegido a mano para un fichero (ruta dentro de la carpeta de la empresa).
    public mutating func cambiarDestino(_ clave: String, a destino: VaultPath) throws {
        guard !destino.isRoot, !destino.components.contains(".."), !destino.components.contains(where: { $0.hasPrefix(".") }) else {
            throw ImportError.mapaIlegible("«\(destino.raw)» no es una ruta válida dentro de tu carpeta")
        }
        ajustes[clave, default: Ajuste()].destino = destino
        if var p = propuestas[clave] {
            p.destino = destino; p.origen = .persona; p.confianza = 1; p.motivo = "Lo has elegido tú"; p.enSuSitio = false
            propuestas[clave] = p
        }
    }

    /// Todo un bloque a una colección de la estructura (la ruta de cada fichero la calcula el clasificador).
    public mutating func cambiarColeccion(bloque id: String, a coleccion: String) {
        guard ColeccionV2.porClave(coleccion) != nil, let b = bloques.first(where: { $0.id == id }) else { return }
        for clave in b.claves {
            guard let e = inventario.elemento(clave) else { continue }
            var p = clasificador.propuesta(e, coleccion: coleccion, confianza: 1, motivo: "Lo has elegido tú",
                                           pistaEnCarpeta: e.ruta.components.count > 1 ? 0 : nil, origen: .persona)
            p.enSuSitio = false
            propuestas[clave] = p
            ajustes[clave, default: Ajuste()].destino = nil
        }
    }

    /// Privado: no se mueve, no se copia, no se clasifica con IA y deja de verse (tampoco en el mapa ni en los
    /// repetidos: lo visible nunca se aparta por un gemelo privado). En la carpeta de la empresa, al aplicar queda
    /// declarado en `privado:` de `.tls/config.yaml` (`privadasDeLaEmpresa`).
    public mutating func marcarPrivado(_ clave: String) {
        ajustes[clave, default: Ajuste()].privado = true
        recalcularDuplicados()
    }

    public mutating func marcarPrivado(bloque id: String) {
        for e in inventario.elementos where e.fuente + "/" + e.bloque == id { ajustes[e.clave, default: Ajuste()].privado = true }
        recalcularDuplicados()
    }

    /// Los repetidos, solo entre lo visible. Lo que la persona eligió como «el que se queda» se conserva si sigue en
    /// su grupo.
    mutating func recalcularDuplicados() {
        let antes = Dictionary(duplicados.map { ($0.id, $0.seQueda) }, uniquingKeysWith: { a, _ in a })
        let inv = inventario
        var nuevos = Self.buscarDuplicados(visibles, clase: { inv.fuente($0.fuente)?.clase ?? .externa })
        for i in nuevos.indices {
            if let elegido = antes[nuevos[i].id] ?? nil, nuevos[i].claves.contains(elegido) { nuevos[i].seQueda = elegido }
        }
        duplicados = nuevos
    }

    /// Lo marcado como privado en la carpeta de la empresa, para declararlo en sus ajustes: la carpeta de primer
    /// nivel entera si todo lo suyo es privado; si no, cada fichero.
    public var privadasDeLaEmpresa: [VaultPath] {
        let empresa = inventario.elementos.filter { inventario.fuente($0.fuente)?.clase == .carpetaDeLaEmpresa }
        let privados = empresa.filter { ajustes[$0.clave]?.privado == true }
        guard !privados.isEmpty else { return [] }
        var out: [VaultPath] = []
        var porBloque: [String: [ElementoInventario]] = [:]
        for e in empresa { porBloque[e.bloque, default: []].append(e) }
        var bloquesEnteros = Set<String>()
        for (b, els) in porBloque where !b.isEmpty && els.allSatisfy({ ajustes[$0.clave]?.privado == true }) {
            bloquesEnteros.insert(b)
            out.append(VaultPath(b))
        }
        for e in privados where !bloquesEnteros.contains(e.bloque) { out.append(e.ruta) }
        return out.sorted()
    }

    /// Dejar fuera: no se toca (se ve en la lista como «Se queda fuera»).
    public mutating func dejarFuera(_ clave: String, _ fuera: Bool = true) { ajustes[clave, default: Ajuste()].fuera = fuera }

    public mutating func dejarFuera(bloque id: String, _ fuera: Bool = true) {
        for e in inventario.elementos where e.fuente + "/" + e.bloque == id { dejarFuera(e.clave, fuera) }
    }

    /// «Todo / lo activo / nada» para una herramienta.
    public mutating func fijarAlcance(_ h: HerramientaOrigen, _ a: AlcanceImportacion) { alcances[h] = a }

    /// En un grupo de duplicados, el que se queda (los demás se apartan).
    public mutating func quedarseCon(_ clave: String, enGrupo id: String) {
        guard let i = duplicados.firstIndex(where: { $0.id == id }), duplicados[i].claves.contains(clave) else { return }
        duplicados[i].seQueda = clave
    }

    /// Lo que propone la IA (solo cambia lo que el clasificador dejó con poca confianza y la persona no tocó).
    public mutating func incorporar(_ ia: [String: PropuestaDestino], umbral: Double = AIClassifier.umbral) {
        for (clave, p) in ia {
            guard let actual = propuestas[clave], actual.origen == .reglas, actual.confianza < umbral, !actual.enSuSitio,
                  ajustes[clave]?.privado != true, p.confianza > actual.confianza else { continue }
            propuestas[clave] = p
        }
    }

    /// Lo que se le puede preguntar a la IA: poca confianza, ni privado, ni con claves, ni elegido por la persona.
    public func candidatosIA(umbral: Double = AIClassifier.umbral) -> [ElementoInventario] {
        visibles.filter { e in
            guard !e.sensible, ajustes[e.clave]?.fuera != true, let p = propuestas[e.clave] else { return false }
            return p.origen == .reglas && p.confianza < umbral && !p.enSuSitio
        }
    }

    /// Carga un mapa revisado a mano: destinos y «mantener fuera».
    public mutating func aplicar(mapa: MapaImportacion) throws {
        for f in mapa.filas {
            let clave = f.origen.hasSuffix("/") ? String(f.origen.dropLast()) : f.origen
            guard inventario.elemento(clave) != nil, ajustes[clave]?.privado != true else { continue }
            switch f.accion {
            case .fuera, .noMigrar: dejarFuera(clave)
            default:
                dejarFuera(clave, false)
                if f.accion.traslada, f.accion != .archivar, f.accion != .duplicado, let d = f.rutaDestino,
                   d != propuestas[clave]?.destino {
                    try cambiarDestino(clave, a: d)
                }
            }
        }
    }

    // MARK: Decisiones

    /// Carpeta del archivo de esta importación (`Archivo/Importación AAAA-MM-DD`).
    public var carpetaArchivo: VaultPath { VaultPath(layout.archivo).appending("Importación \(hoy.description)") }

    /// Lo que se hará con cada fichero visible, en orden.
    public func decisiones() -> [DecisionImportacion] {
        var apartados: [String: String] = [:]   // clave → clave del que se queda
        for g in duplicados where g.clase == .identicos || g.seQueda != nil {
            guard let queda = g.seQueda else { continue }
            for c in g.claves where c != queda { apartados[c] = queda }
        }
        return visibles.map { e in decision(e, apartadoPor: apartados[e.clave]) }
    }

    func decision(_ e: ElementoInventario, apartadoPor: String?) -> DecisionImportacion {
        let clase = clase(e)
        let dentro = clase == .carpetaDeLaEmpresa
        let p = propuestas[e.clave]
        let aj = ajustes[e.clave] ?? Ajuste()
        func d(_ a: AccionMapa, _ destino: VaultPath?, _ motivo: String, _ conflicto: String = "", tipo: String? = nil)
            -> DecisionImportacion {
            DecisionImportacion(elemento: e, clase: clase, accion: a, destino: destino, tipoFicha: tipo, motivo: motivo,
                                conflicto: conflicto, confianza: p?.confianza ?? 0)
        }
        if aj.fuera { return d(.fuera, nil, "Lo has dejado fuera") }
        if e.sensible { return d(.fuera, nil, p?.motivo ?? "Parece un fichero con claves o contraseñas: no lo toco") }
        if e.soloEnICloud {
            return dentro ? d(.mantener, nil, "Solo está en iCloud: lo miro por su nombre y lo dejo donde está", "Solo en iCloud")
                : d(.noMigrar, nil, "Solo está en iCloud: no lo traigo para no descargarlo", "Solo en iCloud")
        }
        if let queda = apartadoPor, let otro = inventario.elemento(queda) {
            let motivo = "Es igual que «\(otro.nombreLimpio)»"
            return dentro ? d(.duplicado, VaultPath(layout.archivo).appending("Duplicados").appendingAll(e.ruta), motivo,
                              "Duplicado de \(otro.clave)")
                : d(.noMigrar, nil, motivo, "Duplicado de \(otro.clave)")
        }
        if !dentro, let sha = e.sha256, let ya = huellasDeLaCarpeta[sha] {
            return d(.noMigrar, nil, "Ya está en tu carpeta como «\(ya.name)»", "Duplicado de \(ya.raw)")
        }
        switch alcance(e.herramienta) {
        case .nada:
            return dentro ? d(.mantener, nil, "«Nada» para \(e.herramienta.nombre): se queda donde está")
                : d(.noMigrar, nil, "«Nada» para \(e.herramienta.nombre): no lo traigo")
        case .loActivo(let desde):
            if let f = fechaActividad(e), f < desde, p?.enSuSitio != true {
                let destino = dentro ? carpetaArchivo.appendingAll(e.ruta) : carpetaArchivo.appending(e.fuente).appendingAll(e.ruta)
                return d(.archivar, destino, "Es anterior al \(FormatoFechaImportacion.corta(desde)): va al Archivo como antecedente")
            }
        case .todo:
            break
        }
        guard let p else { return d(dentro ? .mantener : .noMigrar, nil, "Sin propuesta") }
        if p.enSuSitio || p.destino == nil {
            let adoptar = dentro && p.tipoFicha != nil && e.propiedades["id"] == nil && e.propiedadesLegibles
            return d(adoptar ? .propiedades : .mantener, nil, p.motivo, tipo: adoptar ? p.tipoFicha : nil)
        }
        let destino = aj.destino ?? p.destino!
        let tipo = (e.propiedades["id"] == nil && e.propiedadesLegibles) ? p.tipoFicha : nil
        if dentro {
            if TextFolding.pathKey(destino.raw) == TextFolding.pathKey(e.ruta.raw) {
                return d(tipo != nil ? .propiedades : .mantener, nil, p.motivo, tipo: tipo)
            }
            return d(destino.name == e.ruta.name ? .mover : .moverYRenombrar, destino, p.motivo, tipo: tipo)
        }
        return d(destino.name == e.ruta.name ? .copiar : .copiarYRenombrar, destino, p.motivo, tipo: tipo)
    }

    /// Fecha que cuenta para «lo activo»: la del nombre o, si no tiene, la de su última modificación.
    func fechaActividad(_ e: ElementoInventario) -> LocalDate? {
        if let f = e.fechaEnNombre {
            if f.count == 10 { return LocalDate(parsing: f) }
            // Solo el mes: cuenta su último día (un documento de octubre sigue activo el 15 de octubre).
            if let y = Int(f.prefix(4)), let m = Int(f.suffix(2)),
               let siguiente = LocalDate(year: m == 12 ? y + 1 : y, month: m == 12 ? 1 : m + 1, day: 1) {
                return siguiente.adding(days: -1)
            }
        }
        return e.modificado.map { LocalDate(date: $0) }
    }

    /// El mapa (formato de `mapa-migracion.csv`). Lo privado no sale.
    public func mapa() -> MapaImportacion {
        MapaImportacion(filas: decisiones().map { d in
            FilaMapa(origen: d.elemento.clave + (d.elemento.esPaquete ? "/" : ""), destino: d.destino?.raw ?? "—",
                     accion: d.accion, motivo: d.motivo, conflicto: d.conflicto, sha256: d.elemento.sha256 ?? "")
        })
    }

    // MARK: Duplicados

    static let sufijoCopia = try! NSRegularExpression(
        pattern: #"(?:\s*\(\d+\)|\s+\d{1,2}|\s*-?\s*(?:copia|copy)(?:\s*\d+)?)$"#, options: [.caseInsensitive])
    static let prefijoCopia = try! NSRegularExpression(pattern: #"^(?:copia de|copy of)\s+"#, options: [.caseInsensitive])

    /// Nombre sin las marcas de copia («Factura (1)», «Factura 2», «Copia de Factura»).
    static func nombreBase(_ p: VaultPath) -> String {
        var s = TextFolding.fold(InventarioImportacion.sinIdNotion(p.stem))
        for re in [sufijoCopia, prefijoCopia] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespaces) + "." + p.ext
    }

    static func pareceCopia(_ p: VaultPath) -> Bool {
        let s = TextFolding.fold(p.stem)
        let r = NSRange(location: 0, length: (s as NSString).length)
        return sufijoCopia.firstMatch(in: s, range: r) != nil || prefijoCopia.firstMatch(in: s, range: r) != nil
    }

    static func buscarDuplicados(_ els: [ElementoInventario], clase: (ElementoInventario) -> FuenteImportacion.Clase)
        -> [GrupoDuplicados] {
        var out: [GrupoDuplicados] = []
        var porHuella: [String: [ElementoInventario]] = [:]
        for e in els where !e.sensible && !e.soloEnICloud {
            if let h = e.sha256 { porHuella[h, default: []].append(e) }
        }
        var enGrupo = Set<String>()
        for (h, grupo) in porHuella where grupo.count > 1 {
            // Se queda: el de la carpeta de la empresa, el que no parece copia, el de ruta más corta, el más antiguo.
            let ordenado = grupo.sorted { a, b in
                let ka = (clase(a) == .carpetaDeLaEmpresa ? 0 : 1, pareceCopia(a.ruta) ? 1 : 0, a.ruta.components.count,
                          a.modificado ?? .distantFuture, a.clave)
                let kb = (clase(b) == .carpetaDeLaEmpresa ? 0 : 1, pareceCopia(b.ruta) ? 1 : 0, b.ruta.components.count,
                          b.modificado ?? .distantFuture, b.clave)
                return ka < kb
            }
            out.append(GrupoDuplicados(id: "sha:" + h, clase: .identicos, claves: ordenado.map(\.clave), seQueda: ordenado[0].clave))
            enGrupo.formUnion(grupo.map(\.clave))
        }
        // Nombre parecido y contenido distinto: se enseñan; no se aparta nada hasta que la persona elige.
        var porNombre: [String: [ElementoInventario]] = [:]
        for e in els where !e.sensible && !enGrupo.contains(e.clave) {
            porNombre[(e.ruta.parent?.raw ?? "") + "|" + nombreBase(e.ruta), default: []].append(e)
        }
        for (k, grupo) in porNombre where grupo.count > 1 && grupo.contains(where: { pareceCopia($0.ruta) }) {
            out.append(GrupoDuplicados(id: "nombre:" + k, clase: .nombreParecido, claves: grupo.map(\.clave).sorted(), seQueda: nil))
        }
        return out.sorted { $0.id < $1.id }
    }
}

extension VaultPath {
    /// Esta ruta seguida de todos los componentes de `otra`.
    func appendingAll(_ otra: VaultPath) -> VaultPath { VaultPath(components: components + otra.components) }
}
