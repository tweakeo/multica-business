import Foundation
import TLSCore

/// Lo que no es una ficha: `Empresa.md`, cabeceras de área, notas índice, `.tls/`, `Archivo/` y el informe.
extension ConversionG2 {
    /// Pregunta fija de cada área (biblioteca de sistemas, SISTEMAS.md §2.6). Dirección no tiene una.
    static let preguntas: [AreaCode: String] = [
        .ventas: "¿De dónde sale el próximo cliente?",
        .entrega: "¿Estamos cumpliendo lo prometido?",
        .finanzas: "¿Hay caja y hay margen?",
        .marca: "¿Nos conocen los que importan?",
        .equipo: "¿Quién hace esto cuando yo no esté?",
    ]

    func escribirEstructura() {
        escribirEmpresaPropia()
        for indice in IndiceV2.todos where tieneRegistros(indice) { escribirIndice(indice) }
        // Las cabeceras de área van al final: listan las carpetas que ya existen.
        for codigo in AreaCode.allCases { escribirArea(codigo) }
        escribirAjustes()
    }

    /// Rol (nota) por su nombre en `Empresa.md` de G2.
    func rol(_ nombre: String?) -> DestinoV2? {
        guard let nombre else { return nil }
        let k = TextFolding.fold(nombre)
        let r = carpeta.registros("role").first { TextFolding.fold($0.campos.texto("name") ?? "") == k }
        return r?.id.flatMap { destinos[$0] }
    }

    func escribirEmpresaPropia() {
        contar(empresa)
        bloque("Empresa.md", destino: "Empresa.md, .tls/config.yaml y las seis Área.md")
        let c = empresa.campos
        let perfil = c.mapa("profile") ?? .vacio
        let semilla = c.texto("workspace_id") ?? nombreOrigen
        var fm = FrontmatterNuevo(tipo: "company", id: IDsDerivados.id("empresa:" + semilla))
        fm.texto("nombre", nombreEmpresa)
        fm.texto("sector", perfil.texto("sector"))
        fm.texto("ciudad", perfil.texto("ciudad"))
        fm.literal("personas", perfil.entero("personas").map(String.init))
        let destino = VaultPath("Empresa.md")
        var nota = NotaNueva(frontmatter: fm, titulo: nombreEmpresa)
        nota.resumen = [perfil.texto("sector"), perfil.texto("ciudad"), perfil.entero("personas").map { "\($0) personas" }]
        nota.seccion("Qué hace")
        var filas: [[String]] = []
        for codigo in AreaCode.allCases {
            let a = area(codigo)
            let enlaceArea = Nombres.enlaceMarkdown(a.carpeta, desde: destino, a: ruta(codigo, AreaReader.fileName))
            let enlaceRol = rol(a.rol).map { Nombres.enlaceMarkdown($0.nombre, desde: destino, a: $0.ruta) } ?? (a.rol ?? "")
            filas.append([enlaceArea, a.convierte ?? "", enlaceRol])
        }
        nota.seccion("Las seis áreas", TablaMarkdown.texto(["Área", "Convierte", "Rol"], filas))
        nota.seccion("Cómo fluye el trabajo")
        nota.seccion("Reglas comunes", perfil.texto("politica_arranque").map { "- \($0)" })
        nota.seccion("Pendiente")
        escribir(destino, nota)
        for clave in perfil.claves where !["sector", "ciudad", "personas", "politica_arranque", "razon_social", "nif",
                                           "servicios"].contains(clave) && !(perfil[clave]?.vacio ?? true) {
            registrarNoConvertido("company.profile.\(clave)", ruta: empresa.ruta.raw, motivo: "No tiene sitio en «Tu empresa».")
        }
        if !perfil.lista("servicios").isEmpty {
            registrarNoConvertido("company.profile.servicios", ruta: empresa.ruta.raw,
                                  motivo: "Los servicios son sus fichas en Productos.")
        }
        if c.lista("areas").compactMap(\.mapa).contains(where: { $0.texto("color") != nil }) {
            registrarNoConvertido("company.areas.color", ruta: empresa.ruta.raw, motivo: "La app usa su propia paleta por área.")
        }
        if empresa.cuerpoUtil != nil {
            registrarNoConvertido("company.cuerpo", ruta: empresa.ruta.raw,
                                  motivo: "Explica el formato de G2; no describe la empresa.")
        }
        revisar(empresa, usados: ["name", "profile", "areas", "exported_at"])
    }

