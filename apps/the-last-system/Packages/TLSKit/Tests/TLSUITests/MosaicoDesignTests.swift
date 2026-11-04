import AppKit
import CoreText
import Foundation
import SwiftUI
import Testing
@testable import TLSDesign

@Suite("TLSDesign · Mosaico v2")
struct MosaicoDesignTests {
    // MARK: Color (§1, criterio §11.2)

    @Test("Todas las parejas de color de §1 pasan su mínimo con la fórmula de WCAG")
    func parejasWCAG() {
        let parejas = TLSParejas.todas
        #expect(parejas.count > 250)
        for p in parejas {
            #expect(p.relacion >= p.minimo - 0.005, "\(p): \(String(format: "%.2f", p.relacion)) < \(p.minimo)")
        }
    }

    @Test("Los valores del documento de diseño coinciden con los de la app")
    func valoresDocumentados() {
        let documentadas = TLSParejas.todas.filter { $0.documentado != nil }
        #expect(documentadas.count > 100)
        for p in documentadas {
            let d = p.documentado ?? 0
            #expect(abs(p.relacion - d) < 0.05, "\(p): calculado \(String(format: "%.2f", p.relacion)), documento \(d)")
        }
    }

    @Test("La fórmula de WCAG da los valores de referencia")
    func formula() throws {
        let negro = try #require(TLSTokens.RGBA(hex: "#000000"))
        let blanco = try #require(TLSTokens.RGBA(hex: "#FFFFFF"))
        #expect(abs(TLSContraste.relacion(negro, sobre: blanco) - 21) < 0.001)
        #expect(abs(TLSContraste.relacion(blanco, sobre: blanco) - 1) < 0.001)
        // La insignia magenta con número blanco queda justo en 4,5 (§1.5).
        let magenta = try #require(TLSTokens.RGBA(hex: "#E6007E"))
        #expect(TLSContraste.relacion(blanco, sobre: magenta) >= 4.5)
        // Translúcido: blanco al 50 % sobre negro es un gris medio.
        let gris = TLSTokens.RGBA(r: 1, g: 1, b: 1, a: 0.5).sobre(negro)
        #expect(abs(gris.r - 0.5) < 0.001)
    }

    @Test("Ningún color de la paleta está mal escrito (sería magenta puro)")
    func paletaBienEscrita() {
        let error = TLSTokens.RGBA(r: 1, g: 0, b: 1)
        for c in TLSPaleta.todos {
            for v in [c.claro, c.oscuro, c.claroContraste, c.oscuroContraste] {
                #expect(v != error, "\(c.id) tiene un valor mal escrito")
            }
        }
    }

    @Test("Valores clave de §1: azul noche, violeta, magenta y áreas reajustadas")
    func valoresClave() {
        #expect(TLSPaleta.principal.claro.hex == "#1E2A78")
        #expect(TLSPaleta.principal.oscuro.hex == "#7C8CFF")
        #expect(TLSPaleta.violeta.claro.hex == "#7C3AED")
        #expect(TLSPaleta.anillo.claro.hex == "#E6007E")
        #expect(TLSPaleta.chispa.claroContraste.hex == "#C4006B")
        #expect(TLSPaleta.fondo.oscuro.hex == "#000000")
        #expect(TLSArea.direccion.relleno.claro.hex == "#791E74")
        #expect(TLSArea.marca.tinta.oscuro.hex == "#C1C75D")
        // Con «Aumentar contraste», los rellenos de área pasan a sus tintas.
        for a in TLSArea.allCases {
            #expect(a.relleno.claroContraste == a.tinta.claro)
            #expect(a.relleno.oscuroContraste == a.tinta.oscuro)
        }
        #expect(TLSPaleta.textoSecundario.claroContraste.hex == "#3F4563")
        #expect(TLSPaleta.textoSecundario.oscuroContraste.hex == "#BCC1DD")
    }

