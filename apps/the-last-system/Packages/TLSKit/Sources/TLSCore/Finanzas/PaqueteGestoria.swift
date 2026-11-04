// Procedencia: lectura de los originales de `Fiscal/` portada de PROG core/fiscal.js (`leerCarpetaFiscal`, Manu);
// la forma del paquete (índice y 4 CSV con «;» y coma decimal) sigue la plantilla «Índice del paquete trimestral» y el
// paquete T3 de Asesoría Ribera. Ver docs/PROCEDENCIA.md.
import Foundation

/// Un fichero del paquete.
public struct FicheroPaquete: Sendable, Hashable {
    public let ruta: VaultPath
    public let texto: String
    /// Filas de datos (sin la cabecera); 0 en el índice.
    public let registros: Int
    /// Ya está en la carpeta: no se toca (la nota del trimestre del contable no se pisa).
    public let yaExiste: Bool
}

/// Un original del trimestre en `Fiscal/AAAA/Tn/{Ingresos,Gastos}`.
public struct DocumentoTrimestre: Sendable, Hashable {
    public let leido: LectorFiscal.Documento
    /// Alguna fila de emitidas o recibidas apunta a él.
    public let registrado: Bool
}

/// «Preparar paquete para la gestoría»: la lista de documentos y los CSV del trimestre. **No envía nada**:
/// se deja en `Fiscal/AAAA/Tn/Modelos/Paquete gestoría/` para que la persona lo revise y lo mande ella.
public struct PaqueteGestoria: Sendable {
    public let periodo: PeriodoTrimestre
    public let carpeta: VaultPath
    public let ficheros: [FicheroPaquete]
    public let documentos: [DocumentoTrimestre]
    /// Originales en carpetas privadas: no entran ni se nombran en el paquete (la cuenta es solo para la app).
    public let documentosPrivados: Int
    public let diferencias: [FaltaTrimestre]

    /// Sin diferencias: `listo: true` en el índice.
    public var listo: Bool { diferencias.isEmpty }
    /// Todo el paquete ya estaba: no hay nada que escribir.
    public var yaExiste: Bool { ficheros.allSatisfy(\.yaExiste) }

    public var resumen: String {
        if yaExiste { return "El paquete del \(periodo.titulo) ya está preparado: no lo toco." }
        let falta = diferencias.isEmpty ? "no falta nada" : "falta resolver " + Plural.de(diferencias.count, "cosa", "cosas")
        return "Paquete del \(periodo.titulo): " + Plural.de(documentos.count, "documento", "documentos") + ", \(falta)."
    }

    /// Crear lo que falta del paquete (nunca pisa lo que ya hay). `nil` si ya está todo.
    public func plan(autor: Autor) -> WritePlan? {
        let ops = ficheros.filter { !$0.yaExiste }.map { CommandBus.Comando.crear($0.ruta, texto: $0.texto).op }
        guard !ops.isEmpty else { return nil }
        return WritePlan(autor: autor, descripcion: "Preparar el paquete para la gestoría del \(periodo.titulo)", ops: ops)
    }
}

/// Prepara el paquete de un trimestre a partir de los registros y de los originales de `Fiscal/`.
public struct PreparadorPaquete: Sendable {
    public let registros: RegistrosFinanzas
    public let reloj: Reloj

