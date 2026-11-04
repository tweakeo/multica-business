import AppKit
import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F5 · rol buzon-relevo. Carpeta › Buzón con la estética Mosaico v2: cabecera azul noche con las cifras del mes, un día
// del registro del correo (pestañas por día), cada correo con su tipo, adónde fue y la tarea o el borrador que salió de
// él; después las propuestas pendientes, los informes de importación y lo que está por ordenar, con «Ordenar el Buzón»
// (la acción rápida del Ordenador). Nada se escribe desde aquí.

/// El estado de la pantalla (día y mes elegidos) y su lectura.
@MainActor
@Observable
final class ModeloBuzon {
    private(set) var lectura: LecturaBuzon?
    /// «AAAA-MM» elegido (`nil` = el que toca).
    var mes: String?
    /// Día elegido (`nil` = el que toca).
    var dia: LocalDate?

    init() {}

    /// Lee la foto fuera del hilo principal.
    func cargar(_ sesion: VaultSession) async {
        guard let foto = await sesion.instantanea() else { return }
        let hoy = sesion.hoy
        let mes = self.mes
        lectura = await Task.detached(priority: .userInitiated) { LecturaBuzon.leer(foto: foto, hoy: hoy, mes: mes) }.value
    }

    /// Lo mismo, con una foto ya hecha (pruebas y capturas).
    func cargar(foto: VaultSnapshot, hoy: LocalDate) {
        lectura = LecturaBuzon.leer(foto: foto, hoy: hoy, mes: mes)
    }

    /// El día que se enseña.
    var diaVisible: DiaDelBuzon? {
        guard let l = lectura else { return nil }
        return l.dia(dia) ?? l.dia(l.diaPorDefecto)
    }

    /// Las pestañas de los días (como mucho los 10 últimos; el resto, en el menú «Más»).
    var pestanasDias: [PestanaCapsula] {
        (lectura?.dias ?? []).map { d in
            PestanaCapsula(id: d.dia.description, titulo: Self.diaCorto(d.dia, hoy: lectura?.hoy), contador: d.lineas.count,
                           urgente: d.conPlazo > 0 ? .mal : nil)
        }
    }

    /// «Hoy», «Ayer» o «lun 12».
    static func diaCorto(_ d: LocalDate, hoy: LocalDate?) -> String {
        if let hoy {
            if d == hoy { return "Hoy" }
            if d == hoy.adding(days: -1) { return "Ayer" }
        }
        let dias = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
        return "\(dias[(d.weekday - 1 + 7) % 7]) \(d.day)"
    }

    /// «lunes, 19 de octubre».
    static func diaLargo(_ d: LocalDate) -> String {
        let dias = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
        return "\(dias[(d.weekday - 1 + 7) % 7]), \(d.day) de \(LecturaBuzon.meses[d.month - 1])"
    }

    /// El resumen de un día en una frase: «4 correos · 1 privado · 1 con plazo oficial».
    static func resumen(_ d: DiaDelBuzon) -> String {
        var partes = [d.lineas.count == 1 ? "1 correo" : "\(d.lineas.count) correos"]
        if d.privados > 0 { partes.append(d.privados == 1 ? "1 privado" : "\(d.privados) privados") }
        if d.conPlazo > 0 { partes.append(d.conPlazo == 1 ? "1 con plazo oficial" : "\(d.conPlazo) con plazo oficial") }
        if d.porRevisar > 0 { partes.append(d.porRevisar == 1 ? "1 por revisar" : "\(d.porRevisar) por revisar") }
        return partes.joined(separator: " · ")
    }

    /// El tipo en pantalla («Cliente», «Administración»…).
    static func tipo(_ l: LineaDelBuzon) -> String {
        let t = l.tipo?.rawValue ?? l.tipoTexto
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    static func estado(_ l: LineaDelBuzon) -> TLSEstado {
        switch l.estado {
        case .hecho?: .bien
        // F5 · corrector (P3-16): «Propuesto» no es un problema: neutro, sin triángulo naranja.
        case .propuesto?: .sinDato
        default: .sinDato
        }
    }
}

/// Carpeta › Buzón. Se llega por `Destino.carpeta(<Buzón>)` (el enrutador la elige si la carpeta es el Buzón).
struct BuzonPantalla: View {
    let sesion: VaultSession
    @State private var modelo = ModeloBuzon()
    @Environment(\.navegar) private var navegar

    init(sesion: VaultSession, modelo: ModeloBuzon? = nil) {
        self.sesion = sesion
        if let modelo { _modelo = State(initialValue: modelo) }
    }

