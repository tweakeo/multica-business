import SwiftUI
import TLSCore
import TLSDesign

// F5 · rol conexiones. La pantalla Conexiones (Mosaico v2): una fila por conexión con su icono, su estado en texto e
// icono (Conectado · Sin permiso · Ahora no · Con error) y su «Ahora no»; debajo de cada fila, su panel (explicación
// antes del permiso, recuperación, cuentas, programas…). La misma vista sirve en Ajustes (con su cabecera) y en el paso
// 7 de la puesta en marcha (`modo: .paso`, sin cabecera: la pone el paso).

extension ConexionPuesta {
    /// Icono de la fila (SF Symbols).
    public var iconoConexion: String {
        switch self {
        case .claude: "sparkles"
        case .mail: "envelope"
        case .calendario: "calendar"
        case .banco: "building.columns"
        case .otros: "puzzlepiece.extension"
        case .avisos: "bell"
        case .ventanaCerrada: "menubar.rectangle"
        }
    }

    /// Bloque de la pantalla en el que va.
    var bloqueConexion: String {
        switch self {
        case .claude: "Tus asistentes"
        case .mail, .calendario: "Tu Mac"
        case .banco, .otros: "Tus programas"
        case .avisos, .ventanaCerrada: "Fuera de la ventana"
        }
    }
}

/// La pantalla Conexiones.
public struct ConexionesVista: View {
    @Bindable var modelo: ModeloConexiones
    /// Ir a Finanzas › Banco (en la ventana de una empresa; `nil`: solo se explica).
    var abrirBanco: (() -> Void)?

    public init(modelo: ModeloConexiones, abrirBanco: (() -> Void)? = nil) {
        self.modelo = modelo
        self.abrirBanco = abrirBanco
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if !modelo.modo.esPaso { cabecera.fixedSize(horizontal: false, vertical: true) }
            if !modelo.hayServicios {
                AvisoEnLinea(modelo.modo.esPaso
                             ? "Mail, Calendario y otros programas se conectan cuando la app ya escribe en tu empresa. Elige ahora y lo terminas en Ajustes › Conexiones."
                             : "Para conectar Mail, Calendario y otros programas, abre una empresa en la que la app escriba (una copia o una nueva).",
                             estado: .sinDato)
                    .accessibilityIdentifier("conexiones.sinServicios")
            }
            if let p = modelo.problema { AvisoEnLinea(p, estado: .atencion) }
            if !modelo.revisiones.isEmpty {
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    ForEach(modelo.revisiones) { r in TarjetaRevisionHerramientas(modelo: modelo, revision: r) }
                }
            }
            ForEach(Self.bloques, id: \.self) { bloque in
                let filas = ModeloConexiones.orden.filter { $0.bloqueConexion == bloque }
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    Rotulo(bloque)
                    TarjetaFilas {
                        ForEach(Array(filas.enumerated()), id: \.element) { i, c in
                            if i > 0 { SeparadorFila() }
                            FilaConexionVista(modelo: modelo, conexion: c, abrirBanco: abrirBanco)
                        }
                    }
                }
            }
        }
        .task { if !modelo.cargado { await modelo.cargar() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexiones.pantalla")
    }

    static let bloques = ["Tus asistentes", "Tu Mac", "Tus programas", "Fuera de la ventana"]

    private var cabecera: some View {
        let conectadas = ModeloConexiones.orden.filter { modelo.estado($0) == .conectado }.count
        let sinPermiso = ModeloConexiones.orden.filter { modelo.estado($0) == .sinPermiso }.count
        return CabeceraAzulNoche(rotulo: "Ajustes", titulo: "Conexiones",
                                 subtitulo: "Lo que la app usa de tu Mac y de otros programas. Nada sale de la empresa sin tu OK.",
                                 datos: [DatoClave("Conectadas", "\(conectadas) de \(ModeloConexiones.orden.count)"),
                                         DatoClave("Sin permiso", "\(sinPermiso)"),
                                         DatoClave("Por revisar", "\(modelo.revisiones.count)")],
                                 altoMinimo: TLSAltura.cabeceraBase,
                                 identidad: { AvatarCabecera(simbolo: "cable.connector") },
                                 acciones: { BotonSaberMas(seccion: "conexiones", titulo: "Cómo funcionan").tlsBoton(.secundario) })
    }
}

