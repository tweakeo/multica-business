import SwiftUI
import TLSCore
import TLSDesign
import TLSVisores

/// La vista previa de una ficha (§2.5, §7.7): tarjeta flotante de 360 pt (hasta 320 de alto), en
/// `superficieElevada`, radio 16 y sombra 2, con el icono del tipo, el título, el código y la pastilla de estado,
/// el dato protagonista en `cifraMedia` (sin violeta: el destacado es de la pantalla), hasta 4 datos, la
/// primera línea de «Ahora», lo último de su actividad y, al pie, «Abrir» (↩) y «En pestaña nueva» (⌘↩).
///
/// **Nunca escribe** (criterio §11.8) y nunca enseña lo privado. Sale de la foto de la carpeta que ya tiene la
/// sesión (`AlmacenRelaciones`), sin leer el fichero; los enlaces de dentro abren su ficha y la cierran.
struct VistaPreviaPopover: View {
    let ruta: VaultPath
    let sesion: VaultSession
    /// Cierra la vista previa (la del puntero o la de la barra espaciadora).
    var cerrar: (() -> Void)?
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @State private var almacen: AlmacenRelaciones

    init(ruta: VaultPath, sesion: VaultSession) {
        self.ruta = ruta
        self.sesion = sesion
        self._almacen = State(initialValue: AlmacenRelaciones.de(sesion))
    }

