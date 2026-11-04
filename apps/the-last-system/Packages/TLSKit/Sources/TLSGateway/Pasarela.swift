import Foundation
import MCP
import TLSCore

/// Una herramienta con su conexión.
public struct HerramientaDeConexion: Sendable, Hashable {
    public let conexion: Conexion
    public let herramienta: HerramientaExterna

    /// `ext:<servidor>:<herramienta>`.
    public var origen: String { conexion.origen(herramienta.nombre) }
}

/// Tarjeta «hay herramientas nuevas: revísalas» (una por conexión con algo pendiente).
public struct TarjetaDeRevision: Sendable, Hashable, Identifiable {
    public var id: String { "conexion-revisar:\(conexion):\(huella)" }
    public let conexion: String
    public let nombreConexion: String
    public let herramientas: [HerramientaExterna]
    public let huella: String

    /// «GoHighLevel trae 2 herramientas nuevas o cambiadas: están desactivadas hasta que las revises».
    public var titulo: String {
        let n = herramientas.count
        return n == 1
            ? "\(nombreConexion) trae una herramienta nueva o cambiada: está desactivada hasta que la revises"
            : "\(nombreConexion) trae \(n) herramientas nuevas o cambiadas: están desactivadas hasta que las revises"
    }
}

/// La pasarela de una empresa (PLAN §7.4): sus conexiones, sus clientes abiertos y lo único que puede llamar a otro
/// programa. Los asistentes nunca la ven directamente: pasan por `tls-mcp` (`ext_<servidor>_<herramienta>`), que
/// comprueba sus permisos; lo sensible solo lo llama `GatewayRouter` al aprobar.
public actor Pasarela {
    public nonisolated let almacen: AlmacenDeConexiones
    public nonisolated let llavero: any AlmacenDeSecretos
    nonisolated let fabrica: any FabricaDeClientes
    nonisolated let ahora: @Sendable () -> Date
    private var clientes: [String: any ClienteExterno] = [:]

    public init(almacen: AlmacenDeConexiones, llavero: any AlmacenDeSecretos = LlaveroDelSistema(),
                fabrica: any FabricaDeClientes = FabricaMCP(), ahora: @escaping @Sendable () -> Date = { Date() }) {
        self.almacen = almacen; self.llavero = llavero; self.fabrica = fabrica; self.ahora = ahora
    }

    // MARK: Lo que hace la persona (pantalla Conexiones)

    /// Añade una conexión: los secretos van al Llavero y en `conexiones.json` queda solo el nombre de sus campos.
    @discardableResult
    public func anadir(id: String, nombre: String, plantilla: String, transporte: TransporteDeConexion,
                       secretos: [String: String] = [:], autor: Autor) throws -> Conexion {
        guard autor.esPersona else { throw ErrorDePasarela.soloPersonas }
        guard almacen.conexion(id) == nil else { throw ErrorDePasarela.yaExiste(id) }
        let campos = secretos.filter { !$0.value.isEmpty }.keys.sorted()
        let c = Conexion(id: id, nombre: nombre, plantilla: plantilla, transporte: transporte, secretos: campos,
                         creada: ahora())
        try c.validar()
        for campo in campos { try llavero.guardar(secretos[campo]!, id: id, campo: campo) }
        do {
            try almacen.guardar(c)
        } catch {
            for campo in campos { try? llavero.borrar(id: id, campo: campo) }
            throw error
        }
        return c
    }

    /// Cambia (o pone) una clave. Se cierra el cliente para que la siguiente llamada use la nueva.
    public func cambiarSecreto(_ id: String, campo: String, valor: String, autor: Autor) async throws {
        guard autor.esPersona else { throw ErrorDePasarela.soloPersonas }
        guard let c = almacen.conexion(id) else { throw ErrorDePasarela.conexionDesconocida(id) }
        guard !c.transporte.esStdio else { throw ErrorDePasarela.stdioConSecretos }
        try llavero.guardar(valor, id: id, campo: campo)
        if !c.secretos.contains(campo) { try almacen.cambiar(id) { $0.secretos = ($0.secretos + [campo]).sorted() } }
        await cerrar(id)
    }

    /// Enciende o apaga una conexión (apagada: nadie la ve ni se sincroniza).
    public func activar(_ id: String, _ activa: Bool, autor: Autor) async throws {
        guard autor.esPersona else { throw ErrorDePasarela.soloPersonas }
        try almacen.cambiar(id) { $0.activa = activa }
        if !activa { await cerrar(id) }
    }

    /// Cambia cada cuánto se sincroniza (0 = a mano).
    public func sincronizarCada(_ id: String, minutos: Int, autor: Autor) throws {
        guard autor.esPersona else { throw ErrorDePasarela.soloPersonas }
        try almacen.cambiar(id) { $0.sincronizarCadaMinutos = max(0, minutos) }
    }

    /// Quita la conexión y borra sus claves del Llavero (lo que ya se reflejó en las fichas, se queda).
    public func quitar(_ id: String, autor: Autor) async throws {
        guard autor.esPersona else { throw ErrorDePasarela.soloPersonas }
        guard let c = almacen.conexion(id) else { throw ErrorDePasarela.conexionDesconocida(id) }
        await cerrar(id)
        for campo in c.secretos { try? llavero.borrar(id: id, campo: campo) }
        try almacen.quitar(id)
    }

    /// Revisas lo nuevo o cambiado: «sí» lo activa (con su huella de hoy); «no», lo deja desactivado.
    @discardableResult
    public func revisar(_ id: String, herramientas: [String], aceptar: Bool, autor: Autor) throws -> Conexion {
        guard autor.esPersona else { throw ErrorDePasarela.soloPersonas }
        return try almacen.cambiar(id) { c in
            guard var cat = c.catalogo else { return }
            for i in cat.herramientas.indices where herramientas.contains(cat.herramientas[i].nombre)
                && cat.herramientas[i].estado != .retirada {
                cat.herramientas[i].estado = aceptar ? .activa : .rechazada
            }
            c.catalogo = cat
        }
    }

    // MARK: Conectar y catálogo

    /// Conecta, lista las herramientas y revisa el catálogo (huella; lo nuevo o cambiado, desactivado).
    @discardableResult
    public func conectar(_ id: String) async throws -> CambiosDeCatalogo {
        await cerrar(id)
        return try await refrescar(id)
    }

    /// Vuelve a listar (también al llegar `listChanged`).
    @discardableResult
    public func refrescar(_ id: String) async throws -> CambiosDeCatalogo {
        guard let c = almacen.conexion(id) else { throw ErrorDePasarela.conexionDesconocida(id) }
        let cliente = try await cliente(c)
        let tools: [Tool]
        do {
            tools = try await cliente.listarHerramientas()
        } catch {
            await cerrar(id)
            throw limpiar(error, c)
        }
        let secretos = Array(llavero.secretos(de: c).values)
        var cambios: CambiosDeCatalogo?
        try almacen.cambiar(id) { c in
            let (cat, cam) = Catalogo.revisar(previo: c.catalogo, herramientas: tools, servidor: c.id, secretos: secretos,
                                              ahora: ahora())
            c.catalogo = cat
            cambios = cam
        }
        return cambios!
    }

    /// Lo que espera tu revisión (una tarjeta por conexión).
    public nonisolated func tarjetasDeRevision() -> [TarjetaDeRevision] {
        almacen.todas().compactMap { c in
            guard let cat = c.catalogo, !cat.pendientes.isEmpty else { return nil }
            return TarjetaDeRevision(conexion: c.id, nombreConexion: c.nombre, herramientas: cat.pendientes, huella: cat.huella)
        }
    }

    public nonisolated func conexiones() -> [Conexion] { almacen.todas() }

    /// Las herramientas que se pueden usar: de conexiones activas y activas ellas mismas.
    public nonisolated func herramientasActivas() -> [HerramientaDeConexion] {
        almacen.todas().filter(\.activa).flatMap { c in
            (c.catalogo?.activas ?? []).map { HerramientaDeConexion(conexion: c, herramienta: $0) }
        }
    }

    /// Una herramienta por su nombre expuesto (`ext_<servidor>_<herramienta>`), esté como esté.
    public nonisolated func buscar(expuesta: String) -> HerramientaDeConexion? {
        for c in almacen.todas() {
            if let h = c.catalogo?.herramienta(expuesta: expuesta) { return HerramientaDeConexion(conexion: c, herramienta: h) }
        }
        return nil
    }

    // MARK: Llamar

    /// Una herramienta de **lectura** activa. El resultado es un dato no confiable (20 KB, secretos ocultados).
    public func leer(expuesta: String, argumentos: [String: Value]) async throws -> DatoExterno {
        let hc = try usable(expuesta)
        guard hc.herramienta.clase == .lectura else { throw ErrorDePasarela.noEsDeLectura(hc.herramienta.nombreVisible) }
        try Self.validar(argumentos, esquema: hc.herramienta.esquema)
        let r = try await llamar(hc, argumentos: argumentos)
        return DatoExterno.de(r, origen: hc.origen, secretos: Array(llavero.secretos(de: hc.conexion).values))
    }

    /// Una herramienta **sensible** ya aprobada (solo `GatewayRouter`): con los argumentos exactos aprobados y solo si
    /// la herramienta sigue activa y con la misma huella que cuando se pidió.
    public func ejecutarAprobada(expuesta: String, huella: String, argumentos: [String: Value]) async throws -> DatoExterno {
        let hc = try usable(expuesta)
        guard hc.herramienta.clase == .sensible else { throw ErrorDePasarela.noEsSensible(hc.herramienta.nombreVisible) }
        guard hc.herramienta.huella == huella else { throw ErrorDePasarela.herramientaCambiada(hc.herramienta.nombreVisible) }
        try Self.validar(argumentos, esquema: hc.herramienta.esquema)
        let r = try await llamar(hc, argumentos: argumentos)
        let dato = DatoExterno.de(r, origen: hc.origen, secretos: Array(llavero.secretos(de: hc.conexion).values))
        if r.isError == true { throw ErrorDePasarela.programaConError(Self.textoDeError(dato.contenido, secretos: [])) }
        return dato
    }

    /// Para la sincronización: una de lectura activa, sin comprobar asistentes (eso lo hace quien sincroniza).
    func leerParaReflejo(_ hc: HerramientaDeConexion, argumentos: [String: Value]) async throws -> CallTool.Result {
        let hc = try usable(hc.herramienta.expuesta)
        guard hc.herramienta.clase == .lectura else { throw ErrorDePasarela.noEsDeLectura(hc.herramienta.nombreVisible) }
        return try await llamar(hc, argumentos: argumentos)
    }

    /// Activa, de una conexión activa.
    func usable(_ expuesta: String) throws -> HerramientaDeConexion {
        guard let hc = buscar(expuesta: expuesta) else { throw ErrorDePasarela.herramientaDesconocida(expuesta) }
        guard hc.conexion.activa, hc.herramienta.estado == .activa else {
            throw ErrorDePasarela.herramientaDesactivada(hc.herramienta.nombreVisible)
        }
        return hc
    }

    private func llamar(_ hc: HerramientaDeConexion, argumentos: [String: Value]) async throws -> CallTool.Result {
        let cliente = try await cliente(hc.conexion)
        do {
            return try await cliente.llamar(hc.herramienta.nombre, argumentos: argumentos)
        } catch {
            await cerrar(hc.conexion.id)
            throw limpiar(error, hc.conexion)
        }
    }

    private func cliente(_ c: Conexion) async throws -> any ClienteExterno {
        if let ya = clientes[c.id] { return ya }
        let id = c.id
        let nuevo: any ClienteExterno
        do {
            nuevo = try await fabrica.abrir(c, secretos: llavero.secretos(de: c)) { [weak self] in
                // El programa cambió su lista: se vuelve a listar; lo nuevo queda desactivado hasta que lo revises.
                _ = try? await self?.refrescar(id)
            }
        } catch {
            throw limpiar(error, c)
        }
        clientes[c.id] = nuevo
        return nuevo
    }

    /// S6: lo que cuenta un error del otro programa (o de su transporte) es un dato que trae él: nunca sale tal cual.
    /// Nuestros errores pasan igual; los demás, como `programaConError` con los secretos de la conexión ocultados, en
    /// una línea y recortados (quien lo enseña a un asistente lo envuelve además como dato no confiable).
    nonisolated func limpiar(_ error: any Error, _ c: Conexion) -> ErrorDePasarela {
        if let e = error as? ErrorDePasarela { return e }
        let bruto = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return .programaConError(Self.textoDeError(bruto, secretos: Array(llavero.secretos(de: c).values)))
    }

    /// Un texto de error del otro programa sin secretos, en una línea y con 300 caracteres como mucho.
    public static func textoDeError(_ bruto: String, secretos: [String]) -> String {
        let limpio = Ocultador.ocultar(bruto, secretos: secretos)
        let linea = limpio.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined().trimmingCharacters(in: .whitespaces)
        return linea.count > 300 ? String(linea.prefix(300)) + "…" : linea
    }

    public func cerrar(_ id: String) async {
        if let c = clientes.removeValue(forKey: id) { await c.cerrar() }
    }

    public func cerrarTodo() async {
        for id in Array(clientes.keys) { await cerrar(id) }
    }

    // MARK: Argumentos

    /// Un objeto JSON de 16 KB como mucho; si el esquema dice qué claves hay y no admite más, solo esas; las
    /// obligatorias, presentes.
    public static func validar(_ args: [String: Value], esquema: Value) throws {
        guard JSONCanonico.texto(Value.object(args)).utf8.count <= TLSGatewayInfo.topeArgumentos else {
            throw ErrorDePasarela.argumentosNoValidos("son demasiado largos.")
        }
        guard case .object(let e) = esquema else { return }
        if case .object(let props)? = e["properties"], e["additionalProperties"] == .bool(false) {
            if let sobra = args.keys.sorted().first(where: { props[$0] == nil }) {
                throw ErrorDePasarela.argumentosNoValidos("sobra «\(sobra)».")
            }
        }
        if case .array(let req)? = e["required"] {
            for r in req.compactMap(\.stringValue) where args[r] == nil {
                throw ErrorDePasarela.argumentosNoValidos("falta «\(r)».")
            }
        }
    }
}
