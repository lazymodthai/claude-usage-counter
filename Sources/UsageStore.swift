import Foundation
import AppKit

@MainActor
final class UsageStore: ObservableObject {
    @Published var data: UsageData = .init()
    @Published var isLoading: Bool = false
    @Published var showSettings: Bool = false

    // Token limits (stored in UserDefaults, default = Claude Code Pro)
    @Published var sessionTokenLimit: Int {
        didSet { UserDefaults.standard.set(sessionTokenLimit, forKey: "sessionTokenLimit") }
    }
    @Published var weeklyTokenLimit: Int {
        didSet { UserDefaults.standard.set(weeklyTokenLimit, forKey: "weeklyTokenLimit") }
    }
    @Published var refreshInterval: Double {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            reschedule()
        }
    }

    // Selected model (mirrors ~/.claude/settings.json)
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    weak var statusItem: NSStatusItem?
    private var watcher: FileWatcher?
    private var periodicTimer: Timer?
    private var scraper: ClaudeAIScraper?
    private var scrapeTimer: Timer?
    private var countdownTimer: Timer?

    @Published var scrapedUsage: ScrapedUsage?
    @Published var isLoggedIn: Bool = false
    @Published var useClaudeAISource: Bool = UserDefaults.standard.bool(forKey: "useClaudeAISource") {
        didSet {
            UserDefaults.standard.set(useClaudeAISource, forKey: "useClaudeAISource")
            if useClaudeAISource { startScraping() } else { stopScraping() }
        }
    }

    func refreshLoginStatus() {
        Task { @MainActor in
            self.isLoggedIn = await ClaudeAIAuth.checkLoggedIn()
        }
    }

    func signOutClaudeAI() {
        Task { @MainActor in
            await ClaudeAIAuth.signOut()
            self.isLoggedIn = false
            self.scrapedUsage = nil
            self.updateStatusBar()
        }
    }

    init() {
        let ud = UserDefaults.standard

        // One-time migration: clear hardcoded Pro/Max defaults so auto-detect from
        // rate_limit events takes over (much more accurate than guessing the plan).
        if ud.integer(forKey: "configVersion") < 2 {
            ud.removeObject(forKey: "sessionTokenLimit")
            ud.removeObject(forKey: "weeklyTokenLimit")
            ud.set(2, forKey: "configVersion")
        }

        // 0 = auto-detect (uses rate_limit events from JSONL)
        sessionTokenLimit = ud.object(forKey: "sessionTokenLimit") != nil
            ? ud.integer(forKey: "sessionTokenLimit") : 0
        weeklyTokenLimit  = ud.object(forKey: "weeklyTokenLimit")  != nil
            ? ud.integer(forKey: "weeklyTokenLimit")  : 0
        refreshInterval   = ud.object(forKey: "refreshInterval")   != nil
            ? ud.double(forKey: "refreshInterval")    : 30.0
        selectedModel     = ud.string(forKey: "selectedModel") ?? "sonnet"
    }

    // Reschedule periodic timer when interval changes
    private func reschedule() {
        schedulePeriodicRefresh()
    }

    func startWatching() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects").path

        watcher = FileWatcher(path: claudeDir) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        schedulePeriodicRefresh()

        refreshLoginStatus()
        if useClaudeAISource { startScraping() }
    }

    // MARK: - claude.ai scraping
    func startScraping() {
        runScrape()
        scheduleNextScrape()
    }

    func stopScraping() {
        scrapeTimer?.invalidate()
        scrapeTimer = nil
        scraper = nil
    }

    private func scheduleNextScrape() {
        scrapeTimer?.invalidate()
        // If at limit, don't scrape — countdown timer handles UI updates locally
        if isInCountdownMode { return }
        scrapeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runScrape()
                self?.scheduleNextScrape()
            }
        }
    }

    func runScrape() {
        // Skip if in countdown mode (saves CPU + bandwidth)
        if isInCountdownMode {
            updateStatusBar()
            return
        }
        let s = ClaudeAIScraper()
        scraper = s
        s.scrape { [weak self] result in
            Task { @MainActor in
                if let r = result {
                    self?.scrapedUsage = r
                    self?.evaluateCountdownMode()
                }
                self?.updateStatusBar()
                self?.scraper = nil
            }
        }
    }

    // MARK: - Countdown Mode
    var isInCountdownMode: Bool {
        guard let s = scrapedUsage, !s.isStale else { return false }
        if s.sessionAtLimit, let r = s.sessionResetTime, r > Date() { return true }
        if s.weeklyAtLimit,  let r = s.weeklyResetTime,  r > Date() { return true }
        return false
    }

    private func evaluateCountdownMode() {
        if isInCountdownMode {
            startCountdownTicks()
        } else {
            stopCountdownTicks()
        }
    }

    private func startCountdownTicks() {
        countdownTimer?.invalidate()
        // 1-second tick when ≤ 60s remaining (for second-by-second display),
        // otherwise 60s tick (minute-by-minute display)
        let interval = nearestResetWithinSeconds(60) ? 1.0 : 60.0
        countdownTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.countdownTick() }
        }
    }

    private func stopCountdownTicks() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func countdownTick() {
        // Refresh status bar
        updateStatusBar()
        // Notify observers (popup re-renders)
        objectWillChange.send()

        // If reset reached, exit countdown mode and resume scraping
        if !isInCountdownMode {
            stopCountdownTicks()
            scrapedUsage = nil   // force a fresh scrape
            if useClaudeAISource { startScraping() }
            return
        }

        // Adjust tick frequency when crossing the 60s boundary
        let needFastTick = nearestResetWithinSeconds(60)
        let isFastTick   = (countdownTimer?.timeInterval ?? 60) <= 1.5
        if needFastTick != isFastTick {
            startCountdownTicks()
        }
    }

    private func nearestResetWithinSeconds(_ seconds: TimeInterval) -> Bool {
        guard let s = scrapedUsage else { return false }
        let candidates = [s.sessionResetTime, s.weeklyResetTime].compactMap { $0 }
        return candidates.contains { $0.timeIntervalSinceNow <= seconds && $0.timeIntervalSinceNow > 0 }
    }

    func openClaudeAILogin() {
        let s = scraper ?? ClaudeAIScraper()
        scraper = s
        s.showLoginWindow()
    }

    func refresh() {
        isLoading = true
        Task {
            let result = await UsageParser.parse()
            self.data = result
            self.isLoading = false
            self.updateStatusBar()
        }
    }

    private func schedulePeriodicRefresh() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Model switching
    func setModel(_ key: String, fullId: String) {
        selectedModel = key
        writeModelToClaudeSettings(fullId)
    }

    private func writeModelToClaudeSettings(_ modelId: String) {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        var dict: [String: Any] = [:]
        if let existing = try? Data(contentsOf: path),
           let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            dict = parsed
        }
        dict["model"] = modelId

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: data, encoding: .utf8) else { return }
        try? pretty.write(to: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Status bar
    func updateStatusBar() {
        guard let button = statusItem?.button else { return }
        if let img = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
            img.size = NSSize(width: 14, height: 14)
            button.image = img
        }

        let sessionDisplay = currentSessionDisplay()
        let weeklyDisplay  = currentWeeklyDisplay()
        button.title = " \(sessionDisplay) | \(weeklyDisplay)"
    }

    // MARK: - Display formatters (used by both menu bar and popup)
    func currentSessionDisplay() -> String {
        if useClaudeAISource, let s = scrapedUsage, !s.isStale {
            if s.sessionAtLimit, let reset = s.sessionResetTime {
                return formatSessionCountdown(reset.timeIntervalSinceNow)
            }
            if let pct = s.sessionPct {
                return String(format: "%.2f%%", pct)
            }
        }
        // Local fallback
        let sessionLimit = sessionTokenLimit > 0 ? sessionTokenLimit : max(1, data.detectedSessionLimit)
        if let block = data.currentBlock, block.isActive {
            let frac = Double(block.tokens) / Double(sessionLimit)
            if frac >= 0.9999 {
                return formatSessionCountdown(block.timeUntilReset)
            }
            return String(format: "%.2f%%", min(frac, 1.0) * 100)
        }
        return "0.00%"
    }

    func currentWeeklyDisplay() -> String {
        if useClaudeAISource, let s = scrapedUsage, !s.isStale {
            if s.weeklyAtLimit, let reset = s.weeklyResetTime {
                return formatWeeklyCountdown(reset.timeIntervalSinceNow)
            }
            if let pct = s.weeklyPct {
                return String(format: "%.2f%%", pct)
            }
        }
        let weekLimit = weeklyTokenLimit > 0 ? weeklyTokenLimit : max(1, data.detectedWeeklyLimit)
        let frac = Double(data.weeklyBlock.tokens) / Double(weekLimit)
        if frac >= 0.9999 {
            return formatWeeklyCountdown(data.weeklyBlock.timeUntilReset)
        }
        return String(format: "%.2f%%", min(frac, 1.0) * 100)
    }

    /// Session reset (max 5h). Shown as ">4h", "<4h", "<3h", "<2h", "59m"…"1m", "59s"…"0s"
    func formatSessionCountdown(_ secs: TimeInterval) -> String {
        let s = max(0, Int(secs))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let h = m / 60
        if h >= 4 { return ">4h" }
        if h >= 3 { return "<4h" }
        if h >= 2 { return "<3h" }
        if h >= 1 { return "<2h" }
        return "\(m)m"
    }

    /// Weekly reset. If > 1 day: "1d 22h", "4d 22h". Otherwise same as session.
    func formatWeeklyCountdown(_ secs: TimeInterval) -> String {
        let s = max(0, Int(secs))
        let d = s / 86400
        if d >= 1 {
            let h = (s % 86400) / 3600
            return "\(d)d \(h)h"
        }
        return formatSessionCountdown(secs)
    }

}

// MARK: - Formatting
extension UsageStore {
    func formatTokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000_000 { return String(format: "%.1fG", d / 1_000_000_000) }
        if d >= 1_000_000     { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000         { return String(format: "%.0fK", d / 1_000) }
        return "\(n)"
    }

    func formatCost(_ v: Double) -> String { String(format: "$%.2f", v) }

    func formatDuration(_ secs: TimeInterval) -> String {
        let s = Int(secs)
        if s < 60 { return "\(s)s" }
        let m = s / 60; let h = m / 60
        if h > 0 { return "\(h)h \(m % 60)m" }
        return "\(m)m"
    }
}
