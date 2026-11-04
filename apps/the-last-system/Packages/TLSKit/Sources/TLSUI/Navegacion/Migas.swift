import AppKit
import SwiftUI
import TLSCore
import TLSDesign

/// Una miga: un nivel del camino con su nombre corto (§2.3).
public struct Miga: Identifiable, Hashable, Sendable {
    /// Posición en las migas (0 = la raíz).
    public let id: Int
    public let destino: Destino
    /// Nombre corto (código, sin el nombre del nivel anterior, 24 caracteres como mucho).
    public let nombre: String
    /// Nombre completo (al pasar el puntero y para VoiceOver).
    public let completo: String
    public let icono: String
    public let area: AreaCode?
    /// Pestaña desde la que se salió de la pantalla anterior, en gris detrás («· Oportunidades»).
    public let pestanaOrigen: String?
}

/// Cálculo de las migas: nombre corto y plegado por espacio (§2.3). Puro, para poder probarlo.
public enum PlegadoMigas {
    /// Lo que se pinta: una miga o el «…» con las plegadas dentro.
    public enum Elemento: Hashable, Sendable {
        case miga(Miga, conOrigen: Bool)
        case plegadas([Miga])
    }

    public static let maximoCaracteres = 24
    /// Ancho del separador (chevron de 9 pt y 6 pt a cada lado) y de la miga «…».
    public static let anchoSeparador: CGFloat = 21
    public static let anchoPliegue: CGFloat = 30

    /// Nombre corto, en este orden: el código si lo tiene; el título sin el nombre de un nivel anterior,
    /// ni al principio ni al final; recortado a 24 caracteres con «…».
    public static func nombreCorto(_ titulo: String, codigo: String? = nil, anteriores: [String] = []) -> String {
        if let codigo, !codigo.isEmpty { return recortar(codigo) }
        var t = titulo.trimmingCharacters(in: .whitespaces)
        let conectores = [" · ", " — ", " – ", " - ", ": ", " a ", " de ", " para ", " con "]
        for previo in anteriores where !previo.isEmpty {
            let clave = plegar(previo)
            let tClave = plegar(t)
            // Al principio: «Arquitectura Nexo · Trimestrales» → «Trimestrales».
            if tClave.hasPrefix(clave) {
                var resto = String(t.dropFirst(previo.count))
                for c in conectores where resto.hasPrefix(c) { resto = String(resto.dropFirst(c.count)); break }
                resto = resto.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—:"))
                if !resto.isEmpty { t = resto; continue }
            }
            // Al final o casi: «Factura a Arquitectura Nexo SLP» → «Factura».
            if let r = tClave.range(of: clave, options: .backwards), r.lowerBound > tClave.startIndex {
                let corte = tClave.distance(from: tClave.startIndex, to: r.lowerBound)
                var antes = String(t.prefix(corte))
                for c in conectores where antes.hasSuffix(c) { antes = String(antes.dropLast(c.count)); break }
                antes = antes.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—:"))
                let despues = tClave[r.upperBound...].trimmingCharacters(in: .whitespaces)
                // Solo si lo que queda detrás es corto (SL, SLP, SA…): no se corta un título con contenido.
                if !antes.isEmpty, despues.count <= 4 { t = antes }
            }
        }
        return recortar(t)
    }

    /// Código al principio del título o del nombre del fichero: «F-2026-0014», «T-0041», «FI1».
    public static func codigo(titulo: String, fichero: String?) -> String? {
        let patron = #"^([A-Za-z]{1,4}-\d{2,4}(?:-\d{2,4})?|[A-Z]{2,4}\d{1,3})(?=$|[\s·:\-–—_])"#
        for candidato in [titulo, fichero ?? ""] where !candidato.isEmpty {
            if let r = candidato.range(of: patron, options: .regularExpression) {
                let c = String(candidato[r])
                // «t-0042-revisar…» → «T-0042»; los años solos («2026-10») no son códigos.
                if c.first?.isLetter == true { return c.uppercased() }
            }
        }
        return nil
    }

