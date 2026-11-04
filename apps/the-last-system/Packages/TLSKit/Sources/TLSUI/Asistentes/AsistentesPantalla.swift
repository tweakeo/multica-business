import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes (PLAN §6.1, §6.5; DISENO-MOSAICO-V2 §6). La raíz «Asistentes» de la barra lateral: cada asistente
// en una fila con su icono, su área, cómo está (en texto e icono), lo último que hizo, su próxima rutina y el uso del
// mes como parte de su tope; el interruptor general y la pausa por área. El `init` es contrato con el enrutador
// (`Shell/PantallaDestino`, `.asistentes`).

/// Asistentes: quién trabaja, en qué y cuánto usa.
struct AsistentesPantalla: View {
    let sesion: VaultSession
    @State private var modelo: ModeloAsistentes
    @Environment(\.navegar) private var navegar

    init(sesion: VaultSession) {
        self.sesion = sesion
        _modelo = State(initialValue: ModeloAsistentes(sesion: sesion))
    }

    var body: some View {
        ContenedorPantalla(destino: .asistentes) {
            if let l = modelo.lectura {
                contenido(l)
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Leyendo a los asistentes…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task(id: modelo.claveRecarga) { await modelo.cargar() }
        .accessibilityIdentifier("asistentes.pantalla")
    }

    @ViewBuilder
    private func contenido(_ l: LecturaAsistentes) -> some View {
        let vivos = l.asistentes.map { ($0, $0.estado(vivo: modelo.vivo($0.slug))) }
        let trabajando = vivos.filter { $0.1.trabajando }.count
        CabeceraAzulNoche(rotulo: "Tu equipo", titulo: "Asistentes",
                          subtitulo: "Preparan borradores, tareas y avisos. Nada sale de la empresa sin tu OK.",
                          datos: [DatoClave("Activos", "\(l.asistentes.filter(\.activo).count) de \(l.asistentes.count)"),
                                  DatoClave("Trabajando", "\(trabajando)"),
                                  DatoClave("Uso del mes", l.usoTotal.cifra + (l.usoTotal.simulado ? " (Simulado)" : ""))],
                          altoMinimo: TLSAltura.cabeceraBase,
                          identidad: { AvatarCabecera(simbolo: "sparkle") },
                          acciones: { InterruptorGeneralAsistentes(sesion: sesion, estilo: .cabecera) })
        avisos(l)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) { resumen(l, vivos: vivos) }
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) { resumen(l, vivos: vivos) }
        }
        TituloSeccionAsistentes(titulo: "Tus asistentes",
                                explicacion: "Cada uno lleva un área y se rige por su ficha. Pulsa uno para ver qué hace, sus permisos, sus rutinas y lo que ha hecho.")
        TarjetaFilas {
            ForEach(Array(vivos.enumerated()), id: \.element.0.id) { i, par in
                if i > 0 { SeparadorFila() }
                FilaAsistente(asistente: par.0, estado: par.1, hoy: l.hoy, zona: l.zona) {
                    navegar(.asistente(par.0.slug), modo: .entrar)
                }
            }
        }
        .accessibilityIdentifier("asistentes.lista")
        PausaPorArea(sesion: sesion, lectura: l)
        // La Bitácora también está aquí: Equipo › Operación no se ve mientras Equipo está en reposo (como en Ribera).
        TituloSeccionAsistentes(titulo: "Bitácora",
                                explicacion: "Lo que hizo cada uno, día a día. Solo se añade; nadie la edita. También está en Equipo › Operación › Asistentes.")
        BitacoraAsistentesVista(sesion: sesion, lectura: l)
    }

    @ViewBuilder
    private func avisos(_ l: LecturaAsistentes) -> some View {
        if !l.interruptor {
            AvisoEnLinea("Los asistentes están en pausa: no hacen nada hasta que los enciendas. Lo que tengan pendiente espera en la cola.",
                         estado: .atencion)
        }
        if let c = l.cambiosDeFuera {
            HStack(spacing: TLSEspacio.e8) {
                AvisoEnLinea(c + ". Mientras tanto siguen con los permisos de antes.", estado: .atencion)
                Button("Ir a Decisiones") { navegar(.decisiones, modo: .raiz) }.tlsBoton(.secundario)
            }
        }
        if l.demo {
            AvisoEnLinea("Es un ejemplo: lo que hacen aquí los asistentes es simulado y lleva la marca «Simulado». Nada sale de verdad.",
                         estado: .sinDato)
        }
        // F4 · integración: en una copia sin Claude Code (o sin la sesión iniciada) los asistentes no pueden trabajar.
        if let motivo = modelo.conexion?.sinMotor {
            HStack(spacing: TLSEspacio.e8) {
                AvisoEnLinea(motivo, estado: .atencion)
                // F4 · corrector (revisión de experiencia, P2): cómo se instala y qué cuenta hace falta, en el manual.
                BotonSaberMas(seccion: "claude-code", titulo: "Cómo se conecta")
                if let reintentar = modelo.conexion?.reintentar {
                    Button("Buscar otra vez") { Task { await reintentar() } }.tlsBoton(.secundario)
                        .accessibilityIdentifier("asistentes.buscarClaude")
                }
            }
            .accessibilityIdentifier("asistentes.sinMotor")
        }
        if case .soloLectura(let m) = sesion.modoEscritura {
            AvisoEnLinea("Solo lectura (\(m.texto)): ves cómo están, pero no puedes cambiar sus ajustes.", estado: .sinDato)
        }
    }

    /// El destacado (lo que pasa ahora) y el uso del mes.
    @ViewBuilder
    private func resumen(_ l: LecturaAsistentes, vivos: [(AsistenteEnLista, EstadoDeAsistente)]) -> some View {
        // F4 · integración: sin Claude Code en esta copia no hay «próxima rutina» que valga: lo dice el destacado.
        let ahora = modelo.conexion?.sinMotor != nil && !l.demo
            ? DestacadoAhora(cifra: "Ahora no pueden trabajar", contexto: "Falta Claude Code en este Mac: mira el aviso de arriba.",
                             accion: nil, slug: nil)
            : DestacadoAhora.de(vivos, lectura: l)
        Destacado(rotulo: "Ahora", accion: ahora.accion, alPulsar: ahora.accion == nil ? nil : {
            if let slug = ahora.slug { navegar(.asistente(slug), modo: .entrar) } else { navegar(.decisiones, modo: .raiz) }
        }) {
            CifraDestacada(ahora.cifra, contexto: ahora.contexto, estilo: TLSTipo.cifraMedia)
        }
        .frame(minWidth: 260, maxWidth: 420, minHeight: 150)
        .accessibilityIdentifier("asistentes.ahora")
        Mosaico("Uso del mes", icono: "gauge.with.dots.needle.33percent",
                pie: "De los asistentes activos, frente a la suma de sus topes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(l.usoTotal.cifra).tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                    Text("de tu tope").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    if l.usoTotal.simulado { MarcaSimulado() }
                }
                BarraUso(uso: l.usoTotal)
            }
        }
        .frame(minWidth: 240, minHeight: 150)
        let mes = l.bitacora.filter { $0.mes == l.mes }
        Mosaico("Trabajos este mes", icono: "list.bullet.rectangle", pie: "Sale de la bitácora de Equipo") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(mes.count)").tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                let sim = mes.filter(\.simulado).count
                Text(sim == 0 ? "apuntados en la bitácora" : (sim == mes.count ? "todos simulados" : "\(sim) simulados"))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .frame(minWidth: 200, minHeight: 150)
    }
}

