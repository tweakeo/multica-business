import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol tareas (antes HUECO del andamio). El `init` es contrato con la ventana (`Shell/ContenidoEmpresa`, hoja
// `HojaVentana.nuevaTarea` que abre ⌘N; docs/F2-CONTRATOS.md §2). Criterio 1 de F2: ⌘N, título y ⏎ crean
// `…/Tareas/t-NNNN-slug.md` con el orden exacto de PLAN §4.2 y solo cambia además `.tls/secuencias.json` (lo
// garantiza `TaskStore.crear`; lo prueba `Tests/TLSUITests/Tareas/CriteriosF2Tests`). Lo demás es opcional: área (o
// el proyecto de la pantalla), quién la lleva (por defecto, tú) y el día planificado (ENT-04: nunca sábado ni domingo).

enum ErrorNuevaTarea: Error, LocalizedError {
    case sinCarpeta
    var errorDescription: String? { "No se pudo leer la carpeta. Vuelve a intentarlo en un momento." }
}

/// Hoja «Nueva tarea» (⌘N). `contexto` es la pantalla desde la que se abrió: en un área, la tarea es de esa área;
/// en un proyecto (o en una tarea de un proyecto), de ese proyecto; en Banco, de Finanzas.
struct NuevaTareaHoja: View {
    let contexto: Destino
    let sesion: VaultSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navegar) private var navegar
    @Environment(\.undoManager) private var undoManager
    @State private var titulo = ""
    @State private var area: AreaCode
    @State private var responsable: String?
    @State private var conDia = false
    @State private var dia = Date()
    @State private var creando = false
    @State private var error: String?
    @FocusState private var enfocado: Bool

    init(contexto: Destino, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
        _area = State(initialValue: Self.areaDe(contexto, sesion: sesion) ?? .direccion)
        _responsable = State(initialValue: sesion.persona)
    }

    /// El proyecto si se abrió desde la ficha de un proyecto (o desde una tarea que vive en un proyecto).
    private var proyecto: VaultPath? { Self.proyectoDe(contexto, sesion: sesion) }

    static func proyectoDe(_ d: Destino, sesion: VaultSession) -> VaultPath? {
        switch d {
        case .ficha(let r, _) where sesion.resumen(de: r)?.kind == .project:
            return sesion.esPrivado(r) ? nil : r
        case .tarea(let r):
            // `…/Proyectos/<slug>/Tareas/t-….md` → `…/Proyectos/<slug>/Proyecto.md`.
            let c = r.components
            guard c.count >= 4, let layout = sesion.estructura,
                  TextFolding.nameKey(c[c.count - 4]) == TextFolding.nameKey(layout.proyectos) else { return nil }
            let p = VaultPath(components: Array(c.prefix(c.count - 2))).appending("Proyecto.md")
            return sesion.resumen(de: p) != nil && !sesion.esPrivado(p) ? p : nil
        default:
            return nil
        }
    }

    static func areaDe(_ d: Destino, sesion: VaultSession) -> AreaCode? {
        switch d {
        case .area(let a, _): return a
        case .banco: return .finanzas
        default: return d.ruta.flatMap { sesion.estructura?.area(of: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text("Nueva tarea").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            TextField("Título", text: $titulo, prompt: Text("Qué hay que hacer"))
                .textFieldStyle(.roundedBorder)
                .focused($enfocado)
                .onSubmit(crear)
                .accessibilityIdentifier("nuevaTarea.titulo")
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                if let proyecto {
                    fila("Dónde") {
                        Label("En el proyecto «\(sesion.titulo(de: proyecto))»", systemImage: "folder")
                            .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    }
                } else {
                    fila("Área") {
                        Picker("Área", selection: $area) {
                            ForEach(AreaCode.allCases, id: \.self) { a in Text(sesion.area(a)?.etiquetaNumerada ?? a.etiquetaNumerada).tag(a) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("nuevaTarea.area")
                    }
                }
                fila("La lleva") {
                    Picker("La lleva", selection: $responsable) {
                        Text("Tú (\(sesion.persona))").tag(Optional(sesion.persona))
                        ForEach(asistentes, id: \.self) { a in Text(Responsables.nombre(de: a)).tag(Optional(a)) }
                        Text("Nadie todavía").tag(String?.none)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                fila("Cuándo") {
                    Toggle("Con día", isOn: $conDia).toggleStyle(.switch).controlSize(.small)
                    if conDia {
                        DatePicker("Día", selection: $dia, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .environment(\.locale, Locale(identifier: "es_ES"))
                    }
                }
                if conDia, LocalDate(date: dia).isWeekend {
                    Label("Ese día no se trabaja: se planifica el lunes \(FormatoFicha.fechaCorta(Tarea.laborable(LocalDate(date: dia))))",
                          systemImage: "calendar.badge.exclamationmark")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                }
            }
            Text(conDia ? "Nace «Por hacer» con su día." : "Nace «Sin programar»: le pones día cuando toque.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            if let error {
                Label(error, systemImage: TLSEstado.atencion.simbolo)
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
            }
            if !sesion.puedeEscribir {
                Label("No se puede crear: \(EdicionRelaciones.motivoSoloLectura(sesion) ?? "solo lectura").", systemImage: "lock")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            HStack {
                Text("↩ crea · Esc cancela").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer()
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Button("Crear", action: crear).tlsBoton(.principal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(creando || titulo.trimmingCharacters(in: .whitespaces).isEmpty || !sesion.puedeEscribir)
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 480)
        .onAppear { enfocado = true }
    }

    private func fila<C: View>(_ etiqueta: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            Text(etiqueta).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: 72, alignment: .leading)
            c()
            Spacer(minLength: 0)
        }
        .frame(minHeight: TLSAltura.objetivoMinimo)
    }

    /// Asistentes que pueden llevarla (uno por rol de Equipo y los que ya llevan algo), del grafo compartido.
    private var asistentes: [String] {
        ResponsablesTarea.asistentes(grafo: AlmacenRelaciones.de(sesion).grafo, persona: sesion.persona).map(\.id)
    }

    private func crear() {
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !creando, sesion.puedeEscribir else { return }
        creando = true
        Task {
            defer { creando = false }
            do {
                let ruta = try await Self.crear(titulo: t, area: proyecto == nil ? area : nil, proyecto: proyecto,
                                                responsable: responsable, planificada: conDia ? LocalDate(date: dia) : nil,
                                                sesion: sesion, deshacer: undoManager)
                dismiss()
                navegar(.tarea(ruta), modo: .entrar)
            } catch let e as TareaError {
                error = e.localizedDescription
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Crea la ficha (`…/Tareas/t-NNNN-slug.md`) con `TaskStore.crear` (orden de PLAN §4.2, contador en
    /// `.tls/secuencias.json`; nada más cambia) y la escribe como la persona, con Deshacer. Devuelve su ruta.
    static func crear(titulo: String, area: AreaCode?, proyecto: VaultPath?, responsable: String?, planificada: LocalDate?,
                      sesion: VaultSession, deshacer: UndoManager? = nil) async throws -> VaultPath {
        guard let foto = await sesion.instantanea() else { throw ErrorNuevaTarea.sinCarpeta }
        let nota = try TaskStore(snapshot: foto).crear(NuevaTarea(titulo: titulo, area: area, proyecto: proyecto,
                                                                 responsable: responsable,
                                                                 estado: planificada == nil ? nil : .porHacer,
                                                                 planificada: planificada, autor: sesion.autor))
        try await sesion.escribir(plan: nota.plan, aviso: "Creé \(nota.numero ?? "la tarea")", deshacer: deshacer)
        return nota.ruta
    }
}
