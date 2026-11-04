import Foundation
import Yams

/// Lo que las métricas necesitan de la carpeta, leído una vez de una `VaultSnapshot`.
///
/// - Lo privado (`layout.isPrivate`), lo retirado a `Archivo/` y las plantillas no entran nunca.
/// - No escribe nada. Las cifras se leen tal cual; lo que falta queda `nil` (nunca 0).
/// - Los tipos van dentro de `FotoMetricas` para no chocar con los del dominio.
public struct FotoMetricas: Sendable {
    public let hoy: LocalDate
    /// La hora con la que se mira (la del `Reloj`); `nil` = la de la máquina.
    public let ahora: Date?
    public let layout: VaultLayout
    public let config: ConfigMetricas
    public let oportunidades: [Oportunidad]
    public let proyectos: [Proyecto]
    public let objetivos: [Objetivo]
    public let tareas: [TareaMedida]
    public let contenidos: [Contenido]
    public let conversaciones: [Conversacion]
    public let roles: [Rol]
    public let contactos: [Contacto]
    public let borradores: [Borrador]
    public let reuniones: [Reunion]
    public let rutinas: [Rutina]
    public let estadoAreas: [AreaCode: AreaStatus]
    public let facturas: [Factura]
    public let gastos: [Gasto]
    public let pagos: [Pago]
    public let cuentas: [Cuenta]
    public let usos: [UsoAsistente]
    /// Fechas de las decisiones de `1 · Dirección/Decisiones.md` (sin las sustituidas). `nil` si no hay registro.
    public let decisiones: [LocalDate]?
    /// Veces que la bitácora apunta cada función (`VEN-08` → 5): de aquí sale la tarjeta CRITERIO.
    public let ejecuciones: [String: Int]
    /// Qué ficheros de registro existen (aunque estén vacíos): distingue «sin dato» de «cero».
    public let registros: Registros
    /// `Incidencias.md` de los proyectos de entrega (integración F2: ENT-INC). Vacío = ningún registro («Sin dato»).
    public let incidencias: [RegistroIncidencias]

    // MARK: Tipos

    public enum EstadoOportunidad: String, Sendable, Hashable, CaseIterable {
        case prospecto = "Prospecto", diagnostico = "Diagnóstico", propuesta = "Propuesta", aceptada = "Aceptada"
        case ganada = "Ganada", perdida = "Perdida", pausada = "Pausada"

        /// Lee también los heredados (Borrador → Prospecto, Ganado, Perdido, Archivada → Perdida).
        public init?(leyendo texto: String) {
            switch TextFolding.fold(texto.trimmingCharacters(in: .whitespaces)) {
            case "prospecto", "borrador", "nuevo", "nueva": self = .prospecto
            case "diagnostico": self = .diagnostico
            case "propuesta", "pago inicial": self = .propuesta
            case "aceptada", "aceptado": self = .aceptada
            case "ganada", "ganado": self = .ganada
            case "perdida", "perdido", "archivada", "archivado": self = .perdida
            case "pausada", "pausado": self = .pausada
            default: return nil
            }
        }

        public var cerrada: Bool { self == .ganada || self == .perdida }
    }

    public struct Oportunidad: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let nombre: String
        public let estado: EstadoOportunidad?
        public let valor: Double?
        /// 0–100.
        public let probabilidad: Double?
        public let responsable: String?
        public let servicio: String?
        public let contacto: String?
        public let empresa: String?
        public let canal: String?
        public let creada: LocalDate?
        public let aceptada: LocalDate?
        public let cerrada: LocalDate?
        public let motivoPerdida: String?
        public let conPropuesta: Bool
        /// Día del primer cobro confirmado por una persona (fila `confirmado` de `pagos.csv` de su factura o de su
        /// proyecto, o el recibo de su factura). Es el día que cuenta en «Ventas cobradas del mes» (VEN-WON).
        public var cobrada: LocalDate? = nil
        /// Último contacto conocido (`ultimo_toque`, la última fecha de «Seguimiento», la de aceptación o la de
        /// creación), nunca posterior a hoy.
        public let ultimoContacto: LocalDate?

        public var abierta: Bool { !(estado?.cerrada ?? false) }

