import AppKit
import SwiftUI
import TLSCore

/// Valor de una ventana (o pestaña de ventana) de empresa: `WindowGroup(id: "vault", for: VentanaRuta.self)`.
///
/// Lleva un `id` propio porque `WindowGroup` reutiliza la ventana si el valor es igual, y ⌘clic debe
/// abrir siempre una pestaña nueva (§7.1).
public struct VentanaRuta: Hashable, Codable, Sendable {
    public var empresa: UUID
    /// Dónde abre (`nil` = Hoy, o lo que se restaure de esa pestaña).
    public var destino: Destino?
    /// Camino natural delante del destino (migas sembradas).
    public var sembrar: [Destino]
    /// `false` = la pestaña nueva se abre detrás y la de origen sigue delante (⌘clic).
    public var alFrente: Bool
    /// `true` = ventana nueva, no pestaña (⌥⌘clic).
    public var nuevaVentana: Bool
    /// Ventana desde la que se abrió (para volver a ella si la nueva va detrás).
    public var origen: Int?
    public var id: UUID

    public init(empresa: UUID, destino: Destino? = nil, sembrar: [Destino] = [], alFrente: Bool = true,
                nuevaVentana: Bool = false, origen: Int? = nil, id: UUID = UUID()) {
        self.empresa = empresa; self.destino = destino; self.sembrar = sembrar; self.alFrente = alFrente
        self.nuevaVentana = nuevaVentana; self.origen = origen; self.id = id
    }
}

/// Cómo abrir un destino.
public enum ModoApertura: Sendable, Hashable {
    /// Según las teclas pulsadas: nada = entrar un nivel; ⌘ = pestaña nueva detrás; ⇧⌘ = pestaña nueva
    /// delante; ⌥⌘ = ventana nueva (§2.1).
    case automatico
    /// Entrar un nivel en esta pestaña.
    case entrar
    /// Raíz nueva en esta pestaña (barra lateral, ⌘1–9, ⌘K), con el camino natural delante si se da.
    case raiz(sembrar: [Destino])
    case pestanaNueva
    case pestanaNuevaAlFrente
    case ventanaNueva

    public static let raiz = ModoApertura.raiz(sembrar: [])
}

/// Acción de navegar de la pestaña de ventana (`@Environment(\.navegar)`), como `openURL`:
/// `navegar(.ficha(ruta))`, `navegar(.base("facturas"), modo: .pestanaNueva)`.
public struct NavegarAccion: Sendable {
    let nav: Navegacion?
    let empresa: UUID?
    let abrirVentana: @MainActor @Sendable (VentanaRuta) -> Void

    public init(nav: Navegacion?, empresa: UUID?, abrirVentana: @escaping @MainActor @Sendable (VentanaRuta) -> Void) {
        self.nav = nav; self.empresa = empresa; self.abrirVentana = abrirVentana
    }

    /// No hace nada (fuera de una ventana de empresa).
    public static let ninguna = NavegarAccion(nav: nil, empresa: nil) { _ in }

    @MainActor
    public func callAsFunction(_ destino: Destino, modo: ModoApertura = .automatico) {
        var modo = modo
        if case .automatico = modo { modo = Self.modo(teclas: NSEvent.modifierFlags) }
        switch modo {
        case .automatico, .entrar:
            nav?.entrar(destino)
        case .raiz(let sembrar):
            nav?.nuevaRaiz(destino, sembrar: sembrar)
        case .pestanaNueva, .pestanaNuevaAlFrente, .ventanaNueva:
            guard let empresa else { nav?.entrar(destino); return }
            let raiz = destino.puedeSerRaiz ? destino : (nav?.raiz ?? .hoy)
            let sembrar: [Destino] = destino.puedeSerRaiz ? [] : ((nav?.pila ?? []) + [destino])
            abrirVentana(VentanaRuta(empresa: empresa, destino: raiz, sembrar: sembrar,
                                     alFrente: modo != .pestanaNueva, nuevaVentana: modo == .ventanaNueva,
                                     origen: nav?.numeroVentana))
        }
    }

    /// ⌘ = pestaña nueva detrás; ⇧⌘ = delante; ⌥⌘ = ventana nueva; nada = entrar.
    public static func modo(teclas: NSEvent.ModifierFlags) -> ModoApertura {
        let t = teclas.intersection([.command, .shift, .option])
        if t.contains(.command), t.contains(.option) { return .ventanaNueva }
        if t.contains(.command), t.contains(.shift) { return .pestanaNuevaAlFrente }
        if t.contains(.command) { return .pestanaNueva }
        return .entrar
    }
}

extension EnvironmentValues {
    /// Navegar desde cualquier pantalla de la ventana de empresa.
    @Entry public var navegar: NavegarAccion = .ninguna
    /// Navegación de la pestaña de ventana (para leer migas, recuerdos o la vista previa).
    @Entry public var navegacion: Navegacion? = nil
}

extension FocusedValues {
    /// Navegación de la pestaña con el foco (menús Ir, ⌘[ ⌘], ⌘K).
    @Entry public var navegacion: Navegacion?
}
