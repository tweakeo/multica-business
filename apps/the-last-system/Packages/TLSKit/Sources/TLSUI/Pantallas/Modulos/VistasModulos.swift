import SwiftUI
import TLSCore
import TLSDesign

// Cada módulo de inicio (DISENO §6): `superficie`, radio 22, sombra 1; arriba el icono del área (16 pt) y el nombre en
// `rotulo`; en medio la cifra en Space Grotesk o su vista (caja, ritmo, semana, lo de hoy); al pie «Sale de…». Sin dato,
// un vacío que dice por qué (nunca un 0). El color nunca va solo: estado = icono y palabra.

/// Lo que se puede hacer con un módulo (lo da la rejilla).
struct AccionesModulo {
    var ocultar: () -> Void
    var mover: (Int) -> Void
    var siguienteTamano: () -> Void
    var editarInicio: () -> Void
}

/// Marco de un módulo: cabecera con su icono y nombre, el «…» con sus opciones (o los controles de editar), el
/// contenido y el pie con la fuente.
struct MarcoModulo<Contenido: View>: View {
    let colocado: ModuloColocado
    let posicion: Int
    let total: Int
    let editando: Bool
    let pie: String?
    let acciones: AccionesModulo
    let contenido: Contenido
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var temblor = false

    init(colocado: ModuloColocado, posicion: Int, total: Int, editando: Bool, pie: String?, acciones: AccionesModulo,
         @ViewBuilder contenido: () -> Contenido) {
        self.colocado = colocado; self.posicion = posicion; self.total = total; self.editando = editando
        self.pie = pie; self.acciones = acciones; self.contenido = contenido()
    }

