import Foundation

/// Token occupancy of a Claude Code session's context window, derived from the
/// **last main-thread assistant message** in the session transcript.
///
/// The Messages API is stateless: every turn re-sends the whole conversation, so the most
/// recent assistant message's `usage` already reflects the entire accumulated context. We
/// therefore read a **single line**, never a sum over the file — summing double-counts
/// `cache_read`, which re-reads prior tokens on every turn.
struct ContextUsage: Codable, Sendable, Equatable {
    let inputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int

    /// Everything fed into the model on that request — cache reads + fresh cache writes +
    /// uncached input. This is the live context fill (what Claude Code's statusLine reports
    /// as `used_percentage`).
    var inputSide: Int { inputTokens + cacheCreationTokens + cacheReadTokens }

    /// Input side plus the tokens just generated: what the **next** turn starts with.
    /// This is the value we surface as "current context".
    var total: Int { inputSide + outputTokens }
}
