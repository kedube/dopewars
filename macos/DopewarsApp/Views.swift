import AppKit

extension Notification.Name {
    /// Posted whenever the mute state flips, so the toolbar icon can sync.
    static let dopewarsMuteChanged = Notification.Name("DopewarsMuteChanged")
    /// Posted when a preference changes, so open windows can re-apply.
    static let dopewarsPrefsChanged = Notification.Name("DopewarsPrefsChanged")
}

/// User-tunable game aids (Preferences window). Both default to on;
/// turning them off hides market intel and makes the game harder.
enum DopewarsPrefs {
    private static let trendsKey = "DopewarsShowTrends"
    private static let avgPaidKey = "DopewarsShowAvgPaid"

    private static func bool(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true : UserDefaults.standard.bool(forKey: key)
    }

    static var showTrends: Bool {
        get { bool(trendsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: trendsKey)
            NotificationCenter.default.post(name: .dopewarsPrefsChanged, object: nil)
        }
    }

    static var showAvgPaid: Bool {
        get { bool(avgPaidKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: avgPaidKey)
            NotificationCenter.default.post(name: .dopewarsPrefsChanged, object: nil)
        }
    }

    // MARK: Game rules (engine overrides, applied at the next new game)

    static let defaultGameTurns = 31
    static let defaultStartCash: Int64 = 2000
    static let defaultStartDebt: Int64 = 5500
    static let defaultDebtInterest = 10
    static let defaultBankInterest = 5
    static let defaultCheapDivide = 4
    static let defaultExpensiveMultiply = 4
    static let defaultPlayerArmor = 100
    static let defaultBitchArmor = 50
    static let defaultBitchMinPrice: Int64 = 50000
    static let defaultBitchMaxPrice: Int64 = 150000
    static let defaultStartDay = 1
    static let defaultStartMonth = 12
    static let defaultStartYear = 1984
    static let defaultDifficulty = 1          // 0 easy, 1 normal, 2 hard
    static let defaultCurrencySymbol = "$"
    static let defaultCurrencyPrefix = true   // symbol precedes the amount

    private static let turnsKey = "DopewarsGameTurns"
    private static let startCashKey = "DopewarsStartCash"
    private static let startDebtKey = "DopewarsStartDebt"
    private static let sanitizedKey = "DopewarsSanitized"
    private static let debtInterestKey = "DopewarsDebtInterest"
    private static let bankInterestKey = "DopewarsBankInterest"
    private static let cheapDivideKey = "DopewarsCheapDivide"
    private static let expensiveMultiplyKey = "DopewarsExpensiveMultiply"
    private static let playerArmorKey = "DopewarsPlayerArmor"
    private static let bitchArmorKey = "DopewarsBitchArmor"
    private static let bitchMinPriceKey = "DopewarsBitchMinPrice"
    private static let bitchMaxPriceKey = "DopewarsBitchMaxPrice"
    private static let startDayKey = "DopewarsStartDay"
    private static let startMonthKey = "DopewarsStartMonth"
    private static let startYearKey = "DopewarsStartYear"
    private static let difficultyKey = "DopewarsDifficulty"
    private static let familyFriendlyKey = "DopewarsFamilyFriendly"
    private static let currencySymbolKey = "DopewarsCurrencySymbol"
    private static let currencyPrefixKey = "DopewarsCurrencyPrefix"

    private static let gameRuleKeys = [
        turnsKey, startCashKey, startDebtKey, sanitizedKey,
        debtInterestKey, bankInterestKey, cheapDivideKey,
        expensiveMultiplyKey, playerArmorKey, bitchArmorKey,
        bitchMinPriceKey, bitchMaxPriceKey,
        startDayKey, startMonthKey, startYearKey,
        difficultyKey, familyFriendlyKey,
        currencySymbolKey, currencyPrefixKey,
    ]

    private static func int64(_ key: String, default def: Int64) -> Int64 {
        UserDefaults.standard.object(forKey: key) == nil
            ? def : Int64(UserDefaults.standard.integer(forKey: key))
    }

    private static func int(_ key: String, default def: Int,
                            clamp range: ClosedRange<Int>) -> Int {
        Int(int64(key, default: Int64(def))).clamped(to: range)
    }

