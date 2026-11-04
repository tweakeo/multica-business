import Foundation

/// Un umbral escrito en `Metas.md` («80 %», «1000 €», «3 meses», «0», vacío o texto sin número).
public struct Umbral: Sendable, Hashable {
    /// Tal como está escrito.
    public let texto: String
    /// La cifra, si la hay. «Todos» o «Con histórico propio» no tienen cifra: el umbral no está fijado.
    public let numero: Double?
    /// Para «dentro de un rango» escrito «3–6» o «3-6»: el máximo (el mínimo va en `numero`).
    public let maximo: Double?

    public init(texto: String) {
        let t = texto.trimmingCharacters(in: .whitespaces)
        self.texto = t
        let partes = t.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        if let r = partes.range(of: #"^\s*(\d[\d.,]*)\s*-\s*(\d[\d.,]*)"#, options: .regularExpression) {
            let trozo = String(partes[r])
            let nums = trozo.split(separator: "-").map { Umbral.cifra(String($0)) }
            self.numero = nums.first ?? nil
            self.maximo = nums.count > 1 ? nums[1] : nil
        } else {
            self.numero = Umbral.cifra(t)
            self.maximo = nil
        }
    }

    public static let vacio = Umbral(texto: "")

    /// Tiene cifra.
    public var fijado: Bool { numero != nil }

