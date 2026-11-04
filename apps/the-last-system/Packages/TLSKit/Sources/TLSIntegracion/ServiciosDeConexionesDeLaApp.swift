import Foundation
import MCP
import TLSAgents
import TLSCore
import TLSGateway
import TLSIntegrations
import TLSUI

// F5 · integración. El adaptador de la pantalla Conexiones (y del paso 7 de la puesta en marcha): cumple el puerto de
// TLSUI (`ServiciosDeConexiones`) con las piezas del núcleo de una empresa abierta, según la tabla de
// docs/F5-CONTRATOS.md («Cambios pedidos › conexiones»). Lo que escribe en la carpeta (el Cartero, los interruptores,
// la rutina que va al Calendario) lo escribe **como la persona** y se deshace; las claves van del campo de la pantalla
// al Llavero y no vuelven nunca.

@MainActor
public final class ServiciosDeConexionesDeLaApp: ServiciosDeConexiones {
    private weak var conexiones: ConexionesDeEmpresa?
    /// Las explicaciones enseñadas (`PermisoExplicado.id` → la constancia de `PuertaDePermisos`): cada una sirve una vez.
    private var vistas: [UUID: ExplicacionVista] = [:]
    /// El último error de cada programa al probarlo (para enseñarlo en su fila).
    private var errores: [String: String] = [:]

    init(conexiones: ConexionesDeEmpresa) {
        self.conexiones = conexiones
    }

    private func c() throws -> ConexionesDeEmpresa {
        guard let c = conexiones, c.arrancada else {
            throw ErrorDeConexion("Esta empresa ya no está abierta con cambios permitidos.")
        }
        return c
    }

    private var persona: Autor { .persona(conexiones?.piezas.persona ?? "Manu") }

    // MARK: Ejemplo

    public func enEjemplo(_ p: PermisoDeConexion) async -> String? {
        guard conexiones?.ejemplo == true else { return nil }
        switch p {
        case .mail:
            return "En el ejemplo, Mail no se conecta: los correos de Ribera son ficticios y nada sale de tu Mac. Lo conectas en tu copia."
        case .calendario:
            return "En el ejemplo, el Calendario no se conecta: tu Calendario de verdad no se toca. Lo conectas en tu copia."
        }
    }

    // MARK: Permisos

    static func permiso(_ p: PermisoDeConexion) -> PermisoDelSistema {
        switch p {
        case .mail: .automatizacionMail
        case .calendario: .calendarios
        }
    }

    static func explicacion(_ e: ExplicacionDePermiso) -> ExplicacionDeConexion {
        ExplicacionDeConexion(titulo: e.titulo, para: e.para, hace: e.hace, nunca: e.nunca, queVeras: e.queVeras, boton: e.boton)
    }

    static func recuperacion(_ r: RecuperacionDePermiso, detalle: String? = nil) -> RecuperacionDeConexion {
        RecuperacionDeConexion(titulo: r.titulo, texto: r.texto, pasos: r.pasos, boton: r.boton, enlace: r.enlace, detalleTecnico: detalle)
    }

    static func recuperacion(_ t: TarjetaDePermiso) -> RecuperacionDeConexion {
        RecuperacionDeConexion(titulo: t.titulo, texto: t.texto, pasos: t.pasos, boton: t.boton, enlace: t.enlace,
                               detalleTecnico: t.detalleTecnico)
    }

    static func estado(_ e: EstadoDePermiso) -> EstadoDePermisoConexion {
        EstadoDePermisoConexion(rawValue: e.rawValue) ?? .desconocido
    }

    public func situacion(_ p: PermisoDeConexion) async -> SituacionDeConexion {
        guard let puerta = conexiones?.puerta else { return .sinComprobar }
        switch await puerta.situacion(Self.permiso(p)) {
        case .listo: return .listo
        case .explicar(let e): return .explicar(Self.explicacion(e))
        case .recuperar(let r): return .recuperar(Self.recuperacion(r))
        case .sinComprobar: return .sinComprobar
        }
    }

    public func explicar(_ p: PermisoDeConexion) async -> PermisoExplicado {
        let permiso = Self.permiso(p)
        guard let puerta = conexiones?.puerta else {
            return PermisoExplicado(permiso: p, explicacion: Self.explicacion(permiso.explicacion))
        }
        let (e, vista) = await puerta.explicar(permiso)
        let explicado = PermisoExplicado(permiso: p, explicacion: Self.explicacion(e))
        vistas[explicado.id] = vista
        return explicado
    }

