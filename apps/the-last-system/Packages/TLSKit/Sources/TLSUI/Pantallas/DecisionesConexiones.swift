import AppKit
import Foundation
import os
import SwiftUI
import TLSCore
import TLSDesign

// F5 · rol buzon-relevo. Las tarjetas nuevas de Decisiones que llegan de las conexiones (PLAN §7 y §9 F5):
// - permiso denegado (Mail o Calendario): qué pasa, cómo arreglarlo y «Abrir Ajustes del Sistema»;
// - «¿Actualizo la ficha?» por un evento que cambiaste en Calendario, con la diferencia campo a campo;
// - «Revisar herramientas nuevas de <programa>»: llegan desactivadas hasta que las revisas.
// Y los huecos del ejecutor de aprobaciones de esta empresa (correo y otros programas), para que «Para aprobar» diga la
// verdad: con Mail conectado, «Se abrirá en Mail para que tú lo envíes»; tras abrirlo, «Abierto en Mail».
//
// TLSUI no depende de TLSIntegrations ni de TLSGateway: la integración traduce `TarjetaDePermiso`, `TarjetaCalendario` y
// `TarjetaDeRevision` a `TarjetaDeConexion` y las pone aquí con sus acciones (docs/F5-CONTRATOS.md, «Cambios pedidos ›
// buzon-relevo»). Nada de este fichero envía, invita ni llama a nadie: las acciones las da quien pone la tarjeta.

/// Una fila de la diferencia entre la ficha y Calendario («Hora: 10:00 → 11:30»).
public struct DiferenciaDeConexion: Sendable, Hashable, Identifiable {
    /// Nombre · Cuándo · Hora · Duración.
    public let campo: String
    public let enFicha: String
    public let enCalendario: String

    public var id: String { campo }

    public init(campo: String, enFicha: String, enCalendario: String) {
        self.campo = campo; self.enFicha = enFicha; self.enCalendario = enCalendario
    }
}

/// Una herramienta nueva o cambiada de otro programa, tal como se enseña al revisarla.
public struct HerramientaDeLaTarjeta: Sendable, Hashable, Identifiable {
    /// Nombre visible («Crear contacto»).
    public let nombre: String
    /// Lo que dice el programa que hace (recortado).
    public let descripcion: String?
    /// Cambia cosas allí (pedirá tu OK cada vez) o solo lee.
    public let cambiaCosas: Bool
    /// Por qué se clasifica así (`MotivoDeClase.texto`).
    public let motivo: String
    /// «Nueva», «Cambiada», «Desactivada hasta que la revises» (`EstadoHerramienta.texto`).
    public let estado: String

    public var id: String { nombre }

    public init(nombre: String, descripcion: String? = nil, cambiaCosas: Bool, motivo: String, estado: String) {
        self.nombre = nombre; self.descripcion = descripcion; self.cambiaCosas = cambiaCosas; self.motivo = motivo
        self.estado = estado
    }
}

/// Un botón de una tarjeta: lo que hace lo pone quien crea la tarjeta. Devuelve lo que se le dice a la persona.
public struct AccionDeConexion: Sendable {
    public let titulo: String
    public let hacer: @MainActor @Sendable () async throws -> String

    public init(_ titulo: String, hacer: @escaping @MainActor @Sendable () async throws -> String) {
        self.titulo = titulo; self.hacer = hacer
    }
}

/// Una tarjeta de Decisiones que llega de una conexión.
public struct TarjetaDeConexion: Sendable, Identifiable {
    public enum Clase: String, Sendable, Hashable {
        /// Mail o Calendario sin permiso (`TarjetaDePermiso`).
        case permiso
        /// Un evento cambiado o quitado en Calendario (`TarjetaCalendario`).
        case calendario
        /// Herramientas nuevas o cambiadas de otro programa (`TarjetaDeRevision`).
        case herramientas
    }

    /// Estable (`permiso:<permiso>`, el de la tarjeta de Calendario, `conexion-revisar:<id>:<huella>`).
    public let id: String
    public let clase: Clase
    /// De dónde viene, para poder sustituirlas de una vez: «mail», «calendario», «pasarela:<id>».
    public let origen: String
    public let titulo: String
    public let texto: String
    /// Pasos para arreglarlo (permisos).
    public var pasos: [String] = []
    public var diferencias: [DiferenciaDeConexion] = []
    public var herramientas: [HerramientaDeLaTarjeta] = []
    /// La ficha a la que se refiere (rutina o proyecto).
    public var ruta: VaultPath?
    /// Solo para «Detalle técnico» (nunca en el texto principal).
    public var detalleTecnico: String?
    public let principal: AccionDeConexion
    public var secundaria: AccionDeConexion?

