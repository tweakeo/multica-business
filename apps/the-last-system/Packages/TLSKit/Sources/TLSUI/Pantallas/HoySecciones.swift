import SwiftUI
import TLSCore
import TLSDesign

// Las piezas de Hoy (M2-Hoy): cabecera azul noche, el foco violeta, «Pide tu decisión», «En alerta» y la línea de Mika.

/// Cabecera azul noche: la fecha de la carpeta y la hora, el saludo, la frase del día y tres datos (Decisiones, Tu día y,
/// solo si hay algo en rojo, En alerta).
struct CabeceraHoy: View {
    let datos: DatosHoy?
    let sesion: VaultSession

    private func total(_ d: DatosHoy) -> Int { d.pendientes + ConexionesEnDecisiones.de(sesion).pendientes.count }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text(HoyPantalla.fechaLarga(sesion.hoy) + (datos.map { " · \($0.hora)" } ?? ""))
                .tlsTexto(TLSTipo.interfaz.peso(600)).foregroundStyle(TLSPaleta.subtituloCabecera.color)
            Text("\(HoyPantalla.saludo(Date())), \(sesion.persona)")
                .tlsTexto(TLSTipo.tituloPantalla).foregroundStyle(TLSPaleta.sobreColor.color)
                .accessibilityAddTraits(.isHeader)
            // F5 · integración: también cuenta lo que piden las conexiones (como Decisiones y su insignia).
            Text(datos.map { $0.panel.frase(decisiones: total($0)) } ?? "Leyendo tu empresa…")
                .tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.sobreColor.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("hoy.frase")
            Spacer(minLength: 4)
            if let d = datos {
                FlujoChips(espacio: 8) {
                    dato("Decisiones", total(d) == 0 ? "Ninguna" : "\(total(d))", icono: nil)
                    dato("Tu día", d.textoDia, icono: nil)
                    if d.hayRojo {
                        dato("En alerta", d.alertas.count == 1 ? "1" : "\(d.alertas.count)", icono: TLSEstado.mal.simbolo,
                             debajo: d.areasEnRojo.map(\.nombre).joined(separator: ", "))
                    }
                }
            }
        }
        .padding(TLSEspacio.e24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: 220)
        .background(RoundedRectangle(cornerRadius: TLSRadio.cabecera, style: .continuous).fill(TLSPaleta.cabecera.color))
        .tlsSobreColor()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hoy.cabecera")
    }

    private func dato(_ etiqueta: String, _ valor: String, icono: String?, debajo: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(etiqueta).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.subtituloCabecera.color)
            HStack(spacing: 6) {
                if let icono {
                    Image(systemName: icono).font(.system(size: 15, weight: .bold)).foregroundStyle(TLSPaleta.sobreColor.color)
                        .accessibilityHidden(true)
                }
                Text(valor).tlsTexto(TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 22, interlinea: 26, tabulares: true))
                    .foregroundStyle(TLSPaleta.sobreColor.color).lineLimit(1)
            }
            if let debajo, !debajo.isEmpty {
                Text(debajo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.subtituloCabecera.color).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 104, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.sobreCabeceraSuave.color))
        .accessibilityElement(children: .combine)
    }
}

/// Botón con borde blanco sobre el violeta («Ver detalle», «Posponer»).
struct BotonContornoBlanco: ButtonStyle {
    @Environment(\.isEnabled) private var activo

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tlsTexto(TLSTipo.interfazFuerte)
            // Desactivado: el texto sigue al 100 % (contraste ≥ 4,5:1 sobre el violeta) y lo dice el borde discontinuo.
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: TLSAltura.botonPrincipal)
            .background(Capsule(style: .circular).fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0)))
            .overlay(Capsule(style: .circular).strokeBorder(Color.white.opacity(activo ? 1 : 0.55),
                                            style: StrokeStyle(lineWidth: 1.5, dash: activo ? [] : [4, 3])))
            .contentShape(Capsule(style: .circular))
    }
}