    public func pedir(_ p: PermisoDeConexion, tras explicado: PermisoExplicado) async throws -> EstadoDePermisoConexion {
        let c = try c()
        guard let puerta = c.puerta else { throw ErrorDeConexion("En el ejemplo no se pide ningún permiso.") }
        guard explicado.permiso == p, let vista = vistas.removeValue(forKey: explicado.id) else {
            throw ErrorDeConexion("Antes de pedir el permiso hay que ver para qué es.")
        }
        let r = try await puerta.pedir(Self.permiso(p), tras: vista)
        if p == .mail, r == .concedido { await c.reintentarCorreo() }
        return Self.estado(r)
    }

    // MARK: Mail

    public func cuentasDeMail() async -> CuentasDeMailConexion {
        guard let c = conexiones, !c.ejemplo else { return .fallo("En el ejemplo, Mail no se conecta.") }
        switch await CuentasDeMail.listar(c.sistema.jxa) {
        case .cuentas(let cs): return .cuentas(cs)
        case .mailCerrado: return .mailCerrado
        case .automatizacionDenegada(let t): return .sinPermiso(Self.recuperacion(t))
        case .fallo(let f): return .fallo(f)
        }
    }

    public func ajustesDeMail() async -> AjustesDeMailConexion {
        guard let c = conexiones, !c.ejemplo else { return AjustesDeMailConexion() }
        let a = AjustesDeCorreo.leer(c.piezas.estadoDeCarpeta)
        return AjustesDeMailConexion(cuenta: a.cuenta, privados: a.privados.map { RemitentePrivadoConexion(patron: $0.patron, etiqueta: $0.etiqueta) })
    }

    public func guardarAjustesDeMail(_ a: AjustesDeMailConexion) async throws {
        let c = try c()
        guard !c.ejemplo else { throw ErrorDeConexion("En el ejemplo, Mail no se conecta.") }
        let ajustes = AjustesDeCorreo(cuenta: a.cuenta, privados: a.privados.map { RemitentePrivado(patron: $0.patron, etiqueta: $0.etiqueta) })
        do {
            try ajustes.guardar(c.piezas.estadoDeCarpeta)
        } catch {
            throw ErrorDeConexion("No he podido guardar la cuenta y los remitentes privados.")
        }
        c.actualizarHuecos()
    }

    public func carteroActivo() async -> Bool {
        conexiones?.carteroActivo ?? false
    }

    public func activarCartero(_ activo: Bool) async throws {
        let c = try c()
        guard !c.ejemplo else { throw ErrorDeConexion("En el ejemplo, Mail no se conecta.") }
        do {
            _ = try await ConexionDelCartero.activar(activo, bus: c.piezas.bus, autor: persona)
        } catch {
            throw ErrorDeConexion(error.localizedDescription)
        }
        await c.motor?.host?.ajustesCambiaron()
        c.actualizarHuecos()
        if activo { await c.leerCorreo() } else { c.sesion.map { ConexionesEnDecisiones.de($0).poner([], origen: "mail") } }
    }

    // MARK: Calendario

    public func estadoDelCalendario() async -> CalendarioConexion {
        guard let c = conexiones, let cal = c.calendario else { return .sinConectar }
        let permiso = cal.estadoDelPermiso()
        if permiso.necesitaRecuperacion { return .sinPermiso(Self.recuperacion(TarjetaDePermiso.de(.calendarios))) }
        if await cal.conectado() { return .conectado(resumen: resumenDelCalendario(c)) }
        return .sinConectar
    }

    /// «2 rituales y 3 sesiones», con lo que hay ahora en el calendario.
    func resumenDelCalendario(_ c: ConexionesDeEmpresa) -> String? {
        guard let filas = try? c.mapa?.activas() else { return nil }
        let rutinas = filas.filter { $0.tipo == "rutina" && $0.eventoID != nil }.count
        let sesiones = filas.filter { $0.tipo == "sesion" && $0.eventoID != nil }.count
        guard rutinas + sesiones > 0 else { return "aún sin rituales: marca uno con «Al Calendario» en su ficha" }
        var partes: [String] = []
        if rutinas > 0 { partes.append(rutinas == 1 ? "1 ritual" : "\(rutinas) rituales") }
        if sesiones > 0 { partes.append(sesiones == 1 ? "1 sesión con clientes" : "\(sesiones) sesiones con clientes") }
        return partes.joined(separator: " y ")
    }

