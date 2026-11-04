import Foundation
import MCP
import Testing
@testable import TLSCore
@testable import TLSGateway

/// Piezas de la pasarela sin servidor: clasificación, nombres, recortes, secretos, configuración y sandbox de stdio.
@Suite("Pasarela · piezas")
struct PiezasTests {
    @Test("Nombres con send, publish, pay, charge, refund, invoice, transfer, delete, email, sms o message: sensibles siempre")
    func clasificacion() {
        func tool(_ n: String, _ ro: Bool?) -> Tool {
            Tool(name: n, description: nil, inputSchema: .object(["type": "object"]), annotations: .init(readOnlyHint: ro))
        }
        for n in ["send_message", "sendEmail", "publish_post", "list_payments", "charge_card", "refund", "createinvoice",
                  "transfer-funds", "delete_contact", "sms_list", "list_emails", "get_messages"] {
            #expect(Catalogo.clasificar(tool(n, true)).0 == .sensible, "\(n)")
        }
        #expect(Catalogo.clasificar(tool("list_contacts", true)) == (.lectura, .soloLectura))
        #expect(Catalogo.clasificar(tool("list_contacts", nil)) == (.sensible, .sinIndicacion))
        #expect(Catalogo.clasificar(tool("list_contacts", false)) == (.sensible, .sinIndicacion))
        #expect(Catalogo.palabraSensible("sendSMS") == "send")
    }

    @Test("Nombre expuesto: ext_<servidor>_<herramienta>, limpio, corto y sin choques")
    func nombres() {
        #expect(Catalogo.nombreExpuesto(servidor: "ghl", herramienta: "contacts.list") == "ext_ghl_contacts_list")
        #expect(Catalogo.nombreExpuesto(servidor: "ghl", herramienta: "Get Contact!") == "ext_ghl_get_contact")
        let largo = Catalogo.nombreExpuesto(servidor: "ghl", herramienta: String(repeating: "a", count: 200))
        #expect(largo.count <= 60 && largo.hasPrefix("ext_ghl_"))
        let tools = [Tool(name: "a.b", description: nil, inputSchema: .object([:])),
                     Tool(name: "a-b", description: nil, inputSchema: .object([:]))]
        let (cat, _) = Catalogo.revisar(previo: nil, herramientas: tools, servidor: "x1")
        #expect(Set(cat.herramientas.map(\.expuesta)).count == 2)
    }

    @Test("Descripciones de 300 caracteres como mucho y sin secretos")
    func descripciones() {
        let d = Catalogo.descripcion(String(repeating: "palabra ", count: 100) + " Bearer abcdefghijklmnop")
        #expect(d.count <= 300)
        #expect(Catalogo.descripcion("Usa la clave sk_live_ABCDEFGHIJKLMN para todo") == "Usa la clave [oculto] para todo")
    }

    @Test("Lo que llega de fuera: tipo dato_no_confiable, 20 KB como mucho y secretos ocultados")
    func dato() {
        let grande = String(repeating: "ñ", count: 50_000) + " token=supersecreto123"
        let d = DatoExterno.envolver(grande, origen: "ext:x1:lista", secretos: ["supersecreto123"])
        #expect(d.json.utf8.count <= TLSGatewayInfo.topeDato)
        #expect(d.recortado)
        #expect(d.valor.objectValue?["tipo"]?.stringValue == "dato_no_confiable")
        let corto = DatoExterno.envolver("api_key: \"abcdef123456\" y la mía 9f9f9f9f9f", origen: "ext:x1:a", secretos: ["9f9f9f9f9f"])
        #expect(!corto.contenido.contains("abcdef123456"))
        #expect(!corto.contenido.contains("9f9f9f9f9f"))
        #expect(corto.contenido.contains("api_key"))
    }

