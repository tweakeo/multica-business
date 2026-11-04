import Foundation
import TLSCore
import TLSImport
import TLSUI

// F3 · rol ordenar. Lo que une el paso 2 de la puesta en marcha (motor, TLSCore) con «Ordenar lo que tienes» (TLSUI):
// un `ModeloOrdenar` por carpeta mientras dura la ventana (las pantallas del paso lo comparten), cómo escribe (por la
// sesión abierta de la empresa o con un escritor propio), la ayuda opcional de Claude Code y lo que se le cuenta al motor
// (`registrarOrdenar`: sus pantallas para el contador, sus planes para «Deshacer» hasta el paso 3).

@MainActor
public enum ConexionOrdenar {
    private static var modelos: [UUID: ModeloOrdenar] = [:]

    /// Busca el Claude Code de la persona para «Ayúdame con los dudosos». Solo se llama con su consentimiento
    /// (`usarAsistente`). En las pruebas se cambia por uno falso: nunca se lanza Claude.
    public static var buscarClaude: @MainActor (ModeloPuesta, AccesoEmpresa) async -> (any EjecutorClasificacion)? = { puesta, acceso in
        await claudeDeVerdad(puesta, acceso)
    }

    /// El modelo del paso 2 de esta puesta en marcha (lo crea la primera vez). `nil` si aún no hay carpeta.
    public static func modelo(para puesta: ModeloPuesta, app: AppModel?) -> ModeloOrdenar? {
        let id = puesta.motor.estado.vaultID
        let ruta = rutaOrdenar(puesta.ruta)
        if let m = modelos[id], m.ruta == ruta { return m }
        guard let acceso = acceso(para: puesta, app: app) else { return nil }
        let m = ModeloOrdenar(acceso: acceso, ruta: ruta, hoy: puesta.motor.contexto.hoy)
        // Repasar la puesta en marcha (el ejemplo) solo mira: no se escribe ni se marca nada.
        m.soloMirar = puesta.repasando
        modelos[id] = m
        return m
    }

    /// La pantalla del paso que corresponde a la del motor (por su título; si no, por su número).
    public static func pantalla(para puesta: ModeloPuesta, ordenar: ModeloOrdenar) -> PantallaOrdenar {
        let disponibles = ordenar.pantallas
        if let t = puesta.pantalla?.titulo, let p = PantallaOrdenar(rawValue: t), disponibles.contains(p) { return p }
        if let id = puesta.pantalla?.id, let n = Int(id.split(separator: ".").last ?? ""), n >= 1, n <= disponibles.count {
            return disponibles[n - 1]
        }
        return disponibles.first ?? .loQueHay
    }

    /// En la vista previa y en «Completar las fichas», mientras haya algo por aplicar, el botón del pie es «Aplicar»
    /// (y no «Siguiente», que avanzaba sin aplicar). `nil` si no toca.
    public static func porAplicar(_ puesta: ModeloPuesta) -> ModeloOrdenar? {
        guard !puesta.repasando, puesta.pantalla?.paso == .ordenar, puesta.motor.estado.paso(.ordenar).fase == .pendiente,
              let o = modelo(para: puesta, app: puesta.entorno.app), !o.cerrado, !o.soloMirar,
              [.vistaPrevia, .completarFichas].contains(pantalla(para: puesta, ordenar: o)) else { return nil }
        // Sin vista previa aún (se está preparando o algo falló), o con algo que hacer: «Aplicar», desactivado con su motivo
        // mientras falte. Sin nada que hacer, «Siguiente».
        guard o.vista?.hayCambios ?? true else { return nil }
        return o
    }

    /// Si la empresa se ha abierto en una ventana, mejor escribir por su sesión (mismo escritor, ⌘Z y avisos).
    static func preferirSesion(_ m: ModeloOrdenar, app: AppModel?) {
        let id = m.acceso.entry.id
        if m.acceso.sesion == nil, let s = app?.sesionAbierta(id), s.puedeEscribir, let a = AccesoEmpresa(sesion: s) {
            m.cambiarAcceso(a)
        }
    }

