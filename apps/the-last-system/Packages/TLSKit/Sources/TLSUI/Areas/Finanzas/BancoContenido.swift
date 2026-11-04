import SwiftUI
import TLSCore
import TLSDesign
import UniformTypeIdentifiers

/// El Banco de Finanzas (PLAN §6.5 y §4.6, §7.3; SISTEMAS FI2): soltar o elegir el extracto en CSV con su vista previa
/// («29 movimientos · 0 nuevos · 29 ya importados»), las propuestas de conciliación con su motivo, «Confirmar» de una en
/// una y «Confirmar las exactas», los movimientos sin conciliar y los heredados en preparación. **Nada se confirma sin
/// el clic de una persona** (criterio F2-4) y todo se deshace. Se usa en Finanzas › Operación y en `BancoPantalla`.
struct BancoContenido: View {
    @Bindable var modelo: ModeloFinanzas
    let lectura: LecturaFinanzas
    /// Abre el selector de ficheros (lo pone quien lo enseña).
    let elegirExtracto: () -> Void
    /// Enseñar aquí lo último hecho o fallado (en Operación lo enseña la pantalla, encima de las secciones).
    var mostrarAvisos = true
    @Environment(\.undoManager) private var undoManager
    @State private var encima = false

    private var cuenta: CuentaBancaria? { modelo.cuentaFija }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            if mostrarAvisos { AvisosFinanzas(modelo: modelo) }
            if lectura.cuentas.isEmpty {
                VacioExplicado(icono: "building.columns", titulo: "Aún no hay cuentas del banco",
                               porQue: "Cada cuenta es una ficha en Finanzas › Registros › Bancos (con la plantilla «Cuenta bancaria»). Créala y podrás importar su extracto.",
                               compacto: true)
            } else {
                importar
                if let vista = modelo.vista { VistaPreviaExtractoBanco(modelo: modelo, vista: vista, lectura: lectura) }
                propuestas
                abiertos
            }
            if let h = lectura.heredados { HeredadosBanco(modelo: modelo, preparacion: h, lectura: lectura) }
            ForEach(lectura.avisos, id: \.self) { a in AvisoEnLinea(a, estado: .atencion) }
        }
        .accessibilityIdentifier("finanzas.banco")
    }

    // MARK: Importar

    private var importar: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        return HStack(alignment: .center, spacing: TLSEspacio.e16) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Suelta aquí el extracto del banco").tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                Text("El fichero de movimientos tal como lo descargas de tu banco (CSV). Antes de escribir nada verás qué movimientos son nuevos y cuáles ya estaban.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let e = modelo.errorImportacion {
                    AvisoEnLinea(e, estado: .mal).padding(.top, 4)
                    if modelo.extracto != nil, !modelo.adivinarFormato {
                        Button("Leer sin el formato de la cuenta") { Task { await modelo.leerAdivinando() } }
                            .tlsBoton(.enlace)
                            .help("Por si el banco cambió las columnas del extracto")
                    }
                }
            }
            Spacer(minLength: TLSEspacio.e8)
            Button("Elegir el extracto…", action: elegirExtracto)
                .tlsBoton(.secundario)
                .disabled(modelo.motivoSoloLectura != nil || modelo.trabajando)
                .help(modelo.motivoSoloLectura ?? "Elegir el fichero CSV del extracto")
                .accessibilityIdentifier("banco.elegir")
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(encima ? TLSPaleta.principalSuave.color : TLSPaleta.superficie.color))
        .overlay(forma.strokeBorder(encima ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color,
                                    style: StrokeStyle(lineWidth: encima ? 2 : 1, dash: [5, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            guard modelo.motivoSoloLectura == nil, let url = urls.first(where: \.isFileURL) else { return false }
            Task { await modelo.previsualizar(url: url) }
            return true
        } isTargeted: { encima = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Importar el extracto del banco")
        .accessibilityIdentifier("banco.importar")
        .tutorialAnchor(.bancoImportar)
    }

    // MARK: Propuestas

    @ViewBuilder
    private var propuestas: some View {
        let ps = lectura.propuestas(de: cuenta)
        let exactas = ps.filter(\.exacta)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .center, spacing: TLSEspacio.e8) {
                Text("Propuestas de conciliación").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                if !ps.isEmpty { InsigniaAviso(ps.count, palabra: "Por confirmar") }
                Spacer(minLength: TLSEspacio.e8)
                if !exactas.isEmpty {
                    BotonPrincipal("Confirmar las exactas (\(exactas.count))", icono: "checkmark.circle",
                                   motivoDesactivado: modelo.motivoSoloLectura ?? (modelo.trabajando ? "Escribiendo…" : nil)) {
                        Task { await modelo.confirmarLasExactas(deshacer: undoManager) }
                    }
                    .accessibilityIdentifier("banco.confirmarExactas")
                }
            }
            Text("Cada propuesta casa un movimiento del banco con una factura por su importe exacto. Nada se confirma solo: el cobro cuenta cuando lo confirmas tú.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if ps.isEmpty {
                Text(lectura.abiertos(de: cuenta).isEmpty ? "No hay nada que conciliar." : "No hay propuestas: ningún movimiento abierto coincide con una factura pendiente.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            } else {
                VStack(spacing: 0) {
                    ForEach(ps) { p in
                        FilaPropuestaConciliacion(propuesta: p, hoy: lectura.hoy, motivoDesactivado: modelo.motivoSoloLectura ?? (modelo.trabajando ? "Escribiendo…" : nil)) {
                            Task { await modelo.confirmar(p, deshacer: undoManager) }
                        }
                        if p.id != ps.last?.id { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                .tlsSombra(.uno, radio: TLSRadio.mosaico)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("banco.propuestas")
    }

    // MARK: Sin conciliar

    @ViewBuilder
    private var abiertos: some View {
        let ms = lectura.abiertos(de: cuenta)
        if !ms.isEmpty {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                HStack(spacing: TLSEspacio.e8) {
                    Text("Sin conciliar").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(ms.count)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Text("Movimientos sin factura que casar. Si no llevan factura (impuestos, nóminas, traspasos), ignóralos con su motivo.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(ms) { m in
                        FilaMovimientoSinConciliar(movimiento: m, hoy: lectura.hoy, cuenta: lectura.cuentas.first { $0.id == m.cuentaID },
                                              motivoDesactivado: modelo.motivoSoloLectura) { motivo in
                            Task { await modelo.ignorar(m, motivo: motivo, deshacer: undoManager) }
                        }
                        if m.id != ms.last?.id { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                .tlsSombra(.uno, radio: TLSRadio.mosaico)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("banco.sinConciliar")
        }
    }
}

// MARK: - Vista previa

/// La vista previa del extracto: cuenta, resumen, tres filas, formato leído y avisos. «Importar» es el único que escribe.
private struct VistaPreviaExtractoBanco: View {
    @Bindable var modelo: ModeloFinanzas
    let vista: VistaPreviaExtracto
    let lectura: LecturaFinanzas
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let hoy = lectura.hoy
        let n = vista.nuevas.count
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
                Rotulo("Vista previa")
                Text(modelo.extracto?.nombre ?? vista.lote).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if modelo.carpetaCuenta == nil, lectura.cuentas.count > 1 {
                    Picker("Cuenta", selection: Binding(get: { modelo.cuentaImportar ?? "" },
                                                        set: { id in Task { await modelo.elegirCuenta(id) } })) {
                        ForEach(lectura.cuentas) { c in Text(c.nombre).tag(c.id) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("banco.cuenta")
                } else {
                    Text(vista.cuenta.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                }
            }
            Text(vista.resumen)
                .tlsTexto(TLSTipo.tituloSeccion)
                .foregroundStyle(TLSPaleta.texto.color)
                .accessibilityIdentifier("banco.resumen")
            VStack(spacing: 0) {
                // Primero lo nuevo (lo que se va a escribir); si hay menos de tres, lo ya importado.
                ForEach(Array((vista.nuevas + vista.yaImportadas).prefix(3))) { f in
                    HStack(spacing: TLSEspacio.e12) {
                        Text(FormatoFicha.fechaCorta(f.fila.fecha, hoy: hoy)).frame(width: 64, alignment: .leading)
                        Text(f.fila.concepto).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(TextoFinanzas.eurosConSigno(f.fila.importe)).tlsTexto(TLSTipo.cifraFila).frame(width: 110, alignment: .trailing)
                        PastillaEstado(f.nueva ? .bien : .sinDato,
                                       palabra: f.nueva ? "Nuevo" : (f.repetidaEnElFichero ? "Repetido en el fichero" : "Ya importado"))
                            .frame(width: 170, alignment: .leading)
                    }
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .frame(minHeight: TLSAltura.filaTabla)
                    .accessibilityElement(children: .combine)
                }
                if vista.filas.count > 3 {
                    Text("y \(vista.filas.count - 3) más").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if vista.guardaFormato {
                AvisoEnLinea("Formato leído: \(Self.formato(vista.extracto.formato)). Se guardará en la ficha de la cuenta para la próxima vez.",
                             estado: .sinDato)
            }
            ForEach(Array(vista.extracto.avisos.prefix(4).enumerated()), id: \.offset) { _, a in
                AvisoEnLinea("Fila \(a.fila): \(a.motivo)", estado: .atencion)
            }
            HStack(spacing: TLSEspacio.e8) {
                Spacer(minLength: 0)
                Button("Cancelar") { modelo.cancelarImportacion() }
                    .tlsBoton(.secundario)
                    .keyboardShortcut(.cancelAction)
                if n > 0 {
                    BotonPrincipal("Importar " + FormatoBase.cuenta(n, "nuevo", "nuevos"), icono: "square.and.arrow.down",
                                   motivoDesactivado: modelo.motivoSoloLectura ?? (modelo.trabajando ? "Escribiendo…" : nil)) {
                        Task { await modelo.importar(deshacer: undoManager) }
                    }
                    .accessibilityIdentifier("banco.importarNuevos")
                } else {
                    Text("Nada nuevo que importar").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
        .padding(TLSEspacio.mosaicoGrande)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .overlay(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).strokeBorder(TLSPaleta.principal.color, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vista previa del extracto")
        .accessibilityIdentifier("banco.vistaPrevia")
    }

    /// «separador punto y coma, decimales con coma, fechas DD/MM/AAAA».
    static func formato(_ f: FormatoExtracto) -> String {
        let sep: String
        switch f.separador {
        case ";": sep = "punto y coma"
        case ",": sep = "coma"
        case "\t": sep = "tabulador"
        default: sep = "«\(f.separador)»"
        }
        return "columnas separadas por \(sep), decimales con \(f.decimal == "," ? "coma" : "punto"), fechas \(f.formatoFecha.rawValue)"
    }
}

// MARK: - Filas

/// Una propuesta: el movimiento, la factura con la que casa, el motivo y «Confirmar».
private struct FilaPropuestaConciliacion: View {
    let propuesta: PropuestaConciliacion
    let hoy: LocalDate
    let motivoDesactivado: String?
    let confirmar: () -> Void

    var body: some View {
        let p = propuesta
        let f = p.factura
        HStack(alignment: .center, spacing: TLSEspacio.e12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TLSEspacio.e8) {
                    Text(FormatoFicha.fechaCorta(p.movimiento.fecha, hoy: hoy)).tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text(p.movimiento.concepto).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                }
                Text("Con \(f.numeroVisible)" + (f.tercero.map { " · \($0)" } ?? "") + " · pendiente \(TextoFinanzas.euros(p.pendiente))")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                Text(p.motivo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TLSEspacio.e8)
            Text(TextoFinanzas.eurosConSigno(p.movimiento.importe)).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
            if p.exacta {
                PastillaEstado(.bien, palabra: "Exacta")
            } else {
                PastillaEstado(.atencion, palabra: "\(p.empates + 1) facturas posibles")
            }
            Button("Confirmar", action: confirmar)
                .tlsBoton(.secundario)
                .disabled(motivoDesactivado != nil)
                .help(motivoDesactivado ?? "Confirmar que este movimiento es el cobro o el pago de \(f.numeroVisible)")
                .accessibilityLabel("Confirmar: \(TextoFinanzas.euros(abs(p.movimiento.importe))) con \(f.numeroVisible)")
                .accessibilityIdentifier("banco.confirmar.\(p.movimiento.id)")
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, TLSEspacio.e12)
        .accessibilityElement(children: .contain)
    }
}

/// Un movimiento sin conciliar ni propuesta, con «Ignorar…» y su motivo.
private struct FilaMovimientoSinConciliar: View {
    let movimiento: MovimientoBanco
    let hoy: LocalDate
    let cuenta: CuentaBancaria?
    let motivoDesactivado: String?
    let ignorar: (String) -> Void

    static let motivos = [
        "Sin factura: impuestos", "Sin factura: nómina o seguros sociales", "Traspaso entre cuentas propias",
        "Retirada del titular", "Sin factura: otro gasto",
    ]

    var body: some View {
        let m = movimiento
        HStack(alignment: .center, spacing: TLSEspacio.e12) {
            Text(FormatoFicha.fechaCorta(m.fecha, hoy: hoy)).tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color).frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.concepto).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                Text([cuenta?.nombre, m.estado == .propuesta ? "Propuesta escrita" : nil].compactMap { $0 }.joined(separator: " · "))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
            }
            Spacer(minLength: TLSEspacio.e8)
            Text(TextoFinanzas.eurosConSigno(m.importe)).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
            Menu {
                ForEach(Self.motivos, id: \.self) { motivo in Button(motivo) { ignorar(motivo) } }
            } label: {
                Text("Ignorar…").tlsTexto(TLSTipo.secundario).underline()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(TLSPaleta.enlace.color)
            .fixedSize()
            .disabled(motivoDesactivado != nil)
            .help(motivoDesactivado ?? "No lleva factura: se marca como ignorado con su motivo")
            .accessibilityLabel("Ignorar \(m.concepto)")
        }
        .padding(.horizontal, TLSEspacio.e16)
        .frame(minHeight: TLSAltura.filaLista)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Heredados

/// Los movimientos heredados de `Registros/importar/` (PLAN §7.3): se cargan en preparación, como facturas y pagos sin
/// revisar. **Ninguno queda confirmado** ni toca los movimientos del banco (criterio F2-7).
private struct HeredadosBanco: View {
    /// El nombre de una columna en palabras: `tipo_fiscal` → «tipo fiscal», `iva` → «IVA».
    static func nombreColumna(_ c: String) -> String { NombreDeColumna.de(c) }

    @Bindable var modelo: ModeloFinanzas
    let preparacion: PreparacionHeredada
    let lectura: LecturaFinanzas
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let nuevas = preparacion.nuevas.count
        Mosaico("Movimientos heredados", icono: "tray.full",
                pie: "De " + FormatoBase.cuenta(preparacion.ficheros.count, "fichero", "ficheros") + " en Finanzas › Registros › importar") {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                Text(preparacion.resumen)
                    .tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityIdentifier("banco.heredados.resumen")
                Text("Se cargan en preparación, como facturas y pagos sin revisar. Ninguno cuenta como cobrado ni se concilia con el banco hasta que lo revises.")
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                if !preparacion.columnasQueNoCaben.isEmpty {
                    AvisoEnLinea("Estos datos no caben en los registros y no se cargan: "
                                 + preparacion.columnasQueNoCaben.map(Self.nombreColumna).joined(separator: ", ") + ".", estado: .atencion)
                }
                ForEach(Array(preparacion.avisos.prefix(4).enumerated()), id: \.offset) { _, a in AvisoEnLinea(a, estado: .atencion) }
                if lectura.sinRevisar > 0 {
                    Text("En preparación: " + FormatoBase.cuenta(lectura.sinRevisar, "factura sin revisar", "facturas sin revisar") + ".")
                        .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                }
                HStack {
                    Spacer(minLength: 0)
                    if nuevas > 0 {
                        BotonPrincipal("Cargar en preparación", icono: "tray.and.arrow.down",
                                       motivoDesactivado: modelo.motivoSoloLectura ?? (modelo.trabajando ? "Escribiendo…" : nil)) {
                            Task { await modelo.cargarHeredados(deshacer: undoManager) }
                        }
                        .accessibilityIdentifier("banco.heredados.cargar")
                    } else {
                        Text("Ya están todos cargados").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("banco.heredados")
    }
}

/// El nombre de una columna de un registro en palabras, con sus tildes: `tipo_fiscal` → «tipo fiscal», `iva` → «IVA»,
/// `estado_revision` → «estado de revisión», `numero_documento` → «número de documento».
enum NombreDeColumna {
    static let enteros: [String: String] = [
        "iva": "IVA", "irpf": "IRPF", "nif": "NIF", "cif": "CIF", "iban": "IBAN",
        "estado_revision": "estado de revisión", "numero_documento": "número de documento", "numero_factura": "número de factura",
        "fecha_emision": "fecha de emisión", "fecha_vencimiento": "fecha de vencimiento", "fecha_cobro": "fecha de cobro",
        "fecha_pago": "fecha de pago", "base_imponible": "base imponible",
    ]
    static let palabras: [String: String] = [
        "categoria": "categoría", "retencion": "retención", "numero": "número", "revision": "revisión",
        "descripcion": "descripción", "codigo": "código", "razon": "razón", "direccion": "dirección", "telefono": "teléfono",
        "emision": "emisión", "dias": "días", "periodo": "periodo", "contrasena": "contraseña", "conciliacion": "conciliación",
    ]

    static func de(_ c: String) -> String {
        let clave = TextFolding.fold(c).trimmingCharacters(in: .whitespaces)
        if let e = enteros[clave] { return e }
        return clave.split(separator: "_").map { palabras[String($0)] ?? enteros[String($0)] ?? String($0) }.joined(separator: " ")
    }
}
