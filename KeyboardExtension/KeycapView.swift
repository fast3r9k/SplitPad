import UIKit

/// A reusable key that owns its touch sequence, including flicks and alternate selection.
/// Configure it in place; configuration changes wait until the current touch finishes.
final class KeycapView: UIControl {
    struct Configuration {
        var title: String
        var secondary: String?
        var alternates: [String]
        var symbol: String?
        var trailingText: String?
        var isSpecial: Bool
        var commitsOnRelease: Bool
        var usesLongPressAction: Bool
        var usesCursorTracking: Bool

        init(title: String, secondary: String? = nil, alternates: [String] = [],
             symbol: String? = nil, trailingText: String? = nil,
             isSpecial: Bool = false, commitsOnRelease: Bool = true,
             usesLongPressAction: Bool = false, usesCursorTracking: Bool = false) {
            self.title = title
            self.secondary = secondary
            self.alternates = alternates
            self.symbol = symbol
            self.trailingText = trailingText
            self.isSpecial = isSpecial
            self.commitsOnRelease = commitsOnRelease
            self.usesLongPressAction = usesLongPressAction
            self.usesCursorTracking = usesCursorTracking
        }
    }

    /// The keyboard root, not a row or a clipped half. Popups stay inside its bounds.
    weak var popupHost: UIView?
    /// nil means the ordinary key action; a string means an alternate or downward flick.
    var onCommit: ((String?) -> Void)?
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onCursorTrackingBegan: (() -> Bool)?
    var onCursorMoved: ((Int) -> Void)?
    var onCursorTrackingEnded: (() -> Void)?
    var onAccessibleCursorMove: ((Int) -> Void)?
    private var cursorTracking = false
    private var cursorDrag = KeyboardCursorDrag()
    private(set) var isInteracting = false
    /// Available while tracking, for UIInputViewController.handleInputModeList(from:with:).
    private(set) var trackingEvent: UIEvent?

