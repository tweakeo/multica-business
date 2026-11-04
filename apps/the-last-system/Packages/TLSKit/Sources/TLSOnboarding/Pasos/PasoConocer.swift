import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 1 · Conocer tu negocio (PLAN §6.7, S1): el encuadre (camino y meta), la frase del negocio con sus
// cinco huecos, adónde quieres llegar (texto libre, en su propia pantalla) y una pantalla por área con controles 1–5
// grandes, el dolor y la meta (tres opciones), la etapa (preguntas que se paran en el primer «no») y la cita libre.
// «Lo que he entendido» enseña la foto de las áreas, el cuello (el destacado) y las etapas en llano antes de
// «Aplicar», que escribe el Diagnóstico y el Rumbo. En una copia de G3 todo llega en un resumen premarcado.

public struct PasoConocer: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .conocer) { p in
            switch p.id {
            case "conocer.encuadre":
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    ForEach(modelo.preguntas) { q in
                        BloquePuesta { FilaPregunta(modelo: modelo, pregunta: q, estilo: .filas) }
                    }
                }
            case "conocer.frase":
                FraseDelNegocio(modelo: modelo, preguntas: modelo.preguntas)
            case "conocer.destino":
                BloquePuesta(icono: "flag") {
                    ListaPreguntas(modelo: modelo, preguntas: modelo.preguntas)
                }
            case "conocer.entendido":
                Entendido(modelo: modelo)
            case "conocer.resumen":
                ResumenConocer(modelo: modelo)
            default:
                if let a = p.area { AreaConocer(modelo: modelo, area: a) }
            }
        }
        .accessibilityIdentifier("puesta.paso.conocer")
    }
}

/// «Ayudamos a… a conseguir… en… con…, sin…»: los cinco huecos y cómo queda la frase.
struct FraseDelNegocio: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]

    var frase: String {
        let t = PreguntaID.huecosDeLaFrase.map { id -> String in
            let v = modelo.borradores[id] ?? modelo.respuesta(id)?.valor.texto ?? ""
            return v.trimmingCharacters(in: .whitespaces).isEmpty ? "…" : v
        }
        return "Ayudamos a \(t[0]) a conseguir \(t[1]) en \(t[2]) con \(t[3]), sin \(t[4])."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let ref = preguntas.first?.referencia {
                NotaPuesta(icono: "doc.text", texto: ref)
            }
            BloquePuesta(rotulo: "Los cinco huecos", icono: "text.cursor") {
                ListaPreguntas(modelo: modelo, preguntas: preguntas, compacta: true)
            }
            BloquePuesta(rotulo: "Así queda", icono: "quote.opening") {
                Text(frase)
                    .tlsTexto(TLSTipo.lectura.tamano(17, interlinea: 25))
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("puesta.frase")
            }
        }
    }
}

/// Una pantalla por área: cómo va, qué duele, qué quieres, la etapa y la cita.
struct AreaConocer: View {
    @Bindable var modelo: ModeloPuesta
    let area: AreaCode

    func q(_ id: PreguntaID) -> Pregunta? { modelo.preguntas.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            BloquePuesta(rotulo: "Cómo va hoy", area: area) {
                VStack(alignment: .leading, spacing: TLSEspacio.e20) {
                    if let p = q(.funciona(area)) { FilaPregunta(modelo: modelo, pregunta: p) }
                    if let p = q(.depende(area)) { FilaPregunta(modelo: modelo, pregunta: p) }
                }
            }
            BloquePuesta(rotulo: "Lo que duele y lo que quieres", icono: "bandage") {
                VStack(alignment: .leading, spacing: TLSEspacio.e20) {
                    if let p = q(.dolor(area)) { FilaPregunta(modelo: modelo, pregunta: p, estilo: .filas) }
                    if let p = q(.metaArea(area)) { FilaPregunta(modelo: modelo, pregunta: p, estilo: .filas) }
                }
            }
            EtapaDelArea(modelo: modelo, area: area)
            if let p = q(.cita(area)) {
                BloquePuesta(rotulo: "Con tus palabras", icono: "quote.bubble") {
                    FilaPregunta(modelo: modelo, pregunta: p)
                }
            }
        }
    }
}

/// Las preguntas de etapa, una tras otra: se paran en el primer «no» y dicen en qué etapa queda.
struct EtapaDelArea: View {
    @Bindable var modelo: ModeloPuesta
    let area: AreaCode

    var etapa: Int? {
        for n in 1...6 {
            guard let v = modelo.motor.valor(.etapaPregunta(area, n)) else { return nil }
            if v.esNoLoSe { return nil }
            if v.siNo != true { return n }
        }
        return 6
    }

