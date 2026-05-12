import Foundation

struct TokenUsage: Sendable {
    var input: Int = 0
    var output: Int = 0
    var cacheWrite: Int = 0
    var cacheRead: Int = 0

    var total: Int { input + output + cacheWrite + cacheRead }
    var billed: Int { input + output }
}

struct ModelStats: Sendable, Identifiable {
    let id: String
    let displayName: String
    var cost: Double = 0
    var usage: TokenUsage = .init()
    var messages: Int = 0
}

struct PeriodStats: Sendable {
    var cost: Double = 0
    var usage: TokenUsage = .init()
    var messages: Int = 0
    var toolCalls: Int = 0
    var byModel: [String: ModelStats] = [:]

    mutating func add(model: String, cost c: Double, usage u: TokenUsage, tools t: Int) {
        cost += c
        usage.input += u.input
        usage.output += u.output
        usage.cacheWrite += u.cacheWrite
        usage.cacheRead += u.cacheRead
        messages += 1
        toolCalls += t
        let key = modelKey(model)
        var m = byModel[key] ?? ModelStats(id: key, displayName: modelDisplayName(model))
        m.cost += c
        m.usage.input += u.input
        m.usage.output += u.output
        m.usage.cacheWrite += u.cacheWrite
        m.usage.cacheRead += u.cacheRead
        m.messages += 1
        byModel[key] = m
    }
}

struct DayStats: Sendable, Identifiable {
    var id: Date { date }
    let date: Date
    var messages: Int = 0
    var cost: Double = 0
    var tokens: Int = 0
}

// A 5-hour billing block — matches ccusage "blocks" concept
struct BillingBlock: Sendable {
    var blockStart: Date        // floor to nearest hour of first message
    var lastActivity: Date
    var tokens: Int = 0
    var cost: Double = 0
    var messages: Int = 0
    var models: [String] = []

    // Set after computing max across all blocks
    var maxTokens: Int = 1
    var usedFraction: Double { Double(tokens) / Double(max(1, maxTokens)) }

    var resetTime: Date { blockStart.addingTimeInterval(5 * 3600) }
    var timeUntilReset: TimeInterval { max(0, resetTime.timeIntervalSinceNow) }

    // Block is "active" if there was activity in the last 5h AND we're before reset
    var isActive: Bool {
        timeUntilReset > 0 && Date().timeIntervalSince(lastActivity) < 5 * 3600
    }
}

// Weekly usage stats (Sun–Sat, resets Monday 00:00 local)
struct WeeklyBlock: Sendable {
    var tokens: Int = 0
    var cost: Double = 0
    var messages: Int = 0
    var models: [String] = []

    var maxTokens: Int = 1
    var usedFraction: Double { Double(tokens) / Double(max(1, maxTokens)) }

    // Time until next Monday midnight (local)
    var timeUntilReset: TimeInterval {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now) // 1=Sun
        let daysUntilMonday = weekday == 2 ? 7 : (2 - weekday + 7) % 7
        guard let nextMonday = cal.date(byAdding: .day, value: daysUntilMonday, to: cal.startOfDay(for: now)) else { return 0 }
        return max(0, nextMonday.timeIntervalSinceNow)
    }
}

struct UsageData: Sendable {
    var today: PeriodStats = .init()
    var week: PeriodStats = .init()
    var month: PeriodStats = .init()

    var currentBlock: BillingBlock? = nil
    var weeklyBlock: WeeklyBlock = .init()

    // Auto-detected from history (same method as ccusage)
    var detectedSessionLimit: Int = 1
    var detectedWeeklyLimit: Int = 1

    var last7Days: [DayStats] = []
    var totalSessions: Int = 0
    var firstUsageDate: Date? = nil
    var lastUpdated: Date = Date()
}

func modelKey(_ model: String) -> String {
    let m = model.lowercased()
    if m.contains("opus") { return "opus" }
    if m.contains("sonnet") { return "sonnet" }
    if m.contains("haiku") { return "haiku" }
    return "other"
}

func modelDisplayName(_ model: String) -> String {
    switch modelKey(model) {
    case "opus": return "Opus"
    case "sonnet": return "Sonnet"
    case "haiku": return "Haiku"
    default: return model
    }
}
