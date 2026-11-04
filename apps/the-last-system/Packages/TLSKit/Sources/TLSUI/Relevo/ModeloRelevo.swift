import Foundation
import Observation
import TLSCore
import TLSImport

// F6 · rol buzon-relevo. «Pasar a mi carpeta real» (PLAN §9 F6) en pantalla: el estado de la hoja y sus pasos, sobre
// las piezas del núcleo (`DisponibilidadDelRelevo`, `CerrojoDelRelevo`, `PlanDeRelevo`, `ConfirmacionDeRelevo`,
// `AplicadorDeRelevo`). Solo aparece en una copia cuya carpeta de origen está registrada como real; preparar la vista
// previa solo lee; el botón que escribe nace desactivado y solo se activa escribiendo el nombre de la empresa.
//
// En esta tanda se construye y se prueba SOLO con carpetas sintéticas (Tests/TLSUITests/Relevo): nadie lo ejecuta sobre
// la carpeta real de nadie.

/// El paso en el que está la hoja.
enum FaseDelRelevo: Equatable, Sendable {
    /// La explicación y lo que va a pasar. Nada leído aún.
    case inicio
    /// Comprobando que nadie más usa la carpeta real.
    case comprobando
    /// La otra aplicación, otra ventana u otro Mac la tienen: no sigue (con el mensaje).
    case bloqueado(String)
    /// Leyendo las dos carpetas para la vista previa.
    case preparando
    /// Vista previa lista: se elige en los conflictos y se confirma escribiendo el nombre.
    case vistaPrevia
    /// Copia de seguridad, cambios y comprobación.
    case aplicando
    /// Hecho (y comprobado o no: `resultado.correcto`).
    case hecho
    case deshaciendo
    /// «Deshacer» terminó (`deshechoBien`).
    case deshecho
    /// Algo falló antes de escribir (o al deshacer): el mensaje dice si se cambió algo.
    case error(String)
}

/// Lo que necesita la hoja para trabajar (lo da la app con la sesión; las pruebas, con carpetas sintéticas).
struct EntornoDelRelevo: Sendable {
    var copia: URL
    var copiaEntry: VaultEntry
    var real: URL
    var realEntry: VaultEntry
    var hoy: LocalDate
    var aplicador: AplicadorDeRelevo
    var abrir: AplicadorDeRelevo.AbrirEscritor
    var fileSystem: any FileSystemAccess = LocalFileSystem()
}

@MainActor
@Observable
final class ModeloRelevo {
    let entorno: EntornoDelRelevo
    private(set) var fase: FaseDelRelevo = .inicio
    /// «Nadie más está usando tu carpeta real…» tras comprobar el cerrojo.
    private(set) var cerrojo: String?
    private(set) var vista: VistaPreviaDeRelevo?
    /// Lo que escribe la persona para confirmar.
    var escrito = ""
    private(set) var resultado: ResultadoDeRelevo?
    private(set) var deshechoBien: Bool?
    /// Un error al pasar (ya con la vista previa): se enseña sin perderla.
    private(set) var aviso: String?

    init(entorno: EntornoDelRelevo) {
        self.entorno = entorno
    }

    var empresa: String { entorno.realEntry.nombre }

    var confirmacion: ConfirmacionDeRelevo { ConfirmacionDeRelevo(nombreEmpresa: empresa, escrito: escrito) }

    /// Por qué «Pasar a mi carpeta real» sigue desactivado (o `nil` si se puede pulsar).
    var motivoNoPasar: String? {
        guard fase == .vistaPrevia, let v = vista else { return "Antes, prepara la vista previa." }
        if !v.hayCambios { return "No hay nada que pasar: tu carpeta real ya tiene todo lo de la copia." }
        if !confirmacion.confirmada { return "Escribe el nombre de tu empresa, «\(empresa)», para confirmar." }
        return nil
    }

    var puedePasar: Bool { motivoNoPasar == nil }

    // MARK: Pasos

