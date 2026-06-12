import Foundation
import Combine

/// Owns context tracking: it watches the active Claude Code session (via `SessionTracker`)
/// and turns it into a render-ready `ContextReport`.
///
/// Recompute is push-driven — the hook relay fires on every turn, which republishes the
/// active session, which recomputes here. Transcript parsing runs off the main actor so a
/// large `.jsonl` never stutters the UI. The tracker's slow timer is the only fallback poll.
@MainActor
final class ContextViewModel: ObservableObject {
    @Published private(set) var report: ContextReport?

    private let tracker = SessionTracker()
    private var cancellables = Set<AnyCancellable>()
    private var transcriptTimer: Timer?
    private var lastSeenTranscriptMtime: Date?

    init() {
        tracker.$active
            .removeDuplicates()
            .sink { [weak self] session in self?.recompute(for: session) }
            .store(in: &cancellables)
    }

    func start() {
        tracker.start()
        startTranscriptWatch()
    }

    func stop() {
        tracker.stop()
        transcriptTimer?.invalidate()
        transcriptTimer = nil
    }

    /// Hooks only fire on prompt/response, but local commands (`/model`, `/context`,
    /// `/compact`) change the transcript too — so also recompute whenever the active
    /// transcript's mtime moves. This is what makes a `/model` switch (followed by
    /// `/context`) show up within a couple of seconds, no message required.
    private func startTranscriptWatch() {
        guard transcriptTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recomputeIfTranscriptChanged() }
        }
        RunLoop.main.add(timer, forMode: .common)
        transcriptTimer = timer
    }

    private func recomputeIfTranscriptChanged() {
        guard let session = tracker.active, let path = session.transcriptPath else { return }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        guard let mtime, mtime != lastSeenTranscriptMtime else { return }
        recompute(for: session)
    }

    /// All known sessions, newest activity first (for an optional session list in the UI).
    var sessions: [SessionInfo] { tracker.sessions }

    /// `true` once at least one session has been seen — i.e. the relay hook is wired and firing.
    var hasSeenSession: Bool { !tracker.sessions.isEmpty }

    private func recompute(for session: SessionInfo?) {
        guard let session, let path = session.transcriptPath else {
            report = nil
            return
        }
        let cwd = session.cwd ?? ""
        // This Task inherits the main actor; only the parse hops off it.
        Task { [weak self] in
            let parsed = await Self.parse(atPath: path)
            guard let self else { return }
            self.apply(parsed: parsed, cwd: cwd, session: session)
        }
    }

    /// Parses the transcript off the main actor so a large `.jsonl` never stutters the UI.
    private nonisolated static func parse(
        atPath path: String
    ) async -> (snapshot: TranscriptParser.Snapshot, recorded: Int?, budget: Int?)? {
        await Task.detached(priority: .utility) {
            guard let snapshot = TranscriptParser.snapshot(atPath: path) else { return nil }
            return (snapshot,
                    TranscriptParser.recordedContextLimit(atPath: path),
                    TranscriptParser.declaredTokenBudget(atPath: path))
        }.value
    }

    private func apply(
        parsed: (snapshot: TranscriptParser.Snapshot, recorded: Int?, budget: Int?)?,
        cwd: String,
        session: SessionInfo
    ) {
        guard let parsed else { report = nil; return }
        let limit = ContextLimitDetector.limit(
            cwd: cwd,
            model: parsed.snapshot.model,
            hookModel: session.model,
            recordedLimit: parsed.recorded,
            declaredBudget: parsed.budget,
            occupiedTokens: parsed.snapshot.usage.total
        )
        report = ContextReport(usage: parsed.snapshot.usage, limit: limit, session: session)
    }

    // MARK: - Derived display

    /// Menu-bar text for context, e.g. `"53%"`. Falls back to a dash before the first session.
    var menuBarText: String {
        guard let report else { return "—" }
        return "\(report.percent)%"
    }
}
