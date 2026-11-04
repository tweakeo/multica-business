import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 5 · Tu día a día (PLAN §6.7, S3): una sola rutina semanal para mirar la empresa (el lunes a las
// 9:00, 30 minutos, si te va bien; tú eliges día y hora) y cuántas horas al día quieres planificar como mucho (4 de
// serie). La vista previa enseña la rutina y el tope antes de «Aplicar».

public struct PasoDiaADia: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .diaADia) { _ in
            let qs = Dictionary(uniqueKeysWithValues: modelo.preguntas.map { ($0.id, $0) })
            VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                BloquePuesta(rotulo: "Tu rutina de la semana", icono: "calendar.badge.clock") {
                    Text("Un rato a la semana para mirar cómo va todo y decidir qué toca. Una sola: mejor una que se cumple que tres que no.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                        ForEach([PreguntaID.rutinaDia, .rutinaHora, .rutinaDuracion].compactMap { qs[$0] }) { q in
                            FilaPregunta(modelo: modelo, pregunta: q, compacta: true)
                        }
                    }
                    if let d = elegida(modelo, .rutinaDia), let h = modelo.respuesta(.rutinaHora)?.valor.texto {
                        let dia = TextosPuesta.dias.first { $0.id == d }?.texto.lowercased() ?? d
                        let min = modelo.respuesta(.rutinaDuracion)?.valor.numero.map { FormatoBase.cifraParaEditar($0) } ?? "30"
                        NotaPuesta(icono: "repeat", texto: "Cada \(dia) a las \(h), \(min) minutos.")
                    }
                }
                if let tope = qs[.topeHoras] {
                    BloquePuesta(rotulo: "Tu tope de horas", icono: "hourglass") {
                        FilaPregunta(modelo: modelo, pregunta: tope, compacta: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("puesta.paso.dia-a-dia")
    }
}