    public init(registros: RegistrosFinanzas, reloj: Reloj) {
        self.registros = registros
        self.reloj = reloj
    }

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.init(registros: RegistrosFinanzas(snapshot: snapshot), reloj: reloj ?? Reloj.deCarpeta(snapshot))
    }

    public func carpeta(_ p: PeriodoTrimestre) -> VaultPath {
        registros.carpeta.appending("Fiscal").appending(String(p.anio)).appending("T\(p.numero)").appending("Modelos")
            .appending("Paquete gestoría")
    }

    // MARK: Originales

    /// Los originales del trimestre (PDF, imagen, hoja de cálculo; y las fichas de factura `.md`).
    public func documentos(_ p: PeriodoTrimestre) -> (documentos: [DocumentoTrimestre], privados: Int) {
        let snapshot = registros.snapshot
        let base = registros.carpeta.appending("Fiscal").appending(String(p.anio)).appending("T\(p.numero)")
        let referenciados = Set((registros.emitidas + registros.recibidas).compactMap(\.rutaDocumento).map { TextFolding.pathKey($0.raw) })
        var out: [DocumentoTrimestre] = []
        var privados = 0
        for (sub, clase) in [("Ingresos", LectorFiscal.Documento.Clase.ingreso), ("Gastos", .gasto)] {
            guard let dir = snapshot.existing(base.appending(sub)) else { continue }
            for f in snapshot.files where f.isDescendant(of: dir) && !snapshot.layout.isArchived(f) {
                let esFicha = f.ext == "md" && snapshot.frontmatter(f).text("tls_type") == "invoice"
                guard LectorFiscal.justificantes.contains(f.ext.lowercased()) || esFicha else { continue }
                if snapshot.layout.isPrivate(f) { privados += 1; continue }
                let rel = f.components.dropFirst(dir.components.count)
                let leido: LectorFiscal.Documento
                if clase == .ingreso {
                    leido = esFicha ? Self.leerFicha(f, snapshot: snapshot) : LectorFiscal.leerIngreso(f, anioCarpeta: p.anio)
                } else {
                    leido = LectorFiscal.leerGasto(f, subcarpeta: rel.count > 1 ? rel.first : nil, anioCarpeta: p.anio)
                }
                out.append(DocumentoTrimestre(leido: leido, registrado: referenciados.contains(TextFolding.pathKey(f.raw))))
            }
        }
        return (out.sorted { $0.leido.ruta < $1.leido.ruta }, privados)
    }

    /// Una ficha de factura (`tls_type: invoice`): sus datos están en las propiedades.
    static func leerFicha(_ f: VaultPath, snapshot: VaultSnapshot) -> LectorFiscal.Documento {
        let fm = snapshot.frontmatter(f)
        var falta: [String] = []
        let fecha = fm.text("fecha").flatMap { LocalDate(parsing: $0) }
        if fecha == nil { falta.append("la ficha no dice la fecha") }
        let total = fm.text("total").flatMap(DineroExacto.centimos)
        if total == nil { falta.append("la ficha no dice el total") }
        let cliente = fm.text("empresa").map(Self.textoDeEnlace) ?? fm.text("cliente")
        return LectorFiscal.Documento(clase: .ingreso, ruta: f, nombre: f.stem, fecha: fecha, numero: fm.text("numero"),
                                      tercero: cliente, terceroSupuesto: false, importe: total, tipoFiscal: "ingreso",
                                      categoria: fm.text("categoria"), falta: falta)
    }

    /// `[[slug|Nombre]]` → «Nombre».
    static func textoDeEnlace(_ s: String) -> String {
        guard s.hasPrefix("[["), s.hasSuffix("]]") else { return s }
        let dentro = s.dropFirst(2).dropLast(2)
        return String(dentro.split(separator: "|", maxSplits: 1).last ?? dentro)
    }

    // MARK: Paquete

    public func preparar(_ p: PeriodoTrimestre) -> PaqueteGestoria {
        let snapshot = registros.snapshot
        let destino = snapshot.existing(carpeta(p)) ?? carpeta(p)
        let trimestre = TrimestreFiscal(registros: registros, hoy: reloj.hoy)
        let emitidas = trimestre.emitidas(p).sorted { ($0.fecha ?? p.desde, $0.id) < ($1.fecha ?? p.desde, $1.id) }
        let recibidas = trimestre.recibidas(p).sorted { ($0.fecha ?? p.desde, $0.id) < ($1.fecha ?? p.desde, $1.id) }
        let movimientos = registros.movimientos.filter { p.contiene($0.fecha) }
        let (documentos, privados) = documentos(p)
        func c(_ v: Int?) -> String { v.map(DineroExacto.coma) ?? "" }
        func fila(_ campos: [String]) -> String { campos.map(CSVEscritura.campoPuntoYComa).joined(separator: ";") }

        // Diferencias: lo que hay que resolver o validar.
        var diferencias: [FaltaTrimestre] = []
        for f in recibidas where f.rutaDocumento == nil && !f.documentoPrivado {
            diferencias.append(FaltaTrimestre(tipo: "gasto sin justificante", fecha: f.fecha, descripcion: f.numeroVisible,
                                              importe: f.total, id: f.id))
        }
        for f in emitidas {
            if let pend = registros.pendiente(de: f), pend > 0 {
                diferencias.append(FaltaTrimestre(tipo: "ingreso sin cobrar", fecha: f.fecha, descripcion: f.numeroVisible,
                                                  importe: pend, id: f.id))
            }
        }
        for f in emitidas + recibidas where f.sinRevisar {
            diferencias.append(FaltaTrimestre(tipo: "fila sin revisar", fecha: f.fecha, descripcion: f.numeroVisible,
                                              importe: f.total, id: f.id))
        }
        for m in movimientos where m.estado.abierto {
            diferencias.append(FaltaTrimestre(tipo: "movimiento sin conciliar", fecha: m.fecha, descripcion: m.concepto,
                                              importe: m.importe, id: m.id))
        }
        for d in documentos where !d.registrado {
            diferencias.append(FaltaTrimestre(tipo: "documento sin registrar", fecha: d.leido.fecha,
                                              descripcion: registros.rutaRelativa(d.leido.ruta), importe: d.leido.importe, id: nil))
        }
        for f in trimestre.modelo303(p).faltan where !diferencias.contains(where: { $0.id == f.id && $0.tipo == f.tipo }) {
            diferencias.append(f)
        }

        let ingresos = [fila(["numero", "fecha", "cliente", "nif", "base", "iva", "retencion", "total", "estado", "id"])]
            + emitidas.map { f in
                let pend = registros.pendiente(de: f)
                let estado = f.sinRevisar ? "sin revisar" : pend == 0 ? "cobrada" : pend == nil ? "" : "pendiente"
                return fila([f.numeroVisible, f.fecha?.description ?? "", f.tercero ?? "", "", c(f.base), c(f.iva), c(f.retencion),
                             c(f.total), estado, f.id])
            }
        let gastos = [fila(["numero", "fecha", "proveedor", "nif", "categoria", "naturaleza", "base", "iva", "retencion", "total",
                            "justificante", "id"])]
            + recibidas.map { f in
                // Un original en una carpeta privada no se nombra (ni se da por perdido).
                let justificante = f.documentoPrivado ? "" : f.rutaDocumento.map(registros.rutaRelativa) ?? "FALTA"
                return fila([f.numeroVisible, f.fecha?.description ?? "", f.tercero ?? "", "", f.categoria ?? "", f.naturaleza ?? "",
                             c(f.base), c(f.iva), c(f.retencion), c(f.total), justificante, f.id])
            }
        let nombresCuenta = Dictionary(registros.cuentas.map { ($0.id, $0.carpeta.name) }, uniquingKeysWith: { a, _ in a })
        let movs = [fila(["fecha", "concepto", "importe", "naturaleza", "categoria", "conciliacion", "factura", "id", "cuenta"])]
            + movimientos.map { m in
                let factura = m.documentoID.flatMap { registros.factura(id: $0)?.numeroVisible } ?? m.documentoID ?? ""
                return fila([m.fecha.description, m.concepto, DineroExacto.coma(m.importe), m.naturaleza ?? "", m.categoria ?? "",
                             m.estado.rawValue, factura, m.id, nombresCuenta[m.cuentaID] ?? ""])
            }
        let difs = [fila(["tipo", "fecha", "descripcion", "importe", "id"])]
            + diferencias.map { d in fila([d.tipo, d.fecha?.description ?? "", d.descripcion, c(d.importe), d.id ?? ""]) }

        let totIng = trimestre.totales(emitidas), totGas = trimestre.totales(recibidas)
        func e(_ v: Int?) -> String { v.map(DineroExacto.euros) ?? "Sin dato" }
        var indice = """
        ---
        tls_type: period
        tls_schema: 1
        id: \(UUID().uuidString.lowercased())
        periodo: \(p.titulo)
        desde: \(p.desde)
        hasta: \(p.hasta)
        estado: Preparado
        listo: \(diferencias.isEmpty ? "true" : "false")
        enviado_el:
        origen: app
        ---
        # Paquete para la gestoría · \(p.titulo)
        > Preparado el \(Self.fechaLarga(reloj)) · del \(Self.corta(p.desde)) al \(Self.corta(p.hasta)) · \(diferencias.isEmpty ? "no falta nada" : "falta " + Plural.de(diferencias.count, "cosa", "cosas"))

        > No es una declaración ni calcula lo que hay que pagar: la gestoría lo revisa y lo presenta. La app no lo envía: lo mandas tú.

        ## Qué contiene
        | Fichero | Contenido | Registros |
        |---|---|---|
        | libro-ingresos.csv | Facturas emitidas del trimestre | \(emitidas.count) |
        | libro-gastos.csv | Facturas recibidas, con la ruta del original o FALTA | \(recibidas.count) |
        | movimientos.csv | Movimientos del banco con su conciliación | \(movimientos.count) |
        | diferencias.csv | Lo que hay que resolver o validar | \(diferencias.count) |

        ## Totales
        | | Base | IVA | Retención | Total |
        |---|---|---|---|---|
        | Ingresos | \(e(totIng.base)) | \(e(totIng.iva)) | \(e(totIng.retencion)) | \(e(totIng.total)) |
        | Gastos | \(e(totGas.base)) | \(e(totGas.iva)) | \(e(totGas.retencion)) | \(e(totGas.total)) |

        ## Lo que falta

        """
        if diferencias.isEmpty {
            indice += "Nada: todo tiene su justificante, está cobrado o pagado y conciliado.\n"
        } else {
            for d in diferencias.prefix(100) {
                indice += "- \(d.tipo) · \(d.fecha?.description ?? "sin fecha") · \(d.descripcion)\(d.importe.map { " · " + DineroExacto.euros($0) } ?? "")\n"
            }
            if diferencias.count > 100 { indice += "- … y \(diferencias.count - 100) más en `diferencias.csv`\n" }
        }
        indice += "\n## Documentos del trimestre\n"
        if documentos.isEmpty {
            indice += "No hay originales en `Fiscal/\(p.carpeta)/`.\n"
        } else {
            for d in documentos {
                indice += "- [\(d.leido.ruta.stem)](\(Self.enlace(desde: destino, a: d.leido.ruta)))\(d.registrado ? "" : " · sin fila en el registro")\n"
            }
        }
        indice += """

        ## Modelos del trimestre
        | Modelo | Estado |
        |---|---|
        | | |

        > Los que diga tu gestoría. La app no decide qué modelos tocan.

        """

        let csvs: [(String, [String])] = [("libro-ingresos.csv", ingresos), ("libro-gastos.csv", gastos), ("movimientos.csv", movs),
                                          ("diferencias.csv", difs)]
        var ficheros = [FicheroPaquete(ruta: destino.appending("indice.md"), texto: indice, registros: 0,
                                       yaExiste: snapshot.existing(destino.appending("indice.md")) != nil)]
        for (nombre, lineas) in csvs {
            let ruta = destino.appending(nombre)
            ficheros.append(FicheroPaquete(ruta: ruta, texto: lineas.joined(separator: "\n") + "\n", registros: lineas.count - 1,
                                           yaExiste: snapshot.existing(ruta) != nil))
        }
        // Si el índice ya existe, el paquete es del contable: no se toca nada de él.
        if ficheros[0].yaExiste {
            ficheros = ficheros.map { FicheroPaquete(ruta: $0.ruta, texto: $0.texto, registros: $0.registros, yaExiste: true) }
        }
        return PaqueteGestoria(periodo: p, carpeta: destino, ficheros: ficheros, documentos: documentos,
                               documentosPrivados: privados, diferencias: diferencias)
    }

    /// Enlace Markdown relativo desde la carpeta del paquete (con `%20` en los espacios).
    static func enlace(desde carpeta: VaultPath, a destino: VaultPath) -> String {
        let a = carpeta.components, b = destino.components
        var comun = 0
        while comun < a.count, comun < b.count - 1, a[comun] == b[comun] { comun += 1 }
        let partes = Array(repeating: "..", count: a.count - comun) + b.dropFirst(comun)
        return partes.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? $0 }
            .joined(separator: "/")
    }

    static func corta(_ f: LocalDate) -> String {
        String(format: "%02d/%02d/%04d", f.day, f.month, f.year)
    }

    static func fechaLarga(_ r: Reloj) -> String { corta(r.hoy) + " a las " + r.hora }
}
