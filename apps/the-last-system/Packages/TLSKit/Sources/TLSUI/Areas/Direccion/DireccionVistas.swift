import SwiftUI
import TLSCore
import TLSDesign

/// Mapa 6×6 (SISTEMAS DI3): las seis áreas por las seis etapas, la etapa de cada una marcada y el cuello dicho en
/// texto (el color nunca va solo).
struct MapaMadurezVista: View {
    let mapa: MapaMadurez

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text(mapa.textoCuello).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mapa.cuello")
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Text("Área").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .frame(width: 230, alignment: .leading)
                        ForEach(etapas, id: \.num) { e in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Etapa \(e.num)").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                                Text(e.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                            }
                            .frame(width: 104, alignment: .leading)
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(AreaCode.allCases, id: \.self) { a in fila(a) }
                }
                .padding(.bottom, 4)
            }
            Text(mapa.veredicto).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if !mapa.camino.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("El camino").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    ForEach(mapa.camino) { t in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(t.orden).").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            Text("\(t.area.etiquetaNumerada): \(t.porque)").tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
                            if t.esCuello { PastillaEstado(.mal, palabra: "Cuello") }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("direccion.mapa")
        .tutorialAnchor(.direccionMapa)
    }

    /// Las seis etapas (con el nombre del estándar si está cargado).
    private var etapas: [(num: Int, nombre: String)] {
        (1...6).map { n in (n, mapa.etapas.first { $0.num == n }?.nombre ?? "") }
    }

    private func fila(_ a: AreaCode) -> some View {
        let etapa = mapa.filas.first { $0.area == a }
        let esCuello = mapa.cuello?.area == a
        return GridRow {
            HStack(spacing: 6) {
                IconoArea(a.tlsArea, tamano: 24)
                Text(a.etiquetaNumerada).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                if esCuello { PastillaEstado(.mal, palabra: "Cuello") }
            }
            .frame(width: 230, alignment: .leading)
            ForEach(etapas, id: \.num) { e in celda(a, etapa: e.num, actual: etapa?.etapa, esCuello: esCuello) }
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta(a, etapa: etapa, esCuello: esCuello))
    }

    private func celda(_ a: AreaCode, etapa e: Int, actual: Int?, esCuello: Bool) -> some View {
        let marcada = mapa.marcada(a, etapa: e)
        let pasada = (actual ?? 0) > e
        let forma = RoundedRectangle(cornerRadius: 8, style: .continuous)
        // La celda marcada: borde y palabra en la tinta del área (que se lee en claro y en oscuro); el color nunca va solo.
        return ZStack {
            forma.fill(pasada || marcada ? a.tlsArea.relleno.color.opacity(0.2) : TLSPaleta.bandeja.color)
            if marcada {
                Text(esCuello ? "Aquí · cuello" : "Aquí").tlsTexto(TLSTipo.secundario).fontWeight(.semibold)
                    .foregroundStyle(a.tlsArea.tinta.color)
            }
        }
        .overlay(forma.strokeBorder(marcada ? (esCuello ? TLSEstado.mal.color.color : a.tlsArea.tinta.color) : .clear, lineWidth: 2))
        .frame(width: 104, height: 32)
    }

    private func etiqueta(_ a: AreaCode, etapa: EtapaArea?, esCuello: Bool) -> String {
        var t = a.etiquetaNumerada + ": "
        if let e = etapa {
            let nombre = mapa.etapas.first { $0.num == e.etapa }?.nombre
            t += "etapa \(e.etapa) de 6" + (nombre.map { " (\($0))" } ?? "")
        } else {
            t += "sin dato de etapa"
        }
        if esCuello { t += ". Es el cuello" }
        return t + "."
    }
}

/// Los objetivos con su ritmo (DI2): cifra frente a meta, lo esperado a día de hoy y cuántos proyectos cuelgan.
struct ObjetivosDireccion: View {
    let objetivos: [RitmoObjetivo]
    let proyectos: [VaultPath: Int]
    let hoy: LocalDate
    let alAbrir: (VaultPath) -> Void

