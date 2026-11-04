import Foundation
import TLSAgents
import TLSCore

// F5 · rol buzon-relevo. Carpeta › Buzón (PLAN §4.4, SISTEMAS CO1): el registro del correo del mes
// (`Buzón/Correo AAAA-MM.md`, lo escribe el Cartero con `tls_anotar_correo`) leído como una vista por día, con la tarea o
// el borrador que salió de cada correo; los informes de importación; las propuestas pendientes y lo que aún está por
// ordenar. Todo sale de la foto de la carpeta: aquí no se escribe nada.
//
// Lo privado se queda en «correo privado de X»: ni asunto, ni texto, ni enlace para abrirlo (su referencia es opaca,
// `privado:<huella>`), y de un correo privado nunca salen tareas.

/// Una ficha (tarea o borrador) que salió de un correo.
struct EnlaceDelBuzon: Sendable, Hashable, Identifiable {
    enum Clase: String, Sendable, Hashable { case tarea, borrador }

    let clase: Clase
    let ruta: VaultPath
    let titulo: String
    /// «Por hacer», «Pendiente de tu OK», «Abierto en Mail»…
    let estado: String?

    var id: String { ruta.raw }

    /// «Tarea» o «Respuesta en borrador».
    var rotulo: String { clase == .tarea ? "Tarea" : "Respuesta en borrador" }
}

/// Una línea del registro: un correo, cómo lo clasificó el Cartero y adónde fue.
struct LineaDelBuzon: Sendable, Hashable, Identifiable {
    let dia: LocalDate
    /// Orden dentro del día (para que dos líneas iguales no se confundan).
    let orden: Int
    let hora: String
    /// «Nombre <correo>» o «correo privado de X».
    let de: String
    /// `nil` en lo privado (el registro guarda «—»).
    let asunto: String?
    let tipo: TipoDeCorreo?
    let tipoTexto: String
    /// Lo que anotó el Cartero: «tarea en Finanzas», «lo miras tú (privado)»…
    let destino: String
    let estado: EstadoEntradaCorreo?
    let estadoTexto: String
    let plazo: LocalDate?
    /// `message://%3C…%3E` o `privado:<huella>`.
    let referencia: String?
    /// Las fichas que salieron de este correo (por su enlace en `origen` o `en_respuesta_a`).
    var enlazados: [EnlaceDelBuzon] = []

    var id: String { "\(dia)#\(orden)" }

    var privado: Bool {
        if let r = referencia { return r.hasPrefix(EnlaceDeCorreo.prefijoPrivado) }
        return LectorRegistroBuzon.esPrivado(de)
    }

    /// El enlace que abre el mensaje en Mail (`nil` en lo privado: no se abre desde aquí).
    var enlaceMail: URL? {
        guard !privado, let r = referencia, let id = EnlaceDeCorreo.id(r) else { return nil }
        return URL(string: EnlaceDeCorreo.enlace(id))
    }

    /// El nombre del remitente sin su dirección («Laura Pérez»), o la frase de lo privado.
    var quien: String {
        if privado { return de }
        if let i = de.firstIndex(of: "<") {
            let n = de[..<i].trimmingCharacters(in: .whitespaces)
            if !n.isEmpty { return n }
        }
        return de
    }

    /// La dirección («laura@example.com»), si la hay y no es privado.
    var direccion: String? {
        guard !privado, let a = de.firstIndex(of: "<"), let b = de.lastIndex(of: ">"), a < b else { return nil }
        let d = de[de.index(after: a)..<b].trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? nil : d
    }

    /// Con un plazo oficial: va en rojo.
    var enRojo: Bool { plazo != nil }
}

/// Un día del registro (sección `## AAAA-MM-DD`).
struct DiaDelBuzon: Sendable, Hashable, Identifiable {
    let dia: LocalDate
    var lineas: [LineaDelBuzon]

    var id: String { dia.description }
    var privados: Int { lineas.filter(\.privado).count }
    var conPlazo: Int { lineas.filter(\.enRojo).count }
    var porRevisar: Int { lineas.filter { $0.estado == .propuesto }.count }
}

/// Lee el texto de un `Correo AAAA-MM.md` (forma de «Registro del Buzón v1»). Tolera ediciones a mano: una línea que no
/// se entiende se salta; una sección que no es una fecha, también.
enum LectorRegistroBuzon {
    static let marca = "<!-- tls:correo "