    public init(id: String, clase: Clase, origen: String, titulo: String, texto: String, pasos: [String] = [],
         diferencias: [DiferenciaDeConexion] = [], herramientas: [HerramientaDeLaTarjeta] = [], ruta: VaultPath? = nil,
         detalleTecnico: String? = nil, principal: AccionDeConexion, secundaria: AccionDeConexion? = nil) {
        self.id = id; self.clase = clase; self.origen = origen; self.titulo = titulo; self.texto = texto; self.pasos = pasos
        self.diferencias = diferencias; self.herramientas = herramientas; self.ruta = ruta; self.detalleTecnico = detalleTecnico
        self.principal = principal; self.secundaria = secundaria
    }

    /// F5 · integración: el programa de una tarjeta de herramientas (para la nota común con Conexiones).
    public var programa: String?

    /// El rótulo del grupo en Decisiones.
    public var rotulo: String {
        switch clase {
        case .permiso: "Permiso del Mac"
        case .calendario: "Calendario"
        case .herramientas: "Otros programas"
        }
    }

    public var icono: String {
        switch clase {
        case .permiso: "lock.shield"
        case .calendario: "calendar.badge.exclamationmark"
        case .herramientas: "puzzlepiece.extension"
        }
    }

    /// Para «¿Actualizo la ficha?»: la pregunta que se hace.
    public var pregunta: String? {
        switch clase {
        case .calendario: diferencias.isEmpty ? nil : "¿Actualizo la ficha?"
        case .herramientas: "¿Las activo?"
        case .permiso: nil
        }
    }

    // MARK: Fábricas (las usa la integración con los datos de TLSIntegrations y TLSGateway)

    /// Permiso denegado (Mail o Calendario): `TarjetaDePermiso` → tarjeta. El botón abre Ajustes del Sistema.
    public static func permiso(id: String, titulo: String, texto: String, pasos: [String], boton: String = "Abrir Ajustes del Sistema",
                        enlace: URL?, detalleTecnico: String? = nil, origen: String) -> TarjetaDeConexion {
        TarjetaDeConexion(
            id: id, clase: .permiso, origen: origen, titulo: titulo, texto: texto, pasos: pasos, detalleTecnico: detalleTecnico,
            principal: AccionDeConexion(boton) {
                // F5 · integración: por la app (en pruebas no se abre nada).
                if let enlace { ConexionesDeLaApp.abrirEnlace(enlace) }
                return "Cuando lo cambies en Ajustes del Sistema, vuelve aquí: la app lo comprueba sola."
            })
    }

    /// «Cambiaste «X» en Calendario»: «Actualizar la ficha» (el plan va por el escritor como tú) o «Dejar la ficha como
    /// está» (el evento vuelve a lo de la ficha).
    public static func calendario(id: String, titulo: String, texto: String, diferencias: [DiferenciaDeConexion], ruta: VaultPath?,
                           boton: String = "Actualizar la ficha", botonNo: String? = "Dejar la ficha como está",
                           hacer: @escaping @MainActor @Sendable () async throws -> String,
                           noHacer: (@MainActor @Sendable () async throws -> String)? = nil) -> TarjetaDeConexion {
        TarjetaDeConexion(id: id, clase: .calendario, origen: "calendario", titulo: titulo, texto: texto,
                          diferencias: diferencias, ruta: ruta, principal: AccionDeConexion(boton, hacer: hacer),
                          secundaria: botonNo.flatMap { b in noHacer.map { AccionDeConexion(b, hacer: $0) } })
    }

    /// «Revisar herramientas nuevas de <programa>»: «Activarlas» o «Dejarlas desactivadas».
    public static func herramientas(id: String, programa: String, conexion: String, texto: String,
                             herramientas: [HerramientaDeLaTarjeta],
                             activar: @escaping @MainActor @Sendable () async throws -> String,
                             dejar: @escaping @MainActor @Sendable () async throws -> String) -> TarjetaDeConexion {
        var t = TarjetaDeConexion(id: id, clase: .herramientas, origen: "pasarela:\(conexion)",
                                  titulo: "Revisar herramientas nuevas de \(programa)", texto: texto, herramientas: herramientas,
                                  principal: AccionDeConexion("Activarlas", hacer: activar),
                                  secundaria: AccionDeConexion("Dejarlas desactivadas", hacer: dejar))
        t.programa = programa
        return t
    }
}

