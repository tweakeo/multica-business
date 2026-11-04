import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol mika. La línea de Mika en Hoy (PLAN §6.2 punto 7: «Revisé a las 8:45: nada en rojo», que sustituye al
// ritual diario). Sale de la última revisión de su rutina «¿Algo rojo?» (`AgentHost.ultimaRevision`); si aún no hay
// ninguna de hoy (sin motor, o antes de las 8:45), de los chequeos de la app, que son los mismos que mira Mika antes
// de gastar nada. Debajo, lo que Mika dejó hoy en Decisiones y, si el día ya tiene sus avisos, cuántas cosas esperan
// al resumen semanal: el presupuesto de interrupciones se respeta también aquí.

/// Lo que dice la línea de Mika.
struct TextoLineaMika: Sendable, Hashable {
    let texto: String
    let rojo: Bool
    /// «Te dejé 1 propuesta en Decisiones», «2 cosas más esperan al resumen del lunes».
    let detalle: String?
    /// La revisión la hizo Mika (no solo los chequeos de la app).
    let deMika: Bool
}

struct LineaMikaHoy: View {
    let datos: DatosHoy
    let sesion: VaultSession
    @State private var revision: (fecha: Date, resumen: String?)?
    @Environment(\.navegacion) private var nav
    @Environment(\.navegar) private var navegar

    var body: some View {
        let a = AsistentesDeLaEmpresa.de(sesion)
        let t = Self.texto(datos: datos, sesion: sesion, revision: revision)
        HStack(spacing: TLSEspacio.e12) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TLSPaleta.sobrePrincipal.color)
                .frame(width: 28, height: 28)
                // F4 · corrector (P3): azul noche; el violeta es del destacado de la pantalla.
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TLSPaleta.principal.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: t.rojo ? TLSEstado.mal.simbolo : TLSEstado.bien.simbolo)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.rojo ? TLSPaleta.mal.color : TLSPaleta.bien.color)
                        .accessibilityLabel(t.rojo ? "En rojo" : "Bien")
                    Text("Mika · \(t.texto)").tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("hoy.mika")
                }
                Text(t.detalle ?? (a.encendidos == false ? "Los asistentes están en pausa: no empiezan nada nuevo." : "Pregúntale lo que quieras sobre lo que ves."))
                    .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hoy.mika.detalle")
            }
            Spacer(minLength: 0)
            if t.detalle?.contains("Decisiones") == true {
                Button("Ver") { navegar(.decisiones, modo: .raiz) }.tlsBoton(.enlace)
            }
            Button {
                ConversacionMika.de(sesion).alternar(contexto: .de(nav, sesion: sesion))
            } label: {
                HStack(spacing: 6) {
                    Text("Hablar con Mika")
                    Tecla("⌘J")
                }
            }
            .tlsBoton(.secundario)
            .help("Mika con lo que tienes en pantalla (⌘J)")
            .accessibilityIdentifier("hoy.mika.hablar")
        }
        .padding(TLSEspacio.e16)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mika")
        .task(id: a.revision) {
            revision = await a.host?.ultimaRevision("mika.algo-rojo")
        }
    }

    /// El texto de la línea. `revision`: la última de «¿Algo rojo?» (si es de hoy, manda).
    @MainActor
    static func texto(datos d: DatosHoy, sesion: VaultSession, revision: (fecha: Date, resumen: String?)? = nil) -> TextoLineaMika {
        var texto = d.lineaMika
        var deMika = false
        if let r = revision, let resumen = r.resumen?.trimmingCharacters(in: .whitespacesAndNewlines), !resumen.isEmpty,
           LocalDate(date: r.fecha, timeZone: TimeZone(identifier: "Europe/Madrid") ?? .current) == d.hoy {
            texto = resumen
            deMika = true
        }
        // Lo que dejaron hoy los asistentes en Decisiones (y se ve hoy) y lo que espera al resumen semanal.
        let deHoy = d.decisiones.filter { $0.gobierno?.asistente != nil && $0.creada == d.hoy }
        var partes: [String] = []
        if !deHoy.isEmpty {
            let n = deHoy.count
            partes.append(n == 1 ? "Hoy te dejamos 1 cosa en Decisiones" : "Hoy te dejamos \(n) cosas en Decisiones")
        }
        let resto = d.bandeja.alResumen.count
        if resto > 0 {
            partes.append(resto == 1 ? "1 más espera al resumen semanal para no interrumpirte"
                          : "\(resto) más esperan al resumen semanal para no interrumpirte")
        }
        let detalle = partes.isEmpty ? nil : partes.joined(separator: "; ") + "."
        return TextoLineaMika(texto: texto, rojo: d.hayRojo, detalle: detalle, deMika: deMika)
    }
}
