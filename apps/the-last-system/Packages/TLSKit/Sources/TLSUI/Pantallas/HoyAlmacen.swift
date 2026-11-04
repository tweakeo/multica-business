import Foundation
import Observation
import OSLog
import TLSCore
import TLSDesign

/// Hoy de una empresa abierta: los datos (`DatosHoy`, rehechos fuera del hilo principal con cada cambio de la carpeta y
/// de «Revisar») y lo que decides que no va a la carpeta (`EstadoHoy`, en `hoy.json` del estado). Uno por empresa; lo
/// comparten Hoy, Decisiones y el Resumen de las áreas. Mantiene al día la insignia magenta de Decisiones en la barra
/// lateral. Solo escribe en la carpeta lo que pide un clic de la persona, por el dominio (`escribirConDominio`).
@Observable @MainActor
final class AlmacenHoy {
    private(set) var datos: DatosHoy?
    private(set) var estado: EstadoHoy
    /// Hay una carga en marcha.
    private(set) var cargando = false

    @ObservationIgnored private weak var sesion: VaultSession?
    @ObservationIgnored let archivo: URL?
    @ObservationIgnored private var vigilando = false
    @ObservationIgnored private var ultimaClave: Clave?
    @ObservationIgnored private var cola: Task<Void, Never>?
    /// F5 · calendario: lo ocupado de los otros calendarios entre dos días (`CalendarioEnHoy.conectar`). `nil` = sin
    /// Calendario conectado.
    @ObservationIgnored var ocupado: (@Sendable (LocalDate, LocalDate) async -> [EventoAgenda])?
    private static let log = Logger(subsystem: "es.thelast.system", category: "Hoy")

    struct Clave: Equatable {
        let generacion: Int
        let tarjetas: [UUID]
        let estado: EstadoHoy
        let persona: String
    }

    private final class Entrada {
        weak var sesion: VaultSession?
        let almacen: AlmacenHoy
        init(_ s: VaultSession, _ a: AlmacenHoy) { sesion = s; almacen = a }
    }

    private static var porSesion: [ObjectIdentifier: Entrada] = [:]

    /// El de esta empresa abierta.
    static func de(_ sesion: VaultSession) -> AlmacenHoy {
        porSesion = porSesion.filter { $0.value.sesion != nil }
        let k = ObjectIdentifier(sesion)
        if let e = porSesion[k], e.sesion === sesion { return e.almacen }
        let a = AlmacenHoy(sesion: sesion, archivo: sesion.directorioEstado.appendingPathComponent("hoy.json"))
        porSesion[k] = Entrada(sesion, a)
        return a
    }

    init(sesion: VaultSession?, archivo: URL?) {
        self.sesion = sesion
        self.archivo = archivo
        if let archivo, let data = try? Data(contentsOf: archivo), let e = try? JSONDecoder().decode(EstadoHoy.self, from: data) {
            estado = e
        } else {
            estado = EstadoHoy()
        }
    }

    // MARK: Cargar

    /// Rehace los datos si cambió la carpeta, «Revisar» o lo que decidiste. Las llamadas van en fila (una detrás de
    /// otra, nunca a la vez): al volver, los datos están al día. Con la empresa cerrada no hace nada.
    func actualizar(forzar: Bool = false) async {
        let anterior = cola
        let tarea = Task { [weak self] in
            await anterior?.value
            await self?.cargar(forzar: forzar)
        }
        cola = tarea
        await tarea.value
    }

    private func cargar(forzar: Bool) async {
        guard let sesion, sesion.service != nil else { return }
        let rel = AlmacenRelaciones.de(sesion)
        await rel.actualizar()
        guard sesion.service != nil, let foto = rel.foto else { return }
        let clave = Clave(generacion: rel.generacion, tarjetas: sesion.tarjetas.map(\.id), estado: estado, persona: sesion.persona)
        if !forzar, clave == ultimaClave, datos != nil { vigilar(); return }
        cargando = true
        let conflictos = sesion.tarjetas
        let persona = sesion.persona
        let e = estado
        // F4 · lo de los asistentes (aprobaciones, preguntas, propuestas de mejora…) entra en la misma bandeja.
        let gobierno = AsistentesDeLaEmpresa.de(sesion).autorizador
        // F5 · calendario: lo ocupado de otros calendarios en la semana de hoy (sin títulos ni asistentes).
        let eventos = await Self.ocupadoDeLaSemana(foto: foto, fuente: ocupado)
        let (d, paraHoy, quietas) = await Task.detached(priority: .userInitiated) {
            let d = DatosHoy.calcular(foto: foto, conflictos: conflictos, persona: persona, estados: e.tarjetas,
                                      historial: e.historial, pospuestas: e.fechasPospuestas, gobierno: gobierno,
                                      eventos: eventos)
            // La barra lateral (DISENO §6): «Tareas · 3 para hoy» (lo mismo que cuenta la cabecera de Tareas) y
            // «2 · Ventas · 2 quietas» (abiertas sin contacto desde hace 7 días o más, como el tablero de Ventas).
            let paraHoy = ResumenTareas(LectorTareas.filas(foto: foto), hoy: d.hoy).paraHoy
            let quietas = d.panel.foto.oportunidades.filter { $0.abierta && ($0.diasQuieta(hoy: d.hoy) ?? 0) >= 7 }.count
            return (d, paraHoy, quietas)
        }.value
        datos = d
        ultimaClave = clave
        cargando = false
        ponerInsignia(d.pendientes)
        ponerBarra(paraHoy: paraHoy, quietas: quietas, ventasEnReposo: d.panel.foto.enReposo(.ventas))
        vigilar()
    }

