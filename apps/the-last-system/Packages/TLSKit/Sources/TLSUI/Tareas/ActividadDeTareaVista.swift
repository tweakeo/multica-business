import SwiftUI
import TLSCore
import TLSDesign

/// La Actividad de la tarea como línea de tiempo (DISENO §3.4): cambios de estado en una línea compacta, comentarios
/// con autor y hora, trabajos de asistente como tarjeta con resumen, uso y «Detalle técnico» plegado, aprobaciones
/// con enlace a Decisiones; y al pie la caja de comentario (con @ se menciona a un asistente: se guarda en su
/// evento y, cuando estén encendidos, lo retomará). Solo se añade: nada de lo escrito se cambia.
struct ActividadDeTareaVista: View {
    let modelo: ModeloTarea
    let tarea: Tarea
    @State private var filtro: FiltroActividad = .todo

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        let todas = modelo.entradas
        let lista = todas.filter(admite)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(alignment: .center, spacing: TLSEspacio.e8) {
                Text("Actividad").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                Text("\(todas.count)").tlsTexto(TLSTipo.secundario).monospacedDigit().foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer(minLength: 0)
                SelectorCapsula(etiqueta: "Ver", seleccion: $filtro, opciones: FiltroActividad.allCases.map { ($0, $0.rawValue, nil) })
            }
            if lista.isEmpty {
                Text(todas.isEmpty ? "Aún no hay nada apuntado. Lo que cambie y lo que comentes quedará aquí." : "Nada de este tipo todavía.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.vertical, TLSEspacio.e8)
            }
            ForEach(lista) { e in
                Divider().overlay(TLSPaleta.separador.color)
                FilaActividadTarea(entrada: e, hoy: modelo.hoy, ruta: tarea.ruta)
            }
            Divider().overlay(TLSPaleta.separador.color)
            CajaComentarioTarea(modelo: modelo)
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actividad de la tarea")
    }

    private func admite(_ e: EntradaDeTarea) -> Bool {
        switch filtro {
        case .todo: true
        case .comentarios: e.clase == .comentario
        case .cambios: e.clase == .cambio || e.clase == .sistema
        case .asistentes: e.clase == .asistente
        }
    }
}

