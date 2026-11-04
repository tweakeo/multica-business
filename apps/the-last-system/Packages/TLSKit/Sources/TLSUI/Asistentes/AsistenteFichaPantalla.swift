import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes (PLAN §6.5, SISTEMAS §2.4 y §6). La ficha de un asistente, navegable con migas (`Asistentes ›
// Contable`): misión y pregunta; lo que hace solo, con tu OK y nunca; permisos por función con los cuatro niveles (lo
// que sale fuera, bloqueado en «Siempre con tu OK»); rutinas con su interruptor, día y hora; topes de uso; trabajos
// recientes con «Detalle técnico»; su bitácora; y «Pedir algo». Los cambios se preparan aquí, se revisan en una vista
// previa y se guardan en `config.yaml` como la persona, con Deshacer (`EscrituraAsistentes`).

/// Las pestañas de la ficha de un asistente.
enum PestanaAsistente: String, CaseIterable, Sendable {
    case resumen = "Resumen"
    case permisos = "Permisos"
    case rutinas = "Rutinas y topes"
    case trabajos = "Trabajos"
    case bitacora = "Bitácora"
}

struct AsistenteFichaPantalla: View {
    let slug: String
    let sesion: VaultSession
    @State private var modelo: ModeloAsistentes
    /// Cambios preparados y aún sin guardar (por clave: el último gana).
    @State private var cambios: [String: CambioDeAsistente] = [:]
    @State private var ordenCambios: [String] = []
    @State private var revisando = false
    @State private var pidiendo = false
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav

    static let clavePestana = "asistente.pestana"

    init(slug: String, sesion: VaultSession) {
        self.slug = ConfigAgentes.slug(slug)
        self.sesion = sesion
        _modelo = State(initialValue: ModeloAsistentes(sesion: sesion))
    }

    private var destino: Destino { .asistente(slug) }

    private var pestana: PestanaAsistente {
        nav?.recuerdo(de: destino).extra[Self.clavePestana].flatMap(PestanaAsistente.init(rawValue:)) ?? .resumen
    }

    private func ir(_ p: PestanaAsistente) {
        nav?.actualizarRecuerdo(de: destino) { $0.extra[Self.clavePestana] = p == .resumen ? nil : p.rawValue }
    }

    var listaCambios: [CambioDeAsistente] { ordenCambios.compactMap { cambios[$0] } }

    var body: some View {
        ContenedorPantalla(destino: destino, espacio: TLSEspacio.e16) {
            if let l = modelo.lectura {
                if let a = l.asistente(slug) {
                    contenido(a, l)
                } else {
                    VacioExplicado(icono: "sparkle", titulo: "No conozco a este asistente",
                                   porQue: "No está en la configuración de los asistentes ni entre los de serie.",
                                   accion: "Ver todos", alPulsar: { navegar(.asistentes, modo: .raiz) })
                }
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    ProgressView().controlSize(.small)
                    Text("Abriendo su ficha…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !cambios.isEmpty, let l = modelo.lectura, let a = l.asistente(slug) { barraCambios(a, l) }
        }
        .sheet(isPresented: $revisando) {
            if let l = modelo.lectura, let a = l.asistente(slug) { hojaRevisar(a, l) }
        }
        .sheet(isPresented: $pidiendo) {
            if let l = modelo.lectura, let a = l.asistente(slug) {
                HojaPedirAlgo(nombre: a.nombre, acciones: a.perfil?.accionesRapidas ?? [],
                              motivoNoSePuede: motivoNoPuedePedir(a), pedir: { t, acc in await pedir(t, accion: acc, a: a) })
            }
        }
        .task(id: modelo.claveRecarga) { await modelo.cargar() }
        .accessibilityIdentifier("asistente.ficha")
    }

    // MARK: Contenido

    @ViewBuilder
    private func contenido(_ a: AsistenteEnLista, _ l: LecturaAsistentes) -> some View {
        let vivo = modelo.vivo(slug)
        let estado = a.estado(vivo: vivo)
        let editables = AjustesConCambios.de(a, config: l.config, cambios: listaCambios)
        cabecera(a, l, editables: editables)
        HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
            destacado(a, l, estado: estado, vivo: vivo)
                .frame(minWidth: 260, maxWidth: 380, minHeight: 140)
            Mosaico("Uso del mes", icono: "gauge.with.dots.needle.33percent", pie: "Frente a su tope del mes") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(a.uso.cifra).tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                        Text("de tu tope").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        if a.uso.simulado { MarcaSimulado() }
                    }
                    BarraUso(uso: a.uso)
                }
            }
            .frame(minWidth: 220, minHeight: 140)
        }
        .fixedSize(horizontal: false, vertical: true)
        if let c = l.cambiosDeFuera {
            HStack(spacing: TLSEspacio.e8) {
                AvisoEnLinea(c + ". Hasta que lo confirmes, sigue con los de antes y aquí no se puede cambiar nada.", estado: .atencion)
                Button("Ir a Decisiones") { navegar(.decisiones, modo: .raiz) }.tlsBoton(.secundario)
            }
        }
        if l.demo {
            AvisoEnLinea("Es un ejemplo: lo que hace aquí \(a.nombre) es simulado y lleva la marca «Simulado».", estado: .sinDato)
        }
        PestanasCapsula(seleccion: Binding(get: { pestana.rawValue }, set: { ir(PestanaAsistente(rawValue: $0) ?? .resumen) }),
                        pestanas: pestanas(a, l))
            .accessibilityLabel("Secciones de la ficha de \(a.nombre)")
            .accessibilityIdentifier("asistente.pestanas")
        switch pestana {
        case .resumen:
            ResumenAsistente(asistente: a, lectura: l, editables: editables, pedirAlgo: { pedirAlgo(a) })
        case .permisos:
            PermisosAsistente(asistente: a, editables: editables, motivoNoSePuede: motivoNoSePuede(l),
                              poner: { poner($0, a: a, l: l) })
        case .rutinas:
            RutinasYTopesAsistente(sesion: sesion, asistente: a, lectura: l, editables: editables,
                                   motivoNoSePuede: motivoNoSePuede(l), poner: { poner($0, a: a, l: l) })
        case .trabajos:
            TrabajosAsistente(sesion: sesion, asistente: a, lectura: l, vivo: vivo, directorio: modelo.directorioDeEstado)
        case .bitacora:
            BitacoraAsistentesVista(sesion: sesion, lectura: l, fijo: slug)
        }
    }

    private func pestanas(_ a: AsistenteEnLista, _ l: LecturaAsistentes) -> [PestanaCapsula] {
        let trabajos = l.trabajos(de: slug)
        let esperando = trabajos.filter { $0.estado == .esperandoRespuesta }.count
        return PestanaAsistente.allCases.map { p in
            switch p {
            case .permisos: PestanaCapsula(id: p.rawValue, titulo: p.rawValue, contador: AjustesConCambios.funciones(a).count)
            case .rutinas: PestanaCapsula(id: p.rawValue, titulo: p.rawValue, contador: a.rutinas.count,
                                          urgente: a.rutinas.contains { $0.autopausa != nil } ? .atencion : nil)
            case .trabajos: PestanaCapsula(id: p.rawValue, titulo: p.rawValue, contador: trabajos.isEmpty ? nil : trabajos.count,
                                           aviso: esperando > 0 ? (esperando, "Te pregunta") : nil)
            case .bitacora: PestanaCapsula(id: p.rawValue, titulo: p.rawValue,
                                           contador: l.bitacora(de: slug).filter { $0.mes == l.mes }.count)
            case .resumen: PestanaCapsula(id: p.rawValue, titulo: p.rawValue)
            }
        }
    }

    private func cabecera(_ a: AsistenteEnLista, _ l: LecturaAsistentes, editables: AjustesConCambios) -> some View {
        let motivo = motivoNoSePuede(l)
        let opciones = [OpcionEstado(id: "si", titulo: "Activo", estado: .bien, motivoDesactivado: editables.activo ? "Ya está activo" : motivo),
                        OpcionEstado(id: "no", titulo: "Apagado", estado: .sinDato, motivoDesactivado: !editables.activo ? "Ya está apagado" : motivo)]
        let lugar = a.esDelSistema || a.area == nil ? "Buzón y orden de la carpeta" : a.area!.etiquetaNumerada
        return CabeceraAzulNoche(
            rotulo: "Asistente · \(lugar)", titulo: a.nombre,
            subtitulo: FormatoFicha.capital(a.descripcion) + (a.coordinador ? ". Coordina a los demás y lee todas las áreas." : "."),
            estado: EstadoCabecera(editables.activo ? "Activo" : "Apagado", estado: editables.activo ? .bien : .sinDato, opciones: opciones) { o in
                poner(.activo(o.id == "si"), a: a, l: l)
            },
            datos: [DatoClave("Área", lugar), DatoClave("Uso del mes", a.uso.cifra), DatoClave("Rutinas", "\(a.rutinas.count)")],
            identidad: { AvatarCabecera(simbolo: a.simbolo) },
            acciones: {
                Button("Pedir algo") { pedirAlgo(a) }
                    .tlsBoton(.sobreCabecera, alto: 36)
                    .help("Abre ⌘J con \(a.nombre)")
                    .accessibilityIdentifier("asistente.pedir")
            })
            .accessibilityIdentifier("asistente.cabecera")
    }

    /// El destacado (uno por pantalla): qué pasa ahora y lo próximo.
    @ViewBuilder
    private func destacado(_ a: AsistenteEnLista, _ l: LecturaAsistentes, estado: EstadoDeAsistente, vivo: TrabajoEnVivo?) -> some View {
        let proxima = a.proxima.map { "Próxima rutina: «\($0.nombre)», \(FormatoAsistentes.cuando($0.fecha, zona: l.zona, hoy: l.hoy))" }
        let accion: (String, () -> Void)? = {
            switch estado {
            case .trabajando:
                if let host = modelo.conexion?.host, let id = vivo?.ejecucion {
                    return ("Parar este trabajo", { Task { await host.cancelar(id) } })
                }
                return nil
            case .esperandoRespuesta: return ("Ir a Decisiones", { navegar(.decisiones, modo: .raiz) })
            case .apagado:
                return motivoNoSePuede(l) == nil ? ("Activarlo", { poner(.activo(true), a: a, l: l) }) : nil
            default: return nil
            }
        }()
        Destacado(rotulo: "Ahora", accion: accion?.0, alPulsar: accion?.1) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    PastillaAsistente(estado, sobreColor: true)
                    if vivo?.simulado == true { MarcaSimulado(sobreColor: true) }
                }
                Text(estado.detalle).tlsTexto(TLSTipo.interfazFuerte).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("asistente.ahora.frase")
                if let p = proxima, !estado.trabajando {
                    Text(p).tlsTexto(TLSTipo.secundario).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("asistente.ahora")
    }

    // MARK: Cambios

    /// Por qué no se puede cambiar nada aquí (`nil` si se puede).
    private func motivoNoSePuede(_ l: LecturaAsistentes) -> String? {
        switch sesion.modoEscritura {
        case .escribe: break
        case .abriendo: return "Abriendo la carpeta…"
        case .soloLectura(let m): return "Solo lectura: \(m.texto)"
        }
        if l.cambiosDeFuera != nil { return "Antes confirma los permisos que cambiaron fuera de la app (en Decisiones)" }
        return nil
    }

    /// Prepara un cambio (sin guardarlo). Si deja las cosas como estaban, se quita.
    private func poner(_ c: CambioDeAsistente, a: AsistenteEnLista, l: LecturaAsistentes) {
        guard motivoNoSePuede(l) == nil else { return }
        let ahora = AjustesConCambios.de(a, config: l.config, cambios: [])
        var con = ahora
        con.aplicar(c)
        if con == ahora {
            cambios[c.clave] = nil
            ordenCambios.removeAll { $0 == c.clave }
        } else {
            if cambios[c.clave] == nil { ordenCambios.append(c.clave) }
            cambios[c.clave] = c
        }
    }

    private func barraCambios(_ a: AsistenteEnLista, _ l: LecturaAsistentes) -> some View {
        let n = cambios.count
        return HStack(spacing: TLSEspacio.e12) {
            Image(systemName: "pencil.circle.fill").font(.system(size: 18)).foregroundStyle(TLSPaleta.principal.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(n == 1 ? "1 cambio sin guardar" : "\(n) cambios sin guardar").tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                Text("En los ajustes de \(a.nombre). Antes de guardar verás qué cambia.").tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer()
            Button("Descartar") { cambios = [:]; ordenCambios = [] }.tlsBoton(.secundario)
                .accessibilityIdentifier("asistente.cambios.descartar")
            Button("Revisar y guardar") { revisando = true }.tlsBoton(.principal)
                .accessibilityIdentifier("asistente.cambios.revisar")
        }
        .padding(.horizontal, TLSEspacio.e24)
        .padding(.vertical, TLSEspacio.e12)
        .background(TLSPaleta.superficieElevada.color)
        .overlay(alignment: .top) { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("asistente.cambios")
    }

    private func hojaRevisar(_ a: AsistenteEnLista, _ l: LecturaAsistentes) -> some View {
        let lista = listaCambios
        let contados = DescripcionDeCambios.contar(lista, asistente: a, config: l.config)
        var lineas: [String] = []
        var problema: String?
        if let root = sesion.root {
            do {
                let p = try EscrituraAsistentes.vistaPrevia(lista, slug: slug, perfil: a.perfil, root: root)
                lineas = DescripcionDeCambios.lineasQueCambian(antes: p.antes, despues: p.despues)
            } catch {
                problema = error.localizedDescription
            }
        }
        return HojaRevisarCambios(nombre: a.nombre, cambios: contados, lineas: lineas, error: problema) {
            do {
                try await EscrituraAsistentes.guardar(lista, slug: slug, nombre: a.nombre, perfil: a.perfil, sesion: sesion)
                cambios = [:]
                ordenCambios = []
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    // MARK: Pedir algo

    private func pedirAlgo(_ a: AsistenteEnLista) {
        if let abrir = modelo.conexion?.abrirChat {
            abrir(a.slug, "Ficha de \(a.nombre) (asistente)")
        } else {
            pidiendo = true
        }
    }

    private func motivoNoPuedePedir(_ a: AsistenteEnLista) -> String? {
        guard modelo.conexion?.host != nil else {
            return "Los asistentes aún no están en marcha en este Mac: cuando lo estén, podrás pedírselo desde aquí o con ⌘J."
        }
        switch a.estadoGuardado {
        case .apagado(let m), .enPausa(let m): return "Ahora no puede trabajar: \(m)."
        default: return nil
        }
    }

    private func pedir(_ texto: String, accion: String?, a: AsistenteEnLista) async -> String? {
        guard let host = modelo.conexion?.host else { return motivoNoPuedePedir(a) }
        do {
            guard try await host.pedir(a: a.slug, instruccion: texto, pantalla: "Ficha de \(a.nombre) (asistente)", accion: accion) != nil else {
                return "Ahora no puede trabajar: \(a.estadoGuardado.detalle)."
            }
            sesion.aviso = Aviso("Se lo he pedido a \(a.nombre): lo verás en sus trabajos", estado: .bien)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
