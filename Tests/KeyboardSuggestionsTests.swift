import Foundation

@main
struct KeyboardSuggestionsTests {
    private static var checks = 0
    private static let field = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func main() {
        completions()
        predictions()
        safety()
        supplementAndUnicode()
        spellingCorrections()
        spellingSafety()
        spellingRanking()
        print("PASS: \(checks) keyboard suggestion checks")
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAIL: \(message)") }
    }

    private static func context(_ before: String?, after: String? = nil, selection: String? = nil,
                                language: KeyboardLanguage = .english,
                                document: UUID = field) -> KeyboardSuggestionContext {
        KeyboardSuggestionContext(before: before, after: after, selectedText: selection,
                                  language: language, documentIdentifier: document)
    }

    private static func completions() {
        let english = context("Can you hel")
        let matches = KeyboardSuggestions.candidates(for: english)
        expect(matches.map(\.displayText).prefix(2) == ["hello", "help"], "Ranked English completions")
        expect(matches[0].replacementCount == 3, "Completion replaces just the current token")
        expect(matches[0].edit(ifCurrent: english) == KeyboardEdit(deleteBackwardCount: 3, text: "hello "),
               "Accepted completion inserts word and space")
        expect(KeyboardSuggestions.completionPrefix(in: english) == "hel", "System dictionary receives just prefix")
        let russian = context("Ну При", language: .russian)
        let ru = KeyboardSuggestions.candidates(for: russian)
        expect(ru.first?.displayText == "Привет", "Russian title case is preserved")
        expect(ru.first?.edit(ifCurrent: russian) == KeyboardEdit(deleteBackwardCount: 3, text: "Привет "),
               "Russian insertion uses grapheme replacement count")
        expect(KeyboardSuggestions.candidates(for: context("ПРИ", language: .russian)).first?.displayText == "ПРИВЕТ",
               "All-capitals prefix keeps capitals")
        expect(KeyboardSuggestions.candidates(for: context("hEL")).first?.displayText == "hELlo",
               "Mixed typed case remains intact")
        expect(KeyboardSuggestions.candidates(for: context("H")).first?.displayText == "Have",
               "One capital gives title case, not caps lock")
        let comma = context("hel", after: ", friend")
        expect(KeyboardSuggestions.candidates(for: comma).first?.insertionText == "hello",
               "Existing punctuation does not get a preceding space")
        let space = context("hel", after: " friend")
        expect(KeyboardSuggestions.candidates(for: space).first?.insertionText == "hello",
               "Existing whitespace is reused")
        expect(KeyboardSuggestions.candidates(for: context("hel"), limit: 0).isEmpty, "Caller may disable suggestions")
        expect(KeyboardSuggestions.candidates(for: context("a"), limit: 1000).count <= 8, "UI result count remains bounded")
    }

    private static func predictions() {
        let afterThanks = context("thank ")
        let next = KeyboardSuggestions.candidates(for: afterThanks)
        expect(next.first?.displayText == "you", "English next-word phrase")
        expect(next.allSatisfy { $0.replacementCount == 0 }, "Next-word suggestions never remove prior word")
        expect(next.first?.edit(ifCurrent: afterThanks) == KeyboardEdit(text: "you "), "Prediction only inserts")
        expect(KeyboardSuggestions.candidates(for: context("спасибо ", language: .russian)).first?.displayText == "за",
               "Russian next-word phrase")
        expect(KeyboardSuggestions.candidates(for: context("доброе ", language: .russian)).first?.displayText == "утро",
               "Russian morning phrase")
        expect(KeyboardSuggestions.candidates(for: context("Hello. ")).map(\.displayText) == ["I", "Hello", "Thanks"],
               "A new sentence uses starter predictions")
        expect(KeyboardSuggestions.candidates(for: context("thank\n")).first?.displayText == "I",
               "Newline does not reuse previous phrase")
        expect(KeyboardSuggestions.candidates(for: context("", language: .russian)).first?.displayText == "Я",
               "Empty Russian document uses sentence starters")
        let nilContext = context(nil)
        let initial = KeyboardSuggestions.candidates(for: nilContext)
        expect(!initial.isEmpty && initial.allSatisfy { $0.replacementCount == 0 },
               "Nil empty-host context permits only insertion predictions")
        expect(initial.first?.edit(ifCurrent: nilContext)?.deleteBackwardCount == 0,
               "Unknown context cannot authorize deletion")
        expect(KeyboardSuggestions.completionPrefix(in: nilContext) == nil, "Unknown context is not a dictionary prefix")
        expect(KeyboardSuggestions.completionPrefix(in: afterThanks) == nil, "Whole words before spaces are not completion prefixes")
        expect(KeyboardSuggestions.candidates(for: context("hello.")).isEmpty, "Prediction requires a word boundary")
    }

