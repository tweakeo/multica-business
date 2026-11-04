import Foundation
import TLSCore

// F5 · rol calendario (PLAN §7.2, §9 F5 criterio 2): EventKit detrás de `AlmacenDeEventos`, el calendario propio
// «The Last System» (rituales y sesiones S1–S9, **sin invitados**), `mapa_calendario`, la tarjeta «¿Actualizo la
// ficha?» y, de los demás calendarios, solo bloques de ocupado.
//
// Cómo se usa (lo monta la app por empresa abierta con escritor):
// 1. Conexiones / paso 7: `PuertaDePermisos` explica y pide `.calendarios`; después `conectar()` crea el calendario.
// 2. Con cada cambio de la carpeta: `sincronizar(foto:hoy:)` → crea, actualiza o retira eventos y devuelve tarjetas.
// 3. Tarjeta «¿Actualizo la ficha?»: `planParaActualizarFicha(_:foto:persona:)` da el `WritePlan` (va por el
//    `CommandBus` como la persona); «Dejar la ficha como está» → `devolverAlaFicha(_:foto:hoy:)`.
// 4. Hoy («Lo que cabe hoy», «Hoy tienes 3 h de 4») y `tls_agenda`: `ocupado(desde:hasta:)`, solo bloques de ocupado.

/// Espacio de nombres del submódulo Calendario.
public enum CalendarioTLS {
    /// El nombre de nuestro calendario.
    public static let nombre = EventosDeLaCarpeta.nombreCalendario
}

/// Cómo quedó una sincronización.
public struct InformeCalendario: Sendable, Hashable {
    public enum Estado: Sendable, Hashable {
        case conectado
        /// Aún no se ha pedido el permiso: no se hace nada (la explicación va antes, en Conexiones).
        case sinConectar
        /// Permiso denegado, restringido o solo para añadir: tarjeta explicativa con enlace a Ajustes del Sistema.
        case sinPermiso(TarjetaDePermiso)
    }

    public var estado: Estado
    /// Claves (`tls://…`) de lo creado, cambiado y retirado en esta pasada.
    public var creados: [String] = []
    public var actualizados: [String] = []
    public var retirados: [String] = []
    /// Lo que pide tu decisión (la ficha nunca se escribe sola).
    public var tarjetas: [TarjetaCalendario] = []
    /// Lo que no se pudo hacer, dicho para personas (el detalle técnico va al log de la app).
    public var avisos: [String] = []

    public init(estado: Estado) { self.estado = estado }

    /// La tarjeta del permiso, si falta.
    public var tarjetaDePermiso: TarjetaDePermiso? {
        if case .sinPermiso(let t) = estado { return t }
        return nil
    }
}

