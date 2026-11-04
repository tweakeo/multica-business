import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. La vista previa de un paso (PLAN §6.7: «vista previa» antes de «Aplicar»), en diferencias que lee
// alguien no técnico: «Nueva: Diagnóstico, en 1 · Dirección», «Esto se añadirá a Área», las líneas nuevas marcadas y
// las propiedades por su nombre; los ajustes de la carpeta, resumidos en palabras. Después de «Aplicar», el resumen
// con «Deshacer». Y «Lo que he entendido» del paso 1: la foto de las áreas, el cuello (el destacado) y las etapas.

/// Una línea de la diferencia, ya en llano.
enum LineaLegible: Hashable {
    case anadida(String)
    case quitada(String)
    case propiedad(String, String)
    case propiedades(String)
    case resumen(String)
    case mas(Int)
}

enum DiferenciaLegible {
    /// Nombre que se enseña de un fichero («Ajustes de la carpeta» en vez de la ruta técnica).
    static func nombre(_ p: VaultPath) -> String {
        switch p.raw {
        case VaultLayout.configFile: return "Ajustes de la carpeta"
        case VaultLayout.layoutFile: return "Cómo se ordena la carpeta"
        case "AGENTS.md": return "Instrucciones para los asistentes"
        default: return p.stem
        }
    }

    /// Dónde está, en palabras («en 1 · Dirección › Rutinas»; nada si está en la raíz).
    static func donde(_ p: VaultPath) -> String? {
        let partes = p.components.dropLast()
        guard !partes.isEmpty, !p.raw.hasPrefix(".tls/") else { return nil }
        return "en " + partes.joined(separator: " › ")
    }

    /// Nombre que se enseña de un cambio: el título del documento (su `# …`) o el nombre del fichero.
    static func nombre(_ c: CambioPrevisto) -> String {
        if c.ruta.raw.hasPrefix(".tls/") || c.ruta.raw == "AGENTS.md" { return nombre(c.ruta) }
        guard let t = c.despues ?? c.antes, let h = tituloDe(t), !h.isEmpty else { return nombre(c.ruta) }
        return c.ruta.stem == "Área" ? "Ficha del área \(h)" : h
    }

