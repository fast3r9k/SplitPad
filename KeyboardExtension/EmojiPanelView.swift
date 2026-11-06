import UIKit
import CoreText

/// A local picker: search stays inside the extension; only emoji are saved in recents.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onInsert: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSearchStateChanged: ((Bool) -> Void)?
    private(set) var isSearching = false
    private(set) var searchQuery = ""

    private struct DisplayedEmoji {
        let entry: EmojiEntry
        let glyph: String
    }

    private let catalog = EmojiCatalog.shared
    private let history = EmojiHistory()
    private let searchButton = UIButton(type: .system)
    private let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let searchLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let toolbar = UIView()
    private let backButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let categoryScroll = UIScrollView()
    private let categoryTitle = UILabel()
    private let emptyLabel = UILabel()
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private lazy var holdGesture = UILongPressGestureRecognizer(target: self, action: #selector(holdEmoji(_:)))
    private var categoryButtons: [UIButton] = []
    private var selectedCategory = 1 // zero is Recent
    private var languageIsRussian = true
    private var hasConfiguredLanguage = false
    private var displayed: [DisplayedEmoji] = []
    private var displayingRecents = false
    private var supportedEntries: [[EmojiEntry]] = []
    private var supportedBases = Set<String>()
    private var lastGridSize = CGSize.zero
    private var toneOverlay: EmojiToneOverlay?
    private var toneSourceIndex: Int?
    private var holdOrigin = CGPoint.zero
    private var draggedTone = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        supportedEntries = catalog.categories.map { category in
            category.entries.filter { EmojiGlyphSupport.supports($0.glyph) }
        }
        supportedBases = Set(supportedEntries.flatMap { $0.map(\.glyph) })
        addSubview(searchButton)
        addSubview(clearButton)
        addSubview(cancelButton)
        addSubview(categoryTitle)
        addSubview(collectionView)
        addSubview(emptyLabel)
        addSubview(toolbar)
        toolbar.addSubview(backButton)
        toolbar.addSubview(categoryScroll)
        toolbar.addSubview(deleteButton)

        searchButton.backgroundColor = .tertiarySystemFill
        searchButton.layer.cornerRadius = 10
        searchButton.accessibilityIdentifier = "emoji.search"
        searchButton.addAction(UIAction { [weak self] _ in self?.beginSearch() }, for: .touchUpInside)
        searchButton.addSubview(searchIcon)
        searchButton.addSubview(searchLabel)
        searchIcon.tintColor = .secondaryLabel
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.isUserInteractionEnabled = false
        searchLabel.font = .systemFont(ofSize: 16)
        searchLabel.lineBreakMode = .byTruncatingHead
        searchLabel.isUserInteractionEnabled = false
        searchLabel.isAccessibilityElement = false
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .secondaryLabel
        clearButton.accessibilityIdentifier = "emoji.search.clear"
        clearButton.addAction(UIAction { [weak self] _ in self?.setSearchQuery("") }, for: .touchUpInside)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15)
        cancelButton.accessibilityIdentifier = "emoji.search.cancel"
        cancelButton.addAction(UIAction { [weak self] _ in self?.endSearch() }, for: .touchUpInside)

        backButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        backButton.tintColor = .label
        backButton.accessibilityIdentifier = "emoji.back"
        backButton.addAction(UIAction { [weak self] _ in
            self?.cancelInteractions()
            self?.onBack?()
        }, for: .touchUpInside)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)), for: .normal)
        deleteButton.tintColor = .label
        deleteButton.accessibilityIdentifier = "emoji.delete"
        deleteButton.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        categoryScroll.showsHorizontalScrollIndicator = false
        categoryScroll.delaysContentTouches = false
        for index in 0...catalog.categories.count {
            let button = UIButton(type: .system)
            if index == 0 {
                button.setImage(UIImage(systemName: "clock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)), for: .normal)
            } else {
                button.setTitle(catalog.categories[index - 1].icon, for: .normal)
            }
            button.tintColor = .secondaryLabel
            button.titleLabel?.font = .systemFont(ofSize: 24)
            button.layer.cornerRadius = 9
            button.accessibilityIdentifier = index == 0 ? "emoji.category.recent" : "emoji.category.\(catalog.categories[index - 1].id)"
            button.addAction(UIAction { [weak self] _ in self?.selectCategory(index) }, for: .touchUpInside)
            categoryScroll.addSubview(button)
            categoryButtons.append(button)
        }
        categoryTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        categoryTitle.textColor = .secondaryLabel
        categoryTitle.accessibilityTraits = .header
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 2
        emptyLabel.isUserInteractionEnabled = false

        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumInteritemSpacing = 5
        flowLayout.minimumLineSpacing = 7
        flowLayout.sectionInset = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceHorizontal = true
        collectionView.showsHorizontalScrollIndicator = true
        collectionView.delaysContentTouches = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseIdentifier)
        collectionView.accessibilityIdentifier = "emoji.grid"
        holdGesture.minimumPressDuration = 0.35
        holdGesture.cancelsTouchesInView = true
        collectionView.addGestureRecognizer(holdGesture)
        configure(languageIsRussian: true)
        prepareForPresentation()
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(languageIsRussian: Bool) {
        guard !hasConfiguredLanguage || self.languageIsRussian != languageIsRussian else { return }
        hasConfiguredLanguage = true
        self.languageIsRussian = languageIsRussian
        backButton.setTitle(languageIsRussian ? "АБВ" : "ABC", for: .normal)
        backButton.accessibilityLabel = languageIsRussian ? "Вернуться к буквам" : "Return to letters"
        deleteButton.accessibilityLabel = languageIsRussian ? "Удалить" : "Delete"
        cancelButton.setTitle(languageIsRussian ? "Отмена" : "Cancel", for: .normal)
        clearButton.accessibilityLabel = languageIsRussian ? "Очистить поиск" : "Clear search"
        collectionView.accessibilityLabel = languageIsRussian ? "Эмодзи" : "Emoji"
        updateSearchAppearance()
        updateCategoryAppearance()
        updateEmptyState()
        refreshCollection(resetOffset: false)
    }

    /// Called before the panel opens; refresh recents without moving cells during a selection.
    func prepareForPresentation() {
        cancelInteractions()
        let wasSearching = isSearching
        isSearching = false
        searchQuery = ""
        selectedCategory = history.recents.contains(where: { EmojiGlyphSupport.supports($0) }) ? 0 : min(1, catalog.categories.count)
        reloadDisplayed(resetOffset: true)
        updateSearchAppearance()
        setNeedsLayout()
        if wasSearching { onSearchStateChanged?(false) }
    }

    func setSearchQuery(_ query: String) {
        guard isSearching else { return }
        cancelInteractions()
        searchQuery = String(query.prefix(120))
        reloadDisplayed(resetOffset: true)
        updateSearchAppearance()
    }

    func endSearch() {
        cancelInteractions()
        let wasSearching = isSearching
        isSearching = false
        searchQuery = ""
        reloadDisplayed(resetOffset: true)
        updateSearchAppearance()
        setNeedsLayout()
        if wasSearching { onSearchStateChanged?(false) }
    }

    func cancelInteractions() {
        toneOverlay?.removeFromSuperview()
        toneOverlay = nil
        toneSourceIndex = nil
    }

    private func beginSearch() {
        guard !isSearching else { return }
        cancelInteractions()
        isSearching = true
        searchQuery = ""
        reloadDisplayed(resetOffset: true)
        updateSearchAppearance()
        setNeedsLayout()
        onSearchStateChanged?(true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let cancelWidth: CGFloat = isSearching ? min(78, width * 0.24) : 0
        searchButton.frame = CGRect(x: 6, y: 3, width: max(0, width - 12 - cancelWidth), height: 36)
        searchIcon.frame = CGRect(x: 11, y: 10, width: 17, height: 17)
        searchLabel.frame = CGRect(x: 36, y: 0, width: max(0, searchButton.bounds.width - 76), height: 36)
        clearButton.frame = CGRect(x: max(6, searchButton.frame.maxX - 40), y: 0, width: 40, height: 44)
        cancelButton.frame = CGRect(x: width - cancelWidth, y: 0, width: cancelWidth, height: 44)
        toolbar.isHidden = isSearching
        categoryTitle.isHidden = isSearching
        cancelButton.isHidden = !isSearching
        let toolbarHeight: CGFloat = min(44, bounds.height)
        toolbar.frame = CGRect(x: 0, y: max(0, bounds.height - toolbarHeight), width: width, height: toolbarHeight)
        let edgeWidth: CGFloat = min(58, width / 3)
        backButton.frame = CGRect(x: 0, y: 0, width: edgeWidth, height: toolbarHeight)
        deleteButton.frame = CGRect(x: max(0, width - edgeWidth), y: 0, width: edgeWidth, height: toolbarHeight)
        categoryScroll.frame = CGRect(x: edgeWidth, y: 0, width: max(0, width - edgeWidth * 2), height: toolbarHeight)
        let categoryWidth: CGFloat = 44
        let stripWidth = categoryWidth * CGFloat(categoryButtons.count)
        let categoryOrigin = max(0, (categoryScroll.bounds.width - stripWidth) / 2)
        for (index, button) in categoryButtons.enumerated() {
            button.frame = CGRect(x: categoryOrigin + CGFloat(index) * categoryWidth,
                                  y: 0, width: categoryWidth, height: toolbarHeight)
        }
        categoryScroll.contentSize = CGSize(width: max(categoryScroll.bounds.width, stripWidth), height: toolbarHeight)
        categoryTitle.frame = CGRect(x: 9, y: 44, width: max(0, width - 18), height: 19)
        let gridY: CGFloat = isSearching ? 44 : 66
        let gridBottom = isSearching ? bounds.height : toolbar.frame.minY
        collectionView.frame = CGRect(x: 0, y: gridY, width: width, height: max(0, gridBottom - gridY))
        emptyLabel.frame = collectionView.frame.insetBy(dx: 8, dy: 0)
        if lastGridSize != collectionView.bounds.size {
            cancelInteractions()
            lastGridSize = collectionView.bounds.size
            let usableHeight = max(1, collectionView.bounds.height - 4)
            let rows = isSearching ? 1 : max(1, Int((usableHeight + 5) / 49))
            let cellHeight = min(52, floor((usableHeight - CGFloat(rows - 1) * 5) / CGFloat(rows)))
            flowLayout.itemSize = CGSize(width: min(48, max(1, width - 12)), height: max(1, cellHeight))
            flowLayout.invalidateLayout()
        }
    }

    private func selectCategory(_ index: Int) {
        guard categoryButtons.indices.contains(index) else { return }
        cancelInteractions()
        selectedCategory = index
        reloadDisplayed(resetOffset: true)
        categoryScroll.scrollRectToVisible(categoryButtons[index].frame.insetBy(dx: -4, dy: 0), animated: true)
    }

    private func reloadDisplayed(resetOffset: Bool) {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        displayingRecents = false
        if isSearching && !trimmedQuery.isEmpty {
            displayed = catalog.search(trimmedQuery).filter { supportedBases.contains($0.glyph) }.map { display($0) }
        } else if selectedCategory == 0 || (isSearching && !history.recents.isEmpty) {
            displayingRecents = true
            displayed = history.recents.compactMap { glyph in
                guard EmojiGlyphSupport.supports(glyph), let entry = catalog.entry(for: glyph) else { return nil }
                return DisplayedEmoji(entry: entry, glyph: glyph)
            }
        } else if supportedEntries.indices.contains(selectedCategory - 1) {
            displayed = supportedEntries[selectedCategory - 1].map { display($0) }
        } else {
            displayed = []
        }
        updateCategoryAppearance()
        updateEmptyState()
        refreshCollection(resetOffset: resetOffset)
    }

    private func refreshCollection(resetOffset: Bool) {
        // Keep a single synchronous update path. Mixing animated item reloads with
        // a subsequent category reload can leave reused cells showing the old grid.
        UIView.performWithoutAnimation {
            collectionView.reloadData()
            if resetOffset { collectionView.setContentOffset(.zero, animated: false) }
            if collectionView.window != nil { collectionView.layoutIfNeeded() }
            for cell in collectionView.visibleCells {
                guard let cell = cell as? EmojiCell, let path = collectionView.indexPath(for: cell) else { continue }
                configure(cell, at: path)
            }
        }
    }

    private func display(_ entry: EmojiEntry) -> DisplayedEmoji {
        let preferred = history.preferredGlyph(for: entry)
        return DisplayedEmoji(entry: entry, glyph: EmojiGlyphSupport.supports(preferred) ? preferred : entry.glyph)
    }

    private func updateSearchAppearance() {
        let placeholder = languageIsRussian ? "Поиск эмодзи" : "Search Emoji"
        searchLabel.text = searchQuery.isEmpty ? placeholder : searchQuery
        searchLabel.textColor = searchQuery.isEmpty ? .secondaryLabel : .label
        searchButton.layer.borderWidth = isSearching ? 1 : 0
        searchButton.layer.borderColor = tintColor.withAlphaComponent(0.5).cgColor
        searchButton.accessibilityLabel = placeholder
        searchButton.accessibilityValue = searchQuery
        searchButton.accessibilityHint = languageIsRussian ? "Поиск на русском и английском" : "Search in Russian or English"
        searchButton.accessibilityTraits = isSearching ? [.button, .selected] : .button
        clearButton.isHidden = !isSearching || searchQuery.isEmpty
    }

    private func updateCategoryAppearance() {
        if selectedCategory == 0 {
            categoryTitle.text = languageIsRussian ? "НЕДАВНИЕ" : "RECENT"
        } else if catalog.categories.indices.contains(selectedCategory - 1) {
            let category = catalog.categories[selectedCategory - 1]
            categoryTitle.text = (languageIsRussian ? category.russian : category.english).uppercased()
        }
        for (index, button) in categoryButtons.enumerated() {
            if index == 0 {
                button.accessibilityLabel = languageIsRussian ? "Недавние" : "Recent"
            } else {
                let category = catalog.categories[index - 1]
                button.accessibilityLabel = languageIsRussian ? category.russian : category.english
            }
            button.accessibilityTraits = index == selectedCategory ? [.button, .selected] : .button
            button.backgroundColor = index == selectedCategory ? .tertiarySystemFill : .clear
        }
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !displayed.isEmpty
        if isSearching && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyLabel.text = languageIsRussian ? "Эмодзи не найдены" : "No emoji found"
        } else {
            emptyLabel.text = languageIsRussian ? "Выбранные эмодзи появятся здесь" : "Your recent emoji will appear here"
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { displayed.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseIdentifier, for: indexPath) as! EmojiCell
        configure(cell, at: indexPath)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? EmojiCell else { return }
        configure(cell, at: indexPath)
    }

    private func configure(_ cell: EmojiCell, at indexPath: IndexPath) {
        guard displayed.indices.contains(indexPath.item) else { return }
        let item = displayed[indexPath.item]
        let name = languageIsRussian ? item.entry.russian : item.entry.english
        cell.configure(glyph: item.glyph, name: name, hasVariants: item.entry.variants.count > 1,
                       hint: languageIsRussian ? "Удерживайте для выбора оттенка кожи" : "Touch and hold to choose a skin tone")
        cell.onActivate = { [weak self] in self?.commit(item.glyph) }
        if item.entry.variants.count > 1 {
            cell.accessibilityCustomActions = [UIAccessibilityCustomAction(name: languageIsRussian ? "Выбрать оттенок кожи" : "Choose skin tone") { [weak self, weak cell] _ in
                guard let self, let cell else { return false }
                self.showTones(for: item.entry, sourceIndex: indexPath.item, anchor: cell.convert(cell.bounds, to: self))
                return true
            }]
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard toneOverlay == nil, displayed.indices.contains(indexPath.item) else { return }
        commit(displayed[indexPath.item].glyph)
    }

    private func commit(_ glyph: String) {
        let sourceIndex = toneSourceIndex
        cancelInteractions()
        history.record(glyph)
        // Keep recents in place. A tone change updates only the tile it came from;
        // other recent variants retain their exact glyphs. Category/search results
        // use the new preferred tone immediately on the next ordinary tap.
        if let base = catalog.entry(for: glyph)?.glyph {
            let changed: [Int]
            if displayingRecents {
                if let index = sourceIndex, displayed.indices.contains(index), displayed[index].entry.glyph == base {
                    changed = [index]
                } else { changed = [] }
            } else {
                changed = displayed.indices.filter { displayed[$0].entry.glyph == base }
            }
            for index in changed {
                displayed[index] = DisplayedEmoji(entry: displayed[index].entry, glyph: glyph)
            }
            if !changed.isEmpty { refreshCollection(resetOffset: false) }
        }
        onInsert?(glyph)
    }

    @objc private func holdEmoji(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            holdOrigin = gesture.location(in: self)
            draggedTone = false
            let point = gesture.location(in: collectionView)
            guard let path = collectionView.indexPathForItem(at: point), displayed.indices.contains(path.item),
                  let cell = collectionView.cellForItem(at: path) else { return }
            let item = displayed[path.item]
            showTones(for: item.entry, sourceIndex: path.item, anchor: cell.convert(cell.bounds, to: self))
        case .changed, .ended:
            let point = gesture.location(in: self)
            if hypot(point.x - holdOrigin.x, point.y - holdOrigin.y) > 8 { draggedTone = true }
            if draggedTone, let overlay = toneOverlay {
                overlay.highlight(at: gesture.location(in: overlay))
                if gesture.state == .ended {
                    if let selected = overlay.selectedGlyph { commit(selected) }
                    else { cancelInteractions() }
                }
            }
            // A stationary long press also permits a subsequent tap on a tone.
        case .cancelled, .failed:
            cancelInteractions()
        default: break
        }
    }

    private func showTones(for entry: EmojiEntry, sourceIndex: Int, anchor: CGRect) {
        cancelInteractions()
        let variants = entry.variants.filter { EmojiGlyphSupport.supports($0) }
        guard variants.count > 1 else { return }
        let host = superview ?? self
        let overlay = EmojiToneOverlay(variants: variants, russian: languageIsRussian)
        overlay.frame = host.bounds
        overlay.onChoose = { [weak self] glyph in self?.commit(glyph) }
        overlay.onDismiss = { [weak self] in self?.cancelInteractions() }
        host.addSubview(overlay)
        overlay.place(near: convert(anchor, to: host))
        toneOverlay = overlay
        toneSourceIndex = sourceIndex
        UIAccessibility.post(notification: .layoutChanged, argument: overlay.firstToneButton)
    }
}

/// Test complete sequences, not individual scalars: unsupported ZWJ emoji can otherwise
/// silently turn into several unrelated pictures. Cache results for the life of the extension.
private enum EmojiGlyphSupport {
    private static let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 32, nil)
    private static var cache: [String: Bool] = [:]

    static func supports(_ glyph: String) -> Bool {
        if let result = cache[glyph] { return result }
        let string = NSAttributedString(string: glyph, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(string)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var result = !runs.isEmpty
        var advancingGlyphs = 0
        var totalAdvance: CGFloat = 0
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName],
                  (CTFontCopyPostScriptName(runFont as! CTFont) as String).contains("AppleColorEmoji") else {
                result = false
                break
            }
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { result = false; break }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            glyphs.withUnsafeMutableBufferPointer { buffer in
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), buffer.baseAddress!)
            }
            advances.withUnsafeMutableBufferPointer { buffer in
                CTRunGetAdvances(run, CFRange(location: 0, length: count), buffer.baseAddress!)
            }
            for (number, advance) in zip(glyphs, advances) {
                if number == 0 || advance.width < -0.1 { result = false }
                if advance.width > 0.1 { advancingGlyphs += 1 }
                totalAdvance += advance.width
            }
        }
        // Apple composes some mixed-tone couples/handshakes from multiple glyphs:
        // zero-advance layers plus one advancing glyph are still one emoji. An
        // unsupported ZWJ fallback instead advances once for each separate picture.
        let em = CTFontGetSize(font)
        result = result && advancingGlyphs == 1 && totalAdvance >= em * 0.75 && totalAdvance <= em * 1.25
        cache[glyph] = result
        return result
    }
}

