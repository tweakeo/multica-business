import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

// F6 · rol buzon-relevo. Ajustes › Esta empresa › «Pasar a mi carpeta real» (solo en una copia con origen real; oculto
// en el resto) y la hoja con los pasos: explicación en llano, comprobación de que nadie más usa la carpeta real, vista
// previa (se añaden N, cambian N, se archivan N, nada se borra; conflictos con «Quedarse con la real» por defecto),
// confirmación escribiendo el nombre de la empresa, progreso, comprobación y «Deshacer». Estética Mosaico v2.

/// La fila de Ajustes. No aparece si esta carpeta no es una copia con su carpeta real registrada.
struct FilaRelevoAjustes: View {
    let sesion: VaultSession
    @Environment(AppModel.self) private var model
    @State private var modelo: ModeloRelevo?
    @State private var hoja = false

    // F6 · corrector (P2-12): si toca, la fila se pinta ya (lo decide `DisponibilidadDelRelevo`, que solo lee el
    // registro) y su `.task` prepara el modelo; antes colgaba de un `Group` vacío cuyo `.task` no se lanzaba.
    private var disponible: Bool {
        if case .disponible = DisponibilidadDelRelevo.evaluar(sesion.entry, registradas: model.registry.load()) { return true }
        return false
    }

    var body: some View {
        if disponible {
            fila.task(id: sesion.entry.id) {
                modelo = ModeloRelevo.deLaSesion(sesion, registro: model.registry)
            }
        }
    }

    @ViewBuilder
    private var fila: some View {
        Group {
            if let modelo {
                LabeledContent("Tu carpeta real") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(ModeloRelevo.explicacionCorta)
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                        Button(TextosDelRelevo.titulo + "…") { hoja = true }
                            .help("Abre la vista previa: hasta que confirmes, no se cambia nada")
                            .accessibilityIdentifier("ajustes.relevo")
                        Text("Antes verás qué cambia y tendrás que confirmarlo escribiendo «\(modelo.empresa)». No se borra nada y se puede deshacer.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .sheet(isPresented: $hoja) { RelevoHoja(modelo: modelo) }
            } else {
                LabeledContent("Tu carpeta real") { Text("Leyendo…").foregroundStyle(.secondary) }
            }
        }
    }
}

/// F6 · corrector (P1-3): «Deshacer el último relevo» en Ajustes, en la copia y en la carpeta real, también después de
/// cerrar la hoja o la app. Usa la marca del relevo y su copia de seguridad (nunca la carpeta). Solo si nada se ha
/// guardado después en la carpeta real; si no, lo dice y deja ver la copia de seguridad.
struct FilaDeshacerRelevo: View {
    let sesion: VaultSession
    @Environment(AppModel.self) private var model
    @State private var confirmar = false
    @State private var trabajando = false
    @State private var aviso: (String, TLSEstado)?
    /// Cambia al deshacer para volver a leer la marca.
    @State private var version = 0

