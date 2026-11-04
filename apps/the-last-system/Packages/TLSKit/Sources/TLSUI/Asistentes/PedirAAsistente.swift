import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · integración. «Pedir a <asistente>» de la cabecera de cada área y las acciones rápidas de las pantallas (como
// «Generar borrador de pieza» en Marca): con ⌘J conectado, abre la conversación con ese asistente («Para Comercial: »);
// una acción rápida con el motor en marcha se encarga como un trabajo del asistente (lo que prepare te espera en
// Decisiones). Sin motor en esta empresa, lleva a la ficha del asistente, que explica por qué no trabaja.

/// Quién es el asistente de cada área (los de serie).
enum AsistenteDeArea {
    static func slug(_ area: AreaCode) -> String {
        PerfilDeAsistente.deSerie.first { $0.area == area }?.slug ?? "mika"
    }
}

/// Encargar una acción rápida del perfil de un asistente (o decir por qué no se puede).
@MainActor
enum PedirAAsistente {
    /// Por qué no se puede encargar ahora (texto llano y corto) o `nil` si se puede. Con `slug`, también lo de ese
    /// asistente: su área preparada o en reposo, apagado o los asistentes en pausa.
    /// `motor: false`: sin mirar si el motor está en marcha (⌘J contesta igual, sin Claude).
    static func motivo(_ sesion: VaultSession, slug: String? = nil, motor: Bool = true) -> String? {
        if case .soloLectura(let m) = sesion.modoEscritura { return "Solo lectura: \(m.texto.lowercased())." }
        if let slug, let perfil = PerfilDeAsistente.deSerie.first(where: { $0.slug == slug }) {
            if let area = perfil.area, let estado = sesion.area(area)?.estado, estado == .preparada || estado == .reposo {
                return "\(area.etiquetaNumerada) está \(estado == .reposo ? "en reposo" : "preparada"): su asistente empezará cuando la actives."
            }
            if let efectiva = sesion.bus?.autorizador?.estadoDeConfig().efectiva {
                if !efectiva.encendido { return "Los asistentes están en pausa." }
                if efectiva.asistente(slug)?.activo != true { return "\(perfil.nombre) está apagado: actívalo en su ficha (Asistentes)." }
            }
        }
        guard !motor || RegistroDeAsistentes.compartido.conexion(de: sesion)?.host != nil else {
            return RegistroDeAsistentes.compartido.conexion(de: sesion)?.sinMotor != nil
                ? "Falta Claude Code en este Mac: mira Asistentes."
                : "Los asistentes no están en marcha en esta empresa: mira Asistentes."
        }
        return nil
    }

    /// Lo mismo, sin leer ficheros (para pintar una cabecera): el estado del área y lo que ya sabe la app del interruptor
    /// y de quién trabaja (`AsistentesDeLaEmpresa`, que se refresca fuera del hilo principal).
    static func motivoRapido(_ sesion: VaultSession, slug: String) -> String? {
        if case .soloLectura(let m) = sesion.modoEscritura { return "Solo lectura: \(m.texto.lowercased())." }
        guard let perfil = PerfilDeAsistente.deSerie.first(where: { $0.slug == slug }) else { return nil }
        if let area = perfil.area, let estado = sesion.area(area)?.estado, estado == .preparada || estado == .reposo {
            return "\(area.etiquetaNumerada) está \(estado == .reposo ? "en reposo" : "preparada"): su asistente empezará cuando la actives."
        }
        let a = AsistentesDeLaEmpresa.de(sesion)
        if a.encendidos == false { return "Los asistentes están en pausa." }
        if a.encendidos == true, !a.activos.contains(slug) { return "\(perfil.nombre) está apagado: actívalo en su ficha (Asistentes)." }
        return nil
    }

    /// Encarga la acción rápida `accion` del perfil de `slug`. Devuelve el aviso para la persona.
    static func encargar(_ slug: String, accion id: String, sesion: VaultSession, tarea: VaultPath? = nil, pantalla: String? = nil) async {
        guard let host = RegistroDeAsistentes.compartido.conexion(de: sesion)?.host else {
            sesion.aviso = Aviso(motivo(sesion, slug: slug) ?? "Ahora no se puede.", estado: .atencion)
            return
        }
        let perfil = PerfilDeAsistente.deSerie.first { $0.slug == slug }
        let accion = perfil?.accionesRapidas.first { $0.id == id }
        let nombre = perfil?.nombre ?? slug.capitalized
        do {
            if try await host.pedir(a: slug, instruccion: accion?.peticion ?? id, tarea: tarea, pantalla: pantalla, accion: id) != nil {
                sesion.aviso = Aviso("Se lo he pedido a \(nombre). Lo que prepare te esperará en Decisiones.", estado: .bien)
            } else {
                sesion.aviso = Aviso("\(nombre) no puede trabajar ahora (en pausa, en reposo o sin permisos). Mira Asistentes.", estado: .atencion)
            }
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .mal)
        }
    }
}

/// «Pedir a Comercial» de la cabecera de un área.
struct BotonPedirAAsistente: View {
    let sesion: VaultSession
    let area: AreaCode
    let nombre: String
    let contexto: String
    @Environment(\.navegar) private var navegar

    var body: some View {
        let slug = AsistenteDeArea.slug(area)
        // F4 · corrector (revisión de experiencia, P3): como «Generar borrador de pieza», desactivado con su motivo si su
        // área está preparada o en reposo, si está apagado o si los asistentes están en pausa.
        let motivo = PedirAAsistente.motivoRapido(sesion, slug: slug)
        Button("Pedir a \(nombre)") {
            if let abrir = RegistroDeAsistentes.compartido.conexion(de: sesion)?.abrirChat {
                abrir(slug, contexto)
            } else {
                navegar(.asistente(slug), modo: .entrar)
            }
        }
        .tlsBoton(.sobreCabecera)
        .disabled(motivo != nil)
        .help(motivo ?? "Habla con \(nombre) sobre lo que estás viendo (⌘J)")
        .accessibilityHint(motivo ?? "Abre la conversación con \(nombre)")
        .accessibilityIdentifier("area.pedir")
    }
}
