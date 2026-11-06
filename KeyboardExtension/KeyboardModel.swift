import Foundation

enum KeyboardLanguage: String, CaseIterable {
    case english, russian
    var spaceLabel: String { self == .english ? "eng" : "ру" }
}

enum KeyboardAction: Equatable {
    case text(String)
    case shift, delete, space, enter, symbols, tab, globe, emoji, toggleSplit, dismiss, settings
}

struct KeyboardKey: Equatable {
    let id: String
    let title: String
    let secondary: String?
    let alternates: [String]
    let action: KeyboardAction
    let weight: Double
    let symbol: String?

    /// A hold defaults to the printed corner symbol; accents remain selectable.
    var holdAlternates: [String] {
        ([secondary].compactMap { $0 } + alternates).reduce(into: []) { values, value in
            if !value.isEmpty && !values.contains(value) { values.append(value) }
        }
    }

    init(id: String, title: String = "", secondary: String? = nil, alternates: [String] = [],
         action: KeyboardAction, weight: Double = 1, symbol: String? = nil) {
        self.id = id
        self.title = title
        self.secondary = secondary
        self.alternates = alternates
        self.action = action
        self.weight = weight
        self.symbol = symbol
    }
}

struct KeyboardRow {
    let left: [KeyboardKey]
    let right: [KeyboardKey]
}

/// Layout values are lowercased; the controller applies the typing engine's case.
/// Accent lists generally retain the original character. Russian е offers ё
/// alongside its secondary digit, without extra accented variants.
struct KeyboardLayout {
    static func rows(language: KeyboardLanguage, symbols: Bool) -> [KeyboardRow] {
        func chars(_ text: String, _ secondary: [String] = [], letterAlternates: Bool = true) -> [KeyboardKey] {
            text.enumerated().map { index, character in
                let value = String(character)
                let offersAlternates = letterAlternates || !character.isLetter
                return KeyboardKey(id: "text.\(value)", title: value,
                                   secondary: offersAlternates && index < secondary.count ? secondary[index] : nil,
                                   alternates: offersAlternates ? alternatives(for: value) : [],
                                   action: .text(value))
            }
        }
        func special(_ id: String, _ action: KeyboardAction, _ title: String = "",
                     _ symbol: String? = nil, _ weight: Double = 1.25) -> KeyboardKey {
            KeyboardKey(id: id, title: title, action: action, weight: weight, symbol: symbol)
        }
        let tab = special("tab", .tab, "Tab", nil, 0.9)
        let delete = special("delete", .delete, "", "delete.left", 1.4)
        let enter = special("enter", .enter, language == .russian ? "ввод" : "return", nil, 2.2)
        let shiftLeft = special("shift.left", .shift, "", "shift", 1.25)
        let shiftRight = special("shift.right", .shift, "", "shift", 1.25)
        let lettersTitle = language == .russian ? "АБВ" : "ABC"
        var rows: [KeyboardRow]
        if symbols {
            rows = [
                KeyboardRow(left: chars("123456"), right: chars("7890-+") + [delete]),
                KeyboardRow(left: [tab] + chars("@#₽$%&"), right: chars("*()=/") + [enter]),
                KeyboardRow(left: [special("symbols.more.left", .symbols, lettersTitle)] + chars("!?[]\\"),
                            right: chars(";:'\",.") + [special("symbols.more.right", .symbols, lettersTitle)])
            ]
        } else if language == .russian {
            rows = [
                KeyboardRow(left: chars("йцукен", ["1", "2", "3", "4", "5", "6"]),
                            right: chars("гшщзхъ", ["7", "8", "9", "0", "-", "+"]) + [delete]),
                KeyboardRow(left: [tab] + chars("фывапр", letterAlternates: false),
                            right: chars("олджэ", letterAlternates: false) + [enter]),
                KeyboardRow(left: [shiftLeft] + chars("ячсми", letterAlternates: false),
                            right: chars("тьбю", letterAlternates: false) + chars(",.", ["!", "?"]) + [shiftRight])
            ]
        } else {
            rows = [
                KeyboardRow(left: chars("qwert", ["1", "2", "3", "4", "5"]),
                            right: chars("yuiop", ["6", "7", "8", "9", "0"]) + [delete]),
                KeyboardRow(left: [tab] + chars("asdfg", letterAlternates: false),
                            right: chars("hjkl", letterAlternates: false) + [enter]),
                KeyboardRow(left: [shiftLeft] + chars("zxcv", letterAlternates: false),
                            right: chars("bnm", letterAlternates: false) + chars(",.", ["!", "?"]) + [shiftRight])
            ]
        }
        rows.append(KeyboardRow(
            left: [special("symbols.left", .symbols, symbols ? lettersTitle : ".?123", nil, 1.45),
                   special("globe", .globe, "", "globe", 1.25),
                   special("emoji", .emoji, "", "face.smiling", 1.25),
                   special("space.left", .space, "", nil, 3.0)],
            right: [special("space.right", .space, "", nil, 2.9),
                    special("split", .toggleSplit, "", "rectangle.split.2x1", 1.4),
                    special("symbols.right", .symbols, symbols ? lettersTitle : ".?123", nil, 1.35),
                    special("dismiss", .dismiss, "", "keyboard.chevron.compact.down", 1.4)]))
        return rows
    }

