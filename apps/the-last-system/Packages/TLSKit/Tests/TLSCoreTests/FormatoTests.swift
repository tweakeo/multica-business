import Foundation
import Testing
@testable import TLSCore

@Suite struct NoteDocumentTests {
    @Test func separaFrontmatterYCuerpo() {
        let doc = NoteDocument(text: "---\ntipo: persona\n---\n\n# Hola\n\nCuerpo.\n")
        #expect(doc.frontmatterText == "tipo: persona\n")
        #expect(doc.body == "\n# Hola\n\nCuerpo.\n")
        #expect(doc.heading == "Hola")
    }

    @Test func sinCierreNoHayFrontmatter() {
        let doc = NoteDocument(text: "---\ntipo: persona\n\n# Hola\n")
        #expect(doc.frontmatterText == nil)
        #expect(doc.body.hasPrefix("---"))
    }

    @Test func toleraCRLFyBOM() {
        let doc = NoteDocument(text: "\u{FEFF}---\r\nnombre: Ana\r\n---\r\nTexto\r\n")
        #expect(doc.frontmatterText == "nombre: Ana\r\n")
        #expect(doc.body == "Texto\r\n")
        #expect(doc.title(fileStem: "ana") == "Ana")
    }

    @Test func tituloH1oNombreDelFichero() {
        #expect(NoteDocument(text: "Texto sin título").title(fileStem: "mi-nota") == "mi-nota")
        #expect(NoteDocument(text: "```\n# no\n```\n# Sí\n").heading == "Sí")
        #expect(NoteDocument(text: "---\ntitulo: Desde propiedades\n---\nTexto").title(fileStem: "x") == "Desde propiedades")
    }
}

@Suite struct FrontmatterTests {
    let yaml = """
    tipo: persona
    nombre: Lucía Prueba
    empresa: "[[Ferretería Ejemplo]]"
    alta: 2026-10-21
    ultimo_contacto: 2026-09-10T22:00:00.000Z
    hora: 10:30
    etiquetas: [cliente, web]
    activo: true
    importe: 1200
    telefono: "0034600000000"
    vacio:
    notas: Persona ficticia.
    direccion:
      calle: Calle Falsa 1
    """

    @Test func conservaElOrdenDeClaves() {
        let fm = FrontmatterReader.read(yaml)
        #expect(fm.isValid)
        #expect(fm.properties.map(\.key) == ["tipo", "nombre", "empresa", "alta", "ultimo_contacto", "hora", "etiquetas",
                                             "activo", "importe", "telefono", "vacio", "notas", "direccion"])
    }

    @Test func fechasComoTexto() {
        let fm = FrontmatterReader.read(yaml)
        #expect(fm.value("alta") == .text("2026-10-21"))
        #expect(fm.value("ultimo_contacto") == .text("2026-09-10T22:00:00.000Z"))
        #expect(fm.value("hora") == .text("10:30"))
    }

    @Test func tiposBasicos() {
        let fm = FrontmatterReader.read(yaml)
        #expect(fm.value("etiquetas") == .list(["cliente", "web"]))
        #expect(fm.value("activo") == .bool(true))
        #expect(fm.value("importe") == .number("1200"))
        #expect(fm.value("telefono") == .text("0034600000000"))
        #expect(fm.value("vacio") == .empty)
        #expect(fm.value("empresa") == .text("[[Ferretería Ejemplo]]"))
        guard case .raw(let r) = fm.value("direccion") else { Issue.record("direccion debería ser literal"); return }
        #expect(r.contains("calle: Calle Falsa 1"))
    }

    @Test func aliasEnEspanol() {
        let fm = FrontmatterReader.read(yaml)
        #expect(fm.text("name") == "Lucía Prueba")
        #expect(fm.text("notes") == "Persona ficticia.")
        #expect(fm.titleText == "Lucía Prueba")
        #expect(FrontmatterReader.read("título: Uno\nname: Dos").titleText == "Uno")
    }

    @Test func yamlRotoNoRompeLaNota() {
        let fm = FrontmatterReader.read("clave: [sin cerrar\n  otra: : :")
        #expect(!fm.isValid)
        #expect(fm.properties.isEmpty)
    }

    @Test func jsonEnOrden() {
        let fm = FrontmatterReader.read("b: 1\na: texto\nc: [x]\nd: 007")
        #expect(fm.json == #"{"b":1,"a":"texto","c":["x"],"d":"007"}"#)
    }
}

