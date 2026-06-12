import Foundation
import Combine

/// Decides which Claude Code session the user is currently looking at, from the per-session
/// files the hook relay writes.
///
/// Two signals are combined, and the freshest wins:
/// - **Hook activity** (`lastActivity`): the session whose prompt/response fired last.
/// - **Keyboard focus** (tty atime): the relay records each session's controlling terminal;
///   that device's atime updates on every keystroke typed into the pane, so the session
///   whose tty was touched most recently is the one the user is typing in. This makes the
///   widget follow a pane switch on the *first keystroke*, well before any prompt is
///   submitted — terminal-agnostic and permission-free. (A click alone sends no bytes to
///   the pty, so click-without-typing still waits for the first key.)
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

    /// Re-reads the sessions directory and republishes the active session, ranked by the
    /// freshest of (hook activity, last keystroke on the session's tty).
    func refresh() {
        let all = SessionStore.all()
            .sorted { Self.effectiveActivity($0) > Self.effectiveActivity($1) }
        if all != sessions { sessions = all }
        if all.first != active { active = all.first }
    }

    /// `max(lastActivity, tty atime)` — the tty signal only counts while the session's
    /// `claude` process is still alive, because ttys numbers get recycled.
    private static func effectiveActivity(_ session: SessionInfo) -> Date {
        max(session.lastActivity, lastKeystroke(of: session) ?? .distantPast)
    }

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