    /// Para enseñar (revisión final de F2): si el texto es solo una cifra con su unidad («6000 €», «80 %», «3 meses»),
    /// con el formato de la app («6.000 €», «80 %», «3 meses»), como el valor de al lado. Si no («Todos», «3–6», «Con
    /// histórico propio»), tal como está escrito. Para editar se usa `texto`.
    public var textoVisible: String {
        guard let n = numero, maximo == nil,
              texto.range(of: #"^[-+−]?\d[\d.,]*\s*(€|%|meses|mes|h)?$"#, options: .regularExpression) != nil else { return texto }
        let unidad = KPIEvaluador.unidad(deUmbral: texto)
        if unidad == "meses", n == n.rounded() { return "\(FormatoBase.cifra(n)) \(n == 1 ? "mes" : "meses")" }
        return KPIEvaluador.formatear(n, unidad: unidad)
    }
    public var vacioDeTexto: Bool { texto.isEmpty }

    /// La primera cifra del texto, con la unidad que lleve detrás («1000 €», «80 %», «3 meses», «-5»).
    static func cifra(_ texto: String) -> Double? {
        guard let r = texto.range(of: #"[-+−]?\d[\d.,]*"#, options: .regularExpression) else { return nil }
        // Lo que va delante de la cifra tiene que ser nada o un signo: «Uno en rojo varias revisiones» no es 1.
        let antes = texto[texto.startIndex..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        guard antes.isEmpty else { return nil }
        let n = String(texto[r]).replacingOccurrences(of: "−", with: "-")
        return FormatoBase.numeroEscrito(n)
    }
}

/// Una fila de la tabla `| Código | Indicador | Meta | Alerta | Por qué |`.
public struct FilaMeta: Sendable, Hashable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    public let indicador: String
    public let meta: Umbral
    public let alerta: Umbral
    public let porQue: String
}

/// Una línea de «## Cómo se mide»: `- CÓDIGO · cálculo · periodo · más es mejor`.
public struct ComoSeMide: Sendable, Hashable {
    public let codigo: String
    public let calculo: String
    public let periodo: String
    public let sentido: SentidoKPI?
}

/// `1 · Dirección/Metas.md`: un número por pregunta, con meta y alerta escritas antes de ver el dato.
/// La app lee la tabla entera y solo reescribe las celdas Meta y Alerta (`MetasEscritor`).
public struct MetasDocumento: Sendable, Hashable {
    public static let nombre = "Metas.md"
    public static let columnas = ["Código", "Indicador", "Meta", "Alerta", "Por qué"]
    public static let selector = TableSelector(columna: "Código")

    public let ruta: VaultPath
    public let filas: [FilaMeta]
    public let comoSeMide: [String: ComoSeMide]
    /// `false` si la nota existe pero no tiene la tabla de códigos.
    public let tieneTabla: Bool

    public init(texto: String, ruta: VaultPath = VaultPath("1 · Dirección/Metas.md")) {
        self.ruta = ruta
        let body = NoteDocument(text: texto).body
        if let filas = MarkdownTable.rows(in: body, selector: Self.selector) {
            tieneTabla = true
            func celda(_ d: [String: String], _ nombre: String) -> String {
                if let v = d[nombre] { return v }
                let k = TextFolding.fold(nombre)
                return d.first { TextFolding.fold($0.key) == k }?.value ?? ""
            }
            var vistos = Set<String>()
            self.filas = filas.compactMap { d in
                let codigo = celda(d, "Código").trimmingCharacters(in: .whitespaces)
                guard !codigo.isEmpty, vistos.insert(codigo.uppercased()).inserted else { return nil }
                return FilaMeta(codigo: codigo, indicador: celda(d, "Indicador"), meta: Umbral(texto: celda(d, "Meta")),
                                alerta: Umbral(texto: celda(d, "Alerta")), porQue: celda(d, "Por qué"))
            }
        } else {
            tieneTabla = false
            self.filas = []
        }
        var como: [String: ComoSeMide] = [:]
        if let seccion = MarkdownSections.content(of: "Cómo se mide", in: body) {
            for linea in seccion.split(whereSeparator: \.isNewline) {
                let l = linea.trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("- ") else { continue }
                let partes = l.dropFirst(2).components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let codigo = partes.first, !codigo.isEmpty, !codigo.contains(" ") else { continue }
                let sentido = partes.last.flatMap { SentidoKPI(leyendo: $0) }
                como[codigo.uppercased()] = ComoSeMide(codigo: codigo, calculo: partes.count > 1 ? partes[1] : "",
                                                       periodo: partes.count > 3 ? partes[2] : "", sentido: sentido)
            }
        }
        self.comoSeMide = como
    }

    /// Ruta de `Metas.md` en esta carpeta.
    public static func ruta(layout: VaultLayout) -> VaultPath {
        layout.areaFolder(.direccion).appending(nombre)
    }

    /// Lee `Metas.md` de la foto. `nil` si no existe o es privado.
    public static func leer(_ snapshot: VaultSnapshot) -> MetasDocumento? {
        let ruta = ruta(layout: snapshot.layout)
        guard let real = snapshot.existing(ruta), !snapshot.layout.isPrivate(real), let t = snapshot.text(real) else { return nil }
        return MetasDocumento(texto: t, ruta: real)
    }

    public var codigos: [String] { filas.map(\.codigo) }

    public func fila(_ codigo: String) -> FilaMeta? {
        let c = codigo.uppercased()
        return filas.first { $0.codigo.uppercased() == c }
    }
}

public enum MetasError: Error, LocalizedError, Sendable, Equatable {
    case sinMetas
    case codigoDesconocido(String)
    case valorNoValido(String)
    case soloPersonas

    public var errorDescription: String? {
        switch self {
        case .sinMetas: "No encuentro la tabla de Metas en 1 · Dirección/Metas.md."
        case .codigoDesconocido(let c): "«\(c)» no está en la tabla de Metas."
        case .valorNoValido(let v): "«\(v)» no es una cifra. Escribe solo el número, por ejemplo 3 o 80."
        case .soloPersonas: "La meta y la alerta las fijas tú: un asistente no puede cambiarlas."
        }
    }
}

/// Cambia la Meta y la Alerta de un código en `Metas.md`. Solo esas dos celdas, por `CommandBus`, y solo una persona.
public enum MetasEscritor {
    /// «3 meses», «80 %», «1000 €», «2,5»: la cifra sin puntos de millares (así la vuelve a leer igual) y su unidad.
    public static func texto(_ n: Double, unidad: String) -> String {
        // Sin millares y con los decimales justos («2,5», no «2,50»).
        var cifra = FormatoBase.cifraParaEditar(n)
        if cifra.contains(",") {
            while cifra.hasSuffix("0") { cifra.removeLast() }
            if cifra.hasSuffix(",") { cifra.removeLast() }
        }
        switch unidad {
        case "%": return "\(cifra) %"
        case "€": return "\(cifra) €"
        case "meses": return n == 1 ? "\(cifra) mes" : "\(cifra) meses"
        case "h": return "\(cifra) h"
        case "USD": return "\(cifra) USD"
        default: return cifra
        }
    }

    /// Normaliza lo que escribe la persona: vacío borra el umbral; si no, tiene que haber una cifra.
    public static func normalizar(_ escrito: String, unidad: String) throws -> String {
        let t = escrito.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "" }
        guard let n = Umbral(texto: t).numero else { throw MetasError.valorNoValido(t) }
        return texto(n, unidad: unidad)
    }

    /// La orden para el bus: solo las celdas Meta y Alerta de la fila de `codigo`.
    public static func comando(_ metas: MetasDocumento, codigo: String, meta: String, alerta: String) throws -> CommandBus.Comando {
        guard metas.tieneTabla else { throw MetasError.sinMetas }
        guard let fila = metas.fila(codigo) else { throw MetasError.codigoDesconocido(codigo) }
        return .cambiarCeldas(metas.ruta, tabla: MetasDocumento.selector, columnaClave: "Código", valorClave: fila.codigo,
                              celdas: ["Meta": meta, "Alerta": alerta])
    }

    /// Fija la meta y la alerta de un número (vacío = sin umbral). La unidad sale del catálogo («meses», «%», «€»…).
    @discardableResult
    public static func fijar(codigo: String, meta: String, alerta: String, en metas: MetasDocumento,
                             catalogo: CatalogoPrograma = .deSerie, bus: CommandBus, autor: Autor) async throws -> WriteResult {
        guard autor.esPersona else { throw MetasError.soloPersonas }
        let unidad = catalogo.kpi(codigo)?.unidad ?? ""
        let m = try normalizar(meta, unidad: unidad)
        let a = try normalizar(alerta, unidad: unidad)
        return try await bus.ejecutar(try comando(metas, codigo: codigo, meta: m, alerta: a), autor: autor)
    }
}
