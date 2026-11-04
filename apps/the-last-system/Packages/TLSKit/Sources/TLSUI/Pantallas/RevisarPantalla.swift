import SwiftUI
import TLSCore
import TLSDesign

/// «Revisar»: lo que la app no ha querido decidir sola. Versiones distintas de una nota (cambió fuera
/// mientras la editabas, o al abrir no estaba como se esperaba), fichas repetidas («X 2.md») y versiones
/// en conflicto de iCloud. Nada se borra: lo que no eliges va a `Archivo/`.
struct RevisarPantalla: View {
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar
    /// «Combinar…»: las dos versiones de la tarjeta abierta.
    @State private var combinando: Combinacion?
    /// Las tarjetas de las tareas (heredados, Adoptar, números repetidos, movidas en Finder; F2).
    @State private var tareas: ModeloTareas

    struct Combinacion: Identifiable {
        let tarjeta: ConflictRecord
        let mia: String
        let deFuera: String
        let markdown: Bool
        var id: UUID { tarjeta.id }
    }

    init(sesion: VaultSession) {
        self.sesion = sesion
        _tareas = State(initialValue: ModeloTareas(sesion: sesion))
    }

    var body: some View {
        ContenedorPantalla(destino: .revisar, espacio: TLSEspacio.e12) {
            CabeceraAzulNoche(rotulo: "Hoy", titulo: "Revisar",
                              subtitulo: "Elige qué versión se queda. La otra no se pierde: va al Archivo.",
                              altoMinimo: TLSAltura.cabeceraBase)
            if !sesion.puedeEscribir, !sesion.tarjetas.isEmpty {
                InfoBanner("Para resolverlas, permite los cambios en esta copia (abajo, en la barra lateral).", systemImage: "lock")
                    .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque))
            }
            if let texto = sesion.textoRecuperacion {
                Tarjeta(icono: "arrow.uturn.backward.circle", estado: .bien, titulo: "Lo que quedó a medias, terminado",
                        detalle: texto) {
                    Button("Entendido") { sesion.olvidarRecuperacion() }.tlsBoton(.secundario)
                }
            }
            ForEach(sesion.tarjetas) { t in tarjeta(t) }
            RevisarTareas(modelo: tareas, abierta: true)
            if sesion.tarjetas.isEmpty && sesion.textoRecuperacion == nil && !tareas.revision.hayAlgo {
                VacioExplicado(icono: "checkmark.circle", titulo: "Nada que revisar",
                               porQue: "Cuando una nota cambie a la vez dentro y fuera de la app, o aparezca una ficha repetida, lo verás aquí.")
            }
        }
        .task(id: sesion.revision) { await tareas.cargar() }
        .sheet(item: $combinando) { c in
            // Las mismas diferencias que en el editor: se compara el cuerpo y se guarda con las propiedades de fuera.
            let fuera = ModeloNotaEditor.cuerpo(de: c.deFuera, markdown: c.markdown)
            DiferenciasVersiones(titulo: c.tarjeta.ruta.stem,
                                 mia: ModeloNotaEditor.cuerpo(de: c.mia, markdown: c.markdown),
                                 deFuera: fuera,
                                 alQuedarme: { Task { await sesion.resolver(c.tarjeta, eleccion: .mia) } },
                                 alUsarFuera: { Task { await sesion.resolver(c.tarjeta, eleccion: .otra) } },
                                 alCombinar: { cuerpo in
                                     let texto = ModeloNotaEditor.prefijo(de: c.deFuera, cuerpo: fuera) + cuerpo
                                     Task { await sesion.resolver(c.tarjeta, eleccion: .combinada(texto)) }
                                 })
                .frame(minWidth: 640, minHeight: 480)
        }
    }

    private func combinar(_ t: ConflictRecord) {
        guard let v = sesion.versionesParaCombinar(t) else {
            sesion.aviso = Aviso("No encuentro las dos versiones de «\(t.ruta.stem)» para compararlas.", estado: .atencion)
            return
        }
        let markdown = ["md", "markdown"].contains(t.ruta.ext)
        combinando = Combinacion(tarjeta: t, mia: v.mia, deFuera: v.deFuera, markdown: markdown)
    }

    @ViewBuilder
    private func tarjeta(_ t: ConflictRecord) -> some View {
        let sinPermiso = !sesion.puedeEscribir
        Tarjeta(icono: icono(t), estado: .atencion, titulo: t.titulo, detalle: t.detalle,
                pie: "\(t.ruta.carpetaVisible) · \(TLSFormat.fechaCorta(t.fecha))") {
            switch t.tipo {
            case .edicion, .recuperacion:
                Button("Quedarme con la mía") { Task { await sesion.resolver(t, eleccion: .mia) } }
                    .tlsBoton(.principal).disabled(sinPermiso)
                Button("Quedarme con la de fuera") { Task { await sesion.resolver(t, eleccion: .otra) } }
                    .tlsBoton(.secundario).disabled(sinPermiso)
                Button("Ver diferencias y combinar…") { combinar(t) }
                    .tlsBoton(.secundario).disabled(sinPermiso)
            case .duplicado:
                Button("Apartar la repetida") { Task { await sesion.descartarDuplicado(t) } }
                    .tlsBoton(.principal).disabled(sinPermiso)
                Button("Quedarme con la repetida") { Task { await sesion.descartarDuplicado(t, quedarmeConLaRepetida: true) } }
                    .tlsBoton(.secundario).disabled(sinPermiso)
            case .icloud:
                Button("Quedarme con la de ahora") { Task { await sesion.resolverICloud(t, quedarmeCon: nil) } }
                    .tlsBoton(.principal).disabled(sinPermiso)
                ForEach(Array(versionesGuardadas(t).enumerated()), id: \.offset) { i, v in
                    Button("Quedarme con «\(v.etiqueta)»") { Task { await sesion.resolverICloud(t, quedarmeCon: i) } }
                        .tlsBoton(.secundario).disabled(sinPermiso)
                }
            }
            Button("Abrir la nota") { navegar(sesion.destino(para: t.ruta), modo: .entrar) }
                .tlsBoton(.enlace)
        }
    }

    private func versionesGuardadas(_ t: ConflictRecord) -> [ConflictVersion] {
        t.versiones.filter { if case .copia = $0.ubicacion { return true } else { return false } }
    }

    private func icono(_ t: ConflictRecord) -> String {
        switch t.tipo {
        case .edicion, .recuperacion: "doc.on.doc"
        case .duplicado: "plus.square.on.square"
        case .icloud: "icloud.and.arrow.down"
        }
    }
}

/// Una tarjeta de «Revisar»: icono de estado, título, explicación y botones.
private struct Tarjeta<Acciones: View>: View {
    let icono: String
    let estado: TLSEstado
    let titulo: String
    let detalle: String
    var pie: String? = nil
    @ViewBuilder let acciones: Acciones

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .top, spacing: TLSEspacio.e12) {
                Image(systemName: icono)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(estado.color.color)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Text(detalle).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pie {
                        Text(pie).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                Spacer(minLength: 0)
                PastillaEstado(estado, palabra: estado == .bien ? "Hecho" : "Elige")
            }
            HStack(spacing: TLSEspacio.e8) { acciones }
                .padding(.leading, 40)
        }
        .padding(TLSEspacio.e20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
    }
}
