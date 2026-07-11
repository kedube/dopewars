import Foundation
import DopewarsBridge

/// A single drug row as shown in the market.
struct DrugInfo {
    let index: Int
    let name: String
    let price: Int64        // price here; 0 => not sold here
    let carried: Int
    let minPrice: Int64     // normal range from the game config
    let maxPrice: Int64
    let totalPaid: Int64    // total spent on the carried units

    /// Market anomaly: below the normal range = cheap event (buy!),
    /// above it = price spike (sell!).
    enum PriceLevel { case normal, cheap, spike }
    var priceLevel: PriceLevel {
        guard price > 0 else { return .normal }
        if price < minPrice { return .cheap }
        if price > maxPrice { return .spike }
        return .normal
    }

    /// Average price paid per carried unit, if known.
    var avgPaid: Int64? {
        guard carried > 0, totalPaid > 0 else { return nil }
        return totalPaid / Int64(carried)
    }
}

/// A single gun row as shown in the gun shop / inventory.
struct GunInfo {
    let index: Int
    let name: String
    let price: Int64
    let space: Int
    let carried: Int
}

/// A high-score line.
struct HiScore {
    let text: String
}

/// Events the engine emits that the UI must react to beyond a plain state
/// refresh. Delivered on the main thread.
enum GameEvent {
    case update
    case message(String)
    case print(String)
    case question(allowed: String, prompt: String)
    case loanShark
    case bank
    case gunShop
    case fight(String)
    case subway(String)
    case hiscoreStart
    case hiscoreLine(text: String, own: Bool)
    case hiscoreEnd(gameOver: Bool)
    case gameOver
}

/// Swift-facing wrapper over the dopewars C engine bridge.
///
/// The engine runs an in-process single-player game. This object owns the
/// bridge callback, republishes state, and forwards structured events to a
/// delegate closure.
final class GameEngine {
    static let shared = GameEngine()

    /// Set by the controller to receive engine events (main thread).
    var onEvent: ((GameEvent) -> Void)?

    private var started = false

    private init() {}

    // MARK: Lifecycle

    func initialize(resourceDir: String?, hiscorePath: String) {
        dp_set_callback({ (kind, s1, s2, _) in
            GameEngine.shared.dispatch(kind: kind, s1: s1, s2: s2)
        }, nil)
        dp_init(resourceDir, hiscorePath)
        baseHiscorePath = hiscorePath
        activeHiscorePath = hiscorePath
    }

    // MARK: Score boards

    private var baseHiscorePath = ""
    private var activeHiscorePath = ""

    /// Label of the board currently in use (e.g. "Standard rules").
    private(set) var scoreBoardLabel = "Standard rules"

    /// Point the engine at the high-score board for a rule set. A nil
    /// suffix selects the standard board (the base score file); a
    /// custom rule set gets its own sibling file so scores are only
    /// compared against identical rules. Call before a new game.
    func setScoreBoard(suffix: String?, label: String) {
        scoreBoardLabel = label
        guard !baseHiscorePath.isEmpty else { return }
        var path = baseHiscorePath
        if let suffix {
            if path.hasSuffix(".sco") {
                path = String(path.dropLast(4)) + "-\(suffix).sco"
            } else {
                path += "-\(suffix)"
            }
        }
        path.withCString { dp_set_hiscore_path($0) }
        activeHiscorePath = path
    }

