import SwiftUI
import TLSCore
import TLSDesign

// F2 · rol areas-b. Las tres secciones de Equipo › Operación (PLAN §6.5; SISTEMAS EQ1–EQ3): roles con su ocupante,
// asistentes (bitácora y uso frente al tope; vacío explicado hasta que lleguen) y la rejilla de rutinas ✓ ✕ –.

// MARK: - Roles

/// Cada rol (persona o asistente) con quien lo ocupa, su misión y sus números; un clic abre su ficha.
struct RolesEquipo: View {
    let lectura: LecturaEquipo
    let contexto: ContextoArea
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            if let f = contexto.numero("EQU-ROLES") {
                HStack(spacing: TLSEspacio.e8) {
                    Text("Roles con ocupante:").tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    Text(f.textoValor).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.texto.color)
                    if f.valorVisible, f.lectura.valor != nil { RhythmBadge(f.ritmo) }
                    if let fuente = f.lectura.fuente {
                        Text(fuente).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("El rol va antes que la persona: cada uno con su misión, lo que decide sin preguntar y sus números. Los roles los escribes tú; los asistentes no tocan esta carpeta.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            if lectura.roles.isEmpty {
                VacioExplicado(icono: "person.2", titulo: "Aún no hay roles",
                               porQue: "Cada área necesita un rol escrito en Equipo › Roles (con la plantilla «Rol»). Sin área, rol y sistema no se contrata.",
                               compacto: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(lectura.roles) { r in
                        fila(r)
                        if r.id != lectura.roles.last?.id { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).padding(.leading, 56) }
                    }
                }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
                .tlsSombra(.uno, radio: TLSRadio.mosaico)
            }
        }
        .accessibilityIdentifier("equipo.roles")
    }

    private func fila(_ r: RolEquipo) -> some View {
        let areas = r.areas.map(\.etiquetaNumerada).joined(separator: ", ")
        // F4 · rol asistentes: el rol de un asistente abre su ficha de asistente (permisos, rutinas, trabajos).
        let destino: Destino = r.esAsistente && r.ruta.stem.hasPrefix("asistente-")
            ? .asistente(String(r.ruta.stem.dropFirst("asistente-".count))) : .ficha(r.ruta)
        return Button { navegar(destino, modo: .automatico) } label: {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                Image(systemName: r.esAsistente ? "sparkle" : "person.crop.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: TLSEspacio.e8) {
                        Text(r.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        Text(r.esAsistente ? "Asistente" : "Persona").tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                        if !areas.isEmpty {
                            Text(areas).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                        }
                    }
                    if let m = r.mision {
                        Text(m).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color).lineLimit(2)
                    }
                    if !r.numeros.isEmpty {
                        Text(r.numeros.joined(separator: " · ")).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                Spacer(minLength: TLSEspacio.e8)
                if let o = r.ocupante {
                    Text(o).tlsTexto(TLSTipo.interfazMedia).foregroundStyle(TLSPaleta.texto.color)
                } else {
                    PastillaEstado(.sinDato, palabra: "Sin ocupante")
                }
            }
            .padding(.horizontal, TLSEspacio.e16)
            .padding(.vertical, TLSEspacio.e8)
            .frame(minHeight: TLSAltura.filaLista)
            .contentShape(Rectangle())
        }
        .buttonStyle(EstiloFila())
        .accessibilityLabel("\(r.nombre), \(r.esAsistente ? "asistente" : "persona"). \(r.ocupante.map { "Lo ocupa \($0)" } ?? "Sin ocupante")."
                            + (r.mision.map { " Misión: \($0)" } ?? ""))
        .accessibilityHint(r.esAsistente ? "Abre la ficha del asistente" : "Abre la ficha del rol")
    }
}

// MARK: - Asistentes

// F4 · rol asistentes: Equipo › Asistentes es `Asistentes/EquipoAsistentesVista.swift` (su estado, su uso frente al
// tope y la Bitácora del mes con filtros).

// MARK: - Rutinas

/// La rejilla de rutinas por semana: ✓ hecha, ✕ no se hizo, – no tocaba o aún a tiempo. Sale de los registros de
/// `Rutinas/` (una nota por vez que se hace). Dos semanas seguidas sin hacerse, aviso (EQU-RUT).
struct RutinasEquipo: View {
    let lectura: LecturaEquipo
    @Environment(\.navegar) private var navegar

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) {
            Text("Cada rutina, semana a semana: ✓ hecha · ✕ no se hizo · – no tocaba o aún estás a tiempo. Sale de sus registros en Rutinas.")
                .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lectura.rutinasCaidas) { r in
                AvisoEnLinea("«\(r.nombre)» lleva dos semanas seguidas sin hacerse.", estado: .mal)
            }
            if lectura.rutinas.isEmpty {
                VacioExplicado(icono: "calendar.badge.clock", titulo: "Aún no hay rutinas",
                               porQue: "Las rutinas (el inicio de semana, el cierre, la revisión del mes) viven en Dirección › Rutinas. Cuando tengas una y la hagas, aquí verás cada semana si se cumplió.",
                               compacto: true)
            } else {
                rejilla
            }
        }
        .accessibilityIdentifier("equipo.rutinas")
    }

    private var rejilla: some View {
        let hoy = lectura.hoy
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Rutina").tlsTexto(TLSTipo.rotulo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(lectura.semanas, id: \.self) { l in
                    VStack(spacing: 0) {
                        Text(l == lectura.semanas.last ? "Esta semana" : "Sem. \(Self.semanaISO(l))")
                        Text(FormatoFicha.fechaCorta(l, hoy: hoy))
                    }
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 84)
                }
            }
            .padding(.horizontal, TLSEspacio.e16)
            .frame(minHeight: 40)
            .accessibilityHidden(true)
            ForEach(lectura.rutinas) { r in
                Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let destino = r.ficha.map({ Destino.ficha($0) }) ?? r.carpeta.map({ Destino.carpeta($0) }) {
                            Button(r.nombre) { navegar(destino, modo: .automatico) }
                                .buttonStyle(.plain)
                                .tlsTexto(TLSTipo.interfazFuerte)
                                .foregroundStyle(TLSPaleta.texto.color)
                        } else {
                            Text(r.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                        }
                        Text([r.cadencia.map { FormatoFicha.capital($0.rawValue) }, r.ultimo.map { "última el \(FormatoFicha.fechaCorta($0, hoy: hoy))" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(r.celdas, id: \.lunes) { c in celda(c, rutina: r.nombre).frame(width: 84) }
                }
                .padding(.horizontal, TLSEspacio.e16)
                .frame(minHeight: TLSAltura.filaLista)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(r.nombre)
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rejilla de rutinas por semana")
        .accessibilityIdentifier("equipo.rutinas.rejilla")
    }

    private func celda(_ c: CeldaRutina, rutina: String) -> some View {
        VStack(spacing: 1) {
            Image(systemName: c.marca.simbolo)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.marca.estado.color.color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(c.marca == .noToca || c.marca == .pendiente ? Color.clear : c.marca.estado.tinte.color))
            if let f = c.fraccion {
                Text(f).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
        .help(c.detalle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rutina), semana del \(FormatoFicha.fechaCorta(c.lunes, hoy: lectura.hoy)): \(c.marca.palabra). \(c.detalle)")
    }

    /// Número de semana ISO («42»).
    static func semanaISO(_ d: LocalDate) -> Int {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal.component(.weekOfYear, from: d.date())
    }
}
