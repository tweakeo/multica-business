import Foundation
import MCP
import TLSAgents
import TLSCore
import TLSMCPShared

// F5 · rol mail. Lo del Cartero en `tls-mcp` (PLAN §7.1):
// - `tls_correo_pendiente`: el correo que recogió la app (fuera de la carpeta) en la ventana del triaje (el lunes, 72 h;
//   el resto, 24 h) que aún no está en el registro del Buzón, cada uno como `{"tipo":"dato_no_confiable",…}` (≤ 20 KB,
//   secretos ocultados; lo privado, solo «correo privado de X»).
// - `tls_anotar_correo`: la sección del día en `Buzón/Correo AAAA-MM.md`; remitente, asunto y hora los pone la app desde
//   el correo guardado (nunca el texto del asistente). Una segunda llamada con el mismo correo no lo repite.
// - El enlace al correo en `tls_crear_tarea` (`mensaje` → `origen: message://…`) y en `tls_preparar_borrador`
//   (`en_respuesta_a`): el Cartero puede crear tareas y borradores **nuevos** en las áreas que lee (lo que entra por el
//   Buzón tiene que llegar a su área: SISTEMAS CO1). Nada más fuera del Buzón.

extension ServidorDeHerramientas {
    static let slugCartero = "cartero"
    static let maxCorreos = 50

