import AppKit
import CryptoKit
import Foundation
import os
import TLSCore

/// El ejemplo del tutorial (Asesoría Ribera): su puesta en marcha ya hecha, el extracto para practicar, las huellas
/// prístinas y «Reiniciar ejemplo» (criterio F3-7).
@MainActor
enum EjemploTutorial {
    private static let log = Logger(subsystem: "es.thelast.system", category: "Tutorial")

    // MARK: Puesta en marcha hecha

    /// Deja el `onboarding.json` del ejemplo marcado como hecho y repasable paso a paso (si aún no lo tiene). Solo
    /// escribe en Application Support, nunca en la carpeta.
    static func prepararPuestaEnMarcha(_ sesion: VaultSession, appSupport: URL = AppLocations.appSupport) {
        guard sesion.entry.clase == .demo, let root = sesion.root else { return }
        prepararPuestaEnMarcha(entrada: sesion.entry, root: root, appSupport: appSupport)
    }

    static func prepararPuestaEnMarcha(entrada: VaultEntry, root: URL, appSupport: URL) {
        let almacen = AlmacenPuesta(vaultID: entrada.id, appSupport: appSupport)
        guard almacen.leer() == nil else { return }
        let contexto = ContextoCarpeta.leer(root, entrada: entrada)
        _ = OnboardingEngine.ejemploCompletado(contexto: contexto, vaultID: entrada.id, almacen: almacen)
    }

    // MARK: Extracto para practicar

    /// Nombre del extracto de ejemplo (fuera de la carpeta, en Application Support).
    static let nombreExtracto = "Extracto de ejemplo (Ribera).csv"

    /// Dos movimientos nuevos de la cuenta corriente de Ribera, con su formato (`;`, coma decimal, DD/MM/AAAA).
    static let textoExtracto = """
    fecha;fecha_valor;concepto;importe;saldo
    19/10/2026;19/10/2026;TRANSFERENCIA DE PANADERIA LA ESPIGA SL;290,40;19955,05
    19/10/2026;19/10/2026;RECIBO TELEFONIA Y FIBRA OFICINA;-48,40;19906,65

    """

    /// Deja el extracto de ejemplo en `Application Support/The Last System/tutorial/` y devuelve dónde.
    static func extractoDeEjemplo(appSupport: URL = AppLocations.appSupport) -> URL? {
        let carpeta = appSupport.appendingPathComponent("tutorial", isDirectory: true)
        let url = carpeta.appendingPathComponent(nombreExtracto)
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            try Data(textoExtracto.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            log.error("No se pudo dejar el extracto de ejemplo: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Huellas prístinas (criterio F3-7)

    /// Ruta relativa → SHA-256 de cada fichero del ejemplo. En `.tls/config.yaml` la línea `id:` se iguala (cada
    /// instalación lleva su propio `id`); `.DS_Store` y la marca del escritor no cuentan.
    nonisolated static func huellas(de carpeta: URL) throws -> [String: String] {
        let raiz = carpeta.resolvingSymlinksInPath().standardizedFileURL
        var out: [String: String] = [:]
        let fm = FileManager.default
        guard let e = fm.enumerator(at: raiz, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return [:] }
        while let u = e.nextObject() as? URL {
            guard try u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let rel = String(u.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(raiz.path.count + 1))
            if rel.hasSuffix(".DS_Store") || rel == ".tls/escritor.json" { continue }
            var datos = try Data(contentsOf: u)
            if rel == ".tls/config.yaml" {
                let lineas = String(decoding: datos, as: UTF8.self).components(separatedBy: "\n")
                    .map { $0.hasPrefix("id:") ? "id: ejemplo" : $0 }
                datos = Data(lineas.joined(separator: "\n").utf8)
            }
            out[rel] = SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined()
        }
        return out
    }

    // MARK: Reiniciar

    /// «Reiniciar ejemplo» desde el propio ejemplo: cierra sus ventanas, manda la carpeta a la Papelera (recuperable),
    /// instala otra como nueva, prepara su puesta en marcha hecha y vuelve a empezar el recorrido.
    static func reiniciar(empresa: UUID, model: AppModel, instalador: InstaladorEjemplo = InstaladorEjemplo(),
                          almacen: AlmacenTutorial = .compartido, appSupport: URL = AppLocations.appSupport) async -> VaultEntry? {
        _ = await model.cerrarVentanas(de: empresa)
        do {
            let nueva = try await instalador.reiniciar(en: model)
            almacen.reiniciar(.ejemplo)
            if let root = model.resolveURL(nueva) {
                prepararPuestaEnMarcha(entrada: nueva, root: root, appSupport: appSupport)
            }
            return nueva
        } catch {
            log.error("No se pudo reiniciar el ejemplo: \(error.localizedDescription, privacy: .public)")
            NSApp?.presentError(error)
            return nil
        }
    }
}

/// Lleva los hitos del «Recorrido con tu empresa» al estado de la puesta en marcha (paso 8, `onboarding.json`).
@MainActor
enum PuenteRecorrido {
    static func marcar(_ hito: String, empresa: UUID, appSupport: URL = AppLocations.appSupport) {
        guard let h = HitoRecorrido(rawValue: hito) else { return }
        let almacen = AlmacenPuesta(vaultID: empresa, appSupport: appSupport)
        guard var estado = almacen.leer(), estado.recorrido[h.rawValue] == nil else { return }
        estado.recorrido[h.rawValue] = Date()
        try? almacen.guardar(estado)
    }
}
