import Foundation
import Testing
@testable import TLSCore

/// Revisión de fidelidad con Obsidian (F1). Cada prueba reproduce un hallazgo ya corregido: la regla
/// de nombres repetidos es la de Obsidian 1.7 (`getLinkpathDest`), crear no cambia el destino de
/// enlaces que ya había, los nombres no rompen enlaces y las series y versiones salen bien numeradas.
@Suite("Revisión de fidelidad")
struct RevisionFidelidadTests {
    static let manu = Autor.persona("Manu")

    static func motor(_ env: EntornoCarpeta, _ reloj: Reloj = relojDePrueba()) -> PlantillaMotor {
        PlantillaMotor(snapshot: env.foto(), opciones: .init(reloj: reloj))
    }

    /// Crea con una plantilla y devuelve la ruta creada y sus propiedades.
    static func crear(_ env: EntornoCarpeta, _ bus: CommandBus, _ p: PlantillaMotor.Peticion,
                      reloj: Reloj = relojDePrueba()) async throws -> (VaultPath, Frontmatter) {
        let nota = try motor(env, reloj).preparar(p)
        let r = try await bus.ejecutar(nota.plan)
        #expect(r.hecho)
        return (nota.ruta, env.foto().frontmatter(nota.ruta))
    }

    // MARK: Hallazgo 1 · nombres repetidos

    @Test("Con nombres repetidos, cada enlace va donde lo lleva Obsidian")
    func nombresRepetidosComoObsidian() {
        let r = LinkResolver(paths: ["P/R/nota.md", "Z/nota.md", "P/Q/x.md"].map { VaultPath($0) })
        // Ninguna cuelga de «P/Q»: la de ruta más corta.
        #expect(r.resolve("[[nota]]", from: VaultPath("P/Q/x.md")) == VaultPath("Z/nota.md"))
        // Desde «P»: la que cuelga de su carpeta, aunque su ruta sea más larga.
        #expect(r.resolve("[[nota]]", from: VaultPath("P/x.md")) == VaultPath("P/R/nota.md"))
        // La de la raíz gana por ruta exacta, también a la de al lado.
        let raiz = LinkResolver(paths: ["nota.md", "A/nota.md", "A/x.md"].map { VaultPath($0) })
        #expect(raiz.resolve("[[nota]]", from: VaultPath("A/x.md")) == VaultPath("nota.md"))
        // Empate de verdad (misma longitud, ninguna cuelga de la carpeta): ambiguo.
        let empate = LinkResolver(paths: ["A/nota.md", "B/nota.md", "C/x.md"].map { VaultPath($0) })
        #expect(empate.resolve("[[nota]]", from: VaultPath("C/x.md")) == nil)
        // En un wikilink la ruta escrita es obligatoria: si no existe, el enlace está roto.
        let unica = LinkResolver(paths: ["Buena/nota.md", "x.md"].map { VaultPath($0) })
        #expect(unica.resolve("[[Vieja/nota]]", from: VaultPath("x.md")) == nil)
        #expect(unica.resolve("[[Buena/nota]]", from: VaultPath("x.md")) == VaultPath("Buena/nota.md"))
    }

    @Test("La salud de enlaces avisa de un wikilink con la carpeta equivocada")
    func rutaEquivocadaSeAvisa() {
        let env = EntornoCarpeta(vacia: false)
        defer { env.limpiar() }
        env.escribir("Buena/nota.md", "n\n")
        env.escribir("x.md", "[[Vieja/nota]]\n")
        #expect(SaludDeEnlaces(snapshot: env.foto()).revisar(VaultPath("x.md")).count == 1)
    }

