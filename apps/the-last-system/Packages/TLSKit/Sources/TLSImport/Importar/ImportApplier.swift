import Foundation
import TLSCore

/// Lo que pasará con un fichero (una fila de la vista previa).
public struct MovimientoPrevisto: Sendable, Hashable {
    public let clave: String
    public let accion: AccionMapa
    /// Ruta final, con el choque de nombres ya resuelto (`ana-lopez-2.md`).
    public let destino: VaultPath?
    public let motivo: String
    public let conflicto: String
    public let confianza: Double
    /// Se le añaden propiedades (`tls_type`, `tls_schema`, `id`).
    public let adopta: Bool
}

/// Vista previa de «Ordenar lo que tienes»: «Mover 312 · Propiedades a 140 · Archivar 28 · No se borra nada».
/// Prepararla no escribe nada; `ImportApplier.aplicar` la ejecuta tal cual (un plan, que se deshace de una vez).
public struct VistaPreviaImportacion: Sendable {
    public let movimientos: [MovimientoPrevisto]
    /// Movidos dentro de la carpeta más traídos de fuera.
    public let mover: Int
    /// Fichas a las que se añaden propiedades.
    public let propiedades: Int
    /// A `Archivo/` (anteriores a la fecha de corte y duplicados).
    public let archivar: Int
    /// Se quedan como están (o no se traen).
    public let dejar: Int
    /// Carpetas que se quedan vacías: van al Archivo de la importación (no se borran).
    public let carpetasVacias: Int
    /// Enlaces que se reescriben para que sigan apuntando a lo mismo.
    public let enlaces: Int
    /// Enlaces que dejarían de apuntar a su nota: hay que revisarlos (o aceptarlos) antes de aplicar.
    public let enlacesEnRiesgo: [ProblemaDeEnlace]
    /// Filas nuevas de `Fechas de documentos.csv`.
    public let fechas: [FilaFecha]
    /// Documentos de Finanzas sin fecha legible (van al informe de calidad).
    public let sinFecha: [VaultPath]
    /// Lo que no se puede traer sin estropearlo (propiedades rotas, formato ilegible).
    public let noSeTraen: [String]
    /// Rutas que la persona marcó como privadas en la carpeta de la empresa: «Aplicar» las declara en `privado:` de
    /// `.tls/config.yaml` (en el mismo plan; se deshace con él). Lo privado no se mueve, no se edita ni se enseña.
    public let privadas: [VaultPath]
    public let informe: VaultPath
    public let mapa: MapaImportacion
    public let plan: WritePlan

    /// «Mover 312 · Propiedades a 140 · Archivar 28 · No se borra nada».
    public var resumen: String {
        "Mover \(mover) · Propiedades a \(propiedades) · Archivar \(archivar) · No se borra nada"
    }

    public var hayCambios: Bool { mover + propiedades + archivar > 0 || !privadas.isEmpty }

    // Para aplicar y comprobar.
    let raiz: URL
    let excluidas: [VaultPath]
    let inventarioAntes: Inventory
    /// En la carpeta de la empresa: ruta → SHA-256 de lo que se mueve o se edita (se comprueba antes de aplicar).
    let comprobaciones: [VaultPath: String]
    /// Notas tocadas (texto de antes, si lo había) para el motor del dominio.
    let notasAntes: [VaultPath: String]
    let autor: Autor
    let datosInforme: InformeImportacion
}

/// Lo que quedó tras aplicar.
public struct ResultadoImportacion: Sendable {
    /// Planes escritos, en orden: la importación y la anotación de la verificación en el informe.
    public let planes: [UUID]
    public let escritura: WriteResult
    public let verificacion: ResultadoVerificacion
    public let informe: VaultPath
    public let mapa: MapaImportacion
    /// Huella del árbol de antes (sin `Archivo/`): «Deshacer» la deja igual.
    public let hashArbolAntes: String
    /// Eventos del dominio que la importación no disparó (modo importación).
    public let eventosOmitidos: Int
}

/// Aplica la zona de preparación a la carpeta de la empresa (PLAN §6.7 paso 2; §9 F3 criterio 4).
///
/// - Un solo `WritePlan` por `CommandBus`, como persona: movimientos (con `LinkRefactor`, así los enlaces siguen
///   apuntando a lo mismo), propiedades (adoptar), lo traído de fuera, `Fechas de documentos.csv` y el informe en
///   `Buzón/`. Todo o nada, y se deshace de una vez.
/// - Nunca se borra ni se sobrescribe: un nombre ocupado se resuelve como en F1 (`ana-lopez-2.md`), retirar es mover
///   a `Archivo/`, y las filas `manual` de las fechas no se tocan.
/// - Con el motor del dominio, las reglas quedan apagadas mientras dura (modo importación).
/// - Al terminar, se comprueba todo (recuento y SHA-256) y se anota en el informe.
public struct ImportApplier: Sendable {
    public struct Opciones: Sendable {
        public var autor: Autor
        public var hoy: LocalDate
        /// Lo que se trae de fuera en una sola vez (va entero en el plan).
        public var maxBytesCopiados: Int64
        /// Escribir `Fechas de documentos.csv`.
        public var fechas: Bool
        public var ocr: (any ReconocedorDeTexto)?
        public var anoMinimoFechas: Int?

        public init(autor: Autor = .persona("Manu"), hoy: LocalDate, maxBytesCopiados: Int64 = 1 << 30, fechas: Bool = true,
                    ocr: (any ReconocedorDeTexto)? = OCRService(), anoMinimoFechas: Int? = nil) {
            self.autor = autor; self.hoy = hoy; self.maxBytesCopiados = maxBytesCopiados; self.fechas = fechas
            self.ocr = ocr; self.anoMinimoFechas = anoMinimoFechas
        }
    }

    /// Carpeta de la empresa (copia o ejemplo).
    public let raiz: URL
    public let opciones: Opciones
    let fs: any FileSystemAccess

