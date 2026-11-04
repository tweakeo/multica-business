import SwiftUI
import TLSCore
import TLSDesign

// Una tarjeta de decisión (M2-Hoy «Pide tu decisión» y la lista de Decisiones): grupo, área y desde cuándo; la pregunta;
// (F4: lo de los asistentes, con su grupo —Para aprobar, Preguntas, Propuestas de mejora— y quién lo trae);
// quién la plantea; el problema en una frase; como mucho 3 opciones con la recomendada (borde azul noche y su porqué);
// «Decidir» (se activa al elegir) y «Ver detalle» (evidencias, qué pasa si se pospone). Decidir escribe como la persona,
// por el dominio, con aviso y Deshacer.

/// Lo que hace un clic en Decisiones (siempre la persona; por el dominio cuando toca la carpeta).
@MainActor
enum Decidir {
    /// Por qué no se puede escribir ahora (`nil` = se puede).
    static func motivoSoloLectura(_ sesion: VaultSession) -> String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .abriendo: "aún se está abriendo"
        case .soloLectura(let m): m.texto
        }
    }

    /// Destino del detalle de una tarjeta.
    static func destino(_ t: TarjetaDecision) -> Destino {
        if t.tipo != .conflicto, let r = t.ruta { return .decision(de: r) }
        return .decision(t.id)
    }

    /// La foto fresca de la carpeta y su reloj.
    static func foto(_ sesion: VaultSession) async -> (VaultSnapshot, Reloj)? {
        let rel = AlmacenRelaciones.de(sesion)
        await rel.actualizar()
        guard let f = rel.foto else { return nil }
        return (f, Reloj.deCarpeta(f))
    }

    /// Tras escribir: rehace la foto y Hoy ya (sin esperar a que el índice avise), para que la bandeja y la insignia
    /// cambien en cuanto se decide.
    static func refrescar(_ sesion: VaultSession) async {
        guard sesion.service != nil else { return }
        AlmacenRelaciones.de(sesion).invalidar()
        await AlmacenHoy.de(sesion).actualizar()
    }

    /// Decide una propuesta o una pregunta: la línea en `Decisiones.md` y la tarea cerrada. `true` si se escribió.
    @discardableResult
    static func decidir(_ t: TarjetaDecision, opcion: OpcionDecision?, texto: String, porque: String?,
                        sesion: VaultSession) async -> Bool {
        guard let (foto, reloj) = await foto(sesion) else { return false }
        do {
            let (plan, _) = try AccionesDecision.planDecidir(t, decision: texto, porque: porque, opcion: opcion, foto: foto,
                                                             reloj: reloj, persona: sesion.persona)
            try await sesion.escribirConDominio(plan: plan, aviso: "Decidido: «\(AccionesDecision.corto(texto))». Queda en el registro de decisiones",
                                                deshacer: sesion.undoManagerActivo)
            await refrescar(sesion)
            return true
        } catch let e as ErrorDecision {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch let e as DecisionError {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch let e as TareaError {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch {
            // `escribirConDominio` ya dejó su aviso.
        }
        return false
    }

    @discardableResult
    static func responder(_ t: TarjetaDecision, texto: String, sesion: VaultSession) async -> Bool {
        guard let (foto, reloj) = await foto(sesion) else { return false }
        do {
            let plan = try AccionesDecision.planResponder(t, respuesta: texto, foto: foto, reloj: reloj, persona: sesion.persona)
            try await sesion.escribirConDominio(plan: plan, aviso: t.tipo == .pregunta ? "Respondida: «\(AccionesDecision.corto(t.titulo))»"
                                                    : "Respuesta apuntada en «\(AccionesDecision.corto(t.titulo))»",
                                                deshacer: sesion.undoManagerActivo)
            await refrescar(sesion)
            return true
        } catch let e as ErrorDecision {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch {}
        return false
    }

    @discardableResult
    static func descartar(_ t: TarjetaDecision, motivo: String?, sesion: VaultSession) async -> Bool {
        guard let (foto, reloj) = await foto(sesion) else { return false }
        do {
            let plan = try AccionesDecision.planDescartar(t, motivo: motivo, foto: foto, reloj: reloj, persona: sesion.persona)
            try await sesion.escribirConDominio(plan: plan, aviso: "Descartada: «\(AccionesDecision.corto(t.titulo))»",
                                                deshacer: sesion.undoManagerActivo)
            await refrescar(sesion)
            return true
        } catch let e as ErrorDecision {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch {}
        return false
    }

    /// Archivos en conflicto: las opciones de la bandeja con lo que ya sabe hacer «Revisar». Combinar o elegir otra
    /// versión necesita ver las dos: se hace en Revisar.
    static func resolver(_ t: TarjetaDecision, opcion: OpcionDecision, sesion: VaultSession, navegar: NavegarAccion) async {
        guard let id = t.conflicto, let rec = sesion.tarjetas.first(where: { $0.id == id }) else {
            sesion.aviso = Aviso("Ese conflicto ya no está pendiente.", estado: .bien)
            return
        }
        switch (rec.tipo, opcion.numero) {
        case (.duplicado, 1): await sesion.descartarDuplicado(rec)
        case (.duplicado, 2): await sesion.descartarDuplicado(rec, quedarmeConLaRepetida: true)
        case (.icloud, 1): await sesion.resolverICloud(rec, quedarmeCon: nil)
        case (.edicion, 2), (.recuperacion, 2): await sesion.resolver(rec, eleccion: .mia)
        case (.edicion, 3), (.recuperacion, 3): await sesion.resolver(rec, eleccion: .otra)
        default: navegar(.revisar, modo: .entrar)
        }
    }

    /// F5 · corrector (P1-1): un correo que preparó un asistente sin pedir la aprobación queda listo para aprobar aquí
    /// (la petición va en su nombre y con las mismas comprobaciones). Al aprobarlo se abre en Mail: lo envías tú.
    @discardableResult
    static func prepararCorreo(_ t: TarjetaDecision, sesion: VaultSession) async -> Bool {
        guard let r = t.ruta else { return false }
        let a = AsistentesDeLaEmpresa.de(sesion)
        guard let aprobaciones = a.aprobaciones else {
            sesion.aviso = Aviso("Para aprobar hace falta que la app pueda escribir en esta carpeta.", estado: .atencion)
            return false
        }
        do {
            _ = try await aprobaciones.pedirParaAprobar(borrador: r, autor: sesion.autor)
            await a.cambio()
            return true
        } catch {
            sesion.aviso = Aviso(error.localizedDescription, estado: .atencion)
            return false
        }
    }

    /// Lo que hace «Decidir» con la opción elegida, según el tipo de tarjeta.
    static func elegir(_ d: DetalleDecision, opcion: OpcionDecision, sesion: VaultSession, navegar: NavegarAccion) async -> Bool {
        let t = d.tarjeta
        // F4 · lo de los asistentes (DecisionesGobierno.swift).
        if let g = t.gobierno {
            switch g.clase {
            case .aprobacion:
                // Aprobar siempre pasa por la hoja que enseña qué sale, a quién y por cuánto.
                navegar(destino(t), modo: .automatico)
                return false
            case .cambioDePermisos:
                return opcion.numero == 1 && !(t.opciones.count == 1)
                    ? await confirmarPermisos(sesion: sesion) : await volverALosPermisosDeAntes(sesion: sesion)
            case .criterio:
                if opcion.numero == 1 { navegar(destino(t), modo: .automatico); return false }
                return await dejarComoEsta(t, sesion: sesion)
            case .propuesta, .mejora:
                if let id = g.propuesta { return await decidirPropuesta(t, propuesta: id, opcion: opcion, sesion: sesion) }
            case .pregunta:
                return await responderAlAsistente(t, texto: opcion.texto, sesion: sesion)
            }
        }
        switch t.tipo {
        case .conflicto:
            await resolver(t, opcion: opcion, sesion: sesion, navegar: navegar)
            return true
        case .paraAprobar:
            sesion.aviso = Aviso(d.motivoNoDecidir ?? "Esto aún no se aprueba aquí.", estado: .atencion)
            return false
        case .pregunta:
            return await responder(t, texto: opcion.texto, sesion: sesion)
        case .propuesta:
            return await decidir(t, opcion: opcion, texto: opcion.texto, porque: opcion.recomendada ? t.porque : nil, sesion: sesion)
        }
    }
}

/// La tarjeta de una decisión.
struct TarjetaDecisionVista: View {
    let detalle: DetalleDecision
    let sesion: VaultSession
    let hoy: LocalDate
    var compacta = false
    @State private var elegida: Int?
    @State private var abierta = false
    @State private var trabajando = false
    @Environment(\.navegar) private var navegar

    var t: TarjetaDecision { detalle.tarjeta }
    var opcionElegida: OpcionDecision? { elegida.flatMap { n in t.opciones.first { $0.numero == n } } }
    var puedeEscribir: Bool { sesion.puedeEscribir }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            arriba
            Button { navegar(Decidir.destino(t), modo: .automatico) } label: {
                Text(t.titulo)
                    .tlsTexto(TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 17, interlinea: 22))
                    .foregroundStyle(TLSPaleta.texto.color)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre la decisión")
            Text(detalle.quien).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            if let p = t.problema {
                Text(LinkParser.plainText(p)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(compacta ? 4 : nil).fixedSize(horizontal: false, vertical: true)
            }
            opciones
            Spacer(minLength: 0)
            botones
            if abierta { masDetalle }
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay {
            if t.prioridad == .roja { forma.strokeBorder(TLSPaleta.mal.color.opacity(0.5), lineWidth: 1) }
        }
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(t.grupoF4): \(t.titulo)")
        .accessibilityIdentifier("decision.\(t.id)")
    }

    private var arriba: some View {
        FlujoChips(espacio: 6) {
            if compacta {
                Text(t.grupoF4).tlsTexto(TLSTipo.secundario.peso(600)).foregroundStyle(TLSPaleta.texto.color)
                    .padding(.horizontal, 8).frame(minHeight: 22)
                    .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
            }
            if let a = t.area {
                HStack(spacing: 4) {
                    IconoArea(a.tlsArea, tamano: 16)
                    Text(a.etiquetaNumerada).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(minHeight: 22)
            }
            if let d = detalle.desde {
                Text("· \(d)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).frame(minHeight: 22)
            }
            if t.creada == hoy {
                InsigniaAviso(nil, palabra: "Nuevo").frame(minHeight: 22)
            }
            if t.prioridad == .roja, let m = t.motivo {
                PastillaEstado(.mal, palabra: m)
            }
            if t.gobierno?.cambio == true {
                PastillaEstado(.atencion, palabra: "Cambió desde que lo preparó el asistente")
            }
        }
    }

    @ViewBuilder private var opciones: some View {
        if !t.opciones.isEmpty {
            VStack(spacing: 6) {
                ForEach(t.opciones) { o in OpcionDecisionVista(opcion: o, porque: o.recomendada ? t.porque : nil, elegida: elegida == o.numero) {
                    elegida = elegida == o.numero ? nil : o.numero
                } }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Opciones")
        } else if !detalle.respuestas.isEmpty {
            // F4 · lo que propone el asistente en su pregunta: se responde con un clic.
            VStack(spacing: 6) {
                ForEach(detalle.respuestas) { r in
                    OpcionDecisionVista(datos: .init(numero: r.numero, texto: r.texto, recomendada: r.recomendada), porque: nil,
                                        elegida: elegida == r.numero) {
                        elegida = elegida == r.numero ? nil : r.numero
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Lo que propone")
        } else if let m = detalle.motivoNoDecidir {
            AvisoEnLinea(m, estado: .sinDato)
        } else if t.tipo == .propuesta || t.tipo == .pregunta {
            AvisoEnLinea(t.tipo == .pregunta ? "Contesta con tus palabras." : "Aún no tiene opciones escritas: decide con tus palabras.",
                         estado: .sinDato)
        }
    }

    /// La respuesta elegida de lo que propone un asistente en su pregunta.
    private var respuestaElegida: RespuestaPropuesta? { elegida.flatMap { n in detalle.respuestas.first { $0.numero == n } } }

    @ViewBuilder private var botones: some View {
        FlujoChips(espacio: 8) {
            if t.opciones.isEmpty, !detalle.respuestas.isEmpty {
                Button("Responder") {
                    guard let r = respuestaElegida else { return }
                    trabajando = true
                    Task {
                        _ = await Decidir.responderAlAsistente(t, texto: r.texto, sesion: sesion)
                        trabajando = false
                    }
                }
                .tlsBoton(.principal)
                .disabled(respuestaElegida == nil || trabajando || !puedeEscribir)
                .help(respuestaElegida == nil ? "Elige una respuesta" : "Responder: «\(respuestaElegida!.texto)»")
            } else if !t.opciones.isEmpty, detalle.motivoNoDecidir == nil {
                Button("Decidir") {
                    guard let o = opcionElegida else { return }
                    trabajando = true
                    Task {
                        _ = await Decidir.elegir(detalle, opcion: o, sesion: sesion, navegar: navegar)
                        trabajando = false
                    }
                }
                .tlsBoton(.principal)
                .disabled(opcionElegida == nil || trabajando || (!puedeEscribir && t.tipo != .conflicto))
                .help(opcionElegida == nil ? "Elige una opción para decidir" : "Decidir con la opción \(opcionElegida!.numero)")
            } else {
                Button(t.tipo == .paraAprobar ? (t.gobierno?.aprobacion != nil || detalle.correoParaPreparar ? "Revisar y aprobar…" : "Abrir el borrador")
                       : (t.tipo == .pregunta ? "Responder…" : "Decidir…")) {
                    if t.tipo == .paraAprobar, t.gobierno?.aprobacion == nil, !detalle.correoParaPreparar, let r = t.ruta {
                        navegar(sesion.destino(para: r), modo: .automatico)
                    } else {
                        navegar(Decidir.destino(t), modo: .automatico)
                    }
                }
                .tlsBoton(.principal)
                .accessibilityIdentifier("decision.tarjeta.principal")
            }
            Button(abierta ? "Ocultar detalle" : "Ver detalle") { abierta.toggle() }.tlsBoton(.secundario)
            if t.opciones.isEmpty, !detalle.respuestas.isEmpty, respuestaElegida == nil {
                Text("Elige una respuesta o ábrela para contestar con tus palabras").tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(minHeight: TLSAltura.objetivoMinimo)
            } else if !t.opciones.isEmpty, opcionElegida == nil, detalle.motivoNoDecidir == nil {
                Text("Elige una opción para decidir").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(minHeight: TLSAltura.objetivoMinimo)
            } else if !puedeEscribir, t.tipo != .conflicto {
                Text("Solo lectura: " + (Decidir.motivoSoloLectura(sesion) ?? "esta carpeta no se puede cambiar")).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(minHeight: TLSAltura.objetivoMinimo)
            }
        }
    }

    private var masDetalle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(TLSPaleta.separador.color)
            EvidenciasDecision(evidencias: detalle.evidencias, sesion: sesion)
            if let c = detalle.queCambia {
                (Text("Si se aprueba: ").bold() + Text(c)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            (Text("Si lo pospones: ").bold() + Text(detalle.siSePospone)).tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Una opción: su número, su texto y, si es la recomendada, borde azul noche, «Recomendada» y su porqué.
struct OpcionDecisionVista: View {
    /// Lo que se pinta de una opción (de una 1-3-1 o, F4, de lo que propone un asistente en su pregunta).
    struct Datos: Hashable {
        let numero: Int
        let texto: String
        let recomendada: Bool
        var aFavor: String? = nil
        var enContra: String? = nil
        var coste: String? = nil
    }

    let opcion: Datos
    let porque: String?
    let elegida: Bool
    var tecla: Bool = false
    let alPulsar: () -> Void

    init(opcion o: OpcionDecision, porque: String?, elegida: Bool, tecla: Bool = false, alPulsar: @escaping () -> Void) {
        self.init(datos: Datos(numero: o.numero, texto: o.texto, recomendada: o.recomendada, aFavor: o.aFavor, enContra: o.enContra,
                               coste: o.coste),
                  porque: porque, elegida: elegida, tecla: tecla, alPulsar: alPulsar)
    }

    init(datos: Datos, porque: String?, elegida: Bool, tecla: Bool = false, alPulsar: @escaping () -> Void) {
        self.opcion = datos; self.porque = porque; self.elegida = elegida; self.tecla = tecla; self.alPulsar = alPulsar
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        Button(action: alPulsar) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(opcion.numero)")
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(elegida ? TLSPaleta.principal.color : TLSPaleta.bandeja.color))
                VStack(alignment: .leading, spacing: 2) {
                    Text(opcion.texto).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if opcion.recomendada {
                        (Text("Recomendada").bold() + Text(porque.map { " · \($0)" } ?? ""))
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.principal.color)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    if let f = opcion.aFavor { Text("A favor: \(f)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
                    if let c = opcion.enContra { Text("En contra: \(c)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
                    if let r = opcion.coste { Text("Coste o riesgo: \(r)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
                }
                Spacer(minLength: 0)
                if tecla { Tecla("\(opcion.numero)") }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(forma.fill(elegida ? TLSPaleta.principalSuave.color : TLSPaleta.superficie.color))
            .overlay(forma.strokeBorder(elegida || opcion.recomendada ? TLSPaleta.principal.color : TLSPaleta.separador.color,
                                        lineWidth: elegida ? 2 : (opcion.recomendada ? 1.5 : 1)))
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Opción \(opcion.numero): \(opcion.texto)" + (opcion.recomendada ? ". Recomendada" + (porque.map { ": \($0)" } ?? "") : ""))
        .accessibilityAddTraits(elegida ? [.isSelected] : [])
    }
}

/// Evidencias enlazadas: chips que abren su ficha (con vista previa al pasar el puntero).
struct EvidenciasDecision: View {
    let evidencias: [EvidenciaDecision]
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rotulo("Evidencias")
            if evidencias.isEmpty {
                Text("La nota no enlaza ninguna ficha ni documento.").tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                FlujoChips(espacio: 6) {
                    ForEach(evidencias) { e in
                        Button { navegar(sesion.destino(para: e.ruta), modo: .automatico) } label: {
                            Chip(e.titulo, icono: sesion.resumen(de: e.ruta)?.kind.systemImage ?? "doc.text")
                        }
                        .buttonStyle(.plain)
                        .vistaPrevia(ruta: e.ruta, sesion: sesion)
                    }
                }
            }
        }
    }
}
