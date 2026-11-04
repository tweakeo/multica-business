import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. 0 · Bienvenida (PLAN §6.7, 1–3 pantallas): «Tengo una carpeta» / «Empiezo de cero» / «Ver un
// ejemplo». Con carpeta: antes de que macOS pida permiso para iCloud, una explicación; si lo deniega, la pantalla de
// recuperación con el enlace a Ajustes del Sistema; «Trabajar sobre una copia (recomendado)» o «Ver sin tocar»; y las
// carpetas privadas, con respuesta obligatoria («Sí, las elijo» con el selector o «No hay»). «Hacer la copia» copia
// sin lo privado y sin descargar nada de iCloud (`DemoCopier`, como «Crear copia de mi carpeta» del arranque) y la
// registra; «Abrir sin tocar» la registra en solo lectura. «Empiezo de cero»: los datos de la empresa y la vista
// previa de lo que se crea; antes de «Crear la carpeta» no existe nada en el disco.

public struct PasoBienvenida: View {
    @Bindable var modelo: ModeloPuesta

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .bienvenida) { p in
            switch p.id {
            case "bienvenida.como": ComoEmpiezas(modelo: modelo)
            case "bienvenida.carpeta": TuCarpeta(modelo: modelo)
            case "bienvenida.recuperacion": Recuperacion(modelo: modelo)
            case "bienvenida.empresa":
                BloquePuesta(rotulo: "Tu empresa", icono: "building.2") {
                    ListaPreguntas(modelo: modelo, preguntas: modelo.preguntas)
                }
            default:
                EmptyView()
            }
        }
        .accessibilityIdentifier("puesta.paso.bienvenida")
    }
}

/// «¿Cómo empiezas?»: tres opciones grandes.
struct ComoEmpiezas: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        if let q = modelo.motor.pregunta(.como) {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                ForEach(q.tipo.opciones) { o in
                    FilaOpcion(titulo: o.texto, detalle: o.detalle, icono: Self.icono(o.id), elegida: elegida(modelo, .como) == o.id) {
                        Task { await modelo.contestar(.como, .opcion(o.id)) }
                    }
                    .accessibilityIdentifier("puesta.opcion.\(PreguntaID.como.rawValue).\(o.id)")
                }
                OrigenEtiqueta(respuesta: modelo.respuesta(.como))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(q.texto)
            .accessibilityIdentifier("puesta.pregunta.\(PreguntaID.como.rawValue)")
        }
    }

    static func icono(_ id: String) -> String {
        switch id {
        case "carpeta": "folder"
        case "cero": "plus.rectangle.on.folder"
        default: "graduationcap"
        }
    }
}

