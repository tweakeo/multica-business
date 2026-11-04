import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol mika. Decidir lo que traen los asistentes (PLAN §5.2 «Qué es una tarjeta de la bandeja», §6.3), sobre lo
// de F2 (`Decidir`, `AccionesDecision`): siempre como la persona, con aviso y Deshacer cuando toca la carpeta.
//
// | Tarjeta | Opción 1 (la recomendada) | Otra opción | Descartar |
// |---|---|---|---|
// | Propuesta o mejora con plan | Se aplica el plan guardado (`EscrituraDeAsistente.aplicar`) | Se apunta tu decisión y el plan no se aplica | El plan no se aplica (Cancelada) |
// | Pregunta de un asistente | Tu respuesta en su ficha y **el asistente sigue** (`AgentHost.responder`) | — | Cancelada |
// | CRITERIO | «Escribir el criterio en su sistema»: una línea en «Aprendido» de la ficha del sistema | «Seguir como hasta ahora»: no vuelve | — |
// | Permisos cambiados fuera | «Confirmar los cambios» | «Volver a los de antes» | — |

extension Decidir {
    /// La parte de los asistentes de la empresa.
    static func asistentes(_ sesion: VaultSession) -> AsistentesDeLaEmpresa { AsistentesDeLaEmpresa.de(sesion) }

    /// Una pregunta de un asistente: tu respuesta queda en su ficha (y la cierra) y el asistente sigue con la misma
    /// conversación. Sin el motor, la respuesta escrita basta: al arrancar, el motor la recoge.
    @discardableResult
    static func responderAlAsistente(_ t: TarjetaDecision, texto: String, sesion: VaultSession) async -> Bool {
        guard await responder(t, texto: texto, sesion: sesion) else { return false }
        if let r = t.ruta, let host = asistentes(sesion).host {
            _ = try? await host.responder(pregunta: r.raw, texto: texto, autor: sesion.persona)
        }
        await asistentes(sesion).cambio()
        return true
    }