    /// «3 para hoy» bajo Tareas y «2 quietas» (en ámbar) bajo Ventas; nada cuando es 0.
    private func ponerBarra(paraHoy: Int, quietas: Int, ventasEnReposo: Bool) {
        guard let sesion else { return }
        var t = sesion.barraLateral.datos[.tareas] ?? DatoFilaBarra()
        t.debajo = paraHoy == 0 ? nil : paraHoy == 1 ? "1 para hoy" : "\(paraHoy) para hoy"
        if sesion.barraLateral.datos[.tareas] != t { sesion.barraLateral.datos[.tareas] = t }
        var v = sesion.barraLateral.datos[.area(.ventas)] ?? DatoFilaBarra()
        v.atencion = quietas == 0 || ventasEnReposo ? nil : quietas == 1 ? "1 quieta" : "\(quietas) quietas"
        if sesion.barraLateral.datos[.area(.ventas)] != v { sesion.barraLateral.datos[.area(.ventas)] = v }
    }

    /// La insignia de Decisiones en la barra lateral: lo que espera tu decisión (nada = sin insignia).
    /// F5 · integración: lo de la bandeja más lo que piden las conexiones (permiso, Calendario, herramientas nuevas).
    func refrescarInsignia() {
        ponerInsignia(datos?.pendientes ?? 0)
    }

    private func ponerInsignia(_ base: Int) {
        guard let sesion else { return }
        let n = base + ConexionesEnDecisiones.de(sesion).pendientes.count
        var dato = sesion.barraLateral.datos[.decisiones] ?? DatoFilaBarra()
        dato.insignia = n > 0 ? n : nil
        dato.palabraInsignia = n == 1 ? "espera tu decisión" : "esperan tu decisión"
        if sesion.barraLateral.datos[.decisiones] != dato { sesion.barraLateral.datos[.decisiones] = dato }
    }

    /// Mientras la empresa siga abierta, cada cambio de la carpeta o de «Revisar» rehace Hoy (y la insignia), aunque
    /// estés en otra pantalla.
    private func vigilar() {
        guard let sesion, sesion.service != nil, !vigilando else { return }
        vigilando = true
        withObservationTracking {
            _ = sesion.revision
            _ = sesion.tarjetas
            _ = sesion.persona
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.vigilando = false
                await self.actualizar()
            }
        }
    }

    // MARK: Lo que no va a la carpeta

    private func cambiarEstado(_ aviso: String?, _ cambio: (inout EstadoHoy) -> Void) {
        let antes = estado
        var e = estado
        cambio(&e)
        if let hoy = datos?.hoy { e.podar(hoy: hoy) }
        guard e != antes else { return }
        estado = e
        guardar()
        Task { await actualizar() }
        if let aviso, let sesion {
            sesion.aviso = Aviso(aviso, estado: .bien) { [weak self] in
                guard let self else { return }
                self.estado = antes
                self.guardar()
                Task { await self.actualizar() }
            }
        }
    }

    /// «Posponer a mañana» del foco (el siguiente laborable). Se puede deshacer.
    func posponer(_ t: Tarjeta) {
        guard let hoy = datos?.hoy else { return }
        let hasta = hoy.siguienteLaborable
        cambiarEstado("Pospuesto hasta \(Self.dia(hasta, hoy: hoy)): «\(t.titulo)»") { e in
            e.poner(EstadoTarjeta(id: t.id, pospuestaHasta: hasta))
            e.historial.append(DecisionTarjeta(patron: t.patron, accion: "posponer"))
        }
    }

    /// Descartar una tarjeta (no vuelve). Se puede deshacer.
    func descartar(_ t: Tarjeta) {
        cambiarEstado("Descartada: «\(t.titulo)»") { e in
            e.poner(EstadoTarjeta(id: t.id, descartada: true))
            e.historial.append(DecisionTarjeta(patron: t.patron, accion: "descartar"))
        }
    }

    /// Apunta lo que hiciste con una tarjeta (para que tres veces lo mismo proponga una regla).
    func apuntar(_ t: Tarjeta, accion: String) {
        cambiarEstado(nil) { e in e.historial.append(DecisionTarjeta(patron: t.patron, accion: accion)) }
    }

    /// Posponer una decisión hasta un día (sale de la bandeja y de la insignia hasta entonces). Se puede deshacer.
    func posponer(decision t: TarjetaDecision, hasta: LocalDate) {
        let hoy = datos?.hoy ?? hasta
        cambiarEstado("Pospuesta hasta \(Self.dia(hasta, hoy: hoy)): «\(t.titulo)»") { e in
            e.pospuestas[t.id] = hasta.description
        }
    }

    /// «mañana», «el lunes 26».
    static func dia(_ d: LocalDate, hoy: LocalDate) -> String {
        if d == hoy.adding(days: 1) { return "mañana" }
        return "el \(HoyPantalla.diasLargos[d.weekday - 1]) \(d.day)"
    }

    private func guardar() {
        guard let archivo else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(estado)
            try FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: archivo, options: .atomic)
        } catch {
            Self.log.error("No se pudo guardar lo decidido en Hoy: \(error.localizedDescription, privacy: .public)")
        }
    }
}
