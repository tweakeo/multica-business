import SwiftUI
import TLSCore
import TLSDesign
import TLSImport
import TLSUI

// F3 · rol ordenar. 2 · «Ordenar lo que tienes» (PLAN §6.7): en una carpeta por ordenar, «Lo que hay», «Preparar», «Por
// programa», «Repetidos» (si los hay), «Vista previa», «Comprobación» y «Calidad»; en la copia de una carpeta ya
// organizada (G3), «Completar las fichas», «Movimientos del banco» y «Calidad» (3 pantallas: el tope de 15 se cumple).
// Cada pantalla del motor (`ordenar.N`) es una de estas y la pinta TLSUI (`PantallaOrdenarVista`); la cabecera (título,
// «Quedan ~N min», «Seguir más tarde») y el pie («Atrás», «Saltar este paso», «Siguiente») los pone `OnboardingFlujo`.
// Nada se escribe antes de «Aplicar» (el botón del pie en la vista previa y en «Completar las fichas»: «Siguiente» no
// avanza sin aplicar); al aplicar o deshacer se le cuenta al motor
// (`registrarOrdenar`). El `init` es contrato con `OnboardingFlujo`.

public struct PasoOrdenar: View {
    @Bindable var modelo: ModeloPuesta
    @Environment(AppModel.self) private var appDelEntorno: AppModel?
    @Environment(\.openWindow) private var openWindow

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    private var app: AppModel? { modelo.entorno.app ?? appDelEntorno }

    public var body: some View {
        Group {
            if let ordenar = ConexionOrdenar.modelo(para: modelo, app: app) {
                contenido(ordenar)
            } else {
                VacioExplicado(icono: "folder.badge.questionmark", titulo: "Aún no hay carpeta que ordenar",
                               porQue: "Primero elige tu carpeta (o haz su copia) en la bienvenida. Después vuelve aquí.",
                               compacto: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("puesta.paso.ordenar")
    }

    private func contenido(_ ordenar: ModeloOrdenar) -> some View {
        let pantalla = pantallaActual(ordenar)
        let id = ordenar.acceso.entry.id
        let abrir = openWindow
        return PantallaOrdenarVista(pantalla: pantalla, modelo: ordenar, pasadoElPaso3: pasadoElPaso3,
                                    abrirBanco: { abrir.abrirEmpresa(id, destino: .banco(nil)) })
            .environment(\.ordenarSinTitulo, true)
            .environment(\.ordenarAplicarEnElPie, !modelo.repasando)
            .task(id: pantalla) { await preparar(pantalla, ordenar) }
            .onChange(of: ordenar.firmaPuesta) { _, _ in
                ConexionOrdenar.sincronizar(modelo, ordenar)
            }
            .onChange(of: ordenar.planes) { antes, ahora in
                // Tras «Aplicar» en la vista previa, a la comprobación.
                if pantalla == .vistaPrevia, antes.isEmpty, !ahora.isEmpty, ordenar.hecho != nil {
                    Task { await modelo.avanzar() }
                }
            }
    }

    // MARK: Qué pantalla es

    /// La pantalla del paso que corresponde a la del motor (por su título; si no, por su número).
    func pantallaActual(_ ordenar: ModeloOrdenar) -> PantallaOrdenar {
        ConexionOrdenar.pantalla(para: modelo, ordenar: ordenar)
    }

    private var pasadoElPaso3: Bool { modelo.motor.estado.paso(.organizar).fase == .aplicado }

    // MARK: Al llegar a cada pantalla

    private func preparar(_ pantalla: PantallaOrdenar, _ ordenar: ModeloOrdenar) async {
        ConexionOrdenar.preferirSesion(ordenar, app: app)
        ordenar.olvidarAvisos()
        await ordenar.arrancar()
        switch pantalla {
        case .preparar:
            if ordenar.ejecutorIA == nil, modelo.motor.estado.usarAsistente == true {
                ordenar.ejecutorIA = await ConexionOrdenar.buscarClaude(modelo, ordenar.acceso)
            }
        case .vistaPrevia, .completarFichas:
            if ordenar.vista == nil, !ordenar.cerrado, ordenar.zona != nil { await ordenar.prepararVista() }
        default:
            break
        }
        ConexionOrdenar.sincronizar(modelo, ordenar)
    }
}