    /// Una propuesta con su plan: la 1 (la recomendada) aplica el plan como tú; otra, apunta tu decisión y deja el plan
    /// sin aplicar.
    @discardableResult
    static func decidirPropuesta(_ t: TarjetaDecision, propuesta id: String, opcion: OpcionDecision, sesion: VaultSession) async -> Bool {
        guard let escritura = asistentes(sesion).escritura else {
            sesion.aviso = Aviso(motivoSoloLectura(sesion).map { "Solo lectura: \($0)." } ?? "Aún se está abriendo.", estado: .atencion)
            return false
        }
        do {
            if opcion.numero == (t.recomendada?.numero ?? 1) {
                let r = try await escritura.aplicar(id, autor: sesion.autor)
                sesion.registrarDeshacer(r, descripcion: "Aplicar «\(AccionesDecision.corto(t.titulo))»",
                                         aviso: "Aplicado: «\(AccionesDecision.corto(t.titulo))»", deshacer: sesion.undoManagerActivo)
                // Tutorial (F4): «Aprueba la primera propuesta de Mika» del recorrido con tu empresa.
                TutorialEventos.registrar(.propuestaAprobada, empresa: sesion.entry.id)
            } else {
                try await escritura.descartar(id, autor: sesion.autor, motivo: "Elegiste la opción \(opcion.numero): \(opcion.texto).")
                // «Dejarlo como está» no es una decisión que apuntar: solo no se aplica.
                if TextFolding.fold(opcion.texto).hasPrefix("dejarlo como esta") {
                    sesion.aviso = Aviso("Se queda como está: «\(AccionesDecision.corto(t.titulo))»", estado: .bien)
                } else {
                    try await apuntar(opcion.texto, t: t, sesion: sesion, aviso: "Decidido: «\(AccionesDecision.corto(opcion.texto))»")
                }
            }
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
        await asistentes(sesion).cambio()
        return true
    }

    /// «Aprobar con mis cambios» en una propuesta: tu decisión, con tus palabras, en el registro; el plan del asistente
    /// no se aplica (si quieres cambiar algo, lo cambias tú).
    @discardableResult
    static func decidirPropuestaConMisPalabras(_ t: TarjetaDecision, propuesta id: String, texto: String, porque: String?,
                                               sesion: VaultSession) async -> Bool {
        guard let escritura = asistentes(sesion).escritura else { return false }
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return false }
        do {
            try await escritura.descartar(id, autor: sesion.autor, motivo: "Lo decidiste con tus palabras: \(limpio).")
            try await apuntar(limpio, porque: porque, t: t, sesion: sesion, aviso: "Decidido: «\(AccionesDecision.corto(limpio))»")
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
        await asistentes(sesion).cambio()
        return true
    }

    /// «Descartar» una propuesta: no se aplica nada.
    @discardableResult
    static func descartarPropuesta(_ t: TarjetaDecision, propuesta id: String, motivo: String?, sesion: VaultSession) async -> Bool {
        guard let escritura = asistentes(sesion).escritura else { return false }
        do {
            let m = motivo?.trimmingCharacters(in: .whitespacesAndNewlines)
            try await escritura.descartar(id, autor: sesion.autor, motivo: m?.isEmpty == false ? m : nil)
            sesion.aviso = Aviso("Descartada: «\(AccionesDecision.corto(t.titulo))». No cambia nada.", estado: .bien)
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
        await asistentes(sesion).cambio()
        return true
    }

    /// Una línea en `Decisiones.md` con su origen (la tarjeta), como la persona.
    static func apuntar(_ decision: String, porque: String? = nil, t: TarjetaDecision, sesion: VaultSession, aviso: String) async throws {
        guard let (foto, reloj) = await foto(sesion) else { return }
        let registro = foto.existing(RegistroDecisiones.ruta(foto.layout)) ?? RegistroDecisiones.ruta(foto.layout)
        let origen = t.ruta.map { NombresDeFicha.enlaceMarkdown(t.titulo, desde: registro, a: $0) }
        let p = porque?.trimmingCharacters(in: .whitespacesAndNewlines)
        let (plan, _) = try RegistroDecisiones.anadir(NuevaDecision(fecha: reloj.hoy, decision: decision, porque: p?.isEmpty == false ? p : nil,
                                                                   area: t.area?.nombre, origen: origen),
                                                      en: foto, autor: sesion.autor)
        try await sesion.escribirConDominio(plan: plan, aviso: aviso, deshacer: sesion.undoManagerActivo)
    }

    // MARK: Permisos cambiados fuera de la app

    @discardableResult
    static func confirmarPermisos(sesion: VaultSession) async -> Bool {
        guard let a = asistentes(sesion).autorizador else { return false }
        do {
            try DecisionesDeGobierno.confirmarPermisos(a, autor: sesion.autor)
            sesion.aviso = Aviso("Confirmado: los asistentes trabajan ya con los permisos nuevos.", estado: .bien)
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
        await asistentes(sesion).host?.ajustesCambiaron()
        await asistentes(sesion).cambio()
        return true
    }

    @discardableResult
    static func volverALosPermisosDeAntes(sesion: VaultSession) async -> Bool {
        guard let a = asistentes(sesion).autorizador, let bus = sesion.bus else { return false }
        do {
            if let r = try await DecisionesDeGobierno.volverALosDeAntes(a, bus: bus, autor: sesion.autor) {
                sesion.registrarDeshacer(r, descripcion: "Volver a los permisos de antes", aviso: "Vuelven los permisos que habías confirmado",
                                         deshacer: sesion.undoManagerActivo)
            }
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
        await asistentes(sesion).host?.ajustesCambiaron()
        await asistentes(sesion).cambio()
        return true
    }

    // MARK: CRITERIO

    /// Las fichas de sistema donde se puede escribir el criterio de un asistente (las de su área; sin plantillas ni
    /// nada privado).
    static func sistemas(de asistente: String?, foto: VaultSnapshot) -> [VaultPath] {
        let area = asistente.flatMap { s in PerfilDeAsistente.deSerie.first { $0.slug == s }?.area } ?? .direccion
        let carpeta = foto.layout.areaFolder(area).appending("Sistemas")
        return foto.notes.filter { p in
            p.isDescendant(of: carpeta) && p.raw.hasSuffix(".md") && !foto.layout.isPrivate(p)
                && !VaultSnapshot.isTemplatePath(p) && !foto.layout.isArchived(p)
        }
        .sorted { $0.stem.localizedStandardCompare($1.stem) == .orderedAscending }
    }

    /// «Escribir el criterio en su sistema»: una línea con fecha en «Aprendido» de la ficha del sistema (solo se añade;
    /// la apruebas tú). Sin ficha de sistema, una tarea para ti con el texto. La tarjeta no vuelve.
    @discardableResult
    static func escribirCriterio(_ t: TarjetaDecision, criterio: String, en sistema: VaultPath?, sesion: VaultSession) async -> Bool {
        let texto = criterio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, let a = asistentes(sesion).autorizador else { return false }
        let hoy = AlmacenHoy.de(sesion).datos?.hoy ?? sesion.hoy
        do {
            if let s = sistema {
                let nombre = t.gobierno?.asistente.map(AsistenteConfigurado.nombre(de:)) ?? "el asistente"
                let linea = "- \(hoy) · \(texto) (criterio de \(nombre), tras tres veces igual) · lo aprobó \(sesion.persona)"
                let plan = WritePlan(autor: sesion.autor, descripcion: "Criterio en «\(s.stem)»",
                                     ops: [.appendToSection(s, section: "Aprendido", text: linea)])
                try await sesion.escribir(plan: plan, aviso: "Criterio apuntado en «\(s.stem)»", deshacer: sesion.undoManagerActivo)
            } else {
                _ = try await NuevaTareaHoja.crear(titulo: "Escribir el criterio: \(AccionesDecision.corto(texto))", area: t.area,
                                                   proyecto: nil, responsable: sesion.persona, planificada: nil, sesion: sesion,
                                                   deshacer: sesion.undoManagerActivo)
            }
            try DecisionesDeGobierno.descartar(t, autorizador: a, autor: sesion.autor, hoy: hoy)
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
        await asistentes(sesion).cambio()
        return true
    }

    /// «Seguir como hasta ahora» (CRITERIO) o descartar la de permisos: no vuelve.
    @discardableResult
    static func dejarComoEsta(_ t: TarjetaDecision, sesion: VaultSession) async -> Bool {
        guard let a = asistentes(sesion).autorizador else { return false }
        do {
            try DecisionesDeGobierno.descartar(t, autorizador: a, autor: sesion.autor, hoy: AlmacenHoy.de(sesion).datos?.hoy ?? sesion.hoy)
            sesion.aviso = Aviso("Sigue como hasta ahora.", estado: .bien)
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
        await asistentes(sesion).cambio()
        return true
    }

    /// El texto de serie del criterio («Lo que prepara Comercial para enviar un correo sale como lo deja»).
    static func criterioSugerido(_ t: TarjetaDecision) -> String {
        guard let g = t.gobierno, let s = g.asistente, let a = g.accion else { return "" }
        if t.titulo.hasPrefix("Corriges") { return "" }
        let accion = a.enFrase
        return "Lo que prepara \(AsistenteConfigurado.nombre(de: s)) para \(accion) suele salir como lo deja: revísalo de un vistazo."
    }
}

// MARK: - La diferencia de una propuesta

/// Una línea de la diferencia, ya en llano.
enum LineaDePropuesta: Hashable, Sendable {
    case anadida(String)
    case quitada(String)
    case igual(String)
    case propiedad(nombre: String, antes: String?, despues: String?)
    case mas(Int)
}

/// Lo que cambia en un fichero si se aprueba.
struct BloqueDiferencia: Identifiable, Hashable, Sendable {
    var id: String { ruta.raw + "|" + resumen }
    let ruta: VaultPath
    let titulo: String
    /// «Nueva», «Se añade a «Aprendido»», «Cambia».
    let resumen: String
    let lineas: [LineaDePropuesta]
}

/// La diferencia de un plan guardado frente a lo que hay ahora en la carpeta (PLAN §5.2: «Propuestas de mejora con la
/// diferencia a la vista»). Pura.
enum DiferenciaDePropuesta {
    static let maximoLineas = 40

    static func de(_ plan: WritePlan, foto: VaultSnapshot) -> [BloqueDiferencia] {
        plan.ops.compactMap { bloque($0, foto: foto) }
    }

    static func titulo(_ p: VaultPath, foto: VaultSnapshot) -> String {
        if foto.layout.isPrivate(p) { return "Una nota privada" }
        return foto.text(p).flatMap { DetalleDecision.tituloDeTexto($0) } ?? p.stem
    }

    static func bloque(_ op: WriteOp, foto: VaultSnapshot) -> BloqueDiferencia? {
        let p = op.path
        let titulo = titulo(p, foto: foto)
        // Lo privado no se enseña ni en la diferencia.
        if foto.layout.isPrivate(p) { return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Cambia", lineas: []) }
        let actual = foto.text(p) ?? ""
        switch op {
        case .create(_, let data):
            let t = String(decoding: data, as: UTF8.self)
            return BloqueDiferencia(ruta: p, titulo: DetalleDecision.tituloDeTexto(t) ?? p.stem, resumen: "Nueva",
                                    lineas: recortar(lineasDeTexto(t).map(LineaDePropuesta.anadida)))
        case .mergeFrontmatter(_, let set, let unset):
            let fm = foto.frontmatter(p)
            var l: [LineaDePropuesta] = set.map { .propiedad(nombre: $0.key, antes: fm.text($0.key), despues: $0.value.displayText) }
            l += unset.map { .propiedad(nombre: $0, antes: fm.text($0), despues: nil) }
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Cambian sus propiedades", lineas: l)
        case .appendToSection(_, let s, let text, _):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Se añade a «\(s)»", lineas: recortar(lineasDeTexto(text).map(LineaDePropuesta.anadida)))
        case .replaceSection(_, let s, let text, _):
            let cuerpo = NoteDocument(text: actual).body
            let antes = MarkdownSections.content(of: s, in: cuerpo) ?? ""
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Cambia «\(s)»", lineas: diferencia(antes: antes, despues: text))
        case .replaceBody(_, let body, _):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Cambia el texto",
                                    lineas: diferencia(antes: NoteDocument(text: actual).body, despues: body))
        case .saveText(_, _, let text):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Cambia", lineas: diferencia(antes: actual, despues: text))
        case .appendLine(_, let line):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Se añade una línea", lineas: [.anadida(line)])
        case .upsertCSVRow(_, let row, _):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Una fila", lineas: [.anadida(fila(row))])
        case .insertCSVRows(_, let rows, _):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: rows.count == 1 ? "Una fila nueva" : "\(rows.count) filas nuevas",
                                    lineas: recortar(rows.map { .anadida(fila($0)) }))
        case .setTableCells(_, _, _, let clave, let cells):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Cambia la fila «\(clave)»",
                                    lineas: cells.sorted { $0.key < $1.key }.map { .propiedad(nombre: $0.key, antes: nil, despues: $0.value) })
        case .appendTableRow(_, _, let cells):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Una fila nueva", lineas: [.anadida(fila(cells))])
        case .editRanges(_, let edits, _):
            var bytes = Array(actual.utf8)
            for e in edits.sorted(by: { $0.offset > $1.offset }) where e.offset + e.length <= bytes.count {
                bytes.replaceSubrange(e.offset..<(e.offset + e.length), with: Array(e.replacement.utf8))
            }
            let despues = String(decoding: bytes, as: UTF8.self)
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Cambia", lineas: diferencia(antes: actual, despues: despues))
        case .move(_, let destino):
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Se mueve a \(destino.components.dropLast().joined(separator: " › "))", lineas: [])
        case .retire:
            return BloqueDiferencia(ruta: p, titulo: titulo, resumen: "Se retira a Archivo (no se borra)", lineas: [])
        }
    }

    static func fila(_ r: [String: String]) -> String {
        r.sorted { $0.key < $1.key }.filter { !$0.value.isEmpty }.map { "\($0.key): \($0.value)" }.joined(separator: " · ")
    }

    static func lineasDeTexto(_ t: String) -> [String] {
        var l = t.components(separatedBy: "\n")
        while l.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { l.removeLast() }
        return l
    }

    static func recortar(_ l: [LineaDePropuesta]) -> [LineaDePropuesta] {
        l.count > maximoLineas ? Array(l.prefix(maximoLineas)) + [.mas(l.count - maximoLineas)] : l
    }

    /// Diferencia por líneas (subsecuencia común más larga): lo quitado y lo añadido, con una línea igual alrededor.
    static func diferencia(antes: String, despues: String) -> [LineaDePropuesta] {
        let a = lineasDeTexto(antes), b = lineasDeTexto(despues)
        if a == b { return [] }
        let n = a.count, m = b.count
        var todas: [LineaDePropuesta] = []
        if n * m > 1_000_000 {
            todas = a.map(LineaDePropuesta.quitada) + b.map(LineaDePropuesta.anadida)
        } else {
            var t = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
                }
            }
            var i = 0, j = 0
            while i < n || j < m {
                // Lo quitado antes que lo añadido (como se lee una corrección).
                if i < n, j < m, a[i] == b[j] { todas.append(.igual(a[i])); i += 1; j += 1 }
                else if i < n, j == m || t[i + 1][j] >= t[i][j + 1] { todas.append(.quitada(a[i])); i += 1 }
                else { todas.append(.anadida(b[j])); j += 1 }
            }
        }
        // Solo lo que cambia y una línea igual a cada lado.
        var out: [LineaDePropuesta] = []
        for (k, l) in todas.enumerated() {
            if case .igual = l {
                let cerca = [k - 1, k + 1].contains { idx in
                    guard idx >= 0, idx < todas.count else { return false }
                    if case .igual = todas[idx] { return false }
                    return true
                }
                if cerca { out.append(l) }
            } else {
                out.append(l)
            }
        }
        return recortar(out)
    }
}

/// La diferencia de una propuesta, a la vista: lo añadido en verde con «+», lo quitado en rojo con «−» (nunca solo
/// el color), las propiedades por su nombre.
struct DiferenciaPropuestaVista: View {
    let bloques: [BloqueDiferencia]
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ForEach(bloques) { b in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                        Text(b.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text("· \(b.resumen)").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Spacer(minLength: 4)
                        if !sesion.esPrivado(b.ruta), sesion.resumen(de: b.ruta) != nil {
                            Button("Abrir") { navegar(sesion.destino(para: b.ruta), modo: .automatico) }.tlsBoton(.enlace)
                        }
                    }
                    if !b.lineas.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(b.lineas.enumerated()), id: \.offset) { _, l in linea(l) }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(TLSPaleta.superficie.color))
                        .overlay(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).strokeBorder(TLSPaleta.separador.color))
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .accessibilityIdentifier("decision.diferencia")
    }

    @ViewBuilder
    private func linea(_ l: LineaDePropuesta) -> some View {
        switch l {
        // F4 · corrector (revisión de experiencia, P3): en palabras y en letra normal («Se añade: …»), no un diff de código.
        case .anadida(let s): fila("Se añade:", s, TLSPaleta.bien.color, fondo: TLSPaleta.bien.color.opacity(0.10), voz: "Se añade")
        case .quitada(let s): fila("Se quita:", s, TLSPaleta.mal.color, fondo: TLSPaleta.mal.color.opacity(0.10), voz: "Se quita")
        case .igual(let s): fila("", s, TLSPaleta.textoSecundario.color, fondo: .clear, voz: "Sigue igual")
        case .propiedad(let n, let antes, let despues):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text(antes.map { "\($0) → " } ?? "").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                Text(despues ?? "(se quita)").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
            }
            .padding(.vertical, 2)
        case .mas(let n):
            Text("Y \(n) líneas más").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).padding(.top, 4)
        }
    }

    private func fila(_ signo: String, _ s: String, _ color: Color, fondo: Color, voz: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !signo.isEmpty {
                Text(signo).tlsTexto(TLSTipo.secundario).fontWeight(.semibold).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityHidden(true)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(color).frame(width: 3).offset(x: -8).accessibilityHidden(true)
                    }
            }
            Text(s.isEmpty ? " " : s).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fondo)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(voz): \(s)")
    }
}

