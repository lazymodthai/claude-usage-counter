import SwiftUI
import Charts

// MARK: - Theme
extension Color {
    static let appBg      = Color(red: 0.051, green: 0.051, blue: 0.059) // #0d0d0f
    static let cardBg     = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let divider    = Color.white.opacity(0.07)
    static let accent     = Color(red: 1.0, green: 0.62, blue: 0.0)      // orange
    static let chartPink  = Color(red: 1.0, green: 0.18, blue: 0.33)
    static let opusBlue   = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let sonnetCyan = Color(red: 0.20, green: 0.68, blue: 0.90)
    static let haikuGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
}

func modelColor(_ key: String) -> Color {
    switch key {
    case "opus":   return .opusBlue
    case "sonnet": return .sonnetCyan
    case "haiku":  return .haikuGreen
    default:       return .white.opacity(0.4)
    }
}

// MARK: - Root
struct ContentView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderRow()
                Rectangle().fill(Color.divider).frame(height: 1)
                UsageBarsSection()
                Rectangle().fill(Color.divider).frame(height: 1)
                ModelSelectorRow()
            }
        }
        .frame(width: 320)
    }
}

// MARK: - Header
struct HeaderRow: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accent)
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            LoginStatusBadge(isLoggedIn: store.isLoggedIn)
            Spacer()
            if store.isLoading {
                ProgressView().scaleEffect(0.55).tint(Color.white.opacity(0.5))
            }
            Button(action: { store.refresh(); store.runScrape() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Button(action: { store.refreshLoginStatus(); store.showSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $store.showSettings) {
                SettingsView().environmentObject(store)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Usage Bars (main section, like claudeusagebar.com)
struct UsageBarsSection: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(spacing: 16) {
            UsageBarRow(
                label: "Current Session",
                icon: "clock.fill",
                iconColor: .accent,
                fraction: sessionFraction,
                used: sessionUsedText,
                limit: sessionLimitText,
                resetLabel: sessionResetLabel,
                isActive: sessionIsActive
            )

            UsageBarRow(
                label: "Weekly — All Models",
                icon: "calendar",
                iconColor: .sonnetCyan,
                fraction: weeklyFraction,
                used: weeklyUsedText,
                limit: weeklyLimitText,
                resetLabel: weeklyResetLabel,
                isActive: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)

        HStack(spacing: 4) {
            if usingScraped {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.haikuGreen)
                Text("Live from claude.ai")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.haikuGreen.opacity(0.8))
                Text("·")
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            Text("Updated \((store.scrapedUsage?.fetchedAt ?? store.data.lastUpdated).formatted(.dateTime.hour().minute().second()))")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.3))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Data source selection
    private var usingScraped: Bool {
        store.useClaudeAISource && (store.scrapedUsage?.isStale == false)
    }

    private var effectiveSessionLimit: Int {
        store.sessionTokenLimit > 0 ? store.sessionTokenLimit : max(1, store.data.detectedSessionLimit)
    }
    private var effectiveWeeklyLimit: Int {
        store.weeklyTokenLimit > 0 ? store.weeklyTokenLimit : max(1, store.data.detectedWeeklyLimit)
    }

    // MARK: - Session
    private var sessionAtLimit: Bool {
        if usingScraped { return store.scrapedUsage?.sessionAtLimit == true }
        guard let block = store.data.currentBlock, block.isActive else { return false }
        return Double(block.tokens) / Double(effectiveSessionLimit) >= 0.9999
    }

    private var sessionFraction: Double {
        if usingScraped, let pct = store.scrapedUsage?.sessionPct {
            return min(pct / 100.0, 1.0)
        }
        guard let block = store.data.currentBlock, block.isActive else { return 0 }
        return min(Double(block.tokens) / Double(effectiveSessionLimit), 1.0)
    }

    private var sessionIsActive: Bool {
        if usingScraped { return store.scrapedUsage?.sessionPct != nil }
        return store.data.currentBlock?.isActive ?? false
    }

    private var sessionUsedText: String {
        // When at limit, show countdown instead of percentage
        if sessionAtLimit {
            return store.currentSessionDisplay()
        }
        if usingScraped, let pct = store.scrapedUsage?.sessionPct {
            return String(format: "%.1f%%", pct)
        }
        return store.data.currentBlock.map { store.formatTokens($0.tokens) } ?? "—"
    }

    private var sessionLimitText: String {
        if sessionAtLimit { return "LIMIT REACHED" }
        if usingScraped { return "100%" }
        return store.formatTokens(effectiveSessionLimit) + " tokens"
    }

    private var sessionResetLabel: String {
        if usingScraped, let text = store.scrapedUsage?.sessionResetText {
            return "Resets in \(text)"
        }
        guard let block = store.data.currentBlock, block.isActive else { return "No active session" }
        let remaining = block.timeUntilReset
        let fmt = DateFormatter(); fmt.timeStyle = .short
        if remaining < 60 { return "Resets in < 1m" }
        return "Resets at \(fmt.string(from: block.resetTime)) (\(store.formatDuration(remaining)))"
    }

    // MARK: - Weekly
    private var weeklyAtLimit: Bool {
        if usingScraped { return store.scrapedUsage?.weeklyAtLimit == true }
        return Double(store.data.weeklyBlock.tokens) / Double(effectiveWeeklyLimit) >= 0.9999
    }

    private var weeklyFraction: Double {
        if usingScraped, let pct = store.scrapedUsage?.weeklyPct {
            return min(pct / 100.0, 1.0)
        }
        return min(Double(store.data.weeklyBlock.tokens) / Double(effectiveWeeklyLimit), 1.0)
    }

    private var weeklyUsedText: String {
        if weeklyAtLimit {
            return store.currentWeeklyDisplay()
        }
        if usingScraped, let pct = store.scrapedUsage?.weeklyPct {
            return String(format: "%.1f%%", pct)
        }
        return store.formatTokens(store.data.weeklyBlock.tokens)
    }

    private var weeklyLimitText: String {
        if weeklyAtLimit { return "LIMIT REACHED" }
        if usingScraped { return "100%" }
        return store.formatTokens(effectiveWeeklyLimit) + " tokens"
    }

    private var weeklyResetLabel: String {
        if usingScraped, let text = store.scrapedUsage?.weeklyResetText {
            return "Resets \(text)"
        }
        return "Resets in \(store.formatDuration(store.data.weeklyBlock.timeUntilReset))"
    }
}

struct UsageBarRow: View {
    let label: String
    let icon: String
    let iconColor: Color
    let fraction: Double
    let used: String
    let limit: String
    let resetLabel: String
    let isActive: Bool

    private var pct: Double { fraction * 100 }
    private var barColor: Color {
        if fraction >= 1.0 { return .red }
        if fraction >= 0.9 { return .orange }
        if fraction >= 0.7 { return Color(red: 1, green: 0.75, blue: 0) }
        return .accent
    }

    // If `used` already contains a %, just show "used" — otherwise show "used / limit tokens"
    private var infoText: String {
        if used.contains("%") { return "" }
        return "\(used) / \(limit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label row
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                Spacer()
                if isActive && fraction > 0 {
                    Text(String(format: "%.2f%%", pct))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(barColor)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.9), barColor],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                        .animation(.easeOut(duration: 0.5), value: fraction)
                }
            }
            .frame(height: 8)
            .cornerRadius(4)

            // Token counts + reset
            HStack {
                Text(infoText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                Spacer()
                Text(resetLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(barColor.opacity(0.8))
            }
        }
    }
}

