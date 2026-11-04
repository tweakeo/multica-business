import Foundation
import TLSAgents
import TLSCore

// F5 · rol mail (PLAN §7.1). La app (nunca un asistente: su sandbox niega `osascript`) lee el correo nuevo de la cuenta
// elegida con JXA: bandeja de entrada, `dateReceived > cursor`, 50 mensajes y 120 s como mucho. Guarda messageId, fecha,
// remitente, destinatarios, asunto, leído y 4 KB de texto en Application Support (fuera de la carpeta); lo privado, solo
// «correo privado de X»; los adjuntos, solo nombre y tamaño. **Nunca** marca como leído, mueve, borra ni responde: el
// guion solo lee propiedades. Si macOS niega la Automatización, deja una tarjeta y no vuelve a intentarlo solo.

/// Cómo fue una lectura.
public enum ResultadoDeLectura: Sendable, Hashable {
    /// Se guardaron `nuevos` correos; `mas` = quedaron más por leer (tope de 50): la próxima lectura sigue.
    case leidos(nuevos: Int, mas: Bool)
    /// No hay cuenta elegida: no se lee nada.
    case sinCuenta
    /// Esa cuenta no está en Mail (o no tiene bandeja de entrada).
    case cuentaNoEncontrada(String)
    /// Mail está cerrado: la app no lo abre por su cuenta. Se vuelve a mirar en la próxima ronda.
    case mailCerrado
    /// macOS no deja usar Mail: la tarjeta explica cómo arreglarlo. No se reintenta hasta que la persona lo pida.
    case automatizacionDenegada(TarjetaDePermiso)
    /// Se pasó de 120 s: no se guarda nada y el cursor no se mueve.
    case tiempoAgotado
    /// Otro problema (texto para la persona; el detalle, en «Detalle técnico»).
    case fallo(String)

    public var texto: String {
        switch self {
        case .leidos(let n, let mas):
            (n == 0 ? "No hay correo nuevo." : n == 1 ? "1 correo nuevo." : "\(n) correos nuevos.") + (mas ? " Quedan más: sigo en la próxima ronda." : "")
        case .sinCuenta: "Elige qué cuenta de Mail mira el Cartero."
        case .cuentaNoEncontrada(let c): "No encuentro la cuenta «\(c)» en Mail."
        case .mailCerrado: "Mail está cerrado. Lo miro cuando lo abras."
        case .automatizacionDenegada(let t): t.titulo
        case .tiempoAgotado: "Mail ha tardado demasiado en contestar. Lo vuelvo a intentar en la próxima ronda."
        case .fallo(let m): m
        }
    }
}

/// Las cuentas de Mail, para que la persona elija cuál mira el Cartero.
public enum CuentasDeMail {
    public enum Resultado: Sendable, Hashable {
        case cuentas([String])
        case mailCerrado
        case automatizacionDenegada(TarjetaDePermiso)
        case fallo(String)
    }

    public static func listar(_ ejecutor: any EjecutorJXA = EjecutorJXAOsascript()) async -> Resultado {
        guard let r = try? await ejecutor.ejecutar(GuionesDeMail.cuentas, argumentos: [], tope: 20) else {
            return .fallo("No he podido hablar con Mail.")
        }
        if r.automatizacionDenegada || r.faltaConsentimiento { return .automatizacionDenegada(.de(.automatizacionMail, detalleTecnico: r.errores)) }
        struct Salida: Decodable { var estado: String; var cuentas: [String]? }
        guard r.estado == 0, !r.tiempoAgotado,
              let s = try? JSONDecoder().decode(Salida.self, from: Data(r.salida.trimmingCharacters(in: .whitespacesAndNewlines).utf8)) else {
            return .fallo("Mail no ha podido darme sus cuentas.")
        }
        if s.estado == "mail_cerrado" { return .mailCerrado }
        return .cuentas((s.cuentas ?? []).filter { !$0.isEmpty })
    }
}