    public init(carpeta: URL, opciones: Opciones, fileSystem: any FileSystemAccess = LocalFileSystem()) {
        self.raiz = carpeta.standardizedFileURL.resolvingSymlinksInPath()
        self.opciones = opciones
        self.fs = fileSystem
    }

    /// Tipos de ficha que, traídos de fuera, llegan con `fecha_corte` (no reactivan nada hasta revisarlos).
    static let conFlujo: Set<String> = ["task", "opportunity", "project"]

    // MARK: Vista previa

    /// Prepara la vista previa y el plan. Solo lee: no escribe nada en ningún sitio.
    public func preparar(_ zona: ZonaPreparacion) async throws -> VistaPreviaImportacion {
        let layout = zona.layout
        let empresa = zona.inventario.fuentes.first { $0.clase == .carpetaDeLaEmpresa }
        if let empresa, CopyJob.canonicalPath(empresa.raiz) != CopyJob.canonicalPath(raiz) {
            throw ImportError.fuenteNoAccesible(empresa.raiz.lastPathComponent)
        }
        // Lo privado (de la carpeta y lo que la persona marcó en la zona) ni se lee ni se toca: tampoco sus enlaces.
        // Lo dejado fuera al copiar apunta a la carpeta real: en la copia solo cuenta lo que existe.
        let privadasZona = zona.privadasDeLaEmpresa
        let excluidas = (empresa?.privado ?? [])
            + (empresa.map { FuenteImportacion.exclusionesDeLaCopia($0.exclusiones, raiz: raiz, archivo: layout.archivo, fileSystem: fs) } ?? [])
            + privadasZona
        let snapshot = VaultSnapshot.read(root: raiz, layout: layout, excluded: excluidas)
        let inventarioAntes = try await Inventory.make(of: raiz, exclusiones: excluidas, incluirArchivo: true, conHashes: true,
                                                       fileSystem: fs)
        let autor = opciones.autor
        let hoy = opciones.hoy
        var decisiones = zona.decisiones()

        // 1. Adoptar en su sitio (lo mismo que «Adoptar» de F1, solo para lo que no se mueve).
        let adopcion = Adopter(snapshot: snapshot).proponer()
        var identidades: [String: [Property]] = [:]
        // Solo lo que el escritor sabe cambiar byte a byte (UTF-8 y ya en el Mac).
        for i in adopcion.identidades where snapshot.text(i.ruta) != nil { identidades[TextFolding.pathKey(i.ruta.raw)] = i.anadir }

        // 2. Nombres libres (`-2`, `-3`… como en F1) y carpetas enteras que se mueven de una vez. Lo privado no está en
        // la foto, pero ocupa su sitio: nada se crea ni se mueve encima.
        var nombres = NombresLibres(snapshot: snapshot)
        for e in zona.inventario.elementos where zona.ajustes[e.clave]?.privado == true && zona.clase(e) == .carpetaDeLaEmpresa {
            nombres.reservarFichero(e.ruta)
        }
        let dentro = decisiones.filter { $0.clase == .carpetaDeLaEmpresa && $0.accion.traslada }
        var pedidos: [String: VaultPath] = [:]   // clave → destino pedido (limpio)
        for d in dentro { if let dest = d.destino { pedidos[d.elemento.clave] = NombresLibres.limpiar(dest) } }
        let carpetasEnteras = empresa.map { compactar(zona: zona, alias: $0.alias, pedidos: pedidos, snapshot: snapshot,
                                                     layout: layout) } ?? []
        var traslados: [Traslado] = []
        var finales: [String: VaultPath] = [:]
        for c in carpetasEnteras {
            nombres.reservar(arbol: c.a, con: c.contenido)
            traslados.append(Traslado(de: c.de, a: c.a))
            for (clave, rel) in c.contenido { finales[clave] = c.a.appendingAll(rel) }
        }
        for d in dentro.sorted(by: { $0.elemento.clave < $1.elemento.clave }) where finales[d.elemento.clave] == nil {
            guard let pedido = pedidos[d.elemento.clave] else { continue }
            let libre = nombres.libre(pedido)
            finales[d.elemento.clave] = libre
            traslados.append(Traslado(de: d.elemento.ruta, a: libre))
        }
        // Las carpetas que se quedan vacías van al Archivo de la importación (no se borran; «Deshacer» las devuelve).
        var carpetasVacias = 0
        if let empresa {
            let externosPedidos = decisiones.filter { $0.clase == .externa }.compactMap { $0.destino.map(NombresLibres.limpiar) }
            for d in vaciadas(zona: zona, alias: empresa.alias, finales: finales, compactadas: carpetasEnteras.map(\.de),
                              otrosDestinos: externosPedidos, layout: layout) {
                traslados.append(Traslado(de: d, a: nombres.libre(zona.carpetaArchivo.appendingAll(d))))
                carpetasVacias += 1
            }
        }

        // 3. Movimientos con sus enlaces (todo en un plan).
        var ops: [WriteOp] = []
        var enlaces = 0
        var problemas: [ProblemaDeEnlace] = []
        if !traslados.isEmpty {
            let previa = try LinkRefactor(snapshot: snapshot).preparar(
                traslados, descripcion: "Ordenar lo que tienes", opciones: LinkRefactor.Opciones(autor: autor))
            ops += previa.plan.ops
            enlaces += previa.enlaces
            problemas += previa.problemas
        }

        // 4. Propiedades: en su sitio (Adoptar) y en lo movido (según su colección).
        var adoptados = Set<String>()
        var notasAntes: [VaultPath: String] = [:]
        var comprobaciones: [VaultPath: String] = [:]
        for (i, d) in decisiones.enumerated() where d.clase == .carpetaDeLaEmpresa {
            let e = d.elemento
            if let sha = e.sha256, d.accion.escribe || identidades[TextFolding.pathKey(e.ruta.raw)] != nil {
                comprobaciones[e.ruta] = sha
            }
            let final = finales[e.clave] ?? e.ruta
            // En su sitio solo se adopta lo que está en el Mac y no tiene «Nada» (ni está fuera).
            let enSitio = (d.accion == .mantener && zona.propuestas[e.clave]?.enSuSitio == true) || d.accion == .propiedades
            let tocable = !e.soloEnICloud && !e.sensible && zona.alcance(e.herramienta) != .nada
            var props: [Property]?
            if enSitio, tocable, let ident = identidades[TextFolding.pathKey(e.ruta.raw)] {
                props = ident
            } else if let tipo = d.tipoFicha, e.tipo == .nota, e.propiedadesLegibles, e.propiedades["id"] == nil, tocable,
                      snapshot.text(e.ruta) != nil,
                      d.accion == .propiedades || d.accion == .mover || d.accion == .moverYRenombrar {
                props = Self.propiedades(e, tipo: tipo, destino: final, layout: layout, hoy: hoy, deFuera: false)
            }
            guard let props, !props.isEmpty else { continue }
            ops.append(.mergeFrontmatter(final, set: props, unset: []))
            adoptados.insert(e.clave)
            if let t = snapshot.text(e.ruta) { notasAntes[final] = t }
            if d.accion == .mantener {
                decisiones[i] = DecisionImportacion(elemento: e, clase: d.clase, accion: .propiedades, destino: nil,
                                                    tipoFicha: props.first(where: { $0.key == "tls_type" })?.value.displayText ?? d.tipoFicha,
                                                    motivo: d.motivo, conflicto: d.conflicto, confianza: d.confianza)
            }
        }
        for d in decisiones where d.clase == .carpetaDeLaEmpresa && d.elemento.tipo == .nota {
            if let f = finales[d.elemento.clave], notasAntes[f] == nil, let t = snapshot.text(d.elemento.ruta) { notasAntes[f] = t }
        }

        // 5. Lo que se trae de fuera: se lee ahora (en el hilo protegido), con sus enlaces y propiedades.
        let externas = decisiones.filter { $0.clase == .externa && $0.accion.traslada }
        var destinosExternos: [String: VaultPath] = [:]
        for d in externas.sorted(by: { $0.elemento.clave < $1.elemento.clave }) {
            guard let dest = d.destino else { continue }
            destinosExternos[d.elemento.clave] = nombres.libre(NombresLibres.limpiar(dest))
        }
        // Lo de fuera que no se trae porque ya está (repetido): sus enlaces llevan a donde queda el que se conserva.
        var redirigidos: [String: VaultPath] = [:]
        for g in zona.duplicados where g.clase == .identicos || g.seQueda != nil {
            guard let queda = g.seQueda, let eq = zona.inventario.elemento(queda) else { continue }
            let final = zona.clase(eq) == .carpetaDeLaEmpresa ? (finales[queda] ?? eq.ruta) : destinosExternos[queda]
            guard let final else { continue }
            for c in g.claves where c != queda && destinosExternos[c] == nil { redirigidos[c] = final }
        }
        for d in decisiones where d.clase == .externa && d.accion == .noMigrar && redirigidos[d.elemento.clave] == nil {
            if let sha = d.elemento.sha256, let ya = zona.huellasDeLaCarpeta[sha] { redirigidos[d.elemento.clave] = ya }
        }
        let traidos = try await traer(externas, destinos: destinosExternos, redirigidos: redirigidos, zona: zona, layout: layout, hoy: hoy)
        ops += traidos.ops
        problemas += traidos.enRiesgo
        var noSeTraen = traidos.noSeTraen
        for (clave, _) in traidos.rechazados { destinosExternos[clave] = nil }
        for d in externas where traidos.rechazados[d.elemento.clave] != nil {
            if let i = decisiones.firstIndex(of: d) {
                decisiones[i] = DecisionImportacion(elemento: d.elemento, clase: d.clase, accion: .noMigrar, destino: nil,
                                                    tipoFicha: nil, motivo: traidos.rechazados[d.elemento.clave]!,
                                                    conflicto: "No se puede traer", confianza: d.confianza)
            }
        }
        enlaces += traidos.enlaces
        adoptados.formUnion(traidos.adoptados)

        // 6. Fechas de los documentos de Finanzas.
        var filasFecha: [FilaFecha] = []
        var sinFecha: [VaultPath] = []
        if opciones.fechas {
            let r = try await fechar(decisiones, finales: finales, externos: destinosExternos, movimientos: traslados,
                                     zona: zona, snapshot: snapshot, layout: layout)
            filasFecha = r.filas
            sinFecha = r.sinFecha
            ops += r.ops
            noSeTraen += r.avisos
        }

        // 7. Lo marcado como privado queda declarado en los ajustes de la carpeta (no solo en el borrador de la app).
        if !privadasZona.isEmpty {
            let ruta = VaultPath(VaultLayout.configFile)
            let actual = snapshot.text(ruta)
            if actual == nil, fs.fileExists(ruta.url(in: raiz)) { throw ImportError.ajustesIlegibles }
            guard let nuevo = VaultLayout.configConPrivado(actual, anadir: privadasZona) else { throw ImportError.ajustesIlegibles }
            if let base = snapshot.data(ruta) {
                if nuevo != actual {
                    guard let op = WriteOp.replaceText(ruta, base: base, text: nuevo) else { throw ImportError.ajustesIlegibles }
                    ops.append(op)
                }
            } else {
                ops.append(.create(ruta, text: nuevo))
            }
        }

        // 8. El informe en el Buzón.
        let buzon = VaultPath(layout.buzon ?? "Buzón")
        let informe = nombres.libre(buzon.appending("Informe de importación \(hoy.description).md"))
        var previstos: [MovimientoPrevisto] = []
        for d in decisiones {
            let destino = finales[d.elemento.clave] ?? destinosExternos[d.elemento.clave]
            var conflicto = d.conflicto
            if let dest = destino, let pedido = d.destino, NombresLibres.limpiar(pedido) != dest {
                conflicto = conflicto.isEmpty ? "Ya había otro «\(NombresLibres.limpiar(pedido).name)»: va como «\(dest.name)»" : conflicto
            }
            previstos.append(MovimientoPrevisto(clave: d.elemento.clave, accion: d.accion, destino: destino, motivo: d.motivo,
                                                conflicto: conflicto, confianza: d.confianza,
                                                adopta: adoptados.contains(d.elemento.clave)))
        }
        let mover = previstos.filter { [.mover, .moverYRenombrar, .copiar, .copiarYRenombrar].contains($0.accion) }.count
        let archivar = previstos.filter { [.archivar, .duplicado].contains($0.accion) && $0.destino != nil }.count
        let dejar = previstos.count - mover - archivar - previstos.filter { $0.accion == .propiedades }.count
        let mapa = MapaImportacion(filas: previstos.map { p in
            let e = zona.inventario.elemento(p.clave)
            return FilaMapa(origen: p.clave + ((e?.esPaquete ?? false) ? "/" : ""),
                            destino: p.destino?.raw ?? "—", accion: p.accion, motivo: p.motivo, conflicto: p.conflicto,
                            sha256: e?.sha256 ?? "")
        })
        let datos = InformeImportacion(
            fecha: hoy, fuentes: zona.inventario.fuentes.map(\.alias), corte: zona.alcances.values.compactMap {
                if case .loActivo(let d) = $0 { return d } else { return nil }
            }.min(), ficheros: decisiones.count, movidos: mover, adoptados: adoptados.count, archivados: archivar,
            bloques: zona.bloques, propuestas: zona.propuestas, previstos: previstos, duplicados: zona.duplicados,
            inventario: zona.inventario, enlacesEnRiesgo: problemas.count, sinFecha: sinFecha.count, noSeTraen: noSeTraen,
            soloEnICloud: decisiones.filter { $0.elemento.soloEnICloud }.count, carpetasVacias: carpetasVacias,
            carpetaArchivo: zona.carpetaArchivo)
        ops.append(.create(informe, text: datos.texto))

        let resumen = "Mover \(mover) · Propiedades a \(adoptados.count) · Archivar \(archivar)"
        let plan = WritePlan(autor: autor, descripcion: "Ordenar lo que tienes (\(resumen))", ops: ops)
        return VistaPreviaImportacion(
            movimientos: previstos, mover: mover, propiedades: adoptados.count, archivar: archivar, dejar: max(0, dejar),
            carpetasVacias: carpetasVacias, enlaces: enlaces, enlacesEnRiesgo: problemas, fechas: filasFecha, sinFecha: sinFecha, noSeTraen: noSeTraen,
            privadas: privadasZona, informe: informe, mapa: mapa, plan: plan, raiz: raiz, excluidas: excluidas, inventarioAntes: inventarioAntes,
            comprobaciones: comprobaciones, notasAntes: notasAntes, autor: autor, datosInforme: datos)
    }

