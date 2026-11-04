import SwiftUI
import TLSCore
import TLSDesign

/// El selector de relación (§5.2): ventana flotante de 360 pt con el buscador enfocado, las fichas del tipo que
/// admite la propiedad (las del contexto primero, luego las recientes), una marca en las ya enlazadas, «Crear
/// … como … nueva» al vuelo y, en las de varias, casillas y «Listo». Teclado: ↑ ↓ ↩ Esc (⌘↩ crea siempre).
struct SelectorRelacion: View {
    let peticion: PeticionSelector
    let sesion: VaultSession
    let almacen: AlmacenRelaciones
    let alElegir: (VaultPath) -> Void
    let alQuitar: () -> Void
    let alCrear: (String) -> Void
    let alListo: (Set<VaultPath>) -> Void
    /// Se cierra solo al elegir (si no, quien lo usa decide: por ejemplo, para enseñar la confirmación dentro).
    var cerrarAlElegir = true

    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @State private var activa = 0
    @State private var buscarEnTodo = false
    @State private var marcadas: Set<VaultPath> = []
    @FocusState private var enfocado: Bool

    struct Opcion: Identifiable {
        var id: VaultPath { ficha.ruta }
        let ficha: FichaGrafo
        let contexto: String
        let admitida: Bool
        let motivo: String?
    }

