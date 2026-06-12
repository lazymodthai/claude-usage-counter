import Foundation
import WebKit

// Codex (ChatGPT) usage via the internal API:
//   GET /api/auth/session                      -> { accessToken }   (cookie auth)
//   GET /backend-api/wham/usage  (Bearer)      -> rate_limit.primary_window (5h)
//                                                 rate_limit.secondary_window (weekly)
// Runs fetch() inside a hidden WebView on chatgpt.com so WebKit handles
// Cloudflare/TLS. Falls back to scraping chatgpt.com/codex/settings/usage.
@MainActor
final class CodexProvider: UsageProvider {
    let id = ProviderID.codex
    private let dataStore = ProviderDataStores.store(for: .codex)
    private lazy var webFetcher = WebViewFetcher(dataStore: dataStore)

    // MARK: - Auth

    private static let loginVerifiedKey = "codexLoginVerified"

    func checkAuth() async -> AuthState {
        // next-auth session cookie (possibly chunked as .0/.1) marks a real login;
        // chatgpt.com sets plenty of cookies even for anonymous visitors.
        let hasSessionCookie = await dataStore.hasCookie(domain: "chatgpt.com") {
            $0.name.contains("session-token")
        }
        if hasSessionCookie { return .signedIn }
        // Cookie names shift across OpenAI auth revisions — if the login window
        // ever verified a token via /api/auth/session, trust that until a fetch
        // says otherwise (it returns .authExpired, which downgrades the state).
        if UserDefaults.standard.bool(forKey: Self.loginVerifiedKey) {
            let hasAnyCookie = await !dataStore.cookies(matching: "chatgpt.com").isEmpty
            if hasAnyCookie { return .signedIn }
        }
        return .signedOut
    }

