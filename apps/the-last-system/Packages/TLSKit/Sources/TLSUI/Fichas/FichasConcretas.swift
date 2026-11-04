import SwiftUI
import TLSCore
import TLSDesign
import TLSVisores

// MARK: - Oportunidad: línea de etapas

/// Bajo la cabecera de la oportunidad (§3.4): Prospecto → Diagnóstico → Propuesta → Aceptada → Ganada, con
/// Perdida y Pausada aparte. Clic en una etapa la cambia (una línea); Ganada sale bloqueada con su motivo
/// al lado mientras no haya un cobro confirmado por una persona.
struct LineaEtapas: View {
    let ficha: FichaGrafo
    let modelo: FichaModelo
    @FocusState private var foco: String?

    var body: some View {
        let actual = TextFolding.fold(ficha.estado ?? "")
        let opciones = Dictionary(uniqueKeysWithValues: modelo.opcionesEstado(ficha).map { ($0.id, $0) })
        let indice = EstadosDeFicha.etapasOportunidad.firstIndex { TextFolding.fold($0) == actual }
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: 4) {
                ForEach(Array(EstadosDeFicha.etapasOportunidad.enumerated()), id: \.offset) { i, etapa in
                    let elegida = TextFolding.fold(etapa) == actual
                    let pasada = indice.map { i < $0 } ?? false
                    let motivo = opciones[etapa]?.motivoDesactivado
                    Button {
                        // La etapa actual no hace nada; una bloqueada dice por qué (en vez de salir apagada y sin motivo).
                        if elegida { return }
                        if let motivo { modelo.sesion.aviso = Aviso(motivo, estado: .atencion); return }
                        Task { await modelo.cambiarEstado(etapa) }
                    } label: {
                        HStack(spacing: 6) {
                            if pasada { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                            if motivo != nil && !elegida { Image(systemName: "lock.fill").font(.system(size: 10)) }
                            Text(etapa).tlsTexto(TLSTipo.interfazFuerte)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo + 8)
                        .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : (motivo != nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color))
                        .background(Capsule(style: .circular).fill(elegida ? TLSPaleta.principal.color : (pasada ? TLSPaleta.principalSuave.color : TLSPaleta.bandeja.color)))
                    }
                    .buttonStyle(.plain)
                    .focused($foco, equals: etapa)
                    .focusEffectDisabled()
                    .tlsAnilloFoco(foco == etapa, radio: 999)
                    .disabled(!modelo.puedeEscribir && !elegida)
                    .help(motivo ?? (elegida ? "Etapa actual" : "Pasar a \(etapa)"))
                    .accessibilityLabel("\(etapa)\(elegida ? ", etapa actual" : "")\(motivo.map { ", bloqueada: \($0)" } ?? "")")
                    .accessibilityAddTraits(elegida ? .isSelected : [])
                    if i < EstadosDeFicha.etapasOportunidad.count - 1 {
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .accessibilityHidden(true)
                    }
                }
                Divider().frame(height: 24).padding(.horizontal, 6)
                ForEach(["Perdida", "Pausada"], id: \.self) { e in
                    let elegida = TextFolding.fold(e) == actual
                    Button(e) { Task { await modelo.cambiarEstado(e) } }
                        .tlsBoton(elegida ? .principal : .secundario, alto: TLSAltura.objetivoMinimo + 8)
                        .disabled(elegida || !modelo.puedeEscribir)
                }
            }
            if let motivo = opciones["Ganada"]?.motivoDesactivado, TextFolding.fold(ficha.estado ?? "") != "ganada" {
                Label(motivo, systemImage: "lock")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Etapas de la oportunidad")
    }
}

// MARK: - Proyecto: fases del plan

/// Franja «Fases del plan» del proyecto (§3.4): una pieza por fase con sus fechas, su estado y la marca de hoy;
/// clic en una fase filtra el tablero de Tareas.
struct FranjaFases: View {
    let modelo: FichaModelo
    let irATareas: () -> Void
    @Environment(\.navegacion) private var nav

