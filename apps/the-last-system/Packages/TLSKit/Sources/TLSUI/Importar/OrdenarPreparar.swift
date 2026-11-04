import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

// F3 · rol ordenar. Las pantallas de antes de aplicar: lo que hay, preparar por bloques, por programa y repetidos.
// Ninguna escribe en la carpeta: cambian la zona de preparación, que se guarda en el estado de la app.

// MARK: - Lo que hay

/// «1.240 ficheros · 310 solo en iCloud: los miro por su nombre», por programa y por tipo, y de dónde se trae.
public struct OrdenarLoQueHay: View {
    @Bindable var modelo: ModeloOrdenar

    public init(modelo: ModeloOrdenar) { self.modelo = modelo }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .loQueHay)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if let inv = modelo.inventario {
                Destacado(rotulo: "Lo que tienes") {
                    CifraDestacada(TLSFormat.cuenta(inv.elementos.count, "fichero", "ficheros"),
                                   contexto: contexto(inv))
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ordenar.inventario")
                HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                    TarjetaOrdenar("Por programa", icono: "square.stack.3d.up") {
                        ForEach(modelo.porHerramienta, id: \.0) { h, r in
                            FilaCifra(h.nombre, TLSFormat.entero(r.ficheros),
                                      detalle: r.soloEnICloud > 0 ? "\(TLSFormat.entero(r.soloEnICloud)) solo en iCloud" : nil)
                        }
                    }
                    TarjetaOrdenar("Por tipo", icono: "doc.on.doc") {
                        let tipos = modelo.porTipo
                        ForEach(tipos.prefix(7), id: \.0) { t, r in
                            FilaCifra(t.nombre, TLSFormat.entero(r.ficheros))
                        }
                        if tipos.count > 7 {
                            Text("Y \(TLSFormat.cuenta(tipos.count - 7, "tipo más", "tipos más"))")
                                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            fuentes
        }
        .accessibilityIdentifier("ordenar.loQueHay")
    }

    private func contexto(_ inv: InventarioImportacion) -> String {
        var partes: [String] = []
        if inv.soloEnICloud > 0 {
            partes.append("\(TLSFormat.entero(inv.soloEnICloud)) solo en iCloud: los miro por su nombre, sin descargarlos.")
        } else {
            partes.append("Todo está en este Mac.")
        }
        partes.append("Lo privado no lo miro.")
        return partes.joined(separator: " ")
    }

    private var fuentes: some View {
        TarjetaOrdenar("De dónde lo traigo", icono: "folder") {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Image(systemName: "building.2").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tu carpeta").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text("Lo ordeno dentro: cada cosa a su sitio, sin borrar nada.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            ForEach(modelo.externas, id: \.alias) { f in
                Divider().overlay(TLSPaleta.separador.color)
                HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                    Image(systemName: "folder.badge.plus").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.alias).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text("Copio lo que elijas; el original no cambia. " + TLSFormat.rutaCorta(f.raiz.path))
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .lineLimit(2)
                    }
                    Spacer(minLength: TLSEspacio.e8)
                    Button("Quitar") { Task { await modelo.quitarFuera(f.alias) } }
                        .tlsBoton(.enlace)
                        .disabled(modelo.trabajo != nil || modelo.cerrado)
                        .accessibilityLabel("Quitar \(f.alias)")
                }
            }
            if !modelo.cerrado {
                Divider().overlay(TLSPaleta.separador.color)
                HStack(spacing: TLSEspacio.e8) {
                    Button {
                        if let url = ElegirCarpeta.pedir(mensaje: "Elige una carpeta con más cosas de tu empresa (una exportación de Notion, una carpeta de Drive…). Solo la leo.") {
                            Task { await modelo.anadirFuera(url) }
                        }
                    } label: {
                        Label("Añadir una carpeta de fuera…", systemImage: "plus")
                    }
                    .tlsBoton(.secundario)
                    .disabled(modelo.trabajo != nil)
                    .accessibilityIdentifier("ordenar.anadirFuera")
                    Text("Una exportación de Notion o una carpeta de Drive, por ejemplo.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
    }
}

// MARK: - Preparar

/// La zona de preparación por bloques: destino editable, privado, dejar fuera, el motivo en una línea y, si hay
/// Claude, «Ayúdame con los dudosos» con consentimiento explícito.
public struct OrdenarPreparar: View {
    @Bindable var modelo: ModeloOrdenar
    @State private var abiertos: Set<String> = []
    @State private var pidiendoIA = false
    @State private var privadoPendiente: ResumenBloque?
    @State private var verEnSuSitio = false

    public init(modelo: ModeloOrdenar) { self.modelo = modelo }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .preparar)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if modelo.cerrado {
                AvisoEnLinea("Ya está aplicado. Para cambiar algo, deshazlo antes en «Comprobación».", estado: .atencion)
            }
            ayudaIA
            if modelo.privadosEnLaZona > 0 {
                HStack(spacing: TLSEspacio.e8) {
                    Image(systemName: "lock").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                    Text(TLSFormat.cuenta(modelo.privadosEnLaZona, "fichero privado", "ficheros privados")
                         + ": no se mueven, no se copian, no se enseñan y no los ve ningún asistente.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: TLSEspacio.e8)
                    Button("Volver a verlos") { modelo.volverAVerPrivados() }
                        .tlsBoton(.enlace)
                        .disabled(modelo.cerrado)
                }
            }
            if modelo.zona != nil {
                let bloques = modelo.bloques
                let porOrdenar = bloques.filter { !$0.enSuSitio }
                let enSuSitio = bloques.filter(\.enSuSitio)
                if bloques.isEmpty {
                    VacioExplicado(icono: "tray", titulo: "No hay nada que preparar",
                                   porQue: "Tu carpeta está vacía o todo lo que hay es privado.", compacto: true)
                } else {
                    if porOrdenar.isEmpty {
                        AvisoEnLinea("Todo está ya en su sitio: no hay nada que mover.", estado: .bien)
                    } else {
                        VStack(spacing: TLSEspacio.e8) {
                            ForEach(porOrdenar) { b in fila(b) }
                        }
                    }
                    if !enSuSitio.isEmpty { yaEnSuSitio(enSuSitio) }
                }
            }
        }
        .confirmationDialog(textoConsentimiento, isPresented: $pidiendoIA, titleVisibility: .visible) {
            Button("Sí, pregúntale") { Task { await modelo.ayudaConLosDudosos(consentimiento: true) } }
                .accessibilityIdentifier("ordenar.ia.si")
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text("Solo le envío el nombre, la carpeta y un trozo del texto de cada uno. Nunca lo privado ni lo que lleve claves. Lo que proponga lo ves aquí antes de aplicar.")
        }
        .confirmationDialog(privadoPendiente.map { "¿«\($0.bloque.nombre)» es privado?" } ?? "", isPresented: Binding(
            get: { privadoPendiente != nil }, set: { if !$0 { privadoPendiente = nil } }), titleVisibility: .visible) {
            Button("Sí, es privado") {
                if let b = privadoPendiente { modelo.marcarPrivado(bloque: b.id) }
                privadoPendiente = nil
            }
            Button("No", role: .cancel) { privadoPendiente = nil }
        } message: {
            Text("Lo privado no se mueve ni se copia, deja de verse aquí y no lo ve ningún asistente.")
        }
        .accessibilityIdentifier("ordenar.preparar")
    }

    private var textoConsentimiento: String {
        "¿Le pregunto a Claude por " + TLSFormat.cuenta(modelo.dudosos, "fichero dudoso", "ficheros dudosos") + "?"
    }

    @ViewBuilder
    private var ayudaIA: some View {
        if modelo.ejecutorIA != nil, modelo.dudosos > 0, !modelo.cerrado {
            HStack(spacing: TLSEspacio.e12) {
                Image(systemName: "sparkles").foregroundStyle(TLSPaleta.violetaTexto.color).accessibilityHidden(true)
                Text("Hay " + TLSFormat.cuenta(modelo.dudosos, "fichero dudoso", "ficheros dudosos")
                     + ". Si quieres, se lo pregunto a tu Claude Code.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TLSEspacio.e8)
                Button("Ayúdame con los dudosos") { pidiendoIA = true }
                    .tlsBoton(.secundario)
                    .disabled(modelo.trabajo != nil)
                    .accessibilityIdentifier("ordenar.ia")
            }
            .padding(TLSEspacio.e12)
            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.violetaSuave.color))
        }
        if let t = modelo.textoIA {
            AvisoEnLinea(t, estado: .bien)
        }
    }

    private func fila(_ b: ResumenBloque) -> some View {
        let externa = modelo.zona?.inventario.fuente(b.bloque.fuente)?.clase == .externa
        let todoFuera = b.fuera == b.bloque.claves.count
        return TarjetaOrdenar {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                Image(systemName: b.bloque.herramienta.simbolo)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 22)
                    .help(b.bloque.herramienta.nombre)
                    .accessibilityLabel(b.bloque.herramienta.nombre)
                Text(b.bloque.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                Text(recuento(b)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                Spacer(minLength: TLSEspacio.e8)
                if todoFuera {
                    Text(externa ? "No lo traigo" : "Se queda como está")
                        .tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else {
                    Text("Va a").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    MenuColeccion(actual: b.coleccion, titulo: "Adónde va «\(b.bloque.nombre)»") { c in
                        modelo.cambiarColeccion(bloque: b.id, a: c)
                    }
                    .disabled(modelo.cerrado)
                    pastilla(b)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e12) {
                Text(todoFuera ? " " : "Por qué: " + b.motivo)
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                    .help(b.motivo)
                    .padding(.leading, 34)
                Spacer(minLength: TLSEspacio.e8)
                Button(abiertos.contains(b.id) ? "Ocultar" : "Ver los ficheros") {
                    if abiertos.contains(b.id) { abiertos.remove(b.id) } else { abiertos.insert(b.id) }
                }
                .tlsBoton(.enlace)
                .accessibilityIdentifier("ordenar.bloque.ver.\(b.id)")
                Toggle(externa ? "No traerlo" : "Dejarlo como está", isOn: Binding(
                    get: { todoFuera }, set: { modelo.dejarFuera(bloque: b.id, $0) }))
                    .toggleStyle(.checkbox)
                    .disabled(modelo.cerrado)
                    .accessibilityIdentifier("ordenar.bloque.fuera.\(b.id)")
                Button("Es privado…") { privadoPendiente = b }
                    .tlsBoton(.enlace)
                    .disabled(modelo.cerrado)
                    .accessibilityIdentifier("ordenar.bloque.privado.\(b.id)")
            }
            if abiertos.contains(b.id) {
                ficheros(b, externa: externa)
            }
        }
        .accessibilityIdentifier("ordenar.bloque.\(b.id)")
    }

    /// Lo que ya está en su sitio, plegado: no hay que decidir nada (como mucho, se completan sus fichas).
    private func yaEnSuSitio(_ bloques: [ResumenBloque]) -> some View {
        let n = bloques.reduce(0) { $0 + $1.bloque.claves.count }
        return TarjetaOrdenar("Ya en su sitio · " + TLSFormat.cuenta(n, "fichero", "ficheros"), icono: "checkmark.circle") {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e12) {
                Text(bloques.map(\.bloque.nombre).joined(separator: ", "))
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(2)
                Spacer(minLength: TLSEspacio.e8)
                Button(verEnSuSitio ? "Ocultar" : "Ver") { verEnSuSitio.toggle() }
                    .tlsBoton(.enlace)
                    .accessibilityIdentifier("ordenar.enSuSitio.ver")
            }
            Text("No muevo nada de aquí; como mucho, completo las fichas a las que les falta su tipo.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            if verEnSuSitio {
                VStack(spacing: TLSEspacio.e8) {
                    ForEach(bloques) { b in fila(b) }
                }
            }
        }
        .accessibilityIdentifier("ordenar.enSuSitio")
    }

    private func recuento(_ b: ResumenBloque) -> String {
        var s = TLSFormat.cuenta(b.bloque.claves.count, "fichero", "ficheros")
        if b.bloque.soloEnICloud > 0 { s += " · \(TLSFormat.entero(b.bloque.soloEnICloud)) solo en iCloud" }
        if b.fuera > 0, b.fuera < b.bloque.claves.count { s += " · \(TLSFormat.entero(b.fuera)) fuera" }
        return s
    }

    @ViewBuilder
    private func pastilla(_ b: ResumenBloque) -> some View {
        if b.elegidoPorTi {
            PastillaEstado(.bien, palabra: "Lo has elegido tú")
        } else if b.segunClaude {
            PastillaEstado(.bien, palabra: "Según Claude")
        } else if b.dudoso {
            PastillaEstado(.atencion, palabra: b.dudosos == 1 ? "1 dudoso" : "\(TLSFormat.entero(b.dudosos)) dudosos")
        } else {
            PastillaEstado(.bien, palabra: "Sin dudas")
        }
    }

    private func ficheros(_ b: ResumenBloque, externa: Bool) -> some View {
        let filas = modelo.ficheros(de: b.id)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(filas.prefix(200)) { f in
                Divider().overlay(TLSPaleta.separador.color)
                HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.elemento.nombreLimpio).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                        Text(detalle(f, externa: externa))
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                            .help(f.propuesta?.motivo ?? "")
                    }
                    Spacer(minLength: TLSEspacio.e8)
                    if !f.fuera, !f.elemento.soloEnICloud, !f.elemento.sensible {
                        MenuColeccion(actual: f.propuesta?.coleccion, titulo: "Adónde va «\(f.elemento.nombreLimpio)»") { c in
                            modelo.cambiarColeccion(fichero: f.id, a: c)
                        }
                        .disabled(modelo.cerrado)
                    }
                    Toggle(externa ? "No traer" : "Dejar", isOn: Binding(get: { f.fuera }, set: { modelo.dejarFuera(fichero: f.id, $0) }))
                        .toggleStyle(.checkbox)
                        .disabled(modelo.cerrado)
                        .help(externa ? "No traerlo" : "Dejarlo donde está")
                    Button {
                        modelo.marcarPrivado(fichero: f.id)
                    } label: {
                        Image(systemName: "lock")
                    }
                    .buttonStyle(.plain)
                    .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .disabled(modelo.cerrado)
                    .help("Es privado: no se mueve ni se enseña")
                    .accessibilityLabel("Marcar «\(f.elemento.nombreLimpio)» como privado")
                }
                .padding(.vertical, 6)
            }
            if filas.count > 200 {
                Text("Y \(TLSFormat.cuenta(filas.count - 200, "fichero más", "ficheros más")) en este bloque.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.top, 6)
            }
        }
    }

    private func detalle(_ f: FilaFichero, externa: Bool) -> String {
        if f.fuera { return externa ? "No lo traigo" : "Se queda donde está" }
        if f.elemento.sensible { return "Parece llevar claves o contraseñas: no lo toco" }
        if f.elemento.soloEnICloud { return externa ? "Solo en iCloud: no lo traigo para no descargarlo" : "Solo en iCloud: se queda donde está" }
        guard let p = f.propuesta else { return "" }
        if p.enSuSitio { return "Ya está en su sitio · " + p.motivo }
        let destino = p.destino?.parent.map(ModeloOrdenar.rutaLegible) ?? ""
        return (destino.isEmpty ? "" : "A \(destino) · ") + p.motivo
    }
}

