import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol mika. El panel flotante de ⌘J (Mosaico v2: `superficieElevada`, radio 16, sombra 2; icono `sparkle` para
// Mika). Arriba, quién es, dónde estás («Estás en Ventas › NEXO») y cómo contesta (con Claude Code, simulado o sin
// él). En medio, la conversación: tus mensajes a la derecha; los de Mika a la izquierda, con sus filas, la propuesta
// con su botón y lo que hizo como tarjetas enlazadas. Abajo, las acciones rápidas del área y el campo para escribir.

/// El panel de Mika (⌘J).
struct PanelMika: View {
    let sesion: VaultSession
    @Bindable var conversacion: ConversacionMika
    var cerrar: () -> Void = {}
    @FocusState private var escribiendo: Bool
    @Environment(\.accessibilityReduceMotion) private var reducir
    @Environment(\.navegar) private var navegar

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.ventanaFlotante, style: .continuous)
        VStack(spacing: 0) {
            cabecera
            Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
            mensajes
            Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
            pie
        }
        .background(forma.fill(TLSPaleta.superficieElevada.color))
        .clipShape(forma)
        .tlsSombra(.dos, forma: forma)
        .onAppear {
            conversacion.ritmo = reducir ? nil : .milliseconds(16)
            escribiendo = true
        }
        .onExitCommand { cerrar() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mika, tu asistente de Dirección")
        .accessibilityIdentifier("mika.panel")
    }

    // MARK: Cabecera

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TLSPaleta.sobrePrincipal.color)
                    .frame(width: 30, height: 30)
                    // F4 · corrector (P3): azul noche; el violeta es del destacado de la pantalla.
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TLSPaleta.principal.color))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mika").tlsTexto(TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 17, interlinea: 22))
                        .foregroundStyle(TLSPaleta.texto.color)
                    Text("Tu asistente de Dirección").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Spacer(minLength: 4)
                Menu {
                    Button("Empezar otra conversación") { Task { await conversacion.nuevaConversacion() } }
                        .disabled(conversacion.mensajes.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityLabel("Más opciones de Mika")
                Button(action: cerrar) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .help("Cerrar (⌘J o Esc)")
                .accessibilityLabel("Cerrar Mika")
            }
            HStack(spacing: 6) {
                Image(systemName: "location").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                Text(conversacion.contexto.frase).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityIdentifier("mika.contexto")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
            modo
        }
        .padding(TLSEspacio.e16)
    }

    private var modo: some View {
        let m = conversacion.modo
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: m == .claude ? TLSEstado.bien.simbolo : (m == .simulado ? "play.circle" : TLSEstado.sinDato.simbolo))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(m == .claude ? TLSPaleta.bien.color : TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            (Text(m.titulo).bold() + Text(" · " + m.explicacion))
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mika.modo")
    }

    // MARK: Mensajes

    private var mensajes: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                    if conversacion.mensajes.isEmpty { saludo }
                    ForEach(conversacion.mensajes) { m in
                        BurbujaMika(mensaje: m, sesion: sesion, conversacion: conversacion).id(m.id)
                    }
                    if conversacion.pensando {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(fraseEnVivo).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                        .padding(.vertical, 4)
                        .id("pensando")
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(TLSEspacio.e16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: conversacion.mensajes.last?.texto) { _, _ in
                guard let id = conversacion.mensajes.last?.id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
            .onChange(of: conversacion.pensando) { _, p in if p { proxy.scrollTo("pensando", anchor: .bottom) } }
            .onAppear { if let id = conversacion.mensajes.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
        }
        .frame(maxHeight: .infinity)
    }

    /// La frase en vivo del trabajo de Mika si el motor la tiene («Leyendo…»); si no, la del chat.
    private var fraseEnVivo: String {
        if let t = AsistentesDeLaEmpresa.de(sesion).enVivo?.trabajo(deAgente: "mika"), t.fase == .trabajando {
            return "Mika · " + t.frase
        }
        return conversacion.frase
    }

    private var saludo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿En qué te ayudo?").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
            Text("Pregúntame por tu día, el dinero o las ventas, o pídeme algo de lo que estás viendo. Lo que prepare te espera en Decisiones: nada sale sin tu OK.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            FlujoChips(espacio: 6) {
                ForEach([Intencion.hoy, .dinero, .pipeline, .atrasado], id: \.self) { i in
                    Button { Task { await conversacion.enviar(i.dice, mostrar: i.dice) } } label: { Chip(i.dice, icono: "text.bubble") }
                        .buttonStyle(.plain)
                        .disabled(conversacion.pensando)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mika.saludo")
    }

    // MARK: Pie

    private var pie: some View {
        VStack(alignment: .leading, spacing: 10) {
            let acciones = conversacion.accionesRapidas
            if !acciones.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo("Pedir")
                    FlujoChips(espacio: 6) {
                        ForEach(acciones) { a in
                            Button { Task { await conversacion.pedir(a) } } label: {
                                Chip(a.titulo, icono: a.asistente == "mika" ? "sparkle" : "arrow.turn.down.right")
                            }
                            .buttonStyle(.plain)
                            .disabled(conversacion.pensando)
                            .help(a.asistente == "mika" ? a.peticion : "Se lo pide a \(a.nombreAsistente): \(a.peticion)")
                            .accessibilityLabel(a.asistente == "mika" ? a.titulo : "\(a.titulo), lo hace \(a.nombreAsistente)")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mika.acciones")
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Escribe a Mika…", text: $conversacion.borrador, axis: .vertical)
                    .textFieldStyle(.plain)
                    .tlsTexto(TLSTipo.interfaz)
                    .lineLimit(1...5)
                    .focused($escribiendo)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous).fill(TLSPaleta.bandeja.color))
                    // F4 · corrector (P3): los campos llevan su borde (Mosaico: `bordeControl`).
                    .overlay(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous)
                        .strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1))
                    .onSubmit { Task { await conversacion.enviar() } }
                    .accessibilityLabel("Mensaje para Mika")
                    .accessibilityIdentifier("mika.campo")
                Button { Task { await conversacion.enviar() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TLSPaleta.sobrePrincipal.color)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(puedeEnviar ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color))
                }
                .buttonStyle(.plain)
                .disabled(!puedeEnviar)
                .help("Enviar (↩)")
                .accessibilityLabel("Enviar a Mika")
                .accessibilityIdentifier("mika.enviar")
            }
        }
        .padding(TLSEspacio.e16)
    }

    private var puedeEnviar: Bool {
        !conversacion.pensando && !conversacion.borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Un mensaje de la conversación.
struct BurbujaMika: View {
    let mensaje: ConversacionMika.Mensaje
    let sesion: VaultSession
    let conversacion: ConversacionMika
    @State private var aplicando = false
    @Environment(\.navegar) private var navegar

    var body: some View {
        if mensaje.quien == .tu {
            HStack {
                Spacer(minLength: 48)
                Text(mensaje.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.principalSuave.color))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tú: \(mensaje.completo)")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(mensaje.texto.isEmpty ? " " : mensaje.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Mika: \(mensaje.completo)")
                if !mensaje.escribiendo {
                    if !mensaje.filas.isEmpty { filas }
                    if let p = mensaje.propuesta { propuesta(p) }
                    if !mensaje.tarjetas.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(mensaje.tarjetas) { t in TarjetaEnlazadaVista(tarjeta: t, sesion: sesion) }
                        }
                    }
                    pieDeMensaje
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
            .padding(.trailing, 24)
            .accessibilityElement(children: .contain)
        }
    }

    private var filas: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(mensaje.filas.prefix(8).enumerated()), id: \.offset) { _, f in
                let abrir: (() -> Void)? = f.ruta.flatMap { r in sesion.esPrivado(r) ? nil : { navegar(sesion.destino(para: r), modo: .automatico) } }
                // F4 · corrector (revisión de experiencia, P1): una fila que no lleva a ninguna ficha no es un botón
                // desactivado (SwiftUI lo atenuaba por debajo de 4,5:1); se pinta como texto normal.
                if let abrir {
                    Button(action: abrir) { filaDeRespuesta(f) }
                        .buttonStyle(.plain)
                        .help("Abrir la ficha")
                } else {
                    filaDeRespuesta(f)
                        .accessibilityElement(children: .combine)
                }
            }
            if mensaje.filas.count > 8 {
                Text("Y \(mensaje.filas.count - 8) más").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(TLSPaleta.superficie.color))
    }

    private func filaDeRespuesta(_ f: FilaDeRespuesta) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if f.mal {
                Image(systemName: TLSEstado.mal.simbolo).foregroundStyle(TLSPaleta.mal.color)
                    .font(.system(size: 11, weight: .semibold)).accessibilityLabel("En rojo")
            }
            Text(f.texto).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
            Spacer(minLength: 4)
            if let v = f.valor {
                Text(v).tlsTexto(TLSTipo.cifraFila).foregroundStyle(f.mal ? TLSPaleta.mal.color : TLSPaleta.textoSecundario.color)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func propuesta(_ p: PropuestaDeChat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(p.aviso).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if let hecha = mensaje.propuestaHecha {
                AvisoEnLinea(hecha, estado: .bien)
            } else {
                Button(p.etiqueta) {
                    aplicando = true
                    Task {
                        await conversacion.aplicar(mensaje.id)
                        aplicando = false
                    }
                }
                .tlsBoton(.secundario)
                .disabled(aplicando || !sesion.puedeEscribir)
                .help(sesion.puedeEscribir ? "Lo haces tú: se puede deshacer" : "Solo lectura")
            }
        }
    }

    private var pieDeMensaje: some View {
        HStack(spacing: 8) {
            if mensaje.modo == .sinClaude {
                Label("Respuesta de la app, sin Claude Code", systemImage: "info.circle")
                    .labelStyle(.titleAndIcon)
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityIdentifier("mika.sinClaude")
            } else if mensaje.modo == .simulado {
                Label("Simulado", systemImage: "play.circle")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: 4)
            if let d = mensaje.ir {
                Button("Ver en \(sesion.nombre(de: d))") { navegar(d, modo: .automatico) }.tlsBoton(.enlace)
            }
        }
    }
}

