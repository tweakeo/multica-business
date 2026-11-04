import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

// F3 · rol ordenar. Las pantallas de aplicar y después: vista previa («Mover 312 · Propiedades a 140 · Archivar 28 ·
// No se borra nada»), comprobación («312 de 312 (recuento + SHA-256)») con «Deshacer», calidad con «Crear tarea» o
// «Ignorar», completar las fichas (carpeta ya organizada) y los movimientos del banco heredados.

// MARK: - Vista previa

public struct OrdenarVistaPrevia: View {
    @Bindable var modelo: ModeloOrdenar
    @Environment(\.ordenarAplicarEnElPie) private var aplicarEnElPie

    public init(modelo: ModeloOrdenar) { self.modelo = modelo }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .vistaPrevia)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if let hecho = modelo.hecho {
                AvisoEnLinea("Ya está aplicado: \(hecho.resumen). Lo tienes comprobado en la pantalla siguiente.", estado: .bien)
            } else if let vista = modelo.vista {
                ResumenVistaPrevia(modelo: modelo, vista: vista)
                if !aplicarEnElPie { pie(vista) }
            } else if modelo.trabajo == nil {
                VacioExplicado(icono: "eye", titulo: "Aún no hay vista previa",
                               porQue: "La preparo con lo que has decidido. Solo leo: no cambio nada.",
                               accion: "Preparar la vista previa", alPulsar: { Task { await modelo.prepararVista() } },
                               compacto: true)
            }
        }
        .accessibilityIdentifier("ordenar.vistaPrevia")
    }

    @ViewBuilder
    private func pie(_ vista: VistaPreviaImportacion) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            Spacer(minLength: 0)
            if modelo.trabajo != .aplicando {
                BotonPrincipal("Aplicar", icono: "checkmark", motivoDesactivado: modelo.trabajo != nil ? "Espera un momento" : modelo.motivoNoAplicar) {
                    Task { await modelo.aplicar() }
                }
                .accessibilityIdentifier("ordenar.aplicar")
            }
        }
    }
}