// MARK: - Por programa

/// «Todo / lo activo / nada» por programa, con fecha de corte, y las tareas de Multica si se usa.
public struct OrdenarPorPrograma: View {
    @Bindable var modelo: ModeloOrdenar
    let multica: Bool
    @State private var hojaMultica = false

    public init(modelo: ModeloOrdenar, multica: Bool = MulticaCLI.localizar() != nil) {
        self.modelo = modelo
        self.multica = multica
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .porPrograma)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if modelo.cerrado {
                AvisoEnLinea("Ya está aplicado. Para cambiar algo, deshazlo antes en «Comprobación».", estado: .atencion)
            }
            if let zona = modelo.zona {
                ForEach(zona.herramientas, id: \.self) { h in fila(h, zona: zona) }
            }
            if multica {
                TarjetaOrdenar("Tareas de Multica", icono: "checklist") {
                    Text("Si usas Multica, traigo sus tareas abiertas como fichas de tarea. Las que parecen personales salen desmarcadas y te digo por qué. Allí no cambio nada.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Importar de Multica…") { hojaMultica = true }
                        .tlsBoton(.secundario)
                        .disabled(modelo.motivoNoEscribir != nil)
                        .accessibilityIdentifier("ordenar.multica")
                }
            }
        }
        .sheet(isPresented: $hojaMultica) {
            ImportarMulticaHoja(acceso: modelo.acceso)
        }
        .accessibilityIdentifier("ordenar.porPrograma")
    }

    private func fila(_ h: HerramientaOrigen, zona: ZonaPreparacion) -> some View {
        let alcance = zona.alcance(h)
        let n = zona.visibles.filter { $0.herramienta == h }.count
        let externa = zona.visibles.contains { $0.herramienta == h && zona.clase($0) == .externa }
        let seleccion = Binding<String>(
            get: {
                switch alcance {
                case .todo: "todo"
                case .loActivo: "activo"
                case .nada: "nada"
                }
            },
            set: { v in
                switch v {
                case "activo":
                    if case .loActivo = alcance { return }
                    modelo.fijarAlcance(h, .loActivo(desde: modelo.corteSugerido))
                case "nada": modelo.fijarAlcance(h, .nada)
                default: modelo.fijarAlcance(h, .todo)
                }
            })
        return TarjetaOrdenar {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                Image(systemName: h.simbolo).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(TLSFormat.cuenta(n, "fichero", "ficheros")).tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Spacer(minLength: TLSEspacio.e8)
                Picker("Qué traigo de \(h.nombre)", selection: seleccion) {
                    Text("Todo").tag("todo")
                    Text("Lo activo").tag("activo")
                    Text("Nada").tag("nada")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .disabled(modelo.cerrado)
                .accessibilityIdentifier("ordenar.programa.\(h.rawValue)")
            }
            HStack(spacing: TLSEspacio.e8) {
                Text(explicacion(alcance, externa: externa, ordenada: h == .ordenada))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TLSEspacio.e8)
                if case .loActivo(let desde) = alcance {
                    DatePicker("Desde", selection: Binding(
                        get: { desde.date() },
                        set: { modelo.fijarAlcance(h, .loActivo(desde: LocalDate(date: $0))) }),
                               displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "es_ES"))
                        .fixedSize()
                        .disabled(modelo.cerrado)
                        .accessibilityLabel("Fecha de corte de \(h.nombre)")
                }
            }
        }
    }

    private func explicacion(_ a: AlcanceImportacion, externa: Bool, ordenada: Bool) -> String {
        if ordenada {
            switch a {
            case .todo: return "Ya está en su sitio: solo completo las fichas que no dicen su tipo."
            case .loActivo(let d): return "Lo anterior al \(d.textoCorto) va al Archivo como antecedente; lo demás se queda donde está."
            case .nada: return "No lo toco: ni lo muevo ni completo nada."
            }
        }
        switch a {
        case .todo: return externa ? "Traigo todo a su sitio." : "Todo va a su sitio."
        case .loActivo(let d):
            return "Lo que es del \(d.textoCorto) en adelante va a su sitio; lo anterior, al Archivo como antecedente."
        case .nada: return externa ? "No traigo nada de aquí." : "Se queda donde está, sin cambios."
        }
    }
}

