import Foundation
import TLSCore

/// ¿Parece personal o de salud? Una tarea así sale **desmarcada** en la vista previa y, si la persona la marca, va
/// a la carpeta privada que elija. Palabras sueltas, sin tildes ni mayúsculas, salvo «IT» (baja por incapacidad
/// temporal), que solo cuenta en mayúsculas para no confundirla con otras palabras.
public enum ClasificadorPersonal {
    /// Palabras (ya plegadas: sin tildes, en minúsculas).
    public static let palabras: [String] = [
        "salud", "medico", "medica", "medicos", "medicas", "medicina", "medicacion", "medicamento", "medicamentos",
        "pastilla", "pastillas", "baja", "fremap", "mutua", "incapacidad", "hospital", "urgencias", "dentista",
        "fisio", "fisioterapia", "farmacia", "receta", "analitica", "analiticas", "psicologo", "psicologa", "terapia",
        "iphone", "airpods", "personal", "personales",
        // Salud corriente (revisión adversarial de F3): también lo dudoso sale desmarcado; la persona decide.
        "clinica", "clinicas", "vacuna", "vacunas", "vacunacion", "gripe", "sangre", "orina", "preoperatorio",
        "postoperatorio", "quirofano", "cirugia", "cirujano", "cirujana", "ambulatorio", "enfermera", "enfermero",
        "pediatra", "psiquiatra", "oculista", "lentillas", "radiografia", "resonancia", "ecografia",
        "mamografia", "citologia", "embarazo", "ginecologia", "traumatologia", "dermatologia", "cardiologia",
        "oftalmologia", "odontologia", "urologia", "neurologia", "oncologia", "pediatria", "psiquiatria",
        "nutricionista", "gimnasio", "dieta",
    ]
    /// Terminaciones de especialistas («ginecólogo», «traumatóloga»…), ya plegadas.
    public static let terminaciones: [String] = ["ologo", "ologa", "ologos", "ologas"]
    /// Palabras que acaban así y no son de salud.
    static let noEspecialistas: Set<String> = ["tecnologo", "tecnologa", "tecnologos", "tecnologas", "catalogo", "catalogos",
                                                 "dialogo", "dialogos", "monologo", "prologo", "epilogo", "homologo", "homologa"]
    /// Expresiones de varias palabras.
    public static let expresiones: [String] = ["cita medica", "apple watch", "seguridad social", "analisis de sangre",
                                               "analisis clinico", "analisis clinicos", "centro de salud"]
    /// Siglas que solo cuentan escritas así.
    public static let siglas: [String] = ["IT"]

    /// La palabra que la delata (tal como se busca), o `nil` si no parece personal.
    public static func motivo(_ textos: String?...) -> String? {
        let texto = textos.compactMap { $0 }.joined(separator: " \n ")
        let originales = fichas(texto)
        if let s = siglas.first(where: { originales.contains($0) }) { return s }
        let plegadas = fichas(TextFolding.fold(texto))
        for (i, f) in plegadas.enumerated() where palabras.contains(f) {
            // «prioridad baja» no es una baja médica. privacidad:permitir
            if f == "baja", i > 0, plegadas[i - 1] == "prioridad" { continue }
            return f
        }
        if let f = plegadas.first(where: { f in f.count > 6 && !noEspecialistas.contains(f) && terminaciones.contains { f.hasSuffix($0) } }) {
            return f
        }
        let frase = " " + plegadas.joined(separator: " ") + " "
        return expresiones.first { frase.contains(" \($0) ") }
    }

