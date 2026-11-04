import AppKit
import SwiftUI
import TLSCore
import TLSDesign

/// Las propiedades de una nota como formulario (PLAN §6.6, DISEÑO §3.1 punto 8): el bloque de propiedades no
/// entra en el texto del editor y **cada cambio escribe una sola clave** (`cambiarPropiedades`), con aviso y
/// Deshacer. Los enlaces de las propiedades (`"[[comercial|Comercial]]"`) se ven como enlaces y se abren.
struct PropertiesForm: View {
    let ruta: VaultPath
    let propiedades: [Property]
    let sesion: VaultSession
    /// Por qué no se puede cambiar (carpeta real, solo lectura, conflicto). `nil` = se puede.
    var motivoSoloLectura: String?
    /// Sin título ni ayuda (en el inspector).
    var compacta = false

    @State private var editando: String?
    @State private var borrador = ""
    @State private var anadiendo = false
    @State private var nuevaClave = ""
    @State private var nuevoValor = ""
    @FocusState private var foco: Campo?

    enum Campo: Hashable { case valor(String), nuevaClave, nuevoValor, elemento(String) }

    /// Claves técnicas de la app: no se enseñan (el tipo ya se ve arriba).
    static let ocultas: Set<String> = ["tls_type", "tls_schema", "id"]

