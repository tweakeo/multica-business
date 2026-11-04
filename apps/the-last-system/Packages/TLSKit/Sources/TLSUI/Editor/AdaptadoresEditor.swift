import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSEditor
import TLSVisores

/// Cómo escribe enlaces la carpeta en el cuerpo de las notas.
enum EstiloEnlacesCarpeta: Sendable, Hashable {
    /// `[Panadería Sol](../Empresas/panaderia-sol.md)`: el estilo de G3 (SISTEMAS §1.6), por defecto.
    case markdown
    /// `[[panaderia-sol|Panadería Sol]]`: si la carpeta es de Obsidian con «Usar enlaces Markdown» apagado.
    case wiki

    /// Lo que dice `.obsidian/app.json` (`useMarkdownLinks`); si no lo dice, el de G3. Solo lee.
    static func de(raiz: URL?) -> EstiloEnlacesCarpeta {
        guard let raiz else { return .markdown }
        // Sin seguir enlaces ni descargar de iCloud.
        guard let datos = AjustesBases.leerTexto(VaultPath(".obsidian/app.json"), root: raiz).map({ Data($0.utf8) }),
              let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let usaMarkdown = json["useMarkdownLinks"] as? Bool else { return .markdown }
        return usaMarkdown ? .markdown : .wiki
    }
}

/// Destino Markdown relativo de `hasta` visto desde la nota `desde`, con `%20` (como los de G3).
enum RutaRelativa {
    static func markdown(desde: VaultPath, hasta: VaultPath) -> String {
        let base = desde.parent?.components ?? []
        let destino = hasta.components
        var comun = 0
        while comun < min(base.count, destino.count - 1),
              TextFolding.pathKey(base[comun]) == TextFolding.pathKey(destino[comun]) { comun += 1 }
        let partes = Array(repeating: "..", count: base.count - comun) + Array(destino[comun...])
        var texto = partes.map(codificar).joined(separator: "/")
        if !equilibrado(texto) {
            texto = texto.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        }
        return texto
    }

