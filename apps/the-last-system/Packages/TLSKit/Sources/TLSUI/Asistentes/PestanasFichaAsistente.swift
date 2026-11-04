import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes. Las pestañas de la ficha de un asistente: Resumen (misión, pregunta, lo que hace solo, con tu
// OK y nunca, en lenguaje llano), Permisos (por función, cuatro niveles; lo que sale fuera, bloqueado), Rutinas y topes
// y Trabajos (con «Detalle técnico» desplegable). La Bitácora es `BitacoraAsistentesVista`.

// MARK: - Resumen

struct ResumenAsistente: View {
    let asistente: AsistenteEnLista
    let lectura: LecturaAsistentes
    let editables: AjustesConCambios
    let pedirAlgo: () -> Void
    @Environment(\.navegar) private var navegar

    var body: some View {
        let a = asistente
        if let p = a.perfil {
            FilaOColumna { mision(p); cuando(p) }
            FilaOColumna { queHace(p) }
            if !p.alertas.isEmpty || !p.accionesRapidas.isEmpty {
                HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                    if !p.alertas.isEmpty {
                        Mosaico("Te avisa si", icono: "bell") {
                            // F4 · corrector (P3): sin códigos de números clave fuera de «Detalle técnico».
                            ListaFrases(frases: p.alertas.map(\.cuando))
                        }
                    }
                    Mosaico("Pídele algo", icono: "sparkle", pie: "Lo prepara y te lo deja para revisar") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(p.accionesRapidas) { acc in
                                Text("«\(acc.titulo)»").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                            }
                            Button("Pedir algo a \(a.nombre)", action: pedirAlgo).tlsBoton(.secundario)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            fichaDeRol(a)
        } else {
            VacioExplicado(icono: "sparkle", titulo: "Sin ficha de serie",
                           porQue: "Este asistente está en la configuración pero no es uno de los de serie: aquí solo ves sus permisos, rutinas y trabajos.",
                           compacto: true)
        }
    }

    private func mision(_ p: PerfilDeAsistente) -> some View {
        Mosaico("Misión", icono: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                Text(p.mision).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Su pregunta").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text("«\(p.pregunta)»").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(p.entrega).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("asistente.mision")
    }

    private func cuando(_ p: PerfilDeAsistente) -> some View {
        var frases = editables.rutinas.map { r in
            "«\(r.nombre)»: " + (r.activa ? FichaDeRolDeAsistente.cuando(r) : "apagada") + (r.soloSiHayRojo ? ", solo si hay algo en rojo" : "")
        }
        frases += p.disparadores.map(\.resumen)
        if frases.isEmpty { frases = ["Trabaja cuando se lo pides o le asignas una tarea."] }
        return Mosaico("Cuándo trabaja", icono: "calendar.badge.clock", pie: p.activacion.explicacion) {
            ListaFrases(frases: frases)
        }
    }

    @ViewBuilder
    private func queHace(_ p: PerfilDeAsistente) -> some View {
        Mosaico("Lo hace solo", icono: "checkmark.circle") {
            ListaFrases(frases: p.puedeSolo + p.decideSolo)
        }
        .accessibilityIdentifier("asistente.solo")
        Mosaico("Con tu OK", icono: "lock") {
            ListaFrases(frases: p.puedeConTuOK.isEmpty ? ["Nada sale de la empresa: no pide aprobaciones."] : p.puedeConTuOK)
        }
        .accessibilityIdentifier("asistente.conTuOK")
        Mosaico("Nunca", icono: "nosign") {
            ListaFrases(frases: Self.nunca(p))
        }
        .accessibilityIdentifier("asistente.nunca")
    }

    /// Lo que nunca hace, siempre con la línea roja delante.
    static func nunca(_ p: PerfilDeAsistente) -> [String] {
        let roja = "Enviar, publicar, facturar, pagar o escribir a clientes sin tu OK"
        return [roja] + p.nunca.filter { TextFolding.fold($0) != TextFolding.fold(roja) }
    }

    @ViewBuilder
    private func fichaDeRol(_ a: AsistenteEnLista) -> some View {
        HStack(spacing: TLSEspacio.e8) {
            Image(systemName: "person.text.rectangle").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
            Text("Su ficha de rol, en Equipo › Roles, lo describe; cambiarla no le da permisos. Sus permisos son los de esta ficha.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Permisos

struct PermisosAsistente: View {
    let asistente: AsistenteEnLista
    let editables: AjustesConCambios
    let motivoNoSePuede: String?
    let poner: (CambioDeAsistente) -> Void

    static let niveles: [ModoCapacidad] = [.manual, .asistido, .supervisado, .autonomo]

    var body: some View {
        let funciones = AjustesConCambios.funciones(asistente)
        TituloSeccionAsistentes(titulo: "Permisos por función",
                                explicacion: "Hasta dónde llega en cada función. Lo que sale de la empresa (enviar, publicar, facturar, pagar o escribir a clientes) siempre pide tu OK, en cualquier nivel.")
        leyenda
        if let m = motivoNoSePuede { AvisoEnLinea(m, estado: .sinDato) }
        if funciones.isEmpty {
            VacioExplicado(icono: "lock", titulo: "No lleva funciones del estándar",
                           porQue: "Trabaja con lo de todos (tareas, comentarios, avisos, borradores) y nada más.", compacto: true)
        } else {
            TarjetaFilas {
                ForEach(Array(funciones.enumerated()), id: \.element) { i, c in
                    if i > 0 { SeparadorFila(sangria: 16) }
                    fila(c)
                }
            }
            .accessibilityIdentifier("asistente.permisos")
        }
        Mosaico("Siempre con tu OK", icono: "lock.fill", pie: "Al aprobar, lo hace la app, no el asistente, y vuelve a comprobar que nada cambió") {
            ListaFrases(frases: (asistente.perfil?.puedeConTuOK ?? []) + ["Enviar, publicar, facturar, pagar o escribir a clientes: siempre te pide la aprobación concreta"],
                        simbolo: "lock.fill", tamanoSimbolo: 9)
        }
        .accessibilityIdentifier("asistente.siempreConTuOK")
    }

    private var leyenda: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TLSEspacio.e16) { ForEach(Self.niveles, id: \.self) { explicacion($0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(Self.niveles, id: \.self) { explicacion($0) } }
        }
        .accessibilityElement(children: .contain)
    }

    private func explicacion(_ m: ModoCapacidad) -> some View {
        let modo = ModoFuncion(leyendo: m.rawValue)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: modo.simbolo).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.etiqueta).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                Text(Self.queSignifica(m)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 230, alignment: .leading)
    }

    static func queSignifica(_ m: ModoCapacidad) -> String {
        switch m {
        case .off: "No lo hace nadie."
        case .manual: "Te deja una tarea y lo haces tú."
        case .asistido: "Lo prepara y te lo propone; decides tú."
        case .supervisado: "Lo hace y lo ves en el resumen de la semana."
        case .autonomo: "Lo hace y queda en su bitácora."
        }
    }

    private func fila(_ codigo: String) -> some View {
        let cap = CatalogoPrograma.deSerie.capacidades.first { $0.codigo == codigo }
        let sale = FormatoAsistentes.saleFuera(cap, codigo: codigo)
        let modo = editables.modos[codigo] ?? .asistido
        return HStack(alignment: .center, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: 2) {
                // F4 · corrector (P3): el nombre de la función; su código, solo al pasar el puntero.
                Text(cap?.nombre ?? codigo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Código de la función: \(codigo)")
                Text(sale ? "Sale fuera de la empresa: lo prepara y siempre te pide tu OK."
                          : (cap?.produce.map { "Deja: \($0)" } ?? "Función de su área"))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if sale {
                ModoPastilla(modo: .siempreConTuOK)
                    .accessibilityLabel("\(codigo): siempre con tu OK, bloqueado")
            } else {
                let enlace = Binding<ModoCapacidad>(get: { modo }, set: { poner(.modo(codigo, $0)) })
                ViewThatFits(in: .horizontal) {
                    Picker("Nivel de \(codigo)", selection: enlace) {
                        ForEach(Self.niveles, id: \.self) { Text($0.etiqueta).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 440)
                    Picker("Nivel de \(codigo)", selection: enlace) {
                        ForEach(Self.niveles, id: \.self) { Text($0.etiqueta).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .labelsHidden()
                .disabled(motivoNoSePuede != nil)
                .help(motivoNoSePuede ?? Self.queSignifica(modo))
                .accessibilityLabel("Nivel de \(codigo), \(cap?.nombre ?? "")")
                .accessibilityValue(modo.etiqueta)
                .accessibilityIdentifier("asistente.permiso.\(codigo)")
            }
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, 10)
    }
}

// MARK: - Rutinas y topes

struct RutinasYTopesAsistente: View {
    let sesion: VaultSession
    let asistente: AsistenteEnLista
    let lectura: LecturaAsistentes
    let editables: AjustesConCambios
    let motivoNoSePuede: String?
    let poner: (CambioDeAsistente) -> Void
    @State private var tecnico = false

    var body: some View {
        TituloSeccionAsistentes(titulo: "Rutinas",
                                explicacion: "Lo que hace solo, en su día y a su hora. Si el Mac estaba dormido, hace la última que se perdió si aún está a tiempo.")
        if let m = motivoNoSePuede { AvisoEnLinea(m, estado: .sinDato) }
        if asistente.rutinas.isEmpty {
            VacioExplicado(icono: "calendar.badge.clock", titulo: "Sin rutinas",
                           porQue: "Trabaja cuando se lo pides, cuando le asignas una tarea o cuando pasa algo en su área.", compacto: true)
        } else {
            TarjetaFilas {
                ForEach(Array(asistente.rutinas.enumerated()), id: \.element.id) { i, v in
                    if i > 0 { SeparadorFila(sangria: 16) }
                    fila(v)
                }
            }
            .accessibilityIdentifier("asistente.rutinas")
            if asistente.rutinas.first?.deSerie == true {
                Text("Son las de serie de \(asistente.nombre): al cambiar una, se escriben en la configuración.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        if let d = asistente.perfil?.disparadores, !d.isEmpty {
            Mosaico("Además trabaja cuando", icono: "bolt") { ListaFrases(frases: d.map(\.resumen)) }
        }
        TituloSeccionAsistentes(titulo: "Topes de uso",
                                explicacion: "Para que nunca use de más. Se cuenta como parte de su tope del mes; con el mes agotado, no empieza nada.")
        topes
    }

    // MARK: Una rutina

    private func fila(_ v: RutinaVista) -> some View {
        let r = editables.rutina(v.id) ?? v.rutina
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                Toggle(r.nombre, isOn: Binding(get: { r.activa }, set: { poner(.rutinaActiva(r.id, $0)) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(TLSPaleta.principal.color)
                    .disabled(motivoNoSePuede != nil)
                    .accessibilityLabel("Rutina \(r.nombre)")
                    .accessibilityValue(r.activa ? "Encendida" : "Apagada")
                    .accessibilityIdentifier("asistente.rutina.\(r.id).activa")
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text((r.activa ? FormatoFicha.capital(FichaDeRolDeAsistente.cuando(r)) : "Apagada: no la hace hasta que la enciendas")
                         + (r.soloSiHayRojo ? ". Solo trabaja si hay algo en rojo: si no, la app lo comprueba y no gasta nada." : ""))
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                dia(r)
                hora(r)
            }
            if let auto = v.autopausa {
                HStack(spacing: TLSEspacio.e8) {
                    AvisoEnLinea("Se pausó sola porque falló muchas veces seguidas: \(auto)", estado: .atencion)
                    if let host = RegistroDeAsistentes.compartido.conexion(de: sesion)?.host {
                        Button("Reanudar") {
                            let clave = "\(asistente.slug).\(r.id)"
                            Task { try? await host.reanudarRutina(clave) }
                        }
                        .tlsBoton(.secundario)
                    }
                }
            }
            if let p = v.proxima, r.activa {
                Text("Próxima vez: " + FormatoAsistentes.cuando(p, zona: lectura.zona, hoy: lectura.hoy))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func dia(_ r: TLSAgents.RutinaDeAsistente) -> some View {
        if let d = r.diaDelMes {
            Stepper(value: Binding(get: { d }, set: { poner(.rutinaDiaDelMes(r.id, $0)) }), in: 1...28) {
                Text("Día \(d)").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
            }
            .fixedSize()
            .disabled(motivoNoSePuede != nil)
            .help(r.meses.isEmpty ? "Día del mes" : "Día del mes (solo en los meses que dice la rutina)")
            .accessibilityLabel("Día del mes de \(r.nombre)")
            .accessibilityValue("\(d)")
        } else {
            HStack(spacing: 3) {
                ForEach(DiaSemana.allCases, id: \.self) { s in
                    let elegido = r.dias.contains(s)
                    Button {
                        var dias = r.dias
                        if elegido { dias.remove(s) } else { dias.insert(s) }
                        if !dias.isEmpty { poner(.rutinaDias(r.id, dias)) }
                    } label: {
                        Text(Self.inicial(s)).tlsTexto(TLSTipo.interfazMedia)
                            .foregroundStyle(elegido ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(elegido ? TLSPaleta.principal.color : TLSPaleta.bandeja.color))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(motivoNoSePuede != nil)
                    .accessibilityLabel(Self.nombre(s))
                    .accessibilityAddTraits(elegido ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Días de \(r.nombre)")
        }
    }

    private func hora(_ r: TLSAgents.RutinaDeAsistente) -> some View {
        Menu {
            ForEach(Self.horas(incluyendo: r.horaTexto), id: \.self) { h in
                Button(h) {
                    let p = h.split(separator: ":")
                    if p.count == 2, let hh = Int(p[0]), let mm = Int(p[1]) { poner(.rutinaHora(r.id, hora: hh, minuto: mm)) }
                }
            }
        } label: {
            Label("a las \(r.horaTexto)", systemImage: "clock").tlsTexto(TLSTipo.interfazMedia)
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(motivoNoSePuede != nil)
        .accessibilityLabel("Hora de \(r.nombre)")
        .accessibilityValue(r.horaTexto)
        .accessibilityIdentifier("asistente.rutina.\(r.id).hora")
    }

    static func horas(incluyendo actual: String) -> [String] {
        var out: [String] = []
        for h in 6...21 { for m in [0, 15, 30, 45] { out.append(String(format: "%02d:%02d", h, m)) } }
        if !out.contains(actual) { out.append(actual); out.sort() }
        return out
    }

    static func inicial(_ d: DiaSemana) -> String { ["L", "M", "X", "J", "V", "S", "D"][d.rawValue - 1] }
    static func nombre(_ d: DiaSemana) -> String {
        ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"][d.rawValue - 1]
    }

    // MARK: Topes

    private var topes: some View {
        let a = asistente
        let parte = editables.topeMes > 0 ? UsoDelMes.parte(editables.topeTrabajo, de: editables.topeMes) : "sin tope fijado"
        return TarjetaFilas {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Uso del mes").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Spacer()
                    Text(a.uso.fraseSinMarca).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    if a.uso.simulado { MarcaSimulado() }
                }
                BarraUso(uso: a.uso)
            }
            .padding(.horizontal, TLSEspacio.e16).padding(.vertical, 10)
            SeparadorFila(sangria: 16)
            HStack {
                Text("Cada trabajo").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Spacer()
                Text("Puede usar como mucho el \(parte) del mes").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
            }
            .padding(.horizontal, TLSEspacio.e16).frame(minHeight: TLSAltura.filaLista)
            SeparadorFila(sangria: 16)
            HStack {
                Text("Tareas nuevas por trabajo").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Spacer()
                Stepper(value: Binding(get: { editables.maxTareas }, set: { poner(.maxTareas($0)) }), in: 1...50) {
                    Text("Como mucho \(editables.maxTareas)").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                }
                .fixedSize()
                .disabled(motivoNoSePuede != nil)
                .accessibilityIdentifier("asistente.topes.tareas")
            }
            .padding(.horizontal, TLSEspacio.e16).frame(minHeight: TLSAltura.filaLista)
            SeparadorFila(sangria: 16)
            DisclosureGroup("Detalle técnico", isExpanded: $tecnico) {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: Binding(get: { editables.topeMes }, set: { poner(.topeMes(max(1, ($0 * 100).rounded() / 100))) }),
                            in: 1...500, step: 5) {
                        Text("Tope del mes: \(Self.usd(editables.topeMes)) USD").tlsTexto(TLSTipo.interfaz)
                    }
                    .accessibilityIdentifier("asistente.topes.mes")
                    Stepper(value: Binding(get: { editables.topeTrabajo }, set: { poner(.topeTrabajo(max(0.1, ($0 * 100).rounded() / 100))) }),
                            in: 0.1...10, step: 0.1) {
                        Text("Tope de cada trabajo: \(Self.usd(editables.topeTrabajo)) USD").tlsTexto(TLSTipo.interfaz)
                    }
                    .accessibilityIdentifier("asistente.topes.trabajo")
                    Text("Modelo: \(a.ajustes.modelo ?? "el de serie") · esfuerzo: \(a.ajustes.esfuerzo ?? "el de serie")")
                        .tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text("Usado este mes: \(Self.usd(a.uso.simulado ? 0 : a.uso.usadoUSD)) USD"
                         + (a.uso.simulado ? " (y \(Self.usd(a.uso.usadoUSD)) USD simulados)" : ""))
                        .tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text("Es la medida de uso que da Claude Code; con una suscripción no es un cargo aparte.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .disabled(motivoNoSePuede != nil)
                .padding(.top, 6)
            }
            .tlsTexto(TLSTipo.interfazMedia)
            .padding(.horizontal, TLSEspacio.e16).padding(.vertical, 8)
            .accessibilityIdentifier("asistente.topes.tecnico")
        }
        .accessibilityIdentifier("asistente.topes")
    }

    static func usd(_ d: Double) -> String { String(format: "%.2f", d).replacingOccurrences(of: ".", with: ",") }
}

// MARK: - Trabajos

struct TrabajosAsistente: View {
    let sesion: VaultSession
    let asistente: AsistenteEnLista
    let lectura: LecturaAsistentes
    let vivo: TrabajoEnVivo?
    let directorio: URL

    var body: some View {
        let trabajos = lectura.trabajos(de: asistente.slug)
        TituloSeccionAsistentes(titulo: "Trabajos recientes",
                                explicacion: "Cada vez que trabaja: por qué, qué dejó y cuánto usó. El detalle técnico, por si hiciera falta revisarlo.")
        if trabajos.isEmpty {
            VacioExplicado(icono: "tray", titulo: "Aún no ha trabajado en este Mac",
                           porQue: "Cuando trabaje, aquí verás cada trabajo con su resumen y lo que usó. Lo que hizo antes queda en su bitácora.",
                           compacto: true)
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        } else {
            TarjetaFilas {
                ForEach(Array(trabajos.prefix(30).enumerated()), id: \.element.id) { i, t in
                    if i > 0 { SeparadorFila(sangria: 16) }
                    FilaTrabajo(sesion: sesion, trabajo: t, tope: asistente.ajustes.presupuestoMesUSD, lectura: lectura,
                                vivo: vivo?.ejecucion == t.id ? vivo : nil, directorio: directorio)
                }
            }
            .accessibilityIdentifier("asistente.trabajos")
        }
    }
}

struct FilaTrabajo: View {
    let sesion: VaultSession
    let trabajo: TrabajoDeAsistente
    let tope: Double
    let lectura: LecturaAsistentes
    let vivo: TrabajoEnVivo?
    let directorio: URL
    @State private var abierto = false
    @State private var registro: String?
    @Environment(\.navegar) private var navegar

    var body: some View {
        let t = trabajo
        let dia = LocalDate(date: t.fecha, timeZone: lectura.zona)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e12) {
                PastillaAsistente(palabra: vivo.map { _ in "Trabajando" } ?? t.palabra, simbolo: simbolo, estado: t.tlsEstado)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vivo?.frase ?? t.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(t.porQue + " · " + FormatoAsistentes.momento(dia, hora: FormatoAsistentes.hora(t.fecha, zona: lectura.zona), hoy: lectura.hoy))
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    if let m = t.motivo {
                        Text(m).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if t.simulado { MarcaSimulado() }
                Text("Usó " + UsoDelMes.parte(t.costeUSD, de: tope)).tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            HStack(spacing: TLSEspacio.e12) {
                if let tarea = t.tarea {
                    Button("Abrir la tarea") { navegar(.tarea(tarea), modo: .entrar) }.tlsBoton(.enlace)
                }
                if t.estado == .esperandoRespuesta {
                    Button("Contestar en Decisiones") { navegar(.decisiones, modo: .raiz) }.tlsBoton(.enlace)
                }
            }
            DisclosureGroup("Detalle técnico", isExpanded: $abierto) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trabajo \(t.id) · intento \(t.intento + 1) · uso \(RutinasYTopesAsistente.usd(t.costeUSD)) USD"
                         + (t.sesion.map { " · sesión \($0)" } ?? ""))
                        .tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .textSelection(.enabled)
                    ScrollView {
                        Text(registro ?? "Sin registro técnico guardado en este Mac.")
                            .tlsTexto(TLSTipo.codigo)
                            .foregroundStyle(TLSPaleta.texto.color)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(TLSEspacio.e8)
                    }
                    .frame(maxHeight: 220)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous).fill(TLSPaleta.bandeja.color))
                    .accessibilityLabel("Registro técnico del trabajo")
                }
                .padding(.top, 4)
            }
            .tlsTexto(TLSTipo.interfazMedia)
            .accessibilityIdentifier("asistente.trabajo.\(t.id).tecnico")
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, 10)
        .task(id: abierto) {
            guard abierto, registro == nil else { return }
            let id = t.id, dir = directorio
            registro = await Task.detached(priority: .utility) { ModeloAsistentes.registroTecnico(id, dir: dir) }.value
        }
        .accessibilityElement(children: .contain)
    }

    private var simbolo: String {
        if vivo != nil { return "bolt.circle.fill" }
        switch trabajo.estado {
        case .completada: return "checkmark.circle"
        case .fallida: return "xmark.octagon"
        case .cancelada: return "minus.circle"
        case .enCurso: return "bolt.circle.fill"
        case .esperandoRespuesta: return "questionmark.bubble.fill"
        case .pendiente, .enCola: return "clock"
        }
    }
}