// MARK: - Permisos cambiados fuera de la app

/// Qué cambió en los permisos de los asistentes (en palabras) y «Confirmar» / «Volver a los de antes».
struct DetallePermisosVista: View {
    let tarjeta: TarjetaDecision
    let sesion: VaultSession
    @State private var estado: EstadoDeConfig?
    @State private var trabajando = false
    @State private var hecho: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let hecho {
                AvisoEnLinea(hecho, estado: .bien)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo("Qué cambió")
                    if let e = estado {
                        if e.ilegible {
                            AvisoEnLinea("El fichero de ajustes no se entiende: los asistentes siguen con lo último que confirmaste.", estado: .atencion)
                        }
                        ForEach(e.cambios, id: \.self) { c in
                            Label(Self.enPalabras(c), systemImage: "arrow.triangle.2.circlepath")
                                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("Mientras no lo confirmes, los asistentes siguen con los permisos de antes. Lo que sea más estricto (apagar, pausar un área, marcar algo privado) ya vale.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                FlujoChips(espacio: 8) {
                    Button("Confirmar") {
                        trabajando = true
                        Task {
                            if await Decidir.confirmarPermisos(sesion: sesion) { hecho = "Confirmado: valen los permisos nuevos." }
                            trabajando = false
                        }
                    }
                    .tlsBoton(.principal)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trabajando || !sesion.puedeEscribir || estado?.ilegible == true)
                    .accessibilityIdentifier("decision.permisos.confirmar")
                    Button("Volver a los de antes") {
                        trabajando = true
                        Task {
                            if await Decidir.volverALosPermisosDeAntes(sesion: sesion) { hecho = "Vuelven los permisos que habías confirmado." }
                            trabajando = false
                        }
                    }
                    .tlsBoton(.secundario)
                    .disabled(trabajando || !sesion.puedeEscribir)
                    MenuPosponer(tarjeta: tarjeta, sesion: sesion)
                }
            }
        }
        .task { estado = await leer() }
    }

    private func leer() async -> EstadoDeConfig? {
        guard let a = AsistentesDeLaEmpresa.de(sesion).autorizador else { return nil }
        return await Task.detached(priority: .userInitiated) { a.estadoDeConfig() }.value
    }

    /// `agente:comercial` → «Lo que puede hacer Comercial».
    static func enPalabras(_ c: String) -> String {
        if c.hasPrefix("agente:") { return "Lo que puede hacer \(AsistenteConfigurado.nombre(de: String(c.dropFirst(7))))" }
        switch c {
        case "interruptor": return "Si los asistentes están encendidos"
        case "pausa": return "Las áreas en pausa"
        case "privado": return "Lo que es privado"
        case "funciones": return "Cuánto hacen solos en cada función"
        case "avisos": return "Cuántos avisos te dan al día"
        default: return c.prefix(1).uppercased() + c.dropFirst()
        }
    }
}

