import Foundation

// Rol areas-a (F2). `Portal.md` de un proyecto de entrega (PLAN §4.4, plantilla «Portal v1»):
// - `## Viaje`: | Sesión | Estado | Fecha | Resumen para el cliente | Nota interna | (S1–S9; Pendiente, Programada,
//   Kit listo, Hecha o No incluida);
// - `## Tareas del cliente`: casillas, deberes del cliente (no son fichas de tarea);
// - `## Documentos` y `## Dudas y problemas`.
// Está en TLSCore (carpeta propia del rol) porque los números de Entrega (ENT-ARR48) también leerán el Viaje.
//
// La vista del cliente (SISTEMAS §4.3, criterio F2-8) es otro tipo, `PortalCliente`, que **no tiene** campos para
// notas internas, responsable, resolución, correos ni kit; y sus textos pasan por `PortalCliente.limpiar`.

/// Estado de una sesión del Viaje.
public enum EstadoSesion: String, Sendable, Hashable, CaseIterable {
    case pendiente = "Pendiente"
    case programada = "Programada"
    case kitListo = "Kit listo"
    case hecha = "Hecha"
    case noIncluida = "No incluida"

    public init?(leyendo texto: String) {
        switch TextFolding.fold(texto.trimmingCharacters(in: .whitespaces)) {
        case "pendiente", "por programar": self = .pendiente
        case "programada", "agendada": self = .programada
        case "kit listo", "kit preparado": self = .kitListo
        case "hecha", "hecho", "realizada": self = .hecha
        case "no incluida", "no incluido", "fuera": self = .noIncluida
        default: return nil
        }
    }

    /// Lo que ve el cliente: preparar el kit es cosa nuestra, para él la sesión sigue «Programada».
    public var paraCliente: EstadoSesion { self == .kitListo ? .programada : self }

    /// Ya está agendada (tiene día): Programada, Kit listo o Hecha.
    public var agendada: Bool { self == .programada || self == .kitListo || self == .hecha }
}

/// Una fila del Viaje (S1–S9).
public struct SesionViaje: Sendable, Hashable, Identifiable {
    public var id: String { celdaSesion }
    /// «S3» (o la celda entera si no empieza por S y un número).
    public let codigo: String
    /// «Revisión de gastos» (lo que va tras «·» en la celda Sesión).
    public let nombre: String?
    /// La celda Sesión tal cual: es la clave para cambiar la fila.
    public let celdaSesion: String
    public let estado: EstadoSesion?
    /// El estado tal como está escrito (si no se entiende, se enseña así).
    public let estadoTexto: String?
    public let fecha: LocalDate?
    public let fechaTexto: String?
    public let resumen: String?
    /// Solo para nosotros: el cliente nunca la ve.
    public let notaInterna: String?

    public init(codigo: String, nombre: String?, celdaSesion: String, estado: EstadoSesion?, estadoTexto: String?,
                fecha: LocalDate?, fechaTexto: String?, resumen: String?, notaInterna: String?) {
        self.codigo = codigo; self.nombre = nombre; self.celdaSesion = celdaSesion; self.estado = estado
        self.estadoTexto = estadoTexto; self.fecha = fecha; self.fechaTexto = fechaTexto; self.resumen = resumen
        self.notaInterna = notaInterna
    }

    /// 3 para «S3».
    public var numero: Int? {
        guard codigo.count > 1, codigo.first == "S" || codigo.first == "s" else { return nil }
        return Int(codigo.dropFirst())
    }

    /// «S3 · Revisión de gastos».
    public var titulo: String { nombre.map { "\(codigo) · \($0)" } ?? codigo }
}

/// Una casilla de `## Tareas del cliente`: «- [ ] Enviar las facturas de septiembre · S2 · vence 2026-10-30».
public struct TareaDelCliente: Sendable, Hashable, Identifiable {
    public var id: String { "\(linea)" }
    public let linea: Int
    public let texto: String
    public let hecha: Bool
    public let sesion: String?
    public let vence: LocalDate?

