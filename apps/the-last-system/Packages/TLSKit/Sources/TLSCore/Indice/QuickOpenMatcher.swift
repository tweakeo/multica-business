import Foundation

/// ⌘O: coincidencia sin tildes ni mayúsculas entre título y nombre del fichero.
/// Orden: prefijo > inicio de palabra > subcadena > subsecuencia.
struct QuickOpenMatcher: Sendable {
    struct Entry: Sendable {
        let summary: NoteSummary
        let title: String
        let stem: String
        let archived: Bool
    }

    let entries: [Entry]

    init(rows: [VaultIndex.NoteRow]) {
        entries = rows.map {
            Entry(summary: $0.summary, title: TextFolding.fold($0.title), stem: TextFolding.fold($0.path.stem),
                  archived: $0.archivado)
        }
    }

    static let empty = QuickOpenMatcher(rows: [])

    func search(_ query: String, limit: Int) -> [NoteSummary] {
        let q = TextFolding.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, limit > 0 else { return [] }
        let words = q.split(whereSeparator: { $0 == " " }).map(String.init)
        var scored: [(Entry, Int)] = []
        for e in entries {
            var best = max(Self.score(q, in: e.title), Self.score(q, in: e.stem))
            if best == 0, words.count > 1 {
                // «ven emb»: todas las palabras deben aparecer.
                let all = words.allSatisfy { Self.score($0, in: e.title) >= 600 || Self.score($0, in: e.stem) >= 600 }
                if all { best = 500 }
            }
            guard best > 0 else { continue }
            if e.archived { best -= 150 }
            scored.append((e, best))
        }
        scored.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.title.count != b.0.title.count { return a.0.title.count < b.0.title.count }
            return a.0.summary.path < b.0.summary.path
        }
        return scored.prefix(limit).map(\.0.summary)
    }

    /// 1000 prefijo · 800 inicio de palabra · 600 subcadena · 300 subsecuencia · 0 nada.
    static func score(_ q: String, in s: String) -> Int {
        if s.hasPrefix(q) { return 1000 }
        var searchStart = s.startIndex
        var substring = false
        while let r = s.range(of: q, range: searchStart..<s.endIndex) {
            substring = true
            if r.lowerBound == s.startIndex || !s[s.index(before: r.lowerBound)].isLetterOrDigit { return 800 }
            searchStart = s.index(after: r.lowerBound)
        }
        if substring { return 600 }
        var it = s.makeIterator()
        for c in q {
            var found = false
            while let x = it.next() { if x == c { found = true; break } }
            if !found { return 0 }
        }
        return 300
    }
}

extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
