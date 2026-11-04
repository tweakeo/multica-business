import SwiftUI
import TLSCore
import TLSDesign

// Hojas de la Carpeta: «Nueva…», «Renombrar», «Mover» y el arreglo de lo movido fuera de la app. Ninguna escribe
// hasta que la persona confirma; todo pasa por `CarpetaModelo` (CommandBus, con Deshacer).

/// Marco común de las hojas: título, subtítulo, contenido y botones abajo (Cancelar · acción principal).
struct MarcoHoja<Contenido: View, Botones: View>: View {
    let titulo: String
    let subtitulo: String?
    let contenido: Contenido
    let botones: Botones

    init(_ titulo: String, subtitulo: String? = nil, @ViewBuilder contenido: () -> Contenido, @ViewBuilder botones: () -> Botones) {
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.contenido = contenido()
        self.botones = botones()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .tlsTexto(TLSTipo.tituloSeccion)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                if let subtitulo {
                    Text(subtitulo)
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: TLSEspacio.e8) {
                Spacer()
                botones
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 600)
        .frame(minHeight: 420, idealHeight: 540, maxHeight: 720)
        .background(TLSPaleta.superficieElevada.color)
    }
}

// MARK: - Nueva…

/// «Nueva…»: elegir qué crear (plantillas de esta carpeta, de la ficha elegida o una nota en blanco),
/// responder sus preguntas y crearla. Si la nota de nombre fijo ya existe, «Completar la que hay».
struct HojaNueva: View {
    let modelo: CarpetaModelo
    let seleccion: VaultPath?
    let alCrear: (Destino) -> Void
    @Environment(\.dismiss) private var cerrar
    @State private var opciones: [OpcionNueva]?
    @State private var elegida: OpcionNueva?
    @State private var valores: [String: String] = [:]
    @State private var error: String?
    @State private var yaExiste: VaultPath?
    @State private var trabajando = false
    @FocusState private var primerCampo: Bool

    var body: some View {
        MarcoHoja(elegida.map { "Nueva: \($0.titulo)" } ?? "Nueva…",
                  subtitulo: elegida?.detalle ?? "En «\(modelo.titulo)»") {
            if let elegida {
                formulario(elegida)
            } else if let opciones {
                listaOpciones(opciones)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } botones: {
            if elegida != nil {
                Button("Atrás") { elegida = nil; error = nil; yaExiste = nil }.tlsBoton(.secundario)
            }
            Button("Cancelar") { cerrar() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
            if let yaExiste, let elegida {
                Button("Abrir la que hay") {
                    cerrar()
                    alCrear(modelo.sesion.destino(para: yaExiste))
                }
                .tlsBoton(.secundario)
                Button("Completar la que hay") {
                    Task {
                        trabajando = true
                        error = await modelo.completar(yaExiste, con: elegida)
                        trabajando = false
                        if error == nil { cerrar() }
                    }
                }
                .tlsBoton(.principal)
                .keyboardShortcut(.defaultAction)
                .disabled(trabajando)
            } else if let elegida {
                Button("Crear") { crear(elegida) }
                    .tlsBoton(.principal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trabajando || motivoNoCrear(elegida) != nil)
                    .help(motivoNoCrear(elegida) ?? "Crear la nota")
            }
        }
        .task { opciones = await modelo.opcionesNueva(seleccion: seleccion) }
    }

    private func listaOpciones(_ opciones: [OpcionNueva]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TLSEspacio.e4) {
                let deFicha = opciones.filter { if case .ficha = $0.origen { return true }; return false }
                let deCarpeta = opciones.filter { $0.origen == .carpeta }
                let blanco = opciones.filter { $0.origen == .notaEnBlanco }
                if !deFicha.isEmpty {
                    Rotulo(deFicha[0].detalle).padding(.top, 4)
                    ForEach(deFicha) { fila($0) }
                }
                if !deCarpeta.isEmpty {
                    Rotulo("En esta carpeta").padding(.top, 8)
                    ForEach(deCarpeta) { fila($0) }
                }
                if deFicha.isEmpty && deCarpeta.isEmpty {
                    Text("Esta carpeta no tiene plantillas propias. Puedes crear una nota en blanco.")
                        .tlsTexto(TLSTipo.interfaz)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .padding(.vertical, 4)
                }
                Rotulo("Sin plantilla").padding(.top, 8)
                ForEach(blanco) { fila($0) }
            }
        }
    }

