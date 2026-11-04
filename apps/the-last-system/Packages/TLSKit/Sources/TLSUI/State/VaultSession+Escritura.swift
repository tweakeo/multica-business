import Foundation
import TLSCore
import TLSDesign

/// Escritura en la carpeta (F1). **Todo** pasa por `CommandBus`; nunca se escribe con `FileManager` en la
/// carpeta de la empresa, nunca se borra (retirar mueve a `Archivo/`) y cada cambio se puede deshacer.
public extension VaultSession {
    // MARK: Escribir

    /// Escribe una orden sencilla como la persona (`Autor.persona`), la deja en Deshacer (⌘Z de la pestaña con
    /// el foco o `deshacer`) y enseña el aviso «… · Deshacer».
    ///
    /// - `aviso`: texto del aviso («Enlacé la reunión del 14 oct a Arquitectura Nexo»). `nil` = la
    ///   descripción del cambio. Cadena vacía = sin aviso.
    /// - Un conflicto no lanza: devuelve `.conflicto`, guarda la tarjeta en «Revisar» y lo avisa.
    /// - Si la carpeta está en solo lectura lanza `WriteError.soloLectura` (o `.carpetaReal`).
    /// - Reglas (integración F2): con escritor, lo escrito pasa por el motor del dominio (`MotorDeDominio.escribirYAtender`):
    ///   sus eventos van a la bandeja de salida y las reglas los atienden como sistema. «Deshacer» deshace la cadena entera
    ///   (lo de las reglas y luego lo tuyo). Las invariantes no se vuelven a mirar aquí: para eso, `escribirConDominio`.
    @discardableResult
    func escribir(_ comando: CommandBus.Comando, aviso: String? = nil, deshacer: UndoManager? = nil) async throws -> WriteResult {
        let bus = try busParaEscribir()
        do {
            if let motor = DominioEmpresa.motor(de: self) {
                let r = try await motor.escribirYAtender(comando, autor: autor)
                despuesDeEscribir(r.escritura, descripcion: Self.descripcion(de: comando), aviso: Self.aviso(aviso, r), deshacer: deshacer,
                                  cadena: Self.planesDeReglas(r))
                return r.escritura
            }
            let resultado = try await bus.ejecutar(comando, autor: autor)
            despuesDeEscribir(resultado, descripcion: Self.descripcion(de: comando), aviso: aviso, deshacer: deshacer)
            return resultado
        } catch let e as DominioError {
            // VEN-07 (Ganada sin cobro confirmado): no es un fallo, es la regla; se dice en ámbar.
            self.aviso = Aviso(e.localizedDescription, estado: .atencion)
            throw e
        } catch {
            self.aviso = Aviso(error.localizedDescription, estado: .mal)
            throw error
        }
    }

    /// El aviso tras escribir: si ENT-04 corrió una fecha del sábado o el domingo al lunes, eso es lo que se dice.
    static func aviso(_ pedido: String?, _ r: ResultadoDominio) -> String? {
        let ent04 = r.invariantes.avisos.filter { $0.codigo == "ENT-04" }.map(\.mensaje)
        guard !ent04.isEmpty, pedido != "" else { return pedido }
        return ent04.joined(separator: " ")
    }

    /// Escribe un plan compuesto (todo o nada): plantillas, renombrar con sus enlaces, cambios en bloque.
    /// Mismo comportamiento que `escribir(_:)`. El autor del plan debe ser `autor`.
    @discardableResult
    func escribir(plan: WritePlan, aviso: String? = nil, deshacer: UndoManager? = nil) async throws -> WriteResult {
        let bus = try busParaEscribir()
        do {
            if plan.autor.esPersona, let motor = DominioEmpresa.motor(de: self) {
                let r = try await motor.escribirYAtender(plan)
                despuesDeEscribir(r.escritura, descripcion: plan.descripcion, aviso: Self.aviso(aviso, r), deshacer: deshacer,
                                  cadena: Self.planesDeReglas(r))
                return r.escritura
            }
            let resultado = try await bus.ejecutar(plan)
            despuesDeEscribir(resultado, descripcion: plan.descripcion, aviso: aviso, deshacer: deshacer)
            return resultado
        } catch let e as DominioError {
            self.aviso = Aviso(e.localizedDescription, estado: .atencion)
            throw e
        } catch {
            self.aviso = Aviso(error.localizedDescription, estado: .mal)
            throw error
        }
    }

