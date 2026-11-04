import AppKit
import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

@Suite("Interfaz · tipos, iconos y textos")
@MainActor
struct PresentacionTests {
    private func existe(_ simbolo: String) -> Bool {
        NSImage(systemSymbolName: simbolo, accessibilityDescription: nil) != nil
    }

    @Test("Cada tipo de ficha tiene nombre y un icono que existe en macOS 15")
    func tipos() {
        for k in NoteKind.allCases {
            #expect(!k.etiqueta.isEmpty, "\(k) sin nombre")
            #expect(existe(k.systemImage), "\(k): \(k.systemImage) no existe")
        }
        #expect(Set(NoteKind.allCases.map(\.etiqueta)).count == NoteKind.allCases.count, "dos tipos con el mismo nombre")
        #expect(NoteKind.invoice.etiqueta == "Factura" && NoteKind.invoice.abreComoFicha)
        #expect(!NoteKind.note.abreComoFicha && !NoteKind.csv.abreComoFicha)
    }

    @Test("Los iconos de bases, áreas y pantallas existen")
    func iconos() {
        for b in BaseConocida.deSerie { #expect(existe(b.icono), "\(b.id): \(b.icono)") }
        for a in AreaCode.allCases { #expect(existe(a.systemImage), "\(a): \(a.systemImage)") }
        let destinos: [Destino] = [.hoy, .decisiones, .tareas, .revisar, .area(.ventas), .todasLasBases, .base("x"),
                                   .ficha(VaultPath("a.md")), .nota(VaultPath("a.md")), .fichero(VaultPath("a.pdf")),
                                   .carpeta(nil), .busqueda("x"), .asistentes, .ajustes]
        for d in destinos { #expect(existe(d.simbolo), "\(d): \(d.simbolo)") }
    }

    @Test("Las áreas de TLSCore van a su área de Mosaico v2 con el mismo número y nombre")
    func areas() {
        for a in AreaCode.allCases {
            #expect(a.tlsArea.numero == a.numero && a.tlsArea.nombre == a.nombre)
            #expect(a.colorHex == a.tlsArea.relleno.claro.hex)
        }
    }

    @Test("Textos nuevos sin jerga prohibida (§6.9)")
    func glosario() {
        let prohibidas = ["frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "vault", "hash"]
        var textos = NoteKind.allCases.map(\.etiqueta) + BaseConocida.deSerie.map(\.nombre)
        textos += [MotivoSoloLectura.carpetaReal.texto, MotivoSoloLectura.elegido.texto]
        textos += ModoVistaPrevia.allCases.map(\.titulo)
        let m = BarraLateralModelo(archivo: nil)
        textos += m.filas.map { m.nombre($0.elemento) }
        for t in textos {
            let palabras = Set(t.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            for p in prohibidas { #expect(!palabras.contains(p), "«\(t)» contiene «\(p)»") }
        }
    }

    @Test("Saludo y fecha de Hoy en español")
    func hoy() throws {
        let cal = Calendar.tlsGregoriano
        let manana = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9, minute: 5)))
        let tarde = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 16)))
        let noche = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 23)))
        #expect(HoyPantalla.saludo(manana, calendario: cal) == "Buenos días")
        #expect(HoyPantalla.saludo(tarde, calendario: cal) == "Buenas tardes")
        #expect(HoyPantalla.saludo(noche, calendario: cal) == "Buenas noches")
        #expect(HoyPantalla.fechaLarga(manana) == "Jueves, 22 de octubre")
    }

    @Test("Persona por defecto y escala de texto sin tocar las preferencias del Mac")
    func ajustes() {
        let model = AppModel(registry: VaultRegistry(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-ajustes-\(UUID().uuidString)")))
        #expect(model.persona == "Manu")
        #expect(model.escalaTexto == 1)
        #expect(model.modoVistaPrevia == .alPasar)
        model.persona = "  "
        #expect(model.personaEfectiva == "Manu")
    }
}
