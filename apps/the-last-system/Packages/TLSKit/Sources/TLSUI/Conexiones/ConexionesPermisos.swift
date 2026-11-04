import SwiftUI
import TLSCore
import TLSDesign

// F5 · rol conexiones. Los paneles de Mail y Calendario: la explicación va SIEMPRE antes del aviso de macOS (su botón
// «Continuar» es lo único que lo lanza) y, si se deniega, la pantalla de recuperación con «Abrir Ajustes del Sistema»
// (sin volver a preguntar). El detalle técnico, plegado.

/// Un panel dentro de una fila: fondo `bandeja`, radio de bloque.
struct PanelConexion<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) { contenido }
            .padding(TLSEspacio.e16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
    }
}

/// «Leyendo…» con su rueda.
struct Comprobando: View {
    let texto: String

    var body: some View {
        HStack(spacing: TLSEspacio.e8) {
            ProgressView().controlSize(.small)
            Text(texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
        }
    }
}

/// La explicación previa al aviso de macOS.
struct ExplicacionPermisoVista: View {
    let explicacion: ExplicacionDeConexion
    /// Una frase que va siempre (lo que lee o lo que crea).
    let promesa: String
    let identificador: String
    let continuar: () -> Void
    let ahoraNo: () -> Void

    var body: some View {
        PanelConexion {
            Text(explicacion.titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text(explicacion.para).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            AvisoEnLinea(promesa, estado: .bien)
            FilaOColumna(umbral: 620) {
                lista("Lo que hace", explicacion.hace, simbolo: "checkmark")
                lista("Lo que nunca hace", explicacion.nunca, simbolo: "nosign")
            }
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Image(systemName: "info.circle").foregroundStyle(TLSPaleta.enlace.color).accessibilityHidden(true)
                Text(explicacion.queVeras).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: TLSEspacio.e8) {
                Button(explicacion.boton, action: continuar).tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
                    .accessibilityIdentifier("conexiones.\(identificador).continuar")
                Button("Ahora no", action: ahoraNo).tlsBoton(.secundario)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexiones.\(identificador).explicacion")
    }

    private func lista(_ titulo: String, _ frases: [String], simbolo: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rotulo(titulo)
            ForEach(Array(frases.enumerated()), id: \.offset) { _, f in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: simbolo).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                    Text(f).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// La pantalla de recuperación de un permiso denegado.
struct RecuperacionPermisoVista: View {
    let recuperacion: RecuperacionDeConexion
    let identificador: String
    let abrir: () -> Void
    let volverAMirar: () -> Void
    @State private var tecnico = false

    var body: some View {
        PanelConexion {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Image(systemName: EstadoConexion.sinPermiso.simbolo).foregroundStyle(TLSPaleta.atencion.color).accessibilityHidden(true)
                Text(recuperacion.titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(recuperacion.texto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(recuperacion.pasos.enumerated()), id: \.offset) { i, p in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Text(p).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: TLSEspacio.e8) {
                Button(recuperacion.boton, action: abrir).tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
                    .accessibilityIdentifier("conexiones.\(identificador).abrirAjustes")
                Button("Ya lo he cambiado", action: volverAMirar).tlsBoton(.secundario)
                    .accessibilityIdentifier("conexiones.\(identificador).volverAMirar")
            }
            if let d = recuperacion.detalleTecnico {
                DisclosureGroup("Detalle técnico", isExpanded: $tecnico) {
                    Text(d).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color).textSelection(.enabled)
                }
                .tlsTexto(TLSTipo.secundario)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexiones.\(identificador).recuperacion")
    }
}

// MARK: Mail

struct PanelMail: View {
    @Bindable var modelo: ModeloConexiones

    var body: some View {
        switch modelo.faseMail {
        case .inicio, .conectado:
            EmptyView()
        case .comprobando:
            Comprobando(texto: "Mirando Mail…")
        case .explicacion(let e):
            ExplicacionPermisoVista(explicacion: e.explicacion, promesa: ModeloConexiones.queHaceMail, identificador: "mail",
                                    continuar: { Task { await modelo.continuarMail() } },
                                    ahoraNo: { Task { await modelo.ahoraNo(.mail) } })
        case .recuperacion(let r):
            RecuperacionPermisoVista(recuperacion: r, identificador: "mail", abrir: { modelo.abrirAjustes(r) },
                                     volverAMirar: { Task { await modelo.volverAMirar(.mail) } })
        case .mailCerrado:
            PanelConexion {
                AvisoEnLinea("Mail está cerrado. Ábrelo y pulsa «Volver a mirar»: la app no lo abre por ti.", estado: .atencion)
                Button("Volver a mirar") { Task { await modelo.volverAMirarMail() } }.tlsBoton(.secundario)
                    .accessibilityIdentifier("conexiones.mail.volverAMirar")
            }
        case .cuentas(let cuentas):
            CuentasMailVista(modelo: modelo, cuentas: cuentas)
        case .error(let t):
            PanelConexion {
                AvisoEnLinea(t, estado: .mal)
                Button("Volver a intentarlo") { Task { await modelo.volverAMirarMail() } }.tlsBoton(.secundario)
            }
        }
    }
}

/// Elegir la cuenta, los remitentes privados y el Cartero.
struct CuentasMailVista: View {
    @Bindable var modelo: ModeloConexiones
    let cuentas: [String]

    var body: some View {
        PanelConexion {
            AvisoEnLinea(ModeloConexiones.queHaceMail, estado: .bien)
            VStack(alignment: .leading, spacing: 6) {
                Rotulo("Cuenta que mira el Cartero")
                Picker("Cuenta", selection: Binding(get: { modelo.ajustesMail.cuenta ?? "" },
                                                    set: { modelo.ajustesMail.cuenta = $0 })) {
                    ForEach(cuentas, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityLabel("Cuenta de Mail")
                .accessibilityIdentifier("conexiones.mail.cuenta")
            }
            VStack(alignment: .leading, spacing: 6) {
                Rotulo("Remitentes y dominios privados")
                Text("De estos correos el Cartero solo sabe que llegó «correo privado de …» y cuándo: ni el remitente, ni el asunto, ni el texto.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(modelo.ajustesMail.privados) { p in
                    HStack(spacing: TLSEspacio.e8) {
                        Image(systemName: "lock").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                        Text(p.patron).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                        Text("→ correo privado de \(p.etiqueta)").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        Spacer(minLength: 0)
                        Button("Quitar") { modelo.quitarPrivado(p.patron) }.tlsBoton(.enlace)
                            .accessibilityLabel("Quitar \(p.patron)")
                    }
                }
                // F5 · corrector (P3-19): cada campo con su rótulo visible (no solo el texto de ayuda gris).
                HStack(alignment: .bottom, spacing: TLSEspacio.e8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dirección o dominio").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                        TextField("Dirección o dominio", text: $modelo.nuevoPrivado.patron, prompt: Text("nombre@dominio.es o dominio.es"))
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                            .accessibilityIdentifier("conexiones.mail.privado.patron")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cómo lo verá el Cartero").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                        TextField("Cómo lo verá el Cartero", text: $modelo.nuevoPrivado.etiqueta, prompt: Text("Por ejemplo: Expediente privado"))
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                            .accessibilityIdentifier("conexiones.mail.privado.etiqueta")
                    }
                    Button("Añadir") { modelo.anadirPrivado() }.tlsBoton(.secundario)
                        .accessibilityIdentifier("conexiones.mail.privado.anadir")
                }
                if let e = modelo.errorPrivado { AvisoEnLinea(e, estado: .atencion) }
            }
            Toggle(isOn: $modelo.activarCartero) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activar el Cartero").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text("Cada mañana de lunes a viernes ordena lo nuevo en tu Buzón y te prepara tareas y borradores de respuesta. Los envías tú desde Mail.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("conexiones.mail.cartero")
            HStack(spacing: TLSEspacio.e8) {
                Button("Conectar Mail") { Task { await modelo.terminarMail() } }
                    .tlsBoton(.principal, alto: TLSAltura.objetivoMinimo + 4)
                    .disabled(modelo.ajustesMail.cuenta == nil || modelo.trabajando)
                    .accessibilityIdentifier("conexiones.mail.terminar")
                Button("Ahora no") { Task { await modelo.ahoraNo(.mail) } }.tlsBoton(.secundario)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conexiones.mail.cuentas")
    }
}

// MARK: Calendario

struct PanelCalendario: View {
    @Bindable var modelo: ModeloConexiones

    var body: some View {
        switch modelo.faseCalendario {
        case .inicio, .conectado:
            EmptyView()
        case .comprobando:
            Comprobando(texto: "Preparando tu calendario…")
        case .explicacion(let e):
            ExplicacionPermisoVista(explicacion: e.explicacion, promesa: ModeloConexiones.queCreaCalendario, identificador: "calendario",
                                    continuar: { Task { await modelo.continuarCalendario() } },
                                    ahoraNo: { Task { await modelo.ahoraNo(.calendario) } })
        case .recuperacion(let r):
            RecuperacionPermisoVista(recuperacion: r, identificador: "calendario", abrir: { modelo.abrirAjustes(r) },
                                     volverAMirar: { Task { await modelo.volverAMirar(.calendario) } })
        case .error(let t):
            PanelConexion {
                AvisoEnLinea(t, estado: .mal)
                Button("Volver a intentarlo") { Task { await modelo.conectarCalendario() } }.tlsBoton(.secundario)
            }
        }
    }
}