/// De ficheros a calendario. Uno por empresa abierta (su `mapa_calendario` está en el estado de esa carpeta). Un actor:
/// las pasadas van de una en una.
public actor SincronizadorCalendario {
    let almacen: any AlmacenDeEventos
    let mapa: MapaCalendario
    let nombreCalendario: String
    let reloj: @Sendable () -> Date

    public init(almacen: any AlmacenDeEventos, mapa: MapaCalendario, nombreCalendario: String = CalendarioTLS.nombre,
                reloj: @escaping @Sendable () -> Date = { Date() }) {
        self.almacen = almacen; self.mapa = mapa; self.nombreCalendario = nombreCalendario; self.reloj = reloj
    }

    // MARK: Conectar

    /// El estado del permiso, como lo cuenta Permisos.
    public nonisolated func estadoDelPermiso() -> EstadoDePermiso { almacen.permiso().estadoDePermiso }

    /// Hay permiso y ya existe nuestro calendario.
    public func conectado() -> Bool {
        almacen.permiso().permiteTrabajar && ((try? mapa.calendarioPropio()) ?? nil) != nil
    }

    /// F5 · corrector (P2-7): deja de usar el Calendario en esta empresa. No borra ni cambia nada en Calendario: lo que ya
    /// está allí se queda; al volver a conectar se recupera el mismo calendario sin repetir eventos.
    public func desconectar() throws {
        try mapa.quitarCalendarioPropio(fecha: reloj())
    }

    /// Crea (una sola vez) el calendario «The Last System» o recupera el que ya hay. Sin permiso, devuelve la tarjeta.
    @discardableResult
    public func conectar() throws -> InformeCalendario {
        guard let e = estadoSinPermiso() else {
            _ = try calendarioPropio()
            return InformeCalendario(estado: .conectado)
        }
        return InformeCalendario(estado: e)
    }

    func estadoSinPermiso() -> InformeCalendario.Estado? {
        switch almacen.permiso() {
        case .concedido: nil
        case .sinPreguntar: .sinConectar
        case .denegado, .restringido, .soloAnadir: .sinPermiso(TarjetaDePermiso.de(.calendarios))
        }
    }

    /// Nuestro calendario: el del mapa si sigue existiendo con ese nombre; si no, el que haya con ese nombre; si no, uno
    /// nuevo (en iCloud o en «En mi Mac»).
    func calendarioPropio() throws -> String {
        let guardado = try mapa.calendarioPropio()
        if let existente = try almacen.calendario(llamado: nombreCalendario) {
            if existente != guardado { try mapa.ponerCalendarioPropio(existente, fecha: reloj()) }
            return existente
        }
        let nuevo = try almacen.crearCalendario(llamado: nombreCalendario)
        try mapa.ponerCalendarioPropio(nuevo, fecha: reloj())
        return nuevo
    }

    // MARK: Sincronizar

    /// Pone el Calendario al día con la carpeta: crea lo nuevo, cambia lo que cambió en la ficha y retira lo que ya no
    /// está (ficha retirada a `Archivo/`, inactiva o sin `calendario: true`). Si cambiaste un evento en Calendario, no
    /// lo pisa: devuelve la tarjeta «¿Actualizo la ficha?». No escribe nada en la carpeta.
    public func sincronizar(foto: VaultSnapshot, hoy: LocalDate? = nil) throws -> InformeCalendario {
        if let e = estadoSinPermiso() { return InformeCalendario(estado: e) }
        var informe = InformeCalendario(estado: .conectado)
        let cal = try calendarioPropio()
        let zona = EventosDeLaCarpeta.zona(foto)
        let dia = hoy ?? Reloj.deCarpeta(foto, zona: zona).hoy
        let filas = Dictionary(try mapa.activas().map { ($0.clave, $0) }, uniquingKeysWith: { a, _ in a })
        let anclas = filas.compactMapValues(\.ancla)
        let deseados = EventosDeLaCarpeta.deseados(foto: foto, hoy: dia, zona: zona, anclas: anclas)
        let ahora = reloj()

        for d in deseados {
            do {
                guard let fila = filas[d.clave], let huellaEscrita = fila.huella else {
                    try crear(d, en: cal, ancla: dia, ahora: ahora, zona: zona)
                    informe.creados.append(d.clave)
                    continue
                }
                guard let actual = try leer(fila, url: d.evento.url, en: cal) else {
                    informe.tarjetas.append(TextosCalendario.quitado(d))
                    continue
                }
                let hActual = HuellaEvento.de(actual, zona: zona)
                let hFicha = HuellaEvento.de(d.evento, zona: zona)
                var f = fila
                if actual.id != fila.eventoID { f.eventoID = actual.id }
                if hActual != huellaEscrita {
                    if hActual == hFicha {
                        // La ficha ya dice lo mismo que el Calendario (aceptaste «Actualizar la ficha»): nada que decidir.
                        f.huella = hActual; f.actualizado = ahora
                        try mapa.guardar(f)
                    } else {
                        informe.tarjetas.append(TextosCalendario.cambiado(d, actual: actual, huella: hActual, zona: zona))
                        if f != fila { try mapa.guardar(f) }
                    }
                    continue
                }
                if hFicha != huellaEscrita {
                    if actual.invitados > 0 {
                        informe.tarjetas.append(TextosCalendario.conInvitados(d))
                        continue
                    }
                    var ev = d.evento
                    ev.id = actual.id
                    let id = try almacen.guardar(ev, enCalendario: cal)
                    f.eventoID = id; f.huella = hFicha; f.ruta = d.ruta; f.celda = d.celdaSesion; f.actualizado = ahora
                    try mapa.guardar(f)
                    informe.actualizados.append(d.clave)
                } else if f != fila {
                    try mapa.guardar(f)
                }
            } catch {
                informe.avisos.append("No pude poner «\(d.evento.titulo)» en Calendario.")
            }
        }

        // Retirar: lo apuntado que la carpeta ya no pide. Con una foto vacía (carpeta no leída) no se retira nada.
        guard !foto.files.isEmpty else { return informe }
        let pedidas = Set(deseados.map(\.clave))
        for fila in filas.values.sorted(by: { $0.clave < $1.clave }) where !pedidas.contains(fila.clave) {
            do {
                if let actual = try leer(fila, url: URL(string: fila.clave), en: cal), let id = actual.id {
                    if actual.invitados > 0 {
                        let d = EventoDeseado(clave: fila.clave, tipo: EventoDeseado.Tipo(rawValue: fila.tipo) ?? .rutina,
                                              ruta: fila.ruta ?? VaultPath(""), celdaSesion: fila.celda, evento: actual)
                        informe.tarjetas.append(TextosCalendario.conInvitados(d))
                        continue
                    }
                    try almacen.retirar(id: id)
                }
                var f = fila
                f.retirado = ahora; f.actualizado = ahora
                try mapa.guardar(f)
                informe.retirados.append(fila.clave)
            } catch {
                informe.avisos.append("No pude quitar un evento retirado del Calendario.")
            }
        }
        return informe
    }

    func crear(_ d: EventoDeseado, en cal: String, ancla: LocalDate, ahora: Date, zona: TimeZone) throws {
        var ev = d.evento
        ev.id = nil
        let id = try almacen.guardar(ev, enCalendario: cal)
        try mapa.guardar(FilaMapaCalendario(clave: d.clave, tipo: d.tipo.rawValue, ruta: d.ruta, celda: d.celdaSesion,
                                            eventoID: id, calendarioID: cal,
                                            huella: HuellaEvento.de(ev, zona: zona),
                                            ancla: d.tipo == .rutina ? ancla : nil, actualizado: ahora))
    }

    func leer(_ fila: FilaMapaCalendario, url: URL?, en cal: String) throws -> EventoDelCalendario? {
        // Solo lo que está en **nuestro** calendario (S5): si Manu lo movió a otro, ya no es nuestro y no se toca
        // (ni se borra de allí ni se devuelve).
        if let id = fila.eventoID, let e = try almacen.evento(id: id), e.calendario == nil || e.calendario == cal { return e }
        if let url { return try almacen.evento(url: url, enCalendario: cal) }
        return nil
    }

    // MARK: Tarjetas

    /// «Actualizar la ficha»: el plan que pasa a la ficha lo que pusiste en Calendario (nombre, día, hora y duración de
    /// la rutina; fecha y hora de la sesión en su fila del Viaje). Va por el `CommandBus` como la persona. No cambia el
    /// mapa: en la siguiente pasada la ficha y el evento coinciden y la tarjeta desaparece sola. `nil` si ya no hay
    /// nada que pasar o el cambio no se puede escribir en la ficha (por ejemplo, un ritual que dejó de repetirse).
    public func planParaActualizarFicha(_ t: TarjetaCalendario, foto: VaultSnapshot, persona: String) throws -> WritePlan? {
        guard t.tipo == .cambiadoEnCalendario, let fila = try mapa.fila(t.clave), fila.activa else { return nil }
        let zona = EventosDeLaCarpeta.zona(foto)
        let cal = try calendarioPropio()
        guard let actual = try leer(fila, url: URL(string: t.clave), en: cal) else { return nil }
        let dia = Reloj.deCarpeta(foto, zona: zona).hoy
        let anclas = fila.ancla.map { [t.clave: $0] } ?? [:]
        guard let d = EventosDeLaCarpeta.deseados(foto: foto, hoy: dia, zona: zona, anclas: anclas).first(where: { $0.clave == t.clave })
        else { return nil }
        return PlanesDeCalendario.actualizarFicha(d, con: actual, zona: zona, persona: persona)
    }

    /// «Dejar la ficha como está» o «Volver a ponerlo en Calendario»: el evento vuelve a lo que dice la ficha.
    @discardableResult
    public func devolverAlaFicha(_ t: TarjetaCalendario, foto: VaultSnapshot, hoy: LocalDate? = nil) throws -> Bool {
        guard estadoSinPermiso() == nil else { return false }
        let cal = try calendarioPropio()
        let zona = EventosDeLaCarpeta.zona(foto)
        let dia = hoy ?? Reloj.deCarpeta(foto, zona: zona).hoy
        let fila = try mapa.fila(t.clave)
        let anclas = fila?.ancla.map { [t.clave: $0] } ?? [:]
        guard let d = EventosDeLaCarpeta.deseados(foto: foto, hoy: dia, zona: zona, anclas: anclas).first(where: { $0.clave == t.clave })
        else { return false }
        let actual = try fila.flatMap { try leer($0, url: d.evento.url, en: cal) }
        if let actual, actual.invitados > 0 { return false }
        var ev = d.evento
        ev.id = actual?.id
        let id = try almacen.guardar(ev, enCalendario: cal)
        let ahora = reloj()
        try mapa.guardar(FilaMapaCalendario(clave: d.clave, tipo: d.tipo.rawValue, ruta: d.ruta, celda: d.celdaSesion,
                                            eventoID: id, calendarioID: cal, huella: HuellaEvento.de(ev, zona: zona),
                                            ancla: fila?.ancla ?? (d.tipo == .rutina ? dia : nil), actualizado: ahora))
        return true
    }

    /// «Quitarla del Calendario» (rutina quitada en Calendario): la ficha deja de pedirlo (`calendario: false`).
    public nonisolated func planParaDejarDeApuntar(_ t: TarjetaCalendario, persona: String) -> WritePlan? {
        guard t.tipo == .quitadoEnCalendario, t.clave.hasPrefix("tls://rutina/") else { return nil }
        return PlanesDeCalendario.dejarDeApuntar(t.ruta, persona: persona)
    }

    // MARK: Puesta en marcha (paso 5)

    /// Al terminar el paso 5 («Tu día a día»): si el Calendario ya está conectado, el plan que marca su rutina semanal
    /// con `calendario: true` (después, `sincronizar` crea el evento). Sin Calendario conectado, `nil`: no se pide nada.
    public func planDeLaPuesta(foto: VaultSnapshot, persona: String) -> WritePlan? {
        guard conectado() else { return nil }
        return PlanesDeCalendario.apuntarRutinaDeLaPuesta(foto: foto, persona: persona)
    }

    // MARK: Ocupado (Hoy y `tls_agenda`)

    /// Lo ocupado de los **demás** calendarios entre dos días (incluidos), en la zona dada, como `EventoAgenda`
    /// «Ocupado» sin títulos ni asistentes. Lo nuestro no cuenta (los rituales ya salen de sus fichas). Sin permiso, nada.
    public func ocupado(desde: LocalDate, hasta: LocalDate, zona: TimeZone) -> [EventoAgenda] {
        guard almacen.permiso().permiteTrabajar, desde <= hasta else { return [] }
        let propio = (try? mapa.calendarioPropio()) ?? nil
        let inicio = desde.date(timeZone: zona)
        let fin = hasta.adding(days: 1, timeZone: zona).date(timeZone: zona)
        guard let bloques = try? almacen.ocupado(desde: inicio, hasta: fin, excepto: Set([propio].compactMap { $0 })) else { return [] }
        return OcupadoEnLaAgenda.eventos(bloques, desde: desde, hasta: hasta, zona: zona)
    }

    /// Para inyectar en `tls_agenda` (`ServidorDeHerramientas.Dependencias.ocupado`) y en Hoy
    /// (`CalendarioEnHoy.conectar`): lo ocupado de otros calendarios en la zona de la carpeta.
    public nonisolated func fuenteDeOcupado(zona: TimeZone) -> @Sendable (LocalDate, LocalDate) async -> [EventoAgenda] {
        { desde, hasta in await self.ocupado(desde: desde, hasta: hasta, zona: zona) }
    }
}