/// Un botón de elección: el elegido en azul noche (como las opciones de la puesta en marcha).
struct BotonEleccion: View {
    let titulo: String
    var elegida = false
    var activo = true
    let accion: () -> Void

    init(_ titulo: String, elegida: Bool = false, activo: Bool = true, accion: @escaping () -> Void) {
        self.titulo = titulo; self.elegida = elegida; self.activo = activo; self.accion = accion
    }

    var body: some View {
        // F5 · corrector (P2-6): lo elegido no se pinta como botón principal (parecía la acción que falta); lleva una
        // marca y su rasgo de seleccionado.
        Button(action: accion) {
            if elegida { Label(titulo, systemImage: "checkmark") } else { Text(titulo) }
        }
        .tlsBoton(.secundario, alto: TLSAltura.objetivoMinimo + 4)
        .disabled(!activo)
        .accessibilityLabel(titulo)
        .accessibilityValue(elegida ? "Elegido" : "")
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }
}

/// La pastilla de estado de una fila: icono propio y palabra.
struct PastillaConexion: View {
    let estado: EstadoConexion
    let palabra: String

    var body: some View {
        PastillaAsistente(palabra: palabra, simbolo: estado.simbolo, estado: estado.tlsEstado)
    }
}

/// Una fila: icono, nombre, estado, una línea y sus botones; debajo, su panel si está abierto.
struct FilaConexionVista: View {
    @Bindable var modelo: ModeloConexiones
    let conexion: ConexionPuesta
    let abrirBanco: (() -> Void)?