    /// Deja en Deshacer un resultado escrito por otro camino (p. ej. `LinkRefactor.aplicar(_:con: bus)`).
    /// `cadena`: los planes que escribieron las reglas después (en orden); «Deshacer» los quita también.
    func registrarDeshacer(_ resultado: WriteResult, descripcion: String, aviso: String? = nil, deshacer: UndoManager? = nil,
                           cadena: [UUID] = []) {
        despuesDeEscribir(resultado, descripcion: descripcion, aviso: aviso, deshacer: deshacer, cadena: cadena)
    }

    /// Deshace un plan concreto si es el último que se puede deshacer en esta carpeta. Lo llama el
    /// UndoManager (⌘Z) y el botón «Deshacer» del aviso.
    func deshacer(plan: UUID) async {
        await deshacer(plan: plan, cadena: [])
    }

    /// Deshace un plan de la persona y, antes, los de las reglas que lo siguieron (`cadena`, en el orden en que se
    /// escribieron): el más reciente primero, de uno en uno, y solo si cada uno es el último que se puede deshacer.
    /// Después, el dominio olvida esos eventos para que, si se repite, las reglas vuelvan a atenderlo.
    func deshacer(plan: UUID, cadena: [UUID]) async {
        guard let bus else {
            aviso = Aviso("No se puede deshacer: esta carpeta está ahora en solo lectura.", estado: .atencion)
            return
        }
        let orden = Array(cadena.reversed()) + [plan]
        var deshechos: [UUID] = []
        var movidas: [(de: VaultPath, a: VaultPath)] = []
        defer {
            aplicarMovimientos(movidas)
            if !deshechos.isEmpty { DominioEmpresa.olvidar(deshechos, de: self) }
        }
        for p in orden {
            if let ultimo = await bus.ultimoDeshacible(), ultimo.planID != p {
                aviso = deshechos.isEmpty
                    ? Aviso("Antes hay que deshacer «\(ultimo.descripcion)», que es más reciente.", estado: .atencion)
                    : Aviso("Deshice una parte: falta «\(ultimo.descripcion)», que cambió después.", estado: .atencion)
                return
            }
            do {
                let r = try await bus.deshacer(autor: autor)
                if let conflicto = r.conflicto {
                    aviso = Aviso("No lo he deshecho: «\(conflicto.ruta.stem)» cambió fuera. Lo tienes en Revisar.", estado: .atencion)
                    recargarTarjetas()
                    return
                }
                deshechos.append(p)
                // Deshacer un renombrado o un movimiento devuelve las rutas: las pestañas vuelven con ellas.
                movidas += r.movidas.map { (de: $0.de, a: $0.a) }
            } catch {
                aviso = Aviso(error.localizedDescription, estado: .mal)
                return
            }
        }
        aviso = Aviso(cadena.isEmpty ? "Deshecho" : "Deshecho, también lo que hicieron las reglas", estado: .bien)
    }

    /// Los planes que escribieron las reglas tras un plan de la persona, en orden (para deshacer la cadena).
    static func planesDeReglas(_ r: ResultadoDominio) -> [UUID] {
        r.reglas.compactMap {
            switch $0.resultado {
            case .hecho(_, let plan), .tareaParaPersona(_, let plan): plan
            default: nil
            }
        }
    }

    // MARK: Revisar (conflictos, duplicados, iCloud, recuperación)