    static func tituloDe(_ texto: String) -> String? {
        for l in texto.split(separator: "\n", omittingEmptySubsequences: false).prefix(60) where l.hasPrefix("# ") {
            return String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// El grupo de un cambio en la vista previa: su área (o el Buzón) o «Tu carpeta» si está en la raíz.
    static func grupo(_ p: VaultPath) -> String {
        guard p.components.count > 1, !p.raw.hasPrefix(".tls/") else { return "Tu carpeta" }
        return p.components[0]
    }

    static func titulo(_ c: CambioPrevisto) -> String {
        let n = nombre(c)
        switch c.clase {
        case .crear: return "Nueva: \(n)"
        case .cambiar: return soloAnade(c) ? "Esto se añadirá a «\(n)»" : "Cambia «\(n)»"
        case .copiar: return c.resumen.isEmpty ? "Copia: \(n)" : "\(c.resumen) en «\(n)»"
        }
    }

    /// Solo añade líneas (no se quita ni se cambia ninguna de las que había).
    static func soloAnade(_ c: CambioPrevisto) -> Bool {
        guard let a = c.antes, let d = c.despues else { return false }
        let nuevas = Set(d.components(separatedBy: "\n"))
        return a.components(separatedBy: "\n").allSatisfy { $0.isEmpty || nuevas.contains($0) }
    }

    /// Las líneas que se enseñan de un cambio.
    static func lineas(_ c: CambioPrevisto, maximo: Int = 12) -> [LineaLegible] {
        guard let despues = c.despues else { return [] }
        if c.ruta.raw.hasPrefix(".tls/") { return ajustes(c) }
        let nuevas = despues.components(separatedBy: "\n")
        let props = rangoPropiedades(nuevas)
        var out: [LineaLegible] = []
        switch c.clase {
        case .crear:
            let claves = props.compactMap { clave(nuevas[$0])?.0 }.filter { !$0.hasPrefix("tls_") && $0 != "id" }
            if !claves.isEmpty { out.append(.propiedades("Propiedades: " + claves.joined(separator: ", "))) }
            let cuerpo = nuevas.indices.filter { !props.contains($0) && !nuevas[$0].trimmingCharacters(in: .whitespaces).isEmpty
                && nuevas[$0] != "---" }
            out += cuerpo.prefix(maximo).map { .anadida(limpia(nuevas[$0])) }
            if cuerpo.count > maximo { out.append(.mas(cuerpo.count - maximo)) }
        case .cambiar:
            let antes = (c.antes ?? "").components(separatedBy: "\n")
            let siguen = Set(nuevas)
            var todas: [LineaLegible] = []
            for l in antes where !l.trimmingCharacters(in: .whitespaces).isEmpty && !siguen.contains(l) && l != "---" {
                todas.append(.quitada(limpia(l)))
            }
            for i in c.lineasCambiadas.sorted() where i < nuevas.count {
                let l = nuevas[i]
                guard !l.trimmingCharacters(in: .whitespaces).isEmpty, l != "---" else { continue }
                if props.contains(i), let (k, v) = clave(l) {
                    if k.hasPrefix("tls_") || k == "id" { continue }
                    todas.append(.propiedad(k, v.isEmpty ? "(lista)" : v))
                } else {
                    todas.append(.anadida(limpia(l)))
                }
            }
            out = Array(todas.prefix(maximo))
            if todas.count > maximo { out.append(.mas(todas.count - maximo)) }
        case .copiar:
            break
        }
        return out
    }

    /// Las líneas de las propiedades (entre los dos `---` del principio).
    static func rangoPropiedades(_ l: [String]) -> Set<Int> {
        guard l.first == "---", let fin = l.dropFirst().firstIndex(of: "---") else { return [] }
        return Set(1..<fin)
    }

    static func clave(_ linea: String) -> (String, String)? {
        guard !linea.hasPrefix(" "), !linea.hasPrefix("-"), let i = linea.firstIndex(of: ":") else { return nil }
        let k = String(linea[..<i]).trimmingCharacters(in: .whitespaces)
        let v = String(linea[linea.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return k.isEmpty ? nil : (k, v)
    }

    /// Quita lo que solo es formato (almohadillas de los títulos, guiones de las listas, corchetes de los enlaces).
    static func limpia(_ l: String) -> String {
        var t = l.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix("#") { t.removeFirst() }
        if t.hasPrefix("- ") { t = "• " + t.dropFirst(2) }
        t = t.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Los ajustes de la carpeta, en palabras: qué apartados cambian.
    static func ajustes(_ c: CambioPrevisto) -> [LineaLegible] {
        guard let d = c.despues else { return [] }
        let nuevas = d.components(separatedBy: "\n")
        var apartados: [String] = []
        for i in c.lineasCambiadas.sorted() where i < nuevas.count {
            var j = i
            while j > 0, nuevas[j].hasPrefix(" ") || nuevas[j].hasPrefix("-") || nuevas[j].isEmpty { j -= 1 }
            guard let (k, _) = clave(nuevas[j]) else { continue }
            let t = apartado(k)
            if !apartados.contains(t) { apartados.append(t) }
        }
        if c.ruta.raw == VaultLayout.layoutFile { return [.resumen("Las carpetas de serie de la app: seis áreas, Buzón y Archivo")] }
        return apartados.map { .resumen($0) }
    }

    static func apartado(_ clave: String) -> String {
        switch clave {
        case "capacidades": "Qué funciona sin ti: quién hace cada función"
        case "agenda": "Las horas al día que planificas como mucho"
        case "vocabulario": "Cómo llamas tú a las cosas"
        case "privado": "Lo privado (nada, de momento)"
        case "version", "id", "clase", "creada": "Datos de la carpeta: es una copia de trabajo"
        default: "Otros ajustes"
        }
    }
}

/// La vista previa de un paso.
struct PanelVistaPrevia: View {
    @Bindable var modelo: ModeloPuesta
    let vista: VistaPreviaPaso
    var titulo = "Lo que se escribirá en tu carpeta"

    /// Los cambios por área (en el orden en que salen), para leerlos de un vistazo.
    var grupos: [(String, [CambioPrevisto])] {
        var orden: [String] = []
        var por: [String: [CambioPrevisto]] = [:]
        for c in vista.cambios {
            let g = DiferenciaLegible.grupo(c.ruta)
            if por[g] == nil { orden.append(g) }
            por[g, default: []].append(c)
        }
        func clave(_ g: String) -> Int { g.first?.wholeNumberValue ?? (g == "Tu carpeta" ? 99 : 50) }
        return orden.sorted { clave($0) < clave($1) }.map { ($0, por[$0] ?? []) }
    }

    var body: some View {
        BloquePuesta(rotulo: titulo, icono: "eye") {
            VStack(alignment: .leading, spacing: TLSEspacio.e12) {
                HStack(spacing: TLSEspacio.e8) {
                    Image(systemName: vista.nadaQueEscribir ? "checkmark.shield" : "doc.badge.plus")
                        .foregroundStyle(TLSPaleta.principal.color)
                        .accessibilityHidden(true)
                    Text(vista.resumen)
                        .tlsTexto(TLSTipo.interfazFuerte.tamano(14, interlinea: 19))
                        .foregroundStyle(TLSPaleta.texto.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("puesta.vistaPrevia")
                ForEach(vista.avisos, id: \.self) { AvisoEnLinea(estado: .atencion, texto: $0) }
                ForEach(vista.fueraDeLaCarpeta, id: \.self) { NotaPuesta(icono: "info.circle", texto: $0) }
                ForEach(grupos, id: \.0) { g in
                    VStack(alignment: .leading, spacing: 0) {
                        Rotulo(g.0).padding(.top, TLSEspacio.e4).padding(.bottom, 2)
                        ForEach(g.1) { c in
                            FilaCambio(cambio: c)
                            if c.id != g.1.last?.id {
                                Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).accessibilityHidden(true)
                            }
                        }
                    }
                }
                if !vista.nadaQueEscribir {
                    Text("Todo se escribe de una vez y se puede deshacer. No se borra nada.")
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
        }
    }
}

/// Un fichero que cambia: qué le pasa y, al abrirlo, sus líneas.
struct FilaCambio: View {
    let cambio: CambioPrevisto
    @State private var abierta = false

    var body: some View {
        let lineas = DiferenciaLegible.lineas(cambio)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Button {
                abierta.toggle()
            } label: {
                HStack(spacing: TLSEspacio.e8) {
                    Image(systemName: icono)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(DiferenciaLegible.titulo(cambio))
                            .tlsTexto(TLSTipo.interfazFuerte)
                            .foregroundStyle(TLSPaleta.texto.color)
                            .lineLimit(2)
                        if let d = DiferenciaLegible.donde(cambio.ruta) {
                            Text(d).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if !lineas.isEmpty {
                        Image(systemName: abierta ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(EstiloFila())
            .disabled(lineas.isEmpty)
            .accessibilityLabel(DiferenciaLegible.titulo(cambio) + (DiferenciaLegible.donde(cambio.ruta).map { ", \($0)" } ?? ""))
            .accessibilityHint(lineas.isEmpty ? "" : (abierta ? "Oculta lo que cambia" : "Enseña lo que cambia"))
            if abierta {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lineas.enumerated()), id: \.offset) { _, l in LineaCambio(linea: l) }
                }
                .padding(.leading, 40)
                .padding(.bottom, TLSEspacio.e8)
            }
        }
    }

    private var icono: String {
        switch cambio.clase {
        case .crear: "doc.badge.plus"
        case .cambiar: "pencil.line"
        case .copiar: "doc.on.doc"
        }
    }
}

struct LineaCambio: View {
    let linea: LineaLegible

    var body: some View {
        switch linea {
        case .anadida(let t):
            fila("plus", t, fondo: TLSEstado.bien.tinte.color, etiqueta: "Se añade")
        case .quitada(let t):
            fila("minus", t, fondo: TLSPaleta.bandeja.color, etiqueta: "Deja de estar", tachada: true)
        case .propiedad(let k, let v):
            fila("tag", "\(k): \(v)", fondo: TLSPaleta.principalSuave.color, etiqueta: "Propiedad")
        case .propiedades(let t), .resumen(let t):
            fila("info.circle", t, fondo: .clear, etiqueta: "")
        case .mas(let n):
            Text("… y \(TLSFormat.cuenta(n, "línea más", "líneas más"))")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
        }
    }

    private func fila(_ icono: String, _ t: String, fondo: Color, etiqueta: String, tachada: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icono)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            Text(t)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.texto.color)
                .strikethrough(tachada)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fondo))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiqueta.isEmpty ? t : "\(etiqueta): \(t)")
    }
}

/// Lo hecho en este paso: el resumen con «Deshacer», o lo que ya estaba hecho al volver.
struct ResumenPaso: View {
    @Bindable var modelo: ModeloPuesta
    let paso: PasoPuesta

    var body: some View {
        let estado = modelo.motor.estado.paso(paso)
        if let a = modelo.aplicado, a.paso == paso {
            tarjeta(texto: a.texto, detalle: a.detalle, deshacer: a.sePuedeDeshacer)
        } else if estado.fase == .aplicado, paso.escribeEnLaCarpeta, !modelo.repasando {
            tarjeta(texto: "Ya está aplicado: \(estado.resumen ?? "hecho")", detalle: nil, deshacer: estado.plan != nil)
        } else if estado.fase == .omitido {
            HStack(spacing: TLSEspacio.e8) {
                AvisoEnLinea(estado: .sinDato, texto: estado.resumen ?? "Lo dejaste para más tarde")
                Button("Volver a mirarlo") { modelo.actualizar { $0.marcarDeshecho(paso) }; modelo.prepararVistaPreviaSiToca() }
                    .tlsBoton(.enlace)
            }
        }
    }

    private func tarjeta(texto: String, detalle: String?, deshacer: Bool) -> some View {
        HStack(alignment: .center, spacing: TLSEspacio.e12) {
            Image(systemName: TLSEstado.bien.simbolo)
                .font(.system(size: 18))
                .foregroundStyle(TLSEstado.bien.color.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(texto).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let detalle {
                    Text(detalle).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if deshacer {
                Button("Deshacer") { Task { await modelo.deshacerPaso(paso) } }
                    .tlsBoton(.enlace)
                    .accessibilityIdentifier("puesta.deshacer")
            }
        }
        .padding(TLSEspacio.e16)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSEstado.bien.tinte.color))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("puesta.resumen")
    }
}

/// Puntos de 1 a 5 (funciona, depende de ti), con su número para VoiceOver.
struct PuntosEscala: View {
    let valor: Int?
    var maximo = 5
    let nombre: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...maximo, id: \.self) { i in
                Circle()
                    .fill(i <= (valor ?? 0) ? TLSPaleta.principal.color : Color.clear)
                    .overlay(Circle().strokeBorder(i <= (valor ?? 0) ? TLSPaleta.principal.color : TLSPaleta.bordeControl.color, lineWidth: 1))
                    .frame(width: 9, height: 9)
            }
            Text(valor.map { "\($0)" } ?? "—")
                .tlsTexto(TLSTipo.cifraFila)
                .foregroundStyle(TLSPaleta.texto.color)
                .frame(minWidth: 14, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(valor.map { "\(nombre): \($0) de \(maximo)" } ?? "\(nombre): pendiente")
    }
}

/// «Lo que he entendido» (paso 1): la foto de tus áreas, el cuello y las etapas, en lenguaje llano.
struct LoQueHeEntendidoVista: View {
    let entendido: LoQueHeEntendido
    let etapas: [EtapaStd]

    func nombreEtapa(_ n: Int?) -> String {
        guard let n else { return "Pendiente" }
        if let e = etapas.first(where: { $0.num == n }) { return "\(n) · \(e.nombre)" }
        return "Etapa \(n)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            Group {
                if let c = entendido.cuello {
                    Destacado(rotulo: "Dónde está el cuello") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: TLSEspacio.e8) {
                                IconoArea(c.tlsArea, tamano: 24, sobreCabecera: true)
                                Text(c.nombre).tlsTexto(TLSTipo.cifraMedia)
                            }
                            Text(entendido.porQue).tlsTexto(TLSTipo.lectura).fixedSize(horizontal: false, vertical: true)
                            Text("El cuello es el área que más frena a las demás: se trabaja esa primero. Es lo primero que mirarás en Hoy y en el mapa de Dirección.")
                                .tlsTexto(TLSTipo.interfaz).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    DestacadoVacio(rotulo: "Dónde está el cuello", texto: entendido.porQue)
                }
            }
            .frame(minHeight: 120)
            .accessibilityIdentifier("puesta.cuello")
            BloquePuesta(rotulo: "La foto de tus áreas", icono: "square.grid.3x2") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entendido.filas, id: \.area) { f in
                        filaArea(f)
                        if f.area != entendido.filas.last?.area {
                            Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).accessibilityHidden(true)
                        }
                    }
                }
                if let g = entendido.etapaGlobal {
                    NotaPuesta(icono: "stairs", texto: "Tu empresa está en la etapa \(nombreEtapa(g)): la del área más atrasada entre Ventas, Entrega y Finanzas.")
                }
            }
        }
    }

    private func filaArea(_ f: LoQueHeEntendido.Fila) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: TLSEspacio.e12) {
                IconoArea(f.area.tlsArea, tamano: 24)
                Text(f.area.nombre)
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .frame(width: 92, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Rotulo("Funciona")
                    PuntosEscala(valor: f.funciona, nombre: "Funciona")
                }
                VStack(alignment: .leading, spacing: 1) {
                    Rotulo("Depende de ti")
                    PuntosEscala(valor: f.depende, nombre: "Depende de ti")
                }
                Spacer(minLength: 0)
                PastillaEtapa(nombreEtapa(f.etapa), paso: max(0, (f.etapa ?? 1) - 1), de: 6)
                if entendido.cuello == f.area {
                    PastillaEstado(.atencion, palabra: "Cuello")
                }
            }
            if f.dolor != nil || f.meta != nil {
                Text([f.dolor.map { "Duele: \($0)" }, f.meta.map { "Quieres: \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 36)
            }
            if let c = f.cita {
                Text("«\(c)»")
                    .tlsTexto(TLSTipo.interfaz.enItalica)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