    var visibles: [Property] { propiedades.filter { !Self.ocultas.contains($0.key) } }
    var puedeCambiar: Bool { motivoSoloLectura == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !compacta {
                HStack(spacing: TLSEspacio.e8) {
                    Text("Propiedades")
                        .tlsTexto(TLSTipo.tituloModulo)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if puedeCambiar, !anadiendo {
                        Button {
                            anadiendo = true
                            foco = .nuevaClave
                        } label: {
                            Label("Añadir propiedad", systemImage: "plus")
                        }
                        .tlsBoton(.discreto)
                    }
                }
                Text(motivoSoloLectura.map { "Solo lectura: \($0)." } ?? "Pulsa un valor para cambiarlo. Cada cambio escribe solo su línea.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.bottom, TLSEspacio.e8)
            }
            if visibles.isEmpty, !anadiendo {
                Text("Esta nota no tiene propiedades.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(minHeight: 32, alignment: .leading)
            }
            ForEach(Array(visibles.enumerated()), id: \.element.key) { i, p in
                if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                fila(p)
            }
            if anadiendo { filaNueva }
        }
        .padding(compacta ? 0 : TLSEspacio.e16)
        .background {
            if !compacta {
                RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(Self.relleno.color)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Propiedades")
    }

    // MARK: Filas

    /// El nombre visible de una clave, con sus tildes («codigo» → «Código»): el mismo que en el panel de la
    /// ficha. Las que no conoce, con la primera en mayúscula y sin guiones.
    static func etiqueta(_ clave: String) -> String {
        InspectorFicha.etiqueta(clave.replacingOccurrences(of: "-", with: "_"))
    }

    /// Relleno del bloque: hundido sobre la superficie del editor (`fondo` en claro, `bandeja` en oscuro, para
    /// que no se vea como un agujero negro sobre el azul de la superficie).
    static let relleno = TLSColor("bloquePropiedadesNota",
                                  claro: TLSPaleta.fondo.claro, oscuro: TLSPaleta.bandeja.oscuro,
                                  claroContraste: TLSPaleta.fondo.claroContraste,
                                  oscuroContraste: TLSPaleta.bandeja.oscuroContraste)

    @ViewBuilder
    private func fila(_ p: Property) -> some View {
        let etiqueta = Self.etiqueta(p.key)
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e12) {
            Text(etiqueta)
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: compacta ? 96 : 128, alignment: .leading)
                .lineLimit(2)
            valor(p, etiqueta: etiqueta)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .frame(minHeight: TLSAltura.filaTabla + 4)
        .contextMenu {
            if puedeCambiar {
                Button("Quitar «\(etiqueta)»") { Task { await quitar(p.key, etiqueta) } }
            }
            Button("Copiar el valor") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p.value.displayText, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(etiqueta)
    }

    @ViewBuilder
    private func valor(_ p: Property, etiqueta: String) -> some View {
        switch p.value {
        case .bool(let b):
            Toggle(isOn: Binding(get: { b }, set: { v in Task { await escribir(p.key, .bool(v), etiqueta) } })) {
                Text(b ? "Sí" : "No").tlsTexto(TLSTipo.interfaz)
            }
            .toggleStyle(.checkbox)
            .disabled(!puedeCambiar)
            .accessibilityLabel(etiqueta)
        case .list(let items):
            lista(p.key, items: items, etiqueta: etiqueta)
        case .raw(let yaml):
            Text(yaml)
                .tlsTexto(TLSTipo.codigo)
                .foregroundStyle(TLSPaleta.texto.color)
                .textSelection(.enabled)
                .help("Este valor tiene varias partes: se cambia desde otro editor de texto.")
        case .text, .number, .empty:
            if editando == p.key {
                campo(p, etiqueta: etiqueta)
            } else {
                textoPulsable(p, etiqueta: etiqueta)
            }
        }
    }

    /// El valor como botón: un clic lo edita; si es un enlace, se ve como enlace y abre con un clic.
    @ViewBuilder
    private func textoPulsable(_ p: Property, etiqueta: String) -> some View {
        let texto = p.value.displayText
        if let enlace = Self.enlace(en: texto) {
            HStack(spacing: TLSEspacio.e4) {
                Button { abrir(enlace.destino) } label: {
                    Text(enlace.visible)
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.enlace.color)
                        .underline()
                }
                .buttonStyle(.plain)
                .frame(minHeight: TLSAltura.objetivoMinimo)
                .accessibilityLabel("\(etiqueta): \(enlace.visible). Abrir")
                if puedeCambiar {
                    Button { empezar(p) } label: { Image(systemName: "pencil") }
                        .tlsBoton(.discreto, alto: TLSAltura.objetivoMinimo)
                        .help("Cambiar")
                        .accessibilityLabel("Cambiar \(etiqueta)")
                }
            }
        } else {
            Button { if puedeCambiar { empezar(p) } } label: {
                Text(texto.isEmpty ? (puedeCambiar ? "Vacía · pulsa para escribir" : "Vacía") : texto)
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(texto.isEmpty ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tlsFocoPropio(radio: TLSRadio.campo)
            .disabled(!puedeCambiar && texto.isEmpty)
            .accessibilityLabel("\(etiqueta): \(texto.isEmpty ? "vacía" : texto)")
            .accessibilityHint(puedeCambiar ? "Pulsa para cambiarla" : "")
        }
    }

    private func campo(_ p: Property, etiqueta: String) -> some View {
        HStack(spacing: TLSEspacio.e8) {
            TextField(etiqueta, text: $borrador)
                .textFieldStyle(.roundedBorder)
                .tlsTexto(TLSTipo.interfaz)
                .focused($foco, equals: .valor(p.key))
                .onSubmit { Task { await guardar(p, etiqueta: etiqueta) } }
                .onExitCommand { editando = nil }
                .accessibilityLabel(etiqueta)
            Button("Guardar") { Task { await guardar(p, etiqueta: etiqueta) } }
                .tlsBoton(.secundario)
            Button("Cancelar") { editando = nil }
                .tlsBoton(.discreto)
        }
    }

    private func lista(_ clave: String, items: [String], etiqueta: String) -> some View {
        HStack(spacing: TLSEspacio.e4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let visible = Self.enlace(en: item)?.visible ?? item
                Chip(visible, quitar: puedeCambiar ? {
                    var nuevos = items
                    nuevos.remove(at: i)
                    Task { await escribir(clave, .list(nuevos), etiqueta) }
                } : nil)
            }
            if puedeCambiar {
                if editando == clave {
                    TextField("Añadir", text: $borrador)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                        .focused($foco, equals: .elemento(clave))
                        .onSubmit {
                            let v = borrador.trimmingCharacters(in: .whitespaces)
                            editando = nil
                            guard !v.isEmpty else { return }
                            Task { await escribir(clave, .list(items + [v]), etiqueta) }
                        }
                        .onExitCommand { editando = nil }
                } else {
                    Button {
                        borrador = ""
                        editando = clave
                        foco = .elemento(clave)
                    } label: { Image(systemName: "plus") }
                    .tlsBoton(.discreto, alto: TLSAltura.objetivoMinimo)
                    .accessibilityLabel("Añadir a \(etiqueta)")
                }
            }
        }
    }

    private var filaNueva: some View {
        HStack(spacing: TLSEspacio.e8) {
            TextField("Nombre", text: $nuevaClave)
                .textFieldStyle(.roundedBorder)
                .frame(width: compacta ? 96 : 128)
                .focused($foco, equals: .nuevaClave)
                .accessibilityLabel("Nombre de la propiedad nueva")
            TextField("Valor", text: $nuevoValor)
                .textFieldStyle(.roundedBorder)
                .focused($foco, equals: .nuevoValor)
                .onSubmit { Task { await anadir() } }
                .accessibilityLabel("Valor de la propiedad nueva")
            Button("Añadir") { Task { await anadir() } }
                .tlsBoton(.secundario)
                .disabled(Self.claveValida(nuevaClave) == nil)
            Button("Cancelar") { anadiendo = false; nuevaClave = ""; nuevoValor = "" }
                .tlsBoton(.discreto)
        }
        .padding(.top, TLSEspacio.e8)
        .onExitCommand { anadiendo = false }
    }

    // MARK: Acciones

    private func empezar(_ p: Property) {
        borrador = p.value.displayText
        editando = p.key
        foco = .valor(p.key)
    }

    private func guardar(_ p: Property, etiqueta: String) async {
        let texto = borrador
        editando = nil
        guard texto != p.value.displayText else { return }
        await escribir(p.key, Self.valor(texto, como: p.value), etiqueta)
    }

    /// El texto escrito con el tipo que ya tenía la propiedad (número si sigue siendo número).
    static func valor(_ texto: String, como anterior: PropertyValue) -> PropertyValue {
        let t = texto.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .empty }
        if case .number = anterior, Double(t.replacingOccurrences(of: ",", with: ".")) != nil, !t.contains(",") { return .number(t) }
        return .text(texto)
    }

    /// Nombre de propiedad aceptable (sin `:` ni saltos, sin espacios a los lados).
    static func claveValida(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains(":"), !t.contains("\n"), !t.hasPrefix("-"), !t.hasPrefix("#") else { return nil }
        return t
    }

    private func anadir() async {
        guard let clave = Self.claveValida(nuevaClave) else { return }
        let etiqueta = Self.etiqueta(clave)
        let v = nuevoValor
        anadiendo = false
        nuevaClave = ""
        nuevoValor = ""
        await escribir(clave, Self.valor(v, como: .text("")), etiqueta)
    }

    private func escribir(_ clave: String, _ valor: PropertyValue, _ etiqueta: String) async {
        guard puedeCambiar else { return }
        _ = try? await sesion.escribir(.cambiarPropiedades(ruta, poner: [Property(key: clave, value: valor)], quitar: []),
                                       aviso: "«\(etiqueta)» cambiada")
    }

    private func quitar(_ clave: String, _ etiqueta: String) async {
        guard puedeCambiar else { return }
        _ = try? await sesion.escribir(.cambiarPropiedades(ruta, poner: [], quitar: [clave]), aviso: "Quitada «\(etiqueta)»")
    }

    private func abrir(_ destino: String) {
        guard let r = sesion.resolverEnlace("[[\(destino)]]", desde: ruta) else {
            sesion.linkProblem = "No encuentro «\(destino)» en la carpeta de tu empresa."
            return
        }
        // Va dentro del editor (otra jerarquía de vistas): navega en la pestaña con el foco.
        sesion.navegar(a: sesion.destino(para: r), modo: .automatico)
    }

    /// `[[destino|visible]]` en un valor de propiedad.
    static func enlace(en texto: String) -> (destino: String, visible: String)? {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[["), t.hasSuffix("]]"), t.count > 4 else { return nil }
        let interior = String(t.dropFirst(2).dropLast(2))
        guard !interior.contains("[["), !interior.contains("]]") else { return nil }
        let partes = interior.split(separator: "|", maxSplits: 1).map(String.init)
        let destino = partes[0].split(separator: "#", maxSplits: 1).first.map(String.init) ?? partes[0]
        let visible = partes.count > 1 ? partes[1] : (destino.split(separator: "/").last.map(String.init) ?? destino)
        return (destino, visible)
    }
}
