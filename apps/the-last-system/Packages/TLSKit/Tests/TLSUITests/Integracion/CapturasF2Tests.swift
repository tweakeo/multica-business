import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// `make capturas` (F2): las pantallas de «Tareas y áreas» con Asesoría Ribera, en claro y en oscuro, dentro de la ventana
/// de la app (barra lateral, ‹ ›, migas y «Buscar o hacer…»), pintadas fuera de pantalla como las de F1
/// (`CapturasF1Tests`). Hoy, Decisiones (y una decisión 1-3-1), Tareas (lista, tablero y ficha), el Resumen y la Operación
/// de cada área, Control, el Banco, la vista del cliente del portal (criterio F2-8) y la Galería de una base con la
/// miniatura de sus PDF (R1). Deja los PNG y `index.html` (F1 y F2) en `TLS_CAPTURAS`.
@Suite("Capturas de F2 (make capturas)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasF2Tests {
    typealias Captura = CapturasF1Tests.Captura

    static let lista: [Captura] = [
        Captura(nombre: "20-hoy", titulo: "Hoy", detalle: "Un solo foco violeta, Pide tu decisión con su insignia, Alertas (hay algo en rojo), tu inicio y la línea de Mika"),
        Captura(nombre: "21-decisiones", titulo: "Decisiones", detalle: "La bandeja: propuestas y preguntas, con su prioridad y hasta tres opciones"),
        Captura(nombre: "22-decision-1-3-1", titulo: "Una decisión 1-3-1", detalle: "Problema, opciones con la recomendada, evidencias y qué pasa si se pospone"),
        Captura(nombre: "23-tareas-lista", titulo: "Tareas · Lista", detalle: "Para hoy, vencidas y en revisión; filtros y grupos"),
        Captura(nombre: "24-tareas-tablero", titulo: "Tareas · Tablero", detalle: "Sin programar → Hecha; arrastrar o ⌘← ⌘→ cambia solo el estado"),
        Captura(nombre: "25-tarea-ficha", titulo: "Ficha de una tarea", detalle: "Cabecera, destacado con lo siguiente, descripción, Actividad y propiedades"),
        Captura(nombre: "26-direccion-resumen", titulo: "1 · Dirección · Resumen", detalle: "Cabecera del área, número clave y sus módulos"),
        Captura(nombre: "27-direccion-operacion", titulo: "1 · Dirección · Operación", detalle: "Cronograma de proyectos internos por objetivo (DIR-03 en atención)"),
        Captura(nombre: "28-ventas-resumen", titulo: "2 · Ventas · Resumen", detalle: "Número clave y módulos de Ventas"),
        Captura(nombre: "29-ventas-operacion", titulo: "2 · Ventas · Operación", detalle: "CRM en tablero con número, euros, conversión y «quieta N d»"),
        Captura(nombre: "30-entrega-resumen", titulo: "3 · Entrega · Resumen", detalle: "Número clave y módulos de Entrega"),
        Captura(nombre: "31-entrega-operacion", titulo: "3 · Entrega · Operación", detalle: "Expedientes de cliente"),
        Captura(nombre: "32-finanzas-resumen", titulo: "4 · Finanzas · Resumen", detalle: "Caja con su gráfica 1S·1M·3M·1A·Todo y meses de caja"),
        Captura(nombre: "33-finanzas-operacion", titulo: "4 · Finanzas · Operación", detalle: "Caja, Cobros, Banco y Trimestre"),
        Captura(nombre: "34-marca-resumen", titulo: "5 · Marca · Resumen", detalle: "Número clave y módulos de Marca"),
        Captura(nombre: "35-marca-operacion", titulo: "5 · Marca · Operación", detalle: "Calendario editorial"),
        Captura(nombre: "36-equipo-resumen", titulo: "6 · Equipo · Resumen", detalle: "Número clave y módulos de Equipo"),
        Captura(nombre: "37-equipo-operacion", titulo: "6 · Equipo · Operación", detalle: "Roles, asistentes y rutinas"),
        Captura(nombre: "38-finanzas-control", titulo: "4 · Finanzas · Control", detalle: "Las filas de Metas.md: solo se cambian Meta y Alerta"),
        Captura(nombre: "39-banco", titulo: "Banco", detalle: "Saldo, movimientos sin conciliar y propuestas: confirmar es siempre tu clic"),
        Captura(nombre: "40-portal-cliente", titulo: "Portal · vista del cliente (F2-8)", detalle: "Sin notas internas, responsable, resolución, correos ni kit"),
        Captura(nombre: "41-galeria-pdf", titulo: "Gastos · Galería", detalle: "Miniatura de la primera página de cada PDF (R1), de la caché de la empresa"),
    ]

    @Test("Hoy, Decisiones, Tareas, cada área (Resumen y Operación), Control, Banco, portal del cliente y Galería con PDF")
    func pantallasF2() async throws {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let f1 = CapturasF1Tests()
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        // En la copia: proyectos internos, el expediente de Talleres con su portal e incidencias, lo privado con nombres
        // neutros, y una decisión 1-3-1 (como en la maqueta M2-Hoy).
        try ApoyoAreasA.preparar(e.carpeta)
        let (rutaDecision, textoDecision) = HoyApoyo.decision131(5, titulo: "¿Cómo retomamos a Jorge Martín?", area: "2 · Ventas")
        try ApoyoAreasA.escribir(textoDecision, rutaDecision, en: e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        await AlmacenHoy.de(sesion).actualizar(forzar: true)

        func nav(_ raiz: Destino, _ niveles: [Destino] = [], extra: [String: String] = [:], de clave: Destino? = nil) -> Navegacion {
            let n = Navegacion(raiz: raiz)
            for d in niveles { n.entrar(d) }
            if let clave { n.actualizarRecuerdo(de: clave) { r in for (k, v) in extra { r.extra[k] = v } } }
            return n
        }
        let gastos = try #require(CatalogoBases.coleccion("gastos"))
        let galeria = ConfigVista(vista: .galeria, columnas: gastos.columnasDeSerie, tamanoGaleria: .m)
        let jsonGaleria = String(decoding: try JSONEncoder().encode(galeria), as: UTF8.self)
        let operacion = PestanaArea.operacion.rawValue

        for oscuro in [false, true] {
            func foto(_ nombre: String, _ n: Navegacion, alto: CGFloat = 1000) async throws {
                n.inspector = false
                sesion.navegacionActiva = n
                try await f1.capturar(VentanaParaCaptura(sesion: sesion, nav: n, model: e.model), ancho: 1440, alto: alto,
                                      oscuro: oscuro, nombre: nombre, editor: false)
            }
            try await foto("20-hoy", nav(.hoy), alto: 2000)
            try await foto("21-decisiones", nav(.decisiones), alto: 1300)
            try await foto("22-decision-1-3-1", nav(.decisiones, [.decision(de: VaultPath(rutaDecision))]), alto: 1300)
            try await foto("23-tareas-lista", nav(.tareas), alto: 1100)
            try await foto("24-tareas-tablero", nav(.tareas, extra: ["tareas.vista": VistaTareas.tablero.rawValue], de: .tareas), alto: 1100)
            try await foto("25-tarea-ficha", nav(.tareas, [.tarea(VaultPath(HoyApoyo.t1))]), alto: 1200)
            let areas: [(String, AreaCode, [String: String])] = [
                ("direccion", .direccion, ["direccion.vista": "Cronograma"]),
                ("ventas", .ventas, ["ventas.vista": "CRM"]),
                ("entrega", .entrega, ["entrega.vista": "Expedientes"]),
                ("finanzas", .finanzas, [FinanzasOperacion.claveSeccion: "Caja"]),
                ("marca", .marca, [MarcaOperacion.claveSeccion: "Calendario"]),
                ("equipo", .equipo, [EquipoOperacion.claveSeccion: "Roles"]),
            ]
            for (i, (nombre, area, extra)) in areas.enumerated() {
                let n = 26 + i * 2
                try await foto(String(format: "%02d-%@-resumen", n, nombre), nav(.area(area)), alto: 1500)
                try await foto(String(format: "%02d-%@-operacion", n + 1, nombre),
                               nav(.area(area, pestana: operacion), extra: extra, de: .area(area)), alto: 1500)
            }
            try await foto("38-finanzas-control", nav(.area(.finanzas, pestana: PestanaArea.control.rawValue)), alto: 1300)
            try await foto("39-banco", nav(.area(.finanzas), [.banco(nil)]), alto: 1300)
            try await foto("40-portal-cliente",
                           nav(.area(.entrega, pestana: operacion),
                               extra: ["entrega.expediente": ApoyoAreasA.talleres.raw, "entrega.pestana": "Portal", "entrega.portal": "cliente"],
                               de: .area(.entrega)), alto: 1400)
            try await foto("41-galeria-pdf", nav(.todasLasBases, [.base("gastos")], extra: ["config": jsonGaleria], de: .base("gastos")),
                           alto: 1100)
        }
        try escribirIndice()
        for c in Self.lista {
            for modo in ["claro", "oscuro"] {
                #expect(FileManager.default.fileExists(atPath: f1.destino.appendingPathComponent("\(c.nombre)-\(modo).png").path))
            }
        }
    }

    /// El índice de `make capturas`: las de F1 (si están) y las de F2.
    func escribirIndice() throws {
        let f1 = CapturasF1Tests()
        let deF1 = CapturasF1Tests.lista.filter {
            FileManager.default.fileExists(atPath: f1.destino.appendingPathComponent("\($0.nombre)-claro.png").path)
        }
        try f1.escribirIndice(deF1 + Self.lista, titulo: "The Last System · capturas de F1 y F2")
    }
}