    private static func set(_ value: Int, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Days per game; 0 means the game never ends.
    static var gameTurns: Int {
        get { int(turnsKey, default: defaultGameTurns, clamp: 0...Int(Int32.max)) }
        set { set(max(0, newValue), forKey: turnsKey) }
    }

    static var startCash: Int64 {
        get { int64(startCashKey, default: defaultStartCash) }
        set { set(Int(max(0, newValue)), forKey: startCashKey) }
    }

    static var startDebt: Int64 {
        get { int64(startDebtKey, default: defaultStartDebt) }
        set { set(Int(max(0, newValue)), forKey: startDebtKey) }
    }

    /// Tones down the engine's random events.
    static var sanitized: Bool {
        get { UserDefaults.standard.bool(forKey: sanitizedKey) }
        set { UserDefaults.standard.set(newValue, forKey: sanitizedKey) }
    }

    /// Daily interest on the loan shark debt, %. Negative shrinks the debt.
    static var debtInterest: Int {
        get { int(debtInterestKey, default: defaultDebtInterest, clamp: -100...1000) }
        set { set(newValue.clamped(to: -100...1000), forKey: debtInterestKey) }
    }

    /// Daily interest on the bank balance, %.
    static var bankInterest: Int {
        get { int(bankInterestKey, default: defaultBankInterest, clamp: -100...1000) }
        set { set(newValue.clamped(to: -100...1000), forKey: bankInterestKey) }
    }

    /// Divider applied to a drug's price on a "cheap" event.
    static var cheapDivide: Int {
        get { int(cheapDivideKey, default: defaultCheapDivide, clamp: 1...1000) }
        set { set(newValue.clamped(to: 1...1000), forKey: cheapDivideKey) }
    }

    /// Multiplier applied to a drug's price on a "spike" event.
    static var expensiveMultiply: Int {
        get { int(expensiveMultiplyKey, default: defaultExpensiveMultiply,
                  clamp: 1...1000) }
        set { set(newValue.clamped(to: 1...1000), forKey: expensiveMultiplyKey) }
    }

    /// Player's % resistance to gunshots (lower = harder fights).
    static var playerArmor: Int {
        get { int(playerArmorKey, default: defaultPlayerArmor, clamp: 0...100) }
        set { set(newValue.clamped(to: 0...100), forKey: playerArmorKey) }
    }

    /// Escorts' % resistance to gunshots.
    static var bitchArmor: Int {
        get { int(bitchArmorKey, default: defaultBitchArmor, clamp: 1...100) }
        set { set(newValue.clamped(to: 1...100), forKey: bitchArmorKey) }
    }

    static var bitchMinPrice: Int64 {
        get { int64(bitchMinPriceKey, default: defaultBitchMinPrice) }
        set { set(Int(max(0, newValue)), forKey: bitchMinPriceKey) }
    }

    static var bitchMaxPrice: Int64 {
        get { max(int64(bitchMaxPriceKey, default: defaultBitchMaxPrice),
                  bitchMinPrice) }
        set { set(Int(max(0, newValue)), forKey: bitchMaxPriceKey) }
    }

    static var startDay: Int {
        get { int(startDayKey, default: defaultStartDay, clamp: 1...31) }
        set { set(newValue.clamped(to: 1...31), forKey: startDayKey) }
    }

    static var startMonth: Int {
        get { int(startMonthKey, default: defaultStartMonth, clamp: 1...12) }
        set { set(newValue.clamped(to: 1...12), forKey: startMonthKey) }
    }

    static var startYear: Int {
        get { int(startYearKey, default: defaultStartYear, clamp: 0...9999) }
        set { set(newValue.clamped(to: 0...9999), forKey: startYearKey) }
    }

    /// Difficulty preset: 0 easy, 1 normal, 2 hard.
    static var difficulty: Int {
        get { int(difficultyKey, default: defaultDifficulty, clamp: 0...2) }
        set { set(newValue.clamped(to: 0...2), forKey: difficultyKey) }
    }

    /// Engine messages say "escort(s)" instead of the original wording.
    static var familyFriendly: Bool {
        get { UserDefaults.standard.bool(forKey: familyFriendlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: familyFriendlyKey) }
    }

    /// Currency symbol shown on prices. Cosmetic; applies immediately.
    static var currencySymbol: String {
        get {
            UserDefaults.standard.string(forKey: currencySymbolKey)
                ?? defaultCurrencySymbol
        }
        set {
            let symbol = newValue.trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(symbol.isEmpty ? defaultCurrencySymbol
                                                     : symbol,
                                      forKey: currencySymbolKey)
            NotificationCenter.default.post(name: .dopewarsPrefsChanged, object: nil)
        }
    }

    /// Whether the currency symbol precedes the amount ($100 vs 100$).
    static var currencyPrefix: Bool {
        get { bool(currencyPrefixKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: currencyPrefixKey)
            NotificationCenter.default.post(name: .dopewarsPrefsChanged, object: nil)
        }
    }

    static func restoreGameRuleDefaults() {
        for key in gameRuleKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .dopewarsPrefsChanged, object: nil)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension NSView {
    /// Float a short piece of text (e.g. "−12") up from this view and fade.
    func dpFloatText(_ text: String, color: NSColor) {
        guard let host = window?.contentView else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .heavy)
        label.textColor = color
        label.sizeToFit()
        let anchor = host.convert(bounds, from: self)
        label.setFrameOrigin(NSPoint(x: anchor.midX - label.frame.width / 2,
                                     y: anchor.maxY - 6))
        host.addSubview(label)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.0
            label.animator().setFrameOrigin(NSPoint(x: label.frame.origin.x,
                                                    y: anchor.maxY + 26))
            label.animator().alphaValue = 0
        }, completionHandler: { label.removeFromSuperview() })
    }
}