    static func recortar(_ s: String) -> String {
        s.count > maximoCaracteres ? String(s.prefix(maximoCaracteres - 1)).trimmingCharacters(in: .whitespaces) + "…" : s
    }

    static func plegar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
    }

    /// Plegado por espacio (§2.3): primero se quita el gris de la pestaña de origen; después, los niveles
    /// intermedios se juntan en «…». Siempre se ven la raíz, la penúltima y la última; si aún no cabe, la
    /// penúltima también se pliega; la última, nunca.
    public static func plegar(_ migas: [Miga], ancho: CGFloat, medir: (Miga, _ ultima: Bool, _ conOrigen: Bool) -> CGFloat) -> [Elemento] {
        guard !migas.isEmpty else { return [] }
        func medida(_ elementos: [Elemento]) -> CGFloat {
            var total: CGFloat = 0
            for (i, e) in elementos.enumerated() {
                if i > 0 { total += anchoSeparador }
                switch e {
                case .miga(let m, let o): total += medir(m, m.id == migas.count - 1, o)
                case .plegadas: total += anchoPliegue
                }
            }
            return total
        }
        let n = migas.count
        let completas = migas.map { Elemento.miga($0, conOrigen: $0.pestanaOrigen != nil) }
        if medida(completas) <= ancho { return completas }
        let sinOrigen = migas.map { Elemento.miga($0, conOrigen: false) }
        if medida(sinOrigen) <= ancho || n <= 3 { return sinOrigen }
        let tres: [Elemento] = [.miga(migas[0], conOrigen: false), .plegadas(Array(migas[1..<(n - 2)])),
                                .miga(migas[n - 2], conOrigen: false), .miga(migas[n - 1], conOrigen: false)]
        if medida(tres) <= ancho { return tres }
        return [.miga(migas[0], conOrigen: false), .plegadas(Array(migas[1..<(n - 1)])),
                .miga(migas[n - 1], conOrigen: false)]
    }

    /// Ancho de una miga con la letra de la app: icono de 13 pt, nombre y relleno.
    @MainActor
    public static func medirConLetra(_ miga: Miga, ultima: Bool, conOrigen: Bool) -> CGFloat {
        let estilo = ultima ? TLSTipo.interfazFuerte : TLSTipo.interfazMedia
        var w = (miga.nombre as NSString).size(withAttributes: [.font: estilo.nsFont()]).width
        if conOrigen, let o = miga.pestanaOrigen {
            w += (" · \(o)" as NSString).size(withAttributes: [.font: TLSTipo.interfaz.nsFont()]).width
        }
        return ceil(w) + 13 + 6 + 12
    }

    /// Ancho que queda para las migas en la barra de la ventana: lo de la derecha (buscar, Mika…) y
    /// ‹ › ocupan unos 400 pt.
    public static func anchoParaMigas(anchoDetalle: CGFloat) -> CGFloat {
        max(160, anchoDetalle - 400)
    }
}

/// Las migas de la pestaña (§2.3): en la barra de la ventana, o en una franja de 32 pt si la ventana es
/// estrecha. Grupo «Estás en»; cada miga, un botón «Volver a …».
struct MigasView: View {
    let nav: Navegacion
    let sesion: VaultSession
    let ancho: CGFloat
    @Environment(\.navegar) private var navegar