    /// Propiedades que se añaden a una nota que pasa a ser ficha (solo las que faltan).
    static func propiedades(_ e: ElementoInventario, tipo: String, destino: VaultPath, layout: VaultLayout, hoy: LocalDate,
                            deFuera: Bool) -> [Property] {
        var p: [Property] = []
        if e.propiedades["tls_type"] == nil { p.append(Property(key: "tls_type", value: .text(tipo))) }
        if e.propiedades["tls_schema"] == nil { p.append(Property(key: "tls_schema", value: .number("1"))) }
        p.append(Property(key: "id", value: .text(UUID().uuidString.lowercased())))
        if tipo == "project", e.propiedades["clase"] == nil {
            p.append(Property(key: "clase", value: .text(layout.area(of: destino) == .entrega ? "entrega" : "interno")))
        }
        if deFuera, conFlujo.contains(tipo), e.propiedades["fecha_corte"] == nil {
            p.append(Property(key: "fecha_corte", value: .text(hoy.description)))
        }
        return p
    }

    // MARK: Carpetas enteras

    struct CarpetaEntera {
        let de: VaultPath
        let a: VaultPath
        /// clave del elemento → ruta relativa dentro de la carpeta.
        let contenido: [String: VaultPath]
    }

    /// Carpetas cuyo contenido va entero, con la misma forma, a otra carpeta que aún no existe: se mueven de una vez
    /// (no quedan carpetas vacías detrás y no hace falta copia previa de cada fichero). Nunca si dentro hay algo
    /// privado, excluido, oculto, enlazado o solo en iCloud.
    func compactar(zona: ZonaPreparacion, alias: String, pedidos: [String: VaultPath], snapshot: VaultSnapshot,
                   layout: VaultLayout) -> [CarpetaEntera] {
        let indice = IndiceDeCarpetas(zona.inventario, alias: alias)
        let protegidas = Set([layout.archivo, layout.buzon ?? "Buzón"].map(TextFolding.pathKey))
        var hechas: [CarpetaEntera] = []
        var usadas = Set<String>()
        for d in indice.carpetas {
            if hechas.contains(where: { d.isDescendant(of: $0.de) }) { continue }
            if layout.area(of: d) != nil || protegidas.contains(TextFolding.pathKey(d.components.first ?? "")) { continue }
            let hijos = indice.hijos(d)
            guard !hijos.isEmpty, !indice.bloqueada(d) else { continue }
            var destino: VaultPath?
            var contenido: [String: VaultPath] = [:]
            var vale = true
            for h in hijos {
                guard let pedido = pedidos[h.clave] else { vale = false; break }
                let rel = VaultPath(components: Array(h.ruta.components.dropFirst(d.components.count)))
                guard pedido.components.count > rel.components.count,
                      pedido.components.suffix(rel.components.count).map(TextFolding.pathKey) == rel.components.map(TextFolding.pathKey) else {
                    vale = false; break
                }
                let x = VaultPath(components: Array(pedido.components.dropLast(rel.components.count)))
                if let dd = destino, TextFolding.pathKey(dd.raw) != TextFolding.pathKey(x.raw) { vale = false; break }
                destino = x
                contenido[h.clave] = rel
            }
            guard vale, let x = destino, !x.isRoot, !x.isDescendant(of: d), snapshot.existing(x) == nil,
                  !usadas.contains(TextFolding.pathKey(x.raw)),
                  !hechas.contains(where: { x.isDescendant(of: $0.a) || $0.a.isDescendant(of: x) }) else { continue }
            // Ningún antepasado del destino puede ser un fichero.
            var p = x.parent
            var libre = true
            while let a = p, !a.isRoot {
                if let hit = snapshot.existing(a), !snapshot.isDirectory(hit) { libre = false; break }
                p = a.parent
            }
            guard libre else { continue }
            usadas.insert(TextFolding.pathKey(x.raw))
            hechas.append(CarpetaEntera(de: d, a: x, contenido: contenido))
        }
        return hechas
    }