    /// «Quedarme con la mía», «con la de fuera» o el texto combinado.
    func resolver(_ tarjeta: ConflictRecord, eleccion: CommandBus.EleccionConflicto) async {
        await resolverCon("Resuelto el conflicto de «\(tarjeta.ruta.stem)»") { bus, autor in
            try await bus.resolverConflicto(tarjeta.id, eleccion: eleccion, autor: autor)
        }
    }

    /// Duplicado: aparta la repetida (o el original, si te quedas con la repetida) en `Archivo/Duplicados`.
    func descartarDuplicado(_ tarjeta: ConflictRecord, quedarmeConLaRepetida: Bool = false) async {
        await resolverCon("Apartada la copia repetida de «\(tarjeta.ruta.stem)»") { bus, autor in
            try await bus.descartarDuplicado(tarjeta.id, quedarmeConElDuplicado: quedarmeConLaRepetida, autor: autor)
        }
    }

    /// Conflicto de iCloud: `version` = índice de la versión guardada (`nil` = la de ahora).
    func resolverICloud(_ tarjeta: ConflictRecord, quedarmeCon version: Int?) async {
        await resolverCon("Resuelto el conflicto de iCloud de «\(tarjeta.ruta.stem)»") { bus, autor in
            try await bus.resolverICloud(tarjeta.id, quedarmeCon: version, autor: autor)
        }
    }

    /// «Entendido» en la tarjeta de lo recuperado al abrir.
    func olvidarRecuperacion() {
        recuperacion = nil
    }

    /// Texto llano de lo que hizo la recuperación al abrir (`nil` si no hizo nada).
    var textoRecuperacion: String? {
        guard let r = recuperacion else { return nil }
        var partes: [String] = []
        if r.completados > 0 { partes.append(TLSFormat.cuenta(r.completados, "cambio que había quedado a medias se terminó", "cambios que habían quedado a medias se terminaron")) }
        if r.aplicados > 0 { partes.append(TLSFormat.cuenta(r.aplicados, "cambio pendiente se aplicó", "cambios pendientes se aplicaron")) }
        if r.abandonados > 0 { partes.append(TLSFormat.cuenta(r.abandonados, "cambio sin empezar se dejó como estaba", "cambios sin empezar se dejaron como estaban")) }
        return partes.isEmpty ? nil : "Al abrir: " + partes.joined(separator: "; ") + "."
    }

    /// Hay algo que revisar (lo enseña Hoy).
    var hayQueRevisar: Bool { !tarjetas.isEmpty || textoRecuperacion != nil }

    // MARK: Modo de escritura

    /// Guarda ya lo que los editores de esta empresa aún tienen pendiente (la espera de 800 ms tras la última
    /// tecla). Lo usan pasar a solo lectura y salir de la app.
    func guardarPendientes() async {
        await GuardadosPendientes.compartido.guardarTodo(de: self)
    }

    /// Pasa la copia a solo lectura: antes guarda lo que los editores tengan pendiente (si no, se perdería al
    /// cerrar la nota), desconecta el escritor y lo cierra; se recuerda en la lista.
    func pasarASoloLectura(using model: AppModel) async {
        await guardarPendientes()
        // F4: los asistentes de esta empresa se paran antes de cerrar el escritor.
        if writer != nil, let integracion { await integracion.escritorSeVa(self) }
        if let w = writer {
            if let service { await service.desconectar(w) }
            await w.close()
        }
        writer = nil
        bus = nil
        var e = entry
        e.escritura = .bloqueada
        try? model.register(e)
        entry = e
        modoEscritura = .soloLectura(.elegido)
    }

    /// Vuelve a permitir cambios en una copia o en el ejemplo (nunca en la carpeta real).
    func permitirCambios(using model: AppModel) async {
        guard entry.clase != .real || esRealConRelevo else { return }
        var e = entry
        e.escritura = .permitida
        do { try model.register(e) } catch {
            aviso = Aviso(error.localizedDescription, estado: .mal)
            return
        }
        entry = e
        await conectarEscritor()
    }
}

