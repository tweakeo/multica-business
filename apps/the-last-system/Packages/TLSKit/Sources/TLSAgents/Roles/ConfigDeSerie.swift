import Foundation
import TLSCore

// F4 · rol «roles». Los valores por defecto de los asistentes en `.tls/config.yaml` (PLAN §4.5) para una empresa
// nueva o para la copia, y cómo añadirlos a una configuración que ya existe **sin cambiar nada de lo que ya hay**.
//
// De serie: Mika activo y coordinador; el Contable activo si Finanzas está activa; el Comercial y el Implementador,
// solo si su área lo está; Marca y Equipo en reposo; el Cartero inactivo hasta que conectes Mail; el Ordenador activo.
// Lo escribe una persona (la puesta en marcha, con su «Aplicar»); ningún asistente puede escribir esta configuración.

/// Generador de la configuración de serie de los asistentes.
public enum ConfigDeSerie {
    /// `avisos:` y `uso:` de serie (PLAN §4.5, §5.2 y §5.3).
    public static let topeTarjetasDia = 5
    public static let topeNotificacionesNoRojasDia = 3
    public static let usdEur = 0.92

    /// Comentario que va encima de lo que se añade.
    public static let comentario = "# Asistentes: lo que pueden hacer de verdad. Sus fichas de rol (Equipo › Roles) solo lo describen."

    /// Las claves de primer nivel que pone este generador, en orden.
    public static let claves = ["interruptor", "pausa_areas", "avisos", "uso", "agentes"]

