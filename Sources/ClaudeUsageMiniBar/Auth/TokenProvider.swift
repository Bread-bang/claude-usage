import Foundation

/// Serialises access to the shared Claude Code credential and supplies a valid bearer
/// token to the network layer.
///
/// Strategy (in priority order):
/// 1. **Piggyback.** Read Claude Code's credential on every request. While Claude Code is
///    used, *it* refreshes the token and we get fresh tokens for free — no writes, no races.
/// 2. **Self-refresh (opt-in, default on).** If the token is expired/near-expiry and a
///    refresh token is present, exchange it at the OAuth token endpoint and persist the
///    result into this app's OWN Keychain item. Claude Code's item is never written to:
///    modifying another app's item triggers keychain password prompts, and a re-encode
///    would drop fields this app does not model (e.g. `mcpOAuth` server tokens).
///
/// Being an `actor` guarantees only one refresh runs at a time within this process.
actor TokenProvider {
    /// Claude Code's public OAuth client values. These are not secrets (they ship in the
    /// CLI), but they can change between Claude Code releases — refresh is best-effort and
    /// the app degrades gracefully to "re-auth in Claude Code" if it ever stops working.
    private enum OAuth {
        static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
        static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    }

    /// Claude Code's credential item — read-only from this app's perspective.
    private let claudeCodeStore: KeychainStore
    /// This app's own item, holding bundles produced by self-refresh.
    private let refreshStore: KeychainStore
    private let refreshEnabled: Bool
    private let session: URLSession

    init(claudeCodeStore: KeychainStore = KeychainStore(),
         refreshStore: KeychainStore = KeychainStore(service: "ClaudeUsageMiniBar-credentials",
                                                     readPath: .framework),
         refreshEnabled: Bool = true,
         session: URLSession = .shared) {
        self.claudeCodeStore = claudeCodeStore
        self.refreshStore = refreshStore
        self.refreshEnabled = refreshEnabled
        self.session = session
    }

    /// Decodes the freshest credential bundle available: Claude Code's item, or this app's
    /// own self-refreshed copy when that one expires later (i.e. we refreshed more recently
    /// than Claude Code last wrote its item).
    func currentCredentials() throws -> ClaudeCredentials {
        let claudeCode = try ClaudeCredentials.decode(from: claudeCodeStore.readData())
        if let data = try? refreshStore.readData(),
           let local = try? ClaudeCredentials.decode(from: data),
           let localExpiry = local.expiry,
           let claudeCodeExpiry = claudeCode.expiry,
           localExpiry > claudeCodeExpiry {
            return local
        }
        return claudeCode
    }

    /// Returns a usable access token, refreshing first if necessary.
    func validAccessToken(now: Date = Date()) async throws -> String {
        let creds = try currentCredentials()
        guard creds.isExpired(now: now) else { return creds.accessToken }
        guard refreshEnabled, let refreshToken = creds.refreshToken else {
            throw UsageError.tokenExpired
        }
        return try await refresh(using: refreshToken, base: creds)
    }

    /// Forces a refresh regardless of expiry — used to recover from a 401.
    func forceRefresh() async throws -> String {
        let creds = try currentCredentials()
        guard refreshEnabled, let refreshToken = creds.refreshToken else {
            throw UsageError.tokenExpired
        }
        return try await refresh(using: refreshToken, base: creds)
    }

    // MARK: - Refresh

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func refresh(using refreshToken: String, base: ClaudeCredentials) async throws -> String {
        var request = URLRequest(url: OAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuth.clientID
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        guard http.statusCode == 200 else {
            // Refresh token rotated out from under us (e.g. Claude Code refreshed first),
            // or the client values changed. Surface as expired → "re-auth in Claude Code".
            throw UsageError.refreshFailed(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)

        // Merge and persist so the next read can pick the fresher bundle.
        var updated = base
        updated.claudeAiOauth.accessToken = decoded.accessToken
        if let newRefresh = decoded.refreshToken { updated.claudeAiOauth.refreshToken = newRefresh }
        if let expiresIn = decoded.expiresIn {
            updated.claudeAiOauth.expiresAt = (Date().timeIntervalSince1970 + expiresIn) * 1000.0
        }
        // Best-effort persistence into the app's OWN item — never Claude Code's (writing to
        // another app's item prompts for the keychain password and would clobber fields we
        // don't model). Never fail the request just because persistence failed.
        try? refreshStore.writeData(updated.encoded())

        return decoded.accessToken
    }
}
