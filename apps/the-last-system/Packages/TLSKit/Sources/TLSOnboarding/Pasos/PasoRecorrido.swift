import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 8 · Primer recorrido (PLAN §6.7 y §6.8): cinco cosas para probar con tu empresa (Hoy, el área del cuello,
// la primera propuesta de Mika, editar una ficha y verla en Finder). «Empezar el recorrido» abre tu empresa y lanza
// el tutorial «Recorrido con tu empresa» (`TutorialEventos.empezar(.tuEmpresa, …)`); las marcas se apuntan solas al
// hacerlas de verdad. La de la propuesta de Mika llega con los asistentes.

public struct PasoRecorrido: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .recorrido) { _ in
            VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                BloquePuesta(rotulo: "Cinco cosas para probar", icono: "map") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(HitoRecorrido.allCases.enumerated()), id: \.element) { i, h in
                            FilaHito(numero: i + 1, hito: h, hecho: modelo.motor.estado.recorrido[h.rawValue] != nil)
                            if h != HitoRecorrido.allCases.last {
                                Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).accessibilityHidden(true)
                            }
                        }
                    }
                    Text("Se marcan solas cuando las haces de verdad. Puedes dejarlo a medias y seguir otro día desde el menú Ayuda.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let q = modelo.motor.pregunta(.recorrido) {
                    BloquePuesta(rotulo: q.texto, icono: "figure.walk") {
                        OpcionesEnFilas(modelo: modelo, pregunta: q, opciones: q.tipo.opciones) { o in
                            o.id == "ahora" ? "play.circle" : "clock.arrow.circlepath"
                        }
                        OrigenEtiqueta(respuesta: modelo.respuesta(.recorrido))
                    }
                    .accessibilityIdentifier("puesta.pregunta.\(q.id.rawValue)")
                }
                ResumenPuesta(modelo: modelo)
            }
        }
        .accessibilityIdentifier("puesta.paso.recorrido")
    }
}

/// Una marca del recorrido.
struct FilaHito: View {
    let numero: Int
    let hito: HitoRecorrido
    let hecho: Bool

    var body: some View {
        HStack(spacing: TLSEspacio.e12) {
            ZStack {
                Circle().fill(hecho ? TLSPaleta.principal.color : TLSPaleta.bandeja.color).frame(width: 28, height: 28)
                if hecho {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(TLSPaleta.sobrePrincipal.color)
                } else {
                    Text("\(numero)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                }
            }
            .accessibilityHidden(true)
            Text(hito.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
            Spacer(minLength: 0)
            if hito.llegaConLosAsistentes {
                PastillaEstado(.sinDato, palabra: "Llega con los asistentes")
            } else if hecho {
                PastillaEstado(.bien, palabra: "Hecho")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(numero). \(hito.titulo)" + (hito.llegaConLosAsistentes ? ", llega con los asistentes" : hecho ? ", hecho" : ""))
    }
}

/// Lo que ha quedado hecho en la puesta en marcha, paso a paso (antes de terminar).
struct ResumenPuesta: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        let pasos = modelo.motor.pasosIncluidos.filter { $0 != .alcance && $0 != .recorrido }
        BloquePuesta(rotulo: "Cómo ha quedado", icono: "checklist") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(pasos, id: \.self) { p in
                    let e = modelo.motor.estado.paso(p)
                    HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                        Image(systemName: e.fase == .aplicado ? TLSEstado.bien.simbolo : e.fase == .omitido ? "arrow.uturn.forward" : TLSEstado.sinDato.simbolo)
                            .foregroundStyle(e.fase == .aplicado ? TLSEstado.bien.color.color : TLSPaleta.textoSecundario.color)
                            .accessibilityHidden(true)
                        Text(p.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                            .frame(width: 170, alignment: .leading)
                        Text(e.resumen ?? (e.fase == .pendiente ? "Pendiente" : ""))
                            .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("puesta.comoHaQuedado")
    }
}
