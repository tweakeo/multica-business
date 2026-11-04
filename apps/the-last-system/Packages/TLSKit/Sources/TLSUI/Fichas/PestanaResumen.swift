import SwiftUI
import TLSCore
import TLSDesign

/// Pestaña Resumen (§3.2): mosaicos fijos por tipo: propiedades clave (6 como mucho, se cambian desde el
/// panel de propiedades), lo último (3 entradas de actividad), un minimosaico por relación con sus 3 primeras
/// filas y «Ver las N», y la frase literal del cliente si la hay, como cita.
struct PestanaResumen: View {
    let modelo: FichaModelo
    let irA: (String) -> Void
    @Environment(\.navegar) private var navegar

    /// Propiedades clave por tipo, en orden.
    static func claves(_ tipo: NoteKind) -> [String] {
        switch tipo {
        case .contact: ["email", "telefono", "cargo", "relacion", "canal", "creada"]
        case .organization: ["sector", "ciudad", "nif", "email_facturacion", "relacion", "canal"]
        case .opportunity: ["valor", "probabilidad", "siguiente_paso", "siguiente_fecha", "canal", "creada"]
        case .project: ["inicio", "fin", "fase", "responsable", "sesiones_incluidas", "franja"]
        case .meeting: ["fecha", "hora", "duracion_min", "lugar", "tipo", "grabacion"]
        case .service: ["precio", "codigo", "estado", "duracion", "sesiones_incluidas", "creada"]
        default: []
        }
    }

    @State private var ancho: CGFloat = 1000
    @FocusState private var foco: VaultPath?