    /// Quién queda activo con estos estados de área.
    public static func activos(estados: [AreaCode: AreaStatus], mailConectado: Bool = false,
                               perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: perfiles.map { ($0.slug, $0.activoDeSerie(estados: estados, mailConectado: mailConectado)) })
    }

    /// El bloque `agentes:` entero (con su salto de línea final).
    public static func bloqueAgentes(estados: [AreaCode: AreaStatus], mailConectado: Bool = false,
                                     perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) -> String {
        var l = ["agentes:"]
        for p in perfiles {
            l += entrada(p, activo: p.activoDeSerie(estados: estados, mailConectado: mailConectado)).map { "  " + $0 }
        }
        return l.joined(separator: "\n") + "\n"
    }

    /// La entrada de un asistente (sin sangría de primer nivel): `mika:` y sus claves.
    public static func entrada(_ p: PerfilDeAsistente, activo: Bool) -> [String] {
        var l = ["\(p.slug):", "  activo: \(activo)"]
        if p.coordinador { l.append("  coordinador: true") }
        l.append("  areas: \(lista(p.clavesDeArea))")
        if !p.clavesQueLee.isEmpty { l.append("  lee_areas: \(lista(p.clavesQueLee))") }
        l.append("  capacidades: \(lista(p.capacidades))")
        l.append("  herramientas_externas: []")
        l.append("  modelo: \(p.ajustes.modelo)")
        l.append("  esfuerzo: \(p.ajustes.esfuerzo)")
        l.append("  max_tareas_por_ejecucion: \(p.ajustes.maxTareasPorEjecucion)")
        l.append("  presupuesto_ejecucion_usd: \(numero(p.ajustes.presupuestoEjecucionUSD))")
        l.append("  presupuesto_mes_usd: \(numero(p.ajustes.presupuestoMesUSD))")
        if p.rutinas.isEmpty {
            l.append("  rutinas: []")
        } else {
            l.append("  rutinas:")
            l += p.rutinas.map { "    - " + rutina($0) }
        }
        return l
    }

    /// Una rutina en línea: `{id: algo-rojo, nombre: "¿Algo rojo?", dias: [lun, mar, mie, jue, vie], hora: "08:45", …}`.
    /// La instrucción no se escribe: es del catálogo (`RolDeAsistente.rutinasDeSerie`).
    public static func rutina(_ r: RutinaDeAsistente) -> String {
        var c = ["id: \(r.id)", "nombre: \(cadena(r.nombre))"]
        if let d = r.diaDelMes {
            c.append("dia_mes: \(d)")
        } else {
            c.append("dias: \(lista(r.dias.sorted().map(dia)))")
        }
        if !r.meses.isEmpty { c.append("meses: \(lista(r.meses.sorted().map(String.init)))") }
        c.append("hora: \(cadena(r.horaTexto))")
        c.append("ventana_perdida_h: \(numero(r.ventanaPerdidaH))")
        c.append("activa: \(r.activa)")
        if r.soloSiHayRojo { c.append("solo_si_rojo: true") }
        return "{" + c.joined(separator: ", ") + "}"
    }

    /// Los bloques de primer nivel de serie (clave → líneas), con `agentes:` al final.
    public static func bloques(estados: [AreaCode: AreaStatus], mailConectado: Bool = false,
                               perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) -> [(clave: String, texto: String)] {
        [
            ("interruptor", "interruptor: encendido\n"),
            ("pausa_areas", "pausa_areas: []\n"),
            ("avisos", "avisos: {tope_tarjetas_dia: \(topeTarjetasDia), tope_notificaciones_no_rojas_dia: \(topeNotificacionesNoRojasDia)}\n"),
            ("uso", "uso: {mostrar_eur: false, usd_eur: \(numero(usdEur))}\n"),
            ("agentes", bloqueAgentes(estados: estados, mailConectado: mailConectado, perfiles: perfiles)),
        ]
    }

    /// Añade a `config` lo que le falte (interruptor, pausa de áreas, avisos, uso y asistentes) al final, con un
    /// comentario. **Nunca cambia ni quita nada**: si una clave ya está (aunque sea vacía), se deja como está. Si no
    /// falta nada, devuelve el texto tal cual.
    public static func completar(_ config: String, estados: [AreaCode: AreaStatus], mailConectado: Bool = false,
                                 perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) -> String {
        let presentes = clavesDePrimerNivel(config)
        let faltan = bloques(estados: estados, mailConectado: mailConectado, perfiles: perfiles)
            .filter { !presentes.contains($0.clave) }
        guard !faltan.isEmpty else { return config }
        var texto = config
        if !texto.isEmpty && !texto.hasSuffix("\n") { texto += "\n" }
        if !texto.isEmpty && !texto.hasSuffix("\n\n") { texto += "\n" }
        texto += comentario + "\n"
        texto += faltan.map(\.texto).joined()
        return texto
    }

    /// Claves de primer nivel de un YAML (sin sangría, fuera de comentarios).
    public static func clavesDePrimerNivel(_ texto: String) -> Set<String> {
        var out = Set<String>()
        for linea in texto.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let c = linea.first, c != " ", c != "\t", c != "#", c != "-" else { continue }
            guard let dosPuntos = linea.firstIndex(of: ":") else { continue }
            let clave = linea[..<dosPuntos].trimmingCharacters(in: .whitespaces)
            if !clave.isEmpty, !clave.contains(" ") { out.insert(clave.replacingOccurrences(of: "\"", with: "")) }
        }
        return out
    }

    /// Estados de las seis áreas de una carpeta (solo lee los `Área.md`).
    public static func estados(en root: URL) -> [AreaCode: AreaStatus] {
        let (layout, _) = VaultLayout.load(root: root)
        var out: [AreaCode: AreaStatus] = [:]
        for a in AreaCode.allCases {
            let ruta = layout.areaFolder(a).appending(AreaReader.fileName)
            guard let texto = try? String(contentsOf: ruta.url(in: root), encoding: .utf8) else {
                out[a] = .desconocido
                continue
            }
            out[a] = AreaReader.parse(markdown: texto, code: a, folder: layout.areaFolder(a), resolve: { _ in nil }).estado
        }
        return out
    }

    // MARK: Formato

    static func lista(_ xs: [String]) -> String { "[" + xs.joined(separator: ", ") + "]" }

    static func cadena(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func numero(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }

    static func dia(_ d: DiaSemana) -> String {
        ["lun", "mar", "mie", "jue", "vie", "sab", "dom"][d.rawValue - 1]
    }
}
