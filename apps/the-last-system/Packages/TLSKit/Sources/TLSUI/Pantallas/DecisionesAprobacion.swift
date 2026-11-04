import SwiftUI
import TLSCore
import TLSDesign

// F4 · rol mika. «Para aprobar» (PLAN §5.2 `ApprovalStore`, §6.3): lo que prepara un asistente y solo sale con tu
// aprobación concreta. Antes de aprobar, la hoja `SensitiveConfirmSheet` enseña **literalmente** qué sale, a quién
// y por cuánto (nunca una huella). Si alguien lo cambió desde que lo preparó el asistente (tú en Obsidian, el propio
// asistente), «Aprobar» queda desactivado con «Cambió desde que lo preparó el asistente» y queda «Aprobar con mis
// cambios», que aprueba lo que ves (o lo que corrijas) en un solo gesto. Al aprobar **ejecuta la app**, no el
// asistente, y vuelve a comprobar el contenido, el interruptor y que el asistente siga activo (`Aprobaciones`, TLSCore).
// Un correo queda «Listo para enviar»: lo envías tú.

/// El estado de una aprobación en pantalla.
@MainActor
@Observable
final class ModeloAprobacion {
    let id: String
    private(set) var detalle: DetalleDeAprobacion?
    private(set) var error: String?
    private(set) var trabajando = false
    private(set) var resultado: ResultadoDeAprobacion?
    /// «Aprobar con mis cambios»: los campos se pueden corregir.
    var editando = false
    var para = ""
    var asunto = ""
    var cuerpo = ""
    var importe = ""

    @ObservationIgnored private let aprobaciones: Aprobaciones?
    @ObservationIgnored private let persona: Autor
    @ObservationIgnored private let alCambiar: @MainActor () async -> Void

    init(id: String, aprobaciones: Aprobaciones?, persona: Autor, alCambiar: @escaping @MainActor () async -> Void = {}) {
        self.id = id
        self.aprobaciones = aprobaciones
        self.persona = persona
        self.alCambiar = alCambiar
    }

