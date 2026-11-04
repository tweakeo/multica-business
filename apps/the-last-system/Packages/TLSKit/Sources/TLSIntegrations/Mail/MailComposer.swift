import Foundation
import TLSAgents
import TLSCore

// F5 · rol mail: el hueco de correo de `EjecutorDeAprobaciones` (PLAN §5.2 y §7.1). Al aprobar un borrador de correo o de
// «escribir a cliente», la app abre una redacción NUEVA de Mail, visible y rellena con lo aprobado (para, asunto, cuerpo
// y, si responde a un correo, en su hilo). **No envía**: el clic de Enviar es de la persona. Después, el borrador queda
// «Abierto en Mail» y la Actividad de su tarea lo anota.

/// Lo que se abre en Mail: exactamente lo aprobado.
public struct RedaccionDeCorreo: Sendable, Hashable, Codable {
    public var para: [String]
    public var asunto: String
    public var cuerpo: String
    /// `Message-ID` del correo al que responde (sin `<>`), si lo hay.
    public var enRespuestaA: String?

    public init(para: [String], asunto: String, cuerpo: String, enRespuestaA: String? = nil) {
        self.para = para; self.asunto = asunto; self.cuerpo = cuerpo; self.enRespuestaA = enRespuestaA
    }

    var json: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// Quien abre la redacción en Mail. **No existe ninguna operación de enviar.** Lo real va por JXA (`RedactorDeMailJXA`);
/// en pruebas, un doble que apunta lo que se le pide.
public protocol RedactorDeMail: Sendable {
    func abrirRedaccion(_ r: RedaccionDeCorreo) async throws
}

public enum ErrorDeMail: Error, Sendable, Hashable, LocalizedError {
    case automatizacionDenegada
    case noSeAbrio(String)
    case sinDestinatario

    public var errorDescription: String? {
        switch self {
        case .automatizacionDenegada:
            "La app no tiene permiso para usar Mail. Ve a Ajustes del Sistema › Privacidad y seguridad › Automatización y activa Mail para The Last System. No se ha enviado nada."
        case .noSeAbrio: "No he podido abrir la redacción en Mail. No se ha enviado nada."
        case .sinDestinatario: "El correo no dice a quién va. Añade el destinatario y vuelve a aprobarlo."
        }
    }
}

/// Lo real: el guion `GuionesDeMail.redactar` por `osascript`, lanzado por la app.
public struct RedactorDeMailJXA: RedactorDeMail {
    let ejecutor: any EjecutorJXA

    public init(ejecutor: any EjecutorJXA = EjecutorJXAOsascript()) {
        self.ejecutor = ejecutor
    }

    public func abrirRedaccion(_ r: RedaccionDeCorreo) async throws {
        let out = try await ejecutor.ejecutar(GuionesDeMail.redactar, argumentos: [r.json], tope: 30)
        if out.automatizacionDenegada || out.faltaConsentimiento { throw ErrorDeMail.automatizacionDenegada }
        guard out.estado == 0, !out.tiempoAgotado, out.salida.contains("abierta") else {
            throw ErrorDeMail.noSeAbrio(out.errores.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// `ProtocoloDeCorreo` de F5: abre la redacción y anota. Nada sale de la empresa sin tu clic en Enviar.
public struct MailComposer: ProtocoloDeCorreo {
    let redactor: any RedactorDeMail
    let reloj: (@Sendable (VaultSnapshot) -> Reloj)?

    public init(redactor: any RedactorDeMail = RedactorDeMailJXA(), reloj: (@Sendable (VaultSnapshot) -> Reloj)? = nil) {
        self.redactor = redactor; self.reloj = reloj
    }

    public func preparar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
        guard let ruta = a.aprobacion.ruta else { throw ErrorDeGobierno.borradorNoValido("No sé qué borrador abrir.") }
        let r = try Self.redaccion(a)
        try await redactor.abrirRedaccion(r)
        // La Actividad de su tarea (si la tiene) lo anota, como la app.
        if let plan = Self.planActividad(a, ruta: ruta, reloj: reloj?(a.snapshot) ?? Reloj.deCarpeta(a.snapshot)) {
            _ = try? await a.bus.ejecutar(plan)
        }
        return .abiertoEnMail(ruta)
    }

    /// Lo que se abre: lo **aprobado** (la carga atada a la huella), no lo que diga ahora la ficha.
    public static func redaccion(_ a: AprobacionEnCurso) throws -> RedaccionDeCorreo {
        let c = a.aprobacion.carga
        let para = c.destinatarios.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !para.isEmpty else { throw ErrorDeMail.sinDestinatario }
        let enRespuesta = a.borrador?.enRespuestaA.flatMap { EnlaceDeCorreo.id($0) ?? $0 }
        return RedaccionDeCorreo(para: para, asunto: c.asunto ?? a.borrador?.asunto ?? "", cuerpo: c.cuerpo ?? a.borrador?.cuerpo ?? "",
                                 enRespuestaA: enRespuesta)
    }

    /// `### AAAA-MM-DD HH:MM · Manu` + «Abrí en Mail …» en la Actividad de la tarea del borrador.
    static func planActividad(_ a: AprobacionEnCurso, ruta: VaultPath, reloj: Reloj) -> WritePlan? {
        guard let tarea = a.borrador?.tarea else { return nil }
        let snapshot = a.snapshot
        let candidata = tarea.hasSuffix(".md") ? VaultPath(tarea) : nil
        let real = candidata.flatMap { snapshot.existing($0) }
            ?? snapshot.notes.first { TextFolding.nameKey($0.stem) == TextFolding.nameKey(tarea) }
        guard let real, !snapshot.layout.isPrivate(real) else { return nil }
        let quien: String = switch a.persona {
        case .persona(let p): p
        default: "Manu"
        }
        let asunto = a.aprobacion.carga.asunto ?? ruta.stem
        let texto = "### \(reloj.hoy) \(reloj.hora) · \(quien)\nAbrí en Mail el correo «\(asunto)» con lo aprobado para que lo envíes tú. "
            + "[Borrador](\(ruta.raw.replacingOccurrences(of: " ", with: "%20"))): Abierto en Mail.\n"
            + "<!-- tls:evento {\"aprobacion\":\"\(a.aprobacion.id)\",\"tipo\":\"abierto_en_mail\"} -->"
        return WritePlan(autor: .sistema, descripcion: "Abierto en Mail: «\(asunto)»",
                         ops: [.appendToSection(real, section: "Actividad", text: texto, blankLine: true)])
    }
}
