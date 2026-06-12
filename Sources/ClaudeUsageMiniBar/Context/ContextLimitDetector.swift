import Foundation

/// Resolves the context-window limit — the denominator for the usage percent.
///
/// Claude Code's 1M context is an opt-in, so the limit is a *session* property, not a model
/// property. Signals are tried in order of authority:
///
/// 1. **Transcript budget tag** — Claude Code writes the session's actual window into the
///    transcript at conversation start (`<budget:token_budget>1000000</budget:token_budget>`).
///    Per-session ground truth; also survives compaction dropping occupancy back below 200K.
/// 2. **Fable/Mythos model** — 1M is those models' only window size.
/// 3. **Occupancy ratchet** — anything already past 200K can only be a 1M session.
/// 4. **Default-model setting** — `~/.claude/settings.json` `"model": "claude-fable-5[1m]"`;
///    counts when its base model matches the session's model (sessions started under a
///    `[1m]` default run with 1M).
/// 5. **Per-project usage keys** — `~/.claude.json` `projects[cwd].lastModelUsage` keys
///    carry a `[1m]` suffix once a 1M session has recorded usage there.
/// 6. Otherwise the standard 200K window.
enum ContextLimitDetector {
    static let standard = 200_000
    static let million = 1_000_000

    static func limit(
        cwd: String,
        model: String?,
        hookModel: String?,
        recordedLimit: Int?,
        declaredBudget: Int?,
        occupiedTokens: Int
    ) -> Int {
        // Hard per-model facts about the *current* model come first — these models have
        // exactly one window size, so they invalidate stale `/context` records left over
        // from before a mid-session `/model` switch.
        let anyModel = hookModel ?? model
        if let anyModel {
            if anyModel.contains("fable") || anyModel.contains("mythos") { return million }
            if anyModel.contains("haiku") { return standard }
        }
        // A `/context` record inside the transcript is Claude Code naming the denominator
        // itself; the *last* record wins.
        if let recordedLimit { return recordedLimit }
        // Hook-reported session model with the explicit opt-in suffix is also direct truth.
        if let hookModel, hookModel.contains("[1m]") { return million }
        if let declaredBudget, declaredBudget >= 100_000 { return declaredBudget }
        if occupiedTokens > standard { return million }
        if defaultModelIsMillion(matching: model) { return million }
        if hasMillionContextKey(cwd: cwd) { return million }
        return standard
    }

    /// `~/.claude/settings.json` → `"model"`. A `[1m]` default applies to sessions whose
    /// model matches its base (or whose model we don't know yet — fresh sessions).
    private static func defaultModelIsMillion(matching model: String?) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let defaultModel = root["model"] as? String,
            defaultModel.contains("[1m]")
        else { return false }
        guard let model else { return true }
        return defaultModel.replacingOccurrences(of: "[1m]", with: "") == model
    }

    /// `~/.claude.json` → `projects[cwd].lastModelUsage` → any key with a `[1m]` suffix.
    private static func hasMillionContextKey(cwd: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let projects = root["projects"] as? [String: Any],
            let project = projects[cwd] as? [String: Any],
            let lastModelUsage = project["lastModelUsage"] as? [String: Any]
        else { return false }
        return lastModelUsage.keys.contains { $0.contains("[1m]") }
    }
}