    var body: some View {
        let grupos = gruposRelacionados
        let columnas = max(1, min(4, Int((ancho + TLSEspacio.entreMosaicos) / (230 + TLSEspacio.entreMosaicos))))
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            // Arriba: propiedades clave, lo último y, si la hay, la frase del cliente (como en M2-Contacto). Con
            // poco ancho, uno bajo otro.
            if ancho >= 760 {
                HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                    tarjetaPropiedades.frame(maxWidth: .infinity, maxHeight: .infinity)
                    tarjetaUltimo.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if cita != nil { tarjetaCita.frame(maxWidth: 320, maxHeight: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                tarjetaPropiedades
                tarjetaUltimo
                if cita != nil { tarjetaCita }
            }
            // Un minimosaico por relación, en filas de igual alto (nada se sale de su tarjeta).
            Grid(alignment: .topLeading, horizontalSpacing: TLSEspacio.entreMosaicos, verticalSpacing: TLSEspacio.entreMosaicos) {
                ForEach(Array(stride(from: 0, to: grupos.count, by: columnas)), id: \.self) { i in
                    GridRow {
                        ForEach(i..<min(i + columnas, grupos.count), id: \.self) { j in
                            minimosaico(grupos[j]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        // Huecos al final de la última fila, para que las columnas midan lo mismo.
                        ForEach(0..<max(0, i + columnas - grupos.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
    }

    private func tarjeta<C: View>(_ titulo: String, icono: String, pie: String? = nil, @ViewBuilder _ contenido: () -> C) -> some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: TLSEspacio.e8) {
                Image(systemName: icono).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                Text(titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
            }
            contenido()
            Spacer(minLength: 0)
            if let pie {
                Text(pie).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .padding(TLSEspacio.mosaicoPequeno)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
    }

    private var tarjetaPropiedades: some View {
        tarjeta("Propiedades clave", icono: "list.bullet.rectangle", pie: "Se cambian en Propiedades (⌥⌘I)") { propiedadesClave }
    }

    private var tarjetaUltimo: some View {
        tarjeta("Lo último", icono: "clock") { loUltimo }
    }

    @ViewBuilder
    private var tarjetaCita: some View {
        if let cita {
            tarjeta("Lo que quiere", icono: "quote.opening") {
                Text("«\(cita.texto)»").tlsTexto(TLSTipo.tituloSeccion.enItalica).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let de = cita.de {
                    Text(de).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
    }

    /// Por qué está vacío un grupo, cuando hay un motivo que contar (un vacío nunca es un «0» mudo, §2.2).
    static func porQueVacio(_ tipos: Set<NoteKind>, modelo: FichaModelo) -> String? {
        guard tipos.contains(.project), let g = modelo.grafo else { return nil }
        let aceptadas = modelo.relacionados([.opportunity]).map(\.ficha).filter { TextFolding.fold($0.estado ?? "") == "aceptada" }
        for o in aceptadas {
            let c = g.cobroConfirmado(oportunidad: o.ruta)
            guard !c.confirmado else { continue }
            let factura = modelo.relacionados([.invoice]).map(\.ficha).first { g.destinos(de: $0.ruta, propiedad: "oportunidad").contains(o.ruta) }
            let cual = factura.map { f in "de la factura \(f.numero ?? f.nombre)" + (FormatoFicha.euros(f.texto("total")).map { " (\($0))" } ?? "") } ?? "de su factura"
            return "Aún no hay proyecto. Nace cuando se confirme el cobro \(cual): así no se empieza a trabajar sin haber cobrado."
        }
        return nil
    }

    private var propiedadesClave: some View {
        let f = modelo.ficha
        let claves = Self.claves(modelo.tipo)
        let props: [(String, String)] = {
            guard let f else { return [] }
            if !claves.isEmpty {
                return claves.map { k in (k, f.texto(k).map { valorLegible(k, $0) } ?? "") }
            }
            return f.propiedades.properties.filter { !InspectorFicha.tecnicas.contains($0.key) && !EsquemaRelaciones.clavesDeRelacion.contains($0.key) }
                .prefix(6).map { ($0.key, valorLegible($0.key, $0.value.displayText)) }
        }()
        return Grid(alignment: .leading, horizontalSpacing: TLSEspacio.e12, verticalSpacing: 2) {
            ForEach(props, id: \.0) { k, v in
                GridRow {
                    Text(InspectorFicha.etiqueta(k)).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    if v.isEmpty {
                        Button("Añadir") { modelo.sesion.showInspector = true }
                            .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
                            .accessibilityLabel("Añadir \(InspectorFicha.etiqueta(k).lowercased())")
                    } else {
                        Text(v).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                    }
                }
                // Todas las filas con el alto del «Añadir» (28 pt), para que el ritmo sea el mismo.
                .frame(minHeight: TLSAltura.objetivoMinimo)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func valorLegible(_ clave: String, _ valor: String) -> String {
        if ["valor", "precio", "total", "base", "importe"].contains(clave), let e = FormatoFicha.euros(valor) { return e }
        if clave == "probabilidad" { return "\(valor) %" }
        if clave == "responsable" { return Responsables.nombre(de: valor) }
        if LocalDate(parsing: valor) != nil, valor.count == 10 { return FormatoFicha.fechaLegible(valor, hoy: modelo.hoy) }
        let texto = LinkParser.plainText(valor)
        return ["relacion", "canal", "estado", "origen", "tipo", "verificacion", "fase"].contains(clave) ? FormatoFicha.capital(texto) : texto
    }

    private var loUltimo: some View {
        let entradas = Array(ActividadDeFicha.leer(modelo.texto ?? "").prefix(3))
        return VStack(alignment: .leading, spacing: 6) {
            if entradas.isEmpty {
                Text("Aún no hay actividad apuntada.").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            ForEach(entradas) { e in
                HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                    Text(e.fecha.map { FormatoFicha.fechaCorta($0, hoy: modelo.hoy) } ?? "")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(width: 48, alignment: .leading)
                    Text(e.texto + (e.autor.map { " · \($0)" } ?? "")).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
            Button("Ver la actividad") { irA("Actividad") }
                .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo)
        }
    }

    /// La frase del cliente: `frase_destino` o la primera cita de «Lo que le importa» / «Resultado prometido».
    private var cita: (texto: String, de: String?)? {
        if let f = modelo.ficha?.texto("frase_destino") { return (f, "Frase destino") }
        guard let cuerpo = modelo.cuerpo else { return nil }
        for s in ["Lo que le importa", "Resultado prometido", "Lo que nos contaste"] {
            guard let c = MarkdownSections.content(of: s, in: cuerpo) else { continue }
            for l in c.components(separatedBy: "\n") {
                var t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("> Guía:") { continue }
                if t.hasPrefix("- ") { t.removeFirst(2) }
                if t.hasPrefix("> ") { t.removeFirst(2) }
                if let c = Self.citaEntreComillas(t) { return (LinkParser.plainText(c.cita), c.resto.isEmpty ? s : LinkParser.plainText(c.resto)) }
                t = t.trimmingCharacters(in: CharacterSet(charactersIn: "«»\"“” "))
                if !t.isEmpty { return (LinkParser.plainText(t), s) }
            }
        }
        return nil
    }

    /// «Que en enero no me tenga que acordar de nada.» Frase destino de Jorge… → la cita y lo que sigue (quién y
    /// cuándo). `nil` si la línea no empieza con comillas.
    nonisolated static func citaEntreComillas(_ t: String) -> (cita: String, resto: String)? {
        let pares: [(Character, Character)] = [("«", "»"), ("“", "”"), ("\"", "\"")]
        guard let primera = t.first, let par = pares.first(where: { $0.0 == primera }) else { return nil }
        let dentro = t.dropFirst()
        guard let cierre = dentro.firstIndex(of: par.1) else { return nil }
        let cita = String(dentro[..<cierre]).trimmingCharacters(in: .whitespaces)
        let resto = String(dentro[dentro.index(after: cierre)...]).trimmingCharacters(in: CharacterSet(charactersIn: " .·—-"))
        return cita.isEmpty ? nil : (cita, resto)
    }

    private struct Grupo {
        let titulo: String
        let tipos: Set<NoteKind>
        let filas: [Relacionado]
        let nueva: OpcionNuevo?
    }

    private var gruposRelacionados: [Grupo] {
        modelo.configuracion.pestanas.compactMap { d in
            guard case .relacionados(let tipos) = d.contenido else {
                if case .tareasProyecto = d.contenido { return Grupo(titulo: d.titulo, tipos: [.task], filas: modelo.relacionados([.task]), nueva: nil) }
                return nil
            }
            let filas = modelo.relacionados(tipos)
            let nueva = modelo.configuracion.nuevo.first { tipos.contains($0.tipo) }
            if filas.isEmpty && !d.siempre { return nil }
            return Grupo(titulo: d.titulo, tipos: tipos, filas: filas, nueva: nueva)
        }
    }

    /// Un minimosaico (M2-Contacto): el tipo con lo abierto en grande a la derecha, sus 3 primeras filas (lo urgente
    /// primero) con su estado en palabra, y al pie «Ver las N» y «+ Nueva …». Vacío, dice por qué.
    private func minimosaico(_ g: Grupo) -> some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        let abiertas = g.filas.filter { EstadosDeFicha.abierta($0.ficha.tipo, estado: $0.ficha.estado) }.count
        let icono = (g.tipos.contains(.proposal) ? NoteKind.proposal : g.tipos.sorted { $0.rawValue < $1.rawValue }.first)?.systemImage ?? "tray"
        return VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: TLSEspacio.e8) {
                Image(systemName: icono).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(TLSPaleta.bandeja.color))
                    .accessibilityHidden(true)
                Rotulo(g.titulo)
                Spacer(minLength: 0)
                if abiertas > 0 {
                    Text("\(abiertas)").tlsTexto(TLSTipo.tituloSeccion).monospacedDigit().foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityLabel(abiertas == 1 ? "1 abierta" : "\(abiertas) abiertas")
                }
            }
            .frame(height: 26)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if g.filas.isEmpty {
                Text(PestanaResumen.porQueVacio(g.tipos, modelo: modelo) ?? "Sin \(g.titulo.lowercased()) todavía.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(g.filas.prefix(3).enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider().overlay(TLSPaleta.separador.color) }
                    filaMini(r)
                }
            }
            Spacer(minLength: 0)
            FlujoChips(espacio: 6) {
                if !g.filas.isEmpty {
                    Button(g.filas.count == 1 ? "Ver" : "Ver las \(g.filas.count)") { irA(g.titulo) }
                        .tlsBoton(.secundario)
                }
                if let n = g.nueva {
                    Button { modelo.nuevo = n } label: { Label(n.nuevoTitulo, systemImage: "plus") }
                        .tlsBoton(.secundario)
                        .disabled(!modelo.puedeEscribir)
                        .help(modelo.motivoSoloLectura.map { "No se puede crear: \($0)" } ?? "Nace ya enlazada")
                }
            }
        }
        .padding(TLSEspacio.mosaicoPequeno)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(g.titulo)
    }

    /// Una fila del minimosaico: el nombre y, debajo, el estado en palabra con su icono y el contexto.
    private func filaMini(_ r: Relacionado) -> some View {
        let f = r.ficha
        let contexto = modelo.grafo.map { EdicionRelaciones.contexto(f, grafo: $0, hoy: modelo.hoy) } ?? ""
        let estado = f.estado.map { FormatoFicha.tlsEstado(f.tipo, $0, hoy: modelo.hoy, vence: EstadosDeFicha.fecha(f).flatMap { d in f.texto("vence") != nil ? d : nil }) }
        // El contexto ya lleva el estado al final («150 € · Aceptada»): aquí va aparte, con su icono.
        let sinEstado = f.estado.map { e in contexto.hasSuffix(FormatoFicha.capital(e)) ? String(contexto.dropLast(FormatoFicha.capital(e).count)).trimmingCharacters(in: CharacterSet(charactersIn: " ·")) : contexto } ?? contexto
        return Button { navegar(modelo.sesion.destino(para: f.ruta)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if let estado, let e = f.estado {
                        Image(systemName: estado.simbolo).font(.system(size: 10, weight: .semibold)).foregroundStyle(estado.color.color)
                        Text(FormatoFicha.capital(e)).tlsTexto(TLSTipo.secundario.peso(600)).foregroundStyle(TLSPaleta.texto.color)
                    }
                    if !sinEstado.isEmpty {
                        Text((f.estado == nil ? "" : "· ") + sinEstado).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .lineLimit(1)
                    }
                    if EstadosDeFicha.esperaTuOK(f.tipo, estado: f.estado) { PuntoNovedad(palabra: "Espera tu OK") }
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: TLSAltura.filaLista, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($foco, equals: f.ruta)
        .focusEffectDisabled()
        .tlsAnilloFoco(foco == f.ruta, radio: TLSRadio.fila)
        .contextMenu {
            Button("Abrir") { navegar(modelo.sesion.destino(para: f.ruta), modo: .entrar) }
            Button("Abrir en pestaña nueva") { navegar(modelo.sesion.destino(para: f.ruta), modo: .pestanaNueva) }
            Button("Vista previa") { modelo.sesion.navegacionActiva?.vistaPrevia = f.ruta }
        }
        .vistaPrevia(ruta: f.ruta, sesion: modelo.sesion)
        .accessibilityLabel([f.tipo.etiqueta + " " + f.nombre, f.estado, sinEstado].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