    // F6 · corrector (P2-12): se lee en el momento (registro y marca, sin tocar la carpeta): sin `.task` que pueda no
    // lanzarse en una fila vacía.
    var body: some View {
        let encontrado = buscar()
        Group {
            if let (real, marca) = encontrado {
                LabeledContent("Último relevo") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Pasaste la copia a «\(real.nombre)» \(TextosDelRelevo.cuando(iso: marca.fecha) ?? "hace poco"): "
                             + "\(marca.anadidos) añadidos, \(marca.cambiados) cambiados y \(marca.archivados) archivados.")
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Mostrar la copia de seguridad") {
                                FolderAccess.revealInFinder(URL(fileURLWithPath: marca.respaldo, isDirectory: true))
                            }
                            Button("Deshacer el último relevo…") { confirmar = true }
                                .disabled(trabajando)
                                .accessibilityIdentifier("ajustes.relevo.deshacer")
                        }
                        Text(TextosDelRelevo.respaldo(iso: marca.fecha) + ".")
                            .font(.callout).foregroundStyle(.secondary)
                        if let (t, e) = aviso { AvisoEnLinea(t, estado: e).accessibilityIdentifier("ajustes.relevo.aviso") }
                    }
                }
                .alert("¿Deshacer el último relevo?", isPresented: $confirmar) {
                    Button("Deshacer el relevo", role: .destructive) { Task { await deshacer(real, marca) } }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Tu carpeta real «\(real.nombre)» vuelve a como estaba antes de pasar la copia y queda otra vez en solo lectura. Solo se puede si no has guardado nada después en ella.")
                }
            } else if let (t, e) = aviso {
                LabeledContent("Último relevo") { AvisoEnLinea(t, estado: e) }
            }
        }
    }

    /// La real de esta ventana (si es la real) o aquella a la que se pasó esta copia, con su último relevo en pie.
    private func buscar() -> (VaultEntry, MarcaDeRelevo)? {
        _ = version
        let appSupport = model.registry.directory
        let registradas = model.registry.load()
        let candidatas = sesion.entry.clase == .real ? [sesion.entry] : registradas.filter { $0.clase == .real }
        for r in candidatas {
            guard let m = AplicadorDeRelevo.ultimoRelevo(appSupport: appSupport, real: r.id) else { continue }
            if sesion.entry.clase == .real || m.copia_id == sesion.entry.id.uuidString.lowercased() { return (r, m) }
        }
        return nil
    }

    private func deshacer(_ real: VaultEntry, _ marca: MarcaDeRelevo) async {
        trabajando = true
        defer { trabajando = false }
        let registro = model.registry
        let appSupport = registro.directory
        let aplicador = AplicadorDeRelevo(entorno: .init(appSupport: appSupport, registro: registro, autor: sesion.autor))
        let root = registro.resolveURL(real) ?? URL(fileURLWithPath: real.ruta, isDirectory: true)
        do {
            let propio = sesion.entry.id == real.id ? sesion.bus : nil
            let bus: CommandBus
            if let propio {
                bus = propio
            } else {
                bus = CommandBus(writer: try await VaultWriter.open(entry: real, root: root, options: .init(
                    stateDirectory: appSupport.appendingPathComponent(real.id.uuidString.lowercased(), isDirectory: true),
                    appSupport: appSupport, relevo: true)))
            }
            let igual = try await aplicador.deshacerUltimo(real: real, root: root, con: bus)
            if propio == nil { await bus.writer.close() }
            version += 1
            aviso = (igual ? "Deshecho: tu carpeta real está como antes del relevo y vuelve a solo lectura."
                     : "Deshecho, pero tu carpeta real no ha quedado idéntica a antes. La copia de seguridad sigue en tu Mac.",
                     igual ? .bien : .atencion)
            model.reload()
        } catch {
            aviso = (error.localizedDescription.contains("Cierra") ? error.localizedDescription
                     : error.localizedDescription + " Si tienes tu carpeta real abierta en otra ventana, ciérrala y vuelve a intentarlo.",
                     .atencion)
        }
    }
}

