import Foundation

/// Run without an iOS runtime:
/// swiftc -parse-as-library KeyboardExtension/KeyboardModel.swift Tests/KeyboardModelTests.swift -o /tmp/keyboard-model-tests
@main
private struct KeyboardModelTests {
    private static var checks = 0

    static func main() {
        capitalization()
        shiftTransitions()
        doubleSpace()
        acceleratedDeletion()
        layouts()
        print("PASS: \(checks) keyboard model checks")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    private static func sync(_ engine: inout KeyboardTypingEngine, _ text: String?,
                             selection: String? = nil,
                             mode: KeyboardCapitalizationMode = .sentences) {
        engine.synchronize(contextBefore: text, selectedText: selection, capitalization: mode)
    }

    private static func applied(_ edit: KeyboardEdit, to source: String) -> String {
        var text = source
        for _ in 0..<edit.deleteBackwardCount where !text.isEmpty { text.removeLast() }
        return text + edit.text
    }

    private static func capitalization() {
        var engine = KeyboardTypingEngine()
        sync(&engine, "")
        expect(engine.shiftState == .upper, "Empty document starts with automatic uppercase")
        let initial = engine.insertText("п", contextBefore: "", selectedText: nil, at: 1)
        expect(initial.text == "П", "Russian first letter is uppercase")
        sync(&engine, "П")
        expect(engine.shiftState == .lower, "Only initial letter is capitalized")
        expect(engine.insertText("р", contextBefore: "П", selectedText: nil, at: 2).text == "р", "Next Russian letter stays lowercase")
        sync(&engine, "Hello. ")
        expect(engine.cased("w") == "W", "English sentence boundary")
        sync(&engine, "Привет! ")
        expect(engine.cased("м") == "М", "Russian sentence boundary")
        sync(&engine, "He said «Hello!» ")
        expect(engine.shiftState == .upper, "Punctuation followed by closing quote")
        sync(&engine, "Hello. “")
        expect(engine.shiftState == .upper, "Sentence opening quote")
        sync(&engine, "a\n")
        expect(engine.shiftState == .upper, "Line break starts a sentence")
        sync(&engine, "a ")
        expect(engine.shiftState == .lower, "Ordinary interword space is lowercase")
        sync(&engine, "12.")
        expect(engine.shiftState == .lower, "Do not uppercase immediately after decimal point")
        sync(&engine, nil)
        expect(engine.shiftState == .upper, "Nil proxy context starts with sentence capitalization")
        expect(engine.insertText("h", contextBefore: nil, selectedText: nil, at: 3).text == "H",
               "First letter is uppercase when empty host reports nil")
        sync(&engine, "H")
        expect(engine.shiftState == .lower, "Populated context consumes nil-start capitalization")
        sync(&engine, nil, mode: .words)
        expect(engine.shiftState == .upper, "Nil proxy context starts with word capitalization")
        sync(&engine, nil, mode: .none)
        expect(engine.shiftState == .lower, "Nil proxy context still respects no-autocapitalization")
        sync(&engine, nil, mode: .allCharacters)
        expect(engine.shiftState == .upper, "Nil proxy context respects allCharacters mode")
        sync(&engine, "", mode: .none)
        expect(engine.shiftState == .lower, "Respect no-autocapitalization fields")
        sync(&engine, "hello ", mode: .words)
        expect(engine.shiftState == .upper, "Respect words mode")
        sync(&engine, "hello w", mode: .words)
        expect(engine.shiftState == .lower, "Words mode consumes capitalization")
        sync(&engine, "abc", mode: .allCharacters)
        expect(engine.shiftState == .upper, "Respect allCharacters mode")
    }

    private static func shiftTransitions() {
        var engine = KeyboardTypingEngine()
        sync(&engine, "")
        engine.tapShift(at: 1)
        expect(engine.shiftState == .lower, "First tap turns automatic uppercase off")
        sync(&engine, "")
        expect(engine.shiftState == .lower, "Unchanged proxy callbacks preserve manual override")
        engine.tapShift(at: 1.2)
        expect(engine.shiftState == .locked, "Consecutive second tap locks after automatic uppercase")
        let letter = engine.insertText("a", contextBefore: "", selectedText: nil, at: 1.3)
        expect(letter.text == "A", "Caps Lock uppercases letters")
        sync(&engine, "A")
        expect(engine.shiftState == .locked, "Caps Lock survives context updates")
        engine.tapShift(at: 1.5)
        expect(engine.shiftState == .lower, "Single tap unlocks Caps Lock")

        engine = KeyboardTypingEngine()
        sync(&engine, "word", mode: .none)
        engine.tapShift(at: 4)
        expect(engine.shiftState == .upper, "Manual one-shot uppercase")
        _ = engine.insertText("x", contextBefore: "word", selectedText: nil, at: 4.05)
        sync(&engine, "wordX", mode: .none)
        engine.tapShift(at: 4.15)
        expect(engine.shiftState == .upper, "Shift-letter-Shift is not a double Shift")
        engine.interruptSequence()
        engine.tapShift(at: 4.2)
        expect(engine.shiftState == .lower, "Other controls break Shift double-tap timing")
        engine.tapShift(at: 5)
        sync(&engine, "different context", mode: .none)
        expect(engine.shiftState == .lower, "Cursor context change clears one-shot manual override")
    }

    private static func doubleSpace() {
        var engine = KeyboardTypingEngine()
        var text = "hello"
        sync(&engine, text)
        let first = engine.space(contextBefore: text, selectedText: nil, at: 1)
        text = applied(first, to: text)
        sync(&engine, text)
        // Host may deliver more than one selection/text callback for one insertion.
        sync(&engine, text, selection: "")
        let second = engine.space(contextBefore: text, selectedText: nil, at: 1.3)
        expect(second == KeyboardEdit(deleteBackwardCount: 1, text: ". "), "Rapid double space produces period-space")
        text = applied(second, to: text)
        expect(text == "hello. ", "Double space edits only the preceding space")
        sync(&engine, text)
        expect(engine.shiftState == .upper, "Double space primes next sentence uppercase")
        expect(engine.space(contextBefore: text, selectedText: nil, at: 1.4).text == " ", "Third space does not create another period")

        for context in ["", " ", "word ", "word. ", "word.", "word!", "\n", "😀", "“word?”"] {
            engine = KeyboardTypingEngine()
            sync(&engine, context)
            let once = applied(engine.space(contextBefore: context, selectedText: nil, at: 2), to: context)
            sync(&engine, once)
            expect(engine.space(contextBefore: once, selectedText: nil, at: 2.2).deleteBackwardCount == 0,
                   "Ineligible double space must not add punctuation: \(context)")
        }
        for context in ["123", "«слово»", "(word)"] {
            engine = KeyboardTypingEngine()
            sync(&engine, context)
            let once = applied(engine.space(contextBefore: context, selectedText: nil, at: 3), to: context)
            sync(&engine, once)
            expect(engine.space(contextBefore: once, selectedText: nil, at: 3.2).deleteBackwardCount == 1,
                   "Eligible word/digit/closing delimiter: \(context)")
        }
        engine = KeyboardTypingEngine()
        _ = engine.space(contextBefore: nil, selectedText: nil, at: 4)
        expect(engine.space(contextBefore: nil, selectedText: nil, at: 4.1).deleteBackwardCount == 0, "Unknown context disables double-space replacement")
        engine = KeyboardTypingEngine()
        _ = engine.space(contextBefore: "word", selectedText: nil, at: 5)
        expect(engine.space(contextBefore: "word ", selectedText: nil, at: 6).deleteBackwardCount == 0, "Slow spaces remain spaces")
        engine = KeyboardTypingEngine()
        _ = engine.space(contextBefore: "word", selectedText: nil, at: 7)
        sync(&engine, "other ")
        expect(engine.space(contextBefore: "other ", selectedText: nil, at: 7.1).deleteBackwardCount == 0, "Cursor movement cancels pending replacement")
        engine = KeyboardTypingEngine()
        _ = engine.space(contextBefore: "word", selectedText: "selection", at: 8)
        expect(engine.space(contextBefore: "word ", selectedText: nil, at: 8.1).deleteBackwardCount == 0, "Replacing selection cannot prime double space")
        engine = KeyboardTypingEngine()
        _ = engine.space(contextBefore: "word", selectedText: nil, at: 9)
        sync(&engine, "word ", selection: "selected")
        expect(engine.space(contextBefore: "word ", selectedText: nil, at: 9.1).deleteBackwardCount == 0, "Selection change cancels double space")
        engine = KeyboardTypingEngine()
        _ = engine.space(contextBefore: "word", selectedText: nil, at: 10)
        engine.interruptSequence()
        expect(engine.space(contextBefore: "word ", selectedText: nil, at: 10.1).deleteBackwardCount == 0, "Layout/document controls break double-space timing")
    }

    private static func acceleratedDeletion() {
        let samples: [(String?, Int)] = [
            (nil, 1), ("", 1), ("hello", 5), ("hello world", 5),
            ("hello world  ", 7), ("hello, world!", 6), ("don't", 5),
            ("Привет мир", 3), ("cafe\u{301}", 4), ("a 👨‍👩‍👧‍👦", 1),
            ("a\n", 1), ("a\n  ", 2), ("a...", 4), ("   ", 3)
        ]
        for (context, expected) in samples {
            expect(KeyboardTypingEngine.wordDeletionCount(contextBefore: context) == expected,
                   "Unicode-safe word deletion: \(String(describing: context))")
        }
        expect(KeyboardTypingEngine.wordDeletionCount(contextBefore: String(repeating: "x", count: 500)) == 128,
               "Deletion work is bounded for long/truncated tokens")
    }

    private static func layouts() {
        for language in KeyboardLanguage.allCases {
            for symbols in [false, true] {
                let rows = KeyboardLayout.rows(language: language, symbols: symbols)
                let keys = rows.flatMap { $0.left + $0.right }
                expect(rows.count == 4, "Four rows in each layout")
                expect(Set(keys.map(\.id)).count == keys.count, "Stable unique key IDs")
                expect(keys.allSatisfy { $0.weight > 0 }, "Positive key weights")
                expect(keys.filter { $0.secondary != nil }.allSatisfy { $0.holdAlternates.first == $0.secondary },
                       "Every printed corner symbol is the default long-press choice")
                expect(keys.allSatisfy { Set($0.alternates).isSubset(of: Set($0.holdAlternates)) },
                       "Holding retains all accents, currencies and punctuation variants")
                expect(keys.filter { $0.secondary == nil }.allSatisfy { $0.holdAlternates == $0.alternates },
                       "Keys without a corner symbol keep their existing hold behavior")
                for action in [KeyboardAction.delete, .enter, .tab, .globe, .emoji, .toggleSplit, .dismiss] {
                    expect(keys.contains { $0.action == action }, "Required action \(action) in all modes")
                }
                expect(keys.filter { $0.action == .space }.count == 2, "Space on each half")
                if !symbols {
                    let lowerLetters = rows.dropFirst().flatMap { $0.left + $0.right }.filter {
                        if case .text(let value) = $0.action { return value.allSatisfy(\.isLetter) }
                        return false
                    }
                    expect(lowerLetters.allSatisfy { $0.secondary == nil && $0.holdAlternates.isEmpty },
                           "Lower-row letters have no corner symbols or hold variants")
                    expect(rows[0].left.allSatisfy { $0.secondary != nil }, "Top-row number shortcuts remain available")
                }
                if symbols {
                    expect(keys.contains { $0.action == .text("!") }, "Direct exclamation key on symbol page")
                    expect(keys.contains { $0.action == .text("?") }, "Direct question key on symbol page")
                    expect(keys.first { $0.action == .text("[") }?.alternates.contains("{") == true,
                           "Opening brace remains available by holding bracket")
                    expect(keys.first { $0.action == .text("]") }?.alternates.contains("}") == true,
                           "Closing brace remains available by holding bracket")
                }
            }
        }
        let ru = KeyboardLayout.rows(language: .russian, symbols: false)
        let en = KeyboardLayout.rows(language: .english, symbols: false)
        let ruKeys = ru.flatMap { $0.left + $0.right }
        let enKeys = en.flatMap { $0.left + $0.right }
        let ruCharacters = Set(ruKeys.flatMap { [$0.title] + $0.alternates }.joined())
        let enCharacters = Set(enKeys.flatMap { [$0.title] + $0.alternates }.joined())
        expect(Set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя").isSubset(of: ruCharacters), "Complete Russian alphabet including hold-е ё")
        expect(Set("abcdefghijklmnopqrstuvwxyz").isSubset(of: enCharacters), "Complete English alphabet")
        expect(ru[0].left.map(\.title).joined() == "йцукен", "Reference left top row")
        expect(ru[0].right.prefix(6).map(\.title).joined() == "гшщзхъ", "Reference right top row")
        expect(ru[0].left.compactMap(\.secondary) == ["1", "2", "3", "4", "5", "6"], "Corner legends retain the complete number row")
        expect(ru[2].left.dropFirst().map(\.title).joined() == "ячсми", "Reference left bottom letter row")
        expect(ru[1].left.first?.action == .tab, "Tab on home row's left")
        expect(enKeys.first { $0.title == "e" }?.alternates.contains("ë") == true, "English accents")
        expect(enKeys.first { $0.title == "q" }?.holdAlternates == ["1"], "Holding Q offers 1 without requiring accents")
        expect(enKeys.first { $0.title == "e" }?.holdAlternates.first == "3", "Holding E defaults to 3 while keeping accents")
        expect(ruKeys.first { $0.title == "ф" }?.holdAlternates.isEmpty == true, "Lower-row Russian letters have no hold symbols")
        expect(ruKeys.first { $0.title == "е" }?.holdAlternates == ["5", "ё"], "Holding Russian E offers its digit and yo only")
        let duplicate = KeyboardKey(id: "test", secondary: "!", alternates: ["", "!", "¡", "¡"], action: .text("!"))
        expect(duplicate.holdAlternates == ["!", "¡"], "Hold choices contain no empty or duplicate values")
        expect(KeyboardLayout.alternatives(for: "₽").contains("€"), "Currency alternatives")
        expect(KeyboardLayout.alternatives(for: "-").contains("—"), "Dash alternatives")
        expect(KeyboardLayout.alternatives(for: "\"").contains("«"), "Quote alternatives")
    }
}
