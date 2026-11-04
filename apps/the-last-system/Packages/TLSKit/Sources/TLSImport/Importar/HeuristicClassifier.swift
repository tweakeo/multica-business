import Foundation
import TLSCore

/// Un sitio de la estructura v2 adonde puede ir un fichero (SISTEMAS.md §1.2). Lo que propone la IA es siempre una
/// de estas claves: la ruta la calcula la app, nunca la escribe el modelo.
public struct ColeccionV2: Sendable, Hashable, Codable, Identifiable {
    public enum Forma: String, Sendable, Hashable, Codable {
        /// Las fichas van sueltas en la carpeta (`Contactos/ana-lopez.md`).
        case plana
        /// Se conserva la estructura de carpetas de debajo de la pista (`Recursos/Fotos/…`).
        case conSubcarpetas
        /// `Fiscal/AAAA/Tn/<apartado>` según la fecha del documento.
        case fiscal
        /// `Proyectos/<proyecto>/Materiales/…`; la nota del proyecto es `Proyectos/<proyecto>/Proyecto.md`.
        case proyecto
    }

    public let clave: String
    public let area: AreaCode?
    /// Nombre para la persona («Ventas › Contactos»).
    public let nombre: String
    /// Plantilla de carpeta (`{ventas}/Contactos`, `Buzón/Por ordenar`).
    public let carpeta: String
    /// `tls_type` que toma una nota que llega aquí (las demás notas y los ficheros no se adoptan).
    public let tipoFicha: String?
    public let forma: Forma
    /// Para la IA: qué va aquí.
    public let descripcion: String

    public var id: String { clave }