    public init(linea: Int, texto: String, hecha: Bool, sesion: String?, vence: LocalDate?) {
        self.linea = linea; self.texto = texto; self.hecha = hecha; self.sesion = sesion; self.vence = vence
    }
}

/// `Portal.md` leído (vista interna: todo).
public struct PortalDocumento: Sendable, Hashable {
    public let ruta: VaultPath?
    /// «Portal de Talleres Martín e Hijos SL».
    public let titulo: String?
    /// Borrador · Publicado · Cerrado (de sus propiedades).
    public let estado: String?
    public let sesiones: [SesionViaje]
    public let tareasCliente: [TareaDelCliente]
    public let documentos: [String]
    public let dudas: [String]
    /// La nota tiene la tabla del Viaje (aunque esté vacía).
    public let tieneViaje: Bool

    public static let seccionViaje = "Viaje"
    /// La tabla del Viaje: dentro de `## Viaje` y con la columna «Sesión».
    public static let tablaViaje = TableSelector(seccion: seccionViaje, columna: "Sesión")

    public init(ruta: VaultPath?, titulo: String?, estado: String?, sesiones: [SesionViaje], tareasCliente: [TareaDelCliente],
                documentos: [String], dudas: [String], tieneViaje: Bool) {
        self.ruta = ruta; self.titulo = titulo; self.estado = estado; self.sesiones = sesiones
        self.tareasCliente = tareasCliente; self.documentos = documentos; self.dudas = dudas; self.tieneViaje = tieneViaje
    }

    /// Lee la nota entera (propiedades y cuerpo). Las filas y líneas de guía o de plantilla («{{…}}», «> Guía…»)
    /// no cuentan.
    public static func leer(_ texto: String, ruta: VaultPath? = nil) -> PortalDocumento {
        let doc = NoteDocument(text: texto)
        let fm = doc.frontmatter
        let filas = MarkdownTable.rows(in: texto, selector: tablaViaje)
        var sesiones: [SesionViaje] = []
        for f in filas ?? [] {
            let celda = valor(f, "Sesión") ?? ""
            guard !celda.isEmpty, !celda.contains("{{") else { continue }
            let (codigo, nombre) = partirSesion(celda)
            let estadoTexto = valor(f, "Estado")
            let fechaTexto = valor(f, "Fecha")
            sesiones.append(SesionViaje(codigo: codigo, nombre: nombre, celdaSesion: celda,
                                        estado: estadoTexto.flatMap(EstadoSesion.init(leyendo:)), estadoTexto: estadoTexto,
                                        fecha: fechaTexto.flatMap { LocalDate(parsing: String($0.prefix(10))) }, fechaTexto: fechaTexto,
                                        resumen: valor(f, "Resumen para el cliente") ?? valor(f, "Resumen"),
                                        notaInterna: valor(f, "Nota interna")))
        }
        let cuerpo = doc.body
        let tareas = lineas(MarkdownSections.content(of: "Tareas del cliente", in: cuerpo)).enumerated().compactMap { i, l in
            tareaCliente(l, linea: i)
        }
        let documentos = lineas(MarkdownSections.content(of: "Documentos", in: cuerpo)).map(sinVineta)
        let dudas = lineas(MarkdownSections.content(of: "Dudas y problemas", in: cuerpo)).map(sinVineta)
        let titulo = NoteDocument.firstHeading(in: cuerpo).flatMap { $0.contains("{{") ? nil : $0 }
        return PortalDocumento(ruta: ruta, titulo: titulo, estado: fm.text("estado"), sesiones: sesiones, tareasCliente: tareas,
                               documentos: documentos, dudas: dudas, tieneViaje: filas != nil)
    }

    /// Sesiones hechas.
    public var hechas: Int { sesiones.filter { $0.estado == .hecha }.count }
    /// Sesiones que entran en el servicio (todas menos «No incluida»).
    public var incluidas: Int { sesiones.filter { $0.estado != .noIncluida }.count }

