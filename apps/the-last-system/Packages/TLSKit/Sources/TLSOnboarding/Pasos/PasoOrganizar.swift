import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 3 · Organizar (PLAN §6.7, S2, ≤8 pantallas): el estado de cada área; por área activa o preparada,
// su rol y quién lo lleva y sus 2–3 sistemas (montado / a medias / falta); en Ventas, hasta tres ofertas y el embudo;
// en Entrega, el plan de entrega; el logo; y, si quieres, «¿Cómo llamas tú a…?». La vista previa enseña las fichas de
// área, los roles, la oferta y los sistemas que faltan antes de «Aplicar». En una copia de G3, un resumen premarcado.

public struct PasoOrganizar: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .organizar) { p in
            let preguntas = modelo.preguntas
            switch p.id {
            case "organizar.estados":
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    BloquePuesta(rotulo: "El estado de cada área", icono: "square.grid.2x2") {
                        EstadosDeArea(modelo: modelo, preguntas: preguntas.filter { $0.id.rawValue.hasSuffix(".estado") })
                    }
                    Vocabulario(modelo: modelo, preguntas: preguntas.filter { $0.id.rawValue.hasPrefix("organizar.vocabulario.") })
                }
            case "organizar.resumen":
                // Lo que no llegó premarcado va aparte, plegado en «Lo que falta».
                let blancas = modelo.motor.enBlanco(p)
                let enBlanco = Set(blancas.map(\.id))
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    ResumenOrganizar(modelo: modelo, preguntas: preguntas.filter { !enBlanco.contains($0.id) })
                    LoQueFalta(modelo: modelo, preguntas: blancas)
                }
            case "organizar.logo":
                BloquePuesta(rotulo: "Tu logo", area: .marca) { Logo(modelo: modelo, preguntas: preguntas) }
            default:
                if let a = p.area { AreaOrganizar(modelo: modelo, area: a, preguntas: preguntas) }
            }
        }
        .accessibilityIdentifier("puesta.paso.organizar")
    }
}

/// Activa, preparada o en reposo: una fila por área.
struct EstadosDeArea: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(preguntas) { q in
                HStack(alignment: .center, spacing: TLSEspacio.e12) {
                    if let a = q.area { IconoArea(a.tlsArea, tamano: 24) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.texto).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        OrigenEtiqueta(respuesta: modelo.respuesta(q.id))
                    }
                    .frame(width: 190, alignment: .leading)
                    OpcionesEnChips(modelo: modelo, pregunta: q, opciones: q.tipo.opciones)
                    Spacer(minLength: 0)
                    BotonNoLoSe(modelo: modelo, pregunta: q)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(q.texto)
                .accessibilityIdentifier("puesta.pregunta.\(q.id.rawValue)")
                if q.id != preguntas.last?.id {
                    Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).accessibilityHidden(true)
                }
            }
            HStack(spacing: TLSEspacio.e16) {
                ForEach(TextosPuesta.estadosArea) { o in
                    Text("\(o.texto): \(o.detalle ?? "")")
                }
            }
            .tlsTexto(TLSTipo.secundario)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .padding(.top, TLSEspacio.e8)
        }
    }
}

/// «¿Cómo llamas tú a…?» (opcional, plegado).
struct Vocabulario: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]
    @State private var abierto = false

    var body: some View {
        if !preguntas.isEmpty {
            BloquePuesta(rotulo: "¿Cómo llamas tú a…? (si quieres)", icono: "character.bubble") {
                Text("Si en tu empresa un cliente es un paciente o un proyecto es un expediente, dímelo y la app hablará como tú.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                if abierto || preguntas.contains(where: { modelo.respuesta($0.id) != nil }) {
                    ListaPreguntas(modelo: modelo, preguntas: preguntas, compacta: true)
                } else {
                    Button("Decir cómo lo llamo") { abierto = true }.tlsBoton(.secundario)
                        .accessibilityIdentifier("puesta.vocabulario")
                }
            }
        }
    }
}

/// Una pantalla por área: rol y quién lo lleva, sus sistemas y lo propio de cada área.
struct AreaOrganizar: View {
    @Bindable var modelo: ModeloPuesta
    let area: AreaCode
    let preguntas: [Pregunta]

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            DetalleArea(modelo: modelo, area: area, preguntas: preguntas, compacta: false)
        }
    }
}

/// Lo de un área: rol y ocupante, sistemas, ofertas y embudo, plan de entrega y logo.
struct DetalleArea: View {
    @Bindable var modelo: ModeloPuesta
    let area: AreaCode
    let preguntas: [Pregunta]
    let compacta: Bool

    func q(_ id: PreguntaID) -> Pregunta? { preguntas.first { $0.id == id } }

    var rol: RolStd? { modelo.motor.contexto.catalogo.roles.first { $0.area == area } }

