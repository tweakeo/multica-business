import Foundation
import Testing
@testable import TLSEditor

@Suite("Editor · análisis del Markdown")
struct AnalizadorMarkdownTests {
    func linea(_ texto: String, _ i: Int = 0) -> ParrafoMarkdown {
        AnalizadorMarkdown.analizar(texto).parrafos[i]
    }

    func trozos(_ p: ParrafoMarkdown, _ texto: String, de clase: TramoMarkdown.Clase) -> [String] {
        let ns = texto as NSString
        let linea = ns.substring(with: p.rangoContenido) as NSString
        return p.tramos.filter { $0.clase == clase }.map { linea.substring(with: $0.rango) }
    }

    @Test("Títulos: las almohadillas son marca y el nivel va en el bloque")
    func titulos() {
        let t = "## Notas de la reunión"
        let p = linea(t)
        #expect(p.bloque.nivelEncabezado == 2)
        #expect(trozos(p, t, de: .marcador) == ["## "])
    }

    @Test("Negrita, cursiva, tachado y código: marcas a los lados")
    func enLinea() {
        let t = "Hola **fuerte** y *suave* con ~~fuera~~ y `x = 1`"
        let p = linea(t)
        #expect(trozos(p, t, de: .marcador) == ["**", "**", "*", "*", "~~", "~~", "`", "`"])
        #expect(trozos(p, t, de: .negrita) == ["**fuerte**"])
        #expect(trozos(p, t, de: .codigo) == ["`x = 1`"])
    }

    @Test("Wikilink con texto: se ve el texto; destino, ancla y alias por separado")
    func wikilink() throws {
        let t = "Habla con [[jorge-martin#Notas|Jorge Martín]] mañana"
        let p = linea(t)
        let e = try #require(p.enlaces.first)
        #expect(e.destino == "jorge-martin")
        #expect(e.ancla == "Notas")
        #expect(e.estilo == .wiki)
        #expect(e.texto == "Jorge Martín")
        #expect(e.paraResolver == "[[jorge-martin]]")
        #expect(trozos(p, t, de: .marcador) == ["[[jorge-martin#Notas|", "]]"])
    }

    @Test("Enlace Markdown con %20: el destino se guarda tal cual y se lee sin codificar")
    func enlaceMarkdown() throws {
        let t = "- [LEEME.md](../Archivo/Importación%202026-10-19/LEEME.md)"
        let p = linea(t)
        let e = try #require(p.enlaces.first)
        #expect(e.destino == "../Archivo/Importación%202026-10-19/LEEME.md")
        #expect(e.destinoLegible == "../Archivo/Importación 2026-10-19/LEEME.md")
        #expect(e.texto == "LEEME.md")
        #expect(trozos(p, t, de: .marcador) == ["[", "](../Archivo/Importación%202026-10-19/LEEME.md)"])
        #expect(trozos(p, t, de: .vineta) == ["-"])
    }

    @Test("Incrustaciones: ![[x.pdf#page=3]], ![[imagen.png|300]] y ![](Materiales/acta.pdf) son bloques")
    func incrustaciones() throws {
        let t = "![[factura-2026-014.pdf#page=3]]\n![[logo.png|300]]\n![](Materiales/acta%20final.pdf)\nTexto con ![[x.pdf]] dentro"
        let a = AnalizadorMarkdown.analizar(t)
        let pdf = try #require(a.parrafos[0].incrustacion)
        #expect(pdf.enlace.destino == "factura-2026-014.pdf")
        #expect(pdf.pagina == 3)
        #expect(pdf.enlace.extensionDestino == "pdf")
        let img = try #require(a.parrafos[1].incrustacion)
        #expect(img.ancho == 300)
        #expect(img.enlace.destino == "logo.png")
        let md = try #require(a.parrafos[2].incrustacion)
        #expect(md.enlace.estilo == .markdown)
        #expect(md.enlace.destinoLegible == "Materiales/acta final.pdf")
        // Dentro de una frase no es un bloque: es un enlace con su `!` escondido.
        #expect(a.parrafos[3].incrustacion == nil)
        #expect(a.parrafos[3].enlaces.first?.destino == "x.pdf")
    }

    @Test("Aviso de Obsidian: tipo, posición y título; las marcas `> [!…]` se esconden")
    func aviso() {
        let t = "> [!warning] Ojo con el plazo\n> El 20 no se mueve.\n\nFuera"
        let a = AnalizadorMarkdown.analizar(t)
        #expect(a.parrafos[0].bloque.aviso == AvisoMarkdown(tipo: "warning", posicion: .primera))
        #expect(a.parrafos[1].bloque.aviso == AvisoMarkdown(tipo: "warning", posicion: .ultima))
        #expect(a.parrafos[3].bloque.aviso == nil)
        #expect(trozos(a.parrafos[0], t, de: .tituloAviso) == ["Ojo con el plazo"])
        #expect(trozos(a.parrafos[0], t, de: .marcador).joined() == "> [!warning] ")
        let segunda = (t as NSString).substring(with: a.parrafos[1].rangoContenido)
        #expect(trozos(a.parrafos[1], t, de: .marcador) == ["> "], "\(segunda)")
    }

