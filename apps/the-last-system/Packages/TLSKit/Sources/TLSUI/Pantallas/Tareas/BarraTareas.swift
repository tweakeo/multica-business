import SwiftUI
import TLSCore
import TLSDesign

/// La barra de Tareas (PLAN §6.4): conmutador Lista | Tablero, «Lo mío», fecha (Hoy · Semana · Vencidas · Sin
/// programar), búsqueda y, debajo, los filtros por área, proyecto u oportunidad, responsable y estado, la
/// agrupación de la lista y «Ver canceladas». Lo puesto se ve en chips con «×».
struct BarraTareas: View {
    @Bindable var modelo: ModeloTareas
    @FocusState private var buscando: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            FlujoChips(espacio: TLSEspacio.e8) {
                SelectorCapsula(etiqueta: "Vista", seleccion: $modelo.consulta.vista,
                                opciones: [(.lista, "Lista", "list.bullet"), (.tablero, "Tablero", "rectangle.split.3x1")])
                loMio
                SelectorCapsula(etiqueta: "Fecha", seleccion: $modelo.consulta.fecha,
                                opciones: FiltroFecha.allCases.map { ($0, $0.rawValue, nil) })
                buscador
            }
            FlujoChips(espacio: TLSEspacio.e8) {
                filtroArea
                filtroContenedor
                filtroResponsable
                filtroEstado
                if modelo.consulta.vista == .lista { agrupar }
                Toggle("Ver canceladas", isOn: $modelo.consulta.verCanceladas)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tlsTexto(TLSTipo.interfazMedia)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .frame(minHeight: TLSAltura.objetivoMinimo + 4)
                    .help("Cancelada no sale ni en la lista ni en el tablero salvo que lo pidas")
                if modelo.consulta.filtrando {
                    Button("Quitar filtros") { modelo.consulta.quitarFiltros() }
                        .tlsBoton(.enlace, alto: TLSAltura.objetivoMinimo + 4)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filtros de las tareas")
    }

    private var loMio: some View {
        let on = modelo.consulta.loMio
        return Button {
            modelo.consulta.loMio.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "person.fill" : "person").font(.system(size: 12, weight: .medium))
                Text("Lo mío").tlsTexto(TLSTipo.interfazMedia)
            }
            .foregroundStyle(on ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
            .padding(.horizontal, 12)
            .frame(minHeight: TLSAltura.objetivoMinimo + 4)
            .background(Capsule(style: .circular).fill(on ? TLSPaleta.principal.color : Color.clear))
            .overlay(Capsule(style: .circular).strokeBorder(on ? .clear : TLSPaleta.bordeControl.color, lineWidth: 1))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .tlsFocoPropio(radio: 999)
        .help("Solo las que llevas tú (\(modelo.persona))")
        .accessibilityLabel("Lo mío")
        .accessibilityValue(on ? "Puesto: solo las que llevas tú" : "Quitado")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var buscador: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            TextField("Buscar", text: $modelo.consulta.busqueda, prompt: Text("Buscar por número, título o proyecto"))
                .textFieldStyle(.plain)
                .tlsTexto(TLSTipo.interfaz)
                .focused($buscando)
                .frame(width: 220)
                .onExitCommand { modelo.consulta.busqueda = ""; buscando = false }
                .accessibilityLabel("Buscar tareas")
            if !modelo.consulta.busqueda.isEmpty {
                Button { modelo.consulta.busqueda = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .frame(width: TLSAltura.objetivoMinimo, height: TLSAltura.objetivoMinimo)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityLabel("Borrar la búsqueda")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: TLSAltura.objetivoMinimo + 4)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .tlsAnilloFoco(buscando, radio: 999)
    }

    private var filtroArea: some View {
        MenuFiltro(etiqueta: "Área", valor: modelo.consulta.area.map { "\($0.numero) · \($0.nombre)" }) {
            Button("Todas") { modelo.consulta.area = nil }
            Divider()
            ForEach(AreaCode.allCases, id: \.self) { a in
                Button(modelo.sesion.area(a)?.etiquetaNumerada ?? a.etiquetaNumerada) { modelo.consulta.area = a }
            }
        }
    }

    private var filtroContenedor: some View {
        let lista = modelo.contenedores
        let elegido = modelo.consulta.contenedor.flatMap { c in lista.first { $0.ruta == c }?.nombre ?? c.stem }
        return MenuFiltro(etiqueta: "Proyecto u oportunidad", valor: elegido) {
            Button("Todos") { modelo.consulta.contenedor = nil }
            if lista.isEmpty {
                Text("Ninguna tarea cuelga de un proyecto u oportunidad")
            }
            let proyectos = lista.filter(\.esProyecto)
            let oportunidades = lista.filter { !$0.esProyecto }
            if !proyectos.isEmpty {
                Section("Proyectos") {
                    ForEach(proyectos, id: \.ruta) { c in Button(c.nombre) { modelo.consulta.contenedor = c.ruta } }
                }
            }
            if !oportunidades.isEmpty {
                Section("Oportunidades") {
                    ForEach(oportunidades, id: \.ruta) { c in Button(c.nombre) { modelo.consulta.contenedor = c.ruta } }
                }
            }
        }
    }

    private var filtroResponsable: some View {
        let valor: String? = modelo.consulta.responsable.map { $0 == ConsultaTareas.sinResponsable ? "Sin responsable" : Responsables.nombre(de: $0) }
        return MenuFiltro(etiqueta: "Responsable", valor: valor) {
            Button("Todos") { modelo.consulta.responsable = nil }
            Divider()
            ForEach(modelo.responsables, id: \.id) { r in Button(r.nombre) { modelo.consulta.responsable = r.id } }
            Button("Sin responsable") { modelo.consulta.responsable = ConsultaTareas.sinResponsable }
        }
    }

    private var filtroEstado: some View {
        MenuFiltro(etiqueta: "Estado", valor: modelo.consulta.estado?.rawValue) {
            Button("Todos") { modelo.consulta.estado = nil }
            Divider()
            ForEach(EstadoTarea.allCases, id: \.self) { e in Button(e.rawValue) { modelo.consulta.estado = e } }
        }
    }

    private var agrupar: some View {
        MenuFiltro(etiqueta: "Agrupar por", valor: modelo.consulta.agrupar.rawValue, resaltado: modelo.consulta.agrupar != .estado) {
            ForEach(AgrupacionTareas.allCases, id: \.self) { a in
                Button(a.rawValue) { modelo.consulta.agrupar = a }
            }
        }
    }
}
