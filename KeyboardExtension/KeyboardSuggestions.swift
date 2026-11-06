import Foundation

/// A suggestion is bound to one field, language and cursor context. The controller
/// must capture a fresh context when the user taps it, not reuse this snapshot.
struct KeyboardSuggestionContext: Equatable {
    let before: String?
    let after: String?
    let selectedText: String?
    let language: KeyboardLanguage
    let documentIdentifier: UUID
}

struct KeyboardSuggestion: Equatable {
    let displayText: String
    let insertionText: String
    let replacementCount: Int
    let isCorrection: Bool
    private let source: KeyboardSuggestionContext
    private let replacedSuffix: String

    fileprivate init(word: String, replacing suffix: String, source: KeyboardSuggestionContext,
                     isCorrection: Bool = false, trailingSeparator: String = "") {
        displayText = word
        // Corrections preserve the exact captured separators. Otherwise respect
        // whitespace or punctuation already following the cursor.
        insertionText = word + (trailingSeparator.isEmpty
            ? ((source.after?.isEmpty ?? true) ? " " : "") : trailingSeparator)
        replacementCount = suffix.count
        self.isCorrection = isCorrection
        self.source = source
        replacedSuffix = suffix
    }

    func edit(ifCurrent current: KeyboardSuggestionContext) -> KeyboardEdit? {
        guard current == source, current.selectedText?.isEmpty ?? true,
              replacedSuffix.isEmpty || current.before?.hasSuffix(replacedSuffix) == true,
              !KeyboardSuggestions.isInsideWord(after: current.after) else { return nil }
        return KeyboardEdit(deleteBackwardCount: replacementCount, text: insertionText)
    }
}

/// Small, deterministic on-device vocabulary. No network, persistence, learning,
/// or access to typed history; optional system lexicon words only aid completion.
struct KeyboardSuggestions {
    static func candidates(for context: KeyboardSuggestionContext,
                           supplementaryWords: [String] = [], limit: Int = 3) -> [KeyboardSuggestion] {
        let count = max(0, min(limit, 8))
        guard count > 0, let prefix = validatedPrefix(in: context) else { return [] }
        // UIKit also returns nil for an empty field. In this case predictions
        // only insert; they never infer or remove unseen text.
        let before = context.before ?? ""
        let words: [String]
        if !prefix.isEmpty {
            let vocabulary = context.language == .english ? englishWords : russianWords
            let normalized = prefix.lowercased()
            words = (vocabulary + supplementaryWords.prefix(2048)).filter { word in
                isValidWord(word, language: context.language) && word.count <= 48 &&
                    word.lowercased().hasPrefix(normalized)
            }.map { preserveCase(of: prefix, completing: $0) }
        } else {
            let startsSentence = KeyboardTypingEngine.shouldCapitalize(contextBefore: before, mode: .sentences)
            let previous = String(before.trimmingCharacters(in: .whitespacesAndNewlines)
                .reversed().prefix(while: isTokenCharacter).reversed()).lowercased()
            if context.language == .english {
                words = startsSentence ? ["I", "Hello", "Thanks"]
                    : (englishNext[previous] ?? ["and", "the", "to"])
            } else {
                words = startsSentence ? ["Я", "Привет", "Спасибо"]
                    : (russianNext[previous] ?? ["и", "в", "на"])
            }
        }

        var seen = Set<String>()
        return words.filter { seen.insert($0.lowercased()).inserted }.prefix(count).map {
            KeyboardSuggestion(word: $0, replacing: prefix, source: context)
        }
    }

    /// The controller may pass this token to a local system dictionary and
    /// return its completions through supplementaryWords. No whole document is needed.
    static func completionPrefix(in context: KeyboardSuggestionContext) -> String? {
        guard let prefix = validatedPrefix(in: context), !prefix.isEmpty else { return nil }
        return prefix
    }

    /// Returns one complete captured word for a local spell checker. The caller
    /// must verify its entire range is misspelled before offering guessed fixes.
    static func spellingWord(in context: KeyboardSuggestionContext) -> String? {
        spellingTarget(in: context)?.word
    }

