import Foundation
import TLSCore
import TLSDesign
import TLSImport
import TLSUI

// F3 · rol pasos. Lo que hacen los botones de la puesta en marcha (PLAN §6.7, patrón de cada paso): guardar lo
// escrito, «Siguiente», la vista previa, «Aplicar» (solo aquí se escribe en la carpeta, por `CommandBus` y como la
// persona), «Deshacer», la copia de la bienvenida, «Ver sin tocar», «Empiezo de cero», el ejemplo, Claude Code y el
// final (el recorrido sobre tu empresa). Las vistas solo llaman a esto; las pruebas, también.

/// La copia de la carpeta de la empresa (bienvenida con carpeta).
public enum EstadoCopia: Equatable, Sendable {
    case copiando(fase: String, hechos: Int, total: Int?)
    case cancelando
    case cancelada
    case hecha(String)
}

/// Lo que se aplicó en la pantalla («Crear 9 · Cambiar 2 · No se borra nada»), para el resumen y «Deshacer».
public struct ResumenAplicado: Equatable, Sendable {
    public let paso: PasoPuesta
    public let texto: String
    public let detalle: String?
    public let sePuedeDeshacer: Bool
}

/// El botón principal de la pantalla (↩).
public enum AccionPrincipal: Equatable, Sendable {
    case siguiente
    case aplicar
    /// «Aplicar» de «Ordenar lo que tienes» (vista previa o «Completar las fichas»).
    case aplicarOrdenar
    case hacerCopia
    case abrirSinTocar
    case crearCarpeta
    case abrirEjemplo
    case abrirAjustes
    case empezarRecorrido
    case terminar
    case abrirMiCarpeta

    public var titulo: String {
        switch self {
        case .siguiente: "Siguiente"
        case .aplicar, .aplicarOrdenar: "Aplicar"
        case .hacerCopia: "Hacer la copia"
        case .abrirSinTocar: "Abrir sin tocar"
        case .crearCarpeta: "Crear la carpeta"
        case .abrirEjemplo: "Abrir el ejemplo"
        case .abrirAjustes: "Abrir Ajustes del Sistema"
        case .empezarRecorrido: "Empezar el recorrido"
        case .terminar: "Terminar"
        case .abrirMiCarpeta: "Abrir mi carpeta"
        }
    }
}

extension ModeloPuesta {
    // MARK: Qué se ve

    /// La respuesta que se enseña (la de la persona o la premarcada, con su origen).
    public func respuesta(_ id: PreguntaID) -> Respuesta? { motor.respuesta(id) }

    /// El paso ya está escrito (o se dejó para más tarde).
    public func pasoHecho(_ p: PasoPuesta) -> Bool { motor.estado.paso(p).fase != .pendiente }

    /// Es la última pantalla.
    public var esUltima: Bool { pantallas.last?.id == pantalla?.id }

    /// La carpeta ya es una copia (o el ejemplo): la bienvenida no tiene que copiar nada.
    public var yaHayCarpeta: Bool {
        guard let e = motor.contexto.entrada else { return false }
        return e.clase == .copia || e.clase == .demo
    }

    /// Repasar una puesta en marcha terminada (el ejemplo): se mira, no se escribe.
    public var repasando: Bool { peticion?.modo == .repasar }

    public var accionPrincipal: AccionPrincipal {
        guard let p = pantalla else { return .terminar }
        if p.id == "bienvenida.recuperacion" { return .abrirAjustes }
        if p.id == "bienvenida.como", motor.valor(.como)?.opcion == "ejemplo", !repasando { return .abrirEjemplo }
        if p.paso == .ordenar, ConexionOrdenar.porAplicar(self) != nil { return .aplicarOrdenar }
        if !repasando, p.aplicaAqui, p.paso.escribeEnLaCarpeta, motor.estado.paso(p.paso).fase == .pendiente {
            switch p.paso {
            case .bienvenida:
                if motor.ruta == .empresaNueva { return .crearCarpeta }
                if yaHayCarpeta { return .siguiente }
                return motor.soloMirar ? .abrirSinTocar : .hacerCopia
            case .ordenar:
                return .siguiente
            default:
                return .aplicar
            }
        }
        if esUltima {
            if motor.soloMirar { return .abrirMiCarpeta }
            if !repasando, motor.valor(.recorrido)?.opcion == "ahora" { return .empezarRecorrido }
            return .terminar
        }
        return .siguiente
    }