extension VaultSession {
    /// Abre el escritor en copias y en el ejemplo con escritura; la carpeta real nunca.
    func conectarEscritor() async {
        guard let service, let root else { return }
        // F6 · integración: la real solo con el relevo hecho (y `escritura: permitida`).
        guard entry.clase != .real || esRealConRelevo else {
            modoEscritura = .soloLectura(.carpetaReal)
            return
        }
        guard entry.escritura == .permitida else {
            modoEscritura = .soloLectura(.elegido)
            recargarTarjetas()
            return
        }
        if writer != nil { modoEscritura = .escribe; return }
        do {
            var options = VaultWriter.Options()
            options.registroDeRelevo = registroDeRelevo
            if let estado {
                options.stateDirectory = estado
                options.appSupport = estado.appendingPathComponent("asup", isDirectory: true)
            }
            let w = try await VaultWriter.open(entry: entry, root: root, options: options)
            guard self.service === service else { await w.close(); return }
            writer = w
            bus = CommandBus(writer: w)
            _ = await service.conectar(w) { [weak self] paths in
                Task { @MainActor in self?.escrituraAplicada(paths) }
            }
            let rec = await w.lastRecovery
            recuperacion = (rec.completados + rec.aplicados + rec.abandonados) > 0 ? rec : nil
            modoEscritura = .escribe
            recargarTarjetas()
            buscarDuplicados()
            // F4: con el escritor listo, la integración monta los asistentes de esta empresa.
            integracionEscritorListo()
        } catch {
            Self.log.error("No se pudo abrir el escritor: \(String(describing: error), privacy: .private)")
            modoEscritura = .soloLectura(.noSePudo(error.localizedDescription))
            recargarTarjetas()
        }
    }

    /// Las dos versiones completas de una tarjeta de edición o de recuperación, para «Combinar» en Revisar:
    /// «tu versión» (la copia que guardó la app) y la que hay ahora en la carpeta. Solo lee.
    func versionesParaCombinar(_ t: ConflictRecord) -> (mia: String, deFuera: String)? {
        guard t.tipo == .edicion || t.tipo == .recuperacion, let writer, let root else { return nil }
        let registro = writer.conflicts
        guard let version = t.versiones.first(where: {
            if case .copia = $0.ubicacion { return $0.etiqueta != "La de fuera" } else { return false }
        }), let mia = registro.datos(de: version, root: root).flatMap(TextDecoding.decode),
              let fuera = AjustesBases.leerTexto(t.ruta, root: root) else { return nil }  // sin enlaces ni iCloud
        return (mia, fuera)
    }

    /// Relee las tarjetas pendientes (del escritor o, en solo lectura, del registro guardado).
    func recargarTarjetas() {
        guard entry.clase != .real || esRealConRelevo else { tarjetas = []; return }
        let registro = writer?.conflicts ?? ConflictRegistry(stateDirectory: directorioEstado)
        tarjetas = registro.pendientes().sorted { $0.fecha > $1.fecha }
    }

    /// Duplicados «X 2.md» en toda la carpeta (al abrir), fuera del hilo principal.
    func buscarDuplicados() {
        guard let writer, let root else { return }
        let excluidas = entry.exclusionesCopia.map { VaultPath($0) }
        let layout = service?.layout
        Task { [weak self] in
            let registro = writer.conflicts
            _ = await Task.detached(priority: .utility) {
                let d = DuplicateDetector(root: root, excluidas: excluidas, layout: layout)
                return try? d.registrar(d.scan(), en: registro)
            }.value
            self?.recargarTarjetas()
        }
    }