    init(ruta: VaultPath, sesion: VaultSession, cerrar: (() -> Void)?) {
        self.init(ruta: ruta, sesion: sesion)
        self.cerrar = cerrar
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.previa, style: .continuous)
        Group {
            if sesion.esPrivado(ruta) {
                Label("Es privada: no se enseña en la vista previa.", systemImage: "lock")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // El pie («Abrir», «En pestaña nueva») siempre se ve: si no cabe todo en 320 pt, se recorta lo de
                // arriba por abajo (lo último de la actividad), nunca el pie.
                TarjetaConPie(altoMaximo: TLSAncho.vistaPreviaAltoMaximo - 2 * TLSEspacio.e16, espacio: TLSEspacio.e12) {
                    // Con mínimo y máximo, el marco toma siempre el alto que le dan (y recorta lo que sobre).
                    VStack(alignment: .leading, spacing: TLSEspacio.e12) { arriba }
                        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                    pie
                }
            }
        }
        .padding(TLSEspacio.e16)
        .frame(width: TLSAncho.vistaPrevia, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.superficieElevada.color))
        .clipShape(forma)
        .tlsSombra(.dos, forma: forma)
        .task(id: sesion.revision) { await almacen.actualizar() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vista previa de \(sesion.titulo(de: ruta))")
    }

    /// Lo de arriba de la tarjeta, según sea un fichero, una ficha o una nota.
    @ViewBuilder
    private var arriba: some View {
        if TipoFichero.de(extension: ruta.ext).tieneMiniatura, let url = sesion.url(for: ruta) {
            // Un fichero (PDF, imagen): su miniatura, sin descargar nada de iCloud.
            cabecera(titulo: ruta.name, simbolo: TipoFichero.de(extension: ruta.ext).simbolo, codigo: nil, estado: nil, tipo: .other)
            MiniaturaFicheroVista(url: url, lado: 480)
                .frame(maxWidth: .infinity, maxHeight: 180)
        } else if let grafo = almacen.grafo, let ficha = grafo.ficha(ruta) {
            contenido(ResumenDeFicha(ficha: ficha, grafo: grafo, hoy: almacen.hoy), grafo: grafo)
        } else {
            cabecera(titulo: sesion.titulo(de: ruta), simbolo: sesion.resumen(de: ruta)?.kind.systemImage ?? "doc.text",
                     codigo: nil, estado: nil, tipo: sesion.resumen(de: ruta)?.kind ?? .note)
            Text(almacen.grafo == nil ? "Leyendo…" : sesion.resumen(de: ruta)?.kind.etiqueta ?? "Nota")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
        }
    }

    @ViewBuilder
    private func contenido(_ r: ResumenDeFicha, grafo: GrafoRelaciones) -> some View {
        cabecera(titulo: r.ficha.nombre, simbolo: r.ficha.tipo.systemImage, codigo: r.codigo, estado: r.estado, tipo: r.ficha.tipo)
        Text(r.rotulo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        if let p = r.protagonista, !p.valor.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.rotulo).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                Text(p.valor)
                    .tlsTexto(p.esCifra ? TLSTipo.cifraMedia : TLSTipo.tituloModulo)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(2)
                if let c = p.contexto, !c.isEmpty {
                    Text(c).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                }
                if let segundo = p.segundo {
                    Text([segundo, p.segundoDetalle].compactMap { $0 }.joined(separator: " · "))
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
        if !r.datos.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: TLSEspacio.e12, verticalSpacing: 4) {
                ForEach(Array(r.datos.prefix(4))) { d in
                    GridRow {
                        Text(d.etiqueta).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text(d.valor).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        if let a = r.ahora.first {
            Label {
                Text(a.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
            } icon: {
                Image(systemName: a.estado.simbolo).foregroundStyle(a.estado.color.color)
            }
            .accessibilityLabel("Ahora: \(a.texto)")
        }
        let ultimas = ultimasEntradas(r.ficha)
        if !ultimas.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Rotulo("Lo último")
                ForEach(ultimas) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(e.fecha.map { FormatoFicha.fechaCorta($0, hoy: almacen.hoy) } ?? "")
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .frame(width: 44, alignment: .leading)
                        Text(e.texto).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                    }
                }
            }
        }
    }

    private func cabecera(titulo: String, simbolo: String, codigo: String?, estado: String?, tipo: NoteKind) -> some View {
        HStack(alignment: .top, spacing: TLSEspacio.e8) {
            Image(systemName: simbolo)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let codigo { Text(codigo).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color) }
            }
            Spacer(minLength: 4)
            if let estado {
                PastillaEstado(FormatoFicha.tlsEstado(tipo, estado, hoy: almacen.hoy), palabra: estado)
            }
        }
    }

    private var pie: some View {
        HStack(spacing: TLSEspacio.e8) {
            Spacer(minLength: 0)
            Button("En pestaña nueva") { abrir(.pestanaNueva) }
                .tlsBoton(.secundario)
                .keyboardShortcut(.return, modifiers: .command)
            Button("Abrir") { abrir(.entrar) }
                .tlsBoton(.principal, alto: 36)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 2)
    }

    private func abrir(_ modo: ModoApertura) {
        cerrar?()
        nav?.vistaPrevia = nil
        navegar(sesion.destino(para: ruta), modo: modo)
    }

    /// Las 3 últimas entradas de su actividad (de la foto de la carpeta, sin leer el fichero).
    private func ultimasEntradas(_ f: FichaGrafo) -> [EntradaActividad] {
        guard let texto = almacen.foto?.text(f.ruta) else { return [] }
        return Array(ActividadDeFicha.leer(texto).prefix(3))
    }
}

/// Dos piezas: lo de arriba y un pie que siempre se ve abajo. El alto es el que pida lo de arriba más el pie, sin
/// pasar de `altoMaximo`; si no cabe, lo de arriba recibe menos alto (y se recorta), el pie no.
struct TarjetaConPie: Layout {
    var altoMaximo: CGFloat
    var espacio: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return subviews.first?.sizeThatFits(proposal) ?? .zero }
        let ancho = proposal.width ?? max(subviews[0].sizeThatFits(.unspecified).width, subviews[1].sizeThatFits(.unspecified).width)
        // El alto que pediría lo de arriba sin límite (su tamaño ideal a este ancho).
        let arriba = subviews[0].sizeThatFits(ProposedViewSize(width: ancho, height: nil))
        let pie = subviews[1].sizeThatFits(ProposedViewSize(width: ancho, height: nil))
        return CGSize(width: ancho, height: min(arriba.height + espacio + pie.height, altoMaximo))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            subviews.first?.place(at: bounds.origin, proposal: proposal)
            return
        }
        let pie = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let altoArriba = max(0, bounds.height - pie.height - espacio)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: altoArriba))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - pie.height),
                          proposal: ProposedViewSize(width: bounds.width, height: pie.height))
    }
}