/// Tiny inline trend line: recent samples as a polyline, with the last
/// point dotted green (up vs. the first sample) or red (down).
final class SparklineView: NSView {
    var values: [Int64] = [] { didSet { needsDisplay = true } }
    /// Fixed value range to scale against (e.g. a drug's normal price
    /// range), so line height tracks the absolute level. Without it the
    /// line is normalized to its own min/max, which only shows shape.
    var range: (lo: Int64, hi: Int64)? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance { self.drawSpark() }
        } else {
            drawSpark()
        }
    }

    private func drawSpark() {
        guard values.count >= 2 else { return }
        let r = bounds.insetBy(dx: 3, dy: 4)
        guard r.width > 0, r.height > 0 else { return }
        var lo = values.min()!
        var hi = values.max()!
        if let r = range {
            lo = min(lo, r.lo)
            hi = max(hi, r.hi)
        }
        let span = max(1, hi - lo)
        func pt(_ i: Int) -> NSPoint {
            NSPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: r.minY + r.height * CGFloat(values[i] - lo) / CGFloat(span))
        }
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.move(to: pt(0))
        for i in 1..<values.count { path.line(to: pt(i)) }
        NSColor.secondaryLabelColor.setStroke()
        path.stroke()
        let last = pt(values.count - 1)
        (values.last! >= values.first! ? NSColor.systemGreen : .systemRed).setFill()
        NSBezierPath(ovalIn: NSRect(x: last.x - 2.5, y: last.y - 2.5,
                                    width: 5, height: 5)).fill()
    }
}

/// Simple filled line chart used for the end-of-run net-worth graph.
final class LineChartView: NSView {
    var values: [Int64] = [] { didSet { needsDisplay = true } }
    /// Formats the final value annotation (typically engine.formatPrice).
    var format: ((Int64) -> String)?

    override func draw(_ dirtyRect: NSRect) {
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance { self.drawChart() }
        } else {
            drawChart()
        }
    }

    private func drawChart() {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        guard values.count >= 2 else { return }
        let r = NSRect(x: bounds.minX + 12, y: bounds.minY + 16,
                       width: bounds.width - 24, height: bounds.height - 30)
        let lo = min(values.min()!, 0)
        let hi = max(values.max()!, 1)
        let span = max(1, hi - lo)
        func pt(_ i: Int) -> NSPoint {
            NSPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: r.minY + r.height * CGFloat(values[i] - lo) / CGFloat(span))
        }

        if lo < 0 {
            let y = r.minY + r.height * CGFloat(0 - lo) / CGFloat(span)
            let base = NSBezierPath()
            base.move(to: NSPoint(x: r.minX, y: y))
            base.line(to: NSPoint(x: r.maxX, y: y))
            base.setLineDash([3, 3], count: 2, phase: 0)
            NSColor.tertiaryLabelColor.setStroke()
            base.stroke()
        }

        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: r.minX, y: r.minY))
        for i in 0..<values.count { fill.line(to: pt(i)) }
        fill.line(to: NSPoint(x: r.maxX, y: r.minY))
        fill.close()
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        fill.fill()

        let line = NSBezierPath()
        line.lineWidth = 2
        line.lineJoinStyle = .round
        line.move(to: pt(0))
        for i in 1..<values.count { line.line(to: pt(i)) }
        NSColor.controlAccentColor.setStroke()
        line.stroke()

        let last = pt(values.count - 1)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: last.x - 3, y: last.y - 3,
                                    width: 6, height: 6)).fill()

        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        "Day 1".draw(at: NSPoint(x: r.minX, y: bounds.minY + 3), withAttributes: small)
        let dayN = "Day \(values.count)"
        let ns = dayN.size(withAttributes: small)
        dayN.draw(at: NSPoint(x: r.maxX - ns.width, y: bounds.minY + 3),
                  withAttributes: small)

        if let fmt = format {
            let final = values.last!
            let s = fmt(final)
            let a: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: final >= 0 ? NSColor.systemGreen : NSColor.systemRed,
            ]
            let sz = s.size(withAttributes: a)
            var x = last.x - sz.width - 4
            x = max(bounds.minX + 4, min(x, bounds.maxX - sz.width - 4))
            var y = last.y + 4
            if y + sz.height > bounds.maxY - 2 { y = last.y - sz.height - 4 }
            s.draw(at: NSPoint(x: x, y: y), withAttributes: a)
        }
    }
}