public actor LectorDeCorreo {
    public static let maxMensajes = 50
    public static let tope: TimeInterval = 120
    /// La primera vez (sin cursor), cuánto hacia atrás: 72 h, como el triaje del lunes.
    public static let primeraVez: TimeInterval = 72 * 3600
    /// Margen hacia atrás desde el cursor en cada lectura (S1, S2): Mail baja a veces lo más nuevo primero y guarda la
    /// hora en segundos, así que se relee la ventana `cursor − 48 h` y lo ya guardado se descarta por `Message-ID`.
    public static let margen: TimeInterval = 48 * 3600
    /// Como mucho, cuántos `Message-ID` ya guardados se pasan al guion para que no los vuelva a contar.
    static let maxVistos = 2000

    let ejecutor: any EjecutorJXA
    public let almacen: AlmacenDeCorreo
    let cursor: CursorDeCorreo
    let ajustes: @Sendable () -> AjustesDeCorreo
    let ahora: @Sendable () -> Date
    /// Tras una Automatización denegada no se vuelve a lanzar `osascript` hasta `reintentar()` (sin bucles).
    public private(set) var bloqueo: TarjetaDePermiso?
    /// Lecturas lanzadas de verdad (para pruebas y diagnóstico).
    public private(set) var lanzamientos = 0

    public init(ejecutor: any EjecutorJXA, almacen: AlmacenDeCorreo, cursor: CursorDeCorreo,
                ajustes: @escaping @Sendable () -> AjustesDeCorreo, ahora: @escaping @Sendable () -> Date = { Date() }) {
        self.ejecutor = ejecutor; self.almacen = almacen; self.cursor = cursor; self.ajustes = ajustes; self.ahora = ahora
    }

    /// El de una empresa: almacén, cursor y ajustes en su estado (Application Support).
    public init(estado: URL, ejecutor: any EjecutorJXA = EjecutorJXAOsascript(), zona: TimeZone = .current) throws {
        self.init(ejecutor: ejecutor, almacen: AlmacenDeCorreo(estado: estado, zona: zona), cursor: try CursorDeCorreo(estado: estado),
                  ajustes: { AjustesDeCorreo.leer(estado) })
    }

    /// La persona arregló el permiso (o pulsó «Volver a intentar»): se puede leer otra vez.
    public func reintentar() {
        bloqueo = nil
    }

    /// Lee lo nuevo de la cuenta elegida y lo guarda. Nunca lanza `osascript` si está bloqueado por el permiso.
    public func leer() async -> ResultadoDeLectura {
        if let b = bloqueo { return .automatizacionDenegada(b) }
        let a = ajustes()
        guard let cuenta = a.cuenta?.trimmingCharacters(in: .whitespacesAndNewlines), !cuenta.isEmpty else { return .sinCuenta }
        let desde: Date
        do {
            desde = try cursor.leer(cuenta).map { $0.addingTimeInterval(-Self.margen) } ?? ahora().addingTimeInterval(-Self.primeraVez)
        } catch {
            return .fallo("No he podido leer hasta dónde llegó el Cartero.")
        }
        // Lo ya guardado de la ventana: el guion lo salta antes de cortar en 50 y aquí se vuelve a descartar.
        let yaGuardados = await almacen.mensajes(desde: desde, hasta: .distantFuture).filter { $0.cuenta == cuenta }
        let vistos = Set(yaGuardados.map(\.id))
        let parametros = ParametrosDeLectura(cuenta: cuenta, desde: desde, max: Self.maxMensajes, maxTexto: MensajeDeCorreo.maxTexto,
                                             privados: a.privados.map(\.patron),
                                             vistos: yaGuardados.suffix(Self.maxVistos).map(\.id))
        let r: ResultadoJXA
        do {
            lanzamientos += 1
            r = try await ejecutor.ejecutar(GuionesDeMail.leer, argumentos: [parametros.json], tope: Self.tope)
        } catch {
            return .fallo("No he podido hablar con Mail.")
        }
        if r.tiempoAgotado { return .tiempoAgotado }
        if r.automatizacionDenegada || r.faltaConsentimiento {
            let t = TarjetaDePermiso.de(.automatizacionMail, detalleTecnico: r.errores.trimmingCharacters(in: .whitespacesAndNewlines))
            bloqueo = t
            return .automatizacionDenegada(t)
        }
        guard r.estado == 0 else {
            return .fallo("Mail no ha podido darme el correo nuevo.")
        }
        let respuesta: RespuestaDeLectura
        do {
            respuesta = try RespuestaDeLectura.leer(r.salida)
        } catch {
            return .fallo("No entiendo lo que ha devuelto Mail.")
        }
        switch respuesta.estado {
        case "mail_cerrado": return .mailCerrado
        case "sin_cuenta", "sin_buzon": return .cuentaNoEncontrada(cuenta)
        case "ok": break
        default: return .fallo("Mail no ha podido darme el correo nuevo.")
        }
        // Topes y filtros otra vez aquí (no se fía del guion): solo lo posterior al cursor, 50 como mucho, lo privado y los
        // adjuntos como deben ir.
        let lote = respuesta.mensajes(cuenta: cuenta, privados: a.privados)
            .filter { $0.fecha > desde && !vistos.contains($0.id) }.sorted { $0.fecha < $1.fecha }
        let tomados = Array(lote.prefix(Self.maxMensajes)).map { FiltroDePrivacidad.aplicar($0, ajustes: a) }
        do {
            let nuevos = try almacen.guardar(tomados)
            if let ultimo = tomados.map(\.fecha).max() { try cursor.avanzar(cuenta, a: ultimo, ahora: ahora()) }
            return .leidos(nuevos: nuevos.count, mas: respuesta.mas || lote.count > tomados.count)
        } catch {
            return .fallo("No he podido guardar el correo nuevo.")
        }
    }
}

