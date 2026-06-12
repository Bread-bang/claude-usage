import Foundation

/// A computed view of one session's context fill, ready for the UI.
struct ContextReport: Sendable, Equatable {
    let usage: ContextUsage
    /// The context-window limit this percent is measured against (200K or 1M).
    let limit: Int
    let session: SessionInfo

    /// Current occupancy: the four-field total of the last assistant message.
    var occupied: Int { usage.total }

    /// Occupancy as a 0…1 fraction of the limit, for progress bars.
    var fraction: Double { min(max(Double(occupied) / Double(max(limit, 1)), 0), 1) }

    /// Whole-percent fill, e.g. `53`.
    var percent: Int { Int(fraction * 100) }
}