    /// Carpetas de la carpeta de la empresa de las que sale todo lo que tenían (y nada entra): solo las de más arriba.
    /// Nunca un área, el Buzón o el Archivo, ni una carpeta con algo privado, excluido, enlazado o solo en iCloud.
    func vaciadas(zona: ZonaPreparacion, alias: String, finales: [String: VaultPath], compactadas: [VaultPath],
                  otrosDestinos: [VaultPath], layout: VaultLayout) -> [VaultPath] {
        let indice = IndiceDeCarpetas(zona.inventario, alias: alias)
        let conDestino = IndiceDeCarpetas.antepasados(Array(finales.values) + otrosDestinos)
        let protegidas = Set([layout.archivo, layout.buzon ?? "Buzón"].map(TextFolding.pathKey))
        var elegidas: [VaultPath] = []
        for d in indice.carpetas {
            if elegidas.contains(where: { d.isDescendant(of: $0) }) || compactadas.contains(where: { d.isDescendant(of: $0) }) { continue }
            if layout.area(of: d) != nil || protegidas.contains(TextFolding.pathKey(d.components.first ?? "")) { continue }
            let hijos = indice.hijos(d)
            guard !hijos.isEmpty, hijos.allSatisfy({ finales[$0.clave] != nil }), !indice.bloqueada(d),
                  !conDestino.contains(TextFolding.pathKey(d.raw)) else { continue }
            elegidas.append(d)
        }
        return elegidas
    }

