import SwiftUI
import TLSCore
import TLSDesign

/// La lista de Tareas (PLAN §6.4): estado · T-0042 · título · área · proyecto · responsable (iniciales o «IA») ·
/// planificada · vence (icono y palabra si venció) · estimación; agrupable. Clic (o ↩) abre la tarea un nivel más
/// abajo; ⌘clic, en una pestaña nueva; la barra espaciadora enseña la vista previa; el menú tiene «Mover a…».
struct ListaTareas: View {
    let modelo: ModeloTareas
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @State private var ancho: CGFloat = 1000
    @State private var plegados: Set<String> = []

    /// Por debajo de este ancho se ocultan las columnas de área y proyecto (siguen en el detalle y en VoiceOver).
    static let anchoCompleto: CGFloat = 1080

    var body: some View {
        let completa = ancho >= Self.anchoCompleto
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            cabecera(completa: completa)
            ForEach(modelo.grupos()) { g in
                grupo(g, completa: completa)
            }
        }
        .padding(.vertical, TLSEspacio.e8)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lista de tareas")
    }

    private func cabecera(completa: Bool) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            Text("Estado").frame(width: Columnas.estado, alignment: .leading)
            Text("Nº").frame(width: Columnas.numero, alignment: .leading)
            Text("Título").frame(maxWidth: .infinity, alignment: .leading)
            if completa {
                Text("Área").frame(width: Columnas.area, alignment: .leading)
                Text("Proyecto u oportunidad").frame(width: Columnas.contenedor, alignment: .leading)
            }
            Text("Quién").frame(width: Columnas.responsable, alignment: .leading)
            Text("Planificada").frame(width: Columnas.fecha, alignment: .leading)
            Text("Vence").frame(width: Columnas.vence, alignment: .leading)
            Text("Estim.").frame(width: Columnas.estimacion, alignment: .trailing)
        }
        .tlsTexto(TLSTipo.rotulo)
        .foregroundStyle(TLSPaleta.textoSecundario.color)
        .lineLimit(1)
        .padding(.horizontal, TLSEspacio.e16)
        .frame(minHeight: TLSAltura.cabeceraTabla)
        .accessibilityHidden(true)
    }

    private func grupo(_ g: GrupoTareas, completa: Bool) -> some View {
        let plegado = plegados.contains(g.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if plegado { plegados.remove(g.id) } else { plegados.insert(g.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: plegado ? "chevron.right" : "chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                    if let e = g.estado {
                        Image(systemName: e.simboloColumna).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(e.tlsEstado.color.color)
                    }
                    Text(g.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text("\(g.filas.count)").tlsTexto(TLSTipo.secundario).monospacedDigit().foregroundStyle(TLSPaleta.textoSecundario.color)
                    Spacer()
                }
                .padding(.horizontal, TLSEspacio.e16)
                .frame(minHeight: TLSAltura.filaTabla)
                .background(TLSPaleta.bandeja.color.opacity(0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("\(g.titulo), \(g.filas.count == 1 ? "1 tarea" : "\(g.filas.count) tareas"), \(plegado ? "plegado" : "abierto")")
            if !plegado {
                ForEach(g.filas) { f in
                    FilaDeTarea(fila: f, modelo: modelo, completa: completa)
                    if f.id != g.filas.last?.id { Divider().overlay(TLSPaleta.separador.color).padding(.leading, TLSEspacio.e16) }
                }
            }
        }
    }

    enum Columnas {
        static let estado: CGFloat = 118
        static let numero: CGFloat = 58
        static let area: CGFloat = 104
        static let contenedor: CGFloat = 170
        static let responsable: CGFloat = 40
        static let fecha: CGFloat = 86
        static let vence: CGFloat = 116
        static let estimacion: CGFloat = 44
    }
}

/// Una fila de la lista de Tareas.
struct FilaDeTarea: View {
    let fila: FilaTarea
    let modelo: ModeloTareas
    let completa: Bool
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @FocusState private var enfocada: Bool
    @State private var encima = false

    private typealias C = ListaTareas.Columnas

    var body: some View {
        let hoy = modelo.hoy
        let t = fila.tarea
        Button {
            modelo.elegida = fila.ruta
            navegar(.tarea(fila.ruta))
        } label: {
            HStack(spacing: TLSEspacio.e12) {
                PastillaEstado(fila.estado.tlsEstado, palabra: t.estadoTexto.flatMap { EstadoTarea(leyendo: $0) == nil ? $0 : nil } ?? fila.estado.rawValue)
                    .frame(width: C.estado, alignment: .leading)
                Text(fila.numero).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: C.numero, alignment: .leading)
                HStack(spacing: 6) {
                    Text(fila.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                    if let tipo = t.tipo, tipo != "tarea" {
                        Text(tipo == "decision" ? "Decisión" : (tipo == "pregunta" ? "Pregunta" : FormatoFicha.capital(tipo)))
                            .tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                            .padding(.horizontal, 6)
                            .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if completa {
                    HStack(spacing: 5) {
                        if let a = fila.area {
                            IconoArea(a.tlsArea, tamano: 16)
                            Text(a.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                        } else {
                            Text("—").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                    }
                    .frame(width: C.area, alignment: .leading)
                    Text(fila.contenedorNombre ?? "Sin proyecto").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(fila.contenedorNombre == nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(width: C.contenedor, alignment: .leading)
                }
                ResponsableTarea(identificador: t.responsable, tamano: 24)
                    .frame(width: C.responsable, alignment: .leading)
                Text(t.planificada.map { $0 == hoy ? "hoy" : FormatoFicha.fechaConDia($0, hoy: hoy) } ?? "—")
                    .tlsTexto(TLSTipo.secundario).lineLimit(1)
                    .foregroundStyle(t.planificada == nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                    .frame(width: C.fecha, alignment: .leading)
                VenceTarea(vence: t.vence, abierta: fila.abierta, hoy: hoy)
                    .frame(width: C.vence, alignment: .leading)
                Text(fila.estimacionH.map(Self.horas) ?? "—").tlsTexto(TLSTipo.cifraFila)
                    .foregroundStyle(fila.estimacionH == nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                    .frame(width: C.estimacion, alignment: .trailing)
            }
            .padding(.horizontal, TLSEspacio.e16)
            .frame(minHeight: TLSAltura.filaLista)
            .background(encima ? TLSPaleta.bandeja.color.opacity(0.7) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($enfocada)
        .focusEffectDisabled()
        .tlsAnilloFoco(enfocada, radio: TLSRadio.fila)
        .onHover { encima = $0 }
        .onKeyPress(.space) { nav?.vistaPrevia = fila.ruta; return .handled }
        .vistaPrevia(ruta: fila.ruta, sesion: modelo.sesion)
        .contextMenu { MenuDeTarea(fila: fila, modelo: modelo) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.etiquetaAccesible(fila, hoy: hoy))
        .accessibilityHint("Abre la tarea")
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            ForEach(EstadoTarea.allCases.filter { $0 != fila.estado }, id: \.self) { e in
                Button("Mover a \(e.rawValue)") { Task { await modelo.mover(fila.ruta, a: e) } }
            }
        }
    }

    /// «2 h», «1,5 h».
    static func horas(_ h: Double) -> String {
        let n = h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h).replacingOccurrences(of: ".", with: ",")
        return n + " h"
    }

    /// Lo que lee VoiceOver de una tarea: número, título, estado, área, proyecto, quién, fechas y estimación.
    static func etiquetaAccesible(_ f: FilaTarea, hoy: LocalDate) -> String {
        let t = f.tarea
        var partes = [f.numero, f.titulo, f.estado.rawValue]
        if let a = f.area { partes.append(a.nombre) }
        partes.append(f.contenedorNombre.map { (f.contenedorEsProyecto ? "proyecto " : "oportunidad ") + $0 } ?? "suelta")
        partes.append(t.responsable.map { "la lleva " + Responsables.nombre(de: $0) } ?? "sin responsable")
        if let p = t.planificada { partes.append("planificada " + FormatoFicha.cuando(p, hoy: hoy)) }
        if let v = t.vence { partes.append(f.vencida(hoy: hoy) ? "vencida el " + FormatoFicha.fechaConDia(v, hoy: hoy) : "vence " + FormatoFicha.cuando(v, hoy: hoy)) }
        if let h = f.estimacionH { partes.append("estimación " + horas(h)) }
        return partes.joined(separator: ", ")
    }
}

/// El menú contextual de una tarea en la lista o el tablero.
struct MenuDeTarea: View {
    let fila: FilaTarea
    let modelo: ModeloTareas
    @Environment(\.navegar) private var navegar

    var body: some View {
        Button("Abrir") { navegar(.tarea(fila.ruta), modo: .entrar) }
        Button("Abrir en pestaña nueva") { navegar(.tarea(fila.ruta), modo: .pestanaNueva) }
        if let c = fila.contenedor {
            Button("Ir a \(fila.contenedorNombre ?? c.stem)") { navegar(modelo.sesion.destino(para: c), modo: .entrar) }
        }
        Divider()
        MenuMoverA(actual: fila.estado) { e in Task { await modelo.mover(fila.ruta, a: e) } }
            .disabled(!modelo.sesion.puedeEscribir)
    }
}
