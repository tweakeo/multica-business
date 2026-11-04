import SwiftUI

/// Un vacío que explica (§2.2, principio 6): nunca un «0» mudo. Dice **por qué** está vacío y **qué hacer**,
/// con un botón si hay algo que hacer desde aquí.
public struct VacioExplicado: View {
    let icono: String
    let titulo: String
    let porQue: String
    let accion: (titulo: String, hacer: () -> Void)?
    let secundaria: (titulo: String, hacer: () -> Void)?
    let compacto: Bool

    public init(icono: String, titulo: String, porQue: String, accion: String? = nil, alPulsar: (() -> Void)? = nil,
                secundaria: String? = nil, alPulsarSecundaria: (() -> Void)? = nil, compacto: Bool = false) {
        self.icono = icono; self.titulo = titulo; self.porQue = porQue; self.compacto = compacto
        self.accion = accion.flatMap { t in alPulsar.map { (t, $0) } }
        self.secundaria = secundaria.flatMap { t in alPulsarSecundaria.map { (t, $0) } }
    }

    public var body: some View {
        VStack(alignment: compacto ? .leading : .center, spacing: TLSEspacio.e12) {
            Image(systemName: icono)
                .font(.system(size: compacto ? 20 : 32, weight: .regular))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            Text(titulo)
                .tlsTexto(compacto ? TLSTipo.tituloModulo : TLSTipo.tituloSeccion)
                .foregroundStyle(TLSPaleta.texto.color)
                .multilineTextAlignment(compacto ? .leading : .center)
                .accessibilityAddTraits(.isHeader)
            Text(porQue)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .multilineTextAlignment(compacto ? .leading : .center)
                .frame(maxWidth: 460, alignment: compacto ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if accion != nil || secundaria != nil {
                HStack(spacing: TLSEspacio.e8) {
                    if let secundaria { Button(secundaria.titulo, action: secundaria.hacer).tlsBoton(.secundario) }
                    if let accion { Button(accion.titulo, action: accion.hacer).tlsBoton(.principal) }
                }
                .padding(.top, 4)
            }
        }
        .padding(compacto ? TLSEspacio.e16 : TLSEspacio.e32)
        .frame(maxWidth: .infinity, alignment: compacto ? .leading : .center)
        .accessibilityElement(children: .contain)
    }
}
