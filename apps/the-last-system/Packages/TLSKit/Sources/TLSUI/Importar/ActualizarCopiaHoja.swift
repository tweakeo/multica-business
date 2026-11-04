import Observation
import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

// F3 · rol ordenar. «Actualizar la copia desde la real» (PLAN §9 F3, criterio 9): lee la carpeta real (solo leer, sin lo
// privado, sin descargar nada de iCloud), enseña lo nuevo y lo añade a la copia sin pisar nada, en un solo cambio con
// «Deshacer». La real queda igual: se comprueba que su inventario es el mismo antes y después.

@MainActor
@Observable
final class ModeloActualizarCopia {
    enum Fase: Equatable {
        case leyendo
        case previa
        case aplicando
        case hecho
        case sinOriginal(String)
    }

    let acceso: AccesoEmpresa
    let real: URL?
    private(set) var fase: Fase = .leyendo
    private(set) var actualizacion: ActualizacionDesdeLaReal?
    private(set) var resultado: ActualizacionDesdeLaReal.Resultado?
    private(set) var planEscrito: UUID?
    private(set) var deshecho = false
    var error: String?

    init(acceso: AccesoEmpresa, real: URL?) {
        self.acceso = acceso
        self.real = real
    }

    /// La carpeta real de una copia: la registrada como real con esa ruta (tiene su permiso guardado) o, si no, la ruta
    /// de origen que guardó la copia.
    static func carpetaReal(de entry: VaultEntry, registro: VaultRegistry) -> URL? {
        guard entry.clase == .copia, let origen = entry.origen, !origen.isEmpty else { return nil }
        let clave = TextFolding.pathKey(URL(fileURLWithPath: origen).standardizedFileURL.path)
        if let r = registro.load().first(where: {
            $0.clase == .real && TextFolding.pathKey(URL(fileURLWithPath: $0.ruta).standardizedFileURL.path) == clave
        }), let url = registro.resolveURL(r) {
            return url
        }
        return URL(fileURLWithPath: origen, isDirectory: true)
    }

    /// Compara la real con la copia (solo lee las dos).
    func leer() async {
        guard let real else {
            fase = .sinOriginal("Esta carpeta no es una copia de otra: no hay de dónde traer nada.")
            return
        }
        fase = .leyendo
        error = nil
        switch await FolderAccess.check(real) {
        case .ok: break
        case .sinPermiso:
            fase = .sinOriginal("No tengo permiso para leer tu carpeta real. Ábrela una vez desde «Elegir empresa» o revisa Ajustes del Sistema › Privacidad y seguridad.")
            return
        case .noExiste:
            fase = .sinOriginal("No encuentro tu carpeta real en «\(TLSFormat.rutaCorta(real.path))». Si la has movido, vuelve a elegirla desde «Elegir empresa».")
            return
        case .otro(let d):
            fase = .sinOriginal("No puedo leer tu carpeta real: \(d)")
            return
        }
        do {
            actualizacion = try await ActualizacionDesdeLaReal.preparar(
                real: real, copia: acceso.raiz, exclusiones: acceso.entry.exclusionesCopia.map { VaultPath($0) },
                mapas: MapaImportacion.guardados(en: acceso.estado), autor: acceso.autor)
            fase = .previa
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido comparar las dos carpetas."
            fase = .previa
        }
    }

    /// «Añadir»: un plan, como la persona, que no pisa nada; después se comprueba la copia y que la real no cambió.
    func aplicar(deshacer um: UndoManager?) async {
        guard let a = actualizacion, a.plan != nil else { return }
        fase = .aplicando
        error = nil
        do {
            let r = try await acceso.conBus { bus, _ in try await a.aplicar(con: bus) }
            resultado = r
            if let w = r.escritura, w.hecho {
                let texto = "Traje " + TLSFormat.cuenta(a.nuevos.count, "fichero nuevo", "ficheros nuevos") + " de tu carpeta real"
                if let sesion = acceso.sesion {
                    sesion.registrarDeshacer(w, descripcion: "Traer lo nuevo de tu carpeta real", aviso: texto, deshacer: um)
                } else {
                    planEscrito = w.planID
                }
            }
            fase = .hecho
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido traer lo nuevo. No se ha cambiado nada."
            fase = .previa
        }
    }

