import SwiftUI
import TLSCore
import TLSDesign

/// Pestaña Control de un área (PLAN §6.5): sus números de `Metas.md` con código · valor · meta · alerta · ritmo ·
/// fuente. Meta y Alerta se editan aquí (solo esas dos celdas de su fila, por `CommandBus`, con Deshacer). La
/// primera vez el valor queda oculto hasta guardar la meta. Sin dato, «Sin dato»; sin meta, «Sin meta».
struct ControlArea: View {
    let datos: DatosArea
    @Bindable var modelo: ModeloArea
    @Environment(\.navegar) private var navegar

    var body: some View {
        if datos.controlSustituido {
            VacioExplicado(icono: "chart.line.uptrend.xyaxis", titulo: "Medir esto llega en la etapa 3",
                           porQue: "En las etapas 1 y 2 lo importante es que el área funcione. En la etapa 3 fijarás aquí sus metas y verás su ritmo.")
                .accessibilityIdentifier("area.control.etapa")
        } else if datos.control.isEmpty {
            VacioExplicado(icono: "chart.line.uptrend.xyaxis", titulo: "Esta área aún no tiene números",
                           porQue: "Los números clave de cada área están en la nota Metas de Dirección. Cuando tenga alguno con el código de esta área, aparecerá aquí.",
                           accion: datos.metas == nil ? nil : "Abrir Metas",
                           alPulsar: datos.metas.map { r in { navegar(.nota(r), modo: .entrar) } })
                .accessibilityIdentifier("area.control.vacio")
        } else {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                Text("Fija la meta y la alerta antes de ver el dato. Lo que escribas aquí se guarda en tus metas, en Dirección, y no cambia nada más.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let motivo = modelo.motivoSoloLectura {
                    Label("No se pueden cambiar metas: \(motivo).", systemImage: "lock")
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                VStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        tabla
                        lista
                    }
                }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                .tlsSombra(.uno, radio: TLSRadio.mosaico)
                if let error = modelo.errorGuardado {
                    AvisoEnLinea(error, estado: .mal)
                }
            }
            .accessibilityIdentifier("area.control")
        }
    }

    // MARK: Tabla ancha

    private static let anchos: (codigo: CGFloat, valor: CGFloat, meta: CGFloat, alerta: CGFloat, ritmo: CGFloat, fuente: CGFloat, accion: CGFloat)
        = (112, 132, 104, 104, 112, 150, 112)

    private var tabla: some View {
        let a = Self.anchos
        return VStack(spacing: 0) {
            HStack(spacing: TLSEspacio.e12) {
                cabecera("Código", a.codigo)
                Text("Número").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
                cabecera("Valor", a.valor)
                cabecera("Meta", a.meta)
                cabecera("Alerta", a.alerta)
                cabecera("Ritmo", a.ritmo)
                cabecera("Fuente", a.fuente)
                Color.clear.frame(width: a.accion, height: 1)
            }
            .padding(.horizontal, TLSEspacio.e16)
            .frame(minHeight: 32)
            .accessibilityHidden(true)
            ForEach(datos.control) { fila in
                Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
                filaAncha(fila)
                if modelo.editando == fila.codigo {
                    EditorMeta(fila: fila, modelo: modelo)
                        .padding(.horizontal, TLSEspacio.e16)
                        .padding(.bottom, TLSEspacio.e12)
                }
            }
        }
        .frame(minWidth: 1_020)
    }

    private func cabecera(_ t: String, _ ancho: CGFloat) -> some View {
        Text(t).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
            .frame(width: ancho, alignment: .leading)
    }

    private func filaAncha(_ fila: FilaControl) -> some View {
        let a = Self.anchos
        return HStack(alignment: .center, spacing: TLSEspacio.e12) {
            HStack(spacing: 4) {
                Text(fila.codigo).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                if fila.codigo == datos.numeroClave {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .help("Número clave del área")
                }
            }
            .frame(width: a.codigo, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(fila.indicador).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                // Una frase llana; la fórmula, plegada en «Cómo se calcula» (revisión final de F2).
                if let llano = fila.enPalabras {
                    Text(llano).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                if let como = fila.comoSeMide { ComoSeCalcula(texto: como) }
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
            valor(fila).frame(width: a.valor, alignment: .leading)
            Text(fila.textoMeta).tlsTexto(fila.tieneMeta ? TLSTipo.cifraFila : TLSTipo.secundario)
                .foregroundStyle(fila.tieneMeta ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
                .frame(width: a.meta, alignment: .leading)
            Text(fila.textoAlerta).tlsTexto(fila.alerta == nil ? TLSTipo.secundario : TLSTipo.cifraFila)
                .foregroundStyle(fila.alerta == nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                .frame(width: a.alerta, alignment: .leading)
            RhythmBadge(fila.ritmo).frame(width: a.ritmo, alignment: .leading)
            Text(fila.lectura.fuente ?? "Sin dato").tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                .frame(width: a.fuente, alignment: .leading)
            accion(fila).frame(width: a.accion, alignment: .trailing)
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, TLSEspacio.e8)
        .frame(minHeight: TLSAltura.filaLista + 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(fila.etiquetaAccesible)
        .accessibilityIdentifier("area.control.\(fila.codigo)")
    }

    // MARK: Lista estrecha

    private var lista: some View {
        VStack(spacing: 0) {
            ForEach(Array(datos.control.enumerated()), id: \.element.id) { i, fila in
                if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(fila.codigo).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text(fila.indicador).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Spacer(minLength: 8)
                        RhythmBadge(fila.ritmo)
                    }
                    HStack(spacing: TLSEspacio.e16) {
                        valor(fila)
                        Text("Meta: \(fila.textoMeta)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text("Alerta: \(fila.textoAlerta)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Spacer(minLength: 8)
                        accion(fila)
                    }
                    if let llano = fila.enPalabras {
                        Text(llano).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let f = fila.lectura.fuente {
                        Text(f).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    if let como = fila.comoSeMide { ComoSeCalcula(texto: como) }
                    if modelo.editando == fila.codigo { EditorMeta(fila: fila, modelo: modelo) }
                }
                .padding(.horizontal, TLSEspacio.e16)
                .padding(.vertical, TLSEspacio.e12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(fila.etiquetaAccesible)
            }
        }
    }

    // MARK: Piezas

    @ViewBuilder
    private func valor(_ fila: FilaControl) -> some View {
        if fila.valorVisible {
            Text(fila.textoValor)
                .tlsTexto(fila.lectura.textoValor == nil ? TLSTipo.secundario : TLSTipo.cifraFila)
                .foregroundStyle(fila.lectura.textoValor == nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                .lineLimit(1)
        } else {
            Label("Oculto hasta fijar la meta", systemImage: "eye.slash")
                .labelStyle(.titleAndIcon)
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .lineLimit(2)
        }
    }

    private func accion(_ fila: FilaControl) -> some View {
        let abierto = modelo.editando == fila.codigo
        return Button(fila.metaDecidida ? "Cambiar" : "Fijar meta") {
            modelo.editando = abierto ? nil : fila.codigo
        }
        .tlsBoton(fila.metaDecidida ? .secundario : .principal, alto: TLSAltura.objetivoMinimo + 4)
        .disabled(modelo.motivoSoloLectura != nil || datos.metas == nil)
        .help(modelo.motivoSoloLectura ?? (fila.metaDecidida ? "Cambiar la meta y la alerta" : "Fijar la meta y la alerta antes de ver el dato"))
        .accessibilityLabel(fila.metaDecidida ? "Cambiar la meta de \(fila.codigo)" : "Fijar la meta de \(fila.codigo)")
        .accessibilityIdentifier("area.control.\(fila.codigo).editar")
    }
}

/// Meta y Alerta de un número, en su fila. «Sin meta» escribe esa palabra (y deja la alerta vacía): desde ese
/// momento se ve el dato, sin ritmo.
struct EditorMeta: View {
    let fila: FilaControl
    let modelo: ModeloArea
    @State private var meta: String
    @State private var alerta: String
    @State private var guardando = false
    @Environment(\.undoManager) private var undoManager
    @FocusState private var enfocado: Bool

    init(fila: FilaControl, modelo: ModeloArea) {
        self.fila = fila
        self.modelo = modelo
        _meta = State(initialValue: fila.tieneMeta ? (fila.meta ?? "") : "")
        _alerta = State(initialValue: fila.alerta ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(alignment: .bottom, spacing: TLSEspacio.e12) {
                campo("Meta", texto: $meta, ejemplo: "p. ej. 3 meses")
                    .focused($enfocado)
                campo("Alerta", texto: $alerta, ejemplo: "p. ej. 2 meses")
                Button("Guardar") { guardar(meta: meta, alerta: alerta) }
                    .tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
                    .keyboardShortcut(.defaultAction)
                    .disabled(guardando || meta.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Sin meta") { guardar(meta: "", alerta: "") }
                    .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
                    .disabled(guardando)
                    .help("Deja este número sin meta: verás el dato, sin ritmo")
                Button("Cancelar") { modelo.editando = nil }
                    .tlsBoton(.enlace)
                    .keyboardShortcut(.cancelAction)
            }
            Text(pista)
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e12)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .onAppear { enfocado = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meta y alerta de \(fila.codigo)")
    }

    private var pista: String {
        var t = "Escribe la cifra con su unidad, como en Metas («3 meses», «1.000 €», «80 %»)."
        if let como = fila.comoSeMide, let sentido = como.components(separatedBy: " · ").last {
            t += " Para este número, \(sentido)."
        }
        return t
    }

    private func campo(_ titulo: String, texto: Binding<String>, ejemplo: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
            TextField(titulo, text: texto, prompt: Text(ejemplo))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .accessibilityLabel("\(titulo) de \(fila.codigo)")
        }
    }

    private func guardar(meta: String, alerta: String) {
        guardando = true
        Task {
            await modelo.guardarMeta(fila, meta: meta, alerta: alerta, deshacer: undoManager)
            guardando = false
        }
    }
}

/// «Cómo se calcula»: la fórmula de «Cómo se mide» de Metas, plegada (quien no sabe de cuentas no la necesita para
/// entender el número; quien quiere comprobarlo, la abre).
struct ComoSeCalcula: View {
    let texto: String
    @State private var abierto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                abierto.toggle()
            } label: {
                Label("Cómo se calcula", systemImage: abierto ? "chevron.down" : "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cómo se calcula")
            .accessibilityValue(abierto ? "Abierto" : "Cerrado")
            if abierto {
                Text(texto).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}
