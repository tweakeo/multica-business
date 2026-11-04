import SwiftUI
import TLSCore
import TLSDesign

/// Crea una ficha con su plantilla (§4.8, PLANTILLAS): prepara la nota con `PlantillaMotor` sobre una foto de
/// la carpeta y la escribe como un solo plan por `CommandBus` (con Deshacer). Si otra escritura le gana la
/// carrera, vuelve a prepararla con una foto nueva sin enseñar el error; si el nombre fijo ya existe, ofrece
/// completar la que hay.
@MainActor
enum CreadorFichas {
    /// Devuelve la ruta creada (`nil` si no se creó; el aviso ya dice por qué).
    static func crear(coleccion: ColeccionBase, peticion: PeticionNueva, sesion: VaultSession,
                      deshacer: UndoManager?) async -> VaultPath? {
        do {
            return try await intentar(coleccion: coleccion, peticion: peticion, sesion: sesion, deshacer: deshacer)
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .mal)
            return nil
        }
    }

    /// Como `crear`, pero lanza el error (la hoja lo enseña bajo los campos).
    static func intentar(coleccion: ColeccionBase, peticion: PeticionNueva, sesion: VaultSession,
                         deshacer: UndoManager?) async throws -> VaultPath? {
        guard let plantilla = coleccion.plantilla else {
            throw EdicionError.soloLectura(coleccion.motivoSinCrear ?? "Esta base no se crea desde aquí.")
        }
        guard let bus = sesion.bus else { throw sesion.entry.clase == .real ? WriteError.carpetaReal : WriteError.soloLectura }
        for intento in 0..<2 {
            guard let foto = await sesion.instantanea() else { throw WriteError.soloLectura }
            let registro = PlantillaRegistro.cargar(foto)
            let motor = PlantillaMotor(snapshot: foto, registro: registro,
                                       opciones: .init(yo: sesion.persona, reloj: Reloj.deCarpeta(foto)))
            let poner = peticion.poner.sorted { $0.key < $1.key }.map { Property(key: $0.key, value: .text($0.value)) }
            let p = PlantillaMotor.Peticion(plantilla: plantilla, contexto: peticion.contexto, valores: peticion.valores,
                                            poner: poner, autor: sesion.autor)
            let nota: PlantillaMotor.NotaPreparada
            do {
                nota = try motor.preparar(p)
            } catch PlantillaError.yaExiste(let ruta) {
                ofrecerCompletar(VaultPath(ruta), plantilla: plantilla, motor: motor, sesion: sesion, deshacer: deshacer)
                return nil
            }
            let resultado: WriteResult
            do {
                resultado = try await bus.ejecutar(nota.plan)
            } catch WriteError.cambioExterno where intento == 0 {
                continue   // Otro cambio le ganó la carrera: se prepara de nuevo con una foto nueva.
            }
            if resultado.conflicto != nil, intento == 0 { continue }
            sesion.registrarDeshacer(resultado, descripcion: nota.plan.descripcion,
                                     aviso: "Creé «\(nota.titulo)» en \(nota.ruta.parent?.raw ?? "la carpeta")",
                                     deshacer: deshacer)
            return resultado.hecho ? nota.ruta : nil
        }
        return nil
    }

    /// Un nombre fijo que ya existe (Empresa, el plan de un servicio…): «Completar la que hay».
    private static func ofrecerCompletar(_ ruta: VaultPath, plantilla: String, motor: PlantillaMotor, sesion: VaultSession,
                                         deshacer: UndoManager?) {
        sesion.aviso = Aviso("Ya existe «\(ruta.stem)». Puedo completarla con lo que le falte de la plantilla, sin pisar nada.",
                             estado: .atencion, tituloAccion: "Completar la que hay") {
            Task { @MainActor in
                do {
                    if let plan = try motor.aplicar(plantilla, a: ruta, autor: sesion.autor) {
                        try await sesion.escribir(plan: plan, aviso: "Completé «\(ruta.stem)» con la plantilla", deshacer: deshacer)
                    } else {
                        sesion.aviso = Aviso("«\(ruta.stem)» ya tenía todo lo de la plantilla.", estado: .bien)
                    }
                } catch {
                    sesion.aviso = Aviso(error.localizedDescription, estado: .mal)
                }
            }
        }
    }
}

