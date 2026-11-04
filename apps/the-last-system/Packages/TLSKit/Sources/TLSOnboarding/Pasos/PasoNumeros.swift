import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 6 · Tus números (PLAN §6.7, S4, ≤4 pantallas): por área activa, un número clave y su meta y su
// alerta **antes de ver el dato** (la propuesta, 1,2 × lo de los últimos 90 días, sale marcada «Propuesto») o «Sin
// meta» / «Sin alerta». Si la alerta va al revés de lo que pide el número, se avisa en la misma fila. El objetivo de
// facturación del trimestre es opcional y llega premarcado «Sin objetivo de facturación».

public struct PasoNumeros: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .numeros) { p in
            if p.tipo != .vistaPrevia {
                let qs = Dictionary(uniqueKeysWithValues: modelo.preguntas.map { ($0.id, $0) })
                let areas = AreaCode.allCases.filter { qs[.numeroClave($0)] != nil }
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    ForEach(areas, id: \.self) { a in
                        BloquePuesta(rotulo: a.nombre, area: a) {
                            NumeroDeArea(modelo: modelo, area: a, preguntas: qs)
                        }
                    }
                    if let o = qs[.objetivo] {
                        BloquePuesta(rotulo: "Tu objetivo del trimestre (si quieres)", icono: "target") {
                            FilaPregunta(modelo: modelo, pregunta: o, sinTitulo: true)
                            if let c = qs[.objetivoCifra] { FilaPregunta(modelo: modelo, pregunta: c, compacta: true) }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("puesta.paso.numeros")
    }
}

/// El número de un área, con su meta y su alerta.
struct NumeroDeArea: View {
    @Bindable var modelo: ModeloPuesta
    let area: AreaCode
    let preguntas: [PreguntaID: Pregunta]

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if let n = preguntas[.numeroClave(area)] {
                FilaPregunta(modelo: modelo, pregunta: n, estilo: .filas)
            }
            if let codigo = elegida(modelo, .numeroClave(area)), let def = modelo.motor.contexto.catalogo.kpi(codigo) {
                Text(Self.sentido(def))
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach([PreguntaID.meta(area), .alerta(area)].compactMap { preguntas[$0] }) { q in
                FilaPregunta(modelo: modelo, pregunta: q, compacta: true)
            }
            if let aviso = avisoDeSentido {
                AvisoEnLinea(estado: .atencion, texto: aviso)
                    .accessibilityIdentifier("puesta.sentido.\(area.rawValue)")
            }
        }
    }

    /// La meta y la alerta van al revés de lo que pide el número (la alerta no avisaría nunca, o siempre).
    var avisoDeSentido: String? {
        guard let codigo = elegida(modelo, .numeroClave(area)), let def = modelo.motor.contexto.catalogo.kpi(codigo),
              let meta = modelo.respuesta(.meta(area))?.valor.numero, let alerta = modelo.respuesta(.alerta(area))?.valor.numero
        else { return nil }
        switch def.sentido {
        case .mas where alerta > meta:
            return "La alerta está por encima de la meta. Aquí cuanto más, mejor: la alerta va por debajo, o te avisaría siempre."
        case .menos where alerta < meta:
            return "La alerta está por debajo de la meta. Aquí cuanto menos, mejor: la alerta va por encima, o te avisaría siempre."
        default:
            return nil
        }
    }

    static func sentido(_ k: KPIDefinicion) -> String {
        switch k.sentido {
        case .mas: "Cuanto más, mejor. La alerta va por debajo de la meta."
        case .menos: "Cuanto menos, mejor. La alerta va por encima de la meta."
        default: "Lo bueno es quedarse dentro de un margen."
        }
    }
}
