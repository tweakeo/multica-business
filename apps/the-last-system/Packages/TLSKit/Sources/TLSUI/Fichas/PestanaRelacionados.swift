import SwiftUI
import TLSCore
import TLSDesign

/// Una pestaña de lo relacionado por tipo (§3.2): Lista por defecto o Tabla, lo abierto y lo urgente primero y
/// lo cerrado plegado al final («Cerradas (4)»). Arriba a la derecha, «+ Nueva …» (nace enlazada), «Añadir
/// existente…» (selector, escribe en la otra ficha) y «Ver en la base». Cada fila: clic entra, puntero o barra
/// espaciadora para la vista previa, menú con «Quitar de <esta ficha>».
struct PestanaRelacionados: View {
    let modelo: FichaModelo
    let titulo: String
    let tipos: Set<NoteKind>
    /// Solo lo que cuelga por esta propiedad (subtareas: `padre`).
    var soloPropiedad: String? = nil
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav
    @State private var verCerradas = false
    @State private var enTabla = false

    var body: some View {
        let todas = lista
        let abiertas = todas.filter { EstadosDeFicha.abierta($0.ficha.tipo, estado: $0.ficha.estado) }
        let cerradas = todas.filter { !EstadosDeFicha.abierta($0.ficha.tipo, estado: $0.ficha.estado) }
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .center, spacing: TLSEspacio.e8) {
                Text("\(titulo) · \(modelo.ficha?.nombre ?? "")").tlsTexto(TLSTipo.tituloModulo)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Ver como", selection: $enTabla) {
                    Text("Lista").tag(false)
                    Text("Tabla").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if let opcion = opcionNueva {
                    Button(opcion.nuevoTitulo) { modelo.nuevo = opcion }
                        .tlsBoton(.principal, alto: 36)
                        .disabled(!modelo.puedeEscribir)
                }
                if puedeAnadirExistente {
                    Button("Añadir existente…") { modelo.abrirSelectorInverso(tipos: tipos) }
                        .tlsBoton(.secundario)
                        .disabled(!modelo.puedeEscribir)
                        .popover(item: Binding(get: { modelo.selector.flatMap { esInverso($0) ? $0 : nil } },
                                               set: { if $0 == nil { modelo.selector = nil } }), arrowEdge: .bottom) { p in
                            SelectorRelacion(peticion: p, sesion: modelo.sesion, almacen: modelo.almacen,
                                             alElegir: { d in Task { await modelo.elegido(d, en: p, navegar: navegar) } },
                                             alQuitar: {}, alCrear: { _ in }, alListo: { _ in })
                        }
                }
                if let base = baseDeTipo {
                    Button("Ver en la base") { navegar(.base(base, contexto: modelo.ruta), modo: .entrar) }
                        .tlsBoton(.secundario)
                }
            }
            if todas.isEmpty {
                VacioExplicado(icono: tipos.first?.systemImage ?? "tray", titulo: "Sin \(titulo.lowercased())",
                               porQue: porQueVacio, accion: opcionNueva?.nuevoTitulo,
                               alPulsar: opcionNueva.map { o in { modelo.nuevo = o } }, compacto: true)
            } else if enTabla {
                tabla(abiertas + (verCerradas ? cerradas : []))
                if !cerradas.isEmpty { botonCerradas(cerradas.count) }
            } else {
                VStack(spacing: 2) {
                    ForEach(abiertas) { r in fila(r) }
                }
                if !cerradas.isEmpty {
                    botonCerradas(cerradas.count)
                    if verCerradas {
                        VStack(spacing: 2) { ForEach(cerradas) { r in fila(r) } }
                    }
                }
            }
            Text(pie).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .onAppear { enTabla = nav?.recuerdo(de: .ficha(modelo.ruta)).extra["vista.\(titulo)"] == "tabla" }
        .onChange(of: enTabla) { nav?.actualizarRecuerdo(de: .ficha(modelo.ruta)) { $0.extra["vista.\(titulo)"] = enTabla ? "tabla" : "lista" } }
    }

    private var lista: [Relacionado] {
        let l = modelo.relacionados(tipos)
        guard let p = soloPropiedad else { return l }
        return l.filter { $0.via == .directa(propiedad: p) }
    }

    private func esInverso(_ p: PeticionSelector) -> Bool {
        // El selector puede llevar menos tipos que la pestaña (solo los que guardan la relación con esta ficha).
        if case .inverso = p.modo { return !p.tipos.isEmpty && p.tipos.isSubset(of: tipos) }
        return false
    }

    private var opcionNueva: OpcionNuevo? {
        modelo.configuracion.nuevo.first { tipos.contains($0.tipo) }
    }

    private var puedeAnadirExistente: Bool {
        guard let t = modelo.ficha?.tipo, soloPropiedad == nil else { return soloPropiedad != nil }
        return tipos.contains { EsquemaRelaciones.quienGuarda(apuntandoA: t, desde: $0) != nil }
    }

    /// La base de ese tipo («Ver en la base», filtrada por esta ficha).
    private var baseDeTipo: String? {
        let mapa: [NoteKind: String] = [.contact: "contactos", .organization: "empresas", .opportunity: "oportunidades",
                                        .meeting: "reuniones", .proposal: "propuestas", .quote: "propuestas", .project: "proyectos",
                                        .invoice: "facturas", .task: "tareas", .incident: "incidencias", .conversation: "conversaciones",
                                        .content: "contenidos", .receipt: "cobros", .draft: "borradores", .procedure: "sistemas"]
        return tipos.compactMap { mapa[$0] }.sorted().first
    }

    private var porQueVacio: String {
        if let motivo = PestanaResumen.porQueVacio(tipos, modelo: modelo) { return motivo }
        let nombre = modelo.ficha?.nombre ?? "esta ficha"
        if let p = opcionNueva { return "Aún no hay \(titulo.lowercased()) de \(nombre). Con «\(p.nuevoTitulo)» nace ya enlazada." }
        return "Aún no hay \(titulo.lowercased()) de \(nombre)."
    }

    private var pie: String {
        guard let t = modelo.ficha?.tipo, let principal = tipos.sorted(by: { $0.rawValue < $1.rawValue }).first,
              let def = EsquemaRelaciones.quienGuarda(apuntandoA: t, desde: principal) else {
            return "Pulsa una fila para entrar. Barra espaciadora o puntero encima: vista previa."
        }
        return "Cada una guarda esta relación en «\(def.propiedad)»: añadir o quitar desde aquí escribe allí, una línea. Pulsa una fila para entrar."
    }

    private func botonCerradas(_ n: Int) -> some View {
        Button {
            verCerradas.toggle()
        } label: {
            Label(verCerradas ? "Ocultar las cerradas" : "Cerradas (\(n))", systemImage: verCerradas ? "chevron.down" : "chevron.right")
        }
        .tlsBoton(.discreto)
    }

    private func fila(_ r: Relacionado) -> some View {
        let f = r.ficha
        let hoy = modelo.hoy
        let detalle = detalleFila(r)
        return FilaLista(f.nombre, detalle: detalle, icono: f.tipo.systemImage,
                         etiquetaAccesible: [f.tipo.etiqueta + " " + f.nombre, detalle, f.estado].compactMap { $0 }.joined(separator: ", "),
                         accion: { navegar(modelo.sesion.destino(para: f.ruta)) }) {
            HStack(spacing: TLSEspacio.e8) {
                if EstadosDeFicha.esperaTuOK(f.tipo, estado: f.estado) {
                    InsigniaAviso(nil, palabra: "Espera tu OK")
                }
                if let e = f.estado {
                    let v = EstadosDeFicha.fecha(f)
                    PastillaEstado(FormatoFicha.tlsEstado(f.tipo, e, hoy: hoy, vence: f.texto("vence") != nil ? v : nil),
                                   palabra: FormatoFicha.capital(e))
                }
            }
        }
        .vistaPrevia(ruta: f.ruta, sesion: modelo.sesion)
        .contextMenu { menuFila(r) }
    }

    private func detalleFila(_ r: Relacionado) -> String {
        let f = r.ficha
        var partes = [modelo.grafo.map { EdicionRelaciones.contexto(f, grafo: $0, hoy: modelo.hoy) } ?? ""]
            .filter { !$0.isEmpty }
        if let d = EstadosDeFicha.fecha(f), f.texto("vence") != nil || f.texto("fecha") != nil {
            partes.append(FormatoFicha.fechaConDia(d, hoy: modelo.hoy))
        }
        switch r.via {
        case .indirecta(let por, _):
            partes.append("por \(modelo.grafo?.ficha(por)?.nombre ?? por.stem)")
        case .porCarpeta:
            partes.append("en su carpeta")
        case .directa:
            break
        }
        return partes.joined(separator: " · ")
    }

    @ViewBuilder
    private func menuFila(_ r: Relacionado) -> some View {
        let destino = modelo.sesion.destino(para: r.ficha.ruta)
        Button("Abrir") { navegar(destino, modo: .entrar) }
        Button("Abrir en pestaña nueva") { navegar(destino, modo: .pestanaNueva) }
        Button("Abrir en ventana nueva") { navegar(destino, modo: .ventanaNueva) }
        Button("Vista previa") { nav?.vistaPrevia = r.ficha.ruta }
        Button("Copiar enlace") {
            if let e = modelo.sesion.enlaceParaCopiar(destino) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(e, forType: .string)
            }
        }
        Divider()
        switch r.via {
        case .directa(let p):
            let motivo = EsquemaRelaciones.definicion(tipo: r.ficha.tipo, propiedad: p)?.motivoObligatoria(r.ficha.propiedades)
            Button("Quitar de \(modelo.ficha?.nombre ?? "esta ficha")") { Task { await modelo.quitarRelacionado(r) } }
                .disabled(motivo != nil || !modelo.puedeEscribir)
            if let motivo { Text(motivo) }
        case .indirecta(let por, _):
            Text("Sale por \(modelo.grafo?.ficha(por)?.nombre ?? por.stem): se quita desde allí")
        case .porCarpeta:
            Text("Vive en la carpeta de este proyecto")
        }
    }

    private func tabla(_ filas: [Relacionado]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: TLSEspacio.e16, verticalSpacing: 0) {
            GridRow {
                Rotulo("Nombre")
                Rotulo("Estado")
                Rotulo("Fecha")
                Rotulo("Importe")
            }
            .frame(minHeight: TLSAltura.cabeceraTabla)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(filas) { r in
                let f = r.ficha
                GridRow {
                    Button(f.nombre) { navegar(modelo.sesion.destino(para: f.ruta)) }
                        .buttonStyle(.plain)
                        .tlsTexto(TLSTipo.interfazFuerte)
                        .foregroundStyle(TLSPaleta.enlace.color)
                        .vistaPrevia(ruta: f.ruta, sesion: modelo.sesion)
                        .contextMenu { menuFila(r) }
                    Text(f.estado.map(FormatoFicha.capital) ?? "—").tlsTexto(TLSTipo.interfaz)
                    Text(EstadosDeFicha.fecha(f).map { FormatoFicha.fechaCorta($0, hoy: modelo.hoy) } ?? "—").tlsTexto(TLSTipo.cifraFila)
                    Text(FormatoFicha.euros(f.texto("total") ?? f.texto("valor")) ?? "—").tlsTexto(TLSTipo.cifraFila)
                }
                .foregroundStyle(TLSPaleta.texto.color)
                .frame(minHeight: TLSAltura.filaTabla)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
