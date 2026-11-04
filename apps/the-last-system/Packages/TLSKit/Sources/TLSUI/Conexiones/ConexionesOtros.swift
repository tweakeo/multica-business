import SwiftUI
import TLSCore
import TLSDesign

// F5 · rol conexiones. «Otros programas»: añadir desde una plantilla (Web y formularios, GoHighLevel, Stripe, Calendly u
// otro), pegar la dirección y la clave (va al Llavero de tu Mac; aquí no se vuelve a ver), probar, los interruptores por
// asistente en llano, «Revisar herramientas nuevas» y lo que cambia cosas allí como «Siempre con tu OK». La matriz
// técnica (nombres, clase, huella), solo en Ajustes › Avanzado.

/// La tarjeta «Revisar herramientas nuevas».
struct TarjetaRevisionHerramientas: View {
    @Bindable var modelo: ModeloConexiones
    let revision: RevisionDeOtroPrograma

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(TLSPaleta.atencion.color).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revisar herramientas nuevas de \(revision.nombreConexion)").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Text(revision.titulo + ".").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // F5 · integración: la misma lista que la tarjeta de Decisiones (una sola pieza para revisar herramientas).
            ListaHerramientasPorRevisar(herramientas: revision.herramientas.map {
                HerramientaDeLaTarjeta(nombre: $0.nombre, descripcion: $0.descripcion, cambiaCosas: $0.sensible, motivo: $0.motivo,
                                       estado: "Desactivada hasta que la revises")
            })
            HStack(spacing: TLSEspacio.e8) {
                Button("Activarlas") { Task { await modelo.revisar(revision, aceptar: true) } }
                    .tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
                    .accessibilityIdentifier("conexiones.revision.activar")
                Button("Dejarlas desactivadas") { Task { await modelo.revisar(revision, aceptar: false) } }.tlsBoton(.secundario)
                    .accessibilityIdentifier("conexiones.revision.dejar")
            }
            Text(TextosRevisionHerramientas.nota(revision.nombreConexion))
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: TLSRadio.mosaico, bottomLeadingRadius: TLSRadio.mosaico)
                .fill(TLSPaleta.atencion.color).frame(width: 4).accessibilityHidden(true)
        }
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexiones.revision")
    }
}

/// Lo de «Otros programas»: los conectados, sus interruptores y el alta.
struct PanelOtrosProgramas: View {
    @Bindable var modelo: ModeloConexiones

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ForEach(modelo.programas) { p in ProgramaConectadoVista(modelo: modelo, programa: p) }
            if let alta = modelo.alta {
                AltaProgramaVista(modelo: modelo, borrador: alta)
            } else if modelo.abierta == .otros {
                PlantillasVista(modelo: modelo)
            }
        }
    }
}

/// Elegir con qué plantilla se empieza.
struct PlantillasVista: View {
    @Bindable var modelo: ModeloConexiones

    var body: some View {
        PanelConexion {
            Text("¿Qué programa quieres conectar?").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: TLSEspacio.e8, alignment: .top)],
                      alignment: .leading, spacing: TLSEspacio.e8) {
                ForEach(modelo.plantillas) { p in
                    Button { modelo.empezarAlta(p) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                            Text(p.explicacion).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(TLSEspacio.e12)
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous).fill(TLSPaleta.superficie.color))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.nombre). \(p.explicacion)")
                    .accessibilityIdentifier("conexiones.plantilla.\(p.id)")
                }
            }
        }
    }
}

/// El alta: nombre, dirección y clave (al Llavero), con lo que podrás permitir después.
struct AltaProgramaVista: View {
    @Bindable var modelo: ModeloConexiones
    let borrador: BorradorDeOtroPrograma