/// A rounded "card" showing one stat: small icon + caption on top,
/// a value (or custom accessory view) underneath. Appearance-aware.
final class StatTile: NSView {
    let valueLabel = NSTextField(labelWithString: "")
    private let captionLabel: NSTextField

    /// Caption text; settable so name-dependent tiles (e.g. the
    /// family-friendly "escorts" wording) can follow preference changes.
    var caption: String {
        get { captionLabel.stringValue }
        set {
            captionLabel.stringValue = newValue
            iconView.image?.accessibilityDescription = newValue
        }
    }
    private let iconView = NSImageView()
    private let content: NSStackView

    init(symbol: String, caption: String, accessory: NSView? = nil) {
        captionLabel = NSTextField(labelWithString: caption)
        let top = NSStackView()
        content = NSStackView()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8

        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: caption) {
            iconView.image = img
            iconView.contentTintColor = .secondaryLabelColor
            iconView.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        }
        captionLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byTruncatingTail

        top.orientation = .horizontal
        top.spacing = 3
        top.addArrangedSubview(iconView)
        top.addArrangedSubview(captionLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.lineBreakMode = .byTruncatingTail

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 2
        content.addArrangedSubview(top)
        content.addArrangedSubview(accessory ?? valueLabel)

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor
    }

    /// Briefly tint the value (e.g. green for gains, red for losses).
    func flashValue(_ color: NSColor) {
        valueLabel.textColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self?.valueLabel.animator().textColor = .labelColor
            }
        }
    }

    /// Small horizontal shake (used when the player takes damage).
    func shake() {
        guard let layer = layer else { return }
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.values = [0, -5, 5, -4, 4, -2, 2, 0]
        anim.duration = 0.35
        layer.add(anim, forKey: "shake")
    }
}

/// Full-window overlay shown before a game starts and after game over.
final class WelcomeView: NSView, NSTextFieldDelegate {
    private let titleLabel = NSTextField(labelWithString: "Dope Wars")
    private let subtitleLabel = NSTextField(wrappingLabelWithString:
        "Buy low, sell high, dodge Officer Hardass,\nand pay off the loan shark — you have 31 days.")
    private let nameField = NSTextField(string: "")
    private let antiqueCheck = NSButton(checkboxWithTitle:
        "Antique mode (original Drug Wars rules)", target: nil, action: nil)
    private let startButton = NSButton(title: "Start Dealing", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let chartView = LineChartView()
    private var confetti: CAEmitterLayer?

    var onStart: ((String, Bool) -> Void)?

    private static let playerNameKey = "DopewarsPlayerName"

    /// While fading out, let clicks pass through to the game UI.
    var isDismissing = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isDismissing ? nil : super.hitTest(point)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        titleLabel.font = .systemFont(ofSize: 34, weight: .heavy)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .systemGreen
        statusLabel.alignment = .center
        // Finale narratives (e.g. the paraquat-weed death) run long.
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 4
        statusLabel.preferredMaxLayoutWidth = 480
        statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 480)
            .isActive = true