    /// Por qué no se puede pulsar el botón principal (se dice al lado, §1.3). `nil`: se puede.
    public var motivoSinPrincipal: String? {
        if trabajando { return "Un momento…" }
        if accionPrincipal == .aplicarOrdenar, let o = ConexionOrdenar.porAplicar(self) {
            if o.trabajo != nil { return o.trabajo == .aplicando ? "Aplicando…" : "Espera un momento" }
            return o.motivoNoAplicar
        }
        if [.hacerCopia, .abrirSinTocar].contains(accionPrincipal), let f = faltaParaLaCarpeta { return f }
        if pantalla?.id == "bienvenida.como", motor.valor(.como) == nil { return "Elige cómo empiezas." }
        if case .copiando = copia { return "Copiando…" }
        if case .cancelando = copia { return "Parando la copia…" }
        return nil
    }

    // MARK: Contestar

    /// Contesta y, si la pantalla enseña lo que se escribirá, lo vuelve a preparar.
    public func contestar(_ id: PreguntaID, _ valor: ValorRespuesta) async {
        borradores[id] = nil
        error = nil
        await responder(id, valor)
        await sincronizarEtapa(id)
        programarVistaPrevia()
    }

    /// «No lo sé»: se guarda y se escribirá PENDIENTE.
    public func noLoSeYGuardar(_ id: PreguntaID) {
        borradores[id] = nil
        error = nil
        noLoSe(id)
        Task { await sincronizarEtapa(id) }
        programarVistaPrevia()
    }

    /// «Lo contesto luego» (en un resumen): lo que sigue en blanco queda como «No lo sé» y se escribirá PENDIENTE.
    public func contestarLuego(_ ids: [PreguntaID]) {
        for id in ids { borradores[id] = nil }
        error = nil
        actualizar { $0.contestarLuego(ids) }
        faltanDespuesDeContestar(ids)
        programarVistaPrevia()
    }

    /// Las preguntas de etapa de un área («conocer.VEN.etapa.3») dicen la etapa: se guarda también como la etapa del
    /// área (lo que el resumen elige directamente). Así manda lo contestado y no la etapa que la app calcula al crear
    /// la carpeta (ver «Cambios pedidos › pasos»).
    func sincronizarEtapa(_ id: PreguntaID) async {
        let partes = id.rawValue.split(separator: ".")
        guard partes.count == 4, partes[0] == "conocer", partes[2] == "etapa",
              let area = AreaCode(rawValue: String(partes[1])) else { return }
        var etapa: ValorRespuesta?
        for n in 1...6 {
            guard let v = motor.valor(.etapaPregunta(area, n)) else { return }
            if v.esNoLoSe { etapa = .noLoSe; break }
            if v.siNo != true { etapa = .escala(n); break }
        }
        let valor = etapa ?? .escala(6)
        guard motor.estado.respuesta(.etapa(area))?.valor != valor else { return }
        if valor.esNoLoSe { noLoSe(.etapa(area)) } else { await responder(.etapa(area), valor) }
    }