/// La hoja «Nueva …» (§4.8): solo lo que pide la plantilla (sus `preguntas`), ya rellena con lo que tengas
/// filtrado, la pestaña y la columna del tablero. El nombre lo pone la plantilla. ↩ crea y abre; ⌘↩ crea y
/// deja la hoja lista para la siguiente.
struct HojaNuevaFicha: View {
    @Bindable var modelo: BaseModelo
    let peticion: PeticionNueva
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navegar) private var navegar
    @State private var valores: [String: String] = [:]
    @State private var contexto: [String: VaultPath] = [:]
    @State private var opciones: [String: [(ruta: VaultPath, titulo: String)]] = [:]
    @State private var creando = false
    @State private var error: String?
    @State private var creadas = 0
    @FocusState private var enfocada: String?

    private var c: ColeccionBase { modelo.coleccion }
    private var def: PlantillaDef? { c.plantilla.flatMap { PlantillaRegistro.deSerie[$0] } }
    private var preguntas: [String] {
        let ps = def?.preguntas ?? ["titulo"]
        return ps.filter { peticion.contexto[$0] == nil && peticion.poner[$0] == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.textoNueva).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Text("Solo lo que pide la plantilla. El nombre lo pone ella y la guarda en \(carpeta).")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(preguntas.enumerated()), id: \.element) { i, q in
                pregunta(q, obligatoria: i == 0)
            }
            if !peticion.poner.isEmpty || !peticion.contexto.isEmpty {
                FlowLayout(espacio: 6) {
                    ForEach(peticion.poner.sorted { $0.key < $1.key }, id: \.key) { k, v in
                        Chip("\(c.columna(k)?.etiqueta ?? k): \(FormatoBase.opcionVisible(v))", icono: "checkmark")
                    }
                    ForEach(peticion.contexto.sorted { $0.key < $1.key }, id: \.key) { k, r in
                        Chip("\(etiqueta(k)): \(modelo.sesion.titulo(de: r))", icono: "link")
                    }
                }
            }
            if let error {
                Label(error, systemImage: TLSEstado.mal.simbolo)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if creadas > 0 {
                Text(FormatoBase.cuenta(creadas, "creada; la hoja sigue lista para otra", "creadas; la hoja sigue lista para otra"))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            HStack(spacing: TLSEspacio.e8) {
                Spacer()
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Button("Crear y seguir") { Task { await crear(abrir: false) } }
                    .tlsBoton(.secundario)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(creando)
                    .help("⌘↩: crea y deja la hoja lista para la siguiente")
                Button("\(c.femenino ? "Crear y abrirla" : "Crear y abrirlo")") { Task { await crear(abrir: true) } }
                    .tlsBoton(.principal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(creando)
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 520)
        .task { await cargarOpciones() }
        .onAppear {
            valores = peticion.valores
            contexto = peticion.contexto
            enfocada = preguntas.first
        }
    }

    private var carpeta: String {
        let layout = modelo.sesion.estructura
        guard let carpeta = def?.carpeta, !carpeta.contains("{{") else { return layout?.expand(c.hogar).raw ?? c.hogar }
        let area = modelo.contexto.flatMap { layout?.area(of: $0) } ?? def?.area ?? c.area ?? .direccion
        let conArea = carpeta.replacingOccurrences(of: "{area}", with: "{\(area.layoutKey)}")
        return layout?.expand(conArea).raw ?? conArea
    }

    @ViewBuilder private func pregunta(_ q: String, obligatoria: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(etiqueta(q) + (obligatoria ? " (obligatorio)" : ""))
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(TLSPaleta.texto.color)
            if let base = PapelesNueva.baseDePregunta[q] {
                Picker(etiqueta(q), selection: Binding(get: { contexto[q] }, set: { contexto[q] = $0 })) {
                    Text("Elige \(etiqueta(q).lowercased())…").tag(VaultPath?.none)
                    ForEach(opciones[q] ?? [], id: \.ruta) { o in Text(o.titulo).tag(VaultPath?.some(o.ruta)) }
                }
                .labelsHidden()
                .accessibilityLabel(etiqueta(q))
                if (opciones[q] ?? []).isEmpty {
                    Text("Aún no hay \(CatalogoBases.coleccion(base)?.nombre.lowercased() ?? base).")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            } else if q == "area" {
                Picker(etiqueta(q), selection: Binding(get: { valores[q] ?? "" }, set: { valores[q] = $0 })) {
                    Text("Elige un área…").tag("")
                    ForEach(AreaCode.allCases, id: \.self) { a in Text("\(a.numero) · \(a.nombre)").tag(a.layoutKey) }
                }
                .labelsHidden()
                .accessibilityLabel(etiqueta(q))
            } else if q == "gravedad" {
                Picker(etiqueta(q), selection: Binding(get: { valores[q] ?? "Media" }, set: { valores[q] = $0 })) {
                    ForEach(CatalogoBases.gravedades, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(etiqueta(q))
            } else {
                TextField(ayuda(q), text: Binding(get: { valores[q] ?? "" }, set: { valores[q] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .focused($enfocada, equals: q)
                    .accessibilityLabel(etiqueta(q))
            }
        }
    }

    private func etiqueta(_ q: String) -> String {
        switch q {
        case "titulo": c.tipos.first.map { [NoteKind.contact, .organization, .service, .role, .system, .asset].contains($0) } ?? false ? "Nombre" : "Título"
        case "email": "Correo"
        case "cadencia": "Cada cuánto"
        case "pregunta": "Qué miras"
        case "medido_por": "Número clave que lo mide"
        case "area": "Área"
        case "codigo": "Código"
        case "version": "Versión"
        default: q.prefix(1).uppercased() + q.dropFirst().replacingOccurrences(of: "_", with: " ")
        }
    }

    private func ayuda(_ q: String) -> String {
        switch q {
        case "fecha": "hoy, mañana o 24/10/2026"
        case "hora": "10:00"
        case "titulo": c.tipos.first == .contact ? "Nombre y apellido" : etiqueta(q)
        case "responsable": "Quién la hace (vacío: tú)"
        default: etiqueta(q)
        }
    }

    /// Las fichas que se pueden elegir en cada pregunta de relación (de su base, sin lo privado).
    private func cargarOpciones() async {
        for q in preguntas {
            guard let base = PapelesNueva.baseDePregunta[q], let d = await modelo.almacen.cargar(base) else { continue }
            opciones[q] = d.filas.filter { !$0.esFilaCSV }
                .map { (ruta: $0.ruta, titulo: $0.titulo) }
                .sorted { $0.titulo.localizedStandardCompare($1.titulo) == .orderedAscending }
        }
    }

    private func crear(abrir: Bool) async {
        guard !creando else { return }
        if let q = preguntas.first {
            let falta = PapelesNueva.baseDePregunta[q] != nil ? contexto[q] == nil
                : (valores[q] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            if falta { error = "Falta «\(etiqueta(q).lowercased())»."; return }
        }
        creando = true
        defer { creando = false }
        error = nil
        var p = peticion
        p.contexto = contexto
        p.valores = valores.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if let f = p.valores["fecha"], let d = EdicionCelda.fecha(f, hoy: modelo.hoy) { p.valores["fecha"] = d.description }
        do {
            guard let ruta = try await CreadorFichas.intentar(coleccion: c, peticion: p, sesion: modelo.sesion,
                                                             deshacer: modelo.undoManager) else {
                dismiss()
                return
            }
            if abrir {
                dismiss()
                navegar(modelo.sesion.destino(para: ruta), modo: .entrar)
            } else {
                creadas += 1
                valores = peticion.valores
                contexto = peticion.contexto
                enfocada = preguntas.first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
