import Foundation
import TLSCore

// Las tarjetas del Calendario (las pinta el rol buzon-relevo en Decisiones; aquí, su contenido). La ficha manda y
// **nunca se escribe sola**: si cambiaste un evento nuestro en Calendario, sale «¿Actualizo la ficha?» con la
// diferencia; el permiso denegado usa la tarjeta común de Permisos (`TarjetaDePermiso.de(.calendarios)`).

/// Una diferencia entre la ficha y el evento del Calendario, en palabras.
public struct DiferenciaCalendario: Sendable, Hashable {
    /// «Nombre», «Cuándo», «Hora», «Duración».
    public let campo: String
    public let enFicha: String
    public let enCalendario: String

    public init(campo: String, enFicha: String, enCalendario: String) {
        self.campo = campo; self.enFicha = enFicha; self.enCalendario = enCalendario
    }
}

/// Algo de un evento nuestro que pide tu decisión.
public struct TarjetaCalendario: Sendable, Hashable, Identifiable {
    public enum Tipo: String, Sendable, Hashable, Codable {
        /// Cambiaste el evento en Calendario: ¿actualizo la ficha?
        case cambiadoEnCalendario = "cambiado_en_calendario"
        /// Quitaste el evento en Calendario: ¿lo vuelvo a poner?
        case quitadoEnCalendario = "quitado_en_calendario"
        /// El evento tiene invitados (los pusiste tú en Calendario): la app no lo toca, porque cambiarlo o quitarlo
        /// avisaría a esas personas (sería enviar).
        case conInvitados = "con_invitados"
    }

    /// `calendario:<tipo>:<clave>:<huella del evento>`: estable mientras el evento siga igual.
    public let id: String
    public let tipo: Tipo
    /// `tls://<tipo>/<id>`.
    public let clave: String
    public let ruta: VaultPath
    /// «Cambiaste «Revisión de la semana» en Calendario».
    public let titulo: String
    /// La explicación (qué pasa y qué hace cada botón).
    public let texto: String
    public let diferencias: [DiferenciaCalendario]
    /// El botón principal: «Actualizar la ficha», «Volver a ponerlo en Calendario» o «Entendido».
    public let boton: String
    /// La otra opción: «Dejar la ficha como está» (el Calendario vuelve a lo de la ficha), «Quitarla del Calendario».
    public let botonNo: String?

    public init(id: String, tipo: Tipo, clave: String, ruta: VaultPath, titulo: String, texto: String,
                diferencias: [DiferenciaCalendario], boton: String, botonNo: String?) {
        self.id = id; self.tipo = tipo; self.clave = clave; self.ruta = ruta; self.titulo = titulo; self.texto = texto
        self.diferencias = diferencias; self.boton = boton; self.botonNo = botonNo
    }
}

/// Textos del Calendario, en español de España y sin jerga.
public enum TextosCalendario {
    static let diasConTilde = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                        "octubre", "noviembre", "diciembre"]

    /// «cada lunes», «el día 5 de cada mes», «el día 5, cada tres meses», «22 de octubre de 2026».
    public static func cuando(_ e: EventoDelCalendario, zona: TimeZone) -> String {
        switch e.repeticion {
        case .semanal(let d)?: return "cada \(diasConTilde[max(0, min(6, d - 1))])"
        case .mensual(let n, let cada)?: return cada == 3 ? "el día \(n), cada tres meses" : cada == 1 ? "el día \(n) de cada mes"
            : "el día \(n), cada \(cada) meses"
        case nil:
            let d = LocalDate(date: e.inicio, timeZone: zona)
            return "\(d.day) de \(meses[d.month - 1]) de \(d.year)"
        }
    }

    /// «10:00» o «Todo el día».
    public static func hora(_ e: EventoDelCalendario, zona: TimeZone) -> String {
        if e.todoElDia { return "Todo el día" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.hour, .minute], from: e.inicio)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// «30 min», «1 h», «1 h 30 min».
    public static func duracion(_ e: EventoDelCalendario) -> String {
        if e.todoElDia { return "Todo el día" }
        let m = e.minutos
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    /// Las diferencias que se ven entre lo que pide la ficha y lo que hay en el Calendario.
    public static func diferencias(ficha: EventoDelCalendario, calendario: EventoDelCalendario, zona: TimeZone) -> [DiferenciaCalendario] {
        var out: [DiferenciaCalendario] = []
        func comparar(_ campo: String, _ a: String, _ b: String) {
            if a != b { out.append(DiferenciaCalendario(campo: campo, enFicha: a, enCalendario: b)) }
        }
        comparar("Nombre", ficha.titulo.trimmingCharacters(in: .whitespaces), calendario.titulo.trimmingCharacters(in: .whitespaces))
        comparar("Cuándo", cuando(ficha, zona: zona), cuando(calendario, zona: zona))
        comparar("Hora", hora(ficha, zona: zona), hora(calendario, zona: zona))
        comparar("Duración", duracion(ficha), duracion(calendario))
        return out
    }

    static func cambiado(_ d: EventoDeseado, actual: EventoDelCalendario, huella: String, zona: TimeZone) -> TarjetaCalendario {
        let que = d.tipo == .rutina ? "la rutina" : "la sesión"
        return TarjetaCalendario(
            id: "calendario:\(TarjetaCalendario.Tipo.cambiadoEnCalendario.rawValue):\(d.clave):\(ContentHash.of(huella).prefix(12))",
            tipo: .cambiadoEnCalendario, clave: d.clave, ruta: d.ruta,
            titulo: "Cambiaste «\(d.evento.titulo)» en Calendario",
            texto: "¿Actualizo la ficha de \(que) con lo que pusiste en Calendario? Si prefieres dejar la ficha como está, el "
                + "Calendario vuelve a lo de la ficha. Hasta que decidas, no toco ni la ficha ni el evento.",
            diferencias: diferencias(ficha: d.evento, calendario: actual, zona: zona),
            boton: "Actualizar la ficha", botonNo: "Dejar la ficha como está")
    }

    static func quitado(_ d: EventoDeseado) -> TarjetaCalendario {
        let rutina = d.tipo == .rutina
        return TarjetaCalendario(
            id: "calendario:\(TarjetaCalendario.Tipo.quitadoEnCalendario.rawValue):\(d.clave)",
            tipo: .quitadoEnCalendario, clave: d.clave, ruta: d.ruta,
            titulo: "Quitaste «\(d.evento.titulo)» del Calendario",
            texto: rutina
                ? "La ficha de la rutina sigue pidiendo que esté en Calendario. Puedo volver a ponerla o dejar de apuntarla en Calendario (la ficha se queda)."
                : "La sesión sigue con su fecha en el Viaje. Puedo volver a ponerla en Calendario.",
            diferencias: [], boton: "Volver a ponerlo en Calendario", botonNo: rutina ? "Quitarla del Calendario" : nil)
    }

    static func conInvitados(_ d: EventoDeseado) -> TarjetaCalendario {
        TarjetaCalendario(
            id: "calendario:\(TarjetaCalendario.Tipo.conInvitados.rawValue):\(d.clave)",
            tipo: .conInvitados, clave: d.clave, ruta: d.ruta,
            titulo: "«\(d.evento.titulo)» tiene invitados en Calendario",
            texto: "Los pusiste tú en Calendario. Para no avisar a nadie, la app no cambia ni quita este evento: hazlo tú en "
                + "Calendario si hace falta. La ficha sigue igual.",
            diferencias: [], boton: "Entendido", botonNo: nil)
    }
}