    static func alternatives(for text: String) -> [String] {
        switch text {
        case "a": return ["a", "à", "á", "â", "ä", "æ", "ã", "å", "ā"]
        case "c": return ["c", "ç", "ć", "č"]
        case "e": return ["e", "é", "è", "ê", "ë", "ē", "ė", "ę"]
        case "i": return ["i", "ì", "í", "î", "ï", "ī", "į"]
        case "l": return ["l", "ł"]
        case "n": return ["n", "ñ", "ń"]
        case "o": return ["o", "ò", "ó", "ô", "ö", "õ", "ø", "œ", "ō"]
        case "s": return ["s", "ß", "ś", "š"]
        case "u": return ["u", "ù", "ú", "û", "ü", "ū"]
        case "y": return ["y", "ÿ", "ý"]
        case "z": return ["z", "ž", "ź", "ż"]
        case "е": return ["ё"]
        case "ь": return ["ь", "ъ"]
        case "'": return ["'", "’", "‘", "‹", "›", "`"]
        case "\"": return ["\"", "«", "»", "“", "”", "„"]
        case "₽", "$", "€", "£", "¥":
            return [text] + ["₽", "$", "€", "£", "¥", "₩", "¢"].filter { $0 != text }
        case "-": return ["-", "–", "—", "−", "_"]
        case ".": return [".", "…", "·"]
        case ",": return [",", "‚", "„"]
        case "/": return ["/", "\\", "÷"]
        case "%": return ["%", "‰"]
        case "&": return ["&", "§"]
        case "+": return ["+", "±"]
        case "=": return ["=", "≠", "≈", "≤", "≥"]
        case "[": return ["[", "{"]
        case "]": return ["]", "}"]
        case "!": return ["!", "¡"]
        case "?": return ["?", "¿"]
        default: return []
        }
    }
}

enum KeyboardCapitalizationMode { case none, words, sentences, allCharacters }
enum KeyboardShiftState { case lower, upper, locked }

struct KeyboardEdit: Equatable {
    let deleteBackwardCount: Int
    let text: String
    init(deleteBackwardCount: Int = 0, text: String) {
        self.deleteBackwardCount = deleteBackwardCount
        self.text = text
    }
}

/// Pure editing state. The controller remains responsible for applying edits
/// through UITextDocumentProxy and passing the resulting context back in.
struct KeyboardTypingEngine {
    private(set) var shiftState: KeyboardShiftState = .lower
    private var lastShiftTap: TimeInterval?
    private var pendingSpace: (time: TimeInterval, expectedContext: String)?
    private var hasSynchronized = false
    private var lastContext: String?
    private var lastSelection: String?
    private var manualOverride = false
    private var manualContext: String?

    func cased(_ text: String) -> String {
        shiftState == .lower ? text : text.uppercased()
    }

    mutating func synchronize(contextBefore: String?, selectedText: String?,
                              capitalization: KeyboardCapitalizationMode) {
        let selection = Self.nonempty(selectedText)
        let moved = hasSynchronized && (contextBefore != lastContext || selection != lastSelection)
        if moved { lastShiftTap = nil }
        if selection != nil || contextBefore != pendingSpace?.expectedContext {
            pendingSpace = nil
        }
        if manualOverride && (contextBefore != manualContext || selection != nil) {
            manualOverride = false
        }
        hasSynchronized = true
        lastContext = contextBefore
        lastSelection = selection
        guard shiftState != .locked, !manualOverride else { return }
        shiftState = Self.shouldCapitalize(contextBefore: contextBefore, mode: capitalization) ? .upper : .lower
    }

    mutating func tapShift(at time: TimeInterval) {
        pendingSpace = nil
        if shiftState != .locked, let previous = lastShiftTap,
           time >= previous, time - previous <= 0.35 {
            shiftState = .locked
            lastShiftTap = nil
        } else {
            shiftState = shiftState == .lower ? .upper : .lower
            lastShiftTap = time
        }
        manualOverride = true
        manualContext = lastContext
    }

