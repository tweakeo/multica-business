import SwiftUI
import TLSCore
import TLSDesign

/// El panel de propiedades (⌥⌘I, §3.1 punto 8): todas las propiedades como formulario, con el control
/// adecuado a cada una (texto, fecha, número, lista, estado, relación, responsable, sí/no). Cada cambio escribe
/// solo su línea. Debajo, lo calculado (no se escribe), «Enlazan aquí» desde el texto de otras notas y
/// «Menciones sin enlazar» con «Enlazar».
struct InspectorFicha: View {
    let modelo: FichaModelo
    /// Otra ficha (la tarea elegida en el tablero); `nil` = la de la pantalla.
    var ruta: VaultPath? = nil
    /// Con su propio desplazamiento (en el panel lateral). Sin él, para meterlo en otra vista.
    var desplazable = true

    /// Propiedades internas que no se enseñan.
    static let tecnicas: Set<String> = ["tls_type", "tls_schema", "id", "plantilla", "creada_por"]

    static func etiqueta(_ k: String) -> String {
        let mapa: [String: String] = [
            "email": "Correo", "telefono": "Teléfono", "cargo": "Cargo", "relacion": "Relación", "estado": "Estado",
            "canal": "Canal", "origen": "Origen", "creada": "Creada", "no_contactar": "No contactar",
            "siguiente_paso": "Siguiente paso", "siguiente_fecha": "Fecha del siguiente paso", "valor": "Valor",
            "probabilidad": "Probabilidad (%)", "precio_congelado": "Precio acordado", "oferta_version": "Versión de oferta",
            "aceptada": "Aceptada el", "vence": "Vence", "planificada": "Planificada", "numero": "Número", "iva_pct": "IVA (%)",
            "retencion_pct": "Retención (%)", "cuota_iva": "Cuota de IVA", "duracion_min": "Duración (min)",
            "estimacion_h": "Estimación (h)", "dedicadas_h": "Dedicadas (h)", "aliases": "Otros nombres", "nombre": "Nombre",
            "titulo": "Título", "responsable": "Responsable", "prioridad": "Prioridad", "fecha": "Fecha", "hora": "Hora",
            "lugar": "Lugar", "tipo": "Tipo", "inicio": "Inicio", "fin": "Fin", "fase": "Fase", "base": "Base imponible",
            "total": "Total", "serie": "Serie", "categoria": "Categoría", "ciudad": "Ciudad", "sector": "Sector", "nif": "NIF",
            "verificacion": "Datos", "valida_hasta": "Válida hasta", "version": "Versión", "area": "Área", "capacidad": "Función",
            "sesiones_incluidas": "Sesiones incluidas", "franja": "Franja", "despertar": "Vuelve a aparecer", "cerrada": "Cerrada",
            "codigo": "Código", "numero_clave": "Número clave", "revisado": "Revisado", "revisar_cada": "Revisar cada",
            "etapa": "Etapa", "clase": "Clase", "email_facturacion": "Correo de facturación", "razon_social": "Razón social",
        ]
        if let e = mapa[k] { return e }
        if let d = EsquemaRelaciones.todas.first(where: { $0.claves.contains(k) }) { return d.etiqueta }
        return FormatoFicha.capital(k.replacingOccurrences(of: "_", with: " "))
    }

    static let numeros: Set<String> = ["valor", "precio", "importe", "base", "total", "probabilidad", "iva_pct", "retencion_pct",
                                       "duracion_min", "estimacion_h", "dedicadas_h", "sesiones_incluidas", "precio_congelado",
                                       "cuota_iva", "retencion", "etapa", "horas_previstas"]
    static let fechas: Set<String> = ["fecha", "vence", "planificada", "inicio", "fin", "creada", "cerrada", "siguiente_fecha",
                                      "despertar", "aceptada", "valida_hasta", "revisado", "fecha_corte", "fecha_cierre"]

    @State private var menciones: [MencionSinEnlazar] = []
    @State private var nueva = ""
    @State private var nuevaClave = ""

    private var destino: VaultPath { ruta ?? modelo.ruta }
    private var ficha: FichaGrafo? { ruta == nil ? modelo.ficha : modelo.grafo?.ficha(destino) }

