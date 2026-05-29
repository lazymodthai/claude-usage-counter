import Foundation
import WebKit
import AppKit

struct ScrapedUsage: Sendable {
    var sessionPct: Double?
    var weeklyPct: Double?
    var sessionResetText: String?       // e.g. "57 min" (raw)
    var weeklyResetText: String?        // e.g. "Tue 4:59 AM" (raw)
    var sessionResetTime: Date?         // parsed absolute time
    var weeklyResetTime: Date?          // parsed absolute time
    var fetchedAt: Date = Date()
    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 600 }

    var sessionAtLimit: Bool { (sessionPct ?? 0) >= 99.99 }
    var weeklyAtLimit: Bool { (weeklyPct ?? 0) >= 99.99 }
    var atLimit: Bool { sessionAtLimit || weeklyAtLimit }
}

// MARK: - Reset Time Parsers
enum ResetTimeParser {
    /// Parse "57 min", "1h 23m", "1 hour 23 minutes", "1h" into a future Date
    static func parseSessionReset(_ text: String, relativeTo: Date) -> Date? {
        var total: TimeInterval = 0

        let hRegex  = try? NSRegularExpression(pattern: #"(\d+)\s*h"#, options: .caseInsensitive)
        let mRegex  = try? NSRegularExpression(pattern: #"(\d+)\s*m"#, options: .caseInsensitive)
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)

        if let m = hRegex?.firstMatch(in: text, range: range), m.numberOfRanges >= 2 {
            if let v = Int(ns.substring(with: m.range(at: 1))) { total += TimeInterval(v * 3600) }
        }
        if let m = mRegex?.firstMatch(in: text, range: range), m.numberOfRanges >= 2 {
            if let v = Int(ns.substring(with: m.range(at: 1))) { total += TimeInterval(v * 60) }
        }
        return total > 0 ? relativeTo.addingTimeInterval(total) : nil
    }

    /// Parse "Tue 4:59 AM", "Tuesday at 5:00 AM", "Mon 12:00 PM" → next occurrence of that weekday/time
    static func parseWeeklyReset(_ text: String, relativeTo: Date) -> Date? {
        let pattern = #"(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*\s+(?:at\s+)?(\d{1,2}):(\d{2})\s*(AM|PM)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 5 else { return nil }

        let dayStr = ns.substring(with: m.range(at: 1)).lowercased()
        let hour = Int(ns.substring(with: m.range(at: 2))) ?? 0
        let mins = Int(ns.substring(with: m.range(at: 3))) ?? 0
        let ampm = ns.substring(with: m.range(at: 4)).lowercased()

        let dayMap = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        guard let weekday = dayMap[dayStr] else { return nil }

        var hour24 = hour
        if ampm == "pm" && hour < 12 { hour24 += 12 }
        if ampm == "am" && hour == 12 { hour24 = 0 }

        var comp = DateComponents()
        comp.weekday = weekday
        comp.hour = hour24
        comp.minute = mins
        comp.second = 0
        return Calendar.current.nextDate(after: relativeTo, matching: comp, matchingPolicy: .nextTime)
    }
}

// MARK: - Login Window Controller
// Owns the login NSWindow/WKWebView and retains them until explicitly closed.
@MainActor
final class LoginWindowController: NSObject, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    static var shared: LoginWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = LoginWindowController()
        shared = ctrl
        ctrl.openWindow()
    }

    private func openWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Sign in to Claude.ai"
        w.isReleasedWhenClosed = false        // CRITICAL: ARC manages lifetime
        w.delegate = self
        w.center()
        w.level = .floating

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // persist cookies across launches
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let wv = WKWebView(frame: w.contentView!.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        w.contentView?.addSubview(wv)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = w
        self.webView = wv
    }

    // Handle window.open() popups (Google SSO uses these) by loading in same view
    nonisolated func webView(_ webView: WKWebView,
                             createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction,
                             windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            DispatchQueue.main.async { webView.load(URLRequest(url: url)) }
        }
        return nil
    }

    // Detect "logged in" state — when redirected back to claude.ai (not login page)
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url?.absoluteString else { return }
            // Once user lands on claude.ai (not on /login/* or accounts.google.com), we're done.
            if url.hasPrefix("https://claude.ai/") && !url.contains("/login") && !url.contains("/auth") {
                // small delay so cookies are fully persisted
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.window?.close()
                }
            }
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.webView?.navigationDelegate = nil
            self.webView?.uiDelegate = nil
            self.webView = nil
            self.window = nil
            LoginWindowController.shared = nil
        }
    }
}

// MARK: - Background Scraper
// Checks claude.ai login status by inspecting WKWebsiteDataStore cookies.
enum ClaudeAIAuth {
    @MainActor
    static func checkLoggedIn() async -> Bool {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let loggedIn = cookies.contains { cookie in
                    cookie.domain.contains("claude.ai")
                        && (cookie.name == "sessionKey" || cookie.name == "lastActiveOrg")
                        && !cookie.value.isEmpty
                }
                continuation.resume(returning: loggedIn)
            }
        }
    }

    /// Inject a sessionKey copied from another browser (e.g. Chrome DevTools) so the
    /// app reuses that login. Returns whether claude.ai is now considered signed in.
    @MainActor
    static func setSessionKey(_ value: String) async -> Bool {
        let props: [HTTPCookiePropertyKey: Any] = [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: value,
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(365 * 24 * 3600),
        ]
        guard let cookie = HTTPCookie(properties: props) else { return false }
        let store = WKWebsiteDataStore.default().httpCookieStore
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.setCookie(cookie) { cont.resume() }
        }
        return await checkLoggedIn()
    }

    @MainActor
    static func signOut() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let group = DispatchGroup()
                for c in cookies where c.domain.contains("claude.ai") {
                    group.enter()
                    WKWebsiteDataStore.default().httpCookieStore.delete(c) { group.leave() }
                }
                group.notify(queue: .main) { continuation.resume() }
            }
        }
    }
}

