import Foundation
import Testing
@testable import TLSCore

@Suite("Enlaces: lectura con posición")
struct LinkScannerTests {
    func destinos(_ text: String) -> [String] {
        let b = Array(text.utf8)
        return LinkScanner.scan(text).map { String(decoding: b[$0.targetRange], as: UTF8.self) }
    }

    @Test func todasLasFormas() {
        let text = """
        ---
        empresa: "[[talleres-martin|Talleres Martín]]"
        personas: ["[[ana]]", '[[luis|Luis]]']
        relacion:
          - "[[otra-nota]]"
        ---
        # Título
        Wiki [[nota]], alias [[nota|texto]], sección [[nota#Parte|t]], incrustado ![[logo.png]].
        Markdown [t](../A%20B/c.md), con sección [t](c.md#Notas), ángulos [t](<A B (2).md>), título [t](x.md "T").
        Tabla | [[nota\\|alias]] | ![img](img.png)
        `[[codigo]]` y ``[t](codigo.md)`` no cuentan.
        ```
        [[tampoco]]
        ```
        [ref]: ../ruta/def.md "Título"
        [^1]: nota al pie
        """
        #expect(destinos(text) == ["talleres-martin", "ana", "luis", "otra-nota", "nota", "nota", "nota", "logo.png",
                                   "../A%20B/c.md", "c.md", "A B (2).md", "x.md", "nota", "img.png", "../ruta/def.md"])
        let occ = LinkScanner.scan(text)
        #expect(occ[0].comillas == .dobles)
        #expect(occ[0].lugar == .propiedad("empresa"))
        #expect(occ[2].comillas == .simples)
        #expect(occ[3].lugar == .propiedad("relacion"))
        #expect(occ[4].lugar == .cuerpo)
        #expect(occ[10].angle)
        #expect(occ[12].link.label == "alias")
        #expect(occ.last?.isReference == true)
        #expect(occ[7].link.isEmbed)
    }

    @Test func posicionesEnBytesConTildesYCRLF() {
        let text = "---\r\nempresa: \"[[ñandú]]\"\r\n---\r\nVer [Ñ](Ñu%20á.md) y [[José Núñez|José]].\r\n"
        let b = Array(text.utf8)
        let occ = LinkScanner.scan(text)
        #expect(occ.count == 3)
        #expect(String(decoding: b[occ[0].targetRange], as: UTF8.self) == "ñandú")
        #expect(String(decoding: b[occ[1].targetRange], as: UTF8.self) == "Ñu%20á.md")
        #expect(String(decoding: b[occ[2].targetRange], as: UTF8.self) == "José Núñez")
        #expect(occ[2].line == 4)
    }

    @Test func mismosEnlacesQueElLectorDelIndice() throws {
        // En cuerpos sin tablas, el escáner encuentra lo mismo que `LinkParser`.
        for url in ficherosDeTexto(Apoyo.empresaMinima, extensiones: ["md"]) {
            let text = try String(contentsOf: url, encoding: .utf8)
            let body = NoteDocument(text: text).body
            let a = LinkParser.links(in: body).map(\.raw)
            let b = LinkScanner.scan(text).filter { $0.lugar == .cuerpo }.map(\.link.raw)
            #expect(a == b, "\(url.lastPathComponent)")
        }
    }
}

