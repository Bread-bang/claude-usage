import Foundation

/// A snapshot of one Claude Code session, recorded by the hook relay on each event.
///
/// `transcript_path` and `cwd` come straight from the hook payload — the transcript is what
/// `TranscriptParser` reads for occupancy, and `cwd` is what `ContextLimitDetector` keys on.
/// `lastActivity` lets the app pick the session the user most recently interacted with.
struct SessionInfo: Codable, Sendable, Equatable, Identifiable {
    let sessionId: String
    let transcriptPath: String?
    let cwd: String?
    let lastEvent: String
    let lastActivity: Date
    /// Controlling terminal of the session's `claude` process (e.g. `"ttys000"`), found by
    /// the relay walking its ancestor chain. This is the bridge that lets the app detect
    /// keyboard focus: the tty device's **atime** updates on every keystroke the user types
    /// into that pane, so "freshest atime" = "pane the user is typing in". Optional — old
    /// relay versions and headless (`claude -p`) sessions have none.
    let tty: String?
    /// Pid of the `claude` process owning that tty, used to ignore the tty signal once the
    /// session's process is gone (ttys numbers get recycled).
    let claudePid: Int32?
    /// Model reported by the hook (SessionStart carries it on some Claude Code versions).
    /// May include the `[1m]` opt-in suffix — when it does, that is per-session ground
    /// truth for the 1M context window.
    let model: String?

    var id: String { sessionId }
}