    var body: some View {
        let ops = opciones
        let crear = textoCrear(ops)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .firstTextBaseline) {
                Text(peticion.titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .tlsBoton(.discreto)
                    .help("Cerrar · Esc")
                    .accessibilityLabel("Cerrar el selector")
            }
            TextField(peticion.placeholder, text: $texto, prompt: Text(peticion.placeholder))
                .textFieldStyle(.roundedBorder)
                .focused($enfocado)
                .accessibilityLabel(peticion.titulo)
                .onChange(of: texto) { activa = 0 }
                .onKeyPress(.downArrow) { activa = min(activa + 1, max(ops.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { activa = max(activa - 1, 0); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
                .onKeyPress(.return, phases: .down) { tecla in
                    if tecla.modifiers.contains(.command), let crear { alCrear(crear); dismiss(); return .handled }
                    if ops.indices.contains(activa), ops[activa].admitida { elegir(ops[activa]); return .handled }
                    if let crear { alCrear(crear); dismiss(); return .handled }
                    return .ignored
                }
            Rotulo(texto.isEmpty ? (peticion.contexto.isEmpty ? "Recientes primero" : "Primero las suyas, luego las recientes") : "Coinciden")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(ops.enumerated()), id: \.element.id) { i, o in
                            fila(o, activa: i == activa).id(o.id)
                        }
                        if ops.isEmpty {
                            Text(texto.isEmpty ? "No hay nada que elegir todavía." : "Nada coincide con «\(texto)».")
                                .tlsTexto(TLSTipo.interfaz)
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                                .padding(.vertical, TLSEspacio.e8)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .onChange(of: activa) { if ops.indices.contains(activa) { proxy.scrollTo(ops[activa].id) } }
            }
            if let crear, let c = peticion.crear {
                Button { alCrear(crear); dismiss() } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Crear «\(crear)» como \(c.nombre)")
                        Spacer()
                        Tecla(ops.isEmpty ? "↩" : "⌘↩")
                    }
                }
                .buttonStyle(EstiloFila())
                .focusEffectDisabled()
                .disabled(!sesion.puedeEscribir)
            }
            Text(peticion.nota)
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(buscarEnTodo ? "Solo las que admite" : "Buscar en todo") { buscarEnTodo.toggle() }
                    .tlsBoton(.enlace)
                Spacer()
                if let q = peticion.quitar {
                    Button(q) { alQuitar(); dismiss() }.tlsBoton(.secundario).disabled(!sesion.puedeEscribir)
                }
                if peticion.varias {
                    Button("Listo") { alListo(marcadas); dismiss() }.tlsBoton(.principal, alto: 36).disabled(!sesion.puedeEscribir)
                }
            }
            if let motivo = EdicionRelaciones.motivoSoloLectura(sesion) {
                Text("No se puede cambiar: \(motivo).").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .padding(TLSEspacio.e16)
        .frame(width: TLSAncho.selectorRelacion)
        .background(TLSPaleta.superficieElevada.color)
        .onAppear {
            marcadas = peticion.enlazadas
            enfocado = true
        }
        .task { await almacen.actualizar() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(peticion.titulo)
    }

    private func fila(_ o: Opcion, activa: Bool) -> some View {
        let enlazada = peticion.varias ? marcadas.contains(o.ficha.ruta) : peticion.enlazadas.contains(o.ficha.ruta)
        return Button { elegir(o) } label: {
            HStack(spacing: TLSEspacio.e8) {
                if peticion.varias {
                    Image(systemName: enlazada ? "checkmark.square.fill" : "square")
                        .foregroundStyle(TLSPaleta.principal.color)
                }
                Image(systemName: o.ficha.tipo.systemImage)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.ficha.nombre).tlsTexto(TLSTipo.interfazFuerte).lineLimit(1)
                        .foregroundStyle(o.admitida ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
                    Text(o.motivo ?? o.contexto).tlsTexto(TLSTipo.secundario).lineLimit(1)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Spacer(minLength: 4)
                if enlazada, !peticion.varias {
                    Text("Enlazada").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Image(systemName: "checkmark").foregroundStyle(TLSPaleta.principal.color)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(EstiloFila(seleccionada: false, alto: TLSAltura.filaLista))
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila).fill(activa ? TLSPaleta.principalSuave.color : .clear))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.fila).strokeBorder(activa ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .focusEffectDisabled()
        .disabled(!o.admitida || !sesion.puedeEscribir)
        .accessibilityLabel([o.ficha.nombre, o.motivo ?? o.contexto, enlazada ? "enlazada" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(enlazada ? .isSelected : [])
    }

    private func elegir(_ o: Opcion) {
        guard o.admitida else { return }
        if peticion.varias {
            if marcadas.contains(o.ficha.ruta) { marcadas.remove(o.ficha.ruta) } else { marcadas.insert(o.ficha.ruta) }
            return
        }
        if peticion.enlazadas.contains(o.ficha.ruta) { dismiss(); return }
        alElegir(o.ficha.ruta)
        if cerrarAlElegir { dismiss() }
    }

    /// Las fichas que se pueden elegir, en orden: contexto, recientes y el resto por nombre.
    private var opciones: [Opcion] {
        guard let grafo = almacen.grafo else { return [] }
        let hoy = almacen.hoy
        let propia: VaultPath? = {
            switch peticion.modo {
            case .directo(let d, _): return d
            case .inverso(let d): return d
            }
        }()
        let q = TextFolding.fold(texto.trimmingCharacters(in: .whitespaces))
        var candidatas = grafo.fichas(de: peticion.tipos).filter { $0.ruta != propia }
        if buscarEnTodo {
            let otros = grafo.fichas.values.filter { !peticion.tipos.contains($0.tipo) && !$0.privada && $0.ruta != propia && $0.tipo.abreComoFicha }
                .sorted { $0.nombre.localizedStandardCompare($1.nombre) == .orderedAscending }
            candidatas += otros
        }
        let rango: [VaultPath: Int] = {
            var r: [VaultPath: Int] = [:]
            for (i, c) in peticion.contexto.enumerated() { r[c] = i }
            for (i, c) in sesion.recientes.enumerated() where r[c] == nil { r[c] = 1000 + i }
            return r
        }()
        let admite = peticion.tipos.map(\.etiquetaRelacion).sorted().joined(separator: " o ")
        return candidatas.compactMap { f -> Opcion? in
            let ctx = EdicionRelaciones.contexto(f, grafo: grafo, hoy: hoy)
            if !q.isEmpty, !TextFolding.fold(f.nombre + " " + ctx + " " + (f.numero ?? "")).contains(q) { return nil }
            let admitida = peticion.tipos.contains(f.tipo)
            return Opcion(ficha: f, contexto: ctx, admitida: admitida,
                          motivo: admitida ? nil : "Aquí se enlazan \(admite), no \(f.tipo.etiquetaRelacion)")
        }
        .sorted { a, b in
            if a.admitida != b.admitida { return a.admitida }
            let ra = rango[a.ficha.ruta] ?? Int.max, rb = rango[b.ficha.ruta] ?? Int.max
            if ra != rb { return ra < rb }
            return a.ficha.nombre.localizedStandardCompare(b.ficha.nombre) == .orderedAscending
        }
    }

    /// El nombre para «Crear … como … nueva», si se escribe algo que no existe tal cual.
    private func textoCrear(_ ops: [Opcion]) -> String? {
        guard peticion.crear != nil else { return nil }
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let k = TextFolding.fold(t)
        return ops.contains { TextFolding.fold($0.ficha.nombre) == k } ? nil : t
    }
}

/// La confirmación de un cambio que pisa un valor (§5.3): la pregunta, el fichero, la línea antes y después y,
/// si toca, «Cambiarla también en N fichas que cuelgan de ella».
struct ConfirmarRelacion: View {
    @State var confirmacion: ConfirmacionRelacion
    let grafo: GrafoRelaciones?
    let alConfirmar: (ConfirmacionRelacion) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text(confirmacion.pregunta)
                .tlsTexto(TLSTipo.tituloModulo)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                Text(confirmacion.fichero.raw).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                linea("Antes", confirmacion.preparada.lineas.antes ?? "(no estaba)", estado: .mal)
                linea("Después", confirmacion.preparada.lineas.despues ?? "(se quita)", estado: .bien)
            }
            if !confirmacion.colgantes.isEmpty {
                Toggle(isOn: $confirmacion.tambienColgantes) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(confirmacion.colgantes.count == 1 ? "Cambiarla también en 1 ficha que cuelga de ella"
                                : "Cambiarla también en \(confirmacion.colgantes.count) fichas que cuelgan de ella")
                            .tlsTexto(TLSTipo.interfazFuerte)
                        Text(confirmacion.colgantes.map { grafo?.ficha($0)?.nombre ?? $0.stem }.joined(separator: " · "))
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .toggleStyle(.checkbox)
            }
            if !confirmacion.fijas.isEmpty {
                Label("No cambian: \(confirmacion.fijas.map { grafo?.ficha($0)?.nombre ?? $0.stem }.joined(separator: ", ")). Una factura emitida no se cambia: se rectifica.",
                      systemImage: TLSEstado.atencion.simbolo)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Cambia solo esa línea. Después tienes Deshacer.")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
            HStack {
                Spacer()
                Button("Volver") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Button("Cambiar") { alConfirmar(confirmacion); dismiss() }.tlsBoton(.principal).keyboardShortcut(.defaultAction)
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 520)
        .background(TLSPaleta.superficieElevada.color)
    }

    private func linea(_ rotulo: String, _ texto: String, estado: TLSEstado) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
            Text(rotulo).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color).frame(width: 64, alignment: .leading)
            Text(texto).tlsTexto(TLSTipo.textoPlano).foregroundStyle(TLSPaleta.texto.color).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.campo).fill(estado.tinte.color))
        .accessibilityElement(children: .combine)
    }
}