    @Test("Etiquetas: sí #cliente y #área/2026; no un título, ni un ancla, ni un número")
    func etiquetas() {
        let t = "Ver #cliente y #área/2026 pero no [[x#sec]] ni https://a.es/#frag ni #123"
        let p = linea(t)
        #expect(trozos(p, t, de: .etiqueta) == ["#cliente", "#área/2026"])
        #expect(linea("# Título").tramos.contains { $0.clase == .etiqueta } == false)
    }

    @Test("Casillas: `[ ]` y `[x]`, la viñeta escondida y el texto hecho tachado")
    func casillas() {
        let t = "- [ ] Llamar a Jorge\n- [x] Enviar la factura"
        let a = AnalizadorMarkdown.analizar(t)
        #expect(a.parrafos[0].tramos.contains { $0.clase == .casilla(marcada: false) && $0.rango == NSRange(location: 2, length: 3) })
        #expect(a.parrafos[1].tramos.contains { $0.clase == .casilla(marcada: true) })
        #expect(trozos(a.parrafos[1], t, de: .tareaHecha) == ["Enviar la factura"])
        #expect(trozos(a.parrafos[0], t, de: .marcador) == ["- "])
    }

    @Test("Bloque de código: vallas y líneas; dentro no hay etiquetas ni enlaces")
    func codigo() {
        let t = "```swift\nlet x = \"#no [[no]]\"\n```\ndespués #si"
        let a = AnalizadorMarkdown.analizar(t)
        #expect(a.parrafos[0].bloque.tipo == .vallaCodigo(.primera, lenguaje: "swift"))
        #expect(a.parrafos[1].bloque.tipo == .codigo(.media))
        #expect(a.parrafos[2].bloque.tipo == .vallaCodigo(.ultima, lenguaje: nil))
        #expect(a.parrafos[1].tramos.isEmpty)
        #expect(trozos(a.parrafos[3], t, de: .etiqueta) == ["#si"])
    }

    @Test("Tabla, cita y separador")
    func bloques() {
        let t = "| Qué | Cuántos |\n|---|---|\n| Notas | 113 |\n\n> cita\n\n---"
        let a = AnalizadorMarkdown.analizar(t)
        #expect(a.parrafos[0].bloque.tipo == .tablaCabecera)
        #expect(a.parrafos[1].bloque.tipo == .tablaSeparador)
        #expect(a.parrafos[2].bloque.tipo == .tablaFila)
        #expect(a.parrafos[4].bloque.cita == 1)
        #expect(a.parrafos[6].bloque.tipo == .separador)
    }

    @Test("Saltos «\\r\\n»: las líneas y sus rangos cuadran con NSString")
    func saltosWindows() {
        let t = "# A\r\n**b**\r\nc"
        let a = AnalizadorMarkdown.analizar(t)
        #expect(a.parrafos.count == 3)
        #expect(a.parrafos[1].inicio == 5)
        #expect(a.parrafos[1].salto == 2)
        #expect(trozos(a.parrafos[1], t, de: .marcador) == ["**", "**"])
        #expect(a.longitud == (t as NSString).length)
    }

    @Test("Comparar dos análisis: escribir en una línea solo cambia esa")
    func cambiadas() {
        var lineas = (0..<200).map { "Línea **\($0)** con [[enlace-\($0)]]" }
        let a = AnalizadorMarkdown.analizar(lineas.joined(separator: "\n"))
        lineas[57] += " y algo más"
        let b = AnalizadorMarkdown.analizar(lineas.joined(separator: "\n"))
        #expect(b.cambiadas(respectoA: a) == 57..<58)
        #expect(a.cambiadas(respectoA: a).isEmpty)
    }

    @Test("Resaltado, comentario y escape")
    func obsidian() {
        let t = #"Esto ==importa== y %%nota oculta%% y \*literal\*"#
        let p = linea(t)
        #expect(trozos(p, t, de: .resaltado) == ["==importa=="])
        #expect(trozos(p, t, de: .comentario) == ["%%nota oculta%%"])
        #expect(trozos(p, t, de: .marcador).contains(#"\"#))
    }

    @Test("Títulos de la nota para el índice")
    func indice() {
        let a = AnalizadorMarkdown.analizar("# Uno\ntexto\n## Dos\n### Tres")
        #expect(a.titulos.map(\.nivel) == [1, 2, 3])
    }

    @Test("Secciones ## (lo usa el resumen de las fichas)")
    func secciones() {
        #expect(SeccionesMarkdown.titulos("# Nota\n\n## Notas\nhola\n\n## Actividad\n- a") == ["Notas", "Actividad"])
    }
}
