import Foundation

struct EmojiEntry: Decodable, Hashable {
    let glyph: String
    let russian: String
    let english: String
    let categoryID: String
    /// The unmodified base is always first, followed by every valid tone form.
    let variants: [String]
    fileprivate let keywords: [String]
}

struct EmojiCategory: Decodable, Hashable {
    let id: String
    let icon: String
    let russian: String
    let english: String
    let entries: [EmojiEntry]
}

enum EmojiCatalogError: Error {
    case invalidCatalog(String)
}

/// All data is bundled. New Unicode sequences may need a newer system emoji
/// font; membership here does not promise that the host OS can render a glyph.
final class EmojiCatalog {
    static let shared: EmojiCatalog = {
        guard let url = Bundle.main.url(forResource: "EmojiCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? EmojiCatalog(data: data) else {
            // Keep the keyboard usable if an app packaging error omits the resource.
            return EmojiCatalog()
        }
        return catalog
    }()

    let categories: [EmojiCategory]
    let entries: [EmojiEntry]
    let unicodeVersion: String
    let cldrVersion: String
    private let glyphIndex: [String: Int]
    private let searchRecords: [SearchRecord]

    private struct SearchRecord {
        let names: Set<String>
        let keywords: Set<String>
        let words: Set<String>
        let text: String

        init(entry: EmojiEntry) {
            names = Set([entry.russian, entry.english].map(EmojiCatalog.searchKey))
            keywords = Set(entry.keywords.map(EmojiCatalog.searchKey))
            text = (Array(names) + Array(keywords)).joined(separator: " ")
            words = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }

        func rank(phrase: String, terms: [String]) -> Int? {
            guard terms.allSatisfy({ text.contains($0) }) else { return nil }
            if names.contains(phrase) { return 0 }
            if keywords.contains(phrase) || terms.allSatisfy({ words.contains($0) || keywords.contains($0) }) {
                return 1
            }
            if terms.allSatisfy({ term in words.contains(where: { $0.hasPrefix(term) }) }) { return 2 }
            // Keep partial Russian inflections searchable, but don't let "cat"
            // inside "intoxicated" outrank an actual cat keyword.
            return 3
        }
    }

    private struct Payload: Decodable {
        let formatVersion: Int
        let unicodeVersion: String
        let cldrVersion: String
        let fullyQualifiedCount: Int
        let baseCount: Int
        let categories: [EmojiCategory]
    }

    init(data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let flattened = payload.categories.flatMap(\.entries)
        guard payload.formatVersion == 1, !flattened.isEmpty,
              payload.baseCount == flattened.count,
              Set(payload.categories.map(\.id)).count == payload.categories.count else {
            throw EmojiCatalogError.invalidCatalog("Invalid format, count or categories")
        }
        var index: [String: Int] = [:]
        var offset = 0
        var variantCount = 0
        for category in payload.categories {
            guard !category.id.isEmpty, !category.entries.isEmpty else {
                throw EmojiCatalogError.invalidCatalog("Empty category")
            }
            for entry in category.entries {
                guard !entry.glyph.isEmpty, !entry.russian.isEmpty, !entry.english.isEmpty,
                      entry.categoryID == category.id, entry.variants.first == entry.glyph else {
                    throw EmojiCatalogError.invalidCatalog("Invalid base entry")
                }
                for variant in entry.variants {
                    let key = Self.glyphKey(variant)
                    guard !key.isEmpty, index[key] == nil else {
                        throw EmojiCatalogError.invalidCatalog("Duplicate or empty variant")
                    }
                    index[key] = offset
                    variantCount += 1
                }
                offset += 1
            }
        }
        guard variantCount == payload.fullyQualifiedCount else {
            throw EmojiCatalogError.invalidCatalog("Incomplete variant coverage")
        }
        categories = payload.categories
        entries = flattened
        unicodeVersion = payload.unicodeVersion
        cldrVersion = payload.cldrVersion
        glyphIndex = index
        searchRecords = flattened.map(SearchRecord.init)
    }

    private init() {
        categories = []
        entries = []
        unicodeVersion = ""
        cldrVersion = ""
        glyphIndex = [:]
        searchRecords = []
    }

    /// Every tone/ZWJ variant resolves to its base entry. Omitting an emoji
    /// presentation selector is accepted for pasted glyph searches, too.
    func entry(for glyph: String) -> EmojiEntry? {
        guard let index = glyphIndex[Self.glyphKey(glyph)] else { return nil }
        return entries[index]
    }

    func search(_ query: String) -> [EmojiEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return entries }
        if let exactGlyph = entry(for: trimmed) { return [exactGlyph] }
        let terms = Self.searchKey(trimmed).split(whereSeparator: \.isWhitespace).map(String.init)
        let phrase = terms.joined(separator: " ")
        let matches = entries.indices.compactMap { index -> (index: Int, rank: Int)? in
            guard let rank = searchRecords[index].rank(phrase: phrase, terms: terms) else { return nil }
            return (index, rank)
        }
        return matches.sorted { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.index < rhs.index : lhs.rank < rhs.rank
        }.map { entries[$0.index] }
    }

    fileprivate func canonicalGlyph(for glyph: String) -> String? {
        guard let entry = entry(for: glyph) else { return nil }
        let key = Self.glyphKey(glyph)
        return entry.variants.first { Self.glyphKey($0) == key }
    }

    private static func glyphKey(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FE0F}", with: "")
    }

    private static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
    }
}

/// Local keyboard preferences only: selected emoji and preferred tone forms.
/// It never receives or saves the search query, document text, or input history.
final class EmojiHistory {
    static let storageKey = "ThumbSplit.emoji.history.v1"
    private let defaults: UserDefaults
    private let catalog: EmojiCatalog
    private var preferred: [String: String] = [:]
    private(set) var recents: [String] = []

    init(defaults: UserDefaults = .standard, catalog: EmojiCatalog = .shared) {
        self.defaults = defaults
        self.catalog = catalog
        let saved = defaults.dictionary(forKey: Self.storageKey) ?? [:]
        var seen = Set<String>()
        for value in (saved["recents"] as? [Any] ?? []).prefix(400) {
            guard let raw = value as? String, let glyph = catalog.canonicalGlyph(for: raw),
                  seen.insert(glyph).inserted else { continue }
            recents.append(glyph)
            if recents.count == 40 { break }
        }
        for (base, value) in saved["preferred"] as? [String: Any] ?? [:] {
            guard let raw = value as? String, let entry = catalog.entry(for: base),
                  entry.glyph == base, let glyph = catalog.canonicalGlyph(for: raw),
                  glyph != base, entry.variants.contains(glyph) else { continue }
            preferred[base] = glyph
        }
        // Normalize malformed/obsolete values so persisted data stays emoji-only.
        persist()
    }

    func preferredGlyph(for entry: EmojiEntry) -> String {
        guard let chosen = preferred[entry.glyph], entry.variants.contains(chosen) else { return entry.glyph }
        return chosen
    }

    func record(_ glyph: String) {
        guard let canonical = catalog.canonicalGlyph(for: glyph),
              let entry = catalog.entry(for: canonical) else { return }
        recents.removeAll { $0 == canonical }
        recents.insert(canonical, at: 0)
        if recents.count > 40 { recents.removeLast(recents.count - 40) }
        if canonical == entry.glyph {
            preferred.removeValue(forKey: entry.glyph)
        } else {
            preferred[entry.glyph] = canonical
        }
        persist()
    }

    private func persist() {
        defaults.set(["recents": recents, "preferred": preferred], forKey: Self.storageKey)
    }
}