    @Test("Interruptores: patrones y permisos por nombre exacto o prefijo")
    func patrones() {
        #expect(Patrones.casa("contacts_list", ["*contact*"]))
        #expect(!Patrones.casa("list_leads", ["*contact*"]))
        #expect(Patrones.casa("anything", ["*"]))
        #expect(Patrones.casa("get_opportunity", ["get_*"]))
        #expect(Patrones.permite(["ext_ghl_*"], expuesta: "ext_ghl_contacts_list"))
        #expect(!Patrones.permite(["ext_*"], expuesta: "ext_ghl_contacts_list"))
        #expect(!Patrones.permite(["ext_ghl_contacts"], expuesta: "ext_ghl_contacts_list"))
    }

    @Test("conexiones.json no admite secretos ni direcciones dudosas; stdio sin claves y con aviso")
    func validacion() throws {
        func http(_ url: String, secretos: [String] = ["token"]) -> Conexion {
            Conexion(id: "web", nombre: "Web", plantilla: "web", transporte: .http(HTTPDeConexion(url: url)), secretos: secretos)
        }
        #expect(throws: Never.self) { try http("https://ejemplo.test/mcp").validar() }
        #expect(throws: ErrorDePasarela.self) { try http("http://ejemplo.test/mcp").validar() }
        #expect(throws: Never.self) { try http("http://localhost:8080/mcp").validar() }
        #expect(throws: ErrorDePasarela.self) { try http("https://ejemplo.test/mcp?api_key=abc").validar() }
        #expect(throws: ErrorDePasarela.self) { try http("https://yo:clave@ejemplo.test/mcp").validar() }
        #expect(throws: ErrorDePasarela.self) { try http("https://ejemplo.test/mcp", secretos: []).validar() }
        var mala = http("https://ejemplo.test/mcp")
        mala.id = "Con Espacios"
        #expect(throws: ErrorDePasarela.self) { try mala.validar() }
        let stdio = Conexion(id: "local", nombre: "Local", plantilla: "generico",
                             transporte: .stdio(StdioDeConexion(ejecutable: "/usr/local/bin/x", argumentos: ["--token", "sk_live_ABCDEFGHIJ"])))
        #expect(throws: ErrorDePasarela.self) { try stdio.validar() }
        let conClave = Conexion(id: "local", nombre: "Local", plantilla: "generico",
                                transporte: .stdio(StdioDeConexion(ejecutable: "/usr/local/bin/x")), secretos: ["token"])
        #expect(throws: ErrorDePasarela.stdioConSecretos) { try conClave.validar() }
    }

