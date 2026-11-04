import SwiftUI
import TLSCore
import TLSDesign

/// Un inicio con sus módulos (Hoy y el Resumen de cada área; DISENO §6): «N de 8 módulos», «Añadir» (la galería) y
/// «Editar inicio». En modo edición tiemblan (con «Reducir movimiento», borde discontinuo), se arrastran para ordenarlos
/// o se sueltan en «Ocultos del inicio», y cada uno tiene «−», ← → y su tamaño: todo lo que se hace arrastrando se
/// puede hacer con botones, con el menú «…» o el clic derecho, y con VoiceOver.
struct InicioModulos: View {
    let inicio: InicioID
    let datos: DatosModulos?
    let sesion: VaultSession
    let titulo: String
    var hora: String = ""
    var minutosAhora: Int = 0
    @State private var galeria = false
    @State private var encima: ModuloID?
    @State private var bandejaEncima = false
    @Environment(\.navegar) private var navegar

    private var almacen: AlmacenInicios { AlmacenInicios.de(sesion) }
    private var disposicion: DisposicionInicio { almacen.disposicion(inicio) }
    /// Modo edición de este inicio (lo guarda el almacén: sigue así si vas y vuelves).
    private var editando: Bool {
        get { almacen.editando.contains(inicio.clave) }
        nonmutating set { almacen.alternarEdicion(inicio, newValue) }
    }