    @Test("Renombrar con nombres repetidos no cambia el destino de ningún enlace")
    func renombrarConNombresRepetidos() async throws {
        let env = EntornoCarpeta(vacia: false)
        defer { env.limpiar() }
        env.escribir("P/R/nota.md", "R\n")
        env.escribir("Z/otra.md", "Z\n")
        env.escribir("P/Q/x.md", "[[nota]] y [[otra]]\n")
        let bus = try await env.bus()
        // `Z/otra` pasa a llamarse como `P/R/nota`: los dos enlaces se escriben con su ruta.
        let antes = env.foto()
        let previa = try LinkRefactor(snapshot: antes).renombrar(VaultPath("Z/otra.md"), a: "nota")
        #expect(previa.esSeguro)
        #expect(try await LinkRefactor.aplicar(previa, con: bus).hecho)
        let mapa: (VaultPath) -> VaultPath = { $0 == VaultPath("Z/otra.md") ? VaultPath("Z/nota.md") : $0 }
        #expect(comprobarEnlaces(antes: antes, despues: env.foto(), mapa: mapa).isEmpty)
        #expect(env.texto("P/Q/x.md")?.contains("[[nota]]") == false)
        // Y renombrar la que no es destino no toca el enlace.
        let antes2 = env.foto()
        let destinos = LinkScanner.scan(env.texto("P/Q/x.md")!).map { antes2.resolver.resolve($0.link.resolvable, from: VaultPath("P/Q/x.md")) }
        let previa2 = try LinkRefactor(snapshot: antes2).renombrar(VaultPath("Z/nota.md"), a: "nota-z")
        #expect(try await LinkRefactor.aplicar(previa2, con: bus).hecho)
        let despues2 = env.foto()
        let ahora = LinkScanner.scan(env.texto("P/Q/x.md")!).map { despues2.resolver.resolve($0.link.resolvable, from: VaultPath("P/Q/x.md")) }
        #expect(ahora == destinos.map { $0 == VaultPath("Z/nota.md") ? VaultPath("Z/nota-z.md") : $0 })
    }

    // MARK: Hallazgo 2 · crear con un nombre que ya existe