    public func conectarCalendario() async -> CalendarioConexion {
        guard let c = try? c(), let cal = c.calendario else { return .fallo("En el ejemplo, el Calendario no se conecta.") }
        do {
            let inf = try await cal.conectar()
            if let t = inf.tarjetaDePermiso { return .sinPermiso(Self.recuperacion(t)) }
            if case .sinConectar = inf.estado { return .sinConectar }
        } catch {
            return .fallo("No he podido crear el calendario «The Last System»: \(error.localizedDescription)")
        }
        // La rutina semanal de Dirección pasa a ir al Calendario (como tú; se deshace), si aún no iba.
        if let plan = await cal.planDeLaPuesta(foto: await c.piezas.foto(), persona: c.piezas.persona) {
            _ = try? await c.sesion?.escribirComoPersona(plan, aviso: "Tu revisión semanal irá también a tu Calendario.")
        }
        await c.sincronizarCalendario()
        return .conectado(resumen: resumenDelCalendario(c))
    }

    public func desconectarCalendario() async throws {
        guard let c = try? c(), let cal = c.calendario else { throw ErrorDeConexion("En el ejemplo, el Calendario no se conecta.") }
        do {
            try await cal.desconectar()
        } catch {
            throw ErrorDeConexion("No he podido desconectar el Calendario. Vuelve a intentarlo.")
        }
        await c.sincronizarCalendario()
        c.sesion.map { ConexionesEnDecisiones.de($0).poner([], origen: "calendario") }
    }

    // MARK: Otros programas

    public nonisolated func plantillas() -> [PlantillaDeOtroPrograma] {
        PlantillasDeSerie.todas.map { p in
            let clave = p.campos.first(where: \.secreto).map { CampoDeClave(etiqueta: $0.etiqueta, ayuda: $0.ayuda) }
            return PlantillaDeOtroPrograma(id: p.id, nombre: p.nombre, explicacion: p.explicacion, direccionDeEjemplo: p.direccionDeEjemplo,
                                           clave: clave, permisos: p.permisos.map { $0.texto(conexion: p.nombre) })
        }
    }

    public func otrosProgramas() async -> [OtroProgramaConexion] {
        guard let c = conexiones else { return [] }
        return c.pasarela.conexiones().map { x in
            let estado: EstadoDeOtroPrograma
            if !x.activa { estado = .pausado } else if let e = errores[x.id] { estado = .error(e) }
            else if x.catalogo == nil { estado = .sinProbar } else { estado = .conectado }
            let hs = x.catalogo?.herramientas ?? []
            return OtroProgramaConexion(id: x.id, nombre: x.nombre, plantilla: x.plantilla, estado: estado,
                                        activas: hs.filter { $0.estado == .activa }.count,
                                        porRevisar: hs.filter { $0.estado == .pendienteDeRevision }.count,
                                        ultimaSincronizacion: x.ultimaSincronizacion, local: x.transporte.esStdio,
                                        simulado: c.ejemplo)
        }
    }

    public func anadir(_ alta: AltaDeOtroPrograma) async throws {
        let c = try c()
        let clave = alta.clave?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let transporte: TransporteDeConexion
        switch alta.transporte {
        case .web(let d):
            transporte = .http(clave.isEmpty ? HTTPDeConexion(url: d, cabecera: nil, campo: nil) : HTTPDeConexion(url: d))
        case .local(let e, let args, let aceptado):
            guard clave.isEmpty else { throw ErrorDeConexion("Un programa de este Mac no recibe claves en esta versión.") }
            transporte = .stdio(StdioDeConexion(ejecutable: e, argumentos: args, avisoAceptado: aceptado))
        }
        do {
            try await c.pasarela.anadir(id: alta.id, nombre: alta.nombre, plantilla: alta.plantilla, transporte: transporte,
                                        secretos: clave.isEmpty ? [:] : ["token": clave], autor: persona)
        } catch {
            throw ErrorDeConexion(error.localizedDescription)
        }
    }

    public func probar(_ id: String) async throws -> String {
        let c = try c()
        do {
            let cambios = try await c.pasarela.conectar(id)
            errores[id] = nil
            c.ponerRevisiones()
            let hs = (c.pasarela.almacen.conexion(id)?.catalogo?.herramientas ?? []).filter { $0.estado != .retirada }
            let lee = hs.filter { $0.clase == .lectura }.count
            var texto = "Responde. Trae \(hs.count == 1 ? "1 herramienta" : "\(hs.count) herramientas"): "
                + "\(lee) solo \(lee == 1 ? "lee" : "leen") y \(hs.count - lee) \(hs.count - lee == 1 ? "pide" : "piden") tu OK."
            if !cambios.primeraVez, !cambios.paraRevisar.isEmpty {
                texto += " \(cambios.paraRevisar.count == 1 ? "Hay 1 nueva o cambiada" : "Hay \(cambios.paraRevisar.count) nuevas o cambiadas") por revisar."
            }
            return texto
        } catch {
            let t = error.localizedDescription
            errores[id] = t
            throw ErrorDeConexion(t)
        }
    }