/// La vista previa de una importación: el resumen, las cifras, los avisos y la lista de lo que pasará.
struct ResumenVistaPrevia: View {
    @Bindable var modelo: ModeloOrdenar
    let vista: VistaPreviaImportacion

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Destacado(rotulo: "Lo que haré") {
                ResumenNoSeBorra(cuerpo: "Mover \(TLSFormat.entero(vista.mover)) · Propiedades a \(TLSFormat.entero(vista.propiedades)) · Archivar \(TLSFormat.entero(vista.archivar)) · ")
                    .accessibilityIdentifier("ordenar.resumen")
                Text("Todo va en un solo cambio que se deshace de una vez.")
                    .tlsTexto(TLSTipo.interfaz)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: TLSEspacio.entreMosaicos) {
                cifra("Mover", vista.mover, "a su sitio")
                cifra("Completar", vista.propiedades, "fichas con su tipo")
                cifra("Archivar", vista.archivar, "antecedentes y repetidos")
                cifra("Como está", vista.dejar, "no se toca")
            }
            .fixedSize(horizontal: false, vertical: true)
            detalles
            if !vista.enlacesEnRiesgo.isEmpty { enRiesgo }
            if !vista.noSeTraen.isEmpty {
                TarjetaOrdenar("No lo traigo", icono: "nosign") {
                    ForEach(Array(vista.noSeTraen.prefix(12).enumerated()), id: \.offset) { _, t in
                        Text(t).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ListaMovimientos(modelo: modelo, vista: vista)
        }
    }

    private func cifra(_ titulo: String, _ n: Int, _ detalle: String) -> some View {
        TarjetaOrdenar(titulo) {
            Text(TLSFormat.entero(n)).tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
            Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        }
        .accessibilityElement(children: .combine)
    }

    private var detalles: some View {
        TarjetaOrdenar("Además", icono: "info.circle") {
            ForEach(lineasDetalle, id: \.self) { l in
                Text(l).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lineasDetalle: [String] {
        var lineas: [String] = []
        if vista.enlaces > 0 { lineas.append("Arreglo " + TLSFormat.cuenta(vista.enlaces, "enlace", "enlaces") + " para que sigan llevando a su nota.") }
        if vista.carpetasVacias > 0 {
            lineas.append(TLSFormat.cuenta(vista.carpetasVacias, "carpeta se queda vacía y va", "carpetas se quedan vacías y van") + " al Archivo (no se borran).")
        }
        if !vista.fechas.isEmpty {
            lineas.append("Apunto la fecha de " + TLSFormat.cuenta(vista.fechas.count, "documento", "documentos") + " en «Fechas de documentos».")
        }
        if !vista.sinFecha.isEmpty {
            lineas.append(TLSFormat.cuenta(vista.sinFecha.count, "documento queda", "documentos quedan") + " sin fecha: te lo enseño en Calidad.")
        }
        if !vista.privadas.isEmpty {
            lineas.append("Lo que has marcado como privado queda apuntado así en los ajustes de tu carpeta: no se mueve, no lo ve ningún asistente y no sale en pantalla.")
            lineas.append("Lo privado no se toca: si alguna nota privada enlaza a algo que muevo, ese enlace dejará de llevar a su sitio.")
        }
        lineas.append("El informe queda en el Buzón: «\(vista.informe.stem)».")
        return lineas
    }

    private var enRiesgo: some View {
        TarjetaOrdenar("Enlaces que dejarían de funcionar", icono: "link") {
            AvisoEnLinea(TLSFormat.cuenta(vista.enlacesEnRiesgo.count, "enlace dejaría", "enlaces dejarían")
                         + " de apuntar a su nota. Puedes volver atrás y dejar esa nota donde está, o aplicar igualmente.", estado: .atencion)
            ForEach(Array(vista.enlacesEnRiesgo.prefix(10).enumerated()), id: \.offset) { _, p in
                Text("«\(p.ruta.stem)», línea \(p.linea): \(p.motivo)")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Aplicar igualmente; los reviso después", isOn: $modelo.aceptarEnlacesEnRiesgo)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("ordenar.aceptarEnlaces")
        }
    }
}

/// Lo que pasará, fichero a fichero, por grupos (los 40 primeros de cada uno).
struct ListaMovimientos: View {
    @Bindable var modelo: ModeloOrdenar
    let vista: VistaPreviaImportacion
    @State private var abierto: String?

    struct Grupo: Identifiable {
        let id: String
        let titulo: String
        let filas: [MovimientoPrevisto]
    }

    var grupos: [Grupo] {
        let m = vista.movimientos
        return [
            Grupo(id: "mover", titulo: "A su sitio", filas: m.filter { [.mover, .moverYRenombrar, .copiar, .copiarYRenombrar].contains($0.accion) }),
            Grupo(id: "completar", titulo: "Completar (se quedan donde están)", filas: m.filter { $0.accion == .propiedades }),
            Grupo(id: "archivar", titulo: "Al Archivo", filas: m.filter { [.archivar, .duplicado].contains($0.accion) && $0.destino != nil }),
        ].filter { !$0.filas.isEmpty }
    }

    var body: some View {
        ForEach(grupos) { g in
            TarjetaOrdenar("\(g.titulo) · \(TLSFormat.entero(g.filas.count))", icono: icono(g.id)) {
                let ver = abierto == g.id ? g.filas : Array(g.filas.prefix(5))
                ForEach(ver.prefix(abierto == g.id ? 300 : 5), id: \.clave) { mov in fila(mov) }
                if g.filas.count > 5 {
                    Button(abierto == g.id ? "Ver menos" : "Ver los \(TLSFormat.entero(g.filas.count))") {
                        abierto = abierto == g.id ? nil : g.id
                    }
                    .tlsBoton(.enlace)
                }
                if abierto == g.id, g.filas.count > 300 {
                    Text("Y \(TLSFormat.cuenta(g.filas.count - 300, "más", "más")): todos están en el informe del Buzón.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
    }

    private func icono(_ id: String) -> String {
        switch id {
        case "mover": "arrow.right.doc.on.clipboard"
        case "completar": "text.badge.plus"
        default: "archivebox"
        }
    }

    private func fila(_ m: MovimientoPrevisto) -> some View {
        let e = modelo.zona?.inventario.elemento(m.clave)
        let nombre = e.map { $0.tipo == .nota ? VaultPath($0.nombreLimpio).stem : $0.nombreLimpio }
            ?? (m.clave.split(separator: "/").last.map(String.init) ?? m.clave)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(nombre).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                if let d = m.destino, m.accion != .propiedades {
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityLabel("a")
                    Text((d.parent.map(ModeloOrdenar.rutaLegible) ?? "Tu carpeta")
                         + (d.name != (e?.ruta.name ?? d.name) ? " · como «\(d.ext == "md" ? d.stem : d.name)»" : ""))
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                }
            }
            Text(detalle(m, e))
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                .help(m.motivo)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// El porqué en una línea, sin repetir lo que ya dice ni enseñar rutas internas.
    private func detalle(_ m: MovimientoPrevisto, _ e: ElementoInventario?) -> String {
        if m.accion == .propiedades {
            let donde = e?.ruta.parent.map(ModeloOrdenar.rutaLegible) ?? "Tu carpeta"
            let tipo = modelo.tipoDeFicha(m.clave).map { " (" + ModeloOrdenar.nombreDeTipo($0) + ")" } ?? ""
            return "En \(donde) · le añado su tipo\(tipo)"
        }
        let conflicto = m.conflicto
        if conflicto.isEmpty || conflicto.hasPrefix("Duplicado de") || m.motivo.contains(conflicto) { return m.motivo }
        return m.motivo + " · " + conflicto
    }
}

// MARK: - Comprobación

public struct OrdenarComprobacion: View {
    @Bindable var modelo: ModeloOrdenar
    /// `true` si el paso 3 ya se aplicó: «Deshacer» deja de ofrecerse.
    let pasadoElPaso3: Bool

    public init(modelo: ModeloOrdenar, pasadoElPaso3: Bool = false) {
        self.modelo = modelo
        self.pasadoElPaso3 = pasadoElPaso3
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .comprobacion)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if let hecho = modelo.hecho {
                ResultadoComprobacion(modelo: modelo, hecho: hecho, pasadoElPaso3: pasadoElPaso3)
            } else if modelo.trabajo == nil {
                VacioExplicado(icono: "checkmark.shield", titulo: "Aún no has aplicado nada",
                               porQue: "Cuando apliques la vista previa, aquí verás cada fichero comprobado uno a uno: que están todos y que cada uno sigue idéntico.",
                               compacto: true)
            }
            if modelo.ruta == .ordenar, let h = modelo.heredados {
                TarjetaHeredados(modelo: modelo, preparacion: h, abrirBanco: nil)
            }
        }
        .task { await modelo.prepararHeredados() }
        .accessibilityIdentifier("ordenar.comprobacion")
    }
}

/// «312 de 312 (recuento + SHA-256)», el informe y «Deshacer».
struct ResultadoComprobacion: View {
    @Bindable var modelo: ModeloOrdenar
    let hecho: HechoOrdenar
    let pasadoElPaso3: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if hecho.sinDiferencias {
                Destacado(rotulo: "Comprobado") {
                    CifraDestacada("\(TLSFormat.entero(hecho.verificados)) de \(TLSFormat.entero(hecho.total))",
                                   contexto: "Están todos y cada uno es idéntico por su huella digital. No se ha borrado nada.")
                        .help("Comprobado por recuento y SHA-256")
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ordenar.verificacion")
            } else {
                TarjetaOrdenar("Comprobación", icono: "exclamationmark.triangle") {
                    PastillaEstado(.mal, palabra: TLSFormat.cuenta(hecho.diferencias, "diferencia", "diferencias"))
                    Text(hecho.textoVerificacion).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityIdentifier("ordenar.verificacion")
                    Text("No se ha borrado nada. Revisa el informe del Buzón o deshazlo todo.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            TarjetaOrdenar("Lo que hice", icono: "list.bullet.rectangle") {
                Text(hecho.resumen).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                HStack(spacing: TLSEspacio.e8) {
                    Text("El informe está en el Buzón: «\(VaultPath(hecho.informe).stem)».")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: TLSEspacio.e8)
                    Button("Mostrar en Finder") { FolderAccess.revealInFinder(VaultPath(hecho.informe).url(in: modelo.acceso.raiz)) }
                        .tlsBoton(.enlace)
                }
            }
            TarjetaDeshacer(modelo: modelo, pasadoElPaso3: pasadoElPaso3)
        }
    }
}

/// «Deshacer todo»: mientras siga disponible (nada escrito después y antes del paso 3).
struct TarjetaDeshacer: View {
    @Bindable var modelo: ModeloOrdenar
    let pasadoElPaso3: Bool

    var body: some View {
        if modelo.aplicado {
            TarjetaOrdenar("Deshacer", icono: "arrow.uturn.backward") {
                Text(texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    Button("Deshacer todo") { Task { await modelo.deshacer() } }
                        .tlsBoton(.secundario)
                        .disabled(!disponible || modelo.trabajo != nil || modelo.soloMirar)
                        .accessibilityIdentifier("ordenar.deshacer")
                }
            }
            .task { await modelo.comprobarDeshacer() }
        }
    }

    private var disponible: Bool { modelo.puedeDeshacer && !pasadoElPaso3 }

    private var texto: String {
        if pasadoElPaso3 { return "Ya aplicaste «Organizar»: lo ordenado se queda. Si algo no te cuadra, muévelo desde la carpeta." }
        if !modelo.puedeDeshacer {
            return "Después se han escrito otros cambios en tu carpeta. Para deshacer esto, deshaz antes esos cambios."
        }
        return "Lo dejo todo como estaba, de una vez: lo movido vuelve a su sitio y lo creado va al Archivo. Nada se borra. Disponible hasta que apliques «Organizar»."
    }
}

// MARK: - Calidad

public struct OrdenarCalidad: View {
    @Bindable var modelo: ModeloOrdenar

    public init(modelo: ModeloOrdenar) { self.modelo = modelo }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .calidad)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if let c = modelo.calidad {
                if c.avisos.isEmpty {
                    VacioExplicado(icono: "checkmark.seal", titulo: "Todo en orden",
                                   porQue: "No he encontrado documentos sin fecha, fichas sin tipo, repetidos ni enlaces rotos.",
                                   compacto: true)
                } else {
                    Text(c.resumen).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityIdentifier("ordenar.calidad.resumen")
                    ForEach(AvisoCalidad.Tipo.allCases, id: \.self) { t in
                        let avisos = c.avisos.filter { $0.tipo == t }
                        if !avisos.isEmpty { grupo(t, avisos) }
                    }
                }
            }
        }
        .task(id: modelo.trabajo == nil) { if modelo.calidad == nil, modelo.trabajo == nil { await modelo.revisarCalidad() } }
        .accessibilityIdentifier("ordenar.calidad")
    }

    private func grupo(_ t: AvisoCalidad.Tipo, _ avisos: [AvisoCalidad]) -> some View {
        TarjetaOrdenar("\(t.titulo) · \(TLSFormat.entero(avisos.count))", icono: icono(t)) {
            ForEach(avisos.prefix(30)) { a in
                HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.detalle).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(a.queHacer).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: TLSEspacio.e8)
                    if modelo.tareasCreadas.contains(a.id) {
                        PastillaEstado(.bien, palabra: "Tarea creada")
                    } else {
                        if a.tipo == .sinFecha {
                            PonerFecha(modelo: modelo, aviso: a)
                        }
                        Button("Crear tarea") { Task { await modelo.crearTarea(a) } }
                            .tlsBoton(.secundario)
                            .disabled(modelo.trabajo != nil || modelo.motivoNoEscribir != nil)
                            .accessibilityLabel("Crear tarea: \(a.detalle)")
                        Button("Ignorar") { modelo.ignorar(a) }
                            .tlsBoton(.enlace)
                            .accessibilityLabel("Ignorar: \(a.detalle)")
                    }
                }
                .padding(.vertical, 3)
            }
            if avisos.count > 30 {
                Text("Y \(TLSFormat.cuenta(avisos.count - 30, "más", "más")): los verás aquí cuando resuelvas estos.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }

    private func icono(_ t: AvisoCalidad.Tipo) -> String {
        switch t {
        case .sinFecha: "calendar.badge.exclamationmark"
        case .sinTipo: "questionmark.square"
        case .duplicado: "doc.on.doc"
        case .enlaceRoto: "link.badge.plus"
        }
    }
}

/// «Poner fecha…»: el día del documento, con un calendario; se apunta como tuyo en «Fechas de documentos».
struct PonerFecha: View {
    @Bindable var modelo: ModeloOrdenar
    let aviso: AvisoCalidad
    @State private var abierto = false
    @State private var dia = Date()

    var body: some View {
        Button("Poner fecha…") {
            dia = modelo.hoy.date()
            abierto = true
        }
        .tlsBoton(.secundario)
        .disabled(modelo.trabajo != nil || modelo.motivoNoEscribir != nil)
        .accessibilityLabel("Poner fecha: \(aviso.detalle)")
        .popover(isPresented: $abierto, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                Text("¿De qué día es «\(aviso.ruta.name)»?").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker("Día del documento", selection: $dia, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "es_ES"))
                Text("Queda apuntado como tuyo: nada lo pisa después.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                HStack {
                    Spacer(minLength: 0)
                    Button("Cancelar") { abierto = false }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                    Button("Guardar la fecha") {
                        abierto = false
                        let d = LocalDate(date: dia)
                        Task { await modelo.ponerFecha(aviso, fecha: d) }
                    }
                    .tlsBoton(.principal)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(TLSEspacio.e16)
            .frame(width: 300)
        }
    }
}

// MARK: - Completar las fichas (carpeta ya organizada)

public struct OrdenarCompletarFichas: View {
    @Bindable var modelo: ModeloOrdenar
    let pasadoElPaso3: Bool
    @Environment(\.ordenarAplicarEnElPie) private var aplicarEnElPie

    public init(modelo: ModeloOrdenar, pasadoElPaso3: Bool = false) {
        self.modelo = modelo
        self.pasadoElPaso3 = pasadoElPaso3
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .completarFichas)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if let hecho = modelo.hecho {
                ResultadoComprobacion(modelo: modelo, hecho: hecho, pasadoElPaso3: pasadoElPaso3)
            } else if let vista = modelo.vista {
                if !vista.hayCambios {
                    VacioExplicado(icono: "checkmark.seal", titulo: "Todo está en su sitio",
                                   porQue: "No hay fichas que completar ni nada que mover. Puedes seguir.", compacto: true)
                        .accessibilityIdentifier("ordenar.nadaQueHacer")
                } else {
                    Destacado(rotulo: "Lo que haré") {
                        ResumenNoSeBorra(cuerpo: vista.mover == 0 ? "Completar \(TLSFormat.cuenta(vista.propiedades, "ficha", "fichas")) · No muevo nada · "
                                         : "Mover \(TLSFormat.entero(vista.mover)) · Propiedades a \(TLSFormat.entero(vista.propiedades)) · Archivar \(TLSFormat.entero(vista.archivar)) · ")
                            .accessibilityIdentifier("ordenar.resumen")
                        Text("Les añado su tipo y un identificador; el resto de cada ficha no cambia.")
                            .tlsTexto(TLSTipo.interfaz)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    porTipo(vista)
                    ListaMovimientos(modelo: modelo, vista: vista)
                    if !aplicarEnElPie {
                    HStack {
                        Spacer(minLength: 0)
                        if modelo.trabajo != .aplicando {
                            BotonPrincipal("Aplicar", icono: "checkmark",
                                           motivoDesactivado: modelo.trabajo != nil ? "Espera un momento" : modelo.motivoNoAplicar) {
                                Task { await modelo.aplicar() }
                            }
                            .accessibilityIdentifier("ordenar.aplicar")
                        }
                    }
                    }
                }
            }
        }
        .accessibilityIdentifier("ordenar.completarFichas")
    }

    private func porTipo(_ vista: VistaPreviaImportacion) -> some View {
        var cuenta: [String: Int] = [:]
        for m in vista.movimientos where m.adopta {
            cuenta[modelo.tipoDeFicha(m.clave) ?? "", default: 0] += 1
        }
        let filas = cuenta.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        return TarjetaOrdenar("Fichas que completo", icono: "person.text.rectangle") {
            ForEach(filas, id: \.key) { t, n in
                FilaCifra(t.isEmpty ? "Otras fichas" : ModeloOrdenar.nombreDeTipo(t).capitalizadaPrimera, TLSFormat.entero(n))
            }
        }
    }
}

// MARK: - Movimientos del banco

public struct OrdenarBanco: View {
    @Bindable var modelo: ModeloOrdenar
    let abrirBanco: (() -> Void)?

    public init(modelo: ModeloOrdenar, abrirBanco: (() -> Void)? = nil) {
        self.modelo = modelo
        self.abrirBanco = abrirBanco
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            CabeceraOrdenar(pantalla: .banco)
            ProgresoOrdenar(modelo: modelo)
            AvisosOrdenar(modelo: modelo)
            if let h = modelo.heredados {
                TarjetaHeredados(modelo: modelo, preparacion: h, abrirBanco: abrirBanco)
            } else {
                VacioExplicado(icono: "building.columns", titulo: "No hay movimientos heredados",
                               porQue: "Los extractos nuevos del banco se importan en Finanzas › Banco, cuando quieras.",
                               accion: abrirBanco == nil ? nil : "Abrir el Banco", alPulsar: abrirBanco, compacto: true)
            }
            if modelo.aplicado { TarjetaDeshacer(modelo: modelo, pasadoElPaso3: false) }
        }
        .task { await modelo.prepararHeredados() }
        .accessibilityIdentifier("ordenar.banco")
    }
}

/// Los movimientos heredados de Finanzas › Registros › importar, con «Cargar en preparación».
struct TarjetaHeredados: View {
    @Bindable var modelo: ModeloOrdenar
    let preparacion: PreparacionHeredada
    let abrirBanco: (() -> Void)?

    var body: some View {
        TarjetaOrdenar("Movimientos heredados", icono: "tray.full") {
            Text(preparacion.resumen).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityIdentifier("ordenar.heredados.resumen")
            Text("De " + TLSFormat.cuenta(preparacion.ficheros.count, "fichero", "ficheros")
                 + " en Finanzas › Registros › importar. Se cargan como facturas y pagos sin revisar: ninguno cuenta como cobrado ni toca los movimientos del banco.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if !preparacion.columnasQueNoCaben.isEmpty {
                AvisoEnLinea("Estos datos no caben en los registros y no se cargan: "
                             + preparacion.columnasQueNoCaben.map(NombreDeColumna.de).joined(separator: ", ") + ".",
                             estado: .atencion)
            }
            ForEach(Array(preparacion.avisos.prefix(4).enumerated()), id: \.offset) { _, a in AvisoEnLinea(a, estado: .atencion) }
            HStack(spacing: TLSEspacio.e12) {
                if let abrirBanco {
                    Button("Importar un extracto nuevo en el Banco", action: abrirBanco).tlsBoton(.enlace)
                }
                Spacer(minLength: 0)
                if preparacion.nuevas.isEmpty {
                    PastillaEstado(.bien, palabra: "Ya están todos cargados")
                } else {
                    BotonPrincipal("Cargar en preparación", icono: "tray.and.arrow.down",
                                   motivoDesactivado: modelo.motivoNoEscribir ?? (modelo.trabajo != nil ? "Espera un momento" : nil)) {
                        Task { await modelo.cargarHeredados() }
                    }
                    .accessibilityIdentifier("ordenar.heredados.cargar")
                }
            }
        }
    }
}

/// «Mover 312 · Propiedades a 140 · Archivar 28 · **No se borra nada**» (lo último, en negrita).
struct ResumenNoSeBorra: View {
    let cuerpo: String
    @Environment(\.tlsEscalaTexto) private var escala

    var body: some View {
        (Text(cuerpo).font(TLSTipo.tituloModulo.font(escala: escala))
            + Text("No se borra nada").font(TLSTipo.tituloModulo.peso(700).font(escala: escala)))
            .lineSpacing(TLSTipo.tituloModulo.espacioEntreLineas(escala: escala))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Una pantalla cualquiera

/// La pantalla del paso 2 que toca (la usa la puesta en marcha).
public struct PantallaOrdenarVista: View {
    let pantalla: PantallaOrdenar
    @Bindable var modelo: ModeloOrdenar
    let pasadoElPaso3: Bool
    let multica: Bool
    let abrirBanco: (() -> Void)?

    public init(pantalla: PantallaOrdenar, modelo: ModeloOrdenar, pasadoElPaso3: Bool = false,
                multica: Bool = MulticaCLI.localizar() != nil, abrirBanco: (() -> Void)? = nil) {
        self.pantalla = pantalla; self.modelo = modelo; self.pasadoElPaso3 = pasadoElPaso3
        self.multica = multica; self.abrirBanco = abrirBanco
    }

    public var body: some View {
        switch pantalla {
        case .loQueHay: OrdenarLoQueHay(modelo: modelo)
        case .preparar: OrdenarPreparar(modelo: modelo)
        case .porPrograma: OrdenarPorPrograma(modelo: modelo, multica: multica)
        case .repetidos: OrdenarRepetidos(modelo: modelo)
        case .vistaPrevia: OrdenarVistaPrevia(modelo: modelo)
        case .comprobacion: OrdenarComprobacion(modelo: modelo, pasadoElPaso3: pasadoElPaso3)
        case .calidad: OrdenarCalidad(modelo: modelo)
        case .completarFichas: OrdenarCompletarFichas(modelo: modelo, pasadoElPaso3: pasadoElPaso3)
        case .banco: OrdenarBanco(modelo: modelo, abrirBanco: abrirBanco)
        }
    }
}

extension String {
    /// «Contacto» de «contacto».
    var capitalizadaPrimera: String { prefix(1).uppercased() + dropFirst() }
}
