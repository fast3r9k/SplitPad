import UIKit

private final class KeyboardRootView: UIInputView, UIInputViewAudioFeedback {
    var clicksEnabled = true
    var enableInputClicksWhenVisible: Bool { clicksEnabled }
}

private final class SuggestionButton: UIButton {
    var activateSuggestion: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        activateSuggestion?()
        return true
    }
}

final class KeyboardViewController: UIInputViewController {
    private struct KeyInstance {
        let definition: KeyboardKey
        let view: KeycapView
    }
    private struct RowViews {
        let left: [KeyInstance]
        let right: [KeyInstance]
    }

    private let defaults = UserDefaults.standard
    private let canvas = UIView()
    private let settingsPanel = UIView()
    private var rows: [RowViews] = []
    private var canvasHeight: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint?
    private var engine = KeyboardTypingEngine()
    private var searchEngine = KeyboardTypingEngine()
    private var isSearchingEmoji: Bool { showingEmojis && emojiPanel.isSearching }
    private var activeEngine: KeyboardTypingEngine {
        get { isSearchingEmoji ? searchEngine : engine }
        set {
            if isSearchingEmoji { searchEngine = newValue }
            else { engine = newValue }
        }
    }
    private var language: KeyboardLanguage = .russian
    private var symbols = false
    private var isSplit = true
    private var halfWidthRatio: CGFloat = 0.37
    private var keyHeight: CGFloat = 50
    private var soundEnabled = true
    private var showingSettings = false
    private var showingEmojis = false
    private let suggestionBar = UIView()
    private let emojiPanel = EmojiPanelView()
    private var suggestionButtons: [UIButton] = []
    private var suggestions: [KeyboardSuggestion] = []
    private var pressedSuggestions: [Int: KeyboardSuggestion] = [:]
    private var supplementaryWords: [String] = []
    private let textChecker = UITextChecker()
    private var completionCacheKey: String?
    private var completionCache: [String] = []
    private var spellingCacheKey: String?
    private var spellingCache: [String] = []
    private let checkerLanguages = UITextChecker.availableLanguages
    private let suggestionHeight: CGFloat = 44
    private var lastSize = CGSize.zero
    private var documentID: UUID?
    private var applyingEdit = false
    private var deleteTimer: Timer?
    private var deletionStarted: TimeInterval = 0
    private var lastRepeatedDeletion: TimeInterval = 0
    private let widthSlider = UISlider()
    private let heightSlider = UISlider()
    private let widthLabel = UILabel()
    private let heightLabel = UILabel()
    private let soundSwitch = UISwitch()
    private let outerInset: CGFloat = 7
    private let rowGap: CGFloat = 7
    private var keysHeaderHeight: CGFloat { isSearchingEmoji ? 100 : suggestionHeight }
    private var keysHeight: CGFloat { keysHeaderHeight + rowGap + keyHeight * 4 + rowGap * 3 }
    private var contentHeight: CGFloat { showingSettings ? max(keysHeight, 252) : keysHeight }
    private var allKeys: [KeyInstance] { rows.flatMap { $0.left + $0.right } }

