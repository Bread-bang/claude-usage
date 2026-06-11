import Foundation

/// Every failure surface the app can present, mapped to a friendly message and a hint
/// about whether the user can do anything about it.
enum UsageError: Error, LocalizedError {
    /// Credentials are missing from the Keychain (never signed in / signed out).
    case notSignedIn
    /// Access token expired and could not be refreshed automatically.
    case tokenExpired
    /// The OAuth refresh exchange failed.
    case refreshFailed(status: Int)
    /// API replied 401 even after a refresh attempt.
    case unauthorized
    /// API replied 429 — the usage endpoint allows only a few calls per burst.
    case rateLimited
    /// Response was not an HTTP response, or had no body where one was required.
    case invalidResponse
    /// Any non-success HTTP status from the usage endpoint.
    case http(status: Int, body: String?)
    /// JSON did not match the expected model.
    case decoding(Error)
    /// URLSession transport failure (offline, DNS, TLS, timeout…).
    case transport(Error)
    /// Keychain read/write failure.
    case keychain(KeychainError)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Claude Code."
        case .tokenExpired, .unauthorized:
            return "Session expired. Open Claude Code to sign in again."
        case .refreshFailed(let status):
            return "Could not refresh the session (HTTP \(status))."
        case .rateLimited:
            return "Rate limited — retrying soon."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .http(let status, _):
            return "Server returned HTTP \(status)."
        case .decoding:
            return "Could not read the usage data."
        case .transport:
            return "Network unavailable."
        case .keychain(let inner):
            return inner.errorDescription
        }
    }

    /// Whether the user can recover by signing back in to Claude Code.
    var requiresReauth: Bool {
        switch self {
        case .notSignedIn, .tokenExpired, .unauthorized, .refreshFailed:
            return true
        default:
            return false
        }
    }

    /// Transient conditions that usually resolve on their own (shown softer in the UI).
    var isTransient: Bool {
        switch self {
        case .rateLimited, .transport:
            return true
        default:
            return false
        }
    }
}
