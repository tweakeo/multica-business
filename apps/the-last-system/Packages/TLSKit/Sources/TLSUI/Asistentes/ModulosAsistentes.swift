import Foundation
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes. Los dos módulos de inicio de los asistentes (Hoy y el Resumen de Equipo, `DatosModulos`):
// «Salud de los asistentes» (quién trabaja y quién no, y por qué) y «Uso frente al tope» (como parte del tope, nunca en
// dinero). Hasta F4 decían «aún no trabajan en esta versión». Salen de la configuración y de la Bitácora; sin estado en
// vivo (eso está en Asistentes).

enum ModulosAsistentes {
    /// Las dos cifras, con la foto de la carpeta (fuera del hilo principal).
    static func cifras(foto: VaultSnapshot, ahora: Date) -> (salud: CifraModulo, uso: CifraModulo) {
        let root = foto.root
        let layout = VaultLayout.load(root: root).layout
        var f = FuentesDeAsistentes()
        f.textoFichero = EscrituraAsistentes.leerConfig(root)?.texto
        f.ahora = ahora
        f.estadosArea = ConfigDeSerie.estados(en: root)
        for p in foto.notes where Bitacora.esRutaDeBitacora(p, layout: layout) && !layout.isPrivate(p) {
            if let t = foto.text(p) { f.bitacora += ApunteBitacora.leer(t, ruta: p) }
        }
        let fuenteBitacora = "Sale de la bitácora de los asistentes"
        let enlace = EnlaceModulo(titulo: "Ver asistentes", destino: .asistentes)
        guard f.textoFichero.map({ !AjustesDeAsistentes.leer(yaml: $0).agentes.isEmpty }) ?? false else {
            let sin = CifraModulo.sinDato("Sin dato: aún no hay asistentes en la configuración de esta carpeta.",
                                          fuente: "Sale de la configuración de los asistentes", enlace: enlace)
            return (sin, CifraModulo.sinDato("Sin dato: aún no hay asistentes que usen nada.", fuente: fuenteBitacora, enlace: enlace))
        }
        let l = LecturaAsistentes.calcular(f)
        let activos = l.asistentes.filter(\.activo)
        let salud: CifraModulo
        if !l.interruptor {
            salud = CifraModulo(cifra: "En pausa", linea: "No hacen nada hasta que los enciendas.", estado: .atencion,
                                palabra: "En pausa", enlace: enlace, fuente: "Sale de la configuración de los asistentes")
        } else {
            let fuera = l.asistentes.filter { a in
                if case .enPausa = a.estadoGuardado { return true }
                return !a.activo && a.perfil?.activacion != .alConectarMail
            }
            let linea = fuera.isEmpty ? "Todos trabajan."
                : fuera.map { a in "\(a.nombre), " + (a.activo ? "en pausa" : "apagado") }.joined(separator: " · ")
            salud = CifraModulo(cifra: activos.count == 1 ? "1 activo" : "\(activos.count) activos", linea: linea,
                                estado: .bien, palabra: "En marcha", enlace: enlace, fuente: "Sale de la configuración de los asistentes")
        }
        let u = l.usoTotal
        let uso = CifraModulo(cifra: u.cifra, linea: "de tu tope este mes" + (u.simulado ? " (Simulado)" : ""),
                              estado: u.fraccion >= 0.8 ? .atencion : .bien, palabra: u.fraccion >= 0.8 ? "Cerca del tope" : "Holgado",
                              enlace: enlace, fuente: fuenteBitacora)
        return (salud, uso)
    }
}
