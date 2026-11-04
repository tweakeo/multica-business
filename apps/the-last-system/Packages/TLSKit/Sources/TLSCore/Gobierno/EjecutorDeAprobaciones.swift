import Foundation

// Lo que hace la app (nunca el asistente) cuando apruebas algo (PLAN §5.2), con un protocolo por acción:
//
// | Acción | Qué hace la app |
// |---|---|
// | Correo / escribir a un cliente | F5: `MailComposer` abre la redacción de Mail rellena y **pulsas Enviar tú**. Hasta entonces, el borrador queda «Listo para enviar» y se abre |
// | Publicar o acción de otro programa | F5: `GatewayRouter` llama con los argumentos exactos aprobados. Hasta entonces, «pendiente de conexión» |
// | Emitir factura | Orden FIN-02 del núcleo: número, «Emitida» y fila en `emitidas.csv` (el PDF lo pone la pantalla) |
// | Pagar | **Nunca se ejecuta.** Se preparan las instrucciones y se concilia cuando llegue el extracto |

/// Lo que pasó al ejecutar una aprobación.
public enum ResultadoDeAprobacion: Sendable, Hashable {
    /// Correo o mensaje: listo para que lo envíes tú (se abre este borrador; en F5, la redacción de Mail).
    case listoParaEnviar(VaultPath)
    /// F5 · mail: la redacción de Mail está abierta y rellena con lo aprobado; **el clic de Enviar es tuyo**.
    case abiertoEnMail(VaultPath)
    /// Otro programa lo recibió (F5).
    case enviadoAPasarela(String)
    /// Aún no hay conexión con ese programa: queda aprobado, sin salir.
    case pendienteDeConexion(String)
    /// Factura emitida con su número.
    case emitida(VaultPath, numero: String)
    /// Pagar nunca se ejecuta: estas son las instrucciones para que pagues tú.
    case instruccionesDePago(String)

    /// En pantalla.
    public var texto: String {
        switch self {
        case .listoParaEnviar: "Listo para enviar: revísalo y envíalo tú."
        case .abiertoEnMail: "Abierto en Mail: revísalo y pulsa Enviar tú."
        case .enviadoAPasarela(let m): m
        case .pendienteDeConexion(let m): m
        case .emitida(_, let n): "Factura \(n) emitida."
        case .instruccionesDePago(let m): m
        }
    }

    /// Ruta que conviene abrir después (el borrador o la factura).
    public var abrir: VaultPath? {
        switch self {
        case .listoParaEnviar(let r), .emitida(let r, _): r
        default: nil
        }
    }

    /// Cómo queda el espejo del borrador.
    var espejo: EstadoBorrador? {
        switch self {
        case .listoParaEnviar: .listoParaEnviar
        case .abiertoEnMail: .abiertoEnMail
        case .enviadoAPasarela: .enviado
        case .pendienteDeConexion, .instruccionesDePago: .aprobado
        case .emitida: nil
        }
    }
}

/// Lo que recibe cada protocolo: lo aprobado, tal cual, y quién lo aprobó.
public struct AprobacionEnCurso: Sendable {
    public let aprobacion: Aprobacion
    public let borrador: Borrador?
    public let persona: Autor
    public let bus: CommandBus
    public let snapshot: VaultSnapshot
}

/// Correo y mensajes a clientes (F5: redacción de Mail rellena; el clic de Enviar es tuyo).
public protocol ProtocoloDeCorreo: Sendable {
    func preparar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion
}

/// Publicar y herramientas de otros programas (F5: `GatewayRouter` con los argumentos exactos aprobados).
public protocol ProtocoloDePasarela: Sendable {
    func llamar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion
}

/// Emitir una factura (orden FIN-02 del núcleo).
public protocol ProtocoloDeFacturacion: Sendable {
    func emitir(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion
}

/// Hueco de F5: hoy deja el borrador «Listo para enviar» y pide abrirlo; nada sale de la empresa.
public struct CorreoSinConexion: ProtocoloDeCorreo {
    public init() {}
    public func preparar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
        guard let r = a.aprobacion.ruta else { throw ErrorDeGobierno.borradorNoValido("No sé qué borrador abrir.") }
        return .listoParaEnviar(r)
    }
}

/// Hueco de la pasarela (F5): queda aprobado y no sale nada.
public struct PasarelaSinConexion: ProtocoloDePasarela {
    public init() {}
    public func llamar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
        .pendienteDeConexion("Aprobado. Aún no hay conexión con ese programa: no ha salido nada.")
    }
}

/// FIN-02: número F-AAAA-NNNN (el siguiente del año), estado Emitida, fecha de hoy y su fila en `emitidas.csv`, como la
/// persona que aprobó, en un plan que se puede deshacer. Nunca pisa una fila que ya exista.
public struct FacturacionDelNucleo: ProtocoloDeFacturacion {
    public init() {}

    public func emitir(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
        guard let ruta = a.aprobacion.ruta else { throw ErrorDeGobierno.borradorNoValido("No sé qué factura emitir.") }
        let plan = try Self.plan(ruta, snapshot: a.snapshot, persona: a.persona)
        let r = try await a.bus.ejecutar(plan.plan)
        guard r.hecho else { throw ErrorDeGobierno.borradorNoValido("No he podido emitir la factura: cambió mientras tanto.") }
        return .emitida(ruta, numero: plan.numero)
    }