    /// Como `MarkdownDestination.encode` del núcleo: espacios, `%`, `#`, `<`, `>` y `\` codificados; las tildes, tal cual.
    static func codificar(_ parte: String) -> String {
        var out = ""
        for u in parte.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch u {
            case " ": out += "%20"
            case "%": out += "%25"
            case "#": out += "%23"
            case "<": out += "%3C"
            case ">": out += "%3E"
            case "\\": out += "%5C"
            default:
                if u.value < 0x20 || u.value == 0x7F {
                    for b in String(u).utf8 { out += String(format: "%%%02X", b) }
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out
    }

    static func equilibrado(_ s: String) -> Bool {
        var n = 0
        for c in s {
            if c == "(" { n += 1 }
            if c == ")" { n -= 1; if n < 0 { return false } }
        }
        return n == 0
    }
}

/// Resuelve enlaces a ficheros que no son notas (`![[factura.pdf]]` por su nombre). El índice solo guarda
/// notas, así que para los adjuntos se usa la lista completa de ficheros de una foto de la carpeta, que se
/// lee en segundo plano la primera vez que hace falta (y de nuevo, como mucho cada 10 s, si algo no se
/// encuentra tras un cambio). Nunca descarga nada de iCloud.
@MainActor
final class ResolutorAdjuntos {
    weak var sesion: VaultSession?
    private var resolutor: LinkResolver?
    private var revision = -1
    private var cargadoEn: Date?
    private var cargando: Task<Void, Never>?
    private var fallos = false
    /// Se llama cuando llega una foto nueva y antes algo no se encontró (para repintar la nota).
    var alCargar: (@MainActor () -> Void)?

    init(sesion: VaultSession) { self.sesion = sesion }

    /// Ruta a la que lleva un enlace (`[[x]]` o destino Markdown) escrito en `desde`.
    func resolver(_ enlace: String, desde: VaultPath) -> VaultPath? {
        guard let sesion else { return nil }
        if let r = sesion.resolverEnlace(enlace, desde: desde) { return r }
        if let r = resolutor?.resolve(enlace, from: desde)
            ?? (enlace.hasPrefix("[[") ? nil : resolutor?.resolve("[[\(enlace)]]", from: desde)) { return r }
        fallos = true
        let reciente = cargadoEn.map { Date().timeIntervalSince($0) < 10 } ?? false
        if cargando == nil, revision != sesion.revision, !reciente { cargar() }
        return nil
    }

    private func cargar() {
        guard let sesion else { return }
        let rev = sesion.revision
        cargando = Task { [weak self, weak sesion] in
            let foto = await sesion?.instantanea()
            guard let self else { return }
            self.cargando = nil
            self.cargadoEn = Date()
            guard let foto else { return }
            self.resolutor = foto.resolver
            self.revision = rev
            if self.fallos {
                self.fallos = false
                self.alCargar?()
            }
        }
    }

    /// Espera a que termine la lectura en curso (pruebas).
    func esperar() async {
        await cargando?.value
    }
}

/// Enlaces de una nota: autocompletado (`[[` y `](`) con el índice (nombres y otros nombres), y resolución
/// al ⌘clic con la regla de Obsidian del núcleo (`LinkResolver`). Nunca sugiere lo privado.
@MainActor
final class EnlacesDeNota: AutocompletarEnlaces, ResolutorEnlaces {
    let ruta: VaultPath
    weak var sesion: VaultSession?
    let adjuntos: ResolutorAdjuntos
    private(set) lazy var estiloCarpeta: EstiloEnlacesCarpeta = EstiloEnlacesCarpeta.de(raiz: sesion?.root)

    /// Otros nombres (`aliases`, `nombre`, `titulo`) de cada nota, leídos una vez por revisión.
    private var otrosNombres: [(plegado: String, nombre: String, ruta: VaultPath)] = []
    private var revisionNombres = -1
    private var nombresLeidosEn: Date?
    /// Adjuntos que se pueden incrustar (PDF, imágenes, audio, vídeo) por su nombre plegado, para `![[` (R1).
    private var adjuntosPorNombre: [(plegado: String, ruta: VaultPath)] = []
    private var revisionAdjuntos = -1
    private var adjuntosLeidosEn: Date?

    init(ruta: VaultPath, sesion: VaultSession, adjuntos: ResolutorAdjuntos? = nil) {
        self.ruta = ruta
        self.sesion = sesion
        self.adjuntos = adjuntos ?? ResolutorAdjuntos(sesion: sesion)
    }

    // MARK: Autocompletar

    func sugerencias(_ consulta: String, disparador: DisparadorEnlace) async -> [SugerenciaEnlace] {
        guard let sesion else { return [] }
        let q = consulta.trimmingCharacters(in: .whitespaces)
        var vistas = Set<VaultPath>()
        var out: [SugerenciaEnlace] = []
        func anadir(_ r: NoteSummary, porOtroNombre: String? = nil) {
            guard r.path != ruta, !r.privado, vistas.insert(r.path).inserted else { return }
            out.append(SugerenciaEnlace(id: r.path.raw, titulo: r.title,
                                        detalle: "\(r.kind.etiqueta) · \(r.path.carpetaVisible)",
                                        simbolo: r.kind.systemImage, porOtroNombre: porOtroNombre))
        }
        if q.isEmpty {
            for p in sesion.recientes { if let r = sesion.resumen(de: p) { anadir(r) } }
            return out
        }
        for r in await sesion.abrirRapido(q, limite: 12) { anadir(r) }
        await cargarOtrosNombres()
        let plegada = TextFolding.fold(q)
        for n in otrosNombres where n.plegado.hasPrefix(plegada) || n.plegado.contains(" " + plegada) {
            guard out.count < 12, let r = sesion.resumen(de: n.ruta) else { continue }
            anadir(r, porOtroNombre: n.nombre)
        }
        // Los adjuntos por su nombre (como Obsidian con `![[`): el índice solo tiene notas. Nunca lo privado.
        if out.count < 12 {
            await cargarAdjuntos()
            for a in adjuntosPorNombre where out.count < 12 && a.plegado.contains(plegada) {
                guard !sesion.esPrivado(a.ruta), vistas.insert(a.ruta).inserted else { continue }
                let tipo = TipoFichero.de(extension: a.ruta.ext)
                out.append(SugerenciaEnlace(id: a.ruta.raw, titulo: a.ruta.name,
                                            detalle: "\(tipo.nombre) · \(a.ruta.carpetaVisible)", simbolo: tipo.simbolo))
            }
        }
        return out
    }

    /// Lista de adjuntos de una foto de la carpeta (en segundo plano; como mucho cada 30 s, como los otros nombres).
    private func cargarAdjuntos() async {
        guard let sesion, revisionAdjuntos != sesion.revision else { return }
        if let antes = adjuntosLeidosEn, Date().timeIntervalSince(antes) < 30, !adjuntosPorNombre.isEmpty { return }
        revisionAdjuntos = sesion.revision
        adjuntosLeidosEn = Date()
        guard let foto = await sesion.instantanea() else { return }
        adjuntosPorNombre = await Task.detached(priority: .userInitiated) {
            foto.files.filter { p in
                let tipo = TipoFichero.de(extension: p.ext)
                return tipo.seIncrusta && tipo != .texto && !VaultSnapshot.isTemplatePath(p)
            }
            .map { (plegado: TextFolding.fold($0.name), ruta: $0) }
        }.value
    }

    private func cargarOtrosNombres() async {
        guard let sesion, revisionNombres != sesion.revision else { return }
        // Leer la carpeta entera cuesta: como mucho cada 30 s aunque se siga guardando.
        if let antes = nombresLeidosEn, Date().timeIntervalSince(antes) < 30, !otrosNombres.isEmpty { return }
        revisionNombres = sesion.revision
        nombresLeidosEn = Date()
        guard let foto = await sesion.instantanea() else { return }
        otrosNombres = await Task.detached(priority: .userInitiated) {
            var lista: [(String, String, VaultPath)] = []
            for p in foto.notes where !VaultSnapshot.isTemplatePath(p) {
                for prop in foto.frontmatter(p).properties
                    where ["aliases", "alias", "nombre", "titulo", "título"].contains(prop.key.lowercased()) {
                    let valores: [String]
                    switch prop.value {
                    case .list(let l): valores = l
                    case .text(let t): valores = [t]
                    default: valores = []
                    }
                    for v in valores where v.count >= 2 && !v.contains("[[") {
                        lista.append((TextFolding.fold(v), v, p))
                    }
                }
            }
            return lista
        }.value.map { (plegado: $0.0, nombre: $0.1, ruta: $0.2) }
    }

    func insercion(para s: SugerenciaEnlace, disparador: DisparadorEnlace, textoVisible: String?) -> String {
        let destino = VaultPath(s.id)
        switch disparador {
        case .markdown:
            return RutaRelativa.markdown(desde: ruta, hasta: destino) + ")"
        case .wiki:
            switch estiloCarpeta {
            case .markdown:
                let visible = s.titulo.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
                return "[\(visible)](\(RutaRelativa.markdown(desde: ruta, hasta: destino)))"
            case .wiki:
                return wikilink(a: destino, titulo: s.titulo)
            }
        }
    }

    /// `[[nombre|Título]]`, con la ruta si el nombre no es único (regla de Obsidian).
    func wikilink(a destino: VaultPath, titulo: String) -> String {
        let nombre = destino.ext == "md" ? destino.stem : destino.name
        let unico = sesion?.resolverEnlace("[[\(nombre)]]", desde: ruta) == destino
        let objetivo = unico ? nombre : (destino.ext == "md" ? String(destino.raw.dropLast(3)) : destino.raw)
        let visible = titulo.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "]", with: ")")
        return visible == objetivo || visible.isEmpty ? "[[\(objetivo)]]" : "[[\(objetivo)|\(visible)]]"
    }

    // MARK: Resolver y abrir

    func estado(de enlace: EnlaceMarkdown) -> EstadoEnlace {
        if enlace.esExterno { return .externa }
        if enlace.destino.isEmpty { return .existe }
        return adjuntos.resolver(enlace.paraResolver, desde: ruta) == nil ? .rota : .existe
    }

    func abrir(_ enlace: EnlaceMarkdown, apertura: AperturaEnlace) {
        guard let sesion else { return }
        if enlace.esExterno {
            let d = enlace.destino.lowercased().hasPrefix("www.") ? "https://" + enlace.destino : enlace.destino
            if let url = URL(string: d) { NSWorkspace.shared.open(url) }
            return
        }
        // Un ancla sola (`[[#Sección]]`) es de esta misma nota.
        if enlace.destino.isEmpty { return }
        guard let destino = adjuntos.resolver(enlace.paraResolver, desde: ruta) else {
            sesion.linkProblem = "No encuentro «\(enlace.destinoLegible)» en la carpeta de tu empresa."
            return
        }
        let modo: ModoApertura = switch apertura {
        case .aqui: .entrar
        case .pestanaNueva: .pestanaNueva
        case .ventanaNueva: .ventanaNueva
        }
        sesion.navegar(a: sesion.destino(para: destino), modo: modo)
    }
}

/// Incrustaciones de una nota: resuelve el destino con la regla de Obsidian y pide a TLSVisores el
/// contenido (PDF en su página, imagen, reproductor). No descarga nada de iCloud al pintar.
@MainActor
final class IncrustacionesDeNota: ProveedorIncrustaciones {
    let ruta: VaultPath
    weak var sesion: VaultSession?
    let adjuntos: ResolutorAdjuntos

