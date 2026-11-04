import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSVisores

/// La Carpeta (§2.1: una raíz, y cada carpeta de dentro un nivel): lo que hay en una carpeta de la empresa,
/// con la estética de Mosaico v2. Abre las notas en su pantalla y los ficheros en su visor; «Nueva…» con las
/// plantillas de la carpeta, «Renombrar» y «Mover» con la vista previa de los enlaces que se actualizan,
/// «Retirar» al Archivo (nunca se borra) y «Mostrar en Finder». Arrastrar una fila a una carpeta la mueve
/// (con vista previa); lo mismo se puede hacer con el menú, con atajos y con VoiceOver. El `init` es contrato.
struct CarpetaPantalla: View {
    let carpeta: VaultPath?
    let sesion: VaultSession
    @State private var modelo: CarpetaModelo?

    init(carpeta: VaultPath?, sesion: VaultSession) {
        self.carpeta = carpeta
        self.sesion = sesion
    }

    var body: some View {
        Group {
            if let modelo {
                CarpetaVista(modelo: modelo)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if modelo == nil || modelo?.carpeta != (carpeta ?? .root) {
                modelo = CarpetaModelo(carpeta: carpeta, sesion: sesion)
            }
        }
    }
}

/// El contenido de la Carpeta sobre su modelo.
struct CarpetaVista: View {
    @Bindable var modelo: CarpetaModelo
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @State private var objetivo: VaultPath?
    @State private var primeraRevision = true

    private var sesion: VaultSession { modelo.sesion }
    private var destinoPantalla: Destino { .carpeta(modelo.carpeta.isRoot ? nil : modelo.carpeta) }
    private var elegida: FilaCarpeta? {
        modelo.seleccion.count == 1 ? modelo.seleccion.first.flatMap { modelo.fila($0) } : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            cabecera
            if let arreglo = modelo.arreglo {
                TarjetaArreglo(previa: arreglo, verCambios: { modelo.hoja = .arreglo },
                               arreglar: { Task { await modelo.arreglarMovimientos() } },
                               descartar: { modelo.descartarArreglo() })
            }
            barraAcciones
            lista
        }
        .padding(.horizontal, TLSEspacio.e24)
        .padding(.top, TLSEspacio.e20)
        .padding(.bottom, TLSEspacio.e16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: "\(sesion.revision)·\(sesion.isReady)") {
            await modelo.cargar()
            if primeraRevision {
                primeraRevision = false
                if let guardada = nav?.recuerdo(de: destinoPantalla).seleccion, modelo.seleccion.isEmpty {
                    let validas = Set(guardada.map(VaultPath.init)).filter { modelo.fila($0) != nil }
                    modelo.seleccion = validas
                }
                await modelo.revisarMovimientosExternos()
            } else if modelo.cambioDeExistencia(sesion.ultimasCambiadas) {
                await modelo.revisarMovimientosExternos(fresca: true)
            }
        }
        .onChange(of: modelo.seleccion) { _, nueva in
            nav?.actualizarRecuerdo(de: destinoPantalla) { $0.seleccion = nueva.map(\.raw).sorted() }
        }
        .sheet(item: $modelo.hoja) { hoja in
            switch hoja {
            case .nueva(let s):
                HojaNueva(modelo: modelo, seleccion: s) { destino in navegar(destino, modo: .entrar) }
            case .renombrar(let ruta):
                HojaRenombrar(modelo: modelo, ruta: ruta)
            case .mover(let rutas, let destino):
                HojaMover(modelo: modelo, rutas: rutas, destinoInicial: destino)
            case .arreglo:
                HojaArreglo(modelo: modelo)
            }
        }
        .confirmationDialog(
            "¿Retirar «\(modelo.retirando.map { modelo.fila($0)?.titulo ?? $0.stem } ?? "")» al Archivo?",
            isPresented: Binding(get: { modelo.retirando != nil }, set: { if !$0 { modelo.retirando = nil } }),
            titleVisibility: .visible
        ) {
            Button("Retirar") {
                if let r = modelo.retirando { Task { await modelo.retirar(r) } }
                modelo.retirando = nil
            }
            Button("Cancelar", role: .cancel) { modelo.retirando = nil }
        } message: {
            Text(textoRetirar)
        }
        .background { atajos }
    }

    private var textoRetirar: String {
        guard let r = modelo.retirando else { return "" }
        let n = sesion.enlazanAqui(r).count
        let enlaces = n == 0 ? "" : (n == 1 ? " Una nota la enlaza." : " \(n) notas la enlazan.")
        return "Se mueve a la carpeta Archivo, no se borra. Puedes deshacerlo con ⌘Z." + enlaces
    }

    // MARK: Cabecera

