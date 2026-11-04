import Foundation
import TLSCore

/// Un aviso de calidad de los datos, con «Crear tarea» o «Ignorar».
public struct AvisoCalidad: Sendable, Hashable, Codable, Identifiable {
    public enum Tipo: String, Sendable, Hashable, Codable, CaseIterable {
        /// Documento de Finanzas sin fecha en el nombre ni en `Fechas de documentos.csv`.
        case sinFecha
        /// Nota en una colección de fichas sin `tls_type` (no se ve como ficha).
        case sinTipo
        /// Mismo contenido en dos sitios.
        case duplicado
        /// Enlace con ruta que no lleva a ningún sitio (o solo se encuentra por el nombre).
        case enlaceRoto

        public var titulo: String {
            switch self {
            case .sinFecha: "Documento sin fecha"
            case .sinTipo: "Ficha sin tipo"
            case .duplicado: "Duplicado"
            case .enlaceRoto: "Enlace roto"
            }
        }
    }

    /// Estable (tipo, ruta y detalle): «Ignorar» lo recuerda aunque se vuelva a revisar.
    public let id: String
    public let tipo: Tipo
    public let ruta: VaultPath
    public let detalle: String
    public let queHacer: String

    init(tipo: Tipo, ruta: VaultPath, detalle: String, queHacer: String) {
        self.tipo = tipo; self.ruta = ruta; self.detalle = detalle; self.queHacer = queHacer
        self.id = tipo.rawValue + ":" + ContentHash.of(ruta.raw + "\n" + detalle).prefix(16)
    }
}

/// Calidad de los datos tras ordenar (PLAN §6.7 paso 2): sin fecha, sin tipo, duplicados y enlaces rotos. Solo lee;
/// cada aviso se convierte en una tarea (un plan para el `CommandBus`) o se ignora (se apunta fuera de la carpeta).
/// Lo privado no sale: no está en la foto de la carpeta.
public struct InformeCalidad: Sendable {
    public let avisos: [AvisoCalidad]

    public init(avisos: [AvisoCalidad]) { self.avisos = avisos }

    public func cuantos(_ t: AvisoCalidad.Tipo) -> Int { avisos.filter { $0.tipo == t }.count }

    /// «3 sin fecha · 1 duplicado · 2 enlaces rotos».
    public var resumen: String {
        let partes = [
            (cuantos(.sinFecha), "sin fecha", "sin fecha"), (cuantos(.sinTipo), "ficha sin tipo", "fichas sin tipo"),
            (cuantos(.duplicado), "duplicado", "duplicados"), (cuantos(.enlaceRoto), "enlace roto", "enlaces rotos"),
        ].filter { $0.0 > 0 }.map { Plural.de($0.0, $0.1, $0.2) }
        return partes.isEmpty ? "Sin avisos" : partes.joined(separator: " · ")
    }

    /// Revisa la carpeta de la empresa. `huellas` (SHA-256 por fichero, de `Inventory`) para los duplicados; los
    /// ignorados no salen.
    public static func revisar(snapshot: VaultSnapshot, huellas: Inventory? = nil, ignorados: Set<String> = []) -> InformeCalidad {
        let layout = snapshot.layout
        var avisos: [AvisoCalidad] = []
        // Sin fecha.
        let csv = snapshot.existing(FechasDeDocumentos.ruta(layout))
        let filas = csv.flatMap { snapshot.text($0) }.map(FechasDeDocumentos.leer) ?? []
        let conFila = Set(filas.map { TextFolding.pathKey(FechasDeDocumentos.absoluta($0.ruta, layout: layout).raw) })
        for p in snapshot.files where !layout.isPrivate(p) && DocumentDater.necesitaFila(p, layout: layout)
            && !conFila.contains(TextFolding.pathKey(p.raw)) {
            avisos.append(AvisoCalidad(tipo: .sinFecha, ruta: p, detalle: "«\(p.name)» no tiene fecha",
                                       queHacer: "Pulsa «Poner fecha…» y elige el día del documento. Queda apuntada como tuya y no se pisa."))
        }
        // Sin tipo: lo que «Adoptar» aún propone tipar.
        for i in Adopter(snapshot: snapshot).proponer().identidades where i.anadir.contains(where: { $0.key == "tls_type" }) {
            avisos.append(AvisoCalidad(tipo: .sinTipo, ruta: i.ruta, detalle: "«\(i.ruta.stem)» parece una ficha de \(HeuristicClassifier.nombreDeTipo(i.tipo)) y no lo dice",
                                       queHacer: "Vuelve a «Completar las fichas» para añadirle su tipo, o crea una tarea para luego."))
        }
        // Duplicados (mismo contenido), fuera de Archivo.
        if let huellas {
            var porHuella: [String: [String]] = [:]
            for e in huellas.entradas where e.tipo == .fichero {
                let p = VaultPath(e.ruta)
                guard let h = e.sha256, !layout.isArchived(p), !layout.isPrivate(p), !p.components.contains(where: { $0.hasPrefix(".") }),
                      (e.tamano ?? 0) > 0 else { continue }
                porHuella[h, default: []].append(e.ruta)
            }
            for (_, rutas) in porHuella where rutas.count > 1 {
                let orden = rutas.sorted()
                for r in orden.dropFirst() {
                    avisos.append(AvisoCalidad(tipo: .duplicado, ruta: VaultPath(r), detalle: "Igual que «\(orden[0])»",
                                               queHacer: "Quédate con uno: el otro, a Archivo › Duplicados."))
                }
            }
        }
        // Enlaces rotos: los de ruta que no llevan a nada (los wikilinks a notas que aún no existen son migas, no fallos).
        for e in SaludDeEnlaces(snapshot: snapshot).revisar() where !layout.isPrivate(e.origen) && !layout.isArchived(e.origen) {
            switch e.estado {
            case .pendiente:
                guard e.enlace.contains("](") else { continue }
                avisos.append(AvisoCalidad(tipo: .enlaceRoto, ruta: e.origen, detalle: "Línea \(e.linea): «\(e.destino)» no existe",
                                           queHacer: "Corrige el enlace o crea la nota."))
            case .flojo(let real):
                avisos.append(AvisoCalidad(tipo: .enlaceRoto, ruta: e.origen,
                                           detalle: "Línea \(e.linea): «\(e.destino)» está en «\(real.raw)»",
                                           queHacer: "Abre la nota y corrige el enlace para que lleve a su sitio, o crea una tarea para luego."))
            case .ambiguo:
                continue
            }
        }
        return InformeCalidad(avisos: avisos.filter { !ignorados.contains($0.id) }.sorted { ($0.tipo.rawValue, $0.ruta) < ($1.tipo.rawValue, $1.ruta) })
    }