        // Prefill the last name used; fall back to the account's full name.
        let saved = UserDefaults.standard.string(forKey: Self.playerNameKey) ?? ""
        let user = saved.isEmpty ? NSFullUserName() : saved
        nameField.stringValue = user.isEmpty ? "Player" : user
        nameField.placeholderString = "Your dealer name"
        nameField.alignment = .center
        nameField.font = .systemFont(ofSize: 14)
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"
        startButton.target = self
        startButton.action = #selector(startTapped)
        if let img = NSImage(systemSymbolName: "play.fill",
                             accessibilityDescription: "Start") {
            startButton.image = img
            startButton.imagePosition = .imageLeading
        }

        chartView.isHidden = true
        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.widthAnchor.constraint(equalToConstant: 340).isActive = true
        chartView.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let stack = NSStackView(views: [icon, titleLabel, subtitleLabel, statusLabel,
                                        chartView, nameField, antiqueCheck, startButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    /// Set an optional status line (e.g. the game-over summary).
    func setStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = text.isEmpty
    }

    @objc private func startTapped() {
        let name = nameField.stringValue.isEmpty ? "Player" : nameField.stringValue
        UserDefaults.standard.set(name, forKey: Self.playerNameKey)
        onStart?(name, antiqueCheck.state == .on)
    }

    func focusName() {
        window?.makeFirstResponder(nameField)
    }

    /// Show (or clear, with an empty array) the finished run's net-worth
    /// graph above the name field.
    func showRun(_ values: [Int64], format: ((Int64) -> String)? = nil) {
        chartView.values = values
        chartView.format = format
        chartView.isHidden = values.count < 2
    }

    private static func confettiImage(_ color: NSColor) -> CGImage? {
        let size = NSSize(width: 8, height: 5)
        let img = NSImage(size: size)
        img.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                     xRadius: 1.5, yRadius: 1.5).fill()
        img.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Brief confetti burst for a run that made the high-score table.
    func celebrate() {
        wantsLayer = true
        confetti?.removeFromSuperlayer()
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height + 10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen,
                                 .systemYellow, .systemPurple, .systemOrange]
        emitter.emitterCells = colors.compactMap { color in
            guard let img = Self.confettiImage(color) else { return nil }
            let cell = CAEmitterCell()
            cell.contents = img
            cell.birthRate = 7
            cell.lifetime = 6
            cell.velocity = 180
            cell.velocityRange = 80
            cell.emissionLongitude = -.pi / 2      // falling (layer y is up)
            cell.emissionRange = .pi / 8
            cell.yAcceleration = -120
            cell.spin = 4
            cell.spinRange = 3
            cell.scale = 1
            cell.scaleRange = 0.4
            return cell
        }
        layer?.addSublayer(emitter)
        confetti = emitter
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak emitter] in
            emitter?.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak emitter] in
            emitter?.removeFromSuperlayer()
            if self?.confetti === emitter { self?.confetti = nil }
        }
    }
}

/// Transient travel overlay: "🚇 <DESTINATION>" over a subway map with the
/// route context — origin ringed, destination highlighted and pulsing.
/// Ignores clicks.
final class SubwayFlashView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let map = SubwayMapView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        // Force dark styling so the map reads well over the dark panel.
        appearance = NSAppearance(named: .darkAqua)

        label.font = .systemFont(ofSize: 22, weight: .black)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        map.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(map)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            map.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            map.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            map.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            map.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            map.widthAnchor.constraint(equalToConstant: 330),
            map.heightAnchor.constraint(equalToConstant: 260),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Flash the travel map centered in `host`, then remove.
    static func flash(names: [String], from origin: Int, to destination: Int,
                      in host: NSView) {
        let v = SubwayFlashView(frame: .zero)
        let name = (destination >= 0 && destination < names.count)
            ? names[destination] : ""
        v.label.stringValue = "🚇 \(name.uppercased())"
        v.map.locationNames = names
        v.map.current = destination
        v.map.origin = origin != destination ? origin : -1
        v.translatesAutoresizingMaskIntoConstraints = false
        v.alphaValue = 0
        host.addSubview(v)
        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            v.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
        host.layoutSubtreeIfNeeded()
        // Ride a little train along the route, then pulse the destination.
        if origin >= 0 && origin != destination {
            v.map.animateTrain(from: origin, to: destination) { [weak map = v.map] in
                map?.startPulse()
            }
        } else {
            v.map.startPulse()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            v.animator().alphaValue = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.4
                    v.animator().alphaValue = 0
                }, completionHandler: {
                    v.removeFromSuperview()
                })
            }
        })
    }
}
