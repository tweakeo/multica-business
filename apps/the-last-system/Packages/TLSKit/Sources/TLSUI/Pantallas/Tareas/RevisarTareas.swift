import SwiftUI
import TLSCore
import TLSDesign

/// Las tarjetas de «Revisar» de las tareas: `Tareas.md` heredados (pasan a fichas con tu OK y el fichero va al
/// Archivo), «Adoptar» (tipo, identificador y relaciones propuestas, en una sola tarjeta), números repetidos
/// (se renumeran y se renombran a la vez) y tareas movidas en Finder (la ruta manda). Cada botón es el OK de la
/// persona: nada se escribe solo, todo con Deshacer. Sale en Tareas y se puede poner en «Revisar»
/// (`RevisarTareas(sesion:)`, ver docs/F2-CONTRATOS.md).
struct RevisarTareas: View {
    let sesion: VaultSession
    private let compartido: ModeloTareas?
    @State private var propio: ModeloTareas?
    /// Abierta: en «Revisar» siempre; en Tareas empieza plegada (una línea) y se recuerda en la pestaña.
    @State private var abierta: Bool
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav

    /// Con su propio modelo (para ponerla en otra pantalla, como «Revisar»).
    init(sesion: VaultSession) {
        self.sesion = sesion
        self.compartido = nil
        _propio = State(initialValue: ModeloTareas(sesion: sesion))
        _abierta = State(initialValue: true)
    }

    /// Con el modelo de la pantalla Tareas (plegada) o de «Revisar» (`abierta: true`; quien la pone la carga).
    init(modelo: ModeloTareas, abierta: Bool = false) {
        self.sesion = modelo.sesion
        self.compartido = modelo
        _propio = State(initialValue: nil)
        _abierta = State(initialValue: abierta)
    }

    private var modelo: ModeloTareas { compartido ?? propio ?? ModeloTareas(sesion: sesion) }

    var body: some View {
        let r = modelo.revision
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if r.hayAlgo {
                cabecera(r)
            }
            if r.hayAlgo, abierta {
                if let m = modelo.motivoSoloLectura {
                    Label("Para aplicarlas hay que poder escribir en la carpeta: \(m).", systemImage: "lock")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if !r.legados.isEmpty { legados(r.legados) }
                if !r.adopcion.vacia { adopcion(r.adopcion) }
                if !r.duplicados.isEmpty { duplicados(r.duplicados) }
                if !r.correcciones.isEmpty { correcciones(r.correcciones) }
            }
        }
        .task(id: sesion.revision) { if compartido == nil { await modelo.cargar() } }
        .onAppear { if compartido != nil, nav?.recuerdo(de: .tareas).extra["tareas.revisar"] == "1" { abierta = true } }
    }