    /// Palabras de un texto (letras y cifras seguidas).
    static func fichas(_ s: String) -> [String] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

/// Área sugerida por las palabras del título y la descripción. La persona la puede cambiar en la vista previa.
public enum SugerenciaArea {
    /// Raíces (plegadas) por área. Cuenta la que más coincide; si nada coincide, Dirección.
    public static let raices: [AreaCode: [String]] = [
        .direccion: ["objetivo", "estrategi", "decision", "decidir", "diagnostic", "okr", "meta", "rumbo", "prioridad"],
        .ventas: ["cliente", "venta", "propuesta", "presupuesto", "oferta", "lead", "crm", "oportunidad", "comercial",
                  "prospect", "llamada", "seguimiento"],
        .entrega: ["proyecto", "entrega", "entregar", "implementa", "onboarding", "encargo", "renta", "servicio"],
        .finanzas: ["factura", "facturar", "cobro", "cobrar", "pago", "pagar", "banco", "impuesto", "iva", "irpf",
                    "gestoria", "contab", "hacienda", "nomina", "gasto", "tesoreria", "303", "130", "111"],
        .marca: ["contenido", "web", "linkedin", "instagram", "publica", "post", "marca", "logo", "newsletter", "blog",
                 "video", "youtube", "seo", "redes"],
        .equipo: ["contrat", "rol", "asistente", "agente", "proceso", "sistema", "formacion", "equipo", "delega",
                  "automatiz", "manual"],
    ]

    public static func para(titulo: String, descripcion: String?) -> AreaCode {
        // El título pesa el doble que la descripción.
        let deTitulo = ClasificadorPersonal.fichas(TextFolding.fold(titulo))
        let deTexto = ClasificadorPersonal.fichas(TextFolding.fold(descripcion ?? ""))
        var mejor: (area: AreaCode, puntos: Int) = (.direccion, 0)
        for area in AreaCode.allCases {
            let r = raices[area] ?? []
            let p = deTitulo.filter { f in r.contains { f.hasPrefix($0) } }.count * 2
                + deTexto.filter { f in r.contains { f.hasPrefix($0) } }.count
            if p > mejor.puntos { mejor = (area, p) }
        }
        return mejor.area
    }
}

/// Una tarea de Multica en la vista previa, con lo que se haría con ella.
public struct CandidataMultica: Sendable, Hashable, Identifiable {
    public let tarea: TareaMultica
    /// La palabra por la que parece personal o de salud (`nil` si no lo parece).
    public let personal: String?
    /// La ficha que ya la trae (de una importación anterior): no se vuelve a crear.
    public let yaImportada: VaultPath?
    /// Se importó y ahora está en el Archivo (la retiraste o se deshizo la importación): sale desmarcada; márcala solo
    /// si la quieres de vuelta.
    public var enArchivo: VaultPath? = nil
    public let areaSugerida: AreaCode
    /// Lo que la persona decide: si se importa y a qué área va.
    public var marcada: Bool
    public var area: AreaCode

    public var id: String { tarea.identificador }
    public var estado: EstadoTarea { tarea.estadoFicha }
    public var prioridad: String? { tarea.prioridadFicha }
    public var vence: LocalDate? { tarea.vence }
    public var parecePersonal: Bool { personal != nil }
    public var sePuedeMarcar: Bool { yaImportada == nil }

    /// La nota que acompaña a la fila.
    public var nota: String? {
        if yaImportada != nil { return "Ya la importaste antes: la tienes en Tareas" }
        if enArchivo != nil { return "Ya la importaste y está en el Archivo: márcala solo si la quieres de vuelta" }
        if parecePersonal {
            return "Parece personal: no se importa salvo que la marques; si la marcas, va a la carpeta privada que elijas"
        }
        if tarea.estadoDesconocido, let e = tarea.estado {
            return "No sé qué quiere decir su estado («\(e)»): márcala solo si sigue pendiente"
        }
        return nil
    }
}

/// La vista previa: nada se escribe hasta «Aplicar».
public struct PreviaMultica: Sendable {
    public var candidatas: [CandidataMultica]
    /// Lo anterior a esta fecha entra como antecedente (`fecha_corte`): no reactiva nada.
    public let fechaCorte: LocalDate

    public var marcadas: [CandidataMultica] { candidatas.filter { $0.marcada && $0.sePuedeMarcar } }
    public var personalesMarcadas: [CandidataMultica] { marcadas.filter(\.parecePersonal) }

    /// «12 tareas abiertas · 9 para importar · 2 parecen personales · 1 ya importada».
    public var resumen: String {
        var partes = [Self.cuenta(candidatas.count, "tarea abierta", "tareas abiertas"),
                      Self.cuenta(marcadas.count, "para importar", "para importar")]
        let personales = candidatas.filter { $0.parecePersonal && $0.sePuedeMarcar }.count
        if personales > 0 { partes.append(Self.cuenta(personales, "parece personal", "parecen personales")) }
        let ya = candidatas.filter { !$0.sePuedeMarcar }.count
        if ya > 0 { partes.append(Self.cuenta(ya, "ya importada", "ya importadas")) }
        return partes.joined(separator: " · ")
    }

