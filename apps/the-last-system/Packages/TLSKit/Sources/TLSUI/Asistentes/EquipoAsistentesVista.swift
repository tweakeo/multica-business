import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes (PLAN §6.5 · 6 · Equipo, SISTEMAS EQ2). Equipo › Operación › Asistentes: cómo están, su uso
// frente al tope (como parte del tope, nunca en dinero) y la Bitácora del mes, que se lee y se filtra por asistente.
// Sustituye al vacío de F2 («Llegan con los asistentes»).

struct EquipoAsistentesVista: View {
    let sesion: VaultSession
    let contexto: ContextoArea
    @State private var modelo: ModeloAsistentes
    @Environment(\.navegar) private var navegar

    init(sesion: VaultSession, contexto: ContextoArea) {
        self.sesion = sesion
        self.contexto = contexto
        _modelo = State(initialValue: ModeloAsistentes(sesion: sesion))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            if let l = modelo.lectura {
                contenido(l)
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo a los asistentes…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: modelo.claveRecarga) { await modelo.cargar() }
        .accessibilityIdentifier("equipo.asistentes")
    }

    @ViewBuilder
    private func contenido(_ l: LecturaAsistentes) -> some View {
        let vivos = l.asistentes.map { ($0, $0.estado(vivo: modelo.vivo($0.slug))) }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) { cifras(l, vivos: vivos) }
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) { cifras(l, vivos: vivos) }
        }
        Rotulo("Asistentes")
        TarjetaFilas {
            ForEach(Array(vivos.enumerated()), id: \.element.0.id) { i, par in
                if i > 0 { SeparadorFila(sangria: 52) }
                fila(par.0, estado: par.1)
            }
        }
        .accessibilityIdentifier("equipo.asistentes.lista")
        Rotulo("Bitácora")
        BitacoraAsistentesVista(sesion: sesion, lectura: l)
    }

    @ViewBuilder
    private func cifras(_ l: LecturaAsistentes, vivos: [(AsistenteEnLista, EstadoDeAsistente)]) -> some View {
        Mosaico("Uso del mes", icono: "gauge.with.dots.needle.33percent", pie: "De los asistentes activos, frente a la suma de sus topes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(l.usoTotal.cifra).tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                    Text("de tu tope").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    if l.usoTotal.simulado { MarcaSimulado() }
                }
                BarraUso(uso: l.usoTotal)
            }
        }
        .frame(minWidth: 240, minHeight: 132)
        Mosaico("Activos", icono: "sparkle", pie: "Los demás están apagados o su área no trabaja aún") {
            Text("\(l.asistentes.filter(\.activo).count) de \(l.asistentes.count)").tlsTexto(TLSTipo.cifraMedia)
                .foregroundStyle(TLSPaleta.texto.color)
        }
        .frame(minWidth: 200, minHeight: 132)
        let mes = l.bitacora.filter { $0.mes == l.mes }
        Mosaico("Trabajos este mes", icono: "list.bullet.rectangle", pie: "Sale de la bitácora") {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(mes.count)").tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                let sim = mes.filter(\.simulado).count
                if sim > 0 {
                    Text(sim == mes.count ? "todos simulados" : "\(sim) simulados")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
        .frame(minWidth: 200, minHeight: 132)
    }

    private func fila(_ a: AsistenteEnLista, estado: EstadoDeAsistente) -> some View {
        Button { navegar(.asistente(a.slug), modo: .entrar) } label: {
            HStack(spacing: TLSEspacio.e12) {
                IconoAsistente(a, tamano: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(a.uso.frase).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                }
                Spacer(minLength: TLSEspacio.e8)
                PastillaAsistente(estado)
            }
            .padding(.horizontal, TLSEspacio.e16)
            .frame(minHeight: TLSAltura.filaLista)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloFila())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.nombre). \(estado.palabra): \(estado.detalle). \(a.uso.frase)")
        .accessibilityHint("Abre su ficha")
        .accessibilityIdentifier("equipo.asistente.\(a.slug)")
    }
}