    func presentLogin(onComplete: @escaping @MainActor () -> Void) {
        WebAuthController.show(WebAuthController.Config(
            providerID: .codex,
            title: "Sign in to ChatGPT",
            startURL: URL(string: "https://chatgpt.com/auth/login")!,
            dataStore: dataStore,
            loginCheck: { wv, url in
                // chatgpt.com serves an anonymous chat page too, so a URL check
                // isn't enough — ask the session endpoint whether we have a token.
                guard url.host?.contains("chatgpt.com") == true,
                      !url.path.contains("/auth") else { return false }
                let js = """
                try {
                    const r = await fetch('/api/auth/session', { credentials: 'include' });
                    if (!r.ok) return false;
                    const j = await r.json();
                    return !!(j && j.accessToken);
                } catch (e) { return false; }
                """
                let res = try? await wv.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .defaultClient)
                let ok = (res as? Bool) ?? false
                if ok { UserDefaults.standard.set(true, forKey: Self.loginVerifiedKey) }
                return ok
            }
        ), onComplete: onComplete)
    }

    func signOut() async {
        webFetcher.release()
        await dataStore.wipeAllData()
        UserDefaults.standard.removeObject(forKey: Self.loginVerifiedKey)
    }

    func releaseIdleResources() {
        webFetcher.release()
    }

    // MARK: - Fetch

    func fetchUsage() async -> FetchResult {
        let result = await fetchViaInternalAPI()
        if case .failure = result {
            return await fetchViaUsagePage()
        }
        return result
    }

    private func fetchViaInternalAPI() async -> FetchResult {
        let script = """
        try {
            const sr = await fetch('/api/auth/session', { credentials: 'include' });
            if (!sr.ok) return JSON.stringify({ error: 'auth' });
            const sj = await sr.json();
            const token = sj && sj.accessToken;
            if (!token) return JSON.stringify({ error: 'auth' });
            const r = await fetch('https://chatgpt.com/backend-api/wham/usage', {
                credentials: 'include',
                headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json' }
            });
            if (r.status === 401 || r.status === 403) return JSON.stringify({ error: 'auth' });
            if (!r.ok) return JSON.stringify({ error: 'http_' + r.status });
            return JSON.stringify({ data: await r.json() });
        } catch (e) {
            return JSON.stringify({ error: String(e) });
        }
        """
        guard let raw = await webFetcher.run(
                pageURL: URL(string: "https://chatgpt.com/")!, script: script),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            webFetcher.invalidatePage()
            return .failure
        }
        if (obj["error"] as? String) == "auth" { return .authExpired }
        guard let payload = obj["data"] as? [String: Any],
              let usage = Self.parseWhamUsage(payload) else {
            return .failure
        }
        return .success(usage)
    }

    // MARK: - wham/usage parsing (tolerant — field names have shifted across versions,
    // and unknown plan_type values must never make the whole fetch fail)

    static func parseWhamUsage(_ root: [String: Any]) -> ProviderUsage? {
        let rl = (root["rate_limit"] as? [String: Any])
              ?? (root["rate_limits"] as? [String: Any])
              ?? root

        func window(_ keys: [String]) -> [String: Any]? {
            for k in keys { if let d = rl[k] as? [String: Any] { return d } }
            return nil
        }
        let primary = window(["primary_window", "primary"])
        let secondary = window(["secondary_window", "secondary"])

        func parseWindow(_ d: [String: Any]?) -> (pct: Double?, reset: Date?, durationSecs: Double?) {
            guard let d else { return (nil, nil, nil) }
            let pct = providerPct(d["used_percent"] ?? d["usage_percent"] ?? d["used_percentage"])
            var reset: Date? = nil
            if let s = providerNum(d["resets_in_seconds"] ?? d["reset_after_seconds"] ?? d["resets_after_seconds"]) {
                reset = Date().addingTimeInterval(s)
            } else if let at = d["resets_at"] ?? d["reset_at"] {
                reset = providerDate(at)
            }
            var dur = providerNum(d["limit_window_seconds"] ?? d["window_seconds"])
            if dur == nil, let mins = providerNum(d["window_minutes"]) { dur = mins * 60 }
            return (pct, reset, dur)
        }

        var p = parseWindow(primary)
        var s = parseWindow(secondary)
        // primary = 5h, secondary = weekly — but trust window durations when present
        if let pd = p.durationSecs, let sd = s.durationSecs, pd > sd {
            swap(&p, &s)
        }

        guard p.pct != nil || s.pct != nil else { return nil }
        var u = ProviderUsage(fetchedAt: Date())
        u.sessionPct = p.pct
        u.sessionResetAt = p.reset
        u.weeklyPct = s.pct
        u.weeklyResetAt = s.reset
        u.planName = (root["plan_type"] as? String)?.capitalized
        return u
    }

    // MARK: - Fallback: scrape the usage settings page

    private func fetchViaUsagePage() async -> FetchResult {
        let script = """
        try {
            if (location.host.indexOf('chatgpt.com') < 0 || location.pathname.indexOf('/auth') >= 0) {
                return JSON.stringify({ error: 'auth' });
            }
            // The meters render async — poll the page text briefly.
            for (let i = 0; i < 8; i++) {
                const text = (document.body.innerText || '').replace(/\\u00a0/g, ' ');
                function near(re) {
                    const idx = text.search(re);
                    if (idx < 0) return null;
                    const seg = text.slice(idx, idx + 260);
                    const m = seg.match(/(\\d+(?:\\.\\d+)?)\\s*%/);
                    if (!m) return null;
                    const around = seg.slice(Math.max(0, m.index - 40), m.index + 40);
                    return { pct: parseFloat(m[1]), remaining: /left|remain/i.test(around) };
                }
                const session = near(/5[\\s-]?hour/i);
                const weekly = near(/week/i);
                if (session || weekly) {
                    return JSON.stringify({ data: { session, weekly } });
                }
                await new Promise(r => setTimeout(r, 1000));
            }
            return JSON.stringify({ error: 'notfound' });
        } catch (e) {
            return JSON.stringify({ error: String(e) });
        }
        """
        guard let raw = await webFetcher.run(
                pageURL: URL(string: "https://chatgpt.com/codex/settings/usage")!,
                script: script,
                reloadIfOlderThan: 0),   // always reload — meters must be fresh
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            webFetcher.invalidatePage()
            return .failure
        }
        if (obj["error"] as? String) == "auth" { return .authExpired }
        guard let payload = obj["data"] as? [String: Any] else { return .failure }

        func usedPct(_ any: Any?) -> Double? {
            guard let d = any as? [String: Any], let pct = providerNum(d["pct"]) else { return nil }
            let remaining = (d["remaining"] as? Bool) ?? false
            return remaining ? max(0, 100 - pct) : pct
        }
        var u = ProviderUsage(fetchedAt: Date())
        u.sessionPct = usedPct(payload["session"])
        u.weeklyPct = usedPct(payload["weekly"])
        guard u.sessionPct != nil || u.weeklyPct != nil else { return .failure }
        return .success(u)
    }
}
