import SwiftUI
import TLSCore
import TLSDesign

/// Un bloqueo al soltar una tarjeta (VEN-07): qué oportunidad, por qué y qué se ofrece.
struct BloqueoCRM: Equatable {
    let tarjeta: TarjetaCRM
    let mensaje: String
    let alternativa: AlternativaCRM?
}

/// El CRM en tablero (PLAN §6.5): Prospecto → Diagnóstico → Propuesta → Aceptada → Ganada, con número, euros y
/// conversión en cada columna y «quieta 9 d» en las tarjetas. Arrastrar cambia solo `estado`; sin arrastrar,
/// «Mover a…», ⌘← ⌘→ y las acciones de VoiceOver. Soltar en Ganada sin un cobro confirmado por una persona se bloquea
/// (VEN-07) con su mensaje y «Dejarla en Aceptada».
struct TableroCRMVista: View {
    let tablero: TableroCRM
    let empresa: UUID
    let motivoSoloLectura: String?
    let bloqueo: BloqueoCRM?
    let alMover: (TarjetaCRM, EtapaCRM) -> Void
    let alAbrir: (TarjetaCRM) -> Void
    let alAlternativa: (BloqueoCRM) -> Void
    let alCerrarBloqueo: () -> Void

    @State private var encima: EtapaCRM?
    @FocusState private var enfocada: VaultPath?

