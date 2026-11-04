import SwiftUI
import TLSCore
import TLSDesign

/// La tarea con su actividad «como un gestor de tareas, con la cara de Mosaico» (§3.4): a la izquierda la
/// Descripción (lo único editable del cuerpo), la línea de tiempo y la caja de comentario (con @ se menciona a un
/// asistente); a la derecha, el panel fijo de propiedades. Ningún asistente pone Hecha ni Cancelada (`TaskStore`).
struct ActividadTarea: View {
    let modelo: FichaModelo
    let tarea: VaultPath
    /// En la ficha de la tarea el panel de propiedades va a la derecha, siempre abierto.
    let panelFijo: Bool

    var body: some View {
        if panelFijo {
            HStack(alignment: .top, spacing: TLSEspacio.e16) {
                columnaIzquierda.frame(maxWidth: .infinity, alignment: .topLeading)
                PropiedadesTarea(modelo: modelo, tarea: tarea)
                    .frame(width: 300)
            }
        } else {
            columnaIzquierda
        }
    }

    private var texto: String {
        tarea == modelo.ruta ? (modelo.texto ?? "") : (modelo.almacen.foto?.text(tarea) ?? "")
    }

    private var columnaIzquierda: some View {
        let cuerpo = NoteDocument(text: texto).body
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        return VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if MarkdownSections.content(of: "Descripción", in: cuerpo) != nil {
                BloqueSeccion(modelo: modelo, titulo: "Descripción", ruta: tarea, cuerpo: cuerpo)
            }
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                Text("Actividad").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                LineaDeTiempo(entradas: ActividadDeFicha.leer(texto), hoy: modelo.hoy)
                Comentario(modelo: modelo, tarea: tarea)
            }
            .padding(TLSEspacio.e16)
            .background(forma.fill(TLSPaleta.superficie.color))
            .tlsSombra(.uno, forma: forma)
        }
    }
}

/// La caja de comentario de una tarea: se añade a su Actividad con fecha, hora y quién. Con @ se menciona a un
/// asistente (`@comercial`); retomarla es cosa del asistente cuando esté encendido.
struct Comentario: View {
    let modelo: FichaModelo
    let tarea: VaultPath
    @State private var texto = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                TextField("Comentar", text: $texto, prompt: Text("Escribe un comentario; con @ pides algo a un asistente"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit(enviar)
                    .accessibilityLabel("Comentario para la tarea")
                Button("Comentar", action: enviar)
                    .tlsBoton(.principal, alto: 36)
                    .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty || !modelo.puedeEscribir)
            }
            if let q = consultaMencion {
                FlujoChips(espacio: 6) {
                    ForEach(asistentes.filter { q.isEmpty || TextFolding.fold($0.nombre).contains(TextFolding.fold(q)) }, id: \.id) { a in
                        Button(a.nombre) { mencionar(a.id) }.tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
                    }
                }
            }
            Text("Con @ pides algo a un asistente y retoma la tarea. Ningún asistente la marca como hecha ni cancelada.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        }
        .disabled(!modelo.puedeEscribir)
    }

    private var asistentes: [(id: String, nombre: String)] {
        (modelo.grafo.map { Responsables.opciones(grafo: $0, persona: modelo.sesion.persona) } ?? [])
            .filter { $0.id.hasPrefix("agente:") }
    }

    private var consultaMencion: String? {
        guard let r = texto.range(of: "@", options: .backwards) else { return nil }
        let resto = texto[r.upperBound...]
        return resto.contains(" ") ? nil : String(resto)
    }

    private func mencionar(_ id: String) {
        guard let r = texto.range(of: "@", options: .backwards) else { return }
        texto = String(texto[..<r.lowerBound]) + "@" + id.replacingOccurrences(of: "agente:", with: "") + " "
    }

    private func enviar() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        texto = ""
        Task {
            guard EdicionRelaciones.comprobarEscritura(modelo.sesion) else { return }
            await modelo.almacen.actualizar()
            guard let foto = modelo.almacen.foto else { return }
            let store = TaskStore(snapshot: foto)
            guard let tarea = store.tarea(tarea) else {
                // No es una tarea con número: se añade a «Actividad» con su encabezado.
                let entrada = "### \(modelo.hoy) \(Reloj.sistema().hora) · \(modelo.sesion.persona)\n\(t)"
                _ = try? await modelo.sesion.escribir(.anadirASeccion(self.tarea, seccion: "Actividad", texto: entrada), aviso: "Comentario añadido")
                modelo.almacen.invalidar()
                return
            }
            do {
                let plan = try store.anadirActividad(tarea, autor: modelo.sesion.autor, texto: t, persona: modelo.sesion.persona)
                try await modelo.sesion.escribir(plan: plan, aviso: "Comentario añadido a \(tarea.numero ?? tarea.titulo)")
                modelo.almacen.invalidar()
            } catch let e as TareaError {
                modelo.sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
            } catch {}
        }
    }
}