/// Textos comunes de «Revisar herramientas nuevas» (Conexiones y Decisiones enseñan la misma pieza).
enum TextosRevisionHerramientas {
    static func nota(_ programa: String) -> String {
        "Activarlas no da permiso a ningún asistente: eso lo decides en los interruptores de \(programa), en Ajustes › Conexiones."
    }
}

/// Correo y otros programas de esta empresa para `Aprobaciones`, intercambiables en marcha: la integración pone
/// `MailComposer` y `GatewayRouter` cuando se conectan y los quita al desconectar. Sin nada, lo de F4 (queda «Listo
/// para enviar»; otro programa, aprobado sin salir).
public final class HuecosDeAprobacion: Sendable {
    private let estado = OSAllocatedUnfairLock<(correo: (any ProtocoloDeCorreo)?, pasarela: (any ProtocoloDePasarela)?)>(
        initialState: (nil, nil))

    public init() {}

    public var correo: (any ProtocoloDeCorreo)? {
        get { estado.withLock { $0.correo } }
        set { estado.withLock { $0.correo = newValue } }
    }

    public var pasarela: (any ProtocoloDePasarela)? {
        get { estado.withLock { $0.pasarela } }
        set { estado.withLock { $0.pasarela = newValue } }
    }

    /// El ejecutor que reparte en cada aprobación a lo que esté conectado en ese momento.
    public var ejecutor: EjecutorDeAprobaciones {
        EjecutorDeAprobaciones(correo: CorreoPorHueco(huecos: self), pasarela: PasarelaPorHueco(huecos: self))
    }

    struct CorreoPorHueco: ProtocoloDeCorreo {
        let huecos: HuecosDeAprobacion
        func preparar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
            try await (huecos.correo ?? CorreoSinConexion()).preparar(a)
        }
    }

    struct PasarelaPorHueco: ProtocoloDePasarela {
        let huecos: HuecosDeAprobacion
        func llamar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
            try await (huecos.pasarela ?? PasarelaSinConexion()).llamar(a)
        }
    }

    /// ¿Abre la redacción de Mail al aprobar un correo? (Mail conectado).
    static func abreMail(_ ejecutor: EjecutorDeAprobaciones) -> Bool {
        if let h = ejecutor.correo as? CorreoPorHueco { return h.huecos.correo != nil }
        return !(ejecutor.correo is CorreoSinConexion)
    }
}

/// Las tarjetas de las conexiones de una empresa abierta, y sus huecos de aprobación. Una por sesión.
@MainActor
@Observable
public final class ConexionesEnDecisiones {
    public private(set) var tarjetas: [TarjetaDeConexion] = []
    /// Lo que se le dijo a la persona tras pulsar un botón (por tarjeta).
    public private(set) var hechas: [String: String] = [:]
    public private(set) var errores: [String: String] = [:]
    private(set) var trabajando: Set<String> = []
    @ObservationIgnored public let huecos = HuecosDeAprobacion()

    /// F5 · integración: la empresa de estas tarjetas (para la insignia de Decisiones en la barra lateral).
    @ObservationIgnored private weak var sesion: VaultSession?

    private final class Entrada {
        weak var sesion: VaultSession?
        let valor: ConexionesEnDecisiones
        init(_ s: VaultSession, _ v: ConexionesEnDecisiones) { sesion = s; valor = v }
    }

    private static var porSesion: [ObjectIdentifier: Entrada] = [:]

    public static func de(_ sesion: VaultSession) -> ConexionesEnDecisiones {
        porSesion = porSesion.filter { $0.value.sesion != nil }
        let k = ObjectIdentifier(sesion)
        if let e = porSesion[k], e.sesion === sesion { return e.valor }
        let v = ConexionesEnDecisiones()
        v.sesion = sesion
        porSesion[k] = Entrada(sesion, v)
        return v
    }

    public init() {}

    /// Sustituye las tarjetas de un origen («mail», «calendario», «pasarela:<id>») por estas. Las que ya se decidieron
    /// en esta sesión no vuelven aunque la integración las repita antes de enterarse.
    public func poner(_ nuevas: [TarjetaDeConexion], origen: String) {
        let validas = nuevas.filter { $0.origen == origen && hechas[$0.id] == nil }
        var vistas = Set<String>()
        tarjetas = tarjetas.filter { $0.origen != origen } + validas.filter { vistas.insert($0.id).inserted }
        cambiaron()
    }

