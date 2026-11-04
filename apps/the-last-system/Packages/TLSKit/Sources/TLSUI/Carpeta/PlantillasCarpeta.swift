import Foundation
import TLSCore

/// Una cosa que se puede crear desde «Nueva…» de la Carpeta: una plantilla (en esta carpeta o para la ficha
/// elegida) o una nota en blanco.
struct OpcionNueva: Identifiable, Hashable, Sendable {
    enum Origen: Hashable, Sendable {
        /// La plantilla nace en esta carpeta (`carpeta` de `.tls/plantillas.yaml`).
        case carpeta
        /// «Nueva … para «Jorge Martín»»: la ficha elegida va de contexto (`desde`).
        case ficha(VaultPath, titulo: String)
        case notaEnBlanco
    }

    let id: String
    let titulo: String
    let detalle: String
    let simbolo: String
    let origen: Origen
    /// Identificador de la plantilla (`nil` = nota en blanco).
    let plantilla: String?
    /// `tls_type` de la nota que crea.
    let tipo: String?
    /// Preguntas que se hacen al crear (sin las que piden otra ficha).
    let preguntas: [String]
    /// Carpeta a la fuerza (la plantilla no dice dónde nace).
    let carpetaForzada: VaultPath?

    var desde: VaultPath? {
        if case .ficha(let p, _) = origen { return p }
        return nil
    }
}

/// Qué plantillas ofrece «Nueva…» en una carpeta (PLANTILLAS §1.1): las que nacen en ella y, si hay una ficha
/// elegida, las que esa ficha ofrece (`PlantillaRegistro.desde(tipo:)`). Puro: se prueba sin interfaz.
enum PlantillasCarpeta {
    /// Preguntas que piden otra ficha (no se escriben a mano en «Nueva…»: las pone el contexto).
    static let preguntasDeFicha: Set<String> = [
        "oportunidad", "contacto", "servicio", "factura", "sesion", "rol", "cuello", "proyecto", "presupuesto", "empresa",
    ]
    /// Variables que la plantilla rellena sola en la carpeta (`{{slug}}`, `{{año}}`…).
    static let variablesPropias: Set<String> = ["slug", "titulo", "año", "trimestre", "fecha", "mes", "hora", "numero", "orden", "version"]

    static func opciones(carpeta: VaultPath, registro: PlantillaRegistro, layout: VaultLayout,
                         ficha: (ruta: VaultPath, tipo: NoteKind, titulo: String)? = nil) -> [OpcionNueva] {
        var salida: [OpcionNueva] = []
        var vistas = Set<String>()
        if let ficha {
            for def in registro.desde(tipo: ficha.tipo.rawValue) where !def.esFragmento {
                let id = "ficha:\(def.id)"
                guard vistas.insert(id).inserted else { continue }
                salida.append(OpcionNueva(id: id, titulo: nombre(de: def), detalle: "Para «\(ficha.titulo)»",
                                          simbolo: simbolo(de: def), origen: .ficha(ficha.ruta, titulo: ficha.titulo),
                                          plantilla: def.id, tipo: def.tipo, preguntas: preguntas(de: def),
                                          carpetaForzada: nil))
            }
        }
        for def in registro.plantillas where !def.esFragmento {
            guard let patron = def.carpeta, encaja(patron, en: carpeta, layout: layout),
                  !necesitaOtraFicha(def) else { continue }
            let id = "carpeta:\(def.id)"
            guard vistas.insert(id).inserted else { continue }
            salida.append(OpcionNueva(id: id, titulo: nombre(de: def), detalle: "En «\(carpeta.isRoot ? "la carpeta de tu empresa" : carpeta.name)»",
                                      simbolo: simbolo(de: def), origen: .carpeta, plantilla: def.id, tipo: def.tipo,
                                      preguntas: preguntas(de: def), carpetaForzada: nil))
        }
        salida.append(OpcionNueva(id: "nota", titulo: "Nota en blanco", detalle: "Una nota sin plantilla",
                                  simbolo: "doc.text", origen: .notaEnBlanco, plantilla: nil, tipo: nil,
                                  preguntas: ["titulo"], carpetaForzada: carpeta))
        return salida
    }