    var body: some View {
        Group {
            if desplazable { ScrollView { formulario } } else { formulario }
        }
        .background(TLSPaleta.superficie.color)
        .task(id: modelo.almacen.generacion) {
            guard ruta == nil, let foto = modelo.almacen.foto else { return }
            let r = destino
            let m = await Task.detached(priority: .utility) { SaludDeEnlaces(snapshot: foto).mencionesSinEnlazar(de: r) }.value
            // Un nombre dentro del título de otra nota no se ofrece (enlazarlo cambiaría su título).
            menciones = m.filter { modelo.grafo?.ficha($0.origen)?.privada != true && !$0.extracto.hasPrefix("#") }
        }
    }

    private var formulario: some View {
            VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                HStack {
                    Text("Propiedades").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if ruta == nil {
                        Button { modelo.sesion.showInspector = false } label: { Image(systemName: "sidebar.trailing") }
                            .tlsBoton(.discreto)
                            .help("Ocultar · ⌥⌘I")
                            .accessibilityLabel("Ocultar propiedades")
                    }
                }
                Text(modelo.puedeEscribir ? "Pulsa un valor para cambiarlo. Cada cambio escribe solo su línea."
                        : "Solo lectura: \(modelo.motivoSoloLectura ?? "no se puede cambiar").")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let f = ficha {
                    VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                        ForEach(f.propiedades.properties.filter { !Self.tecnicas.contains($0.key) }) { p in
                            CampoPropiedad(modelo: modelo, ficha: f, propiedad: p)
                        }
                        anadirPropiedad(f)
                    }
                    calculado(f)
                    if ruta == nil {
                        enlazanAqui
                        mencionesSinEnlazar
                    }
                } else {
                    ProgressView()
                }
            }
            .padding(TLSEspacio.e16)
    }

    private func anadirPropiedad(_ f: FichaGrafo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Añadir una propiedad").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            TextField("Nombre (por ejemplo, sector)", text: $nuevaClave, prompt: Text("Nombre (por ejemplo, sector)"))
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Valor", text: $nueva, prompt: Text("Valor"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(anadir)
                Button("Añadir", action: anadir)
                    .tlsBoton(.secundario)
                    .disabled(nuevaClave.trimmingCharacters(in: .whitespaces).isEmpty || nueva.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .disabled(!modelo.puedeEscribir)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Añadir una propiedad")
    }

    /// Una propiedad nueva, en una línea (`sector: Automoción`). El nombre se escribe sin tildes ni espacios.
    private func anadir() {
        let k = NombresDeFicha.slug(nuevaClave).replacingOccurrences(of: "-", with: "_")
        let v = nueva.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty, !v.isEmpty else { return }
        nuevaClave = ""; nueva = ""
        Task { await modelo.cambiar(k, a: .text(v), en: ruta) }
    }

    @ViewBuilder
    private func calculado(_ f: FichaGrafo) -> some View {
        let filas = calculadas(f)
        if !filas.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Rotulo("Calculado · no se escribe aquí")
                ForEach(filas, id: \.0) { k, v, origen in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text(v).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                        Text(origen).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func calculadas(_ f: FichaGrafo) -> [(String, String, String)] {
        guard let g = modelo.grafo else { return [] }
        var out: [(String, String, String)] = []
        let rel = g.relacionados(de: f.ruta).map(\.ficha)
        switch f.tipo {
        case .contact, .organization:
            let servicios = rel.filter { $0.tipo == .opportunity && ["aceptada", "ganada"].contains(TextFolding.fold($0.estado ?? "")) }
                .flatMap { o in g.destinos(de: o.ruta, propiedad: "servicio").compactMap { g.ficha($0)?.nombre }.map { "\($0) (\(o.estado ?? ""))" } }
            out.append(("Servicios contratados", servicios.isEmpty ? "Ninguno" : servicios.joined(separator: ", "), "Sale de sus oportunidades"))
            if f.tipo == .contact {
                let recomendo = (g.entrantes[f.ruta] ?? []).filter { $0.propiedad == "referido_por" }.compactMap { g.ficha($0.origen)?.nombre }
                out.append(("Recomendó a", recomendo.isEmpty ? "Nadie" : recomendo.joined(separator: ", "), "Sale de las fichas que la citan en «Recomendado por»"))
            }
            if let ultima = ActividadDeFicha.leer(modelo.almacen.foto?.text(f.ruta) ?? "").first, let d = ultima.fecha {
                out.append(("Último contacto", FormatoFicha.fechaConDia(d, hoy: modelo.hoy), "Sale de la actividad"))
            }
        case .opportunity:
            if let r = ResumenDeFicha(ficha: f, grafo: g, hoy: modelo.hoy).protagonista, !r.valor.isEmpty {
                out.append(("Valor ponderado", r.valor, "Valor por probabilidad"))
            }
            let c = g.cobroConfirmado(oportunidad: f.ruta)
            out.append(("Cobro confirmado", c.confirmado ? "Sí" : "Aún no", c.confirmado ? "Sale de sus facturas y cobros" : c.motivo))
        case .project:
            if let p = ResumenDeFicha(ficha: f, grafo: g, hoy: modelo.hoy).protagonista {
                out.append(("Avance", p.valor, "Tareas hechas sobre las de su plan"))
            }
        default:
            break
        }
        if let alias = f.texto("aliases"), alias != "[]" { out.append(("Otros nombres", alias, "Se añade solo al renombrar")) }
        return out
    }

    private var enlazanAqui: some View {
        let enlaces = modelo.grafo?.enlazanDesdeTexto(destino) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Rotulo("Enlazan aquí desde el texto")
            if enlaces.isEmpty {
                Text("Ninguna nota enlaza aquí desde su texto.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(enlaces, id: \.self) { e in
                FilaLista(modelo.grafo?.ficha(e.origen)?.nombre ?? e.origen.stem, detalle: FormatoFicha.extracto(e.extracto), icono: "link",
                          accion: { modelo.sesion.navegar(a: modelo.sesion.destino(para: e.origen)) })
                    .vistaPrevia(ruta: e.origen, sesion: modelo.sesion)
            }
        }
    }

    private var mencionesSinEnlazar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rotulo("Menciones sin enlazar")
            if menciones.isEmpty {
                Text("Ninguna mención sin enlazar.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(menciones, id: \.self) { m in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(modelo.grafo?.ficha(m.origen)?.nombre ?? m.origen.stem).tlsTexto(TLSTipo.interfazFuerte)
                        Text("«\(FormatoFicha.extracto(m.extracto))»").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(3)
                    }
                    Spacer()
                    Button("Enlazar") { Task { await enlazar(m) } }
                        .tlsBoton(.secundario)
                        .disabled(!modelo.puedeEscribir)
                        .accessibilityLabel("Enlazar la mención en \(modelo.grafo?.ficha(m.origen)?.nombre ?? m.origen.stem)")
                }
            }
        }
    }

    private func enlazar(_ m: MencionSinEnlazar) async {
        guard EdicionRelaciones.comprobarEscritura(modelo.sesion), let foto = modelo.almacen.foto,
              let plan = SaludDeEnlaces(snapshot: foto).enlazar([m], estilo: .markdown, autor: modelo.sesion.autor) else { return }
        let nombre = modelo.grafo?.ficha(m.origen)?.nombre ?? m.origen.stem
        _ = try? await modelo.sesion.escribir(plan: plan, aviso: "Enlacé la mención en \(nombre)")
        modelo.almacen.invalidar()
    }
}