    var body: some View {
        if objetivos.isEmpty {
            Text("Aún no hay objetivos. Se escriben en 1 · Dirección/Objetivos con su meta, su periodo y el número que los mide.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(objetivos.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                    fila(r)
                }
            }
            .accessibilityIdentifier("direccion.objetivos")
        }
    }

    private func fila(_ r: RitmoObjetivo) -> some View {
        let o = r.objetivo
        let n = proyectos[o.ruta] ?? 0
        let detalle = [o.area?.etiquetaNumerada, o.periodo, o.medidoPor.map { "se mide con \($0)" },
                       n == 0 ? "ningún proyecto" : (n == 1 ? "1 proyecto" : "\(n) proyectos")]
            .compactMap { $0 }.joined(separator: " · ")
        return Button { alAbrir(o.ruta) } label: {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                    if let m = r.motivo, r.real == nil {
                        Text(m).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                    }
                }
                Spacer(minLength: TLSEspacio.e8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.valor(r.real, unidad: r.unidad)).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                    Text(o.meta.map { "meta \(Self.valor($0, unidad: r.unidad))" } ?? "Sin meta")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    if let e = r.esperado, r.real != nil {
                        Text("hoy tocaría \(Self.valor(e, unidad: r.unidad))").tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                RhythmBadge(OperacionComun.ritmo(r.estado)).frame(width: 104, alignment: .trailing)
            }
            .padding(.vertical, TLSEspacio.e8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(o.titulo). \(Self.valor(r.real, unidad: r.unidad))"
            + (o.meta.map { " de \(Self.valor($0, unidad: r.unidad))" } ?? ", sin meta")
            + ". Ritmo: \(OperacionComun.ritmo(r.estado).palabra). \(detalle).")
        .accessibilityAddTraits(.isButton)
    }

    /// «4.200 €», «67 %», «2,5 meses»; sin dato, «Sin dato».
    static func valor(_ v: Double?, unidad: String) -> String {
        guard let v, v.isFinite else { return "Sin dato" }
        switch unidad {
        case "€": return FormatoBase.euros(v, redondo: v == v.rounded())
        case "%": return "\(FormatoBase.cifra(v, decimales: 0)) %"
        case "", "n": return FormatoBase.cifra(v)
        default: return "\(FormatoBase.cifra(v)) \(unidad)"
        }
    }
}

/// La cronología de `Decisiones.md`: lo decidido, por qué, el área y las sustituidas marcadas.
struct CronologiaDecisiones: View {
    let decisiones: [LineaDecision]
    let hoy: LocalDate

    var body: some View {
        if decisiones.isEmpty {
            Text("Aún no hay decisiones registradas. Cada decisión se escribe una vez, con su fecha y su porqué, en Decisiones.md.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(decisiones.enumerated()), id: \.offset) { i, d in
                    if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).padding(.leading, 96) }
                    fila(d)
                }
            }
            .accessibilityIdentifier("direccion.decisiones")
        }
    }

    private func fila(_ d: LineaDecision) -> some View {
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            Text(d.fecha.map { FormatoFicha.fechaConDia($0, hoy: hoy) } ?? "Sin fecha")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(d.decision).tlsTexto(TLSTipo.interfazFuerte)
                        .foregroundStyle(d.sustituida ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                        .strikethrough(d.sustituida)
                        .fixedSize(horizontal: false, vertical: true)
                    if d.sustituida { PastillaEstado(.sinDato, palabra: "Sustituida") }
                }
                if let p = d.porque {
                    Text("Por qué: \(p)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let extra = [d.area, OperacionComun.nombre(d.origen)].compactMap { $0 }.filter { $0 != "—" }
                if !extra.isEmpty {
                    Text(extra.joined(separator: " · ")).tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                }
            }
        }
        .padding(.vertical, TLSEspacio.e8)
        .accessibilityElement(children: .combine)
    }
}

/// Los proyectos en curso sin objetivo (DIR-03): se guardaron, pero quedan en atención con sus dos salidas.
struct AtencionesDIR03: View {
    let barras: [BarraCronograma]
    let objetivos: [FotoMetricas.Objetivo]
    let motivoSoloLectura: String?
    let alColgar: (BarraCronograma, VaultPath) -> Void
    let alSeguirSin: (BarraCronograma) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            ForEach(barras) { b in
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    AvisoEnLinea(b.atencion?.mensaje ?? "«\(b.nombre)» está en curso sin objetivo.", estado: .atencion)
                    HStack(spacing: TLSEspacio.e8) {
                        Menu {
                            ForEach(opciones(b), id: \.ruta) { o in
                                Button(o.titulo) { alColgar(b, o.ruta) }
                            }
                        } label: {
                            Text("Colgar de un objetivo")
                        }
                        .menuStyle(.button)
                        .tlsBoton(.secundario)
                        .fixedSize()
                        .disabled(motivoSoloLectura != nil || opciones(b).isEmpty)
                        .accessibilityIdentifier("dir03.colgar")
                        Button("Seguir sin objetivo") { alSeguirSin(b) }
                            .tlsBoton(.secundario)
                            .disabled(motivoSoloLectura != nil)
                            .help("Escribe «sin_objetivo: sí» en el proyecto y deja de avisar")
                            .accessibilityIdentifier("dir03.seguirSin")
                    }
                    if let m = motivoSoloLectura {
                        Text(m).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .padding(TLSEspacio.e12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSEstado.atencion.tinte.color))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("dir03.\(b.ruta.raw)")
            }
        }
    }

    /// Los objetivos que ofrece la atención (los abiertos de la carpeta).
    private func opciones(_ b: BarraCronograma) -> [FotoMetricas.Objetivo] {
        if case .elegirObjetivo(_, let rutas)? = b.atencion?.alternativas.first(where: {
            if case .elegirObjetivo = $0.accion { return true }
            return false
        })?.accion {
            let claves = Set(rutas.map { TextFolding.pathKey($0.raw) })
            let lista = objetivos.filter { claves.contains(TextFolding.pathKey($0.ruta.raw)) }
            if !lista.isEmpty { return lista }
        }
        return objetivos
    }
}