    /// Lee lo que se aprobaría (y si sigue valiendo). Una edición de otro la deja invalidada.
    func cargar() async {
        guard let aprobaciones else {
            error = "Para aprobar hace falta que la app pueda escribir en esta carpeta."
            return
        }
        do {
            let d = try await aprobaciones.detalle(id)
            detalle = d
            error = nil
            if !editando { rellenar(d) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rellenar(_ d: DetalleDeAprobacion) {
        para = d.aQuien.joined(separator: ", ")
        asunto = d.asunto ?? ""
        cuerpo = d.queSale
        importe = (d.borrador?.importe ?? d.aprobacion.carga.importe).map { Euros.escrito($0).replacingOccurrences(of: ".", with: ",") } ?? ""
    }

    /// ¿Se puede pulsar «Aprobar» tal cual? Si no, por qué.
    var motivoNoAprobar: String? {
        if trabajando { return "Un momento…" }
        if resultado != nil { return "Ya está aprobado" }
        guard let d = detalle else { return error ?? "Leyendo…" }
        if let m = d.motivoNoAprobar { return m }
        if d.aQuien.isEmpty, d.aprobacion.accion != .publicar, d.aprobacion.accion != .emitirFactura, d.aprobacion.accion != .pagar {
            return "Falta a quién: corrígelo con «Aprobar con mis cambios»"
        }
        return nil
    }

    var puedeAprobarConCambios: Bool { !trabajando && resultado == nil && (detalle?.puedeAprobarConCambios ?? false) }

    /// F5 · buzon-relevo: con Mail conectado, aprobar un correo abre su redacción en Mail (el clic de Enviar es tuyo).
    var abreMail: Bool {
        guard let a = detalle?.aprobacion.accion, a == .enviarCorreo || a == .escribirCliente, let aprobaciones else { return false }
        return HuecosDeAprobacion.abreMail(aprobaciones.ejecutor)
    }

    /// F5 · buzon-relevo: una acción en otro programa, legible (qué se manda, a quién y con qué datos).
    var peticionExterna: PeticionExternaLegible? {
        guard let d = detalle, d.aprobacion.accion == .externa else { return nil }
        return PeticionExternaLegible.leer(d.queSale)
    }

    /// Cambió desde que lo preparó el asistente: «Aprobar» no vale y lo principal es aprobar lo que se ve.
    /// F5 · corrector (P1-2, P2-9): el botón dice lo que pasa al pulsarlo.
    var textoAprobar: String {
        switch detalle?.aprobacion.accion {
        case .externa?: "Aprobar y mandar"
        case .enviarCorreo?, .escribirCliente?: abreMail ? "Aprobar y abrir en Mail" : "Aprobar"
        default: "Aprobar"
        }
    }

    var cambioDeFuera: Bool { detalle.map { if case .cambio = $0.vigencia { true } else { false } } ?? false }

    /// F4 · corrector (revisión de experiencia, P2): qué cambió desde que lo preparó el asistente, campo a campo
    /// («Asunto: «…» → «…»»), para no aprobar a ciegas.
    var queCambio: [String] {
        guard let d = detalle, cambioDeFuera, let b = d.borrador else { return [] }
        let antes = d.aprobacion.carga
        var out: [String] = []
        func corto(_ s: String) -> String { s.count > 60 ? String(s.prefix(57)) + "…" : s }
        if b.para != antes.destinatarios {
            out.append("A quién: \(antes.destinatarios.isEmpty ? "nadie" : antes.destinatarios.joined(separator: ", ")) → "
                       + (b.para.isEmpty ? "nadie" : b.para.joined(separator: ", ")))
        }
        if (b.asunto ?? "") != (antes.asunto ?? "") { out.append("Asunto: «\(corto(antes.asunto ?? ""))» → «\(corto(b.asunto ?? ""))»") }
        if b.importe != antes.importe {
            out.append("Por cuánto: \(antes.importe.map(Euros.texto) ?? "sin importe") → \(b.importe.map(Euros.texto) ?? "sin importe")")
        }
        if b.cuerpo.trimmingCharacters(in: .whitespacesAndNewlines) != (antes.cuerpo ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            out.append("Qué sale: el texto es otro")
        }
        if out.isEmpty { out.append("Los adjuntos o la ficha que se aprueba") }
        return out
    }

    /// «Aprobar» (⌘↩): solo si nada cambió.
    @discardableResult
    func aprobar() async -> Bool {
        guard motivoNoAprobar == nil, let aprobaciones else { return false }
        trabajando = true
        defer { trabajando = false }
        do {
            resultado = try await aprobaciones.aprobar(id, autor: persona)
            error = nil
            await alCambiar()
            return true
        } catch {
            self.error = error.localizedDescription
            await cargar()
            return false
        }
    }

    /// Lo que cambiaste respecto a lo que hay (solo eso se escribe).
    var cambios: CambiosDeAprobacion {
        guard let d = detalle else { return CambiosDeAprobacion() }
        var c = CambiosDeAprobacion()
        let nuevos = Self.destinatarios(para)
        if nuevos != d.aQuien { c.para = nuevos }
        if asunto.trimmingCharacters(in: .whitespacesAndNewlines) != (d.asunto ?? "") { c.asunto = asunto.trimmingCharacters(in: .whitespacesAndNewlines) }
        if cuerpo != d.queSale { c.cuerpo = cuerpo }
        let antes = d.borrador?.importe ?? d.aprobacion.carga.importe
        if let i = Self.centimos(importe), i != antes { c.importe = i }
        return c
    }

    /// «Aprobar con mis cambios»: escribe lo que corregiste (como tú) y aprueba lo que se ve, en un solo gesto.
    @discardableResult
    func aprobarConMisCambios() async -> Bool {
        guard puedeAprobarConCambios, let aprobaciones else { return false }
        if !importe.trimmingCharacters(in: .whitespaces).isEmpty, Self.centimos(importe) == nil {
            error = "El importe no es un número: escríbelo como 1.250,00"
            return false
        }
        trabajando = true
        defer { trabajando = false }
        do {
            // F4 · corrector (R8): se aprueba lo que enseñó esta hoja (más tus cambios) o nada.
            resultado = try await aprobaciones.aprobarConMisCambios(id, autor: persona, cambios: cambios, vista: detalle?.vista)
            error = nil
            editando = false
            await alCambiar()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// «Descartar»: no sale nada; el borrador queda «Descartado».
    @discardableResult
    func descartar(motivo: String?) async -> Bool {
        guard let aprobaciones else { return false }
        trabajando = true
        defer { trabajando = false }
        do {
            let m = motivo?.trimmingCharacters(in: .whitespacesAndNewlines)
            try await aprobaciones.rechazar(id, autor: persona, motivo: m?.isEmpty == false ? m : nil)
            await alCambiar()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    static func destinatarios(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// «1.250,00», «1250,5», «1250.50 €» → céntimos.
    static func centimos(_ s: String) -> Int? {
        var t = s.replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.contains(","), t.contains(".") { t = t.replacingOccurrences(of: ".", with: "") }
        return FormatosPlantilla.centimos(t)
    }
}

/// La hoja que enseña literalmente qué sale, a quién y por cuánto antes de aprobar (PLAN §6.3). Sin huellas.
struct SensitiveConfirmSheet: View {
    @Bindable var modelo: ModeloAprobacion
    /// Al terminar: lo que hay que abrir después (el borrador listo para enviar), si algo.
    var terminar: (VaultPath?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera
            Divider().overlay(TLSPaleta.separador.color)
            ScrollView {
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    if let r = modelo.resultado {
                        hecho(r)
                    } else if let d = modelo.detalle {
                        if let m = d.motivoNoAprobar, !modelo.editando {
                            // F4 · corrector (P2): una vez, y diciendo qué cambió.
                            AvisoEnLinea(modelo.cambioDeFuera
                                         ? "Alguien lo cambió después de que lo preparara el asistente. Lo que ves es lo que hay ahora; si te vale, apruébalo así. Cambió: "
                                            + modelo.queCambio.joined(separator: " · ") + "."
                                         : m + ".", estado: .atencion)
                                .accessibilityIdentifier("aprobacion.cambio")
                        }
                        if modelo.editando { edicion(d) } else { literal(d) }
                    } else if let e = modelo.error {
                        AvisoEnLinea(e, estado: .atencion)
                    } else {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Leyendo lo que sale…") }
                            .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    if modelo.resultado == nil, modelo.detalle != nil, let e = modelo.error {
                        AvisoEnLinea(e, estado: .mal)
                    }
                }
                .padding(TLSEspacio.e20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(TLSPaleta.separador.color)
            botones
        }
        .frame(width: 600, height: 620)
        .background(TLSPaleta.superficieElevada.color)
        .task { await modelo.cargar() }
        .accessibilityIdentifier("aprobacion.hoja")
    }

    private var cabecera: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TLSPaleta.principal.color)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TLSPaleta.principalSuave.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tituloDeLaHoja)
                    .tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitulo).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(TLSEspacio.e20)
    }

    /// F5 · corrector (P1-2, P2-9): el título dice qué pasa de verdad («Mandar un SMS desde GoHighLevel», «Correo para
    /// que lo envíes tú»).
    private var tituloDeLaHoja: String {
        guard let d = modelo.detalle else { return "Antes de aprobar" }
        if let p = modelo.peticionExterna { return p.titulo(programa: d.aQuien.first ?? p.conexion) }
        return d.accion
    }

    private var subtitulo: String {
        guard let d = modelo.detalle else { return "Esto es exactamente lo que sale." }
        let quien = AsistenteConfigurado.nombre(de: d.aprobacion.agente)
        // F5 · corrector (P3-13): una vez aprobado, la cabecera ya no habla en futuro.
        if modelo.resultado != nil { return "Lo preparó \(quien) y lo has aprobado." }
        switch d.aprobacion.accion {
        case .enviarCorreo, .escribirCliente:
            // F5 · buzon-relevo: con Mail conectado se abre su redacción; sin él, queda listo en el borrador.
            return modelo.abreMail
                ? "Lo prepara \(quien). Esto es exactamente lo que sale; al aprobar se abrirá en Mail para que tú lo envíes."
                : "Lo prepara \(quien). Esto es exactamente lo que sale; al aprobar queda listo y lo envías tú."
        case .externa:
            return "Lo prepara \(quien). Esto es literalmente lo que se manda y a quién; al aprobar lo hace la app, una sola vez."
        case .pagar:
            return "Lo prepara \(quien). La app nunca paga: al aprobar te deja las instrucciones para que pagues tú."
        case .emitirFactura:
            return "Lo prepara \(quien). Al aprobar, la app la emite con su número; no se manda a nadie."
        default:
            return "Lo prepara \(quien). Esto es exactamente lo que sale."
        }
    }

    // MARK: Lo que sale, tal cual

    @ViewBuilder
    private func literal(_ d: DetalleDeAprobacion) -> some View {
        // F5 · buzon-relevo: una acción en otro programa se enseña como datos legibles, no como el JSON del borrador.
        if let p = modelo.peticionExterna {
            PeticionExternaVista(peticion: p, programa: d.aQuien)
            AvisoEnLinea("Esto sale de verdad y no se puede deshacer desde aquí.", estado: .atencion)
                .accessibilityIdentifier("aprobacion.externa.sinVuelta")
        } else {
            literalComun(d)
        }
    }

    @ViewBuilder
    private func literalComun(_ d: DetalleDeAprobacion) -> some View {
        fila("A quién") {
            if d.aQuien.isEmpty {
                Text(d.aprobacion.accion == .publicar ? "Se publica" : "Nadie: falta a quién")
                    .tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
            } else {
                FlujoChips(espacio: 6) { ForEach(d.aQuien, id: \.self) { Chip($0, icono: "person.crop.circle") } }
            }
        }
        .accessibilityIdentifier("aprobacion.aQuien")
        if let a = d.asunto, !a.isEmpty {
            fila("Asunto") { Text(a).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).textSelection(.enabled) }
        }
        if let c = d.porCuanto {
            fila("Por cuánto") {
                Text(c).tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityIdentifier("aprobacion.importe")
            }
        }
        if let b = d.borrador, !b.adjuntos.isEmpty {
            fila("Adjuntos") { FlujoChips(espacio: 6) { ForEach(b.adjuntos, id: \.self) { Chip($0.name, icono: "paperclip") } } }
        }
        fila(d.aprobacion.accion == .pagar ? "Instrucciones" : "Qué sale") {
            Text(d.queSale.isEmpty ? "Sin texto." : d.queSale)
                .tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(TLSEspacio.e12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.superficie.color))
                .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).strokeBorder(TLSPaleta.separador.color))
                .accessibilityIdentifier("aprobacion.queSale")
        }
        Text("La nota «Para ti» del asistente no sale nunca.").tlsTexto(TLSTipo.secundario)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
        if modelo.abreMail {
            AvisoEnLinea("Se abrirá en Mail para que tú lo envíes: la app nunca pulsa Enviar.", estado: .sinDato)
                .accessibilityIdentifier("aprobacion.seAbriraEnMail")
        }
    }

    @ViewBuilder
    private func edicion(_ d: DetalleDeAprobacion) -> some View {
        AvisoEnLinea("Corrige lo que quieras: se guarda como tuyo en el borrador y se aprueba tal como lo dejes.", estado: .sinDato)
        if d.aprobacion.accion != .publicar && d.aprobacion.accion != .emitirFactura {
            campo("A quién (separa con comas)", $modelo.para)
        }
        if d.asunto != nil || d.aprobacion.accion == .enviarCorreo || d.aprobacion.accion == .escribirCliente {
            campo("Asunto", $modelo.asunto)
        }
        if d.porCuanto != nil { campo("Por cuánto (€)", $modelo.importe) }
        fila("Qué sale") {
            TextEditor(text: $modelo.cuerpo)
                .font(TLSTipo.lectura.font())
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 200)
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.superficie.color))
                .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).strokeBorder(TLSPaleta.bordeControl.color))
                .accessibilityLabel("Qué sale")
        }
    }

    private func campo(_ titulo: String, _ valor: Binding<String>) -> some View {
        fila(titulo) {
            TextField(titulo, text: valor).textFieldStyle(.roundedBorder).accessibilityLabel(titulo)
        }
    }

    private func fila<C: View>(_ titulo: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rotulo(titulo)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hecho(_ r: ResultadoDeAprobacion) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            AvisoEnLinea("Aprobado. " + r.texto, estado: .bien)
                .accessibilityIdentifier("aprobacion.hecho")
            switch r {
            case .listoParaEnviar:
                Text("Ábrelo y envíalo tú cuando quieras: la app no lo manda sola.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            case .instruccionesDePago:
                Text("La app nunca mueve dinero. Cuando llegue el extracto, lo concilias en Finanzas.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            case .abiertoEnMail:
                // F5 · buzon-relevo: la redacción está abierta en Mail con lo aprobado; Enviar lo pulsas tú.
                // F5 · corrector (P3-13): sin repetir lo del aviso de arriba.
                Text("Hasta que lo envíes, el borrador queda «Abierto en Mail».")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityIdentifier("aprobacion.abiertoEnMail")
            default:
                EmptyView()
            }
        }
    }

    // MARK: Botones

    private var botones: some View {
        HStack(spacing: 8) {
            if modelo.resultado != nil {
                Spacer()
                if let r = modelo.resultado?.abrir {
                    Button("Cerrar") { terminar(nil); dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                    Button("Abrirlo") { terminar(r); dismiss() }.tlsBoton(.principal).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cerrar") { terminar(nil); dismiss() }.tlsBoton(.principal).keyboardShortcut(.defaultAction)
                }
            } else {
                Button("Cancelar") { dismiss() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Spacer()
                if modelo.editando {
                    Button("Volver a lo que había") {
                        modelo.editando = false
                        Task { await modelo.cargar() }
                    }
                    .tlsBoton(.enlace)
                    Button("Aprobar con mis cambios") { Task { await modelo.aprobarConMisCambios() } }
                        .tlsBoton(.principal)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!modelo.puedeAprobarConCambios)
                        .accessibilityIdentifier("aprobacion.conCambios.confirmar")
                } else if modelo.cambioDeFuera {
                    // F4 · corrector (revisión de experiencia, P2): cambiado desde fuera, lo principal (⌘↩) es aprobar
                    // lo que se ve ahora; corregirlo sigue a mano.
                    Button("Corregir…") { modelo.editando = true }
                        .tlsBoton(.secundario)
                        .disabled(!modelo.puedeAprobarConCambios)
                        .help("Corrige lo que haga falta antes de aprobarlo")
                        .accessibilityIdentifier("aprobacion.conCambios")
                    Button("Aprobar como está ahora") { Task { await modelo.aprobarConMisCambios() } }
                        .tlsBoton(.principal)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!modelo.puedeAprobarConCambios)
                        .help("Aprueba lo que ves ahora (⌘↩)")
                        .accessibilityIdentifier("aprobacion.aprobarLoQueVes")
                } else {
                    Button("Corregir y aprobar…") { modelo.editando = true }
                        .tlsBoton(.secundario)
                        .disabled(!modelo.puedeAprobarConCambios)
                        .help("Corrige lo que haga falta y apruébalo en un solo paso")
                        .accessibilityIdentifier("aprobacion.conCambios")
                    let motivo = modelo.motivoNoAprobar
                    Button(modelo.textoAprobar) { Task { await modelo.aprobar() } }
                        .tlsBoton(.principal)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(motivo != nil)
                        .help(motivo ?? "Aprobar (⌘↩)")
                        .accessibilityHint(motivo ?? "")
                        .accessibilityIdentifier("aprobacion.aprobar")
                }
            }
        }
        .padding(TLSEspacio.e16)
    }
}