    /// Paso 2 (solo comprobar): nadie más escribe la carpeta real. Toma los cerrojos un momento y los suelta.
    @discardableResult
    func comprobar() async -> Bool {
        fase = .comprobando
        aviso = nil
        let e = entorno
        let a = e.aplicador.entorno
        let r: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let c = try CerrojoDelRelevo.tomar(real: e.real, rutaRegistrada: e.realEntry.ruta, appSupport: a.appSupport,
                                                   estadoDelFork: a.estadoDelFork, instalacion: a.registro.installationID())
                c.soltar()
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        switch r {
        case .success:
            cerrojo = "Nadie más está usando tu carpeta real: ni la otra aplicación (Multica) ni otra ventana ni otro Mac."
            return true
        case .failure(let error):
            cerrojo = nil
            fase = .bloqueado(error.localizedDescription)
            return false
        }
    }

    /// Pasos 2 y 3: comprueba el cerrojo y prepara la vista previa (solo lee las dos carpetas).
    func preparar() async {
        guard await comprobar() else { return }
        fase = .preparando
        let e = entorno
        do {
            let informe = AplicadorDeRelevo.informeDeLaCopia(appSupport: e.aplicador.entorno.appSupport, id: e.copiaEntry.id)
            vista = try await PlanDeRelevo.preparar(copia: e.copia, copiaEntry: e.copiaEntry, real: e.real, realEntry: e.realEntry,
                                                    hoy: e.hoy, informeCopia: informe, fileSystem: e.fileSystem)
            escrito = ""
            fase = .vistaPrevia
        } catch {
            vista = nil
            fase = .error(error.localizedDescription + Self.nadaCambiado(error))
        }
    }

    /// En un conflicto, quedarse con la real (por defecto) o con la copia.
    func elegir(_ e: ConflictoDeRelevo.Eleccion, para ruta: VaultPath) {
        guard fase == .vistaPrevia else { return }
        vista?.elegir(e, para: ruta)
    }

    func eleccion(_ ruta: VaultPath) -> ConflictoDeRelevo.Eleccion {
        vista?.eleccion(ruta) ?? .quedarseConLaReal
    }

    /// Pasos 1 y 4–7: con la confirmación escrita, copia de seguridad, cambios, comprobación y marca.
    @discardableResult
    func pasar() async -> Bool {
        guard puedePasar, let v = vista else { return false }
        fase = .aplicando
        aviso = nil
        do {
            resultado = try await entorno.aplicador.aplicar(v, confirmacion: confirmacion, abrir: entorno.abrir)
            fase = .hecho
            return true
        } catch {
            // No se escribió nada (los errores del aplicador lo dicen); se vuelve a la vista previa con el aviso.
            aviso = error.localizedDescription
            fase = .vistaPrevia
            if let e = error as? ErrorDeRelevo {
                switch e {
                case .laRealCambio, .laCopiaCambio:
                    // La vista previa ya no vale: hay que prepararla otra vez.
                    vista = nil
                    fase = .error(e.localizedDescription)
                case .otraAplicacionAbierta, .otraVentanaAbierta, .otroEquipo, .escritorIlegible:
                    fase = .bloqueado(e.localizedDescription)
                default:
                    break
                }
            }
            return false
        }
    }

    /// «Deshacer»: la real vuelve a su huella de antes, el escritor que había y solo lectura.
    @discardableResult
    func deshacer() async -> Bool {
        guard fase == .hecho, let r = resultado, let v = vista else { return false }
        fase = .deshaciendo
        do {
            deshechoBien = try await entorno.aplicador.deshacer(r, vista: v, con: r.bus)
            fase = .deshecho
            return deshechoBien ?? false
        } catch {
            fase = .error(error.localizedDescription)
            return false
        }
    }

    /// F6 · integración: suelta el escritor del relevo (para abrir la real como una carpeta que escribe, o al cerrar la
    /// hoja). Después, «Deshacer» ya no está en la hoja (queda la copia de seguridad en los ajustes de la app).
    func terminar() async {
        guard let r = resultado else { return }
        await r.bus.writer.close()
    }

