import SwiftUI

/// Un dato clave de la cabecera («Relación · Cliente activo»). Hasta 3 por cabecera.
public struct DatoClave: Hashable, Sendable, Identifiable {
    public var id: String { etiqueta }
    public let etiqueta: String
    public let valor: String
    public init(_ etiqueta: String, _ valor: String) { self.etiqueta = etiqueta; self.valor = valor }
}

/// Una opción del menú de estado. Las que no se pueden elegir salen desactivadas con su motivo (§3.1).
public struct OpcionEstado: Hashable, Sendable, Identifiable {
    public let id: String
    public let titulo: String
    public let estado: TLSEstado?
    public let motivoDesactivado: String?
    public init(id: String, titulo: String, estado: TLSEstado? = nil, motivoDesactivado: String? = nil) {
        self.id = id; self.titulo = titulo; self.estado = estado; self.motivoDesactivado = motivoDesactivado
    }
}

/// Estado de la cabecera: pastilla blanca que, si tiene opciones, abre un menú para cambiarlo.
public struct EstadoCabecera {
    public let palabra: String
    public let estado: TLSEstado
    public let opciones: [OpcionEstado]
    public let alElegir: (OpcionEstado) -> Void

    public init(_ palabra: String, estado: TLSEstado = .sinDato, opciones: [OpcionEstado] = [],
                alElegir: @escaping (OpcionEstado) -> Void = { _ in }) {
        self.palabra = palabra; self.estado = estado; self.opciones = opciones; self.alElegir = alElegir
    }
}

/// Cabecera azul noche de área, base y ficha (§3.1, §4.3, §7.10 `CabeceraPantalla`): identidad (avatar o
/// icono), rótulo, título, resumen y código; estado editable y hasta 3 datos clave; acciones a la derecha.
/// `debajo` se pinta justo tras el resumen (p. ej. «Editar descripción» de una base y su campo, M2-Bases).
/// Dentro, el anillo de foco es blanco.
public struct CabeceraAzulNoche<Identidad: View, Acciones: View, Debajo: View>: View {
    let rotulo: String?
    let titulo: String
    let subtitulo: String?
    let codigo: String?
    let estado: EstadoCabecera?
    let datos: [DatoClave]
    let altoMinimo: CGFloat
    /// Los datos como cifras grandes a la derecha (Space Grotesk 24, tabulares), como las tres cifras de una
    /// base en M2-Bases; si no caben, bajan bajo el título. Sin esto, van en pastillas bajo el resumen.
    let cifrasALaDerecha: Bool
    let identidad: Identidad
    let acciones: Acciones
    let debajo: Debajo

    public init(rotulo: String? = nil, titulo: String, subtitulo: String? = nil, codigo: String? = nil,
                estado: EstadoCabecera? = nil, datos: [DatoClave] = [], altoMinimo: CGFloat = TLSAltura.cabeceraFichaMinima,
                cifrasALaDerecha: Bool = false,
                @ViewBuilder identidad: () -> Identidad, @ViewBuilder acciones: () -> Acciones,
                @ViewBuilder debajo: () -> Debajo) {
        self.rotulo = rotulo; self.titulo = titulo; self.subtitulo = subtitulo; self.codigo = codigo
        self.estado = estado; self.datos = Array(datos.prefix(3)); self.altoMinimo = altoMinimo
        self.cifrasALaDerecha = cifrasALaDerecha
        self.identidad = identidad(); self.acciones = acciones(); self.debajo = debajo()
    }