    /// Guarda lo escrito en los campos (o solo en uno). `false` si el entrevistador repregunta algo: no se sigue,
    /// se enseña la repregunta (una vez).
    @discardableResult
    public func guardarBorradores(solo: PreguntaID? = nil) async -> Bool {
        var repregunta = false
        let ids = solo.map { borradores[$0] == nil ? [] : [$0] } ?? borradores.keys.sorted()
        for id in ids {
            guard let texto = borradores[id] else { continue }
            borradores[id] = nil
            guard let q = motor.pregunta(id) else { continue }
            let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            let nuevo: ValorRespuesta?
            switch q.tipo {
            case .textoCorto, .textoLibre, .hora:
                nuevo = limpio.isEmpty && motor.estado.respuesta(id) == nil ? nil : .texto(limpio)
            case .cifra:
                if limpio.isEmpty { nuevo = nil }
                else if let n = FormatoBase.numero(limpio) { nuevo = .numero(n) }
                else {
                    borradores[id] = texto
                    error = "«\(limpio)» no es una cifra. Escríbela solo con números, por ejemplo 1200 o 2,5."
                    return false
                }
            default:
                nuevo = nil
            }
            guard let nuevo, motor.valor(id) != nuevo || motor.estado.respuesta(id) == nil else { continue }
            let antes = repreguntas[id]
            await responder(id, nuevo)
            if repreguntas[id] != nil, antes == nil { repregunta = true }
        }
        programarVistaPrevia()
        return !repregunta
    }

    /// Guarda un solo campo (al pulsar ↩ en él o al salir).
    public func guardarBorrador(_ id: PreguntaID) async {
        await guardarBorradores(solo: id)
    }

    // MARK: Vista previa