@Suite struct CSVTests {
    @Test func comillasBOMyCRLF() {
        let text = "\u{FEFF}id,cliente,concepto\r\n1,\"Ferretería, S.L.\",\"Web \"\"básica\"\"\"\r\n2,Otro,\"dos\r\nlíneas\"\r\n"
        let t = CSVTable.parse(text)
        #expect(t.header == ["id", "cliente", "concepto"])
        #expect(t.rows.count == 2)
        #expect(t.rows[0] == ["1", "Ferretería, S.L.", "Web \"básica\""])
        #expect(t.rows[1][2] == "dos\r\nlíneas")
    }

    @Test func puntoYComaDeBanco() {
        let t = CSVTable.parse("fecha;concepto;importe\n01/07/2026;RECIBO;-12,50\n")
        #expect(t.delimiter == ";")
        #expect(t.rows[0] == ["01/07/2026", "RECIBO", "-12,50"])
    }

    @Test func camposVaciosYUltimaLineaSinSalto() {
        let t = CSVTable.parse("a,b,c\n1,,3")
        #expect(t.rows == [["1", "", "3"]])
    }
}

@Suite struct LinkParserTests {
    @Test func markdownRelativosConEspacios() {
        let links = LinkParser.links(in: "Ver [Plan](Sistemas/Plan%20del%20estudio.md) y [A](<Gestoría/Asesor (Ejemplo).md>).")
        #expect(links.count == 2)
        #expect(links[0].style == .markdown)
        #expect(links[0].target == "Sistemas/Plan%20del%20estudio.md")
        #expect(links[0].label == "Plan")
        #expect(links[1].target == "Gestoría/Asesor (Ejemplo).md")
    }

    @Test func wikilinks() {
        let links = LinkParser.links(in: "[[Nota]] [[Nota|alias]] [[Nota#Sección]] ![[imagen.png]]")
        #expect(links.map(\.target) == ["Nota", "Nota", "Nota", "imagen.png"])
        #expect(links[1].label == "alias")
        #expect(links[2].anchor == "Sección")
        #expect(links[3].isEmbed)
        #expect(links[2].resolvable == "[[Nota#Sección]]")
    }

    @Test func ignoraCodigoYExternos() {
        let text = "`[[no]]` y [web](https://example.com)\n```\n[[tampoco]]\n```\n[[sí]]"
        let links = LinkParser.links(in: text)
        #expect(links.map(\.target) == ["https://example.com", "sí"])
        #expect(links[0].isExternal)
    }

    @Test func parentesisEquilibradosYAnclas() {
        let links = LinkParser.links(in: "[x](Notas/Plan%20(v2).md#Fase%201)")
        #expect(links.first?.target == "Notas/Plan%20(v2).md")
        #expect(links.first?.anchor == "Fase 1")
    }

    @Test func textoPlano() {
        #expect(LinkParser.plainText("mantiene [Rumbo](Rumbo.md) y [[Mapa|el mapa]].") == "mantiene Rumbo y el mapa.")
    }
}

@Suite struct LinkResolverTests {
    let paths: [VaultPath] = [
        "Empresa.md", "1 · Dirección/Área.md", "1 · Dirección/Sistemas/Plan del estudio.md",
        "2 · Ventas/Contactos/Lucía Prueba.md", "2 · Ventas/Sistemas/Embudo.md",
        "2 · Ventas/Notas/Plan.md", "3 · Entrega/Notas/Plan.md",
    ].map { VaultPath($0) }

    var resolver: LinkResolver { LinkResolver(paths: paths) }