    static func esPrivado(_ de: String) -> Bool {
        TextFolding.fold(de).hasPrefix("correo privado de")
    }

    /// Los días del registro, en el orden del fichero.
    static func leer(_ texto: String) -> [DiaDelBuzon] {
        var dias: [DiaDelBuzon] = []
        var actual: LocalDate?
        var lineas: [LineaDelBuzon] = []
        func cerrar() {
            if let d = actual, !lineas.isEmpty {
                if let i = dias.firstIndex(where: { $0.dia == d }) {
                    dias[i].lineas += lineas
                } else {
                    dias.append(DiaDelBuzon(dia: d, lineas: lineas))
                }
            }
            lineas = []
        }
        for bruta in texto.components(separatedBy: .newlines) {
            let l = bruta.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("## ") {
                cerrar()
                actual = LocalDate(parsing: String(l.dropFirst(3)).trimmingCharacters(in: .whitespaces))
                continue
            }
            if l.hasPrefix("# ") { cerrar(); actual = nil; continue }
            guard let d = actual, l.hasPrefix("- ") else { continue }
            let previas = (dias.first { $0.dia == d }?.lineas.count ?? 0) + lineas.count
            if let linea = linea(l, dia: d, orden: previas) { lineas.append(linea) }
        }
        cerrar()
        return dias
    }

    /// Una línea `- hora · de · asunto · tipo · destino · estado[ · PLAZO AAAA-MM-DD] <!-- tls:correo {…} -->`.
    static func linea(_ texto: String, dia: LocalDate, orden: Int = 0) -> LineaDelBuzon? {
        var cuerpo = String(texto.dropFirst(2))
        var referencia: String?
        if let i = cuerpo.range(of: marca) {
            let resto = cuerpo[i.upperBound...]
            if let f = resto.range(of: "-->") {
                let json = resto[..<f.lowerBound].trimmingCharacters(in: .whitespaces)
                if let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] {
                    referencia = o["mensaje"] as? String
                }
            }
            cuerpo = String(cuerpo[..<i.lowerBound])
        }
        let partes = cuerpo.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard partes.count >= 2 else { return nil }
        func parte(_ n: Int) -> String { n < partes.count ? partes[n] : "" }
        var plazo: LocalDate?
        var resto = Array(partes.dropFirst(6))
        if let i = resto.firstIndex(where: { $0.uppercased().hasPrefix("PLAZO ") }) {
            plazo = LocalDate(parsing: String(resto[i].dropFirst(6)).trimmingCharacters(in: .whitespaces))
            resto.remove(at: i)
        }
        let de = parte(1)
        let asuntoBruto = parte(2)
        let privado = referencia?.hasPrefix(EnlaceDeCorreo.prefijoPrivado) ?? esPrivado(de)
        let asunto: String? = privado || asuntoBruto.isEmpty || asuntoBruto == "—" ? nil : asuntoBruto
        let tipoTexto = parte(3)
        let estadoTexto = parte(5)
        return LineaDelBuzon(
            dia: dia, orden: orden, hora: parte(0), de: privado && !esPrivado(de) ? "correo privado" : de, asunto: asunto,
            tipo: TipoDeCorreo(leyendo: tipoTexto), tipoTexto: tipoTexto, destino: parte(4),
            estado: EstadoEntradaCorreo(leyendo: estadoTexto), estadoTexto: estadoTexto, plazo: plazo,
            referencia: referencia)
    }
}

/// Una nota del Buzón que no es el registro del correo (un informe, unas propuestas, algo por ordenar).
struct NotaDelBuzon: Sendable, Hashable, Identifiable {
    enum Clase: String, Sendable, Hashable { case informe, propuestas, porOrdenar }

    let clase: Clase
    let ruta: VaultPath
    let titulo: String
    /// «Aplicado · 312 ficheros», «Del 24 de octubre: no se ha aplicado nada»…
    let detalle: String?
    let fecha: LocalDate?

    var id: String { ruta.raw }
}

/// Un mes con registro (`Correo AAAA-MM.md`).
struct MesDelBuzon: Sendable, Hashable, Identifiable {
    /// «2026-10».
    let mes: String
    let ruta: VaultPath

    var id: String { mes }

    /// «octubre de 2026».
    var titulo: String {
        let p = mes.split(separator: "-")
        guard p.count == 2, let a = Int(p[0]), let m = Int(p[1]), (1...12).contains(m) else { return mes }
        return "\(LecturaBuzon.meses[m - 1]) de \(a)"
    }
}