    /// «Crear tarea»: una ficha de tarea en el área del aviso (o Dirección), con su motivo. Devuelve el plan (para el
    /// `CommandBus`), como cualquier tarea nueva.
    public static func crearTarea(_ aviso: AvisoCalidad, snapshot: VaultSnapshot, reloj: Reloj? = nil,
                                  autor: Autor = .persona("Manu")) throws -> WritePlan {
        let area = snapshot.layout.area(of: aviso.ruta) ?? .direccion
        let nueva = NuevaTarea(titulo: "Revisar: \(aviso.tipo.titulo.lowercased()) en «\(aviso.ruta.stem)»", area: area,
                               descripcion: "\(aviso.detalle).\n\n\(aviso.queHacer)\n\nFichero: `\(aviso.ruta.raw)`",
                               origen: "importacion", autor: autor)
        return try TaskStore(snapshot: snapshot, reloj: reloj).crear(nueva).plan
    }

    /// «Poner fecha…» de un documento sin fecha: su fila en `Fechas de documentos.csv` con la fuente `manual` (es de la
    /// persona: nada la pisa después). Devuelve el plan (para el `CommandBus`); se deshace como cualquier cambio.
    public static func ponerFecha(_ aviso: AvisoCalidad, fecha: LocalDate, snapshot: VaultSnapshot,
                                  autor: Autor = .persona("Manu")) throws -> WritePlan {
        let layout = snapshot.layout
        let fila = FilaFecha(ruta: FechasDeDocumentos.relativa(aviso.ruta, layout: layout), fecha: fecha.description,
                             fuente: "manual", nota: "Puesta a mano al revisar la calidad")
        let pedido = FechasDeDocumentos.ruta(layout)
        let op: WriteOp
        if let csv = snapshot.existing(pedido) {
            let cabecera = snapshot.text(csv).map { CSVTable.parse(TextDecoding.strippingBOM($0)).header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } } ?? []
            guard cabecera.contains("ruta"), cabecera.contains("fecha") else { throw ImportError.mapaIlegible("«\(FechasDeDocumentos.nombre)» no tiene las columnas «ruta» y «fecha»") }
            op = .upsertCSVRow(csv, row: fila.diccionario.filter { cabecera.contains($0.key) }, key: "ruta")
        } else {
            op = .create(pedido, text: FechasDeDocumentos.texto([fila]))
        }
        return WritePlan(autor: autor, descripcion: "Poner fecha a «\(aviso.ruta.name)»", ops: [op])
    }

    // MARK: Ignorar (fuera de la carpeta de la empresa)

    static let fichero = "calidad-ignorados.json"

    /// «Ignorar»: se apunta en el estado de la app (`<estado>/calidad-ignorados.json`), nunca en la carpeta.
    public static func ignorar(_ aviso: AvisoCalidad, estado: URL) throws {
        var ids = ignorados(estado: estado)
        ids.insert(aviso.id)
        try FileManager.default.createDirectory(at: estado, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(ids.sorted())
        try data.write(to: estado.appendingPathComponent(fichero), options: [.atomic])
    }

    public static func ignorados(estado: URL) -> Set<String> {
        guard let d = try? Data(contentsOf: estado.appendingPathComponent(fichero)),
              let l = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return Set(l)
    }
}
