import Foundation
import Testing
@testable import TLSCore

/// Revisión adversarial de seguridad de datos (F1). Cada prueba reproduce un hallazgo: la parte
/// que hoy falla va dentro de `withKnownIssue`, así la batería sigue en verde y el fallo queda a la
/// vista («known issue»). Cuando se corrija un hallazgo, su `withKnownIssue` empezará a fallar
/// («Known issue was not recorded»): entonces se quita el envoltorio y la prueba queda como regresión.
@Suite(.serialized) struct RevisionSeguridadTests {
    static let manu = Autor.persona("Manu")
    static let rumbo = "1 · Dirección/Rumbo.md"
    static let decisiones = "1 · Dirección/Decisiones.md"
    static let lucia = "2 · Ventas/Contactos/Lucía Prueba.md"

    /// Carpetas (rutas relativas en NFC) bajo `root`, también las ocultas.
    static func carpetas(_ root: URL) -> Set<String> {
        var out = Set<String>()
        let fm = FileManager.default
        var stack = [root]
        while let dir = stack.popLast() {
            for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                let u = dir.appendingPathComponent(n)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    out.insert(String(u.path.dropFirst(root.path.count + 1)).precomposedStringWithCanonicalMapping)
                    stack.append(u)
                }
            }
        }
        return out
    }

    // MARK: 1 · Revertir pisa un cambio de fuera

    /// Un plan de dos ficheros falla en el segundo; al volver atrás el primero, la app lo
    /// sustituye por la copia previa **sin comprobar** que sigue como ella lo dejó: si la persona
    /// lo cambió en Obsidian entre medias, su texto se pierde sin tarjeta.
    @Test func revertirNoPisaLoEscritoFuera() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let deFuera = "# Decisiones\n\nEscrito en Obsidian mientras la app guardaba.\n"
        let uDec = e.url(Self.decisiones), uRumbo = e.url(Self.rumbo)
        await bus.writer.setBeforeStep { n in
            guard n == 1 else { return }
            // Decisiones (paso 0) ya está escrita: la persona la cambia; y Rumbo cambia también (el paso 1 fallará).
            try? Data(deFuera.utf8).write(to: uDec)
            try? Data("# Rumbo cambiado fuera\n".utf8).write(to: uRumbo)
        }
        await esperaErrorAsync(.cambioExterno(Self.rumbo)) {
            try await bus.ejecutar(WritePlan(autor: Self.manu, descripcion: "Dos notas", ops: [
                .appendLine(VaultPath(Self.decisiones), line: "- 2026-10-22 · Una"),
                .appendLine(VaultPath(Self.rumbo), line: "Línea")]))
        }
        await bus.writer.setBeforeStep(nil)
        do {
            #expect(e.texto(Self.decisiones) == deFuera, "el texto escrito en Obsidian se ha perdido")
            #expect(bus.writer.conflicts.pendientes().contains { $0.ruta == VaultPath(Self.decisiones) })
        }
    }

    // MARK: 2 · Recuperar aplica medio plan

    /// El proceso muere antes de escribir nada de un plan de dos ficheros; antes de volver a
    /// abrir, la persona cambia el primero. Al abrir, el primero va a tarjeta (bien), pero el
    /// segundo se aplica igualmente: el plan «todo o nada» queda a medias (en un renombrado,
    /// enlaces que apuntan a una nota que no se movió).
    @Test func recuperarUnPlanQueNoEmpezoEsTodoONada() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let w = try await e.writer()
        await w.setFault(.trasTemporal(0))
        await esperaErrorAsync(.interrumpido) {
            try await CommandBus(writer: w).ejecutar(WritePlan(autor: Self.manu, descripcion: "Dos notas", ops: [
                .appendLine(VaultPath(Self.decisiones), line: "- 2026-10-22 · Una"),
                .appendLine(VaultPath(Self.rumbo), line: "Línea")]))
        }
        let rumboAntes = e.datos(Self.rumbo)
        e.escribir(Self.decisiones, "# Decisiones\n\nCambiado en Obsidian antes de volver a abrir.\n")
        let w2 = try await e.writer()
        let informe = await w2.lastRecovery
        #expect(informe.conflictos.count == 1)
        do {
            #expect(e.datos(Self.rumbo) == rumboAntes, "la recuperación ha aplicado medio plan")
        }
    }

    // MARK: 3 · Deshacer se salta las reglas de autor, lo privado y los enlaces simbólicos

    /// Un asistente no puede escribir lo privado, pero sí «deshacer» el último plan de una
    /// persona aunque toque lo privado (y aunque sea texto humano): `undoLast` no pasa por
    /// `checkAllowed` ni mira quién deshace qué.
    @Test func unAsistenteNoDeshaceLoDeUnaPersonaEnLoPrivado() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        e.escribir(".tls/layout.json", #"{"preset":"humana","privado":["Privado"]}"#)
        let bus = try await e.bus()
        let privada = VaultPath("Privado/Expediente personal.md")
        await esperaErrorAsync(.rutaNoPermitida(privada.raw)) {
            try await bus.ejecutar(.anadirLinea(privada, linea: "Del asistente."), autor: .agente("comercial"))
        }
        #expect(try await bus.ejecutar(.anadirLinea(privada, linea: "Nota de Manu."), autor: Self.manu).hecho)
        let deManu = e.datos(privada.raw)
        do {
            await esperaErrorAsync(.noPermitidoAsistente(privada.raw)) {
                try await bus.deshacer(autor: .agente("comercial"))
            }
            #expect(e.datos(privada.raw) == deManu, "un asistente ha cambiado un fichero privado")
        }
    }

    /// Tras un cambio, la carpeta se lleva a otro sitio (por ejemplo, la carpeta real) y queda un
    /// enlace simbólico con su nombre. «Deshacer» escribe a través del enlace, fuera de la carpeta.
    @Test func deshacerNoEscribeFueraAtravesDeUnEnlace() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        #expect(try await bus.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Línea."), autor: Self.manu).hecho)
        let fuera = Apoyo.tempDir("fuera")
        defer { Apoyo.limpiar(fuera) }
        let destino = fuera.appendingPathComponent("1 · Dirección", isDirectory: true)
        try FileManager.default.moveItem(at: e.url("1 · Dirección"), to: destino)
        try FileManager.default.createSymbolicLink(at: e.url("1 · Dirección"), withDestinationURL: destino)
        let antes = Apoyo.huellaDeArbol(fuera)
        do {
            await esperaErrorAsync(.enlaceSimbolico(Self.rumbo)) { try await bus.deshacer(autor: Self.manu) }
            #expect(Apoyo.huellaDeArbol(fuera) == antes, "deshacer ha escrito fuera de la carpeta")
        }
    }

    // MARK: 4 · Deshacer deja carpetas nuevas

    /// Mover a una carpeta que no existía y deshacer: los ficheros vuelven con los mismos bytes,
    /// pero las carpetas que creó el movimiento se quedan (vacías). El árbol no queda como estaba.
    @Test func deshacerDejaElArbolComoEstaba() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let ficheros = e.huellaSinEscritor()
        let dirs = Self.carpetas(e.root)
        #expect(try await bus.ejecutar(.mover(VaultPath(Self.lucia), a: VaultPath("2 · Ventas/Clientes/2026/Lucía Prueba.md")),
                                       autor: Self.manu).hecho)
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(e.huellaSinEscritor() == ficheros)
        do {
            #expect(Self.carpetas(e.root) == dirs, "sobran: \(Self.carpetas(e.root).subtracting(dirs).sorted())")
        }
    }

    // MARK: 5 · Un asistente sustituye una sección escrita por una persona

    /// PLAN §4.8: asistentes y sistema, si la nota no está como la dejó la app, «solo propiedades y
    /// añadidos». `replaceSection` no lo comprueba: un asistente reescribe una sección humana.
    @Test func unAsistenteNoSustituyeUnaSeccionHumana() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let ruta = "1 · Dirección/Plan.md"
        e.escribir(ruta, "# Plan\n\n## Descripción\n\nTexto que escribió Manu en Obsidian.\n\n## Actividad\n")
        let cuerpo = FrontmatterDocument(text: try #require(e.texto(ruta))).body
        let h = try #require(MarkdownSections.hash(of: "Descripción", in: cuerpo))
        do {
            await esperaErrorAsync(.soloAnadidos(ruta)) {
                try await bus.ejecutar(.sustituirSeccion(VaultPath(ruta), seccion: "Descripción",
                                                         texto: "Resumen del asistente.\n", baseHash: h),
                                       autor: .agente("comercial"))
            }
            #expect(e.texto(ruta)?.contains("Texto que escribió Manu en Obsidian.") == true)
        }
    }

    // MARK: 6 · Renombrar cambia texto dentro de un bloque de código

    /// Un bloque de código con cuatro comillas que enseña otro de tres (lo normal para explicar
    /// Markdown). El escáner cierra el bloque en la primera línea «```» y reescribe el `[[Rumbo]]`
    /// que, para CommonMark y Obsidian, es código.
    @Test func renombrarNoTocaEnlacesDentroDeCodigo() throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let nota = "1 · Dirección/Guía.md"
        e.escribir(nota, "# Guía\n\nEnlace de verdad: [[Rumbo]]\n\n````markdown\nAsí se enlaza:\n```\n[[Rumbo]]\n```\n````\n")
        let previa = try LinkRefactor(root: e.root).renombrar(VaultPath(Self.rumbo), a: "Rumbo 2027",
                                                               opciones: LinkRefactor.Opciones(alias: .nunca))
        let cambios = previa.cambios.first { $0.ruta == VaultPath(nota) }?.enlaces ?? []
        do {
            #expect(cambios.map(\.linea) == [3], "líneas cambiadas: \(cambios.map(\.linea))")
        }
    }

    // MARK: 7 · Rutas con «#» en CSV y propiedades

    /// `Factura #12.pdf`: al mover su carpeta, la celda `documento` y la propiedad `pdf` no se
    /// actualizan (se corta en «#» como si fuera una sección) y la vista previa dice que es seguro.
    @Test func moverCarpetaActualizaRutasConAlmohadilla() throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        e.escribir("4 · Finanzas/Facturas/Factura #12.pdf", "%PDF-1.4\n")
        e.escribir("4 · Finanzas/Registros/documentos.csv", "id,documento\nF-12,Facturas/Factura #12.pdf\n")
        e.escribir("2 · Ventas/Contactos/Cliente.md", "---\npdf: \"4 · Finanzas/Facturas/Factura #12.pdf\"\n---\n# Cliente\n")
        let previa = try LinkRefactor(root: e.root).renombrar(VaultPath("4 · Finanzas/Facturas"), a: "Facturas emitidas")
        #expect(previa.esSeguro)
        do {
            #expect(previa.filasCSV == 1, "la celda del CSV se queda apuntando a la carpeta vieja")
            #expect(previa.cambios.first { $0.ruta == VaultPath("2 · Ventas/Contactos/Cliente.md") }?.enlaces.count == 1)
        }
    }

    // MARK: 8 · Renombrar una carpeta privada la deja de proteger

    /// `privado: ["{finanzas}/Privado"]` (forma de plantilla, como la escribe G3). Renombrar esa
    /// carpeta no actualiza `privado` (se saltan los valores con «{»): deja de ser privada.
    @Test func renombrarUnaCarpetaPrivadaLaSigueProtegiendo() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        e.escribir(".tls/config.yaml", "version: 1\nclase: copia\nprivado:\n  - \"{finanzas}/Privado\"\n")
        e.escribir("4 · Finanzas/Privado/Nóminas.md", "# Nóminas\n")
        #expect(VaultLayout.load(root: e.root).layout.isPrivate(VaultPath("4 · Finanzas/Privado/Nóminas.md")))
        let bus = try await e.bus()
        let previa = try LinkRefactor(root: e.root).renombrar(VaultPath("4 · Finanzas/Privado"), a: "Personal")
        #expect(previa.esSeguro)
        #expect(try await LinkRefactor.aplicar(previa, con: bus).hecho)
        do {
            #expect(VaultLayout.load(root: e.root).layout.isPrivate(VaultPath("4 · Finanzas/Personal/Nóminas.md")),
                    "la carpeta renombrada ya no es privada")
        }
    }

    // MARK: 12 · Hueco entre comprobar la huella y sustituir

    /// `AtomicFiles.replace` compara la huella **antes** de escribir el temporal y llevarlo a disco
    /// (`F_FULLFSYNC`, milisegundos). Un guardado de Obsidian (que no usa `NSFileCoordinator`) que
    /// cae en ese hueco se pierde: la app sustituye el fichero con su versión calculada sobre lo de
    /// antes, sin error ni tarjeta. Aquí, una escritura de fuera a 0–30 ms del guardado de la app.
    @Test func guardarNoPierdeUnGuardadoDeFueraSimultaneo() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let url = e.url(Self.rumbo)
        var perdidas: [Int] = []
        for i in 0..<120 {
            let marca = "FUERA-\(i)"
            let retraso = Double(i % 60) / 2000
            let hilo = Thread {
                Thread.sleep(forTimeInterval: retraso)
                try? Data("# Rumbo\n\n\(marca) guardado en Obsidian.\n".utf8).write(to: url)
            }
            hilo.start()
            let r = try? await bus.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "App \(i)."), autor: Self.manu)
            while !hilo.isFinished { try await Task.sleep(for: .milliseconds(1)) }
            // La escritura de fuera ocurrió seguro: si no está, la app la pisó.
            if r?.hecho == true, e.texto(Self.rumbo)?.contains(marca) == false { perdidas.append(i) }
        }
        do {
            #expect(perdidas.isEmpty, "guardados de fuera perdidos en los intentos \(perdidas)")
        }
    }

    // MARK: 13 · Enlazar menciones rompe URL y etiquetas

    /// «Menciones sin enlazar» propone convertir en enlace el nombre dentro de una URL, de un
    /// autoenlace `<…>` y de una etiqueta `#rumbo`. Enlazarlas rompe la URL y la etiqueta.
    @Test func enlazarMencionesNoTocaURLsNiEtiquetas() throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let nota = "2 · Ventas/Notas.md"
        e.escribir(nota, "Ver https://ejemplo.es/rumbo y <https://ejemplo.es/rumbo>, etiqueta #rumbo.\n")
        let salud = SaludDeEnlaces(snapshot: VaultSnapshot.read(root: e.root))
        let menciones = salud.mencionesSinEnlazar(de: VaultPath(Self.rumbo)).filter { $0.origen.raw == nota }
        do {
            #expect(menciones.isEmpty, "menciones propuestas: \(menciones.map(\.texto))")
        }
    }

    // MARK: 14 · Recuperar da un falso conflicto (y dice que no tocó lo que sí escribió)

    /// Nota de G3 con propiedades ya ilegibles (se le puede añadir texto: `validate` lo permite si
    /// ya lo eran). Si la app muere a mitad y se recupera, el paso se escribe, pero `verify` lo
    /// valida sin los bytes de antes y lo da por malo: tarjeta «No lo he tocado» con el fichero ya
    /// cambiado (criterio F1 4: «no aparecen falsos conflictos»).
    @Test func recuperarNoDaFalsosConflictosConPropiedadesRotas() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let ruta = "1 · Dirección/Vieja.md"
        e.escribir(ruta, "---\nclave: [sin cerrar\n---\n# Vieja\n")
        let w = try await e.writer()
        await w.setFault(.trasTemporal(0))
        await esperaErrorAsync(.interrumpido) {
            try await CommandBus(writer: w).ejecutar(.anadirLinea(VaultPath(ruta), linea: "Añadido."), autor: Self.manu)
        }
        let w2 = try await e.writer()
        let informe = await w2.lastRecovery
        #expect(e.texto(ruta)?.hasSuffix("Añadido.\n") == true)
        do {
            #expect(informe.conflictos.isEmpty && informe.aplicados == 1)
        }
    }

    // MARK: 15 · `.tls/config.yaml` ilegible deja escribir aunque diga `clase: real`

    /// La segunda barrera (lo que dice la propia carpeta) se abre si el YAML tiene un error en otra
    /// línea: `clase(declaradaEn:)` devuelve `nil` y se escribe. El resto del código (lo privado,
    /// `peek`) para o trata la carpeta como real cuando no puede leer sus ajustes.
    @Test func configIlegibleQueDiceRealNoSeEscribe() async throws {
        let e = EntornoEscritura(clase: .copia)
        defer { e.limpiar() }
        e.escribir(".tls/config.yaml", "version: 1\nclase: real\nagentes: [sin cerrar\n")
        do {
            await esperaErrorAsync(.carpetaReal) { try await e.writer() }
        }
    }

    // MARK: 9 · iCloud: se marcan como resueltas versiones que no se guardaron

    final class VersionesICloud: ConflictVersionProvider, @unchecked Sendable {
        let lock = NSLock()
        var versiones: [ConflictVersionInfo] = []
        /// Lo que `markResolved` deja que el sistema descarte.
        var descartadas: [Data] = []
        func unresolvedVersions(of url: URL) -> [ConflictVersionInfo] { lock.withLock { versiones } }
        func markResolved(_ url: URL) throws {
            lock.withLock { descartadas += versiones.compactMap(\.data); versiones = [] }
        }
    }

    /// Llega otra versión en conflicto (otro Mac guarda otra vez) después de crear la tarjeta. Al
    /// resolver, `markResolved` marca **todas** las versiones, también la nueva, que no se copió a
    /// ningún sitio: el sistema puede descartarla.
    @Test func resolverICloudNoDescartaVersionesQueNoSeGuardaron() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let falsas = VersionesICloud()
        falsas.versiones = [ConflictVersionInfo(data: Data("# Rumbo del MacBook\n".utf8), equipo: "MacBook", fecha: nil)]
        let rumbo = VaultPath(Self.rumbo)
        let tarjeta = try #require(try ICloudConflicts.scan([rumbo], root: e.root, registry: bus.writer.conflicts,
                                                            provider: falsas).first)
        let tercera = Data("# Rumbo del iMac (guardado después)\n".utf8)
        falsas.lock.withLock { falsas.versiones.append(ConflictVersionInfo(data: tercera, equipo: "iMac", fecha: nil)) }
        // Volver a mirar no actualiza la tarjeta: sigue con una sola versión.
        _ = try ICloudConflicts.scan([rumbo], root: e.root, registry: bus.writer.conflicts, provider: falsas)
        do {
            _ = try await bus.resolverICloud(tarjeta.id, quedarmeCon: nil, provider: falsas, autor: Self.manu)
        } catch {}
        let guardadas = Set(e.huella().values)
        do {
            for d in falsas.descartadas {
                #expect(guardadas.contains(ContentHash.of(d)), "versión descartada sin copia: \(String(decoding: d, as: UTF8.self))")
            }
        }
    }
}