/// Bloques de ocupado → `EventoAgenda` para la agenda: por día, unidos los que se solapan, recortados al día y sin
/// los de todo el día (festivos, cumpleaños, vacaciones: no son horas de trabajo y no se inventan horas).
public enum OcupadoEnLaAgenda {
    public static let titulo = "Ocupado"

    public static func eventos(_ bloques: [BloqueOcupado], desde: LocalDate, hasta: LocalDate, zona: TimeZone) -> [EventoAgenda] {
        var out: [EventoAgenda] = []
        var dia = desde
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        while dia <= hasta {
            let ini = dia.date(timeZone: zona), fin = dia.adding(days: 1, timeZone: zona).date(timeZone: zona)
            let tramos = bloques.filter { !$0.todoElDia && $0.inicio < fin && $0.fin > ini }
                .map { (max($0.inicio, ini), min($0.fin, fin)) }
                .filter { $0.0 < $0.1 }
                .sorted { $0.0 < $1.0 }
            var unidos: [(Date, Date)] = []
            for t in tramos {
                if let u = unidos.last, t.0 <= u.1 { unidos[unidos.count - 1].1 = max(u.1, t.1) } else { unidos.append(t) }
            }
            for u in unidos {
                let c = cal.dateComponents([.hour, .minute], from: u.0)
                let horas = (u.1.timeIntervalSince(u.0) / 3600 * 10).rounded() / 10
                out.append(EventoAgenda(titulo: titulo, dia: dia, hora: String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0),
                                        horas: horas > 0 ? horas : nil))
            }
            dia = dia.adding(days: 1, timeZone: zona)
        }
        return out
    }
}
