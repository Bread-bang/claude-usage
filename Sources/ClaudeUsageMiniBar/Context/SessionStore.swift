import Foundation

/// The on-disk handoff between the hook relay (writer) and the app (reader).
///
/// Each session is one JSON file under Application Support, named by session id. The relay
/// overwrites its file on every hook event; the app reads the directory and treats the
/// freshest `lastActivity` as the active session. One file per session means concurrent
/// hooks from different sessions never race on the same file.
enum SessionStore {
    /// `~/Library/Application Support/ClaudeUsageMiniBar/sessions/`
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ClaudeUsageMiniBar", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Overwrites the session's file. Called from the headless relay process.
    static func write(_ info: SessionInfo) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(info.sessionId).json")
        guard let data = try? encoder.encode(info) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Reads one session's file back (used by the relay to merge sticky fields like `model`).
    static func read(sessionId: String) -> SessionInfo? {
        let url = directory.appendingPathComponent("\(sessionId).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SessionInfo.self, from: data)
    }

    /// All known sessions, newest activity first. Stale files (sessions long gone) are kept
    /// on disk but sort to the bottom; the app only cares about the freshest.
    static func all() -> [SessionInfo] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SessionInfo.self, from: Data(contentsOf: $0)) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }
}
