import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

// F3 · rol ordenar. Piezas comunes de las pantallas de «Ordenar lo que tienes» (Mosaico v2): tarjeta, cabecera de la
// pantalla, progreso con «Parar», avisos y la lista de colecciones para elegir destino.

/// Tarjeta de Mosaico v2 (superficie, radio 22, sombra 1) con su rótulo.
struct TarjetaOrdenar<Contenido: View>: View {
    let rotulo: String?
    let icono: String?
    let contenido: Contenido

    init(_ rotulo: String? = nil, icono: String? = nil, @ViewBuilder contenido: () -> Contenido) {
        self.rotulo = rotulo; self.icono = icono; self.contenido = contenido()
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if let rotulo {
                HStack(spacing: TLSEspacio.e8) {
                    if let icono {
                        Image(systemName: icono)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                            .accessibilityHidden(true)
                    }
                    Rotulo(rotulo)
                    Spacer(minLength: 0)
                }
            }
            contenido.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TLSEspacio.mosaicoPequeno)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
    }
}

public extension EnvironmentValues {
    /// Dentro de la puesta en marcha el título de cada pantalla y su explicación ya van en su cabecera azul noche
    /// (el motor las toma de `ResumenOrdenar`): aquí no se repiten.
    @Entry var ordenarSinTitulo: Bool = false
    /// Dentro de la puesta en marcha, «Aplicar» de la vista previa y de «Completar las fichas» es el botón del pie (↩):
    /// no hay otro dentro de la pantalla (antes «Siguiente» avanzaba sin aplicar y la persona se quedaba atascada).
    @Entry var ordenarAplicarEnElPie: Bool = false
}

/// Título de la pantalla y su explicación (dos o tres líneas). Dentro de la puesta en marcha, nada: lo dice su cabecera.
struct CabeceraOrdenar: View {
    let pantalla: PantallaOrdenar
    @Environment(\.ordenarSinTitulo) private var sinTitulo

    var body: some View {
        if !sinTitulo {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                Text(pantalla.titulo)
                    .tlsTexto(TLSTipo.tituloSeccion)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Text(pantalla.explicacion)
                    .tlsTexto(TLSTipo.lectura)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Lo que está haciendo el modelo, con «Parar» si se puede parar sin riesgo.
struct ProgresoOrdenar: View {
    @Bindable var modelo: ModeloOrdenar

    var body: some View {
        if let t = modelo.trabajo {
            HStack(spacing: TLSEspacio.e12) {
                ProgressView().controlSize(.small)
                Text(texto(t))
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TLSEspacio.e8)
                switch t {
                case .mirando, .preparando:
                    Button("Parar") { modelo.parar() }
                        .tlsBoton(.secundario)
                        .help("No se ha cambiado nada: solo estaba mirando")
                        .accessibilityIdentifier("ordenar.parar")
                case .aplicando:
                    Button("Cancelar") { modelo.cancelarAplicar() }
                        .tlsBoton(.secundario)
                        .help("Si ya se ha escrito algo, lo dejo como estaba")
                        .accessibilityIdentifier("ordenar.cancelar")
                default:
                    EmptyView()
                }
            }
            .padding(TLSEspacio.e12)
            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ordenar.progreso")
        }
    }

    private func texto(_ t: ModeloOrdenar.Trabajo) -> String {
        if t == .mirando, modelo.contador > 0 { return "Miro lo que tienes… " + TLSFormat.cuenta(modelo.contador, "fichero", "ficheros") }
        return t.texto
    }
}

/// El error y lo último hecho, en una línea cada uno.
struct AvisosOrdenar: View {
    @Bindable var modelo: ModeloOrdenar

    var body: some View {
        if let e = modelo.error {
            AvisoEnLinea(e, estado: .mal).accessibilityIdentifier("ordenar.error")
        }
        if let h = modelo.hechoTexto {
            AvisoEnLinea(h, estado: .bien).accessibilityIdentifier("ordenar.hecho")
        }
    }
}

/// Una línea «etiqueta … cifra» de una tarjeta.
struct FilaCifra: View {
    let etiqueta: String
    let cifra: String
    let detalle: String?

    init(_ etiqueta: String, _ cifra: String, detalle: String? = nil) {
        self.etiqueta = etiqueta; self.cifra = cifra; self.detalle = detalle
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(etiqueta).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                if let detalle {
                    Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            Spacer(minLength: TLSEspacio.e8)
            Text(cifra).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Las colecciones de la estructura, agrupadas por área, para elegir adónde va algo.
struct MenuColeccion: View {
    let actual: String?
    let titulo: String
    let elegir: (String) -> Void

    static var grupos: [(String, [ColeccionV2])] {
        var out: [(String, [ColeccionV2])] = []
        for a in AreaCode.allCases {
            let cols = ColeccionV2.catalogo.filter { $0.area == a }
            if !cols.isEmpty { out.append(("\(a.numero) · \(a.nombre)", cols)) }
        }
        out.append(("Buzón", ColeccionV2.catalogo.filter { $0.area == nil }))
        return out
    }

    var body: some View {
        Menu {
            ForEach(Self.grupos, id: \.0) { grupo in
                Section(grupo.0) {
                    ForEach(grupo.1) { c in
                        Button {
                            elegir(c.clave)
                        } label: {
                            if c.clave == actual { Label(Self.corto(c), systemImage: "checkmark") } else { Text(Self.corto(c)) }
                        }
                        .help(c.descripcion)
                    }
                }
            }
        } label: {
            Text(ModeloOrdenar.nombreColeccion(actual))
                .tlsTexto(TLSTipo.interfazMedia)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Cambiar adónde va")
        .accessibilityLabel(titulo)
        .accessibilityValue(ModeloOrdenar.nombreColeccion(actual))
    }

    /// «Contactos» en lugar de «Ventas › Contactos» (el área ya está en la sección del menú).
    static func corto(_ c: ColeccionV2) -> String {
        c.nombre.components(separatedBy: " › ").last ?? c.nombre
    }
}

/// Icono de cada programa de origen.
extension HerramientaOrigen {
    var simbolo: String {
        switch self {
        case .ordenada: "checkmark.rectangle.stack"
        case .notion: "doc.richtext"
        case .drive: "externaldrive"
        case .obsidian: "diamond"
        case .correo: "envelope"
        case .carpetas: "folder"
        }
    }
}

extension LocalDate {
    /// «19 oct 2026».
    var textoCorto: String {
        let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
        return "\(day) \(meses[max(0, min(11, month - 1))]) \(year)"
    }
}

/// Elegir una carpeta de fuera (solo se lee). Nunca se abre sola: la pide la persona.
@MainActor
enum ElegirCarpeta {
    static func pedir(mensaje: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Elegir"
        panel.message = mensaje
        return panel.runModal() == .OK ? panel.url : nil
    }
}