    // MARK: Traer de fuera

    struct Traidos {
        var ops: [WriteOp] = []
        var enlaces = 0
        var adoptados = Set<String>()
        var rechazados: [String: String] = [:]
        var noSeTraen: [String] = []
        /// Enlaces de lo que se trae que llevan a algo de su carpeta que no se trae: quedarán rotos.
        var enRiesgo: [ProblemaDeEnlace] = []
    }

    /// Lee lo que se trae de fuera (hilo protegido: nada se descarga) y prepara su creación. Comprueba que lo leído es
    /// lo que se inventarió (SHA-256) y que cada fichero se podrá volver a leer tras crearlo.
    func traer(_ externas: [DecisionImportacion], destinos: [String: VaultPath], redirigidos: [String: VaultPath] = [:],
               zona: ZonaPreparacion, layout: VaultLayout, hoy: LocalDate) async throws -> Traidos {
        guard !externas.isEmpty else { return Traidos() }
        let fs = self.fs
        let maximo = opciones.maxBytesCopiados
        return try await DatalessGuard.run("TLSImport.importar.traer") { cancel in
            var t = Traidos()
            var total: Int64 = 0
            // Un reescritor de enlaces por fuente: ruta en la fuente → ruta final.
            var porFuente: [String: [VaultPath: VaultPath]] = [:]
            for d in externas { if let dest = destinos[d.elemento.clave] { porFuente[d.elemento.fuente, default: [:]][d.elemento.ruta] = dest } }
            for (clave, dest) in redirigidos {
                guard let e = zona.inventario.elemento(clave), zona.ajustes[clave]?.privado != true else { continue }
                porFuente[e.fuente, default: [:]][e.ruta] = dest
            }
            var reescritores: [String: LinkRewriter] = [:]
            for f in zona.inventario.fuentes where f.clase == .externa {
                let ficheros = zona.inventario.elementos.filter { $0.fuente == f.alias }.map(\.ruta)
                reescritores[f.alias] = LinkRewriter(destinos: porFuente[f.alias] ?? [:], raizFuente: f.raiz, ficherosDeLaFuente: ficheros)
            }
            for d in externas.sorted(by: { $0.elemento.clave < $1.elemento.clave }) {
                try cancel.check()
                let e = d.elemento
                guard let dest = destinos[e.clave], let fuente = zona.inventario.fuente(e.fuente) else { continue }
                let url = e.ruta.url(in: fuente.raiz.standardizedFileURL.resolvingSymlinksInPath())
                if e.esPaquete {
                    var dentro: [(VaultPath, Data)] = []
                    try TreeWalker(fs: fs, rules: ExclusionRules()).walk(root: url) { item in
                        if case .file = item.kind { dentro.append((item.path, try fs.contents(of: item.url))) }
                    }
                    let (huella, _) = try InventarioImportacion.huellaDePaquete(url, fs: fs)
                    guard huella == e.sha256 else { throw ImportError.cambioDesdeLaVistaPrevia(e.nombreLimpio) }
                    for (rel, data) in dentro {
                        total += Int64(data.count)
                        t.ops.append(.create(dest.appendingAll(rel), contents: data))
                    }
                } else {
                    var data = try fs.contents(of: url)
                    guard ContentHash.of(data) == e.sha256 else { throw ImportError.cambioDesdeLaVistaPrevia(e.nombreLimpio) }
                    // Una nota en otra codificación (Windows, Latin-1) llega en UTF-8: es una copia, el original no cambia.
                    if e.tipo == .nota, FrontmatterDocument(data: data) == nil, let texto = TextDecoding.decode(data) {
                        data = Data(TextDecoding.strippingBOM(texto).utf8)
                    }
                    if e.tipo == .nota, let doc = FrontmatterDocument(data: data) {
                        var texto = doc.text
                        let bom = texto.hasPrefix("\u{FEFF}")
                        if bom { texto.removeFirst() }
                        if let rw = reescritores[e.fuente] {
                            let r = rw.reescribir(texto, origen: e.ruta, destino: dest)
                            texto = r.texto
                            t.enlaces += r.cambios
                            for x in r.quedanRotos {
                                t.enRiesgo.append(ProblemaDeEnlace(ruta: dest, linea: x.linea, enlace: x.enlace,
                                                                   motivo: "lleva a «\(x.destino.name)», que no traigo"))
                            }
                        }
                        var nuevo = FrontmatterDocument(text: (bom ? "\u{FEFF}" : "") + texto)
                        if let tipo = d.tipoFicha, e.propiedadesLegibles, !(nuevo.hasFrontmatter && !nuevo.frontmatter.isValid) {
                            nuevo.merge(set: ImportApplier.propiedades(e, tipo: tipo, destino: dest, layout: layout, hoy: hoy, deFuera: true),
                                        unset: [])
                            t.adoptados.insert(e.clave)
                        }
                        data = nuevo.data
                    }
                    if let motivo = Self.noSePuedeCrear(dest, data: data) {
                        t.rechazados[e.clave] = motivo
                        t.noSeTraen.append("\(e.nombreLimpio): \(motivo)")
                        t.adoptados.remove(e.clave)
                        t.enRiesgo.removeAll { $0.ruta == dest }
                        continue
                    }
                    total += Int64(data.count)
                    t.ops.append(.create(dest, contents: data))
                }
                if total > maximo { throw ImportError.demasiadoGrande(total) }
            }
            return t
        }
    }