    /// Cambios de fuera: duplicados nuevos y versiones en conflicto de iCloud en esas rutas.
    func revisarCambiosDeFuera(_ paths: [VaultPath]) async {
        guard let writer, let root else { return }
        let excluidas = entry.exclusionesCopia.map { VaultPath($0) }
        let layout = service?.layout
        let registro = writer.conflicts
        _ = await Task.detached(priority: .utility) {
            let d = DuplicateDetector(root: root, excluidas: excluidas, layout: layout)
            _ = try? d.registrar(d.scan(paths: paths), en: registro)
            _ = try? ICloudConflicts.scan(paths, root: root, registry: registro)
        }.value
        recargarTarjetas()
    }

    func busParaEscribir() throws -> CommandBus {
        if let bus { return bus }
        throw entry.clase == .real ? WriteError.carpetaReal : WriteError.soloLectura
    }

    private func resolverCon(_ texto: String, _ hacer: (CommandBus, Autor) async throws -> WriteResult) async {
        guard let bus else {
            aviso = Aviso("Para resolverlo, permite los cambios en esta copia (abajo, en la barra lateral).", estado: .atencion)
            return
        }
        do {
            let r = try await hacer(bus, autor)
            despuesDeEscribir(r, descripcion: texto, aviso: texto, deshacer: nil)
        } catch {
            aviso = Aviso(error.localizedDescription, estado: .mal)
        }
        recargarTarjetas()
    }

    func despuesDeEscribir(_ resultado: WriteResult, descripcion: String, aviso texto: String?, deshacer um: UndoManager?,
                           cadena: [UUID] = []) {
        switch resultado.estado {
        case .hecho:
            let plan = resultado.planID
            let manager = um ?? undoManagerActivo
            if let manager {
                manager.registerUndo(withTarget: self) { sesion in
                    MainActor.assumeIsolated {
                        let tarea: @MainActor () async -> Void = { await sesion.deshacer(plan: plan, cadena: cadena) }
                        Task { @MainActor in await tarea() }
                    }
                }
                manager.setActionName(descripcion)
            }
            if texto != "" {
                aviso = Aviso(texto ?? descripcion) { [weak self] in
                    Task { await self?.deshacer(plan: plan, cadena: cadena) }
                }
            }
            aplicarMovimientos(resultado.movidas.map { (de: $0.de, a: $0.a) })
        case .sinCambios:
            break
        case .conflicto(let c):
            aviso = Aviso("No lo he guardado: «\(c.ruta.stem)» cambió fuera de la app. Tienes las dos versiones en Revisar.",
                          estado: .atencion, tituloAccion: "Revisar") { [weak self] in
                self?.navegar(a: .revisar, modo: .entrar)
            }
            recargarTarjetas()
        }
    }

    /// Texto para «Deshacer» y el aviso (el de `CommandBus` no es público).
    static func descripcion(de comando: CommandBus.Comando) -> String {
        switch comando {
        case .crear(let p, _): "Crear «\(p.stem)»"
        case .cambiarPropiedades(let p, _, _): "Cambiar «\(p.stem)»"
        case .guardarNota(let p, _, _), .sustituirCuerpo(let p, _, _): "Guardar «\(p.stem)»"
        case .anadirASeccion(let p, let s, _): "Añadir a «\(s)» en «\(p.stem)»"
        case .sustituirSeccion(let p, let s, _, _): "Cambiar «\(s)» en «\(p.stem)»"
        case .anadirLinea(let p, _): "Añadir una línea a «\(p.stem)»"
        case .guardarFila(let p, _, _): "Guardar una fila en «\(p.stem)»"
        case .cambiarCeldas(let p, _, _, _, _): "Cambiar una tabla de «\(p.stem)»"
        case .anadirFilaATabla(let p, _, _): "Añadir una fila a «\(p.stem)»"
        case .mover(let a, let b): a.parent == b.parent ? "Renombrar «\(a.stem)»" : "Mover «\(a.stem)»"
        case .retirar(let p): "Retirar «\(p.stem)»"
        }
    }
}