// MARK: - Repetidos

/// Repetidos: «Quedarme con…» en cada grupo. Los iguales ya llevan uno elegido; los de nombre parecido, ninguno.
public struct OrdenarRepetidos: View {
    @Bindable var modelo: ModeloOrdenar

    public init(modelo: ModeloOrdenar) { self.modelo = modelo }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .repetidos)
            AvisosOrdenar(modelo: modelo)
            if modelo.cerrado {
                AvisoEnLinea("Ya está aplicado. Para cambiar algo, deshazlo antes en «Comprobación».", estado: .atencion)
            }
            if let zona = modelo.zona {
                let grupos = zona.duplicados.filter { g in g.claves.allSatisfy { zona.inventario.elemento($0) != nil } }
                if grupos.isEmpty {
                    VacioExplicado(icono: "checkmark.circle", titulo: "No hay repetidos",
                                   porQue: "No he encontrado dos ficheros iguales ni nombres que parezcan copias.", compacto: true)
                } else {
                    Text(TLSFormat.cuenta(grupos.count, "grupo", "grupos") + " · los iguales ya tienen uno elegido; cámbialo si prefieres otro.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    ForEach(grupos) { g in grupo(g, zona: zona) }
                }
            }
        }
        .accessibilityIdentifier("ordenar.repetidos")
    }

    private func grupo(_ g: ZonaPreparacion.GrupoDuplicados, zona: ZonaPreparacion) -> some View {
        TarjetaOrdenar(g.clase == .identicos ? "Iguales" : "Nombre parecido", icono: g.clase == .identicos ? "doc.on.doc" : "textformat") {
            if g.clase == .nombreParecido, g.seQueda == nil {
                Text("Su contenido es distinto: por ahora se quedan todos.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(g.claves, id: \.self) { c in
                if let e = zona.inventario.elemento(c) {
                    let queda = g.seQueda == c
                    let externa = zona.clase(e) == .externa
                    HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.nombreLimpio).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                            Text(donde(e, externa: externa))
                                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                        }
                        Spacer(minLength: TLSEspacio.e8)
                        if queda {
                            PastillaEstado(.bien, palabra: "Me quedo con este")
                        } else {
                            if g.seQueda != nil {
                                Text(externa ? "No se trae" : "Al Archivo")
                                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            }
                            Button("Quedarme con este") { modelo.quedarseCon(c, enGrupo: g.id) }
                                .tlsBoton(.secundario)
                                .disabled(modelo.cerrado)
                                .accessibilityLabel("Quedarme con «\(e.nombreLimpio)» de \(donde(e, externa: externa))")
                        }
                    }
                }
            }
        }
    }

    private func donde(_ e: ElementoInventario, externa: Bool) -> String {
        var partes: [String] = []
        let carpeta = e.ruta.parent.map(ModeloOrdenar.rutaLegible) ?? ""
        partes.append(externa ? "\(e.fuente)\(carpeta.isEmpty ? "" : " › " + carpeta)" : (carpeta.isEmpty ? "En la raíz de tu carpeta" : carpeta))
        if let t = e.tamano { partes.append(TLSFormat.tamano(t)) }
        if let m = e.modificado { partes.append(TLSFormat.fecha(m)) }
        return partes.joined(separator: " · ")
    }
}
