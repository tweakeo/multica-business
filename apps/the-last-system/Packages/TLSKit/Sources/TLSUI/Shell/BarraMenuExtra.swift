import AppKit
import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol mika. La app en la barra de menús (PLAN §6.1 `MenuBarExtra`, opcional y **apagada de serie**): cómo van
// los asistentes de cada empresa abierta (qué hacen ahora, lo que espera tu decisión, la línea de Mika), el
// interruptor y «Abrir Decisiones». Con «Trabajar con la ventana cerrada», además, mantiene abierta la última empresa
// para que los asistentes sigan aunque cierres su ventana. Lo añade `TLSScenes` con `EscenaBarraDeMenus(model:)`.

/// La escena de la barra de menús (solo se ve si la enciendes).
public struct EscenaBarraDeMenus: Scene {
    let model: AppModel
    @Bindable var preferencias: PreferenciasPresencia

    public init(model: AppModel) {
        self.model = model
        self.preferencias = .compartidas
    }

    init(model: AppModel, preferencias: PreferenciasPresencia) {
        self.model = model
        self.preferencias = preferencias
    }

    public var body: some Scene {
        MenuBarExtra(isInserted: $preferencias.barraDeMenus) {
            MenuBarraAsistentes(model: model, preferencias: preferencias)
                .environment(model)
                .environment(\.tlsEscalaTexto, model.escalaTexto)
        } label: {
            EtiquetaBarraDeMenus(model: model, preferencias: preferencias)
        }
        .menuBarExtraStyle(.window)
    }
}

/// El icono de la barra de menús. Vive mientras esté puesto: con «Trabajar con la ventana cerrada», retiene la última
/// empresa (su sesión sigue abierta y los asistentes trabajan).
struct EtiquetaBarraDeMenus: View {
    let model: AppModel
    let preferencias: PreferenciasPresencia
    @State private var retenida: UUID?

    var body: some View {
        Image(systemName: hayAlgo ? "sparkle.magnifyingglass" : "sparkle")
            .accessibilityLabel(hayAlgo ? "The Last System: algo espera tu decisión" : "The Last System: asistentes")
            .task(id: preferencias.ventanaCerrada) { retener(preferencias.ventanaCerrada) }
    }

    /// Algo espera tu decisión en alguna empresa abierta.
    private var hayAlgo: Bool {
        model.entries.contains { e in
            guard let s = model.sesionAbierta(e.id) else { return false }
            return (AlmacenHoy.de(s).datos?.pendientes ?? 0) > 0
        }
    }

    private func retener(_ si: Bool) {
        if si, retenida == nil, let id = model.ultimaEmpresa ?? model.entries.first?.id, model.retenerSesion(id) != nil {
            retenida = id
        } else if !si, let id = retenida {
            model.soltarSesion(id)
            retenida = nil
        }
    }
}

/// El contenido de la barra de menús.
struct MenuBarraAsistentes: View {
    let model: AppModel
    let preferencias: PreferenciasPresencia
    /// Las empresas abiertas (por defecto, las sesiones abiertas del modelo; las pruebas dan las suyas).
    var sesiones: (@MainActor () -> [VaultSession])? = nil
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(TLSPaleta.violetaTexto.color).accessibilityHidden(true)
                Text("Tus asistentes").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                Spacer()
            }
            let abiertas = sesiones?() ?? model.entries.compactMap { e in model.sesionAbierta(e.id) }
            if abiertas.isEmpty {
                Text("No hay ninguna empresa abierta: los asistentes trabajan mientras su empresa está abierta.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(abiertas, id: \.entry.id) { s in
                    EmpresaEnBarraDeMenus(sesion: s, abrir: abrir)
                    if s !== abiertas.last { Divider() }
                }
            }
            Divider()
            HStack {
                Button("Abrir The Last System") {
                    NSApp?.activate()
                    if let id = model.ultimaEmpresa { openWindow.abrirEmpresa(id) } else { openWindow(id: SceneID.launcher) }
                }
                .tlsBoton(.enlace)
                Spacer()
                SettingsLink { Text("Ajustes…") }.tlsBoton(.enlace)
            }
            if preferencias.ventanaCerrada {
                Text("Sigue con la ventana cerrada y se abre al iniciar sesión. Lo cambias en Ajustes › Asistentes.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(width: 340)
        .background(TLSPaleta.superficieElevada.color)
        .onAppear {
            let abrir = openWindow
            PreferenciasPresencia.abrirEmpresa = { id, destino in abrir.abrirEmpresa(id, destino: destino) }
        }
        .accessibilityIdentifier("barraDeMenus")
    }

    private func abrir(_ s: VaultSession, _ destino: Destino, mika: Bool = false) {
        PreferenciasPresencia.abrirEmpresa = { [openWindow] id, d in openWindow.abrirEmpresa(id, destino: d) }
        PreferenciasPresencia.abrir(s.entry.id, destino)
        if mika { ConversacionMika.de(s).abrir(contexto: .general) }
    }
}