    @Test("Añadir guarda la clave en el Llavero y nada más; quitar la borra")
    func anadirYQuitar() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tg-" + UUID().uuidString.prefix(8), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let llavero = LlaveroEnMemoria()
        let p = Pasarela(almacen: AlmacenDeConexiones(directorio: dir), llavero: llavero)
        await #expect(throws: ErrorDePasarela.soloPersonas) {
            try await p.anadir(id: "web", nombre: "Web", plantilla: "web", transporte: .http(HTTPDeConexion(url: "https://e.test")),
                               secretos: ["token": "clave-de-prueba-123"], autor: .agente("comercial"))
        }
        try await p.anadir(id: "web", nombre: "Web", plantilla: "web", transporte: .http(HTTPDeConexion(url: "https://e.test")),
                           secretos: ["token": "clave-de-prueba-123"], autor: .persona("Manu"))
        #expect(llavero.cuentas == ["web.token"])
        let json = try String(contentsOf: dir.appendingPathComponent("conexiones.json"), encoding: .utf8)
        #expect(!json.contains("clave-de-prueba-123"))
        // Una conexión que no valida no deja la clave en el Llavero.
        await #expect(throws: ErrorDePasarela.self) {
            try await p.anadir(id: "otra", nombre: "Otra", plantilla: "web", transporte: .http(HTTPDeConexion(url: "http://e.test")),
                               secretos: ["token": "x"], autor: .persona("Manu"))
        }
        #expect(llavero.cuentas == ["web.token"])
        try await p.quitar("web", autor: .persona("Manu"))
        #expect(llavero.cuentas.isEmpty)
        #expect(p.conexiones().isEmpty)
    }

    @Test("Plantillas de serie: GoHighLevel, Stripe, Calendly, Web y genérica, en lenguaje llano")
    func plantillas() {
        #expect(Set(PlantillasDeSerie.todas.map(\.id)) == ["web", "ghl", "stripe", "calendly", "generico"])
        let p = PlantillasDeSerie.ghl.permisos.first { $0.id == "leer-contactos" }!
        #expect(p.texto(conexion: "GoHighLevel") == "Comercial puede leer contactos de GoHighLevel")
        #expect(PlantillasDeSerie.plantilla("desconocida").id == "generico")
    }

    @Test("Lo que ve la persona no lleva jerga (glosario)")
    func glosario() {
        let prohibidas = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash", "agente", "agentes",
                          "token", "json"]
        var textos: [String] = []
        for p in PlantillasDeSerie.todas {
            textos += [p.nombre, p.explicacion] + p.campos.flatMap { [$0.etiqueta, $0.ayuda] }
            textos += p.permisos.map { $0.texto(conexion: "Programa") } + p.reflejos.map(\.registro.texto)
        }
        let errores: [ErrorDePasarela] = [
            .conexionDesconocida("x"), .identificadorNoValido("x"), .yaExiste("x"), .direccionNoValida("x"), .pareceUnSecreto("x"),
            .faltaSecreto("clave"), .avisoSinAceptar, .stdioConSecretos, .herramientaDesconocida("x"), .herramientaDesactivada("x"),
            .herramientaCambiada("x"), .noEsDeLectura("x"), .noEsSensible("x"), .argumentosNoValidos("x"), .soloPersonas,
            .programaConError("x"), .sinRespuesta("x"), .llavero(-1),
        ]
        textos += errores.compactMap(\.errorDescription)
        textos += [ClaseExterna.lectura.texto, ClaseExterna.sensible.texto, MotivoDeClase.soloLectura.texto,
                   MotivoDeClase.sinIndicacion.texto, MotivoDeClase.nombreSensible("sms").texto]
        textos += [EstadoHerramienta.activa, .pendienteDeRevision, .rechazada, .retirada].map(\.texto)
        textos.append(DatoExterno.aviso)
        for t in textos {
            let palabras = Set(t.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            #expect(prohibidas.filter(palabras.contains).isEmpty, "«\(t)»")
        }
    }

    @Test("Un programa local corre en su sandbox: no lee las carpetas prohibidas, sí su directorio de trabajo")
    func sandboxStdio() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("tg-sb-" + UUID().uuidString.prefix(8), isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let empresa = base.appendingPathComponent("Empresa", isDirectory: true)
        let trabajo = base.appendingPathComponent("trabajo", isDirectory: true)
        try fm.createDirectory(at: empresa, withIntermediateDirectories: true)
        try fm.createDirectory(at: trabajo, withIntermediateDirectories: true)
        try "Expediente privado\n".write(to: empresa.appendingPathComponent("nota.md"), atomically: true, encoding: .utf8)
        try "del programa\n".write(to: trabajo.appendingPathComponent("suyo.txt"), atomically: true, encoding: .utf8)
        let perfil = PerfilDeSandboxStdio.texto(home: fm.homeDirectoryForCurrentUser.path, trabajo: trabajo.path,
                                                ejecutable: "/bin/cat", prohibidas: [empresa.path])
        #expect(perfil.contains("(deny appleevent-send)"))
        #expect(perfil.contains("(deny process-exec (literal \"/usr/bin/osascript\"))"))
        let sb = base.appendingPathComponent("p.sb")
        try perfil.write(to: sb, atomically: true, encoding: .utf8)
        func cat(_ f: URL) throws -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            p.arguments = ["-f", sb.path, "/bin/cat", f.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        }
        #expect(try cat(empresa.appendingPathComponent("nota.md")) != 0)
        #expect(try cat(trabajo.appendingPathComponent("suyo.txt")) == 0)
    }
}