/// Una tarjeta de lo que hizo un asistente: qué es, su título y lo que espera de ti, con «Abrir».
struct TarjetaEnlazadaVista: View {
    let tarjeta: TarjetaEnlazada
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tarjeta.clase.icono)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TLSPaleta.principal.color)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TLSPaleta.principalSuave.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Rotulo(tarjeta.etiqueta)
                Text(tarjeta.titulo).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let estado = enVivo {
                    Text(estado).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else if let e = tarjeta.espera {
                    Text(e).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            Spacer(minLength: 4)
            if let r = tarjeta.ruta, !sesion.esPrivado(r) {
                Button("Abrir") { navegar(sesion.destino(para: r), modo: .automatico) }
                    .tlsBoton(.enlace)
                    .accessibilityLabel("Abrir \(tarjeta.titulo)")
            } else if tarjeta.espera != nil {
                Button("Decisiones") { navegar(.decisiones, modo: .raiz) }.tlsBoton(.enlace)
            }
        }
        .padding(10)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay(forma.strokeBorder(TLSPaleta.separador.color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tarjeta.etiqueta): \(tarjeta.titulo)")
    }

    /// Un encargo en marcha: su frase en vivo («En cola», «Leyendo…», «Esperando tu respuesta»).
    private var enVivo: String? {
        guard tarjeta.clase == .trabajo, let id = tarjeta.ejecucion,
              let t = AsistentesDeLaEmpresa.de(sesion).enVivo?.trabajos[id] else { return nil }
        switch t.fase {
        case .enCola: return "En cola"
        case .esperandoRespuesta: return "Esperando tu respuesta"
        default: return t.frase
        }
    }
}
