import Foundation

/// Registers our `--statusline` command as Claude Code's status line in `~/.claude/settings.json`,
/// so the app receives exact `context_window` data without the user configuring anything.
///
/// Unlike hooks (an array, where we append alongside others), `statusLine` is a **single slot**.
/// So this is strictly non-destructive: we install only when the slot is empty or already ours,
/// and never overwrite another tool's status line (ccusage, a custom script, …). When someone
/// else owns it, the app silently falls back to transcript parsing for context.
enum StatusLineInstaller {
    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// `"<app binary>" --statusline` — quoted to survive spaces in the bundle path.
    private static var relayCommand: String? {
        guard let exec = Bundle.main.executablePath else { return nil }
        return "\"\(exec)\" --statusline"
    }

    static func installIfPossible() {
        guard let command = relayCommand else { return }

        var root = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        if let existing = root["statusLine"] as? [String: Any] {
            // Someone else's status line — leave it untouched (single slot, their choice wins).
            guard isOurs(existing) else { return }
            // Already ours; only rewrite if the binary moved (e.g. an app update).
            if commandOf(existing) == command { return }
        }

        root["statusLine"] = ["type": "command", "command": command]
        try? FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    /// Removes our status line — used when the user disables context tracking. Only ever clears
    /// our own entry; another tool's status line is left in place.
    static func uninstall() {
        guard
            let data = try? Data(contentsOf: settingsURL),
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let existing = root["statusLine"] as? [String: Any],
            isOurs(existing)
        else { return }
        root.removeValue(forKey: "statusLine")
        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? out.write(to: settingsURL, options: .atomic)
        }
    }

    /// Ours iff the command runs our binary in `--statusline` mode. Matching on the binary
    /// name (not full path) keeps it stable when the app moves between updates.
    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        return command.contains("--statusline") && command.contains("ClaudeUsageMiniBar")
    }

    private static func commandOf(_ entry: [String: Any]) -> String? {
        entry["command"] as? String
    }
}