    public func quitar(_ id: String) {
        tarjetas.removeAll { $0.id == id }
        cambiaron()
    }

    /// La insignia de Decisiones (barra lateral) cuenta también estas.
    private func cambiaron() {
        if let sesion { AlmacenHoy.de(sesion).refrescarInsignia() }
    }

    /// Las pendientes (sin decidir), en orden: permisos, Calendario y otros programas.
    public var pendientes: [TarjetaDeConexion] {
        let orden: [TarjetaDeConexion.Clase] = [.permiso, .calendario, .herramientas]
        return tarjetas.filter { hechas[$0.id] == nil }
            .sorted { (orden.firstIndex(of: $0.clase) ?? 9, $0.id) < (orden.firstIndex(of: $1.clase) ?? 9, $1.id) }
    }

    /// Pulsa un botón de una tarjeta. Si sale bien, la tarjeta queda resuelta con el texto que devuelve (los permisos
    /// no: siguen hasta que la app vea el permiso concedido).
    @discardableResult
    public func pulsar(_ t: TarjetaDeConexion, principal: Bool = true) async -> Bool {
        guard let accion = principal ? t.principal : t.secundaria, !trabajando.contains(t.id) else { return false }
        trabajando.insert(t.id)
        defer { trabajando.remove(t.id) }
        do {
            let texto = try await accion.hacer()
            errores[t.id] = nil
            if t.clase == .permiso {
                avisos[t.id] = texto
            } else {
                hechas[t.id] = texto
                tarjetas.removeAll { $0.id == t.id }
                ultimas.insert(t, at: 0)
                cambiaron()
            }
            return true
        } catch {
            errores[t.id] = error.localizedDescription
            return false
        }
    }

    /// Lo último que se dijo en una tarjeta de permiso (sigue a la vista).
    private(set) var avisos: [String: String] = [:]
    /// Las decididas en esta sesión (para enseñar «Hecho: …» un momento).
    private(set) var ultimas: [TarjetaDeConexion] = []
}

// MARK: - Acción externa sensible, legible

/// Lo que guarda un borrador `accion: externa` en «Mensaje» (`PeticionExterna` de TLSGateway, JSON canónico) leído para
/// enseñar **literalmente qué se manda y a quién**, sin huellas ni nombres técnicos fuera de «Detalle técnico».
struct PeticionExternaLegible: Sendable, Hashable {
    /// `ext_<conexión>_<herramienta>`.
    let herramienta: String
    let conexion: String?
    /// «Mandar un SMS» (en llano: verbo y objeto; `NombresLlanos`).
    let accion: String
    /// Los datos tal cual, en el orden de las claves (`clave` es la original; `etiqueta`, en llano).
    let datos: [(clave: String, valor: String)]
    /// El nombre de la herramienta en el otro programa (`send_sms`): solo para «Detalle técnico».
    var nombreOriginal: String = ""

    /// «Mandar un SMS desde GoHighLevel».
    func titulo(programa: String?) -> String { programa.map { accion + " desde " + $0 } ?? accion }

    static func etiqueta(_ clave: String) -> String { NombresLlanos.dato(clave) }

    static func == (a: Self, b: Self) -> Bool {
        a.herramienta == b.herramienta && a.datos.map(\.clave) == b.datos.map(\.clave) && a.datos.map(\.valor) == b.datos.map(\.valor)
    }

    func hash(into h: inout Hasher) {
        h.combine(herramienta)
        for d in datos { h.combine(d.clave); h.combine(d.valor) }
    }

    /// `nil` si el texto no es una petición (p. ej. se editó a mano y ya no es JSON).
    static func leer(_ texto: String) -> PeticionExternaLegible? {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
                .filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        guard let o = (try? JSONSerialization.jsonObject(with: Data(t.utf8))) as? [String: Any],
              let h = o["herramienta"] as? String, h.hasPrefix("ext_") else { return nil }
        let args = o["argumentos"] as? [String: Any] ?? [:]
        let resto = h.dropFirst(4)
        let conexion = resto.split(separator: "_", maxSplits: 1).first.map(String.init)
        let nombre = resto.split(separator: "_", maxSplits: 1).dropFirst().first.map(String.init) ?? String(resto)
        return PeticionExternaLegible(herramienta: h, conexion: conexion, accion: NombresLlanos.accion(nombre),
                                      datos: args.keys.sorted().map { ($0, valor(args[$0] as Any)) }, nombreOriginal: nombre)
    }

