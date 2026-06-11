import Foundation

/// JSON shape of the Claude Code Keychain blob.
///
/// ```json
/// { "claudeAiOauth": {
///     "accessToken": "sk-ant-oat01-…",
///     "refreshToken": "sk-ant-ort01-…",
///     "expiresAt": 1781211869970,
///     "scopes": ["user:inference", "user:profile", …],
///     "subscriptionType": "max"
/// } }
/// ```
///
/// The keys are already camelCase in the stored JSON, so no custom `CodingKeys`
/// are needed. Everything except `accessToken` is optional for forward-compatibility.
struct ClaudeCredentials: Codable, Sendable {
    var claudeAiOauth: OAuthBundle

    struct OAuthBundle: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        /// Epoch milliseconds.
        var expiresAt: Double?
        var scopes: [String]?
        var subscriptionType: String?
        var rateLimitTier: String?
    }

    static func decode(from data: Data) throws -> ClaudeCredentials {
        try JSONDecoder().decode(ClaudeCredentials.self, from: data)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    var accessToken: String { claudeAiOauth.accessToken }
    var refreshToken: String? { claudeAiOauth.refreshToken }

    /// Expiry as a `Date`, derived from the epoch-millisecond field.
    var expiry: Date? {
        guard let ms = claudeAiOauth.expiresAt else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }

    /// True when the access token is expired or within `buffer` seconds of expiring.
    func isExpired(now: Date = Date(), buffer: TimeInterval = 120) -> Bool {
        guard let expiry else { return false } // No expiry info → assume usable.
        return expiry.timeIntervalSince(now) <= buffer
    }
}
