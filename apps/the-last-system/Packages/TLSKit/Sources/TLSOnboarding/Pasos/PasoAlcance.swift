import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 0b · Alcance (PLAN §6.7, 1 pantalla): un proceso, un área o todo; decide cuántos pasos siguen
// («Quedan ~N min» cambia al momento). Y el consentimiento para usar Claude Code al afinar las respuestas: opcional,
// sin él todo funciona igual y nunca le llega nada privado.

public struct PasoAlcance: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .alcance) { _ in
            VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                if let q = modelo.motor.pregunta(.alcance) {
                    BloquePuesta(rotulo: q.texto, icono: "scope") {
                        OpcionesEnFilas(modelo: modelo, pregunta: q, opciones: q.tipo.opciones) { o in
                            switch o.id {
                            case "proceso": "arrow.triangle.turn.up.right.circle"
                            case "area": "square.grid.2x2"
                            default: "square.stack.3d.up"
                            }
                        }
                        PieEleccion(modelo: modelo, pregunta: q)
                        Text("Te quedan unos \(modelo.motor.quedanMinutos) minutos con lo que has elegido.")
                            .tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    .accessibilityIdentifier("puesta.pregunta.\(q.id.rawValue)")
                }
                if modelo.motor.alcance == .area {
                    BloquePuesta(rotulo: "¿Qué área?", icono: "square.grid.2x2") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: TLSEspacio.e8)], alignment: .leading,
                                  spacing: TLSEspacio.e8) {
                            ForEach(AreaCode.allCases, id: \.self) { a in
                                FilaOpcion(titulo: a.nombre, detalle: modelo.motor.contexto.catalogo.area(a)?.convierte,
                                           icono: a.tlsArea.simbolo, elegida: elegida(modelo, .alcanceArea) == a.rawValue) {
                                    Task { await modelo.contestar(.alcanceArea, .opcion(a.rawValue)) }
                                }
                                .accessibilityIdentifier("puesta.opcion.\(PreguntaID.alcanceArea.rawValue).\(a.rawValue)")
                            }
                        }
                        if let q = modelo.motor.pregunta(.alcanceArea) { PieEleccion(modelo: modelo, pregunta: q) }
                    }
                    .accessibilityIdentifier("puesta.pregunta.\(PreguntaID.alcanceArea.rawValue)")
                }
                if modelo.motor.alcance == .proceso, let q = modelo.motor.pregunta(.alcanceProceso) {
                    BloquePuesta(rotulo: q.texto, icono: "arrow.triangle.turn.up.right.circle") {
                        OpcionesEnMenu(modelo: modelo, pregunta: q, opciones: q.tipo.opciones)
                        if let o = q.tipo.opciones.first(where: { $0.id == elegida(modelo, q.id) }), let d = o.detalle {
                            Text(d).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                        PieEleccion(modelo: modelo, pregunta: q)
                        if modelo.faltan.contains(q.id) {
                            AvisoEnLinea(estado: .atencion, texto: "Elige el proceso o pulsa «No lo sé».")
                        }
                    }
                    .accessibilityIdentifier("puesta.pregunta.\(q.id.rawValue)")
                }
                asistente
            }
        }
        .accessibilityIdentifier("puesta.paso.alcance")
    }

    @ViewBuilder
    private var asistente: some View {
        if let q = modelo.motor.pregunta(.asistente) {
            let si = modelo.respuesta(.asistente)?.valor.siNo
            BloquePuesta(rotulo: q.texto, icono: "sparkles") {
                if let a = q.ayuda {
                    Text(a).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: TLSEspacio.e8) {
                    ChipOpcion(titulo: "Sí, úsalo", elegida: si == true) { Task { await modelo.usarAsistenteYConectar(true) } }
                        .accessibilityIdentifier("puesta.si.\(q.id.rawValue)")
                    ChipOpcion(titulo: "No, sin asistente", elegida: si == false) { Task { await modelo.usarAsistenteYConectar(false) } }
                        .accessibilityIdentifier("puesta.no.\(q.id.rawValue)")
                }
                PieEleccion(modelo: modelo, pregunta: q)
                if si == true { EstadoClaudeVista(estado: modelo.claude) }
            }
            .accessibilityIdentifier("puesta.pregunta.\(q.id.rawValue)")
        }
    }
}

/// Lo que se sabe de Claude Code, en una línea con icono.
struct EstadoClaudeVista: View {
    let estado: EstadoClaude

    var body: some View {
        switch estado {
        case .sinMirar:
            EmptyView()
        case .buscando:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Buscando Claude Code en este Mac…") }
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
        case .encontrado(_, let aviso):
            VStack(alignment: .leading, spacing: 4) {
                Label("Claude Code está en este Mac.", systemImage: TLSEstado.bien.simbolo)
                    .foregroundStyle(TLSPaleta.texto.color)
                if let aviso { Text(aviso).foregroundStyle(TLSPaleta.textoSecundario.color).fixedSize(horizontal: false, vertical: true) }
            }
            .tlsTexto(TLSTipo.interfaz)
        case .noEncontrado:
            AvisoEnLinea(estado: .sinDato, texto: "No encuentro Claude Code en este Mac. Sigo sin él: todo funciona igual.")
        case .probando:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Probando dentro de su caja…") }
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
        case .probado(let ok, let t):
            AvisoEnLinea(estado: ok ? .bien : .atencion, texto: t)
        }
    }
}

/// Debajo de una elección hecha a mano: de dónde sale lo marcado y «No lo sé».
struct PieEleccion: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta

    var body: some View {
        HStack(alignment: .center, spacing: TLSEspacio.e8) {
            OrigenEtiqueta(respuesta: modelo.respuesta(pregunta.id))
            Spacer(minLength: 0)
            if pregunta.admiteNoLoSe { BotonNoLoSe(modelo: modelo, pregunta: pregunta) }
        }
    }
}
