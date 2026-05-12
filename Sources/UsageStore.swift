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
        scrapeTimer?.invalidate()
        // Refresh from claude.ai every 60s (page is rate-limited / heavy)
        scrapeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runScrape() }
        }
    }

    func stopScraping() {
        scrapeTimer?.invalidate()
        scrapeTimer = nil
        scraper = nil
    }

    func runScrape() {
        let s = ClaudeAIScraper()
        scraper = s
        s.scrape { [weak self] result in
            Task { @MainActor in
                if let r = result { self?.scrapedUsage = r }
                self?.updateStatusBar()
                self?.scraper = nil
            }
        }
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

        // Prefer scraped values from claude.ai if available
        if useClaudeAISource, let s = scrapedUsage, !s.isStale,
           let sp = s.sessionPct, let wp = s.weeklyPct {
            button.title = String(format: " %.2f%% | %.2f%%", sp, wp)
            return
        }

        let sessionLimit = sessionTokenLimit > 0 ? sessionTokenLimit : max(1, data.detectedSessionLimit)
        let weekLimit   = weeklyTokenLimit  > 0 ? weeklyTokenLimit  : max(1, data.detectedWeeklyLimit)

        let sessionPct: Double
        if let block = data.currentBlock, block.isActive {
            sessionPct = min(Double(block.tokens) / Double(sessionLimit), 1.0) * 100
        } else {
            sessionPct = 0
        }
        let weeklyPct = min(Double(data.weeklyBlock.tokens) / Double(weekLimit), 1.0) * 100
        button.title = String(format: " %.2f%% | %.2f%%", sessionPct, weeklyPct)
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