/// Lo que dice el destacado de Asistentes: quién trabaja ahora, quién espera tu respuesta o qué toca después.
struct DestacadoAhora: Hashable {
    let cifra: String
    let contexto: String
    let accion: String?
    let slug: String?

    static func de(_ vivos: [(AsistenteEnLista, EstadoDeAsistente)], lectura l: LecturaAsistentes) -> DestacadoAhora {
        if let par = vivos.first(where: { $0.1.trabajando }) {
            let (a, e) = par
            let otros = vivos.filter { $0.1.trabajando }.count - 1
            return DestacadoAhora(cifra: "\(a.nombre) está trabajando", contexto: e.detalle + (otros > 0 ? " · y \(otros) más" : ""),
                                  accion: "Ver qué hace", slug: a.slug)
        }
        if let a = vivos.first(where: { $0.1 == .esperandoRespuesta })?.0 {
            return DestacadoAhora(cifra: "\(a.nombre) espera tu respuesta", contexto: "Te ha hecho una pregunta. Contéstale y sigue.",
                                  accion: "Ir a Decisiones", slug: nil)
        }
        if !l.interruptor {
            return DestacadoAhora(cifra: "En pausa", contexto: "Ningún asistente trabaja hasta que los enciendas.", accion: nil, slug: nil)
        }
        if let a = vivos.map(\.0).filter({ $0.proxima != nil }).min(by: { $0.proxima!.fecha < $1.proxima!.fecha }), let p = a.proxima {
            return DestacadoAhora(cifra: "Ninguno trabaja ahora",
                                  contexto: "Lo próximo: \(a.nombre), «\(p.nombre)», \(FormatoAsistentes.cuando(p.fecha, zona: l.zona, hoy: l.hoy))"
                                    + (p.soloSiHayRojo ? " (solo si hay algo en rojo)" : ""),
                                  accion: nil, slug: nil)
        }
        return DestacadoAhora(cifra: "Ninguno trabaja ahora", contexto: "No hay rutinas pendientes. Pídeles algo desde su ficha.",
                              accion: nil, slug: nil)
    }
}

/// Una fila de Asistentes: icono, nombre y área, cómo está, lo último, lo próximo y el uso del mes.
struct FilaAsistente: View {
    let asistente: AsistenteEnLista
    let estado: EstadoDeAsistente
    let hoy: LocalDate
    let zona: TimeZone
    let alPulsar: () -> Void

