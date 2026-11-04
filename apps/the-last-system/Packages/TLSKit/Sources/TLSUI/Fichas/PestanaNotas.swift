import SwiftUI
import TLSCore
import TLSDesign

/// Pestaña Notas (§3.2): el texto de la nota, un bloque plegable por cada `##`, editable en el sitio
/// (`sustituirSeccion`, con la huella de lo leído). Las «Guía:» se ven como pista en gris; los `[falta: …]`,
/// como «Falta». Abajo, «Añadir nota» escribe una línea con fecha al final de «## Notas». Con `[[` se elige
/// una ficha y queda un enlace normal que se lee en cualquier editor.
struct PestanaNotas: View {
    let modelo: FichaModelo

    /// Secciones que van en otras pestañas.
    static let fuera: Set<String> = ["actividad", "historial", "todo lo relacionado"]

    var body: some View {
        let secciones = (modelo.cuerpo.map { MarkdownSections.titles(in: $0, level: 2) } ?? [])
            .filter { !Self.fuera.contains(TextFolding.fold($0)) && !(modelo.tipo == .task && TextFolding.fold($0) == "descripcion") }
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if secciones.isEmpty {
                VacioExplicado(icono: "text.alignleft", titulo: "Aún no tiene notas",
                               porQue: "Escribe abajo lo que quieras recordar: se guarda al final de «Notas» con la fecha de hoy.",
                               compacto: true)
            }
            ForEach(secciones.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }, id: \.self) { t in
                BloqueSeccion(modelo: modelo, titulo: t, ruta: modelo.ruta, cuerpo: modelo.cuerpo ?? "")
            }
            AnadirNota(modelo: modelo)
        }
    }
}

/// Un bloque `## Sección` plegable y editable en el sitio. `ruta`/`cuerpo`: la nota (esta ficha u otra, como
/// la tarea elegida en el tablero de un proyecto).
struct BloqueSeccion: View {
    let modelo: FichaModelo
    let titulo: String
    let ruta: VaultPath
    let cuerpo: String
    var guia: String? = nil
    @State private var abierto = true
    @State private var editando = false
    @State private var borrador = ""
    /// Huella de la sección al pulsar «Editar»: si cambia fuera mientras se escribe, no se pisa.
    @State private var huella: String?
    @State private var guardando = false
    /// La sección cambió fuera: el borrador sigue abierto y se ofrece «Ver diferencias».
    @State private var cambiadaFuera = false
    @State private var viendoDiferencias = false

    var body: some View {
        let contenido = MarkdownSections.content(of: titulo, in: cuerpo, level: 2)
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack {
                Button {
                    abierto.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: abierto ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold))
                        Text(titulo).tlsTexto(TLSTipo.tituloModulo)
                    }
                    .foregroundStyle(TLSPaleta.texto.color)
                    .frame(minHeight: TLSAltura.objetivoMinimo)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("\(titulo), \(abierto ? "abierto" : "plegado")")
                Spacer()
                if !editando {
                    Button("Editar") {
                        borrador = Self.sinGuias(contenido ?? "")
                        huella = modelo.huellaSeccion(titulo, en: ruta)
                        cambiadaFuera = false
                        editando = true
                        abierto = true
                    }
                    .tlsBoton(.discreto)
                    .disabled(!modelo.puedeEscribir || contenido == nil)
                    .accessibilityLabel("Editar «\(titulo)»")
                    .help(modelo.motivoSoloLectura.map { "No se puede editar: \($0)" } ?? "Editar en el sitio")
                }
            }
            if abierto {
                if editando {
                    EditorConEnlaces(texto: $borrador, modelo: modelo, desde: ruta, etiqueta: titulo)
                        .frame(minHeight: 120)
                    if cambiadaFuera {
                        HStack(spacing: TLSEspacio.e8) {
                            PastillaEstado(.atencion, palabra: "Cambió fuera")
                            Text("Mientras escribías, «\(titulo)» cambió en otra ventana o en otra app. Tu texto sigue aquí.")
                                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Ver diferencias…") { viendoDiferencias = true }.tlsBoton(.secundario)
                        }
                    }
                    HStack {
                        Text("Una línea por elemento. Con [[ enlazas otra ficha. ⌘↩ guarda · Esc cancela.")
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Spacer()
                        Button("Cancelar") { editando = false; cambiadaFuera = false }
                            .tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                        Button("Guardar") { Task { await guardar(borrador, huella: huella) } }
                            .tlsBoton(.principal, alto: 36)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(guardando || cambiadaFuera)
                            .help(cambiadaFuera ? "Antes mira las diferencias: la sección cambió fuera." : "Guardar «\(titulo)»")
                    }
                } else {
                    TextoDeSeccion(texto: contenido ?? "", guia: guia)
                }
            }
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .sheet(isPresented: $viendoDiferencias) {
            DiferenciasVersiones(
                titulo: titulo, mia: borrador, deFuera: Self.sinGuias(contenido ?? ""),
                alQuedarme: { Task { await guardar(borrador, huella: modelo.huellaSeccion(titulo, en: ruta)) } },
                alUsarFuera: { editando = false; cambiadaFuera = false },
                alCombinar: { combinado in
                    borrador = combinado
                    Task { await guardar(combinado, huella: modelo.huellaSeccion(titulo, en: ruta)) }
                })
        }
    }

    /// Guarda el borrador con la huella de cuando se empezó (o la de ahora, tras ver las diferencias). Solo
    /// cierra el editor si se guardó; si la sección cambió fuera, el borrador se queda abierto.
    private func guardar(_ texto: String, huella: String?) async {
        guard !guardando else { return }
        guardando = true
        defer { guardando = false }
        switch await modelo.guardarSeccion(titulo, texto: texto, en: ruta, huella: huella) {
        case .guardada:
            editando = false
            cambiadaFuera = false
        case .cambiadaFuera:
            cambiadaFuera = true
        case .noSePudo:
            break
        }
    }

    /// Quita las líneas «> Guía: …» (se ven como pista; no se editan).
    static func sinGuias(_ s: String) -> String {
        s.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("> Guía:") }
            .joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