/// Lo que recibe el guion (un solo argumento JSON: nada se pega dentro del código).
struct ParametrosDeLectura: Encodable {
    var cuenta: String
    /// Milisegundos desde 1970.
    var desde: Double
    var max: Int
    var maxTexto: Int
    var privados: [String]
    /// `Message-ID` ya guardados de la ventana (sin `<>`): el guion no los vuelve a devolver.
    var vistos: [String]

    init(cuenta: String, desde: Date, max: Int, maxTexto: Int, privados: [String], vistos: [String] = []) {
        self.cuenta = cuenta; self.desde = (desde.timeIntervalSince1970 * 1000).rounded(.down); self.max = max
        self.maxTexto = maxTexto; self.privados = privados; self.vistos = vistos
    }

    var json: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// Lo que devuelve el guion de lectura.
struct RespuestaDeLectura: Decodable {
    struct Crudo: Decodable {
        var id: String?
        var fecha: Double?
        var de: String?
        var para: [String]?
        var asunto: String?
        var leido: Bool?
        var texto: String?
        var adjuntos: [AdjuntoDeCorreo]?
        var privado: Bool?
        /// Índice de la regla privada que casó (el guion no devuelve nada más de ese correo).
        var regla: Int?
    }

    var estado: String
    var crudos: [Crudo]?
    var mas: Bool

    enum CodingKeys: String, CodingKey { case estado, crudos = "mensajes", mas }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        estado = try c.decode(String.self, forKey: .estado)
        crudos = try c.decodeIfPresent([Crudo].self, forKey: .crudos)
        mas = try c.decodeIfPresent(Bool.self, forKey: .mas) ?? false
    }

    static func leer(_ salida: String) throws -> RespuestaDeLectura {
        let t = salida.trimmingCharacters(in: .whitespacesAndNewlines)
        return try JSONDecoder().decode(RespuestaDeLectura.self, from: Data(t.utf8))
    }

