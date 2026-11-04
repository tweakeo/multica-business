import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSVisores

/// Filtro de la línea de tiempo (§3.2: Todo · Comentarios · Cambios · Asistentes).
enum FiltroActividad: String, CaseIterable, Identifiable {
    case todo = "Todo", comentarios = "Comentarios", cambios = "Cambios", asistentes = "Asistentes"
    var id: String { rawValue }

    func admite(_ e: EntradaActividad) -> Bool {
        switch self {
        case .todo: true
        case .comentarios: e.tipo == .comentario
        case .cambios: e.tipo == .cambio
        case .asistentes: e.tipo == .asistente
        }
    }
}

/// Una línea de tiempo de actividad (la de la ficha o la de una tarea).
struct LineaDeTiempo: View {
    let entradas: [EntradaActividad]
    let hoy: LocalDate
    @State private var filtro: FiltroActividad = .todo

    var body: some View {
        let lista = entradas.filter(filtro.admite)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            FlujoChips(espacio: 6) {
                ForEach(FiltroActividad.allCases) { f in
                    Button(f.rawValue) { filtro = f }
                        .tlsBoton(filtro == f ? .principal : .secundario, alto: TLSAltura.objetivoMinimo + 4)
                        .accessibilityAddTraits(filtro == f ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Ver")
            if lista.isEmpty {
                Text("Nada de este tipo todavía.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.vertical, TLSEspacio.e8)
            }
            ForEach(Array(lista.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Divider().overlay(TLSPaleta.separador.color) }
                HStack(alignment: .top, spacing: TLSEspacio.e12) {
                    Image(systemName: icono(e))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(e.tipo == .comentario ? TLSPaleta.texto.color : TLSPaleta.principal.color)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(e.tipo == .comentario ? TLSPaleta.bandeja.color : TLSPaleta.principalSuave.color))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text([e.fecha.map { FormatoFicha.fechaConDia($0, hoy: hoy) }, e.hora, e.autor].compactMap { $0 }.joined(separator: " · "))
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func icono(_ e: EntradaActividad) -> String {
        switch e.tipo {
        case .cambio: "pencil"
        case .comentario: "text.bubble"
        case .asistente: "sparkles"
        }
    }
}

/// Pestaña Actividad (§3.2): la línea de tiempo de la ficha con sus filtros y, al pie, «Añadir nota».
struct PestanaActividad: View {
    let modelo: FichaModelo

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                LineaDeTiempo(entradas: ActividadDeFicha.leer(modelo.texto ?? ""), hoy: modelo.hoy)
                Text("Sale de lo apuntado en la propia nota: su actividad, su historial y sus notas con fecha.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .padding(TLSEspacio.e16)
            .background(forma.fill(TLSPaleta.superficie.color))
            .tlsSombra(.uno, forma: forma)
            AnadirNota(modelo: modelo)
        }
    }
}

/// Pestaña Fichero (§3.2): la ruta, el texto tal cual («Ver como texto», ⌘E) con las líneas cambiadas en esta
/// sesión marcadas, lo que se guarda en otras fichas, los enlaces que salen de la nota y su salud, Mostrar en
/// Finder y Copiar la ruta.
struct PestanaFichero: View {
    let modelo: FichaModelo
    @Environment(\.navegar) private var navegar

    var body: some View {
        let texto = modelo.texto ?? ""
        let lineas = texto.components(separatedBy: "\n")
        let cambiadas = modelo.almacen.textoInicial[modelo.ruta].map { DiferenciaDeLineas.cambiadas(antes: $0, despues: texto) } ?? []
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                HStack {
                    Text("Fichero · ver como texto (⌘E)").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Mostrar en Finder") { modelo.sesion.revealInFinder(modelo.ruta) }.tlsBoton(.secundario)
                    Button("Copiar la ruta") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(modelo.ruta.raw, forType: .string)
                        modelo.sesion.aviso = Aviso("Copié la ruta: \(modelo.ruta.raw)", estado: .bien)
                    }
                    .tlsBoton(.secundario)
                }
                Text(modelo.ruta.raw).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color).textSelection(.enabled)
                Text("Lo que verías en cualquier editor. Las relaciones son enlaces en las propiedades. Líneas cambiadas desde que la abriste: \(cambiadas.count), marcadas en azul claro.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lineas.enumerated()), id: \.offset) { i, l in
                            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e12) {
                                Text("\(i + 1)").tlsTexto(TLSTipo.textoPlano).foregroundStyle(TLSPaleta.textoSecundario.color)
                                    .frame(width: 36, alignment: .trailing)
                                Text(l.isEmpty ? " " : l).tlsTexto(TLSTipo.textoPlano).foregroundStyle(TLSPaleta.texto.color)
                                    .fixedSize()
                                if cambiadas.contains(i) {
                                    Text("cambiada").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.principal.color)
                                }
                            }
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cambiadas.contains(i) ? TLSPaleta.principalSuave.color : .clear)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Línea \(i + 1)\(cambiadas.contains(i) ? ", cambiada" : ""): \(l)")
                        }
                    }
                    .textSelection(.enabled)
                }
            }
            .padding(TLSEspacio.e16)
            .background(forma.fill(TLSPaleta.superficie.color))
            .tlsSombra(.uno, forma: forma)
            adjuntosVista.frame(maxWidth: .infinity, alignment: .leading).padding(TLSEspacio.e16).background(forma.fill(TLSPaleta.superficie.color)).tlsSombra(.uno, forma: forma)
            enOtrasFichas.frame(maxWidth: .infinity, alignment: .leading).padding(TLSEspacio.e16).background(forma.fill(TLSPaleta.superficie.color)).tlsSombra(.uno, forma: forma)
            enlacesQueSalen.frame(maxWidth: .infinity, alignment: .leading).padding(TLSEspacio.e16).background(forma.fill(TLSPaleta.superficie.color)).tlsSombra(.uno, forma: forma)
            versionesYObsidian.frame(maxWidth: .infinity, alignment: .leading).padding(TLSEspacio.e16).background(forma.fill(TLSPaleta.superficie.color)).tlsSombra(.uno, forma: forma)
        }
    }

    /// Adjuntos (§3.2): el PDF del documento y los ficheros que no son notas y que esta nota enlaza o incrusta
    /// (`![[acta.pdf]]`, `[extracto](Materiales/extracto.pdf)`). Nada privado.
    static func adjuntos(de modelo: FichaModelo) -> [VaultPath] {
        guard let texto = modelo.texto, let foto = modelo.almacen.foto else { return [] }
        let resolver = modelo.almacen.resolver ?? foto.resolver
        var out: [VaultPath] = []
        if let pdf = DocumentoFicha.pdf(de: modelo) { out.append(pdf) }
        for occ in LinkScanner.scan(texto) where !occ.link.isExternal {
            guard let r = resolver.resolve(occ.link.resolvable, from: modelo.ruta),
                  !["md", "markdown"].contains(r.ext.lowercased()), r != modelo.ruta else { continue }
            out.append(r)
        }
        var vistos = Set<VaultPath>()
        return out.filter { !modelo.sesion.esPrivado($0) && vistos.insert($0).inserted }
    }

    private var adjuntosVista: some View {
        let lista = Self.adjuntos(de: modelo)
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Adjuntos").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            if lista.isEmpty {
                Text(modelo.tipo == .project ? "No enlaza ficheros. Lo que mande el cliente está en la pestaña Materiales."
                        : "No enlaza ni incrusta ficheros (PDF, imágenes, audio o vídeo).")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(lista, id: \.self) { p in
                let tipo = TipoFichero.de(extension: p.ext)
                FilaLista(p.name, detalle: [tipo.nombre, p.parent?.raw].compactMap { $0 }.joined(separator: " · "), icono: tipo.simbolo,
                          accion: { navegar(modelo.sesion.destino(para: p)) })
                    .vistaPrevia(ruta: p, sesion: modelo.sesion)
                    .contextMenu {
                        Button("Abrir") { navegar(modelo.sesion.destino(para: p), modo: .entrar) }
                        Button("Abrir en pestaña nueva") { navegar(modelo.sesion.destino(para: p), modo: .pestanaNueva) }
                        Button("Mostrar en Finder") { modelo.sesion.revealInFinder(p) }
                    }
            }
        }
    }

    /// Versiones (aún sin historial propio) y «Abrir en Obsidian».
    private var versionesYObsidian: some View {
        let raiz = modelo.sesion.root
        let conoceObsidian = raiz.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".obsidian").path) } ?? false
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Versiones").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text("Lo que cambias con la app se deshace con ⌘Z o con «Deshacer» del aviso, y las líneas cambiadas desde que abriste la ficha salen marcadas arriba. Antes de cada cambio, la app guarda una copia del fichero durante 30 días en sus ajustes (fuera de tu carpeta).")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if let raiz, conoceObsidian, let url = Self.urlObsidian(modelo.ruta.url(in: raiz)) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Abrir en Obsidian", systemImage: "arrow.up.forward.app")
                }
                .tlsBoton(.secundario)
            } else {
                Text("Para abrirla en Obsidian, abre antes la carpeta de tu empresa desde Obsidian («Abrir carpeta»).")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// `obsidian://open?path=…` (solo lee; no crea nada en la carpeta).
    static func urlObsidian(_ fichero: URL) -> URL? {
        var c = URLComponents()
        c.scheme = "obsidian"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "path", value: fichero.path)]
        return c.url
    }

    /// «Lo que se guarda en otras fichas»: cada relación que apunta aquí, con su fichero y su línea.
    private var enOtrasFichas: some View {
        let entrantes = (modelo.grafo?.entrantes[modelo.ruta] ?? []).filter { modelo.grafo?.ficha($0.origen)?.privada != true }
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Lo que se guarda en otras fichas").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text("Cada relación vive en una sola ficha. Si la cambias desde aquí, la app escribe allí, una sola línea, con Deshacer.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            if entrantes.isEmpty {
                Text("Ninguna otra ficha guarda una relación con esta.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(entrantes, id: \.self) { e in
                let nombre = modelo.grafo?.ficha(e.origen)?.nombre ?? e.origen.stem
                Button { navegar(modelo.sesion.destino(para: e.origen)) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(nombre) · en «\(e.clave)»").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text(e.origen.raw).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text(linea(e)).tlsTexto(TLSTipo.textoPlano).foregroundStyle(TLSPaleta.texto.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(EstiloFila(alto: TLSAltura.filaLista))
                .focusEffectDisabled()
                .vistaPrevia(ruta: e.origen, sesion: modelo.sesion)
            }
        }
    }

    private func linea(_ e: EnlaceTipado) -> String {
        guard let t = modelo.almacen.foto?.text(e.origen),
              let l = FrontmatterDocument(text: t).rawLines(e.clave) else { return "\(e.clave): \(e.valor)" }
        return l.trimmingCharacters(in: .newlines)
    }

    /// Enlaces que salen de esta nota y su salud (`SaludDeEnlaces`).
    private var enlacesQueSalen: some View {
        let revisados = modelo.almacen.foto.map { SaludDeEnlaces(snapshot: $0).revisar(modelo.ruta) } ?? []
        let salientes = modelo.grafo?.relacionesGuardadas(por: modelo.ruta) ?? []
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Enlaces que salen de esta nota").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            if revisados.isEmpty {
                Label("\(salientes.isEmpty ? "No enlaza a otras fichas desde sus propiedades" : "Todos sus enlaces llevan a su sitio (\(salientes.count) en las propiedades)").",
                      systemImage: TLSEstado.bien.simbolo)
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
            }
            ForEach(revisados, id: \.self) { r in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: TLSEstado.atencion.simbolo).foregroundStyle(TLSPaleta.atencion.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Línea \(r.linea): \(r.enlace)").tlsTexto(TLSTipo.textoPlano)
                        Text(motivo(r)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func motivo(_ r: EnlaceRevisado) -> String {
        switch r.estado {
        case .pendiente: "Aún no existe: se puede crear con su plantilla."
        case .ambiguo(let c): "Hay \(c.count) notas con ese nombre: hay que elegir una."
        case .flojo(let p): "Se encuentra por el nombre (\(p.raw)), pero la ruta escrita no es la suya."
        }
    }
}