    /// «Revisar · Por revisar 2 · Completar las fichas · 3 tareas cambiaron de carpeta» con «Ver» u «Ocultar».
    private func cabecera(_ r: RevisionTareas) -> some View {
        let titulos = [r.legados.isEmpty ? nil : (r.legados.count == 1 ? "Un Tareas.md heredado" : "\(r.legados.count) Tareas.md heredados"),
                       r.adopcion.vacia ? nil : "Completar las fichas",
                       r.duplicados.isEmpty ? nil : (r.duplicados.count == 1 ? "Un número repetido" : "\(r.duplicados.count) números repetidos"),
                       r.correcciones.isEmpty ? nil : (r.correcciones.count == 1 ? "Una tarea cambió de carpeta" : "\(r.correcciones.count) tareas cambiaron de carpeta")]
            .compactMap { $0 }
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        return HStack(spacing: TLSEspacio.e8) {
            Text("Revisar").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            InsigniaAviso(r.cuantas, palabra: "Por revisar", enCapsula: true)
            if !abierta {
                Text(titulos.joined(separator: " · ")).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button(abierta ? "Ocultar" : "Ver") {
                abierta.toggle()
                let valor = abierta
                if compartido != nil { nav?.actualizarRecuerdo(de: .tareas) { $0.extra["tareas.revisar"] = valor ? "1" : nil } }
            }
            .tlsBoton(.secundario)
            .accessibilityLabel(abierta ? "Ocultar lo que hay que revisar" : "Ver lo que hay que revisar")
        }
        .padding(.horizontal, TLSEspacio.e16)
        .frame(minHeight: TLSAltura.filaLista)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
    }

    private var puede: Bool { modelo.sesion.puedeEscribir }

    private func legados(_ l: [RevisionTareas.Legado]) -> some View {
        let total = l.reduce(0) { $0 + $1.titulos.count }
        let lineas = l.prefix(4).map { g in
            "«\(g.fichero.raw)»: " + (g.titulos.isEmpty ? "vacío, solo se retira" : (g.titulos.count == 1 ? "1 tarea" : "\(g.titulos.count) tareas"))
                + (g.titulos.isEmpty ? "" : " (" + g.titulos.prefix(3).joined(separator: " · ") + (g.titulos.count > 3 ? "…" : "") + ")")
        }
        return TarjetaRevisarTarea(icono: "list.bullet.rectangle",
                                   titulo: l.count == 1 ? "Un Tareas.md heredado" : "\(l.count) Tareas.md heredados",
                                   detalle: "Las tareas ya no viven en una lista: cada una pasa a su ficha, con su número, y el fichero va al Archivo. "
                                       + (total == 0 ? "No tienen tareas: solo se retiran." : "Se crean " + (total == 1 ? "1 ficha." : "\(total) fichas.")),
                                   lineas: Array(lineas)) {
            Button(total == 0 ? "Retirar al Archivo" : "Pasar a fichas") {
                Task { await modelo.aplicar(RevisionTareas.planHeredados, aviso: total == 0 ? "Retiré los Tareas.md vacíos" : "Pasé a fichas \(total == 1 ? "1 tarea heredada" : "\(total) tareas heredadas")") }
            }
            .tlsBoton(.principal, alto: 36).disabled(!puede)
            if let primero = l.first {
                Button("Ver el fichero") { navegar(.nota(primero.fichero), modo: .entrar) }.tlsBoton(.secundario)
            }
        }
    }

    private func adopcion(_ a: RevisionTareas.Adopcion) -> some View {
        var partes: [String] = []
        if a.identidades > 0 { partes.append(a.identidades == 1 ? "1 ficha sin identificar (se le añade su tipo y un identificador)" : "\(a.identidades) fichas sin identificar (se les añade su tipo y un identificador)") }
        if a.relaciones > 0 { partes.append(a.relaciones == 1 ? "1 relación deducida de sus enlaces" : "\(a.relaciones) relaciones deducidas de sus enlaces") }
        var lineas: [String] = a.ejemplos
        if a.relaciones + a.identidades > a.ejemplos.count { lineas.append("…") }
        if a.ambiguas > 0 { lineas.append(a.ambiguas == 1 ? "1 relación tiene varias fichas posibles: no se toca; elígela en su ficha." : "\(a.ambiguas) relaciones tienen varias fichas posibles: no se tocan; elígelas en cada ficha.") }
        return TarjetaRevisarTarea(icono: "checkmark.seal", titulo: "Completar las fichas de la carpeta",
                                   detalle: FormatoFicha.capital(partes.joined(separator: " y ")) + ". Solo se añaden propiedades; el texto no cambia.",
                                   lineas: lineas) {
            Button("Completar") { Task { await modelo.aplicar(RevisionTareas.planAdoptar, aviso: "Fichas completadas") } }
                .tlsBoton(.principal, alto: 36).disabled(!puede)
        }
    }

    private func duplicados(_ grupos: [[Tarea]]) -> some View {
        let lineas = grupos.prefix(4).map { g in
            let numero = g.first?.numero ?? "?"
            return "\(numero): se queda «\(g.first?.titulo ?? "")»; " + g.dropFirst().map { "«\($0.titulo)»" }.joined(separator: ", ")
                + (g.count == 2 ? " pasa al siguiente número libre" : " pasan a los siguientes números libres")
        }
        let repetidas = grupos.reduce(0) { $0 + $1.count - 1 }
        return TarjetaRevisarTarea(icono: "number",
                                   titulo: grupos.count == 1 ? "Un número de tarea repetido" : "\(grupos.count) números de tarea repetidos",
                                   detalle: "Pasa al copiar fichas de otra carpeta. La más antigua se queda con su número; "
                                       + (repetidas == 1 ? "la otra recibe uno nuevo" : "las otras reciben uno nuevo")
                                       + " y su fichero se renombra a la vez, con sus enlaces.",
                                   lineas: Array(lineas)) {
            Button("Renumerar") { Task { await modelo.renumerarRepetidas() } }
                .tlsBoton(.principal, alto: 36).disabled(!puede)
        }
    }

    private func correcciones(_ l: [CorreccionDeUbicacion]) -> some View {
        let lineas = l.prefix(4).map { c in "«\(c.tarea.stem)»: \(c.motivo)" }
        return TarjetaRevisarTarea(icono: "folder.badge.questionmark",
                                   titulo: l.count == 1 ? "Una tarea cambió de carpeta" : "\(l.count) tareas cambiaron de carpeta",
                                   detalle: "Se movieron fuera de la app. Manda la carpeta: se corrige su proyecto para que diga lo mismo.",
                                   lineas: Array(lineas)) {
            Button("Corregir") { Task { await modelo.aplicar(RevisionTareas.planCorrecciones, aviso: "Corregí el proyecto de \(l.count == 1 ? "1 tarea" : "\(l.count) tareas")") } }
                .tlsBoton(.principal, alto: 36).disabled(!puede)
        }
    }
}

/// Una tarjeta de revisión: icono, título, por qué, unas líneas de detalle y sus botones.
struct TarjetaRevisarTarea<Acciones: View>: View {
    let icono: String
    let titulo: String
    let detalle: String
    var lineas: [String] = []
    @ViewBuilder let acciones: Acciones

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .top, spacing: TLSEspacio.e12) {
                Image(systemName: icono)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(TLSPaleta.atencion.color)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Text(detalle).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(lineas, id: \.self) { l in
                        Text("· " + l).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                PastillaEstado(.atencion, palabra: "Con tu OK")
            }
            HStack(spacing: TLSEspacio.e8) { acciones }
                .padding(.leading, 40)
        }
        .padding(TLSEspacio.e20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
    }
}