    private func fila(_ o: OpcionNueva) -> some View {
        FilaLista(o.titulo, detalle: o.preguntas.isEmpty ? o.detalle : "Pide: " + o.preguntas.map { PlantillasCarpeta.etiqueta($0, tipo: o.tipo) }.joined(separator: ", "),
                  icono: o.simbolo, etiquetaAccesible: "\(o.titulo), \(o.detalle)") {
            elegir(o)
        } derecha: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
        }
    }

    private func elegir(_ o: OpcionNueva) {
        Task {
            valores = await modelo.valoresIniciales(para: o)
            error = nil
            yaExiste = nil
            elegida = o
            if o.preguntas.isEmpty { crear(o) } else { primerCampo = true }
        }
    }

    private func formulario(_ o: OpcionNueva) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ForEach(Array(o.preguntas.enumerated()), id: \.element) { i, p in
                VStack(alignment: .leading, spacing: 4) {
                    Text(PlantillasCarpeta.etiqueta(p, tipo: o.tipo))
                        .tlsTexto(TLSTipo.interfazMedia)
                        .foregroundStyle(TLSPaleta.texto.color)
                    TextField(PlantillasCarpeta.etiqueta(p, tipo: o.tipo), text: Binding(get: { valores[p] ?? "" }, set: { valores[p] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .tlsTexto(TLSTipo.interfaz)
                        .focused($primerCampo, equals: i == 0)
                        .onSubmit { if motivoNoCrear(o) == nil, yaExiste == nil { crear(o) } }
                        .accessibilityLabel(PlantillasCarpeta.etiqueta(p, tipo: o.tipo))
                }
            }
            if o.preguntas.isEmpty {
                Text("No hace falta ningún dato: pulsa Crear.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if let yaExiste {
                Label("Ya existe «\(yaExiste.stem)». Puedes completarla con la plantilla: solo se añade lo que le falta.",
                      systemImage: TLSEstado.atencion.simbolo)
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Label(error, systemImage: TLSEstado.mal.simbolo)
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSEstado.mal.color.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if trabajando { ProgressView().controlSize(.small) }
        }
    }

    private func motivoNoCrear(_ o: OpcionNueva) -> String? {
        if o.preguntas.contains("titulo"), (valores["titulo"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            return "Escribe un título"
        }
        return nil
    }

    private func crear(_ o: OpcionNueva) {
        guard !trabajando else { return }
        trabajando = true
        Task {
            let r = await modelo.crear(o, valores: valores)
            trabajando = false
            switch r {
            case .hecho(_, let destino):
                cerrar()
                alCrear(destino)
            case .yaExiste(let ruta):
                yaExiste = ruta
            case .error(let t):
                error = t
            }
        }
    }
}

// MARK: - Renombrar

/// «Renombrar»: el nombre nuevo y, mientras se escribe, los enlaces que se actualizarán (antes → después).
struct HojaRenombrar: View {
    let modelo: CarpetaModelo
    let ruta: VaultPath
    /// Nombre con el que abre (por defecto, el de ahora).
    var nombrePropuesto: String?
    @Environment(\.dismiss) private var cerrar
    @State private var nombre = ""
    @State private var previa: RefactorPreview?
    @State private var error: String?
    @State private var calculando = false
    @State private var trabajando = false
    @FocusState private var enCampo: Bool

    private var esCarpeta: Bool { modelo.fila(ruta)?.esCarpeta ?? false }
    /// Las notas y los ficheros se renombran sin la extensión (se conserva).
    private var nombreActual: String { esCarpeta ? ruta.name : ruta.stem }

    var body: some View {
        MarcoHoja("Renombrar «\(modelo.fila(ruta)?.titulo ?? nombreActual)»",
                  subtitulo: "Los enlaces que apuntan aquí se actualizan solos. Se puede deshacer.") {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nombre nuevo").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                    HStack(spacing: TLSEspacio.e8) {
                        TextField("Nombre nuevo", text: $nombre)
                            .textFieldStyle(.roundedBorder)
                            .tlsTexto(TLSTipo.interfaz)
                            .focused($enCampo)
                            .onSubmit { confirmar() }
                            .accessibilityLabel("Nombre nuevo")
                        if !esCarpeta, !ruta.ext.isEmpty {
                            Text(".\(ruta.ext)").tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                    }
                }
                VistaPreviaCambios(previa: previa, error: error, calculando: calculando, titulo: { modelo.sesion.titulo(de: $0) })
            }
        } botones: {
            Button("Cancelar") { cerrar() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
            Button("Renombrar") { confirmar() }
                .tlsBoton(.principal)
                .keyboardShortcut(.defaultAction)
                .disabled(!puedeConfirmar)
        }
        .onAppear {
            nombre = nombrePropuesto ?? nombreActual
            enCampo = true
        }
        .task(id: nombre) { await recalcular() }
    }

    private var puedeConfirmar: Bool {
        !trabajando && !calculando && error == nil && (previa?.esSeguro ?? false)
    }

    private func recalcular() async {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard n != nombreActual, !n.isEmpty else { previa = nil; error = nil; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        calculando = true
        defer { calculando = false }
        do {
            let p = try await modelo.prepararRenombrar(ruta, a: n)
            guard !Task.isCancelled else { return }
            previa = p
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            previa = nil
            self.error = (error as? LocalizedError)?.errorDescription ?? "No se puede usar ese nombre."
        }
    }

    private func confirmar() {
        guard puedeConfirmar, let previa else { return }
        trabajando = true
        let n = nombre.trimmingCharacters(in: .whitespaces)
        Task {
            let r = await modelo.aplicar(previa) { try await modelo.prepararRenombrar(ruta, a: n, fresca: true) }
            trabajando = false
            switch r {
            case .hecho: cerrar()
            case .enRiesgo(let k): error = RefactorError.enlacesEnRiesgo(k).errorDescription
            case .error(let t): error = t
            }
        }
    }
}

// MARK: - Mover

/// «Mover a…»: elegir la carpeta de destino y ver los enlaces que se actualizan antes de mover.
struct HojaMover: View {
    let modelo: CarpetaModelo
    let rutas: [VaultPath]
    let destinoInicial: VaultPath?
    @Environment(\.dismiss) private var cerrar
    @State private var carpetas: [VaultPath] = []
    @State private var filtro = ""
    @State private var destino: VaultPath?
    @State private var previa: RefactorPreview?
    @State private var error: String?
    @State private var calculando = false
    @State private var trabajando = false

    private var titulo: String {
        rutas.count == 1 ? "Mover «\(modelo.fila(rutas[0])?.titulo ?? rutas[0].stem)»" : "Mover \(rutas.count) elementos"
    }

    var body: some View {
        MarcoHoja(titulo, subtitulo: destino.map { "A «\(Self.nombre($0))»" } ?? "Elige la carpeta de destino") {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                if destinoInicial == nil {
                    TextField("Buscar carpeta", text: $filtro)
                        .textFieldStyle(.roundedBorder)
                        .tlsTexto(TLSTipo.interfaz)
                        .accessibilityLabel("Buscar carpeta")
                    List(selection: $destino) {
                        ForEach(filtradas, id: \.self) { c in
                            HStack(spacing: TLSEspacio.e8) {
                                Image(systemName: "folder").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                                Text(Self.nombre(c)).tlsTexto(TLSTipo.interfaz).lineLimit(1).truncationMode(.middle)
                            }
                            .frame(minHeight: TLSAltura.objetivoMinimo)
                            .tag(c)
                            .accessibilityLabel(Self.nombre(c))
                        }
                    }
                    .listStyle(.bordered)
                    .frame(minHeight: 160, maxHeight: 220)
                }
                if let destino, let aviso = modelo.avisoSalePrivado(rutas, a: destino) {
                    Label(aviso, systemImage: "lock.open")
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Aviso: \(aviso)")
                }
                VistaPreviaCambios(previa: previa, error: error, calculando: calculando, titulo: { modelo.sesion.titulo(de: $0) })
            }
        } botones: {
            Button("Cancelar") { cerrar() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
            Button("Mover") { confirmar() }
                .tlsBoton(.principal)
                .keyboardShortcut(.defaultAction)
                .disabled(trabajando || calculando || error != nil || !(previa?.esSeguro ?? false))
        }
        .task {
            carpetas = await modelo.carpetasDestino(moviendo: rutas)
            if let destinoInicial { destino = destinoInicial }
        }
        .task(id: destino?.raw ?? "\u{0}") { await recalcular() }
    }

    static func nombre(_ c: VaultPath) -> String {
        c.isRoot ? "Carpeta de tu empresa" : c.components.joined(separator: " › ")
    }

    private var filtradas: [VaultPath] {
        let f = filtro.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return carpetas }
        let clave = TextFolding.nameKey(f)
        return carpetas.filter { TextFolding.nameKey($0.raw).contains(clave) }
    }

    private func recalcular() async {
        guard let destino else { previa = nil; error = nil; return }
        calculando = true
        defer { calculando = false }
        do {
            previa = try await modelo.prepararMover(rutas, a: destino)
            error = nil
        } catch {
            previa = nil
            self.error = (error as? LocalizedError)?.errorDescription ?? "No se puede mover ahí."
        }
    }

    private func confirmar() {
        guard let previa, let destino else { return }
        trabajando = true
        Task {
            let r = await modelo.aplicar(previa) { try await modelo.prepararMover(rutas, a: destino, fresca: true) }
            trabajando = false
            switch r {
            case .hecho: cerrar()
            case .enRiesgo(let k): error = RefactorError.enlacesEnRiesgo(k).errorDescription
            case .error(let t): error = t
            }
        }
    }
}

// MARK: - Arreglo de lo movido fuera

/// Lo que cambia al arreglar los enlaces de lo movido fuera de la app.
struct HojaArreglo: View {
    let modelo: CarpetaModelo
    @Environment(\.dismiss) private var cerrar
    @State private var trabajando = false
    @State private var error: String?

    var body: some View {
        MarcoHoja("Arreglar los enlaces", subtitulo: "Solo cambia hacia dónde apuntan los enlaces; nada se mueve. Se puede deshacer.") {
            VistaPreviaCambios(previa: modelo.arreglo, error: error, calculando: false, titulo: { modelo.sesion.titulo(de: $0) })
        } botones: {
            Button("Cancelar") { cerrar() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
            Button("Arreglar los enlaces") {
                trabajando = true
                Task {
                    let r = await modelo.arreglarMovimientos()
                    trabajando = false
                    if case .hecho = r { cerrar() } else if case .error(let t) = r { error = t }
                }
            }
            .tlsBoton(.principal)
            .keyboardShortcut(.defaultAction)
            .disabled(trabajando || modelo.arreglo == nil)
        }
    }
}

// MARK: - Vista previa de los cambios

/// Qué cambia en un renombrado o movimiento: el resumen, los avisos y, por fichero, cada enlace antes y después.
struct VistaPreviaCambios: View {
    let previa: RefactorPreview?
    let error: String?
    let calculando: Bool
    /// Título de una nota (del índice) para la lista; si no, el nombre del fichero.
    var titulo: ((VaultPath) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            if let error {
                Label(error, systemImage: TLSEstado.mal.simbolo)
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSEstado.mal.color.color)
                    .fixedSize(horizontal: false, vertical: true)
            } else if calculando && previa == nil {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Buscando los enlaces que cambian…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            } else if let previa {
                Text(previa.resumen)
                    .tlsTexto(TLSTipo.interfazMedia)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                avisos(previa)
                lista(previa)
            }
        }
    }

    @ViewBuilder
    private func avisos(_ p: RefactorPreview) -> some View {
        if !p.problemas.isEmpty {
            aviso(.mal, RefactorError.enlacesEnRiesgo(p.problemas.count).errorDescription ?? "")
            ForEach(Array(p.problemas.prefix(5).enumerated()), id: \.offset) { _, prob in
                Text("\(prob.ruta.stem), línea \(prob.linea): \(prob.motivo)")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.leading, 24)
            }
        }
        if !p.sinDescargar.isEmpty {
            aviso(.atencion, p.sinDescargar.count == 1
                  ? "Una nota está solo en iCloud y no la he podido revisar: si enlaza aquí, seguirá apuntando al nombre de antes."
                  : "\(p.sinDescargar.count) notas están solo en iCloud y no las he podido revisar: si enlazan aquí, seguirán apuntando al nombre de antes.")
        }
        if !p.enConflicto.isEmpty {
            aviso(.atencion, p.enConflicto.count == 1
                  ? "Un fichero que cambia tiene un conflicto pendiente en Revisar."
                  : "\(p.enConflicto.count) ficheros que cambian tienen un conflicto pendiente en Revisar.")
        }
        if !p.noEditables.isEmpty {
            aviso(.sinDato, p.noEditables.count == 1
                  ? "Un fichero de texto no se puede leer y no se revisa."
                  : "\(p.noEditables.count) ficheros de texto no se pueden leer y no se revisan.")
        }
    }

    private func aviso(_ estado: TLSEstado, _ texto: String) -> some View {
        Label {
            Text(texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: estado.simbolo).foregroundStyle(estado.color.color).accessibilityLabel(estado.palabra)
        }
    }

    private func lista(_ p: RefactorPreview) -> some View {
        let conEnlaces = p.cambios.filter { !$0.enlaces.isEmpty || $0.alias != nil }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: TLSEspacio.e8) {
                ForEach(Array(conEnlaces.prefix(60).enumerated()), id: \.offset) { _, cambio in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            if let alias = cambio.alias {
                                Text("Guarda «\(alias)» como otro nombre")
                                    .tlsTexto(TLSTipo.secundario)
                                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                            }
                            ForEach(Array(cambio.enlaces.prefix(20).enumerated()), id: \.offset) { _, e in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.lugar(e)).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                                    Text(e.antes).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                                        .strikethrough(true, color: TLSPaleta.textoSecundario.color)
                                        .lineLimit(2)
                                    Text(e.despues).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(Self.lugar(e)): antes \(e.antes), después \(e.despues)")
                            }
                            if cambio.enlaces.count > 20 {
                                Text("y \(cambio.enlaces.count - 20) más").tlsTexto(TLSTipo.secundario)
                                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.top, 4)
                    } label: {
                        HStack(spacing: TLSEspacio.e8) {
                            Text(titulo?(cambio.ruta) ?? (cambio.rutaFinal.ext == "md" ? cambio.rutaFinal.stem : cambio.rutaFinal.name))
                                .tlsTexto(TLSTipo.interfazFuerte)
                                .foregroundStyle(TLSPaleta.texto.color)
                                .lineLimit(1)
                                .layoutPriority(1)
                            Text(cambio.enlaces.count == 1 ? "1 enlace" : "\(cambio.enlaces.count) enlaces")
                                .tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                                .fixedSize()
                            Text(cambio.rutaFinal.carpetaVisible)
                                .tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                }
                if conEnlaces.count > 60 {
                    Text("y \(conEnlaces.count - 60) ficheros más").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            .padding(TLSEspacio.e12)
        }
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .opacity(conEnlaces.isEmpty ? 0 : 1)
    }

    static func lugar(_ e: CambioDeEnlace) -> String {
        switch e.lugar {
        case .cuerpo: "Línea \(e.linea)"
        case .propiedad(let k): "Propiedad «\(k)» · línea \(e.linea)"
        case .columna(let c): "Columna «\(c)» · fila \(e.linea)"
        case .ajustes: "Ajustes de la carpeta"
        }
    }
}
