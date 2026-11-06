import Foundation

/// Uses the same property-list shape as UserDefaults without touching the user's
/// preference domain. Reload tests serialize and reconstruct that persisted data.
private final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    init(values: [String: Any] = [:]) {
        super.init(suiteName: "SplitPad.EmojiCatalogTests")!
        self.values = values
    }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        values[defaultName] as? [String: Any]
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}

@main
struct EmojiCatalogTests {
    private static var checks = 0

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: emoji-catalog-tests EmojiCatalog.json emoji-test.txt")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let source = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let catalog = try EmojiCatalog(data: data)
        coverage(catalog, source: source)
        variants(catalog)
        searches(catalog)
        try history(catalog)
        try invalidCatalogs(data)
        print("PASS: \(checks) emoji catalog/history checks; \(catalog.entries.count) bases; Unicode \(catalog.unicodeVersion), CLDR \(catalog.cldrVersion)")
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }

    private static func coverage(_ catalog: EmojiCatalog, source: String) {
        var expected = Set<String>()
        for line in source.split(separator: "\n") {
            let parts = line.split(separator: ";", maxSplits: 1)
            guard parts.count == 2, parts[1].trimmingCharacters(in: .whitespaces).hasPrefix("fully-qualified") else { continue }
            let scalars = parts[0].split(whereSeparator: \.isWhitespace).map { UnicodeScalar(UInt32($0, radix: 16)!)! }
            expected.insert(String(String.UnicodeScalarView(scalars)))
        }
        let variants = catalog.entries.flatMap(\.variants)
        expect(catalog.unicodeVersion == "18.0" && catalog.cldrVersion == "49", "Pinned stable release metadata")
        expect(expected.count == 3963, "Independent Unicode source contains all fully-qualified forms")
        expect(Set(variants) == expected, "Every fully-qualified source sequence occurs in catalog")
        expect(variants.count == expected.count, "No duplicate variants across entries")
        expect(catalog.entries.count == 1923, "Skin variants are grouped into base entries")
        expect(catalog.categories.map(\.id) == ["smileys", "people", "nature", "food", "travel", "activities", "objects", "symbols", "flags"],
               "All nine categories retain Unicode ordering")
        expect(catalog.entries.allSatisfy { $0.variants.first == $0.glyph }, "Every picker starts with its unmodified base")
        expect(catalog.entries.allSatisfy { !$0.russian.isEmpty && !$0.english.isEmpty }, "All bases have RU and EN names")
        expect(catalog.categories.allSatisfy { category in category.entries.allSatisfy { $0.categoryID == category.id } },
               "Entry categories match category grouping")
        expect(catalog.categories.first { $0.id == "flags" }?.entries.count == 270, "Complete flag category")
        for flag in ["🇷🇺", "🇺🇸", "🇪🇺", "🇺🇳", "🏳️‍🌈", "🏳️‍⚧️", "🏴‍☠️",
                     "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
                     "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
                     "🏴\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"] {
            expect(catalog.entry(for: flag)?.categoryID == "flags", "Country, identity or subdivision flag is present")
        }
        expect(catalog.entry(for: "🏽") == nil, "Isolated skin components are not invented as selectable bases")
        expect(catalog.entry(for: "not an emoji") == nil, "Arbitrary text is not an emoji entry")
    }

    private static func variants(_ catalog: EmojiCatalog) {
        for base in ["👍", "👩‍⚕️", "👨‍🚀", "🧑‍💻", "🏃‍♀️‍➡️"] {
            let entry = catalog.entry(for: base)!
            expect(entry.variants.count == 6, "Single-person tone set includes base and five tones")
            expect(entry.variants.allSatisfy { catalog.entry(for: $0)?.glyph == base }, "Each tone maps to original base")
        }
        for base in ["🤝", "👯", "👯‍♂️", "👯‍♀️", "🤼", "🤼‍♂️", "🤼‍♀️", "👫", "👬", "👭", "💏", "💑", "🧑‍🤝‍🧑", "👩‍❤️‍👨"] {
            expect(catalog.entry(for: base)?.variants.count == 26, "Two-person base includes all 25 tone combinations")
        }
        let mixed = [
            ("🫱🏻‍🫲🏿", "🤝"), ("👩🏻‍🤝‍👨🏿", "👫"), ("👨🏿‍🤝‍👨🏻", "👬"),
            ("🧑🏻‍❤️‍💋‍🧑🏿", "💏"), ("🧑🏿‍❤️‍🧑🏻", "💑"),
            ("👩🏻‍❤️‍👨🏿", "👩‍❤️‍👨"), ("🧑🏻‍🐰‍🧑🏿", "👯"), ("🧑🏻‍🫯‍🧑🏿", "🤼")
        ]
        for (glyph, base) in mixed {
            expect(catalog.entry(for: glyph)?.glyph == base, "Mixed tones resolve to the correct family of forms")
        }
        expect(catalog.entry(for: "👨‍👩‍👧‍👦")?.variants == ["👨‍👩‍👧‍👦"],
               "Unspecified family skin-tone combinations are not fabricated")
        expect(catalog.entry(for: "❤")?.glyph == "❤️", "Pasted text-presentation heart resolves to emoji base")
        expect(catalog.entry(for: "👩🏻‍⚕")?.glyph == "👩‍⚕️", "Variant lookup tolerates missing presentation selector")
        let newEmoji = "\u{1FAEB}"
        expect(catalog.entry(for: newEmoji) != nil, "Unicode 18 entry remains in data independently of OS font support")
    }

    private static func searches(_ catalog: EmojiCatalog) {
        func contains(_ query: String, _ glyph: String) -> Bool {
            catalog.search(query).contains { $0.glyph == glyph }
        }
        expect(contains("cat", "🐈"), "English CLDR keywords")
        let catMatches = catalog.search("cat")
        expect(catMatches.first?.glyph == "🐈", "Exact English name outranks incidental substring matches")
        expect(catMatches.prefix(10).allSatisfy { $0.english.contains("cat") },
               "Cat search leads with felines, not intoxicated or complicated faces")
        expect(catalog.search("cat face").first?.glyph == "🐱", "Exact multiword name ranks first")
        expect(catalog.search("плачущий кот").first?.glyph == "😿", "Exact Russian name ranks first")
        expect(catalog.search("кот").prefix(9).allSatisfy { $0.english.contains("cat") },
               "Russian cat keyword leads with feline results")
        expect(catMatches.firstIndex { $0.glyph == "😺" }! < catMatches.firstIndex { $0.glyph == "😸" }!,
               "Equivalent keyword matches retain Unicode order")
        expect(catMatches.lastIndex { $0.glyph == "🥴" }! > catMatches.firstIndex { $0.glyph == "🐱" }!,
               "Inside-word intoxicated match remains a low-priority fallback")
        expect(catMatches.firstIndex { $0.glyph == "🐱" }! < catMatches.firstIndex { $0.glyph == "🫴" }! &&
               catMatches.firstIndex { $0.glyph == "🫴" }! < catMatches.firstIndex { $0.glyph == "🥴" }!,
               "Whole-word cat outranks prefix catch, which outranks interior intoxicated")
        expect(contains("шач", "🐱"), "Partial Russian inflections retain substring fallback")
        expect(contains("КОШКА", "🐈"), "Russian case-insensitive keywords")
        expect(contains("woman technologist", "👩‍💻"), "Multiword English AND search")
        expect(contains("женщина врач", "👩‍⚕️"), "Multiword Russian AND search")
        expect(contains("красн heart", "❤️"), "Terms can match both languages")
        expect(contains("велосипед", "🚲"), "Russian object keywords")
        expect(contains("елка", "🎄"), "Russian Christmas-tree keyword")
        expect(catalog.search("ёлка") == catalog.search("елка"), "Russian ё and е are equivalent")
        expect(catalog.search("  WOMAN\nTECHNOLOGIST  ") == catalog.search("woman technologist"), "Whitespace and case normalization")
        expect(catalog.search("woman nonexistent-term-qzx").isEmpty, "Every query word must match")
        expect(catalog.search("👍🏽").map(\.glyph) == ["👍"], "Exact variant glyph search returns its base")
        expect(catalog.search("❤").map(\.glyph) == ["❤️"], "Text-style glyph search")
        expect(catalog.search("  ") == catalog.entries, "Empty search returns the full catalog")
    }

    private static func history(_ catalog: EmojiCatalog) throws {
        let defaults = MemoryDefaults()
        let history = EmojiHistory(defaults: defaults, catalog: catalog)
        let thumb = catalog.entry(for: "👍")!
        expect(history.recents.isEmpty, "History begins empty")
        expect(history.preferredGlyph(for: thumb) == "👍", "No tone preference means base")
        history.record("👍🏻")
        history.record("👍🏿")
        history.record("👍🏻")
        expect(history.recents == ["👍🏻", "👍🏿"], "Exact-glyph dedup keeps distinct tones and moves selected form first")
        expect(history.preferredGlyph(for: thumb) == "👍🏻", "Last tone is preferred")
        history.record("not an emoji")
        history.record("👍 hello")
        history.record("🏽")
        expect(history.recents == ["👍🏻", "👍🏿"], "Invalid text and isolated components never enter history")
        let encoded = try PropertyListSerialization.data(fromPropertyList: defaults.values, format: .binary, options: 0)
        let decoded = try PropertyListSerialization.propertyList(from: encoded, format: nil) as! [String: Any]
        let reloadedDefaults = MemoryDefaults(values: decoded)
        let reloaded = EmojiHistory(defaults: reloadedDefaults, catalog: catalog)
        expect(reloaded.recents == history.recents, "Recents survive property-list persistence and reload")
        expect(reloaded.preferredGlyph(for: thumb) == "👍🏻", "Tone preference survives reload")
        reloaded.record("👍")
        expect(reloaded.preferredGlyph(for: thumb) == "👍", "Selecting unmodified base resets tone preference")
        expect(EmojiHistory(defaults: reloadedDefaults, catalog: catalog).preferredGlyph(for: thumb) == "👍",
               "Tone reset persists")
        reloaded.record("❤")
        expect(reloaded.recents.first == "❤️", "Stored forms are canonical fully-qualified emoji")
        for entry in catalog.entries.prefix(50) { reloaded.record(entry.glyph) }
        expect(reloaded.recents.count == 40, "Recents remain bounded at 40")
        expect(reloaded.recents.first == catalog.entries[49].glyph && reloaded.recents.last == catalog.entries[10].glyph,
               "Bound evicts least recent exact glyphs")

        let corrupt = MemoryDefaults(values: [EmojiHistory.storageKey: [
            "recents": ["secret typed text", "👍🏻", 42, "👍🏻", "❤️", "❤"],
            "preferred": ["👍": "👍🏻", "❤️": "👍🏿", "😀": "typed text", "unknown": "👍🏻", "👋": 42]
        ]])
        let repaired = EmojiHistory(defaults: corrupt, catalog: catalog)
        expect(repaired.recents == ["👍🏻", "❤️"], "Corrupt recents are validated, canonicalized and deduplicated")
        expect(repaired.preferredGlyph(for: thumb) == "👍🏻", "Valid persisted tone survives repair")
        expect(repaired.preferredGlyph(for: catalog.entry(for: "❤️")!) == "❤️", "Cross-base persisted preference is rejected")
        let sanitized = corrupt.dictionary(forKey: EmojiHistory.storageKey)!
        expect((sanitized["preferred"] as? [String: String]) == ["👍": "👍🏻"], "Persisted preference map contains only validated forms")
        expect((sanitized["recents"] as? [String]) == ["👍🏻", "❤️"], "Corrupt raw text is removed from persisted recents")
        let wrongType = MemoryDefaults(values: [EmojiHistory.storageKey: "corrupt"])
        expect(EmojiHistory(defaults: wrongType, catalog: catalog).recents.isEmpty, "Wrong top-level defaults type is safely reset")
    }

    private static func invalidCatalogs(_ data: Data) throws {
        func rejected(_ object: [String: Any]) -> Bool {
            let bytes = try! JSONSerialization.data(withJSONObject: object)
            return (try? EmojiCatalog(data: bytes)) == nil
        }
        let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var wrongCount = original
        wrongCount["fullyQualifiedCount"] = 1
        expect(rejected(wrongCount), "Decoder rejects incomplete coverage metadata")
        var duplicate = original
        var categories = original["categories"] as! [[String: Any]]
        var entries = categories[0]["entries"] as! [[String: Any]]
        entries[0]["variants"] = [entries[0]["glyph"]!, entries[0]["glyph"]!]
        categories[0]["entries"] = entries
        duplicate["categories"] = categories
        expect(rejected(duplicate), "Decoder rejects duplicate variant ownership")
        var wrongVersion = original
        wrongVersion["formatVersion"] = 99
        expect(rejected(wrongVersion), "Unknown data schema is rejected")
    }
}
