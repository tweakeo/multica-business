import Observation
import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

// «Importar tareas de Multica» (PLAN §9 F3, «Si dices sí»; rol tutorial). Hoja propia y completa: la puede abrir el
// paso «Ordenar lo que tienes» o cualquier pantalla con `ImportarMulticaHoja(sesion:)`. Solo lee de Multica; nada se
// escribe en la carpeta hasta «Importar», que va en un solo plan (un solo Deshacer) y con las reglas apagadas.
// Rol ordenar (F3): también desde la puesta en marcha sin ventana de la empresa (`init(acceso:)`, con su «Deshacer» en la
// hoja) y, la segunda vez, «0 nuevas».

/// Lo que va pasando en la hoja.
@MainActor
@Observable
final class ModeloImportarMultica {
    enum Fase: Equatable {
        case buscando
        case sinPrograma
        case elegir
        case leyendo
        case previa
        case aplicando
        case hecho(String)
    }

    /// La sesión de la empresa, si la hoja se abre desde su ventana (así el aviso y ⌘Z son los de la ventana).
    let sesion: VaultSession?
    /// Por dónde se escribe desde la puesta en marcha (sin ventana de la empresa abierta).
    private let accesoPropio: AccesoEmpresa?
    private let ejecutor: (any EjecutorMultica)?
    private(set) var fase: Fase = .buscando
    /// Lo que se escribió (para «Deshacer» cuando no hay ventana de la empresa con su ⌘Z).
    private(set) var planEscrito: UUID?
    private(set) var deshecho = false
    private(set) var perfiles: [PerfilMultica] = []
    var perfil = "default"
    private(set) var espacios: [EspacioMultica] = []
    var espacio: String?
    var previa: PreviaMultica?
    var carpetaPrivada: VaultPath?
    private(set) var privadas: [VaultPath] = []
    private(set) var error: String?
    @ObservationIgnored private var foto: VaultSnapshot?

    init(sesion: VaultSession, ejecutor: (any EjecutorMultica)? = nil) {
        self.sesion = sesion
        self.accesoPropio = nil
        self.ejecutor = ejecutor
    }

    /// Desde la puesta en marcha (paso 2): escribe por `acceso` (la sesión abierta o un escritor propio).
    init(acceso: AccesoEmpresa, ejecutor: (any EjecutorMultica)? = nil) {
        self.sesion = acceso.sesion
        self.accesoPropio = acceso
        self.ejecutor = ejecutor
    }

    private var acceso: AccesoEmpresa? { accesoPropio ?? sesion.flatMap { AccesoEmpresa(sesion: $0) } }

    private var autor: Autor { acceso?.autor ?? sesion?.autor ?? .persona(AppModel.personaPorDefecto) }

    /// Tareas abiertas que aún no se han importado (la segunda vez: «0 nuevas»).
    var nuevas: Int { previa?.candidatas.filter(\.sePuedeMarcar).count ?? 0 }

    private var lector: LectorMultica? {
        if let ejecutor { return LectorMultica(ejecutor: ejecutor) }
        return MulticaCLI.localizar().map { LectorMultica(ejecutor: ProcesoMultica(cli: $0)) }
    }

    func arrancar() async {
        guard let lector else { fase = .sinPrograma; return }
        perfiles = await lector.perfiles()
        if let p = perfiles.first, !perfiles.contains(where: { $0.nombre == perfil }) { perfil = p.nombre }
        fase = .elegir
        await cargarEspacios()
    }

    func cargarEspacios() async {
        guard let lector else { return }
        error = nil
        do {
            espacios = try await lector.espacios(perfil: perfil)
            if espacio == nil || !espacios.contains(where: { $0.id == espacio }) { espacio = espacios.first?.id }
        } catch {
            espacios = []
            espacio = nil
            self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido leer los espacios de trabajo."
        }
    }