/// Registrar una decisión en `Decisiones.md` (solo se añade una línea; se deshace).
struct RegistrarDecisionHoja: View {
    let hoy: LocalDate
    let motivoSoloLectura: String?
    let guardar: (NuevaDecision) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var decision = ""
    @State private var porque = ""
    @State private var area: AreaCode? = .direccion
    @State private var error: String?
    @State private var guardando = false

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text("Registrar decisión").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
            Text("Se añade una línea a Decisiones.md con la fecha de hoy (\(FormatoFicha.fechaConDia(hoy))). Lo de antes no se toca.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Qué decides").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                TextField("Por ejemplo: la Renta pasa a 95 € desde enero", text: $decision, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    .accessibilityLabel("Qué decides")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Por qué").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                TextField("El motivo, en una frase", text: $porque, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    .accessibilityLabel("Por qué")
            }
            Picker("Área", selection: $area) {
                Text("Sin área").tag(AreaCode?.none)
                ForEach(AreaCode.allCases, id: \.self) { a in Text(a.etiquetaNumerada).tag(AreaCode?.some(a)) }
            }
            .frame(maxWidth: 320)
            if let error { AvisoEnLinea(error, estado: .mal) }
            if let m = motivoSoloLectura { AvisoEnLinea("No se puede registrar: \(m).", estado: .sinDato) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction).tlsBoton(.secundario)
                Button("Registrar") { registrar() }
                    .keyboardShortcut(.defaultAction)
                    .tlsBoton(.principal)
                    .disabled(decision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || motivoSoloLectura != nil || guardando)
                    .accessibilityIdentifier("decision.registrar")
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 520)
    }

    private func registrar() {
        let d = NuevaDecision(fecha: hoy, decision: decision.trimmingCharacters(in: .whitespacesAndNewlines),
                              porque: porque.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : porque,
                              area: area?.nombre)
        guardando = true
        Task {
            let e = await guardar(d)
            guardando = false
            if let e { error = e } else { dismiss() }
        }
    }
}

/// «Plan de 4 semanas para el cuello»: la propuesta, semana a semana; nada se crea sin tu OK.
struct PlanCuelloHoja: View {
    let plan: PlanCuello
    let hoy: LocalDate
    let motivoSoloLectura: String?
    let crear: (Set<Int>) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var elegidas: Set<Int>
    @State private var error: String?
    @State private var guardando = false

    init(plan: PlanCuello, hoy: LocalDate, motivoSoloLectura: String?, crear: @escaping (Set<Int>) async -> String?) {
        self.plan = plan; self.hoy = hoy; self.motivoSoloLectura = motivoSoloLectura; self.crear = crear
        _elegidas = State(initialValue: Set(plan.semanas.map(\.numero)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text("Plan de 4 semanas para el cuello").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
            Text(plan.porque).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                ForEach(plan.semanas) { s in
                    Toggle(isOn: Binding(get: { elegidas.contains(s.numero) },
                                         set: { if $0 { elegidas.insert(s.numero) } else { elegidas.remove(s.numero) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Semana \(s.numero) · lunes \(FormatoFicha.fechaCorta(s.lunes, hoy: hoy))")
                                .tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                            Text(s.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                            Text(s.descripcion).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Text("Con tu OK se crean \(elegidas.count == 1 ? "1 tarea" : "\(elegidas.count) tareas") en \(plan.area.etiquetaNumerada), una por semana y planificada el lunes. Se deshace de una vez.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if let error { AvisoEnLinea(error, estado: .mal) }
            if let m = motivoSoloLectura { AvisoEnLinea("No se puede crear: \(m).", estado: .sinDato) }
            HStack {
                Spacer()
                Button("Ahora no") { dismiss() }.keyboardShortcut(.cancelAction).tlsBoton(.secundario)
                Button(elegidas.count == 1 ? "Crear 1 tarea" : "Crear \(elegidas.count) tareas") { aceptar() }
                    .keyboardShortcut(.defaultAction)
                    .tlsBoton(.principal)
                    .disabled(elegidas.isEmpty || motivoSoloLectura != nil || guardando)
                    .accessibilityIdentifier("plan.crear")
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 560)
    }

    private func aceptar() {
        guardando = true
        Task {
            let e = await crear(elegidas)
            guardando = false
            if let e { error = e } else { dismiss() }
        }
    }
}