/// Una empresa en la barra de menús: interruptor, qué hacen ahora, lo que espera tu decisión y la línea de Mika.
struct EmpresaEnBarraDeMenus: View {
    let sesion: VaultSession
    let abrir: (VaultSession, Destino, Bool) -> Void

    var body: some View {
        let a = AsistentesDeLaEmpresa.de(sesion)
        let datos = AlmacenHoy.de(sesion).datos
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Monograma(nombre: sesion.entry.nombre, tamano: 22)
                Text(sesion.entry.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                Spacer(minLength: 4)
            }
            InterruptorGeneralAsistentes(sesion: sesion, estilo: .compacto)
            ForEach(EstadoDeAsistentes.lineas(sesion: sesion), id: \.self) { l in
                Label(l, systemImage: "circle.fill")
                    .labelStyle(PuntoYTexto())
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
            }
            if let d = datos {
                Text(LineaMikaHoy.texto(datos: d, sesion: sesion).texto)
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                let n = datos?.pendientes ?? 0
                Button(n == 0 ? "Abrir Decisiones" : "Abrir Decisiones (\(n))") { abrir(sesion, .decisiones, false) }
                    .tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
                    .accessibilityIdentifier("barraDeMenus.decisiones")
                Button("Hablar con Mika") { abrir(sesion, .hoy, true) }.tlsBoton(.secundario)
            }
            if a.encendidos == false {
                AvisoEnLinea("En pausa: no empiezan nada nuevo.", estado: .sinDato)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sesion.entry.nombre)
    }
}

/// Un punto pequeño y el texto.
struct PuntoYTexto: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(TLSPaleta.violetaTexto.color).accessibilityHidden(true)
            configuration.title
        }
    }
}

/// Qué hacen los asistentes de una empresa ahora, en frases cortas.
enum EstadoDeAsistentes {
    @MainActor
    static func lineas(sesion: VaultSession) -> [String] {
        let a = AsistentesDeLaEmpresa.de(sesion)
        if a.encendidos == nil { return [] }
        let enCurso = a.enVivo?.trabajos.values.sorted { $0.desde < $1.desde } ?? []
        var out: [String] = []
        for t in enCurso.prefix(3) {
            let nombre = AsistenteConfigurado.nombre(de: t.agente)
            switch t.fase {
            case .enCola: out.append("\(nombre): en cola")
            case .esperandoRespuesta: out.append("\(nombre): espera tu respuesta")
            case .trabajando: out.append("\(nombre): \(t.frase.lowercased())")
            default: continue
            }
        }
        if out.isEmpty {
            let n = a.activos.count
            out.append(a.encendidos == false ? "Asistentes en pausa"
                       : (n == 0 ? "Ningún asistente activo" : (n == 1 ? "1 asistente activo, nada en marcha" : "\(n) asistentes activos, nada en marcha")))
        }
        return out
    }
}