// MARK: - Model Selector
struct ModelSelectorRow: View {
    @EnvironmentObject var store: UsageStore

    private let models: [(key: String, label: String, full: String)] = [
        ("opus",   "Opus",   "claude-opus-4-7"),
        ("sonnet", "Sonnet", "claude-sonnet-4-6"),
        ("haiku",  "Haiku",  "claude-haiku-4-5-20251001"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "cpu")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.leading, 14)
                .padding(.trailing, 6)

            Text("Model:")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.trailing, 8)

            HStack(spacing: 4) {
                ForEach(models, id: \.key) { m in
                    ModelChip(
                        label: m.label,
                        key: m.key,
                        isSelected: store.selectedModel == m.key
                    ) {
                        store.setModel(m.key, fullId: m.full)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

struct ModelChip: View {
    let label: String
    let key: String
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { modelColor(key) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? color : color.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? color : Color.white.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? color.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Login Status Badge
struct LoginStatusBadge: View {
    let isLoggedIn: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isLoggedIn ? Color.haikuGreen : Color.white.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(isLoggedIn ? "Signed in" : "Not signed in")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isLoggedIn ? Color.haikuGreen : Color.white.opacity(0.35))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            (isLoggedIn ? Color.haikuGreen : Color.white).opacity(0.08)
        )
        .cornerRadius(4)
    }
}

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss

    @State private var sessionLimitText = ""
    @State private var weeklyLimitText = ""
    @State private var intervalText = ""

    private let proSessionLimit  = 8_800_000
    private let proWeeklyLimit   = 88_000_000
    private let maxSessionLimit  = 44_000_000
    private let maxWeeklyLimit   = 440_000_000

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Done") { applySettings(); dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Rectangle().fill(Color.divider).frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // claude.ai live source (most accurate)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Data Source", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.5))
                                Spacer()
                                LoginStatusBadge(isLoggedIn: store.isLoggedIn)
                            }

                            Toggle(isOn: $store.useClaudeAISource) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use claude.ai live data")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text("Matches claude.ai/settings/usage exactly")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!store.isLoggedIn)
                            .opacity(store.isLoggedIn ? 1.0 : 0.5)

                            HStack(spacing: 6) {
                                Button(action: {
                                    store.openClaudeAILogin()
                                    // Re-check status after a delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        store.refreshLoginStatus()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: store.isLoggedIn ? "arrow.clockwise.circle" : "person.crop.circle.badge.plus")
                                        Text(store.isLoggedIn ? "Re-authenticate" : "Sign in to claude.ai")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.accent)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.cardBg)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)

                                if store.isLoggedIn {
                                    Button(action: { store.signOutClaudeAI() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                            Text("Sign out")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.cardBg)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if let s = store.scrapedUsage {
                                Text("Last scraped: \(s.fetchedAt.formatted(.dateTime.hour().minute().second()))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.3))
                            }
                        }

                        Rectangle().fill(Color.divider).frame(height: 1)

                        // Plan presets
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Plan Presets (local fallback)", systemImage: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))

                            HStack(spacing: 8) {
                                PlanPresetButton(label: "Pro", sublabel: "8.8M / 88M") {
                                    sessionLimitText = "\(proSessionLimit)"
                                    weeklyLimitText  = "\(proWeeklyLimit)"
                                }
                                PlanPresetButton(label: "Max 5×", sublabel: "44M / 440M") {
                                    sessionLimitText = "\(maxSessionLimit)"
                                    weeklyLimitText  = "\(maxWeeklyLimit)"
                                }
                                PlanPresetButton(label: "Custom", sublabel: "manual") {
                                    // do nothing, let user type
                                }
                            }
                        }

                        Rectangle().fill(Color.divider).frame(height: 1)

                        // Token limits
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Token Limits", systemImage: "cpu")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))

                            SettingField(label: "Session limit (5h block)", placeholder: "8800000", text: $sessionLimitText)
                            SettingField(label: "Weekly limit", placeholder: "88000000", text: $weeklyLimitText)
                        }

                        Rectangle().fill(Color.divider).frame(height: 1)

                        // Refresh
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Refresh Interval", systemImage: "clock")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))
                            SettingField(label: "Interval (seconds)", placeholder: "30", text: $intervalText)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 280)
        .onAppear {
            sessionLimitText = "\(store.sessionTokenLimit)"
            weeklyLimitText  = "\(store.weeklyTokenLimit)"
            intervalText     = String(Int(store.refreshInterval))
            store.refreshLoginStatus()
        }
    }

    private func applySettings() {
        if let v = Int(sessionLimitText), v > 0 { store.sessionTokenLimit = v }
        if let v = Int(weeklyLimitText),  v > 0 { store.weeklyTokenLimit  = v }
        if let v = Double(intervalText),  v >= 10 { store.refreshInterval = v }
    }
}

struct PlanPresetButton: View {
    let label: String
    let sublabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(sublabel)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.cardBg)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SettingField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.cardBg)
                .cornerRadius(6)
        }
    }
}