        /// Días sin contacto a día `hoy` (`nil` sin ninguna fecha).
        public func diasQuieta(hoy: LocalDate) -> Int? {
            ultimoContacto.map { max(0, RangoFechas.diasEntre($0, hoy)) }
        }
    }

    public enum EstadoProyecto: String, Sendable, Hashable {
        case sinEmpezar = "Sin empezar", enCurso = "En curso", pausado = "Pausado", cerrado = "Cerrado", archivado = "Archivado"

        public init?(leyendo texto: String) {
            switch TextFolding.fold(texto.trimmingCharacters(in: .whitespaces)) {
            case "sin empezar", "pendiente", "no iniciado": self = .sinEmpezar
            case "en curso", "en progreso", "activo": self = .enCurso
            case "pausado", "pausada": self = .pausado
            case "cerrado", "completado", "terminado", "hecho": self = .cerrado
            case "archivado", "cancelado": self = .archivado
            default: return nil
            }
        }

        public var abierto: Bool { self != .cerrado && self != .archivado }
    }

    public struct Proyecto: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let nombre: String
        public let area: AreaCode?
        /// `entrega` o `interno`.
        public let clase: String?
        public let estado: EstadoProyecto?
        public let objetivo: String?
        /// La ficha del objetivo, si el enlace se resuelve.
        public let objetivoRuta: VaultPath?
        /// «Seguir sin objetivo» (`sin_objetivo: true`): DIR-03 ya no lo señala.
        public let sinObjetivo: Bool
        public let oportunidad: String?
        public let empresa: String?
        public let inicio: LocalDate?
        public let fin: LocalDate?

        public var esDeEntrega: Bool { TextFolding.fold(clase ?? "") == "entrega" }
    }

    public struct Objetivo: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let titulo: String
        public let area: AreaCode?
        public let periodo: String?
        public let desde: LocalDate?
        public let hasta: LocalDate?
        public let meta: Double?
        public let unidad: String?
        public let acumulado: Bool
        /// Código del número clave que lo mide.
        public let medidoPor: String?
        public let prioritario: Bool
        /// En curso | Conseguido | No conseguido | Aplazado.
        public let estado: String?

        /// En curso (o sin estado) y con el periodo empezado y sin terminar.
        public func vivo(hoy: LocalDate) -> Bool {
            let e = TextFolding.fold(estado ?? "en curso")
            guard e == "en curso" || e.isEmpty else { return false }
            if let h = hasta, h < hoy { return false }
            return true
        }

        /// Tiene número: meta, periodo y código.
        public var conNumero: Bool { meta != nil && desde != nil && hasta != nil && medidoPor != nil }
    }

    /// Una tarea con lo que `Tarea` no lee (estimación, horas dedicadas).
    public struct TareaMedida: Sendable, Hashable, Identifiable {
        public var id: VaultPath { tarea.ruta }
        public let tarea: Tarea
        public let estimacionH: Double?
        public let dedicadasH: Double?
        /// Día en que se cerró: `cerrada` o, si falta (el tablero cambia solo `estado`, criterio F2-2), el de la última
        /// entrada de su Actividad que la pasó a su estado de ahora («Estado: En curso → Hecha.»).
        public var cerradaEn: LocalDate? = nil

        public var abierta: Bool { !(tarea.estado?.cerrada ?? false) }
        /// Decisión o pregunta (van a Decisiones, no son trabajo).
        public var esDecision: Bool {
            let t = TextFolding.fold(tarea.tipo ?? "tarea")
            return t == "decision" || t == "pregunta"
        }
    }

    public struct Contenido: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let titulo: String
        public let estado: String?
        public let publicado: LocalDate?
        public let evidencia: String?

        public var esPublicado: Bool { TextFolding.fold(estado ?? "") == "publicado" }
    }

    public struct Conversacion: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let perfil: String?
        public let estado: String?
        public let fecha: LocalDate?
        public let contacto: String?
        public let oportunidad: String?
        public let motivo: String?

        public var cualificada: Bool { TextFolding.fold(estado ?? "") == "cualificada" }
    }

    public struct Rol: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let nombre: String
        /// `humano` o `agente`.
        public let clase: String?
        public let areas: [AreaCode]
        /// Vacío o ausente: sin cubrir (o sin saber quién lo ocupa, si la clave ni siquiera existe).
        public let ocupante: String?
        /// La ficha escribe la clave `ocupante` (aunque esté vacía).
        public let declaraOcupante: Bool

        public var esHumano: Bool { TextFolding.fold(clase ?? "humano") != "agente" }
    }

    public struct Contacto: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let nombre: String
        public let empresa: String?
        public let estado: String?
    }

    public struct Borrador: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let estado: String?

        /// Sigue esperando tu OK (ni aprobado, ni enviado, ni descartado).
        public var pendiente: Bool {
            let e = TextFolding.fold(estado ?? "pendiente")
            return !["aprobado", "aprobada", "enviado", "enviada", "publicado", "publicada", "descartado",
                     "descartada", "rechazado", "rechazada", "emitida", "pagado"].contains(e)
        }
    }

    public struct Reunion: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let titulo: String
        public let fecha: LocalDate?
        public let hora: String?
        public let duracionMin: Double?
    }

    public struct Rutina: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        public let ruta: VaultPath
        public let nombre: String
        public let cadencia: String?
        /// «lunes»… (semanal) o el día del mes.
        public let dia: String?
        public let hora: String?
        public let duracionMin: Double?
        public let activa: Bool
    }

    public struct Factura: Sendable, Hashable, Identifiable {
        public let id: String
        public let numero: String
        public let fecha: LocalDate?
        public let tercero: String
        public let total: Double?
        /// Base imponible (de la ficha de la factura), si se conoce.
        public let base: Double?
        public let vence: LocalDate?
        public let ficha: VaultPath?
    }

    public struct Gasto: Sendable, Hashable, Identifiable {
        public let id: String
        public let fecha: LocalDate?
        public let tercero: String
        public let total: Double?
        public let base: Double?
    }

    public struct Pago: Sendable, Hashable, Identifiable {
        public let id: String
        public let fecha: LocalDate?
        /// `cobro` o `pago`.
        public let direccion: String
        public let importe: Double?
        public let documentoId: String?
        public let confirmado: Bool
    }

    public struct MovimientoBancario: Sendable, Hashable, Identifiable {
        public let id: String
        public let fecha: LocalDate?
        public let concepto: String
        /// Con el signo del banco.
        public let importe: Double?
        public let saldo: Double?
        public let naturaleza: String?
        public let categoria: String?
        public let documentoId: String?
        public let estadoConciliacion: String?

        /// Conciliado o ignorado.
        public var resuelto: Bool {
            let e = TextFolding.fold(estadoConciliacion ?? "")
            return e == "conciliado" || e == "ignorado"
        }

        public var esTraspaso: Bool { TextFolding.fold(naturaleza ?? "").hasPrefix("traspaso") }
    }

    public struct Cuenta: Sendable, Hashable, Identifiable {
        public var id: VaultPath { ruta }
        /// `…/Bancos/<cuenta>/Cuenta.md` (o la carpeta, si solo hay `movimientos.csv`).
        public let ruta: VaultPath
        public let nombre: String
        public let saldoInicial: Double?
        public let fechaSaldoInicial: LocalDate?
        public let movimientos: [MovimientoBancario]
        /// Existe `movimientos.csv` (aunque esté vacío).
        public let tieneMovimientosCSV: Bool

        /// Saldo a día `dia`: el último que dio el banco hasta ese día; si no hay, el inicial más los movimientos;
        /// si tampoco, `nil` (desconocido).
        public func saldo(a dia: LocalDate) -> Double? {
            let hasta = movimientos.filter { m in m.fecha.map { $0 <= dia } ?? false }
            if let ultimo = hasta.last(where: { $0.saldo != nil }), let s = ultimo.saldo {
                // Lo que entró después de ese movimiento y no trae saldo se suma.
                let idx = hasta.lastIndex(of: ultimo)!
                let despues = hasta[hasta.index(after: idx)...].compactMap(\.importe).reduce(0, +)
                return Self.redondear(s + despues)
            }
            guard let inicial = saldoInicial else { return nil }
            if let f = fechaSaldoInicial, f > dia { return nil }
            let suma = hasta.filter { m in
                guard let f = m.fecha else { return false }
                return fechaSaldoInicial.map { f > $0 } ?? true
            }.compactMap(\.importe).reduce(0, +)
            return Self.redondear(inicial + suma)
        }

        static func redondear(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    }

    /// Uso de un asistente apuntado en la bitácora.
    public struct UsoAsistente: Sendable, Hashable {
        public let fecha: LocalDate
        public let usd: Double
    }

    public struct Registros: Sendable, Hashable {
        public var emitidas = false
        public var recibidas = false
        public var pagos = false
        public var bitacora = false
    }

    // MARK: Lectura

    /// - Parameter ahora: la hora del reloj con el que se mira (`Reloj.ahora`), para lo que cuenta horas (ENT-INC y su
    ///   cuenta atrás). `nil` = la de la máquina.
    public init(snapshot: VaultSnapshot, hoy: LocalDate, ahora: Date? = nil) {
        let layout = snapshot.layout
        self.hoy = hoy
        self.ahora = ahora
        self.layout = layout
        self.config = ConfigMetricas.leer(snapshot.text(VaultPath(".tls/config.yaml")))
        let resolver = snapshot.resolver
        let ids = snapshot.idIndex()

        var oportunidades: [Oportunidad] = [], proyectos: [Proyecto] = [], objetivos: [Objetivo] = []
        var contenidos: [Contenido] = [], conversaciones: [Conversacion] = [], roles: [Rol] = []
        var contactos: [Contacto] = [], borradores: [Borrador] = [], reuniones: [Reunion] = [], rutinas: [Rutina] = []
        var cuentasMd: [VaultPath: FichaLeida] = [:]
        var facturasMd: [String: FichaLeida] = [:]
        // Para el día del cobro de cada oportunidad (VEN-WON).
        var facturasPorClave: [String: FichaLeida] = [:], proyectosPorId: [String: FichaLeida] = [:]
        var recibos: [FichaLeida] = []

        for p in snapshot.notes where Self.visible(p, layout: layout) {
            guard let text = snapshot.text(p) else { continue }
            let doc = NoteDocument(text: text)
            let fm = doc.frontmatter
            let kind = NoteKindResolver.kind(of: p, frontmatter: fm, layout: layout)
            let f = FichaLeida(ruta: p, fm: fm, body: doc.body, titulo: doc.title(fileStem: p.stem, frontmatter: fm),
                               resolver: resolver, ids: ids)
            switch kind {
            case .opportunity: oportunidades.append(Self.oportunidad(f, hoy: hoy))
            case .project:
                proyectos.append(Self.proyecto(f, layout: layout))
                if let i = f.texto("id") { proyectosPorId[TextFolding.fold(i)] = f }
            case .objective: objetivos.append(Self.objetivo(f, layout: layout))
            case .content:
                contenidos.append(Contenido(ruta: p, titulo: f.texto("titulo") ?? f.titulo, estado: f.texto("estado"),
                                            publicado: f.fecha("publicado"), evidencia: f.texto("evidencia_url") ?? f.texto("evidencia")))
            case .conversation:
                conversaciones.append(Conversacion(ruta: p, perfil: f.texto("perfil"), estado: f.texto("estado"), fecha: f.fecha("fecha"),
                                                   contacto: f.texto("contacto"), oportunidad: f.texto("oportunidad"),
                                                   motivo: f.texto("motivo")))
            case .role:
                let areas = f.lista("areas").compactMap { ConfigMetricas.area($0) }
                roles.append(Rol(ruta: p, nombre: f.texto("nombre") ?? f.titulo, clase: f.texto("clase"),
                                 areas: areas.isEmpty ? [layout.area(of: p)].compactMap { $0 } : areas,
                                 ocupante: f.texto("ocupante").map(LinkParser.plainText), declaraOcupante: f.tiene("ocupante")))
            case .contact:
                contactos.append(Contacto(ruta: p, nombre: f.texto("nombre") ?? f.titulo, empresa: f.texto("empresa"), estado: f.texto("estado")))
            case .draft: borradores.append(Borrador(ruta: p, estado: f.texto("estado")))
            case .meeting:
                reuniones.append(Reunion(ruta: p, titulo: f.texto("titulo") ?? f.titulo, fecha: f.fecha("fecha"), hora: f.texto("hora"),
                                         duracionMin: f.numero("duracion_min")))
            case .routine:
                rutinas.append(Rutina(ruta: p, nombre: f.texto("nombre") ?? f.titulo, cadencia: f.texto("cadencia"), dia: f.texto("dia"),
                                      hora: f.texto("hora"), duracionMin: f.numero("duracion_min"),
                                      activa: f.booleano("activa") ?? true))
            case .account: cuentasMd[p] = f
            case .invoice:
                if let n = f.texto("numero") { facturasMd[n.uppercased()] = f }
                for k in [f.texto("numero"), f.texto("id")].compactMap({ $0 }) { facturasPorClave[TextFolding.fold(k)] = f }
                facturasPorClave[TextFolding.pathKey(p.raw)] = f
            case .receipt: recibos.append(f)
            default: break
            }
        }

        // Tareas: las de `TaskStore`, sin lo privado.
        let store = TaskStore(snapshot: snapshot, reloj: Reloj(hoy: hoy))
        self.tareas = store.tareas.filter { !layout.isPrivate($0.ruta) }.map { t in
            let fm = snapshot.frontmatter(t.ruta)
            var cierre = t.cerrada
            if cierre == nil, let e = t.estado, e.cerrada, let texto = snapshot.text(t.ruta) {
                cierre = Self.fechaDeCierre(texto, estado: e.rawValue)
            }
            return TareaMedida(tarea: t, estimacionH: fm.text("estimacion_h").flatMap(FormatoBase.numero),
                               dedicadasH: fm.text("dedicadas_h").flatMap(FormatoBase.numero), cerradaEn: cierre)
        }

        // Estado de cada área (solo de su `Área.md`).
        var estados: [AreaCode: AreaStatus] = [:]
        for code in AreaCode.allCases {
            let folder = layout.areaFolder(code)
            if let real = snapshot.existing(folder.appending(AreaReader.fileName)), let t = snapshot.text(real) {
                estados[code] = AreaReader.parse(markdown: t, code: code, folder: folder, resolve: { resolver.resolve($0, from: real) }).estado
            } else {
                estados[code] = .desconocido
            }
        }
        self.estadoAreas = estados

        // Registros de Finanzas.
        let registros = layout.areaFolder(.finanzas).appending("Registros")
        var flags = Registros()
        func csv(_ nombre: String) -> CSVTable? {
            guard let real = snapshot.existing(registros.appending(nombre)), Self.visible(real, layout: layout),
                  let t = snapshot.text(real) else { return nil }
            return CSVTable.parse(t)
        }
        let pagosCSV = csv("pagos.csv")
        flags.pagos = pagosCSV != nil
        let pagos: [Pago] = (pagosCSV.map(Self.filas) ?? []).compactMap { d in
            guard let id = d["id"]?.nilSiVacio else { return nil }
            return Pago(id: id, fecha: d["fecha"].flatMap { LocalDate(parsing: $0) }, direccion: TextFolding.fold(d["direccion"] ?? ""),
                        importe: d["importe"].flatMap(FormatoBase.numero), documentoId: d["documento_id"]?.nilSiVacio,
                        confirmado: TextFolding.fold(d["verificacion"] ?? "") == "confirmado")
        }
        self.pagos = pagos
        // VEN-WON («Ventas cobradas del mes»): el día en que una persona confirmó el cobro de cada oportunidad.
        var cobroDe: [String: LocalDate] = [:]
        func apuntar(_ o: VaultPath?, _ d: LocalDate?) {
            guard let o, let d else { return }
            let k = TextFolding.pathKey(o.raw)
            cobroDe[k] = min(cobroDe[k] ?? d, d)
        }
        let filasPago = (pagosCSV.map(Self.filas) ?? [])
        for d in filasPago where TextFolding.fold(d["direccion"] ?? "") == "cobro" && TextFolding.fold(d["verificacion"] ?? "") == "confirmado" {
            var opo: VaultPath?
            if let pr = d["proyecto_id"]?.nilSiVacio, let f = proyectosPorId[TextFolding.fold(pr)] { opo = f.enlace("oportunidad") }
            if opo == nil, let doc = d["documento_id"]?.nilSiVacio, let f = facturasPorClave[TextFolding.fold(doc)] {
                opo = f.enlace("oportunidad")
            }
            apuntar(opo, d["fecha"].flatMap { LocalDate(parsing: $0) })
        }
        for r in recibos {
            guard let quien = r.texto("confirmado_por"), !quien.lowercased().hasPrefix("agente:"),
                  let fr = r.enlace("factura"), let f = facturasPorClave[TextFolding.pathKey(fr.raw)] else { continue }
            apuntar(f.enlace("oportunidad"), r.fecha("fecha"))
        }
        for i in oportunidades.indices { oportunidades[i].cobrada = cobroDe[TextFolding.pathKey(oportunidades[i].ruta.raw)] }
        let emitidasCSV = csv("emitidas.csv")
        flags.emitidas = emitidasCSV != nil
        let finanzas = layout.areaFolder(.finanzas)
        self.facturas = (emitidasCSV.map(Self.filas) ?? []).compactMap { d in
            guard let id = d["id"]?.nilSiVacio else { return nil }
            let numero = d["numero_documento"]?.nilSiVacio ?? id
            var ficha: FichaLeida? = facturasMd[numero.uppercased()] ?? facturasMd[id.uppercased()]
            if ficha == nil, let doc = d["documento"]?.nilSiVacio {
                let ruta = finanzas.appending(doc)
                if let real = snapshot.existing(ruta), Self.visible(real, layout: layout), let t = snapshot.text(real) {
                    let nd = NoteDocument(text: t)
                    ficha = FichaLeida(ruta: real, fm: nd.frontmatter, body: nd.body, titulo: real.stem, resolver: resolver, ids: ids)
                }
            }
            return Factura(id: id, numero: numero, fecha: d["fecha_documento"].flatMap { LocalDate(parsing: $0) },
                           tercero: d["tercero"] ?? "", total: d["total_documento"].flatMap(FormatoBase.numero) ?? ficha?.numero("total"),
                           base: ficha?.numero("base"), vence: ficha?.fecha("vence") ?? d["vence"].flatMap { LocalDate(parsing: $0) },
                           ficha: ficha?.ruta)
        }
        let recibidasCSV = csv("recibidas.csv")
        flags.recibidas = recibidasCSV != nil
        self.gastos = (recibidasCSV.map(Self.filas) ?? []).compactMap { d in
            guard let id = d["id"]?.nilSiVacio else { return nil }
            return Gasto(id: id, fecha: d["fecha_documento"].flatMap { LocalDate(parsing: $0) }, tercero: d["tercero"] ?? "",
                         total: d["total_documento"].flatMap(FormatoBase.numero), base: d["base"].flatMap(FormatoBase.numero))
        }

        // Cuentas: cada `movimientos.csv` con su `Cuenta.md` al lado (o solo uno de los dos).
        var carpetas = Set<VaultPath>()
        for p in cuentasMd.keys { if let d = p.parent { carpetas.insert(d) } }
        for p in snapshot.textPaths where p.name.lowercased() == "movimientos.csv" && Self.visible(p, layout: layout)
            && TextFolding.nameKey(p.parent?.parent?.name ?? "") == "bancos" {
            if let d = p.parent { carpetas.insert(d) }
        }
        var cuentas: [Cuenta] = []
        for dir in carpetas.sorted() {
            let md = cuentasMd.first { $0.key.parent == dir }?.value
            let csvRuta = snapshot.existing(dir.appending("movimientos.csv"))
            let filas = csvRuta.flatMap { snapshot.text($0) }.map { Self.filas(CSVTable.parse($0)) } ?? []
            let movimientos: [MovimientoBancario] = filas.compactMap { d in
                guard let id = d["id"]?.nilSiVacio ?? d["import_hash"]?.nilSiVacio else { return nil }
                return MovimientoBancario(id: id, fecha: d["fecha"].flatMap { LocalDate(parsing: $0) }, concepto: d["concepto"] ?? "",
                                          importe: d["importe"].flatMap(FormatoBase.numero), saldo: d["saldo"].flatMap(FormatoBase.numero),
                                          naturaleza: d["naturaleza"]?.nilSiVacio, categoria: d["categoria"]?.nilSiVacio,
                                          documentoId: d["documento_id"]?.nilSiVacio, estadoConciliacion: d["estado_conciliacion"]?.nilSiVacio)
            }.enumerated().sorted { a, b in
                // Por fecha y, a igual fecha, en el orden del fichero.
                switch (a.element.fecha, b.element.fecha) {
                case let (x?, y?) where x != y: return x < y
                default: return a.offset < b.offset
                }
            }.map(\.element)
            cuentas.append(Cuenta(ruta: md?.ruta ?? dir, nombre: md.flatMap { $0.texto("nombre") } ?? md?.titulo ?? dir.name,
                                  saldoInicial: md?.numero("saldo_inicial"), fechaSaldoInicial: md?.fecha("fecha_saldo_inicial"),
                                  movimientos: movimientos, tieneMovimientosCSV: csvRuta != nil))
        }
        self.cuentas = cuentas

        // Bitácora de los asistentes: «… · uso 0,04 USD …».
        let bitacora = layout.areaFolder(.equipo).appending("Bitácora")
        var usos: [UsoAsistente] = []
        var ejecuciones: [String: Int] = [:]
        for p in snapshot.notes where p.parent.map({ TextFolding.pathKey($0.raw) == TextFolding.pathKey(bitacora.raw) }) ?? false
            && Self.visible(p, layout: layout) {
            flags.bitacora = true
            for linea in (snapshot.text(p) ?? "").split(whereSeparator: \.isNewline) {
                let l = String(linea)
                if l.hasPrefix("- "), let r = l.range(of: #"· ([A-Z]{3}-\d{2}) ·"#, options: .regularExpression) {
                    let cod = l[r].dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
                    if LocalDate(parsing: String(l.dropFirst(2).prefix(10))).map({ $0 <= hoy }) ?? false {
                        ejecuciones[cod, default: 0] += 1
                    }
                }
                guard l.hasPrefix("- "), let fecha = LocalDate(parsing: String(l.dropFirst(2).prefix(10))),
                      let r = l.range(of: #"uso\s+([\d.,]+)\s*USD"#, options: [.regularExpression, .caseInsensitive]) else { continue }
                let cifra = l[r].replacingOccurrences(of: "uso", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "USD", with: "", options: .caseInsensitive)
                if let n = FormatoBase.numero(cifra) { usos.append(UsoAsistente(fecha: fecha, usd: n)) }
            }
        }
        self.usos = usos
        self.ejecuciones = ejecuciones

        // Registro de decisiones: `- 2026-10-21 · … ` (lo corregido lleva «(sustituida)» y no cuenta).
        let registro = layout.areaFolder(.direccion).appending("Decisiones.md")
        if let real = snapshot.existing(registro), Self.visible(real, layout: layout), let t = snapshot.text(real) {
            self.decisiones = t.split(whereSeparator: \.isNewline).compactMap { linea in
                let l = linea.trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("- "), !l.contains("(sustituida)") else { return nil }
                return LocalDate(parsing: String(l.dropFirst(2).prefix(10)))
            }
        } else {
            self.decisiones = nil
        }
        self.registros = flags

        // Registros de incidencias junto a la ficha de cada proyecto de entrega (como los lee la Operación de Entrega).
        let zona = TimeZone(identifier: config.zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
        var incidencias: [RegistroIncidencias] = []
        for p in proyectos where (p.esDeEntrega || p.area == .entrega) {
            guard let carpeta = p.ruta.parent, let real = snapshot.existing(carpeta.appending("Incidencias.md")),
                  Self.visible(real, layout: layout), let t = snapshot.text(real) else { continue }
            incidencias.append(RegistroIncidencias.leer(t, ruta: real, zona: zona))
        }
        self.incidencias = incidencias

        self.oportunidades = oportunidades.sorted { $0.ruta < $1.ruta }
        self.proyectos = proyectos.sorted { $0.ruta < $1.ruta }
        self.objetivos = objetivos.sorted { $0.ruta < $1.ruta }
        self.contenidos = contenidos.sorted { $0.ruta < $1.ruta }
        self.conversaciones = conversaciones.sorted { $0.ruta < $1.ruta }
        self.roles = roles.sorted { $0.ruta < $1.ruta }
        self.contactos = contactos.sorted { $0.ruta < $1.ruta }
        self.borradores = borradores.sorted { $0.ruta < $1.ruta }
        self.reuniones = reuniones.sorted { $0.ruta < $1.ruta }
        self.rutinas = rutinas.sorted { $0.ruta < $1.ruta }
    }

    /// Ni privado, ni en `Archivo/`, ni plantilla.
    static func visible(_ p: VaultPath, layout: VaultLayout) -> Bool {
        !layout.isPrivate(p) && !layout.isArchived(p) && !VaultSnapshot.isTemplatePath(p)
    }

    static func filas(_ t: CSVTable) -> [[String: String]] {
        let cab = t.header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return t.rows.map { r in
            var d: [String: String] = [:]
            for (i, h) in cab.enumerated() where i < r.count { d[h] = r[i].trimmingCharacters(in: .whitespaces) }
            return d
        }
    }

    static func oportunidad(_ f: FichaLeida, hoy: LocalDate) -> Oportunidad {
        let estado = f.texto("estado").flatMap { EstadoOportunidad(leyendo: $0) }
        var fechas: [LocalDate] = [f.fecha("ultimo_toque"), f.fecha("aceptada"), f.fecha("creada")].compactMap { $0 }
        if let seg = MarkdownSections.content(of: "Seguimiento", in: f.body) {
            for linea in seg.split(whereSeparator: \.isNewline) {
                let l = linea.trimmingCharacters(in: .whitespaces)
                let sinVineta = l.hasPrefix("- ") ? String(l.dropFirst(2)) : (l.hasPrefix("### ") ? String(l.dropFirst(4)) : l)
                if let d = LocalDate(parsing: String(sinVineta.prefix(10))) { fechas.append(d) }
            }
        }
        let conPropuesta = f.texto("oferta_version") != nil || f.texto("precio_congelado") != nil
            || [.propuesta, .aceptada, .ganada].contains(estado)
        return Oportunidad(ruta: f.ruta, nombre: f.texto("nombre") ?? f.titulo, estado: estado, valor: f.numero("valor"),
                           probabilidad: f.numero("probabilidad"), responsable: f.texto("responsable"), servicio: f.texto("servicio"),
                           contacto: f.texto("contacto"), empresa: f.texto("empresa"), canal: f.texto("canal"),
                           creada: f.fecha("creada"), aceptada: f.fecha("aceptada"), cerrada: f.fecha("cerrada"),
                           motivoPerdida: f.texto("motivo_perdida"), conPropuesta: conPropuesta,
                           ultimoContacto: fechas.filter { $0 <= hoy }.max())
    }

    /// Día de la última entrada de Actividad que pasó la tarea a `estado` (`### AAAA-MM-DD HH:MM · autor` y su
    /// `<!-- tls:evento {"tipo":"estado","a":"Hecha",…} -->`). `nil` si no hay ninguna.
    static func fechaDeCierre(_ texto: String, estado: String) -> LocalDate? {
        var dia: LocalDate?
        var cierre: LocalDate?
        let objetivo = TextFolding.fold(estado)
        for linea in texto.split(whereSeparator: \.isNewline) {
            let l = linea.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("### ") {
                dia = LocalDate(parsing: String(l.dropFirst(4).prefix(10)))
                continue
            }
            guard l.hasPrefix("<!-- tls:evento "), l.hasSuffix("-->"), let d = dia else { continue }
            let json = l.dropFirst("<!-- tls:evento ".count).dropLast(3).trimmingCharacters(in: .whitespaces)
            guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  obj["tipo"] as? String == "estado", let a = obj["a"] as? String, TextFolding.fold(a) == objetivo else { continue }
            cierre = d
        }
        return cierre
    }

    static func proyecto(_ f: FichaLeida, layout: VaultLayout) -> Proyecto {
        Proyecto(ruta: f.ruta, nombre: f.texto("nombre") ?? f.ruta.parent?.name ?? f.titulo,
                 area: ConfigMetricas.area(f.texto("area") ?? "") ?? layout.area(of: f.ruta),
                 clase: f.texto("clase"), estado: f.texto("estado").flatMap { EstadoProyecto(leyendo: $0) },
                 objetivo: f.texto("objetivo") ?? f.texto("objetivo_id"),
                 objetivoRuta: f.enlace("objetivo") ?? f.enlace("objetivo_id"), sinObjetivo: f.booleano("sin_objetivo") ?? false,
                 oportunidad: f.texto("oportunidad") ?? f.texto("oportunidad_id"), empresa: f.texto("empresa"),
                 inicio: f.fecha("inicio"), fin: f.fecha("fin"))
    }

    static func objetivo(_ f: FichaLeida, layout: VaultLayout) -> Objetivo {
        Objetivo(ruta: f.ruta, titulo: f.texto("titulo") ?? f.titulo, area: ConfigMetricas.area(f.texto("area") ?? ""),
                 periodo: f.texto("periodo"), desde: f.fecha("desde"), hasta: f.fecha("hasta"), meta: f.numero("meta"),
                 unidad: f.texto("unidad"), acumulado: f.booleano("acumulado") ?? false,
                 medidoPor: f.texto("medido_por")?.uppercased(), prioritario: f.booleano("prioritario") ?? f.booleano("critico") ?? false,
                 estado: f.texto("estado"))
    }

    // MARK: Consultas comunes

    public var oportunidadesAbiertas: [Oportunidad] { oportunidades.filter(\.abierta) }
    public var tareasAbiertas: [TareaMedida] { tareas.filter(\.abierta) }
    public var decisionesAbiertas: [TareaMedida] { tareas.filter { $0.abierta && $0.esDecision } }
    public var objetivosVivos: [Objetivo] { objetivos.filter { $0.vivo(hoy: hoy) } }

    /// Las seis áreas, salvo las que están en reposo.
    public func enReposo(_ a: AreaCode) -> Bool { estadoAreas[a] == .reposo }

    /// Un área tiene dueño distinto de ti: un rol humano suyo con ocupante que no eres tú.
    public func tieneDueno(_ a: AreaCode) -> Bool {
        roles.contains { r in
            guard r.esHumano, r.areas.contains(a), let o = r.ocupante?.trimmingCharacters(in: .whitespaces), !o.isEmpty else { return false }
            return !config.esTitular(o)
        }
    }

    /// Algún rol de las personas dice quién lo ocupa (si ninguno lo dice, «dueño» es un dato que falta). Las fichas de
    /// los asistentes (`clase: agente`) siempre dicen su ocupante y se cuentan aparte (F4, como `tieneDueno`).
    public var rolesDicenOcupante: Bool { roles.contains { $0.esHumano && $0.declaraOcupante } }
}

/// Lo que las métricas leen de `.tls/config.yaml`.
public struct ConfigMetricas: Sendable, Hashable {
    /// `agenda.tope_horas_dia` (4 por defecto).
    public var topeHorasDia: Double = 4
    /// `avisos.tope_tarjetas_dia`: tarjetas al día que no son rojas (5 por defecto).
    public var topeTarjetasDia: Int = 5
    /// `agenda.zona`.
    public var zona: String = "Europe/Madrid"
    /// `capacidades:` declaradas (declarada = madurez; modo = permiso).
    public var capacidades: [String: DeclaracionCapacidad] = [:]
    /// Quién es el titular (`titular:`); además «Manu», «yo» y «titular» cuentan siempre como tú.
    public var titular: [String] = []
    public var pausaAreas: [AreaCode] = []

    public init() {}

    public struct DeclaracionCapacidad: Sendable, Hashable {
        public let codigo: String
        public let declarada: Bool
        public let ejecutor: Ejecutor?
        public let modo: String?
        public let declaradaPor: String?
        public let desde: LocalDate?
        /// `sin_ti: si`: la persona dijo que funciona sin ella (aunque lo haga otra persona, `H`).
        public var sinTi: Bool? = nil
    }

    public func esTitular(_ nombre: String) -> Bool {
        let n = TextFolding.fold(LinkParser.plainText(nombre))
        return (["manu", "yo", "titular"] + titular.map { TextFolding.fold($0) }).contains(n)
    }

    /// Lee la configuración (lo que no se entiende se queda en su valor por defecto).
    public static func leer(_ texto: String?) -> ConfigMetricas {
        var c = ConfigMetricas()
        guard let texto, let node = try? Yams.compose(yaml: texto, Resolver.basic), case .mapping(let raiz) = node else { return c }
        func mapa(_ n: Node?) -> [String: Node] {
            guard case .mapping(let m)? = n else { return [:] }
            var d: [String: Node] = [:]
            for (k, v) in m { if case .scalar(let s) = k { d[s.string] = v } }
            return d
        }
        func escalar(_ n: Node?) -> String? {
            guard case .scalar(let s)? = n else { return nil }
            let t = s.string.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t == "~" || t == "null" ? nil : t
        }
        let r = mapa(.mapping(raiz))
        let agenda = mapa(r["agenda"])
        if let t = escalar(agenda["tope_horas_dia"]).flatMap(FormatoBase.numero), t >= 0 { c.topeHorasDia = t }
        if let z = escalar(agenda["zona"]) { c.zona = z }
        let avisos = mapa(r["avisos"])
        if let t = escalar(avisos["tope_tarjetas_dia"]).flatMap({ Int($0) }), t >= 0 { c.topeTarjetasDia = t }
        if let t = escalar(r["titular"]) { c.titular = [t] }
        if case .sequence(let seq)? = r["titular"] { c.titular = seq.compactMap { escalar($0) } }
        if case .sequence(let seq)? = r["pausa_areas"] { c.pausaAreas = seq.compactMap { escalar($0).flatMap(area) } }
        for (codigo, v) in mapa(r["capacidades"]) {
            let d = mapa(v)
            let declarada = escalar(d["declarada"]).map { ["si", "sí", "true", "yes", "1"].contains(TextFolding.fold($0)) } ?? false
            c.capacidades[codigo.uppercased()] = DeclaracionCapacidad(
                codigo: codigo.uppercased(), declarada: declarada, ejecutor: escalar(d["ejecutor"]).flatMap { Ejecutor(leyendo: $0) },
                modo: escalar(d["modo"]), declaradaPor: escalar(d["declarada_por"]), desde: escalar(d["desde"]).flatMap { LocalDate(parsing: $0) },
                sinTi: escalar(d["sin_ti"]).map { ["si", "sí", "true", "yes", "1"].contains(TextFolding.fold($0)) })
        }
        return c
    }

    /// «ventas», «Ventas», «VEN», «2 · Ventas», «[[2 · Ventas/Área|Ventas]]» → área.
    public static func area(_ texto: String) -> AreaCode? {
        let t = TextFolding.fold(LinkParser.plainText(texto)).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        for a in AreaCode.allCases {
            let nombre = TextFolding.fold(a.nombre)
            if t == nombre || t == a.layoutKey || t == a.rawValue.lowercased() || t == "\(a.numero) · \(nombre)" || t.hasSuffix("· \(nombre)") {
                return a
            }
        }
        return nil
    }
}

/// Una ficha leída con ayudas para sacar textos, cifras, fechas y listas.
struct FichaLeida: Sendable {
    let ruta: VaultPath
    let fm: Frontmatter
    let body: String
    let titulo: String
    let resolver: LinkResolver
    let ids: [String: VaultPath]

    func propiedad(_ k: String) -> Property? {
        let key = TextFolding.nameKey(k)
        return fm.properties.first { TextFolding.nameKey($0.key) == key }
    }

    func tiene(_ k: String) -> Bool { propiedad(k) != nil }

    func texto(_ k: String) -> String? {
        guard let v = propiedad(k)?.value else { return nil }
        let s = v.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty || s.contains("{{") ? nil : s
    }

    func numero(_ k: String) -> Double? { texto(k).flatMap(FormatoBase.numero) }
    func fecha(_ k: String) -> LocalDate? { texto(k).flatMap { LocalDate(parsing: $0) } }

    func booleano(_ k: String) -> Bool? {
        guard let v = propiedad(k)?.value else { return nil }
        if case .bool(let b) = v { return b }
        let t = TextFolding.fold(v.displayText.trimmingCharacters(in: .whitespaces))
        if ["si", "true", "yes", "1"].contains(t) { return true }
        if ["no", "false", "0"].contains(t) { return false }
        return nil
    }

    func lista(_ k: String) -> [String] {
        guard let v = propiedad(k)?.value else { return [] }
        if case .list(let l) = v { return l }
        let s = v.displayText.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? [] : s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func enlace(_ k: String) -> VaultPath? {
        guard let v = texto(k) else { return nil }
        return ContextoPlantilla.resolve(v, from: ruta, resolver: resolver, ids: { ids[$0.lowercased()] })
    }
}

extension String {
    var nilSiVacio: String? {
        let t = trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