    var body: some View {
        let datos = fases
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack {
                Rotulo("Fases del plan")
                Spacer()
                if let plan = planFicha {
                    Text(plan.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            if datos.fases.isEmpty {
                Text(planFicha == nil ? "Sin plan de entrega enlazado: ponlo en «Conectado con» y aquí saldrán sus fases."
                        : "Su plan de entrega no tiene fases escritas (## Fase 1 · …).")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                HStack(alignment: .top, spacing: TLSEspacio.e8) {
                    ForEach(datos.fases) { f in pieza(f, filtrada: filtro == "\(f.fase.numero)") }
                }
                HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e16) {
                    // Leyenda de la línea magenta de hoy (M2-Proyecto: «Hoy, jue 22 oct»).
                    if datos.fases.contains(where: \.contieneHoy) {
                        HStack(spacing: 6) {
                            MarcaAhora(.vertical, palabra: "Hoy").frame(width: 8, height: 14)
                            Text("Hoy, " + FormatoBase.fechaConDia(modelo.hoy))
                                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                        .fixedSize()
                    }
                    if let t = datos.terminado {
                        Text("Terminado cuando: \(t)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fases del plan")
    }

    private var filtro: String? { nav?.recuerdo(de: .ficha(modelo.ruta)).filtros["fase"] }

    private var planFicha: FichaGrafo? {
        modelo.grafo.flatMap { g in g.destinos(de: modelo.ruta, propiedad: "plan").first.flatMap(g.ficha) }
    }

    var fases: (fases: [FaseDelProyecto], terminado: String?) {
        guard let plan = planFicha, let texto = modelo.almacen.foto?.text(plan.ruta) else { return ([], nil) }
        let p = PlanDeEntrega.leer(texto)
        let inicio = modelo.ficha?.texto("inicio").flatMap { LocalDate(parsing: $0) }
        let tareas = modelo.relacionados([.task]).map(\.ficha)
        return (FasesDelPlan.delProyecto(plan: p, inicio: inicio, tareas: tareas, hoy: modelo.hoy),
                modelo.ficha?.texto("terminado_cuando") ?? p.terminadoCuando)
    }

    private func pieza(_ f: FaseDelProyecto, filtrada: Bool) -> some View {
        let actual = modelo.ficha?.texto("fase").map { TextFolding.fold($0) == TextFolding.fold(f.fase.nombre) } ?? false
        let estado: (String, String, Color) = {
            switch f.situacion {
            case .hecha: ("Hecha", TLSEstado.bien.simbolo, TLSPaleta.bien.color)
            case .enCurso: ("En curso", "clock.fill", TLSPaleta.principal.color)
            case .pendiente: ("Pendiente · \(f.tareas.count == 1 ? "1 tarea" : "\(f.tareas.count) tareas")", TLSEstado.sinDato.simbolo, TLSPaleta.sinDato.color)
            }
        }()
        let fechas = [f.inicio, f.fin].compactMap { $0 }.map { FormatoFicha.fechaCorta($0, hoy: modelo.hoy) }
        return Button {
            nav?.actualizarRecuerdo(de: .ficha(modelo.ruta)) { $0.filtros["fase"] = filtrada ? nil : "\(f.fase.numero)" }
            irATareas()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(f.fase.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text(fechas.joined(separator: " – ")).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                Label {
                    Text(estado.0).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                } icon: {
                    Image(systemName: estado.1).foregroundStyle(estado.2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque).fill(actual ? TLSPaleta.principalSuave.color : TLSPaleta.superficie.color))
            .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque)
                .strokeBorder(filtrada ? TLSPaleta.principal.color : (actual ? TLSPaleta.principal.color.opacity(0.6) : TLSPaleta.separador.color),
                              lineWidth: filtrada ? 2 : 1))
        }
        .buttonStyle(.plain)
        // La línea magenta de hoy marca la fase en curso (M2-Proyecto), en su borde izquierdo para no tachar el
        // texto de la pieza; la leyenda de debajo dice el día. No recibe clics.
        .overlay(alignment: .leading) {
            if f.contieneHoy {
                MarcaAhora(.vertical, palabra: "Hoy")
                    .frame(width: 8)
                    .padding(.vertical, -6)
                    .offset(x: -1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Fase \(f.fase.nombre), \(fechas.joined(separator: " a ")), \(estado.0)\(f.contieneHoy ? ", hoy" : ""). \(filtrada ? "Quitar el filtro del tablero" : "Ver sus tareas en el tablero")")
    }
}

// MARK: - Documento (factura, propuesta, presupuesto)

/// El Resumen de un documento (§3.4 Factura): la línea de estados, sus tablas (partes, conceptos, totales) y la
/// vista previa de su PDF con el visor de TLSVisores. Una factura emitida no se edita: se rectifica.
struct DocumentoFicha: View {
    let modelo: FichaModelo

    /// El PDF del documento: su propiedad `pdf` o un PDF de su carpeta con su número en el nombre.
    static func pdf(de modelo: FichaModelo) -> VaultPath? {
        guard let f = modelo.ficha, let foto = modelo.almacen.foto else { return nil }
        if let p = f.texto("pdf"), let r = (modelo.almacen.resolver ?? foto.resolver).resolve(p, from: f.ruta) { return r }
        guard let numero = f.numero, let carpeta = f.ruta.parent else { return nil }
        return foto.files.first { $0.ext.lowercased() == "pdf" && $0.parent == carpeta && $0.name.contains(numero) }
    }

    @State private var ancho: CGFloat = 1000

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if modelo.tipo == .invoice, let f = modelo.ficha {
                lineaEstados(f)
            }
            // Con sitio, el documento a la izquierda y su PDF a la derecha (como en un visor); si no, uno bajo otro.
            if ancho >= 980 {
                HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                    documento(forma).frame(maxWidth: .infinity)
                    pdfVista(forma).frame(width: min(440, ancho * 0.4))
                }
            } else {
                documento(forma)
                pdfVista(forma)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
    }

    /// El documento como pantalla de app: los datos (para quién, vence, de qué oportunidad, cómo se paga), sus
    /// importes y sus secciones con las tablas como tablas.
    private func documento(_ forma: RoundedRectangle) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let f = modelo.ficha {
                let datos = Self.datos(f, modelo: modelo)
                if !datos.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: TLSEspacio.e16, verticalSpacing: 6) {
                        ForEach(datos, id: \.0) { d in
                            GridRow {
                                Text(d.0).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                Text(d.1).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                let importes = Self.importes(f)
                if !importes.isEmpty {
                    FlujoChips(espacio: TLSEspacio.e8) {
                        ForEach(importes, id: \.self) { t in
                            Text(t).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                                .padding(.horizontal, 10).frame(minHeight: 24)
                                .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
                        }
                    }
                }
                Divider().overlay(TLSPaleta.separador.color)
            }
            ForEach(secciones, id: \.self) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(s).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                    TextoDeSeccion(texto: MarkdownSections.content(of: s, in: modelo.cuerpo ?? "", level: 2) ?? "")
                }
            }
        }
        .padding(TLSEspacio.e20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
    }

    @ViewBuilder
    private func pdfVista(_ forma: RoundedRectangle) -> some View {
        if let pdf = Self.pdf(de: modelo), let url = modelo.sesion.url(for: pdf), !modelo.sesion.esPrivado(pdf) {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                Text("Vista previa del PDF").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                VistaPreviaPDF(url: url, titulo: pdf.stem, alto: 460) {
                    modelo.sesion.navegar(a: .fichero(pdf), modo: .entrar)
                }
            }
            .padding(TLSEspacio.e16)
            .background(forma.fill(TLSPaleta.superficie.color))
            .tlsSombra(.uno, forma: forma)
        } else if modelo.tipo == .invoice {
            VacioExplicado(icono: "doc.richtext", titulo: "Aún no tiene PDF",
                           porQue: TextFolding.fold(modelo.ficha?.estado ?? "") == "borrador"
                               ? "El PDF nace al emitirla. Mientras es un borrador, lo que ves a la izquierda es lo que llevará."
                               : "El PDF lo genera tu herramienta de facturación al emitirla; cuando esté en su carpeta lo verás aquí.",
                           compacto: true)
                .background(forma.fill(TLSPaleta.superficie.color))
        }
    }

    /// Los datos secundarios del documento (GUION §6.1): para quién, vence, de qué oportunidad y cómo se paga.
    static func datos(_ f: FichaGrafo, modelo: FichaModelo) -> [(String, String)] {
        let g = modelo.grafo
        func nombre(_ prop: String) -> String? { g.flatMap { g in g.destinos(de: f.ruta, propiedad: prop).first.flatMap(g.ficha)?.nombre } }
        var out: [(String, String)] = []
        if let e = nombre("empresa") ?? nombre("contacto") { out.append(("Para", e)) }
        if let v = f.texto("vence") {
            out.append(("Vence", FormatoFicha.fechaLegible(v, hoy: modelo.hoy)))
        } else if let d = f.texto("plazo_dias") {
            out.append(("Vence", "\(d) días tras emitir"))
        } else if let v = f.texto("valida_hasta") {
            out.append(("Válida hasta", FormatoFicha.fechaLegible(v, hoy: modelo.hoy)))
        }
        if let o = nombre("oportunidad") { out.append(("Oportunidad", o)) }
        if let p = f.texto("forma_pago") { out.append(("Forma de pago", FormatoFicha.capital(p))) }
        return out
    }

    /// Los importes auxiliares: base, IVA, retención y plantilla.
    static func importes(_ f: FichaGrafo) -> [String] {
        var out: [String] = []
        if let b = FormatoFicha.euros(f.texto("base")) { out.append("Base \(b)") }
        if let i = FormatoFicha.euros(f.texto("cuota_iva")) { out.append("IVA \(i)") }
        if f.tipo == .invoice {
            if let r = FormatoFicha.numero(f.texto("retencion")), r != 0, let e = FormatoFicha.euros(r.description) {
                out.append("Retención −\(e)")
            } else {
                out.append("Retención: no aplica")
            }
        }
        if let p = f.texto("plantilla"), !p.contains("{{") { out.append("Plantilla \(p)") }
        return out
    }

    private var secciones: [String] {
        let todas = MarkdownSections.titles(in: modelo.cuerpo ?? "", level: 2)
        return todas.filter { !["historial", "actividad"].contains(TextFolding.fold($0)) }
    }

    private func lineaEstados(_ f: FichaGrafo) -> some View {
        let pasos = ["Borrador", "Emitida", "Enviada", "Cobrada"]
        let i = pasos.firstIndex { TextFolding.fold($0) == TextFolding.fold(f.estado ?? "") } ?? 0
        return HStack(spacing: 4) {
            ForEach(Array(pasos.enumerated()), id: \.offset) { j, p in
                Text(p).tlsTexto(TLSTipo.interfazFuerte)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo + 4)
                    .foregroundStyle(j == i ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                    .background(Capsule(style: .circular).fill(j == i ? TLSPaleta.principal.color : (j < i ? TLSPaleta.principalSuave.color : TLSPaleta.bandeja.color)))
                    .accessibilityLabel("\(p)\(j == i ? ", ahora" : "")")
                if j < pasos.count - 1 {
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Estados de la factura")
    }
}

/// Una acción de un documento según su estado (§3.4 Factura: Revisar y emitir · Preparar envío · Confirmar cobro ·
/// Preparar recordatorio). La primera es la principal (cabecera y barra fija). Crear el correo, el recibo o el
/// recordatorio usa su plantilla y nace ya enlazado con la factura («Nuevo» de la ficha).
struct AccionDocumento: Identifiable {
    var id: String { titulo }
    let titulo: String
    /// Por qué aún no se puede (sale desactivada con el motivo).
    let motivo: String?
    let hacer: () -> Void

    @MainActor
    static func de(_ modelo: FichaModelo) -> [AccionDocumento] {
        guard let f = modelo.ficha else { return [] }
        let estado = TextFolding.fold(f.estado ?? "")
        switch f.tipo {
        case .invoice:
            let envio = AccionDocumento(titulo: "Preparar el envío", motivo: nil) {
                modelo.nuevo = OpcionNuevo(titulo: "Correo de envío", plantilla: "mensaje", tipo: .draft)
            }
            let cobro = AccionDocumento(titulo: "Confirmar el cobro", motivo: nil) {
                modelo.nuevo = OpcionNuevo(titulo: "Recibo de cobro", plantilla: "recibo-de-cobro", tipo: .receipt)
            }
            let recordatorio = AccionDocumento(titulo: "Preparar recordatorio", motivo: nil) {
                modelo.nuevo = OpcionNuevo(titulo: "Recordatorio de cobro", plantilla: "recordatorio-de-cobro", tipo: .draft)
            }
            let vencida = f.texto("vence").flatMap { LocalDate(parsing: $0) }.map { $0 < modelo.hoy } ?? false
            switch estado {
            case "borrador":
                return [AccionDocumento(titulo: "Revisar y emitir",
                                        motivo: "La factura se emite con tu programa de facturación (la app no factura): cuando la emitas allí, aquí se verá Emitida.") {}]
            case "emitida":
                return vencida ? [recordatorio, cobro] : [envio, cobro]
            case "enviada":
                return vencida ? [recordatorio, cobro] : [cobro, recordatorio]
            default:
                return []
            }
        default:
            return []
        }
    }
}

// MARK: - Sistema

/// El Resumen de una ficha de sistema (SISTEMAS §2.2): sus secciones en orden, cada una editable en el sitio;
/// las que faltan salen como «Falta» con su guía.
struct ResumenSistema: View {
    let modelo: FichaModelo

    static let secciones: [(String, String)] = [
        ("Para qué", "una frase."),
        ("Cuándo se usa", "cuándo empieza y cuándo termina."),
        ("Entradas", "qué tiene que estar antes de empezar y quién lo da."),
        ("Pasos", "cada paso con verbo, quién lo hace y en qué modo."),
        ("Quién lo hace", "dueño, asistente y qué apruebas tú."),
        ("Salida esperada y criterio de «bien hecho»", "qué entrega y de 3 a 5 frases de sí o no."),
        ("Lo que nunca hace", "los límites del asistente en este sistema."),
        ("Herramientas y conexiones", "programas conectados y para qué."),
        ("Plantillas y activos", "enlaces a sus plantillas y activos."),
        ("Referencias y ejemplos", "de 1 a 3 resultados buenos."),
        ("Cómo sabemos que va bien", "el código del número clave."),
        ("Rutina", "cuándo se revisa y con qué pregunta."),
        ("Aprendido", "lo aprendido con fecha; solo se añade."),
        ("Origen", "de dónde sale y cuándo se escribió."),
    ]

    var body: some View {
        let cuerpo = modelo.cuerpo ?? ""
        let titulos = Set(MarkdownSections.titles(in: cuerpo, level: 2).map(TextFolding.fold))
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ForEach(Self.secciones, id: \.0) { titulo, guia in
                let existe = titulos.contains(TextFolding.fold(titulo))
                    || (titulo.hasPrefix("Salida") && titulos.contains(TextFolding.fold("Qué deja hecho")))
                if existe {
                    BloqueSeccion(modelo: modelo, titulo: titulo.hasPrefix("Salida") && !titulos.contains(TextFolding.fold(titulo)) ? "Qué deja hecho" : titulo,
                                  ruta: modelo.ruta, cuerpo: cuerpo, guia: "Guía: \(guia)")
                } else {
                    HStack {
                        Text(titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        PastillaEstado(.atencion, palabra: "Falta")
                        Text(guia).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Spacer()
                        Button("Añadir") { Task { await anadir(titulo) } }
                            .tlsBoton(.secundario)
                            .disabled(!modelo.puedeEscribir)
                    }
                    .padding(TLSEspacio.e12)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.bloque).fill(TLSPaleta.superficie.color))
                }
            }
        }
    }

    /// Crea la sección vacía al final (con `anadirASeccion`, que la crea si no existe).
    private func anadir(_ titulo: String) async {
        guard EdicionRelaciones.comprobarEscritura(modelo.sesion) else { return }
        _ = try? await modelo.sesion.escribir(.anadirASeccion(modelo.ruta, seccion: titulo, texto: "> Guía: escribe aquí."),
                                              aviso: "Añadí «\(titulo)» a \(modelo.ficha?.nombre ?? modelo.ruta.stem)")
        modelo.almacen.invalidar()
    }
}

/// Una sola sección de la nota, editable en el sitio (pestañas Pasos, Aprendido… del sistema; Viaje).
struct PestanaSeccion: View {
    let modelo: FichaModelo
    let titulo: String

    var body: some View {
        if MarkdownSections.content(of: titulo, in: modelo.cuerpo ?? "", level: 2) != nil {
            BloqueSeccion(modelo: modelo, titulo: titulo, ruta: modelo.ruta, cuerpo: modelo.cuerpo ?? "")
        } else {
            VacioExplicado(icono: "text.alignleft", titulo: "Aún no tiene «\(titulo)»",
                           porQue: "Esta ficha no tiene esa sección. Puedes añadirla desde el Resumen.", compacto: true)
        }
    }
}

/// Ejecuciones de un sistema (calculado, no se escribe): las tareas cuya función es suya y lo que se creó con
/// sus plantillas.
struct PestanaEjecuciones: View {
    let modelo: FichaModelo
    @Environment(\.navegar) private var navegar

    var body: some View {
        let lista = ejecuciones
        VStack(alignment: .leading, spacing: 2) {
            if lista.isEmpty {
                VacioExplicado(icono: "play.circle", titulo: "Aún no hay ejecuciones",
                               porQue: "Aquí salen las tareas con una función de este sistema y lo creado con sus plantillas. Se calculan; no se escriben.",
                               compacto: true)
            }
            ForEach(lista) { f in
                FilaLista(f.nombre, detalle: [f.numero, f.estado].compactMap { $0 }.joined(separator: " · "), icono: f.tipo.systemImage,
                          accion: { navegar(modelo.sesion.destino(para: f.ruta)) })
                    .vistaPrevia(ruta: f.ruta, sesion: modelo.sesion)
            }
        }
    }

    private var ejecuciones: [FichaGrafo] {
        guard let g = modelo.grafo, let codigo = modelo.ficha?.texto("codigo") else { return [] }
        let k = codigo.uppercased()
        return g.fichas.values.filter { f in
            guard !f.privada, f.ruta != modelo.ruta else { return false }
            if let c = f.texto("capacidad"), c.uppercased().hasPrefix(k) { return true }
            return false
        }
        .sorted { $0.nombre.localizedStandardCompare($1.nombre) == .orderedAscending }
    }
}

/// Materiales del proyecto (§3.4): galería de los ficheros de su carpeta `Materiales/`, con su miniatura (sin
/// descargar nada de iCloud). Clic abre su visor; puntero o barra espaciadora, la vista previa.
struct PestanaMateriales: View {
    let modelo: FichaModelo
    @Environment(\.navegar) private var navegar
    @FocusState private var foco: VaultPath?

    var body: some View {
        let ficheros = materiales
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack {
                Text("Materiales · \(modelo.ficha?.nombre ?? "")").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Mostrar la carpeta en Finder") { modelo.sesion.revealInFinder(modelo.ruta.parent?.appending("Materiales")) }
                    .tlsBoton(.secundario)
            }
            if ficheros.isEmpty {
                VacioExplicado(icono: "photo.on.rectangle", titulo: "Aún no hay materiales",
                               porQue: "Lo que el cliente mande (facturas escaneadas, extractos…) va a la carpeta «Materiales» del proyecto y sale aquí.",
                               compacto: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 240), spacing: TLSEspacio.e12)],
                          alignment: .leading, spacing: TLSEspacio.e12) {
                    ForEach(ficheros, id: \.self) { p in tarjeta(p) }
                }
            }
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
    }

    private func tarjeta(_ p: VaultPath) -> some View {
        let tipo = TipoFichero.de(extension: p.ext)
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        return Button { navegar(modelo.sesion.destino(para: p)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let url = modelo.sesion.url(for: p) {
                        MiniaturaFicheroVista(url: url, tipo: tipo, lado: 360)
                    } else {
                        Image(systemName: tipo.simbolo).font(.system(size: 22)).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110)
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque).fill(TLSPaleta.bandeja.color))
                .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque))
                Text(p.name).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tipo.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(forma.fill(TLSPaleta.superficie.color))
            .overlay(forma.strokeBorder(TLSPaleta.separador.color, lineWidth: 1))
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .focused($foco, equals: p)
        .focusEffectDisabled()
        .tlsAnilloFoco(foco == p, radio: TLSRadio.tarjeta)
        .vistaPrevia(ruta: p, sesion: modelo.sesion)
        .contextMenu {
            Button("Abrir") { navegar(modelo.sesion.destino(para: p), modo: .entrar) }
            Button("Abrir en pestaña nueva") { navegar(modelo.sesion.destino(para: p), modo: .pestanaNueva) }
            Button("Mostrar en Finder") { modelo.sesion.revealInFinder(p) }
        }
        .accessibilityLabel("\(tipo.nombre) \(p.name)")
    }

    private var materiales: [VaultPath] {
        guard let carpeta = modelo.ruta.parent, let foto = modelo.almacen.foto else { return [] }
        let m = carpeta.appending("Materiales")
        return foto.files.filter { $0.isDescendant(of: m) && !modelo.sesion.esPrivado($0) }
    }
}
