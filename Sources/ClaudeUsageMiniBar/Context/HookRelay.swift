import Foundation

/// Runs in the headless `--hook-relay` process spawned by Claude Code hooks.
///
/// Reads the hook payload from stdin, records the session, and returns. It must stay silent
/// on stdout — a `UserPromptSubmit` hook's stdout is injected into Claude's context, so any
/// output would leak into the conversation. Errors are swallowed: a relay failure must never
/// break the user's Claude Code turn.
enum HookRelay {
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let payload = try? JSONDecoder().decode(HookPayload.self, from: data),
            let sessionId = payload.sessionId
        else { return }

        // The relay runs detached from the terminal (tty "??"), but its *ancestors* aren't:
        // one or two ppid hops up sits the `claude` process, which carries the pane's
        // controlling tty. Recording it gives the app a session-id ↔ tty mapping, which is
        // what makes keystroke-based focus detection possible.
        let terminal = controllingTTYOfAncestors()

        // `model` only arrives on some events (SessionStart) — don't clobber a previously
        // recorded value with nil on later events.
        let model = payload.model ?? SessionStore.read(sessionId: sessionId)?.model

        SessionStore.write(SessionInfo(
            sessionId: sessionId,
            transcriptPath: payload.transcriptPath,
            cwd: payload.cwd,
            lastEvent: payload.hookEventName ?? "",
            lastActivity: Date(),
            tty: terminal?.name,
            claudePid: terminal?.pid,
            model: model
        ))
    }

    // MARK: - Controlling-tty discovery

    /// Walks the ppid chain upward and returns the first ancestor that has a controlling
    /// terminal — in practice the session's `claude` process (verified: relay → claude is
    /// one hop). Returns the device name (`"ttys000"`) and that ancestor's pid.
    private static func controllingTTYOfAncestors() -> (name: String, pid: pid_t)? {
        var pid = getppid()
        for _ in 0..<10 {
            guard let info = kinfoProc(pid) else { return nil }
            let tdev = info.kp_eproc.e_tdev
            if tdev != 0, tdev != ~dev_t(0), // 0 / NODEV → no controlling terminal
               let cName = devname(tdev, mode_t(S_IFCHR)) {
                return (String(cString: cName), pid)
            }
            let ppid = info.kp_eproc.e_ppid
            guard ppid > 1 else { return nil }
            pid = ppid
        }
        return nil
    }

    private static func kinfoProc(_ pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        return info
    }
}

/// The hook payload fields we use. Common to every event (`session_id`/`transcript_path`/
/// `cwd`/`hook_event_name`); everything else in the payload is ignored.
private struct HookPayload: Decodable {
    let sessionId: String?
    let transcriptPath: String?
    let cwd: String?
    let hookEventName: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case model
    }
}
