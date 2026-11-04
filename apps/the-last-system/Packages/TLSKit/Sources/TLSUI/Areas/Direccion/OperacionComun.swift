import Foundation
import Observation
import SwiftUI
import TLSCore
import TLSDesign

// Piezas comunes de las pantallas de Operación de Dirección, Ventas y Entrega (rol areas-a, F2). Viven aquí porque
// el resto de `Areas/` es del andamio; las usan los tres.

/// Lo que calcula una pantalla de Operación a partir de la foto compartida de la empresa, fuera del hilo principal,
/// cada vez que cambia la carpeta (`sesion.revision`). Nunca escribe.
@Observable @MainActor
final class CargaOperacion<Datos: Sendable> {
    let sesion: VaultSession
    private let calcular: @Sendable (VaultSnapshot, LocalDate) -> Datos
    private(set) var datos: Datos?
    /// La foto con la que se calcularon los datos (incluye lo privado: solo para preparar escrituras).
    @ObservationIgnored private(set) var foto: VaultSnapshot?
    private(set) var revisionLeida = -1
    @ObservationIgnored private var carga: Task<Void, Never>?

    init(sesion: VaultSession, calcular: @escaping @Sendable (VaultSnapshot, LocalDate) -> Datos) {
        self.sesion = sesion
        self.calcular = calcular
    }

    func cargar() async {
        let revision = sesion.revision
        guard revision != revisionLeida || datos == nil else { return }
        if let carga { await carga.value; if revision == revisionLeida, datos != nil { return } }
        let almacen = AlmacenRelaciones.de(sesion)
        let calcular = self.calcular
        let tarea = Task { [weak self] in
            await almacen.actualizar()
            guard let self, let foto = almacen.foto else { return }
            let hoy = self.sesion.hoy
            let d = await Task.detached(priority: .userInitiated) { calcular(foto, hoy) }.value
            guard !Task.isCancelled else { return }
            self.datos = d
            self.foto = foto
            self.revisionLeida = revision
        }
        carga = tarea
        await tarea.value
        carga = nil
    }

    /// Por qué no se puede escribir ahora (o `nil` si se puede).
    var motivoSoloLectura: String? { OperacionComun.motivoSoloLectura(sesion) }
}

enum OperacionComun {
    /// Por qué no se puede escribir (`nil` si se puede).
    @MainActor
    static func motivoSoloLectura(_ sesion: VaultSession) -> String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .soloLectura(let m): m.texto
        case .abriendo: "La carpeta aún se está abriendo"
        }
    }

    /// El ritmo del núcleo con las palabras del andamio (objetivos y cronograma). Un objetivo no tiene alerta: en riesgo
    /// o crítico es «Atención»; el rojo con ✖ queda para lo que está en la sección Alertas de Hoy.
    static func ritmo(_ e: EstadoRitmo) -> RitmoNumero {
        switch e {
        case .adelantado, .enRitmo: .enRitmo
        case .atencion: .atencion
        case .enRiesgo, .critico: .atencion
        case .sinMeta: .sinMeta
        case .sinDato: .sinDato
        }
    }

    /// El estado de un número (Bien, Atención, Mal…) como color con palabra.
    static func estado(_ e: EstadoKPI) -> TLSEstado {
        switch e {
        case .bien: .bien
        case .atencion: .atencion
        case .mal: .mal
        case .sinMeta, .sinDato: .sinDato
        }
    }

    /// «30 oct» (con el año si no es el de hoy).
    static func fecha(_ d: LocalDate, hoy: LocalDate) -> String { FormatoFicha.fechaCorta(d, hoy: hoy) }

    /// El nombre visible de un enlace escrito («[[frutas-ribera|Frutas Ribera SC]]» → «Frutas Ribera SC»).
    static func nombre(_ enlace: String?) -> String? {
        guard let e = enlace?.trimmingCharacters(in: .whitespaces), !e.isEmpty else { return nil }
        let t = LinkParser.plainText(e).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// El lunes de la semana de `d`.
    static func lunes(de d: LocalDate) -> LocalDate { d.adding(days: -(d.weekday - 1)) }

    /// El día laborable siguiente (o anterior) a `d`, saltando sábado y domingo.
    static func laborable(_ d: LocalDate, paso: Int) -> LocalDate {
        var x = d.adding(days: paso)
        while x.isWeekend { x = x.adding(days: paso > 0 ? 1 : -1) }
        return x
    }
}