    /// El instante que corresponde a «ahora» en el día del reloj de la carpeta (en la demo, `hoy` es fijo).
    static func instante(_ reloj: Reloj) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = reloj.zona
        let h = cal.dateComponents([.hour, .minute, .second], from: reloj.ahora)
        var d = DateComponents(year: reloj.hoy.year, month: reloj.hoy.month, day: reloj.hoy.day)
        d.hour = h.hour; d.minute = h.minute; d.second = h.second
        return cal.date(from: d) ?? reloj.ahora
    }

    func correoPendiente(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let limite = max(1, min(try a.entero("limite") ?? Self.maxCorreos, Self.maxCorreos))
        guard c.asistente == Self.slugCartero else { throw ErrorDeHerramienta("Esa herramienta no está disponible para ti.") }
        guard let fuente = d.correo else {
            return Respuesta.hecho("Llega con la conexión de Mail.", ["estado": "no_disponible"])
        }
        let buzon = d.vista.layout.buzon.map { VaultPath($0) }
        try exigir(await autorizar(c, "leer", .lectura, rutas: buzon.map { [$0] } ?? []))
        let (foto, reloj) = await fotoYReloj()
        let horas = VentanaDeTriaje.horas(reloj.hoy)
        let hasta = Self.instante(reloj)
        let desde = hasta.addingTimeInterval(-Double(horas) * 3600)
        let apuntados = RegistroDelCorreo.idsApuntados(snapshot: foto, hoy: reloj.hoy)
        let pendientes = await fuente.mensajes(desde: desde, hasta: hasta).filter { !apuntados.contains($0.referencia) }
        let lote = Array(pendientes.prefix(limite))
        let datos: [Value] = lote.map { Self.dato($0, zona: reloj.zona) }
        return Respuesta.hecho(
            lote.isEmpty ? "No hay correo por clasificar." : "\(lote.count) correos por clasificar (los de las últimas \(horas) h).",
            ["correos": .array(datos), "total": .int(lote.count), "quedan": .int(pendientes.count - lote.count),
             "ventana_horas": .int(horas), "aviso": .string(DatoNoConfiable.aviso)])
    }

    /// `{"tipo":"dato_no_confiable","origen":"correo:<cuenta>","contenido":{…}}`, 20 KB como mucho.
    static func dato(_ m: MensajeDeCorreo, zona: TimeZone) -> Value {
        var contenido = m.paraElCartero(zona)
        func valor() -> Value {
            let data = (try? JSONSerialization.data(withJSONObject: contenido, options: [.sortedKeys])) ?? Data("{}".utf8)
            return (try? JSONDecoder().decode(Value.self, from: data)) ?? .object([:])
        }
        var v = valor()
        // Si se pasa de 20 KB (destinatarios o adjuntos de más), se recorta lo largo y se dice.
        if Respuesta.json(v).utf8.count > DatoNoConfiable.maxBytes {
            contenido["texto"] = DatoNoConfiable.recortar((contenido["texto"] as? String) ?? "", max: 1024)
            contenido["para"] = Array(((contenido["para"] as? [String]) ?? []).prefix(20))
            contenido["adjuntos"] = Array(((contenido["adjuntos"] as? [[String: Any]]) ?? []).prefix(20))
            contenido["recortado"] = true
            v = valor()
        }
        return .object(["tipo": .string(DatoNoConfiable.tipo), "origen": .string("correo:" + m.cuenta), "contenido": v])
    }

    func anotarCorreo(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        guard c.asistente == Self.slugCartero else { throw ErrorDeHerramienta("Esa herramienta no está disponible para ti.") }
        let crudas = try a.objetos("entradas", max: Self.maxCorreos)
        guard !crudas.isEmpty else { throw ErrorDeArgumentos("Falta «entradas».") }
        guard let fuente = d.correo else { throw ErrorDeHerramienta("Mail no está conectado: no hay correo que apuntar.") }
        let (foto, reloj) = await fotoYReloj()
        guard let ruta = RegistroDelCorreo.ruta(reloj.hoy, layout: d.vista.layout) else {
            throw ErrorDeHerramienta("Esta carpeta no tiene Buzón.")
        }
        var ya = RegistroDelCorreo.idsApuntados(snapshot: foto, hoy: reloj.hoy)
        var entradas: [EntradaDeCorreo] = []
        var repetidos = 0
        for o in crudas {
            let e = try Argumentos(o, permitidas: ["mensaje", "tipo", "destino", "estado", "plazo"])
            let enlace = try e.obligatorio("mensaje", max: 400)
            guard let m = await fuente.mensaje(enlace) else { throw ErrorDeHerramienta("No conozco el correo «\(enlace)».") }
            let tipoTexto = try e.obligatorio("tipo", max: 20)
            guard let tipo = TipoDeCorreo(leyendo: tipoTexto) else { throw ErrorDeArgumentos("No conozco la clase «\(tipoTexto)».") }
            let estadoTexto = try e.texto("estado", max: 12) ?? EstadoEntradaCorreo.propuesto.rawValue
            guard let estado = EstadoEntradaCorreo(leyendo: estadoTexto), estado != .deshecho else {
                throw ErrorDeArgumentos("El estado es «Propuesto» o «Hecho».")
            }
            let destino = TextoDeAsistente.linea(try e.obligatorio("destino", max: 120))
            if ya.contains(m.referencia) { repetidos += 1; continue }
            ya.insert(m.referencia)
            entradas.append(EntradaDeCorreo(mensaje: m, tipo: tipo, destino: destino, estado: estado, plazo: try e.fecha("plazo")))
        }
        guard !entradas.isEmpty else {
            return Respuesta.hecho("Ya estaban apuntados: no repito nada.", ["apuntados": .int(0), "repetidos": .int(repetidos)])
        }
        let ops = RegistroDelCorreo.ops(entradas, dia: reloj.hoy, zona: reloj.zona, layout: d.vista.layout) { foto.existing($0) != nil }
        let plan = WritePlan(autor: c.autor, descripcion: "Registro del correo del \(reloj.hoy)", ops: ops)
        try exigir(await autorizar(c, "buzon.registrar", .suelo, rutas: [ruta], plan: plan))
        let r = try await escribir(plan, c)
        guard r.hecho else { throw ErrorDeHerramienta("No he podido apuntarlo: el registro cambió mientras tanto.") }
        let plazos = entradas.filter { $0.plazo != nil }.count
        return Respuesta.hecho("Apuntados \(entradas.count) correos en el registro de hoy." + (plazos > 0 ? " Con plazo oficial: \(plazos) (avísalo con tls_avisar en rojo)." : ""),
                               ["ruta": .string(ruta.raw), "apuntados": .int(entradas.count), "repetidos": .int(repetidos),
                                "plazos": .int(plazos)])
    }

    // MARK: Enlaces al correo en tareas y borradores

    /// `mensaje` de `tls_crear_tarea`: solo el Cartero, un correo que la app conoce. Devuelve su enlace (`origen`).
    func origenDeCorreo(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> String? {
        guard let enlace = try a.texto("mensaje", max: 400) else { return nil }
        guard c.asistente == Self.slugCartero else { throw ErrorDeHerramienta("Solo el Cartero enlaza tareas a un correo.") }
        guard EnlaceDeCorreo.esEnlace(enlace) else { throw ErrorDeArgumentos("«mensaje» tiene que ser un enlace message://.") }
        guard let fuente = d.correo, let m = await fuente.mensaje(enlace) else { throw ErrorDeHerramienta("No conozco ese correo.") }
        // De un correo privado no sale nada: ni tareas con su enlace.
        guard !m.privado else { throw ErrorDeHerramienta("Ese correo es privado: apúntalo en el registro y lo mira la persona.") }
        return m.enlace
    }

    /// Áreas donde puede crear una tarea o un borrador que sale de un correo: el Cartero, las que lee; los demás, las suyas.
    func areasParaCorreo(_ c: ContextoDelAsistente, desdeCorreo: Bool) -> Set<AreaCode> {
        guard desdeCorreo, c.asistente == Self.slugCartero, c.buzon else { return c.areasEscribibles }
        return c.areasEscribibles.union(c.areasLegibles)
    }

    /// Destinatario por defecto de una respuesta: el remitente del correo (si no es privado).
    func remitenteDe(_ enRespuestaA: String?) async -> String? {
        guard let r = enRespuestaA, let fuente = d.correo, let m = await fuente.mensaje(r), !m.privado else { return nil }
        let t = m.de.trimmingCharacters(in: .whitespaces)
        if let i = t.lastIndex(of: "<"), let f = t.lastIndex(of: ">"), i < f { return String(t[t.index(after: i)..<f]) }
        return t.contains("@") ? t : nil
    }
}