/// **El** destacado violeta de Hoy: tu foco, con sus cinco preguntas (qué pasa, por qué importa, qué hago, qué pasa si
/// no y qué recomiendo), su botón, «Ver detalle» y «Posponer» (con su consecuencia antes de confirmar).
struct FocoHoy: View {
    let tarjeta: Tarjeta
    let hoy: LocalDate
    let codigo: String?
    let sesion: VaultSession
    /// Su área (o su número) está en la sección Alertas: solo entonces la pastilla va en rojo («En alerta»).
    var enAlerta = false
    @State private var detalle = false
    @State private var confirmar = false
    @State private var trabajando = false
    @Environment(\.navegar) private var navegar

    init(tarjeta: Tarjeta, hoy: LocalDate, codigo: String? = nil, sesion: VaultSession, enAlerta: Bool = false) {
        self.tarjeta = tarjeta; self.hoy = hoy; self.codigo = codigo; self.sesion = sesion; self.enAlerta = enAlerta
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.destacado, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            chips
            Text(tarjeta.titulo)
                .tlsTexto(TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 28, interlinea: 32))
                .foregroundStyle(TLSPaleta.sobreColor.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("hoy.foco.titulo")
            VStack(alignment: .leading, spacing: 8) {
                Text(tarjeta.quePasa).tlsTexto(TLSTipo.lectura)
                Text(tarjeta.recomendacion).tlsTexto(TLSTipo.lectura.peso(600))
            }
            .foregroundStyle(TLSPaleta.sobreColor.color)
            .fixedSize(horizontal: false, vertical: true)
            if detalle { porQue }
            if confirmar { confirmarPosponer }
            if let r = tarjeta.contexto, !sesion.esPrivado(r) { conectado(r) }
            Spacer(minLength: 0)
            botones
        }
        .padding(TLSEspacio.e24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: 220)
        .background(forma.fill(TLSPaleta.violeta.color))
        .overlay(forma.strokeBorder(TLSPaleta.violetaBorde.color, lineWidth: 1))
        .tlsSobreColor()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tu foco de hoy: \(tarjeta.titulo)")
        .accessibilityIdentifier("hoy.foco")
        .tutorialAnchor(.hoyFoco)
        .preference(key: ContadorDestacados.self, value: 1)
    }

    private var chips: some View {
        FlujoChips(espacio: 8) {
            Text("Tu foco de hoy").tlsTexto(TLSTipo.rotulo.peso(700)).foregroundStyle(TLSPaleta.sobreColor.color)
                .frame(minHeight: 26)
            if let a = tarjeta.area {
                HStack(spacing: 6) {
                    IconoArea(a.tlsArea, tamano: 18)
                    Text(a.etiquetaNumerada)
                }
                .modifier(ChipBlanco())
            }
            if let codigo { Text(codigo).font(TLSTipo.codigo.font()).modifier(ChipBlanco()) }
            // Las mismas palabras que en el resto de la app: «En alerta» (✖) solo si está en Alertas; si no, «Atención».
            if tarjeta.prioridad != .normal {
                let roja = tarjeta.prioridad.esRoja && enAlerta
                PastillaEstado(roja ? .mal : .atencion, palabra: roja ? "En alerta" : "Atención", sobreColor: true)
            }
        }
    }

    private var porQue: some View {
        HStack(alignment: .top, spacing: 12) {
            caja("Por qué importa", tarjeta.porQueImporta)
            caja("Qué pasa si no", tarjeta.siNo)
        }
    }

    private func caja(_ titulo: String, _ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).tlsTexto(TLSTipo.rotulo.peso(700))
            Text(texto).tlsTexto(TLSTipo.interfaz).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(TLSPaleta.sobreColor.color)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(FocoHoy.velo(0.22)))
        .accessibilityElement(children: .combine)
    }

    private var hasta: LocalDate { hoy.siguienteLaborable }

    private var confirmarPosponer: some View {
        FlujoChips(espacio: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: TLSEstado.atencion.simbolo).accessibilityHidden(true)
                Text("Si lo pospones hasta \(AlmacenHoy.dia(hasta, hoy: hoy)): \(Self.minuscula(tarjeta.siNo))")
                    .tlsTexto(TLSTipo.interfazMedia).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)
            }
            .foregroundStyle(TLSPaleta.sobreColor.color)
            Button("Posponer") {
                confirmar = false
                AlmacenHoy.de(sesion).posponer(tarjeta)
            }
            .buttonStyle(BotonContornoBlanco())
            Button("Mejor no") { confirmar = false }.tlsBoton(.sobreDestacado)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(FocoHoy.velo(0.26)))
        .accessibilityElement(children: .contain)
    }

    private func conectado(_ r: VaultPath) -> some View {
        FlujoChips(espacio: 8) {
            Text("Conectado con").tlsTexto(TLSTipo.rotulo.peso(700)).foregroundStyle(TLSPaleta.sobreColor.color).frame(minHeight: 36)
            Button { navegar(sesion.destino(para: r), modo: .automatico) } label: {
                HStack(spacing: 8) {
                    Image(systemName: sesion.resumen(de: r)?.kind.systemImage ?? "doc.text").font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24).background(Circle().fill(Color(red: 232 / 255, green: 235 / 255, blue: 245 / 255)))
                    Text(sesion.titulo(de: r)).lineLimit(1)
                    if let tipo = sesion.resumen(de: r)?.kind.etiqueta {
                        Text(tipo).foregroundStyle(Color(red: 84 / 255, green: 90 / 255, blue: 122 / 255))
                    }
                }
                .modifier(ChipBlanco(alto: 36))
            }
            .buttonStyle(.plain)
            .vistaPrevia(ruta: r, sesion: sesion)
        }
    }

    // MARK: Botones

    private var botones: some View {
        let (titulo, motivo) = boton
        return FlujoChips(espacio: 8) {
            Button {
                trabajando = true
                Task {
                    await ejecutar()
                    trabajando = false
                }
            } label: {
                Text(titulo).frame(minWidth: 160)
            }
            .tlsBoton(.sobreDestacado, alto: 52)
            .disabled(motivo != nil || trabajando)
            .help(motivo ?? titulo)
            .accessibilityIdentifier("hoy.foco.boton")
            Button(detalle ? "Ocultar detalle" : "Ver detalle") { detalle.toggle() }.buttonStyle(BotonContornoBlanco())
            if tarjeta.acciones.contains(.posponer) {
                Button("Posponer") { confirmar = true }
                    .buttonStyle(BotonContornoBlanco())
                    .disabled(confirmar)
                    .help(confirmar ? "Confírmalo arriba" : "Posponer hasta \(AlmacenHoy.dia(hasta, hoy: hoy))")
            }
            if tarjeta.acciones.contains(.descartar) {
                Button("Descartar") { AlmacenHoy.de(sesion).descartar(tarjeta) }.buttonStyle(BotonContornoBlanco())
            }
            if let motivo {
                Text(motivo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.sobreColor.color).frame(minHeight: 44)
            }
        }
    }

    /// El texto del botón y, si no se puede pulsar, por qué.
    private var boton: (String, String?) {
        let t = tarjeta.boton.etiqueta
        switch tarjeta.boton.accion {
        case .marcarHecha:
            if let m = Decidir.motivoSoloLectura(sesion) { return (t, "No se puede: \(m).") }
            return (t, nil)
        case .convertirEnRegla:
            // F4: lo prepara Mika como propuesta (en Decisiones, con tu OK); sin su motor en esta empresa, no se puede.
            if let m = Decidir.motivoSoloLectura(sesion) { return (t, "No se puede: \(m).") }
            guard AsistentesDeLaEmpresa.de(sesion).host != nil else {
                return (t, "Mika no está trabajando en esta empresa: mira Asistentes.")
            }
            return (t, nil)
        default:
            return (t, nil)
        }
    }

    private func ejecutar() async {
        let almacen = AlmacenHoy.de(sesion)
        switch tarjeta.boton.accion {
        case .abrir(let r), .prepararMensaje(let r), .decidirPlan(let r), .replantearPlazo(let r), .meterEnEmbudo(let r):
            almacen.apuntar(tarjeta, accion: "abrir")
            navegar(sesion.destino(para: r), modo: .automatico)
        case .prepararReclamacion(_, let ficha):
            almacen.apuntar(tarjeta, accion: "abrir")
            navegar(ficha.map { sesion.destino(para: $0) } ?? .base("facturas"), modo: .automatico)
        case .marcarHecha(let r):
            if await Self.marcarHecha(r, sesion: sesion) { almacen.apuntar(tarjeta, accion: "hecha") }
        case .fijarUmbral(let codigo):
            let a = AreaCode(rawValue: String(codigo.prefix(3))) ?? tarjeta.area ?? .direccion
            navegar(.area(a, pestana: PestanaArea.control.rawValue), modo: .automatico)
        case .verArea(let a):
            navegar(.area(a), modo: .automatico)
        case .bajarDeEscalon:
            navegar(.area(tarjeta.area ?? .direccion, pestana: PestanaArea.sistemas.rawValue), modo: .automatico)
        case .convertirEnRegla(let patron, let accion):
            // Mika lo prepara como propuesta: te espera en Decisiones y no cambia nada hasta que la apruebes.
            guard let host = AsistentesDeLaEmpresa.de(sesion).host else { return }
            let peticion = "La persona ha resuelto la tarjeta «\(patron)» con «\(accion)» tres veces o más. Propón convertirlo en "
                + "regla con tls_proponer: cuándo se aplica, qué hace y qué no hace nunca. No cambies nada por tu cuenta."
            if (try? await host.pedir(a: "mika", instruccion: peticion, accion: "convertir-en-regla")) != nil {
                almacen.apuntar(tarjeta, accion: "regla")
                sesion.aviso = Aviso("Se lo he pedido a Mika: su propuesta te esperará en Decisiones.", estado: .bien)
            } else {
                sesion.aviso = Aviso("Mika no puede trabajar ahora (en pausa o sin permisos). Mira Asistentes.", estado: .atencion)
            }
        case .verSemana:
            navegar(.tareas, modo: .automatico)
        }
    }

    /// «Marcar hecha»: la tarea pasa a Hecha (con su Actividad), como la persona y con Deshacer.
    static func marcarHecha(_ ruta: VaultPath, sesion: VaultSession) async -> Bool {
        guard let (foto, reloj) = await Decidir.foto(sesion) else { return false }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        guard let t = store.tarea(ruta) else {
            sesion.aviso = Aviso("No encuentro esa tarea. Puede que alguien la haya movido fuera de la app.", estado: .atencion)
            return false
        }
        do {
            let plan = try store.cambiarEstado(t, a: .hecha, autor: sesion.autor, persona: sesion.persona)
            try await sesion.escribirConDominio(plan: plan, aviso: "Hecha: «\(AccionesDecision.corto(t.titulo))»",
                                                deshacer: sesion.undoManagerActivo)
            await Decidir.refrescar(sesion)
            return true
        } catch let e as TareaError {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch {}
        return false
    }

    static func minuscula(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.lowercased() + s.dropFirst()
    }

    /// Velo azul noche sobre el violeta (las cajas de «Por qué importa» y la confirmación de posponer).
    static func velo(_ a: Double) -> Color { Color(.sRGB, red: 15 / 255, green: 20 / 255, blue: 48 / 255, opacity: a) }
}

