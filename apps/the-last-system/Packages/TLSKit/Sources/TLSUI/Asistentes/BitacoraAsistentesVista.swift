import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes (PLAN §4.4, §6.5; SISTEMAS EQ2). La Bitácora de los asistentes (`6 · Equipo/Bitácora/AAAA-MM.md`)
// como una lista que se lee: por días, quién, qué hizo, cómo acabó y cuánto usó (como parte de su tope), con la marca
// «Simulado» en lo del ejemplo. Se elige el mes y se filtra por asistente. Solo lee: la Bitácora la escribe la app al
// cerrar cada trabajo y nadie la edita.

struct BitacoraAsistentesVista: View {
    let sesion: VaultSession
    let lectura: LecturaAsistentes
    /// Solo la de este asistente (en su ficha): sin filtros.
    var fijo: String?
    @State private var mes: String?
    @State private var filtro: String?
    @Environment(\.navegar) private var navegar

    private var mesElegido: String {
        if let mes, lectura.mesesDeBitacora.contains(mes) { return mes }
        return lectura.mesesDeBitacora.contains(lectura.mes) ? lectura.mes : (lectura.mesesDeBitacora.first ?? lectura.mes)
    }

    var body: some View {
        let delMes = lectura.bitacora.filter { $0.mes == mesElegido && (fijo == nil || $0.agente == fijo) }
        let quien = fijo ?? filtro
        let visibles = delMes.filter { quien == nil || $0.agente == quien }
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            barra(delMes)
            if visibles.isEmpty {
                VacioExplicado(icono: "list.bullet.rectangle",
                               titulo: "Nada apuntado en \(Self.nombreDeMes(mesElegido))",
                               porQue: fijo == nil
                                ? "Cada trabajo de un asistente deja aquí una línea: quién, qué hizo, cómo acabó y cuánto usó. Nadie la edita."
                                : "Cuando trabaje, cada trabajo dejará aquí una línea: qué hizo, cómo acabó y cuánto usó.",
                               compacto: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            } else {
                lista(visibles)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(fijo == nil ? "bitacora.asistentes" : "bitacora.asistente")
    }

    // MARK: Barra: mes y filtros

    @ViewBuilder
    private func barra(_ delMes: [ApunteBitacora]) -> some View {
        let meses = lectura.mesesDeBitacora.isEmpty ? [lectura.mes] : lectura.mesesDeBitacora
        HStack(alignment: .center, spacing: TLSEspacio.e8) {
            Menu {
                ForEach(meses, id: \.self) { m in
                    Button(FormatoFicha.capital(Self.nombreDeMes(m))) { mes = m }
                }
            } label: {
                Label(FormatoFicha.capital(Self.nombreDeMes(mesElegido)), systemImage: "calendar")
                    .tlsTexto(TLSTipo.interfazMedia)
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityLabel("Mes de la bitácora")
            .accessibilityValue(Self.nombreDeMes(mesElegido))
            .accessibilityIdentifier("bitacora.mes")
            if fijo == nil {
                let conLineas = lectura.asistentes.filter { a in delMes.contains { $0.agente == a.slug } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("Todos", n: delMes.count, elegido: filtro == nil) { filtro = nil }
                        ForEach(conLineas) { a in
                            chip(a.nombre, n: delMes.filter { $0.agente == a.slug }.count, elegido: filtro == a.slug) {
                                filtro = filtro == a.slug ? nil : a.slug
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Filtrar por asistente")
                .accessibilityIdentifier("bitacora.filtros")
            }
            Spacer(minLength: 0)
            if let ruta = rutaDelMes {
                Button("Abrir el fichero") { navegar(sesion.destino(para: ruta), modo: .entrar) }
                    .tlsBoton(.enlace)
                    .help("La bitácora del mes tal como está en la carpeta")
            }
        }
    }

    private func chip(_ titulo: String, n: Int, elegido: Bool, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                Text(titulo).tlsTexto(TLSTipo.interfazMedia)
                Text("\(n)").tlsTexto(TLSTipo.cifraFila)
            }
            .foregroundStyle(elegido ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
            .padding(.horizontal, 10)
            .frame(minHeight: TLSAltura.objetivoMinimo)
            .background(Capsule(style: .circular).fill(elegido ? TLSPaleta.principal.color : TLSPaleta.bandeja.color))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(titulo), \(n)")
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    private var rutaDelMes: VaultPath? {
        guard let layout = sesion.estructura, let d = LocalDate(parsing: mesElegido + "-01") else { return nil }
        let r = Bitacora.ruta(d, layout: layout)
        return sesion.resumen(de: r) != nil ? r : nil
    }

    // MARK: Lista por días

    private func lista(_ apuntes: [ApunteBitacora]) -> some View {
        let dias = Dictionary(grouping: apuntes, by: \.fecha).sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            ForEach(dias, id: \.key) { dia, lineas in
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo(FormatoFicha.capital(FormatoAsistentes.momento(dia, hora: nil, hoy: lectura.hoy)))
                        .padding(.leading, 4)
                    TarjetaFilas {
                        let orden = lineas.sorted { ($0.hora, $0.id) > ($1.hora, $1.id) }
                        ForEach(Array(orden.enumerated()), id: \.element.id) { i, l in
                            if i > 0 { SeparadorFila(sangria: 16) }
                            fila(l)
                        }
                    }
                }
            }
        }
    }

    private func fila(_ l: ApunteBitacora) -> some View {
        let a = lectura.asistente(l.agente)
        let tope = a?.ajustes.presupuestoMesUSD ?? 15
        return HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e12) {
            Text(l.hora).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(width: 44, alignment: .leading)
            if fijo == nil {
                HStack(spacing: 6) {
                    if let a { IconoAsistente(a, tamano: 18) }
                    Text(a?.nombre ?? AsistenteConfigurado.nombre(de: l.agente)).tlsTexto(TLSTipo.interfazFuerte)
                        .foregroundStyle(TLSPaleta.texto.color).lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(l.que).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    PastillaAsistente(palabra: FormatoFicha.capital(l.resultado), simbolo: l.estado.simbolo, estado: l.estado)
                    if let u = l.linea.usoUSD {
                        Text("Usó " + UsoDelMes.parte(u, de: tope)).tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    if l.simulado { MarcaSimulado() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let c = l.linea.capacidad {
                Text(c).tlsTexto(TLSTipo.codigo).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .help(CatalogoPrograma.deSerie.capacidades.first { $0.codigo == c }?.nombre ?? c)
            }
        }
        .padding(.horizontal, TLSEspacio.e16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([l.hora, fijo == nil ? (a?.nombre ?? l.agente) : nil, l.que, l.resultado,
                             l.linea.usoUSD.map { "usó " + UsoDelMes.parte($0, de: tope) }, l.simulado ? "Simulado" : nil]
            .compactMap { $0 }.joined(separator: ". "))
    }

    // MARK: Formato

    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
                        "noviembre", "diciembre"]

    /// «2026-10» → «octubre de 2026».
    static func nombreDeMes(_ m: String) -> String {
        let p = m.split(separator: "-")
        guard p.count == 2, let a = Int(p[0]), let n = Int(p[1]), (1...12).contains(n) else { return m }
        return "\(meses[n - 1]) de \(a)"
    }
}
