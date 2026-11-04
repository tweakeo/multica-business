import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 4 · Qué funciona sin ti (PLAN §6.7, ≤6 pantallas): por sistema y solo en las áreas activas. Son los
// mismos sistemas, con los mismos nombres, que en Organizar: si está montado ya lo dijiste allí (sale con su origen y no
// se vuelve a preguntar); aquí solo «¿Funciona sin ti?» y «¿Lo dejo a un asistente y tú lo revisas?». Lo sensible
// (enviar, facturar, pagar, escribir a clientes) queda bloqueado en «Siempre con tu OK» digas lo que digas. Decir «Sí»
// a dejarlo a un asistente lo pone en «Lo hace y revisas» y deja una revisión a los 7 días.

public struct PasoSinTi: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .sinTi) { p in
            if p.tipo != .vistaPrevia {
                let porSistema = Dictionary(grouping: modelo.preguntas) { Self.codigo($0.id) }
                // Los sistemas de esta pantalla (también los que no tienen nada que preguntar: a medias, «No lo sé»).
                let deLaPantalla = Set(p.preguntas.map { Self.codigo($0) })
                let sistemas = modelo.motor.sistemasSinTi.filter { deLaPantalla.contains($0.codigo) }
                let areas = AreaCode.allCases.filter { a in sistemas.contains { $0.area == a } }
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    ForEach(areas, id: \.self) { a in
                        BloquePuesta(rotulo: a.nombre, area: a) {
                            VStack(alignment: .leading, spacing: 0) {
                                let deArea = sistemas.filter { $0.area == a }
                                ForEach(deArea) { s in
                                    SistemaSinTi(modelo: modelo, sistema: s, preguntas: porSistema[s.codigo] ?? [])
                                    if s.codigo != deArea.last?.codigo {
                                        Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("puesta.paso.sin-ti")
    }

    /// `sinti.FI1.sinti` → `FI1`.
    static func codigo(_ id: PreguntaID) -> String {
        let partes = id.rawValue.split(separator: ".")
        return partes.count == 3 ? String(partes[1]) : ""
    }
}

/// Un sistema: si está montado (lo dijo Organizar), sus dos preguntas y sus funciones, con lo sensible bloqueado.
struct SistemaSinTi: View {
    @Bindable var modelo: ModeloPuesta
    let sistema: SistemaCatalogo
    let preguntas: [Pregunta]
    @State private var verFunciones = false

    var funciones: [CapacidadStd] {
        let codigos = sistema.estandar.compactMap { c in modelo.motor.contexto.catalogo.sistemas.first { $0.codigo == c } }
            .flatMap(\.capacidades)
        return modelo.motor.contexto.catalogo.capacidades.filter { codigos.contains($0.codigo) }
    }

    /// «Montado · Lo dijiste en Organizar».
    var enOrganizar: String {
        let r = modelo.respuesta(.sistema(sistema.codigo))
        let estado: String
        switch r?.valor {
        case .noLoSe?: estado = "No lo sabías: lo apunto como pendiente"
        case .opcion(let o)?: estado = TextosPuesta.estadosSistema.first { $0.id == o }?.texto ?? o
        default: estado = "Sin contestar en Organizar"
        }
        guard let r else { return estado }
        let origen = r.origen.clase == .persona ? "Lo dijiste en Organizar" : r.origen.texto
        return "\(estado) · \(origen)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sistema.nombre)
                    .tlsTexto(TLSTipo.tituloModulo)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Text(sistema.pregunta)
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                Label(enOrganizar, systemImage: "checklist")
                    .labelStyle(.titleAndIcon)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityIdentifier("puesta.sistema.\(sistema.codigo).organizar")
            }
            ForEach(preguntas) { q in
                FilaPregunta(modelo: modelo, pregunta: q, compacta: true)
            }
            let sensibles = funciones.filter { FuncionDeSistema.esSensible($0.nombre) }
            if !sensibles.isEmpty, modelo.respuesta(.automatizar(sistema.codigo))?.valor.siNo == true {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sensibles) { f in
                        Label {
                            Text("\(TextoLlano.de(f.nombre)) · Siempre con tu OK")
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityLabel("\(TextoLlano.de(f.nombre)): bloqueado, siempre con tu OK porque sale fuera")
                    }
                    Text("Sale fuera de la empresa: nunca se hace sin tu OK, digas lo que digas aquí.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
                .accessibilityIdentifier("puesta.sensible.\(sistema.codigo)")
            }
            if !funciones.isEmpty, !preguntas.isEmpty {
                Button(verFunciones ? "Ocultar sus funciones" : "Ver sus \(funciones.count) funciones") { verFunciones.toggle() }
                    .tlsBoton(.enlace)
                if verFunciones {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(funciones) { f in
                            let sensible = FuncionDeSistema.esSensible(f.nombre)
                            Label(TextoLlano.de(f.nombre), systemImage: sensible ? "lock.fill" : "circle.fill")
                                .labelStyle(.titleAndIcon)
                                .tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                                .accessibilityLabel(TextoLlano.de(f.nombre) + (sensible ? ", siempre con tu OK" : ""))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("puesta.sistema.\(sistema.codigo)")
    }
}

/// Los nombres del estándar sin jerga («agéntico», «KPI», «Onboarding»…).
enum TextoLlano {
    static func de(_ s: String) -> String {
        var t = TextosPuesta.llano(s)
        for (a, b) in [("agénticos", "con asistentes"), ("agéntico", "con asistente"), ("agénticas", "con asistentes"),
                       ("Agéntico", "Con asistente"), ("KPIs", "números clave"), ("KPI", "número clave"),
                       ("onboarding", "arranque"), ("runway", "meses de caja")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }
}