    /// ¿Es `ruta` la carpeta del Buzón de esta empresa?
    static func es(_ ruta: VaultPath?, _ sesion: VaultSession) -> Bool {
        guard let ruta, let b = sesion.estructura?.buzon, !b.isEmpty else { return false }
        return TextFolding.pathKey(ruta.raw) == TextFolding.pathKey(b)
    }

    var body: some View {
        ContenedorPantalla(destino: .carpeta(modelo.lectura?.carpeta ?? sesion.estructura?.buzon.map { VaultPath($0) })) {
            if let l = modelo.lectura {
                cabecera(l)
                if l.carpeta == nil {
                    VacioExplicado(icono: "tray", titulo: "Esta empresa no tiene Buzón",
                                   porQue: "El Buzón es la carpeta por la que entra todo lo de fuera: el correo, los informes de importación y lo que sueltas para ordenar.")
                } else {
                    correo(l)
                    if !l.propuestas.isEmpty { notas("Propuestas pendientes", l.propuestas, icono: "lightbulb") }
                    if !l.informes.isEmpty { notas("Informes de importación", l.informes, icono: "doc.text.magnifyingglass") }
                    porOrdenar(l)
                }
            } else {
                CabeceraAzulNoche(rotulo: "Carpeta", titulo: "Buzón", subtitulo: "Leyendo el Buzón…", altoMinimo: TLSAltura.cabeceraBase)
            }
        }
        .task(id: sesion.revision) { await modelo.cargar(sesion) }
        .tlsPantalla("Buzón")
        .accessibilityIdentifier("pantalla.buzon")
    }

    // MARK: Cabecera

    private func cabecera(_ l: LecturaBuzon) -> some View {
        let motivo = PedirAAsistente.motivoRapido(sesion, slug: "ordenador")
        return CabeceraAzulNoche(
            rotulo: "Carpeta", titulo: "Buzón",
            subtitulo: "Lo que entra de fuera y adónde va. El Cartero apunta aquí el correo que ha llegado.",
            datos: [DatoClave(l.mes.map { "Correos de \($0.titulo.components(separatedBy: " de ").first ?? "")" } ?? "Correos del mes",
                              "\(l.correosDelMes)"),
                    DatoClave("Por revisar", l.propuestosDelMes == 0 ? "Ninguno" : "\(l.propuestosDelMes)"),
                    DatoClave("Por ordenar", l.porOrdenar.isEmpty ? "Nada" : "\(l.porOrdenar.count)")],
            altoMinimo: TLSAltura.cabeceraBase, cifrasALaDerecha: true
        ) {
            EmptyView()
        } acciones: {
            Button("Ordenar el Buzón") {
                Task { await PedirAAsistente.encargar("ordenador", accion: "ordenar-buzon", sesion: sesion, pantalla: "Buzón") }
            }
            .tlsBoton(.sobreCabecera)
            .disabled(motivo != nil)
            .help(motivo ?? "El Ordenador mueve lo que está claro y te deja una sola tarjeta con las dudas")
            .accessibilityIdentifier("buzon.ordenar")
        } debajo: {
            EmptyView()
        }
    }

    // MARK: Correo

