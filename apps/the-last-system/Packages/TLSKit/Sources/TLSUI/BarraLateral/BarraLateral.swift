import AppKit
import SwiftUI
import TLSCore
import TLSDesign

/// Barra lateral de la ventana de empresa (§6 y la maqueta M2-Hoy): empresa, Hoy · Decisiones · Tareas,
/// Áreas, Bases (fijadas y «Todas las bases»), Asistentes · Carpeta · Ajustes, Recientes y, al pie, si la
/// app escribe y el selector de empresa.
struct BarraLateral: View {
    @Bindable var sesion: VaultSession
    let nav: Navegacion
    @Environment(\.navegar) private var navegar
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reducir

    private var modelo: BarraLateralModelo { sesion.barraLateral }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                CabeceraBarra(sesion: sesion, modelo: modelo)
                if modelo.editando {
                    Text("Arrastra para ordenar. Suelta fuera de la barra para ocultar. Para meter dentro, arrastra a la derecha o pulsa ⌥⌘→.")
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                }
                ForEach(Array(modelo.filas.enumerated()), id: \.element.elemento) { i, fila in
                    if case .seccion(let s) = fila.elemento {
                        RotuloSeccion(seccion: s, pista: s == .bases && !modelo.editando ? "buscar en todas: ⌘K" : nil,
                                      siguiente: i + 1 < modelo.filas.count ? modelo.filas[i + 1].elemento : nil,
                                      modelo: modelo)
                    } else {
                        FilaBarraView(fila: fila, modelo: modelo, sesion: sesion,
                                      elegida: ElementoBarra.para(nav.raiz) == fila.elemento, indice: i)
                    }
                }
                Recientes(sesion: sesion)
                if let aviso = modelo.aviso {
                    AvisoDeshacer(aviso) { modelo.aviso = nil }
                        .padding(.top, 12)
                        .task(id: aviso.id) {
                            try? await Task.sleep(for: TLSMovimiento.duracionAviso)
                            if modelo.aviso == aviso { modelo.aviso = nil }
                        }
                }
                if modelo.editando {
                    BandejaOcultos(modelo: modelo)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .animation(TLSMovimiento.si(TLSMovimiento.muelle, reducir: reducir), value: modelo.filas)
        }
        .background(TLSPaleta.superficie.color)
        .safeAreaInset(edge: .bottom, spacing: 0) { PieBarra(sesion: sesion) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Barra lateral")
        .accessibilityIdentifier("lateral")
    }
}

// MARK: Cabecera: empresa y Editar/Listo

private struct CabeceraBarra: View {
    let sesion: VaultSession
    let modelo: BarraLateralModelo