    /// Cifra de la cabecera de una base (M2-Bases: 24/30, 600, tabulares).
    static var estiloCifra: TLSEstiloTexto { TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 24, interlinea: 30, tabulares: true) }

    private var cifras: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(datos) { dato in
                VStack(alignment: .leading, spacing: 2) {
                    Text(dato.etiqueta).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.subtituloCabecera.color)
                    Text(dato.valor).tlsTexto(Self.estiloCifra).foregroundStyle(TLSPaleta.sobreColor.color).lineLimit(1)
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Ancho de la cabecera (las cifras van a la derecha desde `anchoCifrasAlLado`, como el `flex-wrap` de M2-Bases).
    @State private var ancho: CGFloat = 1000
    static var anchoCifrasAlLado: CGFloat { 760 }

    public var body: some View {
        marco(conCifrasAlLado: cifrasALaDerecha && !datos.isEmpty && ancho >= Self.anchoCifrasAlLado)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
    }

    private func marco(conCifrasAlLado: Bool) -> some View {
        HStack(alignment: conCifrasAlLado ? .center : .top, spacing: TLSEspacio.e16) {
            principal(cifrasDebajo: cifrasALaDerecha && !conCifrasAlLado)
                .frame(minWidth: conCifrasAlLado ? 340 : nil)
            if conCifrasAlLado { cifras.padding(.leading, 12) }
            HStack(spacing: TLSEspacio.e8) { acciones }
        }
        .padding(TLSEspacio.e24)
        .frame(maxWidth: .infinity, minHeight: altoMinimo, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.cabecera, style: .continuous).fill(TLSPaleta.cabecera.color))
        .tlsSobreColor()
        .accessibilityElement(children: .contain)
    }

    private func principal(cifrasDebajo: Bool) -> some View {
        let blanco = TLSPaleta.sobreColor.color
        let suave = TLSPaleta.subtituloCabecera.color
        return HStack(alignment: .top, spacing: TLSEspacio.e16) {
            identidad
            VStack(alignment: .leading, spacing: 6) {
                if let rotulo {
                    Text(rotulo).tlsTexto(TLSTipo.secundario.peso(600)).foregroundStyle(suave)
                }
                Text(titulo)
                    .tlsTexto(TLSTipo.tituloPantalla)
                    .foregroundStyle(blanco)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitulo, !subtitulo.isEmpty {
                    Text(subtitulo)
                        .tlsTexto(TLSTipo.lectura)
                        .foregroundStyle(suave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                debajo
                if let codigo {
                    Text(codigo).tlsTexto(TLSTipo.codigo).foregroundStyle(suave)
                }
                if cifrasDebajo {
                    cifras.padding(.top, 6)
                } else if estado != nil || (!datos.isEmpty && !cifrasALaDerecha) {
                    HStack(alignment: .center, spacing: TLSEspacio.e8) {
                        if let estado { PastillaEstadoEditable(estado: estado) }
                        ForEach(cifrasALaDerecha ? [] : datos) { dato in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dato.etiqueta).tlsTexto(TLSTipo.rotulo).foregroundStyle(suave)
                                Text(dato.valor).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(blanco).lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
                                .fill(TLSPaleta.sobreCabeceraSuave.color))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public extension CabeceraAzulNoche where Debajo == EmptyView {
    init(rotulo: String? = nil, titulo: String, subtitulo: String? = nil, codigo: String? = nil,
         estado: EstadoCabecera? = nil, datos: [DatoClave] = [], altoMinimo: CGFloat = TLSAltura.cabeceraFichaMinima,
         @ViewBuilder identidad: () -> Identidad, @ViewBuilder acciones: () -> Acciones) {
        self.init(rotulo: rotulo, titulo: titulo, subtitulo: subtitulo, codigo: codigo, estado: estado, datos: datos,
                  altoMinimo: altoMinimo, identidad: identidad, acciones: acciones, debajo: { EmptyView() })
    }
}

public extension CabeceraAzulNoche where Identidad == EmptyView, Acciones == EmptyView, Debajo == EmptyView {
    init(rotulo: String? = nil, titulo: String, subtitulo: String? = nil, codigo: String? = nil,
         estado: EstadoCabecera? = nil, datos: [DatoClave] = [], altoMinimo: CGFloat = TLSAltura.cabeceraFichaMinima) {
        self.init(rotulo: rotulo, titulo: titulo, subtitulo: subtitulo, codigo: codigo, estado: estado, datos: datos,
                  altoMinimo: altoMinimo, identidad: { EmptyView() }, acciones: { EmptyView() }, debajo: { EmptyView() })
    }
}

public extension CabeceraAzulNoche where Identidad == EmptyView, Debajo == EmptyView {
    init(rotulo: String? = nil, titulo: String, subtitulo: String? = nil, codigo: String? = nil,
         estado: EstadoCabecera? = nil, datos: [DatoClave] = [], altoMinimo: CGFloat = TLSAltura.cabeceraFichaMinima,
         @ViewBuilder acciones: () -> Acciones) {
        self.init(rotulo: rotulo, titulo: titulo, subtitulo: subtitulo, codigo: codigo, estado: estado, datos: datos,
                  altoMinimo: altoMinimo, identidad: { EmptyView() }, acciones: acciones, debajo: { EmptyView() })
    }
}

/// Nombre de §7.10.
public typealias CabeceraPantalla = CabeceraAzulNoche

/// Avatar de 44 pt de la cabecera: iniciales (personas y empresas) o el icono del tipo en blanco al 20 %.
public struct AvatarCabecera: View {
    let iniciales: String?
    let simbolo: String?

    public init(iniciales: String) { self.iniciales = iniciales; self.simbolo = nil }
    public init(simbolo: String) { self.iniciales = nil; self.simbolo = simbolo }

    public var body: some View {
        Group {
            if let iniciales {
                Text(iniciales).font(TLSEstiloTexto(.spaceGrotesk, peso: 700, tamano: 17, interlinea: 20).font())
            } else if let simbolo {
                Image(systemName: simbolo).font(.system(size: 20, weight: .medium))
            }
        }
        .foregroundStyle(TLSPaleta.sobreColor.color)
        .frame(width: 44, height: 44)
        .background(Circle().fill(Color.white.opacity(0.2)))
        .accessibilityHidden(true)
    }
}

/// Pastilla blanca del estado, con menú si hay opciones.
struct PastillaEstadoEditable: View {
    let estado: EstadoCabecera

    var body: some View {
        if estado.opciones.isEmpty {
            PastillaEstado(estado.estado, palabra: estado.palabra, sobreColor: true)
        } else {
            Menu {
                ForEach(estado.opciones) { opcion in
                    Button {
                        estado.alElegir(opcion)
                    } label: {
                        Text(opcion.titulo)
                        if let motivo = opcion.motivoDesactivado { Text(motivo) }
                    }
                    .disabled(opcion.motivoDesactivado != nil)
                }
            } label: {
                HStack(spacing: 4) {
                    PastillaEstado(estado.estado, palabra: estado.palabra, sobreColor: true)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TLSPaleta.sobreColor.color)
                }
                .frame(minHeight: TLSAltura.objetivoMinimo)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Estado: \(estado.palabra)")
            .accessibilityHint("Cambia el estado")
        }
    }
}
