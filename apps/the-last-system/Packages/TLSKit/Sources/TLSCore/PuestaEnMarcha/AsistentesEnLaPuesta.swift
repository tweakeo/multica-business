import Foundation

// F4 · integración. Lo que escribe la puesta en marcha para dejar listos los asistentes de serie (PLAN §4.5 y §5.1):
// la sección de los asistentes en `.tls/config.yaml` y sus fichas de rol en `6 · Equipo/Roles/`. Lo sabe TLSAgents
// (`AsistentesDeSerie`, rol roles), que TLSCore no puede importar; TLSOnboarding lo pone en el motor
// (`OnboardingEngine.asistentes`). Se escribe en el paso 4 («Qué funciona sin ti»), en el mismo plan de la persona (un
// solo Deshacer); si ese paso no sale (ningún sistema que preguntar), en el 3 («Organizar»). Nunca cambia ni quita nada
// de lo que ya hay: si la carpeta ya trae `agentes:`, solo se añade lo que falte.

/// Quién sabe completar la configuración y las fichas de los asistentes de serie.
public protocol ProveedorAsistentesDeSerie: Sendable {
    /// `.tls/config.yaml` con lo que falte de los asistentes (interruptor, pausa por área, avisos, uso y `agentes:`).
    /// `estados`: los de la puesta en marcha (un área preparada o en reposo deja a su asistente sin activar).
    func completarConfig(_ texto: String, estados: [AreaCode: AreaStatus]) -> String
    /// Las fichas de rol de los asistentes que faltan (ruta y texto). `existe` dice si una ruta ya está.
    func fichas(layout: VaultLayout, existe: (VaultPath) -> Bool, semilla: String) -> [(ruta: VaultPath, texto: String)]
}

extension EstadoAreaPuesta {
    /// El estado que se escribe en `Área.md`.
    public var areaStatus: AreaStatus {
        switch self {
        case .activa: .activa
        case .preparada: .preparada
        case .reposo: .reposo
        }
    }
}

extension PlanesPuesta {
    /// Los asistentes de serie, en el plan de este paso (si el motor sabe escribirlos).
    func asistentes(_ b: inout BorradorCarpeta) throws {
        guard let proveedor = motor.asistentes else { return }
        var estados: [AreaCode: AreaStatus] = [:]
        for a in AreaCode.allCases {
            if let e = motor.estadoArea(a) {
                estados[a] = e.areaStatus
            } else if let s = contexto.areas[a]?.estado {
                estados[a] = s
            } else {
                estados[a] = .desconocido
            }
        }
        // Fuera del alcance de esta puesta en marcha: lo que diga su `Área.md` (sin estado, su asistente no se activa).
        for a in AreaCode.allCases where !motor.areasDelAlcance.contains(a) && motor.estadoArea(a) == nil {
            estados[a] = contexto.areas[a]?.estado ?? .desconocido
        }
        try cambiarConfig(&b) { proveedor.completarConfig($0, estados: estados) }
        let semilla = motor.estado.vaultID.uuidString.lowercased()
        for f in proveedor.fichas(layout: layout, existe: { b.existe($0) }, semilla: semilla) where !b.existe(f.ruta) {
            b.escribir(f.ruta, f.texto)
        }
    }
}