/// Lo que enseña Carpeta › Buzón.
struct LecturaBuzon: Sendable {
    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                        "octubre", "noviembre", "diciembre"]

    /// La carpeta del Buzón (`nil` si la empresa no tiene).
    let carpeta: VaultPath?
    /// Los meses con registro, del más reciente al más antiguo.
    let meses: [MesDelBuzon]
    /// El mes que se enseña.
    let mes: MesDelBuzon?
    /// Sus días, del más reciente al más antiguo.
    let dias: [DiaDelBuzon]
    let informes: [NotaDelBuzon]
    let propuestas: [NotaDelBuzon]
    /// Lo que ha llegado al Buzón y aún no tiene sitio (lo ordena el Ordenador).
    let porOrdenar: [NotaDelBuzon]
    let hoy: LocalDate

    /// Correos del mes cuya tarea o borrador sigue «Propuesto» (esperan que los mires).
    var propuestosDelMes: Int { dias.reduce(0) { $0 + $1.porRevisar } }
    var correosDelMes: Int { dias.reduce(0) { $0 + $1.lineas.count } }

    /// El día que se enseña al entrar: hoy si hay registro de hoy; si no, el último con correo.
    var diaPorDefecto: LocalDate? { dias.first { $0.dia == hoy }?.dia ?? dias.first?.dia }

    func dia(_ d: LocalDate?) -> DiaDelBuzon? {
        guard let d else { return nil }
        return dias.first { $0.dia == d }
    }

    /// Lee el Buzón de la foto. `mes`: «AAAA-MM» (por defecto, el de hoy si tiene registro; si no, el más reciente).
    static func leer(foto: VaultSnapshot, hoy: LocalDate, mes elegido: String? = nil) -> LecturaBuzon {
        guard let b = foto.layout.buzon, !b.isEmpty else {
            return LecturaBuzon(carpeta: nil, meses: [], mes: nil, dias: [], informes: [], propuestas: [], porOrdenar: [], hoy: hoy)
        }
        let carpeta = VaultPath(b)
        let clave = TextFolding.pathKey(carpeta.raw)
        // Lo que está directamente en el Buzón.
        let directos = foto.files.filter { p in
            guard let padre = p.parent else { return false }
            return TextFolding.pathKey(padre.raw) == clave && !p.name.hasPrefix(".")
        }
        var meses: [MesDelBuzon] = []
        var informes: [NotaDelBuzon] = []
        var propuestas: [NotaDelBuzon] = []
        var porOrdenar: [NotaDelBuzon] = []
        for p in directos.sorted() {
            if let m = mesDeRegistro(p) {
                meses.append(MesDelBuzon(mes: m, ruta: p))
                continue
            }
            let fm = p.ext.lowercased() == "md" ? foto.frontmatter(p) : Frontmatter.empty
            let tipo = fm.text("tls_type")?.lowercased()
            if tipo == "system" || TextFolding.fold(p.stem) == "correspondencia" { continue }   // la ficha del sistema CO1
            if tipo == "import_report" || p.stem.hasPrefix("Informe de importación") {
                informes.append(NotaDelBuzon(clase: .informe, ruta: p, titulo: titulo(p, foto: foto),
                                             detalle: detalleInforme(fm), fecha: fecha(p, fm)))
            } else if p.stem.hasPrefix("Propuestas") {
                propuestas.append(NotaDelBuzon(clase: .propuestas, ruta: p, titulo: titulo(p, foto: foto),
                                               detalle: "No se ha aplicado nada: revísalas tú.", fecha: fecha(p, fm)))
            } else {
                porOrdenar.append(NotaDelBuzon(clase: .porOrdenar, ruta: p, titulo: p.ext.lowercased() == "md" ? titulo(p, foto: foto) : p.name,
                                               detalle: nil, fecha: fecha(p, fm)))
            }
        }
        meses.sort { $0.mes > $1.mes }
        informes.sort { ($0.fecha ?? hoy, $0.ruta.raw) > ($1.fecha ?? hoy, $1.ruta.raw) }
        propuestas.sort { ($0.fecha ?? hoy, $0.ruta.raw) > ($1.fecha ?? hoy, $1.ruta.raw) }
        let deHoy = String(format: "%04d-%02d", hoy.year, hoy.month)
        let mes = meses.first { $0.mes == elegido } ?? meses.first { $0.mes == deHoy } ?? meses.first
        var dias: [DiaDelBuzon] = []
        if let mes, let real = foto.existing(mes.ruta), let t = foto.text(real) {
            let enlaces = indiceDeEnlaces(foto)
            dias = LectorRegistroBuzon.leer(t).map { d in
                var d = d
                d.lineas = d.lineas.map { l in
                    var l = l
                    if !l.privado, let r = l.referencia, let id = EnlaceDeCorreo.id(r) {
                        l.enlazados = enlaces[EnlaceDeCorreo.enlace(id)] ?? []
                    }
                    return l
                }
                return d
            }.sorted { $0.dia > $1.dia }
        }
        return LecturaBuzon(carpeta: carpeta, meses: meses, mes: mes, dias: dias, informes: informes,
                            propuestas: propuestas, porOrdenar: porOrdenar, hoy: hoy)
    }

    /// `Correo AAAA-MM.md` → «AAAA-MM».
    static func mesDeRegistro(_ p: VaultPath) -> String? {
        guard p.ext.lowercased() == "md", p.stem.hasPrefix("Correo ") else { return nil }
        let m = String(p.stem.dropFirst("Correo ".count))
        let partes = m.split(separator: "-")
        guard partes.count == 2, partes[0].count == 4, partes[1].count == 2, Int(partes[0]) != nil,
              let n = Int(partes[1]), (1...12).contains(n) else { return nil }
        return m
    }

    /// Las tareas (`origen: message://…`) y los borradores (`en_respuesta_a: message://…`) de la carpeta, por enlace.
    static func indiceDeEnlaces(_ foto: VaultSnapshot) -> [String: [EnlaceDelBuzon]] {
        var out: [String: [EnlaceDelBuzon]] = [:]
        for p in foto.notes where !VaultSnapshot.isTemplatePath(p) {
            guard let t = foto.text(p), t.contains("message://") else { continue }
            let fm = foto.frontmatter(p)
            let tipo = fm.text("tls_type")?.lowercased()
            let candidatos: [(String?, EnlaceDelBuzon.Clase)] = [
                (fm.text("origen"), tipo == "draft" ? .borrador : .tarea),
                (fm.text("en_respuesta_a"), .borrador),
            ]
            for (valor, clase) in candidatos {
                guard let v = valor, let id = EnlaceDeCorreo.id(v) else { continue }
                let titulo = fm.titleText ?? fm.text("asunto") ?? p.stem
                let e = EnlaceDelBuzon(clase: clase, ruta: p, titulo: LinkParser.plainText(titulo), estado: fm.text("estado"))
                let k = EnlaceDeCorreo.enlace(id)
                if !(out[k]?.contains(where: { $0.ruta == p }) ?? false) { out[k, default: []].append(e) }
            }
        }
        // Primero las tareas, después los borradores.
        return out.mapValues { $0.sorted { ($0.clase == .tarea ? 0 : 1, $0.ruta) < ($1.clase == .tarea ? 0 : 1, $1.ruta) } }
    }

    static func titulo(_ p: VaultPath, foto: VaultSnapshot) -> String {
        if let t = foto.text(p) {
            for l in t.components(separatedBy: .newlines) where l.hasPrefix("# ") {
                return String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return p.stem
    }

    static func fecha(_ p: VaultPath, _ fm: Frontmatter) -> LocalDate? {
        if let f = fm.text("fecha"), let d = LocalDate(parsing: f) { return d }
        // «… AAAA-MM-DD» al final del nombre.
        let s = p.stem
        guard s.count >= 10 else { return nil }
        return LocalDate(parsing: String(s.suffix(10)))
    }

    static func detalleInforme(_ fm: Frontmatter) -> String? {
        var partes: [String] = []
        if let e = fm.text("estado"), !e.isEmpty { partes.append(e) }
        if let n = fm.text("ficheros").flatMap({ Int($0) }) { partes.append(n == 1 ? "1 fichero revisado" : "\(n) ficheros revisados") }
        if let n = fm.text("movidos").flatMap({ Int($0) }), n > 0 { partes.append(n == 1 ? "1 llevado a su sitio" : "\(n) llevados a su sitio") }
        partes.append("no se borró nada")
        return partes.joined(separator: " · ")
    }
}