    @ViewBuilder
    private func correo(_ l: LecturaBuzon) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Correo").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                if let m = l.mes {
                    if l.meses.count > 1 {
                        Menu(m.titulo) {
                            ForEach(l.meses) { x in
                                Button(x.titulo) { modelo.mes = x.mes; modelo.dia = nil; Task { await modelo.cargar(sesion) } }
                            }
                        }
                        .menuStyle(.button).fixedSize().tlsBoton(.discreto)
                    } else {
                        Text(m.titulo).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                Spacer()
                if let m = l.mes {
                    Button("Abrir el registro") { navegar(.nota(m.ruta), modo: .entrar) }.tlsBoton(.enlace)
                }
            }
            if l.dias.isEmpty {
                VacioExplicado(icono: "envelope", titulo: "Aún no hay correo apuntado",
                               porQue: "Cuando conectes Mail, la app recoge lo que llega cada 15 minutos y cada mañana el Cartero lo clasifica y lo apunta aquí con su tarea o su borrador. Nunca contesta ni borra nada.",
                               compacto: true)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            } else {
                PestanasCapsula(seleccion: Binding(get: { modelo.diaVisible?.id ?? "" },
                                                   set: { modelo.dia = LocalDate(parsing: $0) }),
                                pestanas: Array(modelo.pestanasDias.prefix(10)), mas: Array(modelo.pestanasDias.dropFirst(10)), atajosControl: false)
                if let d = modelo.diaVisible { DiaDelBuzonVista(dia: d, sesion: sesion) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("buzon.correo")
    }

    // MARK: Notas

    private func notas(_ titulo: String, _ lista: [NotaDelBuzon], icono: String) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: 8) {
                Text(titulo).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
                InsigniaAviso(lista.count, palabra: lista.count == 1 ? "nota" : "notas")
            }
            VStack(spacing: 2) {
                ForEach(lista) { n in
                    FilaLista(n.titulo, detalle: [n.fecha.map { ModeloBuzon.diaLargo($0) }, n.detalle].compactMap { $0 }.joined(separator: " · "),
                              icono: icono, accion: { navegar(sesion.destino(para: n.ruta), modo: .entrar) }) {
                        EmptyView()
                    }
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("buzon.\(icono == "lightbulb" ? "propuestas" : "informes")")
    }

    @ViewBuilder
    private func porOrdenar(_ l: LecturaBuzon) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text("Por ordenar").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
            if l.porOrdenar.isEmpty {
                Text("Nada suelto en el Buzón: todo está en su sitio.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                VStack(spacing: 2) {
                    ForEach(l.porOrdenar) { n in
                        FilaLista(n.titulo, detalle: n.titulo == n.ruta.name ? nil : n.ruta.name, icono: "doc",
                                  accion: { navegar(sesion.destino(para: n.ruta), modo: .entrar) }) { EmptyView() }
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                Text("«Ordenar el Buzón» lleva lo que está claro a su sitio (con deshacer) y te deja una sola tarjeta con las dudas.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .accessibilityIdentifier("buzon.porOrdenar")
    }
}

/// Un día del registro: un mosaico con un correo por fila.
struct DiaDelBuzonVista: View {
    let dia: DiaDelBuzon
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(ModeloBuzon.diaLargo(dia.dia).prefix(1).uppercased() + ModeloBuzon.diaLargo(dia.dia).dropFirst())
                    .tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                Spacer()
                Text(ModeloBuzon.resumen(dia)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .padding(.horizontal, TLSEspacio.e16).padding(.vertical, TLSEspacio.e12)
            ForEach(dia.lineas) { l in
                Divider().overlay(TLSPaleta.separador.color)
                FilaCorreoBuzon(linea: l, sesion: sesion)
            }
        }
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).strokeBorder(TLSPaleta.borde1.color))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("buzon.dia.\(dia.dia)")
    }
}

/// Un correo del registro.
struct FilaCorreoBuzon: View {
    let linea: LineaDelBuzon
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            Text(linea.hora).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: 44, alignment: .leading)
            Image(systemName: linea.privado ? "lock.fill" : "envelope")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(linea.privado ? TLSPaleta.textoSecundario.color : TLSPaleta.principal.color)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(linea.quien).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    if let d = linea.direccion {
                        Text(d).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                    }
                }
                if linea.privado {
                    Text("Privado: solo se apunta que llegó. Ni el asunto ni el texto llegan a ningún asistente.")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                } else if let a = linea.asunto {
                    Text(a).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                }
                FlujoChips(espacio: 6) {
                    Chip(ModeloBuzon.tipo(linea), icono: "tag")
                    Chip(linea.destino.isEmpty ? "Sin destino" : linea.destino, icono: "arrow.turn.down.right")
                    if let p = linea.plazo { Chip("Plazo \(AlmacenHoy.dia(p, hoy: sesion.hoy))", icono: "exclamationmark.triangle", estado: .mal) }
                }
                if !linea.enlazados.isEmpty {
                    FlujoChips(espacio: 8) {
                        ForEach(linea.enlazados) { e in
                            Button {
                                navegar(sesion.destino(para: e.ruta), modo: .entrar)
                            } label: {
                                Label("\(e.rotulo): \(e.titulo)" + (e.estado.map { " · \($0)" } ?? ""),
                                      systemImage: e.clase == .tarea ? "checklist" : "square.and.pencil")
                            }
                            .tlsBoton(.enlace)
                            .accessibilityIdentifier("buzon.enlace.\(e.clase.rawValue)")
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                PastillaEstado(ModeloBuzon.estado(linea), palabra: linea.estadoTexto.isEmpty ? "Sin estado" : linea.estadoTexto)
                if let url = linea.enlaceMail {
                    Button("Abrir en Mail") { NSWorkspace.shared.open(url) }
                        .tlsBoton(.enlace)
                        .help("Abre el mensaje en Mail (no se envía ni se cambia nada)")
                }
            }
        }
        .padding(.horizontal, TLSEspacio.e16).padding(.vertical, TLSEspacio.e12)
        // F5 · corrector (P2-11): `.contain`, no `.combine`: los enlaces y «Abrir en Mail» se alcanzan con VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("buzon.linea")
    }
}