    /// Call for cursor/selection/document changes and nontyping controls, such as
    /// language, layout, settings and deletion, so separate actions never count
    /// as a double-tap or double-space sequence.
    mutating func interruptSequence() {
        lastShiftTap = nil
        pendingSpace = nil
    }

    mutating func insertText(_ text: String, contextBefore: String?, selectedText: String?,
                             at time: TimeInterval, applyShift: Bool = true) -> KeyboardEdit {
        interruptSequence()
        let output = applyShift ? cased(text) : text
        if shiftState == .upper && text.contains(where: { $0.isLetter }) {
            shiftState = .lower
            manualOverride = false
        }
        return KeyboardEdit(text: output)
    }

    mutating func space(contextBefore: String?, selectedText: String?, at time: TimeInterval) -> KeyboardEdit {
        lastShiftTap = nil
        defer { manualOverride = false }
        if Self.nonempty(selectedText) == nil,
           let contextBefore, let previous = pendingSpace,
           contextBefore == previous.expectedContext,
           time >= previous.time, time - previous.time <= 0.7,
           contextBefore.last == " " {
            pendingSpace = nil
            return KeyboardEdit(deleteBackwardCount: 1, text: ". ")
        }
        pendingSpace = nil
        if Self.nonempty(selectedText) == nil, let contextBefore,
           Self.canCompleteSentence(after: contextBefore) {
            pendingSpace = (time, contextBefore + " ")
        }
        return KeyboardEdit(text: " ")
    }

    static func shouldCapitalize(contextBefore: String?, mode: KeyboardCapitalizationMode) -> Bool {
        guard mode != .none else { return false }
        if mode == .allCharacters { return true }
        // Some hosts, including an empty SwiftUI TextEditor, report nil at
        // the start of a document. Honor their capitalization trait there.
        guard let contextBefore else { return true }
        if contextBefore.isEmpty { return true }
        if mode == .words {
            return contextBefore.last?.isWhitespace == true
        }
        // Opening quote/bracket characters do not suppress a sentence's initial
        // capital. A line break starts a new sentence even without punctuation.
        let opening: Set<Character> = ["\"", "'", "“", "‘", "«", "„", "(", "[", "{"]
        let closing: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]", "}"]
        var chars = Array(contextBefore)
        while let last = chars.last, opening.contains(last) { chars.removeLast() }
        var hadWhitespace = false
        while let last = chars.last, last.isWhitespace {
            hadWhitespace = true
            if last.isNewline { return true }
            chars.removeLast()
        }
        if chars.isEmpty { return true }
        guard hadWhitespace else { return false }
        while let last = chars.last, closing.contains(last) { chars.removeLast() }
        guard let last = chars.last else { return true }
        return ".!?…".contains(last)
    }

    /// Number of user-perceived characters to remove for one accelerated repeat.
    /// Stops at a line boundary and caps work for truncated/very long contexts.
    static func wordDeletionCount(contextBefore: String?) -> Int {
        guard let contextBefore, !contextBefore.isEmpty else { return 1 }
        let chars = Array(contextBefore.suffix(128))
        var index = chars.count
        while index > 0 && chars[index - 1].isWhitespace && !chars[index - 1].isNewline {
            index -= 1
        }
        let whitespaceCount = chars.count - index
        guard index > 0 else { return max(1, whitespaceCount) }
        if chars[index - 1].isNewline { return max(1, whitespaceCount) }
        let tokenEnd = index
        // Remove punctuation attached to a word, but preserve other graphemes
        // (for example an emoji family) as a single deletion step.
        while index > 0 && chars[index - 1].isPunctuation { index -= 1 }
        let punctuationStart = index
        while index > 0 {
            let char = chars[index - 1]
            if char.isLetter || char.isNumber {
                index -= 1
            } else if (char == "'" || char == "’"), index > 1,
                      chars[index - 2].isLetter || chars[index - 2].isNumber {
                index -= 1
            } else {
                break
            }
        }
        if index == punctuationStart && index == tokenEnd {
            index -= 1
        }
        return max(1, chars.count - index)
    }

    private static func canCompleteSentence(after context: String) -> Bool {
        guard let last = context.last else { return false }
        if last.isLetter || last.isNumber { return true }
        let closers: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]", "}"]
        guard closers.contains(last) else { return false }
        var chars = Array(context)
        while let tail = chars.last, closers.contains(tail) { chars.removeLast() }
        return chars.last.map { $0.isLetter || $0.isNumber } ?? false
    }

    private static func nonempty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
