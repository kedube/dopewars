import AppKit

/// The main game window: location strip, status header with health/turn
/// indicators, drug market + inventory tables, inline prompt bar, fight
/// HUD, and a scrolling news log.
final class GameWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private let engine = GameEngine.shared

    // MARK: Controls (internal so the headless UI auto-test can drive them)

    let locationStrip = NSSegmentedControl()

    private let nameLabel = makeStat()
    private let dateLabel = makeStat()
    private let cashTile = StatTile(symbol: "dollarsign.circle", caption: "CASH")
    private let bankTile = StatTile(symbol: "building.columns", caption: "BANK")
    private let debtTile = StatTile(symbol: "creditcard", caption: "DEBT")
    private let netValueLabel = NSTextField(labelWithString: "")
    private let netSpark = SparklineView()
    private lazy var netTile: StatTile = {
        netValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        netValueLabel.lineBreakMode = .byTruncatingTail
        netSpark.translatesAutoresizingMaskIntoConstraints = false
        netSpark.widthAnchor.constraint(equalToConstant: 46).isActive = true
        netSpark.heightAnchor.constraint(equalToConstant: 15).isActive = true
        let row = NSStackView(views: [netValueLabel, netSpark])
        row.orientation = .horizontal
        row.spacing = 4
        return StatTile(symbol: "chart.line.uptrend.xyaxis", caption: "NET WORTH",
                        accessory: row)
    }()
    private let spaceTile = StatTile(symbol: "bag", caption: "SPACE")
    private var bitchesTile: StatTile!
    private var healthTile: StatTile!
    private var timeTile: StatTile!
    private let healthBar = NSLevelIndicator()
    private let healthLabel = makeStat()
    private let turnBar = NSLevelIndicator()
    private let turnLabel = makeStat()
    private let locationLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 20, weight: .bold)
        return l
    }()

    // Welcome overlay + delta tracking for feedback flashes
    private var welcomeView: WelcomeView?
    private var lastCash: Int64?
    private var lastHealth: Int?
    // Where we jetted from, for the travel-map overlay.
    private var lastLocation = -1

    // Always-visible mini map in the sidebar (click a station to jet).
    let miniMap = SubwayMapView()

    // Per-day histories: drug prices seen (for the trend sparklines) and
    // net worth (for the end-of-run chart). Sampled once per game day.
    private var priceHistory: [Int: [Int64]] = [:]
    private var netWorthHistory: [Int64] = []
    private var lastRecordedTurn: Int?
    private var warnedLastDay = false

    // Fight damage tracking for floating numbers / bar animation.
    private var lastEnemyHealth: Int?
    private var lastEnemyName = ""

    // Right-click trade menu state.
    private let drugMenu = NSMenu()
    private var menuRow = -1

    private weak var muteToolbarItem: NSToolbarItem?
    private weak var themeMenu: NSMenu?

    let drugTable = NSTableView()
    let gunTable = NSTableView()
    let logView = NSTextView()

    let buyButton = NSButton(title: "Buy", target: nil, action: nil)
    let sellButton = NSButton(title: "Sell", target: nil, action: nil)
    let dropButton = NSButton(title: "Drop", target: nil, action: nil)
    let jetButton = NSButton(title: "Jet ✈", target: nil, action: nil)

    // Inline prompt bar (replaces question alert sheets)
    let promptBox = NSBox()
    let promptLabel = NSTextField(wrappingLabelWithString: "")
    private let promptButtonRow = NSStackView()
    private var promptAllowed: [Character] = []

    // Fight HUD
    let fightBox = NSBox()
    private let fightStatusLabel = NSTextField(labelWithString: "")
    private let enemyHealthBar = NSLevelIndicator()
    let fightFireButton = NSButton(title: "Fight 🔫", target: nil, action: nil)
    let fightStandButton = NSButton(title: "Stand", target: nil, action: nil)
    let fightRunButton = NSButton(title: "Run 🏃", target: nil, action: nil)
    let fightDealButton = NSButton(title: "Deal drugs", target: nil, action: nil)

    private var drugRows: [DrugInfo] = []
    private var gunRows: [GunInfo] = []
    private var tablesCapConstraint: NSLayoutConstraint?
    private var tablesPrefConstraint: NSLayoutConstraint?
    private var refreshScheduled = false
    private var pendingHiscores: [(text: String, own: Bool)] = []
    /// Most recent engine print; at game over this holds the finale
    /// narrative (e.g. how you died) plus the high-score commentary.
    private var lastPrintMessage = ""
    private var hiscoresWindow: HighScoresWindowController?
    private var tradePopover: NSPopover?
    private var keyMonitor: Any?
    var retainSheet: NSWindowController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Dope Wars"
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        self.init(window: window)
        window.setFrameAutosaveName("DopewarsMainWindow")
        buildUI()
        setupToolbar(on: window)
        wireEngine()
        installKeyMonitor()
        showWelcome(status: "")
        NotificationCenter.default.addObserver(self, selector: #selector(muteChanged),
                                               name: .dopewarsMuteChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: .dopewarsPrefsChanged, object: nil)
        applyColumnPrefs()
    }

    /// Re-apply live-effect preferences: market-intel columns and the
    /// currency used on displayed prices.
    @objc private func prefsChanged() {
        engine.setCurrency(symbol: DopewarsPrefs.currencySymbol,
                           prefix: DopewarsPrefs.currencyPrefix)
        applyColumnPrefs()
        drugTable.reloadData()
        scheduleRefresh()
    }

    private func applyColumnPrefs() {
        drugTable.tableColumn(withIdentifier: .init("trend"))?.isHidden =
            !DopewarsPrefs.showTrends
        drugTable.tableColumn(withIdentifier: .init("avg"))?.isHidden =
            !DopewarsPrefs.showAvgPaid
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "DopewarsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
    }

    // MARK: UI construction

    private static func makeStat() -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        return l
    }

    private func labeled(_ caption: String, _ view: NSView) -> NSStackView {
        let cap = NSTextField(labelWithString: caption)
        cap.font = .systemFont(ofSize: 11, weight: .semibold)
        cap.textColor = .secondaryLabelColor
        let s = NSStackView(views: [cap, view])
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 1
        return s
    }

    /// NSBox whose content is pinned properly (an unpinned autolayout
    /// contentView leaves the box zero-height and unclickable).
    private func pinned(into box: NSBox, _ view: NSView) {
        box.titlePosition = .noTitle
        view.translatesAutoresizingMaskIntoConstraints = false
        if let inner = box.contentView {
            inner.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 10),
                view.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -10),
                view.topAnchor.constraint(equalTo: inner.topAnchor, constant: 8),
                view.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -8),
            ])
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // ---- Location strip ----
        locationStrip.target = self
        locationStrip.action = #selector(locationPicked)
        locationStrip.segmentDistribution = .fillEqually
        locationStrip.controlSize = .small
        locationStrip.font = .systemFont(ofSize: 11)

        // ---- Header ----
        healthBar.levelIndicatorStyle = .continuousCapacity
        healthBar.minValue = 0; healthBar.maxValue = 100
        healthBar.warningValue = 40; healthBar.criticalValue = 25
        healthBar.translatesAutoresizingMaskIntoConstraints = false
        healthBar.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let healthStack = NSStackView(views: [healthBar, healthLabel])
        healthStack.orientation = .horizontal
        healthStack.spacing = 6

        turnBar.levelIndicatorStyle = .continuousCapacity
        turnBar.minValue = 0
        turnBar.translatesAutoresizingMaskIntoConstraints = false
        turnBar.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let turnStack = NSStackView(views: [turnBar, turnLabel])
        turnStack.orientation = .horizontal
        turnStack.spacing = 6

        bitchesTile = StatTile(symbol: "person.2", caption: engine.bitchesName.uppercased())
        healthTile = StatTile(symbol: "heart", caption: "HEALTH", accessory: healthStack)
        timeTile = StatTile(symbol: "calendar", caption: "TIME", accessory: turnStack)

        let statsRow = NSStackView(views: [cashTile, bankTile, debtTile, netTile,
                                           spaceTile, bitchesTile, healthTile, timeTile])
        statsRow.orientation = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 8

        let topRow = NSStackView(views: [locationLabel, NSView(),
                                         labeled("Dealer", nameLabel),
                                         labeled("Date", dateLabel)])
        topRow.orientation = .horizontal
        topRow.spacing = 24

        let header = NSStackView(views: [topRow, statsRow])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 6, right: 14)

        // ---- Tables ----
        configureTable(drugTable, columns: [
            ("drug", engine.drugsName.capitalized, 130),
            ("price", "Price", 100),
            ("trend", "Trend", 58),
            ("carried", "Held", 50),
            ("avg", "Avg paid", 80),
        ])
        drugMenu.delegate = self
        drugTable.menu = drugMenu
        let drugScroll = wrap(drugTable)
        configureTable(gunTable, columns: [
            ("gun", engine.gunsName.capitalized, 110),
            ("price", "Price", 90),
            ("space", "Space", 50),
            ("carried", "Held", 45),
        ])
        let gunScroll = wrap(gunTable)

        let marketTitle = sectionTitle("Market — double-click to trade")
        let gunTitle = sectionTitle("Inventory — \(engine.gunsName)")

        let leftCol = NSStackView(views: [marketTitle, drugScroll])
        leftCol.orientation = .vertical
        leftCol.alignment = .leading
        leftCol.spacing = 4
        let mapTitle = sectionTitle("City map — click to jet")
        miniMap.compact = true
        miniMap.translatesAutoresizingMaskIntoConstraints = false
        miniMap.onSelect = { [weak self] i in
            guard let self = self, self.jetButton.isEnabled,
                  self.promptBox.isHidden, self.welcomeView == nil,
                  i != self.engine.location else { return }
            self.engine.jet(to: i)
        }

        let rightCol = NSStackView(views: [gunTitle, gunScroll, mapTitle, miniMap])
        rightCol.orientation = .vertical
        rightCol.alignment = .leading
        rightCol.spacing = 4

        let tables = NSStackView(views: [leftCol, rightCol])
        tables.orientation = .horizontal
        tables.spacing = 12
        // Fill the pinned width; the leftCol:rightCol ratio constraint
        // then determines each column's share. (The default .gravityAreas
        // clusters the columns at minimal width, clipping the tables.)
        tables.distribution = .fill

        // ---- Prompt bar ----
        promptLabel.font = .systemFont(ofSize: 13, weight: .medium)
        promptButtonRow.orientation = .horizontal
        promptButtonRow.spacing = 8
        let promptRow = NSStackView(views: [promptLabel, NSView(), promptButtonRow])
        promptRow.orientation = .horizontal
        promptRow.spacing = 12
        pinned(into: promptBox, promptRow)
        promptBox.isHidden = true

        // ---- Fight HUD ----
        fightStatusLabel.font = .systemFont(ofSize: 13, weight: .bold)
        fightStatusLabel.textColor = .systemRed
        enemyHealthBar.levelIndicatorStyle = .continuousCapacity
        enemyHealthBar.minValue = 0; enemyHealthBar.maxValue = 100
        enemyHealthBar.warningValue = 40; enemyHealthBar.criticalValue = 25
        enemyHealthBar.translatesAutoresizingMaskIntoConstraints = false
        enemyHealthBar.widthAnchor.constraint(equalToConstant: 110).isActive = true

        fightFireButton.target = self;  fightFireButton.action = #selector(fightFireTapped)
        fightStandButton.target = self; fightStandButton.action = #selector(fightStandTapped)
        fightRunButton.target = self;   fightRunButton.action = #selector(fightRunTapped)
        fightDealButton.target = self;  fightDealButton.action = #selector(fightDealTapped)
        for b in [fightFireButton, fightStandButton, fightRunButton, fightDealButton] {
            b.bezelStyle = .rounded
        }
        fightFireButton.title = "Fight"
        fightRunButton.title = "Run"
        setSymbol("scope", on: fightFireButton)
        setSymbol("figure.stand", on: fightStandButton)
        setSymbol("figure.run", on: fightRunButton)
        setSymbol("checkmark.circle", on: fightDealButton)
        let fightRow = NSStackView(views: [fightStatusLabel, enemyHealthBar, NSView(),
                                           fightFireButton, fightStandButton,
                                           fightRunButton, fightDealButton])
        fightRow.orientation = .horizontal
        fightRow.spacing = 10
        pinned(into: fightBox, fightRow)
        fightBox.isHidden = true

        // ---- Buttons ----
        buyButton.target = self;  buyButton.action = #selector(buyTapped)
        sellButton.target = self; sellButton.action = #selector(sellTapped)
        dropButton.target = self; dropButton.action = #selector(dropTapped)
        jetButton.target = self;  jetButton.action = #selector(jetTapped)
        buyButton.bezelStyle = .rounded
        sellButton.bezelStyle = .rounded
        dropButton.bezelStyle = .rounded
        jetButton.bezelStyle = .rounded
        jetButton.title = "Jet"
        setSymbol("cart.badge.plus", on: buyButton)
        setSymbol("cart.badge.minus", on: sellButton)
        setSymbol("trash", on: dropButton)
        setSymbol("airplane", on: jetButton)
        let shortcuts = NSTextField(labelWithString: "Keys: B buy · S sell · D drop · J jet · 1–\(min(engine.locations.count, 9)) travel · F/R/S/D in fights")
        shortcuts.font = .systemFont(ofSize: 11)
        shortcuts.textColor = .tertiaryLabelColor
        let buttons = NSStackView(views: [buyButton, sellButton, dropButton, jetButton,
                                          NSView(), shortcuts])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        // ---- Log ----
        logView.isEditable = false
        logView.isRichText = true
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.textContainerInset = NSSize(width: 6, height: 6)
        logView.backgroundColor = .textBackgroundColor    // adapts to dark mode
        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.documentView = logView
        logScroll.borderType = .bezelBorder
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        let logTitle = sectionTitle("News & messages")
        let logCol = NSStackView(views: [logTitle, logScroll])
        logCol.orientation = .vertical
        logCol.alignment = .leading
        logCol.spacing = 4
        logCol.distribution = .fill
        logTitle.setContentHuggingPriority(.init(751), for: .vertical)

        // ---- Root ----
        let root = NSStackView(views: [locationStrip, header, tables,
                                       promptBox, fightBox, buttons, logCol])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        drugScroll.translatesAutoresizingMaskIntoConstraints = false
        gunScroll.translatesAutoresizingMaskIntoConstraints = false
        locationStrip.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            locationStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            locationStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statsRow.widthAnchor.constraint(equalTo: header.widthAnchor, constant: -28),
            topRow.widthAnchor.constraint(equalTo: statsRow.widthAnchor),

            tables.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            tables.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            // Tables grow with the window (the scroll views stretch inside
            // their columns); the log keeps a weak preferred height below,
            // so extra vertical space goes to the tables.
            tables.heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
            leftCol.heightAnchor.constraint(equalTo: tables.heightAnchor),
            rightCol.heightAnchor.constraint(equalTo: tables.heightAnchor),
            leftCol.widthAnchor.constraint(equalTo: rightCol.widthAnchor, multiplier: 1.3),
            drugScroll.widthAnchor.constraint(equalTo: leftCol.widthAnchor),
            gunScroll.widthAnchor.constraint(equalTo: rightCol.widthAnchor),
            miniMap.widthAnchor.constraint(equalTo: rightCol.widthAnchor),
            miniMap.heightAnchor.constraint(equalToConstant: 160),

            promptBox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            promptBox.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            fightBox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            fightBox.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            logCol.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            logCol.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            logScroll.widthAnchor.constraint(equalTo: logCol.widthAnchor),
            logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])

        // Deterministic vertical stretch order:
        //  - the log's bottom is pinned to the window (required), so all
        //    extra height must be absorbed by the flexible sections;
        //  - the log prefers 150pt (weak, 400);
        //  - the tables prefer their content cap (weaker, 350) and are
        //    hard-capped there (required);
        // so growing the window first expands the tables until every drug
        // row is visible, then all remaining space goes to the log.
        logScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor,
                                          constant: -14).isActive = true

        let logPreferred = logScroll.heightAnchor.constraint(equalToConstant: 150)
        logPreferred.priority = NSLayoutConstraint.Priority(400)
        logPreferred.isActive = true

        let cap = tables.heightAnchor.constraint(lessThanOrEqualToConstant: 400)
        cap.isActive = true
        tablesCapConstraint = cap
        let pref = tables.heightAnchor.constraint(equalToConstant: 400)
        pref.priority = NSLayoutConstraint.Priority(350)
        pref.isActive = true
        tablesPrefConstraint = pref

        rebuildLocationStrip()

        // Horizontal stacks let their frame grow past their content with
        // no autolayout penalty, silently soaking up window height. Pin
        // the fixed sections to their fitting height so vertical stretch
        // goes to the tables and log as intended.
        for section: NSView in [header, buttons] {
            let h = section.fittingSize.height
            if h > 0 {
                section.heightAnchor.constraint(equalToConstant: h).isActive = true
            }
        }
    }

    private func setSymbol(_ name: String, on button: NSButton) {
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: button.title) {
            button.image = img
            button.imagePosition = .imageLeading
        }
    }

    /// Animate a panel (prompt bar / fight HUD) in or out of the stack.
    private func setPanel(_ box: NSBox, hidden: Bool) {
        guard box.isHidden != hidden else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.allowsImplicitAnimation = true
            box.animator().isHidden = hidden
            window?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func sectionTitle(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func configureTable(_ table: NSTableView, columns: [(String, String, CGFloat)]) {
        for (i, (id, title, width)) in columns.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = 40
            // Let the name column soak up any extra width.
            col.resizingMask = i == 0 ? [.autoresizingMask, .userResizingMask]
                                      : [.userResizingMask]
            if id != "trend" {
                col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            }
            table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.rowHeight = 22
        if #available(macOS 11.0, *) { table.style = .inset }
        table.doubleAction = #selector(tableDoubleClicked)
        table.target = self
    }

    private func wrap(_ table: NSTableView) -> NSScrollView {
        let s = NSScrollView()
        s.documentView = table
        s.hasVerticalScroller = true
        s.borderType = .noBorder
        s.wantsLayer = true
        s.layer?.cornerRadius = 8
        return s
    }

    func rebuildLocationStrip() {
        let locs = engine.locations
        locationStrip.segmentCount = locs.count
        for (i, name) in locs.enumerated() {
            locationStrip.setLabel(name, forSegment: i)
        }
        locationStrip.trackingMode = .selectOne
        if engine.location < locs.count {
            locationStrip.selectedSegment = engine.location
        }
        miniMap.locationNames = locs
        miniMap.current = engine.location
    }

    // MARK: Keyboard shortcuts

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self = self,
                  ev.window === self.window,
                  !(self.window?.firstResponder is NSTextView),
                  ev.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  let ch = ev.charactersIgnoringModifiers?.lowercased().first
            else { return ev }
            return self.handleKey(ch) ? nil : ev
        }
    }

    private func handleKey(_ ch: Character) -> Bool {
        let fighting = !fightBox.isHidden
        switch ch {
        case "b" where !fighting:
            buyTapped(); return true
        case "j" where !fighting:
            jetTapped(); return true
        case "s" where fighting:
            if fightStandButton.isEnabled && !fightStandButton.isHidden {
                fightStandTapped(); return true
            }
            return false
        case "s":
            sellTapped(); return true
        case "f" where fighting:
            if fightFireButton.isEnabled && !fightFireButton.isHidden {
                fightFireTapped(); return true
            }
            return false
        case "r" where fighting:
            if fightRunButton.isEnabled { fightRunTapped(); return true }
            return false
        case "d" where fighting:
            if fightDealButton.isEnabled { fightDealTapped(); return true }
            return false
        case "d":
            if dropButton.isHidden { return false }   // antique: no dumping
            dropTapped(); return true
        case "y", "n":
            if !promptBox.isHidden, let idx = promptAllowed.firstIndex(
                    of: Character(ch.uppercased())) {
                answerPrompt(letter: promptAllowed[idx]); return true
            }
            return false
        case "1"..."9":
            guard !fighting, let n = ch.wholeNumberValue else { return false }
            let dest = n - 1
            if dest < engine.locations.count && dest != engine.location
                && locationStrip.isEnabled {
                engine.jet(to: dest); return true
            }
            return false
        default:
            return false
        }
    }

    // MARK: Engine wiring

    private func wireEngine() {
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func startNewGame(name: String, antique: Bool) {
        dismissWelcome()
        engine.setAntique(antique)
        engine.setGameRules(turns: DopewarsPrefs.gameTurns,
                            startCash: DopewarsPrefs.startCash,
                            startDebt: DopewarsPrefs.startDebt,
                            sanitized: DopewarsPrefs.sanitized,
                            debtInterest: DopewarsPrefs.debtInterest,
                            bankInterest: DopewarsPrefs.bankInterest,
                            cheapDivide: DopewarsPrefs.cheapDivide,
                            expensiveMultiply: DopewarsPrefs.expensiveMultiply,
                            playerArmor: DopewarsPrefs.playerArmor,
                            bitchArmor: DopewarsPrefs.bitchArmor,
                            bitchMinPrice: DopewarsPrefs.bitchMinPrice,
                            bitchMaxPrice: DopewarsPrefs.bitchMaxPrice,
                            startDay: DopewarsPrefs.startDay,
                            startMonth: DopewarsPrefs.startMonth,
                            startYear: DopewarsPrefs.startYear)
        engine.setDifficulty(DopewarsPrefs.difficulty)
        engine.setFamilyFriendlyNames(DopewarsPrefs.familyFriendly)
        bitchesTile.caption = engine.bitchesName.uppercased()
        // Antique mode has no escorts (street offers are trenchcoat
        // upgrades instead) and no drug dumping; hide both like the
        // original clients do.
        bitchesTile.isHidden = engine.isAntique
        dropButton.isHidden = engine.isAntique
        clearLog()
        lastCash = nil
        lastHealth = nil
        lastPrintMessage = ""
        priceHistory = [:]
        netWorthHistory = []
        lastRecordedTurn = nil
        warnedLastDay = false
        turnLabel.textColor = .labelColor
        lastEnemyHealth = nil
        lastEnemyName = ""
        engine.newGame(playerName: name)
        lastLocation = engine.location
        rebuildLocationStrip()
        hidePrompt()
        updateFightUI(forceHide: true)
        scheduleRefresh()
    }

    // MARK: Welcome overlay

    func showWelcome(status: String, run: [Int64] = [], celebrate: Bool = false) {
        guard let content = window?.contentView else { return }
        if welcomeView == nil {
            let v = WelcomeView(frame: .zero)
            v.onStart = { [weak self] name, antique in
                self?.startNewGame(name: name, antique: antique)
            }
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                v.topAnchor.constraint(equalTo: content.topAnchor),
                v.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            welcomeView = v
        }
        welcomeView?.setStatus(status)
        welcomeView?.showRun(run, format: run.isEmpty ? nil : engine.formatPrice)
        welcomeView?.alphaValue = 1
        welcomeView?.isHidden = false
        welcomeView?.focusName()
        window?.title = "Dope Wars"
        if celebrate, let v = welcomeView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak v] in
                v?.celebrate()
            }
        }
    }

    private func dismissWelcome() {
        guard let v = welcomeView else { return }
        v.isDismissing = true
        welcomeView = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            v.animator().alphaValue = 0
        }, completionHandler: {
            v.removeFromSuperview()
        })
    }

    private func handle(_ event: GameEvent) {
        switch event {
        case .update:
            scheduleRefresh()
        case .message(let m):
            appendLog(m, color: .secondaryLabelColor)
        case .print(let m):
            lastPrintMessage = m
            appendLog(m, color: .labelColor)
        case .subway(let loc):
            appendLog("You travel to \(loc)…", color: .systemBlue)
            if let content = window?.contentView, welcomeView == nil {
                SubwayFlashView.flash(names: engine.locations,
                                      from: lastLocation,
                                      to: engine.location,
                                      in: content)
            }
            lastLocation = engine.location
            updateFightUI()
            scheduleRefresh()
        case .fight(let line):
            if !line.isEmpty { appendLog("⚔️ \(line)", color: .systemRed) }
            scheduleRefresh()
            updateFightUI()
        case .question(let allowed, let prompt):
            showPrompt(allowed: allowed, prompt: prompt)
        case .loanShark:
            showLoanShark()
        case .bank:
            showBank()
        case .gunShop:
            showGunShop()
        case .hiscoreStart:
            pendingHiscores = []
        case .hiscoreLine(let text, let own):
            pendingHiscores.append((text, own))
        case .hiscoreEnd(let gameOver):
            showHighScores(gameOver: gameOver)
        case .gameOver:
            updateFightUI(forceHide: true)
            hidePrompt()
        }
    }

    // MARK: Refresh

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    private func refresh() {
        nameLabel.stringValue = engine.playerName
        dateLabel.stringValue = engine.dateString

        let cash = engine.cash
        cashTile.valueLabel.stringValue = engine.formatPrice(cash)
        if let prev = lastCash, cash != prev {
            cashTile.flashValue(cash > prev ? .systemGreen : .systemRed)
        }
        lastCash = cash

        bankTile.valueLabel.stringValue = engine.formatPrice(engine.bank)
        debtTile.valueLabel.stringValue = engine.formatPrice(engine.debt)
        debtTile.valueLabel.textColor = engine.debt > 0 ? .systemRed : .labelColor

        // Sample per-day histories once per game day (after the engine has
        // finished updating prices for the new location).
        if engine.isStarted && engine.turn != lastRecordedTurn {
            lastRecordedTurn = engine.turn
            recordHistories()
        }

        let net = engine.netWorth
        netValueLabel.stringValue = engine.formatPrice(net)
        netValueLabel.textColor = net >= 0 ? .systemGreen : .systemRed
        netSpark.values = netWorthHistory

        spaceTile.valueLabel.stringValue = "\(engine.spaceFree) / \(engine.coatSize)"
        bitchesTile.valueLabel.stringValue = "\(engine.bitches)"

        let health = engine.health
        healthBar.intValue = Int32(health)
        healthLabel.stringValue = "\(health)%"
        if let prev = lastHealth, health < prev {
            healthTile.shake()
            healthTile.dpFloatText("−\(prev - health)", color: .systemRed)
            healthLabel.textColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.healthLabel.textColor = .labelColor
            }
        }
        lastHealth = health

        let turns = engine.numTurns
        if turns > 0 {
            turnBar.isHidden = false
            turnBar.maxValue = Double(turns)
            turnBar.warningValue = Double(turns) * 0.7
            turnBar.criticalValue = Double(turns) * 0.9
            turnBar.intValue = Int32(engine.turn)
            turnLabel.stringValue = "Day \(engine.turn)/\(turns)"
        } else {
            turnBar.isHidden = true
            turnLabel.stringValue = "Day \(engine.turn)"
        }

        // Final-day alarm: the whole endgame is dumping inventory, so make
        // sure the player can't miss it.
        if engine.isStarted && turns > 0 && engine.turn >= turns && !warnedLastDay {
            warnedLastDay = true
            turnLabel.textColor = .systemRed
            timeTile.shake()
            appendLog("🕛 LAST DAY — sell everything before the game ends!",
                      color: .systemOrange)
        }

        let loc = engine.locationName(engine.location)
        locationLabel.stringValue = "📍 \(loc)"
        window?.title = turns > 0 ? "Dope Wars - Day \(engine.turn) of \(turns)"
                                  : "Dope Wars - Day \(engine.turn)"

        if engine.location < locationStrip.segmentCount {
            locationStrip.selectedSegment = engine.location
        }
        miniMap.current = engine.location

        drugRows = sortedDrugRows(engine.drugs)
        gunRows = sortedGunRows(engine.guns)
        drugTable.reloadData()
        gunTable.reloadData()
        updateTablesCap()
    }

    /// Append today's samples to the price and net-worth histories.
    private func recordHistories() {
        for d in engine.drugs where d.price > 0 {
            priceHistory[d.index, default: []].append(d.price)
            if priceHistory[d.index]!.count > 20 {
                priceHistory[d.index]!.removeFirst()
            }
        }
        netWorthHistory.append(engine.netWorth)
    }

    // MARK: Sorting

    private func sortedDrugRows(_ rows: [DrugInfo]) -> [DrugInfo] {
        guard let sd = drugTable.sortDescriptors.first, let key = sd.key else {
            return rows
        }
        let asc = sd.ascending
        return rows.sorted { a, b in
            let r: Bool
            switch key {
            case "price":   r = a.price < b.price
            case "carried": r = a.carried < b.carried
            case "avg":     r = (a.avgPaid ?? 0) < (b.avgPaid ?? 0)
            default:        r = a.name.localizedCaseInsensitiveCompare(b.name)
                                == .orderedAscending
            }
            return asc ? r : !r
        }
    }

    private func sortedGunRows(_ rows: [GunInfo]) -> [GunInfo] {
        guard let sd = gunTable.sortDescriptors.first, let key = sd.key else {
            return rows
        }
        let asc = sd.ascending
        return rows.sorted { a, b in
            let r: Bool
            switch key {
            case "price":   r = a.price < b.price
            case "space":   r = a.space < b.space
            case "carried": r = a.carried < b.carried
            default:        r = a.name.localizedCaseInsensitiveCompare(b.name)
                                == .orderedAscending
            }
            return asc ? r : !r
        }
    }

    func tableView(_ tableView: NSTableView,
                   sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if tableView === drugTable {
            drugRows = sortedDrugRows(engine.drugs)
        } else {
            gunRows = sortedGunRows(engine.guns)
        }
        tableView.reloadData()
    }

    /// Cap the tables row at the height that shows every drug row —
    /// beyond that, extra window height belongs to the log.
    private func updateTablesCap() {
        guard !drugRows.isEmpty else { return }
        let contentHeight = drugTable.rect(ofRow: drugRows.count - 1).maxY
        let headerHeight = drugTable.headerView?.frame.height ?? 28
        let titleHeight: CGFloat = 24     // section label + stack spacing
        let padding: CGFloat = 8          // .inset style breathing room
        let cap = max(250, contentHeight + headerHeight + titleHeight + padding)
        tablesCapConstraint?.constant = cap
        tablesPrefConstraint?.constant = cap
    }

    // MARK: Log

    private func clearLog() { logView.string = "" }

    private func appendLog(_ s: String, color: NSColor = .labelColor) {
        guard !s.isEmpty else { return }
        let text = s.replacingOccurrences(of: "^", with: "\n") + "\n"
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ])
        logView.textStorage?.append(attr)
        logView.scrollToEndOfDocument(nil)
    }

    // MARK: Table data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === drugTable ? drugRows.count : gunRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""
        if tableView === drugTable && id == "trend" {
            let d = drugRows[row]
            let spark = SparklineView()
            spark.values = priceHistory[d.index] ?? []
            // Scale against the drug's normal price range so the line's
            // height reflects how cheap/expensive it actually is.
            spark.range = (d.minPrice, d.maxPrice)
            spark.toolTip = "Prices you've seen for \(d.name)"
            return spark
        }
        let cell = (tableView.makeView(withIdentifier: tableColumn!.identifier, owner: self)
                    as? NSTextField) ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = tableColumn!.identifier
            f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            f.lineBreakMode = .byTruncatingTail
            return f
        }()
        cell.textColor = .labelColor
        cell.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        if tableView === drugTable {
            let d = drugRows[row]
            switch id {
            case "drug":
                cell.stringValue = d.name
                switch d.priceLevel {
                case .cheap: cell.textColor = .systemGreen
                case .spike: cell.textColor = .systemRed
                case .normal: break
                }
            case "price":
                if d.price > 0 {
                    switch d.priceLevel {
                    case .cheap:
                        cell.stringValue = engine.formatPrice(d.price) + " ▼"
                        cell.textColor = .systemGreen
                        cell.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
                    case .spike:
                        cell.stringValue = engine.formatPrice(d.price) + " ▲"
                        cell.textColor = .systemRed
                        cell.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
                    case .normal:
                        cell.stringValue = engine.formatPrice(d.price)
                    }
                } else {
                    cell.stringValue = "—"
                    cell.textColor = .tertiaryLabelColor
                }
            case "carried":
                cell.stringValue = d.carried > 0 ? "\(d.carried)" : ""
            case "avg":
                if let avg = d.avgPaid {
                    cell.stringValue = engine.formatPrice(avg)
                    if d.price > 0 {
                        cell.textColor = d.price > avg ? .systemGreen : .systemRed
                    } else {
                        cell.textColor = .secondaryLabelColor
                    }
                } else {
                    cell.stringValue = ""
                }
            default: break
            }
        } else {
            let g = gunRows[row]
            switch id {
            case "gun": cell.stringValue = g.name
            case "price": cell.stringValue = engine.formatPrice(g.price)
            case "space": cell.stringValue = "\(g.space)"
            case "carried": cell.stringValue = g.carried > 0 ? "\(g.carried)" : ""
            default: break
            }
        }
        return cell
    }

    // MARK: Trading

    @objc private func tableDoubleClicked() {
        if drugTable.clickedRow >= 0 {
            drugTable.selectRowIndexes([drugTable.clickedRow], byExtendingSelection: false)
            openTrade()
        }
    }

    @objc func buyTapped() { openTrade(prefer: .buy) }
    @objc func sellTapped() { openTrade(prefer: .sell) }
    @objc func dropTapped() { openTrade(prefer: .drop) }

    // MARK: Right-click trade menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === themeMenu {
            // Refresh the checkmarks from the saved appearance choice.
            let current = UserDefaults.standard.string(forKey: "DopewarsAppearance")
                ?? "system"
            for item in menu.items {
                item.state = (item.representedObject as? String) == current
                    ? .on : .off
            }
            return
        }
        menu.removeAllItems()
        guard menu === drugMenu else { return }
        let row = drugTable.clickedRow
        guard row >= 0, row < drugRows.count, buyButton.isEnabled,
              welcomeView == nil else { return }
        menuRow = row
        drugTable.selectRowIndexes([row], byExtendingSelection: false)
        let d = drugRows[row]
        func add(_ title: String, _ action: Selector) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                .target = self
        }
        if d.price > 0 {
            let maxBuy = min(engine.cash / d.price, Int64(engine.spaceFree))
            if maxBuy > 0 {
                add("Buy Max — \(maxBuy) @ \(engine.formatPrice(d.price))",
                    #selector(menuBuyMax))
            }
            if d.carried > 0 {
                add("Sell All — \(d.carried)", #selector(menuSellAll))
                if d.carried > 1 {
                    add("Sell Half — \(d.carried / 2)", #selector(menuSellHalf))
                }
            }
        } else if d.carried > 0 && !engine.isAntique {
            add("Drop All — \(d.carried)", #selector(menuDropAll))
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        add("Trade…", #selector(menuTrade))
    }

    @objc private func menuBuyMax() {
        guard menuRow >= 0, menuRow < drugRows.count else { return }
        let d = drugRows[menuRow]
        guard d.price > 0 else { return }
        let n = Int(min(engine.cash / d.price, Int64(engine.spaceFree)))
        guard n > 0 else { return }
        engine.buyDrug(d.index, amount: n)
        appendLog("Bought \(n) \(d.name) @ \(engine.formatPrice(d.price)).",
                  color: .systemGreen)
    }

    @objc private func menuSellAll() { sellFromMenu(dividingBy: 1) }
    @objc private func menuSellHalf() { sellFromMenu(dividingBy: 2) }

    private func sellFromMenu(dividingBy divisor: Int) {
        guard menuRow >= 0, menuRow < drugRows.count else { return }
        let d = drugRows[menuRow]
        let n = d.carried / divisor
        guard n > 0, d.price > 0 else { return }
        engine.buyDrug(d.index, amount: -n)
        appendLog("Sold \(n) \(d.name) @ \(engine.formatPrice(d.price)).",
                  color: .systemGreen)
    }

    @objc private func menuDropAll() {
        guard menuRow >= 0, menuRow < drugRows.count else { return }
        let d = drugRows[menuRow]
        guard d.carried > 0 else { return }
        engine.buyDrug(d.index, amount: -d.carried)
        appendLog("Dropped \(d.carried) \(d.name).", color: .secondaryLabelColor)
    }

    @objc private func menuTrade() { openTrade() }

    private func openTrade(prefer: TradeMode? = nil) {
        let row = drugTable.selectedRow
        guard row >= 0, row < drugRows.count else {
            NSSound.beep()
            appendLog("Select a \(engine.drugsName) row first.", color: .secondaryLabelColor)
            return
        }
        let d = drugRows[row]

        // Decide the trade mode.
        let mode: TradeMode
        let canBuy = d.price > 0 && engine.cash >= d.price && engine.spaceFree > 0
        let canSell = d.carried > 0 && d.price > 0
        let canDrop = d.carried > 0 && d.price == 0 && !engine.isAntique

        // Dropping is deliberate — never silently fall back to buy/sell.
        // (The engine treats a "drop" where the drug is traded as a sale,
        // so refuse that case and point at Sell.)
        if prefer == .drop && !canDrop {
            NSSound.beep()
            let reason: String
            if d.carried == 0 {
                reason = "You aren't carrying any \(d.name)."
            } else if engine.isAntique {
                reason = "You can't dump \(engine.drugsName) in antique mode."
            } else {
                reason = "\(d.name) sells here for \(engine.formatPrice(d.price)) — use Sell instead."
            }
            appendLog(reason, color: .secondaryLabelColor)
            return
        }

        switch prefer {
        case .some(.buy) where canBuy:   mode = .buy
        case .some(.sell) where canSell: mode = .sell
        case .some(.sell) where canDrop: mode = .drop
        case .some(.drop):               mode = .drop
        default:
            // No explicit Buy/Sell choice (double-click, context menu): if
            // you're already holding the drug, you're here to unload it.
            if canSell { mode = .sell }
            else if canDrop { mode = .drop }
            else if canBuy { mode = .buy }
            else {
                NSSound.beep()
                let reason: String
                if d.price == 0 {
                    reason = "\(d.name) isn't traded here right now."
                } else if engine.spaceFree <= 0 {
                    reason = "You have no space to carry any \(d.name)."
                } else if engine.cash < d.price {
                    reason = d.carried > 0 ? "You can't afford more \(d.name)."
                                           : "You can't afford any \(d.name)."
                } else {
                    reason = "You can't trade \(d.name) right now."
                }
                appendLog(reason, color: .secondaryLabelColor)
                return
            }
        }

        let max: Int
        switch mode {
        case .buy:  max = Swift.min(Int(engine.cash / d.price), engine.spaceFree)
        case .sell: max = d.carried
        case .drop: max = d.carried
        }
        guard max > 0 else { NSSound.beep(); return }

        tradePopover?.close()
        let pop = NSPopover()
        pop.behavior = .transient
        let vc = TradeViewController(mode: mode, drug: d, maxAmount: max,
                                     engine: engine) { [weak self] amount in
            guard let self = self, amount > 0 else { return }
            switch mode {
            case .buy:
                self.engine.buyDrug(d.index, amount: amount)
                self.appendLog("Bought \(amount) \(d.name) @ \(self.engine.formatPrice(d.price)).",
                               color: .systemGreen)
            case .sell:
                self.engine.buyDrug(d.index, amount: -amount)
                self.appendLog("Sold \(amount) \(d.name) @ \(self.engine.formatPrice(d.price)).",
                               color: .systemGreen)
            case .drop:
                self.engine.buyDrug(d.index, amount: -amount)
                self.appendLog("Dropped \(amount) \(d.name).", color: .secondaryLabelColor)
            }
            self.tradePopover?.close()
        }
        pop.contentViewController = vc
        let rect = drugTable.rect(ofRow: row)
        pop.show(relativeTo: rect, of: drugTable, preferredEdge: .maxY)
        tradePopover = pop
    }

    // MARK: Jet

    @objc private func locationPicked() {
        let dest = locationStrip.selectedSegment
        if dest >= 0 && dest != engine.location {
            engine.jet(to: dest)
        }
        // If the jet was refused (e.g. mid-event), snap back.
        if engine.location < locationStrip.segmentCount {
            locationStrip.selectedSegment = engine.location
        }
    }

    @objc func jetTapped() {
        let picker = LocationPicker(engine: engine) { [weak self] dest in
            guard let self = self, dest != self.engine.location else { return }
            self.engine.jet(to: dest)
        }
        window?.beginSheet(picker.window!) { [weak self] _ in self?.retainSheet = nil }
        retainSheet = picker
    }

    // MARK: Prompt bar (inline questions)

    private func showPrompt(allowed: String, prompt: String) {
        promptAllowed = Array(allowed)
        promptLabel.stringValue = "❓ " + prompt.replacingOccurrences(of: "^", with: "  ")

        for v in promptButtonRow.arrangedSubviews {
            promptButtonRow.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let labelFor: (Character) -> String = { ch in
            switch ch {
            case "Y": return "Yes"
            case "N": return "No"
            case "R": return "Run"
            case "F": return "Fight"
            case "A": return "Attack"
            case "E": return "Evade"
            default:  return String(ch)
            }
        }
        for (i, ch) in promptAllowed.enumerated() {
            let b = NSButton(title: labelFor(ch), target: self,
                             action: #selector(promptButtonTapped(_:)))
            b.tag = i
            b.bezelStyle = .rounded
            if ch == "Y" { b.keyEquivalent = "\r" }
            promptButtonRow.addArrangedSubview(b)
        }
        if promptAllowed.isEmpty {
            let b = NSButton(title: "OK", target: self,
                             action: #selector(promptButtonTapped(_:)))
            b.tag = -1
            b.bezelStyle = .rounded
            promptButtonRow.addArrangedSubview(b)
        }
        setPanel(promptBox, hidden: false)
        locationStrip.isEnabled = false

        // Attention flash so an offer can't slip by unnoticed in the log.
        if let inner = promptBox.contentView {
            let glow = NSView(frame: inner.bounds)
            glow.autoresizingMask = [.width, .height]
            glow.wantsLayer = true
            glow.layer?.backgroundColor =
                NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            glow.layer?.cornerRadius = 5
            inner.addSubview(glow, positioned: .below, relativeTo: nil)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.9
                glow.animator().alphaValue = 0
            }, completionHandler: { glow.removeFromSuperview() })
        }
    }

    @objc private func promptButtonTapped(_ sender: NSButton) {
        if sender.tag >= 0 && sender.tag < promptAllowed.count {
            answerPrompt(letter: promptAllowed[sender.tag])
        } else {
            hidePrompt()
        }
    }

    private func answerPrompt(letter: Character) {
        hidePrompt()
        engine.answer(String(letter))
        scheduleRefresh()
    }

    private func hidePrompt() {
        setPanel(promptBox, hidden: true)
        promptAllowed = []
        locationStrip.isEnabled = fightBox.isHidden
    }

    // MARK: Fight HUD

    func updateFightUI(forceHide: Bool = false) {
        let fp = engine.fightPoint
        let active = !forceHide && (engine.isFighting || fp != nil)
        setPanel(fightBox, hidden: !active)
        buyButton.isEnabled = !active
        sellButton.isEnabled = !active
        dropButton.isEnabled = !active
        jetButton.isEnabled = !active
        locationStrip.isEnabled = !active && promptBox.isHidden
        guard active else { return }

        let guns = engine.totalGuns
        let canFire = engine.fightCanFire
        let over = engine.fightIsOver

        // Enemy readout: "Officer Hardass — 3 deputies" plus health bar.
        var status: String
        if over {
            status = "Fight over"
        } else {
            let enemy = engine.enemyName
            status = enemy.isEmpty ? "⚔️ FIGHT!" : "⚔️ \(enemy)"
            if !enemy.isEmpty && engine.enemyBitches > 0 {
                let escort = engine.enemyBitchName.isEmpty
                    ? engine.bitchesName : engine.enemyBitchName
                status += " + \(engine.enemyBitches) \(escort)"
            }
        }
        fightStatusLabel.stringValue = status
        let eh = engine.enemyHealth
        let ename = engine.enemyName
        if eh >= 0 && !over {
            enemyHealthBar.isHidden = false
            if ename == lastEnemyName, let prev = lastEnemyHealth, eh < prev {
                // Same opponent took damage: float the number and ease the
                // bar down instead of snapping.
                enemyHealthBar.dpFloatText("−\(prev - eh)", color: .systemOrange)
                animateLevel(enemyHealthBar, from: prev, to: eh)
            } else if lastEnemyHealth != eh || ename != lastEnemyName {
                enemyHealthBar.intValue = Int32(eh)
            }
            lastEnemyHealth = eh
            lastEnemyName = ename
        } else {
            enemyHealthBar.isHidden = true
            lastEnemyHealth = nil
            lastEnemyName = ""
        }

        fightFireButton.isHidden = (guns == 0)
        fightFireButton.isEnabled = canFire && guns > 0 && !over
        fightStandButton.isHidden = (guns > 0)
        fightStandButton.isEnabled = canFire && guns == 0 && !over
        fightRunButton.isEnabled = !over
        fightDealButton.isEnabled = !engine.fightCanRunHere || over
        fightDealButton.title = over ? "Continue" : "Deal drugs"
    }

    /// Ease a level indicator between two values (NSLevelIndicator has no
    /// implicit animation of its own).
    private func animateLevel(_ bar: NSLevelIndicator, from: Int, to: Int) {
        let steps = 6
        for s in 1...steps {
            let t = Double(s) / Double(steps)
            let v = Double(from) + (Double(to) - Double(from)) * t
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(s)) {
                bar.doubleValue = v
            }
        }
    }

    @objc func fightFireTapped() {
        engine.fightShoot()
        updateFightUI()
    }

    @objc func fightStandTapped() {
        engine.fightStand()
        updateFightUI()
    }

    @objc func fightRunTapped() {
        if engine.fightCanRunHere {
            engine.fightRun()
            updateFightUI()
        } else {
            let picker = LocationPicker(engine: engine) { [weak self] dest in
                guard let self = self, dest != self.engine.location else { return }
                self.engine.jet(to: dest)
                self.updateFightUI()
            }
            window?.beginSheet(picker.window!) { [weak self] _ in self?.retainSheet = nil }
            retainSheet = picker
        }
    }

    @objc func fightDealTapped() {
        engine.fightFinish()
        updateFightUI()
        scheduleRefresh()
    }

    // MARK: Bank / loan shark / gun shop (real "places" stay as sheets)

    private func showLoanShark() {
        let c = LoanSharkController(engine: engine) { [weak self] in
            self?.engine.done()
        }
        window?.beginSheet(c.window!) { [weak self] _ in self?.retainSheet = nil }
        retainSheet = c
    }

    private func showBank() {
        let c = BankSheetController(engine: engine) { [weak self] in
            self?.engine.done()
        }
        window?.beginSheet(c.window!) { [weak self] _ in self?.retainSheet = nil }
        retainSheet = c
    }

    private func showGunShop() {
        let gunWindow = GunShopController(engine: engine) { [weak self] in
            self?.engine.done()
        }
        window?.beginSheet(gunWindow.window!) { [weak self] _ in self?.retainSheet = nil }
        retainSheet = gunWindow
    }

    // MARK: High scores

    private func showHighScores(gameOver: Bool) {
        let win = hiscoresWindow ?? HighScoresWindowController()
        hiscoresWindow = win
        win.setScores(pendingHiscores, gameOver: gameOver)
        win.showWindow(nil)
        win.window?.makeKeyAndOrderFront(nil)
        if gameOver {
            // Freshen the last daily sample with the true final worth so
            // the chart's endpoint matches the score.
            if !netWorthHistory.isEmpty {
                netWorthHistory[netWorthHistory.count - 1] = engine.netWorth
            }
            // Confetti only if this run actually made the 18-entry table
            // (a non-qualifying own score is appended beyond it).
            let qualified = pendingHiscores.prefix(18).contains { $0.own }
            let worth = engine.formatPrice(engine.netWorth)
            // The engine's final print is "<finale narrative>^<high-score
            // commentary>" — e.g. the paraquat weed ends the game with
            // "You hallucinated…^Then you died…^You didn't even make…".
            // The news log is hidden behind this overlay, so surface the
            // narrative (the commentary is always the last segment; a
            // narrative-less ending leaves it empty) as the status.
            let finale = lastPrintMessage.split(separator: "^")
                .dropLast().joined(separator: " ")
            let status = finale.isEmpty
                ? (engine.isDead
                   ? "You died. Final worth: \(worth) — one more run?"
                   : "Time's up! You finished worth \(worth) — play again?")
                : "\(finale) Final worth: \(worth) — play again?"
            showWelcome(status: status, run: netWorthHistory, celebrate: qualified)
        }
    }

    // MARK: Toolbar actions

    @objc private func toolbarScores() { engine.requestScore() }

    @objc private func toolbarMute() {
        // Reach the app delegate dynamically: the headless UI test harness
        // links this file without AppDelegate.swift.
        let sel = Selector(("toggleMute"))
        if let delegate = NSApp.delegate as? NSObject, delegate.responds(to: sel) {
            delegate.perform(sel)
        }
    }

    @objc private func muteChanged() {
        muteToolbarItem?.image = muteImage()
    }

    fileprivate func muteImage() -> NSImage? {
        let name = engine.soundEnabled ? "speaker.wave.2" : "speaker.slash"
        return NSImage(systemSymbolName: name, accessibilityDescription: "Sound")
    }

}

// MARK: - Menu delegate

extension GameWindowController: NSMenuDelegate {}

// MARK: - Toolbar

private extension NSToolbarItem.Identifier {
    static let dpTheme = NSToolbarItem.Identifier("DopewarsTheme")
    static let dpScores = NSToolbarItem.Identifier("DopewarsScores")
    static let dpMute = NSToolbarItem.Identifier("DopewarsMute")
}

extension GameWindowController: NSToolbarDelegate, NSToolbarItemValidation {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .dpTheme, .dpScores, .dpMute]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == .dpTheme {
            // Pull-down menu mirroring View → Appearance. Targets the app
            // delegate dynamically (the headless UI test harness links
            // this file without AppDelegate.swift).
            let themeItem = NSMenuToolbarItem(itemIdentifier: id)
            themeItem.label = "Appearance"
            themeItem.toolTip = "Switch between light and dark themes"
            themeItem.image =
                NSImage(systemSymbolName: "circle.lefthalf.filled",
                        accessibilityDescription: "Appearance")
                ?? NSImage(systemSymbolName: "circle.lefthalf.fill",
                           accessibilityDescription: "Appearance")
            let menu = NSMenu()
            for (title, tag) in [("System", "system"), ("Light", "light"),
                                 ("Dark", "dark")] {
                let mi = menu.addItem(withTitle: title,
                                      action: Selector(("appearancePicked:")),
                                      keyEquivalent: "")
                mi.target = NSApp.delegate
                mi.representedObject = tag
            }
            menu.delegate = self
            themeMenu = menu
            themeItem.menu = menu
            themeItem.showsIndicator = true
            return themeItem
        }

        let item = NSToolbarItem(itemIdentifier: id)
        item.target = self
        if #available(macOS 10.15, *) { item.isBordered = true }
        switch id {
        case .dpScores:
            item.label = "High Scores"
            item.toolTip = "Show the high score table"
            item.image = NSImage(systemSymbolName: "trophy",
                                 accessibilityDescription: "High Scores")
                ?? NSImage(systemSymbolName: "list.number",
                           accessibilityDescription: "High Scores")
            item.action = #selector(toolbarScores)
        case .dpMute:
            item.label = "Sound"
            item.toolTip = "Mute or unmute sound"
            item.image = muteImage()
            item.action = #selector(toolbarMute)
            muteToolbarItem = item
        default:
            return nil
        }
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        true
    }
}