    /// `send_message` / `createContact` → «Send message» / «Create contact» (sin traducir: es el nombre del programa).
    static func legible(_ s: String) -> String {
        var palabras: [String] = []
        var actual = ""
        for ch in s {
            if ch == "_" || ch == "-" || ch == " " {
                if !actual.isEmpty { palabras.append(actual); actual = "" }
            } else if ch.isUppercase, let u = actual.last, u.isLowercase {
                palabras.append(actual); actual = String(ch)
            } else {
                actual.append(ch)
            }
        }
        if !actual.isEmpty { palabras.append(actual) }
        let t = palabras.map { $0.lowercased() }.joined(separator: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Un valor JSON en una línea legible.
    static func valor(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "sí" : "no" }
            return n.stringValue
        case let a as [Any]: return a.map(valor).joined(separator: ", ")
        case is NSNull: return "—"
        default:
            if let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes]) {
                return String(decoding: d, as: UTF8.self)
            }
            return "\(v)"
        }
    }
}

// MARK: - Vistas

/// «De tus conexiones» en Decisiones: lo que piden Mail, Calendario y los otros programas. No sale si no hay nada.
struct SeccionConexionesDecisiones: View {
    let sesion: VaultSession

    var body: some View {
        let c = ConexionesEnDecisiones.de(sesion)
        let lista = c.pendientes
        if !lista.isEmpty || !c.ultimas.isEmpty {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                HStack(spacing: 8) {
                    Text("De tus conexiones").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    if !lista.isEmpty {
                        InsigniaAviso(lista.count, palabra: lista.count == 1 ? "espera tu decisión" : "esperan tu decisión")
                    }
                }
                ForEach(lista) { t in TarjetaDeConexionVista(tarjeta: t, sesion: sesion) }
                ForEach(c.ultimas.prefix(3)) { t in
                    if let h = c.hechas[t.id] { AvisoEnLinea("\(t.titulo): \(h)", estado: .bien) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("decisiones.grupo.conexiones")
        }
    }
}

/// Una tarjeta de una conexión, con sus botones.
struct TarjetaDeConexionVista: View {
    let tarjeta: TarjetaDeConexion
    let sesion: VaultSession
    @State private var verTecnico = false
    @Environment(\.navegar) private var navegar

    private var c: ConexionesEnDecisiones { ConexionesEnDecisiones.de(sesion) }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tarjeta.icono)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tarjeta.clase == .permiso ? TLSPaleta.atencion.color : TLSPaleta.principal.color)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TLSPaleta.principalSuave.color))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Rotulo(tarjeta.rotulo)
                    Text(tarjeta.titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tarjeta.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !tarjeta.diferencias.isEmpty { TablaDiferenciasCalendario(diferencias: tarjeta.diferencias) }
            if !tarjeta.herramientas.isEmpty {
                ListaHerramientasPorRevisar(herramientas: tarjeta.herramientas)
                if let p = tarjeta.programa {
                    Text(TextosRevisionHerramientas.nota(p)).tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !tarjeta.pasos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(tarjeta.pasos.enumerated()), id: \.offset) { i, p in
                        Text("\(i + 1). \(p)").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let p = tarjeta.pregunta {
                Text(p).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
            }
            if let e = c.errores[tarjeta.id] { AvisoEnLinea(e, estado: .mal) }
            if let a = c.avisos[tarjeta.id] { AvisoEnLinea(a, estado: .sinDato) }
            FlujoChips(espacio: 8) {
                Button(tarjeta.principal.titulo) { Task { await c.pulsar(tarjeta) } }
                    .tlsBoton(.principal)
                    .disabled(c.trabajando.contains(tarjeta.id) || (tarjeta.clase == .calendario && !sesion.puedeEscribir))
                    .accessibilityIdentifier("conexion.principal")
                if let s = tarjeta.secundaria {
                    Button(s.titulo) { Task { await c.pulsar(tarjeta, principal: false) } }
                        .tlsBoton(.secundario)
                        .disabled(c.trabajando.contains(tarjeta.id))
                        .accessibilityIdentifier("conexion.secundaria")
                }
                if let r = tarjeta.ruta {
                    Button("Abrir la ficha") { navegar(sesion.destino(para: r), modo: .automatico) }.tlsBoton(.enlace)
                }
                if tarjeta.detalleTecnico != nil {
                    Button(verTecnico ? "Ocultar el detalle técnico" : "Detalle técnico") { verTecnico.toggle() }.tlsBoton(.enlace)
                }
            }
            if verTecnico, let d = tarjeta.detalleTecnico {
                Text(d).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color).textSelection(.enabled)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).strokeBorder(TLSPaleta.borde1.color))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexion.tarjeta.\(tarjeta.clase.rawValue)")
    }
}