    /// La próxima sesión que toca: la primera agendada desde hoy que no está hecha; si no, la primera pendiente.
    public func proxima(hoy: LocalDate) -> SesionViaje? {
        let abiertas = sesiones.filter { $0.estado != .hecha && $0.estado != .noIncluida }
        if let agendada = abiertas.filter({ ($0.fecha.map { $0 >= hoy } ?? false) }).min(by: { $0.fecha! < $1.fecha! }) {
            return agendada
        }
        return abiertas.first
    }

    /// El comando que cambia el estado de una sesión (solo esa celda de su fila).
    public func comandoEstado(_ sesion: SesionViaje, a nuevo: EstadoSesion) -> CommandBus.Comando? {
        guard let ruta else { return nil }
        return .cambiarCeldas(ruta, tabla: Self.tablaViaje, columnaClave: "Sesión", valorClave: sesion.celdaSesion,
                              celdas: ["Estado": nuevo.rawValue])
    }

    // MARK: Lectura

    static func valor(_ fila: [String: String], _ columna: String) -> String? {
        let clave = TextFolding.fold(columna)
        guard let v = fila.first(where: { TextFolding.fold($0.key) == clave })?.value.trimmingCharacters(in: .whitespaces),
              !v.isEmpty, v != "—", v != "-" else { return nil }
        return v
    }

    /// «S3 · Revisión de gastos» → («S3», «Revisión de gastos»).
    static func partirSesion(_ celda: String) -> (String, String?) {
        let partes = celda.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        let primera = partes.first ?? celda
        if let r = primera.range(of: #"^[Ss]\d+"#, options: .regularExpression) {
            let codigo = "S" + primera[r].dropFirst()
            var resto = String(primera[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " :-–"))
            if partes.count > 1 { resto = ([resto] + partes.dropFirst()).filter { !$0.isEmpty }.joined(separator: " · ") }
            return (codigo, resto.isEmpty ? nil : resto)
        }
        return (celda, nil)
    }

    /// Líneas con texto de una sección, sin guías («> …»), comentarios ni plantillas.
    static func lineas(_ seccion: String?) -> [String] {
        guard let seccion else { return [] }
        return seccion.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { l in
            !l.isEmpty && !l.hasPrefix(">") && !l.hasPrefix("<!--") && !l.contains("{{")
        }
    }

    static func sinVineta(_ l: String) -> String {
        for p in ["- ", "* ", "+ "] where l.hasPrefix(p) { return String(l.dropFirst(p.count)) }
        return l
    }

    static func tareaCliente(_ l: String, linea: Int) -> TareaDelCliente? {
        let marcas: [(String, Bool)] = [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false), ("* [x] ", true)]
        guard let marca = marcas.first(where: { l.hasPrefix($0.0) }) else { return nil }
        let hecha = marca.1
        let partes = l.dropFirst(marca.0.count).components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        var texto: [String] = []
        var sesion: String?
        var vence: LocalDate?
        for p in partes where !p.isEmpty {
            if p.range(of: #"^[Ss]\d+$"#, options: .regularExpression) != nil { sesion = p.uppercased(); continue }
            let f = TextFolding.fold(p)
            if f.hasPrefix("vence "), let d = LocalDate(parsing: String(p.dropFirst(6)).trimmingCharacters(in: .whitespaces)) {
                vence = d; continue
            }
            texto.append(p)
        }
        guard !texto.isEmpty else { return nil }
        return TareaDelCliente(linea: linea, texto: texto.joined(separator: " · "), hecha: hecha, sesion: sesion, vence: vence)
    }
}

/// Lo que ve el cliente en su portal: su viaje, lo que necesitamos de él, sus documentos y sus dudas o problemas.
/// **No tiene** notas internas, responsable, resolución, correos ni kit (criterio F2-8).
public struct PortalCliente: Sendable, Hashable {
    public struct Sesion: Sendable, Hashable, Identifiable {
        public var id: String { codigo }
        public let codigo: String
        public let nombre: String?
        public let estado: EstadoSesion?
        public let fecha: LocalDate?
        public let resumen: String?

