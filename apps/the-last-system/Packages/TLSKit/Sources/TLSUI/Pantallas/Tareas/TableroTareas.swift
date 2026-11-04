import SwiftUI
import TLSCore
import TLSDesign

/// El tablero de Tareas (PLAN §6.4): columnas Sin programar, Por hacer, En curso, En revisión, Bloqueada y Hecha
/// (Cancelada con «Ver canceladas»). Arrastrar una tarjeta a otra columna, ⌘← ⌘→ con la elegida, «Mover a…» del
/// menú y las acciones de VoiceOver cambian **solo** su estado (criterio F2-2) y lo apuntan en su Actividad.
/// Clic (o Tab) elige; doble clic o ↩ abre la tarea; la barra espaciadora enseña la vista previa.
struct TableroTareas: View {
    let modelo: ModeloTareas
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @FocusState private var enfocada: VaultPath?
    @State private var sobre: String?
    @State private var anchoVisible: CGFloat = 1000

    var body: some View {
        let columnas = modelo.columnas()
        let ancho = Self.anchoColumna(visible: anchoVisible, columnas: columnas.count)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: TLSEspacio.e12) {
                    ForEach(columnas) { c in columna(c, ancho: ancho) }
                }
                .padding(.bottom, 4)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { anchoVisible = $0 }
            Text("Clic (o Tab) elige una tarjeta y ↩ la abre. Arrástrala a otra columna o usa ⌘← y ⌘→: solo cambia su estado y queda apuntado en su actividad.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: enfocada) { _, r in if let r { modelo.elegida = r } }
    }

    /// Las columnas reparten el ancho visible; como mínimo 188 pt (si no caben, el tablero se desplaza).
    static func anchoColumna(visible: CGFloat, columnas n: Int) -> CGFloat {
        guard n > 0 else { return 188 }
        let espacio = TLSEspacio.e12 * CGFloat(n - 1)
        return max(188, floor((visible - espacio) / CGFloat(n)))
    }

    private func columna(_ c: GrupoTareas, ancho: CGFloat) -> some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        let estado = c.estado ?? .sinProgramar
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: 6) {
                // Un icono propio por columna (Sin programar, Por hacer y En curso ya no comparten el de «Sin dato»).
                Image(systemName: estado.simboloColumna).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(estado.tlsEstado.color.color)
                    .accessibilityHidden(true)
                Text(c.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                Text("\(c.filas.count)").tlsTexto(TLSTipo.secundario).monospacedDigit().foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Columna \(c.titulo), \(c.filas.count == 1 ? "1 tarea" : "\(c.filas.count) tareas")")
            if c.filas.isEmpty {
                Text(ColumnasTablero.vacio(estado)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            }
            ForEach(c.filas) { f in tarjeta(f) }
        }
        .padding(TLSEspacio.e8)
        .frame(width: ancho, alignment: .topLeading)
        .frame(minHeight: 220, alignment: .top)
        .background(forma.fill(TLSPaleta.bandeja.color))
        .overlay(forma.strokeBorder(sobre == c.id ? TLSPaleta.principal.color : .clear, style: StrokeStyle(lineWidth: 2, dash: [5])))
        .dropDestination(for: String.self) { items, _ in
            guard modelo.sesion.puedeEscribir,
                  let raw = items.first.flatMap({ ArrastreFila.id($0, empresa: modelo.sesion.entry.id) }) else { return false }
            Task { await modelo.mover(VaultPath(raw), a: estado) }
            return true
        } isTargeted: { dentro in
            sobre = dentro ? c.id : (sobre == c.id ? nil : sobre)
        }
        .accessibilityElement(children: .contain)
    }

    private func tarjeta(_ f: FilaTarea) -> some View {
        let elegida = modelo.elegida == f.ruta
        let hoy = modelo.hoy
        let t = f.tarea
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(f.numero).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer(minLength: 0)
                // Te toca: espera tu revisión (insignia con palabra, §1.5).
                if f.estado == .enRevision { InsigniaAviso(nil, palabra: "Espera tu OK") }
            }
            Text(f.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if f.area != nil || f.contenedorNombre != nil {
                HStack(spacing: 5) {
                    if let a = f.area { IconoArea(a.tlsArea, tamano: 16) }
                    Text(f.contenedorNombre ?? f.area?.nombre ?? "").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                }
            }
            if t.vence != nil {
                VenceTarea(vence: t.vence, abierta: f.abierta, hoy: hoy, conPalabraVence: true, corta: true)
            }
            HStack(spacing: 6) {
                ResponsableTarea(identificador: t.responsable, tamano: 22)
                // El «IA» de al lado ya dice que es un asistente: aquí, solo su nombre.
                Text(t.responsable.map { Responsables.nombre(de: $0).replacingOccurrences(of: " (asistente)", with: "") } ?? "Sin responsable")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                Spacer(minLength: 0)
                if let h = f.estimacionH {
                    Text(FilaDeTarea.horas(h)).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay(forma.strokeBorder(elegida ? TLSPaleta.principal.color : TLSPaleta.separador.color, lineWidth: elegida ? 2 : 1))
        .contentShape(forma)
        // Con el teclado como con el ratón: Tab la enfoca (anillo magenta) y la elige; ↩ abre, espacio vista previa.
        .focusable()
        .focused($enfocada, equals: f.ruta)
        .focusEffectDisabled()
        .tlsAnilloFoco(enfocada == f.ruta, radio: TLSRadio.tarjeta)
        .onKeyPress(.return) { navegar(.tarea(f.ruta)); return .handled }
        // ⌘← y ⌘→ con la tarjeta enfocada la mueven a la columna de al lado (alternativa al arrastre).
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { k in
            guard k.modifiers.contains(.command) else { return .ignored }
            mover(f.ruta, k.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(.space) { nav?.vistaPrevia = f.ruta; return .handled }
        .onTapGesture(count: 2) { navegar(.tarea(f.ruta)) }
        .onTapGesture { modelo.elegida = f.ruta; enfocada = f.ruta }
        .draggable(ArrastreFila.texto(f.ruta.raw, empresa: modelo.sesion.entry.id)) {
            Text(f.titulo).tlsTexto(TLSTipo.interfazFuerte).padding(8)
                .background(forma.fill(TLSPaleta.superficieElevada.color))
        }
        .vistaPrevia(ruta: f.ruta, sesion: modelo.sesion)
        .contextMenu { MenuDeTarea(fila: f, modelo: modelo) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FilaDeTarea.etiquetaAccesible(f, hoy: hoy))
        .accessibilityAddTraits(elegida ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Elige la tarjeta; la acción Abrir entra en la tarea")
        .accessibilityAction(.default) { modelo.elegida = f.ruta }
        .accessibilityAction(named: "Abrir") { navegar(.tarea(f.ruta), modo: .entrar) }
        .accessibilityActions {
            ForEach(EstadoTarea.allCases.filter { $0 != f.estado }, id: \.self) { e in
                Button("Mover a \(e.rawValue)") { Task { await modelo.mover(f.ruta, a: e) } }
            }
        }
    }

    /// Mueve la tarjeta a la columna de al lado y le devuelve el foco (sigue elegida en su columna nueva).
    private func mover(_ r: VaultPath, _ paso: Int) {
        modelo.elegida = r
        Task {
            if await modelo.moverAlLado(r, paso: paso) { enfocada = r }
        }
    }
}