    var body: some View {
        let preguntas = modelo.preguntas.filter { $0.id.rawValue.hasPrefix("conocer.\(area.rawValue).etapa.") }
        BloquePuesta(rotulo: "En qué etapa está", icono: "stairs") {
            Text("Contesta sí o no. En cuanto digas «no», ya sé la etapa.")
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                ForEach(Array(preguntas.enumerated()), id: \.element.id) { i, p in
                    HStack(alignment: .top, spacing: TLSEspacio.e12) {
                        Text("\(i + 1)")
                            .tlsTexto(TLSTipo.cifraFila)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                            .frame(width: 18, alignment: .trailing)
                            .accessibilityHidden(true)
                        FilaPregunta(modelo: modelo, pregunta: p, compacta: true)
                    }
                }
            }
            if let e = etapa {
                let nombre = modelo.motor.contexto.catalogo.etapa(e)?.nombre ?? "Etapa \(e)"
                HStack(spacing: TLSEspacio.e8) {
                    PastillaEtapa("\(e) · \(nombre)", paso: e - 1, de: 6)
                    Text("Ahí veo \(TextosPuesta.nombreComun(area)) ahora.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("puesta.etapa.\(area.rawValue)")
            }
        }
    }
}

/// «Lo que he entendido»: la matriz, el cuello y las etapas, sacados de la vista previa del paso.
struct Entendido: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        if let e = modelo.vista?.entendido {
            LoQueHeEntendidoVista(entendido: e, etapas: modelo.motor.contexto.catalogo.etapas)
        } else if modelo.pasoHecho(.conocer) {
            NotaPuesta(icono: "checkmark.circle", texto: "Ya está en tu Diagnóstico y en tu Rumbo.")
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}

/// Copia de G3: todo lo que ya sé, premarcado, para confirmar o cambiar en una pantalla.
struct ResumenConocer: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        let todas = modelo.preguntas
        // Lo que no llegó premarcado va aparte, plegado en «Lo que falta».
        let blancas = modelo.pantalla.map { modelo.motor.enBlanco($0) } ?? []
        let enBlanco = Set(blancas.map(\.id))
        let porId = Dictionary(uniqueKeysWithValues: todas.filter { !enBlanco.contains($0.id) }.map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            let busca = [PreguntaID.camino, .metaGeneral].compactMap { porId[$0] }
            if !busca.isEmpty {
                BloquePuesta(rotulo: "Qué buscas", icono: "scope") {
                    ListaPreguntas(modelo: modelo, preguntas: busca, compacta: true)
                }
            }
            let frase = PreguntaID.huecosDeLaFrase.compactMap { porId[$0] }
            if !frase.isEmpty {
                BloquePuesta(rotulo: "La frase de tu negocio", icono: "quote.opening") {
                    ListaPreguntas(modelo: modelo, preguntas: frase, compacta: true)
                }
            }
            if let d = porId[.destino] {
                BloquePuesta(rotulo: "Adónde quieres llegar", icono: "flag") {
                    FilaPregunta(modelo: modelo, pregunta: d, sinTitulo: true)
                }
            }
            ForEach(modelo.motor.areasDelAlcance.filter { a in [PreguntaID.funciona(a), .depende(a), .etapa(a)].contains { porId[$0] != nil } },
                    id: \.self) { a in
                BloquePuesta(rotulo: a.nombre, area: a) {
                    VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                        ForEach([PreguntaID.funciona(a), .depende(a)].compactMap { porId[$0] }) { p in
                            FilaPregunta(modelo: modelo, pregunta: p, compacta: true)
                        }
                        if let p = porId[.etapa(a)] { EtapaElegida(modelo: modelo, pregunta: p) }
                    }
                }
            }
            LoQueFalta(modelo: modelo, preguntas: blancas)
            Entendido(modelo: modelo)
        }
    }
}

/// La etapa de un área elegida directamente (en el resumen), con el nombre de cada etapa.
struct EtapaElegida: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta

    var body: some View {
        let actual = modelo.respuesta(pregunta.id)?.valor.escala
        HStack(alignment: .top, spacing: TLSEspacio.e16) {
            Text("Etapa").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                .frame(width: 230, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                FlujoChipsPuesta(espacio: 6) {
                    ForEach(modelo.motor.contexto.catalogo.etapas) { e in
                        ChipOpcion(titulo: "\(e.num) · \(e.nombre)", elegida: actual == e.num) {
                            Task { await modelo.contestar(pregunta.id, .escala(e.num)) }
                        }
                        .accessibilityIdentifier("puesta.escala.\(pregunta.id.rawValue).\(e.num)")
                    }
                }
                OrigenEtiqueta(respuesta: modelo.respuesta(pregunta.id))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            BotonNoLoSe(modelo: modelo, pregunta: pregunta)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pregunta.texto)
        .accessibilityIdentifier("puesta.pregunta.\(pregunta.id.rawValue)")
    }
}