    /// Lo que el escritor no aceptaría al crearlo (propiedades rotas, texto ilegible): mejor no traerlo y decirlo.
    static func noSePuedeCrear(_ p: VaultPath, data: Data) -> String? {
        switch p.ext {
        case "md", "markdown":
            guard let doc = FrontmatterDocument(data: data) else { return "no es texto que se pueda leer" }
            if doc.hasFrontmatter, !doc.frontmatter.isValid { return "sus propiedades están rotas; arréglalas y vuelve a traerlo" }
        case "csv":
            if TextDecoding.decode(data) == nil { return "no es texto que se pueda leer" }
        case "json":
            if (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) == nil { return "su contenido está dañado" }
        case "yaml", "yml":
            guard let t = TextDecoding.decode(data), FrontmatterReader.read(t).isValid else {
                return "no puedo comprobar que se lea bien"
            }
        default:
            break
        }
        return nil
    }

    // MARK: Fechas

    struct Fechado {
        var filas: [FilaFecha] = []
        var sinFecha: [VaultPath] = []
        var ops: [WriteOp] = []
        var avisos: [String] = []
    }

    /// Fecha de los documentos de Finanzas que acaban en Fiscal, Gestoría, Trámites o Registros sin fecha en el nombre
    /// y sin fila (las filas que ya hay siguen a su documento si se mueve; las `manual` no se tocan).
    func fechar(_ decisiones: [DecisionImportacion], finales: [String: VaultPath], externos: [String: VaultPath],
                movimientos: [Traslado], zona: ZonaPreparacion, snapshot: VaultSnapshot, layout: VaultLayout) async throws -> Fechado {
        let csvPedido = FechasDeDocumentos.ruta(layout)
        let csvReal = snapshot.existing(csvPedido)
        var cabecera: [String] = []
        var cubiertas = Set<String>()
        if let csvReal, let texto = snapshot.text(csvReal) {
            cabecera = CSVTable.parse(texto).header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            for f in FechasDeDocumentos.leer(texto) {
                let p = Verificador.seguir(FechasDeDocumentos.absoluta(f.ruta, layout: layout), movimientos)
                cubiertas.insert(TextFolding.pathKey(p.raw))
            }
        }
        var trabajo: [(URL, VaultPath)] = []
        for d in decisiones {
            let e = d.elemento
            guard !e.soloEnICloud, !e.sensible, !e.esPaquete, d.accion != .fuera, d.accion != .noMigrar,
                  zona.alcance(e.herramienta) != .nada else { continue }
            let final: VaultPath
            let url: URL
            if d.clase == .carpetaDeLaEmpresa {
                final = finales[e.clave] ?? e.ruta
                url = e.ruta.url(in: raiz)
            } else {
                guard let x = externos[e.clave], let f = zona.inventario.fuente(e.fuente) else { continue }
                final = x
                url = e.ruta.url(in: f.raiz.standardizedFileURL.resolvingSymlinksInPath())
            }
            guard DocumentDater.necesitaFila(final, layout: layout), !cubiertas.contains(TextFolding.pathKey(final.raw)) else { continue }
            trabajo.append((url, final))
        }
        guard !trabajo.isEmpty else { return Fechado() }
        let pendientes = trabajo
        let dater = DocumentDater(opciones: .init(hoy: opciones.hoy, anoMinimo: opciones.anoMinimoFechas, ocr: opciones.ocr))
        let leidas = try await DatalessGuard.run("TLSImport.importar.fechas") { cancel in
            try pendientes.map { (url, final) -> (VaultPath, FechaDocumento?) in
                try cancel.check()
                return (final, dater.fecha(de: url, ruta: final))
            }
        }
        var r = Fechado()
        for (final, f) in leidas {
            if let f {
                r.filas.append(FilaFecha(ruta: FechasDeDocumentos.relativa(final, layout: layout), fecha: f.fecha,
                                         fuente: f.fuente.rawValue, nota: f.nota))
            } else {
                r.sinFecha.append(final)
            }
        }
        guard !r.filas.isEmpty else { return r }
        if let csvReal {
            guard cabecera.contains("ruta") else {
                r.avisos.append("«\(FechasDeDocumentos.nombre)» no tiene la columna «ruta»: no he apuntado \(Plural.de(r.filas.count, "fecha", "fechas"))")
                r.filas = []
                return r
            }
            let filas = r.filas.map { f in f.diccionario.filter { cabecera.contains($0.key) } }
            r.ops.append(.insertCSVRows(csvReal, rows: filas, key: "ruta"))
        } else {
            r.ops.append(.create(csvPedido, text: FechasDeDocumentos.texto(r.filas)))
        }
        return r
    }