// MARK: - CRITERIO

/// «Escribir el criterio en su sistema» o «Seguir como hasta ahora».
struct DetalleCriterioVista: View {
    let tarjeta: TarjetaDecision
    let sesion: VaultSession
    @State private var criterio = ""
    @State private var sistemas: [VaultPath] = []
    @State private var sistema: VaultPath?
    @State private var trabajando = false
    @State private var hecho: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if let hecho {
                AvisoEnLinea(hecho, estado: .bien)
            } else {
                Rotulo("El criterio, en una frase")
                TextField(tarjeta.titulo.hasPrefix("Corriges") ? "Qué corriges siempre, en una frase" : "El criterio", text: $criterio, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4).frame(maxWidth: 640)
                    .accessibilityLabel("El criterio, en una frase")
                if sistemas.isEmpty {
                    Text("Su área aún no tiene fichas de sistema: te dejo una tarea para escribirlo.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else {
                    Picker("En la ficha del sistema", selection: $sistema) {
                        ForEach(sistemas, id: \.self) { s in Text(sesion.titulo(de: s)).tag(Optional(s)) }
                    }
                    .frame(maxWidth: 420)
                }
                FlujoChips(espacio: 8) {
                    Button(sistemas.isEmpty ? "Crear la tarea" : "Escribir el criterio en su sistema") {
                        trabajando = true
                        Task {
                            if await Decidir.escribirCriterio(tarjeta, criterio: criterio, en: sistema, sesion: sesion) {
                                hecho = sistema.map { "Apuntado en «Aprendido» de \(sesion.titulo(de: $0))." } ?? "Te dejé una tarea para escribirlo."
                            }
                            trabajando = false
                        }
                    }
                    .tlsBoton(.principal)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trabajando || !sesion.puedeEscribir || criterio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Seguir como hasta ahora") {
                        trabajando = true
                        Task {
                            if await Decidir.dejarComoEsta(tarjeta, sesion: sesion) { hecho = "Sigue como hasta ahora: esta tarjeta no vuelve." }
                            trabajando = false
                        }
                    }
                    .tlsBoton(.secundario)
                    .disabled(trabajando || !sesion.puedeEscribir)
                    MenuPosponer(tarjeta: tarjeta, sesion: sesion)
                }
            }
        }
        .task {
            if criterio.isEmpty { criterio = Decidir.criterioSugerido(tarjeta) }
            guard let foto = await sesion.instantanea() else { return }
            sistemas = Decidir.sistemas(de: tarjeta.gobierno?.asistente, foto: foto)
            if sistema == nil { sistema = sistemas.first }
        }
    }
}

