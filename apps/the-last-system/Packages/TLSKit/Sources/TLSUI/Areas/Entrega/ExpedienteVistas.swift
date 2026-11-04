import SwiftUI
import TLSCore
import TLSDesign
import TLSVisores

/// La lista de expedientes de Entrega: cada proyecto de cliente con su avance, su próxima sesión, sus incidencias
/// abiertas y si está en riesgo (con palabra, nunca solo color).
struct ListaExpedientes: View {
    let datos: DatosEntrega
    let alElegir: (ExpedienteEntrega) -> Void

    var body: some View {
        if datos.expedientes.isEmpty {
            Text("Aún no hay expedientes. Un expediente nace de una oportunidad Aceptada o Ganada y vive en 3 · Entrega/Proyectos.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(datos.expedientes.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                    fila(e)
                }
            }
            .accessibilityIdentifier("entrega.expedientes")
        }
    }

    private func fila(_ e: ExpedienteEntrega) -> some View {
        let hoy = datos.hoy
        let riesgo = e.riesgo(hoy: hoy, ahora: datos.ahora, zona: datos.zona)
        let proxima = e.portal?.proxima(hoy: hoy)
        let detalle = [e.empresa, e.fase.map { "fase \($0)" }, e.textoSesiones,
                       proxima.map { s in "próxima: \(s.codigo)" + (s.fecha.map { " el \(FormatoFicha.fechaConDia($0, hoy: hoy))" } ?? " sin fecha") }]
            .compactMap { $0 }.joined(separator: " · ")
        let abiertas = e.incidenciasAbiertas
        return Button { alElegir(e) } label: {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                IconoArea(.entrega, tamano: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                }
                Spacer(minLength: TLSEspacio.e8)
                if !abiertas.isEmpty {
                    let peor = abiertas.compactMap { $0.cuentaAtras(ahora: datos.ahora, zona: datos.zona) }.min { $0.minutosRestantes < $1.minutosRestantes }
                    PastillaEstado(peor.map { $0.fueraDePlazo ? .mal : ($0.apurada ? .atencion : .bien) } ?? .sinDato,
                                   palabra: abiertas.count == 1 ? "1 incidencia" : "\(abiertas.count) incidencias")
                }
                if let riesgo { PastillaEstado(.atencion, palabra: "En riesgo").help(riesgo) }
                PastillaEstado(e.estado == .enCurso ? .bien : .sinDato, palabra: e.estado?.rawValue ?? "Sin estado")
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
            }
            .padding(.vertical, TLSEspacio.e8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([e.nombre, detalle, e.estado?.rawValue, riesgo.map { "En riesgo: \($0)" },
                             abiertas.isEmpty ? nil : "\(abiertas.count) incidencias abiertas"].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Abre el expediente")
        .accessibilityIdentifier("expediente.\(e.ruta.raw)")
    }
}

/// Un expediente abierto dentro de Operación: Viaje S1–S9 · Tareas · Portal (interno o del cliente) · Incidencias
/// con cuenta atrás · Materiales.
struct ExpedienteDetalle: View {
    let expediente: ExpedienteEntrega
    let datos: DatosEntrega
    let sesion: VaultSession
    let motivoSoloLectura: String?
    let alVolver: () -> Void

    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager
    @State private var error: String?
    @State private var nuevaIncidencia = false
    @State private var nuevaTarea = false

    static let pestanas = ["Viaje", "Tareas", "Portal", "Incidencias", "Materiales"]
    static let clavePestana = "entrega.pestana"
    static let claveVista = "entrega.portal"

    var body: some View {
        let e = expediente
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Button(action: alVolver) { Label("Todos los expedientes", systemImage: "chevron.left") }
                .tlsBoton(.enlace)
                .accessibilityIdentifier("expediente.volver")
            cabecera(e)
            if let error { AvisoEnLinea(error, estado: .mal) }
            PestanasCapsula(seleccion: Binding(get: { pestana }, set: { p in
                nav?.actualizarRecuerdo(de: .area(.entrega)) { $0.extra[Self.clavePestana] = p }
            }), pestanas: pestanasCapsula(e), atajosControl: false)
            .accessibilityIdentifier("expediente.pestanas")
            switch pestana {
            case "Tareas": tareas(e)
            case "Portal": portal(e)
            case "Incidencias": incidencias(e)
            case "Materiales": materiales(e)
            default: viaje(e)
            }
        }
        .sheet(isPresented: $nuevaIncidencia) {
            NuevaIncidenciaHoja(expediente: e, motivoSoloLectura: motivoSoloLectura) { quien, email, tipo, severidad, descripcion in
                await AccionesEntrega.nuevaIncidencia(e, quien: quien, email: email, tipo: tipo, severidad: severidad,
                                                      descripcion: descripcion, ahora: DatosEntrega.ahora(hoy: sesion.hoy, reloj: Date(), zona: datos.zona),
                                                      zona: datos.zona, sesion: sesion, deshacer: undoManager)
            }
        }
        .sheet(isPresented: $nuevaTarea) { NuevaTareaHoja(contexto: .ficha(e.ruta), sesion: sesion) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("expediente.detalle")
    }

    private var pestana: String {
        let r = nav?.recuerdo(de: .area(.entrega)).extra[Self.clavePestana]
        return r.flatMap { Self.pestanas.contains($0) ? $0 : nil } ?? "Viaje"
    }

    private func pestanasCapsula(_ e: ExpedienteEntrega) -> [PestanaCapsula] {
        let fuera = e.incidencias?.fueraDePlazo(ahora: datos.ahora, zona: datos.zona).count ?? 0
        return [
            PestanaCapsula(id: "Viaje", titulo: "Viaje", contador: e.portal?.sesiones.isEmpty == false ? e.portal?.sesiones.count : nil),
            PestanaCapsula(id: "Tareas", titulo: "Tareas", contador: e.tareas.isEmpty ? nil : e.tareas.count),
            PestanaCapsula(id: "Portal", titulo: "Portal"),
            PestanaCapsula(id: "Incidencias", titulo: "Incidencias", contador: e.incidenciasAbiertas.isEmpty ? nil : e.incidenciasAbiertas.count,
                           urgente: fuera > 0 ? .mal : nil),
            PestanaCapsula(id: "Materiales", titulo: "Materiales", contador: e.materiales.isEmpty ? nil : e.materiales.count),
        ]
    }

    private func cabecera(_ e: ExpedienteEntrega) -> some View {
        let hoy = datos.hoy
        let datosClave = [e.empresa, e.contacto, e.fase.map { "Fase \($0)" }, e.textoSesiones,
                          e.fin.map { "fin \(FormatoFicha.fechaConDia($0, hoy: hoy))" }, e.responsable.map { "lo lleva \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: TLSEspacio.e8) {
                    Text(e.nombre).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    PastillaEstado(e.estado == .enCurso ? .bien : .sinDato, palabra: e.estado?.rawValue ?? "Sin estado")
                    if let r = e.riesgo(hoy: hoy, ahora: datos.ahora, zona: datos.zona) { PastillaEstado(.atencion, palabra: r) }
                }
                Text(datosClave).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TLSEspacio.e8)
            Button("Nueva incidencia") { nuevaIncidencia = true }
                .tlsBoton(.secundario)
                .disabled(motivoSoloLectura != nil)
                .help(motivoSoloLectura ?? "Apunta una incidencia con su plazo de 24, 48 o 72 h hábiles")
                .accessibilityIdentifier("expediente.nuevaIncidencia")
            Button("Abrir la ficha") { navegar(.ficha(e.ruta), modo: .automatico) }
                .tlsBoton(.secundario)
        }
    }

    // MARK: Viaje

    @ViewBuilder
    private func viaje(_ e: ExpedienteEntrega) -> some View {
        BloqueOperacion("Viaje", detalle: "Las sesiones del cliente, de S1 a S9. Cambiar un estado escribe solo esa celda de Portal.md.") {
            if let p = e.portal, !p.sesiones.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(p.sesiones.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                        filaSesion(s, portal: p)
                    }
                }
                .accessibilityIdentifier("expediente.viaje")
            } else {
                Text(e.portal == nil
                     ? "Este expediente aún no tiene portal. Su Viaje (S1–S9) va en Portal.md, en la carpeta del proyecto."
                     : "El Viaje de Portal.md está vacío: una fila por sesión del plan.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }

    private func filaSesion(_ s: SesionViaje, portal p: PortalDocumento) -> some View {
        let hoy = datos.hoy
        return HStack(alignment: .top, spacing: TLSEspacio.e12) {
            Text(s.codigo).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color).frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.nombre ?? "Sesión \(s.numero.map(String.init) ?? s.codigo)").tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                if let r = s.resumen {
                    Text(r).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
                }
                if let n = s.notaInterna {
                    Label("Nota interna: \(n)", systemImage: "lock").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: TLSEspacio.e8)
            Text(s.fecha.map { FormatoFicha.fechaConDia($0, hoy: hoy) } ?? (s.fechaTexto ?? "Sin fecha"))
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            PastillaEstado(Self.estado(s.estado), palabra: s.estado?.rawValue ?? s.estadoTexto ?? "Sin estado")
            Menu {
                ForEach(EstadoSesion.allCases, id: \.self) { nuevo in
                    Button(nuevo.rawValue) { cambiar(s, a: nuevo, portal: p) }.disabled(nuevo == s.estado)
                }
            } label: {
                Text("Cambiar").tlsTexto(TLSTipo.secundario).underline()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(TLSPaleta.enlace.color)
            .fixedSize()
            .disabled(motivoSoloLectura != nil)
            .help(motivoSoloLectura ?? "Cambiar el estado de \(s.codigo)")
            .accessibilityLabel("Cambiar el estado de \(s.codigo)")
        }
        .padding(.vertical, TLSEspacio.e8)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if motivoSoloLectura == nil {
                ForEach(EstadoSesion.allCases.filter { $0 != s.estado }, id: \.self) { nuevo in
                    Button("Pasar a \(nuevo.rawValue)") { cambiar(s, a: nuevo, portal: p) }
                }
            }
        }
        .accessibilityIdentifier("viaje.\(s.codigo)")
    }

    static func estado(_ e: EstadoSesion?) -> TLSEstado {
        switch e {
        case .hecha: .bien
        case .kitListo, .programada: .bien
        case .pendiente: .atencion
        case .noIncluida, nil: .sinDato
        }
    }

    private func cambiar(_ s: SesionViaje, a nuevo: EstadoSesion, portal p: PortalDocumento) {
        error = nil
        Task { error = await AccionesEntrega.cambiarSesion(s, a: nuevo, en: p, sesion: sesion, deshacer: undoManager) }
    }

    // MARK: Tareas

    private func tareas(_ e: ExpedienteEntrega) -> some View {
        BloqueOperacion("Tareas", detalle: "Las tareas de la carpeta Tareas del proyecto.", acciones: {
            Button("Nueva tarea") { nuevaTarea = true }.tlsBoton(.secundario).disabled(motivoSoloLectura != nil)
        }) {
            if e.tareas.isEmpty {
                Text("Este expediente aún no tiene tareas.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                VStack(spacing: 2) {
                    ForEach(e.tareas) { t in
                        let detalle = [t.numero, t.responsable.map { OperacionComun.nombre($0) ?? $0 },
                                       t.vence.map { "vence \(FormatoFicha.fechaConDia($0, hoy: datos.hoy))" }].compactMap { $0 }.joined(separator: " · ")
                        FilaLista(t.titulo, detalle: detalle, icono: t.estado?.cerrada == true ? "checkmark.circle" : "circle",
                                  accion: { navegar(sesion.destino(para: t.ruta), modo: .automatico) }) {
                            let vencida = !(t.estado?.cerrada ?? false) && (t.vence.map { $0 < datos.hoy } ?? false)
                            PastillaEstado(vencida ? .mal : (t.estado?.cerrada == true ? .bien : .sinDato),
                                           palabra: vencida ? "Vencida" : (t.estado?.rawValue ?? "Sin estado"))
                        }
                    }
                }
            }
        }
    }

    // MARK: Portal

    private var vistaCliente: Bool { nav?.recuerdo(de: .area(.entrega)).extra[Self.claveVista] == "cliente" }

    @ViewBuilder
    private func portal(_ e: ExpedienteEntrega) -> some View {
        Picker("Vista", selection: Binding(get: { vistaCliente ? "cliente" : "interna" }, set: { v in
            nav?.actualizarRecuerdo(de: .area(.entrega)) { $0.extra[Self.claveVista] = v == "cliente" ? "cliente" : nil }
        })) {
            Text("Vista interna").tag("interna")
            Text("Vista del cliente").tag("cliente")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
        .accessibilityIdentifier("portal.vista")
        if let p = e.portal {
            if vistaCliente {
                PortalClienteVista(cliente: PortalCliente(portal: p, incidencias: e.incidencias?.filas ?? []), hoy: datos.hoy)
            } else {
                PortalInternoVista(portal: p, incidencias: e.incidencias?.filas ?? [], hoy: datos.hoy)
            }
        } else {
            Text("Este expediente aún no tiene Portal.md.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        }
    }

    // MARK: Incidencias

    private func incidencias(_ e: ExpedienteEntrega) -> some View {
        BloqueOperacion("Incidencias", detalle: "Plazo de respuesta en horas hábiles (de lunes a viernes): grave 24 h, media 48 h, leve 72 h.",
                        acciones: {
            Button("Nueva incidencia") { nuevaIncidencia = true }.tlsBoton(.secundario).disabled(motivoSoloLectura != nil)
        }) {
            let filas = e.incidencias?.filas ?? []
            if filas.isEmpty {
                Text("Sin incidencias. Si el cliente escribe con una duda, un bloqueo o un problema, entra aquí con su plazo.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filas.enumerated()), id: \.element.id) { i, inc in
                        if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                        FilaIncidencia(incidencia: inc, ahora: datos.ahora, zona: datos.zona, interna: true)
                    }
                }
                .accessibilityIdentifier("expediente.incidencias")
            }
        }
    }

    // MARK: Materiales

    private func materiales(_ e: ExpedienteEntrega) -> some View {
        BloqueOperacion("Materiales", detalle: "Lo que hay en la carpeta Materiales del proyecto.", acciones: {
            Button("Mostrar en Finder") { sesion.revealInFinder(e.carpeta.appending("Materiales")) }.tlsBoton(.secundario)
        }) {
            if e.materiales.isEmpty {
                Text("Aún no hay materiales.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                VStack(spacing: 2) {
                    ForEach(e.materiales, id: \.self) { m in
                        FilaLista(m.name, detalle: m.parent?.name == "Materiales" ? nil : m.parent?.name,
                                  icono: TipoFichero.de(extension: m.ext).simbolo,
                                  accion: { navegar(sesion.destino(para: m), modo: .automatico) }) { EmptyView() }
                    }
                }
            }
        }
    }
}

/// Una incidencia con su cuenta atrás. En la vista interna lleva quién la reporta con su correo, el responsable y la
/// resolución; la del cliente no (la pinta `PortalClienteVista`, sin esos campos).
struct FilaIncidencia: View {
    let incidencia: IncidenciaRegistrada
    let ahora: Date
    let zona: TimeZone
    let interna: Bool

    var body: some View {
        let i = incidencia
        let c = i.cuentaAtras(ahora: ahora, zona: zona)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Text(i.id).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                Text(i.descripcion ?? "Sin descripción").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: TLSEspacio.e8)
                PastillaEstado(i.severidad == .grave ? .mal : (i.severidad == .media ? .atencion : .sinDato),
                               palabra: i.severidad?.rawValue ?? i.severidadTexto ?? "Sin gravedad")
                PastillaEstado(i.abierta ? .atencion : .bien, palabra: i.estado?.rawValue ?? i.estadoTexto ?? "Sin estado")
            }
            Text([i.tipo, i.fechaTexto.map { "llegó \($0)" }].compactMap { $0 }.joined(separator: " · "))
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            if let c {
                HStack(spacing: TLSEspacio.e8) {
                    PastillaEstado(c.fueraDePlazo ? .mal : (c.apurada ? .atencion : .bien), palabra: c.texto)
                        .accessibilityIdentifier("incidencia.cuentaAtras.\(i.id)")
                    Text("responder antes del \(c.textoPlazo) · \(c.total) h hábiles").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            } else if i.abierta {
                Text("Sin plazo: falta la fecha o la gravedad.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if interna {
                let quien = [i.quien, i.email].compactMap { $0 }.joined(separator: " · ")
                if !quien.isEmpty {
                    Text("Reporta: \(quien)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if let r = i.responsable {
                    Text("Responsable: \(r)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if let r = i.resolucion {
                    Text("Resolución: \(r)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, TLSEspacio.e8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("incidencia.\(i.id)")
    }
}

/// El portal en vista interna: todo, también las notas internas y las incidencias con sus datos internos.
struct PortalInternoVista: View {
    let portal: PortalDocumento
    let incidencias: [IncidenciaRegistrada]
    let hoy: LocalDate

    var body: some View {
        BloqueOperacion("Portal · vista interna", detalle: "Lo que ves tú. El cliente no ve las notas internas, el responsable, la resolución, los correos ni el kit.") {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                ForEach(portal.sesiones) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(s.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                            PastillaEstado(ExpedienteDetalle.estado(s.estado), palabra: s.estado?.rawValue ?? s.estadoTexto ?? "Sin estado")
                            if let f = s.fecha { Text(FormatoFicha.fechaConDia(f, hoy: hoy)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
                        }
                        if let r = s.resumen { Text(r).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color) }
                        if let n = s.notaInterna {
                            Label("Nota interna: \(n)", systemImage: "lock").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                    }
                }
                ListaPortal(titulo: "Lo que necesitamos del cliente", lineas: portal.tareasCliente.map { ($0.hecha ? "Hecho: " : "") + $0.texto })
                ListaPortal(titulo: "Documentos", lineas: portal.documentos)
                ListaPortal(titulo: "Dudas y problemas", lineas: portal.dudas)
            }
        }
        .accessibilityIdentifier("portal.interna")
    }
}

/// El portal como lo ve el cliente (criterio F2-8): su viaje, lo que necesitamos de él, sus documentos y sus dudas o
/// incidencias. Solo pinta `PortalCliente`, que no tiene notas internas, responsable, resolución, correos ni kit.
struct PortalClienteVista: View {
    let cliente: PortalCliente
    let hoy: LocalDate

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            AvisoEnLinea("Así lo ve el cliente: sin notas internas, responsable, resolución, correos ni kit.", estado: .sinDato)
            BloqueOperacion(cliente.titulo ?? "Tu portal", detalle: "Tu viaje, sesión a sesión.") {
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    ForEach(cliente.sesiones) { s in
                        HStack(alignment: .top, spacing: TLSEspacio.e12) {
                            Text(s.codigo).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color).frame(width: 34, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.nombre ?? "Sesión").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                                if let r = s.resumen { Text(r).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color) }
                            }
                            Spacer(minLength: TLSEspacio.e8)
                            if let f = s.fecha { Text(FormatoFicha.fechaConDia(f, hoy: hoy)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
                            PastillaEstado(ExpedienteDetalle.estado(s.estado), palabra: s.estado?.rawValue ?? "Sin estado")
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ListaPortal(titulo: "Lo que necesitamos de ti", lineas: cliente.tareas.map { t in
                        (t.hecha ? "Hecho: " : "") + t.texto + (t.vence.map { " · antes del \(FormatoFicha.fechaConDia($0, hoy: hoy))" } ?? "")
                    })
                    ListaPortal(titulo: "Documentos", lineas: cliente.documentos)
                    ListaPortal(titulo: "Tus dudas y problemas", lineas: cliente.dudas + cliente.incidencias.map { i in
                        [i.id, i.descripcion, i.severidad, i.estado].compactMap { $0 }.joined(separator: " · ")
                    })
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portal.cliente")
    }
}

/// Una lista sencilla con su rótulo (si está vacía, no se pinta).
struct ListaPortal: View {
    let titulo: String
    let lineas: [String]

    var body: some View {
        if !lineas.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(lineas.enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                        // Los enlaces, con su texto visible («Guía para enviar facturas»), no con la ruta.
                        Text(LinkParser.plainText(l)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

/// «Nueva incidencia»: quién la reporta, el tipo, la gravedad (con su plazo) y qué pasa. Se apunta con la fecha y la
/// hora de ahora; la responde la persona.
struct NuevaIncidenciaHoja: View {
    let expediente: ExpedienteEntrega
    let motivoSoloLectura: String?
    let guardar: (String, String, String, SeveridadIncidencia, String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var quien: String
    @State private var email = ""
    @State private var tipo = "Técnica"
    @State private var severidad: SeveridadIncidencia = .media
    @State private var descripcion = ""
    @State private var error: String?
    @State private var guardando = false

    static let tipos = ["Técnica", "Accesos", "Automatización", "Negocio", "Otro"]

    init(expediente: ExpedienteEntrega, motivoSoloLectura: String?,
         guardar: @escaping (String, String, String, SeveridadIncidencia, String) async -> String?) {
        self.expediente = expediente; self.motivoSoloLectura = motivoSoloLectura; self.guardar = guardar
        _quien = State(initialValue: expediente.contacto ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text("Nueva incidencia").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
            Text(expediente.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            TextField("Qué pasa, con las palabras del cliente", text: $descripcion, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4).accessibilityLabel("Qué pasa")
            HStack {
                TextField("Quién la reporta", text: $quien).textFieldStyle(.roundedBorder).accessibilityLabel("Quién la reporta")
                TextField("Su correo (solo lo ves tú)", text: $email).textFieldStyle(.roundedBorder).accessibilityLabel("Correo de quien la reporta")
            }
            HStack(spacing: TLSEspacio.e16) {
                Picker("Tipo", selection: $tipo) { ForEach(Self.tipos, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 220)
                Picker("Gravedad", selection: $severidad) {
                    ForEach(SeveridadIncidencia.allCases, id: \.self) { s in Text("\(s.rawValue) · \(s.horasHabiles) h").tag(s) }
                }
                .frame(maxWidth: 220)
            }
            Text("Plazo: \(severidad.horasHabiles) h hábiles desde ahora (de lunes a viernes). La respondes tú.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            if let error { AvisoEnLinea(error, estado: .mal) }
            if let m = motivoSoloLectura { AvisoEnLinea("No se puede apuntar: \(m).", estado: .sinDato) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction).tlsBoton(.secundario)
                Button("Apuntar") { apuntar() }
                    .keyboardShortcut(.defaultAction)
                    .tlsBoton(.principal)
                    .disabled(descripcion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || motivoSoloLectura != nil || guardando)
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 560)
    }

    private func apuntar() {
        guardando = true
        Task {
            let e = await guardar(quien.trimmingCharacters(in: .whitespaces), email.trimmingCharacters(in: .whitespaces), tipo, severidad,
                                  descripcion.trimmingCharacters(in: .whitespacesAndNewlines))
            guardando = false
            if let e { error = e } else { dismiss() }
        }
    }
}