    @Test("El orden de luminosidad de las áreas se conserva (Dirección la más oscura, Finanzas la más clara)")
    func ordenLuminosidad() {
        let orden: [TLSArea] = [.direccion, .equipo, .entrega, .marca, .ventas, .finanzas]
        for oscuro in [false, true] {
            let l = orden.map { TLSContraste.luminancia($0.relleno.valor(oscuro: oscuro)) }
            #expect(l == l.sorted(), "rellenos en \(oscuro ? "oscuro" : "claro")")
        }
    }

    /// «Aumentar contraste» lo resuelve el sistema con `bestMatch` y los nombres de accesibilidad (§7.8);
    /// `NSAppearance(named:)` no deja crear esas apariencias, así que aquí se prueban claro y oscuro, y
    /// los valores con contraste se prueban con `valor(oscuro:contraste:)`.
    @Test("Los colores dinámicos cambian con la apariencia")
    func dinamicos() throws {
        let c = TLSPaleta.textoSecundario.ns
        func hex(_ nombre: NSAppearance.Name) throws -> String {
            let ap = try #require(NSAppearance(named: nombre))
            var out = ""
            ap.performAsCurrentDrawingAppearance {
                let s = c.usingColorSpace(.sRGB) ?? c
                out = TLSTokens.RGBA(r: Double(s.redComponent), g: Double(s.greenComponent), b: Double(s.blueComponent)).hex
            }
            return out
        }
        #expect(try hex(.aqua) == "#545A7A")
        #expect(try hex(.darkAqua) == "#9AA1C4")
    }

    // MARK: Letra (§1.9)

    @Test("Las tres familias van en el paquete y se registran")
    func fuentesRegistradas() {
        TLSFuentes.registrar()
        for familia in [TLSFamilia.spaceGrotesk, .dmSans, .jetBrainsMono] {
            #expect(TLSFuentes.disponible(familia), "falta \(familia.nombreFamilia)")
            let f = TLSFuentes.ctFont(familia, peso: 400, tamano: 13)
            #expect(CTFontCopyFamilyName(f) as String == familia.nombreFamilia)
        }
        let licencias = ["SpaceGrotesk/OFL.txt", "DMSans/OFL.txt", "JetBrainsMono/OFL.txt"]
        for l in licencias {
            let url = TLSFuentes.carpeta?.appendingPathComponent(l)
            #expect(url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false, "falta \(l)")
        }
    }

    @Test("Cifras tabulares: Space Grotesk las trae; DM Sans no, y cifraFila usa las del sistema")
    func cifrasTabulares() {
        #expect(TLSFuentes.tieneCifrasTabulares(.spaceGrotesk))
        #expect(!TLSFuentes.tieneCifrasTabulares(.dmSans), "si DM Sans trae ya tnum, cifraFila puede volver a DM Sans")
        #expect(TLSTipo.cifraFila.familia == .sistema && TLSTipo.cifraFila.tabulares)
        for estilo in [TLSTipo.cifraHoy, TLSTipo.cifraGrande, TLSTipo.cifraMedia, TLSTipo.cifraFila] {
            let f = estilo.nsFont()
            let unos = ("1111" as NSString).size(withAttributes: [.font: f]).width
            let ceros = ("0000" as NSString).size(withAttributes: [.font: f]).width
            #expect(abs(unos - ceros) < 0.5, "\(estilo.familia) \(estilo.tamano): 1111=\(unos) 0000=\(ceros)")
        }
    }

    @Test("El peso del eje variable se aplica")
    func pesoVariable() {
        let f = TLSTipo.tituloPantalla.ctFont()
        let variacion = CTFontCopyVariation(f) as? [NSNumber: NSNumber] ?? [:]
        #expect(variacion[NSNumber(value: 0x7767_6874)]?.doubleValue == 700)
        #expect(TLSTipo.rotulo.mayusculas && abs(TLSTipo.rotulo.espaciado - 0.04) < 0.0001)
        #expect(TLSTipo.lectura.tamano == 15 && TLSTipo.lectura.interlinea == 23)
        #expect(TLSTipo.lectura.espacioEntreLineas() > 0)
    }

    // MARK: Componentes

