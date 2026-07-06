import AppKit

/// Preferences: toggle the market-intel aids (trend sparklines, average
/// paid) and override the engine's game rules (length, starting money,
/// sanitized events). Game rules apply at the next new game.
final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {
    private let trendsCheck = NSButton(checkboxWithTitle: "Show drug price trends",
                                       target: nil, action: nil)
    private let avgCheck = NSButton(checkboxWithTitle: "Show average paid per drug",
                                    target: nil, action: nil)
    private let turnsField = NSTextField(string: "")
    private let cashField = NSTextField(string: "")
    private let debtField = NSTextField(string: "")
    private let debtInterestField = NSTextField(string: "")
    private let bankInterestField = NSTextField(string: "")
    private let spikeField = NSTextField(string: "")
    private let crashField = NSTextField(string: "")
    private let playerArmorField = NSTextField(string: "")
    private let escortArmorField = NSTextField(string: "")
    private let escortMinField = NSTextField(string: "")
    private let escortMaxField = NSTextField(string: "")
    private let startDayField = NSTextField(string: "")
    private let startMonthField = NSTextField(string: "")
    private let startYearField = NSTextField(string: "")
    private let difficultyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let currencyField = NSTextField(string: "")
    private let currencyPositionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sanitizedCheck = NSButton(checkboxWithTitle: "Sanitize random events",
                                          target: nil, action: nil)
    private let familyFriendlyCheck = NSButton(
        checkboxWithTitle: "Family-friendly wording", target: nil, action: nil)

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 845),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Preferences"
        w.center()
        self.init(window: w)
        build()
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Market intel")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        trendsCheck.target = self
        trendsCheck.action = #selector(toggled)
        trendsCheck.state = DopewarsPrefs.showTrends ? .on : .off
        let trendsHint = hint("Price history sparklines in the Market table.")

        avgCheck.target = self
        avgCheck.action = #selector(toggled)
        avgCheck.state = DopewarsPrefs.showAvgPaid ? .on : .off
        let avgHint = hint("What you paid on average, in the Market table "
                           + "and the sell popover's profit readout.")

        let note = NSTextField(wrappingLabelWithString:
            "Turn these off to play without market intel — harder, "
            + "like the original game.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        let gameTitle = NSTextField(labelWithString: "Game rules")
        gameTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        // (field, minimum, maximum) — nil max means unbounded.
        let fieldSpecs: [(NSTextField, Int, Int?)] = [
            (turnsField, 0, nil),
            (cashField, 0, nil),
            (debtField, 0, nil),
            (debtInterestField, -100, 1000),
            (bankInterestField, -100, 1000),
            (spikeField, 1, 1000),
            (crashField, 1, 1000),
            (playerArmorField, 0, 100),
            (escortArmorField, 1, 100),
            (escortMinField, 0, nil),
            (escortMaxField, 0, nil),
            (startDayField, 1, 31),
            (startMonthField, 1, 12),
            (startYearField, 0, 9999),
        ]
        for (field, minVal, maxVal) in fieldSpecs {
            let fmt = NumberFormatter()
            fmt.numberStyle = .none
            fmt.minimum = NSNumber(value: minVal)
            if let maxVal { fmt.maximum = NSNumber(value: maxVal) }
            field.formatter = fmt
            field.delegate = self
            let width: CGFloat = (field === startDayField
                                  || field === startMonthField) ? 36 : 80
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        let dateStack = NSStackView(views: [startDayField, startMonthField,
                                            startYearField])
        dateStack.orientation = .horizontal
        dateStack.spacing = 4

        difficultyPopup.addItems(withTitles: ["Easy", "Normal", "Hard"])
        difficultyPopup.target = self
        difficultyPopup.action = #selector(toggled)

        currencyField.delegate = self
        currencyField.widthAnchor.constraint(equalToConstant: 40).isActive = true
        currencyPositionPopup.addItems(withTitles: ["before amount", "after amount"])
        currencyPositionPopup.target = self
        currencyPositionPopup.action = #selector(toggled)
        let currencyStack = NSStackView(views: [currencyField,
                                                currencyPositionPopup])
        currencyStack.orientation = .horizontal
        currencyStack.spacing = 4
        let grid = NSGridView(views: [
            [gridLabel("Difficulty:"), difficultyPopup,
             hint("scales police presence and cop squads")],
            [gridLabel("Game length:"), turnsField,
             hint("days (0 = never ends)")],
            [gridLabel("Starting cash:"), cashField, hint("$")],
            [gridLabel("Starting debt:"), debtField, hint("$")],
            [gridLabel("Debt interest:"), debtInterestField,
             hint("% per day, charged by the loan shark")],
            [gridLabel("Bank interest:"), bankInterestField,
             hint("% per day, earned on your balance")],
            [gridLabel("Price spikes:"), spikeField,
             hint("× multiplier on \"expensive\" drug events")],
            [gridLabel("Price crashes:"), crashField,
             hint("÷ divider on \"cheap\" drug events")],
            [gridLabel("Your armor:"), playerArmorField,
             hint("% gunshot resistance (lower = harder fights)")],
            [gridLabel("Escort armor:"), escortArmorField,
             hint("% gunshot resistance of your escorts")],
            [gridLabel("Escort hire, min:"), escortMinField, hint("$")],
            [gridLabel("Escort hire, max:"), escortMaxField, hint("$")],
            [gridLabel("Start date:"), dateStack,
             hint("day / month / year of day 1")],
            [gridLabel("Currency:"), currencyStack,
             hint("symbol on prices; applies immediately")],
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8

        sanitizedCheck.target = self
        sanitizedCheck.action = #selector(toggled)
        let sanitizedHint = hint("Tones down the nastier random events.")

        familyFriendlyCheck.target = self
        familyFriendlyCheck.action = #selector(toggled)
        let familyFriendlyHint = hint("News log and stats show \"escort\" "
                                      + "instead of the original wording.")

        let restoreButton = NSButton(title: "Restore Defaults", target: self,
                                     action: #selector(restoreDefaults))

        let gameNote = NSTextField(wrappingLabelWithString:
            "Game rules take effect when you start a new game. High scores "
            + "from games with non-default rules aren't really comparable.")
        gameNote.font = .systemFont(ofSize: 11)
        gameNote.textColor = .secondaryLabelColor

        refreshGameControls()

        let stack = NSStackView(views: [title, trendsCheck, trendsHint,
                                        avgCheck, avgHint, note,
                                        gameTitle, grid,
                                        sanitizedCheck, sanitizedHint,
                                        familyFriendlyCheck, familyFriendlyHint,
                                        restoreButton, gameNote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: title)
        stack.setCustomSpacing(12, after: trendsHint)
        stack.setCustomSpacing(16, after: avgHint)
        stack.setCustomSpacing(24, after: note)
        stack.setCustomSpacing(12, after: gameTitle)
        stack.setCustomSpacing(12, after: grid)
        stack.setCustomSpacing(12, after: sanitizedHint)
        stack.setCustomSpacing(12, after: familyFriendlyHint)
        stack.setCustomSpacing(12, after: restoreButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            content.bottomAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor,
                                            constant: 16),
        ])
    }

    private func hint(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func gridLabel(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func refreshGameControls() {
        turnsField.integerValue = DopewarsPrefs.gameTurns
        cashField.integerValue = Int(DopewarsPrefs.startCash)
        debtField.integerValue = Int(DopewarsPrefs.startDebt)
        debtInterestField.integerValue = DopewarsPrefs.debtInterest
        bankInterestField.integerValue = DopewarsPrefs.bankInterest
        spikeField.integerValue = DopewarsPrefs.expensiveMultiply
        crashField.integerValue = DopewarsPrefs.cheapDivide
        playerArmorField.integerValue = DopewarsPrefs.playerArmor
        escortArmorField.integerValue = DopewarsPrefs.bitchArmor
        escortMinField.integerValue = Int(DopewarsPrefs.bitchMinPrice)
        escortMaxField.integerValue = Int(DopewarsPrefs.bitchMaxPrice)
        startDayField.integerValue = DopewarsPrefs.startDay
        startMonthField.integerValue = DopewarsPrefs.startMonth
        startYearField.integerValue = DopewarsPrefs.startYear
        difficultyPopup.selectItem(at: DopewarsPrefs.difficulty)
        currencyField.stringValue = DopewarsPrefs.currencySymbol
        currencyPositionPopup.selectItem(at: DopewarsPrefs.currencyPrefix ? 0 : 1)
        sanitizedCheck.state = DopewarsPrefs.sanitized ? .on : .off
        familyFriendlyCheck.state = DopewarsPrefs.familyFriendly ? .on : .off
    }

    private func saveGameFields() {
        // An emptied field keeps its previous value rather than becoming 0.
        func save(_ field: NSTextField, _ store: (Int) -> Void) {
            if !field.stringValue.isEmpty { store(field.integerValue) }
        }
        save(turnsField) { DopewarsPrefs.gameTurns = $0 }
        save(cashField) { DopewarsPrefs.startCash = Int64($0) }
        save(debtField) { DopewarsPrefs.startDebt = Int64($0) }
        save(debtInterestField) { DopewarsPrefs.debtInterest = $0 }
        save(bankInterestField) { DopewarsPrefs.bankInterest = $0 }
        save(spikeField) { DopewarsPrefs.expensiveMultiply = $0 }
        save(crashField) { DopewarsPrefs.cheapDivide = $0 }
        save(playerArmorField) { DopewarsPrefs.playerArmor = $0 }
        save(escortArmorField) { DopewarsPrefs.bitchArmor = $0 }
        save(escortMinField) { DopewarsPrefs.bitchMinPrice = Int64($0) }
        save(escortMaxField) { DopewarsPrefs.bitchMaxPrice = Int64($0) }
        save(startDayField) { DopewarsPrefs.startDay = $0 }
        save(startMonthField) { DopewarsPrefs.startMonth = $0 }
        save(startYearField) { DopewarsPrefs.startYear = $0 }
        let symbol = currencyField.stringValue.trimmingCharacters(in: .whitespaces)
        if !symbol.isEmpty && symbol != DopewarsPrefs.currencySymbol {
            DopewarsPrefs.currencySymbol = symbol
        }
        refreshGameControls()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        saveGameFields()
    }

    @objc private func toggled() {
        DopewarsPrefs.showTrends = trendsCheck.state == .on
        DopewarsPrefs.showAvgPaid = avgCheck.state == .on
        DopewarsPrefs.sanitized = sanitizedCheck.state == .on
        DopewarsPrefs.familyFriendly = familyFriendlyCheck.state == .on
        DopewarsPrefs.difficulty = difficultyPopup.indexOfSelectedItem
        let prefix = currencyPositionPopup.indexOfSelectedItem == 0
        if prefix != DopewarsPrefs.currencyPrefix {
            DopewarsPrefs.currencyPrefix = prefix
        }
    }

    @objc private func restoreDefaults() {
        window?.makeFirstResponder(nil)   // commit any in-progress edit first
        DopewarsPrefs.restoreGameRuleDefaults()
        refreshGameControls()
    }
}

/// Sheet that lets the player pick a destination to jet to.
final class LocationPicker: NSWindowController {
    private let engine: GameEngine
    private let onPick: (Int) -> Void

    init(engine: GameEngine, onPick: @escaping (Int) -> Void) {
        self.engine = engine
        self.onPick = onPick
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Where to?"
        super.init(window: w)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "Where to, dude? Click a station.")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let map = SubwayMapView()
        map.locationNames = engine.locations
        map.current = engine.location
        map.onSelect = { [weak self] i in
            guard let self = self else { return }
            if i != self.engine.location {
                self.onPick(i)
                self.dismiss()
            }
        }
        map.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "Stay here", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [title, map, cancel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            map.widthAnchor.constraint(equalToConstant: 340),
            map.heightAnchor.constraint(equalToConstant: 300),
        ])
    }

    @objc private func cancel() { dismiss() }

    private func dismiss() {
        if let sheet = window { sheet.sheetParent?.endSheet(sheet) }
        window?.orderOut(nil)
    }
}

/// Sheet for Dan's House of Guns.
final class GunShopController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let engine: GameEngine
    private let onDone: () -> Void
    private let table = NSTableView()
    private let cashLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var rows: [GunInfo] = []

    init(engine: GameEngine, onDone: @escaping () -> Void) {
        self.engine = engine
        self.onDone = onDone
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Dan's House of Guns"
        super.init(window: w)
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        cashLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        for (id, title, width) in [("gun", "Gun", 170), ("price", "Price", 110),
                                    ("space", "Space", 60), ("held", "Held", 50)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = CGFloat(width)
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let buy = NSButton(title: "Buy", target: self, action: #selector(buy))
        let sell = NSButton(title: "Sell", target: self, action: #selector(sell))
        let leave = NSButton(title: "Leave", target: self, action: #selector(leave))
        for b in [buy, sell, leave] { b.bezelStyle = .rounded }
        leave.keyEquivalent = "\r"
        let buttons = NSStackView(views: [buy, sell, NSView(), leave])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .systemRed

        let root = NSStackView(views: [cashLabel, scroll, statusLabel, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 210),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func reload() {
        rows = engine.guns
        cashLabel.stringValue = "Cash: \(engine.formatPrice(engine.cash))   ·   Space free: \(engine.spaceFree)"
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let g = rows[row]
        let f = NSTextField(labelWithString: "")
        f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        switch tableColumn?.identifier.rawValue {
        case "gun": f.stringValue = g.name
        case "price": f.stringValue = engine.formatPrice(g.price)
        case "space": f.stringValue = "\(g.space)"
        case "held": f.stringValue = g.carried > 0 ? "\(g.carried)" : ""
        default: break
        }
        return f
    }

    private func fail(_ message: String) {
        NSSound.beep()
        statusLabel.stringValue = message
    }

    @objc private func buy() {
        let r = table.selectedRow
        guard r >= 0 else { fail("Select something to buy."); return }
        let g = rows[r]
        // Mirror the server's BuyObject checks so refusals are explained
        // rather than silently ignored.
        guard engine.cash >= g.price else {
            fail("You can't afford that!"); return
        }
        guard engine.spaceFree >= g.space else {
            fail("You don't have enough space to carry that."); return
        }
        guard engine.totalGuns + 1 <= engine.bitches + 2 else {
            fail("You can't carry any more \(engine.gunsName) — hire more \(engine.bitchesName)."); return
        }
        let before = engine.totalGuns
        engine.buyGun(g.index, amount: 1)
        if engine.totalGuns > before {
            statusLabel.stringValue = ""
        } else {
            fail("The dealer won't sell you that right now.")
        }
        reload()
    }

    @objc private func sell() {
        let r = table.selectedRow
        guard r >= 0 else { fail("Select something to sell."); return }
        let g = rows[r]
        guard g.carried > 0 else { fail("You aren't carrying one of those."); return }
        engine.buyGun(g.index, amount: -1)
        statusLabel.stringValue = ""
        reload()
    }

    @objc private func leave() {
        if let sheet = window { sheet.sheetParent?.endSheet(sheet) }
        window?.orderOut(nil)
        onDone()
    }
}

/// What a trade popover is doing.
enum TradeMode {
    case buy, sell, drop

    var verb: String {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .drop: return "Drop"
        }
    }
}

/// Popover content for buying/selling/dropping a drug: slider + amount
/// field + Max button with a live cost readout.
final class TradeViewController: NSViewController, NSTextFieldDelegate {
    private let mode: TradeMode
    private let drug: DrugInfo
    private let maxAmount: Int
    private let engine: GameEngine
    private let onCommit: (Int) -> Void

    private let slider = NSSlider(value: 0, minValue: 1, maxValue: 1,
                                  target: nil, action: nil)
    private let amountField = NSTextField(string: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let commitButton = NSButton(title: "", target: nil, action: nil)

    init(mode: TradeMode, drug: DrugInfo, maxAmount: Int, engine: GameEngine,
         onCommit: @escaping (Int) -> Void) {
        self.mode = mode
        self.drug = drug
        self.maxAmount = maxAmount
        self.engine = engine
        self.onCommit = onCommit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let title = NSTextField(labelWithString: {
            switch mode {
            case .buy:
                return "Buy \(drug.name) @ \(engine.formatPrice(drug.price))"
            case .sell:
                return "Sell \(drug.name) @ \(engine.formatPrice(drug.price))"
            case .drop:
                return "Drop worthless \(drug.name)"
            }
        }())
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        slider.minValue = 1
        slider.maxValue = Double(maxAmount)
        slider.integerValue = maxAmount
        slider.allowsTickMarkValuesOnly = maxAmount <= 40
        slider.numberOfTickMarks = maxAmount <= 40 ? maxAmount : 0
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true

        amountField.stringValue = "\(maxAmount)"
        amountField.alignment = .right
        amountField.delegate = self
        amountField.translatesAutoresizingMaskIntoConstraints = false
        amountField.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let maxButton = NSButton(title: "Max", target: self, action: #selector(maxTapped))
        maxButton.bezelStyle = .rounded

        commitButton.title = mode.verb
        commitButton.bezelStyle = .rounded
        commitButton.keyEquivalent = "\r"
        commitButton.target = self
        commitButton.action = #selector(commitTapped)

        totalLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        totalLabel.textColor = .secondaryLabelColor

        let controls = NSStackView(views: [slider, amountField, maxButton])
        controls.orientation = .horizontal
        controls.spacing = 8

        let bottom = NSStackView(views: [totalLabel, NSView(), commitButton])
        bottom.orientation = .horizontal
        bottom.spacing = 8

        let root = NSStackView(views: [title, controls, bottom])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
        ])
        view = container
        updateTotal()
    }

    private var amount: Int {
        max(1, min(maxAmount, Int(amountField.stringValue) ?? maxAmount))
    }

    private func updateTotal() {
        let n = amount
        switch mode {
        case .buy:
            let cost = Int64(n) * drug.price
            totalLabel.stringValue = "\(n) × \(engine.formatPrice(drug.price)) = \(engine.formatPrice(cost))"
        case .sell:
            let value = Int64(n) * drug.price
            var s = "\(n) × \(engine.formatPrice(drug.price)) = \(engine.formatPrice(value))"
            if DopewarsPrefs.showAvgPaid, let avg = drug.avgPaid {
                let profit = value - Int64(n) * avg
                s += profit >= 0 ? "  (+\(engine.formatPrice(profit)))"
                                 : "  (\(engine.formatPrice(profit)))"
            }
            totalLabel.stringValue = s
        case .drop:
            totalLabel.stringValue = "Dropping \(n) of \(drug.carried) carried"
        }
    }

    @objc private func sliderMoved() {
        amountField.stringValue = "\(slider.integerValue)"
        updateTotal()
    }

    @objc private func maxTapped() {
        amountField.stringValue = "\(maxAmount)"
        slider.integerValue = maxAmount
        updateTotal()
    }

    @objc private func commitTapped() {
        onCommit(amount)
    }

    func controlTextDidChange(_ obj: Notification) {
        slider.integerValue = amount
        updateTotal()
    }
}

/// Shared amount-entry row (slider + field + Max) used by the bank and
/// loan shark sheets.
final class AmountRow: NSView, NSTextFieldDelegate {
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1,
                                  target: nil, action: nil)
    private let field = NSTextField(string: "")
    private var maximum: Int64 = 0
    var onChange: (() -> Void)?

    init(width: CGFloat = 200) {
        super.init(frame: .zero)
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.alignment = .right
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let maxBtn = NSButton(title: "Max", target: self, action: #selector(maxTapped))
        maxBtn.bezelStyle = .rounded
        let row = NSStackView(views: [slider, field, maxBtn])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    var amount: Int64 {
        max(0, min(maximum, Int64(field.stringValue) ?? 0))
    }

    func setMaximum(_ m: Int64, preset: Int64? = nil) {
        maximum = max(0, m)
        slider.maxValue = Double(maximum)
        let v = min(maximum, preset ?? maximum)
        slider.doubleValue = Double(v)
        field.stringValue = "\(v)"
        onChange?()
    }

    @objc private func sliderMoved() {
        field.stringValue = "\(Int64(slider.doubleValue))"
        onChange?()
    }

    @objc private func maxTapped() {
        slider.doubleValue = slider.maxValue
        field.stringValue = "\(maximum)"
        onChange?()
    }

    func controlTextDidChange(_ obj: Notification) {
        slider.doubleValue = Double(amount)
        onChange?()
    }
}

/// The bank: deposit/withdraw repeatedly, then leave (sends C_DONE once).
final class BankSheetController: NSWindowController {
    private let engine: GameEngine
    private let onDone: () -> Void
    private let balanceLabel = NSTextField(labelWithString: "")
    private let amountRow = AmountRow()

    init(engine: GameEngine, onDone: @escaping () -> Void) {
        self.engine = engine
        self.onDone = onDone
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Bank"
        super.init(window: w)
        build()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "🏦 The Bank")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        balanceLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let deposit = NSButton(title: "Deposit", target: self, action: #selector(depositTapped))
        let withdraw = NSButton(title: "Withdraw", target: self, action: #selector(withdrawTapped))
        let leave = NSButton(title: "Leave", target: self, action: #selector(leaveTapped))
        for b in [deposit, withdraw, leave] { b.bezelStyle = .rounded }
        leave.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [deposit, withdraw, NSView(), leave])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let root = NSStackView(views: [title, balanceLabel, amountRow, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func refresh() {
        balanceLabel.stringValue =
            "Cash \(engine.formatPrice(engine.cash))   ·   Balance \(engine.formatPrice(engine.bank))"
        amountRow.setMaximum(max(engine.cash, engine.bank),
                             preset: min(engine.cash, max(engine.cash, engine.bank)))
    }

    @objc private func depositTapped() {
        let amt = min(amountRow.amount, engine.cash)
        if amt > 0 { engine.bankDeposit(amt) }
        refresh()
    }

    @objc private func withdrawTapped() {
        let amt = min(amountRow.amount, engine.bank)
        if amt > 0 { engine.bankDeposit(-amt) }
        refresh()
    }

    @objc private func leaveTapped() {
        if let sheet = window { sheet.sheetParent?.endSheet(sheet) }
        window?.orderOut(nil)
        onDone()
    }
}

/// The loan shark: pay down debt, then leave (sends C_DONE once).
final class LoanSharkController: NSWindowController {
    private let engine: GameEngine
    private let onDone: () -> Void
    private let debtLabel = NSTextField(labelWithString: "")
    private let amountRow = AmountRow()

    init(engine: GameEngine, onDone: @escaping () -> Void) {
        self.engine = engine
        self.onDone = onDone
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Loan Shark"
        super.init(window: w)
        build()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "🦈 The Loan Shark")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        debtLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let pay = NSButton(title: "Pay Back", target: self, action: #selector(payTapped))
        let leave = NSButton(title: "Leave", target: self, action: #selector(leaveTapped))
        for b in [pay, leave] { b.bezelStyle = .rounded }
        pay.keyEquivalent = "\r"
        leave.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [pay, NSView(), leave])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let root = NSStackView(views: [title, debtLabel, amountRow, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func refresh() {
        debtLabel.stringValue =
            "You owe \(engine.formatPrice(engine.debt))   ·   Cash \(engine.formatPrice(engine.cash))"
        amountRow.setMaximum(min(engine.debt, engine.cash))
    }

    @objc private func payTapped() {
        let amt = min(amountRow.amount, min(engine.debt, engine.cash))
        if amt > 0 { engine.payLoan(amt) }
        refresh()
        if engine.debt == 0 { leaveTapped() }
    }

    @objc private func leaveTapped() {
        if let sheet = window { sheet.sheetParent?.endSheet(sheet) }
        window?.orderOut(nil)
        onDone()
    }
}

/// High score table in a fixed-size window sized to its content, with the
/// player's own score emphasized.
final class HighScoresWindowController: NSWindowController {
    private let titleLabel = NSTextField(labelWithString: "High Scores")
    private let scoresLabel = NSTextField(labelWithString: "")

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "High Scores"
        w.center()
        self.init(window: w)
        build()
    }

    private func build() {
        guard let content = window?.contentView else { return }
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        scoresLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scoresLabel.maximumNumberOfLines = 0

        let root = NSStackView(views: [titleLabel, scoresLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
    }

    /// One parsed score row. The server pads lines to fixed columns
    /// ("%18s  %-14s %-34s %8s"), which wraps and leaves a huge gap before
    /// "(R.I.P.)"; we re-format to the actual content widths instead.
    private struct ScoreRow {
        let money: String
        let date: String
        let name: String
        let note: String   // "(R.I.P.)" or empty
        let own: Bool
    }

    private func parse(_ raw: String, own: Bool) -> ScoreRow? {
        // Strip the emphasis marker pair ('>' … '<') the server adds
        // around the player's own line, then slice the fixed columns.
        var chars = Array(raw)
        if chars.first == ">" || chars.first == " " { chars.removeFirst() }
        if chars.last == "<" { chars.removeLast() }
        guard chars.count >= 69 else { return nil }
        func slice(_ r: Range<Int>) -> String {
            String(chars[r.clamped(to: 0..<chars.count)])
                .trimmingCharacters(in: .whitespaces)
        }
        return ScoreRow(money: slice(0..<18),
                        date: slice(20..<34),
                        name: slice(35..<69),
                        note: slice(69..<min(chars.count, 78)),
                        own: own)
    }

    func setScores(_ scores: [(text: String, own: Bool)], gameOver: Bool) {
        titleLabel.stringValue = gameOver ? "Game Over — High Scores" : "High Scores"

        var rows: [ScoreRow] = []
        var rawFallback: [(String, Bool)] = []
        for (line, own) in scores {
            if let row = parse(line, own: own) {
                rows.append(row)
            } else {
                rawFallback.append((line, own))
            }
        }

        // The engine keeps 18 scores; show them all. A non-qualifying
        // final score is appended by the server beyond the table — show
        // it unranked ("—") rather than inventing a 19th place.
        let tableSize = 18
        let display: [(rank: String, row: ScoreRow)] =
            rows.enumerated().map { i, row in
                (i < tableSize ? "\(i + 1)." : "—", row)
            }

        // Compact columns sized to the longest displayed value.
        let shown = display.map { $0.row }
        let moneyW = shown.map { $0.money.count }.max() ?? 0
        let nameW = shown.map { $0.name.count }.max() ?? 0
        let dateW = shown.map { $0.date.count }.max() ?? 0

        // Breathing room between rows.
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 7

        let out = NSMutableAttributedString()
        func attrs(_ own: Bool) -> [NSAttributedString.Key: Any] {
            let base: [NSAttributedString.Key: Any] = own
                ? [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                   .foregroundColor: NSColor.systemGreen]
                : [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                   .foregroundColor: NSColor.labelColor]
            return base.merging([.paragraphStyle: para]) { a, _ in a }
        }
        func pad(_ s: String, _ w: Int, right: Bool = false) -> String {
            let fill = String(repeating: " ", count: max(0, w - s.count))
            return right ? fill + s : s + fill
        }
        let rankW = (display.map { $0.rank.count }.max() ?? 3) + 1
        for entry in display {
            let r = entry.row
            let line = "\(pad(entry.rank, rankW))\(pad(r.money, moneyW, right: true))  " +
                       "\(pad(r.name, nameW))  \(pad(r.date, dateW))" +
                       (r.note.isEmpty ? "" : "  \(r.note)")
            out.append(NSAttributedString(string: line + "\n", attributes: attrs(r.own)))
        }
        for (line, own) in rawFallback {
            out.append(NSAttributedString(string: line + "\n", attributes: attrs(own)))
        }
        scoresLabel.attributedStringValue = out

        // Fix the window size to exactly fit the content, with comfortable
        // margins around the table.
        window?.contentView?.layoutSubtreeIfNeeded()
        let title = titleLabel.fittingSize
        let body = scoresLabel.fittingSize
        let width = max(title.width, body.width) + 52
        let height = title.height + 14 + body.height + 44
        window?.setContentSize(NSSize(width: width, height: height))
    }
}