    /// Vuelve a preparar la vista previa al poco de contestar (solo en las pantallas que la enseñan).
    public func programarVistaPrevia() {
        guard let p = pantalla, p.conVistaPrevia, p.paso.escribeEnLaCarpeta, !pasoHecho(p.paso) else { return }
        tareaVista?.cancel()
        tareaVista = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            // Mientras un botón trabaja (aplicar, copiar), la vista previa no cambia: es la que se va a escribir.
            guard !Task.isCancelled, let self, !self.ocupado, !self.trabajando else { return }
            self.prepararVistaPreviaSiToca()
        }
    }

    /// Prepara ya la vista previa de la pantalla, si la enseña y su paso está por aplicar.
    public func prepararVistaPreviaSiToca() {
        guard let p = pantalla, p.conVistaPrevia, p.paso != .ordenar else { return }
        if p.paso == .bienvenida, motor.ruta != .empresaNueva {
            // Con carpeta, la bienvenida no escribe en ella: la vista previa dice qué se hace fuera.
            prepararVistaPrevia()
            return
        }
        guard p.paso.escribeEnLaCarpeta, !pasoHecho(p.paso) else { return }
        let antes = error
        prepararVistaPrevia()
        if vista == nil, error == nil { error = antes }
    }

    /// Al llegar a una pantalla (la vista la pinta).
    public func alPintar(_ p: Pantalla) {
        if pintadas.last != p.id { pintadas.append(p.id) }
        if vista?.paso != p.paso || vista == nil { prepararVistaPreviaSiToca() }
        if p.paso == .conectar, claude == .sinMirar { Task { await detectarClaude() } }
    }

    // MARK: Botones

    /// El botón principal (↩).
    public func pulsarPrincipal() async {
        guard motivoSinPrincipal == nil, !ocupado else { return }
        ocupado = true
        defer { ocupado = false }
        switch accionPrincipal {
        case .siguiente, .terminar, .empezarRecorrido, .abrirMiCarpeta: await avanzar()
        case .aplicar: await aplicarPasoActual()
        case .aplicarOrdenar: await ConexionOrdenar.porAplicar(self)?.aplicar()
        case .hacerCopia: await hacerCopia()
        case .abrirSinTocar: await abrirSinTocar()
        case .crearCarpeta: await crearEmpresa()
        case .abrirEjemplo: await abrirEjemplo()
        case .abrirAjustes: entorno.abrirAjustes()
        }
    }

    /// «Siguiente»: guarda lo escrito, confirma lo premarcado y pasa a la pantalla siguiente.
    public func avanzar() async {
        guard await guardarBorradores() else { return }
        if repasando, let p = pantalla, let i = pantallas.firstIndex(where: { $0.id == p.id }) {
            // Repasar no escribe ni marca nada: solo se mira.
            if i + 1 < pantallas.count {
                let siguienteID = pantallas[i + 1].id
                actualizar { $0.ir(a: siguienteID) }
                nuevaPantalla()
            }
            else { await terminar() }
            return
        }
        if let p = pantalla, p.id == "bienvenida.carpeta", yaHayCarpeta, !pasoHecho(.bienvenida) {
            actualizar { $0.marcarAplicado(.bienvenida, plan: nil, resumen: "Ya trabajas sobre una copia") }
        }
        let r = siguiente()
        tratar(r)
        if case .terminada = r { await terminar() }
    }

    private func tratar(_ r: ResultadoAvance) {
        switch r {
        case .pantalla:
            nuevaPantalla()
        case .faltan(let f):
            error = f.count == 1 ? "Falta una respuesta. Si no lo sabes, pulsa «No lo sé»."
                : "Faltan \(f.count) respuestas. Si no lo sabes, pulsa «No lo sé»."
        case .faltaAplicar(let paso):
            if paso == .ordenar {
                error = "Aplica «Ordenar lo que tienes» antes de seguir, o pulsa «Saltar este paso»."
            } else {
                prepararVistaPreviaSiToca()
            }
        case .terminada:
            break
        }
    }

    func nuevaPantalla() {
        aplicado = nil
        error = nil
        borradores = [:]
        prepararVistaPreviaSiToca()
    }

    /// «Atrás» (⌘[).
    public func atras() async {
        await guardarBorradores()
        anterior()
        nuevaPantalla()
    }

    /// «Saltar este paso»: no se escribe nada; se puede volver a él.
    public func saltarPaso() async {
        guard let p = pantalla, p.paso.escribeEnLaCarpeta, !pasoHecho(p.paso) else { return }
        actualizar { $0.omitir(p.paso) }
        // A la primera pantalla del paso siguiente.
        let todas = pantallas
        if let i = todas.lastIndex(where: { $0.paso == p.paso }), i + 1 < todas.count {
            actualizar { $0.ir(a: todas[i + 1].id) }
            nuevaPantalla()
        } else {
            await terminar()
        }
    }

    /// «Seguir más tarde»: queda guardado y se cierra la ventana.
    public func seguirMasTardeYCerrar() async {
        await guardarBorradores()
        seguirMasTarde()
        ventana.cerrar()
    }

    // MARK: Aplicar y Deshacer

    /// «Aplicar»: comprueba lo que falta, prepara la vista previa con lo último y la escribe de una vez.
    public func aplicarPasoActual() async {
        guard await guardarBorradores() else { return }
        tareaVista?.cancel()
        let r = siguiente()
        guard case .faltaAplicar(let paso) = r else { tratar(r); if case .terminada = r { await terminar() }; return }
        prepararVistaPrevia()
        guard let v = vista else { return }
        let fuera = v.nadaQueEscribir
        await conBus { bus in await self.aplicar(bus: bus) }
        guard motor.estado.paso(paso).fase == .aplicado else { return }
        await releerCarpeta()
        let deshacible = !fuera && motor.estado.paso(paso).plan != nil
        aplicado = ResumenAplicado(paso: paso, texto: fuera ? "Hecho. En tu carpeta no se escribe nada." : "Hecho: \(v.resumen)",
                                   detalle: v.fueraDeLaCarpeta.first, sePuedeDeshacer: deshacible)
    }

    /// «Deshacer» del paso (si es lo último que se escribió).
    public func deshacerPaso(_ paso: PasoPuesta) async {
        await conBus { bus in await self.deshacer(paso, bus: bus) }
        guard !pasoHecho(paso) else { return }
        await releerCarpeta()
        aplicado = nil
        prepararVistaPreviaSiToca()
    }

    /// La entrada de la carpeta de esta puesta en marcha.
    var entradaDeLaCarpeta: VaultEntry? {
        let id = motor.estado.vaultID
        return (entorno.app?.entry(id: id)) ?? registro.load().first { $0.id == id } ?? motor.contexto.entrada
    }

    func raiz(_ e: VaultEntry) -> URL {
        registro.resolveURL(e) ?? URL(fileURLWithPath: e.ruta, isDirectory: true)
    }

    /// Escribe por la sesión abierta de la empresa (si está abierta en la app) o abre un escritor y lo cierra.
    func conBus(_ hacer: (CommandBus) async -> Void) async {
        let id = motor.estado.vaultID
        if let s = entorno.app?.sesionAbierta(id), s.puedeEscribir, let bus = s.bus {
            await hacer(bus)
            return
        }
        guard let e = entradaDeLaCarpeta else { error = ErrorPuesta.sinCarpeta.localizedDescription; return }
        do {
            let estado = appSupport.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
            let writer = try await VaultWriter.open(entry: e, root: raiz(e),
                                                    options: .init(stateDirectory: estado, appSupport: appSupport))
            await hacer(CommandBus(writer: writer))
            await writer.close()
        } catch {
            self.error = Self.mensaje(error)
        }
    }

    /// Vuelve a leer la carpeta: lo siguiente sale premarcado con lo recién escrito.
    func releerCarpeta() async {
        guard let e = entradaDeLaCarpeta else { return }
        let root = raiz(e)
        let reloj = motor.contexto.reloj
        let catalogo = motor.contexto.catalogo
        let ctx = await Task.detached(priority: .userInitiated) {
            ContextoCarpeta.leer(root, entrada: e, reloj: reloj, catalogo: catalogo)
        }.value
        actualizar { $0.cambiarContexto(ctx) }
    }

    static func mensaje(_ e: Error) -> String {
        if let l = e as? LocalizedError, let d = l.errorDescription { return d }
        return "No he podido terminar. Tu carpeta no ha cambiado; vuelve a intentarlo."
    }

    // MARK: 0 · Bienvenida

    /// La carpeta de origen elegida.
    public var carpetaDeOrigen: URL? {
        motor.valor(.origen)?.rutas?.first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Las carpetas privadas elegidas (rutas dentro de la de origen).
    public var privadasElegidas: [String] {
        guard motor.valor(.privadas)?.opcion == "si" else { return [] }
        return motor.valor(.privadasCuales)?.rutas ?? []
    }

    /// «Elegir carpeta…»: la explicación del permiso ya está en pantalla; aquí sale el panel y, si macOS no deja
    /// leerla, la pantalla de recuperación.
    public func elegirCarpetaDeOrigen() async {
        guard let url = entorno.paneles.elegirCarpeta(mensaje: "Elige la carpeta de tu empresa. Tu original no se toca.") else { return }
        let antes = carpetaDeOrigen
        await contestar(.origen, .rutas([url.standardizedFileURL.path]))
        if let antes, antes.standardizedFileURL != url.standardizedFileURL, motor.estado.respuesta(.privadas) != nil {
            // Otra carpeta: lo privado era de la anterior y hay que volver a decirlo.
            privadasPorConfirmar = true
            actualizar { $0.olvidar(.privadas); $0.olvidar(.privadasCuales) }
        }
        await comprobarPermiso(url)
    }

    /// Comprueba el permiso de macOS; si lo deniega, la pantalla de recuperación.
    @discardableResult
    func comprobarPermiso(_ url: URL) async -> Bool {
        switch await entorno.comprobarAcceso(url) {
        case .ok:
            if motor.estado.permisoDenegado { actualizar { $0.permisoDenegado(false) } }
            return true
        case .sinPermiso:
            actualizar { $0.permisoDenegado(true) }
            actualizar { $0.ir(a: "bienvenida.recuperacion") }
            nuevaPantalla()
            return false
        case .noExiste:
            error = "No encuentro esa carpeta. Elige otra."
            return false
        case .otro:
            error = "No he podido abrir esa carpeta: el disco no responde o no está disponible. Prueba de nuevo."
            return false
        }
    }

    /// «Volver a intentarlo» en la pantalla de recuperación.
    public func reintentarPermiso() async {
        guard let url = carpetaDeOrigen else {
            actualizar { $0.permisoDenegado(false); $0.ir(a: "bienvenida.carpeta") }
            nuevaPantalla()
            return
        }
        if await entorno.comprobarAcceso(url) == .ok {
            actualizar { $0.permisoDenegado(false); $0.ir(a: "bienvenida.carpeta") }
            nuevaPantalla()
        } else {
            error = "macOS sigue sin dejar leer «\(url.lastPathComponent)». Revisa el permiso y vuelve a intentarlo."
        }
    }

    /// «Sí, las elijo»: el panel solo deja elegir dentro de la carpeta de origen.
    public func elegirPrivadas() async {
        guard let raiz = yaHayCarpeta ? nil : carpetaDeOrigen else {
            error = "Elige primero la carpeta de tu empresa."
            return
        }
        let elegidas = entorno.paneles.elegirDentro(de: raiz, mensaje: "Elige las carpetas privadas: no se copian ni se miran.")
        privadasPorConfirmar = false
        await contestar(.privadas, .opcion("si"))
        var actuales = privadasElegidas
        for p in elegidas.map(\.raw) where !actuales.contains(p) { actuales.append(p) }
        if !actuales.isEmpty { await contestar(.privadasCuales, .rutas(actuales)) }
    }

    /// «No hay» carpetas privadas.
    public func noHayPrivadas() async {
        privadasPorConfirmar = false
        await contestar(.privadas, .opcion("no"))
    }

    /// Quita una carpeta privada de la lista (si no queda ninguna, hay que volver a contestar).
    public func quitarPrivada(_ ruta: String) async {
        await contestar(.privadasCuales, .rutas(privadasElegidas.filter { $0 != ruta }))
    }

    /// Lo que falta para poder copiar o abrir la carpeta (se dice al lado del botón).
    public var faltaParaLaCarpeta: String? {
        guard !yaHayCarpeta else { return nil }
        if carpetaDeOrigen == nil { return "Elige la carpeta de tu empresa." }
        if motor.valor(.modo) == nil { return "Elige cómo quieres trabajar con ella." }
        guard let pr = motor.valor(.privadas)?.opcion, !privadasPorConfirmar else { return "Dime si hay carpetas privadas." }
        if pr == "si", privadasElegidas.isEmpty { return "Elige las carpetas privadas o contesta «No hay»." }
        return nil
    }

    /// «Hacer la copia»: copia la carpeta (sin lo privado, sin descargar nada de iCloud), la comprueba y la registra.
    public func hacerCopia() async {
        guard await guardarBorradores() else { return }
        if let f = faltaParaLaCarpeta { error = f; return }
        let r = siguiente()
        guard case .faltaAplicar(.bienvenida) = r, let origen = carpetaDeOrigen else { tratar(r); return }
        guard await comprobarPermiso(origen) else { return }
        let exclusiones = privadasElegidas.map(VaultPath.init)
        let copiador = DemoCopier(appSupport: appSupport)
        let archivo = incluirArchivo
        let destino = empresas
        copia = .copiando(fase: "Contar archivos", hechos: 0, total: nil)
        error = nil
        let modelo = self
        let avisar: @Sendable (CopyProgress) -> Void = { p in
            Task { @MainActor in
                guard case .copiando = modelo.copia else { return }
                modelo.copia = .copiando(fase: ModeloPuesta.fase(p.fase), hechos: p.hechos, total: p.total)
            }
        }
        let tarea = Task {
            do {
                let (informe, nueva) = try await copiador.copy(from: origen, into: destino,
                                                               options: CopyOptions(exclusiones: exclusiones, incluirArchivo: archivo),
                                                               progress: avisar)
                if Task.isCancelled {
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: informe.destino), resultingItemURL: nil)
                    modelo.copia = .cancelada
                    return
                }
                await modelo.registrarLaCopia(nueva, informe: informe, origen: origen, exclusiones: exclusiones)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    modelo.copia = .cancelada
                } else if case CopyError.origenNoAccesible = error {
                    modelo.copia = nil
                    modelo.actualizar { $0.permisoDenegado(true); $0.ir(a: "bienvenida.recuperacion") }
                    modelo.nuevaPantalla()
                } else {
                    modelo.copia = nil
                    modelo.error = ModeloPuesta.mensaje(error)
                }
            }
        }
        tareaCopia = tarea
        await tarea.value
    }

    private func registrarLaCopia(_ nueva: VaultEntry, informe: CopyReport, origen: URL, exclusiones: [VaultPath]) async {
        var e = nueva
        if e.bookmark == nil { e.bookmark = try? VaultRegistry.makeBookmark(for: URL(fileURLWithPath: e.ruta)) }
        if e.exclusionesCopia.isEmpty { e.exclusionesCopia = exclusiones.map(\.raw) }
        if e.origen == nil { e.origen = origen.path }
        do {
            if let app = entorno.app { try app.register(e) } else { try registro.upsert(e) }
        } catch {
            copia = nil
            self.error = "La copia está hecha, pero no he podido apuntarla en la lista: \(Self.mensaje(error))"
            return
        }
        let root = URL(fileURLWithPath: e.ruta, isDirectory: true)
        let entrada = e
        let reloj = motor.contexto.reloj
        let catalogo = motor.contexto.catalogo
        let ctx = await Task.detached(priority: .userInitiated) {
            ContextoCarpeta.leer(root, entrada: entrada, reloj: reloj, catalogo: catalogo)
        }.value
        let soporte = appSupport
        actualizar { m in
            m.registrarCopia(entrada, root: root, appSupport: soporte)
            m.cambiarContexto(ctx)
        }
        let texto = Self.resumenCopia(informe)
        copia = .hecha(texto)
        aplicado = ResumenAplicado(paso: .bienvenida, texto: "Copia hecha en «\(e.nombre)»", detalle: texto, sePuedeDeshacer: false)
    }

    /// «Cancelar» durante la copia: se para de verdad y lo copiado a medias va a la Papelera.
    public func cancelarCopia() {
        guard let t = tareaCopia else { return }
        t.cancel()
        if case .copiando = copia { copia = .cancelando }
    }

    static func fase(_ f: CopyProgress.Fase) -> String {
        switch f {
        case .inventario: "Contar archivos"
        case .copia: "Copiar"
        case .verificacion: "Comprobar que cada archivo es idéntico"
        case .terminado: "Terminado"
        }
    }

    /// «1.034 archivos copiados y comprobados · 12 solo en iCloud, no se han descargado».
    static func resumenCopia(_ r: CopyReport) -> String {
        var partes = [r.verificados == r.copiados
            ? TLSFormat.cuenta(r.copiados, "archivo copiado y comprobado", "archivos copiados y comprobados")
            : TLSFormat.cuenta(r.copiados, "archivo copiado", "archivos copiados")]
        if !r.soloEnICloud.isEmpty {
            partes.append("\(TLSFormat.entero(r.soloEnICloud.count)) solo en iCloud, no se han descargado")
        }
        let privadas = r.exclusiones.filter { $0 != "Archivo" }
        if !privadas.isEmpty {
            partes.append(TLSFormat.cuenta(privadas.count, "carpeta privada sin copiar", "carpetas privadas sin copiar"))
        }
        if r.exclusiones.contains("Archivo") { partes.append("Archivo, sin copiar (lo retirado)") }
        return partes.joined(separator: " · ")
    }

    /// «Ver sin tocar»: se registra en solo lectura, se apunta y se abre (la carpeta no se toca).
    public func abrirSinTocar() async {
        guard await guardarBorradores() else { return }
        if let f = faltaParaLaCarpeta { error = f; return }
        let r = siguiente()
        guard case .faltaAplicar(.bienvenida) = r, let url = carpetaDeOrigen else { tratar(r); return }
        guard await comprobarPermiso(url) else { return }
        let peek = try? await CopyConfig.peek(url)
        let app = entorno.app ?? AppModel(registry: registro)
        do {
            let e = try app.registerReadOnly(url: url, privadas: privadasElegidas.map(VaultPath.init), config: peek)
            empresaAlTerminar = e.id
            actualizar { $0.marcarAplicado(.bienvenida, plan: nil, resumen: "Tu carpeta, abierta sin tocarla") }
            await avanzar()
        } catch {
            self.error = Self.mensaje(error)
        }
    }

    /// «Crear la carpeta» (Empiezo de cero): antes no existe nada en el disco.
    public func crearEmpresa() async {
        guard await guardarBorradores() else { return }
        tareaVista?.cancel()
        let r = siguiente()
        guard case .faltaAplicar(.bienvenida) = r else { tratar(r); return }
        prepararVistaPrevia()
        guard vista != nil else { return }
        guard let e = await aplicarEmpezarDeCero(empresas: empresas, registro: registro, appSupport: appSupport) else { return }
        entorno.app?.reload()
        aplicado = ResumenAplicado(paso: .bienvenida, texto: "Carpeta creada: «\(e.nombre)»",
                                   detalle: TLSFormat.rutaCorta(e.ruta), sePuedeDeshacer: false)
    }

    /// «Abrir el ejemplo»: Asesoría Ribera, con la puesta en marcha ya hecha.
    public func abrirEjemplo() async {
        _ = siguiente()
        terminada = true
        if let instalar = entorno.instalarEjemplo {
            do {
                let e = try await instalar()
                ventana.abrirEmpresa(e.id)
                ventana.cerrar()
            } catch {
                terminada = false
                self.error = Self.mensaje(error)
            }
        } else {
            // Sin la integración, el selector de empresa tiene «Ver un ejemplo».
            ventana.abrirSelector()
            ventana.cerrar()
        }
    }

    // MARK: Claude Code

    /// El estado de la carpeta para el entrevistador (dentro del Application Support, nunca en la carpeta).
    var estadoDelAsistente: URL {
        appSupport.appendingPathComponent(motor.estado.vaultID.uuidString.lowercased(), isDirectory: true)
    }

    var carpetasNegadas: [URL] {
        var out: [URL] = []
        if let e = entradaDeLaCarpeta { out.append(raiz(e)) }
        if let o = carpetaDeOrigen { out.append(o) }
        return out
    }

    public func detectarClaude() async {
        guard claude == .sinMirar || claude == .noEncontrado else { return }
        claude = .buscando
        claude = await entorno.detectorClaude.detectar()
    }

    /// «Probar» Claude Code: una consulta mínima dentro del sandbox.
    public func probarClaude() async {
        guard claude.encontrado else { return }
        claude = .probando
        claude = await entorno.detectorClaude.probar(estado: estadoDelAsistente, negadas: carpetasNegadas)
    }

    /// El consentimiento del alcance: con Claude Code, el entrevistador lo usa para repreguntar.
    public func usarAsistenteYConectar(_ si: Bool) async {
        await contestar(.asistente, .siNo(si))
        guard si else { actualizar { $0.entrevista.lanzador = nil }; return }
        await detectarClaude()
        guard claude.encontrado, let l = await entorno.detectorClaude.lanzador(estado: estadoDelAsistente, negadas: carpetasNegadas)
        else { return }
        actualizar { $0.entrevista.lanzador = l }
    }

    // MARK: Final

    /// Fin: el recorrido sobre tu empresa (si lo pidió), la empresa abierta y la ventana cerrada.
    public func terminar() async {
        terminada = true
        let id = empresaAlTerminar ?? motor.estado.vaultID
        if !repasando, !motor.soloMirar, motor.ruta != .ejemplo, motor.valor(.recorrido)?.opcion == "ahora" {
            await TutorialEventos.empezar(.tuEmpresa, empresa: id, almacen: entorno.almacenTutorial)
        }
        let registrada = entorno.app?.entry(id: id) != nil || registro.load().contains { $0.id == id }
        if registrada, !repasando { ventana.abrirEmpresa(id) }
        ventana.cerrar()
    }
}
