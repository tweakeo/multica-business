import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes. El interruptor general «Asistentes encendidos / en pausa» (DIR-11, PLAN §6.1): en la cabecera de
// Asistentes, en el pie de la barra lateral y, con `InterruptorGeneralAsistentes(sesion:estilo: .barraDeHerramientas)`,
// en la barra de herramientas (rol mika). Escribe `interruptor:` en `config.yaml` como la persona, con Deshacer; apagar
// vale al momento: el motor para lo que esté en marcha (≤ 5 s) y no saca nada más de la cola.

/// Lo que dice ahora el interruptor (la configuración que se aplica, si la app ya tiene gobierno; si no, el fichero).
@MainActor
@Observable
final class ModeloInterruptorAsistentes {
    let sesion: VaultSession
    private(set) var encendido = true
    private(set) var cambiando = false

    init(sesion: VaultSession) { self.sesion = sesion }

    func cargar() {
        guard !cambiando, let root = sesion.root else { return }
        if let g = sesion.bus?.autorizador {
            encendido = g.estadoDeConfig().efectiva.encendido
            return
        }
        let texto = EscrituraAsistentes.leerConfig(root)?.texto
        encendido = ConfigAgentes.leer(yaml: texto).encendido && AjustesDeAsistentes.leer(yaml: texto).interruptor
    }

    /// Por qué no se puede cambiar aquí (`nil` si se puede).
    var motivoNoSePuede: String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .abriendo: "Abriendo la carpeta…"
        case .soloLectura(let m): "Solo lectura: \(m.texto)"
        }
    }

    func poner(_ v: Bool) async {
        guard v != encendido, !cambiando, motivoNoSePuede == nil else { return }
        cambiando = true
        let antes = encendido
        encendido = v
        do {
            try await EscrituraAsistentes.ponerInterruptor(v, sesion: sesion)
        } catch {
            encendido = antes
            sesion.aviso = Aviso(error.localizedDescription, estado: .mal)
        }
        cambiando = false
    }

    var titulo: String { encendido ? (sinMotor != nil ? "Encendidos · falta Claude Code" : "Asistentes encendidos") : "Asistentes en pausa" }

    /// F4 · corrector (revisión de experiencia, P2): encendidos pero sin Claude Code en una copia, no pueden trabajar.
    /// En el ejemplo, no (va simulado).
    var sinMotor: String? {
        sesion.entry.clase == .demo ? nil : RegistroDeAsistentes.compartido.conexion(de: sesion)?.sinMotor
    }
}

/// El interruptor general, con su palabra al lado (nunca solo el color).
public struct InterruptorGeneralAsistentes: View {
    public enum Estilo: Sendable { case barraDeHerramientas, cabecera, compacto }

    let sesion: VaultSession
    let estilo: Estilo
    @State private var modelo: ModeloInterruptorAsistentes

    public init(sesion: VaultSession, estilo: Estilo = .barraDeHerramientas) {
        self.sesion = sesion
        self.estilo = estilo
        _modelo = State(initialValue: ModeloInterruptorAsistentes(sesion: sesion))
    }

    public var body: some View {
        let sobreCabecera = estilo == .cabecera
        Toggle(isOn: Binding(get: { modelo.encendido }, set: { v in Task { await modelo.poner(v) } })) {
            Text(modelo.titulo)
                .tlsTexto(estilo == .compacto ? TLSTipo.secundario : TLSTipo.interfazMedia)
                .foregroundStyle(sobreCabecera ? TLSPaleta.sobreColor.color : TLSPaleta.texto.color)
                .lineLimit(1)
        }
        .toggleStyle(.switch)
        .controlSize(estilo == .cabecera ? .regular : .small)
        // F4 · corrector (revisión de experiencia, P3): sobre la cabecera, azul claro (el violeta es del destacado).
        .tint(sobreCabecera ? TLSPaleta.interruptorSobreCabecera.color : TLSPaleta.principal.color)
        .disabled(modelo.motivoNoSePuede != nil || modelo.cambiando)
        .help(modelo.motivoNoSePuede ?? modelo.sinMotor.map { "No pueden trabajar: \($0)" } ?? (modelo.encendido
            ? "Pausa a todos los asistentes: dejan lo que estén haciendo y no empiezan nada nuevo"
            : "Enciende a los asistentes: vuelven a trabajar en lo que tengan pendiente"))
        .fixedSize()
        .task(id: sesion.revision) { modelo.cargar() }
        .accessibilityLabel("Asistentes")
        .accessibilityValue(modelo.encendido ? "Encendidos" : "En pausa")
        .accessibilityIdentifier("asistentes.interruptor")
    }
}

/// El pie de la barra lateral: el interruptor de los asistentes con lo que pasa («1 trabajando», «en pausa»). También
/// pone el dato de la fila «Asistentes» de la barra.
struct PieAsistentesBarra: View {
    let sesion: VaultSession
    @State private var modelo: ModeloInterruptorAsistentes

    init(sesion: VaultSession) {
        self.sesion = sesion
        _modelo = State(initialValue: ModeloInterruptorAsistentes(sesion: sesion))
    }

    var body: some View {
        let trabajando = RegistroDeAsistentes.compartido.conexion(de: sesion)?.enVivo.enCurso.count ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: modelo.encendido ? "sparkle" : "pause.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(modelo.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(detalle(trabajando)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Asistentes", isOn: Binding(get: { modelo.encendido }, set: { v in Task { await modelo.poner(v) } }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(TLSPaleta.principal.color)
                    .disabled(modelo.motivoNoSePuede != nil || modelo.cambiando)
                    .help(modelo.motivoNoSePuede ?? (modelo.encendido ? "Pausar a todos los asistentes" : "Encender a los asistentes"))
                    .accessibilityValue(modelo.encendido ? "Encendidos" : "En pausa")
                    .accessibilityIdentifier("lateral.asistentes.interruptor")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
        }
        .task(id: sesion.revision) { modelo.cargar() }
        .onChange(of: "\(modelo.encendido)|\(trabajando)", initial: true) { _, _ in
            var d = sesion.barraLateral.datos[.asistentes] ?? DatoFilaBarra()
            d.debajo = !modelo.encendido ? "en pausa"
                : (modelo.sinMotor != nil ? "sin Claude Code" : (trabajando > 0 ? "\(trabajando) trabajando" : nil))
            if sesion.barraLateral.datos[.asistentes] != d { sesion.barraLateral.datos[.asistentes] = d }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lateral.asistentes")
    }

    private func detalle(_ trabajando: Int) -> String {
        if let m = modelo.motivoNoSePuede, sesion.modoEscritura != .abriendo { return m.hasPrefix("Solo lectura") ? "Solo lectura" : m }
        if !modelo.encendido { return "No hacen nada hasta que los enciendas" }
        if modelo.sinMotor != nil { return "No pueden trabajar: falta Claude Code" }
        if trabajando > 0 { return trabajando == 1 ? "1 trabajando ahora" : "\(trabajando) trabajando ahora" }
        return "Nada sale sin tu OK"
    }
}