/// Una propiedad con su control. Guarda al confirmar (↩, al elegir o al soltar el foco); Esc cancela.
struct CampoPropiedad: View {
    let modelo: FichaModelo
    let ficha: FichaGrafo
    let propiedad: Property
    @State private var editando = false
    @State private var borrador = ""
    @State private var fecha = Date()
    @FocusState private var enfocado: Bool

    private var clave: String { propiedad.key }
    private var otra: VaultPath? { ficha.ruta == modelo.ruta ? nil : ficha.ruta }
    private var relacion: DefinicionRelacion? { EsquemaRelaciones.definicion(tipo: ficha.tipo, propiedad: clave) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(InspectorFicha.etiqueta(clave)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            control
        }
        .disabled(!modelo.puedeEscribir)
    }

    @ViewBuilder
    private var control: some View {
        if let def = relacion {
            relacionControl(def)
        } else if clave == "estado" {
            let opciones = modelo.opcionesEstado(ficha)
            Menu(ficha.estado.map(FormatoFicha.capital) ?? "Elegir") {
                ForEach(opciones) { o in
                    Button { Task { await modelo.cambiarEstado(o.titulo, de: otra) } } label: {
                        Text(o.titulo)
                        if let m = o.motivoDesactivado { Text(m) }
                    }
                    .disabled(o.motivoDesactivado != nil)
                }
            }
            .fixedSize()
            .accessibilityLabel("Estado: \(ficha.estado ?? "sin estado"). Cambiar")
        } else if clave == "responsable" {
            let opciones = modelo.grafo.map { Responsables.opciones(grafo: $0, persona: modelo.sesion.persona) } ?? []
            Menu(ficha.texto("responsable").map(Responsables.nombre(de:)) ?? "Elegir") {
                ForEach(opciones, id: \.id) { o in
                    Button(o.nombre) { Task { await modelo.cambiar("responsable", a: .text(o.id), aviso: "Responsable: \(o.nombre)", en: otra) } }
                }
                Divider()
                Button("Sin responsable") { Task { await modelo.cambiar("responsable", a: nil, en: otra) } }
            }
            .fixedSize()
            .help("Se guarda con un identificador que no cambia; aquí ves el nombre")
            .accessibilityLabel("Responsable: \(ficha.texto("responsable").map(Responsables.nombre(de:)) ?? "nadie"). Cambiar")
        } else if case .bool(let b) = propiedad.value {
            Toggle(InspectorFicha.etiqueta(clave), isOn: Binding(get: { b }, set: { v in Task { await modelo.cambiar(clave, a: .bool(v), en: otra) } }))
                .labelsHidden()
                .toggleStyle(.switch)
        } else if InspectorFicha.fechas.contains(clave) || (LocalDate(parsing: propiedad.value.displayText) != nil && propiedad.value.displayText.count == 10) {
            fechaControl
        } else if clave == "relacion" {
            opcionesMultiples(["cliente", "proveedor", "colaborador", "gestoría", "otro"])
        } else if case .raw = propiedad.value {
            Text("Se cambia en el texto (Fichero, ⌘E)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        } else {
            textoControl
        }
    }

    private var textoControl: some View {
        let actual: String = {
            if case .list(let l) = propiedad.value { return l.joined(separator: ", ") }
            return propiedad.value.displayText
        }()
        let numero = InspectorFicha.numeros.contains(clave) || { if case .number = propiedad.value { return true }; return false }()
        return Group {
            if editando {
                TextField(InspectorFicha.etiqueta(clave), text: $borrador)
                    .textFieldStyle(.roundedBorder)
                    .focused($enfocado)
                    .onSubmit { guardar(numero: numero) }
                    .onExitCommand { editando = false }
                    .onAppear { enfocado = true }
                if numero, !borrador.isEmpty, FormatoFicha.numero(borrador) == nil {
                    Text("Escribe un número (por ejemplo, 150 o 150,50).").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.mal.color)
                }
            } else {
                Button {
                    borrador = actual
                    editando = true
                } label: {
                    HStack(spacing: 4) {
                        Text(actual.isEmpty ? "Añadir" : mostrar(actual, numero: numero))
                            .tlsTexto(actual.isEmpty ? TLSTipo.interfazFuerte : TLSTipo.interfazMedia)
                            .foregroundStyle(actual.isEmpty ? TLSPaleta.enlace.color : TLSPaleta.texto.color)
                            .underline(actual.isEmpty)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: actual.isEmpty ? "plus" : "pencil").font(.system(size: 10)).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    .frame(minHeight: TLSAltura.objetivoMinimo)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actual.isEmpty ? "Añadir \(InspectorFicha.etiqueta(clave).lowercased())" : "\(InspectorFicha.etiqueta(clave)): \(actual). Cambiar")
            }
        }
    }