    /// Erase the active high-score board (recreated empty). With
    /// `allBoards`, also delete every other rule-set board file next to
    /// the base score file; those aren't open, so plain deletion works.
    func resetHighScores(allBoards: Bool) {
        dp_reset_hiscores()
        guard allBoards, !baseHiscorePath.isEmpty else { return }
        let base = baseHiscorePath as NSString
        let dir = base.deletingLastPathComponent
        let stem = (base.lastPathComponent as NSString).deletingPathExtension
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
            guard f.hasSuffix(".sco"),
                  f == stem + ".sco" || f.hasPrefix(stem + "-") else { continue }
            let path = dir + "/" + f
            guard path != activeHiscorePath else { continue }
            try? fm.removeItem(atPath: path)
        }
    }

    func setAntique(_ on: Bool) { dp_set_antique(on) }

    /// Game-rule overrides; take effect at the next new game.
    func setGameRules(turns: Int, startCash: Int64, startDebt: Int64,
                      sanitized: Bool, debtInterest: Int, bankInterest: Int,
                      cheapDivide: Int, expensiveMultiply: Int,
                      playerArmor: Int, bitchArmor: Int,
                      bitchMinPrice: Int64, bitchMaxPrice: Int64,
                      startDay: Int, startMonth: Int, startYear: Int) {
        var r = DPGameRules()
        r.num_turns = Int32(turns)
        r.start_cash = startCash
        r.start_debt = startDebt
        r.sanitized = sanitized
        r.debt_interest = Int32(debtInterest)
        r.bank_interest = Int32(bankInterest)
        r.cheap_divide = Int32(cheapDivide)
        r.expensive_multiply = Int32(expensiveMultiply)
        r.player_armor = Int32(playerArmor)
        r.bitch_armor = Int32(bitchArmor)
        r.bitch_min_price = bitchMinPrice
        r.bitch_max_price = bitchMaxPrice
        // Spy/tipoff are multiplayer-only errands with no effect in this
        // single-player port; keep the engine defaults rather than
        // exposing dead knobs in Preferences.
        r.spy_price = 20000
        r.tipoff_price = 10000
        r.start_day = Int32(startDay)
        r.start_month = Int32(startMonth)
        r.start_year = Int32(startYear)
        dp_set_game_rules(&r)
    }

    /// Difficulty preset (0 easy, 1 normal, 2 hard); scales police
    /// presence and cop squads from the configured baselines.
    func setDifficulty(_ level: Int) {
        dp_set_difficulty(DPDifficulty(UInt32(max(0, min(2, level)))))
    }

    /// Swap the engine's "bitch(es)" wording for "escort(s)" in
    /// generated messages, matching the UI's terminology.
    func setFamilyFriendlyNames(_ on: Bool) {
        dp_set_family_friendly_names(on)
    }

    /// Currency used by the engine's price formatting: symbol and
    /// whether it precedes the amount. Cosmetic; applies immediately.
    func setCurrency(symbol: String, prefix: Bool) {
        symbol.withCString { dp_set_currency($0, prefix) }
    }

    func newGame(playerName: String) {
        started = true
        playerName.withCString { dp_new_game($0) }
    }

    var isStarted: Bool { started }

    // MARK: Callback trampoline

    private func dispatch(kind: DPEventKind, s1: UnsafePointer<CChar>?,
                          s2: UnsafePointer<CChar>?) {
        let a = s1.map { String(cString: $0) } ?? ""
        let b = s2.map { String(cString: $0) } ?? ""
        let event: GameEvent
        switch kind {
        case DP_EV_UPDATE:        event = .update
        case DP_EV_MESSAGE:       event = .message(a)
        case DP_EV_PRINT:         event = .print(a)
        case DP_EV_QUESTION:      event = .question(allowed: a, prompt: b)
        case DP_EV_LOANSHARK:     event = .loanShark
        case DP_EV_BANK:          event = .bank
        case DP_EV_GUNSHOP:       event = .gunShop
        case DP_EV_FIGHT:         event = .fight(a)
        case DP_EV_SUBWAY:        event = .subway(a)
        case DP_EV_HISCORE_START: event = .hiscoreStart
        case DP_EV_HISCORE_LINE:  event = .hiscoreLine(text: a, own: b == "B")
        case DP_EV_HISCORE_END:   event = .hiscoreEnd(gameOver: a == "end")
        case DP_EV_GAMEOVER:      event = .gameOver
        default:                  event = .update
        }
        // The engine is synchronous and already on the main thread, but be
        // defensive in case that ever changes.
        if Thread.isMainThread {
            onEvent?(event)
        } else {
            DispatchQueue.main.async { self.onEvent?(event) }
        }
    }

    // MARK: State accessors

    var playerName: String { String(cString: dp_player_name()) }
    var cash: Int64 { dp_cash() }
    var debt: Int64 { dp_debt() }
    var bank: Int64 { dp_bank() }
    var health: Int { Int(dp_health()) }
    var coatSize: Int { Int(dp_coat_size()) }      // total capacity
    var coatUsed: Int { Int(dp_coat_used()) }
    var spaceFree: Int { Int(dp_space_free()) }    // engine's own count
    var bitches: Int { Int(dp_bitches()) }
    var location: Int { Int(dp_location()) }
    var turn: Int { Int(dp_turn()) }
    var numTurns: Int { Int(dp_num_turns()) }
    var isFighting: Bool { dp_is_fighting() }
    var canShoot: Bool { dp_can_shoot() }
    var isDead: Bool { dp_is_dead() }
    var isAntique: Bool { dp_is_antique() }

    /// Last fight point received ('D' = fight over); nil before any fight.
    var fightPoint: Character? {
        let c = dp_fight_point()
        return c == 0 ? nil : Character(UnicodeScalar(UInt8(bitPattern: c)))
    }
    /// The fight has concluded (the "last leave" message was received).
    var fightIsOver: Bool { fightPoint == "D" }
    var fightCanFire: Bool { dp_fight_can_fire() }
    /// Player can run while staying at this location (else flee = jet).
    var fightCanRunHere: Bool { dp_fight_can_run_here() }
    var totalGuns: Int { Int(dp_total_guns()) }

    var dateString: String {
        guard let c = dp_date_string() else { return "" }
        defer { dp_free_string(c) }
        return String(cString: c)
    }

    var currencySymbol: String { String(cString: dp_currency_symbol()) }
    var drugsName: String { String(cString: dp_name_drugs()) }
    var gunsName: String { String(cString: dp_name_guns()) }
    var bitchesName: String { String(cString: dp_name_bitches()) }

    func formatPrice(_ price: Int64) -> String {
        guard let c = dp_format_price(price) else { return "\(price)" }
        defer { dp_free_string(c) }
        return String(cString: c)
    }

    var locations: [String] {
        (0..<Int(dp_num_locations())).map { String(cString: dp_location_name(Int32($0))) }
    }

    func locationName(_ i: Int) -> String {
        String(cString: dp_location_name(Int32(i)))
    }

    var drugs: [DrugInfo] {
        var out: [DrugInfo] = []
        let n = Int(dp_num_drugs())
        out.reserveCapacity(n)
        for i in 0..<n {
            let idx = Int32(i)
            let name = String(cString: dp_drug_name(idx))
            let price: Int64 = dp_drug_price(idx)
            let carried = Int(dp_drug_carried(idx))
            let minP: Int64 = dp_drug_min_price(idx)
            let maxP: Int64 = dp_drug_max_price(idx)
            let paid: Int64 = dp_drug_total_value(idx)
            out.append(DrugInfo(index: i, name: name, price: price,
                                carried: carried, minPrice: minP,
                                maxPrice: maxP, totalPaid: paid))
        }
        return out
    }

    // MARK: Fight opponent (for the fight HUD)

    var enemyName: String { String(cString: dp_fight_enemy_name()) }
    var enemyHealth: Int { Int(dp_fight_enemy_health()) }      // -1 unknown
    var enemyBitches: Int { Int(dp_fight_enemy_bitches()) }    // -1 unknown
    var enemyBitchName: String { String(cString: dp_fight_enemy_bitch_name()) }

    var guns: [GunInfo] {
        (0..<Int(dp_num_guns())).map { i in
            GunInfo(index: i,
                    name: String(cString: dp_gun_name(Int32(i))),
                    price: dp_gun_price(Int32(i)),
                    space: Int(dp_gun_space(Int32(i))),
                    carried: Int(dp_gun_carried(Int32(i))))
        }
    }

    // MARK: Actions

    func jet(to location: Int) { dp_jet(Int32(location)) }
    func buyDrug(_ index: Int, amount: Int) { dp_buy_drug(Int32(index), Int32(amount)) }
    func buyGun(_ index: Int, amount: Int) { dp_buy_gun(Int32(index), Int32(amount)) }
    func payLoan(_ amount: Int64) { dp_pay_loan(amount) }
    func bankDeposit(_ amount: Int64) { dp_bank_deposit(amount) }
    func answer(_ letter: String) { letter.withCString { dp_answer($0) } }
    func done() { dp_done() }
    func fightShoot() { dp_fight_shoot() }
    func fightStand() { dp_fight_stand() }
    func fightRun() { dp_fight_run() }
    func fightFinish() { dp_fight_finish() }
    func requestScore() { dp_request_score() }
    func wantQuit() { dp_want_quit() }
    func openURL(_ url: String) { url.withCString { dp_open_url($0) } }

    var soundEnabled: Bool {
        get { dp_sound_enabled() }
        set { dp_set_sound_enabled(newValue) }
    }

    /// Cash + bank − debt: the number that decides the high score table.
    var netWorth: Int64 { cash + bank - debt }
}
