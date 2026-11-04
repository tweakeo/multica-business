import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Escritor conectado (F1-CONTRATOS «Pendiente para la interfaz»): copia y ejemplo escriben por
/// `CommandBus` con Deshacer; la carpeta real y la copia en solo lectura, nunca.
@Suite("Sesión · escritura conectada", .serialized)
@MainActor
struct SesionEscrituraTests {
    struct Entorno {
        let base: URL
        let carpeta: URL
        let estado: URL
        let model: AppModel
        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    static var ribera: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    /// Copia el ejemplo a una carpeta temporal propia y lo registra con la clase y el modo pedidos.
    func entorno(clase: VaultClass, escritura: WriteAccess) throws -> (Entorno, VaultEntry) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-sesion-\(UUID().uuidString)", isDirectory: true)
        let carpeta = base.appendingPathComponent("Ribera", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.ribera, to: carpeta)
        if clase != .demo {
            // La clase que dice la propia carpeta manda: se ajusta para que coincida con la entrada.
            let config = carpeta.appendingPathComponent(".tls/config.yaml")
            let texto = try String(contentsOf: config, encoding: .utf8).replacingOccurrences(of: "clase: demo", with: "clase: \(clase.rawValue)")
            try Data(texto.utf8).write(to: config)
        }
        let model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("asup", isDirectory: true)))
        let entry = VaultEntry(nombre: "Asesoría Ribera", ruta: carpeta.path, bookmark: nil, clase: clase, escritura: escritura)
        try model.register(entry)
        return (Entorno(base: base, carpeta: carpeta, estado: base.appendingPathComponent("estado", isDirectory: true), model: model), entry)
    }

    func esperar(_ condicion: @MainActor () -> Bool, segundos: Double = 10) async {
        let fin = Date().addingTimeInterval(segundos)
        while !condicion(), Date() < fin { try? await Task.sleep(for: .milliseconds(50)) }
    }

    let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")

    @Test("Ejemplo: escribe por CommandBus, cambia una sola línea y ⌘Z deja los mismos bytes")
    func escribeYDeshace() async throws {
        let (e, entry) = try entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        #expect(sesion.isReady)
        #expect(sesion.modoEscritura == .escribe)
        #expect(sesion.puedeEscribir)

        let url = jorge.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        let r = try await sesion.escribir(.cambiarPropiedades(jorge, poner: [Property(key: "estado", value: .text("Activo"))], quitar: []),
                                          aviso: "Jorge pasa a Activo", deshacer: um)
        um.endUndoGrouping()
        #expect(r.hecho)
        let despues = try String(contentsOf: url, encoding: .utf8)
        let lineasAntes = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n")
        let lineasDespues = despues.components(separatedBy: "\n")
        #expect(lineasAntes.count == lineasDespues.count)
        #expect(zip(lineasAntes, lineasDespues).filter { $0 != $1 }.count == 1)
        #expect(despues.contains("estado: Activo"))
        #expect(sesion.aviso?.texto == "Jorge pasa a Activo")
        #expect(sesion.aviso?.accion != nil)

        // El índice se entera sin esperar a la vigilancia.
        await esperar { sesion.revision > 0 }
        #expect(sesion.revision > 0)

        #expect(um.canUndo)
        um.undo()
        await esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("«Deshacer» de un plan que ya no es el último no deshace otro distinto")
    func deshacerSoloElUltimo() async throws {
        let (e, entry) = try entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let primero = try await sesion.escribir(.cambiarPropiedades(jorge, poner: [Property(key: "canal", value: .text("correo"))], quitar: []))
        let segundo = try await sesion.escribir(.cambiarPropiedades(jorge, poner: [Property(key: "canal", value: .text("visita"))], quitar: []))
        await sesion.deshacer(plan: primero.planID)
        #expect(try String(contentsOf: jorge.url(in: e.carpeta), encoding: .utf8).contains("canal: visita"))
        #expect(sesion.aviso?.estado == .atencion)
        await sesion.deshacer(plan: segundo.planID)
        #expect(try String(contentsOf: jorge.url(in: e.carpeta), encoding: .utf8).contains("canal: correo"))
    }

    @Test("Copia en solo lectura: no escribe; al permitir cambios, escribe; y vuelta a solo lectura")
    func soloLecturaYPermitir() async throws {
        let (e, entry) = try entorno(clase: .copia, escritura: .bloqueada)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        #expect(sesion.modoEscritura == .soloLectura(.elegido))
        await #expect(throws: WriteError.soloLectura) {
            try await sesion.escribir(.anadirLinea(VaultPath("1 · Dirección/Decisiones.md"), linea: "- prueba"))
        }
        #expect(!FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent(".tls/escritor.json").path))

        await sesion.permitirCambios(using: e.model)
        #expect(sesion.modoEscritura == .escribe)
        #expect(e.model.entry(id: entry.id)?.escritura == .permitida)
        try await sesion.escribir(.cambiarPropiedades(jorge, poner: [Property(key: "canal", value: .text("correo"))], quitar: []))

        await sesion.pasarASoloLectura(using: e.model)
        #expect(sesion.modoEscritura == .soloLectura(.elegido))
        #expect(e.model.entry(id: entry.id)?.escritura == .bloqueada)
        await #expect(throws: WriteError.soloLectura) {
            try await sesion.escribir(.cambiarPropiedades(jorge, poner: [Property(key: "canal", value: .text("x"))], quitar: []))
        }
    }

    @Test("Carpeta real: solo lectura siempre; no se crea nada dentro")
    func carpetaReal() async throws {
        let (e, entry) = try entorno(clase: .real, escritura: .bloqueada)
        defer { e.limpiar() }
        let antes = try Self.arbol(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        #expect(sesion.modoEscritura == .soloLectura(.carpetaReal))
        await #expect(throws: WriteError.carpetaReal) {
            try await sesion.escribir(.anadirLinea(VaultPath("1 · Dirección/Decisiones.md"), linea: "- prueba"))
        }
        await sesion.permitirCambios(using: e.model)
        #expect(sesion.modoEscritura == .soloLectura(.carpetaReal))
        // La barra lateral se guarda en el estado, fuera de la carpeta.
        sesion.barraLateral.ocultar(.decisiones)
        #expect(FileManager.default.fileExists(atPath: e.estado.appendingPathComponent("barra-lateral.json").path))
        sesion.close()
        #expect(try Self.arbol(e.carpeta) == antes)
    }

    @Test("Duplicados: salen como tarjeta en Revisar y se apartan al Archivo sin borrar nada")
    func duplicados() async throws {
        let (e, entry) = try entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let repetida = VaultPath("2 · Ventas/Contactos/jorge-martin 2.md")
        try FileManager.default.copyItem(at: jorge.url(in: e.carpeta), to: repetida.url(in: e.carpeta))
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        await esperar { sesion.tarjetas.contains { $0.tipo == .duplicado } }
        let tarjeta = try #require(sesion.tarjetas.first { $0.tipo == .duplicado })
        #expect(sesion.hayQueRevisar)
        #expect(tarjeta.otraRuta == repetida)
        await sesion.descartarDuplicado(tarjeta)
        #expect(!FileManager.default.fileExists(atPath: repetida.url(in: e.carpeta).path))
        #expect(FileManager.default.fileExists(atPath: jorge.url(in: e.carpeta).path))
        let archivo = e.carpeta.appendingPathComponent("Archivo")
        let apartadas = (FileManager.default.enumerator(atPath: archivo.path)?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix("jorge-martin 2.md") }
        #expect(apartadas.count == 1)
        #expect(!sesion.tarjetas.contains { $0.id == tarjeta.id })
    }

    @Test("Lectura para las pantallas: nombres, migas, privado fuera de ⌘K y recientes")
    func lectura() async throws {
        let (e, entry) = try entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        #expect(sesion.titulo(de: jorge) == "Jorge Martín")
        #expect(sesion.destino(para: jorge) == .ficha(jorge))
        #expect(sesion.destino(para: VaultPath("2 · Ventas")) == .carpeta(VaultPath("2 · Ventas")))
        let nav = Navegacion(raiz: .area(.ventas))
        nav.entrar(.base("contactos"))
        nav.entrar(.ficha(jorge))
        let migas = sesion.migas(de: nav)
        #expect(migas.map(\.nombre) == ["2 · Ventas", "Contactos", "Jorge Martín"])
        #expect(migas.first?.area == .ventas)
        #expect(sesion.enlaceParaCopiar(.ficha(jorge)) == "[[2 · Ventas/Contactos/jorge-martin|Jorge Martín]]")
        let lector = LectorNota(ruta: jorge, sesion: sesion)
        await lector.cargar()
        #expect(lector.nota?.summary?.kind == .contact)
        sesion.registrarVisita(.ficha(jorge))
        sesion.registrarVisita(.area(.ventas))
        #expect(sesion.recientes == [jorge])
        #expect(await sesion.abrirRapido("jorge").contains { $0.path == jorge })
        let foto = await sesion.instantanea()
        #expect(foto?.text(jorge)?.contains("Jorge Martín") == true)
    }

    /// Rutas y tamaños de todo lo que hay en una carpeta (también lo oculto).
    static func arbol(_ url: URL) throws -> [String: Int] {
        var out: [String: Int] = [:]
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [])
        while let f = e?.nextObject() as? URL {
            out[f.path] = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        }
        return out
    }
}
