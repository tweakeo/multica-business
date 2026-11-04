import Foundation
import Testing
import TLSCore
@testable import TLSImport

@Suite("Ordenar lo que tienes · enlaces de lo que se trae de fuera")
struct LinkRewriterTests {
    let raiz = URL(fileURLWithPath: "/tmp/Origen de prueba")

    func rw(_ destinos: [String: String], ficheros: [String]) -> LinkRewriter {
        var d: [VaultPath: VaultPath] = [:]
        for (k, v) in destinos { d[VaultPath(k)] = VaultPath(v) }
        return LinkRewriter(destinos: d, raizFuente: raiz, ficherosDeLaFuente: ficheros.map(VaultPath.init))
    }

    @Test("Relativos, con %20 o <…>, y absolutos dentro del origen: siguen apuntando a lo mismo")
    func markdown() {
        let r = rw(["Clientes/Ana López.md": "2 · Ventas/Contactos/ana-lopez.md",
                    "Propuestas/Propuesta (final).pdf": "2 · Ventas/Oportunidades/Propuesta (final).pdf",
                    "Notas/Plan.md": "1 · Dirección/Recursos/Plan.md"],
                   ficheros: ["Clientes/Ana López.md", "Propuestas/Propuesta (final).pdf", "Notas/Plan.md"])
        let texto = """
        Ver [Ana](../Clientes/Ana%20L%C3%B3pez.md#datos), [la propuesta](<../Propuestas/Propuesta (final).pdf>),
        [otra vez](/tmp/Origen de prueba/Clientes/Ana López.md) y [fuera](https://example.com).
        Y [roto](../No/existe.md).
        """
        let out = r.reescribir(texto, origen: VaultPath("Notas/Plan.md"), destino: VaultPath("1 · Dirección/Recursos/Plan.md"))
        #expect(out.texto.contains("[Ana](../../2%20·%20Ventas/Contactos/ana-lopez.md#datos)"))
        #expect(out.texto.contains("[la propuesta](<../../2 · Ventas/Oportunidades/Propuesta (final).pdf>)"))
        #expect(out.texto.contains("[otra vez](../../2%20·%20Ventas/Contactos/ana-lopez.md)"))
        #expect(out.texto.contains("[fuera](https://example.com)"))
        #expect(out.texto.contains("[roto](../No/existe.md)"))
        #expect(out.cambios == 3)
        #expect(out.sinDestino == ["../No/existe.md"])
    }

    @Test("Wikilinks a una nota que cambia de nombre: el nombre nuevo y el de antes como texto visible")
    func wikilinks() {
        let r = rw(["Clientes/Ana López.md": "2 · Ventas/Contactos/ana-lopez.md"], ficheros: ["Clientes/Ana López.md", "Otra.md"])
        let out = r.reescribir("Hablé con [[Ana López]], con [[Ana López|Ana]], de [[Ana López#Datos]] y de [[Otra]].\n",
                               origen: VaultPath("Notas/x.md"), destino: VaultPath("Buzón/x.md"))
        #expect(out.texto == "Hablé con [[ana-lopez|Ana López]], con [[ana-lopez|Ana]], de [[ana-lopez#Datos]] y de [[Otra]].\n")
    }

    @Test("Las rutas relativas se calculan desde la carpeta de la nota en su sitio nuevo")
    func relativa() {
        #expect(LinkRewriter.relativa(desde: VaultPath("a/b/n.md"), a: VaultPath("a/c/d.md")) == "../c/d.md")
        #expect(LinkRewriter.relativa(desde: VaultPath("n.md"), a: VaultPath("a/d.md")) == "a/d.md")
        #expect(LinkRewriter.relativa(desde: VaultPath("a/n.md"), a: VaultPath("a/d.md")) == "d.md")
        #expect(LinkRewriter.codificar("a b/(c)%.md") == "a%20b/%28c%29%25.md")
    }
}
