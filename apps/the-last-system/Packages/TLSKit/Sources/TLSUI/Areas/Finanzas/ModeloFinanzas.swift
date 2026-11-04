import Foundation
import Observation
import SwiftUI
import TLSCore
import TLSDesign

/// El modelo de Finanzas › Operación y del Banco (F2 · rol areas-b): lee `LecturaFinanzas` fuera del hilo principal
/// con cada `sesion.revision` y hace lo que estas pantallas dejan hacer, **siempre con el clic de una persona** y como
/// ella (`sesion.autor`), con su aviso y Deshacer:
/// - importar un extracto (vista previa con huellas; nada se escribe sin «Importar»);
/// - confirmar una conciliación o «Confirmar las exactas» (por el dominio: sale `cobro.confirmado` y, de ahí, Ganada y
///   el proyecto, PLAN §4.7); ninguna regla ni asistente confirma un cobro (criterio F2-4);
/// - ignorar un movimiento sin factura, con su motivo;
/// - preparar el paquete del trimestre para la gestoría (nunca envía nada);
/// - cargar los movimientos heredados en preparación, sin confirmar ninguno (criterio F2-7; por el dominio en modo
///   importación: no dispara reglas).
@Observable @MainActor
final class ModeloFinanzas {
    let sesion: VaultSession
    /// La cuenta fija del Banco (`.banco(cuenta)`); `nil` = todas.
    let carpetaCuenta: VaultPath?
    private(set) var lectura: LecturaFinanzas?
    private(set) var revisionLeida = -1
    /// Trimestre elegido en Trimestre (`nil` = el que toca presentar).
    private(set) var periodoElegido: PeriodoTrimestre?
    /// Periodo de la gráfica de la caja.
    var rango: RangoCaja = .trimestre

    // MARK: Importar un extracto

    /// El fichero soltado o elegido (aún sin escribir).
    private(set) var extracto: (datos: Data, nombre: String)?
    /// Vista previa del extracto con la cuenta elegida.
    private(set) var vista: VistaPreviaExtracto?
    /// Cuenta en la que se importa (`id` de su ficha).
    private(set) var cuentaImportar: String?
    /// Leer sin el formato de la cuenta (el banco lo cambió): el formato adivinado se guarda en la ficha.
    private(set) var adivinarFormato = false
    private(set) var errorImportacion: String?

    // MARK: Resultado de lo último

    /// Lo último que salió bien («Importé 12 movimientos…»), para enseñarlo en su sitio.
    private(set) var hecho: String?
    /// Lo último que no se pudo hacer.
    private(set) var error: String?
    /// Hay una escritura en marcha o esperando su turno (los botones se apagan con «Escribiendo…»).
    var trabajando: Bool { enMarcha > 0 }
    private var enMarcha = 0
    @ObservationIgnored private var carga: Task<Void, Never>?
    /// La última escritura pedida: la siguiente espera a que termine (`enCola`).
    @ObservationIgnored private var ultimaEscritura: Task<Bool, Never>?

    init(sesion: VaultSession, cuenta: VaultPath? = nil) {
        self.sesion = sesion
        self.carpetaCuenta = cuenta
    }