private final class EmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiCell"
    var onActivate: (() -> Void)?
    private let label = UILabel()
    private let toneIndicator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 9
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        label.isAccessibilityElement = false
        contentView.addSubview(label)
        toneIndicator.backgroundColor = .tertiaryLabel
        toneIndicator.layer.cornerRadius = 1.5
        contentView.addSubview(toneIndicator)
        isAccessibilityElement = true
        accessibilityTraits = [.button, .keyboardKey]
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(glyph: String, name: String, hasVariants: Bool, hint: String) {
        label.text = glyph
        toneIndicator.isHidden = !hasVariants
        accessibilityLabel = name + " " + glyph
        accessibilityIdentifier = "emoji.\(glyph)"
        accessibilityHint = hasVariants ? hint : nil
        accessibilityCustomActions = nil
        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        toneIndicator.frame = CGRect(x: max(0, bounds.width - 7), y: max(0, bounds.height - 6), width: 3, height: 3)
    }

    override var isHighlighted: Bool { didSet { updateAppearance() } }
    override var isSelected: Bool { didSet { updateAppearance() } }

    override func prepareForReuse() {
        super.prepareForReuse()
        onActivate = nil
        label.text = nil
        accessibilityLabel = nil
        accessibilityCustomActions = nil
        accessibilityHint = nil
    }

    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }

    private func updateAppearance() {
        contentView.backgroundColor = isHighlighted || isSelected ? .tertiarySystemFill : .clear
    }
}