    @Test("Mosaicos: primer hueco libre en 4 columnas, y bajan a 2 y a 1 con poco ancho")
    func mosaicoLayout() {
        let celdas = MosaicoLayout.colocar([.grande, .pequeno, .pequeno, .mediano, .ancho, .pequeno], columnas: 4)
        #expect(celdas[0] == .init(columna: 0, fila: 0, ancho: 2, alto: 2))
        #expect(celdas[1] == .init(columna: 2, fila: 0, ancho: 1, alto: 1))
        #expect(celdas[2] == .init(columna: 3, fila: 0, ancho: 1, alto: 1))
        #expect(celdas[3] == .init(columna: 2, fila: 1, ancho: 2, alto: 1))
        #expect(celdas[4] == .init(columna: 0, fila: 2, ancho: 4, alto: 1))
        #expect(celdas[5] == .init(columna: 0, fila: 3, ancho: 1, alto: 1))
        let dos = MosaicoLayout.colocar([.ancho, .grande], columnas: 2)
        #expect(dos == [.init(columna: 0, fila: 0, ancho: 2, alto: 1), .init(columna: 0, fila: 1, ancho: 2, alto: 2)])
        let uno = MosaicoLayout.colocar([.grande, .ancho], columnas: 1)
        #expect(uno.allSatisfy { $0.ancho == 1 && $0.alto == 1 })
        let l = MosaicoLayout()
        #expect(l.columnasEfectivas(ancho: 1000) == 4)
        #expect(l.columnasEfectivas(ancho: 500) == 2)
        #expect(l.columnasEfectivas(ancho: 200) == 1)
    }

    @Test("Monograma, atajos para VoiceOver y estados con icono y palabra")
    func pequenos() {
        #expect(Monograma.iniciales(de: "Asesoría Ribera") == "AR")
        #expect(Monograma.iniciales(de: "Clínica") == "CL")
        #expect(Tecla.leer("⇧⌘B") == "mayúsculas comando B")
        for e in TLSEstado.allCases {
            #expect(!e.palabra.isEmpty && NSImage(systemSymbolName: e.simbolo, accessibilityDescription: nil) != nil)
        }
        for a in TLSArea.allCases {
            #expect(NSImage(systemSymbolName: a.simbolo, accessibilityDescription: nil) != nil, "\(a.simbolo)")
        }
    }

    @Test("Medidas de §1.10: objetivo mínimo de 28 pt y botón principal de 44")
    func medidas() {
        #expect(TLSAltura.objetivoMinimo == 28)
        #expect(TLSAltura.botonPrincipal == 44)
        #expect(TLSRadio.mosaico == 22 && TLSRadio.fila == 10 && TLSRadio.iconoArea24 == 7)
        #expect(TLSEspacio.margenPantalla(ancho: 1200) == 24 && TLSEspacio.margenPantalla(ancho: 800) == 16)
    }

    // MARK: Criterio §11.3

    /// El magenta (`chispa`, `anillo`) solo se usa para el anillo de foco, la insignia, el punto de novedad y
    /// el texto «Nuevo»: nunca como relleno de botones, selección ni nada grande.
    @Test("El magenta solo está en el foco y los avisos")
    func magentaSoloFocoYAvisos() throws {
        let fuentes = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources").standardizedFileURL
        let permitidos: Set<String> = [
            "TLSDesign/Paleta.swift", "TLSDesign/Tokens.swift", "TLSDesign/Contraste.swift",
            "TLSDesign/Componentes/Foco.swift", "TLSDesign/Componentes/Pastillas.swift",
        ]
        var usos: [String] = []
        for carpeta in ["TLSDesign", "TLSUI", "TLSEditor", "TLSVisores"] {
            let dir = fuentes.appendingPathComponent(carpeta)
            let ficheros = FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []
            for f in ficheros where f.hasSuffix(".swift") {
                let texto = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                let clave = "\(carpeta)/\(f)"
                for patron in ["TLSPaleta.chispa", "TLSPaleta.anillo", "TLSTokens.marca", ".chispaTexto", "#E6007E"]
                    where texto.contains(patron) && !permitidos.contains(clave) {
                    usos.append("\(clave): \(patron)")
                }
            }
        }
        #expect(usos.isEmpty, "Magenta fuera de foco y avisos: \(usos)")
    }
}