    /// «Deshacer» desde la hoja cuando no hay ventana de la empresa (con su ⌘Z).
    func deshacer() async {
        guard let planEscrito else { return }
        do {
            try await acceso.deshacer(planes: [planEscrito])
            self.planEscrito = nil
            deshecho = true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "No he podido deshacerlo."
        }
    }
}

/// La hoja «Actualizar la copia desde la real».
public struct ActualizarCopiaHoja: View {
    @State private var modelo: ModeloActualizarCopia
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    /// Desde la ventana de la empresa (Ajustes › Esta empresa o el menú de la copia).
    public init(sesion: VaultSession, registro: VaultRegistry = VaultRegistry()) {
        let acceso = AccesoEmpresa(sesion: sesion)
            ?? AccesoEmpresa(entry: sesion.entry, raiz: URL(fileURLWithPath: sesion.entry.ruta), persona: sesion.persona)
        _modelo = State(initialValue: ModeloActualizarCopia(acceso: acceso,
                                                            real: ModeloActualizarCopia.carpetaReal(de: sesion.entry, registro: registro)))
    }

    /// Con un acceso ya hecho (la puesta en marcha o las pruebas).
    public init(acceso: AccesoEmpresa, real: URL?) {
        _modelo = State(initialValue: ModeloActualizarCopia(acceso: acceso, real: real))
    }