    private var configuration: Configuration
    private var pendingConfiguration: Configuration?
    private let mainLabel = UILabel()
    private let secondaryLabel = UILabel()
    private let trailingLabel = UILabel()
    private let symbolView = UIImageView()
    private var holdTimer: Timer?
    private var touchOrigin = CGPoint.zero
    private var lastTouchPoint = CGPoint.zero
    private var flickedSecondary = false
    private var performedLongPress = false
    private var popup: AlternatePopup?
    private var popupSelectionRegion = CGRect.zero
    private var popupTouchOrigin = CGPoint.zero
    private var popupSelectionMoved = false
    private var activeSecondary: String?
    private var generatedAccessibilityLabel: String?

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.20
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        mainLabel.textAlignment = .center
        mainLabel.adjustsFontSizeToFitWidth = true
        mainLabel.minimumScaleFactor = 0.45
        secondaryLabel.textAlignment = .right
        secondaryLabel.adjustsFontSizeToFitWidth = true
        secondaryLabel.minimumScaleFactor = 0.6
        trailingLabel.textAlignment = .right
        trailingLabel.adjustsFontSizeToFitWidth = true
        trailingLabel.minimumScaleFactor = 0.6
        symbolView.contentMode = .scaleAspectFit
        [mainLabel, secondaryLabel, trailingLabel, symbolView].forEach {
            $0.isUserInteractionEnabled = false
            $0.isAccessibilityElement = false
            addSubview($0)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: KeycapView, _: UITraitCollection) in
            view.updateAppearance()
            view.popup?.updateAppearance()
        }
        applyConfiguration()
    }

    required init?(coder: NSCoder) { fatalError("Use init(configuration:)") }

    func configure(_ configuration: Configuration) {
        if isInteracting {
            pendingConfiguration = configuration
        } else {
            self.configuration = configuration
            applyConfiguration()
        }
    }

    /// Call before rotation, layout replacement, hiding the keyboard, or removing this key.
    func cancelInteraction() {
        guard isInteracting || popup != nil || holdTimer != nil else { return }
        finishInteraction()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = bounds.width < 35 ? 3 : 7
        let hasSecondary = configuration.secondary?.isEmpty == false
        let mainTop: CGFloat = hasSecondary && !flickedSecondary ? 12 : 2
        let mainFont: CGFloat = configuration.isSpecial || configuration.title.count > 2 ? 16 : 26
        mainLabel.font = .systemFont(ofSize: min(mainFont, bounds.height * 0.56))
        mainLabel.frame = CGRect(x: inset, y: mainTop,
                                 width: max(0, bounds.width - inset * 2),
                                 height: max(0, bounds.height - mainTop - 3))
        secondaryLabel.font = .systemFont(ofSize: min(13, bounds.height * 0.26), weight: .medium)
        secondaryLabel.frame = CGRect(x: inset, y: 3,
                                      width: max(0, bounds.width - inset * 2), height: 15)
        trailingLabel.font = .systemFont(ofSize: 11, weight: .medium)
        trailingLabel.frame = CGRect(x: bounds.width * 0.53, y: max(0, (bounds.height - 15) / 2),
                                     width: max(0, bounds.width * 0.47 - inset), height: 15)
        let symbolSide = min(23, bounds.height * 0.49)
        symbolView.frame = CGRect(x: (bounds.width - symbolSide) / 2,
                                  y: (bounds.height - symbolSide) / 2,
                                  width: symbolSide, height: symbolSide)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { cancelInteraction() }
            alpha = isEnabled ? 1 : 0.45
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled, !isInteracting else { return false }
        isInteracting = true
        trackingEvent = event
        touchOrigin = touch.location(in: self)
        lastTouchPoint = touchOrigin
        activeSecondary = configuration.secondary
        flickedSecondary = false
        performedLongPress = false
        isHighlighted = true
        updateAppearance()
        // Deletion can insert/remove on touch-down and own its repeat timer externally.
        onPressBegan?()
        guard isInteracting else { return false }
        if configuration.usesCursorTracking || configuration.usesLongPressAction || !configuration.alternates.isEmpty {
            let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
                self?.holdTriggered()
            }
            holdTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isInteracting else { return false }
        lastTouchPoint = touch.location(in: self)
        trackingEvent = event
        if cursorTracking {
            let offset = cursorDrag.move(to: Double(lastTouchPoint.x))
            if offset != 0 { onCursorMoved?(offset) }
            return isInteracting
        }
        // A repeating action (such as delete) stops permanently for this touch
        // when the finger leaves the key; re-entry must not restart deletion.
        if !configuration.commitsOnRelease,
           !bounds.insetBy(dx: -8, dy: -8).contains(lastTouchPoint) {
            finishInteraction()
            return false
        }
        if popup != nil {
            updatePopupSelection(at: lastTouchPoint)
            return true
        }
        if performedLongPress { return true }
        let dx = lastTouchPoint.x - touchOrigin.x
        let dy = lastTouchPoint.y - touchOrigin.y
        if activeSecondary?.isEmpty == false,
           dy >= max(14, bounds.height * 0.25), abs(dx) <= max(36, bounds.width) {
            flickedSecondary = true
            invalidateHoldTimer()
        }
        if flickedSecondary {
            mainLabel.text = activeSecondary
            mainLabel.isHidden = false
            symbolView.isHidden = true
            secondaryLabel.isHidden = true
            isHighlighted = acceptsFlick(at: lastTouchPoint)
            setNeedsLayout()
        } else {
            isHighlighted = bounds.insetBy(dx: -8, dy: -8).contains(lastTouchPoint)
            if !isHighlighted || hypot(dx, dy) > 12 { invalidateHoldTimer() }
        }
        updateAppearance()
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard isInteracting else { return }
        let point = touch?.location(in: self) ?? lastTouchPoint
        if cursorTracking {
            let offset = cursorDrag.move(to: Double(point.x))
            if offset != 0 { onCursorMoved?(offset) }
            guard isInteracting else { return }
        }
        var commitDefault = false
        var chosen: String?
        if let popup {
            updatePopupSelection(at: point)
            chosen = popup.selectedValue
        } else if !performedLongPress, configuration.commitsOnRelease {
            if flickedSecondary {
                if acceptsFlick(at: point) { chosen = activeSecondary }
            } else {
                commitDefault = bounds.insetBy(dx: -8, dy: -8).contains(point)
            }
        }
        // Clear state before a callback can rebuild the layout or change input context.
        finishInteraction()
        if let chosen {
            onCommit?(chosen)
        } else if commitDefault {
            onCommit?(nil)
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        cancelInteraction()
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        cancelInteraction()
        if configuration.commitsOnRelease {
            onCommit?(nil)
        } else {
            onPressBegan?()
            onPressEnded?()
        }
        return true
    }

    private func applyConfiguration() {
        mainLabel.text = configuration.title
        mainLabel.isHidden = configuration.symbol != nil
        secondaryLabel.text = configuration.secondary
        secondaryLabel.isHidden = configuration.secondary?.isEmpty != false
        trailingLabel.text = configuration.trailingText
        trailingLabel.isHidden = configuration.trailingText?.isEmpty != false
        symbolView.image = configuration.symbol.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
        }
        symbolView.isHidden = configuration.symbol == nil
        // A controller may replace this with a localized semantic name after configure().
        if accessibilityLabel == nil || accessibilityLabel == generatedAccessibilityLabel {
            accessibilityLabel = configuration.title
        }
        if cursorTracking {
            mainLabel.isHidden = true
            secondaryLabel.isHidden = true
            trailingLabel.isHidden = true
            symbolView.image = UIImage(systemName: "arrow.left.and.right")
            symbolView.isHidden = false
        }
        generatedAccessibilityLabel = configuration.title
        accessibilityHint = configuration.secondary == nil ? nil : "Удерживайте или смахните вниз для дополнительного символа"
        var actions: [UIAccessibilityCustomAction] = []
        var values: [String] = []
        if let secondary = configuration.secondary, !secondary.isEmpty { values.append(secondary) }
        for alternate in configuration.alternates where !values.contains(alternate) { values.append(alternate) }
        for value in values {
            actions.append(UIAccessibilityCustomAction(name: value) { [weak self] _ in
                guard let self, self.isEnabled else { return false }
                self.cancelInteraction()
                self.onCommit?(value)
                return true
            })
        }
        if configuration.usesCursorTracking {
            accessibilityHint = "Hold, then slide left or right to move the cursor"
            for (name, offset) in [("Move cursor left", -1), ("Move cursor right", 1)] {
                actions.append(UIAccessibilityCustomAction(name: name) { [weak self] _ in
                    guard let self, self.isEnabled else { return false }
                    self.cancelInteraction()
                    self.onAccessibleCursorMove?(offset)
                    return true
                })
            }
        }
        if configuration.usesLongPressAction {
            actions.append(UIAccessibilityCustomAction(name: "Удержание") { [weak self] _ in
                guard let self, self.isEnabled else { return false }
                self.cancelInteraction()
                self.onLongPress?()
                return true
            })
        }
        accessibilityCustomActions = actions.isEmpty ? nil : actions
        updateAppearance()
        setNeedsLayout()
    }

    private func updateAppearance() {
        let dark = traitCollection.userInterfaceStyle == .dark
        if isHighlighted {
            backgroundColor = dark ? UIColor(white: 0.56, alpha: 1) : UIColor(white: 0.78, alpha: 1)
        } else if configuration.isSpecial {
            backgroundColor = dark ? UIColor(white: 0.25, alpha: 1) : .white
        } else {
            backgroundColor = dark ? UIColor(white: 0.39, alpha: 1) : .white
        }
        mainLabel.textColor = dark ? .white : .black
        symbolView.tintColor = mainLabel.textColor
        secondaryLabel.textColor = dark ? UIColor(white: 0.83, alpha: 1) : UIColor(white: 0.35, alpha: 1)
        trailingLabel.textColor = secondaryLabel.textColor
    }

    private func holdTriggered() {
        holdTimer = nil
        guard isInteracting, !flickedSecondary, isHighlighted else { return }
        if configuration.usesCursorTracking {
            // Suppress a space on release even when the host refuses cursor mode.
            performedLongPress = true
            cursorTracking = onCursorTrackingBegan?() == true
            if cursorTracking {
                cursorDrag.begin(at: Double(lastTouchPoint.x))
                applyConfiguration()
            }
            return
        }
        if configuration.usesLongPressAction {
            performedLongPress = true
            onLongPress?()
            return
        }
        guard let host = popupHost, !configuration.alternates.isEmpty,
              host.bounds.width >= 44, host.bounds.height >= 44 else { return }
        let options = configuration.alternates.reduce(into: [String]()) { values, value in
            if !value.isEmpty && !values.contains(value) { values.append(value) }
        }
        guard !options.isEmpty else { return }
        let keyRect = convert(bounds, to: host)
        let margins = host.bounds.insetBy(dx: 6, dy: 6)
        let width = min(margins.width, CGFloat(options.count) * 44 + 8)
        // The first row has 47 pt above it inside the keyboard. Fit the popup
        // into that header instead of moving it below the key, under the finger.
        let height = min(54, margins.height, keyRect.minY - margins.minY - 5)
        guard height >= 44 else { return }
        // Expand toward the center when a key is near either keyboard edge.
        let x = min(margins.maxX - width, max(margins.minX, keyRect.midX - width / 2))
        let y = keyRect.minY - height - 5
        let popup = AlternatePopup(values: options)
        popup.frame = CGRect(x: x, y: y, width: width, height: height)
        host.addSubview(popup)
        host.bringSubviewToFront(popup)
        self.popup = popup
        popupTouchOrigin = lastTouchPoint
        popupSelectionMoved = false
        popupSelectionRegion = popup.frame.union(keyRect).insetBy(dx: -8, dy: -8).intersection(host.bounds)
        updatePopupSelection(at: lastTouchPoint)
    }

    private func updatePopupSelection(at point: CGPoint) {
        guard let popup, let host = popupHost else { return }
        let hostPoint = convert(point, to: host)
        guard popupSelectionRegion.contains(hostPoint) else {
            popup.select(index: nil)
            return
        }
        if hypot(point.x - popupTouchOrigin.x, point.y - popupTouchOrigin.y) > 8 {
            popupSelectionMoved = true
        }
        // A stationary hold/release selects the corner symbol even when the
        // popup is shifted or clamped at a keyboard edge. Sliding selects accents.
        if configuration.secondary?.isEmpty == false && !popupSelectionMoved {
            popup.select(index: 0)
            return
        }
        let localX = hostPoint.x - popup.frame.minX - 4
        let cellWidth = max(1, (popup.bounds.width - 8) / CGFloat(popup.values.count))
        let index = max(0, min(popup.values.count - 1, Int(floor(localX / cellWidth))))
        popup.select(index: index)
    }

    private func acceptsFlick(at point: CGPoint) -> Bool {
        let region = CGRect(x: -16, y: 0, width: bounds.width + 32,
                            height: bounds.height + min(80, bounds.height * 1.5))
        guard region.contains(point) else { return false }
        if let host = popupHost { return host.bounds.contains(convert(point, to: host)) }
        return true
    }

    private func invalidateHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func finishInteraction() {
        let wasInteracting = isInteracting
        let wasCursorTracking = cursorTracking
        cursorTracking = false
        cursorDrag.end()
        isInteracting = false
        trackingEvent = nil
        invalidateHoldTimer()
        popup?.removeFromSuperview()
        popup = nil
        flickedSecondary = false
        performedLongPress = false
        activeSecondary = nil
        isHighlighted = false
        if let pendingConfiguration {
            configuration = pendingConfiguration
            self.pendingConfiguration = nil
        }
        applyConfiguration()
        if wasCursorTracking { onCursorTrackingEnded?() }
        if wasInteracting { onPressEnded?() }
    }
}

