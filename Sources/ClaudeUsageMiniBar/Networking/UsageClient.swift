import Foundation

/// Fetches the usage report from Anthropic's OAuth usage endpoint.
///
/// Endpoint: `GET https://api.anthropic.com/api/oauth/usage`
/// Auth:     `Authorization: Bearer <oauth access token>`
///
/// Note this is the **api.anthropic.com** endpoint Claude Code itself uses — *not*
/// `claude.ai/api/organizations/{id}/usage`, which sits behind a Cloudflare bot
/// challenge that blocks non-browser clients. This endpoint derives the organization
/// from the token, so no `organization_id` is needed.
struct UsageClient: Sendable {
    static let defaultEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let endpoint: URL
    private let tokenProvider: TokenProvider
    private let session: URLSession

    init(tokenProvider: TokenProvider,
         endpoint: URL = UsageClient.defaultEndpoint,
         session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.endpoint = endpoint
        self.session = session
    }

    /// Fetches the current usage report, transparently refreshing the token once on 401.
    func fetch() async throws -> UsageReport {
        do {
            let token = try await tokenProvider.validAccessToken()
            return try await perform(token: token, allowRefresh: true)
        } catch let error as KeychainError {
            switch error {
            case .notFound: throw UsageError.notSignedIn
            default: throw UsageError.keychain(error)
            }
        }
    }

    private func perform(token: String, allowRefresh: Bool) async throws -> UsageReport {
        let request = makeRequest(token: token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(UsageReport.self, from: data)
            } catch {
                throw UsageError.decoding(error)
            }
        case 401:
            // Token rejected. Try exactly one refresh-and-retry before giving up.
            guard allowRefresh else { throw UsageError.unauthorized }
            let refreshed = try await tokenProvider.forceRefresh()
            return try await perform(token: refreshed, allowRefresh: false)
        case 429:
            throw UsageError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8)
            throw UsageError.http(status: http.statusCode, body: body)
        }
    }

    private func makeRequest(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Optional but matches Claude Code and keeps us forward-compatible.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        return request
    }
}