    var body: some View {
        let b = Binding(get: { modelo.alta ?? borrador }, set: { modelo.alta = $0 })
        PanelConexion {
            Text("Conectar \(borrador.plantilla.nombre)").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text(borrador.plantilla.explicacion).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            campo("Nombre") {
                TextField("Nombre", text: b.nombre, prompt: Text(borrador.plantilla.nombre)).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("conexiones.alta.nombre")
            }
            campo("Dirección") {
                TextField("Dirección", text: b.direccion, prompt: Text(borrador.plantilla.direccionDeEjemplo)).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("conexiones.alta.direccion")
            }
            // F5 · corrector (P2-8): de dónde sale la dirección, en llano y por plantilla.
            DisclosureGroup("¿Cómo consigo la dirección?") {
                Text(AyudaDePlantilla.comoConseguirla(borrador.plantilla))
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.top, 4)
            }
            .tlsTexto(TLSTipo.interfaz)
            .accessibilityIdentifier("conexiones.alta.ayuda")
            if let clave = borrador.plantilla.clave {
                campo(clave.etiqueta) {
                    SecureField(clave.etiqueta, text: b.clave, prompt: Text("Pégala aquí")).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("conexiones.alta.clave")
                }
                HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                    Image(systemName: "key").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                    Text(Self.textoLlavero).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !borrador.plantilla.permisos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Rotulo("Después decidirás, uno a uno")
                    ForEach(borrador.plantilla.permisos, id: \.self) { t in
                        Text("· " + t.replacingOccurrences(of: borrador.plantilla.nombre, with: b.wrappedValue.nombre.isEmpty
                                                           ? borrador.plantilla.nombre : b.wrappedValue.nombre))
                            .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    }
                    Text("Todo empieza apagado. Lo que cambie cosas allí pide siempre tu OK.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            if let e = modelo.errorAlta { AvisoEnLinea(e, estado: .atencion).accessibilityIdentifier("conexiones.alta.error") }
            HStack(spacing: TLSEspacio.e8) {
                Button("Añadir y probar") { Task { await modelo.anadirPrograma() } }
                    .tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
                    .disabled(modelo.trabajando)
                    .accessibilityIdentifier("conexiones.alta.anadir")
                Button("Cancelar") { modelo.cancelarAlta() }.tlsBoton(.secundario)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexiones.alta")
    }

    static let textoLlavero = "La clave se guarda en el Llavero de tu Mac, donde macOS guarda tus contraseñas. No se escribe en tu carpeta, no se vuelve a enseñar y ningún asistente la ve."

    private func campo(_ titulo: String, @ViewBuilder _ c: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Rotulo(titulo)
            c().frame(maxWidth: 420)
        }
    }
}

/// Un programa conectado: su estado, sus interruptores y sus botones.
struct ProgramaConectadoVista: View {
    @Bindable var modelo: ModeloConexiones
    let programa: OtroProgramaConexion

    var body: some View {
        PanelConexion {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Text(programa.nombre).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                PastillaConexion(estado: estado, palabra: palabra)
                if programa.simulado {
                    // F5 · integración: el del ejemplo es de mentira (nada sale de tu Mac).
                    PastillaAsistente(palabra: "Simulado", simbolo: "theatermasks", estado: .sinDato)
                        .help("Un programa de mentira para probar: nada sale de tu Mac.")
                        .accessibilityIdentifier("conexiones.programa.\(programa.id).simulado")
                }
                Spacer(minLength: 0)
            }
            Text(resumen).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            if case .error(let t) = programa.estado { AvisoEnLinea(t, estado: .mal) }
            if let m = modelo.mensajes[programa.id] {
                AvisoEnLinea(m, estado: m.hasPrefix("No ") ? .atencion : .bien)
                    .accessibilityIdentifier("conexiones.programa.\(programa.id).mensaje")
                if let t = modelo.tecnicos[programa.id] {
                    DisclosureGroup("Detalle técnico") {
                        Text(t).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .tlsTexto(TLSTipo.secundario)
                }
            }
            let ints = modelo.interruptores[programa.id] ?? []
            if !ints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Rotulo("Qué puede hacer cada asistente")
                    ForEach(ints) { i in interruptor(i) }
                }
            }
            HStack(spacing: TLSEspacio.e8) {
                Button("Probar") { Task { await modelo.probar(programa.id) } }.tlsBoton(.secundario)
                    .accessibilityIdentifier("conexiones.programa.\(programa.id).probar")
                Button("Sincronizar ahora") { Task { await modelo.sincronizar(programa.id) } }.tlsBoton(.secundario)
                    .disabled(programa.estado != .conectado)
                Button(programa.estado == .pausado ? "Reanudar" : "Pausar") {
                    Task { await modelo.pausar(programa.id, programa.estado != .pausado) }
                }
                .tlsBoton(.secundario)
                Button("Quitar") { Task { await modelo.quitar(programa.id) } }.tlsBoton(.enlace)
                    .help("Borra su clave del Llavero. Lo que ya está en tus fichas se queda.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexiones.programa.\(programa.id)")
    }

    private var estado: EstadoConexion {
        switch programa.estado {
        case .conectado: .conectado
        case .sinProbar, .pausado: .ahoraNo
        case .error(let t): .error(t)
        }
    }

    private var palabra: String {
        switch programa.estado {
        case .conectado: "Conectado"
        case .sinProbar: "Sin probar"
        case .pausado: "En pausa"
        case .error: "Con error"
        }
    }

    private var resumen: String {
        var partes = [programa.simulado ? "De mentira: no sale nada de tu Mac" : programa.local ? "Programa de este Mac" : "Por internet",
                      programa.activas == 1 ? "1 herramienta activa" : "\(programa.activas) herramientas activas"]
        if programa.porRevisar > 0 { partes.append("\(programa.porRevisar) por revisar") }
        if let u = programa.ultimaSincronizacion {
            partes.append("traído por última vez el " + u.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "es_ES"))))
        }
        return partes.joined(separator: " · ")
    }

    private func interruptor(_ i: InterruptorDeOtroPrograma) -> some View {
        HStack(alignment: .top, spacing: TLSEspacio.e8) {
            Toggle(isOn: Binding(get: { i.encendido },
                                 set: { v in Task { await modelo.cambiarInterruptor(programa.id, i, encender: v) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(i.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if !i.disponible {
                        Text("Aún no trae herramientas de este tipo.").tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    } else if !i.asistenteActivo {
                        Text("Ese asistente no está activo: no hará nada hasta que lo actives.").tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
            }
            .toggleStyle(.switch)
            .disabled(!i.disponible)
            .accessibilityIdentifier("conexiones.interruptor.\(programa.id).\(i.id)")
            Spacer(minLength: 0)
            if !i.lectura {
                PastillaAsistente(palabra: "Siempre con tu OK", simbolo: "hand.raised.fill", estado: .atencion)
                    .help("Lo que cambie cosas allí nunca se hace solo: llega a Decisiones y espera tu OK.")
            }
        }
    }
}

// MARK: Avanzado

/// La matriz técnica de los otros programas (solo Ajustes › Avanzado).
struct MatrizTecnicaVista: View {
    @Bindable var modelo: ModeloConexiones

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if modelo.programas.isEmpty {
                Text("Aún no hay otros programas conectados.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(modelo.programas) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    let filas = modelo.matrices[p.id] ?? []
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            ForEach(["Herramienta", "Clase", "Motivo", "Estado", "Huella", "Asistentes"], id: \.self) { t in
                                Text(t).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                            }
                        }
                        ForEach(filas) { f in
                            GridRow {
                                Text(f.expuesta).tlsTexto(TLSTipo.codigo).textSelection(.enabled)
                                Text(f.clase).tlsTexto(TLSTipo.secundario)
                                Text(f.motivo).tlsTexto(TLSTipo.secundario)
                                Text(f.estado).tlsTexto(TLSTipo.secundario)
                                Text(f.huellaCorta).tlsTexto(TLSTipo.codigo)
                                Text(f.asistentes.filter(\.value).keys.sorted().map(AsistenteConfigurado.nombre(de:)).joined(separator: ", ")
                                    .ifVacio("Ninguno"))
                                    .tlsTexto(TLSTipo.secundario)
                            }
                            .foregroundStyle(TLSPaleta.texto.color)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("conexiones.matriz.\(p.id)")
            }
        }
        .task(id: modelo.programas.map(\.id)) { await modelo.leerMatrices() }
    }
}

/// Un programa de este Mac (Avanzado): sin claves, en su caja y solo con el aviso aceptado.
struct AltaProgramaLocalVista: View {
    @Bindable var modelo: ModeloConexiones

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            AvisoEnLinea(Self.aviso, estado: .atencion)
            TextField("Nombre", text: $modelo.local.nombre, prompt: Text("Por ejemplo: Mi programa")).textFieldStyle(.roundedBorder)
            TextField("Programa", text: $modelo.local.ejecutable, prompt: Text("/ruta/completa/del/programa")).textFieldStyle(.roundedBorder)
            TextField("Opciones", text: $modelo.local.argumentos, prompt: Text("Opcional")).textFieldStyle(.roundedBorder)
            Toggle("He leído el aviso", isOn: $modelo.local.avisoAceptado)
                .accessibilityIdentifier("conexiones.local.aviso")
            Button("Añadir y probar") { Task { await modelo.anadirProgramaLocal() } }.tlsBoton(.secundario)
                .disabled(!modelo.local.avisoAceptado || !modelo.hayServicios)
        }
    }

    static let aviso = "Un programa de este Mac funciona dentro de una caja: no ve tu carpeta personal ni tus empresas, no recibe claves y solo escribe en su propio sitio. Añádelo solo si sabes de dónde viene."
}

fileprivate extension String {
    func ifVacio(_ otro: String) -> String { isEmpty ? otro : self }
}

/// F5 · corrector (P2-8): cómo se consigue la dirección (y la clave) de cada plantilla, sin jerga.
enum AyudaDePlantilla {
    static func comoConseguirla(_ p: PlantillaDeOtroPrograma) -> String {
        switch p.id {
        case "ghl":
            "En GoHighLevel, entra en Ajustes › Integraciones privadas y crea una nueva con los permisos de contactos y "
                + "oportunidades. Te dará una clave: pégala abajo. La dirección ya está escrita de ejemplo; si tu cuenta te "
                + "da otra, usa la suya."
        case "stripe":
            "En Stripe, entra en Desarrolladores › Claves y crea una clave restringida de solo lectura. Pégala abajo. La "
                + "dirección es la del ejemplo."
        case "calendly":
            "Calendly no da esta dirección directamente: te la da quien te monte la conexión (la persona que lleva tu web "
                + "o tus programas). Pídele «la dirección de conexión para asistentes» y la clave, y pégalas aquí."
        case "web":
            "Te la da quien hizo tu web o tus formularios: pídele «la dirección de conexión para asistentes» de los "
                + "formularios. Empieza por https:// y no lleva la clave dentro."
        default:
            "Te la da el propio programa (en sus ajustes, a veces en un apartado de integraciones o de asistentes) o quien "
                + "te lo instaló. Empieza por https://. Si además te dan una clave, pégala en su campo, nunca dentro de la "
                + "dirección. Si tienes dudas, no lo conectes: no pasa nada por dejarlo para otro día."
        }
    }
}