@Suite("Enlaces: destinos Markdown")
struct MarkdownDestinationTests {
    @Test func conservaLaForma() {
        let from = VaultPath("2 · Ventas/Oportunidades/x.md")
        // %20 con tildes tal cual.
        #expect(MarkdownDestination.rewrite(original: "../Empresas/Ferretería%20Ejemplo.md", from: from,
                                            to: VaultPath("2 · Ventas/Empresas/Ferretería Nueva.md"), angle: false)
                == "../Empresas/Ferretería%20Nueva.md")
        // Tildes codificadas: se siguen codificando.
        #expect(MarkdownDestination.rewrite(original: "../Empresas/Ferreter%C3%ADa%20Ejemplo.md", from: from,
                                            to: VaultPath("4 · Finanzas/Gestoría/Ferretería Ejemplo.md"), angle: false)
                == "../../4%20%C2%B7%20Finanzas/Gestor%C3%ADa/Ferreter%C3%ADa%20Ejemplo.md")
        // Entre ángulos, sin codificar.
        #expect(MarkdownDestination.rewrite(original: "../Empresas/A B.md", from: from,
                                            to: VaultPath("2 · Ventas/Empresas/C (D).md"), angle: true) == "../Empresas/C (D).md")
        // Sin `.md`.
        #expect(MarkdownDestination.rewrite(original: "../Empresas/a", from: from,
                                            to: VaultPath("2 · Ventas/Empresas/b.md"), angle: false) == "../Empresas/b")
        // `./` delante.
        #expect(MarkdownDestination.rewrite(original: "./a.md", from: from,
                                            to: VaultPath("2 · Ventas/Oportunidades/b.md"), angle: false) == "./b.md")
        // Paréntesis desequilibrados: se codifican.
        #expect(MarkdownDestination.rewrite(original: "a.md", from: from,
                                            to: VaultPath("2 · Ventas/Oportunidades/b (c.md"), angle: false) == "b%20%28c.md")
        // Mayúsculas distintas en una carpeta que no cambia: se conserva lo escrito.
        #expect(MarkdownDestination.rewrite(original: "../empresas/a.md", from: from,
                                            to: VaultPath("2 · Ventas/Empresas/b.md"), angle: false) == "../empresas/b.md")
    }

    @Test func resolucionEstricta() {
        let set: Set<String> = ["2 · ventas/empresas/a.md"]
        let exists: (VaultPath) -> VaultPath? = { set.contains(TextFolding.pathKey($0.raw)) ? $0 : nil }
        let from = VaultPath("2 · Ventas/Contactos/x.md")
        #expect(MarkdownDestination.strictTarget("../Empresas/a.md", from: from, exists: exists) != nil)
        #expect(MarkdownDestination.strictTarget("../Empresas/a", from: from, exists: exists) != nil)
        #expect(MarkdownDestination.strictTarget("a.md", from: from, exists: exists) == nil)
    }
}