        public var titulo: String { nombre.map { "\(codigo) · \($0)" } ?? codigo }
    }

    /// Una incidencia como la ve el cliente: sin correo, responsable ni resolución.
    public struct Incidencia: Sendable, Hashable, Identifiable {
        public let id: String
        public let fecha: String?
        public let tipo: String?
        public let severidad: String?
        public let estado: String?
        public let descripcion: String?
    }

    public let titulo: String?
    public let sesiones: [Sesion]
    public let tareas: [TareaDelCliente]
    public let documentos: [String]
    public let dudas: [String]
    public let incidencias: [Incidencia]

    public init(portal: PortalDocumento, incidencias: [IncidenciaRegistrada] = []) {
        titulo = portal.titulo.map(Self.limpiar)
        sesiones = portal.sesiones.compactMap { s in
            let nombre = s.nombre.map(Self.limpiar)
            return Sesion(codigo: s.codigo, nombre: nombre?.isEmpty == true ? nil : nombre, estado: s.estado?.paraCliente,
                          fecha: s.fecha, resumen: s.resumen.map(Self.limpiar).flatMap { $0.isEmpty ? nil : $0 })
        }
        tareas = portal.tareasCliente.compactMap { t in
            let texto = Self.limpiar(t.texto)
            return texto.isEmpty ? nil : TareaDelCliente(linea: t.linea, texto: texto, hecha: t.hecha, sesion: t.sesion, vence: t.vence)
        }
        documentos = portal.documentos.filter { !Self.hablaDelKit($0) }.map(Self.limpiar).filter { !$0.isEmpty }
        dudas = portal.dudas.map(Self.limpiar).filter { !$0.isEmpty }
        self.incidencias = incidencias.map { i in
            Incidencia(id: i.id, fecha: i.fechaTexto, tipo: i.tipo, severidad: i.severidad?.rawValue ?? i.severidadTexto,
                       estado: i.estado?.rawValue ?? i.estadoTexto,
                       descripcion: i.descripcion.map(Self.limpiar).flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    /// Todo el texto que se pinta en la vista del cliente (para comprobar qué no lleva).
    public var textoCompleto: String {
        var t: [String] = [titulo ?? ""]
        for s in sesiones { t += [s.titulo, s.estado?.rawValue ?? "", s.fecha?.description ?? "", s.resumen ?? ""] }
        t += tareas.map(\.texto) + documentos + dudas
        for i in incidencias { t += [i.id, i.fecha ?? "", i.tipo ?? "", i.severidad ?? "", i.estado ?? "", i.descripcion ?? ""] }
        return t.joined(separator: "\n")
    }

    static let correo = try! NSRegularExpression(pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: [.caseInsensitive])
    static let kit = try! NSRegularExpression(pattern: #"\bkits?\b"#, options: [.caseInsensitive])

    /// ¿Menciona el kit de sesión? (es material nuestro).
    public static func hablaDelKit(_ s: String) -> Bool {
        kit.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Quita los correos y las frases que hablan del kit; deja el resto tal cual.
    public static func limpiar(_ s: String) -> String {
        var t = correo.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        if hablaDelKit(t) {
            let frases = t.components(separatedBy: ". ").filter { !hablaDelKit($0) }
            t = frases.joined(separator: ". ")
            if hablaDelKit(t) { t = kit.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "") }
        }
        // Lo que quede de quitar: paréntesis vacíos, «a », dobles espacios.
        for (de, a) in [("()", ""), ("( )", ""), ("<>", ""), ("  ", " "), (" ,", ","), (" .", ".")] {
            while t.contains(de) { t = t.replacingOccurrences(of: de, with: a) }
        }
        return t.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "·:,;")))
    }
}
