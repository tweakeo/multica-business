import SwiftUI
import TLSCore
import TLSDesign

/// «Todas las bases» (⇧⌘B, §4.1): un mosaico por área (más «Comunes») con una pieza por base: icono, nombre,
/// número de fichas abiertas, la frase de su nota índice, lo urgente en una línea y el último cambio. Cada pieza
/// tiene su menú: Abrir · Abrir en pestaña nueva · Fijar en la barra lateral · Nueva… Las de módulos apagados
/// van al final, en «Apagadas», con «Encender el módulo».
struct TodasLasBasesPantalla: View {
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager
    @Environment(\.tlsEscalaTexto) private var escala
    @State private var filtro = ""

    init(sesion: VaultSession) {
        self.sesion = sesion
    }

    private var almacen: AlmacenBases { AlmacenBases.de(sesion) }

    var body: some View {
        ContenedorPantalla(destino: .todasLasBases) {
            CabeceraAzulNoche(rotulo: "\(sesion.entry.nombre) · \(CatalogoBases.deSerie.count) bases en 6 áreas",
                              titulo: "Todas las bases",
                              subtitulo: "Cada base reúne las fichas de un tipo, estén en la carpeta que estén. Elige una para verla en tabla, tablero, calendario, galería o lista.",
                              altoMinimo: TLSAltura.cabeceraBase) {
                AvatarCabecera(simbolo: "tablecells")
            } acciones: {
                campoFiltro
            }
            let grupos = gruposVisibles
            if grupos.isEmpty && apagadas.isEmpty {
                VacioExplicado(icono: "magnifyingglass", titulo: "Ninguna base se llama así",
                               porQue: "Prueba con «facturas» o «reuniones», o borra el filtro.",
                               accion: "Borrar el filtro", alPulsar: { filtro = "" })
            }
            ForEach(grupos, id: \.grupo) { g in
                seccion(g.grupo.titulo, area: grupoArea(g.grupo), bases: g.bases)
            }
            if !apagadas.isEmpty {
                seccion("Apagadas", area: nil, bases: apagadas, apagada: true)
            }
            Text("El número de cada base es el de sus fichas abiertas; debajo, lo urgente. Fija las que más uses en la barra lateral desde su menú.")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
        }
        .task(id: sesion.revision) { await almacen.cargarTodas() }
    }

