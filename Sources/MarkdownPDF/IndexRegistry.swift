import Foundation

/// Collects index hits while a layout pass draws, then produces the sorted
/// entries. A fresh registry is made for every pass.
struct IndexRegistry {
    private var mainDisplays: [String: String] = [:]
    private var subDisplays: [IndexEntryID: String] = [:]
    private var pagesByEntry: [IndexEntryID: Set<Int>] = [:]

    var isEmpty: Bool {
        pagesByEntry.isEmpty
    }

    /// Parses an entry term: `main` or `main > sub`, split at the first `>`.
    /// Components are trimmed. Returns nil when the main component is empty, which
    /// callers treat as "ignore". `a >` (empty sub) is the main entry `a`.
    static func entry(for term: String) -> (id: IndexEntryID, main: String, sub: String?)? {
        let parts = term.split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
        let main = collapsed(String(parts[0]))
        guard !main.isEmpty else {
            return nil
        }
        let sub = parts.count > 1 ? collapsed(String(parts[1])) : ""
        let id = IndexEntryID(
            main: IndexCollation.key(main),
            sub: sub.isEmpty ? nil : IndexCollation.key(sub),
        )
        return (id, main, sub.isEmpty ? nil : sub)
    }

    /// Registers an entry so it is listed even before any hit, and keeps the first
    /// display spelling seen for each key. Registration alone does not make an entry
    /// appear: an entry with no pages and no sub-entry with pages is dropped.
    mutating func register(_ entry: (id: IndexEntryID, main: String, sub: String?)) {
        if mainDisplays[entry.id.main] == nil {
            mainDisplays[entry.id.main] = entry.main
        }
        if let sub = entry.sub, subDisplays[entry.id] == nil {
            subDisplays[entry.id] = sub
        }
    }

    mutating func record(_ id: IndexEntryID, page: Int) {
        pagesByEntry[id, default: []].insert(page)
    }

    /// The entries in final order. Main entries and each main entry's sub-entries
    /// sort by ``IndexCollation``; an entry with neither pages nor sub-entries is
    /// omitted.
    func records() -> [IndexRecord] {
        var subsByMain: [String: [IndexRecord]] = [:]
        var mainPages: [String: [Int]] = [:]
        for (id, pages) in pagesByEntry {
            if id.sub != nil {
                let display = subDisplays[id] ?? ""
                subsByMain[id.main, default: []].append(IndexRecord(display: display, pages: pages.sorted(), subentries: []))
            } else {
                mainPages[id.main] = pages.sorted()
            }
        }

        let mainKeys = Set(subsByMain.keys).union(mainPages.keys)
        let mains = mainKeys.map { key -> IndexRecord in
            let subs = (subsByMain[key] ?? []).sorted { IndexCollation.precedes($0.display, $1.display) }
            return IndexRecord(display: mainDisplays[key] ?? key, pages: mainPages[key] ?? [], subentries: subs)
        }
        return mains.sorted { IndexCollation.precedes($0.display, $1.display) }
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