    override func loadView() {
        inputView = KeyboardRootView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        language = (defaults.object(forKey: "russian") as? Bool ?? true) ? .russian : .english
        if defaults.object(forKey: "halfWidthRatio") != nil {
            halfWidthRatio = min(0.49, max(0.30, CGFloat(defaults.double(forKey: "halfWidthRatio"))))
        }
        if defaults.object(forKey: "keyHeight") != nil {
            keyHeight = min(70, max(38, CGFloat(defaults.double(forKey: "keyHeight"))))
        }
        isSplit = defaults.object(forKey: "isSplit") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        // Migrate the manual theme used in 0.2 back to the system appearance.
        defaults.removeObject(forKey: "theme")
        primaryLanguage = language == .russian ? "ru-RU" : "en-US"
        applyTheme()
        (inputView as? KeyboardRootView)?.clicksEnabled = soundEnabled
        // UIInputView's keyboard style supplies the system tint and blur.
        view.backgroundColor = .clear
        view.addSubview(canvas)
        // A real directly constrained child is required for iPadOS to honor root height.
        // Keep the root autoresizing mask: the system supplies keyboard width.
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvasHeight = canvas.heightAnchor.constraint(equalToConstant: contentHeight)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.topAnchor, constant: outerInset),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: outerInset),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -outerInset),
            canvasHeight
        ])
        canvas.addSubview(settingsPanel)
        canvas.addSubview(suggestionBar)
        canvas.addSubview(emojiPanel)
        configureSuggestionBar()
        configureSettings()
        emojiPanel.onInsert = { [weak self] value in
            self?.playClick()
            self?.insertIntoDocument(value, applyShift: false)
        }
        emojiPanel.onBack = { [weak self] in
            self?.emojiPanel.endSearch()
            self?.showingEmojis = false
            self?.updateVisibility()
        }
        emojiPanel.onSearchStateChanged = { [weak self] searching in
            guard let self else { return }
            self.cancelInteractions()
            self.engine.interruptSequence()
            self.searchEngine = KeyboardTypingEngine()
            self.searchEngine.synchronize(contextBefore: self.emojiPanel.searchQuery,
                                          selectedText: nil, capitalization: .none)
            if searching { self.symbols = false; self.rebuildKeys() }
            else { self.updateVisibility() }
        }
        emojiPanel.onDelete = { [weak self] in
            self?.playClick()
            self?.deleteOnce(word: false)
        }
        requestSupplementaryLexicon { [weak self] lexicon in
            self?.supplementaryWords = lexicon.entries.map(\.documentText)
            self?.refreshSuggestions()
        }
        rebuildKeys()
        updateHeight()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        synchronize()
        refreshKeys()
        updateHeight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelInteractions()
        engine.interruptSequence()
        emojiPanel.endSearch()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        guard isViewLoaded, !applyingEdit else { return }
        synchronize()
        refreshKeys()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        guard isViewLoaded, !applyingEdit else { return }
        synchronize()
        refreshKeys()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lastSize != view.bounds.size {
            cancelInteractions()
            lastSize = view.bounds.size
        }
        let width = max(0, canvas.bounds.width)
        let gap: CGFloat = width < 500 ? 4 : 7
        let halfWidth = width < 600 ? max(0, (width - gap) / 2) : min((width - gap) / 2, max(240, width * halfWidthRatio))
        for (index, row) in rows.enumerated() {
            let y = keysHeaderHeight + rowGap + CGFloat(index) * (keyHeight + rowGap)
            if isSplit {
                layout(row.left, in: CGRect(x: 0, y: y, width: halfWidth, height: keyHeight), gap: gap)
                layout(row.right, in: CGRect(x: width - halfWidth, y: y, width: halfWidth, height: keyHeight), gap: gap)
            } else {
                layout(row.left + row.right, in: CGRect(x: 0, y: y, width: width, height: keyHeight), gap: gap)
            }
        }
        suggestionBar.frame = CGRect(x: 0, y: 0, width: width, height: suggestionHeight)
        let suggestionWidth = max(0, width / 3)
        for (index, button) in suggestionButtons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * suggestionWidth, y: 0,
                                  width: max(0, suggestionWidth - 4), height: suggestionHeight)
        }
        emojiPanel.frame = CGRect(x: 0, y: 0, width: width, height: isSearchingEmoji ? 100 : canvas.bounds.height)
        settingsPanel.frame = canvas.bounds
        layoutSettings()
        updateHeight()
    }

    private func layout(_ keys: [KeyInstance], in rect: CGRect, gap: CGFloat) {
        let weight = keys.reduce(0) { $0 + $1.definition.weight }
        guard weight > 0 else { return }
        let usable = max(0, rect.width - gap * CGFloat(max(0, keys.count - 1)))
        var x = rect.minX
        for key in keys {
            let width = usable * CGFloat(key.definition.weight / weight)
            key.view.frame = CGRect(x: x, y: rect.minY, width: width, height: rect.height)
            x += width + gap
        }
    }

    private func updateHeight() {
        guard isViewLoaded, canvasHeight != nil else { return }
        if canvasHeight.constant != contentHeight { canvasHeight.constant = contentHeight }
        let desired = outerInset * 2 + contentHeight + view.safeAreaInsets.bottom
        if let heightConstraint {
            if abs(heightConstraint.constant - desired) > 0.5 { heightConstraint.constant = desired }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: desired)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        if abs(preferredContentSize.height - desired) > 0.5 {
            preferredContentSize = CGSize(width: 0, height: desired)
        }
    }

    private func synchronize() {
        applyTheme()
        // The proxy is not attached during viewDidLoad; its UUID can still be nil.
        guard view.window != nil else { return }
        // UIKit can return nil while attaching/detaching despite the nonoptional
        // Swift declaration. Use the public ObjC getter to avoid a UUID bridge trap.
        guard let current = textDocumentProxy.perform(#selector(getter: UITextDocumentProxy.documentIdentifier))?
            .takeUnretainedValue() as? UUID else {
            cancelInteractions()
            return
        }
        if documentID != current {
            cancelInteractions()
            emojiPanel.endSearch()
            engine = KeyboardTypingEngine()
            documentID = current
        }
        let mode: KeyboardCapitalizationMode
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: mode = .none
        case .words: mode = .words
        case .allCharacters: mode = .allCharacters
        default: mode = .sentences
        }
        engine.synchronize(contextBefore: textDocumentProxy.documentContextBeforeInput,
                           selectedText: textDocumentProxy.selectedText, capitalization: mode)
    }

    private func rebuildKeys() {
        cancelInteractions()
        allKeys.forEach { $0.view.removeFromSuperview() }
        rows.removeAll()
        var definitions = KeyboardLayout.rows(language: language, symbols: symbols)
        if !isSplit, let bottom = definitions.last {
            let source = bottom.left + bottom.right
            var seen = Set<String>()
            let merged = source.filter { key in
                let token: String
                switch key.action {
                case .space: token = "space"
                case .symbols: token = "symbols"
                default: token = key.id
                }
                return seen.insert(token).inserted
            }
            definitions[definitions.count - 1] = KeyboardRow(left: merged, right: [])
        }
        for row in definitions {
            rows.append(RowViews(left: row.left.map(makeKey), right: row.right.map(makeKey)))
        }
        canvas.bringSubviewToFront(suggestionBar)
        canvas.bringSubviewToFront(emojiPanel)
        canvas.bringSubviewToFront(settingsPanel)
        updateVisibility()
        view.setNeedsLayout()
    }

    private func makeKey(_ definition: KeyboardKey) -> KeyInstance {
        let key = KeycapView(configuration: configuration(for: definition))
        key.popupHost = view
        key.accessibilityIdentifier = "key." + definition.id
        key.onPressBegan = { [weak self] in
            guard let self else { return }
            self.emojiPanel.cancelInteractions()
            self.playClick()
            if case .delete = definition.action { self.beginDeleting() }
        }
        key.onPressEnded = { [weak self] in
            if case .delete = definition.action { self?.stopDeleting() }
        }
        key.onCommit = { [weak self] alternate in
            guard let self else { return }
            if let alternate { self.insert(alternate, applyShift: false) }
            else { self.perform(definition.action) }
        }
        key.onLongPress = { [weak self] in
            guard let self else { return }
            self.activeEngine.interruptSequence()
            switch definition.action {
            case .globe: self.advanceToNextInputMode()
            case .toggleSplit: self.showSettings()
            default: break
            }
        }
        canvas.addSubview(key)
        return KeyInstance(definition: definition, view: key)
    }

    private func configuration(for key: KeyboardKey) -> KeycapView.Configuration {
        var title = key.title
        var symbol = key.symbol
        var trailing: String?
        var isSpecial = true
        var commitsOnRelease = true
        var usesLongPressAction = false
        switch key.action {
        case .text:
            title = activeEngine.cased(title)
            isSpecial = false
        case .shift:
            title = ""
            switch activeEngine.shiftState {
            case .lower: symbol = "shift"
            case .upper: symbol = "shift.fill"
            case .locked: symbol = "capslock.fill"
            }
        case .space:
            title = ""
            trailing = language.spaceLabel
            isSpecial = false
        case .enter: title = returnTitle; symbol = nil
        case .delete: commitsOnRelease = false
        case .globe: usesLongPressAction = true
        case .toggleSplit:
            title = ""
            symbol = isSplit ? "rectangle" : "rectangle.split.2x1"
            usesLongPressAction = true
        default: break
        }
        return KeycapView.Configuration(title: title, secondary: key.secondary.map { activeEngine.cased($0) },
                                       alternates: key.holdAlternates.map { activeEngine.cased($0) },
                                       symbol: symbol, trailingText: trailing, isSpecial: isSpecial,
                                       commitsOnRelease: commitsOnRelease, usesLongPressAction: usesLongPressAction)
    }

    private func refreshKeys() {
        refreshSuggestions()
        for key in allKeys {
            key.view.configure(configuration(for: key.definition))
            switch key.definition.action {
            case .shift:
                key.view.accessibilityLabel = activeEngine.shiftState == .locked ? "Caps Lock включён" : "Shift"
                key.view.accessibilityValue = activeEngine.shiftState == .lower ? "Строчные" : "Заглавные"
            case .space: key.view.accessibilityLabel = "Пробел, " + language.spaceLabel
            case .toggleSplit:
                key.view.accessibilityLabel = isSplit ? "Соединить клавиатуру" : "Разделить клавиатуру"
                key.view.accessibilityHint = "Удерживайте для настроек"
            case .globe:
                key.view.accessibilityLabel = "Сменить язык"
                key.view.accessibilityHint = "Удерживайте для следующей системной клавиатуры"
            case .delete: key.view.accessibilityLabel = "Удалить"
            case .enter: key.view.accessibilityLabel = returnTitle
            case .dismiss: key.view.accessibilityLabel = "Скрыть клавиатуру"
            case .tab: key.view.accessibilityLabel = "Табуляция"
            case .emoji: key.view.accessibilityLabel = "Эмодзи"
            case .symbols: key.view.accessibilityLabel = symbols ? "Буквы" : "Цифры и символы"
            default: break
            }
        }
    }

    private func perform(_ action: KeyboardAction) {
        switch action {
        case .text(let value): insert(value)
        case .space:
            if isSearchingEmoji {
                insert(" ", applyShift: false)
            } else {
                synchronize()
                apply(engine.space(contextBefore: textDocumentProxy.documentContextBeforeInput,
                                   selectedText: textDocumentProxy.selectedText, at: ProcessInfo.processInfo.systemUptime))
            }
            if symbols {
                symbols = false
                rebuildKeys()
            }
        case .shift:
            activeEngine.tapShift(at: ProcessInfo.processInfo.systemUptime)
            refreshKeys()
        case .delete: deleteOnce(word: false)
        case .enter:
            if isSearchingEmoji { emojiPanel.endSearch() }
            else { insert("\n", applyShift: false) }
        case .tab: insert(isSearchingEmoji ? " " : "\t", applyShift: false)
        case .emoji:
            cancelInteractions()
            activeEngine.interruptSequence()
            showingEmojis = true
            emojiPanel.prepareForPresentation()
            updateVisibility()
        case .globe:
            activeEngine.interruptSequence()
            language = language == .russian ? .english : .russian
            defaults.set(language == .russian, forKey: "russian")
            primaryLanguage = language == .russian ? "ru-RU" : "en-US"
            rebuildKeys()
        case .symbols:
            activeEngine.interruptSequence()
            symbols.toggle()
            rebuildKeys()
        case .toggleSplit:
            activeEngine.interruptSequence()
            isSplit.toggle()
            defaults.set(isSplit, forKey: "isSplit")
            rebuildKeys()
        case .dismiss:
            cancelInteractions()
            activeEngine.interruptSequence()
            emojiPanel.endSearch()
            dismissKeyboard()
        case .settings: showSettings()
        }
    }

    private func insert(_ text: String, applyShift: Bool = true) {
        if isSearchingEmoji {
            let edit = searchEngine.insertText(text, contextBefore: emojiPanel.searchQuery,
                                               selectedText: nil, at: ProcessInfo.processInfo.systemUptime,
                                               applyShift: applyShift)
            let query = String((emojiPanel.searchQuery + edit.text).prefix(100))
            emojiPanel.setSearchQuery(query)
            searchEngine.synchronize(contextBefore: query, selectedText: nil, capitalization: .none)
            refreshKeys()
            return
        }
        insertIntoDocument(text, applyShift: applyShift)
    }

    // Emoji selection always targets the host, even while letters edit a search query.
    private func insertIntoDocument(_ text: String, applyShift: Bool = true) {
        synchronize()
        apply(engine.insertText(text, contextBefore: textDocumentProxy.documentContextBeforeInput,
                                selectedText: textDocumentProxy.selectedText,
                                at: ProcessInfo.processInfo.systemUptime, applyShift: applyShift))
    }

    private func apply(_ edit: KeyboardEdit) {
        applyingEdit = true
        for _ in 0..<edit.deleteBackwardCount { textDocumentProxy.deleteBackward() }
        if !edit.text.isEmpty { textDocumentProxy.insertText(edit.text) }
        applyingEdit = false
        synchronize()
        refreshKeys()
    }

    private func beginDeleting() {
        stopDeleting()
        activeEngine.interruptSequence()
        deletionStarted = ProcessInfo.processInfo.systemUptime
        lastRepeatedDeletion = deletionStarted
        deleteOnce(word: false)
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.synchronize()
            guard self.deleteTimer != nil else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - self.deletionStarted
            guard elapsed >= 0.35 else { return }
            let word = elapsed >= 1.6
            guard now - self.lastRepeatedDeletion >= (word ? 0.24 : 0.075) else { return }
            self.lastRepeatedDeletion = now
            self.deleteOnce(word: word)
            self.playClick()
        }
        deleteTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func deleteOnce(word: Bool) {
        if isSearchingEmoji {
            searchEngine.interruptSequence()
            var query = emojiPanel.searchQuery
            let count = word ? KeyboardTypingEngine.wordDeletionCount(contextBefore: query) : 1
            query.removeLast(min(count, query.count))
            emojiPanel.setSearchQuery(query)
            searchEngine.synchronize(contextBefore: query, selectedText: nil, capitalization: .none)
            refreshKeys()
            return
        }
        engine.interruptSequence()
        let count = word && (textDocumentProxy.selectedText?.isEmpty ?? true)
            ? KeyboardTypingEngine.wordDeletionCount(contextBefore: textDocumentProxy.documentContextBeforeInput) : 1
        applyingEdit = true
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        applyingEdit = false
        synchronize()
        refreshKeys()
    }

    private func stopDeleting() { deleteTimer?.invalidate(); deleteTimer = nil }
    private func cancelInteractions() {
        stopDeleting()
        pressedSuggestions.removeAll()
        allKeys.forEach { $0.view.cancelInteraction() }
        emojiPanel.cancelInteractions()
    }
    private func playClick() { if soundEnabled { UIDevice.current.playInputClick() } }

    private var returnTitle: String {
        let ru = language == .russian
        if isSearchingEmoji { return ru ? "готово" : "done" }
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return ru ? "перейти" : "go"
        case .search: return ru ? "найти" : "search"
        case .send: return ru ? "отпр." : "send"
        case .next: return ru ? "далее" : "next"
        case .done: return ru ? "готово" : "done"
        case .join: return ru ? "войти" : "join"
        default: return ru ? "ввод" : "return"
        }
    }

    private func configureSuggestionBar() {
        for index in 0..<3 {
            let button = SuggestionButton(type: .system)
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.tintColor = .label
            button.layer.cornerRadius = 7
            button.accessibilityIdentifier = "suggestion.\(index)"
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.suggestions.indices.contains(index) else { return }
                self.pressedSuggestions[index] = self.suggestions[index]
            }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                guard let candidate = self.pressedSuggestions.removeValue(forKey: index) else { return }
                self.acceptSuggestion(candidate)
            }, for: .touchUpInside)
            button.activateSuggestion = { [weak self] in
                guard let self, self.suggestions.indices.contains(index) else { return }
                self.acceptSuggestion(self.suggestions[index])
            }
            button.addAction(UIAction { [weak self] _ in
                self?.pressedSuggestions.removeValue(forKey: index)
            }, for: [.touchCancel, .touchUpOutside])
            suggestionBar.addSubview(button)
            suggestionButtons.append(button)
        }
    }

    private func casedSuggestion(_ text: String, replacing count: Int) -> String {
        if engine.shiftState == .locked || textDocumentProxy.autocapitalizationType == .allCharacters {
            return text.uppercased()
        }
        // Completion preserves a prefix the user already typed. New words honor Shift.
        guard count == 0, let first = text.first else { return text }
        // English pronoun I keeps its lexical capitalization inside a sentence.
        if language == .english, text.trimmingCharacters(in: .whitespacesAndNewlines) == "I" { return text }
        let initial = engine.shiftState == .upper ? String(first).uppercased() : String(first).lowercased()
        return initial + text.dropFirst()
    }

    private func acceptSuggestion(_ candidate: KeyboardSuggestion) {
        guard let context = suggestionContext, let edit = candidate.edit(ifCurrent: context) else {
            refreshSuggestions()
            return
        }
        engine.interruptSequence()
        playClick()
        apply(KeyboardEdit(deleteBackwardCount: edit.deleteBackwardCount,
                           text: candidate.isCorrection ? edit.text : casedSuggestion(edit.text, replacing: edit.deleteBackwardCount)))
    }

    private var suggestionContext: KeyboardSuggestionContext? {
        guard view.window != nil,
              let current = textDocumentProxy.perform(#selector(getter: UITextDocumentProxy.documentIdentifier))?
                .takeUnretainedValue() as? UUID else { return nil }
        return KeyboardSuggestionContext(before: textDocumentProxy.documentContextBeforeInput,
                                         after: textDocumentProxy.documentContextAfterInput,
                                         selectedText: textDocumentProxy.selectedText,
                                         language: language, documentIdentifier: current)
    }

    private func refreshSuggestions() {
        let type = textDocumentProxy.keyboardType ?? .default
        let acceptsWords = ![UIKeyboardType.emailAddress, .URL, .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad].contains(type)
        let completionsEnabled = textDocumentProxy.autocorrectionType != .no
        let spellingTrait = textDocumentProxy.spellCheckingType ?? .default
        let spellingEnabled = spellingTrait == .yes || (spellingTrait == .default && completionsEnabled)
        if !showingSettings, !showingEmojis, !symbols, acceptsWords, let context = suggestionContext {
            var words = supplementaryWords
            if completionsEnabled, let prefix = KeyboardSuggestions.completionPrefix(in: context) {
                let checkerLanguage = language == .russian ? "ru_RU" : "en_US"
                let cacheKey = checkerLanguage + ":" + prefix
                if completionCacheKey != cacheKey {
                    completionCacheKey = cacheKey
                    completionCache = textChecker.completions(forPartialWordRange: NSRange(location: 0, length: (prefix as NSString).length),
                                                              in: prefix, language: checkerLanguage) ?? []
                }
                words = completionCache + supplementaryWords
            } else {
                completionCacheKey = nil
                completionCache = []
            }
            let corrections = spellingEnabled ? spellingSuggestions(for: context) : []
            let completions = completionsEnabled
                ? KeyboardSuggestions.candidates(for: context, supplementaryWords: words) : []
            var seen = Set<String>()
            suggestions = Array((corrections + completions).filter {
                seen.insert($0.displayText.lowercased()).inserted
            }.prefix(3))
        } else {
            suggestions = []
        }
        for (index, button) in suggestionButtons.enumerated() {
            let candidate = suggestions.indices.contains(index) ? suggestions[index] : nil
            let title = candidate.map {
                $0.isCorrection ? $0.displayText : casedSuggestion($0.displayText, replacing: $0.replacementCount)
            }
            button.setAttributedTitle(nil, for: .normal)
            button.setTitle(title, for: .normal)
            if candidate?.isCorrection == true, let title {
                let caption = language == .russian ? "Исправить" : "Correct"
                let attributed = NSMutableAttributedString(string: caption + "\n", attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: UIColor.secondaryLabel
                ])
                attributed.append(NSAttributedString(string: title, attributes: [
                    .font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.systemBlue
                ]))
                button.setAttributedTitle(attributed, for: .normal)
            }
            button.isEnabled = candidate != nil
            button.accessibilityLabel = title
            button.accessibilityHint = candidate?.isCorrection == true
                ? (language == .russian ? "Заменить ошибочное слово" : "Replace misspelled word")
                : (language == .russian ? "Вставить подсказку" : "Insert suggestion")
        }
    }

    private func spellingSuggestions(for context: KeyboardSuggestionContext) -> [KeyboardSuggestion] {
        let requestedLanguage = context.language == .russian ? "ru_RU" : "en_US"
        guard let checkerLanguage = checkerLanguages.first(where: {
            $0.replacingOccurrences(of: "-", with: "_") == requestedLanguage
        }), let word = KeyboardSuggestions.spellingWord(in: context),
           !supplementaryWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else {
            spellingCacheKey = nil
            spellingCache = []
            return []
        }
        let cacheKey = checkerLanguage + ":" + word
        if spellingCacheKey != cacheKey {
            spellingCacheKey = cacheKey
            spellingCache = []
            let range = NSRange(location: 0, length: (word as NSString).length)
            let misspelled = textChecker.rangeOfMisspelledWord(in: word, range: range,
                startingAt: 0, wrap: false, language: checkerLanguage)
            // Only replace whole words; guesses for one part of a compound are unsafe here.
            if misspelled == range {
                let guesses = textChecker.guesses(forWordRange: range, in: word, language: checkerLanguage) ?? []
                spellingCache = KeyboardSuggestions.rankedSpellingGuesses(for: word, language: context.language,
                                                                           systemGuesses: guesses)
            }
        }
        return KeyboardSuggestions.corrections(for: context, guesses: spellingCache)
    }

    private func configureSettings() {
        let title = UILabel()
        title.text = "Настройки клавиатуры"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.tag = 1
        settingsPanel.addSubview(title)
        let done = UIButton(type: .system)
        done.setTitle("Готово", for: .normal)
        done.tag = 2
        done.addAction(UIAction { [weak self] _ in
            self?.showingSettings = false
            self?.updateVisibility()
        }, for: .touchUpInside)
        settingsPanel.addSubview(done)
        widthSlider.minimumValue = 0.30
        widthSlider.maximumValue = 0.49
        widthSlider.value = Float(halfWidthRatio)
        widthSlider.accessibilityLabel = "Ширина половинок"
        widthSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.halfWidthRatio = CGFloat(self.widthSlider.value)
            self.defaults.set(Double(self.halfWidthRatio), forKey: "halfWidthRatio")
            self.updateSettingLabels()
            self.view.setNeedsLayout()
        }, for: .valueChanged)
        heightSlider.minimumValue = 38
        heightSlider.maximumValue = 70
        heightSlider.value = Float(keyHeight)
        heightSlider.accessibilityLabel = "Высота клавиш"
        heightSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.keyHeight = CGFloat(self.heightSlider.value.rounded())
            self.defaults.set(Double(self.keyHeight), forKey: "keyHeight")
            self.updateSettingLabels()
            self.updateHeight()
            self.view.setNeedsLayout()
        }, for: .valueChanged)
        soundSwitch.isOn = soundEnabled
        soundSwitch.accessibilityLabel = "Щелчки клавиш"
        soundSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.soundEnabled = self.soundSwitch.isOn
            self.defaults.set(self.soundEnabled, forKey: "soundEnabled")
            (self.inputView as? KeyboardRootView)?.clicksEnabled = self.soundEnabled
        }, for: .valueChanged)
        let soundLabel = UILabel()
        soundLabel.text = "Щелчки клавиш"
        soundLabel.font = .systemFont(ofSize: 15)
        soundLabel.tag = 3
        settingsPanel.addSubview(soundLabel)
        [widthLabel, heightLabel].forEach { $0.font = .systemFont(ofSize: 14); settingsPanel.addSubview($0) }
        [widthSlider, heightSlider, soundSwitch].forEach { settingsPanel.addSubview($0) }
        updateSettingLabels()
    }

    private func layoutSettings() {
        let width = min(540, max(0, settingsPanel.bounds.width - 20))
        let x = (settingsPanel.bounds.width - width) / 2
        settingsPanel.viewWithTag(1)?.frame = CGRect(x: x, y: 0, width: max(0, width - 80), height: 32)
        settingsPanel.viewWithTag(2)?.frame = CGRect(x: x + width - 76, y: 0, width: 76, height: 32)
        widthLabel.frame = CGRect(x: x, y: 36, width: width, height: 20)
        widthSlider.frame = CGRect(x: x, y: 58, width: width, height: 30)
        heightLabel.frame = CGRect(x: x, y: 92, width: width, height: 20)
        heightSlider.frame = CGRect(x: x, y: 114, width: width, height: 30)
        settingsPanel.viewWithTag(3)?.frame = CGRect(x: x, y: 164, width: max(0, width - 60), height: 32)
        soundSwitch.frame = CGRect(x: x + width - 52, y: 164, width: 52, height: 32)
    }
    private func updateSettingLabels() {
        widthLabel.text = "Ширина половинок: \(Int((halfWidthRatio * 100).rounded()))%"
        heightLabel.text = "Высота клавиш: \(Int(keyHeight))"
    }
    private func applyTheme() {
        let style: UIUserInterfaceStyle
        switch textDocumentProxy.keyboardAppearance ?? .default {
        case .dark: style = .dark
        case .light: style = .light
        default: style = .unspecified
        }
        if overrideUserInterfaceStyle != style { overrideUserInterfaceStyle = style }
    }
    private func showSettings() {
        cancelInteractions()
        engine.interruptSequence()
        emojiPanel.endSearch()
        showingEmojis = false
        showingSettings = true
        updateVisibility()
    }
    private func updateVisibility() {
        allKeys.forEach { $0.view.isHidden = showingSettings || (showingEmojis && !isSearchingEmoji) }
        suggestionBar.isHidden = showingSettings || showingEmojis
        emojiPanel.isHidden = showingSettings || !showingEmojis
        emojiPanel.configure(languageIsRussian: language == .russian)
        settingsPanel.isHidden = !showingSettings
        refreshKeys()
        updateHeight()
        view.setNeedsLayout()
    }
}