    @Test func rutaRelativaConPorcentajes() {
        let from = VaultPath("1 · Dirección/Área.md")
        #expect(resolver.resolve("Sistemas/Plan%20del%20estudio.md", from: from) == VaultPath("1 · Dirección/Sistemas/Plan del estudio.md"))
        #expect(resolver.resolve("../Empresa.md", from: from) == VaultPath("Empresa.md"))
        #expect(resolver.resolve("<Sistemas/Plan del estudio.md>", from: from) == VaultPath("1 · Dirección/Sistemas/Plan del estudio.md"))
        #expect(resolver.resolve("../../fuera.md", from: from) == nil)
    }

    @Test func wikilinkPorNombreSinMayusculasNiNFD() {
        let from = VaultPath("Empresa.md")
        #expect(resolver.resolve("[[embudo]]", from: from) == VaultPath("2 · Ventas/Sistemas/Embudo.md"))
        #expect(resolver.resolve("[[Luci\u{301}a Prueba|Lucía]]", from: from) == VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"))
        #expect(resolver.resolve("[[Embudo#Etapas]]", from: from) == VaultPath("2 · Ventas/Sistemas/Embudo.md"))
        #expect(resolver.resolve("[[No existe]]", from: from) == nil)
    }

    @Test func nombreRepetido() {
        // Desde fuera de las dos carpetas, como Obsidian: la de ruta más corta.
        #expect(resolver.resolve("[[Plan]]", from: VaultPath("Empresa.md")) == VaultPath("2 · Ventas/Notas/Plan.md"))
        // Desde la misma carpeta: la más cercana.
        #expect(resolver.resolve("[[Plan]]", from: VaultPath("3 · Entrega/Notas/Otra.md")) == VaultPath("3 · Entrega/Notas/Plan.md"))
        // Con parte de ruta escrita.
        #expect(resolver.resolve("[[2 · Ventas/Notas/Plan]]", from: VaultPath("Empresa.md")) == VaultPath("2 · Ventas/Notas/Plan.md"))
    }
}

@Suite struct KindTests {
    let layout = VaultLayout.humana

    func kind(_ path: String, _ yaml: String? = nil) -> NoteKind {
        NoteKindResolver.kind(of: VaultPath(path), frontmatter: yaml.map(FrontmatterReader.read), layout: layout)
    }

    @Test func prioridadTlsTypeTipoCarpeta() {
        #expect(kind("2 · Ventas/Contactos/x.md", "tls_type: opportunity\ntipo: persona") == .opportunity)
        #expect(kind("Notas/x.md", "tipo: Persona") == .contact)
        #expect(kind("Notas/x.md", "tipo: organización") == .organization)
        #expect(kind("Notas/x.md", "tipo: oportunidad") == .opportunity)
        #expect(kind("Notas/x.md", "tls_type: brand_identity") == .note)
    }

    @Test func porCarpeta() {
        #expect(kind("Empresa.md") == .company)
        #expect(kind("1 · Dirección/Área.md") == .area)
        #expect(kind("2 · Ventas/Sistemas/Embudo.md") == .system)
        #expect(kind("4 · Finanzas/Sistemas/Gastos del mes/Anotar ticket.md") == .system)
        #expect(kind("2 · Ventas/Contactos/Ana.md") == .contact)
        #expect(kind("2 · Ventas/Contactos/Contactos.md") == .note)
        #expect(kind("2 · Ventas/Empresas/Bar.md") == .organization)
        #expect(kind("2 · Ventas/Oportunidades/web.md") == .opportunity)
        #expect(kind("3 · Entrega/Proyectos/web/Proyecto.md") == .project)
        #expect(kind("3 · Entrega/Proyectos/web/Tareas/t-0001-x.md") == .task)
        #expect(kind("6 · Equipo/Tareas/t-0002-y.md") == .task)
        #expect(kind("6 · Equipo/Tareas.md") == .note)
        #expect(kind("4 · Finanzas/Registros/emitidas.csv") == .csv)
        #expect(kind("Archivo/2 · Ventas/Contactos/Ana.md") == .note)
        #expect(kind("4 · Finanzas/Registros/Bancos/principal/Cuenta.md") == .account)
    }