    static func cuenta(_ n: Int, _ uno: String, _ varios: String) -> String { n == 1 ? "1 \(uno)" : "\(n) \(varios)" }

    /// Marca o desmarca una (las ya importadas no se pueden marcar).
    public mutating func marcar(_ id: String, _ si: Bool) {
        guard let i = candidatas.firstIndex(where: { $0.id == id }), candidatas[i].sePuedeMarcar else { return }
        candidatas[i].marcada = si
    }

    public mutating func cambiarArea(_ id: String, _ area: AreaCode) {
        guard let i = candidatas.firstIndex(where: { $0.id == id }) else { return }
        candidatas[i].area = area
    }

    /// Todas las marcadas (o todas las que no parecen personales) a un área.
    public mutating func todasA(_ area: AreaCode) {
        for i in candidatas.indices where !candidatas[i].parecePersonal { candidatas[i].area = area }
    }
}

/// Lo que se va a escribir al aplicar: un solo plan (todo o nada, un solo Deshacer).
public struct PlanImportacionMultica: Sendable {
    public struct Ficha: Sendable, Hashable {
        public let identificador: String
        public let ruta: VaultPath
        /// Va a la carpeta privada elegida.
        public let privada: Bool
    }

    public let plan: WritePlan
    public let fichas: [Ficha]

    /// «Crear 9 fichas de tarea (2 en tu carpeta privada). No se borra ni se cambia nada más.»
    public var resumen: String {
        let privadas = fichas.filter(\.privada).count
        var s = "Crear " + PreviaMultica.cuenta(fichas.count, "ficha de tarea", "fichas de tarea")
        if privadas > 0 { s += " (\(privadas) en tu carpeta privada)" }
        return s + ". No se borra ni se cambia nada más."
    }
}

public enum ErrorImportacionMultica: Error, LocalizedError, Sendable, Equatable {
    case nadaMarcado
    /// Hay alguna tarea personal marcada y no se ha elegido carpeta privada.
    case faltaCarpetaPrivada
    /// La carpeta elegida no está marcada como privada.
    case carpetaNoPrivada(String)

    public var errorDescription: String? {
        switch self {
        case .nadaMarcado: "No hay ninguna tarea marcada para importar."
        case .faltaCarpetaPrivada: "Has marcado tareas que parecen personales: elige la carpeta privada donde van."
        case .carpetaNoPrivada(let c): "«\(c)» no está marcada como privada. Elige una carpeta privada para las tareas personales."
        }
    }
}

/// Convierte las tareas abiertas de Multica en fichas de tarea (`TaskStore.crear`), sin escribir nada hasta
/// aplicar el plan. Cada ficha lleva `origen: importacion`, `fecha_corte`, el estado y la prioridad de allí, su
/// vencimiento, el texto en Descripción y `externo: ext:multica:<IDENTIFICADOR>`: una segunda importación no la
/// repite. Las reglas del dominio no se disparan (modo importación).
public struct ImportadorMultica: Sendable {
    public let snapshot: VaultSnapshot
    public let reloj: Reloj

    /// Propiedad con el identificador de fuera (`ext:multica:MANU-12`).
    public static let propiedadExterna = "externo"

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.snapshot = snapshot
        self.reloj = reloj ?? Reloj.deCarpeta(snapshot)
    }

    public static func clave(_ identificador: String) -> String { "ext:multica:\(identificador.uppercased())" }

    /// Tareas ya importadas de Multica: identificador (en mayúsculas) → ficha. Mira la propiedad `externo` y, por
    /// si alguien la movió, la marca `ext:multica:` en el texto.
    public func yaImportadas() -> [String: VaultPath] {
        conMarcaDeMultica(en: snapshot.notes.filter { TaskStore.esRutaDeTarea($0, layout: snapshot.layout) })
    }