    var definicion: DefinicionModulo { CatalogoModulos.definicion(colocado.modulo) }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: TLSEspacio.e8) {
                if let a = definicion.area {
                    IconoArea(a.tlsArea, tamano: 16)
                } else {
                    Image(systemName: "square.grid.2x2").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                }
                Rotulo(definicion.titulo).lineLimit(1)
                Spacer(minLength: 0)
                if editando { controlesEdicion } else { menu }
            }
            contenido.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let pie, !editando {
                Text(pie)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                    .help(pie)
            }
            if editando { pieEdicion }
        }
        .padding(colocado.tamano == .grande ? TLSEspacio.mosaicoGrande : TLSEspacio.mosaicoPequeno)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay {
            if editando && reducir {
                forma.strokeBorder(TLSPaleta.bordeControl.color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .tlsSombra(.uno, forma: forma)
        .rotationEffect(.degrees(editando && !reducir ? (temblor ? TLSMovimiento.temblorGrados : -TLSMovimiento.temblorGrados) : 0))
        .animation(editando && !reducir ? .easeInOut(duration: 0.18).repeatForever(autoreverses: true).delay(Double(posicion % 4) * 0.05) : .default,
                   value: temblor)
        .onChange(of: editando, initial: true) { _, e in temblor = e }
        .contextMenu { opciones }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(definicion.titulo)
        .accessibilityIdentifier("modulo.\(colocado.modulo.rawValue)")
        .tamanoMosaico(colocado.tamano)
    }

    private var siguiente: TamanoMosaico? {
        let t = definicion.tamanos
        guard t.count > 1, let i = t.firstIndex(of: colocado.tamano) else { return nil }
        return t[(i + 1) % t.count]
    }

    @ViewBuilder private var opciones: some View {
        Button("Ocultar del inicio", action: acciones.ocultar)
        if let s = siguiente {
            Button("Tamaño: \(colocado.tamano.nombre) · pasar a \(s.nombre)", action: acciones.siguienteTamano)
        } else {
            Button("Tamaño: \(colocado.tamano.nombre) · solo tiene este") {}.disabled(true)
        }
        Button(posicion == 0 ? "Mover antes · ya es el primero" : "Mover antes") { acciones.mover(-1) }.disabled(posicion == 0)
        Button(posicion == total - 1 ? "Mover después · ya es el último" : "Mover después") { acciones.mover(1) }
            .disabled(posicion == total - 1)
        Divider()
        Button("Editar inicio", action: acciones.editarInicio)
    }

    private var menu: some View {
        Menu { opciones } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(TLSPaleta.textoSecundario.color)
        .accessibilityLabel("Opciones de \(definicion.titulo)")
    }

    private var controlesEdicion: some View {
        HStack(spacing: 4) {
            Button { acciones.mover(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(posicion == 0)
                .help(posicion == 0 ? "Ya es el primero" : "Mover antes")
                .accessibilityLabel("Mover \(definicion.titulo) antes")
            Button { acciones.mover(1) } label: { Image(systemName: "chevron.right") }
                .disabled(posicion == total - 1)
                .help(posicion == total - 1 ? "Ya es el último" : "Mover después")
                .accessibilityLabel("Mover \(definicion.titulo) después")
            Button(action: acciones.ocultar) {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(TLSPaleta.textoSecundario.color))
            }
            .help("Ocultar del inicio")
            .accessibilityLabel("Ocultar \(definicion.titulo) del inicio")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(TLSPaleta.texto.color)
        .frame(minHeight: TLSAltura.objetivoMinimo)
    }

    private var pieEdicion: some View {
        HStack {
            Text(colocado.tamano.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            Spacer(minLength: 0)
            Button(action: acciones.siguienteTamano) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                    .background(Circle().fill(TLSPaleta.bandeja.color))
            }
            .buttonStyle(.plain)
            .disabled(siguiente == nil)
            .help(siguiente.map { "Pasar a \($0.nombre)" } ?? "Solo tiene este tamaño")
            .accessibilityLabel("Cambiar el tamaño de \(definicion.titulo). Ahora: \(colocado.tamano.nombre)")
        }
    }
}

// MARK: Contenidos

/// Una cifra con su línea, su estado (icono y palabra) y su enlace; sin dato, el porqué.
struct ModuloCifra: View {
    let cifra: CifraModulo
    let tamano: TamanoMosaico
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let c = cifra.cifra {
                Text(c)
                    .tlsTexto(tamano == .pequeno ? TLSTipo.cifraMedia : TLSTipo.cifraGrande)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let l = cifra.linea, !l.isEmpty {
                    Text(l).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: TLSEstado.sinDato.simbolo).foregroundStyle(TLSPaleta.sinDato.color).accessibilityHidden(true)
                    Text(cifra.vacio ?? "Sin dato.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { pastilla; Spacer(minLength: 0); enlace }
                VStack(alignment: .leading, spacing: 4) { pastilla; enlace }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var pastilla: some View {
        if cifra.cifra != nil, let e = cifra.estado, let p = cifra.palabra { PastillaEstado(e, palabra: p) }
    }

    @ViewBuilder private var enlace: some View {
        if let e = cifra.enlace {
            Button(e.titulo) { navegar(e.destino, modo: .automatico) }.tlsBoton(.enlace).fixedSize()
        }
    }
}

/// Ritmo por área: seis filas con su frase y su estado. Pulsar entra en el área.
struct ModuloRitmo: View {
    let filas: [RitmoArea]
    let tamano: TamanoMosaico
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.element.area) { i, r in
                if i > 0 { Divider().overlay(TLSPaleta.separador.color) }
                Button { navegar(.area(r.area), modo: .automatico) } label: {
                    HStack(spacing: TLSEspacio.e8) {
                        IconoArea(r.area.tlsArea, tamano: 20, atenuado: r.estado == .enReposo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.area.etiquetaNumerada).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                                .lineLimit(1)
                            if tamano != .mediano {
                                Text(r.frase).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        PastillaEstado(Self.estado(r.estado), palabra: r.estado.etiqueta)
                    }
                    .padding(.vertical, tamano == .mediano ? 2 : 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.area.etiquetaNumerada): \(r.estado.etiqueta). \(r.frase)")
            }
        }
    }

    static func estado(_ e: RitmoArea.Estado) -> TLSEstado {
        switch e {
        case .enRitmo: .bien
        case .atencion: .atencion
        case .enAlerta: .mal
        case .sinMeta, .sinDato, .enReposo: .sinDato
        }
    }
}

/// Tu semana: de lunes a domingo, una barra por día con sus horas frente al tope; el aviso con icono y texto.
struct ModuloSemana: View {
    let semana: SemanaAgenda

    var body: some View {
        let tope = max(semana.tope, 1)
        let alto = max(tope * 1.25, (semana.dias.map(\.horas).max() ?? 0) * 1.1)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(semana.dias) { d in
                    VStack(spacing: 4) {
                        Text(Self.textoHoras(d)).tlsTexto(TLSTipo.secundario.peso(d.esHoy ? 600 : 500))
                            .foregroundStyle(d.pasaDelTope ? TLSPaleta.atencion.color : TLSPaleta.texto.color)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(TLSPaleta.bandeja.color)
                                if !d.finDeSemana, d.tope > 0 {
                                    Rectangle().fill(TLSPaleta.bordeControl.color.opacity(0.7)).frame(height: 1)
                                        .offset(y: -geo.size.height * d.tope / alto)
                                }
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(d.pasaDelTope ? TLSPaleta.atencion.color : (d.esHoy ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color))
                                    .frame(height: d.horas > 0 ? max(4, geo.size.height * min(d.horas, alto) / alto) : 0)
                            }
                        }
                        .frame(minHeight: 40)
                        HStack(spacing: 2) {
                            if d.pasaDelTope {
                                Image(systemName: TLSEstado.atencion.simbolo).font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(TLSPaleta.atencion.color).accessibilityHidden(true)
                            }
                            Text(Self.dia(d)).tlsTexto(TLSTipo.secundario.peso(d.esHoy ? 700 : 500))
                                .foregroundStyle(d.esHoy ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(d.finDeSemana && d.tareas.isEmpty ? 0.6 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.etiqueta(d))
                }
            }
            .frame(maxHeight: .infinity)
            Text(Self.pie(semana)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
            if let aviso = semana.dias.compactMap(\.aviso).first {
                AvisoEnLinea(aviso, estado: .atencion)
            }
        }
    }

    static let cortos = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]

    static func dia(_ d: DiaAgenda) -> String { "\(cortos[d.dia.weekday - 1]) \(d.dia.day)" }

    /// «3,5 h», «Libre» (nada planificado, que no es lo mismo que 0) o «—» en fin de semana.
    static func textoHoras(_ d: DiaAgenda) -> String {
        if d.horas > 0 { return "\(FormatoBase.cifra(d.horas, decimales: d.horas == d.horas.rounded() ? 0 : 1)) h" }
        if d.sinEstimar > 0 { return d.sinEstimar == 1 ? "1 sin est." : "\(d.sinEstimar) sin est." }
        return d.finDeSemana ? "—" : "Libre"
    }

    static func etiqueta(_ d: DiaAgenda) -> String {
        var s = "\(HoyPantalla.diasLargos[d.dia.weekday - 1]) \(d.dia.day)\(d.esHoy ? ", hoy" : ""): "
        if d.finDeSemana && d.tareas.isEmpty { s += "fin de semana" } else if d.horas > 0 { s += d.textoCarga } else { s += "nada planificado" }
        if d.sinEstimar > 0 { s += ", \(d.sinEstimar) sin estimar" }
        if let a = d.aviso { s += ". \(a)" }
        return s
    }

    static func pie(_ s: SemanaAgenda) -> String {
        var p = "Tope de \(FormatoBase.cifra(s.tope)) h al día"
        if let d = s.diaDeHoy, !d.finDeSemana { p += d.horas > 0 ? " · hoy llevas \(d.textoCarga)" : " · hoy nada planificado" }
        if !s.atrasadas.isEmpty { p += " · " + (s.atrasadas.count == 1 ? "1 tarea atrasada" : "\(s.atrasadas.count) tareas atrasadas") }
        return p
    }
}

/// Lo que cabe hoy: lo que tiene hora, en orden, con la línea «Ahora»; después lo demás.
struct ModuloCabe: View {
    let elementos: [ElementoDia]
    let minutosAhora: Int
    let hora: String
    let tamano: TamanoMosaico
    let sesion: VaultSession?
    @State private var todas = false
    @Environment(\.navegar) private var navegar

    var limite: Int { tamano == .mediano ? 3 : (tamano == .ancho ? 4 : 8) }

    var body: some View {
        if elementos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hoy no tienes nada planificado").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text("Aquí salen las tareas planificadas para hoy, lo que vence hoy y las reuniones de tus fichas. Las citas del Calendario del Mac se verán aquí más adelante, cuando la app pueda leerlo.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            let vistos = todas ? elementos : Array(elementos.prefix(limite))
            let ahoraEn = vistos.firstIndex { ($0.minutos ?? Int.max) > minutosAhora } ?? vistos.firstIndex { $0.minutos == nil }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(vistos.enumerated()), id: \.element.id) { i, e in
                    if i == ahoraEn, vistos.contains(where: { $0.minutos != nil }) {
                        HStack(spacing: 6) {
                            Text(hora).tlsTexto(TLSTipo.secundario.peso(600)).foregroundStyle(TLSPaleta.texto.color)
                            MarcaAhora(.horizontal, palabra: "Ahora, \(hora)")
                        }
                        .frame(height: 16)
                    }
                    fila(e)
                }
                if elementos.count > limite {
                    Button(todas ? "Ver menos" : "Ver las \(elementos.count)") { todas.toggle() }.tlsBoton(.enlace)
                }
            }
        }
    }

    private func fila(_ e: ElementoDia) -> some View {
        Button {
            if let r = e.ruta { navegar(sesion?.destino(para: r) ?? .ficha(r), modo: .automatico) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Text(e.hora ?? "—").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                    HStack(spacing: 4) {
                        if let a = e.area { Text(a.etiquetaNumerada) }
                        Text("· \(e.tipo.texto)")
                        if let c = e.codigo { Text("· \(c)").font(TLSTipo.codigo.font()) }
                    }
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                }
                Spacer(minLength: 4)
                if e.venceHoy && e.tipo != .vence {
                    Label("vence hoy", systemImage: TLSEstado.atencion.simbolo).labelStyle(.titleAndIcon)
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.atencion.color)
                }
                Text(e.textoHoras ?? "sin estimar").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(e.ruta == nil)
        .accessibilityLabel([e.hora, e.titulo, e.tipo.texto, e.area?.etiquetaNumerada, e.textoHoras ?? "sin estimar",
                             e.venceHoy && e.tipo != .vence ? "vence hoy" : nil].compactMap { $0 }.joined(separator: ", "))
    }
}

/// El cuello en texto (Dirección).
struct ModuloCuello: View {
    let cuello: (texto: String, veredicto: String)?

    var body: some View {
        if let c = cuello {
            VStack(alignment: .leading, spacing: 6) {
                Text(c.texto).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(c.veredicto).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Sin dato: aún no hay números para ver qué área frena al resto.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
        }
    }
}