/// La hoja de «Pasar a mi carpeta real».
struct RelevoHoja: View {
    @Bindable var modelo: ModeloRelevo
    /// Alto de la hoja (las capturas lo alargan para enseñarla entera).
    var alto: CGFloat = 780
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model: AppModel?
    @FocusState private var enNombre: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera
            Divider().overlay(TLSPaleta.separador.color)
            ScrollView {
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    contenido
                }
                .padding(TLSEspacio.e20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(TLSPaleta.separador.color)
            botones
        }
        .frame(width: 720, height: alto)
        .background(TLSPaleta.superficieElevada.color)
        .accessibilityIdentifier("relevo.hoja")
    }

    // MARK: Cabecera

    private var cabecera: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TLSPaleta.principal.color)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TLSPaleta.principalSuave.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(TextosDelRelevo.titulo).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Text("De esta copia a «\(modelo.empresa)», tu carpeta de verdad.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: 0)
            if case .vistaPrevia = modelo.fase { PastillaEstado(.sinDato, palabra: "Vista previa: aún no se ha cambiado nada") }
            BotonSaberMas(seccion: "relevo", titulo: "Saber más").tlsBoton(.enlace)
        }
        .padding(TLSEspacio.e20)
    }

    // MARK: Contenido

    @ViewBuilder
    private var contenido: some View {
        switch modelo.fase {
        case .inicio, .comprobando:
            explicacion
            pasos(actual: modelo.fase == .comprobando ? 0 : nil)
        case .bloqueado(let m):
            AvisoEnLinea(m, estado: .mal).accessibilityIdentifier("relevo.bloqueado")
            Text("Cuando la cierres, pulsa «Volver a comprobar». Hasta entonces no se toca nada.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
        case .preparando:
            if let c = modelo.cerrojo { AvisoEnLinea(c, estado: .bien) }
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Comparando la copia con tu carpeta real… (solo leo)") }
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
        case .vistaPrevia:
            vistaPrevia
        case .aplicando:
            pasos(actual: 3)
        case .hecho:
            hecho
        case .deshaciendo:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Dejando tu carpeta real como estaba…") }
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
        case .deshecho:
            AvisoEnLinea(modelo.deshechoBien == true
                         ? "Deshecho: tu carpeta real está exactamente como antes, y vuelve a ser solo lectura desde aquí."
                         : "Deshecho, pero tu carpeta real no ha quedado idéntica a antes. La copia de seguridad sigue en los ajustes de la app.",
                         estado: modelo.deshechoBien == true ? .bien : .atencion)
                .accessibilityIdentifier("relevo.deshecho")
        case .error(let m):
            AvisoEnLinea(m, estado: .mal).accessibilityIdentifier("relevo.error")
        }
    }

    private var explicacion: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text(ModeloRelevo.explicacionCorta).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(TextosDelRelevo.explicacion).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .accessibilityIdentifier("relevo.explicacion")
    }

    /// Los cinco pasos; `actual` lleva el indicador de trabajo.
    private func pasos(actual: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rotulo(actual == nil ? "Qué va a pasar" : "Trabajando")
            ForEach(Array(ModeloRelevo.pasos.enumerated()), id: \.offset) { i, p in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Group {
                        if let a = actual, i == a || (a == 3 && i == 4) {
                            ProgressView().controlSize(.small)
                        } else if let a = actual, i < a {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(TLSPaleta.bien.color)
                        } else {
                            Text("\(i + 1)").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.principal.color)
                        }
                    }
                    .frame(width: 20)
                    Text(p).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Vista previa

    @ViewBuilder
    private var vistaPrevia: some View {
        if let v = modelo.vista {
            if let c = modelo.cerrojo { AvisoEnLinea(c, estado: .bien).accessibilityIdentifier("relevo.cerrojo") }
            cifras
            // F6 · corrector (P3-14): las cifras ya lo dicen; el resumen solo si añade conflictos o lo de iCloud. Y la
            // confirmación (con el campo del nombre) antes de las listas, para que se vea sin bajar.
            if !v.conflictos.isEmpty || !v.soloEnICloud.isEmpty {
                Text(v.resumen).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityIdentifier("relevo.resumen")
            }
            if !v.conflictos.isEmpty { conflictos(v) }
            confirmacion(v)
            listas(v)
        }
    }

    private var cifras: some View {
        HStack(spacing: TLSEspacio.e12) {
            ForEach(modelo.cifras, id: \.etiqueta) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.etiqueta).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text(c.etiqueta == "Se borran" ? "Nada" : "\(c.valor)").tlsTexto(TLSTipo.cifraMedia)
                        .foregroundStyle(c.etiqueta == "Se borran" ? TLSPaleta.bien.color : TLSPaleta.texto.color)
                }
                .padding(TLSEspacio.e12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("relevo.cifras")
    }

    private func conflictos(_ v: VistaPreviaDeRelevo) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: 8) {
                Text("Cambió en las dos").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                InsigniaAviso(v.conflictos.count, palabra: v.conflictos.count == 1 ? "conflicto" : "conflictos")
            }
            Text("Estos ficheros cambiaron en tu carpeta real después de hacer la copia. Si no eliges nada, se queda lo de tu carpeta real.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color).fixedSize(horizontal: false, vertical: true)
            ForEach(v.conflictos, id: \.ruta) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(TLSPaleta.atencion.color).accessibilityHidden(true)
                        Text(c.ruta.raw).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    }
                    Text(c.explicacion).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    Picker("Qué se queda en «\(c.ruta.name)»", selection: Binding(
                        get: { modelo.eleccion(c.ruta) },
                        set: { modelo.elegir($0, para: c.ruta) })) {
                        Text("Quedarse con la real").tag(ConflictoDeRelevo.Eleccion.quedarseConLaReal)
                        Text(c.tipo == .laCopiaLoQuito ? "Quedarse con la copia (se archiva)" : "Quedarse con la copia")
                            .tag(ConflictoDeRelevo.Eleccion.quedarseConLaCopia)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Qué se queda en \(c.ruta.name)")
                }
                .padding(TLSEspacio.e12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                .overlay(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).strokeBorder(TLSPaleta.atencion.color.opacity(0.5)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("relevo.conflictos")
    }

    @ViewBuilder
    private func listas(_ v: VistaPreviaDeRelevo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            grupo("Se añaden", modelo.lista(.anadir).map(\.ruta), icono: "plus.circle")
            grupo("Cambian", modelo.lista(.cambiar).map(\.ruta), icono: "pencil.circle")
            grupo("Se archivan en Archivo/", modelo.lista(.archivar).map(\.ruta), icono: "archivebox")
            grupo("Solo en iCloud: no se tocan", v.soloEnICloud, icono: "icloud")
            grupo("Nuevos en tu carpeta real: se quedan", v.nuevosEnLaReal, icono: "sparkles")
            grupo("Cambiaron solo en tu carpeta real: se quedan", v.soloCambiaronEnLaReal, icono: "checkmark.circle")
            grupo("Dentro de lo privado: nunca se pasan", v.noSePasan, icono: "lock")
        }
        .accessibilityIdentifier("relevo.listas")
    }

    @ViewBuilder
    private func grupo(_ titulo: String, _ rutas: [VaultPath], icono: String) -> some View {
        if !rutas.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rutas.prefix(200), id: \.self) { r in
                        Text(r.raw).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).textSelection(.enabled)
                    }
                    if rutas.count > 200 {
                        Text("y \(rutas.count - 200) más").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .padding(.leading, 24)
            } label: {
                Label("\(titulo) · \(rutas.count)", systemImage: icono).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
            }
        }
    }

    private func confirmacion(_ v: VistaPreviaDeRelevo) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Rotulo("Confirmar")
            Text(v.textoDeConfirmacion).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("relevo.textoConfirmacion")
            Text(TextosDelRelevo.pideNombre(modelo.empresa)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            TextField("Nombre de tu empresa", text: $modelo.escrito)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .focused($enNombre)
                .accessibilityLabel(TextosDelRelevo.pideNombre(modelo.empresa))
                .accessibilityIdentifier("relevo.nombre")
            if let a = modelo.aviso { AvisoEnLinea(a, estado: .mal).accessibilityIdentifier("relevo.aviso") }
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).strokeBorder(TLSPaleta.borde1.color))
    }

    // MARK: Hecho

    @ViewBuilder
    private var hecho: some View {
        if let r = modelo.resultado {
            AvisoEnLinea(modelo.textoDeComprobacion ?? "", estado: r.correcto ? .bien : .atencion)
                .accessibilityIdentifier("relevo.comprobacion")
            VStack(alignment: .leading, spacing: 6) {
                fila("Añadidos", "\(r.marca.anadidos)")
                fila("Cambiados", "\(r.marca.cambiados)")
                fila("Archivados", "\(r.marca.archivados) (en Archivo/, nada borrado)")
                HStack(alignment: .firstTextBaseline) {
                    Text("Copia de seguridad").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(width: 150, alignment: .leading)
                    Text(TextosDelRelevo.respaldo(iso: r.marca.fecha)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Mostrar en Finder") { FolderAccess.revealInFinder(r.respaldo) }.tlsBoton(.enlace)
                        .accessibilityIdentifier("relevo.respaldo.finder")
                }
                if let n = r.notaDePropuestas { fila("Propuestas", "En el Buzón de tu carpeta real: «\(n.stem)» (no se ha aplicado nada)") }
            }
            .padding(TLSEspacio.e12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            Text("Si algo no te convence, «Deshacer» deja tu carpeta real exactamente como estaba (mientras no se haya guardado nada después). Si cierras esta ventana, lo tienes también en Ajustes › Esta empresa › «Deshacer el último relevo». Desde ahora, la app escribe en tu carpeta real y la copia queda como estaba.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fila(_ t: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.textoSecundario.color).frame(width: 150, alignment: .leading)
            Text(v).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Botones

    private var botones: some View {
        HStack(spacing: 8) {
            switch modelo.fase {
            case .inicio, .comprobando:
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Comprobar y ver qué cambia") { Task { await modelo.preparar() } }
                    .tlsBoton(.principal)
                    .disabled(modelo.fase == .comprobando)
                    .help("Solo lee: no se cambia nada")
                    .accessibilityIdentifier("relevo.preparar")
            case .bloqueado, .error:
                Button("Cerrar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Volver a comprobar") { Task { await modelo.preparar() } }.tlsBoton(.principal)
                    .accessibilityIdentifier("relevo.reintentar")
            case .preparando, .aplicando, .deshaciendo:
                Spacer()
                ProgressView().controlSize(.small)
            case .vistaPrevia:
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Spacer()
                if let m = modelo.motivoNoPasar {
                    Text(m).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                }
                Button(TextosDelRelevo.titulo) { Task { await modelo.pasar() } }
                    .tlsBoton(.principal)
                    .disabled(!modelo.puedePasar)
                    .help(modelo.motivoNoPasar ?? "Guarda una copia de seguridad y pasa los cambios")
                    .accessibilityHint(modelo.motivoNoPasar ?? "")
                    .accessibilityIdentifier("relevo.pasar")
            case .hecho:
                Button("Deshacer") { Task { await modelo.deshacer() } }.tlsBoton(.secundario)
                    .accessibilityIdentifier("relevo.deshacer")
                Spacer()
                Button("Cerrar") { Task { await modelo.terminar(); dismiss() } }.tlsBoton(.secundario)
                if modelo.resultado?.correcto == true {
                    // F6 · integración: la real ya escribe; se abre en su ventana (antes se suelta el escritor del relevo).
                    Button("Abrir mi carpeta real") {
                        Task {
                            await modelo.terminar()
                            model?.reload()
                            dismiss()
                            openWindow.abrirEmpresa(modelo.entorno.realEntry.id)
                        }
                    }
                    // F6 · corrector (P1-3): sin Intro, para no cerrar sin querer la hoja donde está «Deshacer».
                    .tlsBoton(.principal)
                    .accessibilityIdentifier("relevo.abrirReal")
                }
            case .deshecho:
                Spacer()
                Button("Cerrar") { dismiss() }.tlsBoton(.principal).keyboardShortcut(.defaultAction)
            }
        }
        .padding(TLSEspacio.e16)
    }
}