    public func interruptores(_ id: String) async -> [InterruptorDeOtroPrograma] {
        guard let c = conexiones, let x = c.pasarela.almacen.conexion(id) else { return [] }
        let config = c.piezas.autorizador.estadoDeConfig().efectiva
        return Interruptores.filas(x, config: config).map {
            InterruptorDeOtroPrograma(id: $0.id, texto: $0.texto, encendido: $0.encendido, disponible: $0.disponible,
                                      asistenteActivo: $0.asistenteActivo, lectura: $0.permiso.lectura, herramientas: $0.herramientas)
        }
    }

    public func cambiarInterruptor(_ id: String, permiso: String, encender: Bool) async throws {
        let c = try c()
        guard let x = c.pasarela.almacen.conexion(id),
              let p = PlantillasDeSerie.plantilla(x.plantilla).permisos.first(where: { $0.id == permiso }) else {
            throw ErrorDeConexion("Ese interruptor ya no está.")
        }
        guard let a = c.piezas.autorizador.estadoDeConfig().efectiva.asistente(p.asistente) else {
            throw ErrorDeConexion("\(AsistenteConfigurado.nombre(de: p.asistente)) no está en esta empresa.")
        }
        let b = Interruptores.aplicar(p, encender: encender, en: x, a: a)
        do {
            _ = try await EditorConfigAgentes.aplicar(.asistente(b), bus: c.piezas.bus, autor: persona)
        } catch {
            throw ErrorDeConexion(error.localizedDescription)
        }
        await c.motor?.host?.ajustesCambiaron()
    }

    public func revisiones() async -> [RevisionDeOtroPrograma] {
        guard let c = conexiones else { return [] }
        return c.pasarela.tarjetasDeRevision().map { t in
            RevisionDeOtroPrograma(id: t.id, conexion: t.conexion, nombreConexion: t.nombreConexion, titulo: t.titulo,
                                   herramientas: t.herramientas.map {
                                       HerramientaNueva(nombre: $0.nombre, descripcion: $0.descripcion, clase: $0.clase.texto,
                                                        motivo: $0.motivo.texto, sensible: $0.clase == .sensible)
                                   })
        }
    }

    public func revisar(_ r: RevisionDeOtroPrograma, aceptar: Bool) async throws {
        let c = try c()
        do {
            try await c.revisar(r.conexion, herramientas: r.herramientas.map(\.nombre), aceptar: aceptar)
        } catch {
            throw ErrorDeConexion(error.localizedDescription)
        }
    }

    public func sincronizarAhora(_ id: String) async throws -> String {
        let c = try c()
        do {
            let i = try await c.sincronizarConexion(id)
            return i.resumen.isEmpty ? "Sin novedades." : i.resumen.prefix(1).uppercased() + i.resumen.dropFirst() + "."
        } catch let e as ErrorDeConexion {
            throw e
        } catch {
            throw ErrorDeConexion(error.localizedDescription)
        }
    }

    public func pausar(_ id: String, _ pausado: Bool) async throws {
        let c = try c()
        do { try await c.pasarela.activar(id, !pausado, autor: persona) } catch { throw ErrorDeConexion(error.localizedDescription) }
    }

    public func quitar(_ id: String) async throws {
        let c = try c()
        do { try await c.pasarela.quitar(id, autor: persona) } catch { throw ErrorDeConexion(error.localizedDescription) }
        errores[id] = nil
        c.sesion.map { ConexionesEnDecisiones.de($0).poner([], origen: "pasarela:\(id)") }
    }

    public func matriz(_ id: String) async -> [FilaDeMatrizConexion] {
        guard let c = conexiones, let x = c.pasarela.almacen.conexion(id) else { return [] }
        return MatrizTecnica.filas(x, config: c.piezas.autorizador.estadoDeConfig().efectiva).map {
            FilaDeMatrizConexion(expuesta: $0.expuesta, nombre: $0.nombre, clase: $0.clase.texto, motivo: $0.motivo.texto,
                                 estado: $0.estado.texto, huellaCorta: String($0.huella.prefix(8)), asistentes: $0.asistentes)
        }
    }
}
