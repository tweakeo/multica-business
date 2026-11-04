import SwiftUI
import TLSCore
import TLSDesign

/// El panel fijo de propiedades de la tarea (DISENO §3.4): Estado, Prioridad, Responsable, Planificada (ENT-04: un
/// sábado o un domingo pasa al lunes y se dice), Vence (ningún asistente la mueve), Estimación y dedicadas, de dónde
/// cuelga y el Área en solo lectura con «Mover a…». Cada cambio es una línea, con Deshacer.
struct PanelPropiedadesTarea: View {
    let modelo: ModeloTarea
    let tarea: Tarea
    @Environment(\.navegar) private var navegar

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Rotulo("Propiedades")
            campo("Estado") { estado }
            campo("Prioridad") { prioridad }
            campo("Responsable") { responsable }
            campo("Planificada") {
                CampoFechaTarea(etiqueta: "Planificada", valor: tarea.planificada, hoy: modelo.hoy, puede: modelo.puedeEscribir) { d in
                    Task { await modelo.planificar(d) }
                }
                if let a = modelo.avisoPlanificada {
                    Label(a, systemImage: "calendar.badge.exclamationmark")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nunca en sábado ni domingo: pasa al lunes.").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            campo("Vence") {
                CampoFechaTarea(etiqueta: "Vence", valor: tarea.vence, hoy: modelo.hoy, puede: modelo.puedeEscribir) { d in
                    Task {
                        await modelo.cambiar("vence", a: d.map { .text($0.description) },
                                             aviso: d.map { "Vence " + FormatoFicha.cuando($0, hoy: modelo.hoy) } ?? "Sin fecha límite")
                    }
                }
                Text("La fecha límite real: ningún asistente la mueve.").tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if let f = modelo.ficha.ficha {
                HStack(alignment: .top, spacing: TLSEspacio.e12) {
                    ForEach(["estimacion_h", "dedicadas_h"], id: \.self) { k in
                        CampoPropiedad(modelo: modelo.ficha, ficha: f,
                                       propiedad: f.propiedades.properties.first { $0.key == k } ?? Property(key: k, value: .empty))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Divider().overlay(TLSPaleta.separador.color)
            contenedores
            area
            Divider().overlay(TLSPaleta.separador.color)
            masDatos
            Text(regla).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Propiedades de la tarea")
    }

    private func campo<C: View>(_ etiqueta: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(etiqueta).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            control()
        }
    }

    private var estado: some View {
        let actual = tarea.estado ?? .sinProgramar
        return Menu {
            ForEach(EstadoTarea.allCases, id: \.self) { e in
                Button(e.rawValue) { Task { await modelo.cambiarEstado(e) } }.disabled(e == actual)
            }
        } label: {
            PastillaEstado(actual.tlsEstado, palabra: tarea.estadoTexto ?? actual.rawValue)
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
        .disabled(!modelo.puedeEscribir)
        .accessibilityLabel("Estado: \(tarea.estadoTexto ?? actual.rawValue). Cambiar")
    }

    private var prioridad: some View {
        Menu(tarea.prioridad ?? "Sin prioridad") {
            ForEach(["Urgente", "Alta", "Media", "Baja"], id: \.self) { p in
                Button(p) { Task { await modelo.cambiar("prioridad", a: .text(p), aviso: "Prioridad: \(p)") } }
                    .disabled(tarea.prioridad == p)
            }
            Divider()
            Button("Sin prioridad") { Task { await modelo.cambiar("prioridad", a: nil, aviso: "Sin prioridad") } }
                .disabled(tarea.prioridad == nil)
        }
        .fixedSize()
        .disabled(!modelo.puedeEscribir)
        .accessibilityLabel("Prioridad: \(tarea.prioridad ?? "sin prioridad"). Cambiar")
    }

    private var responsable: some View {
        let opciones = ResponsablesTarea.opciones(grafo: modelo.ficha.grafo, persona: modelo.sesion.persona)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ResponsableTarea(identificador: tarea.responsable, tamano: 22)
                Menu(tarea.responsable.map(Responsables.nombre(de:)) ?? "Nadie") {
                    ForEach(opciones, id: \.id) { o in
                        Button(o.nombre) { Task { await modelo.cambiar("responsable", a: .text(o.id), aviso: "La lleva \(o.nombre)") } }
                    }
                    Divider()
                    Button("Sin responsable") { Task { await modelo.cambiar("responsable", a: nil, aviso: "Sin responsable") } }
                }
                .fixedSize()
                .disabled(!modelo.puedeEscribir)
                .help("Se guarda con un identificador que no cambia; aquí ves el nombre")
                .accessibilityLabel("Responsable: \(tarea.responsable.map(Responsables.nombre(de:)) ?? "nadie"). Cambiar")
            }
            if tarea.responsable?.lowercased().hasPrefix("agente:") == true, tarea.estado == .sinProgramar || tarea.estado == nil {
                Text("Empezará cuando la pases a Por hacer.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }

    @ViewBuilder private var contenedores: some View {
        let grafo = modelo.ficha.grafo
        let proyecto = (tarea.proyecto ?? tarea.proyectoPorRuta).flatMap { modelo.sesion.esPrivado($0) ? nil : $0 }
        let oportunidad = tarea.oportunidad.flatMap { modelo.sesion.esPrivado($0) ? nil : $0 }
        let empresa = tarea.empresa.flatMap { modelo.sesion.esPrivado($0) ? nil : $0 }
        campo("Proyecto u oportunidad") {
            if proyecto == nil, oportunidad == nil {
                Text("Sin proyecto ni oportunidad").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach([proyecto, oportunidad].compactMap { $0 }, id: \.self) { d in
                Button(grafo?.ficha(d)?.nombre ?? (d.name == "Proyecto.md" ? d.parent?.name ?? d.stem : d.stem)) {
                    navegar(modelo.sesion.destino(para: d), modo: .entrar)
                }
                .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
                .vistaPrevia(ruta: d, sesion: modelo.sesion)
            }
        }
        if let e = empresa {
            campo("Empresa") {
                Button(grafo?.ficha(e)?.nombre ?? e.stem) { navegar(modelo.sesion.destino(para: e), modo: .entrar) }
                    .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
                    .vistaPrevia(ruta: e, sesion: modelo.sesion)
            }
        }
    }

    private var area: some View {
        campo("Área") {
            HStack(spacing: 6) {
                if let a = tarea.area { IconoArea(a.tlsArea, tamano: 16) }
                Text(tarea.area.map { "\($0.numero) · \($0.nombre)" } ?? "Sin área").tlsTexto(TLSTipo.interfazMedia)
                    .foregroundStyle(TLSPaleta.texto.color)
                Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityLabel("Solo lectura")
                Spacer(minLength: 0)
                moverA
            }
            Text("Sale de su carpeta. Para cambiarla, se mueve la tarea.").tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var moverA: some View {
        let proyectos = modelo.proyectos
        let enProyecto = tarea.proyectoPorRuta
        return Menu("Mover a…") {
            Section("Sin proyecto, en un área") {
                ForEach(AreaCode.allCases, id: \.self) { a in
                    Button("\(a.numero) · \(a.nombre)") { Task { _ = await modelo.mover(a: .area(a)) } }
                        .disabled(a == tarea.area && enProyecto == nil)
                }
            }
            if !proyectos.isEmpty {
                Section("A un proyecto") {
                    ForEach(proyectos, id: \.ruta) { p in
                        Button(p.nombre + (p.area.map { " · \($0.nombre)" } ?? "")) { Task { _ = await modelo.mover(a: .proyecto(p.ruta)) } }
                            .disabled(enProyecto == p.ruta)
                    }
                }
            }
        }
        .fixedSize()
        .disabled(!modelo.puedeEscribir)
        .help("Mueve la ficha a otra carpeta Tareas (con sus enlaces) y le pone el área y el proyecto de allí")
        .accessibilityLabel("Mover a otra área o a un proyecto")
    }

    @ViewBuilder private var masDatos: some View {
        let fm = modelo.ficha.ficha?.propiedades
        let filas: [(String, String)] = [
            ("Función", fm?.text("capacidad")),
            ("Origen", tarea.origen.map(Self.origen)),
            ("Creada", tarea.creada.map { FormatoFicha.fechaConDia($0, hoy: modelo.hoy) + (fm?.text("creada_por").map { " · " + ActividadDeTarea.nombre($0) } ?? "") }),
            ("Cerrada", tarea.cerrada.map { FormatoFicha.fechaConDia($0, hoy: modelo.hoy) }),
        ].compactMap { k, v in v.map { (k, $0) } }
        ForEach(filas, id: \.0) { k, v in
            HStack(alignment: .firstTextBaseline) {
                Text(k).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).frame(width: 64, alignment: .leading)
                Text(v).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// `regla:contacto.creado` → «Una regla (contacto creado)».
    static func origen(_ o: String) -> String {
        let t = o.trimmingCharacters(in: .whitespaces)
        if t == "manual" { return "A mano" }
        if t == "importacion" { return "Importada" }
        if t.hasPrefix("regla:") { return "Una regla (" + t.dropFirst(6).replacingOccurrences(of: ".", with: " ") + ")" }
        if t.hasPrefix("rutina:") { return "La rutina «" + t.dropFirst(7) + "»" }
        if t.hasPrefix("agente:") { return Responsables.nombre(de: t) }
        return t
    }

    private var regla: String {
        if tarea.responsable?.lowercased().hasPrefix("agente:") == true {
            return "\(Responsables.nombre(de: tarea.responsable ?? "")) la coge cuando está Por hacer y ha llegado su día. Al terminar la deja En revisión: ningún asistente pone Hecha ni Cancelada."
        }
        return "La lleva una persona: la mueves tú cuando toque. Cambiar de estado nunca mueve el fichero."
    }
}

/// Una fecha de la tarea: la fecha escrita, «Cambiar…» con un calendario (y «Guardar»), y «Quitar».
struct CampoFechaTarea: View {
    let etiqueta: String
    let valor: LocalDate?
    let hoy: LocalDate
    let puede: Bool
    let guardar: (LocalDate?) -> Void
    @State private var abierto = false
    @State private var elegida = Date()

    var body: some View {
        HStack(spacing: 6) {
            Text(valor.map { FormatoFicha.fechaConDia($0, hoy: hoy) + ($0 == hoy ? " (hoy)" : "") } ?? "Sin fecha")
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(valor == nil ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
            Spacer(minLength: 0)
            Button(valor == nil ? "Poner…" : "Cambiar…") {
                elegida = (valor ?? hoy).date()
                abierto = true
            }
            .tlsBoton(.discreto)
            .disabled(!puede)
            .accessibilityLabel("\(valor == nil ? "Poner" : "Cambiar") \(etiqueta.lowercased())")
            .popover(isPresented: $abierto, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                    Text(etiqueta).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    DatePicker(etiqueta, selection: $elegida, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "es_ES"))
                    HStack {
                        Spacer()
                        Button("Cancelar") { abierto = false }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                        Button("Guardar") {
                            abierto = false
                            let d = LocalDate(date: elegida)
                            if d != valor { guardar(d) }
                        }
                        .tlsBoton(.principal, alto: 36)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(TLSEspacio.e16)
                .frame(width: 300)
            }
            if valor != nil {
                Button("Quitar") { guardar(nil) }
                    .tlsBoton(.discreto)
                    .disabled(!puede)
                    .accessibilityLabel("Quitar \(etiqueta.lowercased())")
            }
        }
    }
}
