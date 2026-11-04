import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes. Las dos hojas de la ficha de un asistente: la vista previa de lo que cambia en su configuración
// antes de guardarlo y «Pedir algo» cuando ⌘J no está conectado.

/// Vista previa de los cambios de un asistente: en palabras y, en «Detalle técnico», las líneas que cambian.
struct HojaRevisarCambios: View {
    let nombre: String
    let cambios: [CambioContado]
    let lineas: [String]
    let error: String?
    let guardar: () async -> String?
    @State private var guardando = false
    @State private var fallo: String?
    @State private var tecnico = false
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text("Revisa los cambios de \(nombre)").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text("Esto cambia lo que \(nombre) puede hacer de verdad. Se guarda en la configuración de tu carpeta y se puede deshacer.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cambios.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { SeparadorFila(sangria: 0) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.que).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(c.antes).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                                .strikethrough(true, color: TLSPaleta.textoSecundario.color)
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                            Text(c.despues).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(c.que): antes, \(c.antes); después, \(c.despues)")
                }
            }
            .padding(.horizontal, TLSEspacio.e12)
            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
            if !lineas.isEmpty {
                DisclosureGroup("Detalle técnico", isExpanded: $tecnico) {
                    Text(lineas.joined(separator: "\n"))
                        .tlsTexto(TLSTipo.codigo)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TLSEspacio.e8)
                        .background(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous).fill(TLSPaleta.bandeja.color))
                        .accessibilityLabel("Líneas de la configuración que cambian")
                }
                .tlsTexto(TLSTipo.interfazMedia)
                .accessibilityIdentifier("asistente.revisar.tecnico")
            }
            if let m = fallo ?? error {
                AvisoEnLinea(m, estado: .mal)
            }
            HStack {
                Spacer()
                Button("Cancelar") { cerrar() }
                    .tlsBoton(.secundario)
                    .keyboardShortcut(.cancelAction)
                Button(guardando ? "Guardando…" : "Guardar cambios") {
                    guardando = true
                    Task {
                        fallo = await guardar()
                        guardando = false
                        if fallo == nil { cerrar() }
                    }
                }
                .tlsBoton(.principal)
                .keyboardShortcut(.defaultAction)
                .disabled(guardando || error != nil)
                .accessibilityIdentifier("asistente.revisar.guardar")
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 520)
        .background(TLSPaleta.superficieElevada.color)
        .accessibilityIdentifier("asistente.revisar")
    }
}

/// «Pedir algo» a un asistente sin ⌘J: un texto libre o una de sus peticiones de un clic.
struct HojaPedirAlgo: View {
    let nombre: String
    let acciones: [AccionRapidaDeAsistente]
    let motivoNoSePuede: String?
    let pedir: (_ texto: String, _ accion: String?) async -> String?
    @State private var texto = ""
    @State private var enviando = false
    @State private var fallo: String?
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Text("Pedir algo a \(nombre)").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            Text("Lo prepara y te lo deja para revisar. Nada sale de la empresa sin tu OK.")
                .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
            if !acciones.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo("Con un clic")
                    ForEach(acciones) { a in
                        Button(a.titulo) { enviar(a.peticion, accion: a.id) }
                            .tlsBoton(.secundario)
                            .disabled(enviando || motivoNoSePuede != nil)
                    }
                }
            }
            TextEditor(text: $texto)
                .tlsTexto(TLSTipo.interfaz)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous).fill(TLSPaleta.bandeja.color))
                .overlay(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous).strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1))
                .accessibilityLabel("Qué le pides")
            if let m = fallo ?? motivoNoSePuede { AvisoEnLinea(m, estado: .atencion) }
            HStack {
                Spacer()
                Button("Cancelar") { cerrar() }.tlsBoton(.secundario).keyboardShortcut(.cancelAction)
                Button(enviando ? "Pidiendo…" : "Pedir") { enviar(texto, accion: nil) }
                    .tlsBoton(.principal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(enviando || motivoNoSePuede != nil || texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(TLSEspacio.e24)
        .frame(width: 480)
        .background(TLSPaleta.superficieElevada.color)
    }

    private func enviar(_ t: String, accion: String?) {
        enviando = true
        Task {
            fallo = await pedir(t.trimmingCharacters(in: .whitespacesAndNewlines), accion)
            enviando = false
            if fallo == nil { cerrar() }
        }
    }
}
