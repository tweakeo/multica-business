import SwiftUI
import TLSCore
import TLSDesign

/// ⌘K (§4.9): «Buscar o hacer…» en una ventana flotante de 640 pt. Vacío enseña Recientes, «Pide tu decisión»
/// y las bases fijadas; al escribir, Mejores resultados · una sección por base · Acciones · Bases · Dentro de
/// notas. Encuentra por número o código, título, otros nombres, propiedades y texto, sin tildes ni mayúsculas, y
/// nunca enseña lo privado. Teclado: ↑ ↓, ↩ abre (las migas se siembran con su base), ⌘↩ en pestaña nueva,
/// ⇧espacio para la vista previa, Esc cierra.
struct PaletaBusqueda: View {
    let sesion: VaultSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @State private var texto = ""
    @State private var acotar: AcotarPaleta = .todo
    @State private var catalogo: CatalogoBusqueda = .vacio
    @State private var textoCompleto: [SearchHit] = []
    @State private var activo = 0
    @State private var previa: VaultPath?
    /// Ya se está abriendo un resultado (↩ y la acción del campo no abren dos veces).
    @State private var abriendo = false
    @FocusState private var campoEnfocado: Bool

    init(sesion: VaultSession) {
        self.sesion = sesion
    }

    /// Con un texto ya escrito (capturas y pruebas).
    init(sesion: VaultSession, textoInicial: String) {
        self.sesion = sesion
        _texto = State(initialValue: textoInicial)
    }

    private var secciones: [SeccionPaleta] {
        let fijadas = sesion.barraLateral.filas.compactMap { f -> String? in
            if case .base(let id) = f.elemento { return id }
            return nil
        }
        return MotorPaleta.secciones(texto, catalogo: catalogo, texto: textoCompleto, recientes: sesion.recientes,
                                     fijadas: fijadas, acotar: acotar, puedeCrear: sesion.puedeEscribir)
    }

