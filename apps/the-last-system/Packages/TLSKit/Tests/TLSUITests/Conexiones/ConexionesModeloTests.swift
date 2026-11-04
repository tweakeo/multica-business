import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// F5 · rol conexiones: el modelo de la pantalla Conexiones con servicios en memoria (nunca Mail, Calendario, avisos
/// de macOS, red ni Llavero de verdad). La explicación va antes del aviso, denegado lleva a la recuperación sin volver a
/// preguntar, la clave solo va al «Llavero» del doble y la pantalla la olvida, y los textos no usan jerga.
@Suite("Conexiones · modelo", .serialized)
@MainActor
struct ConexionesModeloTests {
    final class Enlaces { var abiertos: [URL] = [] }

    static func modelo(_ s: ServiciosDeConexionesEnMemoria? = ServiciosDeConexionesEnMemoria(), modo: ModoConexiones = .ajustes,
                       enlaces: Enlaces = Enlaces(), defaults: UserDefaults? = nil, empresa: UUID? = nil) -> ModeloConexiones {
        ModeloConexiones(servicios: s, modo: modo, presencia: PreferenciasPresencia(), abrirEnlace: { enlaces.abiertos.append($0) },
                         empresa: empresa, defaults: defaults)
    }

    @Test("Sin servicios: Claude, Banco, Avisos y ventana cerrada; lo demás «Ahora no» con su explicación; todo apagado de serie")
    func sinServicios() async {
        let m = Self.modelo(nil)
        await m.cargar()
        #expect(!m.hayServicios)
        #expect(ModeloConexiones.orden == [.claude, .mail, .calendario, .banco, .otros, .avisos, .ventanaCerrada])
        for c in [ConexionPuesta.mail, .calendario, .otros, .avisos, .ventanaCerrada] { #expect(m.estado(c) == .ahoraNo, "\(c)") }
        #expect(m.estado(.banco) == .conectado && m.palabra(.banco) == "Con extractos")
        #expect(m.detalle(.mail) == ModeloConexiones.queHaceMail)
        #expect(m.detalle(.mail) == "Solo leo la bandeja de entrada de las cuentas que elijas; nunca envío, muevo ni borro nada.")
        #expect(m.detalle(.calendario).contains("tus rituales y las sesiones con clientes, sin invitar a nadie"))
        #expect(m.plantillas.map(\.nombre) == ["Web y formularios", "GoHighLevel", "Stripe", "Calendly", "Otro programa"])
        await m.conectarMail()
        #expect(m.faseMail == .inicio, "sin servicios no se pide nada")
    }

    @Test("Mail: la explicación va antes del aviso de macOS; luego cuenta, remitentes privados y el Cartero (como tú)")
    func mailConectar() async throws {
        let s = ServiciosDeConexionesEnMemoria()
        let m = Self.modelo(s)
        await m.cargar()
        #expect(m.estado(.mail) == .ahoraNo)
        await m.conectarMail()
        guard case .explicacion(let e) = m.faseMail else { Issue.record("sin explicación: \(m.faseMail)"); return }
        #expect(await s.peticiones.isEmpty, "nada se pide antes de enseñar la explicación")
        #expect(e.explicacion.nunca.contains { $0.contains("Enviar nada") })
        await m.continuarMail()
        #expect(await s.peticiones == [.mail])
        #expect(m.faseMail == .cuentas(["Trabajo", "Personal"]))
        #expect(m.ajustesMail.cuenta == "Trabajo")
        m.ajustesMail.cuenta = "Personal"
        m.nuevoPrivado = RemitentePrivadoConexion(patron: "consulta@clinica-ejemplo.es", etiqueta: "Expediente privado")
        m.anadirPrivado()
        m.nuevoPrivado = RemitentePrivadoConexion(patron: "@abogados-ejemplo.es", etiqueta: "Expediente privado 2")
        m.anadirPrivado()
        #expect(m.errorPrivado == nil && m.ajustesMail.privados.count == 2)
        await m.terminarMail()
        #expect(m.faseMail == .conectado)
        #expect(m.estado(.mail) == .conectado)
        #expect(await s.activaciones == [true])
        let guardado = await s.ajustes
        #expect(guardado.cuenta == "Personal" && guardado.privados.map(\.etiqueta) == ["Expediente privado", "Expediente privado 2"])
        #expect(m.detalle(.mail).contains("«Personal»") && m.detalle(.mail).contains("2 remitentes privados"))
        // Desconectar: el Cartero deja de trabajar (como tú) y la fila vuelve a «Ahora no».
        await m.desconectarMail()
        #expect(await s.activaciones == [true, false])
        #expect(m.estado(.mail) == .ahoraNo)
    }

    @Test("Mail denegado: recuperación con «Abrir Ajustes del Sistema» y sin volver a preguntar")
    func mailDenegado() async {
        let s = ServiciosDeConexionesEnMemoria()
        await s.poner(alPedir: .mail, .denegado)
        let enlaces = Enlaces()
        let m = Self.modelo(s, enlaces: enlaces)
        await m.cargar()
        await m.conectarMail()
        await m.continuarMail()
        guard case .recuperacion(let r) = m.faseMail else { Issue.record("sin recuperación: \(m.faseMail)"); return }
        #expect(m.estado(.mail) == .sinPermiso && m.palabra(.mail) == "Sin permiso")
        #expect(r.texto.contains("Nada se ha enviado"))
        m.abrirAjustes(r)
        #expect(enlaces.abiertos.map(\.absoluteString) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"])
        // «Ya lo he cambiado» sin cambiarlo: vuelve la recuperación; macOS no se pregunta otra vez.
        await m.volverAMirar(.mail)
        guard case .recuperacion = m.faseMail else { Issue.record("debería seguir en recuperación"); return }
        await m.conectarMail()
        #expect(await s.peticiones == [.mail], "denegado no se vuelve a preguntar")
        // Si ya estaba denegado al abrir Conexiones, la fila lo dice desde el principio.
        let m2 = Self.modelo(s)
        await m2.cargar()
        #expect(m2.estado(.mail) == .sinPermiso)
        #expect(m2.detalle(.mail).contains("Nada se ha tocado en tu correo"))
    }

    @Test("Mail cerrado y remitentes privados mal escritos")
    func mailCerradoYPrivados() async {
        let s = ServiciosDeConexionesEnMemoria()
        await s.poner(permiso: .mail, .concedido)
        await s.poner(cuentas: .mailCerrado)
        let m = Self.modelo(s)
        await m.cargar()
        await m.conectarMail()
        #expect(m.faseMail == .mailCerrado)
        await s.poner(cuentas: .cuentas(["Trabajo"]))
        await m.volverAMirarMail()
        #expect(m.faseMail == .cuentas(["Trabajo"]))
        for malo in ["", "sin punto", "a@b@c.es", "@.es"] {
            m.nuevoPrivado = RemitentePrivadoConexion(patron: malo, etiqueta: "Algo")
            m.anadirPrivado()
            #expect(m.errorPrivado != nil, "«\(malo)»")
        }
        m.nuevoPrivado = RemitentePrivadoConexion(patron: "banco-ejemplo.es", etiqueta: "")
        m.anadirPrivado()
        #expect(m.errorPrivado?.contains("nombre neutro") == true)
        #expect(m.ajustesMail.privados.isEmpty)
        // Sin activar el Cartero, se guarda la cuenta pero Mail no cuenta como conectado.
        m.activarCartero = false
        await m.terminarMail()
        #expect(await s.activaciones.isEmpty)
        #expect(m.estado(.mail) == .ahoraNo)
    }

    @Test("Calendario: explicación antes del permiso, «The Last System» sin invitar a nadie; denegado → recuperación")
    func calendario() async {
        let s = ServiciosDeConexionesEnMemoria()
        let m = Self.modelo(s)
        await m.cargar()
        await m.conectarCalendario()
        guard case .explicacion(let e) = m.faseCalendario else { Issue.record("sin explicación"); return }
        #expect(await s.peticiones.isEmpty)
        #expect(e.explicacion.nunca.contains("Invitar a nadie: invitar sería enviar."))
        await m.continuarCalendario()
        #expect(await s.calendarioCreado)
        #expect(m.estado(.calendario) == .conectado)
        #expect(m.detalle(.calendario).contains("«The Last System»") && m.detalle(.calendario).contains("Sin invitar a nadie"))

        let s2 = ServiciosDeConexionesEnMemoria()
        await s2.poner(alPedir: .calendario, .denegado)
        let enlaces = Enlaces()
        let m2 = Self.modelo(s2, enlaces: enlaces)
        await m2.cargar()
        await m2.conectarCalendario()
        await m2.continuarCalendario()
        guard case .recuperacion(let r) = m2.faseCalendario else { Issue.record("sin recuperación"); return }
        #expect(m2.estado(.calendario) == .sinPermiso)
        m2.abrirAjustes(r)
        #expect(enlaces.abiertos.first?.absoluteString.hasSuffix("Privacy_Calendars") == true)
        #expect(await !s2.calendarioCreado)
    }

    @Test("Otros programas: GoHighLevel con su dirección y su clave (al Llavero, y la pantalla la olvida), probar e interruptores")
    func anadirGoHighLevel() async throws {
        let s = ServiciosDeConexionesEnMemoria()
        let m = Self.modelo(s)
        await m.cargar()
        let ghl = try #require(m.plantillas.first { $0.id == "ghl" })
        m.empezarAlta(ghl)
        var b = try #require(m.alta)
        #expect(b.direccion == "https://services.leadconnectorhq.com/mcp/")
        b.clave = ""
        #expect(m.faltaEnAlta(b) == "Pega la clave de acceso.")
        b.direccion = "http://ejemplo.es/mcp"
        #expect(m.faltaEnAlta(b)?.contains("https://") == true)
        b.direccion = "https://ejemplo.es/mcp?token=abc"
        #expect(m.faltaEnAlta(b)?.contains("Llavero") == true)
        b.direccion = "https://services.leadconnectorhq.com/mcp/"
        b.clave = "  pit-clave-de-prueba-123  "
        #expect(m.faltaEnAlta(b) == nil)
        m.alta = b
        await m.anadirPrograma()
        #expect(m.alta == nil && m.errorAlta == nil)
        #expect(await s.llavero == ["gohighlevel.token": "pit-clave-de-prueba-123"])
        // La clave no queda en ninguna parte del modelo.
        #expect(!String(describing: m.programas).contains("pit-clave") && !String(describing: m.mensajes).contains("pit-clave"))
        #expect(m.programas.map(\.id) == ["gohighlevel"])
        #expect(m.estado(.otros) == .conectado)
        #expect(m.mensajes["gohighlevel"]?.contains("Trae 5 herramientas") == true)
        let ints = try #require(m.interruptores["gohighlevel"])
        #expect(ints.map(\.texto) == ["Comercial puede leer contactos de GoHighLevel", "Comercial puede leer oportunidades de GoHighLevel",
                                      "Comercial puede pedirte cambios (siempre con tu OK) en GoHighLevel"])
        #expect(ints.allSatisfy { !$0.encendido }, "todo empieza apagado")
        #expect(ints.last?.lectura == false, "lo que cambia cosas allí va como «Siempre con tu OK»")
        await m.cambiarInterruptor("gohighlevel", ints[0], encender: true)
        #expect(m.interruptores["gohighlevel"]?.first?.encendido == true)
        // Un segundo GoHighLevel no pisa el primero.
        #expect(m.idNuevo("GoHighLevel") == "gohighlevel2")
        // Avanzado: la matriz técnica, con los nombres de verdad y quién tiene cada una.
        await m.leerMatriz("gohighlevel")
        let matriz = try #require(m.matrices["gohighlevel"])
        #expect(matriz.contains { $0.expuesta == "ext_gohighlevel_contacts_list" && $0.asistentes["comercial"] == true })
        #expect(matriz.contains { $0.nombre == "send_sms" && $0.clase == "sensible" && $0.motivo.contains("send") })
        // Quitar borra su clave.
        await m.quitar("gohighlevel")
        #expect(await s.llavero.isEmpty && m.programas.isEmpty)
    }

    @Test("Revisar herramientas nuevas: tarjeta con lo que trae; activarlas o dejarlas desactivadas")
    func revisarHerramientas() async throws {
        let s = ServiciosDeConexionesEnMemoria()
        await s.sembrar(id: "ghl", nombre: "GoHighLevel", plantilla: "ghl", encendidos: ["leer-contactos"],
                        nuevas: [("contacts_search", true), ("invoice_send", false)])
        let m = Self.modelo(s)
        await m.cargar()
        let r = try #require(m.revisiones.first)
        #expect(r.titulo.contains("2 herramientas nuevas o cambiadas: están desactivadas hasta que las revises"))
        #expect(r.herramientas.first { $0.nombre == "invoice_send" }?.sensible == true)
        #expect(m.programas.first?.porRevisar == 2)
        await m.revisar(r, aceptar: false)
        #expect(m.revisiones.isEmpty)
        #expect(m.programas.first?.porRevisar == 0)
        // Activarlas (con otra tanda) las deja activas, sin dar permiso a nadie.
        await s.sembrar(id: "web", nombre: "Web", plantilla: "web", nuevas: [("form_entries_list", true)])
        await m.cargar()
        let r2 = try #require(m.revisiones.first)
        await m.revisar(r2, aceptar: true)
        #expect(m.revisiones.isEmpty)
        #expect(m.interruptores["web"]?.allSatisfy { !$0.encendido } == true)
    }

    @Test("«Ahora no»: en Ajustes se recuerda por empresa; en el paso es la respuesta; avisos y ventana cerrada se apagan")
    func ahoraNo() async throws {
        let suite = "tls.pruebas.conexiones.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let empresa = UUID()
        let m = Self.modelo(defaults: defaults, empresa: empresa)
        await m.cargar()
        await m.ahoraNo(.banco)
        #expect(m.estado(.banco) == .ahoraNo && m.eleccion(.banco) == false)
        let otra = Self.modelo(defaults: defaults, empresa: empresa)
        #expect(otra.eleccion(.banco) == false, "se recuerda en este Mac")
        await otra.encender(.banco)
        #expect(otra.eleccion(.banco) == nil && otra.estado(.banco) == .conectado)
        await m.encender(.ventanaCerrada)
        #expect(m.estado(.ventanaCerrada) == .conectado && m.palabra(.ventanaCerrada) == "Encendido")
        await m.ahoraNo(.ventanaCerrada)
        #expect(m.estado(.ventanaCerrada) == .ahoraNo)

        final class Respuestas { var r: [ConexionPuesta: Bool] = [:] }
        let respuestas = Respuestas()
        let paso = Self.modelo(modo: .paso(EleccionesDelPaso(leer: { respuestas.r[$0] }, elegir: { respuestas.r[$0] = $1 })))
        await paso.cargar()
        await paso.ahoraNo(.mail)
        await paso.encender(.banco)
        #expect(respuestas.r == [.mail: false, .banco: true])
        #expect(paso.eleccion(.mail) == false)
    }

    @Test("Ningún texto de Conexiones usa jerga (otros programas, no MCP; asistente, no agente)")
    func sinJerga() async {
        let s = ServiciosDeConexionesEnMemoria()
        await s.sembrar(id: "ghl", nombre: "GoHighLevel", plantilla: "ghl", nuevas: [("contacts_search", true)])
        let m = Self.modelo(s)
        await m.cargar()
        var textos: [String] = [ModeloConexiones.queHaceMail, ModeloConexiones.queCreaCalendario, AltaProgramaVista.textoLlavero,
                                AltaProgramaLocalVista.aviso]
        for c in ModeloConexiones.orden { textos += [c.titulo, m.detalle(c), m.palabra(c)] }
        for p in m.plantillas { textos += [p.nombre, p.explicacion] + p.permisos }
        for p in PermisoDeConexion.allCases {
            let e = ServiciosDeConexionesEnMemoria.explicacion(p)
            let r = ServiciosDeConexionesEnMemoria.recuperacion(p)
            textos += [e.titulo, e.para, e.queVeras] + e.hace + e.nunca + [r.titulo, r.texto] + r.pasos
        }
        textos += m.revisiones.flatMap { [$0.titulo] + $0.herramientas.flatMap { [$0.clase, $0.motivo] } }
        textos += (m.interruptores["ghl"] ?? []).map(\.texto)
        for t in textos {
            #expect(GlosarioTests.jerga(t).isEmpty, "«\(t)»")
            let l = t.lowercased()
            #expect(!l.contains("agente") && !l.contains("servidor") && !l.contains("token"), "«\(t)»")
        }
    }
}