@MainActor
final class ClaudeAIScraper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((ScrapedUsage?) -> Void)?

    func scrape(completion: @escaping (ScrapedUsage?) -> Void) {
        if webView != nil { completion(nil); return }
        self.completion = completion

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 900), configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView = wv

        wv.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.finishWithFailure()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.pollForData(attemptsLeft: 6) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishWithFailure() }
    }

    private func pollForData(attemptsLeft: Int) {
        guard let wv = webView else { return }
        guard attemptsLeft > 0 else { finishWithFailure(); return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            wv.evaluateJavaScript(Self.extractionScript) { result, _ in
                guard let str = result as? String,
                      let data = str.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self?.pollForData(attemptsLeft: attemptsLeft - 1)
                    return
                }
                let now = Date()
                let sessionText = obj["sessionReset"] as? String
                let weeklyText = obj["weeklyReset"] as? String
                let scraped = ScrapedUsage(
                    sessionPct: (obj["sessionPct"] as? NSNumber)?.doubleValue,
                    weeklyPct: (obj["weeklyPct"] as? NSNumber)?.doubleValue,
                    sessionResetText: sessionText,
                    weeklyResetText: weeklyText,
                    sessionResetTime: sessionText.flatMap { ResetTimeParser.parseSessionReset($0, relativeTo: now) },
                    weeklyResetTime: weeklyText.flatMap { ResetTimeParser.parseWeeklyReset($0, relativeTo: now) },
                    fetchedAt: now
                )
                if scraped.sessionPct != nil || scraped.weeklyPct != nil {
                    Task { @MainActor in self?.finishWithSuccess(scraped) }
                } else {
                    self?.pollForData(attemptsLeft: attemptsLeft - 1)
                }
            }
        }
    }

    private func finishWithSuccess(_ result: ScrapedUsage) {
        let cb = completion; cleanup(); cb?(result)
    }
    private func finishWithFailure() {
        let cb = completion; cleanup(); cb?(nil)
    }
    private func cleanup() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        completion = nil
    }

    func showLoginWindow() {
        LoginWindowController.show()
    }

    private static let extractionScript = """
    (function() {
        var out = {};
        // Normalize non-breaking spaces so regexes match reliably.
        var text = (document.body.innerText || "").replace(/\\u00a0/g, " ");

        // --- Percentages: match each value to its labelled section, ---
        // --- then fall back to positional order (session first, weekly second). ---
        function pctNear(labelRe) {
            var idx = text.search(labelRe);
            if (idx < 0) return null;
            var m = text.slice(idx, idx + 220).match(/(\\d+(?:\\.\\d+)?)\\s*%/);
            return m ? parseFloat(m[1]) : null;
        }

        var sessionPct = pctNear(/current\\s+session/i);
        var weeklyPct  = pctNear(/all\\s+models/i);
        if (weeklyPct === null) weeklyPct = pctNear(/weekly/i);

        if (sessionPct === null || weeklyPct === null) {
            var pcts = [], re = /(\\d+(?:\\.\\d+)?)\\s*%/g, m;
            while ((m = re.exec(text)) !== null) pcts.push(parseFloat(m[1]));
            if (sessionPct === null && pcts.length >= 1) sessionPct = pcts[0];
            if (weeklyPct  === null && pcts.length >= 2) weeklyPct  = pcts[1];
        }
        if (sessionPct !== null) out.sessionPct = sessionPct;
        if (weeklyPct  !== null) out.weeklyPct  = weeklyPct;

        // --- Session reset: relative, e.g. "resets in 57 min" ---
        var sessReset = text.match(/resets?\\s+in\\s+([^\\n.,;]+?)(?=[\\n.,;]|$)/i);
        if (sessReset) out.sessionReset = sessReset[1].trim();

        // --- Weekly reset: absolute day + time, e.g. "Resets Tue 5:00 AM" / ---
        // --- "Resets Tuesday at 5:00 AM". Search the weekly section first, ---
        // --- crossing newlines since label and time are separate DOM nodes. ---
        var dayTime = /(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*\\s+(?:at\\s+)?(\\d{1,2}:\\d{2})\\s*([AaPp]\\.?[Mm]\\.?)/;
        var wIdx = text.search(/all\\s+models/i);
        if (wIdx < 0) wIdx = text.search(/weekly/i);
        var scope = wIdx >= 0 ? text.slice(wIdx, wIdx + 320) : text;
        var w = scope.match(dayTime) || text.match(dayTime);
        if (w) {
            out.weeklyReset = w[1].slice(0, 3) + " " + w[2] + " " +
                              w[3].replace(/\\./g, "").toUpperCase();
        }

        return JSON.stringify(out);
    })();
    """
}
