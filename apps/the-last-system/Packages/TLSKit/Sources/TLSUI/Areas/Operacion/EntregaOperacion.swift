import SwiftUI
import TLSCore
import TLSDesign

// Rol areas-a (F2). El `init` es contrato con `AreaScaffold` (docs/F2-CONTRATOS.md §2). PLAN §6.5 y SISTEMAS §4.2:
// Expedientes (cada uno con su Viaje S1–S9, Tareas, Portal en vista interna o del cliente, Incidencias con cuenta
// atrás y Materiales) · Cronograma · Carga · Revisión del viernes. Arriba, ENT-ONTIME y ENT-INC. Acción rápida:
// Nueva incidencia (en el expediente).

/// Pestaña Operación de Entrega.
struct EntregaOperacion: View {
    let contexto: ContextoArea
    let sesion: VaultSession

    @State private var carga: CargaOperacion<DatosEntrega>
    @State private var error: String?
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @Environment(\.undoManager) private var undoManager

    static let secciones = ["Expedientes", "Cronograma", "Carga", "Revisión del viernes"]
    static let clave = "entrega.vista"
    static let claveExpediente = "entrega.expediente"

    init(contexto: ContextoArea, sesion: VaultSession) {
        self.contexto = contexto
        self.sesion = sesion
        _carga = State(initialValue: CargaOperacion(sesion: sesion) { foto, hoy in DatosEntrega.calcular(foto: foto, hoy: hoy) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if let d = carga.datos {
                contenido(d)
            } else {
                CargandoOperacion(texto: "Leyendo expedientes, portales e incidencias…")
            }
        }
        .task(id: sesion.revision) { await carga.cargar() }
        .accessibilityIdentifier("area.operacion.entrega")
    }

    @ViewBuilder
    private func contenido(_ d: DatosEntrega) -> some View {
        FranjaCifras(cifras: d.cifras)
        if let error { AvisoEnLinea(error, estado: .mal) }
        if let e = elegido(d) {
            ExpedienteDetalle(expediente: e, datos: d, sesion: sesion, motivoSoloLectura: carga.motivoSoloLectura) {
                nav?.actualizarRecuerdo(de: .area(.entrega)) { $0.extra[Self.claveExpediente] = nil }
            }
        } else {
            SeccionesOperacion(area: .entrega, clave: Self.clave, secciones: secciones(d))
            switch SeccionesOperacion.elegida(nav, area: .entrega, clave: Self.clave, secciones: Self.secciones) {
            case "Cronograma":
                BloqueOperacion("Cronograma de expedientes", detalle: "Los proyectos de cliente de inicio a fin. Arrastra para moverlos; si caen en fin de semana, pasan al lunes.") {
                    if d.cronograma.vacio {
                        Text("Aún no hay expedientes abiertos.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    } else {
                        CronogramaVista(cronograma: d.cronograma, motivoSoloLectura: carga.motivoSoloLectura,
                                        alMover: { b, i, f in
                                            error = nil
                                            Task { error = await AccionesDireccion.mover(b, inicio: i, fin: f, sesion: sesion, deshacer: undoManager) }
                                        },
                                        alAbrir: { b in elegir(b.ruta) })
                    }
                }
            case "Carga":
                BloqueOperacion("Carga de la semana", detalle: "Tareas de Entrega planificadas cada día (con su estimación) y sesiones agendadas, frente al tope de horas.") {
                    CargaEntregaVista(dias: d.carga, hoy: d.hoy)
                }
            case "Revisión del viernes":
                RevisionViernesVista(revision: RevisionViernes.de(d), hoy: d.hoy) { ruta in elegir(ruta) }
            default:
                BloqueOperacion("Expedientes", detalle: "Los proyectos de cliente: su viaje, sus incidencias y lo que les falta.") {
                    ListaExpedientes(datos: d) { e in elegir(e.ruta) }
                }
            }
        }
    }

    private func secciones(_ d: DatosEntrega) -> [PestanaCapsula] {
        let abiertos = d.expedientes.filter(\.abierto).count
        let fuera = d.expedientes.reduce(0) { $0 + ($1.incidencias?.fueraDePlazo(ahora: d.ahora, zona: d.zona).count ?? 0) }
        return [
            PestanaCapsula(id: "Expedientes", titulo: "Expedientes", contador: abiertos == 0 ? nil : abiertos, urgente: fuera > 0 ? .mal : nil),
            PestanaCapsula(id: "Cronograma", titulo: "Cronograma"),
            PestanaCapsula(id: "Carga", titulo: "Carga", urgente: d.carga.contains(where: \.pasaDelTope) ? .atencion : nil),
            PestanaCapsula(id: "Revisión del viernes", titulo: "Revisión del viernes"),
        ]
    }

    /// El expediente abierto (recordado por pestaña de ventana).
    private func elegido(_ d: DatosEntrega) -> ExpedienteEntrega? {
        guard let r = nav?.recuerdo(de: .area(.entrega)).extra[Self.claveExpediente] else { return nil }
        return d.expedientes.first { $0.ruta.raw == r }
    }

    private func elegir(_ ruta: VaultPath) {
        if carga.datos?.expedientes.contains(where: { $0.ruta == ruta }) == true {
            nav?.actualizarRecuerdo(de: .area(.entrega)) { $0.extra[Self.claveExpediente] = ruta.raw }
        } else {
            navegar(sesion.destino(para: ruta), modo: .automatico)
        }
    }
}

/// La carga de Entrega de lunes a viernes, frente al tope (el aviso con palabra; nunca horas inventadas).
struct CargaEntregaVista: View {
    let dias: [DiaCarga]
    let hoy: LocalDate

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(dias.enumerated()), id: \.element.id) { i, d in
                if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                fila(d)
            }
        }
        .accessibilityIdentifier("entrega.carga")
    }

    private func fila(_ d: DiaCarga) -> some View {
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FormatoFicha.fechaConDia(d.dia, hoy: hoy)).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                if d.esHoy { Text("Hoy").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color) }
            }
            .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    let fraccion = d.tope > 0 ? min(1, d.horas / d.tope) : 0
                    ZStack(alignment: .leading) {
                        Capsule(style: .circular).fill(TLSPaleta.bandeja.color)
                        Capsule(style: .circular).fill(d.pasaDelTope ? TLSEstado.mal.color.color : TLSArea.entrega.relleno.color)
                            .frame(width: max(0, geo.size.width * fraccion))
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
                let cosas = d.tareas + d.sesiones.map { "Sesión: \($0)" }
                Text(cosas.isEmpty ? "Nada planificado" : cosas.joined(separator: " · "))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                if d.sinEstimar > 0 {
                    Text(d.sinEstimar == 1 ? "1 tarea sin estimar (no suma horas)" : "\(d.sinEstimar) tareas sin estimar (no suman horas)")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            Text(d.textoCarga).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color).frame(width: 84, alignment: .trailing)
            if d.pasaDelTope { PastillaEstado(.mal, palabra: "Pasa del tope") }
        }
        .padding(.vertical, TLSEspacio.e8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FormatoFicha.fechaConDia(d.dia, hoy: hoy)): \(d.textoCarga)"
            + (d.pasaDelTope ? ", pasa del tope" : "") + (d.sesiones.isEmpty ? "" : ", \(d.sesiones.count) sesiones"))
    }
}