private final class EmojiToneOverlay: UIView {
    var onChoose: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    private(set) var selectedGlyph: String?
    var firstToneButton: UIButton? { buttons.first }
    private let dismissButton = UIButton(type: .custom)
    private let panel = UIView()
    private var buttons: [UIButton] = []
    private let variants: [String]

    init(variants: [String], russian: Bool) {
        self.variants = variants
        super.init(frame: .zero)
        accessibilityViewIsModal = true
        dismissButton.accessibilityLabel = russian ? "Закрыть выбор оттенка" : "Dismiss skin tones"
        dismissButton.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        addSubview(dismissButton)
        panel.backgroundColor = .secondarySystemBackground
        panel.layer.cornerRadius = 13
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.22
        panel.layer.shadowRadius = 9
        panel.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(panel)
        let tonesRU = ["светлый", "средне-светлый", "средний", "средне-тёмный", "тёмный"]
        let tonesEN = ["light", "medium-light", "medium", "medium-dark", "dark"]
        for (index, glyph) in variants.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(glyph, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 31)
            button.layer.cornerRadius = 8
            button.accessibilityIdentifier = "emoji.tone.\(index)"
            let tones = glyph.unicodeScalars.compactMap { scalar -> String? in
                let value = Int(scalar.value) - 0x1F3FB
                guard (0..<5).contains(value) else { return nil }
                return (russian ? tonesRU : tonesEN)[value]
            }
            let description = tones.isEmpty ? (russian ? "Без оттенка" : "Default tone") : tones.joined(separator: ", ")
            button.accessibilityLabel = description + " " + glyph
            button.addAction(UIAction { [weak self] _ in self?.onChoose?(glyph) }, for: .touchUpInside)
            panel.addSubview(button)
            buttons.append(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(variants:russian:)") }

    func place(near anchor: CGRect) {
        dismissButton.frame = bounds
        let availableWidth = max(1, bounds.width - 12)
        let columns = max(1, min(6, variants.count, Int((availableWidth - 12) / 44)))
        let rows = Int(ceil(Double(variants.count) / Double(columns)))
        let cell = max(1, min(44, (availableWidth - 12) / CGFloat(columns), (bounds.height - 12) / CGFloat(rows)))
        let size = CGSize(width: CGFloat(columns) * cell + 12, height: CGFloat(rows) * cell + 12)
        let x = min(max(6, anchor.midX - size.width / 2), max(6, bounds.width - size.width - 6))
        let above = anchor.minY - size.height - 7
        let y = min(max(6, above >= 6 ? above : anchor.maxY + 7), max(6, bounds.height - size.height - 6))
        panel.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: 6 + CGFloat(index % columns) * cell, y: 6 + CGFloat(index / columns) * cell, width: cell, height: cell)
        }
    }

    func highlight(at point: CGPoint) {
        let location = convert(point, to: panel)
        let selected = buttons.firstIndex { $0.frame.contains(location) }
        selectedGlyph = selected.map { variants[$0] }
        for (index, button) in buttons.enumerated() {
            button.backgroundColor = selected == index ? .tertiarySystemFill : .clear
        }
    }
}