    /// Tras crear una carpeta privada: vuelve a leer cuáles hay (la vista previa no cambia).
    func recargarPrivadas() async {
        // El índice relee `.tls/config.yaml` al aplicar el cambio: se espera un momento a que lo haga.
        for _ in 0..<20 {
            guard let foto = await acceso?.foto() else { return }
            if !foto.layout.privado.isEmpty {
                self.foto = foto
                privadas = foto.layout.privado
                if carpetaPrivada == nil { carpetaPrivada = privadas.first }
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    /// Lee las abiertas y prepara la vista previa. No escribe nada.
    func leer() async {
        guard let lector, let espacio else { return }
        error = nil
        fase = .leyendo
        do {
            let tareas = try await lector.tareasAbiertas(perfil: perfil, espacio: espacio)
            guard let foto = await acceso?.foto() else {
                error = "No he podido leer la carpeta de tu empresa."
                fase = .elegir
                return
            }
            self.foto = foto
            privadas = foto.layout.privado
            if carpetaPrivada == nil { carpetaPrivada = privadas.first }
            previa = ImportadorMultica(snapshot: foto).previa(tareas)
            fase = .previa
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido leer las tareas de Multica."
            fase = .elegir
        }
    }

    /// Plan que se aplicaría (para el resumen) o el motivo por el que aún no se puede.
    var plan: Result<PlanImportacionMultica, Error>? {
        guard let foto, let previa else { return nil }
        let autor = self.autor
        return Result { try ImportadorMultica(snapshot: foto).plan(previa, carpetaPrivada: carpetaPrivada, autor: autor) }
    }

    /// «Importar»: un solo plan, como la persona, con las reglas del dominio apagadas mientras se escribe.
    func aplicar(deshacer: UndoManager?) async {
        guard case .success(let p)? = plan else { return }
        fase = .aplicando
        let n = p.fichas.count
        let aviso = n == 1 ? "Importé 1 tarea de Multica" : "Importé \(n) tareas de Multica"
        if let sesion, accesoPropio == nil {
            let motor = DominioEmpresa.motor(de: sesion)
            await motor?.setModoImportacion(true)
            do {
                let r = try await sesion.escribir(plan: p.plan, aviso: aviso, deshacer: deshacer)
                await motor?.setModoImportacion(false)
                fase = r.hecho ? .hecho(p.resumen) : .previa
            } catch {
                await motor?.setModoImportacion(false)
                self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido importar las tareas."
                fase = .previa
            }
            return
        }
        do {
            guard let acceso else { throw ErrorAccesoEmpresa.soloLectura("no encuentro la carpeta de tu empresa") }
            let r = try await acceso.escribir(plan: p.plan, importacion: true, aviso: aviso, deshacer: deshacer)
            if r.hecho { planEscrito = r.planID }
            fase = r.hecho ? .hecho(p.resumen) : .previa
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido importar las tareas."
            fase = .previa
        }
    }

    /// «Deshacer» desde la hoja (sin ventana de la empresa): quita las fichas creadas de una vez (al Archivo).
    func deshacerImportacion() async {
        guard let planEscrito, let acceso else { return }
        do {
            try await acceso.deshacer(planes: [planEscrito])
            self.planEscrito = nil
            deshecho = true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido deshacerlo."
        }
    }
}

/// La hoja de importar de Multica.
public struct ImportarMulticaHoja: View {
    @State private var modelo: ModeloImportarMultica
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    public init(sesion: VaultSession) {
        _modelo = State(initialValue: ModeloImportarMultica(sesion: sesion))
    }

    /// Desde «Ordenar lo que tienes» de la puesta en marcha (la empresa puede no estar abierta en ninguna ventana).
    public init(acceso: AccesoEmpresa) {
        _modelo = State(initialValue: ModeloImportarMultica(acceso: acceso))
    }

    init(modelo: ModeloImportarMultica) {
        _modelo = State(initialValue: modelo)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text("Importar tareas de Multica").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text("Solo leo las tareas abiertas de Multica; allí no cambio nada. Cada una se convierte en una ficha de tarea y nada se escribe hasta que pulses «Importar».")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if let e = modelo.error { AvisoEnLinea(e, estado: .mal) }
            cuerpo
            Spacer(minLength: 0)
            pie
        }
        .padding(TLSEspacio.e24)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 620)
        .background(TLSPaleta.fondo.color)
        .task { if modelo.fase == .buscando { await modelo.arrancar() } }
        .accessibilityIdentifier("multica.hoja")
    }

    @ViewBuilder
    private var cuerpo: some View {
        switch modelo.fase {
        case .buscando, .leyendo, .aplicando:
            HStack(spacing: TLSEspacio.e8) {
                ProgressView().controlSize(.small)
                Text(modelo.fase == .aplicando ? "Creando las fichas…" : "Hablando con Multica…")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        case .sinPrograma:
            VacioExplicado(icono: "questionmark.app", titulo: "No encuentro Multica en este Mac",
                           porQue: "Si lo usas, abre su app una vez o instala su programa de línea de órdenes y vuelve a intentarlo. Si no lo usas, no hace falta nada.",
                           compacto: true)
        case .elegir:
            eleccion
        case .previa:
            if let previa = modelo.previa { VistaPreviaMultica(modelo: modelo, previa: previa) }
        case .hecho(let resumen):
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                PastillaEstado(modelo.deshecho ? .sinDato : .bien, palabra: modelo.deshecho ? "Deshecho" : "Hecho")
                Text(modelo.deshecho ? "Las fichas creadas están en el Archivo: no se ha borrado nada." : resumen)
                    .tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                if !modelo.deshecho {
                    Text("Las tienes en Tareas. Si algo no te cuadra, «Deshacer» las quita de una vez.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if modelo.planEscrito != nil {
                    Button("Deshacer") { Task { await modelo.deshacerImportacion() } }
                        .tlsBoton(.secundario)
                        .accessibilityIdentifier("multica.deshacer")
                }
            }
        }
    }

    private var eleccion: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(spacing: TLSEspacio.e12) {
                Text("Perfil").tlsTexto(TLSTipo.interfazFuerte).frame(width: 140, alignment: .leading)
                if modelo.perfiles.isEmpty {
                    TextField("default", text: $modelo.perfil).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                        .onSubmit { Task { await modelo.cargarEspacios() } }
                        .accessibilityIdentifier("multica.perfil")
                } else {
                    Picker("Perfil", selection: $modelo.perfil) {
                        ForEach(modelo.perfiles) { p in Text(p.nombre).tag(p.nombre) }
                    }
                    .labelsHidden().frame(maxWidth: 240)
                    .onChange(of: modelo.perfil) { _, _ in Task { await modelo.cargarEspacios() } }
                    .accessibilityIdentifier("multica.perfil")
                }
            }
            HStack(spacing: TLSEspacio.e12) {
                Text("Espacio de trabajo").tlsTexto(TLSTipo.interfazFuerte).frame(width: 140, alignment: .leading)
                if modelo.espacios.isEmpty {
                    Text("Ninguno con este perfil").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else {
                    Picker("Espacio de trabajo", selection: $modelo.espacio) {
                        ForEach(modelo.espacios) { e in Text(e.nombre).tag(Optional(e.id)) }
                    }
                    .labelsHidden().frame(maxWidth: 320)
                    .accessibilityIdentifier("multica.espacio")
                }
            }
        }
        .padding(TLSEspacio.e16)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
    }

    @ViewBuilder
    private var pie: some View {
        HStack(spacing: TLSEspacio.e8) {
            if case .previa = modelo.fase, modelo.nuevas == 0 {
                Text("0 nuevas: ya las importaste todas.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityIdentifier("multica.ceroNuevas")
            } else if case .previa = modelo.fase, case .failure(let e)? = modelo.plan {
                AvisoEnLinea((e as? LocalizedError)?.errorDescription ?? "Aún no se puede importar.", estado: .atencion)
            } else if case .previa = modelo.fase, case .success(let p)? = modelo.plan {
                Text(p.resumen).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityIdentifier("multica.resumen")
            }
            Spacer(minLength: TLSEspacio.e8)
            switch modelo.fase {
            case .hecho:
                Button("Cerrar") { dismiss() }.tlsBoton(.principal, alto: 36).keyboardShortcut(.defaultAction)
            case .elegir:
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                BotonPrincipal("Ver las tareas abiertas", motivoDesactivado: modelo.espacio == nil ? "Elige un espacio de trabajo" : nil) {
                    Task { await modelo.leer() }
                }
                .accessibilityIdentifier("multica.leer")
            case .previa where modelo.nuevas == 0:
                Button("Cerrar") { dismiss() }.tlsBoton(.principal, alto: 36).keyboardShortcut(.defaultAction)
            case .previa:
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                let n = modelo.previa?.marcadas.count ?? 0
                BotonPrincipal(n == 1 ? "Importar 1 tarea" : "Importar \(n) tareas", icono: "square.and.arrow.down",
                               motivoDesactivado: Self.motivo(modelo.plan)) {
                    Task { await modelo.aplicar(deshacer: undoManager) }
                }
                .accessibilityIdentifier("multica.importar")
            default:
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
            }
        }
    }

    static func motivo(_ plan: Result<PlanImportacionMultica, Error>?) -> String? {
        switch plan {
        case .success?: nil
        case .failure(let e)?: (e as? LocalizedError)?.errorDescription ?? "Aún no se puede importar."
        case nil: "Aún no hay nada que importar."
        }
    }
}

/// La vista previa: una fila por tarea abierta, con su casilla, su área y su nota.
struct VistaPreviaMultica: View {
    @Bindable var modelo: ModeloImportarMultica
    let previa: PreviaMultica

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: TLSEspacio.e8) {
                PastillaEstado(modelo.nuevas == 0 ? .sinDato : .bien, palabra: modelo.nuevas == 1 ? "1 nueva" : "\(modelo.nuevas) nuevas")
                    .accessibilityIdentifier("multica.previa.nuevas")
                Text(previa.resumen).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityIdentifier("multica.previa.resumen")
                Spacer()
                Text("Corte: " + String(format: "%02d/%02d/%04d", previa.fechaCorte.day, previa.fechaCorte.month, previa.fechaCorte.year))
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .help("Lo importado entra como antecedente: no reactiva ninguna regla")
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(previa.candidatas) { c in fila(c) }
                }
                .padding(6)
            }
            .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            if !previa.personalesMarcadas.isEmpty { privada }
        }
    }

    private func fila(_ c: CandidataMultica) -> some View {
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            Toggle(isOn: Binding(get: { c.marcada && c.sePuedeMarcar },
                                 set: { modelo.previa?.marcar(c.id, $0) })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!c.sePuedeMarcar)
                .accessibilityLabel("Importar «\(c.tarea.titulo)»")
                .accessibilityIdentifier("multica.casilla.\(c.id)")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(c.tarea.identificador).font(TLSTipo.codigo.font()).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text(c.tarea.titulo).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(c.estado.rawValue)
                    if let p = c.prioridad { Text("· \(p)") }
                    if let v = c.vence { Text("· vence el " + String(format: "%02d/%02d/%04d", v.day, v.month, v.year)) }
                }
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                if let nota = c.nota {
                    Label(nota, systemImage: c.parecePersonal ? "lock" : "checkmark.circle")
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(c.parecePersonal ? TLSPaleta.atencion.color : TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !c.parecePersonal, c.sePuedeMarcar {
                Picker("Área", selection: Binding(get: { c.area }, set: { modelo.previa?.cambiarArea(c.id, $0) })) {
                    ForEach(AreaCode.allCases, id: \.self) { a in Text(a.etiquetaNumerada).tag(a) }
                }
                .labelsHidden()
                .frame(width: 150)
                .help(c.area == c.areaSugerida ? "Sugerida por sus palabras" : "Elegida por ti")
                .accessibilityIdentifier("multica.area.\(c.id)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var privada: some View {
        HStack(spacing: TLSEspacio.e12) {
            Image(systemName: "lock").accessibilityHidden(true)
            Text("Carpeta privada para las personales").tlsTexto(TLSTipo.interfazFuerte)
            if modelo.privadas.isEmpty {
                Text("No hay ninguna carpeta privada: desmárcalas o crea una.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.atencion.color)
                    .fixedSize(horizontal: false, vertical: true)
                // F4 · integración (pendiente de F3): en una copia hecha por la app lo privado se quedó fuera.
                if let sesion = modelo.sesion, sesion.puedeEscribir {
                    Button("Crear una carpeta privada") {
                        Task {
                            if await sesion.crearCarpetaPrivada(nombre: CarpetaPrivadaNueva.nombrePorDefecto) != nil {
                                await modelo.recargarPrivadas()
                            }
                        }
                    }
                    .tlsBoton(.secundario)
                    .accessibilityIdentifier("multica.crearPrivada")
                }
            } else {
                Picker("Carpeta privada", selection: $modelo.carpetaPrivada) {
                    ForEach(modelo.privadas, id: \.self) { p in Text(p.raw).tag(Optional(p)) }
                }
                .labelsHidden().frame(maxWidth: 280)
                .accessibilityIdentifier("multica.privada")
            }
        }
        .foregroundStyle(TLSPaleta.texto.color)
    }
}
