import SwiftUI
import TLSCore
import TLSDesign

/// Lista (§4.4): filas de 44 pt con el título, dos datos debajo y el estado o la fecha a la derecha; agrupada
/// con grupos plegables. Como en las listas de una ficha, clic entra (§2.1).
struct VistaListaBase: View {
    @Bindable var modelo: BaseModelo
    @Environment(\.navegar) private var navegar

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                if let grupos = modelo.grupos {
                    ForEach(grupos) { g in
                        Section {
                            if !modelo.config.plegados.contains(g.id) {
                                ForEach(g.filas) { fila($0) }
                            }
                        } header: {
                            CabeceraGrupo(grupo: g, plegado: modelo.config.plegados.contains(g.id),
                                          columna: modelo.coleccion.columna(modelo.config.agrupar ?? ""),
                                          coleccion: modelo.coleccion) { modelo.plegar(g.id) }
                                .padding(.horizontal, 4)
                                .background(TLSPaleta.fondo.color)
                        }
                    }
                } else {
                    ForEach(modelo.filas) { fila($0) }
                }
                if modelo.coleccion.creaConTitulo, modelo.motivoSinCrear == nil {
                    FilaCreacion(modelo: modelo).padding(.top, TLSEspacio.e8)
                }
            }
            .padding(.bottom, TLSEspacio.e24)
        }
        .tlsRecordarDesplazamiento(modelo.destino)
    }

    private func fila(_ f: FilaBase) -> some View {
        let (detalle, derecha, estado) = partes(f)
        return FilaLista(f.titulo, detalle: detalle, icono: icono(f), seleccionada: false,
                         etiquetaAccesible: [f.titulo, detalle, derecha].compactMap { $0 }.joined(separator: ", "),
                         accion: { modelo.abrir(f, navegar: navegar) }) {
            if let estado, modelo.config.agrupar != modelo.coleccion.columnaEstado?.clave {
                PastillaDeEstado(valor: estado, coleccion: modelo.coleccion)
            }
            if let derecha {
                Text(derecha).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
        }
        .onKeyPress(.space) { modelo.vistaPrevia(f); return .handled }
        .vistaPrevia(ruta: f.rutaPreviaAlPasar, sesion: modelo.sesion)
        .contextMenu {
            Button("Abrir") { modelo.abrir(f, modo: .entrar, navegar: navegar) }
            Button("Abrir en pestaña nueva") { modelo.abrir(f, modo: .pestanaNueva, navegar: navegar) }
            Button("Vista previa") { modelo.vistaPrevia(f) }
        }
        .accessibilityAction(named: "Vista previa") { modelo.vistaPrevia(f) }
    }

    private func icono(_ f: FilaBase) -> String {
        f.esFilaCSV ? modelo.coleccion.icono : f.tipo.systemImage
    }

    /// Dos datos debajo, el estado y lo de la derecha (fecha o cifra).
    private func partes(_ f: FilaBase) -> (String?, String?, String?) {
        let hoy = modelo.hoy
        let estadoCol = modelo.coleccion.columnaEstado
        let estado = estadoCol.flatMap { c -> String? in
            let t = f.textoCelda(c, hoy: hoy)
            return t.isEmpty ? nil : t
        }
        var datos: [String] = []
        var derecha: String?
        for col in modelo.columnasVisibles where col.tipo != .titulo && col.clave != estadoCol?.clave {
            let t = f.textoCelda(col, hoy: hoy)
            guard !t.isEmpty, t != "—" else { continue }
            if derecha == nil, col.tipo == .fecha || col.tipo == .dinero { derecha = t; continue }
            if datos.count < 2 { datos.append(t) }
        }
        return (datos.isEmpty ? nil : datos.joined(separator: " · "), derecha, estado)
    }
}

/// Galería (§4.4): tarjetas de 220 × 160 (pequeñas, medianas o grandes) con las iniciales o, en F2, la
/// portada o la primera página del PDF; título y tres datos. Clic elige, doble clic o ↩ entra.
struct VistaGaleriaBase: View {
    @Bindable var modelo: BaseModelo
    @Environment(\.navegar) private var navegar
    @FocusState private var enfocada: String?

