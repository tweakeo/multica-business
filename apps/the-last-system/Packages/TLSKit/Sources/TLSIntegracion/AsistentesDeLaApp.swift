import AppKit
import Foundation
import OSLog
import TLSAgents
import TLSCore
import TLSUI

// F4 · integración. Los asistentes de todas las empresas abiertas: al abrir una con escritor (una copia o el ejemplo)
// se monta su `MotorDeEmpresa`; al cerrarla, al pasarla a solo lectura o al salir de la app, se para todo antes de soltar
// el escritor. Además: el Mac despierta → las rutinas se recalculan; la carpeta cambia → el motor vuelve a mirar; una
// vez al día, las aprobaciones de más de 14 días caducan.

@MainActor
public final class AsistentesDeLaApp: IntegracionDeEmpresas {
    /// La de la app (`instalar()` en el arranque).
    public static let compartido = AsistentesDeLaApp()

    public var opciones: MotorDeEmpresa.Opciones
    public private(set) var motores: [ObjectIdentifier: MotorDeEmpresa] = [:]
    private var montando: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var despertar: NSObjectProtocol?
    private weak var model: AppModel?
    private var instalada = false
    private var diario: Task<Void, Never>?
    private static let log = Logger(subsystem: "es.thelast.system", category: "Asistentes")

    public init(opciones: MotorDeEmpresa.Opciones = MotorDeEmpresa.Opciones()) {
        self.opciones = opciones
    }

    /// Engancha la integración a la app: las sesiones que abre `model` avisan aquí, el Mac al despertar, y ⌘Q para
    /// todo antes de salir.
    public func instalar(en model: AppModel) {
        model.integracionDeAsistentes = self
        self.model = model
        instalada = true
        TLSAppDelegate.alSalir = { [weak self] in await self?.pararTodo() }
        despertar = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.despertoElMac() }
        }
        diario?.cancel()
        diario = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 3600))
                await self?.caducarAprobaciones()
            }
        }
    }

    /// Solo en pruebas: deja de escuchar a las sesiones.
    public func desinstalar() async {
        await pararTodo()
        if let m = model, m.integracionDeAsistentes === self { m.integracionDeAsistentes = nil }
        model = nil
        if instalada { TLSAppDelegate.alSalir = nil }
        instalada = false
        if let d = despertar { NSWorkspace.shared.notificationCenter.removeObserver(d) }
        despertar = nil
        diario?.cancel()
        diario = nil
    }

    /// El motor de una empresa abierta, si lo hay.
    public func motor(de sesion: VaultSession) -> MotorDeEmpresa? { motores[ObjectIdentifier(sesion)] }

    // MARK: IntegracionDeEmpresas

    public func escritorListo(_ sesion: VaultSession) async {
        let k = ObjectIdentifier(sesion)
        if let viejo = motores[k] { await viejo.conexiones?.parar(); await viejo.parar(); motores[k] = nil }
        guard let piezas = sesion.piezasParaLosAsistentes() else { return }
        // F5 · integración: las conexiones de la empresa se montan con ella (y se paran con ella).
        var conexiones: ConexionesDeEmpresa?
        if let sistema = opciones.conexiones {
            do {
                conexiones = try ConexionesDeEmpresa(sesion: sesion, piezas: piezas, sistema: sistema,
                                                     prohibidas: model?.entries.map(\.ruta) ?? [])
            } catch {
                Self.log.error("No se pudieron montar las conexiones: \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
            }
        }
        let motor = MotorDeEmpresa(sesion: sesion, piezas: piezas, opciones: opciones, conexiones: conexiones)
        conexiones?.motor = motor
        motores[k] = motor
        let t = Task {
            await motor.arrancar()
            await conexiones?.arrancar()
        }
        montando[k] = t
        await t.value
        montando[k] = nil
    }

    public func escritorSeVa(_ sesion: VaultSession) async {
        let k = ObjectIdentifier(sesion)
        if let t = montando[k] { await t.value }
        guard let motor = motores.removeValue(forKey: k) else { return }
        await motor.conexiones?.parar()
        await motor.parar()
    }

    public func carpetaCambio(_ sesion: VaultSession, rutas: [VaultPath]) async {
        let m = motores[ObjectIdentifier(sesion)]
        m?.conexiones?.carpetaCambio()
        await m?.carpetaCambio()
    }

    // MARK: La app

    /// Al salir: para los asistentes de todas las empresas (cola, chats y servidor de herramientas).
    public func pararTodo() async {
        for t in montando.values { await t.value }
        let todos = Array(motores.values)
        motores = [:]
        await withTaskGroup(of: Void.self) { g in
            for m in todos { g.addTask { await m.conexiones?.parar(); await m.parar() } }
        }
    }

    func despertoElMac() async {
        for m in motores.values { await m.despertoElMac() }
        await caducarAprobaciones()
    }

    func caducarAprobaciones() async {
        for m in motores.values {
            do { _ = try await m.piezas.aprobaciones.caducar() } catch {
                Self.log.error("No se pudieron caducar las aprobaciones: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