/// Una cifra pequeña de la franja de arriba de una Operación (no es el destacado del área: ese es el número clave).
struct CifraOperacion: Identifiable, Hashable, Sendable {
    var id: String { codigo }
    let codigo: String
    let indicador: String
    /// «Sin dato» si no hay de dónde contarlo; nunca un 0 de relleno.
    let valor: String
    let meta: String
    let estado: TLSEstado
    let palabra: String
    let fuente: String?

    init(codigo: String, indicador: String, valor: String, meta: String, estado: TLSEstado, palabra: String, fuente: String?) {
        self.codigo = codigo; self.indicador = indicador; self.valor = valor; self.meta = meta
        self.estado = estado; self.palabra = palabra; self.fuente = fuente
    }

    /// Desde el evaluador del núcleo (`KPIEvaluador`).
    init(_ v: ValorKPI) {
        let fuente = v.medida.motivoSinDato ?? v.fuente
        self.init(codigo: v.codigo, indicador: v.indicador, valor: v.textoValor, meta: v.textoMeta,
                  estado: OperacionComun.estado(v.estado), palabra: v.estado.etiqueta,
                  fuente: fuente.trimmingCharacters(in: .whitespaces).isEmpty ? nil : fuente)
    }
}

/// La franja de cifras de una Operación: código, número, valor, meta y estado (con palabra, nunca solo color).
struct FranjaCifras: View {
    let cifras: [CifraOperacion]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) {
                ForEach(cifras) { c in celda(c).frame(maxWidth: .infinity, alignment: .leading) }
            }
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                ForEach(cifras) { c in celda(c).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("operacion.cifras")
    }

    private func celda(_ c: CifraOperacion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(c.codigo).tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                Spacer(minLength: 0)
                PastillaEstado(c.estado, palabra: c.palabra)
            }
            Text(c.indicador).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(c.valor).tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                Text(c.meta == "Sin meta" ? "Sin meta" : "meta \(c.meta)")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if let f = c.fuente {
                Text(f).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
            }
        }
        .padding(TLSEspacio.e12)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.bloque)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.codigo), \(c.indicador): \(c.valor). \(c.meta == "Sin meta" ? "Sin meta" : "Meta \(c.meta)"). \(c.palabra)."
            + (c.fuente.map { " \($0)." } ?? ""))
    }
}

/// Un bloque blanco con título (las secciones de una Operación).
struct BloqueOperacion<Contenido: View, Acciones: View>: View {
    let titulo: String
    let detalle: String?
    let contenido: Contenido
    let acciones: Acciones

    init(_ titulo: String, detalle: String? = nil, @ViewBuilder acciones: () -> Acciones = { EmptyView() },
         @ViewBuilder contenido: () -> Contenido) {
        self.titulo = titulo; self.detalle = detalle; self.acciones = acciones(); self.contenido = contenido()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    if let detalle {
                        Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: TLSEspacio.e8)
                acciones
            }
            contenido
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
    }
}

/// Las secciones de una Operación (pestañas en cápsula sin ⌃1–⌃9: esos son de las pestañas del área), recordadas
/// por pestaña de ventana con una clave propia (`"ventas.vista"`…).
struct SeccionesOperacion: View {
    let area: AreaCode
    let clave: String
    let secciones: [PestanaCapsula]
    @Environment(\.navegacion) private var nav

    /// La sección elegida (la primera si no hay recuerdo).
    static func elegida(_ nav: Navegacion?, area: AreaCode, clave: String, secciones: [String]) -> String {
        let r = nav?.recuerdo(de: .area(area)).extra[clave]
        return r.flatMap { secciones.contains($0) ? $0 : nil } ?? secciones.first ?? ""
    }

    var body: some View {
        let actual = Self.elegida(nav, area: area, clave: clave, secciones: secciones.map(\.id))
        PestanasCapsula(seleccion: Binding(get: { actual }, set: { nuevo in
            nav?.actualizarRecuerdo(de: .area(area)) { $0.extra[clave] = nuevo }
        }), pestanas: secciones, atajosControl: false)
        .accessibilityLabel("Secciones de la operación")
        .accessibilityIdentifier("operacion.secciones.\(area.rawValue)")
    }
}

/// «Leyendo…» mientras se calcula una Operación.
struct CargandoOperacion: View {
    let texto: String
    var body: some View {
        HStack(spacing: TLSEspacio.e8) {
            ProgressView().controlSize(.small)
            Text(texto).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Un error de escritura que la pantalla enseña en línea (además del aviso de la sesión).
struct ErrorOperacion: Equatable {
    let texto: String
    let estado: TLSEstado
}
