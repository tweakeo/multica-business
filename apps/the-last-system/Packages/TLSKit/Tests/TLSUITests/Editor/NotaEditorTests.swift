import AppKit
import CryptoKit
import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSEditor
@testable import TLSUI

/// Criterios del PLAN §9 F1-5 (editor) con una copia de Ribera en una carpeta temporal: abrir y cerrar no
/// escribe, editar el cuerpo no toca las propiedades, el guardado de una persona no exige `hash_app`, y los
/// cambios de fuera se fusionan o dan conflicto con las dos versiones recuperables.
@Suite("Editor de notas · guardado y criterios F1-5", .serialized)
@MainActor
struct NotaEditorTests {
    let pruebas = SesionEscrituraTests()
    let area = VaultPath("2 · Ventas/Área.md")
    let informe = VaultPath("Buzón/Informe de importación 2026-10-19.md")

    func abrir(_ clase: VaultClass = .demo, escritura: WriteAccess = .permitida) async throws
        -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: clase, escritura: escritura)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        return (e, sesion)
    }

    /// Abre la nota en un modelo como lo hace la pantalla (lectura + editor en una ventana sin enseñar).
    func editor(_ ruta: VaultPath, _ sesion: VaultSession) async throws -> (ModeloNotaEditor, NSWindow) {
        let m = ModeloNotaEditor(ruta: ruta, sesion: sesion)
        m.esperaGuardado = .milliseconds(20)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = m.controlador.scroll
        let nota = try #require(await sesion.leer(ruta))
        m.recibir(nota)
        return (m, w)
    }

    /// Relee la nota y se la pasa al modelo (lo que hace la pantalla con cada revisión).
    func releer(_ m: ModeloNotaEditor, _ sesion: VaultSession) async {
        if let n = await sesion.leer(m.ruta) { m.recibir(n) }
    }

    static func huellas(_ raiz: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.isRegularFileKey])
        while let f = e?.nextObject() as? URL {
            guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !f.path.contains("/.tls/") else { continue }
            out[f.path] = SHA256.hash(data: try Data(contentsOf: f)).map { String(format: "%02x", $0) }.joined()
        }
        return out
    }

    func escribirFuera(_ ruta: VaultPath, _ e: SesionEscrituraTests.Entorno, _ cambio: (String) -> String) throws {
        // Simula otro editor (Obsidian, TextEdit) en la copia temporal de la prueba.
        let url = ruta.url(in: e.carpeta)
        let texto = try String(contentsOf: url, encoding: .utf8)
        try Data(cambio(texto).utf8).write(to: url)
    }

    // MARK: F1-5

    @Test("Abrir y cerrar 100 notas no cambia ninguna huella")
    func abrirYCerrar100() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let antes = try Self.huellas(e.carpeta)
        let foto = try #require(await sesion.instantanea())
        let notas = foto.notes.filter { $0.ext == "md" }.sorted()
        #expect(notas.count >= 100)
        var abiertas = 0
        for ruta in notas.prefix(100) {
            let (m, w) = try await editor(ruta, sesion)
            m.controlador.cambiarModo(.lectura)
            m.controlador.cambiarModo(.vivo)
            m.guardarYa()
            await m.guardar()
            #expect(!m.hayCambiosSinGuardar, "\(ruta.raw)")
            #expect(m.guardadosHechos == 0)
            w.close()
            abiertas += 1
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(abiertas == 100)
        #expect(try Self.huellas(e.carpeta) == antes)
    }

    @Test("Editar el cuerpo no toca las propiedades: el bloque de arriba queda byte a byte")
    func cuerpoSinPropiedades() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let url = area.url(in: e.carpeta)
        let original = try String(contentsOf: url, encoding: .utf8)
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        #expect(m.esMarkdown)
        #expect(!m.controlador.texto.contains("tls_type"), "las propiedades no entran en el texto")
        #expect(m.propiedades.contains { $0.key == "convierte" })
        let fin = (m.controlador.texto as NSString).length
        m.controlador.vista.setSelectedRange(NSRange(location: fin, length: 0))
        m.controlador.vista.insertText("\n- Llamar a [[sergio-nexo|Sergio Nexo]] el lunes", replacementRange: m.controlador.vista.selectedRange())
        #expect(m.estado == .sinGuardar)
        await m.guardar()
        #expect(m.estado == .guardado)
        let despues = try String(contentsOf: url, encoding: .utf8)
        let cuerpo = NoteDocument(text: original).body
        let prefijo = String(original.dropLast(cuerpo.count))
        #expect(despues.hasPrefix(prefijo))
        #expect(despues == prefijo + m.controlador.texto)
        #expect(despues.hasSuffix("- Llamar a [[sergio-nexo|Sergio Nexo]] el lunes"))
    }

    @Test("El guardado de una persona no exige hash_app: una nota cambiada fuera se guarda igual")
    func sinHashApp() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        // Fuera de la app (como un G3 o Obsidian): la app no tiene huella suya de este fichero.
        try escribirFuera(informe, e) { $0 + "\nAñadido en otro editor.\n" }
        let (m, w) = try await editor(informe, sesion)
        defer { w.close() }
        m.controlador.vista.setSelectedRange(NSRange(location: 0, length: 0))
        m.controlador.vista.insertText("Revisado. ", replacementRange: NSRange(location: 0, length: 0))
        await m.guardar()
        #expect(m.estado == .guardado)
        let texto = try String(contentsOf: informe.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("Revisado. # Importación"))
        #expect(texto.contains("Añadido en otro editor."))
    }

    @Test("Muchos guardados a la vez van en fila, acaban y dejan lo último", .timeLimit(.minutes(1)))
    func guardadosEnFila() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        m.esperaGuardado = .zero
        await withTaskGroup(of: Void.self) { grupo in
            for i in 0..<12 {
                let fin = (m.controlador.texto as NSString).length
                m.controlador.vista.insertText("\nLínea \(i)", replacementRange: NSRange(location: fin, length: 0))
                grupo.addTask { await m.guardar() }
                if i.isMultiple(of: 3) { m.guardarYa() }
            }
        }
        await m.guardar()
        #expect(m.estado == .guardado)
        #expect(!m.hayCambiosSinGuardar)
        let texto = try String(contentsOf: area.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.hasSuffix("Línea 10\nLínea 11"))
        #expect(m.guardadosHechos >= 1 && m.guardadosHechos <= 13)
    }

    @Test("Si fuera solo cambian propiedades, se fusiona sin aviso con lo escrito")
    func fusionPropiedades() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        let fin = (m.controlador.texto as NSString).length
        m.controlador.vista.insertText("\nUna línea nueva.", replacementRange: NSRange(location: fin, length: 0))
        // Cambio de propiedad desde otra parte (la ficha de propiedades), con el editor sin guardar.
        try await sesion.escribir(.cambiarPropiedades(area, poner: [Property(key: "pregunta", value: .text("¿Quién compra?"))], quitar: []))
        await m.guardar()
        #expect(m.conflicto == nil)
        #expect(m.estado == .guardado)
        let texto = try String(contentsOf: area.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("pregunta: ¿Quién compra?"))
        #expect(texto.hasSuffix("Una línea nueva."))
        // La lectura nueva cambia la base sin tocar el editor.
        await releer(m, sesion)
        #expect(m.propiedades.first { $0.key == "pregunta" }?.value == .text("¿Quién compra?"))
        #expect(!m.hayCambiosSinGuardar)
    }

    @Test("Actividad añadida fuera mientras se escribe: se fusiona sin aviso")
    func fusionActividad() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let ruta = VaultPath("1 · Dirección/Rutinas/semana/2026-10-12.md")
        try escribirFuera(ruta, e) { $0 + "\n## Actividad\n- 2026-10-20 · sistema · creada\n" }
        let (m, w) = try await editor(ruta, sesion)
        defer { w.close() }
        let foco = (m.controlador.texto as NSString).range(of: "## Foco\n")
        m.controlador.vista.insertText("Cerrar trimestres\n", replacementRange: NSRange(location: NSMaxRange(foco), length: 0))
        try escribirFuera(ruta, e) { $0 + "- 2026-10-21 · agente:financiero · revisó la semana\n" }
        await m.guardar()
        #expect(m.conflicto == nil)
        let texto = try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("## Foco\nCerrar trimestres\n"))
        #expect(texto.contains("revisó la semana"))
    }

    @Test("Conflicto real: banner, las dos versiones recuperables y «Usar lo de fuera»")
    func conflictoUsarFuera() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        let q = (m.controlador.texto as NSString).range(of: "Desconocidos en clientes")
        m.controlador.vista.insertText("Gente que no nos conoce", replacementRange: q)
        try escribirFuera(area, e) { $0.replacingOccurrences(of: "Desconocidos en clientes", with: "Curiosos en clientes fieles") }
        let deFuera = try String(contentsOf: area.url(in: e.carpeta), encoding: .utf8)
        await m.guardar()
        let c = try #require(m.conflicto)
        #expect(m.estado == .conflicto)
        #expect(m.controlador.soloLectura, "con el conflicto delante no se sigue escribiendo")
        #expect(try String(contentsOf: area.url(in: e.carpeta), encoding: .utf8) == deFuera, "no se pisó lo de fuera")
        #expect(c.mia.contains("Gente que no nos conoce"))
        #expect(c.deFuera == deFuera)
        #expect(sesion.tarjetas.contains { $0.id == c.registro.id })
        await m.usarLoDeFuera()
        #expect(m.conflicto == nil)
        #expect(m.controlador.texto.contains("Curiosos en clientes fieles"))
        #expect(!m.controlador.soloLectura)
        // Lo mío no se pierde: queda en Archivo/Conflictos.
        let archivo = e.carpeta.appendingPathComponent("Archivo/Conflictos")
        let guardadas = (FileManager.default.enumerator(atPath: archivo.path)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".md") }
        #expect(guardadas.count == 1)
        let mia = try String(contentsOf: archivo.appendingPathComponent(try #require(guardadas.first)), encoding: .utf8)
        #expect(mia.contains("Gente que no nos conoce"))
    }

    @Test("Conflicto real: «Quedarme con lo mío» deja lo mío y guarda lo de fuera en el Archivo")
    func conflictoQuedarme() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        let q = (m.controlador.texto as NSString).range(of: "Desconocidos en clientes")
        m.controlador.vista.insertText("Gente que no nos conoce", replacementRange: q)
        try escribirFuera(area, e) { $0.replacingOccurrences(of: "Desconocidos en clientes", with: "Curiosos") }
        await m.guardar()
        #expect(m.conflicto != nil)
        await m.quedarmeConLoMio()
        #expect(m.conflicto == nil)
        let texto = try String(contentsOf: area.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("Gente que no nos conoce"))
        #expect(!texto.contains("Curiosos"))
        let archivo = e.carpeta.appendingPathComponent("Archivo/Conflictos")
        let guardadas = (FileManager.default.enumerator(atPath: archivo.path)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".md") }
        #expect(guardadas.count == 1)
        await releer(m, sesion)
        #expect(!m.hayCambiosSinGuardar)
    }

    @Test("Carpeta real: se ve, pero ni el texto ni las propiedades se pueden cambiar; no se escribe nada")
    func carpetaReal() async throws {
        let (e, sesion) = try await abrir(.real, escritura: .bloqueada)
        defer { e.limpiar() }
        let antes = try SesionEscrituraTests.arbol(e.carpeta)
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        #expect(m.motivoSoloLectura == MotivoSoloLectura.carpetaReal.texto)
        #expect(m.controlador.soloLectura)
        #expect(!m.controlador.vista.isEditable)
        m.controlador.alternarCasilla(en: 0)
        await m.guardar()
        sesion.close()
        #expect(try SesionEscrituraTests.arbol(e.carpeta) == antes)
    }

    @Test("Una propiedad cambiada desde el formulario escribe una sola línea")
    func propiedadUnaLinea() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let (m, w) = try await editor(area, sesion)
        defer { w.close() }
        let url = area.url(in: e.carpeta)
        let antes = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        await m.cambiarPropiedad("pregunta", a: PropertiesForm.valor("¿Quién paga?", como: .text("")), etiqueta: "Pregunta")
        let despues = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        #expect(antes.count == despues.count)
        #expect(zip(antes, despues).filter { $0 != $1 }.count == 1)
        #expect(PropertiesForm.valor("12", como: .number("3")) == .number("12"))
        #expect(PropertiesForm.valor("  ", como: .text("x")) == .empty)
        #expect(PropertiesForm.enlace(en: "[[comercial|Comercial]]")?.visible == "Comercial")
        #expect(PropertiesForm.etiqueta("no_contactar") == "No contactar")
        #expect(PropertiesForm.etiqueta("codigo") == "Código")
        #expect(PropertiesForm.etiqueta("ultima-revision") == "Ultima revision")
    }

    @Test("El bloque de propiedades se lee bien en claro, oscuro y con Aumentar contraste")
    func contrastePropiedades() {
        for oscuro in [false, true] {
            for contraste in [false, true] {
                let fondo = PropertiesForm.relleno.valor(oscuro: oscuro, contraste: contraste)
                for (nombre, c) in [("texto", TLSPaleta.texto), ("textoSecundario", TLSPaleta.textoSecundario), ("enlace", TLSPaleta.enlace)] {
                    let r = TLSContraste.relacion(c.valor(oscuro: oscuro, contraste: contraste), sobre: fondo)
                    #expect(r >= TLSContraste.texto, "\(nombre) oscuro=\(oscuro) contraste=\(contraste): \(r)")
                }
            }
        }
    }

    // MARK: Enlaces e incrustaciones

    @Test("Autocompletar: por nombre y por otro nombre, sin lo privado; escribe Markdown relativo (G3) con %20")
    func autocompletar() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let enlaces = EnlacesDeNota(ruta: area, sesion: sesion)
        #expect(enlaces.estiloCarpeta == .markdown)
        let s = await enlaces.sugerencias("jorge", disparador: .wiki)
        let jorge = try #require(s.first { $0.id == "2 · Ventas/Contactos/jorge-martin.md" })
        #expect(jorge.titulo == "Jorge Martín")
        #expect(enlaces.insercion(para: jorge, disparador: .wiki, textoVisible: nil) == "[Jorge Martín](Contactos/jorge-martin.md)")
        #expect(enlaces.insercion(para: jorge, disparador: .markdown, textoVisible: "Jorge") == "Contactos/jorge-martin.md)")
        let desdeDireccion = EnlacesDeNota(ruta: VaultPath("1 · Dirección/Decisiones.md"), sesion: sesion)
        #expect(desdeDireccion.insercion(para: jorge, disparador: .markdown, textoVisible: nil)
                == "../2%20·%20Ventas/Contactos/jorge-martin.md)")
        #expect(enlaces.wikilink(a: VaultPath(jorge.id), titulo: "Jorge Martín") == "[[jorge-martin|Jorge Martín]]")
        // Por otro nombre (`nombre` de la ficha de empresa).
        let t = await enlaces.sugerencias("Talleres Martín", disparador: .wiki)
        #expect(t.contains { $0.id.hasSuffix("talleres-martin-e-hijos.md") })
        #expect(!s.contains { $0.id == area.raw }, "no se sugiere a sí misma")
    }

    @Test("Resolver al ⌘clic: enlaces Markdown con %20, wikilinks por nombre y los rotos en gris")
    func resolver() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let enlaces = EnlacesDeNota(ruta: informe, sesion: sesion)
        let leeme = EnlaceMarkdown(destino: "../Archivo/Importación%202026-10-19/LEEME.md", estilo: .markdown, texto: "LEEME.md")
        #expect(enlaces.estado(de: leeme) == .existe)
        #expect(enlaces.estado(de: EnlaceMarkdown(destino: "jorge-martin", estilo: .wiki, texto: "Jorge")) == .existe)
        #expect(enlaces.estado(de: EnlaceMarkdown(destino: "no-existe", estilo: .wiki, texto: "x")) == .rota)
        #expect(enlaces.estado(de: EnlaceMarkdown(destino: "https://example.com", estilo: .markdown, texto: "web")) == .externa)
        enlaces.abrir(EnlaceMarkdown(destino: "no-existe", estilo: .wiki, texto: "x"), apertura: .aqui)
        #expect(sesion.linkProblem?.contains("no-existe") == true)
    }

    @Test("Incrustaciones: un PDF de la carpeta da un bloque de TLSVisores; lo que no existe, un enlace normal")
    func incrustaciones() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let prov = IncrustacionesDeNota(ruta: area, sesion: sesion)
        var repintar = 0
        prov.adjuntos.alCargar = { repintar += 1 }
        let pdf = EnlaceMarkdown(destino: "2026-07-10 Movil Levante ML-07-2026 78,65€.pdf", ancla: "page=1", estilo: .wiki, texto: "")
        // El resolvedor de la sesión ya conoce los adjuntos por su nombre (no solo las notas): el PDF de otra
        // carpeta sale a la primera, sin esperar a la lista de ficheros ni repintar.
        let b = try #require(prov.bloque(para: Incrustacion(enlace: pdf, pagina: 1)))
        await prov.adjuntos.esperar()
        #expect(repintar == 0)
        #expect(b.alto == 420)
        #expect(b.altoAmpliado > b.alto)
        #expect(b.simbolo == "doc.richtext")
        #expect(prov.bloque(para: Incrustacion(enlace: EnlaceMarkdown(destino: "no-existe.pdf", estilo: .wiki, texto: ""))) == nil)
        #expect(prov.bloque(para: Incrustacion(enlace: EnlaceMarkdown(destino: "jorge-martin", estilo: .wiki, texto: ""))) == nil,
                "una nota incrustada se ve como enlace")
        let alto = try #require(prov.bloque(para: Incrustacion(enlace: pdf, alto: 300)))
        #expect(alto.alto == 300)
    }

    @Test("Nota de texto plano: solo texto fuente, se guarda igual")
    func textoPlano() async throws {
        let (e, sesion) = try await abrir()
        defer { e.limpiar() }
        defer { sesion.close() }
        let ruta = VaultPath("Buzón/apuntes.txt")
        try await sesion.escribir(.crear(ruta, texto: "Apuntes **sin** formato\n"))
        let (m, w) = try await editor(ruta, sesion)
        defer { w.close() }
        #expect(m.contenido == .editable(markdown: false))
        #expect(m.controlador.modo == .fuente)
        m.controlador.vista.insertText("Más. ", replacementRange: NSRange(location: 0, length: 0))
        await m.guardar()
        #expect(try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8) == "Más. Apuntes **sin** formato\n")
    }

    @Test("Diferencias línea a línea entre lo mío y lo de fuera")
    func diferencias() {
        let l = Diferencias.lineas(mia: "a\nb\nc", deFuera: "a\nB\nc")
        #expect(l.map(\.lado) == [.igual, .soloFuera, .soloMia, .igual])
        #expect(RutaRelativa.markdown(desde: VaultPath("A/x.md"), hasta: VaultPath("A/B (1)/y z.md")) == "B%20(1)/y%20z.md")
        #expect(RutaRelativa.markdown(desde: VaultPath("A/x.md"), hasta: VaultPath("A/B)/y.md")) == "B%29/y.md")
        #expect(NoteInspector.urlObsidian(URL(fileURLWithPath: "/a b/n.md"))?.absoluteString == "obsidian://open?path=/a%20b/n.md")
    }
}