    private var campoFiltro: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(TLSPaleta.subtituloCabecera.color).accessibilityHidden(true)
            TextField("Filtrar bases", text: $filtro)
                .textFieldStyle(.plain)
                .foregroundStyle(TLSPaleta.sobreColor.color)
                .frame(width: 180)
                .accessibilityLabel("Filtrar bases por nombre")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Capsule(style: .circular).fill(TLSPaleta.sobreCabeceraSuave.color))
    }

    private func grupoArea(_ g: GrupoBase) -> AreaCode? {
        if case .area(let a) = g { return a }
        return nil
    }

    private func pasaFiltro(_ c: ColeccionBase) -> Bool {
        let q = TextFolding.fold(filtro).trimmingCharacters(in: .whitespaces)
        return q.isEmpty || TextFolding.fold(c.nombre).contains(q) || TextFolding.fold(c.singular).contains(q)
    }

    private func apagada(_ c: ColeccionBase) -> Bool { almacen.ajustes.apagada(c) }

    private var gruposVisibles: [(grupo: GrupoBase, bases: [ColeccionBase])] {
        CatalogoBases.grupos.compactMap { g in
            let bases = g.bases.filter { pasaFiltro($0) && !apagada($0) }
            return bases.isEmpty ? nil : (g.grupo, bases)
        }
    }

    private var apagadas: [ColeccionBase] { CatalogoBases.deSerie.filter { pasaFiltro($0) && apagada($0) } }

    private func seccion(_ titulo: String, area: AreaCode?, bases: [ColeccionBase], apagada: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(spacing: TLSEspacio.e8) {
                if let area {
                    IconoArea(area.tlsArea, tamano: 24)
                } else {
                    Image(systemName: apagada ? "power" : "square.grid.2x2")
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                Text(area.flatMap { sesion.area($0)?.etiquetaNumerada } ?? titulo)
                    .tlsTexto(TLSTipo.tituloSeccion)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Text(FormatoBase.cuenta(bases.count, "base", "bases"))
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            // Arriba, no centradas: las piezas de una fila empiezan a la misma altura (como la rejilla de M2-Bases).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: TLSEspacio.entreMosaicos, alignment: .top)],
                      alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
                ForEach(bases) { c in
                    if apagada { piezaApagada(c) } else { pieza(c) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(titulo)
    }

    private func pieza(_ c: ColeccionBase) -> some View {
        let d = almacen.datos[c.id]
        let fijada = sesion.barraLateral.estaFijada(c.id)
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(alignment: .top, spacing: TLSEspacio.e8) {
                Button { navegar(.base(c.id), modo: .automatico) } label: {
                    HStack(alignment: .top, spacing: TLSEspacio.e12) {
                        if let a = c.tlsArea {
                            IconoArea(a, tamano: 32, simbolo: c.icono)
                        } else {
                            Image(systemName: c.icono)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TLSPaleta.sobrePrincipal.color)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: TLSRadio.iconoArea32, style: .continuous)
                                    .fill(TLSPaleta.principal.color))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(c.nombre).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                                    .lineLimit(1)
                                if fijada {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                                        .help("Fijada en la barra lateral")
                                        .accessibilityHidden(true)
                                }
                            }
                            if let u = d?.urgente {
                                Label(u.texto, systemImage: u.nivel.estado.simbolo)
                                    .labelStyle(.titleAndIcon)
                                    .tlsTexto(TLSTipo.secundario)
                                    .foregroundStyle(u.nivel == .info ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                            } else {
                                Text(d.map { $0.vistaPorDefecto.nombre } ?? c.vista.nombre)
                                    .tlsTexto(TLSTipo.secundario)
                                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(d.map { String($0.abiertas) } ?? "—")
                            .tlsTexto(TLSTipo.cifraMedia)
                            .foregroundStyle(TLSPaleta.texto.color)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tlsFocoPropio(radio: TLSRadio.fila)
                .accessibilityLabel("Abrir \(c.nombre)" + (d.map { ", \(FormatoBase.cuenta($0.abiertas, "abierta", "abiertas")) de \($0.filas.count)" } ?? "")
                                    + (fijada ? ", fijada en la barra lateral" : ""))
                menu(c, fijada: fijada)
            }
            Text(d?.frase ?? c.frase)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let u = d?.ultimoCambio {
                Text("Último cambio: \(u)")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
            }
        }
        .padding(TLSEspacio.mosaicoPequeno)
        // Alto mínimo de una pieza con su frase de tres líneas y «Último cambio»: así las de una fila igualan.
        .frame(maxWidth: .infinity, minHeight: 156 * escala, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .contextMenu { opciones(c, fijada: fijada) }
    }

    private func menu(_ c: ColeccionBase, fijada: Bool) -> some View {
        Menu {
            opciones(c, fijada: fijada)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .foregroundStyle(TLSPaleta.textoSecundario.color)
        .fixedSize()
        .help("Abrir, fijar en la barra o crear")
        .accessibilityLabel("Acciones de \(c.nombre)")
    }

    @ViewBuilder private func opciones(_ c: ColeccionBase, fijada: Bool) -> some View {
        Button("Abrir") { navegar(.base(c.id), modo: .entrar) }
        Button("Abrir en pestaña nueva") { navegar(.base(c.id), modo: .pestanaNueva) }
        if fijada {
            Button("Quitar de la barra lateral") { sesion.barraLateral.desfijarBase(c.id, deshacer: undoManager) }
        } else {
            Button("Fijar en la barra lateral") { sesion.barraLateral.fijarBase(c.id, deshacer: undoManager) }
        }
        if c.plantilla != nil {
            Button(c.textoNuevaCorto) { nueva(c) }
                .disabled(!sesion.puedeEscribir)
        }
    }

    /// «Nueva…»: entra en la base y abre su hoja de crear.
    private func nueva(_ c: ColeccionBase) {
        nav?.actualizarRecuerdo(de: .base(c.id)) { $0.extra["nueva"] = "1" }
        navegar(.base(c.id), modo: .entrar)
    }

    private func piezaApagada(_ c: ColeccionBase) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            Image(systemName: c.icono)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.nombre).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                Text("Módulo apagado · tus fichas se quedan en la carpeta")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: 0)
            Button("Encender el módulo") { Task { await encender(c) } }
                .tlsBoton(.secundario)
                .disabled(!sesion.puedeEscribir)
                .help(sesion.puedeEscribir ? "Enciende \(c.nombre) en esta carpeta" : "Esta carpeta está en solo lectura")
                .accessibilityLabel("Encender el módulo \(c.nombre)")
        }
        .padding(TLSEspacio.mosaicoPequeno)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
            .strokeBorder(TLSPaleta.separador.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    /// Escribe el módulo encendido en los ajustes de la carpeta (una línea, con Deshacer).
    private func encender(_ c: ColeccionBase) async {
        guard let modulo = c.modulo, let root = sesion.root else { return }
        let ruta = AjustesBases.ficheroModulos
        let actual = AjustesBases.leerTexto(ruta, root: root)
        let nuevo = AjustesBases.textoModulos(actual, modulo: modulo, encendido: true)
        let comando: CommandBus.Comando = actual == nil ? .crear(ruta, texto: nuevo) : .guardarNota(ruta, base: actual ?? "", texto: nuevo)
        _ = try? await sesion.escribir(comando, aviso: "Encendí \(c.nombre): su base ya sale en \(c.area.map { "\($0.numero) · \($0.nombre)" } ?? "Comunes").",
                                       deshacer: undoManager)
        await almacen.cargarTodas(forzar: true)
    }
}
