import Foundation
import Observation
import TLSAgents
import TLSCore

/// El modelo de las pantallas de asistentes (Asistentes, la ficha de cada uno y Equipo › Asistentes): lee en segundo
/// plano y se recarga con cada cambio de la carpeta y cada vez que un trabajo empieza o termina.
@MainActor
@Observable
final class ModeloAsistentes {
    let sesion: VaultSession
    private(set) var lectura: LecturaAsistentes?
    @ObservationIgnored private var lecturas = 0

    init(sesion: VaultSession) { self.sesion = sesion }

    var conexion: ConexionAsistentes? { RegistroDeAsistentes.compartido.conexion(de: sesion) }

    /// Lo que pasa en vivo, para mezclarlo al pintar.
    func vivo(_ slug: String) -> TrabajoEnVivo? { conexion?.enVivo.trabajo(deAgente: slug) }

    /// Clave para recargar: la carpeta cambió o un trabajo empezó, cambió de fase o terminó.
    var claveRecarga: String {
        let vivos = conexion?.enVivo.trabajos.values.map { "\($0.ejecucion):\($0.fase.rawValue)" }.sorted() ?? []
        return "\(sesion.revision)|\(vivos.joined(separator: ","))|\(conexion?.enVivo.ultimaFrase.count ?? 0)"
    }

    func cargar() async {
        lecturas += 1
        let n = lecturas
        guard let l = await Self.leer(sesion) else { return }
        guard n == lecturas else { return }
        lectura = l
    }

    /// Lee todo lo que enseñan las pantallas de asistentes (fuera del hilo principal).
    static func leer(_ sesion: VaultSession, ahora fijo: Date? = nil) async -> LecturaAsistentes? {
        guard let root = sesion.root else { return nil }
        let layout = sesion.estructura
        let gobierno = sesion.bus?.autorizador
        let estados = Dictionary(sesion.areas.map { ($0.code, $0.estado) }, uniquingKeysWith: { a, _ in a })
        let demo = sesion.entry.clase == .demo
        let hoyCarpeta = sesion.hoyCarpeta
        let dir = sesion.writer?.stateDirectory ?? sesion.directorioEstado
        let motorDelHost = RegistroDeAsistentes.compartido.conexion(de: sesion)?.host?.estado
        let sinMotor = demo ? nil : RegistroDeAsistentes.compartido.conexion(de: sesion)?.sinMotor
        return await Task.detached(priority: .userInitiated) {
            var f = FuentesDeAsistentes()
            f.textoFichero = EscrituraAsistentes.leerConfig(root)?.texto
            if let g = gobierno {
                let e = g.estadoDeConfig()
                f.efectiva = e.efectiva
                f.textoConfirmado = g.config.textoConfirmado() ?? f.textoFichero
                f.cambiosDeFuera = e.cambiadaFuera ? e.tituloTarjeta : nil
            }
            f.estadosArea = estados
            f.demo = demo
            f.sinMotor = sinMotor
            let ajustes = AjustesDeAsistentes.leer(yaml: f.textoFichero)
            let zona = ajustes.zona
            f.ahora = fijo ?? hoyCarpeta.map { RelojDeDemo(hoy: $0, zona: zona).ahora() } ?? Date()
            f.bitacora = leerBitacora(root: root, layout: layout)
            if let motor = motorDelHost ?? abrirMotor(dir) {
                f.ejecuciones = (try? motor.ejecuciones(limite: 400)) ?? []
                f.pausadas = (try? motor.rutinasPausadas()) ?? []
                let hoy = LocalDate(date: f.ahora, timeZone: zona)
                let mes = String(format: "%04d-%02d", hoy.year, hoy.month)
                var slugs = Set(PerfilDeAsistente.deSerie.map(\.slug)).union(ajustes.agentes.keys)
                slugs.formUnion(f.ejecuciones.map(\.agente))
                for s in slugs {
                    let real = (try? motor.uso(mes: mes, agente: s, incluirSimulado: false)) ?? 0
                    let todo = (try? motor.uso(mes: mes, agente: s, incluirSimulado: true)) ?? 0
                    if real > 0 || todo > 0 { f.usoMotor[s] = (real, max(0, todo - real)) }
                }
            }
            return LecturaAsistentes.calcular(f)
        }.value
    }

    /// El estado del motor de la carpeta, si ya existe (nunca se crea solo por mirarlo).
    nonisolated static func abrirMotor(_ dir: URL) -> EstadoDelMotor? {
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(EstadoDelMotor.fileName).path) else { return nil }
        return try? EstadoDelMotor(directory: dir)
    }

    /// Las líneas de todas las Bitácoras mensuales (`6 · Equipo/Bitácora/AAAA-MM.md`), sin descargar de iCloud.
    nonisolated static func leerBitacora(root: URL, layout: VaultLayout?) -> [ApunteBitacora] {
        let layout = layout ?? VaultLayout.load(root: root).layout
        let carpeta = Bitacora.carpeta(layout)
        guard !layout.isPrivate(carpeta) else { return [] }
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.url(in: root).path)) ?? []
        var out: [ApunteBitacora] = []
        for n in nombres.sorted() {
            let p = carpeta.appending(n.precomposedStringWithCanonicalMapping)
            guard Bitacora.esRutaDeBitacora(p, layout: layout), !layout.isPrivate(p),
                  let texto = AjustesBases.leerTexto(p, root: root) else { continue }
            out += ApunteBitacora.leer(texto, ruta: p)
        }
        return out
    }

    /// El texto de las últimas líneas del registro técnico de un trabajo (`ejecuciones/<id>/stream.jsonl`).
    nonisolated static func registroTecnico(_ ejecucion: String, dir: URL, maximo: Int = 24 * 1024) -> String? {
        guard ejecucion.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        let url = dir.appendingPathComponent("ejecuciones", isDirectory: true)
            .appendingPathComponent(ejecucion, isDirectory: true).appendingPathComponent("stream.jsonl")
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let tam = (try? h.seekToEnd()) ?? 0
        let desde = tam > UInt64(maximo) ? tam - UInt64(maximo) : 0
        try? h.seek(toOffset: desde)
        guard let datos = try? h.readToEnd() else { return nil }
        var texto = String(decoding: datos, as: UTF8.self)
        if desde > 0, let i = texto.firstIndex(of: "\n") { texto = String(texto[texto.index(after: i)...]) }
        let lineas = texto.split(separator: "\n").suffix(60).map { l in
            l.count > 400 ? String(l.prefix(400)) + "…" : String(l)
        }
        return lineas.isEmpty ? nil : lineas.joined(separator: "\n")
    }
}

extension ModeloAsistentes {
    /// La carpeta de estado (fuera de la carpeta de la empresa): índice, `estado.sqlite`, trabajos.
    var directorioDeEstado: URL { sesion.writer?.stateDirectory ?? sesion.directorioEstado }
}
