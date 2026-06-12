import Foundation
import WebKit

// Claude usage via the internal claude.ai JSON API:
//   GET /api/organizations               -> org uuid (cached 24h, prefers lastActiveOrg cookie)
//   GET /api/organizations/{id}/usage    -> { five_hour: {utilization, resets_at},
//                                            seven_day: {utilization, resets_at} }
// Primary path is plain URLSession with cookies from the default WKWebsiteDataStore.
// If that's blocked (e.g. Cloudflare), falls back to fetch() inside a hidden WebView.
@MainActor
final class ClaudeProvider: UsageProvider {
    let id = ProviderID.claude
    private let dataStore = ProviderDataStores.store(for: .claude)
    private lazy var webFetcher = WebViewFetcher(dataStore: dataStore)

    private static let orgIDKey = "claudeOrgID"
    private static let orgIDDateKey = "claudeOrgIDFetchedAt"

    // MARK: - Auth

    func checkAuth() async -> AuthState {
        let signedIn = await dataStore.hasCookie(domain: "claude.ai") { $0.name == "sessionKey" }
        return signedIn ? .signedIn : .signedOut
    }

    func presentLogin(onComplete: @escaping @MainActor () -> Void) {
        WebAuthController.show(WebAuthController.Config(
            providerID: .claude,
            title: "Sign in to Claude",
            startURL: URL(string: "https://claude.ai/login")!,
            dataStore: dataStore,
            loginCheck: { _, url in
                let s = url.absoluteString
                return s.hasPrefix("https://claude.ai/") && !s.contains("/login") && !s.contains("/auth")
            }
        ), onComplete: onComplete)
    }

    func signOut() async {
        await dataStore.clearCookies(domain: "claude.ai")
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Self.orgIDKey)
        ud.removeObject(forKey: Self.orgIDDateKey)
        webFetcher.release()
    }

    // MARK: - Fetch

    func fetchUsage() async -> FetchResult {
        let cookies = await dataStore.cookies(matching: "claude.ai")
        guard cookies.contains(where: { $0.name == "sessionKey" && !$0.value.isEmpty }) else {
            return .authExpired
        }

        switch await fetchViaURLSession(cookies: cookies) {
        case .success(let u): return .success(u)
        case .authExpired:    return .authExpired
        case .failure:        return await fetchViaWebView()
        }
    }

    func releaseIdleResources() {
        webFetcher.release()
    }

    private func fetchViaURLSession(cookies: [HTTPCookie]) async -> FetchResult {
        do {
            guard let orgID = try await resolveOrgID(cookies: cookies) else { return .failure }
            let url = URL(string: "https://claude.ai/api/organizations/\(orgID)/usage")!
            let (json, status) = try await CookieAPIFetcher.getJSON(
                url: url, cookies: cookies, referer: "https://claude.ai/settings/usage")
            if status == 401 { return .authExpired }
            guard status == 200, let obj = json as? [String: Any] else { return .failure }
            guard let usage = Self.parseUsage(obj) else { return .failure }
            return .success(usage)
        } catch {
            return .failure
        }
    }

    private func resolveOrgID(cookies: [HTTPCookie]) async throws -> String? {
        // The web app records the active org in a cookie — trust it first.
        if let c = cookies.first(where: { $0.name == "lastActiveOrg" }), !c.value.isEmpty {
            return c.value
        }
        let ud = UserDefaults.standard
        if let cached = ud.string(forKey: Self.orgIDKey),
           Date().timeIntervalSince(ud.object(forKey: Self.orgIDDateKey) as? Date ?? .distantPast) < 24 * 3600 {
            return cached
        }
        let (json, status) = try await CookieAPIFetcher.getJSON(
            url: URL(string: "https://claude.ai/api/organizations")!,
            cookies: cookies, referer: "https://claude.ai/")
        guard status == 200, let orgs = json as? [[String: Any]], !orgs.isEmpty else { return nil }
        let preferred = orgs.first {
            (($0["capabilities"] as? [String]) ?? []).contains("chat")
        } ?? orgs[0]
        guard let uuid = preferred["uuid"] as? String else { return nil }
        ud.set(uuid, forKey: Self.orgIDKey)
        ud.set(Date(), forKey: Self.orgIDDateKey)
        return uuid
    }

    // Fallback: same API calls but from inside the logged-in page context,
    // which inherits WebKit's TLS/cookie handling (gets past Cloudflare).
    private func fetchViaWebView() async -> FetchResult {
        let script = """
        try {
            const headers = { 'Accept': 'application/json' };
            const orgRes = await fetch('/api/organizations', { credentials: 'include', headers });
            if (orgRes.status === 401 || orgRes.status === 403) return JSON.stringify({ error: 'auth' });
            if (!orgRes.ok) return JSON.stringify({ error: 'http_' + orgRes.status });
            const orgs = await orgRes.json();
            const org = Array.isArray(orgs) && orgs.length
                ? ((orgs.find(o => (o.capabilities || []).includes('chat')) || orgs[0]).uuid)
                : null;
            if (!org) return JSON.stringify({ error: 'noorg' });
            const r = await fetch('/api/organizations/' + org + '/usage', { credentials: 'include', headers });
            if (r.status === 401 || r.status === 403) return JSON.stringify({ error: 'auth' });
            if (!r.ok) return JSON.stringify({ error: 'http_' + r.status });
            return JSON.stringify({ data: await r.json() });
        } catch (e) {
            return JSON.stringify({ error: String(e) });
        }
        """
        guard let raw = await webFetcher.run(
                pageURL: URL(string: "https://claude.ai/")!, script: script),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            webFetcher.invalidatePage()
            return .failure
        }
        if (obj["error"] as? String) == "auth" { return .authExpired }
        guard let payload = obj["data"] as? [String: Any],
              let usage = Self.parseUsage(payload) else {
            webFetcher.invalidatePage()
            return .failure
        }
        return .success(usage)
    }

    private static func parseUsage(_ obj: [String: Any]) -> ProviderUsage? {
        var u = ProviderUsage(fetchedAt: Date())
        if let fh = obj["five_hour"] as? [String: Any] {
            u.sessionPct = providerPct(fh["utilization"])
            u.sessionResetAt = providerDate(fh["resets_at"])
        }
        if let sd = obj["seven_day"] as? [String: Any] {
            u.weeklyPct = providerPct(sd["utilization"])
            u.weeklyResetAt = providerDate(sd["resets_at"])
        }
        guard u.sessionPct != nil || u.weeklyPct != nil else { return nil }
        return u
    }
}
