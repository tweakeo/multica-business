import Foundation
import Testing
@testable import TLSCore

/// Ayudas de las pruebas de Finanzas: la Ribera copiada a un temporal y empresas sintéticas.
enum FinanzasApoyo {
    static let manu = Autor.persona("Manu")
    /// El reloj fijo de Ribera (`hoy: 2026-10-19` en `.tls/config.yaml`).
    static var relojRibera: Reloj { relojDePrueba(2026, 10, 19) }

    static let fin = "4 · Finanzas"
    static let corriente = "4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo"
    static let ahorro = "4 · Finanzas/Registros/Bancos/cuenta-ahorro-banco-demo"
    static let extractoRibera = corriente + "/Extractos/2026-10-19 cuenta-corriente-2026-07-a-10.csv"
    static let idCorriente = "893a2ade-f982-40fb-ba96-eb6d8435e201"
    static let idAhorro = "91f42052-00da-4d58-ad83-cb7e22a14a38"

    /// Copia temporal de Asesoría Ribera (nunca se toca la del repositorio).
    static func ribera() -> EntornoCarpeta {
        EntornoCarpeta(copiando: RutasRepo.ribera, nombre: "Ribera", clase: .demo)
    }

    /// Bytes de un fichero de la Ribera del repositorio (solo lectura).
    static func datosRibera(_ ruta: String) -> Data {
        (try? Data(contentsOf: VaultPath(ruta).url(in: RutasRepo.ribera))) ?? Data()
    }

    /// Empresa vacía con las seis áreas y lo que se pida escrito.
    static func empresa(_ ficheros: [String: String]) -> EntornoCarpeta {
        let env = EntornoCarpeta(vacia: true)
        for (ruta, texto) in ficheros { env.escribir(ruta, texto) }
        return env
    }

    /// Ficha de cuenta sintética.
    static func cuenta(id: String, nombre: String, saldoInicial: String? = nil, fecha: String? = nil, formato: String? = nil) -> String {
        var s = "---\ntls_type: account\ntls_schema: 1\nid: \(id)\nnombre: \(nombre)\nmoneda: EUR\n"
        if let saldoInicial { s += "saldo_inicial: \(saldoInicial)\n" }
        if let fecha { s += "fecha_saldo_inicial: \(fecha)\n" }
        if let formato { s += formato }
        return s + "---\n# \(nombre)\n"
    }

    static let cabMovs = RegistrosFinanzas.cabeceraMovimientos.joined(separator: ",") + "\n"
    static let cabEmitidas = RegistrosFinanzas.cabeceraEmitidas.joined(separator: ",") + "\n"
    static let cabRecibidas = RegistrosFinanzas.cabeceraRecibidas.joined(separator: ",") + "\n"
    static let cabPagos = RegistrosFinanzas.cabeceraPagos.joined(separator: ",") + "\n"

    /// Fila de `movimientos.csv` con lo justo.
    static func mov(_ id: String, _ fecha: String, _ concepto: String, _ importe: String, saldo: String = "",
                    naturaleza: String = "", estado: String = "pendiente") -> String {
        "\(id),\(fecha),\(fecha),\(concepto),\(importe),\(saldo),\(naturaleza),,,,,\(estado),,,,\n"
    }

    /// Ficheros que cambiaron entre dos huellas.
    static func cambiados(_ antes: [String: String], _ despues: [String: String]) -> Set<String> {
        Set(Set(antes.keys).union(despues.keys).filter { antes[$0] != despues[$0] })
    }

    /// Filas de un CSV de la carpeta como diccionarios.
    static func filas(_ env: EntornoCarpeta, _ ruta: String) -> [[String: String]] {
        guard let t = env.texto(ruta) else { return [] }
        let tabla = CSVTable.parse(t)
        return tabla.rows.map { r in
            Dictionary(uniqueKeysWithValues: tabla.header.enumerated().map { ($1, $0 < r.count ? r[$0] : "") })
        }
    }
}