    var body: some View {
        let d = disposicion
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            cabecera(d)
            if editando {
                Text("Arrastra un módulo para moverlo, o suéltalo en «Ocultos del inicio». «−» lo oculta y el botón de tamaño lo cambia. Sin arrastrar: las flechas de cada módulo.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if d.visibles.isEmpty {
                VacioExplicado(icono: "square.grid.2x2", titulo: "Tu inicio está vacío",
                               porQue: "Pulsa «Añadir» o devuelve un módulo desde «Ocultos del inicio».",
                               accion: "Añadir un módulo", alPulsar: { galeria = true }, compacto: true)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            } else {
                MosaicoLayout(altoFila: 212) {
                    ForEach(Array(d.visibles.enumerated()), id: \.element.modulo) { i, c in
                        modulo(c, posicion: i, total: d.visibles.count)
                    }
                }
            }
            if editando { ocultos(d) }
        }
        .sheet(isPresented: $galeria) {
            GaleriaModulos(inicio: inicio, almacen: almacen) { galeria = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inicio.\(inicio.clave)")
    }

    // MARK: Cabecera

    private func cabecera(_ d: DisposicionInicio) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
            Text(titulo).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color).accessibilityAddTraits(.isHeader)
            Text("\(d.visibles.count) de \(DisposicionInicio.maximo) módulos").tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
            if !editando, !d.ocultos.isEmpty {
                Button(d.ocultos.count == 1 ? "1 oculto" : "\(d.ocultos.count) ocultos") { editando = true }.tlsBoton(.enlace)
            }
            Spacer(minLength: 0)
            Button {
                galeria = true
            } label: {
                Label("Añadir", systemImage: "plus")
            }
            .tlsBoton(.secundario)
            .accessibilityIdentifier("inicio.anadir")
            Button(editando ? "Listo" : "Editar inicio") { withAnimation(TLSMovimiento.muelle) { editando.toggle() } }
                .tlsBoton(editando ? .principal : .secundario)
                .accessibilityIdentifier("inicio.editar")
        }
    }

    // MARK: Módulos

    private func acciones(_ c: ModuloColocado) -> AccionesModulo {
        let titulo = CatalogoModulos.definicion(c.modulo).titulo
        return AccionesModulo(
            ocultar: { almacen.cambiar(inicio, aviso: "Ocultaste «\(titulo)» del inicio") { $0.ocultar(c.modulo) } },
            mover: { paso in almacen.cambiar(inicio) { $0.mover(c.modulo, paso) } },
            siguienteTamano: { almacen.cambiar(inicio) { $0.siguienteTamano(c.modulo) != nil } },
            editarInicio: { editando = true })
    }

    @ViewBuilder
    private func modulo(_ c: ModuloColocado, posicion: Int, total: Int) -> some View {
        let marco = MarcoModulo(colocado: c, posicion: posicion, total: total, editando: editando, pie: pie(c),
                                acciones: acciones(c)) {
            contenido(c)
        }
        if editando {
            marco
                .overlay {
                    if encima == c.modulo {
                        RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
                            .strokeBorder(TLSPaleta.principal.color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .draggable(c.modulo.rawValue) {
                    Text(CatalogoModulos.definicion(c.modulo).titulo).tlsTexto(TLSTipo.interfazFuerte).padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(TLSPaleta.superficieElevada.color))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first.flatMap(ModuloID.init(rawValue:)) else { return false }
                    return almacen.cambiar(inicio) { $0.mover(id, aLaPosicionDe: c.modulo) }
                } isTargeted: { dentro in
                    encima = dentro ? c.modulo : (encima == c.modulo ? nil : encima)
                }
        } else {
            marco
        }
    }

    private func pie(_ c: ModuloColocado) -> String? {
        guard let datos else { return nil }
        switch c.modulo {
        case .caja: return datos.caja.fuente
        case .ritmo: return "Sale del número clave de cada área"
        case .semana: return "Sale de tus tareas, reuniones y rutinas"
        case .cabe: return "Sale de tus tareas, reuniones y rutinas de hoy"
        case .cuello: return "Sale del ritmo, la etapa y los chequeos de cada área"
        default: return datos.cifra(c.modulo).fuente
        }
    }

    @ViewBuilder
    private func contenido(_ c: ModuloColocado) -> some View {
        if let datos {
            switch c.modulo {
            case .caja: ModuloCaja(caja: datos.caja, tamano: c.tamano)
            case .ritmo: ModuloRitmo(filas: datos.ritmo, tamano: c.tamano)
            case .semana: ModuloSemana(semana: datos.semana)
            case .cabe: ModuloCabe(elementos: datos.cabe, minutosAhora: minutosAhora, hora: hora, tamano: c.tamano, sesion: sesion)
            case .cuello: ModuloCuello(cuello: datos.cuello)
            default: ModuloCifra(cifra: datos.cifra(c.modulo), tamano: c.tamano)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Calculando…").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }

    // MARK: Ocultos

    private func ocultos(_ d: DisposicionInicio) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            HStack(spacing: 6) {
                Text("Ocultos del inicio").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                Text("\(d.ocultos.count)").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Text("Siguen calculándose y conservan su tamaño. Suelta aquí un módulo para ocultarlo, o pulsa «Mostrar» para devolverlo a su sitio.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if d.ocultos.isEmpty {
                Text("Nada oculto. Suelta aquí lo que no quieras ver cada mañana.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                FlujoChips(espacio: 8) {
                    ForEach(d.ocultos) { o in
                        let def = CatalogoModulos.definicion(o.modulo)
                        HStack(spacing: 6) {
                            if let a = def.area { IconoArea(a.tlsArea, tamano: 16) }
                            Text(def.titulo).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                            Text(o.tamano.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            Button("Mostrar") {
                                if !almacen.cambiar(inicio, { $0.mostrar(o.modulo) }) {
                                    sesion.aviso = Aviso("Tienes 8 de 8 a la vista. Oculta uno para mostrar este.", estado: .atencion)
                                }
                            }
                            .tlsBoton(.enlace)
                            .accessibilityLabel("Mostrar \(def.titulo) en el inicio")
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 4)
                        .background(Capsule(style: .circular).fill(TLSPaleta.superficie.color))
                    }
                }
            }
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .fill(bandejaEncima ? TLSPaleta.principalSuave.color : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
            .strokeBorder(bandejaEncima ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(ModuloID.init(rawValue:)) else { return false }
            let t = CatalogoModulos.definicion(id).titulo
            return almacen.cambiar(inicio, aviso: "Ocultaste «\(t)» del inicio") { $0.ocultar(id) }
        } isTargeted: { bandejaEncima = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inicio.ocultos")
    }
}

/// «Añadir un módulo»: la galería, con búsqueda y categorías. Con 8 a la vista, «Añadir» se desactiva y dice por qué.
struct GaleriaModulos: View {
    let inicio: InicioID
    let almacen: AlmacenInicios
    let cerrar: () -> Void
    @State private var buscar = ""
    @State private var categoria: AreaCode?

    var body: some View {
        let d = almacen.disposicion(inicio)
        let lista = (d.paraAnadir(inicio) + d.ocultos.map(\.modulo)).filter { m in
            let def = CatalogoModulos.definicion(m)
            if let c = categoria, def.area != c { return false }
            let q = TextFolding.fold(buscar.trimmingCharacters(in: .whitespaces))
            return q.isEmpty || TextFolding.fold(def.titulo + " " + def.descripcion).contains(q)
        }
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack {
                Text("Añadir un módulo").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                Spacer()
                Button("Listo", action: cerrar).tlsBoton(.principal).keyboardShortcut(.defaultAction)
            }
            TextField("Buscar módulos", text: $buscar).textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Todas", nil)
                    ForEach(AreaCode.allCases, id: \.self) { a in chip(a.nombre, a) }
                }
            }
            if d.lleno {
                AvisoEnLinea("Tienes 8 de 8. Oculta uno para añadir otro.", estado: .atencion)
            }
            ScrollView {
                VStack(spacing: 2) {
                    if lista.isEmpty {
                        Text("No hay más módulos con ese nombre en esta categoría.")
                            .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color).padding(.vertical, 12)
                    }
                    ForEach(lista, id: \.self) { m in fila(m, oculto: d.ocultos.contains { $0.modulo == m }, lleno: d.lleno) }
                }
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 520, height: 520)
        .background(TLSPaleta.fondo.color)
    }

    private func chip(_ t: String, _ a: AreaCode?) -> some View {
        Button(t) { categoria = a }
            .buttonStyle(.plain)
            .tlsTexto(TLSTipo.interfazMedia)
            .padding(.horizontal, 12)
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .foregroundStyle(categoria == a ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
            .background(Capsule(style: .circular).fill(categoria == a ? TLSPaleta.principal.color : Color.clear))
            .overlay(Capsule(style: .circular).strokeBorder(categoria == a ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color, lineWidth: 1))
            .accessibilityAddTraits(categoria == a ? [.isSelected] : [])
    }

    private func fila(_ m: ModuloID, oculto: Bool, lleno: Bool) -> some View {
        let def = CatalogoModulos.definicion(m)
        return HStack(spacing: TLSEspacio.e12) {
            if let a = def.area { IconoArea(a.tlsArea, tamano: 24) }
            VStack(alignment: .leading, spacing: 2) {
                Text(def.titulo).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Text("\(def.descripcion) · \(def.porDefecto.nombre)" + (oculto ? " · oculto" : ""))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer()
            Button(oculto ? "Mostrar" : "Añadir") {
                almacen.cambiar(inicio) { $0.anadir(m) }
            }
            .tlsBoton(.principal)
            .disabled(lleno)
            .help(lleno ? "Tienes 8 de 8. Oculta uno para añadir otro." : "Añadir \(def.titulo)")
            .accessibilityLabel("Añadir \(def.titulo)")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: TLSAltura.filaLista)
        .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous).fill(TLSPaleta.superficie.color))
    }
}
