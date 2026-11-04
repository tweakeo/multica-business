import SwiftUI
import TLSCore
import TLSDesign
import TLSEditor

/// Aviso encima del editor cuando un guardado choca con un cambio hecho fuera (PLAN §6.6): «Quedarme con lo
/// mío», «Usar lo de fuera» y «Ver diferencias». La versión que no se elige se guarda en `Archivo/Conflictos/`.
struct BannerConflicto: View {
    let alQuedarme: () -> Void
    let alUsarFuera: () -> Void
    let alVer: () -> Void

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        HStack(alignment: .top, spacing: TLSEspacio.e12) {
            Image(systemName: TLSEstado.atencion.simbolo)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TLSEstado.atencion.color.color)
                .accessibilityLabel(TLSEstado.atencion.palabra)
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                Text("Esta nota cambió fuera de la app mientras la escribías")
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                Text("No he guardado lo tuyo para no pisar lo de fuera. Elige con qué te quedas: la otra versión se guarda en «Archivo», no se pierde nada.")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: TLSEspacio.e8) {
                    Button("Quedarme con lo mío", action: alQuedarme).tlsBoton(.principal)
                    Button("Usar lo de fuera", action: alUsarFuera).tlsBoton(.secundario)
                    Button("Ver diferencias", action: alVer).tlsBoton(.enlace, alto: TLSAltura.botonPrincipal)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(TLSEspacio.e16)
        .background(forma.fill(TLSEstado.atencion.tinte.color))
        .overlay(forma.strokeBorder(TLSEstado.atencion.color.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conflicto: esta nota cambió fuera de la app")
    }
}

/// Una línea de la comparación.
struct LineaDiferencia: Identifiable, Hashable {
    enum Lado: Hashable { case igual, soloMia, soloFuera }
    let id: Int
    let lado: Lado
    let texto: String
}

/// Comparación línea a línea de dos textos (lo mismo, solo tuyo, solo de fuera).
enum Diferencias {
    static func lineas(mia: String, deFuera: String) -> [LineaDiferencia] {
        let a = deFuera.components(separatedBy: "\n")
        let b = mia.components(separatedBy: "\n")
        let d = b.difference(from: a)
        var quitadas = Set<Int>(), puestas = Set<Int>()
        for c in d {
            switch c {
            case .remove(let o, _, _): quitadas.insert(o)
            case .insert(let o, _, _): puestas.insert(o)
            }
        }
        var out: [LineaDiferencia] = []
        var i = 0, j = 0, n = 0
        while i < a.count || j < b.count {
            if i < a.count, quitadas.contains(i) {
                out.append(LineaDiferencia(id: n, lado: .soloFuera, texto: a[i])); i += 1
            } else if j < b.count, puestas.contains(j) {
                out.append(LineaDiferencia(id: n, lado: .soloMia, texto: b[j])); j += 1
            } else {
                out.append(LineaDiferencia(id: n, lado: .igual, texto: j < b.count ? b[j] : a[i])); i += 1; j += 1
            }
            n += 1
        }
        return out
    }
}

/// Las dos versiones de una nota en conflicto, con lo que cambia marcado, y las tres salidas: lo tuyo, lo de
/// fuera o combinarlas a mano. La pueden usar el editor y «Revisar» (`resolver(_:eleccion:)`).
struct DiferenciasVersiones: View {
    let titulo: String
    /// Cuerpos (sin propiedades) de las dos versiones.
    let mia: String
    let deFuera: String
    let alQuedarme: () -> Void
    let alUsarFuera: () -> Void
    let alCombinar: (String) -> Void
    @State private var combinando = false
    @State private var combinado = ""
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            Text("Diferencias en «\(titulo)»")
                .tlsTexto(TLSTipo.tituloSeccion)
                .foregroundStyle(TLSPaleta.texto.color)
            HStack(spacing: TLSEspacio.e16) {
                leyenda("Solo en lo tuyo", icono: "plus.circle.fill", color: TLSEstado.bien)
                leyenda("Solo en lo de fuera", icono: "minus.circle.fill", color: TLSEstado.atencion)
            }
            if combinando {
                Text("Escribe cómo debe quedar. Se guarda tal cual y tu versión anterior va a «Archivo».")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                TextEditor(text: $combinado)
                    .font(TLSTipo.textoPlano.font())
                    .scrollContentBackground(.hidden)
                    .padding(TLSEspacio.e8)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.campo).fill(TLSPaleta.bandeja.color))
                    .accessibilityLabel("Texto combinado")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Diferencias.lineas(mia: mia, deFuera: deFuera)) { l in
                            fila(l)
                        }
                    }
                    .padding(.vertical, TLSEspacio.e8)
                }
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque).fill(TLSPaleta.bandeja.color))
                .accessibilityLabel("Comparación línea a línea")
            }
            HStack(spacing: TLSEspacio.e8) {
                if combinando {
                    Button("Guardar la combinación") { alCombinar(combinado); cerrar() }.tlsBoton(.principal)
                    Button("Volver a la comparación") { combinando = false }.tlsBoton(.secundario)
                } else {
                    Button("Quedarme con lo mío") { alQuedarme(); cerrar() }.tlsBoton(.principal)
                    Button("Usar lo de fuera") { alUsarFuera(); cerrar() }.tlsBoton(.secundario)
                    Button("Combinar a mano") { combinado = mia; combinando = true }.tlsBoton(.secundario)
                }
                Spacer()
                Button("Cerrar") { cerrar() }.tlsBoton(.discreto).keyboardShortcut(.cancelAction)
            }
        }
        .padding(TLSEspacio.e24)
        .frame(minWidth: 640, idealWidth: 760, minHeight: 480, idealHeight: 620)
        .background(TLSPaleta.superficieElevada.color)
    }

    private func leyenda(_ t: String, icono: String, color: TLSEstado) -> some View {
        Label {
            Text(t).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.texto.color)
        } icon: {
            Image(systemName: icono).foregroundStyle(color.color.color)
        }
    }

    private func fila(_ l: LineaDiferencia) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
            Image(systemName: l.lado == .soloMia ? "plus" : (l.lado == .soloFuera ? "minus" : "circle"))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(l.lado == .igual ? Color.clear
                                 : (l.lado == .soloMia ? TLSEstado.bien.color.color : TLSEstado.atencion.color.color))
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(l.texto.isEmpty ? " " : l.texto)
                .tlsTexto(TLSTipo.textoPlano)
                .foregroundStyle(TLSPaleta.texto.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TLSEspacio.e12)
        .padding(.vertical, 1)
        .background(l.lado == .igual ? Color.clear
                    : (l.lado == .soloMia ? TLSEstado.bien.tinte.color : TLSEstado.atencion.tinte.color))
        .accessibilityElement(children: .combine)
        .accessibilityLabel((l.lado == .soloMia ? "Solo en lo tuyo: " : (l.lado == .soloFuera ? "Solo en lo de fuera: " : "")) + l.texto)
    }
}