    init(ruta: VaultPath, sesion: VaultSession, adjuntos: ResolutorAdjuntos? = nil) {
        self.ruta = ruta
        self.sesion = sesion
        self.adjuntos = adjuntos ?? ResolutorAdjuntos(sesion: sesion)
    }

    func bloque(para i: Incrustacion) -> BloqueIncrustado? {
        guard let sesion, !i.enlace.esExterno,
              let destino = adjuntos.resolver(i.enlace.paraResolver, desde: ruta) else { return nil }
        let tipo = TipoFichero.de(extension: destino.ext)
        guard tipo.seIncrusta, let url = sesion.url(for: destino) else { return nil }
        let abrir: @MainActor () -> Void = { [weak sesion] in
            sesion?.navegar(a: .fichero(destino), modo: .entrar)
        }
        // Lo privado dentro de una nota que no lo es: no se enseña al pintar; se abre a propósito.
        if sesion.esPrivado(destino), !sesion.esPrivado(ruta) {
            return BloqueIncrustado(alto: 64, altoAmpliado: 64, titulo: destino.stem, simbolo: "lock", abrir: abrir) {
                Text("Este fichero es privado: no se enseña dentro de otras notas. Ábrelo para verlo.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        let alto = i.alto.map { CGFloat($0) } ?? IncrustacionFichero.altoPorDefecto(tipo)
        let ancho = i.ancho.map { CGFloat($0) }
        return BloqueIncrustado(alto: alto, altoAmpliado: IncrustacionFichero.altoAmpliado(tipo, base: alto),
                                titulo: destino.ext == "md" ? destino.stem : destino.name, simbolo: tipo.simbolo, abrir: abrir) {
            ContenidoIncrustado(url: url, tipo: tipo, pagina: i.pagina, ancho: ancho, alAbrir: { abrir() })
        }
    }
}

/// Un trozo de texto de una nota (una sección de una ficha, un borrador) editable como el editor de notas:
/// vista previa en vivo, `[[` con autocompletado, ⌘clic en los enlaces e incrustaciones. Quien lo usa guarda
/// el texto (por ejemplo, con `sustituirSeccion`).
struct EditorTextoDeNota: View {
    @Binding var texto: String
    let ruta: VaultPath
    let sesion: VaultSession
    var soloLectura = false
    @State private var enlaces: EnlacesDeNota
    @State private var incrustaciones: IncrustacionesDeNota

    init(texto: Binding<String>, ruta: VaultPath, sesion: VaultSession, soloLectura: Bool = false) {
        self._texto = texto
        self.ruta = ruta
        self.sesion = sesion
        self.soloLectura = soloLectura
        let adjuntos = ResolutorAdjuntos(sesion: sesion)
        self._enlaces = State(initialValue: EnlacesDeNota(ruta: ruta, sesion: sesion, adjuntos: adjuntos))
        self._incrustaciones = State(initialValue: IncrustacionesDeNota(ruta: ruta, sesion: sesion, adjuntos: adjuntos))
    }

    var body: some View {
        EditorTextoMarkdown(texto: $texto, soloLectura: soloLectura || !sesion.puedeEscribir,
                            autocompletado: enlaces, resolutor: enlaces, incrustaciones: incrustaciones)
    }
}
