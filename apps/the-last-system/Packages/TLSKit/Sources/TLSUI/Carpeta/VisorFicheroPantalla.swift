import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSVisores

/// Un fichero que se ve con un visor (R1): PDF, imagen, audio, vídeo u otros, en el mismo panel que las notas.
/// Arriba, su nombre, tipo y carpeta; abajo, quién lo enlaza. La página de un PDF se recuerda por pestaña de
/// ventana (Atrás vuelve a ella) y se puede pedir antes de entrar con `VisorFicheroPantalla.abrir(_:pagina:…)`.
/// Nunca escribe en el fichero; descarga de iCloud solo porque la persona lo abrió.
struct VisorFicheroPantalla: View {
    let ruta: VaultPath
    let sesion: VaultSession
    @Environment(\.navegacion) private var nav
    @Environment(\.navegar) private var navegar
    @State private var pagina: Int?
    @State private var listo = false

    init(ruta: VaultPath, sesion: VaultSession) {
        self.ruta = ruta
        self.sesion = sesion
    }

    /// Clave del recuerdo de la pantalla con la página del PDF.
    static let clavePagina = "pagina"

    /// Abre un fichero en una página concreta (un PDF incrustado con `#page=N`, un resultado de búsqueda):
    /// deja la página en el recuerdo de la pantalla y navega.
    @MainActor
    static func abrir(_ ruta: VaultPath, pagina: Int?, nav: Navegacion?, navegar: NavegarAccion,
                      modo: ModoApertura = .automatico) {
        if let pagina, pagina > 0 {
            nav?.actualizarRecuerdo(de: .fichero(ruta)) { $0.extra[clavePagina] = String(pagina) }
        }
        navegar(.fichero(ruta), modo: modo)
    }

    private var tipo: TipoFichero { TipoFichero.de(extension: ruta.ext) }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            cabecera
            if let url = sesion.url(for: ruta) {
                if listo {
                    VisorFichero(url: url, tipo: tipo, pagina: pagina, descargaAutomatica: true) { n in
                        nav?.actualizarRecuerdo(de: .fichero(ruta)) { $0.extra[Self.clavePagina] = String(n) }
                    }
                    .id(ruta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VacioExplicado(icono: "questionmark.folder", titulo: "No encuentro este fichero",
                               porQue: "Puede que se haya movido o que la carpeta ya no esté disponible.",
                               accion: "Ver la carpeta", alPulsar: { navegar(.carpeta(ruta.parent.flatMap { $0.isRoot ? nil : $0 }), modo: .entrar) })
            }
            enlazanAqui
        }
        .padding(.horizontal, TLSEspacio.e24)
        .padding(.top, TLSEspacio.e16)
        .padding(.bottom, TLSEspacio.e16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            pagina = nav?.recuerdo(de: .fichero(ruta)).extra[Self.clavePagina].flatMap(Int.init)
            listo = true
        }
    }

    // MARK: Partes

    private var cabecera: some View {
        HStack(alignment: .center, spacing: TLSEspacio.e12) {
            IconoTipo(tipo.simbolo, tamano: 20)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(TLSPaleta.bandeja.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(ruta.stem)
                    .tlsTexto(TLSTipo.tituloSeccion)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(detalle)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: TLSEspacio.e8)
            if sesion.esPrivado(ruta) {
                PastillaEstado(.sinDato, palabra: "Privado")
            }
            Menu {
                Button("Abrir en pestaña nueva") { navegar(.fichero(ruta), modo: .pestanaNueva) }
                if let enlace = sesion.enlaceParaCopiar(.fichero(ruta)) {
                    Button("Copiar enlace") { copiar(enlace) }
                }
                Button("Ver en la carpeta") {
                    navegar(.carpeta(ruta.parent.flatMap { $0.isRoot ? nil : $0 }), modo: .entrar)
                }
                Button("Mostrar en Finder") { sesion.revealInFinder(ruta) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .tlsBoton(.secundario)
            .fixedSize()
            .help("Más")
            .accessibilityLabel("Más acciones del fichero")
        }
    }

    private var detalle: String {
        var partes = [tipo.nombre]
        if let url = sesion.url(for: ruta),
           let tam = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            if let t = TamanoFichero.texto(Int64(tam)) { partes.append(t) }
        }
        partes.append(ruta.carpetaVisible)
        return partes.joined(separator: " · ")
    }

    @ViewBuilder
    private var enlazanAqui: some View {
        let quienes = sesion.enlazanAqui(ruta).filter { !$0.privado || sesion.esPrivado(ruta) }
        if !quienes.isEmpty {
            HStack(spacing: TLSEspacio.e8) {
                Rotulo("Enlazan aquí")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TLSEspacio.e8) {
                        ForEach(quienes.prefix(12)) { s in
                            Button { navegar(sesion.destino(para: s.path)) } label: {
                                Chip(s.title, icono: s.kind.systemImage)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Abrir en pestaña nueva") { navegar(sesion.destino(para: s.path), modo: .pestanaNueva) }
                                Button("Vista previa") { nav?.vistaPrevia = s.path }
                            }
                            .accessibilityLabel("Abrir \(s.title)")
                            .accessibilityAction(named: "Vista previa") { nav?.vistaPrevia = s.path }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Enlazan aquí")
        }
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }
}