@Suite("Renombrar y mover con enlaces")
struct LinkRefactorTests {
    @Test func renombrarNotaActualizaTodo() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let antes = env.foto()
        let hash0 = env.hashArbol()
        let preview = try LinkRefactor(snapshot: antes).renombrar(VaultPath("2 · Ventas/Contactos/Lucía Prueba"), a: "Lucía Ferrer")
        #expect(preview.esSeguro)
        #expect(preview.traslados == [Traslado(de: VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"),
                                               a: VaultPath("2 · Ventas/Contactos/Lucía Ferrer.md"))])
        // [[Lucía Prueba]] ×3, [Lucía Prueba](../Contactos/…) y [Lucía](Lucía%20Prueba.md).
        #expect(preview.enlaces == 5)
        #expect(preview.notas == 5)
        #expect(preview.resumen == "Renombrar «Lucía Prueba» actualizará 5 enlaces en 5 notas.")
        let bus = try await env.bus()
        let r = try await LinkRefactor.aplicar(preview, con: bus)
        #expect(r.hecho)
        #expect(env.existe("2 · Ventas/Contactos/Lucía Ferrer.md"))
        #expect(env.texto("2 · Ventas/Empresas/Ferretería Ejemplo.md")!.contains("[Lucía Prueba](../Contactos/Lucía%20Ferrer.md)"))
        #expect(env.texto("2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md")!.contains("Contacto: [[Lucía Ferrer]]."))
        #expect(env.texto("2 · Ventas/Contactos/José Núñez.md")!.contains("[Lucía](Lucía%20Ferrer.md)"))
        // El H1 manda: el nombre visible no cambia, así que no se añade a «Otros nombres».
        #expect(!env.texto("2 · Ventas/Contactos/Lucía Ferrer.md")!.contains("aliases"))
        let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: MoveMap(moves: preview.traslados.map { ($0.de, $0.a) }).map)
        #expect(fallos.isEmpty, "\(fallos)")
        // Deshacer devuelve el árbol exacto.
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(env.hashArbol() == hash0)
    }

    @Test func renombrarYVolverDejaLosMismosBytes() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let hash0 = env.hashArbol()
        let bus = try await env.bus()
        let a = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("2 · Ventas/Empresas/Ferretería Ejemplo.md"), a: "Ferretería Sol")
        try await LinkRefactor.aplicar(a, con: bus)
        let b = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("2 · Ventas/Empresas/Ferretería Sol.md"), a: "Ferretería Ejemplo")
        try await LinkRefactor.aplicar(b, con: bus)
        #expect(env.hashArbol() == hash0)
    }

    @Test func casoDeConformidadRenombrar() async throws {
        let caso = RutasRepo.casos.appendingPathComponent("escritor-renombrar-actualiza-enlaces")
        let env = EntornoCarpeta(copiando: caso.appendingPathComponent("entrada"))
        defer { env.limpiar() }
        let preview = try LinkRefactor(snapshot: env.foto())
            .renombrar(VaultPath("2 · Ventas/Empresas/talleres-martin-e-hijos.md"), a: "talleres-martin")
        #expect(preview.esSeguro)
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        let esperado = EntornoCarpeta(copiando: caso.appendingPathComponent("esperado"))
        defer { esperado.limpiar() }
        #expect(env.huella() == esperado.huella())
    }

    @Test func moverEntreAreasRecalculaRutasRelativas() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let antes = env.foto()
        let preview = try LinkRefactor(snapshot: antes).mover(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"),
                                                              a: VaultPath("6 · Equipo/Colaboradores"))
        #expect(preview.esSeguro)
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        let lucia = env.texto("6 · Equipo/Colaboradores/Lucía Prueba.md")!
        // Sus enlaces relativos salen ahora desde la carpeta nueva, con las tildes codificadas como estaban.
        #expect(lucia.contains("[José](../../2%20%C2%B7%20Ventas/Contactos/Jos%C3%A9%20N%C3%BA%C3%B1ez.md)"))
        // Los wikilinks por nombre único no cambian.
        #expect(lucia.contains("[[Ferretería Ejemplo]]") && lucia.contains("[[Embudo#Etapas]]"))
        #expect(env.texto("2 · Ventas/Empresas/Ferretería Ejemplo.md")!
            .contains("[Lucía Prueba](../../6%20·%20Equipo/Colaboradores/Lucía%20Prueba.md)"))
        let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: MoveMap(moves: preview.traslados.map { ($0.de, $0.a) }).map)
        #expect(fallos.isEmpty, "\(fallos)")
    }

    @Test func renombrarCarpetaEntera() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Rumbo.md", "# Rumbo\n\nVer [proyecto](../3%20·%20Entrega/Proyectos/web-ferreteria/Proyecto.md) y [[t-0001-preparar-arranque]] y [[3 · Entrega/Proyectos/web-ferreteria/Proyecto|el proyecto]].\n")
        let antes = env.foto()
        let hash0 = env.hashArbol()
        let preview = try LinkRefactor(snapshot: antes).renombrar(VaultPath("3 · Entrega/Proyectos/web-ferreteria"), a: "web-ferreteria-2026")
        #expect(preview.esSeguro)
        let bus = try await env.bus()
        try await LinkRefactor.aplicar(preview, con: bus)
        let rumbo = env.texto("1 · Dirección/Rumbo.md")!
        #expect(rumbo.contains("[proyecto](../3%20·%20Entrega/Proyectos/web-ferreteria-2026/Proyecto.md)"))
        #expect(rumbo.contains("[[t-0001-preparar-arranque]]"))
        #expect(rumbo.contains("[[3 · Entrega/Proyectos/web-ferreteria-2026/Proyecto|el proyecto]]"))
        // Dentro de la carpeta, los enlaces relativos siguen valiendo: no se tocan.
        #expect(env.texto("3 · Entrega/Proyectos/web-ferreteria-2026/Proyecto.md")
            == (try String(contentsOf: Apoyo.empresaMinima.appendingPathComponent("3 · Entrega/Proyectos/web-ferreteria/Proyecto.md"), encoding: .utf8)))
        let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: MoveMap(moves: preview.traslados.map { ($0.de, $0.a) }).map)
        #expect(fallos.isEmpty, "\(fallos)")
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(env.hashArbol() == hash0)
    }

    @Test func soloMayusculasEnDosPasos() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let preview = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"), a: "lucía prueba")
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        let nombres = try FileManager.default.contentsOfDirectory(atPath: env.url("2 · Ventas/Contactos").path)
            .map { $0.precomposedStringWithCanonicalMapping }
        #expect(nombres.contains("lucía prueba.md"))
        #expect(!nombres.contains("Lucía Prueba.md"))
        #expect(env.texto("2 · Ventas/Contactos/Contactos.md")!.contains("[[lucía prueba]]"))
        #expect(env.texto("2 · Ventas/Contactos/José Núñez.md")!.contains("(lucía%20prueba.md)"))
    }

    @Test func tildesEnNFDEnDiscoYEnLosEnlaces() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        // Enlace escrito en NFD hacia el fichero en NFD.
        let nfd = "José Núñez".decomposedStringWithCanonicalMapping
        env.escribir("2 · Ventas/Notas.md", "Ver [[\(nfd)]] y [José](Contactos/\(nfd.replacingOccurrences(of: " ", with: "%20")).md).\n")
        let antes = env.foto()
        let preview = try LinkRefactor(snapshot: antes).renombrar(VaultPath("2 · Ventas/Contactos/José Núñez.md"), a: "José Núñez García")
        #expect(preview.esSeguro)
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        let notas = env.texto("2 · Ventas/Notas.md")!
        #expect(notas.contains("[[José Núñez García]]"))
        #expect(notas.contains("Contactos/José%20Núñez%20García.md"))
        // El título visible salía del nombre del fichero: el anterior pasa a «Otros nombres»… salvo que haya H1.
        let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: MoveMap(moves: preview.traslados.map { ($0.de, $0.a) }).map)
        #expect(fallos.isEmpty, "\(fallos)")
    }

    @Test func parentesisYEspacios() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("4 · Finanzas/Notas.md", "[a](Gestoría/Asesor%20(Ejemplo).md) y [[Asesor (Ejemplo)]] y [b](Gestor%C3%ADa/Asesor%20%28Ejemplo%29.md).\n")
        let antes = env.foto()
        let preview = try LinkRefactor(snapshot: antes).renombrar(VaultPath("4 · Finanzas/Gestoría/Asesor (Ejemplo).md"), a: "Asesor (Nuevo)")
        #expect(preview.esSeguro)
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        #expect(env.texto("4 · Finanzas/Área.md")!.contains("[Asesoría](<Gestoría/Asesor (Nuevo).md>)"))
        #expect(env.texto("4 · Finanzas/Notas.md") == "[a](Gestoría/Asesor%20(Nuevo).md) y [[Asesor (Nuevo)]] y [b](Gestor%C3%ADa/Asesor%20%28Nuevo%29.md).\n")
        let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: MoveMap(moves: preview.traslados.map { ($0.de, $0.a) }).map)
        #expect(fallos.isEmpty, "\(fallos)")
    }

    @Test func dosNotasConElMismoNombre() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("2 · Ventas/Contactos/ana.md", "# Ana de ventas\n")
        env.escribir("6 · Equipo/Roles/ana.md", "# Ana del equipo\n")
        env.escribir("2 · Ventas/Contactos/Notas.md", "Hablar con [[ana]].\n")
        env.escribir("6 · Equipo/Roles/Notas.md", "Rol de [[ana]].\n")
        let antes = env.foto()
        // Mover la de Equipo a Ventas/Equipo: ambas quedarían a la misma distancia de «Contactos/Notas».
        let preview = try LinkRefactor(snapshot: antes).mover(VaultPath("6 · Equipo/Roles/ana.md"), a: VaultPath("2 · Ventas/Equipo"))
        #expect(preview.esSeguro)
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: MoveMap(moves: preview.traslados.map { ($0.de, $0.a) }).map)
        #expect(fallos.isEmpty, "\(fallos)")
        // El enlace a la que se movió se escribe con su ruta para que no se confunda con la otra.
        #expect(env.texto("6 · Equipo/Roles/Notas.md")!.contains("[[2 · Ventas/Equipo/ana]]"))
    }

    @Test func renombrarArea() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir(".tls/layout.json", "{\"preset\":\"humana\",\"areas\":{\"marca\":\"5 · Marca\"},\"privado\":[\"5 · Marca/Privado\"]}\n")
        env.escribir(".tls/config.yaml", "version: 1\nclase: copia\nprivado:\n  - \"5 · Marca/Privado\"\n  - Otra/cosa\n")
        env.escribir("5 · Marca/Privado/nota.md", "privada\n")
        env.escribir("5 · Marca/Logo/logo.png", "png")
        env.escribir("4 · Finanzas/Registros/recibidas.csv", "id,documento,importe\nR1,../5 · Marca/x.pdf,1\nR2,\"5 · Marca/Logo/logo.png\",2\n")
        env.escribir("5 · Marca/Marca.md", "---\nlogo: Logo/logo.png\n---\n# Marca\n")
        let antes = env.foto()
        let preview = try LinkRefactor(snapshot: antes).renombrar(VaultPath("5 · Marca"), a: "5 · Marketing")
        #expect(preview.esSeguro)
        let bus = try await env.bus()
        try await LinkRefactor.aplicar(preview, con: bus)
        #expect(env.texto(".tls/layout.json") == "{\"preset\":\"humana\",\"areas\":{\"marca\":\"5 · Marketing\"},\"privado\":[\"5 · Marketing/Privado\"]}\n")
        #expect(env.texto(".tls/config.yaml") == "version: 1\nclase: copia\nprivado:\n  - \"5 · Marketing/Privado\"\n  - Otra/cosa\n")
        #expect(env.texto("4 · Finanzas/Registros/recibidas.csv") == "id,documento,importe\nR1,../5 · Marca/x.pdf,1\nR2,\"5 · Marketing/Logo/logo.png\",2\n")
        #expect(env.texto("Empresa.md")!.contains("[Marca](5%20·%20Marketing/Área.md)"))
        // `logo` es relativa a la nota y la nota se mueve con su carpeta: no cambia.
        #expect(env.texto("5 · Marketing/Marca.md") == "---\nlogo: Logo/logo.png\n---\n# Marca\n")
        let layout = VaultLayout.load(root: env.root).layout
        #expect(layout.areaFolder(.marca).raw == "5 · Marketing")
        #expect(layout.isPrivate(VaultPath("5 · Marketing/Privado/nota.md")))
        let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: MoveMap(moves: preview.traslados.map { ($0.de, $0.a) }).map)
        #expect(fallos.isEmpty, "\(fallos)")
    }

    @Test func registroDePlantillasSigueAlFichero() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("5 · Marca/Sistemas/Plantillas/Post.md", "---\ntls_type: content\n---\n# {{titulo}}\n")
        env.escribir("5 · Marca/Sistemas/Plantillas/Otra.md", "# Otra\n")
        env.escribir(".tls/plantillas.yaml", "post:\n  fichero: \"{marca}/Sistemas/Plantillas/Post.md\"\n  tipo: content\notra:\n  fichero: 5 · Marca/Sistemas/Plantillas/Otra.md\n  tipo: note\n")
        let bus = try await env.bus()
        // Renombrar el área: la ruta con `{marca}` sigue valiendo; la escrita entera cambia.
        try await LinkRefactor.aplicar(try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("5 · Marca"), a: "5 · Marketing"), con: bus)
        #expect(env.texto(".tls/plantillas.yaml") == "post:\n  fichero: \"{marca}/Sistemas/Plantillas/Post.md\"\n  tipo: content\notra:\n  fichero: 5 · Marketing/Sistemas/Plantillas/Otra.md\n  tipo: note\n")
        // Renombrar la plantilla: el registro apunta al nombre nuevo, con su `{marca}`.
        try await LinkRefactor.aplicar(try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("5 · Marketing/Sistemas/Plantillas/Post.md"), a: "Publicación"), con: bus)
        #expect(env.texto(".tls/plantillas.yaml")!.hasPrefix("post:\n  fichero: \"{marca}/Sistemas/Plantillas/Publicación.md\"\n"))
        #expect(PlantillaRegistro.cargar(env.foto())["post"]?.fichero == "{marca}/Sistemas/Plantillas/Publicación.md")
    }

    @Test func rutasEnCSVYEnPropiedades() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-1.md", "---\npdf: \"2026-10-01 Factura F-1 Cliente 10,00€.pdf\"\n---\n# F-1\n")
        env.escribir("4 · Finanzas/Fiscal/2026/T4/Ingresos/2026-10-01 Factura F-1 Cliente 10,00€.pdf", "%PDF")
        env.escribir("4 · Finanzas/Fechas de documentos.csv", "ruta,fecha,fuente,nota\r\n\"Fiscal/2026/T4/Ingresos/2026-10-01 Factura F-1 Cliente 10,00€.pdf\",2026-10-01,manual,\r\n")
        env.escribir("4 · Finanzas/Registros/pagos.csv", "id,evidencia\nP1,Registros/movs.csv#MOV-1\nP2,Recibo TPV\n")
        env.escribir("4 · Finanzas/Registros/movs.csv", "id\nMOV-1\n")
        let preview = try LinkRefactor(snapshot: env.foto()).renombrar(
            VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/2026-10-01 Factura F-1 Cliente 10,00€.pdf"),
            a: "2026-10-01 Factura F-2026-0001 Cliente 10,00€")
        #expect(preview.filasCSV == 1)
        let bus = try await env.bus()
        try await LinkRefactor.aplicar(preview, con: bus)
        #expect(env.texto("4 · Finanzas/Fechas de documentos.csv") == "ruta,fecha,fuente,nota\r\n\"Fiscal/2026/T4/Ingresos/2026-10-01 Factura F-2026-0001 Cliente 10,00€.pdf\",2026-10-01,manual,\r\n")
        #expect(env.texto("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-1.md") == "---\npdf: \"2026-10-01 Factura F-2026-0001 Cliente 10,00€.pdf\"\n---\n# F-1\n")
        let movs = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("4 · Finanzas/Registros/movs.csv"), a: "movimientos")
        try await LinkRefactor.aplicar(movs, con: bus)
        #expect(env.texto("4 · Finanzas/Registros/pagos.csv") == "id,evidencia\nP1,Registros/movimientos.csv#MOV-1\nP2,Recibo TPV\n")
    }

    @Test func aliasCuandoCambiaElNombreQueSeVe() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Ideas sueltas.md", "Sin título propio.\n")
        env.escribir("1 · Dirección/Otra.md", "Ver [[Ideas sueltas]].\n")
        let preview = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("1 · Dirección/Ideas sueltas.md"), a: "Ideas")
        #expect(preview.cambios.first { $0.ruta.raw == "1 · Dirección/Ideas sueltas.md" }?.alias == "Ideas sueltas")
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        #expect(env.texto("1 · Dirección/Ideas.md") == "---\naliases: [Ideas sueltas]\n---\nSin título propio.\n")
        #expect(env.texto("1 · Dirección/Otra.md") == "Ver [[Ideas]].\n")
    }

    @Test func textoVisibleSoloSiSePide() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Notas.md", "[[Rumbo|Rumbo]] y [Rumbo](Rumbo.md) y [el rumbo](Rumbo.md).\n")
        let opciones = LinkRefactor.Opciones(actualizarTextoVisible: true)
        let preview = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("1 · Dirección/Rumbo.md"), a: "Dirección y rumbo", opciones: opciones)
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        // El H1 «Rumbo» no cambia, pero el texto coincidía con el nombre del fichero.
        #expect(env.texto("1 · Dirección/Notas.md") == "[[Dirección y rumbo|Dirección y rumbo]] y [Dirección y rumbo](Dirección%20y%20rumbo.md) y [el rumbo](Dirección%20y%20rumbo.md).\n")
    }

    @Test func noTocaCodigoNiEnlacesExternos() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let original = "Ver [[Rumbo]].\n\n```\n[[Rumbo]]\n```\n\n`[[Rumbo]]` y [web](https://ejemplo.com/Rumbo.md).\n"
        env.escribir("1 · Dirección/Notas.md", original)
        let preview = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("1 · Dirección/Rumbo.md"), a: "Norte")
        try await LinkRefactor.aplicar(preview, con: try await env.bus())
        #expect(env.texto("1 · Dirección/Notas.md") == original.replacingOccurrences(of: "Ver [[Rumbo]]", with: "Ver [[Norte]]"))
    }

    @Test func errores() throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let r = LinkRefactor(snapshot: env.foto())
        #expect(throws: RefactorError.destinoOcupado("2 · Ventas/Contactos/José Núñez.md")) {
            try r.renombrar(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"), a: "José Núñez")
        }
        #expect(throws: RefactorError.nombreNoValido("a/b")) { try r.renombrar(VaultPath("1 · Dirección/Rumbo.md"), a: "a/b") }
        #expect(throws: RefactorError.nombreNoValido(".oculto")) { try r.renombrar(VaultPath("1 · Dirección/Rumbo.md"), a: ".oculto") }
        #expect(throws: RefactorError.carpetaDeLaApp("Archivo")) { try r.renombrar(VaultPath("Archivo"), a: "Viejo") }
        #expect(throws: RefactorError.dentroDeSiMisma("2 · Ventas")) { try r.mover(VaultPath("2 · Ventas"), a: VaultPath("2 · Ventas/Contactos")) }
        #expect(throws: RefactorError.noExiste("No/existe.md")) { try r.renombrar(VaultPath("No/existe.md"), a: "x") }
        #expect(throws: RefactorError.sinCambios) { try r.renombrar(VaultPath("1 · Dirección/Rumbo.md"), a: "Rumbo") }
    }

    @Test func movidoEnFinderSeArreglaYEnObsidianNoHaceFalta() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let de = VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")
        let a = VaultPath("2 · Ventas/Contactos/Lucía Ferrer.md")
        try FileManager.default.moveItem(at: de.url(in: env.root), to: a.url(in: env.root))
        let arreglo = try LinkRefactor(snapshot: env.foto()).arreglarMovimientoExterno([Traslado(de: de, a: a)])
        #expect(arreglo.enlaces == 5)
        #expect(!arreglo.plan.ops.contains { if case .move = $0 { return true } else { return false } })
        _ = try await LinkRefactor.aplicar(arreglo, con: try await env.bus())
        #expect(env.texto("2 · Ventas/Contactos/Contactos.md")!.contains("[[Lucía Ferrer]]"))
        #expect(env.texto("2 · Ventas/Contactos/José Núñez.md")!.contains("[Lucía](Lucía%20Ferrer.md)"))
        #expect(SaludDeEnlaces(snapshot: env.foto()).revisar().allSatisfy { !$0.enlace.contains("Lucía") })
        // Si los enlaces ya apuntan a la ruta nueva (como deja Obsidian), no hay nada que escribir.
        let otra = try LinkRefactor(snapshot: env.foto()).arreglarMovimientoExterno([Traslado(de: de, a: a)])
        #expect(otra.plan.ops.isEmpty)
    }

    @Test func cambioExternoEntreVistaPreviaYAplicar() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let preview = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"), a: "Lucía Ferrer")
        env.escribir("2 · Ventas/Contactos/Contactos.md", "- [[Lucía Prueba]]\n- [[José Núñez]]\n- cambiado fuera\n")
        let hash = env.hashArbol()
        await esperaErrorAsync(.cambioExterno("2 · Ventas/Contactos/Contactos.md")) {
            try await LinkRefactor.aplicar(preview, con: try await env.bus())
        }
        // Todo o nada: no se escribió ni se movió nada.
        #expect(env.hashArbol() == hash)
    }

    @Test func siLaAppMuereAMitadSeCompletaAlAbrir() async throws {
        // Lo que tiene que quedar.
        let ref = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { ref.limpiar() }
        try await LinkRefactor.aplicar(try LinkRefactor(snapshot: ref.foto()).renombrar(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"), a: "Lucía Ferrer"),
                                       con: try await ref.bus())
        let esperado = ref.huella()
        var interrumpidos = 0
        for fallo in (0..<8).map({ VaultWriter.FaultPoint.trasPaso($0) }) + [.trasTemporal(2), .antesDeHecho] {
            let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
            defer { env.limpiar() }
            let preview = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"), a: "Lucía Ferrer")
            let w = try await env.writer()
            await w.setFault(fallo)
            do {
                try await LinkRefactor.aplicar(preview, con: CommandBus(writer: w))
            } catch WriteError.interrumpido {
                interrumpidos += 1
                let w2 = try await env.writer()
                let informe = await w2.lastRecovery
                #expect(informe.conflictos.isEmpty, "\(fallo)")
                #expect(w2.conflicts.pendientes().isEmpty, "\(fallo)")
            }
            #expect(env.huella() == esperado, "\(fallo)")
        }
        #expect(interrumpidos >= 6)
    }

    @Test func riberaSinEnlacesRotos() async throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let hash0 = env.hashArbol()
        let bus = try await env.bus()
        let pasos: [(String, String)] = [
            ("2 · Ventas/Empresas/talleres-martin-e-hijos.md", "talleres-martin"),
            ("2 · Ventas/Oportunidades/jorge-martin-trimestrales", "jorge-martin-trimestrales-2026"),
            ("2 · Ventas/Productos/trimestrales.md", "trimestrales-pymes"),
            ("4 · Finanzas", "4 · Finanzas y caja"),
            ("2 · Ventas", "2 · Comercial"),
        ]
        var deshacer = 0
        for (ruta, nombre) in pasos {
            let antes = env.foto()
            guard antes.existing(VaultPath(ruta)) != nil else { Issue.record("No existe \(ruta)"); continue }
            let preview = try LinkRefactor(snapshot: antes).renombrar(VaultPath(ruta), a: nombre)
            #expect(preview.esSeguro, "\(ruta): \(preview.problemas)")
            let r = try await LinkRefactor.aplicar(preview, con: bus)
            #expect(r.hecho)
            deshacer += 1
            let mapa = MoveMap(moves: preview.traslados.map { ($0.de, $0.a) })
            let fallos = comprobarEnlaces(antes: antes, despues: env.foto(), mapa: mapa.map)
            #expect(fallos.isEmpty, "\(ruta): \(fallos.prefix(5))")
            // Ningún enlace nuevo sin resolver.
            let rotosAntes = SaludDeEnlaces(snapshot: antes).revisar().count
            let rotosDespues = SaludDeEnlaces(snapshot: env.foto()).revisar().count
            #expect(rotosDespues <= rotosAntes, "\(ruta): \(rotosAntes) → \(rotosDespues)")
        }
        // Las rutas de documento de los CSV siguen apuntando a ficheros que existen.
        let foto = env.foto()
        for csv in foto.textPaths where csv.ext == "csv" {
            let tabla = CSVTable.parse(foto.text(csv)!)
            guard let col = tabla.header.firstIndex(of: "documento") else { continue }
            for fila in tabla.rows where col < fila.count && !fila[col].isEmpty {
                let base = VaultPath(csv.components[0])
                #expect(foto.existing(VaultPath(base.raw + "/" + fila[col])) != nil, "\(csv.raw): \(fila[col])")
            }
        }
        for _ in 0..<deshacer { _ = try await bus.deshacer(autor: .persona("Manu")) }
        #expect(env.hashArbol() == hash0)
    }
}