/// Una entrada de la línea de tiempo.
struct FilaActividadTarea: View {
    let entrada: EntradaDeTarea
    let hoy: LocalDate
    let ruta: VaultPath
    @State private var tecnico = false
    @Environment(\.navegar) private var navegar

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                switch entrada.clase {
                case .cambio, .sistema:
                    (Text(entrada.autor).fontWeight(.semibold).foregroundStyle(TLSPaleta.texto.color)
                        + Text(" · " + linea + (cuando.map { " · " + $0 } ?? "")).foregroundStyle(TLSPaleta.textoSecundario.color))
                        .tlsTexto(TLSTipo.secundario)
                        .fixedSize(horizontal: false, vertical: true)
                case .comentario:
                    cabecera
                    texto
                    menciones
                case .asistente:
                    tarjetaAsistente
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var cuando: String? {
        guard let f = entrada.fecha else { return entrada.sinEncabezado ? "sin fecha" : nil }
        let dia = f == hoy ? "hoy" : (f == hoy.adding(days: -1) ? "ayer" : FormatoFicha.fechaConDia(f, hoy: hoy))
        return dia + (entrada.hora.map { " " + $0 } ?? "")
    }

    /// Lo que dice un cambio en una línea: su texto o, si no tiene, el evento traducido.
    private var linea: String {
        let t = entrada.texto.replacingOccurrences(of: "\n", with: " ")
        if t.isEmpty { return entrada.resumen ?? "Cambio" }
        if let r = entrada.resumen, !t.hasPrefix(r) { return r + ". " + t }
        return t
    }

    private var avatar: some View {
        Group {
            switch entrada.clase {
            case .comentario:
                if entrada.sinEncabezado {
                    Image(systemName: "square.and.pencil").font(.system(size: 12, weight: .semibold))
                } else {
                    Text(Monograma.iniciales(de: entrada.autor)).font(TLSEstiloTexto(.spaceGrotesk, peso: 700, tamano: 10, interlinea: 12).font())
                }
            case .asistente: Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
            case .sistema: Image(systemName: "gearshape").font(.system(size: 12, weight: .semibold))
            case .cambio: Image(systemName: "arrow.right.circle").font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(entrada.clase == .comentario ? TLSPaleta.texto.color : TLSPaleta.principal.color)
        .frame(width: 26, height: 26)
        .background(Circle().fill(entrada.clase == .comentario ? TLSPaleta.bandeja.color : TLSPaleta.principalSuave.color))
        .accessibilityHidden(true)
    }

    private var cabecera: some View {
        (Text(entrada.autor).fontWeight(.semibold).foregroundStyle(TLSPaleta.texto.color)
            + Text(cuando.map { " · " + $0 } ?? "").foregroundStyle(TLSPaleta.textoSecundario.color))
            .tlsTexto(TLSTipo.secundario)
    }

    private var texto: some View {
        Text(entrada.texto.isEmpty ? "Sin texto" : entrada.texto)
            .tlsTexto(TLSTipo.lectura)
            .foregroundStyle(TLSPaleta.texto.color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder private var menciones: some View {
        if !entrada.menciones.isEmpty {
            Label("Para " + entrada.menciones.map(Responsables.nombre(de:)).joined(separator: " y ")
                  + ": queda apuntado y lo retomará cuando los asistentes estén encendidos.", systemImage: "at")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        if entrada.sinEncabezado {
            Text("Escrito fuera de la app debajo de la última entrada. La próxima vez que la app escriba aquí le pondrá encima su encabezado, sin tocar el texto.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tarjetaAsistente: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            (Text(entrada.autor).fontWeight(.semibold).foregroundStyle(TLSPaleta.texto.color)
                + Text(" · " + (entrada.resumen.map { _ in "trabajo" } ?? "nota") + (cuando.map { " · " + $0 } ?? ""))
                    .foregroundStyle(TLSPaleta.textoSecundario.color))
                .tlsTexto(TLSTipo.secundario)
            if let r = entrada.resumen {
                Text(r).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
            }
            if !entrada.texto.isEmpty {
                Text(entrada.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let u = entrada.uso {
                Text(u).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            HStack(spacing: TLSEspacio.e8) {
                if !entrada.detalle.isEmpty {
                    Button {
                        tecnico.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tecnico ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                            Text("Detalle técnico")
                        }
                    }
                    .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
                    .accessibilityLabel("Detalle técnico, \(tecnico ? "abierto" : "plegado")")
                }
                if entrada.pideAprobacion {
                    Button("Ver en Decisiones") { navegar(.decision(de: ruta), modo: .entrar) }
                        .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
                }
            }
            if tecnico {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entrada.detalle, id: \.self) { p in
                        Text("\(p.etiqueta): \(p.valor)").tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.bandeja.color))
    }
}

/// La caja de comentario: se añade a la Actividad con fecha, hora y quién. Con @ se elige un asistente (se escribe
/// «@Comercial» y se guarda `agente:comercial` en el evento del comentario). ⌘↩ comenta.
struct CajaComentarioTarea: View {
    let modelo: ModeloTarea
    @State private var texto = ""
    @State private var enviando = false
    @FocusState private var enfocada: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: TLSEspacio.e8) {
                TextField("Comentar", text: $texto, prompt: Text("Escribe un comentario; con @ pides algo a un asistente"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .focused($enfocada)
                    .accessibilityLabel("Comentario para la tarea")
                Button("Comentar") { enviar() }
                    .tlsBoton(.principal, alto: 36)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(enviando || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !modelo.puedeEscribir)
            }
            if let q = consulta {
                let candidatos = modelo.asistentes.filter { q.isEmpty || TextFolding.fold($0.nombre).contains(TextFolding.fold(q)) }
                if candidatos.isEmpty {
                    Text("No hay ningún asistente que se llame así. Los asistentes salen de los roles de Equipo.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else {
                    FlujoChips(espacio: 6) {
                        ForEach(candidatos, id: \.id) { a in
                            Button(a.nombre) { mencionar(a) }.tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
                        }
                    }
                }
            }
            if let m = modelo.motivoSoloLectura {
                Text("No se puede comentar: \(m).").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                Text("⌘↩ comenta. Con @ pides algo a un asistente y retoma la tarea; ningún asistente la marca como hecha ni cancelada.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Lo escrito tras la última @ (si no tiene espacio), para proponer asistentes.
    private var consulta: String? {
        guard let r = texto.range(of: "@", options: .backwards) else { return nil }
        let resto = texto[r.upperBound...]
        return resto.contains(" ") || resto.contains("\n") ? nil : String(resto)
    }

    private func mencionar(_ a: (id: String, nombre: String)) {
        guard let r = texto.range(of: "@", options: .backwards) else { return }
        let alias = a.nombre.replacingOccurrences(of: " (asistente)", with: "").replacingOccurrences(of: " ", with: "")
        texto = String(texto[..<r.lowerBound]) + "@" + alias + " "
        enfocada = true
    }

    private func enviar() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !enviando else { return }
        enviando = true
        Task {
            if await modelo.comentar(t) { texto = "" }
            enviando = false
        }
    }
}