    static let anchoColumna: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if let b = bloqueo { avisoBloqueo(b) }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: TLSEspacio.e12) {
                    ForEach(tablero.columnas) { c in columna(c) }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)
            if !tablero.perdidas.isEmpty || !tablero.pausadas.isEmpty {
                apartadas
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ventas.crm")
        .tutorialAnchor(.ventasCRM)
    }

    private func avisoBloqueo(_ b: BloqueoCRM) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Label {
                Text("«\(b.tarjeta.nombre)» no pasa a Ganada. \(b.mensaje)").tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(TLSEstado.mal.color.color)
            }
            HStack(spacing: TLSEspacio.e8) {
                if let a = b.alternativa {
                    Button(a.titulo) { alAlternativa(b) }
                        .tlsBoton(.principal, alto: 32)
                        .disabled(motivoSoloLectura != nil)
                        .accessibilityIdentifier("crm.alternativa")
                }
                Button("Cerrar") { alCerrarBloqueo() }.tlsBoton(.secundario, alto: 32)
            }
        }
        .padding(TLSEspacio.e12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSEstado.atencion.tinte.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No se puede mover: \(b.mensaje)")
        .accessibilityIdentifier("crm.bloqueo")
    }

    private func columna(_ c: ColumnaCRM) -> some View {
        let objetivo = encima == c.etapa
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.etapa.rawValue).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Spacer(minLength: 4)
                    Text("\(c.numero)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Text(c.textoTotal).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                Text(c.textoConversion).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                if c.etapa == .ganada {
                    Label("Solo con un cobro confirmado", systemImage: "lock").tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(c.etiquetaAccesible)
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                ForEach(c.tarjetas) { t in tarjeta(t) }
                if c.tarjetas.isEmpty {
                    Text("Ninguna").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(TLSEspacio.e12)
        .frame(width: Self.anchoColumna, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .strokeBorder(objetivo ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { ids, _ in
            guard motivoSoloLectura == nil, let texto = ids.first, let r = ArrastreFila.id(texto, empresa: empresa),
                  let t = tablero.tarjeta(VaultPath(r)) else { return false }
            alMover(t, c.etapa)
            return true
        } isTargeted: { dentro in
            if dentro { encima = c.etapa } else if encima == c.etapa { encima = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("crm.columna.\(c.etapa.rawValue)")
    }

    private func tarjeta(_ t: TarjetaCRM) -> some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        let detalle = [t.empresa, t.servicio].compactMap { $0 }.joined(separator: " · ")
        let etapa = EtapaCRM(t.estado)
        return VStack(alignment: .leading, spacing: 4) {
            Text(t.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            if !detalle.isEmpty {
                Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
            Text(t.cifras).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
            HStack(spacing: 6) {
                if let q = t.textoQuieta { PastillaEstado(.atencion, palabra: q) }
                Spacer(minLength: 0)
                menuMover(t)
            }
        }
        .padding(TLSEspacio.e12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .overlay(forma.strokeBorder(enfocada == t.ruta ? TLSPaleta.principal.color : .clear, lineWidth: 2))
        .contentShape(forma)
        .focusable()
        .focused($enfocada, equals: t.ruta)
        .tlsFocoPropio(radio: TLSRadio.tarjeta)
        .onTapGesture(count: 2) { alAbrir(t) }
        .onTapGesture { enfocada = t.ruta }
        .onKeyPress(.return) { alAbrir(t); return .handled }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { tecla in
            guard tecla.modifiers.contains(.command), motivoSoloLectura == nil, let e = etapa else { return .ignored }
            if let destino = tecla.key == .leftArrow ? e.anterior : e.siguiente { alMover(t, destino) }
            return .handled
        }
        .draggable(ArrastreFila.texto(t.ruta.raw, empresa: empresa)) {
            Text(t.nombre).tlsTexto(TLSTipo.interfazFuerte).padding(10)
                .background(forma.fill(TLSPaleta.superficieElevada.color))
        }
        .contextMenu {
            Button("Abrir") { alAbrir(t) }
            Menu("Mover a") { opcionesMover(t) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([t.nombre, t.estado?.rawValue, detalle.isEmpty ? nil : detalle, t.cifras, t.textoQuieta].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if motivoSoloLectura == nil {
                ForEach(EtapaCRM.allCases.filter { $0 != etapa }, id: \.self) { e in
                    Button("Mover a \(e.rawValue)") { alMover(t, e) }
                }
            }
            Button("Abrir") { alAbrir(t) }
        }
        .accessibilityIdentifier("crm.tarjeta.\(t.ruta.raw)")
    }

    private func menuMover(_ t: TarjetaCRM) -> some View {
        Menu { opcionesMover(t) } label: {
            Text("Mover a…").tlsTexto(TLSTipo.secundario).underline()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(TLSPaleta.enlace.color)
        .fixedSize()
        .frame(minHeight: TLSAltura.objetivoMinimo)
        .disabled(motivoSoloLectura != nil)
        .help(motivoSoloLectura ?? "Cambiar de columna (⌘← ⌘→)")
        .accessibilityLabel("Mover \(t.nombre) a otra columna")
    }

    @ViewBuilder
    private func opcionesMover(_ t: TarjetaCRM) -> some View {
        let etapa = EtapaCRM(t.estado)
        ForEach(EtapaCRM.allCases.filter { $0 != etapa }, id: \.self) { e in
            Button(e == .ganada ? "Ganada (solo con un cobro confirmado)" : e.rawValue) { alMover(t, e) }
        }
        if let m = motivoSoloLectura { Divider(); Text(m) }
    }

    private var apartadas: some View {
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            lista("Perdidas", tablero.perdidas)
            lista("Pausadas", tablero.pausadas)
        }
    }

    @ViewBuilder
    private func lista(_ titulo: String, _ tarjetas: [TarjetaCRM]) -> some View {
        if !tarjetas.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(titulo) · \(tarjetas.count)").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                ForEach(tarjetas) { t in
                    FilaLista(t.nombre, detalle: t.cifras, accion: { alAbrir(t) }) { menuMover(t) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Seguimiento a 7, 14, 21 y 30 días de cada propuesta enviada: lo que toca hoy y «Preparar seguimiento» (deja el
/// borrador en una tarea; enviar, nunca).
struct SeguimientoVista: View {
    let seguimientos: [SeguimientoPropuesta]
    let hoy: LocalDate
    let motivoSoloLectura: String?
    let alPreparar: (SeguimientoPropuesta, Int) -> Void
    let alAbrir: (VaultPath) -> Void

    var body: some View {
        if seguimientos.isEmpty {
            Text("Ninguna propuesta espera respuesta. El seguimiento empieza cuando una oportunidad pasa a Propuesta con su propuesta enviada.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(seguimientos.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                    fila(s)
                }
            }
            .accessibilityIdentifier("ventas.seguimiento")
        }
    }

    private func fila(_ s: SeguimientoPropuesta) -> some View {
        let enviada = s.dias == 0 ? "Propuesta enviada hoy"
            : "Propuesta enviada el \(FormatoFicha.fechaCorta(s.enviada, hoy: hoy)) · hace \(s.dias == 1 ? "1 día" : "\(s.dias) días")"
        let siguiente = s.proximo.map { "Siguiente: día \($0.dia), el \(FormatoFicha.fechaConDia($0.fecha, hoy: hoy))" }
        let hechos = s.preparados.isEmpty ? nil : "Preparado: día " + s.preparados.map(String.init).joined(separator: ", ")
        return HStack(alignment: .center, spacing: TLSEspacio.e12) {
            Button { alAbrir(s.oportunidad) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text([enviada, hechos, siguiente].compactMap { $0 }.joined(separator: " · "))
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                    if let d = s.toca {
                        Text(SeguimientoPropuesta.queToca(d)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let d = s.toca {
                PastillaEstado(.atencion, palabra: "Toca el día \(d)")
                Button("Preparar seguimiento") { alPreparar(s, d) }
                    .tlsBoton(.secundario)
                    .disabled(motivoSoloLectura != nil)
                    .help(motivoSoloLectura ?? "Crea una tarea con el borrador del mensaje. Enviarlo es cosa tuya.")
                    .accessibilityIdentifier("seguimiento.preparar.\(s.oportunidad.raw)")
            } else {
                PastillaEstado(.sinDato, palabra: s.proximo == nil ? "Sin más seguimientos" : "Aún no toca")
            }
        }
        .padding(.vertical, TLSEspacio.e8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel([s.nombre, enviada, hechos, siguiente, s.toca.map { "Toca el seguimiento del día \($0)" }]
            .compactMap { $0 }.joined(separator: ". "))
    }
}

/// Contactos y empresas por estado, con el camino a sus bases.
struct DirectorioVentasVista: View {
    let contactos: DirectorioVentas
    let empresas: DirectorioVentas
    @Environment(\.navegar) private var navegar

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) { bloques }
            VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) { bloques }
        }
        .accessibilityIdentifier("ventas.directorio")
    }

    @ViewBuilder
    private var bloques: some View {
        bloque("Contactos", contactos, base: "contactos", icono: "person.crop.circle")
        bloque("Empresas", empresas, base: "empresas", icono: "building.2")
    }

    private func bloque(_ titulo: String, _ d: DirectorioVentas, base: String, icono: String) -> some View {
        BloqueOperacion(titulo, detalle: d.total == 0 ? "Ninguno todavía" : (d.total == 1 ? "1 en la carpeta" : "\(d.total) en la carpeta"),
                        acciones: {
            Button("Abrir la base") { navegar(.base(base), modo: .entrar) }
                .tlsBoton(.secundario)
                .accessibilityLabel("Abrir la base de \(titulo.lowercased())")
        }) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(d.porEstado) { e in
                    HStack {
                        Image(systemName: icono).foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                        Text(e.estado).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        Spacer()
                        Text("\(e.numero)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