    public static let catalogo: [ColeccionV2] = [
        .init(clave: "direccion.recursos", area: .direccion, nombre: "Dirección › Recursos", carpeta: "{direccion}/Recursos",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Plan de empresa, estrategia, documentos generales de dirección"),
        .init(clave: "direccion.contratos", area: .direccion, nombre: "Dirección › Contratos", carpeta: "{direccion}/Contratos",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Contratos firmados, acuerdos y modelos de contrato"),
        .init(clave: "direccion.decisiones", area: .direccion, nombre: "Dirección › Decisiones", carpeta: "{direccion}/Decisiones",
              tipoFicha: "decision", forma: .plana, descripcion: "Notas de decisiones importantes"),
        .init(clave: "direccion.objetivos", area: .direccion, nombre: "Dirección › Objetivos", carpeta: "{direccion}/Objetivos",
              tipoFicha: "objective", forma: .plana, descripcion: "Objetivos del trimestre o del año"),
        .init(clave: "direccion.reuniones", area: .direccion, nombre: "Dirección › Reuniones", carpeta: "{direccion}/Reuniones",
              tipoFicha: "meeting", forma: .plana, descripcion: "Actas y notas de reuniones"),
        .init(clave: "ventas.contactos", area: .ventas, nombre: "Ventas › Contactos", carpeta: "{ventas}/Contactos",
              tipoFicha: "contact", forma: .plana, descripcion: "Fichas de personas: clientes, interesados, proveedores"),
        .init(clave: "ventas.empresas", area: .ventas, nombre: "Ventas › Empresas", carpeta: "{ventas}/Empresas",
              tipoFicha: "organization", forma: .plana, descripcion: "Fichas de empresas: clientes, proveedores, colaboradores"),
        .init(clave: "ventas.oportunidades", area: .ventas, nombre: "Ventas › Oportunidades", carpeta: "{ventas}/Oportunidades",
              tipoFicha: "opportunity", forma: .conSubcarpetas, descripcion: "Oportunidades de venta, propuestas y presupuestos a clientes"),
        .init(clave: "ventas.productos", area: .ventas, nombre: "Ventas › Productos", carpeta: "{ventas}/Productos",
              tipoFicha: "service", forma: .plana, descripcion: "Servicios y productos que se venden, catálogo y tarifas"),
        .init(clave: "ventas.recursos", area: .ventas, nombre: "Ventas › Recursos", carpeta: "{ventas}/Recursos",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Dossieres, plantillas de propuesta, argumentarios"),
        .init(clave: "entrega.proyectos", area: .entrega, nombre: "Entrega › Proyectos", carpeta: "{entrega}/Proyectos",
              tipoFicha: "project", forma: .proyecto, descripcion: "Proyectos y encargos de clientes con sus materiales"),
        .init(clave: "entrega.planes", area: .entrega, nombre: "Entrega › Planes de entrega", carpeta: "{entrega}/Planes de entrega",
              tipoFicha: "delivery_template", forma: .plana, descripcion: "Cómo se entrega cada servicio: fases y pasos"),
        .init(clave: "entrega.recursos", area: .entrega, nombre: "Entrega › Recursos", carpeta: "{entrega}/Recursos",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Materiales de sesiones, talleres y formación"),
        .init(clave: "finanzas.ingresos", area: .finanzas, nombre: "Finanzas › Facturas emitidas", carpeta: "{finanzas}/Fiscal",
              tipoFicha: nil, forma: .fiscal, descripcion: "Facturas que la empresa emite a sus clientes"),
        .init(clave: "finanzas.gastos", area: .finanzas, nombre: "Finanzas › Gastos", carpeta: "{finanzas}/Fiscal",
              tipoFicha: nil, forma: .fiscal, descripcion: "Facturas recibidas, tickets y recibos de gastos"),
        .init(clave: "finanzas.modelos", area: .finanzas, nombre: "Finanzas › Impuestos", carpeta: "{finanzas}/Fiscal",
              tipoFicha: nil, forma: .fiscal, descripcion: "Modelos de impuestos y documentos de Hacienda"),
        .init(clave: "finanzas.bancos", area: .finanzas, nombre: "Finanzas › Extractos del banco", carpeta: "{finanzas}/Registros/importar",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Extractos y movimientos del banco"),
        .init(clave: "finanzas.gestoria", area: .finanzas, nombre: "Finanzas › Gestoría", carpeta: "{finanzas}/Gestoría",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Lo que prepara o pide la gestoría: libros, nóminas, consultas"),
        .init(clave: "finanzas.tramites", area: .finanzas, nombre: "Finanzas › Trámites", carpeta: "{finanzas}/Trámites",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Alta, Seguridad Social, certificados y otros trámites"),
        .init(clave: "marca.recursos", area: .marca, nombre: "Marca › Recursos", carpeta: "{marca}/Recursos",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Logos, fotos, manual de marca, web"),
        .init(clave: "marca.contenidos", area: .marca, nombre: "Marca › Contenidos", carpeta: "{marca}/Contenidos",
              tipoFicha: "content", forma: .plana, descripcion: "Publicaciones, artículos, boletines, vídeos"),
        .init(clave: "marca.conversaciones", area: .marca, nombre: "Marca › Conversaciones", carpeta: "{marca}/Conversaciones",
              tipoFicha: "conversation", forma: .plana, descripcion: "Conversaciones con el público que se atribuyen a una pieza"),
        .init(clave: "equipo.roles", area: .equipo, nombre: "Equipo › Roles", carpeta: "{equipo}/Roles",
              tipoFicha: "role", forma: .plana, descripcion: "Puestos y funciones de cada persona"),
        .init(clave: "equipo.colaboraciones", area: .equipo, nombre: "Equipo › Colaboraciones", carpeta: "{equipo}/Colaboraciones",
              tipoFicha: "collaboration", forma: .plana, descripcion: "Acuerdos con colaboradores externos"),
        .init(clave: "equipo.recursos", area: .equipo, nombre: "Equipo › Recursos", carpeta: "{equipo}/Recursos",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Selección, vacaciones y documentos del equipo"),
        .init(clave: "buzon.correo", area: nil, nombre: "Buzón › Correo importado", carpeta: "{buzon}/Correo importado",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Correos exportados"),
        .init(clave: "buzon.porOrdenar", area: nil, nombre: "Buzón › Por ordenar", carpeta: "{buzon}/Por ordenar",
              tipoFicha: nil, forma: .conSubcarpetas, descripcion: "Lo que no se sabe dónde va: queda para ordenarlo más tarde"),
    ]

    public static func porClave(_ clave: String) -> ColeccionV2? { catalogo.first { $0.clave == clave } }

    /// Colección de un `tls_type` (o de un `tipo:` heredado ya traducido).
    static let porTipo: [String: String] = [
        "contact": "ventas.contactos", "organization": "ventas.empresas", "opportunity": "ventas.oportunidades",
        "service": "ventas.productos", "offer": "ventas.productos", "project": "entrega.proyectos",
        "delivery_template": "entrega.planes", "meeting": "direccion.reuniones", "decision": "direccion.decisiones",
        "objective": "direccion.objetivos", "content": "marca.contenidos", "conversation": "marca.conversaciones",
        "role": "equipo.roles", "collaboration": "equipo.colaboraciones", "invoice": "finanzas.ingresos",
        "receipt": "finanzas.ingresos", "proposal": "ventas.oportunidades", "quote": "ventas.oportunidades",
        "agreement": "direccion.contratos",
    ]

    /// `tipo:` de las carpetas antiguas (G1/G2, Notion) → `tls_type`.
    static let tiposHeredados: [String: String] = [
        "persona": "contact", "contacto": "contact", "empresa": "organization", "organizacion": "organization",
        "cliente": "organization", "oportunidad": "opportunity", "proyecto": "project", "reunion": "meeting",
        "acta": "meeting", "decision": "decision", "objetivo": "objective", "contenido": "content", "post": "content",
        "rol": "role", "servicio": "service", "producto": "service", "colaboracion": "collaboration",
        "factura": "invoice", "propuesta": "proposal", "presupuesto": "quote", "contrato": "agreement",
    ]
}

/// Adónde propone llevar un fichero el clasificador (o la IA, o la persona).
public struct PropuestaDestino: Sendable, Hashable, Codable {
    public enum Origen: String, Sendable, Hashable, Codable { case reglas, ia, persona }

    /// Clave de `ColeccionV2` (`nil` si se queda donde está).
    public var coleccion: String?
    public var area: AreaCode?
    /// Ruta propuesta en la carpeta de la empresa (`nil` si no se mueve).
    public var destino: VaultPath?
    /// `tls_type` si es una nota que pasa a ser ficha.
    public var tipoFicha: String?
    /// Entre 0 y 1.
    public var confianza: Double
    /// Por qué, en castellano y sin jerga («Se llama «Factura…» y es de 2025»).
    public var motivo: String
    public var origen: Origen
    /// Ya está en su sitio (solo en la carpeta de la empresa).
    public var enSuSitio: Bool

    public init(coleccion: String?, area: AreaCode?, destino: VaultPath?, tipoFicha: String?, confianza: Double,
                motivo: String, origen: Origen = .reglas, enSuSitio: Bool = false) {
        self.coleccion = coleccion; self.area = area; self.destino = destino; self.tipoFicha = tipoFicha
        self.confianza = min(1, max(0, confianza)); self.motivo = motivo; self.origen = origen; self.enSuSitio = enSuSitio
    }
}

/// Clasificador por reglas (sin IA): ruta, nombre, extensión, propiedades y el texto que ya está en el Mac.
///
/// Siempre da una propuesta con su confianza y su motivo. Lo que no tiene pistas va al Buzón («Por ordenar»), con
/// confianza baja: así nada se pierde y la persona lo ve.
public struct HeuristicClassifier: Sendable {
    /// Estructura de la carpeta de destino (las carpetas de área reales).
    public let layout: VaultLayout
    public let hoy: LocalDate
    let dater: DocumentDater

    public init(layout: VaultLayout = .humana, hoy: LocalDate) {
        self.layout = layout
        self.hoy = hoy
        self.dater = DocumentDater(opciones: .init(hoy: hoy, ocr: nil))
    }

    // MARK: Reglas

    /// Lo que suma una colección.
    struct Puntos {
        enum Donde { case nombre, carpeta, texto, `extension` }
        var total = 0.0
        var mejor = 0.0
        var n = 0
        var pista: String
        var donde: Donde
        var indice: Int?
    }

    struct Regla: Sendable {
        let patron: NSRegularExpression
        let coleccion: String
        let peso: Double
        let pista: String
    }

    private static func r(_ palabras: String, _ coleccion: String, _ peso: Double, _ pista: String) -> Regla {
        Regla(patron: try! NSRegularExpression(pattern: #"(?<![a-z0-9])(?:"# + palabras + #")(?![a-z0-9])"#),
              coleccion: coleccion, peso: peso, pista: pista)
    }

    /// Palabras (ya sin tildes ni mayúsculas) que señalan una colección. El orden no importa: se suman.
    static let reglas: [Regla] = [
        r(#"modelo[ _-]?(?:303|111|115|130|131|190|180|347|349|390|036|037|100|200)|mod[ _-]?(?:303|111|130|390|347)|aeat|agencia tributaria|hacienda|declaracion de la renta|impuesto de sociedades"#,
          "finanzas.modelos", 0.8, "impuestos"),
        r(#"facturas? emitidas?|emitidas|ventas facturadas|facturacion a clientes|ingresos"#, "finanzas.ingresos", 0.75, "facturas emitidas"),
        r(#"facturas? recibidas?|recibidas|gastos|tickets?|recibos?|compras|proveedor(?:es)?"#, "finanzas.gastos", 0.7, "gastos"),
        r(#"facturas?|fra|invoices?|billing"#, "finanzas.gastos", 0.65, "factura"),
        r(#"extractos?|movimientos bancarios|movimientos|banco|bancos|cuenta corriente|iban|bbva|santander|caixabank|sabadell|bankinter|openbank|revolut|n26"#,
          "finanzas.bancos", 0.7, "banco"),
        r(#"gestoria|gestor|asesoria fiscal|asesor fiscal|contabilidad|libro diario|libro mayor|balance|cuenta de resultados|nominas?"#,
          "finanzas.gestoria", 0.7, "gestoría"),
        r(#"seguridad social|tgss|reta|alta censal|autonomos?|certificado digital|tramites?|licencias?|ayuntamiento"#,
          "finanzas.tramites", 0.65, "trámites"),
        r(#"propuestas?|presupuestos?|cotizacion(?:es)?|quotes?|proposals?|ofertas? comerciales?"#, "ventas.oportunidades", 0.7, "propuestas"),
        r(#"oportunidad(?:es)?|pipeline|embudo|crm|deals?|ventas"#, "ventas.oportunidades", 0.6, "ventas"),
        r(#"contactos?|personas|people|leads?|agenda"#, "ventas.contactos", 0.65, "contactos"),
        r(#"empresas|clientes?|organizaciones|companies|cuentas de clientes"#, "ventas.empresas", 0.55, "clientes"),
        r(#"productos?|servicios?|catalogo|tarifas?|precios|oferta"#, "ventas.productos", 0.55, "servicios"),
        r(#"dossier|metodologia|argumentario|objeciones|guion de venta|plantillas? de propuesta"#, "ventas.recursos", 0.7, "material de venta"),
        r(#"proyectos?|projects?|encargos?|entregables?|trabajos? de clientes?"#, "entrega.proyectos", 0.65, "proyectos"),
        r(#"planes? de entrega|procedimientos? de entrega|checklist de entrega|onboarding de clientes?"#, "entrega.planes", 0.75, "planes de entrega"),
        r(#"sesion(?:es)?|talleres?|formacion|cursos?|materiales"#, "entrega.recursos", 0.5, "sesiones y formación"),
        r(#"contratos?|acuerdos?|nda|convenios?|contracts?"#, "direccion.contratos", 0.7, "contratos"),
        r(#"actas?|reunion(?:es)?|meetings?|minutes"#, "direccion.reuniones", 0.65, "reuniones"),
        r(#"estrategia|plan de empresa|plan de negocio|business plan|vision|mision|direccion"#, "direccion.recursos", 0.6, "dirección"),
        r(#"objetivos?|okrs?|metas"#, "direccion.objetivos", 0.6, "objetivos"),
        r(#"decision(?:es)?"#, "direccion.decisiones", 0.6, "decisiones"),
        r(#"logos?|logotipos?|marca|branding|brand|identidad|tipografias?|paleta|manual de marca|fotos?|fotografias?|imagenes|web|landing"#,
          "marca.recursos", 0.6, "marca"),
        r(#"posts?|publicacion(?:es)?|instagram|linkedin|newsletter|boletin(?:es)?|blog|articulos?|contenidos?|youtube|podcast"#,
          "marca.contenidos", 0.65, "contenidos"),
        r(#"roles?|puestos?|organigrama|funciones"#, "equipo.roles", 0.6, "roles"),
        r(#"colaborador(?:es)?|colaboracion(?:es)?|freelances?|partners?"#, "equipo.colaboraciones", 0.65, "colaboraciones"),
        r(#"equipo|empleados?|vacaciones|contratacion|seleccion|curriculums?|cv|rrhh|recursos humanos"#, "equipo.recursos", 0.6, "equipo"),
        r(#"correos?|emails?|e-mails?|mail"#, "buzon.correo", 0.55, "correo"),
    ]

    /// Anuales (van a `Fiscal/AAAA/Modelos`): el resto de modelos son trimestrales.
    static let modelosAnuales = try! NSRegularExpression(pattern: #"(?<![0-9])(?:390|347|190|180|100|200|036|037)(?![0-9])"#)

    // MARK: Proponer

    /// Propuesta para un elemento. `clase` dice si está ya dentro de la carpeta de la empresa (puede estar en su sitio).
    public func proponer(_ e: ElementoInventario, clase: FuenteImportacion.Clase) -> PropuestaDestino {
        // 1. Lo que ya sigue la estructura se queda.
        if clase == .carpetaDeLaEmpresa, let p = enSuSitio(e) { return p }
        // 2. Las claves y contraseñas no se tocan (ni se mira dentro).
        if e.sensible {
            return PropuestaDestino(coleccion: nil, area: nil, destino: nil, tipoFicha: nil, confianza: 1,
                                    motivo: "Parece un fichero con claves o contraseñas: no lo toco")
        }
        // 3. Una nota que dice qué es.
        if e.tipo == .nota, let p = porPropiedades(e) { return p }
        // 4. Pistas en el nombre, en las carpetas y en el texto.
        var puntos: [String: Puntos] = [:]
        let nombre = TextFolding.fold(InventarioImportacion.sinIdNotion(e.ruta.stem)).replacingOccurrences(of: "_", with: " ")
        let carpetas = e.ruta.components.dropLast().map { TextFolding.fold(InventarioImportacion.sinIdNotion($0)) }
        let texto = TextFolding.fold(String((e.extracto ?? "").prefix(1_500)))
        func mirar(_ s: String, peso factor: Double, donde: Puntos.Donde, indice: Int?) {
            let ns = s as NSString
            for regla in Self.reglas where regla.patron.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil {
                let w = regla.peso * factor
                var x = puntos[regla.coleccion] ?? Puntos(pista: regla.pista, donde: donde, indice: indice)
                x.total += w
                x.n += 1
                if w > x.mejor { x.mejor = w; x.pista = regla.pista; x.donde = donde; x.indice = indice }
                puntos[regla.coleccion] = x
            }
        }
        mirar(nombre, peso: 1, donde: .nombre, indice: nil)
        for (i, c) in carpetas.enumerated() { mirar(c, peso: 0.92, donde: .carpeta, indice: i) }
        if !texto.isEmpty { mirar(texto, peso: 0.72, donde: .texto, indice: nil) }
        if e.tipo == .correo {
            var x = Puntos(pista: "correo", donde: .extension, indice: nil)
            x.total = 0.8; x.mejor = 0.8; x.n = 1
            puntos["buzon.correo"] = x
        }
        let orden = puntos.sorted { ($0.value.total, $0.key) > ($1.value.total, $1.key) }
        if let primero = orden.first {
            let mejor = primero.value
            var confianza = min(0.9, mejor.mejor + 0.05 * Double(mejor.n - 1))
            if orden.count > 1, orden[1].value.total >= mejor.total * 0.8 { confianza -= 0.15 }
            // Una factura con señales de ingreso gana a la de gasto.
            var col = primero.key
            if col == "finanzas.gastos", let ing = puntos["finanzas.ingresos"], ing.total >= mejor.total * 0.6 { col = "finanzas.ingresos" }
            let motivo: String
            switch mejor.donde {
            case .nombre: motivo = "El nombre habla de \(mejor.pista)"
            case .carpeta:
                let carpeta = InventarioImportacion.sinIdNotion(e.ruta.components[mejor.indice ?? 0])
                motivo = "Está en la carpeta «\(carpeta)» (\(mejor.pista))"
            case .texto: motivo = "El texto habla de \(mejor.pista)"
            case .extension: motivo = "Es un correo exportado"
            }
            return propuesta(e, coleccion: col, confianza: confianza, motivo: motivo, pistaEnCarpeta: mejor.indice)
        }
        // 5. Solo la extensión.
        if e.tipo == .imagen || e.tipo == .video {
            return propuesta(e, coleccion: "marca.recursos", confianza: 0.35,
                             motivo: "Es \(e.tipo == .imagen ? "una imagen" : "un vídeo") sin más pistas: lo llevo a Recursos de Marca",
                             pistaEnCarpeta: nil)
        }
        if clase == .carpetaDeLaEmpresa, e.ruta.isDescendant(of: VaultPath(layout.buzon ?? "Buzón")) {
            return PropuestaDestino(coleccion: nil, area: nil, destino: nil, tipoFicha: nil, confianza: 0.3,
                                    motivo: "Está en el Buzón y no sé dónde va: se queda ahí", enSuSitio: true)
        }
        return propuesta(e, coleccion: "buzon.porOrdenar", confianza: 0.2,
                         motivo: "No he encontrado pistas: lo dejo en el Buzón para que lo ordenes", pistaEnCarpeta: nil)
    }

    /// En la carpeta de la empresa: lo que ya está en un área, en el Buzón o en la raíz.
    func enSuSitio(_ e: ElementoInventario) -> PropuestaDestino? {
        let p = e.ruta
        let area = layout.area(of: p)
        let buzon = VaultPath(layout.buzon ?? "Buzón")
        let raiz = p.components.count == 1
        let enBuzonDeSistema = p.isDescendant(of: buzon) && p.components.count == 2
            && (["correspondencia"].contains(TextFolding.fold(p.stem)) || p.stem.hasPrefix("Correo ") || p.stem.hasPrefix("Informe de importación"))
        guard area != nil || raiz || enBuzonDeSistema else { return nil }
        var tipo: String?
        if e.tipo == .nota, let t = e.propiedades["tls_type"], !t.isEmpty { tipo = t }
        let motivo = area.map { "Ya está en \($0.nombre)" } ?? (raiz ? "Está en la raíz de la carpeta" : "Es del Buzón")
        return PropuestaDestino(coleccion: nil, area: area, destino: nil, tipoFicha: tipo, confianza: 0.95, motivo: motivo,
                                enSuSitio: true)
    }

    /// Una nota con `tls_type` o con un `tipo:` heredado conocido.
    func porPropiedades(_ e: ElementoInventario) -> PropuestaDestino? {
        if let t = e.propiedades["tls_type"], let col = ColeccionV2.porTipo[t] {
            return propuesta(e, coleccion: col, confianza: 0.95, motivo: "Sus propiedades dicen que es «\(Self.nombreDeTipo(t))»",
                             pistaEnCarpeta: nil, tipoFicha: t)
        }
        if let raw = e.propiedades["tipo"] ?? e.propiedades["type"] {
            let k = TextFolding.fold(raw).trimmingCharacters(in: .whitespaces)
            if let t = ColeccionV2.tiposHeredados[k], let col = ColeccionV2.porTipo[t] {
                return propuesta(e, coleccion: col, confianza: 0.85, motivo: "Sus propiedades dicen que es «\(raw)»",
                                 pistaEnCarpeta: nil, tipoFicha: t)
            }
        }
        return nil
    }

    static func nombreDeTipo(_ t: String) -> String {
        let nombres = ["contact": "contacto", "organization": "empresa", "opportunity": "oportunidad", "service": "servicio",
                       "offer": "oferta", "project": "proyecto", "delivery_template": "plan de entrega", "meeting": "reunión",
                       "decision": "decisión", "objective": "objetivo", "content": "contenido", "conversation": "conversación",
                       "role": "rol", "collaboration": "colaboración", "invoice": "factura", "receipt": "recibo",
                       "proposal": "propuesta", "quote": "presupuesto", "agreement": "contrato"]
        return nombres[t] ?? t
    }

    /// Propuesta con su ruta final, a partir de la colección.
    public func propuesta(_ e: ElementoInventario, coleccion clave: String, confianza: Double, motivo: String,
                          pistaEnCarpeta: Int?, tipoFicha forzado: String? = nil, origen: PropuestaDestino.Origen = .reglas)
        -> PropuestaDestino {
        guard let col = ColeccionV2.porClave(clave) else {
            return PropuestaDestino(coleccion: nil, area: nil, destino: nil, tipoFicha: nil, confianza: 0, motivo: motivo)
        }
        let esNota = e.tipo == .nota && !e.esPaquete
        let tipo = esNota ? (forzado ?? col.tipoFicha) : nil
        var motivoFinal = motivo
        let destino = ruta(e, col, tipo: tipo, pistaEnCarpeta: pistaEnCarpeta, motivo: &motivoFinal)
        return PropuestaDestino(coleccion: col.clave, area: col.area, destino: destino, tipoFicha: tipo,
                                confianza: confianza, motivo: motivoFinal, origen: origen)
    }

    /// Ruta final en la carpeta de la empresa (sin resolver choques: eso lo hace `ImportApplier`).
    func ruta(_ e: ElementoInventario, _ col: ColeccionV2, tipo: String?, pistaEnCarpeta: Int?, motivo: inout String) -> VaultPath {
        let base = expandir(col.carpeta)
        let limpio = e.nombreLimpio
        let carpetas = Array(e.ruta.components.dropLast()).map(InventarioImportacion.sinIdNotion)
        // Las fichas, en kebab (SISTEMAS §1.7); el nombre bonito queda en `aliases` al moverlas.
        let nombreFicha: String = {
            guard tipo != nil, e.tipo == .nota else { return limpio }
            let slug = NombresDeFicha.slug(VaultPath(limpio).stem)
            return slug.isEmpty ? limpio : slug + ".md"
        }()
        switch col.forma {
        case .plana:
            return base.appending(nombreFicha)
        case .conSubcarpetas:
            // Debajo de la carpeta que dio la pista (o del bloque).
            let desde = pistaEnCarpeta.map { $0 + 1 } ?? (carpetas.isEmpty ? 0 : 1)
            let sub = carpetas.count > desde ? Array(carpetas[desde...]) : []
            return VaultPath(components: base.components + sub + [tipo != nil ? nombreFicha : limpio])
        case .fiscal:
            let apartado: String
            switch col.clave {
            case "finanzas.ingresos": apartado = "Ingresos"
            case "finanzas.modelos": apartado = "Modelos"
            default: apartado = "Gastos"
            }
            guard let f = fechaFiscal(e), let ano = f.ano else {
                motivo += "; sin fecha: va a «Sin fecha» hasta que la sepamos"
                return VaultPath(components: base.components + ["Sin fecha", apartado, limpio])
            }
            let anual = col.clave == "finanzas.modelos" && Self.modelosAnuales.firstMatch(
                in: e.ruta.name, range: NSRange(location: 0, length: (e.ruta.name as NSString).length)) != nil
            motivo += f.fuente == .nombre ? "; la fecha sale del nombre" : "; la fecha sale del documento"
            guard !anual, let mes = f.mes else { return VaultPath(components: base.components + [String(ano), apartado, limpio]) }
            return VaultPath(components: base.components + [String(ano), FormatoFechaImportacion.trimestre(mes), apartado, limpio])
        case .proyecto:
            // La carpeta del proyecto es la que dio la pista o la de después («Proyectos/Panadería Sol/…»).
            var i = pistaEnCarpeta ?? (carpetas.isEmpty ? -1 : 0)
            if i >= 0, i < carpetas.count, Self.esPalabraGenerica(carpetas[i]), i + 1 < carpetas.count { i += 1 }
            let nombreProyecto = i >= 0 && i < carpetas.count ? carpetas[i] : VaultPath(limpio).stem
            let slug = NombresDeFicha.slug(nombreProyecto).isEmpty ? "proyecto" : NombresDeFicha.slug(nombreProyecto)
            let carpetaProyecto = base.appending(slug)
            if tipo == "project" { return carpetaProyecto.appending("Proyecto.md") }
            let sub = i + 1 < carpetas.count ? Array(carpetas[(i + 1)...]) : []
            return VaultPath(components: carpetaProyecto.components + ["Materiales"] + sub + [limpio])
        }
    }

    /// «Proyectos», «Clientes»…: nombres de colección, no de un proyecto concreto.
    static func esPalabraGenerica(_ s: String) -> Bool {
        ["proyectos", "projects", "clientes", "encargos", "trabajos", "entregables"].contains(TextFolding.fold(s))
    }

    /// Fecha para el año y el trimestre: la del nombre o la que lleva etiqueta en el texto.
    func fechaFiscal(_ e: ElementoInventario) -> FechaDocumento? {
        if let f = e.fechaEnNombre { return FechaDocumento(fecha: f, fuente: .nombre) }
        if let t = e.extracto, let f = dater.fechaConEtiqueta(t) ?? dater.fechas(en: t).first?.fecha {
            return FechaDocumento(fecha: f, fuente: .documento)
        }
        return nil
    }

    func expandir(_ plantilla: String) -> VaultPath {
        layout.expand(plantilla.replacingOccurrences(of: "{buzon}", with: layout.buzon ?? "Buzón"))
    }
}