    private static func safety() {
        for selection in ["hello", " ", "🙂"] {
            let selected = context("hel", selection: selection)
            expect(KeyboardSuggestions.candidates(for: selected).isEmpty, "Selected text is protected")
            expect(KeyboardSuggestions.completionPrefix(in: selected) == nil, "Selected text never queried as prefix")
        }
        expect(!KeyboardSuggestions.candidates(for: context("hel", selection: "")).isEmpty,
               "Empty selection still permits completion")
        for after in ["lo", "2", "’s", "'s", "-word", "ё"] {
            let middle = context("hel", after: after)
            expect(KeyboardSuggestions.candidates(for: middle).isEmpty, "Cursor within token is protected")
            expect(KeyboardSuggestions.completionPrefix(in: middle) == nil, "Midword token never sent to completion dictionary")
        }
        for before in ["hel2", "3hel", "hello--", "--hello", "中文", "heл", String(repeating: "a", count: 49)] {
            expect(KeyboardSuggestions.candidates(for: context(before)).isEmpty, "Unsupported token is not replaced: \(before)")
        }
        let original = context("hel")
        let candidate = KeyboardSuggestions.candidates(for: original)[0]
        let staleContexts = [
            context("help"), context("he"), context("hel", after: "p"),
            context("hel", after: " "), context("hel", selection: "selected"),
            context("hel", language: .russian), context("hel", document: UUID()), context(nil)
        ]
        for changed in staleContexts {
            expect(candidate.edit(ifCurrent: changed) == nil, "Stale cursor, selection, field or language cancels acceptance")
        }
        expect(candidate.edit(ifCurrent: original) != nil, "Unchanged snapshot remains acceptable")
    }