    func escribirArea(_ codigo: AreaCode) {
        let a = area(codigo)
        let destino = ruta(codigo, AreaReader.fileName)
        var fm = FrontmatterNuevo(tipo: "area", id: IDsDerivados.id("area:" + codigo.layoutKey))
        fm.literal("codigo", codigo.layoutKey)
        fm.texto("nombre", a.nombre)
        fm.texto("convierte", a.convierte)
        fm.poner("rol", rol(a.rol).map(wikilink))
        fm.texto("pregunta", Self.preguntas[codigo])
        var nota = NotaNueva(frontmatter: fm, titulo: a.nombre)
        nota.resumen = [rol(a.rol).map { "Rol: \($0.nombre)" } ?? a.rol.map { "Rol: \($0)" }, Self.preguntas[codigo]]
        nota.seccion("Qué transforma", a.convierte)
        nota.seccion("Sistemas")
        nota.seccion("Rutina")
        nota.seccion("Carpetas", carpetasDeArea(codigo, desde: destino))
        let pendientes = tareas.filter { $0.area == codigo }
            .filter { t in
                guard t.registro.tipo == "task" else { return true }
                let estado = estadoTarea(t.registro.campos.texto("status") ?? t.registro.campos.texto("estado"), t.registro)
                return estado != "Hecha" && estado != "Cancelada"
            }
            .map { "- " + Nombres.enlaceMarkdown("\($0.numero) · \($0.destino.nombre)", desde: destino, a: $0.destino.ruta) }
        nota.seccion("Pendiente", pendientes.isEmpty ? nil : pendientes.joined(separator: "\n"))
        escribir(destino, nota)
    }

    /// Una línea por carpeta del área: su nota índice si la tiene; si no, el nombre de la carpeta.
    func carpetasDeArea(_ codigo: AreaCode, desde: VaultPath) -> String? {
        let base = VaultPath(area(codigo).carpeta)
        var primeras = Set<String>()
        var notasSueltas: [VaultPath] = []
        for ruta in salida.keys where ruta.isDescendant(of: base) && ruta != base {
            let resto = Array(ruta.components.dropFirst(base.components.count))
            if resto.count > 1 { primeras.insert(resto[0]) } else if ruta.ext == "md", ruta.name != AreaReader.fileName { notasSueltas.append(ruta) }
        }
        var lineas: [String] = []
        for nota in notasSueltas.sorted(by: { $0.raw < $1.raw }) {
            lineas.append("- " + Nombres.enlaceMarkdown(nota.stem, desde: desde, a: nota))
        }
        for nombre in primeras.sorted() {
            let carpeta = base.appending(nombre)
            if let indice = IndiceV2.todos.first(where: { $0.area == codigo && VaultPath(area(codigo).carpeta + "/" + $0.ruta).parent == carpeta }),
               tieneRegistros(indice) {
                lineas.append("- " + Nombres.enlaceMarkdown(indice.titulo, desde: desde, a: ruta(codigo, indice.ruta)))
            } else {
                lineas.append("- `\(nombre)/`")
            }
        }
        return lineas.isEmpty ? nil : lineas.joined(separator: "\n")
    }

    func escribirIndice(_ indice: IndiceV2) {
        var fm = FrontmatterNuevo(tipo: "index", id: IDsDerivados.id("indice:" + indice.coleccion))
        fm.literal("coleccion", indice.coleccion)
        fm.texto("vista", indice.vista)
        fm.literal("agrupar_por", indice.agruparPor)
        fm.literal("pestanas_por", indice.pestanasPor)
        var nota = NotaNueva(frontmatter: fm, titulo: indice.titulo)
        nota.entradilla = indice.texto
        escribir(ruta(indice.area, indice.ruta), nota)
    }

    /// `.tls/layout.json`, `.tls/config.yaml` (clase, reloj de la demo y datos del emisor) y `.tls/secuencias.json`.
    func escribirAjustes() {
        escribir(VaultPath(".tls/layout.json"), texto: "{\"preset\":\"humana\"}\n")
        let perfil = empresa.campos.mapa("profile") ?? .vacio
        let semilla = empresa.campos.texto("workspace_id") ?? nombreOrigen
        var lineas = [
            "# Configuración de esta carpeta, creada por The Last System al convertir una exportación de G2.",
            "# Lo que cambies aquí no llega a la carpeta de origen.",
            "version: 1",
            "id: \(IDsDerivados.id("carpeta:" + semilla))",
            "clase: \(opciones.clase.rawValue)",
            "origen: \(EscrituraYAML.comillas(nombreOrigen))",
            "creada: \(fecha)",
        ]
        if let hoy = opciones.hoy { lineas.append("hoy: \(hoy)") }
        lineas.append("privado: []")
        let facturacion = [("razon_social", perfil.texto("razon_social")), ("nif", perfil.texto("nif"))]
            .compactMap { k, v in v.map { Propiedad(clave: k, valor: .texto($0)) } }
        if !facturacion.isEmpty {
            lineas.append("# Datos del emisor: solo los pone la app en los PDF; ningún asistente los lee.")
            lineas.append(EscrituraYAML.linea(Propiedad(clave: "facturacion", valor: .mapa(facturacion)), sangria: 0))
        }
        escribir(VaultPath(".tls/config.yaml"), texto: lineas.joined(separator: "\n") + "\n")
        if let ultimo = tareas.compactMap({ Int($0.numero.dropFirst(2)) }).max() {
            escribir(VaultPath(".tls/secuencias.json"), texto: "{\"tarea\":\(ultimo)}\n")
        }
    }

