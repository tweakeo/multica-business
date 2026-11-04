import Foundation
import TLSCore
import TLSDesign

/// El motor del dominio de cada empresa abierta con escritor (F2, rol de dominio: invariantes, eventos y reglas):
/// uno por sesión, sobre el mismo `CommandBus` que `sesion.escribir`. Al crearse termina lo que quedó a medias
/// (`procesarPendientes()`). Si la carpeta pasa a solo lectura y vuelve, se rehace con el escritor nuevo.
@MainActor
enum DominioEmpresa {
    private final class Entrada {
        weak var sesion: VaultSession?
        let motor: MotorDeDominio
        init(_ sesion: VaultSession, _ motor: MotorDeDominio) { self.sesion = sesion; self.motor = motor }
    }

    private static var motores: [ObjectIdentifier: Entrada] = [:]

    /// El motor de la empresa, o `nil` si la carpeta no se puede escribir ahora (solo lectura o abriéndose).
    static func motor(de sesion: VaultSession) -> MotorDeDominio? {
        // Fuera lo de empresas cerradas o sin escritor (no se retiene un escritor cerrado).
        motores = motores.filter { $0.value.sesion != nil && $0.value.sesion?.bus != nil }
        guard let bus = sesion.bus else { return nil }
        let k = ObjectIdentifier(sesion)
        if let e = motores[k], e.motor.bus === bus { return e.motor }
        let opciones = MotorDeDominio.Opciones(persona: sesion.persona)
        guard let motor = try? MotorDeDominio(bus: bus, opciones: opciones) else { return nil }
        motores[k] = Entrada(sesion, motor)
        Task { _ = await motor.procesarPendientes() }
        return motor
    }

    /// Tras deshacer: los eventos de esos planes (y lo que las reglas hicieron por ellos) dejan de contar.
    /// Se hace en el momento (no en una tarea aparte): si la persona lo repite enseguida, las reglas ya lo atienden.
    static func olvidar(_ planes: [UUID], de sesion: VaultSession) {
        guard let motor = motor(de: sesion) else { return }
        _ = try? motor.estado.olvidar(planes: planes)
    }
}

extension VaultSession {
    /// Escribe como la persona **a través del dominio** (invariantes, eventos y reglas; PLAN §4.7): lo que toca estados de
    /// oportunidades y proyectos, fichas o `Decisiones.md`. Igual que `escribir(_:)`: aviso «… · Deshacer» y ⌘Z.
    /// Un bloqueo (VEN-07, ENT-01, precio) lanza `DominioError.bloqueado` con su mensaje y alternativas, sin escribir.
    @discardableResult
    func escribirConDominio(_ comando: CommandBus.Comando, aviso: String? = nil, deshacer: UndoManager? = nil) async throws -> ResultadoDominio {
        let autor = self.autor
        return try await conDominio(descripcion: Self.descripcion(de: comando), aviso: aviso, deshacer: deshacer) { motor in
            try await motor.ejecutar(comando, autor: autor)
        }
    }

    /// Plan compuesto a través del dominio (todo o nada). El autor del plan debe ser `autor`.
    @discardableResult
    func escribirConDominio(plan: WritePlan, aviso: String? = nil, deshacer: UndoManager? = nil) async throws -> ResultadoDominio {
        try await conDominio(descripcion: plan.descripcion, aviso: aviso, deshacer: deshacer) { motor in
            try await motor.ejecutar(plan)
        }
    }

    private func conDominio(descripcion: String, aviso: String?, deshacer: UndoManager?,
                            _ hacer: (MotorDeDominio) async throws -> ResultadoDominio) async throws -> ResultadoDominio {
        _ = try busParaEscribir()
        guard let motor = DominioEmpresa.motor(de: self) else { throw WriteError.soloLectura }
        do {
            let r = try await hacer(motor)
            // Deshacer quita también lo que escribieron las reglas después (Ganada, el proyecto y sus tareas…).
            registrarDeshacer(r.escritura, descripcion: descripcion, aviso: aviso, deshacer: deshacer,
                              cadena: Self.planesDeReglas(r))
            return r
        } catch let e as DominioError {
            self.aviso = Aviso(e.localizedDescription, estado: .atencion)
            throw e
        } catch {
            self.aviso = Aviso(error.localizedDescription, estado: .mal)
            throw error
        }
    }
}