    var body: some View {
        let secciones = self.secciones
        let items = secciones.flatMap(\.items)
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                campo(items)
                chips
                Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
                lista(secciones, items: items)
                Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
                pie
            }
            .frame(width: TLSAncho.paleta)
            if let previa {
                VistaPreviaPopover(ruta: previa, sesion: sesion)
                    .frame(width: TLSAncho.vistaPrevia)
                    .padding(TLSEspacio.e12)
                    .transition(.opacity)
            }
        }
        .background(TLSPaleta.superficieElevada.color)
        .task { catalogo = await AlmacenBases.de(sesion).catalogoBusqueda() }
        .task(id: texto) {
            activo = 0
            let q = texto.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { textoCompleto = []; return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let hits = await sesion.buscar(q, limite: 12)
            guard !Task.isCancelled else { return }
            textoCompleto = hits
        }
        .onAppear { campoEnfocado = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Buscar o hacer, en todas las bases")
    }

    // MARK: Partes

    private func campo(_ items: [ItemPaleta]) -> some View {
        HStack(spacing: TLSEspacio.e8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            TextField("Buscar o hacer…", text: $texto)
                .textFieldStyle(.plain)
                .font(TLSTipo.tituloModulo.font())
                .focused($campoEnfocado)
                .accessibilityLabel("Buscar o hacer")
                .accessibilityIdentifier("paleta.campo")
                .onKeyPress(.downArrow) { mover(1, total: items.count) }
                .onKeyPress(.upArrow) { mover(-1, total: items.count) }
                .onKeyPress(.escape) {
                    if previa != nil { previa = nil } else { dismiss() }
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { tecla in
                    guard items.indices.contains(activo) else { return .handled }
                    abrir(items[activo], pestanaNueva: tecla.modifiers.contains(.command))
                    return .handled
                }
                .onKeyPress(.space, phases: .down) { tecla in
                    guard tecla.modifiers.contains(.shift) else { return .ignored }
                    alternarPrevia(items)
                    return .handled
                }
                .onSubmit {
                    // Por si el campo se queda el ↩ antes que `onKeyPress`.
                    if items.indices.contains(activo) { abrir(items[activo], pestanaNueva: false) }
                }
                .background {
                    Button("") { if items.indices.contains(activo) { abrir(items[activo], pestanaNueva: true) } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            Button { dismiss() } label: { Tecla("Esc") }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, TLSEspacio.e16)
        .frame(minHeight: 52)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(AcotarPaleta.allCases, id: \.self) { a in
                let on = acotar == a
                Button { acotar = a; activo = 0; campoEnfocado = true } label: {
                    Text(a.nombre)
                        .tlsTexto(TLSTipo.interfazMedia)
                        .foregroundStyle(on ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                        .padding(.horizontal, 12)
                        .frame(minHeight: TLSAltura.objetivoMinimo)
                        .background(Capsule(style: .circular).fill(on ? TLSPaleta.principal.color : TLSPaleta.bandeja.color))
                        .contentShape(Capsule(style: .circular))
                }
                .buttonStyle(.plain)
                .tlsFocoPropio(radio: 999)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.bottom, TLSEspacio.e8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Acotar la búsqueda")
    }

    private func lista(_ secciones: [SeccionPaleta], items: [ItemPaleta]) -> some View {
        Group {
            if items.isEmpty {
                Text(texto.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Escribe un nombre, un número (F-2026-0013, T-0041) o una palabra de las notas."
                     : "Nada coincide con «\(texto.trimmingCharacters(in: .whitespaces))». Prueba con un número (F-2026-0013, T-0041), otro nombre o una palabra de las notas.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .multilineTextAlignment(.center)
                    .padding(TLSEspacio.e24)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            let indices = indicesPorItem(secciones)
                            ForEach(secciones) { s in
                                Text(s.titulo)
                                    .tlsTexto(TLSTipo.rotulo)
                                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                                    .padding(.horizontal, TLSEspacio.e12)
                                    .padding(.top, TLSEspacio.e8)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(s.items) { it in
                                    let i = indices[it.id] ?? 0
                                    fila(it, activo: i == activo)
                                        .id(i)
                                        .onTapGesture(count: 2) { activo = i; abrir(it, pestanaNueva: false) }
                                        .onTapGesture { activo = i }
                                        .onHover { if $0 { activo = i } }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: activo) { _, i in proxy.scrollTo(i) }
                }
                .accessibilityIdentifier("paleta.lista")
            }
        }
    }

    private func indicesPorItem(_ s: [SeccionPaleta]) -> [String: Int] {
        var out: [String: Int] = [:]
        var i = 0
        for sec in s { for it in sec.items where out[it.id] == nil { out[it.id] = i; i += 1 } }
        return out
    }

    private func fila(_ it: ItemPaleta, activo: Bool) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            Group {
                if let a = it.area {
                    IconoArea(a.tlsArea, tamano: 24, simbolo: it.icono)
                } else {
                    Image(systemName: it.icono)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(activo ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: TLSRadio.iconoArea24, style: .continuous)
                            .fill(activo ? Color.white.opacity(0.18) : TLSPaleta.bandeja.color))
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if it.resaltar { TextoResaltado(it.titulo, busqueda: texto, sobreColor: activo) } else { Text(it.titulo) }
                }
                .tlsTexto(TLSTipo.interfazFuerte)
                .lineLimit(1)
                Text(it.sub).tlsTexto(TLSTipo.secundario).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(activo ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
            }
            .foregroundStyle(activo ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
            Spacer(minLength: TLSEspacio.e8)
            Text(it.tipo).tlsTexto(TLSTipo.secundario)
                .foregroundStyle(activo ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
            if activo { Text("↩").tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.sobrePrincipal.color).accessibilityHidden(true) }
        }
        .padding(.horizontal, TLSEspacio.e12)
        .frame(minHeight: TLSAltura.filaLista)
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
            .fill(activo ? TLSPaleta.principal.color : Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(it.titulo), \(it.sub), \(it.tipo)")
        .accessibilityAddTraits(activo ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { abrir(it, pestanaNueva: false) }
        .accessibilityAction(named: "Abrir en pestaña nueva") { abrir(it, pestanaNueva: true) }
    }

    private var pie: some View {
        HStack(spacing: TLSEspacio.e16) {
            ForEach(["↑ ↓ moverte", "↩ abrir", "⌘↩ en pestaña nueva", "⇧espacio: vista previa", "Esc cerrar"], id: \.self) {
                Text($0)
            }
            Spacer(minLength: 0)
        }
        .tlsTexto(TLSTipo.secundario)
        .foregroundStyle(TLSPaleta.textoSecundario.color)
        .padding(.horizontal, TLSEspacio.e16)
        .frame(minHeight: 36)
    }

    // MARK: Acciones

    private func mover(_ paso: Int, total: Int) -> KeyPress.Result {
        guard total > 0 else { return .handled }
        activo = (activo + paso + total) % total
        if previa != nil { alternarPrevia(secciones.flatMap(\.items), forzar: true) }
        return .handled
    }

    private func alternarPrevia(_ items: [ItemPaleta], forzar: Bool = false) {
        guard items.indices.contains(activo), let r = items[activo].ruta, !sesion.esPrivado(r) else {
            previa = nil
            return
        }
        previa = (previa == r && !forzar) ? nil : r
    }

    private func abrir(_ it: ItemPaleta, pestanaNueva: Bool) {
        guard !abriendo else { return }
        abriendo = true
        let nav = self.nav
        let sesion = self.sesion
        let navegar = self.navegar
        dismiss()
        Task { @MainActor in
            // Se abre cuando la hoja ya se cerró.
            try? await Task.sleep(for: .milliseconds(120))
            switch it.accion {
            case .abrir(let ruta, let base):
                let destino = sesion.destino(para: ruta)
                if pestanaNueva {
                    if let base, let abrirVentana = sesion.abrirVentana {
                        abrirVentana(VentanaRuta(empresa: sesion.entry.id, destino: .base(base), sembrar: [destino],
                                                 alFrente: false, origen: nav?.numeroVentana))
                    } else {
                        navegar(destino, modo: .pestanaNueva)
                    }
                } else if let base {
                    // §2.1 regla 3: las migas se siembran con el camino natural (`Facturas › F-2026-0013`).
                    navegar(.base(base), modo: .raiz(sembrar: [destino]))
                } else if let carpeta = ruta.parent, !carpeta.isRoot {
                    navegar(.carpeta(carpeta), modo: .raiz(sembrar: [destino]))
                } else {
                    navegar(destino, modo: .entrar)
                }
            case .base(let id, let busqueda):
                if let busqueda { nav?.actualizarRecuerdo(de: .base(id)) { $0.busqueda = busqueda } }
                navegar(.base(id), modo: pestanaNueva ? .pestanaNueva : .raiz)
            case .nueva(let id, let contexto):
                let destino = Destino.base(id, contexto: contexto)
                nav?.actualizarRecuerdo(de: destino) { $0.extra["nueva"] = "1" }
                navegar(destino, modo: .raiz)
            case .ir(let destino):
                navegar(destino, modo: pestanaNueva ? .pestanaNueva : .raiz)
            }
        }
    }
}
