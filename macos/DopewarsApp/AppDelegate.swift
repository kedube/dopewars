import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var gameController: GameWindowController!
    private var prefsController: PreferencesWindowController?
    private var muteItem: NSMenuItem!
    private var appearanceItems: [NSMenuItem] = []

    private static let muteDefaultsKey = "DopewarsSoundMuted"
    private static let appearanceDefaultsKey = "DopewarsAppearance"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        applyAppearance(UserDefaults.standard.string(forKey: Self.appearanceDefaultsKey)
                        ?? "system")

        // High score file lives in Application Support.
        let fm = FileManager.default
        let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Dopewars", isDirectory: true)
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let hiscore = supportDir.appendingPathComponent("dopewars.sco").path

        GameEngine.shared.initialize(resourceDir: Bundle.main.resourcePath,
                                     hiscorePath: hiscore)

        // Restore mute preference.
        let muted = UserDefaults.standard.bool(forKey: Self.muteDefaultsKey)
        GameEngine.shared.soundEnabled = !muted
        muteItem.state = muted ? .on : .off

        gameController = GameWindowController()
        gameController.showWindow(nil)
        gameController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The in-window welcome screen takes it from here.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Dope Wars", action: #selector(about),
                        keyEquivalent: "").target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(showPrefs),
                        keyEquivalent: ",").target = self
        appMenu.addItem(NSMenuItem.separator())
        muteItem = appMenu.addItem(withTitle: "Mute Sound", action: #selector(toggleMute),
                                   keyEquivalent: "m")
        muteItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Dope Wars", action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Dope Wars", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Game menu
        let gameItem = NSMenuItem()
        mainMenu.addItem(gameItem)
        let gameMenu = NSMenu(title: "Game")
        gameItem.submenu = gameMenu
        gameMenu.addItem(withTitle: "New Game…", action: #selector(newGame),
                         keyEquivalent: "n").target = self
        gameMenu.addItem(NSMenuItem.separator())
        gameMenu.addItem(withTitle: "High Scores", action: #selector(scores),
                         keyEquivalent: "s").target = self
        gameMenu.addItem(NSMenuItem.separator())
        gameMenu.addItem(withTitle: "End Game", action: #selector(endGame),
                         keyEquivalent: "e").target = self

        // View menu (appearance override)
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        viewMenu.addItem(appearanceItem)
        let appearanceMenu = NSMenu(title: "Appearance")
        appearanceItem.submenu = appearanceMenu
        for (title, tag) in [("System", "system"), ("Light", "light"), ("Dark", "dark")] {
            let item = appearanceMenu.addItem(withTitle: title,
                                              action: #selector(appearancePicked(_:)),
                                              keyEquivalent: "")
            item.target = self
            item.representedObject = tag
            appearanceItems.append(item)
        }

        // Edit menu (copy from the log, select all)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m").keyEquivalentModifierMask = [.command]
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "Dope Wars Website", action: #selector(website),
                         keyEquivalent: "").target = self

        NSApp.mainMenu = mainMenu
    }

    @objc private func showPrefs() {
        if prefsController == nil { prefsController = PreferencesWindowController() }
        prefsController?.showWindow(nil)
        prefsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func newGame() {
        gameController.showWelcome(status: "")
        gameController.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func scores()   { GameEngine.shared.requestScore() }
    @objc private func endGame()  { GameEngine.shared.wantQuit() }
    @objc private func website()  { GameEngine.shared.openURL("https://dopewars.sourceforge.io/") }

    @objc private func appearancePicked(_ sender: NSMenuItem) {
        let choice = sender.representedObject as? String ?? "system"
        applyAppearance(choice)
        UserDefaults.standard.set(choice, forKey: Self.appearanceDefaultsKey)
    }

    private func applyAppearance(_ choice: String) {
        switch choice {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil    // follow the system setting
        }
        for item in appearanceItems {
            item.state = (item.representedObject as? String) == choice ? .on : .off
        }
    }

    @objc func toggleMute() {
        let newMuted = GameEngine.shared.soundEnabled   // toggling: on -> muted
        GameEngine.shared.soundEnabled = !newMuted
        muteItem.state = newMuted ? .on : .off
        UserDefaults.standard.set(newMuted, forKey: Self.muteDefaultsKey)
        NotificationCenter.default.post(name: .dopewarsMuteChanged, object: nil)
    }

    @objc private func about() {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let credits = NSAttributedString(
            string: """
                Native macOS port by Katherine Dubé

                Dopewars 1.6.2 by Ben Webb,
                based on John E. Dell's "Drug Wars".

                Released under the GNU General Public License.
                """,
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .paragraphStyle: centered])
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "Dope Wars",
        ])
    }
}
