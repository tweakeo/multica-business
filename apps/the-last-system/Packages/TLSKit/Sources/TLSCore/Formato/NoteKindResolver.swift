import Foundation

/// Qué es una nota: `tls_type` > `tipo` heredado > carpeta.
public enum NoteKindResolver {
    /// `tipo:` de las notas hechas a mano (G1/G3).
    static let legacyTypes: [String: NoteKind] = [
        "persona": .contact, "contacto": .contact,
        "empresa": .organization, "organizacion": .organization, "organización": .organization,
        "oportunidad": .opportunity,
    ]

    /// Tipos de layout.json que no coinciden con el nombre de `NoteKind`.
    static let layoutTypes: [String: NoteKind] = [
        "invoice_draft": .draft,
    ]

    public static func kind(of path: VaultPath, frontmatter: Frontmatter?, layout: VaultLayout) -> NoteKind {
        let ext = path.ext
        if ext == "csv" { return .csv }
        guard ext == "md" || ext == "markdown" else {
            return ext == "txt" ? .note : .other
        }
        // Las plantillas (`…/Sistemas/Plantillas/…`) llevan `tls_type`, pero no son fichas.
        if isTemplate(path) { return .note }
        if let fm = frontmatter {
            if let t = fm.text("tls_type") {
                let key = t.lowercased()
                if let k = NoteKind(rawValue: key) { return k }
                if let k = layoutTypes[key] { return k }
                return .note
            }
            if let t = fm.text("tipo"), let k = legacyTypes[TextFolding.nameKey(t)] {
                return k
            }
        }
        return kindByFolder(path, layout: layout)
    }

    /// `true` si la nota es una plantilla (`…/Sistemas/Plantillas/…`): se lista y se busca como nota normal.
    public static func isTemplate(_ path: VaultPath) -> Bool {
        VaultSnapshot.isTemplatePath(path)
    }

    /// Reglas por carpeta (sin leer el contenido).
    public static func kindByFolder(_ path: VaultPath, layout: VaultLayout) -> NoteKind {
        let comps = path.components
        let nameKey = TextFolding.nameKey(path.name)
        if path.ext == "csv" { return .csv }
        guard path.ext == "md" || path.ext == "markdown" else { return path.ext == "txt" ? .note : .other }
        if layout.isArchived(path) || isTemplate(path) { return .note }
        // Empresa.md en la raíz.
        if comps.count == 1, nameKey == "empresa.md" { return .company }
        let area = layout.area(of: path)
        // Área.md directamente en la carpeta del área.
        if comps.count == 2, area != nil, nameKey == "área.md" || nameKey == "area.md" { return .area }
        // N · Área/Sistemas/** → sistema.
        if area != nil, comps.count >= 3, TextFolding.nameKey(comps[1]) == "sistemas" { return .system }
        // …/Proyectos/<slug>/Proyecto.md
        if comps.count >= 3, nameKey == "proyecto.md",
           TextFolding.nameKey(comps[comps.count - 3]) == TextFolding.nameKey(layout.proyectos) {
            return .project
        }
        // …/Tareas/<ficha>.md (no el `Tareas.md` heredado).
        if comps.count >= 2, TextFolding.nameKey(comps[comps.count - 2]) == TextFolding.nameKey(layout.tareas),
           layout.isRecordNote(path) {
            return .task
        }
        // Cuenta bancaria: …/Bancos/<cuenta>/Cuenta.md
        if let acc = layout.dir(for: "account"), nameKey == "cuenta.md", path.parent?.parent == acc { return .account }
        if let type = layout.inferType(path) {
            if let k = NoteKind(rawValue: type) { return k }
            if let k = layoutTypes[type] { return k }
            return .note
        }
        return .note
    }
}