/// El detalle de una aprobación en Decisiones: qué sale (vista previa), por qué, y los botones de §6.3.
struct DetalleAprobacionVista: View {
    let detalle: DetalleDecision
    let sesion: VaultSession
    @State private var modelo: ModeloAprobacion?
    @State private var hoja = false
    @State private var descartando = false
    @State private var motivo = ""
    @State private var hecho: String?
    @Environment(\.navegar) private var navegar

    private var t: TarjetaDecision { detalle.tarjeta }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let hecho {
                AvisoEnLinea(hecho, estado: .bien)
            } else if let m = modelo {
                vistaPrevia(m)
                acciones(m)
            }
        }
        .task(id: t.gobierno?.aprobacion) { await preparar() }
        .sheet(isPresented: $hoja) {
            if let m = modelo {
                SensitiveConfirmSheet(modelo: m) { abrir in
                    if m.resultado != nil { hecho = "Aprobado. " + (m.resultado?.texto ?? "") }
                    if let abrir { navegar(sesion.destino(para: abrir), modo: .automatico) }
                }
            }
        }
    }

    private func preparar() async {
        guard let id = t.gobierno?.aprobacion else { return }
        let a = AsistentesDeLaEmpresa.de(sesion)
        let m = ModeloAprobacion(id: id, aprobaciones: a.aprobaciones, persona: sesion.autor) { await a.cambio() }
        modelo = m
        await m.cargar()
    }

    @ViewBuilder
    private func vistaPrevia(_ m: ModeloAprobacion) -> some View {
        if let d = m.detalle {
            VStack(alignment: .leading, spacing: 10) {
                Rotulo("Lo que sale")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.peticionExterna.map { $0.titulo(programa: d.aQuien.first ?? $0.conexion) } ?? d.accion)
                        .tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    if !d.aQuien.isEmpty, m.peticionExterna == nil {
                        Text("a " + d.aQuien.joined(separator: ", ")).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    }
                    if let c = d.porCuanto { Text("· " + c).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color) }
                }
                if let a = d.asunto { Text(a).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color) }
                if let p = m.peticionExterna {
                    // F5 · buzon-relevo: literalmente qué se manda y a quién.
                    PeticionExternaVista(peticion: p, programa: d.aQuien)
                } else {
                    Text(d.queSale).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                        .lineLimit(8).fixedSize(horizontal: false, vertical: true)
                        .padding(TLSEspacio.e12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.superficie.color))
                }
                if m.abreMail {
                    Text("Al aprobar se abrirá en Mail para que tú lo envíes.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if let motivo = d.motivoNoAprobar {
                    AvisoEnLinea(motivo, estado: .atencion).accessibilityIdentifier("decision.aprobacion.motivo")
                }
            }
        } else if let e = m.error {
            AvisoEnLinea(e, estado: .atencion)
        }
    }

    @ViewBuilder
    private func acciones(_ m: ModeloAprobacion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if descartando {
                TextField("Por qué lo descartas (opcional)", text: $motivo, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3).frame(maxWidth: 640)
            }
            FlujoChips(espacio: 8) {
                if descartando {
                    Button("Descartar el borrador") {
                        Task {
                            if await m.descartar(motivo: motivo) { hecho = "Descartado: no sale nada." }
                            descartando = false
                        }
                    }
                    .tlsBoton(.principal)
                    .keyboardShortcut(.return, modifiers: .command)
                    Button("Cancelar") { descartando = false }.tlsBoton(.secundario)
                } else {
                    let motivoNo = m.motivoNoAprobar
                    Button(m.textoAprobar + "…") { m.editando = false; hoja = true }
                        .tlsBoton(.principal)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(motivoNo != nil || !sesion.puedeEscribir)
                        .help(motivoNo ?? "Revisa qué sale, a quién y por cuánto, y apruébalo (⌘↩)")
                        .accessibilityIdentifier("decision.aprobar")
                    Button("Aprobar con mis cambios") { m.editando = true; hoja = true }
                        .tlsBoton(.secundario)
                        .disabled(!m.puedeAprobarConCambios || !sesion.puedeEscribir)
                        .accessibilityIdentifier("decision.aprobarConCambios")
                    MenuPosponer(tarjeta: t, sesion: sesion)
                    Button("Descartar") { descartando = true; motivo = "" }
                        .tlsBoton(.secundario)
                        .disabled(!sesion.puedeEscribir || m.resultado != nil)
                    if let r = t.ruta {
                        Button("Abrir el borrador") { navegar(sesion.destino(para: r), modo: .automatico) }.tlsBoton(.enlace)
                    }
                }
            }
            if let motivoNo = m.motivoNoAprobar, m.detalle != nil, !descartando {
                Text("«Aprobar» no está disponible: \(motivoNo.prefix(1).lowercased() + motivoNo.dropFirst()).")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }
}

/// «Posponer» de una decisión (hasta mañana, el lunes o una semana).
struct MenuPosponer: View {
    let tarjeta: TarjetaDecision
    let sesion: VaultSession

    var body: some View {
        let almacen = AlmacenHoy.de(sesion)
        Menu("Posponer") {
            let hoy = almacen.datos?.hoy ?? sesion.hoy
            Button("Hasta mañana") { almacen.posponer(decision: tarjeta, hasta: hoy.adding(days: 1)) }
            Button("Hasta el lunes") {
                var l = hoy.adding(days: 1)
                while l.weekday != 1 { l = l.adding(days: 1) }
                almacen.posponer(decision: tarjeta, hasta: l)
            }
            Button("Una semana") { almacen.posponer(decision: tarjeta, hasta: hoy.adding(days: 7)) }
        }
        .menuStyle(.button)
        .fixedSize()
        .tlsBoton(.secundario)
    }
}