    /// `true` si la plantilla nace en `carpeta` (o en una subcarpeta propia, `…/Proyectos/{{slug}}`).
    static func encaja(_ patron: String, en carpeta: VaultPath, layout: VaultLayout) -> Bool {
        var p = patron
        if p.contains("{area}") {
            guard let area = layout.area(of: carpeta) else { return false }
            p = p.replacingOccurrences(of: "{area}", with: "{\(area.layoutKey)}")
        }
        if let r = p.range(of: "{{") {
            // Solo si lo que va entre llaves lo pone la propia plantilla (no otra ficha).
            let resto = p[r.lowerBound...]
            for variable in variables(en: String(resto)) where !variablesPropias.contains(variable) { return false }
            var corte = String(p[..<r.lowerBound])
            if !corte.hasSuffix("/"), let barra = corte.lastIndex(of: "/") {
                corte = String(corte[..<barra])   // `…/Proyectos/plan-{{x}}` nace en `…/Proyectos`
            } else if !corte.hasSuffix("/") {
                corte = ""
            }
            p = corte
        }
        let destino = layout.expand(p.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        return TextFolding.pathKey(destino.raw) == TextFolding.pathKey(carpeta.raw)
    }

    /// `true` si el nombre o la carpeta de la plantilla salen de otra ficha (`{{oportunidad.slug}}`).
    static func necesitaOtraFicha(_ def: PlantillaDef) -> Bool {
        let patrones = [def.nombre, def.carpeta, def.titulo].compactMap { $0 }
        for p in patrones {
            for v in variables(en: p) where v.contains(".") || preguntasDeFicha.contains(v) { return true }
        }
        return false
    }

    /// Nombres de variable de `{{…}}` (sin el formato tras «:»).
    static func variables(en texto: String) -> [String] {
        var salida: [String] = []
        var resto = Substring(texto)
        while let a = resto.range(of: "{{"), let b = resto.range(of: "}}", range: a.upperBound..<resto.endIndex) {
            let dentro = resto[a.upperBound..<b.lowerBound]
            let nombre = dentro.split(separator: ":", maxSplits: 1).first.map(String.init) ?? String(dentro)
            salida.append(nombre.trimmingCharacters(in: .whitespaces))
            resto = resto[b.upperBound...]
        }
        return salida
    }

    static func preguntas(de def: PlantillaDef) -> [String] {
        def.preguntas.filter { !preguntasDeFicha.contains($0) && $0 != "area" }
    }

    /// «Reunión», «Contacto»… (el nombre del fichero de la plantilla).
    static func nombre(de def: PlantillaDef) -> String {
        let fichero = VaultPath(def.fichero).stem
        if !fichero.isEmpty, !fichero.contains("{") { return fichero }
        return NoteKind(rawValue: def.tipo)?.etiqueta ?? def.id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func simbolo(de def: PlantillaDef) -> String {
        NoteKind(rawValue: def.tipo)?.systemImage ?? "doc.text"
    }

    /// Etiqueta de una pregunta para el formulario. El título de una persona o una empresa es su nombre.
    static func etiqueta(_ pregunta: String, tipo: String? = nil) -> String {
        switch pregunta {
        case "titulo" where ["contact", "organization", "company", "role", "collaboration"].contains(tipo ?? ""): "Nombre"
        case "titulo": "Título"
        case "fecha": "Fecha (AAAA-MM-DD)"
        case "hora": "Hora (HH:MM)"
        case "responsable": "Quién la lleva"
        case "para": "Para"
        case "tipo": "Tipo"
        case "motivo": "Motivo"
        case "gravedad": "Gravedad"
        case "codigo": "Código"
        case "email": "Correo"
        case "coleccion": "Colección"
        case "cadencia": "Cada cuánto"
        case "pregunta": "Pregunta"
        case "banco": "Banco"
        case "asistente": "Asistente"
        case "palabra_clave": "Palabra clave"
        case "ocupante": "Quién la ocupa"
        case "periodo": "Periodo"
        case "meta": "Meta"
        case "medido_por": "Cómo se mide"
        case "pilar": "Pilar"
        case "sistema": "Función"
        case "version": "Versión"
        case "hito": "Hito"
        case "metodo": "Método"
        case "canal": "Canal"
        case "dia": "Día"
        default: pregunta.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