    var body: some View {
        let estado = modelo.estado(conexion)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: TLSEspacio.e12) {
                    cabeza(estado)
                    Spacer(minLength: TLSEspacio.e8)
                    botones(estado)
                }
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    cabeza(estado)
                    HStack(spacing: TLSEspacio.e8) { botones(estado) }.padding(.leading, 40)
                }
            }
            panel
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, TLSEspacio.e12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(conexion.titulo), \(modelo.palabra(conexion))")
        .accessibilityIdentifier("conexiones.fila.\(conexion.rawValue)")
    }

    private func cabeza(_ estado: EstadoConexion) -> some View {
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            IconoTipo(conexion.iconoConexion, tamano: 16).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: TLSEspacio.e8) {
                    Text(conexion.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    PastillaConexion(estado: estado, palabra: modelo.palabra(conexion))
                        .accessibilityIdentifier("conexiones.estado.\(conexion.rawValue)")
                }
                Text(modelo.detalle(conexion))
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                if case .error(let t) = estado, conexion != .claude {
                    AvisoEnLinea(t, estado: .mal)
                }
            }
        }
    }

    @ViewBuilder
    private func botones(_ estado: EstadoConexion) -> some View {
        let eleccion = modelo.eleccion(conexion)
        let ahoraNo = BotonEleccion("Ahora no", elegida: eleccion == false && estado != .conectado) {
            Task { await modelo.ahoraNo(conexion) }
        }
        .accessibilityIdentifier("conexiones.ahoraNo.\(conexion.rawValue)")
        HStack(spacing: TLSEspacio.e8) {
            switch conexion {
            case .claude:
                let i = modelo.claude.info()
                if i.puedeProbar {
                    Button("Probar") { Task { await modelo.claude.probar() } }.tlsBoton(.secundario).disabled(i.ocupado)
                        .help("Una consulta muy pequeña dentro de su caja: no ve tu carpeta")
                        .accessibilityIdentifier("conexiones.claude.probar")
                } else if i.puedeBuscar {
                    Button("Buscar otra vez") { Task { await modelo.claude.buscar() } }.tlsBoton(.secundario).disabled(i.ocupado)
                }
                if modelo.modo.esPaso {
                    // F5 · corrector (P2-6): conectado y sin elegir aún cuenta como elegido.
                    BotonEleccion("Conectar", elegida: eleccion == true || (eleccion == nil && i.estado == .conectado),
                                  activo: i.estado == .conectado) {
                        Task { await modelo.encender(.claude) }
                    }
                    .accessibilityIdentifier("conexiones.conectar.claude")
                }
                if i.estado != .conectado { ahoraNo }
            case .mail where estado == .enEjemplo, .calendario where estado == .enEjemplo:
                EmptyView()
            case .mail:
                if estado == .conectado {
                    Button("Cambiar") { Task { await modelo.cambiarMail() } }.tlsBoton(.secundario)
                        .accessibilityIdentifier("conexiones.mail.cambiar")
                    Button("Desconectar") { Task { await modelo.desconectarMail() } }.tlsBoton(.secundario)
                } else {
                    BotonEleccion("Conectar", elegida: abiertoMail, activo: modelo.hayServicios) {
                        Task { await modelo.conectarMail() }
                    }
                    .accessibilityIdentifier("conexiones.conectar.mail")
                    ahoraNo
                }
            case .calendario:
                if estado != .conectado {
                    BotonEleccion("Conectar", elegida: abiertoCalendario, activo: modelo.hayServicios) {
                        Task { await modelo.conectarCalendario() }
                    }
                    .accessibilityIdentifier("conexiones.conectar.calendario")
                    ahoraNo
                } else {
                    // F5 · corrector (P2-7): el Calendario también se desconecta (sus eventos se quedan donde están).
                    Button("Desconectar") { Task { await modelo.desconectarCalendario() } }.tlsBoton(.secundario)
                        .help("La app deja de poner tus rituales en Calendario; lo que ya está allí se queda")
                        .accessibilityIdentifier("conexiones.calendario.desconectar")
                }
            case .banco:
                if let abrirBanco, !modelo.modo.esPaso {
                    Button("Importar un extracto") { abrirBanco() }.tlsBoton(.secundario)
                        .help("Abre 4 · Finanzas › Banco")
                        .accessibilityIdentifier("conexiones.banco.abrir")
                } else {
                    BotonEleccion("Usaré extractos", elegida: eleccion == true) { Task { await modelo.encender(.banco) } }
                        .accessibilityIdentifier("conexiones.conectar.banco")
                }
                ahoraNo
            case .otros:
                BotonEleccion("Añadir un programa", elegida: modelo.abierta == .otros, activo: modelo.hayServicios) {
                    modelo.alternar(.otros)
                }
                .accessibilityIdentifier("conexiones.conectar.otros")
                ahoraNo
            case .avisos, .ventanaCerrada:
                BotonEleccion("Encender", elegida: estado == .conectado) { Task { await modelo.encender(conexion) } }
                    .accessibilityIdentifier("conexiones.conectar.\(conexion.rawValue)")
                BotonEleccion("Ahora no", elegida: estado != .conectado && eleccion == false) { Task { await modelo.ahoraNo(conexion) } }
                    .accessibilityIdentifier("conexiones.ahoraNo.\(conexion.rawValue)")
            }
        }
    }

    private var abiertoMail: Bool { if case .inicio = modelo.faseMail { false } else { true } }
    private var abiertoCalendario: Bool { if case .inicio = modelo.faseCalendario { false } else { true } }

    @ViewBuilder
    private var panel: some View {
        switch conexion {
        case .claude:
            if let c = modelo.claude.info().consejo {
                Text(c).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 40)
            }
        case .mail:
            PanelMail(modelo: modelo).padding(.leading, 40)
        case .calendario:
            PanelCalendario(modelo: modelo).padding(.leading, 40)
        case .otros:
            PanelOtrosProgramas(modelo: modelo).padding(.leading, 40)
        case .ventanaCerrada:
            if modelo.presencia.item.pidePermiso {
                Button("Permitirlo en Ajustes del Sistema") { modelo.presencia.item.abrirAjustesDelSistema() }
                    .tlsBoton(.enlace).padding(.leading, 40)
            }
            if let p = modelo.presencia.problema { AvisoEnLinea(p, estado: .atencion).padding(.leading, 40) }
        default:
            EmptyView()
        }
    }
}