    @Test("Crear un segundo «Proyecto.md» no se lleva los enlaces del primero")
    func crearConNombreRepetidoProtegeEnlaces() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        let primero = VaultPath("3 · Entrega/Proyectos/talleres-martin-renta-anual/Proyecto.md")
        let tarea = VaultPath("3 · Entrega/Proyectos/talleres-martin-renta-anual/Tareas/t-0001-primera-sesion.md")
        env.escribir(primero.raw, "---\ntls_type: project\n---\n# Talleres\n")
        env.escribir(tarea.raw, "---\ntls_type: task\nproyecto: \"[[Proyecto|Talleres]]\"\n---\n# Primera sesión\n")
        let nuevo = VaultPath("3 · Entrega/Proyectos/bar/Proyecto.md")
        let ops = LinkRefactor(snapshot: env.foto()).protegerEnlaces(alCrear: [nuevo])
        #expect(ops.count == 1)
        let bus = try await env.bus()
        #expect(try await bus.ejecutar(WritePlan(autor: Self.manu, descripcion: "Crear «Bar»",
                                                 ops: ops + [.create(nuevo, text: "---\ntls_type: project\n---\n# Bar\n")])).hecho)
        let foto = env.foto()
        let enlace = try #require(foto.frontmatter(tarea).text("proyecto"))
        #expect(foto.resolver.resolve(enlace, from: tarea) == primero)
        #expect(enlace.hasSuffix("|Talleres]]"))
        // Sin nombres repetidos no hay nada que proteger.
        #expect(LinkRefactor(snapshot: foto).protegerEnlaces(alCrear: [VaultPath("3 · Entrega/Otra.md")]).isEmpty)
    }

    @Test("Ribera: factura, colaboración con el mismo nombre y renombrar el contacto")
    func cadenaDeRibera() async throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let bus = try await env.bus()
        let contacto = VaultPath("2 · Ventas/Contactos/amparo-ribera.md")
        let (factura, _) = try await Self.crear(env, bus, .init(plantilla: "factura",
                                                                desde: VaultPath("2 · Ventas/Oportunidades/amparo-ribera-trimestrales.md")))
        func destinoEnLaFactura() throws -> VaultPath? {
            let foto = env.foto()
            let enlace = try #require(foto.frontmatter(factura).text("contacto"))
            return foto.resolver.resolve(enlace, from: factura)
        }
        #expect(try destinoEnLaFactura() == contacto)
        // La colaboración se llama como el contacto: la factura sigue yendo al contacto.
        let (colaboracion, _) = try await Self.crear(env, bus, .init(plantilla: "acuerdo-de-colaboracion", desde: contacto))
        #expect(colaboracion.name == contacto.name)
        #expect(try destinoEnLaFactura() == contacto)
        // Renombrar el contacto actualiza la factura.
        let previa = try LinkRefactor(snapshot: env.foto()).renombrar(contacto, a: "amparo-ribera-soler")
        #expect(previa.esSeguro)
        #expect(try await LinkRefactor.aplicar(previa, con: bus).hecho)
        #expect(try destinoEnLaFactura() == VaultPath("2 · Ventas/Contactos/amparo-ribera-soler.md"))
    }

    // MARK: Hallazgo 3 · nombres que rompen enlaces

    @Test("Los nombres con / : \\ # ^ [ ] | no se aceptan ni se crean")
    func nombresQueRompenEnlaces() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        env.escribir("N/n.md", "n\n")
        for nombre in ["Cliente #1", "Pedido [2026]", "A|B", "Copia ^2", "Barra\\Invertida", "a/b", "c:d"] {
            #expect(throws: RefactorError.nombreNoValido(nombre)) {
                try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("N/n.md"), a: nombre)
            }
        }
        #expect(NombresDeFicha.fichero("Embudo #2") == "Embudo 2")
        #expect(NombresDeFicha.fichero("Alta | baja [2026]") == "Alta baja 2026")
        // Una ficha con título «Embudo #2»: el enlace que escribe la app resuelve.
        let bus = try await env.bus()
        let (ruta, _) = try await Self.crear(env, bus, .init(plantilla: "ficha-de-sistema", valores: ["titulo": "Embudo #2"], area: .ventas))
        #expect(ruta == VaultPath("2 · Ventas/Sistemas/Embudo 2.md"))
        let foto = env.foto()
        let enlace = NombresDeFicha.wikilink(ruta, nombre: "Embudo #2", en: foto)
        #expect(foto.resolver.resolve(enlace, from: VaultPath("Empresa.md")) == ruta)
    }

    // MARK: Hallazgo 4 · nombre fijo

    @Test("Las plantillas de nombre fijo no duplican; las de slug siguen en kebab")
    func nombreFijoNoDuplica() throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let m = Self.motor(env)
        #expect(throws: PlantillaError.yaExiste("2 · Ventas/Área.md")) {
            try m.preparar(.init(plantilla: "cabecera-de-area", area: .ventas))
        }
        #expect(throws: PlantillaError.yaExiste("Empresa.md")) { try m.preparar(.init(plantilla: "tu-empresa")) }
        let c = try m.preparar(.init(plantilla: "contacto", valores: ["titulo": "Lucía Ferrer"]))
        #expect(c.ruta == VaultPath("2 · Ventas/Contactos/lucia-ferrer-2.md"))
    }

    // MARK: Hallazgos 5 y 6 · versiones y series

    @Test("Versiones: la mayor con el mismo nombre, más uno; el presupuesto no gasta número")
    func versionesBienNumeradas() async throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let bus = try await env.bus()
        let contador = Secuencias.leer(env.foto())
        // Ribera tiene renta-v1, renta-v2 y trim-v1: la siguiente de renta es la 3.
        let (oferta, fo) = try await Self.crear(env, bus, .init(plantilla: "version-de-oferta", desde: VaultPath("2 · Ventas/Productos/renta.md")))
        #expect(oferta.name == "renta-v3.md")
        #expect(fo.text("version") == "3")
        let (guion, fg) = try await Self.crear(env, bus, .init(plantilla: "guion-de-diagnostico"))
        #expect(guion.name == "guion-de-diagnostico-v2.md")
        #expect(fg.text("version") == "2")
        let opp = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
        let (propuesta, fp) = try await Self.crear(env, bus, .init(plantilla: "propuesta", desde: opp))
        #expect(propuesta.name == "Propuesta v2.md")
        #expect(fp.text("version") == "2")
        let (p1, f1) = try await Self.crear(env, bus, .init(plantilla: "presupuesto", desde: opp))
        let (p2, f2) = try await Self.crear(env, bus, .init(plantilla: "presupuesto", desde: opp))
        #expect([p1.name, p2.name] == ["Presupuesto v1.md", "Presupuesto v2.md"])
        #expect([f1.text("version"), f2.text("version")] == ["1", "2"])
        // Se numera al aprobarlo (PLANTILLAS §3.3), no al crear el borrador.
        #expect(Secuencias.leer(env.foto()) == contador)
    }

    @Test("Seguimientos: el orden cuenta todos los del cliente, no solo los del día")
    func seguimientoCuentaTodos() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let bus = try await env.bus()
        let proyecto = VaultPath("3 · Entrega/Proyectos/web-ferreteria/Proyecto.md")
        let (r1, _) = try await Self.crear(env, bus, .init(plantilla: "reunion-de-seguimiento", desde: proyecto),
                                           reloj: relojDePrueba(2026, 10, 1))
        let (r2, _) = try await Self.crear(env, bus, .init(plantilla: "reunion-de-seguimiento", desde: proyecto))
        #expect(r1.name == "2026-10-01-seguimiento-1.md")
        #expect(r2.name == "2026-10-22-seguimiento-2.md")
        #expect(env.texto(r2.raw)?.contains("# Seguimiento 2 ·") == true)
    }

    @Test("Recibos: el número va en la ficha y no se repite aunque se pierda el contador")
    func recibosNumerados() async throws {
        let env = EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
        defer { env.limpiar() }
        let bus = try await env.bus()
        let factura = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
        let (r1, f1) = try await Self.crear(env, bus, .init(plantilla: "recibo-de-cobro", desde: factura))
        #expect(f1.text("numero") == r1.stem)
        #expect(env.texto(r1.raw)?.contains("[falta: numero]") == false)
        // El contador se pierde (una copia restaurada sin `.tls`, un conflicto de iCloud…).
        try FileManager.default.removeItem(at: env.url(Secuencias.ruta.raw))
        let (r2, f2) = try await Self.crear(env, bus, .init(plantilla: "recibo-de-cobro", desde: factura))
        #expect(r2.stem != r1.stem)
        #expect(!r2.name.contains("("))
        #expect(f2.text("numero") == r2.stem)
    }

    // MARK: Hallazgo 7 · nombre de tarea

    @Test("Una tarea creada con la plantilla no pasa de 60 caracteres de nombre")
    func tareaLargaConPlantilla() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        let titulo = "Preparar la propuesta económica completa para la renovación anual del servicio de asesoría fiscal"
        let n = try Self.motor(env).preparar(.init(plantilla: "tarea", valores: ["titulo": titulo]))
        #expect(n.ruta.stem.count <= 60)
        #expect(n.ruta.stem.hasPrefix("t-0001-preparar-la-propuesta-economica"))
        #expect(!n.ruta.stem.hasSuffix("-"))
        let t = try TaskStore(snapshot: env.foto(), reloj: relojDePrueba()).crear(NuevaTarea(titulo: titulo, area: .direccion))
        #expect(t.ruta.stem.count <= 60)
    }

    // MARK: Hallazgo 8 · lienzos

    @Test("Renombrar actualiza los lienzos de Obsidian y deshacer los deja igual")
    func lienzosAlRenombrar() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        env.escribir("Marca/Marca.md", "# Marca\n")
        env.escribir("Marca/Logo.md", "# Logo\n")
        env.escribir("Mapa.canvas", """
        {"nodes":[{"id":"a","type":"file","file":"Marca/Marca.md","x":0,"y":0,"width":400,"height":400},\
        {"id":"b","type":"file","file":"Marca/Logo.md","x":500,"y":0,"width":400,"height":400},\
        {"id":"c","type":"text","text":"Marca/Marca.md","x":0,"y":500,"width":400,"height":100}],"edges":[]}
        """)
        let bus = try await env.bus()
        let huella = env.huella()
        let previa = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("Marca"), a: "Imagen")
        #expect(previa.esSeguro)
        #expect(try await LinkRefactor.aplicar(previa, con: bus).hecho)
        let lienzo = try #require(env.texto("Mapa.canvas"))
        #expect(lienzo.contains(#""file":"Imagen/Marca.md""#))
        #expect(lienzo.contains(#""file":"Imagen/Logo.md""#))
        // El texto de una tarjeta no es un enlace: no se toca.
        #expect(lienzo.contains(#""text":"Marca/Marca.md""#))
        let renombrar = try LinkRefactor(snapshot: env.foto()).renombrar(VaultPath("Imagen/Logo.md"), a: "Logotipo")
        #expect(try await LinkRefactor.aplicar(renombrar, con: bus).hecho)
        #expect(env.texto("Mapa.canvas")?.contains(#""file":"Imagen/Logotipo.md""#) == true)
        _ = try await bus.deshacer(autor: Self.manu)
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(env.huella() == huella)
    }
}
