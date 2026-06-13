import Foundation

/// Removes the `--hook-relay` hooks that versions ≤0.2.x installed into
/// `~/.claude/settings.json`. v0.3.0 dropped hook-relay entirely (context moved to the status
/// line), but an in-place upgrade leaves the old entries behind — and the current binary no
/// longer handles `--hook-relay`, so each one would boot the GUI instead of a quick relay.
/// `AppEntry` already guards the hang; this clears the dead entries so Claude Code stops
/// spawning the app on every turn.
///
/// Surgical and idempotent: only commands carrying **both** `--hook-relay` and our binary name
/// are removed, so another tool's hooks are never touched, and empty containers are pruned
/// (entry → event → `hooks`) to leave the file as if we had never been there.
enum LegacyHookCleaner {
    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static func removeLegacyHooks() {
        guard
            let data = try? Data(contentsOf: settingsURL),
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var hooks = root["hooks"] as? [String: Any]
        else { return }

        var changed = false
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.compactMap(prune)
            guard kept.count != entries.count else { continue }
            changed = true
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        guard changed else { return } // nothing of ours present → leave the file untouched

        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? out.write(to: settingsURL, options: .atomic)
        }
    }

    /// Strips our `--hook-relay` commands from one hook entry's nested `hooks` array. Returns
    /// the entry with the survivors, `nil` if it becomes empty (so the caller drops it), or the
    /// entry unchanged when it held none of ours.
    private static func prune(_ entry: [String: Any]) -> [String: Any]? {
        guard let nested = entry["hooks"] as? [[String: Any]] else { return entry }
        let kept = nested.filter { !isOurs($0) }
        if kept.count == nested.count { return entry } // none of ours here
        if kept.isEmpty { return nil }                 // entry now empty → drop it
        var copy = entry
        copy["hooks"] = kept
        return copy
    }

    /// Ours iff the command runs our binary in `--hook-relay` mode. Requiring the binary name
    /// (not just the flag) keeps another tool's relay hook safe.
    private static func isOurs(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.contains("--hook-relay") && command.contains("ClaudeUsageMiniBar")
    }
}