    /// Las plantillas instaladas llevan `tls_type` pero no son fichas (ni sistemas).
    @Test func plantillasNoSonFichas() {
        #expect(kind("2 · Ventas/Sistemas/Plantillas/Contacto.md", "tls_type: contact") == .note)
        #expect(kind("6 · Equipo/Sistemas/Plantillas/Tarea.md", "tls_type: task") == .note)
        #expect(kind("6 · Equipo/Sistemas/Plantillas/Tarea.md") == .note)
        #expect(kind("2 · Ventas/Sistemas/Embudo.md", "tls_type: system") == .system)
    }

    @Test func demoAntigua() {
        let demo = VaultLayout.demo
        #expect(NoteKindResolver.kind(of: VaultPath("Ventas/Organizaciones/bar.md"), frontmatter: nil, layout: demo) == .organization)
        #expect(demo.area(of: VaultPath("Finanzas/2026/T3/periodo.md")) == .finanzas)
    }
}

@Suite struct AreaReaderTests {
    @Test func estados() {
        #expect(AreaReader.status("activa") == .activa)
        #expect(AreaReader.status("preparada, sin activar (vuelve en enero)") == .preparada)
        #expect(AreaReader.status("en reposo") == .reposo)
        #expect(AreaReader.status("Reposo hasta marzo") == .reposo)
        #expect(AreaReader.status("inactiva") == .desconocido)
        #expect(AreaReader.status("") == .desconocido)
    }

    @Test func lineaDeEstado() {
        let f = AreaReader.labeledFields("**Estado:** activa · **La llevan:** Ana y Luis · **Rol:** Ana decide; Luis registra.")
        #expect(f.map(\.label) == ["estado", "la llevan", "rol"])
        #expect(f.map(\.value) == ["activa", "Ana y Luis", "Ana decide; Luis registra."])
    }

    /// v2 (SISTEMAS §2.3): el estado sale de la propiedad y manda sobre el texto; la tabla de sistemas se lee.
    @Test func areaV2LeeLasPropiedades() {
        let md = """
        ---
        tls_type: area
        codigo: ventas
        nombre: Ventas
        estado: en reposo
        convierte: Desconocidos en clientes
        rol: "[[comercial|Comercial]]"
        ocupante: Lucía
        ---
        # Ventas
        > Preparada · La lleva Lucía

        **Estado:** activa · **La lleva:** Ana

        ## Sistemas
        | Código | Sistema | Estado |
        |---|---|---|
        | VEN-01 | [[Embudo]] | activo |
        | VEN-02 | Referidos | preparado |
        | | | |
        """
        let a = AreaReader.parse(markdown: md, code: .ventas, folder: VaultPath("2 · Ventas")) { t in
            t == "[[Embudo]]" ? VaultPath("2 · Ventas/Sistemas/Embudo.md") : nil
        }
        #expect(a.estado == .reposo)
        #expect(a.estadoTexto == "en reposo")
        #expect(a.lleva == "Ana")  // la línea del texto sigue valiendo para quién la lleva
        #expect(a.rol == "Comercial")
        #expect(a.transforma == "Desconocidos en clientes")
        #expect(a.sistemas.map(\.nombre) == ["Embudo", "Referidos"])
        #expect(a.sistemas.first?.path == VaultPath("2 · Ventas/Sistemas/Embudo.md"))

        let sinCuerpo = AreaReader.parse(markdown: "---\ntls_type: area\nnombre: Marca\nestado: preparada\nocupante: agente:marca\n---\n",
                                         code: .marca, folder: VaultPath("5 · Marca")) { _ in nil }
        #expect(sinCuerpo.titulo == "Marca")
        #expect(sinCuerpo.estado == .preparada)
        #expect(sinCuerpo.lleva == "agente:marca")
    }

    @Test func formatoDistintoDegradaADesconocido() {
        let a = AreaReader.parse(markdown: "---\ntls_type: area\n---\n# Ventas\n\nSin línea de estado.\n",
                                 code: .ventas, folder: VaultPath("Ventas")) { _ in nil }
        #expect(a.estado == .desconocido)
        #expect(a.tieneFicha)
        #expect(a.titulo == "Ventas")
        #expect(a.sistemas.isEmpty)
    }
}
