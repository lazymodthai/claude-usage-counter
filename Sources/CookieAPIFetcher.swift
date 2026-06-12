import Foundation

// Plain URLSession fetcher that borrows cookies from a provider's
// WKWebsiteDataStore. Much lighter than spinning up a WKWebView —
// used as the primary path for Claude's internal JSON API.
enum CookieAPIFetcher {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieAcceptPolicy = .never   // cookies are managed by WKWebsiteDataStore
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    /// GET `url` with the given cookies. Returns parsed JSON (if any) + HTTP status.
    static func getJSON(url: URL,
                        cookies: [HTTPCookie],
                        referer: String? = nil) async throws -> (json: Any?, status: Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data)
        return (json, status)
    }
}