    /// Lo que no se ha convertido se guarda tal cual en `Archivo/Importación <fecha>/<ruta de origen>`.
    func archivarLoNoConvertido() {
        let base = VaultPath("Archivo/Importación \(fecha)")
        for r in carpeta.registros where !tratadas.contains(r.ruta.raw) {
            let motivo: String
            if r.ilegible { motivo = "Propiedades ilegibles" }
            else if let t = r.tipo { motivo = "Tipo «\(t)» sin conversión" }
            else { motivo = "Nota sin tipo" }
            avisar("Notas que se guardan sin convertir en Archivo (\(motivo.lowercased()))", r,
                   queHacer: "Revísalas en \(base.raw)/ y decide si las quieres en un área.")
            copiar(r.ruta.url(in: carpeta.raiz), a: reservar(base.appending(r.ruta.raw)))
            archivados.append(r.ruta.raw)
        }
        for f in carpeta.ficheros where !tratadas.contains(f.ruta.raw) {
            avisar("Ficheros que se guardan sin convertir en Archivo", ruta: f.ruta.raw,
                   queHacer: "Revísalos en \(base.raw)/ y decide dónde van.")
            copiar(f.url, a: reservar(base.appending(f.ruta.raw)))
            archivados.append(f.ruta.raw)
        }
        for ruta in carpeta.soloEnICloud {
            avisar("Ficheros solo en iCloud (no se han leído ni copiado)", ruta: ruta.raw, queHacer: "Descárgalos y vuelve a convertir.")
        }
        for ruta in carpeta.enlaces {
            avisar("Enlaces simbólicos (no se siguen)", ruta: ruta.raw, queHacer: "Copia a mano lo que apunten si hace falta.")
        }
        if !archivados.isEmpty { bloque("Lo que no tiene conversión", destino: base.raw) }
    }

    /// `Buzón/Informe de importación <fecha>.md`.
    func escribirInforme(_ i: InformeConversionG2) {
        let destino = VaultPath(i.informe)
        var fm = FrontmatterNuevo(tipo: "import_report", id: IDsDerivados.id("informe:" + nombreOrigen + ":" + fecha))
        fm.literal("fecha", fecha)
        fm.texto("fuente", "G2 · \(nombreOrigen)")
        fm.literal("ficheros", String(i.ficherosOrigen))
        fm.literal("convertidos", String(i.porTipo.values.reduce(0, +)))
        fm.literal("archivados", String(i.archivados.count))
        fm.literal("verificados", String(i.verificados))
        fm.texto("estado", "Aplicado")
        var nota = NotaNueva(frontmatter: fm, titulo: "Importación del \(G2Fecha.corta(fecha)) \(fecha.prefix(4))")
        nota.resumen = ["Aplicado", "\(i.ficherosOrigen) ficheros de origen", "no se borró nada"]
        nota.seccion("Resumen", TablaMarkdown.texto(["Qué", "Cuántos"], [
            ["Ficheros de origen", String(i.ficherosOrigen)],
            ["Registros convertidos", String(i.porTipo.values.reduce(0, +))],
            ["Notas creadas", String(i.notas)],
            ["Tablas CSV creadas", String(i.tablas)],
            ["Ficheros copiados tal cual (PDF y CSV)", String(i.copiados)],
            ["Justificantes comprobados con su huella", String(i.verificados)],
            ["Fichas de tarea creadas", String(i.tareas)],
            ["Guardados sin convertir en Archivo", String(i.archivados.count)],
        ]))
        nota.seccion("Por bloques", TablaMarkdown.texto(["Bloque de origen", "Ficheros", "Destino"],
                                                        i.bloques.map { [$0.origen, String($0.ficheros), $0.destino] }))
        let base = VaultPath("Archivo/Importación \(fecha)")
        let archivo = i.archivados.map { "- " + Nombres.enlaceMarkdown($0, desde: destino, a: base.appending($0)) }
        nota.seccion("Lo que se quedó donde estaba",
                     (["La carpeta de origen no se ha tocado. Lo que no tiene sitio en la estructura nueva se guarda tal cual en `\(base.raw)/`:"]
                      + archivo).joined(separator: "\n"))
        nota.seccion("Duplicados", "Ninguno.")
        nota.seccion("Calidad de los datos", i.avisos.isEmpty ? "Sin avisos." :
            TablaMarkdown.texto(["Aviso", "Fichas", "Qué hacer"], i.avisos.map { [$0.texto, String($0.fichas.count), $0.queHacer] }))
        nota.seccion("Campos sin convertir", i.camposNoConvertidos.isEmpty ? "Ninguno." :
            TablaMarkdown.texto(["Campo de G2", "Fichas", "Por qué"], i.camposNoConvertidos.map { [$0.campo, String($0.fichas), $0.motivo] }))
        nota.seccion("Cómo deshacer", "La conversión crea una carpeta nueva y no cambia la de origen. Para deshacerla, retira esta carpeta.")
        escribir(destino, nota)
    }
}
