import Foundation

// F3 · rol motor. «Aplicar» y «Deshacer» de la puesta en marcha: lo único que escribe en la carpeta, siempre por
// `CommandBus` y como la persona (criterio F3-1). Nunca en la carpeta real.

public enum AplicadorPuesta {
    /// Escribe el plan de la vista previa (todo o nada). `nil` si no había nada que escribir.
    @discardableResult
    public static func aplicar(_ vista: VistaPreviaPaso, bus: CommandBus) async throws -> WriteResult? {
        guard let plan = vista.plan else { return nil }
        let entrada = bus.writer.entry
        guard entrada.clase != .real else { throw ErrorPuesta.carpetaReal }
        guard entrada.escritura == .permitida else { throw ErrorPuesta.soloLectura }
        guard plan.autor.esPersona else { throw ErrorPuesta.soloLectura }
        return try await bus.ejecutar(plan)
    }

    /// «Empiezo de cero»: al aplicar el paso 0 se crea la carpeta en `empresas` (`~/The Last System/Empresas/`), se
    /// registra en `vaults.json` con el identificador de la puesta en marcha y se escribe el plan de la vista previa.
    /// Antes de «Aplicar» no existe nada en el disco.
    public static func empezarDeCero(_ vista: VistaPreviaPaso, nombre: String, vaultID: UUID,
                                     empresas: URL = AppLocations.empresas,
                                     registro: VaultRegistry = VaultRegistry(),
                                     appSupport: URL = AppLocations.appSupport) async throws -> (VaultEntry, WriteResult?) {
        let limpio = NombresDeFicha.fichero(nombre).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { throw ErrorPuesta.nombreVacio }
        guard !AppLocations.isInICloudDrive(empresas.path) else { throw ErrorPuesta.estadoEnICloud }
        let fm = FileManager.default
        try fm.createDirectory(at: empresas, withIntermediateDirectories: true)
        var root = empresas.appendingPathComponent(limpio, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: root.path) {
            root = empresas.appendingPathComponent("\(limpio) \(n)", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let entrada = VaultEntry(id: vaultID, nombre: nombre, ruta: root.path, bookmark: try? VaultRegistry.makeBookmark(for: root),
                                 clase: .copia, escritura: .permitida)
        try registro.upsert(entrada)
        let writer = try await VaultWriter.open(entry: entrada, root: root,
                                                options: .init(stateDirectory: appSupport.appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true),
                                                               appSupport: appSupport))
        let bus = CommandBus(writer: writer)
        let resultado = try await aplicar(vista, bus: bus)
        await writer.close()
        return (entrada, resultado)
    }

    /// Deshace un paso si su plan es lo último que se escribió en la carpeta (si no, avisa de qué hay después).
    public static func deshacer(_ paso: PasoPuesta, estado: EstadoPuestaEnMarcha, bus: CommandBus) async throws -> WriteResult {
        guard let id = estado.paso(paso).plan else { throw ErrorPuesta.nadaQueDeshacer }
        guard let ultimo = await bus.ultimoDeshacible() else { throw ErrorPuesta.nadaQueDeshacer }
        guard ultimo.planID == id else { throw ErrorPuesta.otroPlanDespues(ultimo.descripcion) }
        return try await bus.deshacer(autor: .persona(estado.persona))
    }
}

extension OnboardingEngine {
    /// «Aplicar»: escribe el paso y lo marca hecho (con su plan para «Deshacer»). Sin nada que escribir, solo lo marca.
    @discardableResult
    public mutating func aplicar(_ vista: VistaPreviaPaso, bus: CommandBus) async throws -> WriteResult? {
        let r = try await AplicadorPuesta.aplicar(vista, bus: bus)
        let resumen = vista.nadaQueEscribir ? "Nada que escribir en tu carpeta" : vista.resumen
        marcarAplicado(vista.paso, plan: r.flatMap { $0.hecho ? $0.planID : nil }, resumen: resumen)
        return r
    }

    /// «Empiezo de cero» al aplicar el paso 0: crea y registra la carpeta y escribe el plan.
    @discardableResult
    public mutating func aplicarEmpezarDeCero(_ vista: VistaPreviaPaso, empresas: URL = AppLocations.empresas,
                                              registro: VaultRegistry = VaultRegistry(),
                                              appSupport: URL = AppLocations.appSupport) async throws -> VaultEntry {
        let nombre = valor(.nombreEmpresa)?.texto ?? contexto.nombreEmpresa ?? "Mi empresa"
        let (entrada, r) = try await AplicadorPuesta.empezarDeCero(vista, nombre: nombre, vaultID: estado.vaultID,
                                                                   empresas: empresas, registro: registro, appSupport: appSupport)
        estado.ruta = .empresaNueva
        marcarAplicado(.bienvenida, plan: r?.planID, resumen: vista.resumen)
        cambiarContexto(ContextoCarpeta.leer(URL(fileURLWithPath: entrada.ruta), entrada: entrada, reloj: contexto.reloj,
                                             catalogo: contexto.catalogo))
        return entrada
    }

    /// «Deshacer» de un paso aplicado (vuelve a estar pendiente, con las mismas respuestas).
    @discardableResult
    public mutating func deshacer(_ paso: PasoPuesta, bus: CommandBus) async throws -> WriteResult {
        let r = try await AplicadorPuesta.deshacer(paso, estado: estado, bus: bus)
        marcarDeshecho(paso)
        return r
    }
}