    /// Use only after the local spell checker flags the entire captured word.
    /// Common one-edit words lead; unchanged system guesses remain a fallback.
    static func rankedSpellingGuesses(for word: String, language: KeyboardLanguage,
                                      systemGuesses: [String]) -> [String] {
        guard !word.isEmpty, word.count <= 48, isValidWord(word, language: language) else { return [] }
        let original = spellingKey(word)
        let characters = Array(original)
        var nearby: [(word: String, lengthDifference: Int, order: Int)] = []
        if word.count >= 3 {
            let vocabulary = language == .english ? englishWords : russianWords
            for (order, candidate) in vocabulary.enumerated() {
                let candidateCharacters = Array(spellingKey(candidate))
                guard isOneEditApart(characters, candidateCharacters) else { continue }
                nearby.append((candidate, abs(characters.count - candidateCharacters.count), order))
            }
            nearby.sort { lhs, rhs in
                lhs.lengthDifference == rhs.lengthDifference ? lhs.order < rhs.order
                    : lhs.lengthDifference < rhs.lengthDifference
            }
        }
        var seen = Set<String>()
        var results: [String] = []
        for guess in nearby.map(\.word) + systemGuesses.prefix(256) {
            guard guess.count <= 48, isValidWord(guess, language: language) else { continue }
            let key = spellingKey(guess)
            guard key != original, seen.insert(key).inserted else { continue }
            results.append(guess)
            if results.count == 64 { break }
        }
        return results
    }

    private static func isOneEditApart(_ first: [Character], _ second: [Character]) -> Bool {
        guard abs(first.count - second.count) <= 1 else { return false }
        if first.count == second.count {
            var differences: [Int] = []
            for index in first.indices where first[index] != second[index] {
                differences.append(index)
                if differences.count > 2 { return false }
            }
            if differences.count == 1 { return true }
            guard differences.count == 2, differences[1] == differences[0] + 1 else { return false }
            return first[differences[0]] == second[differences[1]] &&
                first[differences[1]] == second[differences[0]]
        }
        let shorter = first.count < second.count ? first : second
        let longer = first.count < second.count ? second : first
        var index = 0
        var skipped = false
        for character in longer {
            if index < shorter.count && shorter[index] == character {
                index += 1
            } else {
                if skipped { return false }
                skipped = true
            }
        }
        return index == shorter.count
    }

    static func corrections(for context: KeyboardSuggestionContext, guesses: [String],
                            limit: Int = 3) -> [KeyboardSuggestion] {
        let count = max(0, min(limit, 8))
        guard count > 0, let target = spellingTarget(in: context) else { return [] }
        let original = spellingKey(target.word)
        var seen = Set<String>()
        var results: [KeyboardSuggestion] = []
        for guess in guesses.prefix(256) {
            guard guess.count <= 48, isValidWord(guess, language: context.language),
                  spellingKey(guess) != original else { continue }
            let word = correctionCase(of: target.word, guess: guess, language: context.language)
            guard seen.insert(spellingKey(word)).inserted else { continue }
            results.append(KeyboardSuggestion(word: word, replacing: target.word + target.separator,
                                              source: context, isCorrection: true,
                                              trailingSeparator: target.separator))
            if results.count == count { break }
        }
        return results
    }

    private struct SpellingTarget {
        let word: String
        let separator: String
    }

    private static func spellingTarget(in context: KeyboardSuggestionContext) -> SpellingTarget? {
        guard context.selectedText?.isEmpty ?? true, !isInsideWord(after: context.after),
              let before = context.before, !before.isEmpty else { return nil }
        var wordEnd = before.endIndex
        var separatorCount = 0
        while wordEnd > before.startIndex {
            let previous = before.index(before: wordEnd)
            let character = before[previous]
            guard isSpellingSeparator(character) else { break }
            separatorCount += 1
            guard separatorCount <= 8 else { return nil }
            wordEnd = previous
        }
        var wordStart = wordEnd
        var wordCount = 0
        while wordStart > before.startIndex {
            let previous = before.index(before: wordStart)
            guard isTokenCharacter(before[previous]) else { break }
            wordCount += 1
            guard wordCount <= 48 else { return nil }
            wordStart = previous
        }
        // An opening straight quote is a delimiter, unlike an internal apostrophe.
        while wordStart < wordEnd && (before[wordStart] == "'" || before[wordStart] == "’") {
            wordStart = before.index(after: wordStart)
        }
        let word = String(before[wordStart..<wordEnd])
        guard isValidWord(word, language: context.language) else { return nil }
        if wordStart > before.startIndex,
           unsafeTokenBoundaries.contains(before[before.index(before: wordStart)]) { return nil }
        // Protect a partially typed URL/email even when its punctuation and
        // remaining domain are after the cursor, e.g. "exampel|.com".
        if let after = context.after, let first = after.first {
            if unsafeTokenBoundaries.subtracting([".", ":"]).contains(first) { return nil }
            if (first == "." || first == ":"), let second = after.dropFirst().first,
               second.isLetter || second.isNumber || second == "/" { return nil }
        }
        return SpellingTarget(word: word, separator: String(before[wordEnd...]))
    }