/// El texto de una sección para leer: las «Guía:» en gris, los `[falta: …]` como «Falta», las tablas como tablas
/// (la fila de **Total** en negrita) y los enlaces con su texto visible.
struct TextoDeSeccion: View {
    let texto: String
    var guia: String? = nil

    /// Un trozo de la sección: una línea suelta o una tabla entera.
    enum Trozo: Hashable {
        case linea(String)
        case tabla(TablaMarkdown, [String])
    }

    static func trozos(_ texto: String) -> [Trozo] {
        var out: [Trozo] = []
        var tabla: [String] = []
        func cerrarTabla() {
            guard !tabla.isEmpty else { return }
            if let t = TablaMarkdown.leer(tabla) { out.append(.tabla(t, tabla)) } else { out += tabla.map(Trozo.linea) }
            tabla = []
        }
        for l in texto.components(separatedBy: "\n") {
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("|") { tabla.append(l); continue }
            cerrarTabla()
            out.append(.linea(l))
        }
        cerrarTabla()
        return out
    }

    var body: some View {
        let lineas = texto.components(separatedBy: "\n")
        let vacio = lineas.allSatisfy { let t = $0.trimmingCharacters(in: .whitespaces); return t.isEmpty || t.hasPrefix("> Guía:") }
        VStack(alignment: .leading, spacing: 4) {
            if vacio {
                Text(guia ?? lineas.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("> Guía:") }
                        .map { String($0.trimmingCharacters(in: .whitespaces).dropFirst("> Guía:".count)).trimmingCharacters(in: .whitespaces) }
                        ?? "Vacía. Pulsa «Editar» para escribir.")
                    .tlsTexto(TLSTipo.interfaz.enItalica)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                ForEach(Array(Self.trozos(texto).enumerated()), id: \.offset) { _, t in
                    switch t {
                    case .linea(let l): linea(l)
                    case .tabla(let tabla, _): VistaTablaMarkdown(tabla: tabla).padding(.vertical, 4)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func linea(_ l: String) -> some View {
        let t = l.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            Color.clear.frame(height: 4)
        } else if t.hasPrefix("> Guía:") {
            Text(String(t.dropFirst(2))).tlsTexto(TLSTipo.secundario.enItalica).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        } else if t.hasPrefix("<!--") {
            EmptyView()
        } else if t.contains("[falta:") {
            HStack(spacing: 6) {
                Text(LinkParser.plainText(t.replacingOccurrences(of: #"\[falta:[^\]]*\]"#, with: "…", options: .regularExpression)))
                    .tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                PastillaEstado(.atencion, palabra: "Falta")
            }
        } else if t.hasPrefix("### ") {
            Text(LinkParser.plainText(String(t.dropFirst(4)))).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                .padding(.top, 4)
        } else if let casilla = Self.casilla(t) {
            Label {
                Text(LinkParser.plainText(casilla.texto)).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                    .strikethrough(casilla.hecha)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: casilla.hecha ? "checkmark.square.fill" : "square")
                    .foregroundStyle(casilla.hecha ? TLSPaleta.bien.color : TLSPaleta.textoSecundario.color)
                    .accessibilityLabel(casilla.hecha ? "Hecha" : "Pendiente")
            }
        } else {
            Text(Self.conNegrita(t.hasPrefix("> ") ? "«" + t.dropFirst(2) + "»" : (t.hasPrefix("- ") || t.hasPrefix("* ") ? "• " + t.dropFirst(2) : t)))
                .tlsTexto(TLSTipo.lectura)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `- [ ] Llamar a Jorge` → casilla sin hacer.
    static func casilla(_ t: String) -> (texto: String, hecha: Bool)? {
        for (p, hecha) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false), ("* [x] ", true)] where t.hasPrefix(p) {
            return (String(t.dropFirst(p.count)), hecha)
        }
        return nil
    }

    /// El texto visible de la línea, con lo que va entre `**` en negrita.
    static func conNegrita(_ s: String) -> AttributedString {
        let plano = LinkParser.plainText(s)
        var out = AttributedString()
        let partes = plano.components(separatedBy: "**")
        for (i, p) in partes.enumerated() {
            var a = AttributedString(p)
            if i % 2 == 1, partes.count > 2 { a.inlinePresentationIntent = .stronglyEmphasized }
            out += a
        }
        return out
    }
}

/// Una tabla Markdown enseñada como tabla: la cabecera como rótulo, las cifras alineadas a la derecha y la fila en
/// **negrita** (el total) destacada.
struct VistaTablaMarkdown: View {
    let tabla: TablaMarkdown

    var body: some View {
        let columnas = max(tabla.cabecera.count, tabla.filas.map(\.count).max() ?? 0)
        Grid(alignment: .leading, horizontalSpacing: TLSEspacio.e16, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columnas, id: \.self) { i in
                    Text(LinkParser.plainText(i < tabla.cabecera.count ? tabla.cabecera[i] : ""))
                        .tlsTexto(TLSTipo.rotulo)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .gridColumnAlignment(Self.esCifra(columna: i, tabla) ? .trailing : .leading)
                }
            }
            .frame(minHeight: TLSAltura.cabeceraTabla)
            Divider().overlay(TLSPaleta.separador.color).gridCellUnsizedAxes(.horizontal)
            ForEach(Array(tabla.filas.enumerated()), id: \.offset) { _, fila in
                let negrita = fila.contains { TablaMarkdown.sinNegrita($0).negrita }
                GridRow {
                    ForEach(0..<columnas, id: \.self) { i in
                        let celda = TablaMarkdown.sinNegrita(i < fila.count ? fila[i] : "")
                        Text(LinkParser.plainText(celda.texto))
                            .tlsTexto(negrita ? TLSTipo.interfazFuerte : (Self.esCifra(columna: i, tabla) ? TLSTipo.cifraFila : TLSTipo.interfaz))
                            .foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: TLSAltura.filaTabla)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabla")
    }

    /// Una columna es de cifras si casi todas sus celdas lo son («150,00 €», «21 %», «1»).
    static func esCifra(columna i: Int, _ t: TablaMarkdown) -> Bool {
        let celdas = t.filas.compactMap { i < $0.count ? TablaMarkdown.sinNegrita($0[i]).texto : nil }.filter { !$0.isEmpty }
        guard !celdas.isEmpty else { return false }
        let cifras = celdas.filter { c in
            let limpio = c.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: " ", with: "")
            return !limpio.isEmpty && limpio.allSatisfy { $0.isNumber || ".,-h".contains($0) }
        }
        return cifras.count * 2 > celdas.count
    }
}

/// «Añadir nota»: una línea con la fecha de hoy al final de «## Notas», con `[[` para enlazar.
struct AnadirNota: View {
    let modelo: FichaModelo
    @State private var texto = ""

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Añadir nota").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
            HStack(alignment: .top) {
                CampoConEnlaces(texto: $texto, modelo: modelo, desde: modelo.ruta, placeholder: "Escribe una nota; con [[ enlazas una ficha") {
                    enviar()
                }
                Button("Añadir", action: enviar)
                    .tlsBoton(.principal, alto: 36)
                    .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty || !modelo.puedeEscribir)
            }
            Text("Se guarda al final de «Notas» con la fecha de hoy (\(modelo.hoy.description) · …). Con [[ eliges una ficha y queda un enlace normal que se lee en cualquier editor.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
    }

    private func enviar() {
        let t = texto
        texto = ""
        Task { await modelo.anadirNota(t) }
    }
}

/// Lo que hay después del último `[[` sin cerrar (lo que se está buscando para enlazar).
func consultaDeEnlace(_ texto: String) -> String? {
    guard let r = texto.range(of: "[[", options: .backwards) else { return nil }
    let resto = texto[r.upperBound...]
    if resto.contains("]]") || resto.contains("\n") { return nil }
    return String(resto)
}

/// Sustituye el último `[[consulta` por un enlace Markdown relativo a `destino` (el estilo de la carpeta).
func insertarEnlace(_ texto: String, a destino: FichaGrafo, desde: VaultPath) -> String {
    guard let r = texto.range(of: "[[", options: .backwards) else { return texto }
    return String(texto[..<r.lowerBound]) + NombresDeFicha.enlaceMarkdown(destino.nombre, desde: desde, a: destino.ruta) + " "
}

/// Sugerencias de fichas para `[[`.
struct SugerenciasEnlace: View {
    let consulta: String
    let modelo: FichaModelo
    let elegir: (FichaGrafo) -> Void

    var body: some View {
        let q = TextFolding.fold(consulta)
        let fichas = (modelo.grafo?.fichas.values.filter { !$0.privada && $0.tipo.abreComoFicha && $0.ruta != modelo.ruta } ?? [])
            .filter { q.isEmpty || TextFolding.fold($0.nombre).contains(q) }
            .sorted { $0.nombre.localizedStandardCompare($1.nombre) == .orderedAscending }
            .prefix(6)
        VStack(alignment: .leading, spacing: 2) {
            if fichas.isEmpty {
                Text("Ninguna ficha coincide. Sigue escribiendo o borra los [[.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).padding(6)
            }
            ForEach(Array(fichas)) { f in
                Button { elegir(f) } label: {
                    HStack {
                        Image(systemName: f.tipo.systemImage).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text(f.nombre).tlsTexto(TLSTipo.interfazMedia)
                        Spacer()
                        Text(f.tipo.etiqueta).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .buttonStyle(EstiloFila(alto: TLSAltura.filaTabla))
                .focusEffectDisabled()
                .accessibilityLabel("Enlazar con \(f.nombre) (\(f.tipo.etiqueta))")
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque).fill(TLSPaleta.superficieElevada.color))
        .tlsSombra(.dos, radio: TLSRadio.bloque)
    }
}

/// Campo de una línea con `[[` para enlazar.
struct CampoConEnlaces: View {
    @Binding var texto: String
    let modelo: FichaModelo
    let desde: VaultPath
    let placeholder: String
    let alEnviar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $texto, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let q = consultaDeEnlace(texto), let f = primera(q) { texto = insertarEnlace(texto, a: f, desde: desde) }
                    else { alEnviar() }
                }
                .disabled(!modelo.puedeEscribir)
                .accessibilityLabel(placeholder)
            if let q = consultaDeEnlace(texto) {
                SugerenciasEnlace(consulta: q, modelo: modelo) { f in texto = insertarEnlace(texto, a: f, desde: desde) }
            }
        }
    }

    private func primera(_ q: String) -> FichaGrafo? {
        let k = TextFolding.fold(q)
        return modelo.grafo?.fichas.values.filter { !$0.privada && $0.tipo.abreComoFicha && TextFolding.fold($0.nombre).contains(k) }
            .sorted { $0.nombre.localizedStandardCompare($1.nombre) == .orderedAscending }.first
    }
}

/// Editor de varias líneas con `[[` para enlazar (el editor completo es de TLSEditor; aquí basta el sencillo).
struct EditorConEnlaces: View {
    @Binding var texto: String
    let modelo: FichaModelo
    let desde: VaultPath
    let etiqueta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $texto)
                .font(TLSTipo.lectura.font())
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: TLSRadio.campo).fill(TLSPaleta.fondo.color))
                .overlay(RoundedRectangle(cornerRadius: TLSRadio.campo).strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1))
                .accessibilityLabel(etiqueta)
            if let q = consultaDeEnlace(texto) {
                SugerenciasEnlace(consulta: q, modelo: modelo) { f in texto = insertarEnlace(texto, a: f, desde: desde) }
            }
        }
    }
}