    /// Los válidos (con id y fecha).
    func mensajes(cuenta: String, privados: [RemitentePrivado] = []) -> [MensajeDeCorreo] {
        (crudos ?? []).compactMap { c in
            guard let id = c.id?.trimmingCharacters(in: CharacterSet(charactersIn: "<> \n")), !id.isEmpty, let f = c.fecha else { return nil }
            var de = c.de ?? ""
            if c.privado == true {
                let etiqueta = c.regla.flatMap { privados.indices.contains($0) ? privados[$0].etiqueta : nil } ?? "un remitente privado"
                de = FiltroDePrivacidad.textoPrivado(etiqueta)
            }
            return MensajeDeCorreo(id: id, cuenta: cuenta, fecha: Date(timeIntervalSince1970: f / 1000), de: de,
                                   para: c.para ?? [], asunto: c.asunto ?? "", leido: c.leido ?? false, texto: c.texto ?? "",
                                   adjuntos: c.adjuntos ?? [], privado: c.privado ?? false)
        }
    }
}

/// Los guiones JXA de la app. **Solo leen** (lectura) o abren una redacción visible (`MailComposer`): ninguno llama a
/// `send`, `delete`, `move` ni cambia `readStatus` (lo comprueba una prueba sobre el texto).
public enum GuionesDeMail {
    /// Lectura: `run([json])` → `{"estado":"ok","mensajes":[…],"mas":false}`. No abre Mail si está cerrado.
    public static let leer = #"""
    function run(argv) {
      const p = JSON.parse(argv[0]);
      const Mail = Application('com.apple.mail');
      if (!Mail.running()) { return JSON.stringify({estado: 'mail_cerrado'}); }
      let buzon = null;
      const entradas = Mail.inbox.mailboxes();
      for (let i = 0; i < entradas.length; i++) {
        try { if (entradas[i].account().name() === p.cuenta) { buzon = entradas[i]; break; } } catch (e) {}
      }
      if (buzon === null) { return JSON.stringify({estado: 'sin_buzon'}); }
      const privados = (p.privados || []).map(function (x) { return String(x).toLowerCase().trim(); });
      function direccion(remitente) {
        const m = /<([^>]+)>\s*$/.exec(remitente || '');
        return (m ? m[1] : (remitente || '')).trim().toLowerCase();
      }
      function reglaPrivada(dir) {
        const dominio = dir.indexOf('@') >= 0 ? dir.slice(dir.lastIndexOf('@') + 1) : '';
        for (let i = 0; i < privados.length; i++) {
          const q = privados[i];
          if (!q) { continue; }
          if (q.indexOf('@') > 0) { if (dir === q) { return i; } continue; }
          const d = q.charAt(0) === '@' ? q.slice(1) : q;
          if (dominio === d || dominio.endsWith('.' + d)) { return i; }
        }
        return -1;
      }
      const desde = new Date(p.desde);
      const vistos = {};
      (p.vistos || []).forEach(function (x) { vistos[String(x).toLowerCase()] = true; });
      function limpio(id) { return String(id || '').replace(/^[\s<]+|[\s>]+$/g, '').toLowerCase(); }
      const lista = buzon.messages.whose({dateReceived: {_greaterThan: desde}})();
      const conFecha = [];
      for (let i = 0; i < lista.length; i++) {
        let id = '';
        try { id = limpio(lista[i].messageId()); } catch (e) {}
        if (id && vistos[id]) { continue; }
        conFecha.push({m: lista[i], f: lista[i].dateReceived()});
      }
      conFecha.sort(function (a, b) { return a.f - b.f; });
      const lote = conFecha.slice(0, p.max);
      const salida = [];
      for (let i = 0; i < lote.length; i++) {
        const m = lote[i].m;
        const remitente = m.sender();
        const r = {id: m.messageId(), fecha: lote[i].f.getTime(), leido: m.readStatus()};
        const regla = reglaPrivada(direccion(remitente));
        if (regla >= 0) { r.privado = true; r.regla = regla; salida.push(r); continue; }
        r.de = remitente;
        r.para = m.toRecipients().map(function (x) { return x.address(); });
        r.asunto = m.subject() || '';
        let texto = '';
        try { texto = m.content() || ''; } catch (e) {}
        r.texto = String(texto).slice(0, p.maxTexto);
        let adjuntos = [];
        try { adjuntos = m.mailAttachments().map(function (a) { return {nombre: a.name(), bytes: a.fileSize()}; }); } catch (e) {}
        r.adjuntos = adjuntos;
        salida.push(r);
      }
      return JSON.stringify({estado: 'ok', mensajes: salida, mas: conFecha.length > lote.length});
    }
    """#

    /// Cuentas (para elegir en Conexiones): `{"estado":"ok","cuentas":["…"]}`. Solo nombres; no abre Mail si está cerrado.
    public static let cuentas = #"""
    function run(argv) {
      const Mail = Application('com.apple.mail');
      if (!Mail.running()) { return JSON.stringify({estado: 'mail_cerrado'}); }
      return JSON.stringify({estado: 'ok', cuentas: Mail.accounts.name()});
    }
    """#

    /// Redacción: `run([json])` con `{para, asunto, cuerpo, enRespuestaA}` → abre una ventana de redacción NUEVA y visible.
    /// Si responde a un correo que está en Mail, abre su respuesta (queda en el mismo hilo) y pone el cuerpo aprobado.
    /// **Nunca envía**: el clic de Enviar es de la persona.
    public static let redactar = #"""
    function run(argv) {
      const p = JSON.parse(argv[0]);
      const Mail = Application('com.apple.mail');
      const aprobados = (p.para || []).map(function (x) { return String(x).toLowerCase().trim(); });
      function direccion(remitente) {
        const m = /<([^>]+)>\s*$/.exec(remitente || '');
        return (m ? m[1] : (remitente || '')).trim().toLowerCase();
      }
      function soloAprobados(r) {
        const lista = r.toRecipients();
        if (lista.length === 0) { return false; }
        for (let i = 0; i < lista.length; i++) {
          if (aprobados.indexOf(String(lista[i].address()).toLowerCase().trim()) < 0) { return false; }
        }
        return true;
      }
      let redaccion = null;
      if (p.enRespuestaA) {
        try {
          const originales = Mail.inbox.messages.whose({messageId: p.enRespuestaA})();
          if (originales.length > 0) {
            const o = originales[0];
            let responderA = '';
            try { responderA = direccion(o.replyTo()); } catch (e) {}
            if (!responderA) { responderA = direccion(o.sender()); }
            // En el hilo solo si la respuesta va exactamente a lo aprobado (S4); si no, redacción nueva. La respuesta se
            // crea oculta y solo se enseña tras comprobar sus destinatarios: la que no cuadra no se ve ni se guarda.
            if (aprobados.indexOf(responderA) >= 0) {
              const r = o.reply({openingWindow: false, replyToAll: false});
              if (r.toRecipients().length === aprobados.length && soloAprobados(r)) { redaccion = r; }
            }
          }
        } catch (e) { redaccion = null; }
      }
      if (redaccion === null) {
        redaccion = Mail.OutgoingMessage({subject: p.asunto, content: p.cuerpo, visible: true});
        Mail.outgoingMessages.push(redaccion);
        for (let i = 0; i < p.para.length; i++) {
          redaccion.toRecipients.push(Mail.Recipient({address: p.para[i]}));
        }
      } else {
        redaccion.subject = p.asunto;
        redaccion.content = p.cuerpo;
        redaccion.visible = true;
      }
      Mail.activate();
      return JSON.stringify({estado: 'abierta'});
    }
    """#
}
