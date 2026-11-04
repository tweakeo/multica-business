import SwiftUI
import TLSCore
import TLSDesign

/// «+ Nuevo» ya enlazado (§3.4, §5.3): crea una reunión, propuesta, proyecto, factura o tarea con su plantilla
/// (`PlantillaMotor.preparar`, o `TaskStore.crear` en las tareas), con la relación puesta, y entra en la nueva.
/// Si hay varias oportunidades abiertas, pregunta cuál. Si la plantilla es de nombre fijo y ya existe
/// (`PlantillaError.yaExiste`), ofrece «Completar la que hay». Si la creación pierde la carrera con otro
/// cambio, la vuelve a preparar con una foto nueva sin enseñar el error.
struct NuevoEnlazado: View {
    let opcion: OpcionNuevo
    let desde: VaultPath
    let modelo: FichaModelo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navegar) private var navegar
    @State private var titulo = ""
    @State private var fecha = Date()
    @State private var oportunidad: VaultPath?
    @State private var creando = false

    /// Lo que se va a crear con lo que hay escrito ahora en la hoja.
    private var preparador: PreparadorNuevo {
        PreparadorNuevo(opcion: opcion, modelo: modelo, titulo: titulo, fecha: LocalDate(date: fecha), oportunidad: oportunidad)
    }
    private var pideTitulo: Bool { preparador.pideTitulo }
    private var etiquetaTitulo: String { preparador.etiquetaTitulo }
    private var usaOportunidad: Bool { preparador.usaOportunidad }
    private var oportunidades: [FichaGrafo] { preparador.oportunidades }

    var body: some View {
        let estado = preparador.estado()
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            HStack(spacing: TLSEspacio.e12) {
                Image(systemName: opcion.tipo.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(TLSPaleta.sobrePrincipal.color)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(TLSPaleta.principal.color))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opcion.nuevoTitulo).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Text("Nace ya enlazado con \(modelo.ficha?.nombre ?? "esta ficha"). El nombre lo pone la plantilla.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            if opcion.plantilla == "recibo-de-cobro", let f = modelo.ficha {
                Label("Un cobro solo lo confirma una persona: al crear el recibo, lo confirmas tú (\(modelo.sesion.persona)), con el movimiento del banco delante. Será de \(FormatoFicha.euros(f.texto("total")) ?? "su total") y con fecha de hoy; luego puedes cambiarlos en Propiedades.",
                      systemImage: "person.badge.shield.checkmark")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pideTitulo {
                TextField(etiquetaTitulo, text: $titulo, prompt: Text(etiquetaTitulo))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(etiquetaTitulo)
            }
            if opcion.tipo == .meeting {
                DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .environment(\.locale, Locale(identifier: "es_ES"))
            }
            if !oportunidades.isEmpty, usaOportunidad {
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo("Oportunidad")
                    Picker("Oportunidad", selection: $oportunidad) {
                        if opcion.tipo != .proposal && opcion.tipo != .project && opcion.tipo != .quote { Text("Ninguna").tag(VaultPath?.none) }
                        ForEach(oportunidades) { o in
                            Text("\(o.nombre) · \(o.estado ?? "")").tag(Optional(o.ruta))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }
            switch estado {
            case .lista(let nota):
                let enlaces = PreparadorNuevo.enlaces(nota)
                if !enlaces.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Rotulo("Nace enlazado con")
                        FlujoChips(espacio: 6) {
                            ForEach(enlaces, id: \.self) { (e: [String]) in
                                HStack(spacing: 4) {
                                    Text(e[0]).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                    Text(e[1]).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                                }
                                .padding(.horizontal, 10).frame(minHeight: 28)
                                .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Se llamará «\(nota.titulo)».").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                    Text("Dónde: \(nota.ruta.parent?.raw ?? "")").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    if !nota.faltan.isEmpty {
                        Text("Quedan por rellenar: \(nota.faltan.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ")).")
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
            case .bloqueada(let motivo, let abrir):
                Label(motivo, systemImage: "lock")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let abrir {
                    let esFactura = modelo.grafo?.ficha(abrir)?.tipo == .invoice
                    Button(esFactura ? "Abrir la factura para confirmar el cobro" : "Abrirlo") {
                        dismiss(); navegar(.ficha(abrir), modo: .entrar)
                    }
                    .tlsBoton(.secundario)
                }
            case .yaExiste(let ruta):
                Label("Ya existe «\(ruta.stem)». Puedes completarla con la plantilla: solo se añade lo que le falta.", systemImage: "doc.on.doc")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            case .falta(let motivo):
                Text(motivo).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                if case .yaExiste(let ruta) = estado {
                    Button("Abrirla") { dismiss(); navegar(.ficha(ruta), modo: .entrar) }.tlsBoton(.secundario)
                    Button("Completar la que hay") { Task { await completar(ruta) } }
                        .tlsBoton(.principal).keyboardShortcut(.defaultAction)
                        .disabled(creando || !modelo.puedeEscribir)
                } else {
                    BotonPrincipal("Crear", motivoDesactivado: motivo(estado)) { Task { await crear() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 560)
        .background(TLSPaleta.superficieElevada.color)
        .onAppear {
            oportunidad = oportunidades.count == 1 || [.proposal, .quote, .project].contains(opcion.tipo) ? oportunidades.first?.ruta : nil
            if modelo.tipo == .opportunity { oportunidad = modelo.ruta }
            // El correo de envío de una factura ya lleva su asunto.
            if modelo.tipo == .invoice, opcion.tipo == .draft, titulo.isEmpty, let f = modelo.ficha {
                titulo = "Factura \(f.numero ?? f.nombre)"
            }
        }
        .task { await modelo.almacen.actualizar() }
    }

    private func motivo(_ e: Estado) -> String? {
        if creando { return "Creando…" }
        if !modelo.puedeEscribir { return modelo.motivoSoloLectura.map { "No se puede crear: \($0)" } }
        switch e {
        case .lista: return nil
        case .bloqueada(let m, _), .falta(let m): return m
        case .yaExiste: return "Ya existe"
        }
    }

    typealias Estado = PreparadorNuevo.Estado

    // MARK: Escribir

    private func crear() async {
        guard !creando else { return }
        creando = true
        defer { creando = false }
        guard let ruta = await preparador.crear() else { return }
        dismiss()
        navegar(.ficha(ruta), modo: .entrar)
    }

    private func completar(_ ruta: VaultPath) async {
        guard EdicionRelaciones.comprobarEscritura(modelo.sesion), let foto = modelo.almacen.foto else { return }
        do {
            let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: modelo.sesion.persona))
            guard let plan = try motor.aplicar(opcion.plantilla, a: ruta, autor: modelo.sesion.autor) else {
                modelo.sesion.aviso = Aviso("«\(ruta.stem)» ya tiene todo lo de la plantilla.", estado: .bien)
                dismiss()
                return
            }
            try await modelo.sesion.escribir(plan: plan, aviso: "Completé «\(ruta.stem)» con la plantilla")
            modelo.almacen.invalidar()
            dismiss()
            navegar(.ficha(ruta), modo: .entrar)
        } catch let e as PlantillaError {
            modelo.sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch {}
    }
}

/// Renombrar una ficha (⋯ › Renombrar): actualiza todos los enlaces que apuntan a ella, también los de las
/// propiedades de otras fichas, en un solo cambio con Deshacer (`LinkRefactor`).
struct RenombrarFicha: View {
    let modelo: FichaModelo
    @Environment(\.dismiss) private var dismiss
    @State private var nombre = ""
    @State private var resumen: String?
    @State private var problema: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text("Renombrar «\(modelo.ficha?.nombre ?? modelo.ruta.stem)»").tlsTexto(TLSTipo.tituloModulo)
                .accessibilityAddTraits(.isHeader)
            TextField("Nombre del fichero", text: $nombre, prompt: Text("Nombre del fichero"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: nombre) { calcular() }
            if let resumen { Text(resumen).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
            if let problema { Text(problema).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.mal.color) }
            Text("El nombre que se ve sale de «nombre» en sus propiedades; aquí cambias el del fichero y la app actualiza los enlaces.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Button("Renombrar") { Task { await renombrar() } }.tlsBoton(.principal).keyboardShortcut(.defaultAction)
                    .disabled(problema != nil || nombre.isEmpty || nombre == modelo.ruta.stem || !modelo.puedeEscribir)
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 480)
        .onAppear { nombre = modelo.ruta.stem; calcular() }
    }

    private func preview() throws -> RefactorPreview? {
        guard let foto = modelo.almacen.foto else { return nil }
        let n = nombre.hasSuffix(".md") ? nombre : nombre + ".md"
        return try LinkRefactor(snapshot: foto).renombrar(modelo.ruta, a: n, opciones: .init(autor: modelo.sesion.autor))
    }

    private func calcular() {
        guard nombre != modelo.ruta.stem, !nombre.isEmpty else { resumen = nil; problema = nil; return }
        do {
            let p = try preview()
            resumen = p?.resumen
            problema = p.map { $0.esSeguro ? nil : ($0.problemas.first?.motivo ?? "No se puede renombrar sin romper enlaces.") } ?? nil
        } catch {
            resumen = nil
            problema = error.localizedDescription
        }
    }

    private func renombrar() async {
        guard EdicionRelaciones.comprobarEscritura(modelo.sesion), let p = try? preview(), p.esSeguro else { return }
        _ = try? await modelo.sesion.escribir(plan: p.plan, aviso: p.avisoHecho)
        modelo.almacen.invalidar()
        dismiss()
    }
}

/// Prepara y crea lo de «+ Nuevo» ya enlazado (lo usa la hoja `NuevoEnlazado` y lo prueban las pruebas): qué se
/// pregunta, el plan de la plantilla (o de `TaskStore` en las tareas) y la escritura con Deshacer.
@MainActor
struct PreparadorNuevo {
    let opcion: OpcionNuevo
    let modelo: FichaModelo
    var titulo: String = ""
    var fecha: LocalDate? = nil
    var oportunidad: VaultPath? = nil

    enum Estado {
        case lista(PlantillaMotor.NotaPreparada)
        case bloqueada(String, abrir: VaultPath?)
        case yaExiste(VaultPath)
        case falta(String)
    }

    // MARK: Qué se pregunta

    /// Plantillas con nombre fijo (no se pregunta el título).
    static let nombreFijo: Set<String> = ["recibo-de-cobro", "recordatorio-de-cobro"]

    var pideTitulo: Bool {
        guard !Self.nombreFijo.contains(opcion.plantilla) else { return false }
        return [.task, .draft, .contact, .organization, .incident].contains(opcion.tipo) || opcion.plantilla == "reunion"
    }

    var etiquetaTitulo: String {
        switch opcion.tipo {
        case .task: "Qué hay que hacer"
        case .draft: "Asunto del correo"
        case .contact, .organization: "Nombre"
        case .meeting: "De qué es la reunión"
        default: "Título"
        }
    }

    var usaOportunidad: Bool {
        modelo.tipo != .opportunity && [.meeting, .proposal, .quote, .project, .invoice, .task].contains(opcion.tipo)
            && [.contact, .organization].contains(modelo.tipo)
    }

    /// Las oportunidades abiertas de esta ficha (y la Ganada sin proyecto, para crear el proyecto).
    var oportunidades: [FichaGrafo] {
        modelo.relacionados([.opportunity]).map(\.ficha).filter {
            EstadosDeFicha.abierta(.opportunity, estado: $0.estado) || (opcion.tipo == .project && TextFolding.fold($0.estado ?? "") == "ganada")
        }
    }

    /// Las relaciones con las que nace (de las propiedades del texto preparado): «Empresa · Talleres Martín…».
    static func enlaces(_ nota: PlantillaMotor.NotaPreparada) -> [[String]] {
        let fm = NoteDocument(text: nota.texto).frontmatter
        return fm.properties.compactMap { p -> [String]? in
            guard EsquemaRelaciones.clavesDeRelacion.contains(p.key) else { return nil }
            let valores: [String]
            switch p.value {
            case .text(let t): valores = [t]
            case .list(let l): valores = l
            default: return nil
            }
            let nombres = valores.filter { $0.contains("[[") || $0.contains("](") }.map { LinkParser.plainText($0) }.filter { !$0.isEmpty }
            guard !nombres.isEmpty else { return nil }
            return [InspectorFicha.etiqueta(p.key), nombres.joined(separator: ", ")]
        }
    }

    // MARK: Preparar

    func estado() -> Estado {
        guard let foto = modelo.almacen.foto, let grafo = modelo.grafo, let f = modelo.ficha else { return .falta("Leyendo la carpeta…") }
        let opo = modelo.tipo == .opportunity ? modelo.ruta : oportunidad
        // Proyecto de entrega: nace de una oportunidad con el cobro confirmado, y como mucho uno por oportunidad.
        if opcion.tipo == .project {
            guard let opo else { return .bloqueada("Elige su oportunidad: un proyecto de entrega siempre nace de una.", abrir: nil) }
            if let ya = grafo.origenes(de: opo, propiedad: "oportunidad", tipo: .project).first {
                return .bloqueada("Esta oportunidad ya tiene proyecto: «\(grafo.ficha(ya)?.nombre ?? ya.stem)». Una oportunidad tiene como mucho un proyecto.", abrir: ya)
            }
            let c = grafo.cobroConfirmado(oportunidad: opo)
            if !c.confirmado {
                let factura = grafo.origenes(de: opo, propiedad: "oportunidad", tipo: .invoice).first
                return .bloqueada("El proyecto nace al confirmar el cobro, para no empezar a trabajar sin haber cobrado. " + c.motivo, abrir: factura)
            }
        }
        if [.proposal, .quote].contains(opcion.tipo), opo == nil {
            return .falta("Elige su oportunidad: una propuesta siempre cuelga de una.")
        }
        // Un cobro se confirma una vez: si la factura ya tiene recibo confirmado, se abre ese.
        if opcion.plantilla == "recibo-de-cobro", f.tipo == .invoice {
            if TextFolding.fold(f.estado ?? "") == "cobrada" {
                return .bloqueada("Esta factura ya está cobrada.", abrir: nil)
            }
            if let r = grafo.origenes(de: f.ruta, propiedad: "factura", tipo: .receipt).first {
                return .bloqueada("Su cobro ya está confirmado: «\(grafo.ficha(r)?.nombre ?? r.stem)».", abrir: r)
            }
        }
        if pideTitulo && titulo.trimmingCharacters(in: .whitespaces).isEmpty && opcion.plantilla != "reunion" {
            return .falta("Escribe \(etiquetaTitulo.lowercased()).")
        }
        do {
            if opcion.tipo == .task {
                return .lista(try TaskStore(snapshot: foto).crear(nuevaTarea(f, opo: opo, grafo: grafo)))
            }
            return .lista(try PlantillaMotor(snapshot: foto, opciones: .init(yo: modelo.sesion.persona)).preparar(peticion(f, opo: opo, grafo: grafo, foto: foto)))
        } catch PlantillaError.yaExiste(let r) {
            return .yaExiste(VaultPath(r))
        } catch let e as PlantillaError {
            return .falta(e.localizedDescription)
        } catch let e as TareaError {
            return .falta(e.localizedDescription)
        } catch {
            return .falta(error.localizedDescription)
        }
    }

    func nuevaTarea(_ f: FichaGrafo, opo: VaultPath?, grafo: GrafoRelaciones) -> NuevaTarea {
        let empresa = f.tipo == .organization ? f.ruta : grafo.destinos(de: f.ruta, propiedad: "empresa").first
        var props: [Property] = []
        if f.tipo == .task, let foto = modelo.almacen.foto {
            props.append(Property(key: "padre", value: .text(EditorDeRelaciones(snapshot: foto, grafo: grafo).enlace(a: f.ruta))))
        }
        let proyecto: VaultPath? = f.tipo == .project ? f.ruta : (f.tipo == .task ? grafo.destinos(de: f.ruta, propiedad: "proyecto").first : nil)
        return NuevaTarea(titulo: titulo, proyecto: proyecto, oportunidad: proyecto == nil ? opo : nil, empresa: empresa,
                          estado: .porHacer, autor: modelo.sesion.autor, propiedades: props)
    }

    func peticion(_ f: FichaGrafo, opo: VaultPath?, grafo: GrafoRelaciones, foto: VaultSnapshot) -> PlantillaMotor.Peticion {
        var contexto: [String: VaultPath] = [:]
        if let rol = ContextoPlantilla.papeles[f.tipo.rawValue] { contexto[rol] = f.ruta }
        if let opo { contexto["oportunidad"] = opo }
        var valores: [String: String] = [:]
        let t = titulo.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { valores["titulo"] = t }
        if opcion.tipo == .meeting { valores["fecha"] = (fecha ?? modelo.hoy).description }
        if opcion.plantilla == "recibo-de-cobro" {
            // El cobro de toda la factura, hoy; lo confirma la persona que lo crea (`confirmado_por: {{yo}}`).
            if let total = f.texto("total") { valores["importe"] = total }
            valores["fecha"] = modelo.hoy.description
        }
        if opcion.tipo == .meeting, t.isEmpty, opcion.plantilla == "reunion" {
            valores["titulo"] = "Reunión con \(f.nombre)"
        }
        var poner: [Property] = []
        if opcion.tipo == .meeting, f.tipo == .contact {
            poner.append(Property(key: "personas", value: .list([EditorDeRelaciones(snapshot: foto, grafo: grafo).enlace(a: f.ruta)])))
        }
        if opcion.plantilla == "recibo-de-cobro" {
            // El importe va como número (`importe: 181.50`), no como texto con «€»; la fecha, la de hoy.
            if let importe = f.texto("total") { poner.append(Property(key: "importe", value: .text(importe))) }
            poner.append(Property(key: "fecha", value: .text(modelo.hoy.description)))
        }
        return PlantillaMotor.Peticion(plantilla: opcion.plantilla, desde: opo ?? f.ruta, contexto: contexto, valores: valores,
                                       poner: poner, autor: modelo.sesion.autor)
    }

    // MARK: Escribir

    /// El plan de la plantilla y, al confirmar un cobro, la factura pasa a Cobrada en el mismo paso (todo o nada,
    /// un solo Deshacer): el recibo lo crea una persona, así que el cobro queda confirmado por ella.
    func planCompleto(_ nota: PlantillaMotor.NotaPreparada) -> WritePlan {
        guard opcion.plantilla == "recibo-de-cobro", let f = modelo.ficha, f.tipo == .invoice else { return nota.plan }
        let estado = Property(key: "estado", value: .text(EstadosDeFicha.escrito("Cobrada", como: f.estado)))
        return WritePlan(autor: nota.plan.autor, descripcion: "Confirmar el cobro de \(f.numero ?? f.nombre)",
                         ops: nota.plan.ops + [.mergeFrontmatter(f.ruta, set: [estado], unset: [])])
    }

    /// Crea la nota con su plan (todo o nada) y deja «Deshacer». Si pierde la carrera con otro cambio, la vuelve a
    /// preparar con una foto nueva. Devuelve la ruta creada (`nil` si no se creó: el aviso ya lo dice).
    func crear() async -> VaultPath? {
        guard EdicionRelaciones.comprobarEscritura(modelo.sesion) else { return nil }
        for intento in 0..<2 {
            guard case .lista(let nota) = estado() else { return nil }
            do {
                let bus = try modelo.sesion.busParaEscribir()
                let plan = planCompleto(nota)
                let r = try await bus.ejecutar(plan)
                let aviso = opcion.plantilla == "recibo-de-cobro"
                    ? "Confirmé el cobro de \(modelo.ficha?.numero ?? modelo.ficha?.nombre ?? "la factura"): \(nota.titulo)"
                    : "Creé «\(nota.titulo)» ya enlazado con \(modelo.ficha?.nombre ?? "esta ficha")"
                modelo.sesion.registrarDeshacer(r, descripcion: plan.descripcion, aviso: aviso)
                modelo.almacen.invalidar()
                if r.conflicto != nil { return nil }
                return nota.ruta
            } catch WriteError.destinoOcupado(_) where intento == 0 {
                // Otra creación llegó antes: se vuelve a preparar con una foto nueva.
                modelo.almacen.invalidar()
                await modelo.almacen.actualizar()
            } catch WriteError.cambioExterno(_) where intento == 0 {
                modelo.almacen.invalidar()
                await modelo.almacen.actualizar()
            } catch {
                modelo.sesion.aviso = Aviso(error.localizedDescription, estado: .mal)
                return nil
            }
        }
        return nil
    }
}