    init(modelo: ModeloActualizarCopia) {
        _modelo = State(initialValue: modelo)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text("Actualizar la copia desde la real").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text("Leo tu carpeta real sin cambiar nada y traigo a la copia lo que es nuevo. Lo que ya está en la copia no se pisa, aunque sea distinto. Nada se escribe hasta que pulses «Añadir».")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if let e = modelo.error { AvisoEnLinea(e, estado: .mal) }
            ScrollView { cuerpo.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, TLSEspacio.e4).padding(.horizontal, 2) }
            pie
        }
        .padding(TLSEspacio.e24)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .background(TLSPaleta.fondo.color)
        .task { if modelo.fase == .leyendo, modelo.actualizacion == nil { await modelo.leer() } }
        .accessibilityIdentifier("actualizarCopia.hoja")
    }

    @ViewBuilder
    private var cuerpo: some View {
        switch modelo.fase {
        case .leyendo, .aplicando:
            HStack(spacing: TLSEspacio.e8) {
                ProgressView().controlSize(.small)
                Text(modelo.fase == .aplicando ? "Traigo lo nuevo y lo compruebo…" : "Comparo tu carpeta real con la copia…")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        case .sinOriginal(let porQue):
            VacioExplicado(icono: "externaldrive.badge.questionmark", titulo: "No puedo leer tu carpeta real", porQue: porQue, compacto: true)
        case .previa:
            if let a = modelo.actualizacion { previa(a) }
        case .hecho:
            hecho
        }
    }

    private func previa(_ a: ActualizacionDesdeLaReal) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text(a.resumen).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityIdentifier("actualizarCopia.resumen")
            if a.nuevos.isEmpty {
                VacioExplicado(icono: "checkmark.circle", titulo: "No hay nada nuevo",
                               porQue: "Todo lo de tu carpeta real ya está en la copia" + (a.yaEstan > 0 ? " (\(TLSFormat.entero(a.yaEstan)) ficheros)." : "."),
                               compacto: true)
            } else {
                TarjetaOrdenar("Nuevos · \(TLSFormat.entero(a.nuevos.count))", icono: "plus.circle") {
                    ForEach(a.nuevos.prefix(200), id: \.origen) { n in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ModeloOrdenar.rutaLegible(n.destino)).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                            Text(n.motivo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                        }
                    }
                    if a.nuevos.count > 200 {
                        Text("Y \(TLSFormat.cuenta(a.nuevos.count - 200, "más", "más")).").tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
            }
            if !a.noSeTraen.isEmpty {
                TarjetaOrdenar("No los puedo traer · \(TLSFormat.entero(a.noSeTraen.count))", icono: "nosign") {
                    Text("Si los trajera, llegarían estropeados. Arréglalos en tu carpeta real y vuelve a actualizar.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(a.noSeTraen.prefix(30).enumerated()), id: \.offset) { _, x in
                        Text("\(ModeloOrdenar.rutaLegible(x.ruta)): \(x.motivo)").tlsTexto(TLSTipo.interfaz)
                            .foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("actualizarCopia.noSeTraen")
            }
            if !a.distintos.isEmpty {
                TarjetaOrdenar("Distintos: no los toco · \(TLSFormat.entero(a.distintos.count))", icono: "equal.circle") {
                    Text("Están en las dos carpetas con contenido distinto, o han cambiado en tu carpeta real después de ordenarlos en la copia. Me quedo con el de la copia; si quieres el otro, cópialo tú.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(a.distintos.prefix(30), id: \.self) { p in
                        Text(ModeloOrdenar.rutaLegible(p)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                    }
                }
            }
            if !a.soloEnICloud.isEmpty {
                AvisoEnLinea(TLSFormat.cuenta(a.soloEnICloud.count, "fichero está", "ficheros están")
                             + " solo en iCloud en tu carpeta real: no los traigo para no descargarlos.", estado: .atencion)
            }
        }
    }

    private var hecho: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if modelo.deshecho {
                PastillaEstado(.sinDato, palabra: "Deshecho")
                Text("Lo traído está en el Archivo de la copia: no se ha borrado nada.")
                    .tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
            } else if let r = modelo.resultado {
                PastillaEstado(r.diferencias.isEmpty && r.realIntacta ? .bien : .mal, palabra: r.diferencias.isEmpty ? "Hecho" : "Revisar")
                Text("\(TLSFormat.entero(r.comprobados)) de \(TLSFormat.entero(modelo.actualizacion?.nuevos.count ?? 0)) comprobados por su huella digital.")
                    .tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityIdentifier("actualizarCopia.comprobados")
                Text(r.realIntacta ? "Tu carpeta real no ha cambiado: la he comprobado entera."
                     : "Tu carpeta real ha cambiado mientras la leía (no por la app). Vuelve a intentarlo dentro de un rato.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("actualizarCopia.realIntacta")
                if modelo.planEscrito != nil {
                    Button("Deshacer") { Task { await modelo.deshacer() } }.tlsBoton(.secundario)
                }
            }
        }
    }

    private var pie: some View {
        HStack(spacing: TLSEspacio.e8) {
            Spacer(minLength: 0)
            switch modelo.fase {
            case .previa:
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                let n = modelo.actualizacion?.nuevos.count ?? 0
                BotonPrincipal(n == 1 ? "Añadir 1 fichero" : "Añadir \(TLSFormat.entero(n)) ficheros", icono: "plus",
                               motivoDesactivado: n == 0 ? "No hay nada nuevo" : modelo.acceso.motivoSoloLectura.map { "No se puede escribir: \($0)" }) {
                    Task { await modelo.aplicar(deshacer: undoManager) }
                }
                .accessibilityIdentifier("actualizarCopia.anadir")
            default:
                Button(modelo.fase == .hecho ? "Cerrar" : "Cancelar") { dismiss() }
                    .tlsBoton(modelo.fase == .hecho ? .principal : .secundario, alto: modelo.fase == .hecho ? 36 : nil)
                    .keyboardShortcut(modelo.fase == .hecho ? .defaultAction : .cancelAction)
                    .disabled(modelo.fase == .aplicando)
            }
        }
    }
}

/// Una fila para «Ajustes › Esta empresa» (o el menú de la copia): abre la hoja. Solo en copias con su carpeta real.
public struct FilaActualizarCopia: View {
    let sesion: VaultSession
    @State private var abierta = false

    public init(sesion: VaultSession) { self.sesion = sesion }

    public var body: some View {
        if sesion.entry.clase == .copia, sesion.entry.origen != nil {
            LabeledContent("Carpeta real") {
                Button("Actualizar la copia desde la real…") { abierta = true }
                    .disabled(!sesion.puedeEscribir)
                    .help("Trae a la copia lo nuevo de tu carpeta real, sin pisar nada. La real solo se lee.")
                    .accessibilityIdentifier("ajustes.actualizarCopia")
            }
            .sheet(isPresented: $abierta) { ActualizarCopiaHoja(sesion: sesion) }
        }
    }
}