    // MARK: Aplicar

    /// Aplica la vista previa tal cual (un plan, como persona) y lo comprueba todo.
    ///
    /// - Antes: lo que se mueve o se edita sigue como en la vista previa (SHA-256); si no, no se escribe nada.
    /// - `motor`: si se pasa, las reglas del dominio quedan apagadas mientras dura (lo importado no dispara nada).
    /// - Después: recuento y SHA-256 de todo el árbol (también lo retirado a `Archivo/`), anotados en el informe.
    public func aplicar(_ vista: VistaPreviaImportacion, con bus: CommandBus, motor: MotorDeDominio? = nil,
                        aceptarEnlacesEnRiesgo: Bool = false) async throws -> ResultadoImportacion {
        guard vista.enlacesEnRiesgo.isEmpty || aceptarEnlacesEnRiesgo else {
            throw ImportError.enlacesEnRiesgo(vista.enlacesEnRiesgo.count)
        }
        guard vista.hayCambios else { throw ImportError.sinNadaQueHacer }
        // 1. Nada ha cambiado desde la vista previa.
        let raiz = vista.raiz
        let fs = self.fs
        let comprobaciones = vista.comprobaciones
        try await DatalessGuard.run("TLSImport.importar.comprobar") { cancel in
            for (p, sha) in comprobaciones {
                try cancel.check()
                let actual = try? fs.sha256(of: p.url(in: raiz))
                guard actual == sha else { throw ImportError.cambioDesdeLaVistaPrevia(p.name) }
            }
        }
        // 2. Escribir, con las reglas apagadas.
        if let motor { await motor.setModoImportacion(true) }
        let escritura: WriteResult
        do {
            escritura = try await bus.ejecutar(vista.plan)
        } catch {
            if let motor { await motor.setModoImportacion(false) }
            throw error
        }
        guard escritura.hecho else {
            if let motor { await motor.setModoImportacion(false) }
            throw ImportError.cambioDesdeLaVistaPrevia(escritura.conflicto?.ruta.name ?? "la carpeta")
        }
        var omitidos = 0
        if let motor {
            let cambios = escritura.cambiadas.filter { $0.ext == "md" }.map { p in
                CambioAplicado(ruta: p, antes: vista.notasAntes[p], despues: Self.leerTexto(p, raiz: raiz))
            }
            let antes = (try? motor.estado.eventos().count) ?? 0
            _ = try? await motor.registrar(cambios, autor: vista.autor, plan: escritura.planID)
            omitidos = max(0, ((try? motor.estado.eventos().count) ?? 0) - antes)
            await motor.setModoImportacion(false)
        }
        // 3. Comprobar (recuento y SHA-256).
        var creados: [VaultPath: String] = [:]
        for p in escritura.creadas { if let h = escritura.hashes[p] { creados[p] = h } }
        var editados: [VaultPath: String] = [:]
        for (p, h) in escritura.hashes where creados[p] == nil { editados[p] = h }
        let verificacion: ResultadoVerificacion
        do {
            let despues = try await Inventory.make(of: raiz, exclusiones: vista.excluidas, incluirArchivo: true, conHashes: true,
                                                   fileSystem: fs)
            verificacion = Verificador.verificar(antes: vista.inventarioAntes, despues: despues, movimientos: escritura.movidas,
                                                 editados: editados, creados: creados)
        } catch {
            // Lo escrito, escrito está (y se puede deshacer): sin foto de después, nada cuenta como comprobado.
            let antesN = vista.inventarioAntes.entradas.filter { $0.tipo == .fichero }.count
            verificacion = ResultadoVerificacion(
                total: antesN + creados.count, identicos: 0, editadosAProposito: 0, creados: 0,
                diferencias: [.init(tipo: .falta, origen: "(sin comprobar)", destino: error.localizedDescription)],
                recuentoAntes: antesN, recuentoDespues: 0, recuentoEsperado: antesN + creados.count)
        }
        // 4. Anotarlo en el informe (otro plan pequeño; «Deshacer» deshace los dos).
        let informe = escritura.creadas.last { $0.stem.hasPrefix("Informe de importación") } ?? vista.informe
        var planes = [escritura.planID]
        let anotacion = WritePlan(autor: vista.autor, descripcion: "Anotar la comprobación de la importación", ops: [
            .mergeFrontmatter(informe, set: [Property(key: "verificados", value: .number(String(verificacion.comprobados)))], unset: []),
            .appendToSection(informe, section: "Comprobación", text: vista.datosInforme.textoComprobacion(verificacion)),
        ])
        if let r = try? await bus.ejecutar(anotacion), r.hecho { planes.append(r.planID) }
        return ResultadoImportacion(planes: planes, escritura: escritura, verificacion: verificacion, informe: informe,
                                    mapa: vista.mapa, hashArbolAntes: Verificador.sinArchivo(vista.inventarioAntes).hashArbol,
                                    eventosOmitidos: omitidos)
    }

    static func leerTexto(_ p: VaultPath, raiz: URL) -> String? {
        UbiquityInspector.withoutMaterializing {
            guard let d = try? Data(contentsOf: p.url(in: raiz), options: [.uncached]) else { return nil }
            return TextDecoding.decode(d).map(TextDecoding.strippingBOM)
        }
    }

    // MARK: Deshacer

