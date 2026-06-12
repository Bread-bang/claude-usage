import Foundation
import Combine

/// Decides which Claude Code session the user is currently looking at, from the per-session
/// files the hook relay writes.
///
/// Signals are combined into a composite rank (see `rank(of:)`), and the freshest wins:
/// - **Real activity** (`max(lastActivity, last user turn)`): when a human last acted in the
///   session. `lastActivity` is the hook signal (prompt/response), but it stalls when a relay
///   socket dies — which is exactly what happens inside cmux — so the last *user turn* read
///   from the transcript is the hook-independent backstop. Crucially this is NOT the file's
///   mtime: Claude Code rewrites a transcript's tail (resume/mode markers) for a backgrounded
///   pane nobody is watching, and ranking on mtime let such a pane overtake the focused one.
///   This signal works for panes with no controlling tty (GUI multiplexers like cmux, VS
///   Code's integrated terminal) where keystrokes can't be read.
/// - **Keyboard focus** (tty atime): the relay records each session's controlling terminal;
///   that device's atime updates on every keystroke typed into the pane, so the session
///   whose tty was touched most recently is the one the user is typing in. This makes the
///   widget follow a pane switch on the *first keystroke*, before any prompt is submitted —
///   terminal-agnostic and permission-free. But it only counts while the session's real
///   activity is recent (`keystrokeTrustWindow`): a fresh atime on a session whose last turn
///   was hours ago is a background tty read or a glance, not the pane being worked in, and
///   trusting it resurrects long-idle sessions. (A click alone sends no bytes to the pty, so
///   click-without-typing still waits for the first key.)
///
/// Updates are push-driven (a `DispatchSource` watches the sessions directory) plus a short
/// poll that carries the tty signal (atime changes don't generate file events we can watch).
@MainActor
final class SessionTracker: ObservableObject {
    @Published private(set) var active: SessionInfo?
    @Published private(set) var sessions: [SessionInfo] = []

    private var source: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var pollTimer: Timer?

    func start() {
        refresh()
        startWatching()
        startPolling()
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Re-reads the sessions directory and republishes the active session, ordered by the
    /// composite `Rank` (computed once per session, not per comparison).
    func refresh() {
        let now = Date()
        let all = SessionStore.all()
            .map { (session: $0, rank: self.rank(of: $0, now: now)) }
            .sorted { $0.rank > $1.rank }
            .map(\.session)
        if all != sessions { sessions = all }
        if all.first != active { active = all.first }
    }

    /// A keystroke (tty atime) only counts as focus while the session's real activity is this
    /// recent. Beyond it, a fresh atime is treated as background noise, not the active pane —
    /// this is what stops a session idle for hours from being resurrected by a tty read.
    private static let keystrokeTrustWindow: TimeInterval = 15 * 60

    /// Caches `lastUserTurn` per transcript, keyed off the file's mtime so the tail is only
    /// re-parsed when it actually changes — a cheap `stat()` gates the read, not every refresh.
    private var userTurnCache: [String: (mtime: Date, turn: Date?)] = [:]

    /// Composite ranking key for a session; the highest wins the active slot.
    ///
    /// - `activity` starts from **real activity** = `max(lastActivity, last user turn)`. The
    ///   last user turn (read from the transcript) is the hook-independent signal that a human
    ///   acted here; unlike the file's mtime it doesn't move for a backgrounded pane. The tty
    ///   atime (keystroke focus) is folded in only when real activity is within
    ///   `keystrokeTrustWindow`, so a long-idle session can't ride a stray tty read to the top.
    /// - tie-breakers `transcriptMtime`, then `lastActivity`: a last resort when two sessions
    ///   have identical real activity (e.g. a controlling tty shared across resume/clear).
    private func rank(of session: SessionInfo, now: Date) -> Rank {
        let mtime = Self.transcriptMtime(of: session)
        let userTurn = lastUserTurn(of: session, mtime: mtime)
        let real = max(session.lastActivity, userTurn ?? .distantPast)
        var activity = real
        if now.timeIntervalSince(real) < Self.keystrokeTrustWindow,
           let keystroke = Self.lastKeystroke(of: session) {
            activity = max(activity, keystroke)
        }
        return Rank(activity: activity,
                    transcriptMtime: mtime ?? .distantPast,
                    lastActivity: session.lastActivity)
    }

    /// Last real user turn for the session, served from `userTurnCache` unless the transcript's
    /// mtime has moved since the cached read.
    private func lastUserTurn(of session: SessionInfo, mtime: Date?) -> Date? {
        guard let path = session.transcriptPath, let mtime else { return nil }
        if let cached = userTurnCache[path], cached.mtime == mtime { return cached.turn }
        let turn = TranscriptParser.lastUserTurn(atPath: path)
        userTurnCache[path] = (mtime, turn)
        return turn
    }

    /// Lexicographic ranking key: primary activity, then transcript mtime, then hook activity.
    private struct Rank: Comparable {
        let activity: Date
        let transcriptMtime: Date
        let lastActivity: Date
        static func < (lhs: Rank, rhs: Rank) -> Bool {
            if lhs.activity != rhs.activity { return lhs.activity < rhs.activity }
            if lhs.transcriptMtime != rhs.transcriptMtime {
                return lhs.transcriptMtime < rhs.transcriptMtime
            }
            return lhs.lastActivity < rhs.lastActivity
        }
    }

    /// `tty atime` — only counts while the session's `claude` process is still alive, because
    /// ttys numbers get recycled.
    private static func lastKeystroke(of session: SessionInfo) -> Date? {
        guard
            let tty = session.tty,
            let pid = session.claudePid,
            kill(pid, 0) == 0 // owner process gone → stale mapping, ignore
        else { return nil }
        var st = stat()
        guard stat("/dev/\(tty)", &st) == 0 else { return nil }
        return Date(timeIntervalSince1970:
            TimeInterval(st.st_atimespec.tv_sec) + TimeInterval(st.st_atimespec.tv_nsec) / 1e9)
    }

    /// mtime of the session's transcript file. Used to invalidate the `lastUserTurn` cache and
    /// as a last-resort rank tie-breaker — *not* as an activity signal, since it also moves when
    /// Claude Code touches a backgrounded transcript. `nil` if the path is missing or unstattable.
    private static func transcriptMtime(of session: SessionInfo) -> Date? {
        guard let path = session.transcriptPath else { return nil }
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970:
            TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
    }

    // MARK: - Directory watching

    private func startWatching() {
        try? FileManager.default.createDirectory(
            at: SessionStore.directory, withIntermediateDirectories: true
        )
        let fd = open(SessionStore.directory.path, O_EVTONLY)
        guard fd >= 0 else { return } // poll-only fallback
        watchedFD = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .rename], queue: .main
        )
        src.setEventHandler { [weak self] in self?.refresh() }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.watchedFD >= 0 { close(self.watchedFD); self.watchedFD = -1 }
        }
        source = src
        src.resume()
    }

    private func startPolling() {
        // 2s keeps keystroke-based switching feeling immediate; the work per tick is a
        // handful of stat() calls, which is negligible.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