    private static func supplementAndUnicode() {
        let names = KeyboardSuggestions.candidates(for: context("Nik"),
            supplementaryWords: ["Nikita", "nikita", "Никита", "Nik🙂", "Niko Smith", "Nikolai"])
        expect(names.map(\.displayText) == ["Nikita", "Nikolai"], "Local supplements filter scripts, duplicates and phrases")
        let ruName = KeyboardSuggestions.candidates(for: context("Жан", language: .russian),
                                                   supplementaryWords: ["Жанна", "Jan", "Жанна"])
        expect(ruName.map(\.displayText) == ["Жанна"], "Russian supplementary names")
        let accent = context("E\u{301}")
        let accented = KeyboardSuggestions.candidates(for: accent, supplementaryWords: ["Éclair"])
        expect(accented.first?.displayText == "E\u{301}clair", "Canonical-equivalent accented prefix matches")
        expect(accented.first?.replacementCount == 1, "Combining accent is one grapheme to remove")
        expect(accented.first?.edit(ifCurrent: accent) == KeyboardEdit(deleteBackwardCount: 1, text: "E\u{301}clair "),
               "Unicode acceptance preserves typed prefix representation")
        let yo = KeyboardSuggestions.candidates(for: context("ё", language: .russian), supplementaryWords: ["ёлка", "ель"])
        expect(yo.map(\.displayText) == ["ёлка"], "Russian ё retains its spelling")
        let hyphen = KeyboardSuggestions.candidates(for: context("well-"), supplementaryWords: ["well-known"])
        expect(hyphen.first?.displayText == "well-known", "Internal hyphen can be completed")
        let apostrophe = KeyboardSuggestions.candidates(for: context("don'"))
        expect(apostrophe.first?.displayText == "don't", "English apostrophe completion")
        let same = KeyboardSuggestions.candidates(for: context("hel"))
        expect(same == KeyboardSuggestions.candidates(for: context("hel")), "No history changes deterministic suggestions")
    }
    private static func spellingCorrections() {
        let original = context("Please fix teh")
        let guesses = KeyboardSuggestions.corrections(for: original, guesses: ["the", "ten"])
        expect(KeyboardSuggestions.spellingWord(in: original) == "teh", "Only current full word is passed to spell checker")
        expect(guesses.first?.displayText == "the", "Correction uses guessed word, not misspelled prefix")
        expect(guesses.first?.isCorrection == true, "Correction candidates are distinguished from completions")
        expect(guesses.first?.edit(ifCurrent: original) == KeyboardEdit(deleteBackwardCount: 3, text: "the "),
               "Current-word correction replaces exact word and appends a space at document end")
        expect(KeyboardSuggestions.candidates(for: context("hel")).allSatisfy { !$0.isCorrection },
               "Completions remain unmarked")
        expect(KeyboardSuggestions.candidates(for: context("thank ")).allSatisfy { !$0.isCorrection },
               "Next-word predictions remain unmarked")
        for (typed, guess, expected) in [("Hlelo", "hello", "Hello"), ("HLELO", "hello", "HELLO"),
                                        ("hlelo", "Hello", "hello"), ("l", "I", "I"), ("im", "I'm", "I'm")] {
            expect(KeyboardSuggestions.corrections(for: context(typed), guesses: [guess]).first?.displayText == expected,
                   "Correction preserves intended case and lexical I: \(typed)")
        }
        let ru = context("Пирвет", language: .russian)
        expect(KeyboardSuggestions.corrections(for: ru, guesses: ["привет"]).first?.displayText == "Привет",
               "Russian title case is preserved")
        expect(KeyboardSuggestions.corrections(for: context("ПИРВЕТ", language: .russian), guesses: ["привет"]).first?.displayText == "ПРИВЕТ",
               "Russian all-caps correction")
        expect(KeyboardSuggestions.corrections(for: context("Елкка", language: .russian), guesses: ["ёлка"]).first?.displayText == "Ёлка",
               "Russian correction may restore ё")
        for separator in [" ", "  ", "!? ", "…»,  ", "\t", "\u{00A0}", ".", ": ", "\""] {
            let source = context("Earlier helllo" + separator)
            let correction = KeyboardSuggestions.corrections(for: source, guesses: ["hello"]).first
            expect(KeyboardSuggestions.spellingWord(in: source) == "helllo", "Previous word is found before bounded separators")
            expect(correction?.edit(ifCurrent: source) == KeyboardEdit(deleteBackwardCount: 6 + separator.count,
                                                                       text: "hello" + separator),
                   "Exact trailing spaces and punctuation are reinserted without an extra space")
        }
        let quoted = context("'helllo'")
        expect(KeyboardSuggestions.corrections(for: quoted, guesses: ["hello"]).first?.edit(ifCurrent: quoted)
               == KeyboardEdit(deleteBackwardCount: 7, text: "hello'"), "Opening quote is preserved outside replacement")
        for after in [", friend", " friend", ".", ": next", "🙂"] {
            let source = context("teh", after: after)
            expect(KeyboardSuggestions.corrections(for: source, guesses: ["the"]).first?.insertionText == "the",
                   "Existing cursor-after punctuation or whitespace is respected")
        }
        let accent = context("cafe\u{301}t ")
        expect(KeyboardSuggestions.corrections(for: accent, guesses: ["café"]).first?.edit(ifCurrent: accent)
               == KeyboardEdit(deleteBackwardCount: 6, text: "café "), "Correction deletion counts Unicode graphemes")
        let emoji = context("🙂teh")
        expect(KeyboardSuggestions.corrections(for: emoji, guesses: ["the"]).first?.replacementCount == 3,
               "Correction never removes preceding emoji")
        expect(KeyboardSuggestions.corrections(for: context("dont"), guesses: ["don't", "don’t"]).count == 1,
               "Equivalent apostrophe guesses are deduplicated")
        expect(KeyboardSuggestions.corrections(for: context("well-konwn"), guesses: ["well-known"]).first?.displayText == "well-known",
               "Valid hyphenated words can be corrected")
        let filtered = KeyboardSuggestions.corrections(for: context("helllo"),
            guesses: ["helllo", "HELLLO", "", "two words", "hello", "Hello", "привет", "hello🙂", String(repeating: "a", count: 49), "help"])
        expect(filtered.map(\.displayText) == ["hello", "help"], "Same word, duplicates and invalid guesses are filtered")
        expect(KeyboardSuggestions.corrections(for: original, guesses: ["the"], limit: 0).isEmpty,
               "Caller can disable corrections")
        expect(KeyboardSuggestions.corrections(for: original, guesses: ["the", "ten", "tea", "tech", "ted", "tie", "two", "toe", "test"], limit: 100).count == 8,
               "Correction output is bounded")
    }

