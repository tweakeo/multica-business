import SwiftUI
import TLSCore
import TLSDesign

/// Una acción de la sección «Acciones» de una reunión (`- acción · @responsable · vence AAAA-MM-DD`).
struct AccionDeReunion: Hashable, Identifiable {
    var id: Int { indice }
    let indice: Int
    let linea: String
    let titulo: String
    let responsable: String?
    let vence: LocalDate?
    /// Ya enlaza su tarea (se convirtió antes).
    let convertida: Bool

    /// Lee las líneas `- …` de la sección (sin las guías).
    static func leer(_ contenido: String) -> [AccionDeReunion] {
        var out: [AccionDeReunion] = []
        for (i, l) in contenido.components(separatedBy: "\n").enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") || t.hasPrefix("* ") else { continue }
            var partes = String(t.dropFirst(2)).components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
            let convertida = t.contains("](") || t.contains("[[")
            let titulo = partes.removeFirst().replacingOccurrences(of: #"^\[[ xX]\]\s*"#, with: "", options: .regularExpression)
            var responsable: String?
            var vence: LocalDate?
            for p in partes {
                if p.hasPrefix("@") { responsable = String(p.dropFirst()) }
                if p.lowercased().hasPrefix("vence"), let d = LocalDate(parsing: String(p.dropFirst(5)).trimmingCharacters(in: .whitespaces)) { vence = d }
            }
            guard !titulo.isEmpty else { continue }
            out.append(AccionDeReunion(indice: i, linea: l, titulo: LinkParser.plainText(titulo), responsable: responsable, vence: vence, convertida: convertida))
        }
        return out
    }
}

/// Reunión Hecha (§3.4): «Acciones» arriba con «Convertir en tareas»: cada acción, una casilla; al confirmar nacen
/// las tareas enlazadas (con su proyecto u oportunidad y su empresa) y cada línea enlaza su tarea.
struct AccionesReunion: View {
    let modelo: FichaModelo
    @State private var elegidas: Set<Int> = []
    @State private var convirtiendo = false

    var body: some View {
        let acciones = AccionDeReunion.leer(MarkdownSections.content(of: "Acciones", in: modelo.cuerpo ?? "") ?? "")
        let pendientes = acciones.filter { !$0.convertida }
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack {
                Text("Acciones").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                Spacer()
                BotonPrincipal(convirtiendo ? "Creando…" : "Convertir en tareas",
                               motivoDesactivado: elegidas.isEmpty ? (pendientes.isEmpty ? "No hay acciones sin convertir" : "Elige al menos una")
                                   : modelo.motivoSoloLectura.map { "No se puede: \($0)" }) {
                    let lista = pendientes.filter { elegidas.contains($0.indice) }
                    Task {
                        convirtiendo = true
                        await Self.convertir(lista, modelo: modelo)
                        convirtiendo = false
                        elegidas = []
                    }
                }
            }
            if acciones.isEmpty {
                Text("Sin acciones apuntadas. Escríbelas en «Acciones», una por línea: «- acción · @responsable · vence AAAA-MM-DD».")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(acciones) { a in
                Toggle(isOn: Binding(get: { a.convertida || elegidas.contains(a.indice) },
                                     set: { v in if v { elegidas.insert(a.indice) } else { elegidas.remove(a.indice) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.titulo).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                        Text([a.responsable.map { "@\($0)" }, a.vence.map { "vence " + FormatoFicha.fechaConDia($0, hoy: modelo.hoy) },
                              a.convertida ? "ya es una tarea" : nil].compactMap { $0 }.joined(separator: " · "))
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(a.convertida || !modelo.puedeEscribir)
            }
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .onAppear { elegidas = Set(pendientes.map(\.indice)) }
    }

    /// Crea una tarea por acción (cada una con su Deshacer) y deja la línea enlazando su tarea.
    static func convertir(_ acciones: [AccionDeReunion], modelo: FichaModelo) async {
        guard !acciones.isEmpty, EdicionRelaciones.comprobarEscritura(modelo.sesion) else { return }
        var enlaces: [Int: String] = [:]
        for a in acciones {
            await modelo.almacen.actualizar()
            guard let foto = modelo.almacen.foto, let grafo = modelo.grafo else { return }
            let r = modelo.ruta
            let nueva = NuevaTarea(titulo: a.titulo, proyecto: grafo.destinos(de: r, propiedad: "proyecto").first,
                                   oportunidad: grafo.destinos(de: r, propiedad: "oportunidad").first,
                                   empresa: grafo.destinos(de: r, propiedad: "empresa").first,
                                   responsable: a.responsable, estado: .porHacer, vence: a.vence,
                                   origen: "reunion:\(r.stem)", autor: modelo.sesion.autor)
            do {
                let nota = try TaskStore(snapshot: foto).crear(nueva)
                try await modelo.sesion.escribir(plan: nota.plan, aviso: "Creé \(nota.numero ?? "la tarea") desde la reunión")
                modelo.almacen.invalidar()
                enlaces[a.indice] = NombresDeFicha.enlaceMarkdown(nota.numero ?? a.titulo, desde: r, a: nota.ruta)
            } catch let e as TareaError {
                modelo.sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
                return
            } catch {
                return
            }
        }
        // Cada línea convertida enlaza su tarea (una sola escritura de la sección).
        await modelo.almacen.actualizar()
        guard let texto = modelo.almacen.foto?.text(modelo.ruta) else { return }
        let cuerpo = NoteDocument(text: texto).body
        guard let actual = MarkdownSections.content(of: "Acciones", in: cuerpo) else { return }
        var lineas = actual.components(separatedBy: "\n")
        for (i, enlace) in enlaces where i < lineas.count { lineas[i] += " → \(enlace)" }
        await modelo.guardarSeccion("Acciones", texto: lineas.joined(separator: "\n"))
    }
}

/// Reunión Prevista (§3.4): arriba «Antes de la reunión» (la ficha previa) y el objetivo; debajo, el Resumen.
struct ResumenReunion: View {
    let modelo: FichaModelo
    let irA: (String) -> Void

    var body: some View {
        let cuerpo = modelo.cuerpo ?? ""
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ForEach(["Antes de la reunión", "Objetivo"], id: \.self) { s in
                if MarkdownSections.content(of: s, in: cuerpo) != nil {
                    BloqueSeccion(modelo: modelo, titulo: s, ruta: modelo.ruta, cuerpo: cuerpo)
                }
            }
            PestanaResumen(modelo: modelo, irA: irA)
        }
    }
}