private final class AlternatePopup: UIView {
    let values: [String]
    private let labels: [UILabel]
    private var selectedIndex: Int?
    var selectedValue: String? { selectedIndex.map { values[$0] } }

    init(values: [String]) {
        self.values = values
        labels = values.map { value in
            let label = UILabel()
            label.text = value
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 24)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.45
            label.layer.cornerRadius = 5
            label.clipsToBounds = true
            return label
        }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.27
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        labels.forEach(addSubview)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AlternatePopup, _: UITraitCollection) in
            view.updateAppearance()
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("Use init(values:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cellWidth = max(0, (bounds.width - 8) / CGFloat(labels.count))
        for (index, label) in labels.enumerated() {
            label.frame = CGRect(x: 4 + CGFloat(index) * cellWidth, y: 4,
                                 width: cellWidth, height: max(0, bounds.height - 8))
        }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
    }

    func select(index: Int?) {
        selectedIndex = index
        updateAppearance()
    }

    func updateAppearance() {
        let dark = traitCollection.userInterfaceStyle == .dark
        backgroundColor = dark ? UIColor(white: 0.32, alpha: 1) : .white
        for (index, label) in labels.enumerated() {
            let selected = index == selectedIndex
            label.backgroundColor = selected ? .systemBlue : .clear
            label.textColor = selected ? .white : (dark ? .white : .black)
        }
    }
}
