import Foundation
import TLSCore

/// Qué no se copia (ni se lista) de un origen, y las comprobaciones de antes y después de recorrerlo.
///
/// - Lo de la persona (`CopyOptions.exclusiones`), tal cual lo eligió.
/// - Lo que la carpeta declara `privado` en `.tls/layout.json` y `.tls/config.yaml`, leído con el
///   núcleo (Yams y las plantillas `{finanzas}/…`), como rutas literales. Si esos ficheros existen pero
///   no se pueden leer (solo en iCloud, dañados…), se para: no se sabe qué es privado.
/// - `CopyOptions.siempre` y `Archivo/` (salvo que se pida).
///
/// Todo se compara en NFC y sin distinguir mayúsculas. Una ruta declarada que no coincide con nada
/// (errata, carpeta movida o renombrada) para la copia: mejor parar que copiar lo privado.
struct CopyExclusions: Sendable {
    let personales: [VaultPath]
    let privado: [VaultPath]
    let incluirArchivo: Bool
    /// Reglas del recorrido.
    let rules: ExclusionRules

    /// Debe llamarse en el hilo protegido (`DatalessGuard`): lee `.tls/` del origen.
    /// `completo`: solo lo de la persona y lo privado (incluye ocultos, `.DS_Store` y `Archivo/`).
    static func make(origen: URL, personales raw: [VaultPath], incluirArchivo: Bool, completo: Bool = false,
                     fs: any FileSystemAccess) throws -> CopyExclusions {
        let personales = ExclusionRules.relativized(raw, origen: origen)
        let privado: [VaultPath]
        do {
            privado = try VaultLayout.declaredPrivado(root: origen)
        } catch {
            throw CopyGuardError.privadoIlegible
        }
        let rules = completo
            ? ExclusionRules(paths: personales + privado)
            : ExclusionRules.forCopy(personales: personales, privado: privado, incluirArchivo: incluirArchivo)
        let plan = CopyExclusions(personales: personales, privado: privado,
                                  incluirArchivo: completo || incluirArchivo, rules: rules)
        // Antes de listar nada: cada ruta declarada existe o cuelga de algo que no se recorre.
        if let missing = ExclusionRules.missingBeforeWalk(personales, origen: origen, others: rules, fs: fs) {
            throw CopyGuardError.exclusionNoEncontrada(missing.raw)
        }
        if let missing = ExclusionRules.missingBeforeWalk(privado, origen: origen, others: rules, fs: fs) {
            throw CopyGuardError.privadoNoEncontrado(missing.raw)
        }
        return plan
    }

    /// Después de recorrer: lo declarado que no se podó ni quedó cubierto por otra cosa.
    func checkUnmatched(pruned: [VaultPath], items: [WalkItem]) throws {
        if let missing = ExclusionRules.unmatched(personales, pruned: pruned, items: items).first {
            throw CopyGuardError.exclusionNoEncontrada(missing.raw)
        }
        if let missing = ExclusionRules.unmatched(privado, pruned: pruned, items: items).first {
            throw CopyGuardError.privadoNoEncontrado(missing.raw)
        }
    }

    /// Lo que se informa como no copiado: lo declarado (persona, privado y `Archivo`) que de verdad se
    /// podó, con el nombre que tiene en disco. Lo de siempre (`.DS_Store`…) no se informa.
    func reported(pruned: [VaultPath]) -> [String] {
        var declared = personales + privado
        if !incluirArchivo { declared.append(VaultPath("Archivo")) }
        var byKey: [String: VaultPath] = [:]
        for p in pruned where byKey[ExclusionRules.key(p.raw)] == nil { byKey[ExclusionRules.key(p.raw)] = p }
        var seen = Set<String>()
        var out: [String] = []
        for d in declared {
            let k = ExclusionRules.key(d.raw)
            if let p = byKey[k], seen.insert(k).inserted { out.append(p.raw) }
        }
        return out
    }
}
