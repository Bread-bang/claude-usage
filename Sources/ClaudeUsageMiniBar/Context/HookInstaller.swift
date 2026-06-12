import Foundation

/// Registers (and keeps current) our hook-relay command in `~/.claude/settings.json`, so
/// context tracking works the moment the app is installed — no manual config.
///
/// Idempotent and additive: our entry is appended alongside any hooks the user (or another
/// tool like cmux) already has — Claude Code merges hooks from all sources, so they coexist.
/// We only ever touch our own entry; every other key in settings.json is preserved.
enum HookInstaller {
    /// Hooks we attach to. `UserPromptSubmit`/`Stop` mark activity each turn; `SessionStart`
    /// registers a session the instant it opens (before any prompt).
    private static let events = ["SessionStart", "UserPromptSubmit", "Stop"]

    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// `"<app binary>" --hook-relay` — quoted to survive spaces in the bundle path.
    private static var relayCommand: String? {
        guard let exec = Bundle.main.executablePath else { return nil }
        return "\"\(exec)\" --hook-relay"
    }

    static func installIfNeeded() {
        guard let command = relayCommand else { return }

        var root = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if let index = indexOfRelayEntry(in: entries) {
                // Already present — refresh the command if the binary moved (e.g. updated app).
                if commandOf(entries[index]) != command {
                    entries[index] = relayEntry(command: command)
                    hooks[event] = entries
                    changed = true
                }
            } else {
                entries.append(relayEntry(command: command))
                hooks[event] = entries
                changed = true
            }
        }

        guard changed else { return }
        root["hooks"] = hooks
        try? FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    /// Removes our hook entries — used when the user disables context tracking.
    static func uninstall() {
        guard
            let data = try? Data(contentsOf: settingsURL),
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var hooks = root["hooks"] as? [String: Any]
        else { return }
        var changed = false
        for event in events {
            guard let entries = hooks[event] as? [[String: Any]] else { continue }
            let kept = entries.filter { indexOfRelayEntry(in: [$0]) == nil }
            if kept.count != entries.count {
                if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
                changed = true
            }
        }
        guard changed else { return }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? out.write(to: settingsURL, options: .atomic)
        }
    }

    // MARK: - Entry shape

    private static func relayEntry(command: String) -> [String: Any] {
        ["matcher": "", "hooks": [["type": "command", "command": command]]]
    }

    /// Finds our entry by the `--hook-relay` marker (path-independent, so it matches even
    /// after the binary moves).
    private static func indexOfRelayEntry(in entries: [[String: Any]]) -> Int? {
        entries.firstIndex { entry in
            (entry["hooks"] as? [[String: Any]])?.contains {
                ($0["command"] as? String)?.contains("--hook-relay") ?? false
            } ?? false
        }
    }

    private static func commandOf(_ entry: [String: Any]) -> String? {
        (entry["hooks"] as? [[String: Any]])?
            .compactMap { $0["command"] as? String }
            .first { $0.contains("--hook-relay") }
    }
}