    private static let unsafeTokenBoundaries: Set<Character> = ["@", "#", ".", ":", "/", "\\", "_", "%", "+", "&", "=", "~", "$"]

    private static func isSpellingSeparator(_ character: Character) -> Bool {
        if character.isNewline { return false }
        if character.isWhitespace { return true }
        return ".,;:!?…)]}»”’\"'".contains(character)
    }

    private static func spellingKey(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    private static func correctionCase(of original: String, guess: String, language: KeyboardLanguage) -> String {
        let letters = original.filter(\.isLetter)
        if letters.count > 1 && letters == letters.uppercased() { return guess.uppercased() }
        let lowercase = guess.lowercased()
        if language == .english && (lowercase == "i" || lowercase.hasPrefix("i'") || lowercase.hasPrefix("i’")) {
            return "I" + lowercase.dropFirst()
        }
        if let first = letters.first, first.isUppercase,
           letters.dropFirst().allSatisfy({ $0.isLowercase }) {
            return String(guess.prefix(1)).uppercased() + guess.dropFirst().lowercased()
        }
        return letters == letters.lowercased() ? lowercase : guess
    }

    private static func validatedPrefix(in context: KeyboardSuggestionContext) -> String? {
        guard context.selectedText?.isEmpty ?? true, !isInsideWord(after: context.after) else { return nil }
        let before = context.before ?? ""
        let prefix = String(before.reversed().prefix(while: isTokenCharacter).reversed())
        if prefix.isEmpty {
            // Do not join a prediction directly onto punctuation or another token.
            return before.isEmpty || before.last?.isWhitespace == true ? "" : nil
        }
        guard prefix.count <= 48,
              isValidWord(prefix, language: context.language, allowTrailingConnector: true) else { return nil }
        return prefix
    }

    fileprivate static func isInsideWord(after: String?) -> Bool {
        after?.first.map(isTokenCharacter) ?? false
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’" || character == "-"
    }

    private static func isValidWord(_ word: String, language: KeyboardLanguage,
                                    allowTrailingConnector: Bool = false) -> Bool {
        guard let first = word.first, first.isLetter,
              allowTrailingConnector || word.last?.isLetter == true else { return false }
        var previousWasConnector = false
        for character in word {
            if character == "'" || character == "’" || character == "-" {
                guard !previousWasConnector else { return false }
                previousWasConnector = true
                continue
            }
            guard character.isLetter else { return false }
            previousWasConnector = false
            // Check base letters; combining accents remain part of their grapheme.
            for scalar in String(character).decomposedStringWithCanonicalMapping.unicodeScalars {
                if CharacterSet.nonBaseCharacters.contains(scalar) { continue }
                let value = scalar.value
                switch language {
                case .english:
                    guard (0x0041...0x005A).contains(value) || (0x0061...0x007A).contains(value) ||
                            (0x00C0...0x024F).contains(value) || (0x1E00...0x1EFF).contains(value) else { return false }
                case .russian:
                    guard (0x0400...0x052F).contains(value) else { return false }
                }
            }
        }
        return true
    }

    private static func preserveCase(of prefix: String, completing word: String) -> String {
        let letters = prefix.filter(\.isLetter)
        let tail = String(word.dropFirst(prefix.count))
        // A single initial capital means title case; two or more capitals mean
        // the user has started an uppercase word. Keep mixed typed case verbatim.
        if letters.count > 1 && letters == letters.uppercased() {
            return prefix + tail.uppercased()
        }
        return prefix + tail
    }

    private static let englishWords = """
    the to and you I it is in that we for have this with a of on not are be can will
    hello help here hey thanks thank please yes no okay sorry good great morning
    night day today tomorrow yesterday now later soon again already just still
    how what when where why who which there then these those they them their our
    your my me us he she his her am was were been being do does did done would
    could should may might must want need like love know think feel hope make take
    give get go going come coming see look find tell say said ask call send write
    read work home time way people friend friends family happy better best really
    very much more most some any all each other another new first last next same
    right left back only also too well about after before because but or if so as
    at from into out over up down off never always maybe sure welcome everyone
    everything something nothing anything anything else let's don't can't won't
    I'm I'll I've you're we're it's that's goodnight goodbye meeting message
    phone email address number problem question answer weekend lunch dinner
    water coffee tea tomorrow tonight together minutes hours busy ready done
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    private static let russianWords = """
    привет просто правильно проблема спасибо сегодня сейчас скоро снова сразу
    скажи сказать сообщение сообщения смогу пожалуйста пока потом потому поэтому
    да нет не на но ну нужно надо нормально хорошо хочу хотел хотите хочется
    как когда куда кто какой какие где что чтобы это этот эта эти ещё уже очень
    я ты вы мы он она они мне меня мой моя мои мой тебе тебя твой твоя ваш вас
    наш нас нам вам его её их и или а в во с со у к ко о об от до для за из по
    будет буду будем будешь будете будут был была были быть есть если можно могу
    можешь можете можем могли давай давайте делать сделаю сделал сделать работа
    работает работать домой дома дом день доброе добрый утро вечер ночь доброй
    завтра вчера время минут минута минуту час часа часов позже раньше сразу
    встреча встречи встретиться увидимся увидел знаю думаю понимаю понял хорошо
    хорошо спасибо большое тебе всем тоже только тогда там тут здесь ещё раз
    конечно точно возможно наверное вместе опять всегда никогда иногда всё все
    всё-таки лучший лучше новый новые нравится люблю люблю тебя друг друзья
    семья жизнь дела дело вопрос вопросы ответ помощь помоги помочь позвоню
    напиши написать отправь отправить получил получить удобно свободен занят
    готов готово отлично прекрасно понятно согласен ладно ага ура извини
    извините простите приветствую здравствуйте свидания счастья здоровья удачи
    выходные обед ужин кофе чай вода деньги номер телефон адрес письмо увидеть
    читать книга кино музыка фото фотография машина дорога поезд билет интернет
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    private static let englishNext: [String: [String]] = [
        "hello": ["there", "everyone", "again"], "hi": ["there", "everyone", "again"],
        "thank": ["you", "everyone"], "thanks": ["for", "again", "everyone"],
        "how": ["are", "is", "do"], "are": ["you", "we", "they"],
        "i": ["am", "will", "have"], "i'm": ["not", "going", "here"],
        "you": ["are", "can", "have"], "we": ["can", "will", "are"],
        "see": ["you", "the", "it"], "good": ["morning", "night", "luck"],
        "can": ["you", "we", "I"], "would": ["you", "like", "be"],
        "let": ["me", "us"], "let's": ["go", "meet", "try"],
        "want": ["to", "some", "a"], "need": ["to", "a", "some"],
        "going": ["to", "home", "out"], "on": ["the", "my", "a"],
        "in": ["the", "a", "my"], "at": ["the", "home", "work"],
        "happy": ["birthday", "to", "with"], "talk": ["to", "about", "soon"]
    ]

    private static let russianNext: [String: [String]] = [
        "привет": ["как", "всем", "ещё"], "как": ["дела", "ты", "вы"],
        "доброе": ["утро"], "добрый": ["день", "вечер"], "доброй": ["ночи"],
        "спасибо": ["за", "большое", "вам"], "большое": ["спасибо"],
        "я": ["не", "буду", "могу"], "мы": ["можем", "будем", "уже"],
        "ты": ["можешь", "будешь", "где"], "вы": ["можете", "будете", "уже"],
        "до": ["встречи", "завтра", "свидания"], "что": ["ты", "это", "будет"],
        "давай": ["встретимся", "завтра", "попробуем"], "давайте": ["завтра", "начнём", "обсудим"],
        "хочу": ["сказать", "тебя", "спросить"], "можешь": ["помочь", "сказать", "позвонить"],
        "можно": ["ли", "будет", "сейчас"], "увидимся": ["завтра", "скоро", "вечером"],
        "у": ["меня", "тебя", "нас"], "с": ["тобой", "вами", "днём"],
        "всё": ["хорошо", "готово", "понятно"], "не": ["знаю", "могу", "буду"],
        "сейчас": ["буду", "не", "могу"], "очень": ["хорошо", "рад", "нравится"]
    ]
}