/// Campo · En la ficha · En Calendario, con lo distinto resaltado.
struct TablaDiferenciasCalendario: View {
    let diferencias: [DiferenciaDeConexion]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Rotulo("Qué")
                Rotulo("En la ficha")
                Rotulo("En Calendario")
            }
            Divider().overlay(TLSPaleta.separador.color).gridCellColumns(3)
            ForEach(diferencias) { d in
                GridRow {
                    Text(d.campo).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                    Text(d.enFicha.isEmpty ? "—" : d.enFicha).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .strikethrough(d.enFicha != d.enCalendario, color: TLSPaleta.textoSecundario.color)
                    Text(d.enCalendario.isEmpty ? "—" : d.enCalendario).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(d.campo): en la ficha \(d.enFicha), en Calendario \(d.enCalendario)")
            }
        }
        .padding(TLSEspacio.e12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .accessibilityIdentifier("conexion.diferencias")
    }
}

/// Las herramientas por revisar: qué hacen y si cambian cosas allí.
struct ListaHerramientasPorRevisar: View {
    let herramientas: [HerramientaDeLaTarjeta]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(herramientas) { h in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: h.cambiaCosas ? "exclamationmark.shield" : "eye")
                        .foregroundStyle(h.cambiaCosas ? TLSPaleta.atencion.color : TLSPaleta.bien.color)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(NombresLlanos.accion(h.nombre)).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                            Chip(h.estado)
                        }
                        Text(h.cambiaCosas ? "Cambia cosas en ese programa: cada vez pedirá tu OK. \(h.motivo)" : "Solo lee. \(h.motivo)")
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                        if let d = h.descripcion, !d.isEmpty {
                            Text("Dice el programa: «\(d)»").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                .lineLimit(2)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            // F5 · corrector (P2-5): los nombres del programa, tal cual, solo aquí.
            DisclosureGroup("Detalle técnico") {
                Text(herramientas.map(\.nombre).joined(separator: ", "))
                    .tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tlsTexto(TLSTipo.secundario)
        }
        .padding(TLSEspacio.e12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .accessibilityIdentifier("conexion.herramientas")
    }
}

/// Lo que se manda a otro programa, literalmente: a quién (el programa), qué hace y con qué datos.
struct PeticionExternaVista: View {
    let peticion: PeticionExternaLegible
    let programa: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: 6) {
                Rotulo("A quién")
                FlujoChips(espacio: 6) {
                    ForEach(programa.isEmpty ? [peticion.conexion ?? "Otro programa"] : programa, id: \.self) {
                        Chip($0, icono: "puzzlepiece.extension")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Rotulo("Qué hace allí")
                Text(peticion.accion).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityIdentifier("aprobacion.externa.accion")
            }
            VStack(alignment: .leading, spacing: 6) {
                Rotulo("Con estos datos, tal cual")
                if peticion.datos.isEmpty {
                    Text("Sin datos.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(Array(peticion.datos.enumerated()), id: \.offset) { _, d in
                            GridRow {
                                Text(PeticionExternaLegible.etiqueta(d.clave)).tlsTexto(TLSTipo.interfaz)
                                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                                Text(d.valor).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(TLSEspacio.e12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.superficie.color))
                    .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).strokeBorder(TLSPaleta.separador.color))
                }
            }
            Text("Al aprobar lo hace la app, una sola vez y con estos datos exactos. Si el programa cambia esa herramienta antes, no se hace nada.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Detalle técnico") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Herramienta: \(peticion.nombreOriginal.isEmpty ? peticion.herramienta : peticion.nombreOriginal)")
                    if !peticion.datos.isEmpty {
                        Text("Campos: " + peticion.datos.map(\.clave).joined(separator: ", "))
                    }
                }
                .tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tlsTexto(TLSTipo.secundario)
        }
        .accessibilityIdentifier("aprobacion.externa")
    }
}