    private static func spellingSafety() {
        let invalid: [String?] = [nil, "", " ", "...", "helllo\n", "helllo\n  ", "helllo \n,",
            "helllo" + String(repeating: " ", count: 9), String(repeating: "a", count: 49),
            "helllo2", "3helllo", "heлlo", "中文", "hello--", "-helllo", "helllo-",
            "test@example.com", "test@example.com ", "bad@helllo", "#helllo", "#helllo? ",
            "https://example.com", "https://example.com?q=helllo ", "mailto:helllo", "www.helllo",
            "path/helllo", "file_helllo", "user+helllo"]
        for before in invalid {
            let source = context(before)
            expect(KeyboardSuggestions.spellingWord(in: source) == nil,
                   "Unsafe or unknown spelling target is rejected: \(String(describing: before))")
            expect(KeyboardSuggestions.corrections(for: source, guesses: ["hello"]).isEmpty,
                   "Unsafe target cannot authorize deletion")
        }
        for after in ["lo", "2", "'s", "-next", ".com", "@example.com", "://example", "/path", "_name", ":8080"] {
            expect(KeyboardSuggestions.spellingWord(in: context("helllo", after: after)) == nil,
                   "Midword or URL continuation after cursor is rejected")
        }
        expect(KeyboardSuggestions.spellingWord(in: context("Earlier\nteh")) == "teh",
               "Current word after a newline is allowed without crossing the line")
        expect(KeyboardSuggestions.spellingWord(in: context("Good: helllo")) == "helllo",
               "Whitespace separates a normal word from earlier punctuation")
        expect(KeyboardSuggestions.spellingWord(in: context("helllo", selection: "selected")) == nil,
               "Spelling never touches selected text")
        expect(KeyboardSuggestions.spellingWord(in: context("helllo", selection: " ")) == nil,
               "Whitespace selection is still protected")
        let source = context("teh, ")
        let correction = KeyboardSuggestions.corrections(for: source, guesses: ["the"])[0]
        let changedContexts = [context("teh "), context("teh,  "), context("other, "),
                               context("teh, ", after: " "), context("teh, ", selection: "x"),
                               context("teh, ", language: .russian), context("teh, ", document: UUID()), context(nil)]
        for changed in changedContexts {
            expect(correction.edit(ifCurrent: changed) == nil,
                   "Correction snapshot rejects stale word, separator, field, language or selection")
        }
        expect(correction.edit(ifCurrent: source) == KeyboardEdit(deleteBackwardCount: 5, text: "the, "),
               "Fresh snapshot permits only exact captured suffix replacement")
    }

