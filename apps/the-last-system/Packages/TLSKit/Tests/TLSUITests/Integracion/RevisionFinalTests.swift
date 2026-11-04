import AppKit
import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSEditor
@testable import TLSUI

/// Corrector final de F1 (23/10): pruebas de regresión de los hallazgos de la revisión de diseño y accesibilidad
/// (los de datos están en `RevisionF1InterfazTests`). Todo sobre una copia temporal de Ribera.
@Suite("Revisión F1 · correcciones de diseño", .serialized)
@MainActor
struct RevisionFinalTests {
    let pruebas = SesionEscrituraTests()
    let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")

    func abrir(_ preparar: (URL) throws -> Void = { _ in }) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        try preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        #expect(sesion.isReady)
        return (e, sesion)
    }

    // MARK: P1 · «Ahora» con el destacado vacío

    @Test("P1: con el destacado vacío, «Ahora» no se borra entera (Jorge con el cobro confirmado)")
    func ahoraConDestacadoVacio() async throws {
        let (e, sesion) = try await abrir(CapturasFichasTests.prepararProyecto)
        defer { sesion.close(); e.limpiar() }
        let m = FichaModelo(ruta: jorge, sesion: sesion)
        await m.cargar()
        let r = try #require(m.resumen)
        // La tarea que espera tu OK (la de la pestaña Tareas, «1 · Por revisar») está en «Ahora».
        #expect(r.ahora.contains { $0.clase == .decision && $0.texto.contains("espera tu OK") })
        // La regla: un destacado vacío no quita nada (`hasPrefix("")` es siempre verdad).
        let linea = LineaAhora(clase: .decision, texto: "T-0042 · Revisar la petición: espera tu OK", destino: nil, boton: nil)
        let vacio = DatoProtagonista(rotulo: "Siguiente paso", valor: "", contexto: nil, esCifra: false)
        #expect(ResumenDeFicha.quitandoLoDelDestacado([linea], protagonista: vacio) == [linea])
        let igual = DatoProtagonista(rotulo: "Siguiente paso", valor: "T-0042", contexto: nil, esCifra: false)
        #expect(ResumenDeFicha.quitandoLoDelDestacado([linea], protagonista: igual).isEmpty)
    }

    // MARK: P1 · Botón desactivado sobre la cabecera

    @Test("P1: el texto de un botón desactivado sobre la cabecera y sobre el destacado pasa 4,5:1")
    func botonDesactivadoSobreColor() {
        let parejas = TLSParejas.todas.filter { $0.nombre.hasPrefix("desactivadoSobreColor") }
        #expect(parejas.count == 4)
        for p in parejas { #expect(p.relacion >= TLSContraste.texto, "\(p)") }
        // Antes: el gris de desactivado sobre azul noche daba 1,9:1.
        let antes = TLSContraste.relacion(TLSPaleta.desactivadoTexto.valor(oscuro: false), sobre: TLSPaleta.cabecera.valor(oscuro: false))
        #expect(antes < 2)
    }

    // MARK: P2 · Etapas del embudo y estados

    @Test("P2: las etapas abiertas del embudo no llevan colores de estado; «Emitida» es igual en la base y en la ficha")
    func etapasSinColorDeEstado() throws {
        let opo = try #require(CatalogoBases.coleccion("oportunidades"))
        #expect(EstadoVisible.etapa("Prospecto", coleccion: opo) == 0)
        #expect(EstadoVisible.etapa("Propuesta", coleccion: opo) == 2)
        #expect(EstadoVisible.etapa("Aceptada", coleccion: opo) == 3)
        #expect(EstadoVisible.etapa("Ganada", coleccion: opo) == nil)
        #expect(EstadoVisible.etapa("Propuesta", coleccion: CatalogoBases.coleccion("facturas")) == nil)
        #expect(EstadoVisible.de("Emitida") == .sinDato)
        #expect(FormatoFicha.tlsEstado(.invoice, "Emitida", hoy: LocalDate(year: 2026, month: 10, day: 19)!) == .sinDato)
        #expect(EstadoVisible.de("Propuesta") == .sinDato)
        #expect(EstadoVisible.de("Borrador") == .atencion)
    }

    // MARK: P2 · Un solo «hoy»

    @Test("P2: Hoy, las bases y las fichas usan el mismo día (el de la carpeta)")
    func unSoloHoy() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let dia = LocalDate(year: 2026, month: 10, day: 19)!  // `hoy:` de `.tls/config.yaml` de Ribera
        #expect(sesion.hoy == dia)
        #expect(HoyPantalla.fechaLarga(sesion.hoy) == "Lunes, 19 de octubre")
        let base = try #require(await AlmacenBases.de(sesion).cargar("tareas"))
        #expect(base.hoy == sesion.hoy)
        let m = FichaModelo(ruta: jorge, sesion: sesion)
        await m.cargar()
        #expect(m.hoy == sesion.hoy)
    }

    // MARK: P2 · «Aumentar contraste»

    @Test("P2: con «Aumentar contraste» los colores cambian también en SwiftUI (apariencia o ajuste del Mac)")
    func aumentarContraste() {
        defer { TLSApariencia.contrasteForzado = nil }
        let aqua = NSAppearance(named: .aqua)!
        TLSApariencia.contrasteForzado = true
        #expect(TLSApariencia.modo(de: aqua).contraste)
        var resuelto = NSColor.clear
        aqua.performAsCurrentDrawingAppearance {
            resuelto = TLSPaleta.textoSecundario.ns.usingColorSpace(.sRGB) ?? .clear
        }
        let esperado = TLSPaleta.textoSecundario.valor(oscuro: false, contraste: true)
        #expect(abs(resuelto.redComponent - esperado.r) < 0.01)
        #expect(abs(resuelto.blueComponent - esperado.b) < 0.01)
        TLSApariencia.contrasteForzado = false
        #expect(!TLSApariencia.modo(de: NSAppearance(named: .accessibilityHighContrastAqua)!).contraste)
    }

    // MARK: P3 y probables

    @Test("P3: la línea «>» de la ficha no repite (ni contradice) el estado")
    func lineaSinEstado() {
        #expect(FormatoFicha.sinEstado("Talleres Martín e Hijos SL · Interesado", tipo: .contact) == "Talleres Martín e Hijos SL")
        #expect(FormatoFicha.sinEstado("Interesado", tipo: .contact) == nil)
        #expect(FormatoFicha.sinEstado("Cliente desde 2024", tipo: .contact) == "Cliente desde 2024")
    }

    @Test("Probable: encender un módulo que estaba en «apagados: […]» lo enciende")
    func moduloEncendidoGanaALaLista() {
        let texto = AjustesBases.textoModulos("apagados: [objetivos, crm]\n", modulo: "objetivos", encendido: true)
        let m = AjustesBases.modulos(yaml: texto)
        #expect(m["objetivos"] == true)
        #expect(m["crm"] == false)
    }

    @Test("Probable: la carpeta Archivo no se mueve, y mover algo fuera de lo privado se avisa")
    func archivoYPrivado() async throws {
        let privada = VaultPath("4 · Finanzas/Trámites/Expediente privado/documento.md")
        let (e, sesion) = try await abrir { carpeta in
            let config = carpeta.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: config, encoding: .utf8)
                .replacingOccurrences(of: "privado: []", with: "privado: [\"4 · Finanzas/Trámites\"]")
            try Data(t.utf8).write(to: config)
            let url = privada.url(in: carpeta)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# Parte\n".utf8).write(to: url)
        }
        defer { sesion.close(); e.limpiar() }
        let modelo = CarpetaModelo(carpeta: nil, sesion: sesion)
        #expect(modelo.esLaCarpetaArchivo(VaultPath("Archivo")))
        #expect(!modelo.esLaCarpetaArchivo(VaultPath("Archivo/2 · Ventas")))
        #expect(modelo.avisoSalePrivado([privada], a: VaultPath("2 · Ventas")) != nil)
        #expect(modelo.avisoSalePrivado([privada], a: VaultPath("4 · Finanzas/Trámites")) == nil)
    }
}