    /// Para las pruebas y las capturas: un modelo ya hecho para una carpeta.
    public static func registrar(_ m: ModeloOrdenar, para id: UUID) { modelos[id] = m }

    /// Al cerrar la ventana de la puesta en marcha (o en las pruebas).
    public static func olvidar(_ id: UUID) { modelos[id] = nil }

    static func rutaOrdenar(_ r: RutaPuesta) -> RutaOrdenar { r == .carpetaPorOrdenar ? .ordenar : .completar }

    /// Por la sesión abierta de la empresa o, si no hay, con un escritor propio sobre la carpeta de la puesta en marcha.
    static func acceso(para puesta: ModeloPuesta, app: AppModel?) -> AccesoEmpresa? {
        let id = puesta.motor.estado.vaultID
        if let s = (app ?? puesta.entorno.app)?.sesionAbierta(id), let a = AccesoEmpresa(sesion: s) { return a }
        let entrada = puesta.motor.contexto.entrada.flatMap { $0.id == id ? $0 : nil }
            ?? puesta.registro.load().first { $0.id == id }
        guard let entrada else { return nil }
        let raiz = puesta.motor.contexto.foto?.root ?? puesta.registro.resolveURL(entrada)
        guard let raiz, entrada.clase != .real else { return nil }
        return AccesoEmpresa(entry: entrada, raiz: raiz, appSupport: puesta.motor.almacen?.appSupport ?? puesta.appSupport,
                             persona: puesta.motor.estado.persona)
    }

    /// Le cuenta al motor cómo va el paso 2: sus pantallas (para el contador y «Quedan ~N min») y, si escribió algo, sus
    /// planes (el paso queda aplicado, con «Deshacer» hasta el paso 3). Si no hay nada que hacer, el paso queda hecho
    /// sin escribir («Nada que ordenar»); si se deshizo todo, o ahora sí hay algo que aplicar, vuelve a estar pendiente.
    public static func sincronizar(_ puesta: ModeloPuesta, _ ordenar: ModeloOrdenar) {
        guard !puesta.repasando else { return }
        let r = ordenar.resumenPuesta()
        let antes = puesta.motor.estado.ordenar
        let fase = puesta.motor.estado.paso(.ordenar).fase
        if ordenar.aplicado {
            if antes != r || fase != .aplicado { puesta.actualizar { $0.registrarOrdenar(r, aplicado: true) } }
            return
        }
        let nadaQueHacer = ordenar.vista.map { !$0.hayCambios } ?? false
        if fase == .aplicado, ordenar.deshizo || (ordenar.vista != nil && !nadaQueHacer) {
            puesta.actualizar { m in
                m.marcarDeshecho(.ordenar)
                m.registrarOrdenar(r, aplicado: false)
            }
            return
        }
        if fase == .pendiente, nadaQueHacer, !ordenar.cerrado {
            puesta.actualizar { $0.registrarOrdenar(r, aplicado: true) }
            return
        }
        if antes?.titulos != r.titulos || antes?.pantallas != r.pantallas {
            puesta.actualizar { $0.registrarOrdenar(r, aplicado: false) }
        }
    }

    /// Claude Code de verdad (el detector de la puesta en marcha: `ClaudeLocator` y `LanzadorClaudeCode`, dentro del
    /// sandbox de los asistentes, sesión efímera, `--json-schema`, sin servidores ni herramientas). La carpeta de la
    /// empresa y la original quedan negadas: solo le llega lo que manda el clasificador. Sin consentimiento, nada.
    static func claudeDeVerdad(_ puesta: ModeloPuesta, _ acceso: AccesoEmpresa) async -> (any EjecutorClasificacion)? {
        guard puesta.motor.estado.usarAsistente == true else { return nil }
        if let l = puesta.motor.entrevista.lanzador as? any EjecutorClasificacion { return l }
        var negadas = [acceso.raiz]
        if let origen = acceso.entry.origen { negadas.append(URL(fileURLWithPath: origen, isDirectory: true)) }
        return await puesta.entorno.detectorClaude.lanzador(estado: acceso.estado, negadas: negadas) as? any EjecutorClasificacion
    }
}