/// El selector de relación listo para usar fuera de una ficha (la celda de una base, §4.7): abre el selector de
/// esa propiedad de `dueno`, y al elegir escribe una línea en `dueno` o, si cambia algo que ya existía, enseña
/// dentro la confirmación con la línea antes y después. Va dentro de un `popover`.
struct SelectorDeRelacion: View {
    let dueno: VaultPath
    let propiedad: String
    let sesion: VaultSession
    @State private var modelo: FichaModelo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navegar) private var navegar

    init(dueno: VaultPath, propiedad: String, sesion: VaultSession) {
        self.dueno = dueno
        self.propiedad = propiedad
        self.sesion = sesion
        self._modelo = State(initialValue: FichaModelo(ruta: dueno, sesion: sesion))
    }

    var body: some View {
        Group {
            if let c = modelo.confirmacion {
                ConfirmarRelacion(confirmacion: c, grafo: modelo.grafo) { elegida in
                    Task { await EdicionRelaciones.confirmar(elegida, sesion: sesion, almacen: modelo.almacen) }
                }
            } else if let p = modelo.selector {
                SelectorRelacion(peticion: p, sesion: sesion, almacen: modelo.almacen,
                                 alElegir: { d in
                                     Task {
                                         await modelo.elegido(d, en: p, navegar: navegar)
                                         if modelo.confirmacion == nil { dismiss() }
                                     }
                                 },
                                 alQuitar: { Task { await modelo.quitar(propiedad: propiedad, destino: nil, guardaEn: dueno) } },
                                 alCrear: { nombre in
                                     if let c = p.crear {
                                         Task { await EdicionRelaciones.crearYEnlazar(nombre: nombre, tipo: c.tipo, dueno: dueno, propiedad: propiedad,
                                                                                      sesion: sesion, almacen: modelo.almacen) }
                                     }
                                 },
                                 alListo: { m in Task { await modelo.listo(m, en: p) } },
                                 cerrarAlElegir: false)
            } else {
                ProgressView().padding(TLSEspacio.e24).frame(width: TLSAncho.selectorRelacion)
            }
        }
        .task {
            await modelo.almacen.actualizar()
            if modelo.selector == nil { modelo.abrirSelector(propiedad: propiedad, origen: "celda", en: dueno) }
        }
    }
}