    /// Deshace la importación entera (y su anotación). Solo si después no se ha escrito nada más: si no, lo dice.
    /// Deja el árbol con su huella de antes (fuera de `Archivo/`, adonde va lo que se creó).
    @discardableResult
    public static func deshacer(_ r: ResultadoImportacion, con bus: CommandBus, autor: Autor = .persona("Manu")) async throws -> WriteResult {
        try await deshacer(planes: r.planes, con: bus, autor: autor)
    }

    /// Igual, con los planes guardados (la puesta en marcha los guarda en su estado para ofrecer «Deshacer» hasta el
    /// paso 3, también tras cerrar y abrir la app).
    @discardableResult
    public static func deshacer(planes: [UUID], con bus: CommandBus, autor: Autor = .persona("Manu")) async throws -> WriteResult {
        guard !planes.isEmpty, await sePuedeDeshacer(planes: planes, con: bus) else { throw ImportError.deshacerNoDisponible }
        var resultado: WriteResult?
        for id in planes.reversed() {
            guard let u = await bus.ultimoDeshacible(), u.planID == id else { throw ImportError.deshacerNoDisponible }
            resultado = try await bus.deshacer(autor: autor)
        }
        return resultado!
    }

    /// Se puede deshacer ahora (nada se ha escrito después).
    public static func sePuedeDeshacer(_ r: ResultadoImportacion, con bus: CommandBus) async -> Bool {
        await sePuedeDeshacer(planes: r.planes, con: bus)
    }

    public static func sePuedeDeshacer(planes: [UUID], con bus: CommandBus) async -> Bool {
        guard let ultimo = planes.last else { return false }
        return await bus.ultimoDeshacible()?.planID == ultimo
    }
}

/// Nombres libres en la carpeta de la empresa: lo que ya hay más lo que el plan va a ocupar. Un nombre ocupado pasa a
/// `nombre-2`, `nombre-3`… (como las fichas en F1), nunca «(2)».
struct NombresLibres {
    var ocupadas: Set<String>
    var ficheros: Set<String>

    init(snapshot: VaultSnapshot) {
        ocupadas = Set((snapshot.files + snapshot.directories).map { TextFolding.pathKey($0.raw) })
        ficheros = Set(snapshot.files.map { TextFolding.pathKey($0.raw) })
    }

    /// Cada parte de la ruta, válida como nombre (sin `/ : \ # ^ [ ] |`, sin punto delante, no vacía).
    static func limpiar(_ p: VaultPath) -> VaultPath {
        VaultPath(components: p.components.map { c in
            var n = NombresDeFicha.fichero(c)
            while n.utf8.count > 240 { n.removeLast() }
            return n.isEmpty ? "Sin nombre" : n
        })
    }

    func ocupada(_ p: VaultPath) -> Bool {
        if ocupadas.contains(TextFolding.pathKey(p.raw)) { return true }
        var a = p.parent
        while let x = a, !x.isRoot {
            if ficheros.contains(TextFolding.pathKey(x.raw)) { return true }
            a = x.parent
        }
        return false
    }

    mutating func reservar(_ p: VaultPath) {
        ocupadas.insert(TextFolding.pathKey(p.raw))
        var a = p.parent
        while let x = a, !x.isRoot { ocupadas.insert(TextFolding.pathKey(x.raw)); a = x.parent }
    }

    /// Un fichero que no está en la foto (privado) pero ocupa su sitio.
    mutating func reservarFichero(_ p: VaultPath) {
        reservar(p)
        ficheros.insert(TextFolding.pathKey(p.raw))
    }

    mutating func reservar(arbol: VaultPath, con contenido: [String: VaultPath]) {
        reservar(arbol)
        for rel in contenido.values {
            let p = arbol.appendingAll(rel)
            reservar(p)
            ficheros.insert(TextFolding.pathKey(p.raw))
        }
    }

    /// `p` si está libre; si no, `nombre-2.ext`, `nombre-3.ext`…
    mutating func libre(_ p: VaultPath) -> VaultPath {
        var c = p
        var n = 2
        while ocupada(c) {
            let ext = p.ext.isEmpty ? "" : "." + (p.name.split(separator: ".").last.map(String.init) ?? "")
            c = (p.parent ?? .root).appending("\(p.stem)-\(n)\(ext)")
            n += 1
        }
        reservar(c)
        ficheros.insert(TextFolding.pathKey(c.raw))
        return c
    }
}

/// Índice de una fuente por carpetas: qué cuelga de cada una y cuáles tienen dentro algo que no se puede mover.
struct IndiceDeCarpetas {
    /// De arriba abajo.
    let carpetas: [VaultPath]
    let porCarpeta: [String: [ElementoInventario]]
    let bloqueadas: Set<String>

    init(_ inv: InventarioImportacion, alias: String) {
        carpetas = (inv.carpetas[alias] ?? []).sorted { ($0.components.count, $0.raw) < ($1.components.count, $1.raw) }
        var por: [String: [ElementoInventario]] = [:]
        for e in inv.elementos where e.fuente == alias {
            var a = e.ruta.parent
            while let x = a, !x.isRoot { por[TextFolding.pathKey(x.raw), default: []].append(e); a = x.parent }
        }
        porCarpeta = por
        var b = Set<String>()
        for p in inv.bloqueos[alias] ?? [] {
            b.insert(TextFolding.pathKey(p.raw))
            b.formUnion(Self.antepasados([p]))
        }
        bloqueadas = b
    }

    func hijos(_ d: VaultPath) -> [ElementoInventario] { porCarpeta[TextFolding.pathKey(d.raw)] ?? [] }
    func bloqueada(_ d: VaultPath) -> Bool { bloqueadas.contains(TextFolding.pathKey(d.raw)) }

    /// Claves de todas las carpetas que contienen alguna de estas rutas.
    static func antepasados(_ rutas: [VaultPath]) -> Set<String> {
        var out = Set<String>()
        for r in rutas {
            var a = r.parent
            while let x = a, !x.isRoot { out.insert(TextFolding.pathKey(x.raw)); a = x.parent }
        }
        return out
    }
}
