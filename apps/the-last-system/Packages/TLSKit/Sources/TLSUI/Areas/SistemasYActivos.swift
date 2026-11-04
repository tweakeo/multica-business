import SwiftUI
import TLSCore
import TLSDesign

/// Pestaña «Sistemas y activos» de un área (PLAN §6.5, SISTEMAS §4.2): cada sistema con su estado (montado,
/// a medias o falta), sus pasos en lenguaje llano («Lo haces tú», «Te ayuda», «Lo hace y revisas», «Lo hace
/// solo»; lo que sale fuera, bloqueado en «Siempre con tu OK»), sus plantillas y los activos ligados a él.
struct SistemasYActivos: View {
    let datos: DatosArea
    let sesion: VaultSession
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            if datos.sistemasEnUso > 3 {
                AvisoEnLinea("Más de 3 sistemas suele ser burocracia: revisa si alguno sobra.", estado: .atencion)
            }
            if datos.sistemas.isEmpty {
                VacioExplicado(icono: "gearshape.2", titulo: "Esta área no tiene sistemas en el catálogo",
                               porQue: "Puedes escribir los suyos en su carpeta Sistemas; aparecerán aquí con su estado.")
            }
            ForEach(datos.sistemas) { s in bloque(s) }
            if !datos.activosSueltos.isEmpty {
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    Rotulo("Activos sin sistema")
                    Text("Activos del área que no dicen de qué sistema son.")
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                    VStack(spacing: 2) {
                        ForEach(datos.activosSueltos) { a in filaActivo(a) }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                    .tlsSombra(.uno, radio: TLSRadio.mosaico)
                }
                .accessibilityIdentifier("area.activosSueltos")
            }
        }
        .accessibilityIdentifier("area.sistemas")
    }

    // MARK: Un sistema

    private func bloque(_ s: SistemaDeArea) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                if let codigo = s.codigo {
                    Text(codigo).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Text(s.nombre).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                    .accessibilityAddTraits(.isHeader)
                PastillaEstado(s.estado.estado, palabra: s.estado.palabra)
                Spacer(minLength: TLSEspacio.e8)
                if let ficha = s.ficha {
                    Button("Abrir") { navegar(sesion.destino(para: ficha), modo: .automatico) }
                        .tlsBoton(.secundario)
                        .accessibilityLabel("Abrir el sistema \(s.nombre)")
                }
            }
            Text(detalle(s))
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if !s.funciones.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(s.funciones.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                        filaFuncion(f)
                    }
                }
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
            } else if s.ficha != nil {
                Text("Su ficha aún no tiene la tabla de pasos.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if !s.activos.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activos").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    ForEach(s.activos) { a in filaActivo(a) }
                }
            }
        }
        .padding(TLSEspacio.e16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(s.nombre), \(s.estado.palabra)")
        .accessibilityIdentifier("area.sistema.\(s.id)")
    }

    /// «Número clave FIN-AR · 3 de 4 sin ti · 2 plantillas · Se instala en la etapa 2».
    private func detalle(_ s: SistemaDeArea) -> String {
        var partes: [String] = []
        if s.ficha == nil {
            if s.deSerie {
                partes.append("Aún no tiene ficha. Viene de serie en cualquier empresa")
            } else if let e = s.etapa {
                partes.append("Aún no tiene ficha. Se instala en la etapa \(e)")
            } else {
                partes.append("Aún no tiene ficha")
            }
        }
        if let n = s.numeroClave { partes.append("Número clave \(n)") }
        if let st = s.sinTi { partes.append("\(st.hechos) de \(st.total) sin ti") }
        if !s.plantillas.isEmpty { partes.append(s.plantillas.count == 1 ? "1 plantilla" : "\(s.plantillas.count) plantillas") }
        if let r = s.revisado { partes.append("Revisado: \(FormatoBase.fecha(r, hoy: datos.hoy))") }
        return partes.joined(separator: " · ")
    }

    private func filaFuncion(_ f: FuncionDeSistema) -> some View {
        HStack(alignment: .center, spacing: TLSEspacio.e12) {
            Text("\(f.numero)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.paso).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let q = f.quien ?? f.dejaHecho {
                    Text(f.quien == nil ? "Deja hecho: \(q)" : "Quién: \(q)")
                        .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            Spacer(minLength: TLSEspacio.e8)
            ModoPastilla(modo: f.modo)
        }
        .padding(.horizontal, TLSEspacio.e12)
        .frame(minHeight: TLSAltura.filaLista)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paso \(f.numero): \(f.paso). \(f.modo.palabra)" + (f.sensible ? ", bloqueado: sale fuera" : ""))
    }

    private func filaActivo(_ a: ActivoDeArea) -> some View {
        FilaLista(a.nombre, detalle: [a.estado, a.ejemploBueno ? "Ejemplo bueno" : nil].compactMap { $0 }.joined(separator: " · "),
                  icono: "shippingbox") {
            navegar(sesion.destino(para: a.ruta), modo: .automatico)
        }
        .vistaPrevia(ruta: a.ruta, sesion: sesion)
    }
}

/// El modo de un paso, con icono y palabra. Lo sensible lleva el candado: nunca sube de «Siempre con tu OK».
struct ModoPastilla: View {
    let modo: ModoFuncion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: modo.simbolo)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            Text(modo.palabra).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(Capsule(style: .circular).fill(TLSPaleta.superficie.color))
        .overlay(Capsule(style: .circular).strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1))
        .fixedSize()
        .help(modo == .siempreConTuOK ? "Sale fuera: siempre con tu OK, en cualquier modo" : modo.palabra)
    }
}