    var body: some View {
        HStack(spacing: 10) {
            Monograma(nombre: sesion.entry.nombre)
            VStack(alignment: .leading, spacing: 3) {
                // Hasta dos líneas: con «Editar» al lado, el nombre se cortaba («Asesoría Ri…»).
                Text(sesion.entry.nombre)
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(sesion.entry.nombre)
                Badge(sesion.entry.clase.badge)
                    .accessibilityIdentifier("empresa.insignia")
            }
            Spacer(minLength: 0)
            if modelo.editando {
                Button("Listo") { modelo.editando = false }
                    .tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 8)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Editar") { modelo.editando = true }
                    .tlsBoton(.secundario, alto: 32)
                    .help("Editar la barra lateral. También manteniendo pulsado un elemento.")
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Rótulo de sección

private struct RotuloSeccion: View {
    let seccion: SeccionBarra
    let pista: String?
    let siguiente: ElementoBarra?
    let modelo: BarraLateralModelo
    @Environment(\.undoManager) private var undoManager
    @State private var encima = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Rotulo(seccion.titulo)
            Spacer(minLength: 0)
            if let pista {
                Text(pista).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            if encima { Rectangle().fill(TLSPaleta.principal.color).frame(height: 3) }
        }
        .dropDestination(for: ArrastreBarra.self) { items, _ in
            for item in items {
                if item.desdeOcultos {
                    modelo.mostrar(item.elemento, antesDe: siguiente, deshacer: undoManager)
                } else {
                    modelo.mover(item.elemento, antesDe: siguiente, deshacer: undoManager)
                }
            }
            return true
        } isTargeted: { encima = $0 }
    }
}

// MARK: Fila

private struct FilaBarraView: View {
    let fila: FilaBarra
    let modelo: BarraLateralModelo
    let sesion: VaultSession
    let elegida: Bool
    let indice: Int
    @Environment(\.navegar) private var navegar
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var pulsacionLarga = false
    @State private var temblor = false
    @State private var destinoEncima: Bool? = nil

    private var e: ElementoBarra { fila.elemento }
    private var dato: DatoFilaBarra { modelo.datos[e] ?? datoPorDefecto }
    private var nombre: String { modelo.nombre(e) }

    var body: some View {
        HStack(spacing: 0) {
            if fila.dentro {
                RoundedRectangle(cornerRadius: 1)
                    .fill(colorGuia)
                    .frame(width: 2)
                    .padding(.vertical, 6)
                    .padding(.leading, 21)
                    .padding(.trailing, 8)
                    .accessibilityHidden(true)
            }
            if modelo.editando { filaEdicion } else { filaNormal }
        }
        .overlay(alignment: destinoEncima == true ? .bottom : .top) {
            if destinoEncima != nil { Rectangle().fill(TLSPaleta.principal.color).frame(height: 3) }
        }
        .dropDestination(for: ArrastreBarra.self) { items, punto in
            let despues = punto.y > TLSAltura.filaBarraLateral / 2
            let siguiente = despues ? (indice + 1 < modelo.filas.count ? modelo.filas[indice + 1].elemento : nil) : e
            for item in items where item.elemento != e {
                if item.desdeOcultos {
                    modelo.mostrar(item.elemento, antesDe: siguiente, deshacer: undoManager)
                } else {
                    modelo.mover(item.elemento, antesDe: siguiente, dentro: punto.x > 60, deshacer: undoManager)
                }
            }
            return true
        } isTargeted: { destinoEncima = $0 ? false : nil }
        .contextMenu { menu }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { tecla in
            guard tecla.modifiers.contains(.command), tecla.modifiers.contains(.option) else { return .ignored }
            switch tecla.key {
            case .upArrow: modelo.desplazar(e, -1, deshacer: undoManager)
            case .downArrow: modelo.desplazar(e, 1, deshacer: undoManager)
            case .rightArrow: modelo.meterDentro(e, true, deshacer: undoManager)
            default: modelo.meterDentro(e, false, deshacer: undoManager)
            }
            return .handled
        }
        .accessibilityAction(named: "Subir") { modelo.desplazar(e, -1, deshacer: undoManager) }
        .accessibilityAction(named: "Bajar") { modelo.desplazar(e, 1, deshacer: undoManager) }
        .accessibilityAction(named: modelo.estaDentro(e) ? "Sacar del grupo" : "Meter dentro") {
            modelo.meterDentro(e, !modelo.estaDentro(e), deshacer: undoManager)
        }
        .accessibilityAction(named: "Ocultar") { modelo.ocultar(e, deshacer: undoManager) }
        .accessibilityAction(named: "Abrir en pestaña nueva") { abrir(.pestanaNueva) }
    }

    // MARK: Normal

    private var filaNormal: some View {
        Button {
            if pulsacionLarga { pulsacionLarga = false; return }
            abrir(nil)
        } label: {
            HStack(spacing: 10) {
                icono
                VStack(alignment: .leading, spacing: 0) {
                    Text(nombre)
                        .tlsTexto(elegida ? TLSTipo.interfazFuerte : TLSTipo.interfazMedia)
                        .lineLimit(1)
                    if dato.debajo != nil || dato.atencion != nil {
                        HStack(spacing: 3) {
                            if let debajo = dato.debajo { Text(debajo) }
                            if let atencion = dato.atencion {
                                // El punto solo separa: sin texto delante, la línea empieza por el aviso.
                                if dato.debajo != nil { Text("·") }
                                Image(systemName: TLSEstado.atencion.simbolo)
                                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.atencion.color)
                                Text(atencion)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.atencion.color)
                            }
                        }
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let derecha = dato.derecha {
                    if dato.derechaEsAtajo {
                        Text(derecha).tlsTexto(TLSTipo.codigo.peso(400))
                            .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                            .accessibilityLabel(Tecla.leer(derecha))
                    } else {
                        Text(derecha).tlsTexto(TLSTipo.secundario.peso(500))
                            .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                    }
                }
                if let n = dato.insignia, n > 0 {
                    InsigniaAviso(n, palabra: dato.palabraInsignia, palabraVisible: false)
                }
            }
            .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : (dato.atenuado ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color))
        }
        .buttonStyle(EstiloFila(seleccionada: elegida, alto: TLSAltura.filaBarraLateral))
        .focusEffectDisabled()
        .simultaneousGesture(LongPressGesture(minimumDuration: TLSMovimiento.pulsacionLarga).onEnded { _ in
            pulsacionLarga = true
            modelo.editando = true
        })
        .accessibilityLabel(etiquetaAccesible)
        .accessibilityAddTraits(elegida ? .isSelected : [])
        .accessibilityIdentifier("lateral.\(e.id)")
    }

    // MARK: Edición

    private var filaEdicion: some View {
        HStack(spacing: 8) {
            if e.sePuedeOcultar {
                Button { modelo.ocultar(e, deshacer: undoManager) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TLSPaleta.superficie.color)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(TLSPaleta.textoSecundario.color))
                        .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ocultar \(nombre)")
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                    .help("Hoy no se puede ocultar")
                    .accessibilityLabel("Hoy no se puede ocultar")
            }
            icono
            Text(nombre)
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(dato.atenuado ? TLSPaleta.textoSecundario.color : TLSPaleta.texto.color)
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu { menu } label: {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Más opciones · ⌥⌘↑ ⌥⌘↓ mover · ⌥⌘→ ⌥⌘← meter y sacar")
            .accessibilityLabel("Mover u ocultar \(nombre)")
        }
        .padding(.leading, 2)
        .frame(minHeight: TLSAltura.filaLista)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(reducir ? TLSPaleta.bordeControl.color : TLSPaleta.separador.color,
                              style: StrokeStyle(lineWidth: reducir ? 1.5 : 1, dash: reducir ? [4, 3] : []))
        }
        .rotationEffect(.degrees(reducir ? 0 : (temblor ? TLSMovimiento.temblorGrados : -TLSMovimiento.temblorGrados)))
        .onAppear {
            guard !reducir else { return }
            withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true).delay(Double(indice % 4) * 0.07)) {
                temblor = true
            }
        }
        .onDisappear { temblor = false }
        .draggable(ArrastreBarra(elemento: e, desdeOcultos: false)) {
            HStack(spacing: 8) { icono; Text(nombre).tlsTexto(TLSTipo.interfazMedia) }
                .padding(.horizontal, 12)
                .frame(height: TLSAltura.filaBarraLateral)
                .background(RoundedRectangle(cornerRadius: 12).fill(TLSPaleta.superficieElevada.color))
        }
    }

    // MARK: Partes

    @ViewBuilder private var icono: some View {
        switch e {
        case .area(let a):
            IconoArea(a.tlsArea, tamano: 24, seleccionado: elegida && !modelo.editando, atenuado: dato.atenuado)
        case .base(let id):
            if let area = modelo.base(id)?.area {
                IconoArea(area.tlsArea, tamano: 24, simbolo: modelo.base(id)?.icono, seleccionado: elegida && !modelo.editando)
            } else {
                simbolo(modelo.base(id)?.icono ?? "tablecells")
            }
        default:
            simbolo(e.destino?.simbolo ?? "circle")
        }
    }

    private func simbolo(_ nombre: String) -> some View {
        Image(systemName: nombre)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(elegida && !modelo.editando ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private var colorGuia: Color {
        if case .area(let a)? = modelo.padre(de: e) { return a.tlsArea.relleno.color }
        if case .base(let id)? = modelo.padre(de: e), let a = modelo.base(id)?.area { return a.tlsArea.relleno.color }
        return TLSPaleta.bordeControl.color
    }

    private var datoPorDefecto: DatoFilaBarra {
        e == .todasLasBases ? DatoFilaBarra(derecha: "⇧⌘B", derechaEsAtajo: true) : DatoFilaBarra()
    }

    private var etiquetaAccesible: String {
        var partes = [nombre]
        if let d = dato.debajo { partes.append(d) }
        if let a = dato.atencion { partes.append(a) }
        if let n = dato.insignia, n > 0 { partes.append("\(n) \(dato.palabraInsignia)") }
        if let d = dato.derecha, !dato.derechaEsAtajo { partes.append(d) }
        return partes.joined(separator: ", ")
    }

    private func abrir(_ modo: ModoApertura?) {
        guard let destino = e.destino else { return }
        let m = modo ?? NavegarAccion.modo(teclas: NSEvent.modifierFlags)
        if case .entrar = m { navegar(destino, modo: .raiz) } else { navegar(destino, modo: m) }
    }

    @ViewBuilder private var menu: some View {
        if e.destino != nil {
            Button("Abrir en pestaña nueva") { abrir(.pestanaNueva) }
            Divider()
        }
        Button("Subir (⌥⌘↑)") { modelo.desplazar(e, -1, deshacer: undoManager) }
            .disabled(indice == 0)
        Button("Bajar (⌥⌘↓)") { modelo.desplazar(e, 1, deshacer: undoManager) }
            .disabled(indice >= modelo.filas.count - 1)
        if fila.dentro {
            Button("Sacar del grupo (⌥⌘←)") { modelo.meterDentro(e, false, deshacer: undoManager) }
        } else {
            Button("Meter dentro (⌥⌘→)") { modelo.meterDentro(e, true, deshacer: undoManager) }
                .disabled(!modelo.sePuedeMeter(e))
        }
        Button(e.sePuedeOcultar ? "Ocultar" : "Ocultar (Hoy siempre se ve)") { modelo.ocultar(e, deshacer: undoManager) }
            .disabled(!e.sePuedeOcultar)
        if case .base(let id) = e {
            Button("Quitar de la barra") { modelo.desfijarBase(id, deshacer: undoManager) }
        }
        Divider()
        Button(modelo.editando ? "Listo" : "Editar barra lateral") { modelo.editando.toggle() }
        Button("Restaurar barra original") { modelo.restaurarOriginal(deshacer: undoManager) }
    }
}

// MARK: Ocultos

private struct BandejaOcultos: View {
    let modelo: BarraLateralModelo
    @Environment(\.undoManager) private var undoManager
    @State private var encima = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Rotulo("Ocultos")
                Spacer()
                Text("\(modelo.ocultos.count)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Text("Siguen funcionando y los encuentras con ⌘K. Arrástralos a la barra o pulsa «Mostrar».")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            if modelo.ocultos.isEmpty {
                Text("Nada oculto. Arrastra aquí lo que no uses.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(modelo.ocultos, id: \.elemento) { o in
                HStack(spacing: 8) {
                    Text(modelo.nombre(o.elemento))
                        .tlsTexto(TLSTipo.interfazMedia)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        modelo.mostrar(o.elemento, deshacer: undoManager)
                    } label: {
                        Label("Mostrar", systemImage: "eye")
                    }
                    .tlsBoton(.secundario)
                    .accessibilityLabel("Mostrar \(modelo.nombre(o.elemento))")
                }
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .frame(minHeight: 44)
                .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
                .draggable(ArrastreBarra(elemento: o.elemento, desdeOcultos: true))
            }
            Button("Restaurar barra original") { modelo.restaurarOriginal(deshacer: undoManager) }
                .tlsBoton(.enlace)
                .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .fill(encima ? TLSPaleta.principalSuave.color : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .strokeBorder(encima ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color,
                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .dropDestination(for: ArrastreBarra.self) { items, _ in
            for item in items where !item.desdeOcultos { modelo.ocultar(item.elemento, deshacer: undoManager) }
            return true
        } isTargeted: { encima = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ocultos")
    }
}

// MARK: Recientes

private struct Recientes: View {
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        let lista = Array(sesion.recientes.prefix(3))
        if !lista.isEmpty {
            Rotulo("Recientes")
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ForEach(lista, id: \.self) { ruta in
                let resumen = sesion.resumen(de: ruta)
                Button {
                    let destino = sesion.destino(para: ruta)
                    let m = NavegarAccion.modo(teclas: NSEvent.modifierFlags)
                    if case .entrar = m { navegar(destino, modo: .raiz) } else { navegar(destino, modo: m) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: resumen?.kind.systemImage ?? "doc.text")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(sesion.titulo(de: ruta)).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                            Text((resumen?.kind.etiqueta ?? "Nota").lowercased())
                                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(EstiloFila(alto: TLSAltura.filaBarraLateral))
                .focusEffectDisabled()
            }
        }
    }
}

// MARK: Pie

private struct PieBarra: View {
    let sesion: VaultSession
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
            PieAsistentesBarra(sesion: sesion)  // F4 · rol asistentes: el interruptor «Asistentes encendidos / en pausa»
            Menu {
                if sesion.entry.clase != .real {
                    if sesion.puedeEscribir {
                        Button("Pasar a solo lectura") { Task { await sesion.pasarASoloLectura(using: model) } }
                    } else {
                        Button("Permitir cambios en esta copia") { Task { await sesion.permitirCambios(using: model) } }
                    }
                    Divider()
                }
                Section("Cambiar de empresa") {
                    ForEach(model.entries) { otra in
                        Button("\(otra.nombre) · \(otra.claseDescripcion)") { openWindow.abrirEmpresa(otra.id) }
                            .disabled(otra.id == sesion.entry.id)
                    }
                }
                Button("Abrir el selector de empresas…") { openWindow(id: SceneID.launcher) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: sesion.puedeEscribir ? "pencil" : "lock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("\(titulo). \(detalle)")
            .accessibilityHint("Cambia el modo o la empresa")
            .accessibilityIdentifier("lateral.soloLectura")
        }
        .background(TLSPaleta.superficie.color)
    }

    private var titulo: String {
        switch sesion.modoEscritura {
        case .escribe: "Esta app escribe"
        case .abriendo: "Abriendo…"
        case .soloLectura: "Solo lectura"
        }
    }

    private var detalle: String {
        switch sesion.modoEscritura {
        case .escribe: sesion.entry.clase == .demo ? "En este ejemplo; se puede deshacer" : "En esta copia; se puede deshacer"
        case .abriendo: sesion.entry.claseDescripcion
        case .soloLectura(let motivo): motivo.texto
        }
    }
}