// MARK: - Respuestas propuestas en una pregunta de un asistente

/// Las respuestas que propone un asistente en su pregunta («Lo que propongo»: `1. … (recomendada)`), como mucho 3.
struct RespuestaPropuesta: Hashable, Sendable, Identifiable {
    var id: Int { numero }
    let numero: Int
    let texto: String
    let recomendada: Bool

    static func de(_ cuerpo: String) -> [RespuestaPropuesta] {
        guard let s = MarkdownSections.content(of: "Lo que propongo", in: cuerpo, level: 2) else { return [] }
        var out: [RespuestaPropuesta] = []
        for l in s.components(separatedBy: .newlines) {
            let t = l.trimmingCharacters(in: .whitespaces)
            guard let r = t.range(of: #"^(\d)[\.\)]\s+"#, options: .regularExpression), let n = Int(t[r].prefix(1)) else { continue }
            var texto = String(t[r.upperBound...])
            var rec = false
            if let m = texto.range(of: "(recomendada)", options: [.caseInsensitive, .diacriticInsensitive]) {
                rec = true
                texto.removeSubrange(m)
            }
            texto = texto.trimmingCharacters(in: .whitespaces)
            if !texto.isEmpty { out.append(RespuestaPropuesta(numero: n, texto: texto, recomendada: rec)) }
        }
        return Array(out.prefix(3))
    }
}
