import Foundation

/// Display-only account metadata, read best-effort from `~/.claude.json`.
///
/// Purely cosmetic (shown in the dropdown header). Never required for the API call —
/// the usage endpoint derives the organization from the token itself.
struct AccountInfo: Sendable, Equatable {
    let email: String?
    let organizationName: String?

    static func loadFromClaudeConfig() -> AccountInfo? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = json["oauthAccount"] as? [String: Any]
        else { return nil }

        let email = account["emailAddress"] as? String
        let org = account["organizationName"] as? String
        guard email != nil || org != nil else { return nil }
        return AccountInfo(email: email, organizationName: org)
    }
}