    /// Por qué no se puede escribir ahora (o `nil` si se puede).
    var motivoSoloLectura: String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .soloLectura(let m): m.texto
        case .abriendo: "La carpeta aún se está abriendo"
        }
    }

    /// La cuenta del Banco, si la pantalla es de una cuenta.
    var cuentaFija: CuentaBancaria? { carpetaCuenta.flatMap { lectura?.cuenta(carpeta: $0) } }

    // MARK: Leer

    /// Relee si la carpeta cambió (o si `forzar`).
    func cargar(forzar: Bool = false) async {
        let revision = sesion.revision
        guard forzar || revision != revisionLeida || lectura == nil else { return }
        if let carga { await carga.value; if !forzar, revision == revisionLeida, lectura != nil { return } }
        let almacen = AlmacenRelaciones.de(sesion)
        if forzar { almacen.invalidar() }
        let periodo = periodoElegido
        let tarea = Task { [weak self] in
            await almacen.actualizar()
            guard let self, let foto = almacen.foto else { return }
            let hoy = self.sesion.hoy
            let leida = await Task.detached(priority: .userInitiated) {
                LecturaFinanzas(foto: foto, hoy: hoy, periodo: periodo)
            }.value
            guard !Task.isCancelled else { return }
            self.lectura = leida
            self.revisionLeida = revision
        }
        carga = tarea
        await tarea.value
        carga = nil
    }

    /// Enseña otro trimestre (`nil` = el que toca presentar).
    func elegirPeriodo(_ p: PeriodoTrimestre?) async {
        guard p != periodoElegido else { return }
        periodoElegido = p
        await cargar(forzar: true)
    }

    /// La foto de ahora (después de lo último escrito).
    private func fotoActual() async -> VaultSnapshot? {
        let almacen = AlmacenRelaciones.de(sesion)
        await almacen.actualizar()
        return almacen.foto
    }

    // MARK: Importar

    /// Lee el fichero soltado o elegido y prepara la vista previa (no escribe nada).
    func previsualizar(url: URL) async {
        let accede = url.startAccessingSecurityScopedResource()
        defer { if accede { url.stopAccessingSecurityScopedResource() } }
        do {
            let datos = try Data(contentsOf: url, options: .mappedIfSafe)
            await previsualizar(datos: datos, nombre: url.lastPathComponent)
        } catch {
            limpiarImportacion()
            errorImportacion = "No puedo leer «\(url.lastPathComponent)». Comprueba que el fichero esté en el Mac."
        }
    }

    /// Prepara la vista previa de un extracto (no escribe nada). Sin cuenta elegida, prueba en todas y se queda con la
    /// que ya tiene más movimientos de ese fichero (o la que tiene formato de extracto).
    func previsualizar(datos: Data, nombre: String) async {
        limpiarImportacion()
        extracto = (datos, nombre)
        guard let foto = await fotoActual() else { return }
        let hoy = sesion.hoy
        let fija = carpetaCuenta
        let elegida = await Task.detached(priority: .userInitiated) { () -> String? in
            let registros = RegistrosFinanzas(snapshot: foto)
            if let fija {
                return registros.cuentas.first { TextFolding.pathKey($0.carpeta.raw) == TextFolding.pathKey(fija.raw) }?.id
            }
            let imp = ImportadorExtracto(snapshot: foto, reloj: Reloj(hoy: hoy))
            let pruebas = registros.cuentas.map { c in (c, try? imp.vistaPrevia(datos, nombre: nombre, cuenta: c)) }
            let mejor = pruebas.max { a, b in
                let ka = (a.1?.yaImportadas.count ?? -1, a.1 != nil ? 1 : 0, a.0.formato != nil ? 1 : 0)
                let kb = (b.1?.yaImportadas.count ?? -1, b.1 != nil ? 1 : 0, b.0.formato != nil ? 1 : 0)
                return ka < kb
            }
            return mejor?.0.id
        }.value
        guard let elegida else {
            errorImportacion = "No hay ninguna cuenta del banco en Finanzas. Crea la ficha de la cuenta antes de importar."
            return
        }
        cuentaImportar = elegida
        await rehacerVista(foto: foto)
    }

    /// Cambia la cuenta en la que se importa y rehace la vista previa.
    func elegirCuenta(_ id: String) async {
        guard id != cuentaImportar, extracto != nil else { return }
        cuentaImportar = id
        await rehacerVista(foto: nil)
    }

    /// Vuelve a leer el extracto sin el formato de la cuenta (el banco lo cambió).
    func leerAdivinando() async {
        guard extracto != nil else { return }
        adivinarFormato = true
        await rehacerVista(foto: nil)
    }

    func cancelarImportacion() { limpiarImportacion() }

    private func limpiarImportacion() {
        extracto = nil; vista = nil; errorImportacion = nil; adivinarFormato = false; hecho = nil; error = nil
        if carpetaCuenta == nil { cuentaImportar = nil }
    }

    private func rehacerVista(foto: VaultSnapshot?) async {
        guard let extracto else { return }
        var f = foto
        if f == nil { f = await fotoActual() }
        guard let foto = f, let id = cuentaImportar else { return }
        let hoy = sesion.hoy
        let adivinar = adivinarFormato
        let r = await Task.detached(priority: .userInitiated) { () -> Result<VistaPreviaExtracto, ErrorImportacion> in
            let registros = RegistrosFinanzas(snapshot: foto)
            guard let cuenta = registros.cuenta(id: id) else { return .failure(.sinCuenta) }
            do {
                return .success(try ImportadorExtracto(snapshot: foto, reloj: Reloj(hoy: hoy))
                    .vistaPrevia(extracto.datos, nombre: extracto.nombre, cuenta: cuenta, adivinarFormato: adivinar))
            } catch let e as ErrorImportacion {
                return .failure(e)
            } catch {
                return .failure(.extracto(.ilegible))
            }
        }.value
        switch r {
        case .success(let v): vista = v; errorImportacion = nil
        case .failure(let e): vista = nil; errorImportacion = e.localizedDescription
        }
    }

    /// Escribe los movimientos nuevos de la vista previa (y el original en `Extractos/`). Con 0 nuevos, nada.
    /// Dos clics seguidos: el segundo espera al primero y, como la vista previa ya se ha escrito, no hace nada.
    @discardableResult
    func importar(deshacer: UndoManager?) async -> Bool {
        await enCola { await self.importarAhora(deshacer: deshacer) }
    }

    private func importarAhora(deshacer: UndoManager?) async -> Bool {
        guard let vista else { return false }
        guard let plan = vista.plan(autor: sesion.autor) else {
            hecho = "Nada nuevo: los \(vista.filas.count) movimientos ya estaban importados."
            self.vista = nil; extracto = nil
            return false
        }
        let n = vista.nuevas.count
        let texto = "Importé " + FormatoBase.cuenta(n, "movimiento nuevo", "movimientos nuevos") + " en \(vista.cuenta.nombre)"
        guard await escribir(plan, aviso: texto, deshacer: deshacer, dominio: true) else { return false }
        hecho = texto + "."
        self.vista = nil; extracto = nil; adivinarFormato = false
        return true
    }

    // MARK: Conciliar (solo una persona)

    /// Confirma una conciliación (el clic de la persona). Escribe el movimiento conciliado y su fila de `pagos.csv`.
    @discardableResult
    func confirmar(_ p: PropuestaConciliacion, deshacer: UndoManager?) async -> Bool {
        await confirmarLote([p], deshacer: deshacer)
    }

    /// «Confirmar las exactas» (de la cuenta del Banco, o de todas): un solo plan, un solo Deshacer.
    @discardableResult
    func confirmarLasExactas(deshacer: UndoManager?) async -> Bool {
        guard let l = lectura else { return false }
        let exactas = l.propuestas(de: cuentaFija).filter(\.exacta)
        guard !exactas.isEmpty else { error = ErrorConciliacion.nadaQueConfirmar.localizedDescription; return false }
        return await confirmarLote(exactas, deshacer: deshacer)
    }

    /// Cada confirmación se prepara con la foto de después de la anterior (`enCola`): dos «Confirmar» seguidos de
    /// cobros del mismo día dan `PAG-…-001` y `PAG-…-002`, y un doble clic en la misma no la repite (ya no está abierta).
    private func confirmarLote(_ ps: [PropuestaConciliacion], deshacer: UndoManager?) async -> Bool {
        await enCola { await self.confirmarLoteAhora(ps, deshacer: deshacer) }
    }

    private func confirmarLoteAhora(_ ps: [PropuestaConciliacion], deshacer: UndoManager?) async -> Bool {
        hecho = nil; error = nil
        guard let foto = await fotoActual() else { return false }
        let confirmacion: ConfirmacionConciliacion
        do {
            confirmacion = try Conciliador(snapshot: foto, reloj: Reloj(hoy: sesion.hoy)).confirmar(ps, autor: sesion.autor)
        } catch {
            self.error = error.localizedDescription
            return false
        }
        let texto = ps.count == 1
            ? "Confirmado: \(TextoFinanzas.euros(abs(ps[0].movimiento.importe))) de \(ps[0].factura.numeroVisible)"
            : "Confirmadas " + FormatoBase.cuenta(ps.count, "conciliación", "conciliaciones")
        guard await escribir(confirmacion.plan, aviso: texto, deshacer: deshacer, dominio: true) else { return false }
        hecho = texto + "."
        return true
    }

    /// Deja un movimiento como ignorado (no lleva factura: impuestos, nómina, traspaso…), con su motivo.
    @discardableResult
    func ignorar(_ m: MovimientoBanco, motivo: String, deshacer: UndoManager?) async -> Bool {
        await enCola { await self.ignorarAhora(m, motivo: motivo, deshacer: deshacer) }
    }

    private func ignorarAhora(_ m: MovimientoBanco, motivo: String, deshacer: UndoManager?) async -> Bool {
        hecho = nil; error = nil
        guard let foto = await fotoActual() else { return false }
        do {
            let plan = try Conciliador(snapshot: foto, reloj: Reloj(hoy: sesion.hoy)).planIgnorar(m, motivo: motivo, autor: sesion.autor)
            return await escribir(plan, aviso: "Movimiento ignorado: \(motivo.lowercased())", deshacer: deshacer, dominio: false)
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: Trimestre

    /// Prepara el paquete del trimestre que se ve (índice y 4 CSV) sin pisar nada y **sin enviarlo**.
    @discardableResult
    func prepararPaquete(deshacer: UndoManager?) async -> Bool {
        await enCola { await self.prepararPaqueteAhora(deshacer: deshacer) }
    }

    private func prepararPaqueteAhora(deshacer: UndoManager?) async -> Bool {
        hecho = nil; error = nil
        guard let l = lectura, let foto = await fotoActual() else { return false }
        let paquete = PreparadorPaquete(snapshot: foto, reloj: Reloj(hoy: sesion.hoy)).preparar(l.periodo)
        guard let plan = paquete.plan(autor: sesion.autor) else {
            hecho = paquete.resumen
            return false
        }
        let texto = "Preparé el paquete del \(l.periodo.titulo) para la gestoría"
        guard await escribir(plan, aviso: texto, deshacer: deshacer, dominio: false) else { return false }
        hecho = texto + ". No se ha enviado nada: está en su carpeta para que lo mandes tú."
        return true
    }

    // MARK: Heredados

    /// Carga los movimientos heredados de `Registros/importar/` en preparación (`estado_revision: pendiente`,
    /// `verificacion` vacía). Ninguno queda confirmado y `movimientos.csv` no se toca.
    @discardableResult
    func cargarHeredados(deshacer: UndoManager?) async -> Bool {
        await enCola { await self.cargarHeredadosAhora(deshacer: deshacer) }
    }

    private func cargarHeredadosAhora(deshacer: UndoManager?) async -> Bool {
        hecho = nil; error = nil
        guard let foto = await fotoActual() else { return false }
        let prep = LegacyMovementsImporter(snapshot: foto).preparar()
        guard let plan = prep.plan(autor: sesion.autor) else {
            hecho = prep.resumen
            return false
        }
        let texto = "Cargué " + FormatoBase.cuenta(prep.nuevas.count, "movimiento heredado", "movimientos heredados")
            + " en preparación"
        guard await escribir(plan, aviso: texto, deshacer: deshacer, dominio: true, importacion: true) else { return false }
        hecho = texto + ". Ninguno cuenta como cobrado hasta que lo revises."
        return true
    }

    // MARK: Meses de caja en Control

    /// La propuesta de PLAN §6.5 para FIN-RUNWAY: meta 3 meses y alerta 1 mes. Solo se escribe como propuesta en «Por
    /// qué»: la meta y la alerta las decides tú en Control, antes de ver el dato.
    static let propuestaRunway = "Propuesta: meta 3 meses, alerta 1 mes"

    /// Añade FIN-RUNWAY a `Metas.md` (una fila al final de la tabla, sin meta ni alerta) si aún no está.
    @discardableResult
    func anadirRunwayAMetas(deshacer: UndoManager?) async -> Bool {
        hecho = nil; error = nil
        guard let metas = lectura?.metas else { error = "No encuentro la nota Metas en Dirección."; return false }
        if let t = await fotoActual()?.text(metas), t.contains("| FIN-RUNWAY |") { return false }
        let celdas = ["Código": "FIN-RUNWAY", "Indicador": "Meses de caja", "Meta": "", "Alerta": "", "Por qué": Self.propuestaRunway]
        if let motivo = motivoSoloLectura { error = "No se puede escribir: \(motivo)."; return false }
        do {
            let r = try await sesion.escribir(.anadirFilaATabla(metas, tabla: TableSelector(columna: "Código"), celdas: celdas),
                                              aviso: "Meses de caja añadidos a Metas: fija su meta en Control", deshacer: deshacer)
            if case .conflicto = r.estado { error = "Metas cambió fuera de la app a la vez. Revísalo en Revisar."; return false }
        } catch {
            self.error = error.localizedDescription
            return false
        }
        await cargar(forzar: true)
        return true
    }

    // MARK: Escribir

    /// Una escritura detrás de otra (revisión final de F2): `trabajando` se enciende ya con el clic, antes de esperar a
    /// nada, y cada una prepara su plan cuando ha terminado la anterior, con la foto de después. Así dos clics seguidos
    /// (o «Importar» y «Confirmar» a la vez) nunca se preparan con la misma foto.
    private func enCola(_ trabajo: @escaping @MainActor () async -> Bool) async -> Bool {
        enMarcha += 1
        defer { enMarcha -= 1 }
        let anterior = ultimaEscritura
        let esta = Task { @MainActor () -> Bool in
            _ = await anterior?.value
            return await trabajo()
        }
        ultimaEscritura = esta
        return await esta.value
    }

    /// Escribe un plan como la persona: por el dominio (eventos y reglas) o directo. En modo importación las reglas no
    /// se disparan. Después relee.
    private func escribir(_ plan: WritePlan, aviso: String, deshacer: UndoManager?, dominio: Bool,
                          importacion: Bool = false) async -> Bool {
        if let motivo = motivoSoloLectura { error = "No se puede escribir: \(motivo)."; return false }
        let motor = dominio ? DominioEmpresa.motor(de: sesion) : nil
        if importacion, let motor { await motor.setModoImportacion(true) }
        var ok = false
        do {
            let r: WriteResult
            if dominio {
                r = try await sesion.escribirConDominio(plan: plan, aviso: aviso, deshacer: deshacer).escritura
            } else {
                r = try await sesion.escribir(plan: plan, aviso: aviso, deshacer: deshacer)
            }
            if case .conflicto = r.estado {
                error = "Alguien cambió estos registros a la vez. Revísalo en Revisar."
            } else {
                ok = true
            }
        } catch {
            self.error = error.localizedDescription
        }
        if importacion, let motor { await motor.setModoImportacion(false) }
        await cargar(forzar: true)
        return ok
    }
}