    private var cabecera: some View {
        HStack(alignment: .center, spacing: TLSEspacio.e12) {
            if let area = modelo.areaDeLaCarpeta {
                IconoArea(area.tlsArea, tamano: 32)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(TLSPaleta.bandeja.color))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(modelo.titulo)
                    .tlsTexto(TLSTipo.tituloPantalla)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                Text(modelo.cargada ? modelo.resumen : "Leyendo…")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: TLSEspacio.e8)
            Button { sesion.revealInFinder(modelo.carpeta) } label: { Label("Mostrar en Finder", systemImage: "folder") }
                .tlsBoton(.secundario)
                .help("Abre esta carpeta en Finder")
            Button { modelo.hoja = .nueva(seleccion: elegida?.ruta) } label: { Label("Nueva…", systemImage: "plus") }
                .tlsBoton(.principal)
                .disabled(modelo.motivoSoloLectura != nil)
                .help(modelo.motivoSoloLectura ?? "Crear una nota en esta carpeta (⌘N)")
                .accessibilityHint(modelo.motivoSoloLectura ?? "")
        }
    }

    // MARK: Acciones con lo elegido

    private var barraAcciones: some View {
        HStack(spacing: TLSEspacio.e8) {
            Group {
                if let motivo = modelo.motivoSoloLectura {
                    Label(motivo, systemImage: "lock")
                } else if modelo.seleccion.isEmpty {
                    Text("Elige algo para renombrarlo, moverlo o retirarlo. Doble clic o ↩ para abrir.")
                } else if let elegida {
                    Text(elegida.titulo)
                } else {
                    Text("\(modelo.seleccion.count) elegidos")
                }
            }
            .tlsTexto(TLSTipo.secundario)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: TLSEspacio.e8)
            Button("Abrir") { if let elegida { abrir(elegida) } }
                .tlsBoton(.secundario)
                .disabled(elegida == nil)
            Button("Renombrar…") { if let elegida { modelo.hoja = .renombrar(elegida.ruta) } }
                .tlsBoton(.secundario)
                .disabled(elegida == nil || modelo.motivoSoloLectura != nil || elegida.map { modelo.estaRetirada($0.ruta) } == true)
                .help("Renombrar (⌘R)")
            Button("Mover a…") { modelo.hoja = .mover(Array(modelo.seleccion).sorted(), destino: nil) }
                .tlsBoton(.secundario)
                .disabled(modelo.seleccion.isEmpty || modelo.motivoSoloLectura != nil || modelo.seleccion.contains(where: modelo.esLaCarpetaArchivo))
                .help("Mover a otra carpeta (⇧⌘M)")
            Button("Retirar…") { if let elegida { modelo.retirando = elegida.ruta } }
                .tlsBoton(.secundario)
                .disabled(elegida == nil || modelo.motivoSoloLectura != nil || elegida.map { modelo.estaRetirada($0.ruta) } == true)
                .help("Retirar al Archivo (⌘⌫)")
        }
        .frame(minHeight: TLSAltura.objetivoMinimo + 4)
    }

    // MARK: Lista

    @ViewBuilder
    private var lista: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        Group {
            if !modelo.cargada {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if modelo.filas.isEmpty {
                VacioExplicado(icono: "folder", titulo: "Esta carpeta está vacía",
                               porQue: modelo.motivoSoloLectura == nil
                                   ? "Crea una nota con «Nueva…» o arrastra aquí algo desde otra carpeta."
                                   : "Aquí no hay nada todavía.",
                               accion: modelo.motivoSoloLectura == nil ? "Nueva…" : nil,
                               alPulsar: { modelo.hoja = .nueva(seleccion: nil) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $modelo.seleccion) {
                    ForEach(modelo.filas) { fila in
                        filaVista(fila)
                            .tag(fila.ruta)
                            .listRowInsets(EdgeInsets(top: 0, leading: TLSEspacio.e8, bottom: 0, trailing: TLSEspacio.e8))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, TLSAltura.filaLista)
                .contextMenu(forSelectionType: VaultPath.self) { rutas in
                    menu(rutas)
                } primaryAction: { rutas in
                    if rutas.count == 1, let r = rutas.first, let f = modelo.fila(r) { abrir(f) }
                }
                .onKeyPress(.space) {
                    guard let elegida, !elegida.esCarpeta, !elegida.privado else { return .ignored }
                    nav?.vistaPrevia = nav?.vistaPrevia == elegida.ruta ? nil : elegida.ruta
                    return .handled
                }
                .tlsRecordarDesplazamiento(destinoPantalla)
                .accessibilityLabel("Contenido de \(modelo.titulo)")
            }
        }
        .padding(.vertical, TLSEspacio.e4)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func filaVista(_ fila: FilaCarpeta) -> some View {
        FilaCarpetaVista(fila: fila, objetivo: objetivo == fila.ruta)
            .draggable(ArrastreCarpeta(empresa: sesion.entry.id, rutas: rutasArrastradas(fila).map(\.raw))) {
                Chip(rutasArrastradas(fila).count > 1 ? "\(rutasArrastradas(fila).count) elementos" : fila.titulo,
                     icono: fila.esCarpeta ? "folder" : fila.simbolo)
            }
            .modifier(SoltarEnCarpeta(fila: fila, modelo: modelo, objetivo: $objetivo))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fila.etiquetaAccesible)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Abrir") { abrir(fila) }
            .accessibilityAction(named: "Vista previa") { if !fila.esCarpeta, !fila.privado { nav?.vistaPrevia = fila.ruta } }
            .accessibilityAction(named: "Renombrar") { if modelo.motivoSoloLectura == nil { modelo.hoja = .renombrar(fila.ruta) } }
            .accessibilityAction(named: "Mover a otra carpeta") {
                if modelo.motivoSoloLectura == nil, !modelo.esLaCarpetaArchivo(fila.ruta) { modelo.hoja = .mover([fila.ruta], destino: nil) }
            }
            .accessibilityAction(named: "Retirar al Archivo") { if modelo.motivoSoloLectura == nil { modelo.retirando = fila.ruta } }
    }

    /// Lo que se arrastra: lo elegido si la fila está entre lo elegido; si no, solo la fila.
    private func rutasArrastradas(_ fila: FilaCarpeta) -> [VaultPath] {
        modelo.seleccion.contains(fila.ruta) ? Array(modelo.seleccion).sorted() : [fila.ruta]
    }

    @ViewBuilder
    private func menu(_ rutas: Set<VaultPath>) -> some View {
        let soloLectura = modelo.motivoSoloLectura != nil
        if rutas.isEmpty {
            Button("Nueva…") { modelo.hoja = .nueva(seleccion: nil) }.disabled(soloLectura)
            Button("Mostrar en Finder") { sesion.revealInFinder(modelo.carpeta) }
        } else if rutas.count == 1, let r = rutas.first, let f = modelo.fila(r) {
            Button("Abrir") { abrir(f) }
            Button("Abrir en pestaña nueva") { navegar(modelo.destino(de: f), modo: .pestanaNueva) }
            Button("Abrir en ventana nueva") { navegar(modelo.destino(de: f), modo: .ventanaNueva) }
            if !f.esCarpeta, !f.privado {
                Button("Vista previa") { nav?.vistaPrevia = r }
            }
            Divider()
            if let tipo = f.tipo, tipo.abreComoFicha {
                Button("Nueva para «\(f.titulo)»…") { modelo.hoja = .nueva(seleccion: r) }.disabled(soloLectura)
            }
            Button("Renombrar…") { modelo.hoja = .renombrar(r) }.disabled(soloLectura || modelo.estaRetirada(r))
            Button("Mover a…") { modelo.hoja = .mover([r], destino: nil) }.disabled(soloLectura || modelo.esLaCarpetaArchivo(r))
            Button("Retirar al Archivo…") { modelo.retirando = r }.disabled(soloLectura || modelo.estaRetirada(r))
            Divider()
            if let enlace = sesion.enlaceParaCopiar(modelo.destino(de: f)) {
                Button("Copiar enlace") { copiar(enlace) }
            }
            Button("Mostrar en Finder") { sesion.revealInFinder(r) }
        } else {
            Button("Mover \(rutas.count) elementos a…") { modelo.hoja = .mover(Array(rutas).sorted(), destino: nil) }
                .disabled(soloLectura || rutas.contains(where: modelo.esLaCarpetaArchivo))
            Button("Mostrar en Finder") {
                if let root = sesion.root { NSWorkspace.shared.activateFileViewerSelecting(rutas.map { $0.url(in: root) }) }
            }
        }
    }

    private func abrir(_ fila: FilaCarpeta) {
        navegar(modelo.destino(de: fila))
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }

    // MARK: Atajos

    /// ⌘N Nueva…, ⌘R Renombrar, ⇧⌘M Mover a…, ⌘⌫ Retirar (con la Carpeta delante).
    private var atajos: some View {
        Group {
            Button("") { if modelo.motivoSoloLectura == nil { modelo.hoja = .nueva(seleccion: elegida?.ruta) } }
                .keyboardShortcut("n", modifiers: .command)
            Button("") {
                if let elegida, modelo.motivoSoloLectura == nil, !modelo.estaRetirada(elegida.ruta) { modelo.hoja = .renombrar(elegida.ruta) }
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("") {
                if !modelo.seleccion.isEmpty, modelo.motivoSoloLectura == nil { modelo.hoja = .mover(Array(modelo.seleccion).sorted(), destino: nil) }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("") {
                if let elegida, modelo.motivoSoloLectura == nil, !modelo.estaRetirada(elegida.ruta) { modelo.retirando = elegida.ruta }
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Soltar filas sobre una carpeta: abre «Mover» con la vista previa de los enlaces (nunca mueve sin confirmar).
private struct SoltarEnCarpeta: ViewModifier {
    let fila: FilaCarpeta
    let modelo: CarpetaModelo
    @Binding var objetivo: VaultPath?

    func body(content: Content) -> some View {
        if fila.esCarpeta {
            content.dropDestination(for: ArrastreCarpeta.self) { items, _ in
                let rutas = ArrastreCarpeta.rutas(items, en: modelo.sesion.entry.id).filter { r in
                    r != fila.ruta && !fila.ruta.isDescendant(of: r) && r.parent != fila.ruta && !modelo.esLaCarpetaArchivo(r)
                }
                objetivo = nil
                guard !rutas.isEmpty, modelo.motivoSoloLectura == nil else { return false }
                modelo.hoja = .mover(rutas, destino: fila.ruta)
                return true
            } isTargeted: { dentro in
                if dentro { objetivo = fila.ruta } else if objetivo == fila.ruta { objetivo = nil }
            }
        } else {
            content
        }
    }
}

/// Una fila de la Carpeta: icono (o el icono de app del área), título, detalle y marcas (Privado, En iCloud).
struct FilaCarpetaVista: View {
    let fila: FilaCarpeta
    let objetivo: Bool
    @Environment(\.backgroundProminence) private var prominencia

    var body: some View {
        let resaltada = prominencia == .increased
        HStack(spacing: TLSEspacio.e12) {
            if let area = fila.area {
                IconoArea(area.tlsArea, tamano: 24, seleccionado: resaltada)
            } else {
                Image(systemName: fila.simbolo)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(fila.titulo)
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fila.detalle)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: TLSEspacio.e8)
            if fila.privado {
                PastillaEstado(.sinDato, palabra: "Privado", sobreColor: resaltada)
            }
            if fila.enICloud {
                Label("En iCloud", systemImage: "icloud")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
            }
            if fila.esCarpeta {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, TLSEspacio.e4)
        .frame(minHeight: TLSAltura.filaLista)
        .background {
            if objetivo {
                RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                    .fill(TLSPaleta.principalSuave.color)
                    .overlay(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                        .strokeBorder(TLSPaleta.principal.color, lineWidth: 1.5))
            }
        }
        .contentShape(Rectangle())
    }
}

/// Tarjeta de lo movido fuera de la app con enlaces que siguen apuntando a donde estaba.
struct TarjetaArreglo: View {
    let previa: RefactorPreview
    let verCambios: () -> Void
    let arreglar: () -> Void
    let descartar: () -> Void

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            Image(systemName: TLSEstado.atencion.simbolo)
                .foregroundStyle(TLSEstado.atencion.color.color)
                .font(.system(size: 17, weight: .semibold))
                .accessibilityLabel(TLSEstado.atencion.palabra)
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                Text(detalle)
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TLSEspacio.e8)
            Button("Ahora no", action: descartar).tlsBoton(.discreto)
            Button("Ver los cambios", action: verCambios).tlsBoton(.secundario)
            Button("Arreglar los enlaces", action: arreglar).tlsBoton(.principal)
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSEstado.atencion.tinte.color))
        .overlay(forma.strokeBorder(TLSEstado.atencion.color.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var titulo: String {
        previa.traslados.count == 1
            ? "«\(previa.traslados[0].a.stem)» se movió fuera de la app"
            : "\(previa.traslados.count) elementos se movieron fuera de la app"
    }

    private var detalle: String {
        let total = previa.enlaces + previa.filasCSV
        let enlaces = total == 1 ? "1 enlace sigue" : "\(total) enlaces siguen"
        let arreglar = total == 1 ? "Puedo arreglarlo (se puede deshacer)." : "Puedo arreglarlos (se puede deshacer)."
        if previa.traslados.count == 1 {
            let t = previa.traslados[0]
            let donde = t.a.parent.map { $0.isRoot ? "la carpeta de tu empresa" : $0.components.joined(separator: " › ") } ?? ""
            return "Ahora está en «\(donde)» y \(enlaces) apuntando a donde estaba. \(arreglar)"
        }
        return "\(enlaces.prefix(1).uppercased() + enlaces.dropFirst()) apuntando a donde estaban. \(arreglar)"
    }
}
