// Procedencia: lógica portada a Swift desde la unificación de octubre (`fase2_verificar.py`, autor: Manuel Trigo):
// cada fichero de la foto de antes se busca en su destino (siguiendo el registro de movimientos por prefijo) y se
// compara su tamaño y su SHA-256; aparte, los editados a propósito y el recuento total. Reescrito sobre
// `Inventory`; sin código copiado. Ver docs/PROCEDENCIA.md.

import Foundation
import TLSCore

/// Resultado de comprobar una importación: «312 de 312 (recuento + SHA-256)».
public struct ResultadoVerificacion: Sendable, Codable, Hashable {
    public struct Diferencia: Sendable, Codable, Hashable {
        public enum Tipo: String, Sendable, Codable, Hashable {
            /// No está donde debía.
            case falta
            /// Está, pero con otro tamaño.
            case tamano
            /// Está, con el mismo tamaño y otro contenido.
            case huella
        }
        public let tipo: Tipo
        /// Ruta de antes.
        public let origen: String
        /// Ruta donde se esperaba.
        public let destino: String
    }

    /// Ficheros comprobados: los de antes más los creados.
    public let total: Int
    /// Iguales byte a byte que antes (movidos o no).
    public let identicos: Int
    /// Cambiados a propósito (propiedades o enlaces): coinciden con lo que escribió la app.
    public let editadosAProposito: Int
    /// Creados por la importación (traídos de fuera, informe, fechas) y comprobados.
    public let creados: Int
    public let diferencias: [Diferencia]
    public let recuentoAntes: Int
    public let recuentoDespues: Int
    public let recuentoEsperado: Int

    public var comprobados: Int { identicos + editadosAProposito + creados }
    public var cuadraElRecuento: Bool { recuentoDespues == recuentoEsperado }
    public var sinDiferencias: Bool { diferencias.isEmpty && cuadraElRecuento }

    /// «312 de 312 (recuento + SHA-256)».
    public var texto: String {
        var s = "\(comprobados) de \(total) (recuento + SHA-256)"
        if !cuadraElRecuento {
            s += " · el recuento no cuadra: hay \(recuentoDespues) y esperaba \(recuentoEsperado)"
        }
        return s
    }
}

/// Comprobación de punta a punta (port de `fase2_verificar.py`).
public enum Verificador {
    /// Compara la foto de antes con la de después.
    ///
    /// - `movimientos`: lo que movió el plan, en orden (de un fichero o de una carpeta entera).
    /// - `editados`: ruta final → SHA-256 que escribió la app (cambios a propósito).
    /// - `creados`: ruta → SHA-256 de lo nuevo.
    /// Las dos fotos se hacen con las mismas exclusiones (`Inventory.make(… incluirArchivo: true)`), así que lo
    /// retirado a `Archivo/` también se comprueba.
    public static func verificar(antes: Inventory, despues: Inventory, movimientos: [Movimiento],
                                 editados: [VaultPath: String], creados: [VaultPath: String]) -> ResultadoVerificacion {
        var despuesPorRuta: [String: InventoryEntry] = [:]
        for e in despues.entradas where e.tipo == .fichero { despuesPorRuta[TextFolding.pathKey(e.ruta)] = e }
        var editadosPorRuta: [String: String] = [:]
        for (p, h) in editados { editadosPorRuta[TextFolding.pathKey(p.raw)] = h }
        var identicos = 0, aProposito = 0, okCreados = 0
        var diferencias: [ResultadoVerificacion.Diferencia] = []
        let ficherosAntes = antes.entradas.filter { $0.tipo == .fichero && !$0.dataless }
        for e in ficherosAntes {
            let destino = seguir(VaultPath(e.ruta), movimientos)
            let k = TextFolding.pathKey(destino.raw)
            guard let ahora = despuesPorRuta[k] else {
                diferencias.append(.init(tipo: .falta, origen: e.ruta, destino: destino.raw)); continue
            }
            if let esperado = editadosPorRuta[k] {
                if ahora.sha256 == esperado { aProposito += 1 } else {
                    diferencias.append(.init(tipo: .huella, origen: e.ruta, destino: destino.raw))
                }
                continue
            }
            if ahora.tamano != e.tamano {
                diferencias.append(.init(tipo: .tamano, origen: e.ruta, destino: destino.raw))
            } else if ahora.sha256 != e.sha256 {
                diferencias.append(.init(tipo: .huella, origen: e.ruta, destino: destino.raw))
            } else {
                identicos += 1
            }
        }
        for (p, h) in creados.sorted(by: { $0.key.raw < $1.key.raw }) {
            guard let ahora = despuesPorRuta[TextFolding.pathKey(p.raw)] else {
                diferencias.append(.init(tipo: .falta, origen: "(nuevo)", destino: p.raw)); continue
            }
            if ahora.sha256 == h { okCreados += 1 } else {
                diferencias.append(.init(tipo: .huella, origen: "(nuevo)", destino: p.raw))
            }
        }
        let antesN = antes.entradas.filter { $0.tipo == .fichero }.count
        let despuesN = despues.entradas.filter { $0.tipo == .fichero }.count
        return ResultadoVerificacion(total: ficherosAntes.count + creados.count, identicos: identicos,
                                     editadosAProposito: aProposito, creados: okCreados, diferencias: diferencias,
                                     recuentoAntes: antesN, recuentoDespues: despuesN, recuentoEsperado: antesN + creados.count)
    }

    /// Dónde acaba una ruta tras los movimientos (por prefijo y en orden, como el registro de la unificación).
    public static func seguir(_ p: VaultPath, _ movimientos: [Movimiento]) -> VaultPath {
        seguir(p, pares: movimientos.map { ($0.de, $0.a) })
    }

    public static func seguir(_ p: VaultPath, _ traslados: [Traslado]) -> VaultPath {
        seguir(p, pares: traslados.map { ($0.de, $0.a) })
    }

    static func seguir(_ p: VaultPath, pares: [(VaultPath, VaultPath)]) -> VaultPath {
        var actual = p
        for (de, a) in pares {
            let k = TextFolding.pathKey(actual.raw), o = TextFolding.pathKey(de.raw)
            if k == o {
                actual = a
            } else if k.hasPrefix(o + "/") {
                actual = VaultPath(components: a.components + Array(actual.components.dropFirst(de.components.count)))
            }
        }
        return actual
    }

    /// Diferencias entre dos fotos del mismo árbol (para «Deshacer» y «Actualizar la copia»): rutas que aparecen,
    /// desaparecen o cambian.
    public static func diferencias(_ a: Inventory, _ b: Inventory) -> [String] { a.diferencias(con: b) }

    /// La foto sin lo que cuelga de `Archivo/` (lo que retira «Deshacer» va ahí y no cuenta para «el árbol de antes»).
    public static func sinArchivo(_ inv: Inventory, archivo: String = "Archivo") -> Inventory {
        let k = TextFolding.pathKey(archivo)
        let entradas = inv.entradas.filter { e in
            let r = TextFolding.pathKey(e.ruta)
            return r != k && !r.hasPrefix(k + "/")
        }
        return Inventory(raiz: inv.raiz, entradas: entradas, excluidas: inv.excluidas, conHashes: inv.conHashes)
    }
}