/// El panel fijo de propiedades de una tarea: Estado, Prioridad, Responsable, Planificada, Vence, Estimación y
/// dedicadas, Proyecto (con «Cambiar…») y Área en solo lectura.
struct PropiedadesTarea: View {
    let modelo: FichaModelo
    let tarea: VaultPath

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Rotulo("Propiedades")
            if let f = modelo.grafo?.ficha(tarea) ?? (tarea == modelo.ruta ? modelo.ficha : nil) {
                ForEach(campos(f), id: \.key) { p in
                    CampoPropiedad(modelo: modelo, ficha: f, propiedad: p)
                }
                relacion(f, "proyecto")
                if let a = ResumenDeFicha.area(f) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Área").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text(a.etiquetaNumerada).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                        Text("Sale de su carpeta. Para cambiarla, se mueve la tarea a otra área.")
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(regla(f)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
    }

    /// Las de la tarea, en el orden del panel, aunque estén vacías (para poder ponerlas).
    private func campos(_ f: FichaGrafo) -> [Property] {
        ["estado", "prioridad", "responsable", "planificada", "vence", "estimacion_h", "dedicadas_h"].map { k in
            f.propiedades.properties.first { $0.key == k } ?? Property(key: k, value: .empty)
        }
    }

    private func relacion(_ f: FichaGrafo, _ prop: String) -> some View {
        let destinos = modelo.grafo?.destinos(de: f.ruta, propiedad: prop) ?? []
        return VStack(alignment: .leading, spacing: 2) {
            Text("Proyecto").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            HStack {
                if let d = destinos.first {
                    Button(modelo.grafo?.ficha(d)?.nombre ?? d.stem) { modelo.sesion.navegar(a: .ficha(d)) }
                        .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
                } else {
                    Text("Sin proyecto").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Spacer()
                Button("Cambiar…") { modelo.abrirSelector(propiedad: prop, origen: "panel", en: f.ruta) }
                    .tlsBoton(.secundario)
                    .disabled(!modelo.puedeEscribir)
                    .popover(item: Binding(get: { modelo.selector.flatMap { s in
                        if case .directo(let dueno, let p) = s.modo, dueno == f.ruta, p == prop, s.origen == "panel" { return s }
                        return nil } }, set: { if $0 == nil { modelo.selector = nil } }), arrowEdge: .leading) { p in
                        SelectorRelacion(peticion: p, sesion: modelo.sesion, almacen: modelo.almacen,
                                         alElegir: { d in Task { await modelo.elegido(d, en: p, navegar: nil) } },
                                         alQuitar: { Task { await modelo.quitar(propiedad: prop, destino: nil, guardaEn: f.ruta) } },
                                         alCrear: { _ in }, alListo: { _ in })
                    }
            }
        }
    }

    private func regla(_ f: FichaGrafo) -> String {
        let r = f.texto("responsable") ?? ""
        if r.lowercased().hasPrefix("agente:") {
            return "\(Responsables.nombre(de: r)) la coge cuando está Por hacer y ha llegado su fecha. Al terminar la deja En revisión: ningún asistente pone Hecha ni Cancelada."
        }
        return "La lleva una persona: la mueves tú cuando toque."
    }
}

/// El panel de la tarea elegida en el tablero del proyecto: su cabecera, «Abrir como ficha», sus propiedades
/// editables, la descripción y su actividad.
struct PanelTarea: View {
    let modelo: FichaModelo
    let tarea: VaultPath
    let cerrar: () -> Void
    @Environment(\.navegar) private var navegar

    var body: some View {
        let f = modelo.grafo?.ficha(tarea)
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f?.numero ?? "Tarea").tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text(f?.nombre ?? tarea.stem).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Button { cerrar() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .tlsBoton(.discreto)
                    .accessibilityLabel("Cerrar el panel de la tarea")
            }
            if let f, let e = f.estado {
                HStack {
                    PastillaEstado(FormatoFicha.tlsEstado(.task, e, hoy: modelo.hoy), palabra: e)
                    if EstadosDeFicha.esperaTuOK(.task, estado: e) { InsigniaAviso(nil, palabra: "Espera tu OK") }
                }
            }
            Button("Abrir como ficha") { navegar(.ficha(tarea), modo: .entrar) }
                .tlsBoton(.secundario)
                .accessibilityLabel("Abrir \(f?.numero ?? "la tarea") como ficha, un nivel más abajo")
            PropiedadesTarea(modelo: modelo, tarea: tarea)
            ActividadTarea(modelo: modelo, tarea: tarea, panelFijo: false)
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficieElevada.color))
        .tlsSombra(.dos, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tarea \(f?.numero ?? ""): \(f?.nombre ?? "")")
    }
}