    private static func spellingRanking() {
        func ranked(_ word: String, _ guesses: [String] = [], _ language: KeyboardLanguage = .english) -> [String] {
            KeyboardSuggestions.rankedSpellingGuesses(for: word, language: language, systemGuesses: guesses)
        }
        let ru = ranked("Превет", ["Пресет", "Ревет", "Преет"], .russian)
        expect(ru.first == "привет", "Common Russian привет leads over less useful system guesses")
        expect(Array(ru.suffix(3)) == ["Пресет", "Ревет", "Преет"], "System fallback order and spelling are preserved")
        expect(KeyboardSuggestions.corrections(for: context("Превет", language: .russian), guesses: ru).first?.displayText == "Привет",
               "Ranking integrates with original-word capitalization")
        expect(ranked("teh").first == "the", "Adjacent transposition finds the common English word")
        let helo = ranked("helo", ["Hello", "help", "halo"])
        expect(Array(helo.prefix(2)) == ["help", "hello"], "Nearby same-length word leads, followed by common insertion")
        expect(helo.filter { $0.lowercased() == "hello" }.count == 1 && helo.filter { $0.lowercased() == "help" }.count == 1,
               "Local and system candidates are deduplicated")
        for typo in ["ello", "hell", "hhello", "helloo", "hlelo", "hellp"] {
            expect(ranked(typo).contains("hello"), "Single insertion, deletion, substitution or adjacent swap is accepted: \(typo)")
        }
        for typo in ["oellh", "heoll", "hxllp", "hxo", "zzzz"] {
            expect(!ranked(typo).contains("hello"), "Multiple edits and distant words do not invent hello: \(typo)")
        }
        expect(ranked("héllo").contains("hello"), "Unicode character substitution is one edit")
        expect(ranked("he\u{301}llo") == ranked("héllo"), "Canonical-equivalent graphemes rank consistently")
        expect(ranked("еще", [], .russian).contains("ещё"), "One Russian ё substitution is allowed")
        let duplicateRU = ranked("спасбо", ["СПАСИБО", "Спасибо", "спасибо"], .russian)
        expect(duplicateRU.filter { $0.lowercased() == "спасибо" }.count == 1, "Duplicate vocabulary and system entries collapse")
        expect(ranked("he", ["he", "hey", "hey", "hello"]) == ["hey", "hello"],
               "Short words retain only deduplicated system fallback without invented common alternatives")
        expect(ranked("zzzz", ["unrelated"]) == ["unrelated"], "A system suggestion remains available as fallback")
        for invalid in ["", "he2", "heлlo", "hello world", String(repeating: "a", count: 49)] {
            expect(ranked(invalid, ["hello"]).isEmpty, "Invalid or excessively long input is rejected")
        }
        expect(ranked(String(repeating: "x", count: 48), ["hello"]) == ["hello"], "Maximum supported input length preserves system fallback")
        expect(ranked("zzzz", ["zzzz", "ZZZZ", "", "two words", "привет", "hello🙂", String(repeating: "a", count: 49), "hello", "HELLO"])
               == ["hello"], "Malformed, same-word, wrong-language and duplicate system guesses are filtered")
        let many = (0..<300).map { "q" + String(UnicodeScalar(97 + $0 / 26)!) + String(UnicodeScalar(97 + $0 % 26)!) }
        expect(ranked("zzzz", many).count == 64, "Ranked output has a fixed bound")
        expect(ranked("zzzz", Array(repeating: "", count: 256) + ["hello"]).isEmpty,
               "Only a bounded number of system candidates are examined")
    }

}
