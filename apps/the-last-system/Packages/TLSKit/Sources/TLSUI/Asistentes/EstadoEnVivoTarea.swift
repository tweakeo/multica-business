import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes (PLAN §6.4: «estado en vivo del asistente: en cola, trabajando, esperando tu respuesta o
// terminado»). El componente que la ficha de tarea (`Tareas/TareaDetalle`) incrusta en su destacado cuando la tarea la
// lleva un asistente. Mezcla lo que dice la ficha (`EstadoAsistenteTarea`, F2) con lo que pasa ahora (`EstadoEnVivo` del
// motor): «Leyendo…», «Creando tarea…». No escribe nada: la Actividad la escribe el motor una sola vez, al terminar.

/// Lo que se dice del asistente de una tarea, ya en palabras.
struct EstadoVivoTarea: Hashable, Sendable {
    let palabra: String
    let simbolo: String
    let estado: TLSEstado
    let frase: String
    let detalle: String?
    let simulado: Bool

    /// `nil` si la tarea no la lleva un asistente.
    static func de(_ t: Tarea, hoy: LocalDate, vivo: TrabajoEnVivo?, interruptorEncendido: Bool,
                   conectado: Bool) -> EstadoVivoTarea? {
        guard let base = EstadoAsistenteTarea.de(t, hoy: hoy, enMarcha: vivo?.enMarcha ?? false) else { return nil }
        let nombre = Responsables.nombre(de: t.responsable ?? "")
        let esPregunta = ["decision", "pregunta"].contains(TextFolding.fold(t.tipo ?? ""))
        if let vivo {
            switch vivo.fase {
            case .trabajando:
                return EstadoVivoTarea(palabra: "Trabajando", simbolo: "bolt.circle.fill", estado: .bien,
                                       frase: "\(nombre) está trabajando en ella.", detalle: vivo.frase, simulado: vivo.simulado)
            case .enCola:
                return EstadoVivoTarea(palabra: "En cola", simbolo: "clock", estado: .sinDato,
                                       frase: "En cola: \(nombre) la cogerá en cuanto termine lo anterior.", detalle: nil,
                                       simulado: vivo.simulado)
            case .esperandoRespuesta:
                return EstadoVivoTarea(palabra: "Esperando tu respuesta", simbolo: "questionmark.bubble.fill", estado: .sinDato,
                                       frase: "\(nombre) te ha hecho una pregunta.",
                                       detalle: "Contéstale en Decisiones o comentando aquí abajo: retoma el trabajo donde lo dejó.",
                                       simulado: vivo.simulado)
            case .terminado, .fallido, .cancelado:
                break
            }
        }
        switch base {
        case .enCola:
            if !interruptorEncendido {
                return EstadoVivoTarea(palabra: "En pausa", simbolo: "pause.circle", estado: .sinDato,
                                       frase: "Los asistentes están en pausa: \(nombre) la cogerá cuando los enciendas.",
                                       detalle: nil, simulado: false)
            }
            return EstadoVivoTarea(palabra: "En cola", simbolo: "clock", estado: .sinDato,
                                   frase: "En cola: \(nombre) la cogerá en su próxima vuelta.",
                                   detalle: conectado ? nil : "Empezará cuando los asistentes estén en marcha en este Mac.",
                                   simulado: false)
        case .esperaTuRespuesta:
            if esPregunta {
                return EstadoVivoTarea(palabra: "Esperando tu respuesta", simbolo: "questionmark.bubble.fill", estado: .sinDato,
                                       frase: "\(nombre) espera tu respuesta.", detalle: "Contéstale en Decisiones.", simulado: false)
            }
            return EstadoVivoTarea(palabra: "Terminado", simbolo: "checkmark.circle", estado: .bien,
                                   frase: "\(nombre) terminó su parte: revisa lo que dejó en la Actividad.",
                                   detalle: "Si está bien, márcala como hecha; si no, coméntale qué cambiar y la retoma.",
                                   simulado: false)
        case .terminado:
            return EstadoVivoTarea(palabra: "Terminado", simbolo: "checkmark.circle", estado: .bien,
                                   frase: base.frase(asistente: nombre, hoy: hoy), detalle: nil, simulado: false)
        case .sinEmpezar:
            return EstadoVivoTarea(palabra: base.palabra, simbolo: "tray", estado: .sinDato,
                                   frase: base.frase(asistente: nombre, hoy: hoy),
                                   detalle: "«Empezar ahora» la pasa a Por hacer con el día de hoy.", simulado: false)
        case .esperaSuDia:
            return EstadoVivoTarea(palabra: base.palabra, simbolo: "calendar", estado: .sinDato,
                                   frase: base.frase(asistente: nombre, hoy: hoy),
                                   detalle: "«Empezar ahora» la adelanta a hoy.", simulado: false)
        case .bloqueada:
            return EstadoVivoTarea(palabra: base.palabra, simbolo: "xmark.octagon", estado: .mal,
                                   frase: base.frase(asistente: nombre, hoy: hoy), detalle: nil, simulado: false)
        case .trabajando:
            return EstadoVivoTarea(palabra: "Trabajando", simbolo: "bolt.circle.fill", estado: .bien,
                                   frase: base.frase(asistente: nombre, hoy: hoy), detalle: nil, simulado: false)
        }
    }
}

/// El estado en vivo del asistente de una tarea, dentro del destacado violeta de la ficha de tarea (texto en blanco).
struct EstadoEnVivoDeTarea: View {
    let sesion: VaultSession
    let tarea: Tarea
    let hoy: LocalDate
    @State private var interruptor: ModeloInterruptorAsistentes

    init(sesion: VaultSession, tarea: Tarea, hoy: LocalDate) {
        self.sesion = sesion
        self.tarea = tarea
        self.hoy = hoy
        _interruptor = State(initialValue: ModeloInterruptorAsistentes(sesion: sesion))
    }

    var body: some View {
        let conexion = RegistroDeAsistentes.compartido.conexion(de: sesion)
        let vivo = conexion?.enVivo.trabajo(deTarea: tarea.ruta)
        VStack(alignment: .leading, spacing: 6) {
            if let e = EstadoVivoTarea.de(tarea, hoy: hoy, vivo: vivo, interruptorEncendido: interruptor.encendido,
                                          conectado: conexion != nil) {
                HStack(spacing: 6) {
                    PastillaAsistente(palabra: e.palabra, simbolo: e.simbolo, estado: e.estado, sobreColor: true)
                    if e.simulado { MarcaSimulado(sobreColor: true) }
                }
                Text(e.frase).tlsTexto(TLSTipo.interfazFuerte).fixedSize(horizontal: false, vertical: true)
                if let d = e.detalle {
                    Text(d).tlsTexto(e.palabra == "Trabajando" ? TLSTipo.interfazMedia : TLSTipo.secundario)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tarea.asistente.frase")
                }
                if vivo?.fase == .trabajando, let host = conexion?.host, let id = vivo?.ejecucion {
                    Button("Parar este trabajo") { Task { await host.cancelar(id) } }
                        .tlsBoton(.enlace)
                        .help("El asistente deja lo que está haciendo; lo que ya escribió se puede deshacer")
                }
            }
        }
        .task(id: sesion.revision) { interruptor.cargar() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tarea.asistente.estado")
    }
}