/// Tu carpeta: cuál es, cómo trabajar con ella y lo privado.
struct TuCarpeta: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if modelo.yaHayCarpeta, let e = modelo.motor.contexto.entrada {
                yaHecha(e)
            } else {
                origen
                if let q = modelo.motor.pregunta(.modo) {
                    BloquePuesta(rotulo: "Cómo quieres trabajar con ella", icono: "doc.on.doc") {
                        OpcionesEnFilas(modelo: modelo, pregunta: q, opciones: q.tipo.opciones) { o in
                            o.id == "copia" ? "doc.on.doc" : "eye"
                        }
                        OrigenEtiqueta(respuesta: modelo.respuesta(.modo))
                    }
                    .accessibilityIdentifier("puesta.pregunta.\(PreguntaID.modo.rawValue)")
                }
                privadas
                if !modelo.motor.soloMirar {
                    Toggle(isOn: $modelo.incluirArchivo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Copiar también lo retirado (más lento)").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                            Text("Lo que tienes en la carpeta Archivo. Si no lo copias, la copia es mucho más rápida.")
                                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, TLSEspacio.e8)
                    .accessibilityIdentifier("puesta.incluirArchivo")
                }
                if let c = modelo.copia { ProgresoCopia(modelo: modelo, estado: c) }
            }
        }
    }

    /// La carpeta de origen, con la explicación del permiso de iCloud **antes** de elegirla.
    private var origen: some View {
        BloquePuesta(rotulo: "La carpeta de tu empresa", icono: "folder") {
            VStack(alignment: .leading, spacing: 4) {
                Label("Puede que macOS te pida permiso para leer iCloud Drive.", systemImage: "icloud")
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                Text("Acéptalo: la app solo lee tu carpeta y no cambia nada. Lo que está solo en iCloud no se descarga.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.leading, 26)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("permiso.explicacion")
            HStack(spacing: TLSEspacio.e12) {
                if let url = modelo.carpetaDeOrigen {
                    IconoTipo("folder.fill", tamano: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.lastPathComponent).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text(TLSFormat.rutaCorta(url.path)).tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1).truncationMode(.middle)
                    }
                } else {
                    Text("Aún no la has elegido.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Spacer(minLength: 0)
                Button(modelo.carpetaDeOrigen == nil ? "Elegir carpeta…" : "Cambiar…") {
                    Task { await modelo.elegirCarpetaDeOrigen() }
                }
                .tlsBoton(.secundario)
                .disabled(modelo.copia != nil && modelo.copia != .cancelada)
                .accessibilityIdentifier("puesta.elegirCarpeta")
            }
        }
        .accessibilityIdentifier("puesta.pregunta.\(PreguntaID.origen.rawValue)")
    }

    /// Lo privado: respuesta obligatoria.
    private var privadas: some View {
        let respuesta = modelo.privadasPorConfirmar ? nil : modelo.motor.valor(.privadas)?.opcion
        return BloquePuesta(rotulo: "¿Hay carpetas privadas que no deba copiar ni mirar?", icono: "lock") {
            Text("Lo privado nunca se copia, no lo ve ningún asistente y no sale en pantalla. Hay que contestar para seguir.")
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: TLSEspacio.e8) {
                ChipOpcion(titulo: "Sí, las elijo", elegida: respuesta == "si", activa: modelo.carpetaDeOrigen != nil) {
                    Task { await modelo.elegirPrivadas() }
                }
                .accessibilityIdentifier("puesta.privadas.si")
                ChipOpcion(titulo: "No hay", elegida: respuesta == "no", activa: modelo.carpetaDeOrigen != nil) {
                    Task { await modelo.noHayPrivadas() }
                }
                .accessibilityIdentifier("puesta.privadas.no")
            }
            if modelo.carpetaDeOrigen == nil {
                Text("Elige primero la carpeta de tu empresa.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if respuesta == "si" {
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    FlujoChipsPuesta(espacio: 8) {
                        ForEach(modelo.privadasElegidas, id: \.self) { r in
                            Chip(r, icono: "lock", etiquetaQuitar: "Quitar \(r) de lo privado") {
                                Task { await modelo.quitarPrivada(r) }
                            }
                        }
                    }
                    Button("Añadir otra…") { Task { await modelo.elegirPrivadas() } }
                        .tlsBoton(.enlace)
                    Text("No se copian ni se abren: ni siquiera se mira qué contienen.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .accessibilityIdentifier("puesta.pregunta.\(PreguntaID.privadasCuales.rawValue)")
            }
        }
        .accessibilityIdentifier("puesta.pregunta.\(PreguntaID.privadas.rawValue)")
    }

    /// La puesta en marcha empezó sobre una copia ya hecha (desde el arranque).
    private func yaHecha(_ e: VaultEntry) -> some View {
        BloquePuesta(rotulo: "Tu carpeta", icono: "folder") {
            HStack(spacing: TLSEspacio.e12) {
                Monograma(nombre: e.nombre, tamano: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(e.clase == .demo ? "Es el ejemplo: puedes tocar lo que quieras."
                         : "Trabajas sobre una copia" + (e.origen.map { " de «\(URL(fileURLWithPath: $0).lastPathComponent)»" } ?? "") + ": tu original no se toca.")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if e.carpetasPrivadasDeLaCopia.isEmpty {
                Label("Sin carpetas privadas.", systemImage: "lock.open").tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                Label(TLSFormat.cuenta(e.carpetasPrivadasDeLaCopia.count, "carpeta privada se quedó fuera de la copia",
                                       "carpetas privadas se quedaron fuera de la copia"), systemImage: "lock")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }
}

/// El avance de la copia: contar, copiar y comprobar, con «Cancelar».
struct ProgresoCopia: View {
    @Bindable var modelo: ModeloPuesta
    let estado: EstadoCopia

    var body: some View {
        BloquePuesta(rotulo: titulo, icono: "doc.on.doc") {
            switch estado {
            case .copiando(let fase, let hechos, let total):
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    Text(fase + (total.map { " · \(TLSFormat.progreso(hechos, de: $0))" } ?? (hechos > 0 ? " · \(TLSFormat.entero(hechos))" : "")))
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    if let total, total > 0, fase != "Contar archivos" {
                        ProgressView(value: Double(min(hechos, total)), total: Double(total))
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    HStack {
                        Text("Tu carpeta original no cambia. Lo que está solo en iCloud no se descarga.")
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Spacer()
                        Button("Cancelar") { modelo.cancelarCopia() }.tlsBoton(.secundario)
                            .accessibilityIdentifier("puesta.cancelarCopia")
                    }
                }
            case .cancelando:
                ProgressView("Parando la copia…").tlsTexto(TLSTipo.interfaz)
            case .cancelada:
                AvisoEnLinea(estado: .sinDato, texto: "He parado la copia. No se ha guardado nada; lo copiado a medias está en la Papelera.")
            case .hecha(let t):
                AvisoEnLinea(estado: .bien, texto: t)
            }
        }
        .accessibilityIdentifier("puesta.copia")
    }

    private var titulo: String {
        switch estado {
        case .copiando: "Haciendo la copia"
        case .cancelando, .cancelada: "Copia parada"
        case .hecha: "Copia lista"
        }
    }
}

/// macOS no deja leer la carpeta: qué hacer, paso a paso.
struct Recuperacion: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        BloquePuesta(rotulo: "macOS no deja leer " + (modelo.carpetaDeOrigen.map { "«\($0.lastPathComponent)»" } ?? "tu carpeta"),
                     icono: "lock.trianglebadge.exclamationmark") {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                Text("1. Pulsa «Abrir Ajustes del Sistema»: se abre Privacidad y seguridad › Archivos y carpetas.")
                Text("2. Busca The Last System y activa iCloud Drive (o la carpeta donde está tu empresa).")
                Text("3. Vuelve aquí y pulsa «Volver a intentarlo».")
            }
            .tlsTexto(TLSTipo.lectura)
            .foregroundStyle(TLSPaleta.texto.color)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Volver a intentarlo") { Task { await modelo.reintentarPermiso() } }
                    .tlsBoton(.secundario)
                    .accessibilityIdentifier("permiso.reintentar")
                Button("Elegir otra carpeta") {
                    modelo.actualizar { $0.permisoDenegado(false); $0.ir(a: "bienvenida.carpeta") }
                }
                .tlsBoton(.enlace)
            }
        }
        .accessibilityIdentifier("permiso.recuperacion")
    }
}