    var body: some View {
        let a = asistente
        Button(action: alPulsar) {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                IconoAsistente(a, tamano: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: TLSEspacio.e8) {
                        Text(a.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text(lugar).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                    }
                    Text(lineaUltima).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                        .truncationMode(.tail)
                    Text(lineaProxima).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        if a.ultima?.simulado == true || a.uso.simulado { MarcaSimulado() }
                        PastillaAsistente(estado)
                    }
                    Text(estado.detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(1)
                    Text(a.uso.fraseSinMarca).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(1)
                }
                .frame(maxWidth: 300, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TLSEspacio.e16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloFila(alto: 72))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.nombre), \(lugar). \(estado.palabra): \(estado.detalle). \(lineaUltima). \(lineaProxima). \(a.uso.frase)"
                            + (a.ultima?.simulado == true ? ". Simulado" : ""))
        .accessibilityHint("Abre su ficha")
        .accessibilityIdentifier("asistentes.fila.\(a.slug)")
    }

    private var lugar: String {
        if let area = asistente.area, !asistente.esDelSistema {
            return "\(area.etiquetaNumerada)" + (asistente.coordinador ? " · coordina a los demás" : "")
        }
        return "Buzón y orden de la carpeta"
    }

    private var lineaUltima: String {
        guard let u = asistente.ultima else { return "Aún no ha trabajado" }
        return "Último: " + FormatoAsistentes.momento(u.dia, hora: u.hora, hoy: hoy) + " · " + u.texto
    }

    private var lineaProxima: String {
        if let p = asistente.proxima {
            return "Próxima rutina: «\(p.nombre)», \(FormatoAsistentes.cuando(p.fecha, zona: zona, hoy: hoy))"
                + (p.soloSiHayRojo ? " (solo si hay algo en rojo)" : "")
        }
        if asistente.rutinas.isEmpty { return "Sin rutinas: trabaja cuando se lo pides o le asignas algo" }
        if asistente.estadoGuardado == .enPausa(LecturaAsistentes.faltaClaude) {
            return "Sin próxima rutina hasta que conectes Claude Code"
        }
        return asistente.activo ? "Sin próxima rutina mientras esté en pausa" : "Sin próxima rutina mientras esté apagado"
    }
}

/// Pausa por área (`pausa_areas`): los asistentes no trabajan en un área en pausa, aunque estén encendidos.
struct PausaPorArea: View {
    let sesion: VaultSession
    let lectura: LecturaAsistentes
    @State private var cambiando: AreaCode?

    var body: some View {
        TituloSeccionAsistentes(titulo: "Pausa por área",
                                explicacion: "Para que ningún asistente trabaje en un área sin apagarlos a todos. Lo que tengan allí espera en la cola.")
        TarjetaFilas {
            ForEach(Array(AreaCode.allCases.enumerated()), id: \.element) { i, area in
                if i > 0 { SeparadorFila(sangria: 52) }
                fila(area)
            }
        }
        .accessibilityIdentifier("asistentes.pausaAreas")
    }

    private func fila(_ area: AreaCode) -> some View {
        let enPausa = lectura.pausaAreas.contains(area)
        let quienes = lectura.asistentes.filter { $0.area == area && !$0.esDelSistema }.map(\.nombre)
        let estado = lectura.estadosArea[area] ?? .desconocido
        let motivo: String? = switch sesion.modoEscritura {
        case .escribe: nil
        case .abriendo: "Abriendo la carpeta…"
        case .soloLectura(let m): "Solo lectura: \(m.texto)"
        }
        return HStack(spacing: TLSEspacio.e12) {
            IconoArea(area.tlsArea, tamano: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.etiquetaNumerada).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text(detalle(estado: estado, quienes: quienes, enPausa: enPausa))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
            Spacer(minLength: TLSEspacio.e8)
            Toggle(enPausa ? "En pausa" : "Trabajan", isOn: Binding(get: { enPausa }, set: { v in
                cambiando = area
                Task {
                    do { try await EscrituraAsistentes.pausar(area, v, actuales: lectura.pausaAreas, sesion: sesion) } catch {
                        sesion.aviso = Aviso(error.localizedDescription, estado: .mal)
                    }
                    cambiando = nil
                }
            }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(TLSPaleta.principal.color)
            .disabled(motivo != nil || cambiando != nil)
            .help(motivo ?? (enPausa ? "Quitar la pausa: los asistentes vuelven a trabajar en \(area.nombre)" : "Pausar \(area.nombre) para los asistentes"))
            .accessibilityLabel("\(area.etiquetaNumerada) en pausa para los asistentes")
            .accessibilityValue(enPausa ? "Sí" : "No")
            .accessibilityIdentifier("asistentes.pausa.\(area.rawValue)")
        }
        .padding(.horizontal, TLSEspacio.e16)
        .frame(minHeight: TLSAltura.filaLista)
    }

    private func detalle(estado: AreaStatus, quienes: [String], enPausa: Bool) -> String {
        var partes: [String] = []
        if estado != .desconocido { partes.append("Área \(estado.etiqueta.lowercased())") }
        partes.append(quienes.isEmpty ? "Sin asistente propio" : quienes.joined(separator: ", "))
        if enPausa { partes.append("los asistentes no trabajan aquí") }
        return partes.joined(separator: " · ")
    }
}