/// Chip blanco con texto en `texto` fijo (dentro del violeta, M2-Hoy).
struct ChipBlanco: ViewModifier {
    var alto: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .tlsTexto(TLSTipo.secundario.peso(600))
            .foregroundStyle(Color(red: 15 / 255, green: 20 / 255, blue: 48 / 255))
            .padding(.horizontal, 10)
            .frame(minHeight: alto)
            .background(Capsule(style: .circular).fill(Color.white))
            .fixedSize()
    }
}

/// «Pide tu decisión»: como mucho 3 tarjetas, con la insignia magenta del número y «Ver todas».
struct PideTuDecision: View {
    let datos: DatosHoy
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        let n = datos.pendientes + ConexionesEnDecisiones.de(sesion).pendientes.count
        let tres = Array(datos.decisiones.prefix(3))
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            FlujoChips(espacio: 10) {
                Text("Pide tu decisión").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                if n > 0 {
                    InsigniaAviso(n, palabra: n == 1 ? "espera tu decisión" : "esperan tu decisión").frame(minHeight: 26)
                }
                Text("Una pregunta, hasta tres opciones y la que te recomiendo.").tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color).frame(minHeight: 26)
                Button(n > 3 ? "Ver las \(n)" : "Ver todas") { navegar(.decisiones, modo: .automatico) }.tlsBoton(.enlace)
            }
            // F5 · integración: lo que piden las conexiones (un permiso, un evento cambiado, herramientas nuevas).
            let deConexiones = ConexionesEnDecisiones.de(sesion).pendientes
            if let primera = deConexiones.first {
                HStack(spacing: TLSEspacio.e8) {
                    Image(systemName: primera.icono).foregroundStyle(TLSPaleta.atencion.color).accessibilityHidden(true)
                    // F5 · corrector (P3-15): una frase corta que no se corta.
                    Text(deConexiones.count == 1 ? "1 cosa de tus conexiones espera tu decisión."
                         : "\(deConexiones.count) cosas de tus conexiones esperan tu decisión.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Ver") { navegar(.decisiones, modo: .automatico) }.tlsBoton(.enlace)
                        .accessibilityLabel("Ver en Decisiones")
                }
                .padding(TLSEspacio.e12)
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("hoy.decisiones.conexiones")
            }
            if tres.isEmpty && deConexiones.isEmpty {
                VacioExplicado(icono: "signpost.right.and.left", titulo: "Nada pide tu decisión",
                               porQue: "Cuando una tarea de decisión, una pregunta o un archivo en conflicto te esperen, aparecerán aquí con la opción que te recomiendo.",
                               compacto: true)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            } else if !tres.isEmpty {
                ViewThatFits(in: .horizontal) {
                    RepartoFlex(bases: Array(repeating: 300, count: tres.count), pesos: Array(repeating: 1, count: tres.count),
                                espacio: TLSEspacio.entreMosaicos) {
                        ForEach(tres) { t in tarjeta(t).frame(maxHeight: .infinity, alignment: .top) }
                    }
                    VStack(spacing: TLSEspacio.entreMosaicos) {
                        ForEach(tres) { t in tarjeta(t) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hoy.decisiones")
    }

    @ViewBuilder
    private func tarjeta(_ t: TarjetaDecision) -> some View {
        if let d = datos.detalles[t.id] {
            TarjetaDecisionVista(detalle: d, sesion: sesion, hoy: datos.hoy, compacta: true)
        }
    }
}

/// «En alerta»: **solo existe si hay algo en rojo** (lo decide `DatosHoy.secciones`).
struct AlertasHoy: View {
    let alertas: [AlertaHoy]
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: TLSEstado.mal.simbolo).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TLSPaleta.mal.color).accessibilityHidden(true)
                Text("En alerta").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                Text(alertas.count == 1 ? "1 cosa en rojo" : "\(alertas.count) cosas en rojo")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(alertas) { a in
                HStack(spacing: TLSEspacio.e8) {
                    if let area = a.area { IconoArea(area.tlsArea, tamano: 20) }
                    Text(a.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Ver") { navegar(destino(a), modo: .automatico) }.tlsBoton(.enlace)
                        .accessibilityLabel("Ver \(a.texto)")
                }
                .frame(minHeight: TLSAltura.objetivoMinimo)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay(forma.strokeBorder(TLSPaleta.mal.color.opacity(0.45), lineWidth: 1))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alertas")
        .accessibilityIdentifier("hoy.alertas")
    }

    private func destino(_ a: AlertaHoy) -> Destino {
        if let r = a.ruta, !sesion.esPrivado(r) { return sesion.destino(para: r) }
        guard let area = a.area else { return .tareas }
        return a.origen.hasPrefix("numero:") ? .area(area, pestana: PestanaArea.control.rawValue) : .area(area)
    }
}

