import Foundation

/// Instala las plantillas de serie en la carpeta (PLANTILLAS.md §1.1): cada una junto a su sistema
/// (`N · Área/Sistemas/Plantillas/`; las comunes y las del Buzón, en Dirección) y su ficha en
/// `.tls/plantillas.yaml`. Nunca pisa: lo que ya está se deja (y se avisa si es distinto del original).
public struct PlantillaInstalador: Sendable {
    /// Lo que haría la instalación.
    public struct Informe: Sendable {
        /// Plantillas que se copian.
        public let nuevas: [VaultPath]
        /// Ya estaban, iguales a la original.
        public let yaEstaban: [VaultPath]
        /// Ya estaban, pero cambiadas por ti: no se tocan (se pueden ver las diferencias).
        public let distintas: [VaultPath]
        /// Entradas que se añaden a `.tls/plantillas.yaml`.
        public let registro: [String]
        /// `nil` si no hay nada que hacer.
        public let plan: WritePlan?

        public var resumen: String {
            if plan == nil { return "Las plantillas ya están instaladas." }
            var partes = [Plural.de(nuevas.count, "plantilla nueva", "plantillas nuevas")]
            if !distintas.isEmpty { partes.append(Plural.de(distintas.count, "cambiada por ti, que no se toca", "cambiadas por ti, que no se tocan")) }
            return "Instalar " + Plural.lista(partes) + "."
        }
    }

    public let snapshot: VaultSnapshot

    public init(snapshot: VaultSnapshot) { self.snapshot = snapshot }

    static let cabecera = """
    # Plantillas de esta carpeta: qué crea cada una, dónde, con qué nombre y qué pregunta al crear.
    # Lo instaló The Last System. Puedes cambiarlo: la app no pisa lo que escribas.

    """

    /// Prepara la instalación de las plantillas de serie (todas, las de unas áreas, unas concretas o las
    /// de unos sistemas). Las comunes van con Dirección.
    public func preparar(areas: Set<AreaCode>? = nil, ids: Set<String>? = nil, sistemas: Set<String>? = nil,
                         autor: Autor = .persona("Manu")) -> Informe {
        let serie = PlantillaRegistro.deSerie
        let elegidas = serie.plantillas.filter { def in
            if let ids, !ids.contains(def.id) { return false }
            if let areas, !areas.contains(def.area ?? .direccion) { return false }
            if let sistemas, Set(def.sistemas).isDisjoint(with: sistemas), !def.sistemas.contains("todos") { return false }
            return true
        }
        var nuevas: [VaultPath] = [], ya: [VaultPath] = [], distintas: [VaultPath] = []
        var ops: [WriteOp] = []
        for def in elegidas {
            guard let origen = def.origen, let datos = PlantillasDeSerie.datos(origen) else { continue }
            let destino = snapshot.layout.expand(def.fichero)
            if let actual = snapshot.existing(destino) {
                if snapshot.data(actual) == datos || snapshot.dataless.contains(actual) { ya.append(actual) } else { distintas.append(actual) }
                continue
            }
            nuevas.append(destino)
            ops.append(.create(destino, contents: datos))
        }
        // `.tls/plantillas.yaml`: se añaden las que falten, sin reescribir lo que hay.
        var registro: [String] = []
        let bloques = PlantillaRegistro.bloques(PlantillasDeSerie.registroTexto ?? "")
        let elegidasIDs = Set(elegidas.map(\.id))
        let ruta = PlantillaRegistro.ruta
        if let data = snapshot.data(ruta), let text = snapshot.text(ruta) {
            let existentes = Set(PlantillaRegistro.bloques(text).map(\.id))
            let faltan = bloques.filter { elegidasIDs.contains($0.id) && !existentes.contains($0.id) }
            if !faltan.isEmpty {
                registro = faltan.map(\.id)
                var nuevo = text
                if !nuevo.isEmpty, !nuevo.hasSuffix("\n") { nuevo += "\n" }
                nuevo += faltan.map(\.texto).joined(separator: "\n") + "\n"
                if let op = WriteOp.replaceText(ruta, base: data, text: nuevo) { ops.append(op) }
            }
        } else {
            let elegidos = bloques.filter { elegidasIDs.contains($0.id) }
            if !elegidos.isEmpty {
                registro = elegidos.map(\.id)
                ops.append(.create(ruta, text: Self.cabecera + elegidos.map(\.texto).joined(separator: "\n") + "\n"))
            }
        }
        // Las plantillas se llaman como notas de verdad (`Contrato`, `Portal`, `Metas`…): los enlaces que ya
        // había siguen yendo a la suya.
        if !nuevas.isEmpty { ops = LinkRefactor(snapshot: snapshot).protegerEnlaces(alCrear: nuevas, opciones: .init(autor: autor)) + ops }
        let plan = ops.isEmpty ? nil : WritePlan(autor: autor, descripcion: "Instalar " + Plural.de(nuevas.count, "plantilla", "plantillas"), ops: ops)
        return Informe(nuevas: nuevas, yaEstaban: ya, distintas: distintas, registro: registro, plan: plan)
    }
}