/// La revisión del viernes: lo hecho esta semana, lo que viene, lo que se atasca y lo que esperamos del cliente.
struct RevisionViernesVista: View {
    let revision: RevisionViernes
    let hoy: LocalDate
    let alAbrir: (VaultPath) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text(hoy.weekday == 5 ? "Hoy es viernes: toca la revisión. \(revision.titulo)."
                 : "La revisión toca el viernes. \(revision.titulo).")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
            if revision.vacia {
                Text("Nada que revisar esta semana.").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            seccion("Hecho esta semana", revision.hechas, vacio: "Ninguna sesión hecha esta semana.")
            seccion("La semana que viene", revision.proximas, vacio: "Nada agendado para la semana que viene.")
            seccion("Lo que se atasca", revision.atascos, vacio: "Nada atascado: ni incidencias abiertas ni expedientes en riesgo.")
            seccion("Lo que esperamos de los clientes", revision.delCliente, vacio: "Los clientes no tienen nada pendiente.")
        }
        .accessibilityIdentifier("entrega.revision")
    }

    private func seccion(_ titulo: String, _ lineas: [RevisionViernes.Linea], vacio: String) -> some View {
        BloqueOperacion(titulo) {
            if lineas.isEmpty {
                Text(vacio).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                VStack(spacing: 2) {
                    ForEach(lineas) { l in
                        FilaLista(l.texto, detalle: l.detalle, accion: l.ruta.map { r in { alAbrir(r) } }) {
                            PastillaEstado(l.estado, palabra: l.palabra)
                        }
                    }
                }
            }
        }
    }
}