    var body: some View {
        let ancho = modelo.config.tamanoGaleria.ancho
        ScrollView {
            if let grupos = modelo.grupos {
                LazyVStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    ForEach(grupos) { g in
                        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                            CabeceraGrupo(grupo: g, plegado: modelo.config.plegados.contains(g.id),
                                          columna: modelo.coleccion.columna(modelo.config.agrupar ?? ""),
                                          coleccion: modelo.coleccion) { modelo.plegar(g.id) }
                            if !modelo.config.plegados.contains(g.id) { rejilla(g.filas, ancho: ancho) }
                        }
                    }
                }
            } else {
                rejilla(modelo.filas, ancho: ancho)
            }
        }
        .tlsRecordarDesplazamiento(modelo.destino)
    }

    private func rejilla(_ filas: [FilaBase], ancho: Double) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: ancho, maximum: ancho + 80), spacing: TLSEspacio.entreMosaicos)],
                  alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            ForEach(filas) { tarjeta($0, ancho: ancho) }
        }
        .padding(.bottom, TLSEspacio.e24)
    }

    private func tarjeta(_ f: FilaBase, ancho: Double) -> some View {
        let hoy = modelo.hoy
        let elegida = modelo.seleccion.contains(f.id)
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        let estado = modelo.coleccion.columnaEstado.map { f.textoCelda($0, hoy: hoy) }.flatMap { $0.isEmpty ? nil : $0 }
        let datos = modelo.columnasVisibles
            .filter { $0.tipo != .titulo && $0.clave != modelo.coleccion.columnaEstado?.clave }
            .map { f.textoCelda($0, hoy: hoy) }.filter { !$0.isEmpty && $0 != "—" }.prefix(3)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                if let doc = f.documento, doc.ext.lowercased() == "pdf" {
                    // Miniatura de la primera página del PDF (R1, F2): de la caché de la empresa, fuera de la carpeta;
                    // nunca de una ruta privada ni de un PDF que esté solo en iCloud (entonces, el icono).
                    let grande = modelo.config.tamanoGaleria != .s
                    MiniaturaDeRuta(ruta: doc, sesion: modelo.sesion, lado: grande ? 160 : 120)
                        .frame(width: grande ? 48 : 36, height: grande ? 60 : 44)
                        .background(RoundedRectangle(cornerRadius: 6).fill(TLSPaleta.bandeja.color))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                } else {
                    Monograma(nombre: f.titulo, tamano: modelo.config.tamanoGaleria == .s ? 28 : 36)
                }
                Spacer(minLength: 0)
                if let estado, modelo.config.agrupar != modelo.coleccion.columnaEstado?.clave { PastillaDeEstado(valor: estado, coleccion: modelo.coleccion) }
            }
            TextoResaltado(f.titulo, busqueda: modelo.busqueda)
                .tlsTexto(TLSTipo.tituloModulo)
                .foregroundStyle(TLSPaleta.texto.color)
                .lineLimit(2)
            ForEach(Array(datos.enumerated()), id: \.offset) { _, d in
                Text(d).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(TLSEspacio.e16)
        .frame(minHeight: modelo.config.tamanoGaleria == .l ? 200 : 160, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .overlay(forma.strokeBorder(elegida ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .contentShape(forma)
        .focusable()
        .focused($enfocada, equals: f.id)
        .tlsFocoPropio(radio: TLSRadio.tarjeta)
        .vistaPrevia(ruta: f.rutaPreviaAlPasar, sesion: modelo.sesion)
        .onTapGesture(count: 2) { modelo.abrir(f, navegar: navegar) }
        .onTapGesture { modelo.seleccion = [f.id]; enfocada = f.id }
        .onKeyPress(.return) { modelo.abrir(f, modo: .entrar, navegar: navegar); return .handled }
        .onKeyPress(.space) { modelo.vistaPrevia(f); return .handled }
        .contextMenu {
            Button("Abrir") { modelo.abrir(f, modo: .entrar, navegar: navegar) }
            Button("Abrir en pestaña nueva") { modelo.abrir(f, modo: .pestanaNueva, navegar: navegar) }
            Button("Vista previa") { modelo.vistaPrevia(f) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([f.titulo, estado].compactMap { $0 } + datos).joined(separator: ", "))
        .accessibilityAddTraits(elegida ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Abrir") { modelo.abrir(f, modo: .entrar, navegar: navegar) }
        .accessibilityAction(named: "Vista previa") { modelo.vistaPrevia(f) }
    }
}