    /// Vuelve al principio (tras un bloqueo o un error).
    func reiniciar() {
        fase = .inicio
        vista = nil
        escrito = ""
        aviso = nil
        cerrojo = nil
    }

    static func nadaCambiado(_ error: Error) -> String {
        let t = error.localizedDescription
        return t.contains("No se ha cambiado nada") ? "" : " No se ha cambiado nada."
    }

    // MARK: Para la pantalla

    /// Los pasos en orden, para la explicación y el progreso.
    static let pasos = [
        "Compruebo que nadie más está usando tu carpeta real.",
        "Te enseño qué se añade, qué cambia y qué se archiva. Nada se borra.",
        "Escribes el nombre de tu empresa para confirmar.",
        "Guardo una copia de seguridad de todo lo que se toca y paso tus cambios.",
        "Compruebo que todo cuadra, fichero a fichero. Si algo no te gusta, lo deshaces.",
    ]

    static let explicacionCorta = "Hasta ahora trabajabas en una copia. Esto pasa tus cambios a tu carpeta de verdad."

    /// Las cifras de la vista previa para la cabecera de la hoja.
    var cifras: [(etiqueta: String, valor: Int)] {
        guard let v = vista else { return [] }
        return [("Se añaden", v.anadir), ("Cambian", v.cambiar), ("Se archivan", v.archivar), ("Se borran", 0)]
    }

    /// Los cambios efectivos de una acción (para las listas).
    func lista(_ a: CambioDeRelevo.Accion) -> [CambioDeRelevo] {
        vista?.efectivos.filter { $0.accion == a } ?? []
    }

    /// Lo que dice la comprobación al terminar.
    var textoDeComprobacion: String? {
        guard let r = resultado else { return nil }
        if r.correcto {
            return "Hecho y comprobado: \(Self.ficheros(r.comprobados)) uno a uno, y tu carpeta real tiene "
                + "\(Self.ficheros(r.recuentoDespues)), los que esperaba la vista previa."
        }
        return ErrorDeRelevo.comprobacionFallida(max(r.diferencias.count, 1)).localizedDescription
    }

    static func ficheros(_ n: Int) -> String { n == 1 ? "1 fichero" : "\(n) ficheros" }
}

extension ModeloRelevo {
    /// El modelo de la sesión abierta, o `nil` si en esta carpeta no toca (no es una copia con origen real).
    /// `estadoDelFork`: dónde mira los cerrojos de la otra aplicación (las pruebas ponen uno sintético).
    static func deLaSesion(_ sesion: VaultSession, registro: VaultRegistry,
                           estadoDelFork: URL = CerrojoDelRelevo.estadoDelForkPorDefecto) -> ModeloRelevo? {
        guard case .disponible(let realEntry) = DisponibilidadDelRelevo.evaluar(sesion.entry, registradas: registro.load()),
              let copia = sesion.root else { return nil }
        let real = registro.resolveURL(realEntry) ?? URL(fileURLWithPath: realEntry.ruta, isDirectory: true)
        let appSupport = registro.directory
        let aplicador = AplicadorDeRelevo(entorno: .init(appSupport: appSupport, registro: registro, estadoDelFork: estadoDelFork,
                                                         autor: sesion.autor))
        // El escritor de la real: solo para el relevo (`relevo: true`, `WritePolicy`), ya confirmado y con el cerrojo del
        // escritor anterior tomado por el aplicador. Después, la real se abre como cualquier carpeta que escribe.
        let abrir: AplicadorDeRelevo.AbrirEscritor = { entry, root in
            CommandBus(writer: try await VaultWriter.open(entry: entry, root: root,
                                                          options: .init(stateDirectory: appSupport.appendingPathComponent(
                                                              entry.id.uuidString.lowercased(), isDirectory: true),
                                                                         appSupport: appSupport, relevo: true)))
        }
        return ModeloRelevo(entorno: EntornoDelRelevo(copia: copia, copiaEntry: sesion.entry, real: real, realEntry: realEntry,
                                                      hoy: sesion.hoy, aplicador: aplicador, abrir: abrir))
    }
}