    var body: some View {
        let migas = sesion.migas(de: nav)
        let elementos = PlegadoMigas.plegar(migas, ancho: ancho) { m, ultima, origen in
            PlegadoMigas.medirConLetra(m, ultima: ultima, conOrigen: origen)
        }
        HStack(spacing: 0) {
            ForEach(Array(elementos.enumerated()), id: \.offset) { i, e in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .padding(.horizontal, 6)
                        .accessibilityHidden(true)
                }
                switch e {
                case .miga(let m, let conOrigen):
                    BotonMiga(miga: m, ultima: m.id == migas.count - 1, conOrigen: conOrigen, nav: nav, sesion: sesion)
                case .plegadas(let dentro):
                    Menu {
                        ForEach(dentro) { m in
                            Button { nav.volver(a: m.id) } label: { Label(m.completo, systemImage: m.icono) }
                        }
                    } label: {
                        Text("…").tlsTexto(TLSTipo.interfazFuerte)
                            .frame(minWidth: TLSAltura.objetivoMinimo, minHeight: TLSAltura.objetivoMinimo)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("\(dentro.count) niveles más")
                }
            }
        }
        .frame(maxWidth: ancho, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Estás en")
    }
}

private struct BotonMiga: View {
    let miga: Miga
    let ultima: Bool
    let conOrigen: Bool
    let nav: Navegacion
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar
    @State private var encima = false

    var body: some View {
        if ultima {
            etiqueta
                .padding(.horizontal, 6)
                .frame(minHeight: TLSAltura.objetivoMinimo)
                .help(miga.completo)
                .accessibilityLabel(miga.completo)
                .accessibilityAddTraits(.isStaticText)
        } else {
            Button { nav.volver(a: miga.id) } label: { etiqueta }
                .buttonStyle(EstiloFila(alto: TLSAltura.objetivoMinimo))
                .focusEffectDisabled()
                .help(miga.completo)
                .accessibilityLabel("Volver a \(miga.completo)")
                .contextMenu {
                    Button("Abrir en pestaña nueva") { navegar(miga.destino, modo: .pestanaNueva) }
                    if let enlace = sesion.enlaceParaCopiar(miga.destino) {
                        Button("Copiar enlace") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(enlace, forType: .string)
                        }
                    }
                    if miga.id == 0 {
                        Button("Mostrar en la barra lateral") { sesion.barraLateral.mostrarEnBarra(miga.destino) }
                    }
                }
        }
    }

    private var etiqueta: some View {
        HStack(spacing: 6) {
            if let area = miga.area {
                IconoArea(area.tlsArea, tamano: 16)
            } else {
                Image(systemName: miga.icono)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
            }
            Text(miga.nombre)
                .tlsTexto(ultima ? TLSTipo.interfazFuerte : TLSTipo.interfazMedia)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(1)
            if conOrigen, let o = miga.pestanaOrigen {
                Text("· \(o)")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
            }
        }
    }
}

/// ‹ y ›: clic va atrás o adelante; mantener pulsado enseña los 10 últimos sitios (§2.1).
struct BotonesAtrasAdelante: View {
    let nav: Navegacion
    let sesion: VaultSession

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(Array(nav.atras.reversed().prefix(10).enumerated()), id: \.offset) { i, paso in
                    Button(sesion.nombre(de: paso.actual)) { nav.saltar(atras: i + 1) }
                }
            } label: {
                Image(systemName: "chevron.left")
            } primaryAction: {
                nav.irAtras()
            }
            .menuIndicator(.hidden)
            .disabled(!nav.puedeIrAtras)
            .help(nav.puedeIrAtras ? "Atrás (⌘[)" : "Atrás (⌘[): aún no has entrado en nada")
            .accessibilityLabel("Atrás")

            Menu {
                ForEach(Array(nav.adelante.reversed().prefix(10).enumerated()), id: \.offset) { i, paso in
                    Button(sesion.nombre(de: paso.actual)) { nav.saltar(adelante: i + 1) }
                }
            } label: {
                Image(systemName: "chevron.right")
            } primaryAction: {
                nav.irAdelante()
            }
            .menuIndicator(.hidden)
            .disabled(!nav.puedeIrAdelante)
            .help("Adelante (⌘])")
            .accessibilityLabel("Adelante")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Atrás y adelante")
    }
}