    /// Plan de la emisión (sin escribir).
    public static func plan(_ ruta: VaultPath, snapshot: VaultSnapshot, persona: Autor,
                            reloj: Reloj? = nil) throws -> (plan: WritePlan, numero: String) {
        guard persona.esPersona else { throw ErrorDeGobierno.soloPersonas }
        guard let real = snapshot.existing(ruta), let texto = snapshot.text(real) else { throw ErrorDeGobierno.noEncontrado(ruta.stem) }
        let fm = NoteDocument(text: texto).frontmatter
        guard fm.text("tls_type")?.lowercased() == "invoice" else {
            throw ErrorDeGobierno.borradorNoValido("«\(ruta.stem)» no es una factura.")
        }
        let estado = TextFolding.fold(fm.text("estado") ?? "borrador")
        guard estado == "borrador" || estado.isEmpty else {
            throw ErrorDeGobierno.borradorNoValido("La factura ya está «\(fm.text("estado") ?? "")»: no se vuelve a emitir.")
        }
        let reloj = reloj ?? Reloj.deCarpeta(snapshot)
        let hoy = reloj.hoy
        let registros = RegistrosFinanzas(snapshot: snapshot)
        let numero: String
        if let n = fm.text("numero")?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            numero = n
        } else {
            let patron = "^F-\(hoy.year)-(\\d+)$"
            var mayor = registros.emitidas.compactMap { $0.numero.flatMap { Secuencias.captura($0, patron) } }.max() ?? 0
            for p in snapshot.notes where !VaultSnapshot.isTemplatePath(p) {
                if let n = snapshot.frontmatter(p).text("numero"), let k = Secuencias.captura(n, patron) { mayor = max(mayor, k) }
            }
            numero = String(format: "F-%04d-%04d", hoy.year, mayor + 1)
        }
        let id = fm.text("id") ?? UUID().uuidString.lowercased()
        guard !registros.emitidas.contains(where: { $0.id == id || $0.numero == numero }) else {
            throw ErrorDeGobierno.borradorNoValido("Ya hay una factura emitida con el número \(numero).")
        }
        let total = fm.text("total").flatMap(FormatosPlantilla.centimos)
        let tercero = fm.text("empresa").map(LinkParser.plainText) ?? fm.text("contacto").map(LinkParser.plainText) ?? ""
        let documento = real.raw.hasPrefix(registros.carpeta.raw + "/") ? String(real.raw.dropFirst(registros.carpeta.raw.count + 1)) : real.raw
        let fila: [String: String] = [
            "id": id, "fecha_documento": hoy.description, "tercero": tercero, "numero_documento": numero, "moneda": "EUR",
            "total_documento": total.map(Euros.escrito) ?? "", "documento": documento, "ambito": "",
            "proyecto_id": fm.text("proyecto").map(LinkParser.plainText) ?? "", "estado_revision": "", "fuente": "app",
        ]
        var ops: [WriteOp] = [.mergeFrontmatter(real, set: [Property(key: "numero", value: .text(numero)),
                                                            Property(key: "estado", value: .text("Emitida")),
                                                            Property(key: "fecha", value: .text(hoy.description))], unset: [])]
        if snapshot.existing(registros.emitidasCSV) != nil {
            ops.append(.insertCSVRows(registros.emitidasCSV, rows: [fila], key: "id"))
        } else {
            let cab = RegistrosFinanzas.cabeceraEmitidas
            func celda(_ v: String) -> String {
                v.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
            }
            let csv = cab.joined(separator: ",") + "\n" + cab.map { celda(fila[$0] ?? "") }.joined(separator: ",") + "\n"
            ops.append(.create(registros.emitidasCSV, text: csv))
        }
        return (WritePlan(autor: persona, descripcion: "Emitir la factura \(numero)", ops: ops), numero)
    }
}

/// Elige el protocolo de cada acción. Pagar no tiene protocolo: nunca se ejecuta.
public struct EjecutorDeAprobaciones: Sendable {
    public var correo: any ProtocoloDeCorreo
    public var pasarela: any ProtocoloDePasarela
    public var facturacion: any ProtocoloDeFacturacion

    public init(correo: any ProtocoloDeCorreo = CorreoSinConexion(), pasarela: any ProtocoloDePasarela = PasarelaSinConexion(),
                facturacion: any ProtocoloDeFacturacion = FacturacionDelNucleo()) {
        self.correo = correo; self.pasarela = pasarela; self.facturacion = facturacion
    }

    public func ejecutar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
        switch a.aprobacion.accion {
        case .enviarCorreo, .escribirCliente: try await correo.preparar(a)
        case .publicar, .externa: try await pasarela.llamar(a)
        case .emitirFactura: try await facturacion.emitir(a)
        case .pagar: .instruccionesDePago(Self.instruccionesDePago(a))
        }
    }

    /// Lo que tienes que hacer tú en el banco (nunca se mueve dinero desde la app).
    static func instruccionesDePago(_ a: AprobacionEnCurso) -> String {
        let c = a.aprobacion.carga
        var partes = ["Pago aprobado. La app no mueve dinero: hazlo tú desde tu banco."]
        if !c.destinatarios.isEmpty { partes.append("A: " + c.destinatarios.joined(separator: ", ") + ".") }
        if let i = c.importe { partes.append("Importe: \(Euros.texto(i)).") }
        if let s = c.asunto { partes.append("Concepto: \(s).") }
        partes.append("Cuando llegue el extracto, se concilia solo y lo confirmas.")
        return partes.joined(separator: " ")
    }
}