    /// Las importadas que ahora están en el Archivo (retiradas por la persona o por «Deshacer»): no salen marcadas,
    /// para no volver a traer lo que se retiró; la persona puede marcarlas si las quiere de vuelta.
    public func enElArchivo() -> [String: VaultPath] {
        let archivo = VaultPath(snapshot.layout.archivo)
        return conMarcaDeMultica(en: snapshot.notes.filter { $0.isDescendant(of: archivo) && !snapshot.layout.isPrivate($0) })
    }

    func conMarcaDeMultica(en notas: [VaultPath]) -> [String: VaultPath] {
        var out: [String: VaultPath] = [:]
        let marca = "ext:multica:"
        for p in notas {
            guard let texto = snapshot.text(p), texto.contains(marca) else { continue }
            var resto = Substring(texto)
            while let r = resto.range(of: marca) {
                let id = resto[r.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                if !id.isEmpty, out[id.uppercased()] == nil { out[id.uppercased()] = p }
                resto = resto[r.upperBound...]
            }
        }
        return out
    }

    /// Vista previa: abiertas, con su área sugerida; marcadas salvo las personales y las ya importadas.
    public func previa(_ tareas: [TareaMultica]) -> PreviaMultica {
        let ya = yaImportadas()
        let archivadas = enElArchivo()
        let candidatas = tareas.filter(\.abierta).map { t -> CandidataMultica in
            let personal = ClasificadorPersonal.motivo(t.titulo, t.descripcion)
            let previa = ya[t.identificador.uppercased()]
            let archivada = previa == nil ? archivadas[t.identificador.uppercased()] : nil
            let area = SugerenciaArea.para(titulo: t.titulo, descripcion: t.descripcion)
            var c = CandidataMultica(tarea: t, personal: personal, yaImportada: previa, areaSugerida: area,
                                     marcada: personal == nil && previa == nil && archivada == nil && !t.estadoDesconocido, area: area)
            c.enArchivo = archivada
            return c
        }
        return PreviaMultica(candidatas: candidatas, fechaCorte: reloj.hoy)
    }

    /// Prepara el plan. Las marcadas que parecen personales van a `<carpetaPrivada>/Tareas/`, que tiene que ser
    /// privada. Numeración seguida desde el contador de la carpeta.
    public func plan(_ previa: PreviaMultica, carpetaPrivada: VaultPath? = nil, autor: Autor) throws -> PlanImportacionMultica {
        let marcadas = previa.marcadas
        guard !marcadas.isEmpty else { throw ErrorImportacionMultica.nadaMarcado }
        if !previa.personalesMarcadas.isEmpty {
            guard let c = carpetaPrivada else { throw ErrorImportacionMultica.faltaCarpetaPrivada }
            guard snapshot.layout.isPrivate(c) else { throw ErrorImportacionMultica.carpetaNoPrivada(c.raw) }
        }
        let store = TaskStore(snapshot: snapshot, reloj: reloj)
        var n = store.siguienteNumero()
        var ops: [WriteOp] = []
        var fichas: [PlanImportacionMultica.Ficha] = []
        for c in marcadas {
            let t = c.tarea
            let propiedades = [
                Property(key: "fecha_corte", value: .text(previa.fechaCorte.description)),
                Property(key: Self.propiedadExterna, value: .text(Self.clave(t.identificador))),
            ]
            let nueva = NuevaTarea(titulo: Self.titulo(t), area: c.area, estado: c.estado, prioridad: c.prioridad, vence: c.vence,
                                   descripcion: Self.descripcion(t.descripcion), origen: "importacion", autor: autor,
                                   propiedades: propiedades)
            let nota = try store.crear(nueva)
            let carpeta: VaultPath
            if c.parecePersonal, let privada = carpetaPrivada {
                carpeta = privada.appending(snapshot.layout.tareas)
            } else {
                carpeta = nota.ruta.parent ?? store.carpeta(area: c.area, proyecto: nil)
            }
            let ruta = carpeta.appending(TareaArchivo.nombre(numero: n, slug: TareaArchivo.slug(deNombre: nota.ruta.name)))
            var doc = FrontmatterDocument(text: nota.texto)
            doc.set("numero", .text(String(format: "T-%04d", n)))
            let texto = Self.conActividad(doc.text, entrada: actividad(t, autor: autor))
            ops.append(.create(ruta, text: texto))
            fichas.append(.init(identificador: t.identificador, ruta: ruta, privada: c.parecePersonal))
            n += 1
        }
        if let op = Secuencias.op(["tarea": n - 1], en: snapshot) { ops.append(op) }
        let descripcion = "Importar de Multica " + PreviaMultica.cuenta(fichas.count, "tarea", "tareas")
        return PlanImportacionMultica(plan: WritePlan(autor: autor, descripcion: descripcion, ops: ops), fichas: fichas)
    }

    /// Aplica el plan por el `CommandBus` (como la persona). Se deshace de una vez.
    public static func aplicar(_ p: PlanImportacionMultica, con bus: CommandBus) async throws -> WriteResult {
        try await bus.ejecutar(p.plan)
    }

    /// Aplica el plan a través del dominio con las reglas apagadas (modo importación) y las vuelve a encender.
    public static func aplicar(_ p: PlanImportacionMultica, con motor: MotorDeDominio) async throws -> WriteResult {
        await motor.setModoImportacion(true)
        do {
            let r = try await motor.ejecutar(p.plan)
            await motor.setModoImportacion(false)
            return r.escritura
        } catch {
            await motor.setModoImportacion(false)
            throw error
        }
    }

    // MARK: Texto

    /// Título en una línea.
    static func titulo(_ t: TareaMultica) -> String {
        let limpio = t.titulo.split(whereSeparator: \.isNewline).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return limpio.isEmpty ? t.identificador : limpio
    }

    /// El texto de fuera es un dato: sus encabezados bajan a cuarto nivel (no crean secciones nuevas en la ficha) y
    /// sus comentarios HTML no pueden pasar por marcas de la app.
    public static func descripcion(_ s: String?) -> String? {
        guard var s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.count > 20_000 { s = String(s.prefix(20_000)) + "\n\n[…]" }
        let lineas = s.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { linea -> String in
                let l = String(linea)
                let sinSangria = l.drop { $0 == " " }
                let almohadillas = sinSangria.prefix { $0 == "#" }.count
                guard almohadillas > 0, almohadillas <= 3 else { return l }
                let resto = sinSangria.dropFirst(almohadillas)
                guard resto.isEmpty || resto.hasPrefix(" ") else { return l }
                return "####" + resto
            }
        return lineas.joined(separator: "\n")
            .replacingOccurrences(of: "<!--", with: "&lt;!--")
            .replacingOccurrences(of: "-->", with: "--&gt;")
    }

    /// Entrada de Actividad: de dónde viene, con su marca para la máquina.
    func actividad(_ t: TareaMultica, autor: Autor) -> String {
        var texto = "Importada de Multica (\(t.identificador))."
        if let e = t.estado { texto += " Estado allí: «\(e)»." }
        texto += " Corte: \(reloj.hoy)."
        let campos = ["tipo": "importacion", "externo": Self.clave(t.identificador),
                      "id": "ev-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(6))]
        let data = (try? JSONSerialization.data(withJSONObject: campos, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "-->", with: "--\\u003e").replacingOccurrences(of: "<!--", with: "\\u003c!--")
        return "### \(reloj.hoy) \(reloj.hora) · \(autor.etiqueta)\n\(texto)\n<!-- tls:evento \(json) -->"
    }

    /// Añade la entrada al final de la sección `## Actividad` (después de su guía), sin tocar lo demás.
    static func conActividad(_ texto: String, entrada: String) -> String {
        var lineas = texto.components(separatedBy: "\n")
        guard let i = lineas.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Actividad" }) else {
            return texto.hasSuffix("\n") ? texto + "\n## Actividad\n\n" + entrada + "\n" : texto + "\n\n## Actividad\n\n" + entrada + "\n"
        }
        var fin = lineas.count
        for j in (i + 1)..<lineas.count where lineas[j].hasPrefix("# ") || lineas[j].hasPrefix("## ") {
            fin = j
            break
        }
        // Sin líneas vacías al final de la sección: la entrada va tras una vacía.
        var hasta = fin
        while hasta > i + 1, lineas[hasta - 1].trimmingCharacters(in: .whitespaces).isEmpty { hasta -= 1 }
        let bloque = ["", entrada] + (fin < lineas.count ? [""] : [])
        lineas.replaceSubrange(hasta..<fin, with: bloque)
        var out = lineas.joined(separator: "\n")
        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }
}