    var sistemas: [Pregunta] { preguntas.filter { $0.id.rawValue.hasPrefix("organizar.sistema.") && $0.area == area || (area == .direccion && $0.id == .sistema("CO1")) } }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let o = q(.ocupante(area)) {
                SeccionPuesta(rotulo: rol.map { "Rol: \($0.nombre)" } ?? "Quién la lleva", icono: "person.crop.circle", anidada: compacta) {
                    if let m = rol?.mision, !compacta {
                        Text(TextosPuesta.llano(m)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FilaPregunta(modelo: modelo, pregunta: o, compacta: true)
                }
            }
            if !sistemas.isEmpty {
                SeccionPuesta(rotulo: "Sus sistemas", icono: "gearshape.2", anidada: compacta) {
                    if !compacta {
                        Text("Un sistema es una forma escrita de hacer algo que se repite. Lo que falte, te lo dejo preparado.")
                            .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ListaPreguntas(modelo: modelo, preguntas: sistemas, compacta: true)
                }
            }
            if area == .ventas { Ofertas(modelo: modelo, preguntas: preguntas, anidada: compacta) }
            if area == .entrega, let p = q(.planEntrega) {
                SeccionPuesta(rotulo: "Cómo entregas", icono: "list.number", anidada: compacta) {
                    FilaPregunta(modelo: modelo, pregunta: p, compacta: compacta, estilo: compacta ? .chips : .filas)
                }
            }
            if area == .marca, q(.logo) != nil {
                SeccionPuesta(rotulo: "Tu logo", icono: "seal", anidada: compacta) { Logo(modelo: modelo, preguntas: preguntas) }
            }
        }
    }
}

/// Ventas: hasta tres ofertas con su precio y el embudo.
struct Ofertas: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]
    var anidada = false

    func q(_ id: PreguntaID) -> Pregunta? { preguntas.first { $0.id == id } }

    var body: some View {
        SeccionPuesta(rotulo: "Lo que vendes", icono: "tag", anidada: anidada) {
            Text("Hasta tres ofertas, con su precio sin IVA. La segunda y la tercera, si las tienes.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                ForEach(1...3, id: \.self) { n in
                    if let nombre = q(.ofertaNombre(n)) {
                        HStack(alignment: .top, spacing: TLSEspacio.e12) {
                            FilaPregunta(modelo: modelo, pregunta: nombre)
                                .frame(maxWidth: .infinity)
                            if let precio = q(.ofertaPrecio(n)) {
                                FilaPregunta(modelo: modelo, pregunta: precio)
                                    .frame(width: 280)
                            }
                        }
                    }
                }
            }
        }
        if let e = q(.embudo) {
            SeccionPuesta(rotulo: "Tu embudo", icono: "line.3.horizontal.decrease", anidada: anidada) {
                FilaPregunta(modelo: modelo, pregunta: e, compacta: anidada, estilo: anidada ? .chips : .filas)
                if let pasos = q(.embudoEtapas) { FilaPregunta(modelo: modelo, pregunta: pasos, compacta: anidada) }
            }
        }
    }
}

/// El logo: «Ya lo tengo» (el fichero), «Está en mi web» (la dirección) o «Aún no tengo» (una tarea en Marca).
struct Logo: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ForEach(preguntas.filter { [.logo, .logoFichero, .logoWeb].contains($0.id) }) { p in
                FilaPregunta(modelo: modelo, pregunta: p, estilo: .filas)
            }
        }
    }
}

/// Copia de G3: cómo está organizada, área por área, premarcado para confirmar.
struct ResumenOrganizar: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            let estados = preguntas.filter { $0.id.rawValue.hasSuffix(".estado") }
            if !estados.isEmpty {
                BloquePuesta(rotulo: "El estado de cada área", icono: "square.grid.2x2") {
                    EstadosDeArea(modelo: modelo, preguntas: estados)
                }
            }
            ForEach(modelo.motor.areasConDetalle, id: \.self) { a in
                let propias = preguntas.filter { $0.area == a && !$0.id.rawValue.hasSuffix(".estado") || (a == .direccion && $0.id == .sistema("CO1")) }
                if !propias.isEmpty {
                    BloquePuesta(rotulo: a.nombre, area: a) {
                        DetalleArea(modelo: modelo, area: a, preguntas: propias, compacta: true)
                    }
                }
            }
            if !modelo.motor.areasConDetalle.contains(.marca), preguntas.contains(where: { $0.id == .logo }) {
                BloquePuesta(rotulo: "Tu logo", area: .marca) { Logo(modelo: modelo, preguntas: preguntas) }
            }
            Vocabulario(modelo: modelo, preguntas: preguntas.filter { $0.id.rawValue.hasPrefix("organizar.vocabulario.") })
        }
    }
}