@Suite("Salud de enlaces y menciones")
struct SaludDeEnlacesTests {
    @Test func pendientesAmbiguosYFlojos() {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        // Mismo largo de ruta: también ambiguo en Obsidian.
        env.escribir("2 · Ventas/Contactos/ana.md", "# Ana\n")
        env.escribir("6 · Equipo/Contactos/ana.md", "# Ana\n")
        env.escribir("1 · Dirección/Notas.md", "[[Nota que no existe]], [[ana]], [Rumbo](Otra/Rumbo.md) y [x](Rumbo.md).\n")
        let salud = SaludDeEnlaces(snapshot: env.foto())
        let r = salud.revisar(VaultPath("1 · Dirección/Notas.md"))
        #expect(r.count == 3)
        #expect(r[0].estado == .pendiente)
        #expect(r[1].estado == .ambiguo([VaultPath("2 · Ventas/Contactos/ana.md"), VaultPath("6 · Equipo/Contactos/ana.md")]))
        #expect(r[2].estado == .flojo(VaultPath("1 · Dirección/Rumbo.md")))
    }

    @Test func arreglarFlojos() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("2 · Ventas/Notas.md", "[Rumbo](Otra/Rumbo.md)\n")
        let plan = try #require(SaludDeEnlaces(snapshot: env.foto()).arreglarFlojos())
        _ = try await (try await env.bus()).ejecutar(plan)
        #expect(env.texto("2 · Ventas/Notas.md") == "[Rumbo](../1%20·%20Dirección/Rumbo.md)\n")
    }

    @Test func mencionesSinEnlazarYEnlazar() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Notas.md", """
        Hablé con lucía prueba ayer. [[Lucía Prueba]] ya está enlazada.
        `Lucía Prueba` en código no cuenta, ni LucíaPruebas.
        """)
        let salud = SaludDeEnlaces(snapshot: env.foto())
        let destino = VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")
        let menciones = salud.mencionesSinEnlazar(de: destino).filter { $0.origen.raw == "1 · Dirección/Notas.md" }
        #expect(menciones.count == 1)
        #expect(menciones.first?.texto == "lucía prueba")
        let plan = try #require(salud.enlazar(menciones))
        _ = try await (try await env.bus()).ejecutar(plan)
        #expect(env.texto("1 · Dirección/Notas.md")!.hasPrefix("Hablé con [lucía prueba](../2%20·%20Ventas/Contactos/Lucía%20Prueba.md) ayer."))
    }
}