    private func mostrar(_ v: String, numero: Bool) -> String {
        if ["valor", "precio", "importe", "base", "total", "precio_congelado", "cuota_iva", "retencion"].contains(clave), let e = FormatoFicha.euros(v) { return e }
        return LinkParser.plainText(v)
    }

    private func guardar(numero: Bool) {
        editando = false
        let t = borrador.trimmingCharacters(in: .whitespacesAndNewlines)
        let valor: PropertyValue?
        if t.isEmpty {
            valor = nil
        } else if numero {
            guard let n = FormatoFicha.numero(t) else { return }
            valor = .number(NSDecimalNumber(decimal: n).stringValue)
        } else if case .list = propiedad.value {
            valor = .list(t.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        } else {
            valor = .text(t)
        }
        if valor == propiedad.value { return }
        Task { await modelo.cambiar(clave, a: valor, en: otra) }
    }

    private var fechaControl: some View {
        let actual = LocalDate(parsing: propiedad.value.displayText)
        return HStack {
            DatePicker(InspectorFicha.etiqueta(clave), selection: Binding(
                get: { actual?.date() ?? Date() },
                set: { d in
                    let nueva = LocalDate(date: d)
                    guard nueva != actual else { return }
                    Task { await modelo.cambiar(clave, a: .text(nueva.description), en: otra) }
                }), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .environment(\.locale, Locale(identifier: "es_ES"))
            if actual != nil {
                Button("Quitar") { Task { await modelo.cambiar(clave, a: nil, en: otra) } }
                    .tlsBoton(.discreto)
                    .accessibilityLabel("Quitar \(InspectorFicha.etiqueta(clave).lowercased())")
            }
        }
    }

    private func opcionesMultiples(_ opciones: [String]) -> some View {
        let actuales: [String] = {
            if case .list(let l) = propiedad.value { return l }
            return propiedad.value.displayText.isEmpty ? [] : [propiedad.value.displayText]
        }()
        return FlujoChips(espacio: 6) {
            ForEach(opciones, id: \.self) { o in
                let on = actuales.contains { TextFolding.fold($0) == TextFolding.fold(o) }
                Button(FormatoFicha.capital(o)) {
                    var nuevas = actuales
                    if on { nuevas.removeAll { TextFolding.fold($0) == TextFolding.fold(o) } } else { nuevas.append(o) }
                    Task { await modelo.cambiar(clave, a: .list(nuevas), en: otra) }
                }
                .tlsBoton(on ? .principal : .secundario, alto: TLSAltura.objetivoMinimo + 4)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func relacionControl(_ def: DefinicionRelacion) -> some View {
        let destinos = modelo.grafo?.destinos(de: ficha.ruta, propiedad: def.propiedad) ?? []
        FlujoChips(espacio: 6) {
            ForEach(destinos, id: \.self) { d in
                Button(modelo.grafo?.ficha(d)?.nombre ?? d.stem) { modelo.sesion.navegar(a: modelo.sesion.destino(para: d)) }
                    .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
                    .vistaPrevia(ruta: d, sesion: modelo.sesion)
            }
            if ficha.ruta == modelo.ruta {
                Button(destinos.isEmpty ? "Elegir \(def.etiqueta.lowercased())" : "Cambiar…") { modelo.abrirSelector(propiedad: def.propiedad, origen: "inspector") }
                    .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
                    .popover(item: Binding(get: { modelo.selector.flatMap { s in
                        if case .directo(_, let p) = s.modo, p == def.propiedad, s.origen == "inspector" { return s }
                        return nil } }, set: { if $0 == nil { modelo.selector = nil } }), arrowEdge: .leading) { p in
                        SelectorRelacion(peticion: p, sesion: modelo.sesion, almacen: modelo.almacen,
                                         alElegir: { d in Task { await modelo.elegido(d, en: p, navegar: nil) } },
                                         alQuitar: { Task { await modelo.quitar(propiedad: def.propiedad, destino: nil, guardaEn: modelo.ruta) } },
                                         alCrear: { nombre in
                                             if let c = p.crear {
                                                 Task { await EdicionRelaciones.crearYEnlazar(nombre: nombre, tipo: c.tipo, dueno: modelo.ruta, propiedad: def.propiedad,
                                                                                              sesion: modelo.sesion, almacen: modelo.almacen) }
                                             }
                                         },
                                         alListo: { m in Task { await modelo.listo(m, en: p) } })
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(def.etiqueta): \(destinos.compactMap { modelo.grafo?.ficha($0)?.nombre }.joined(separator: ", "))")
    }
}
