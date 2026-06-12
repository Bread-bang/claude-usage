import Foundation

/// Extracts the current context occupancy from a Claude Code transcript (`*.jsonl`).
///
/// Scans **from the end of the file** for the most recent line that is a main-thread
/// (`isSidechain != true`) `assistant` message carrying a `usage` block. Subagent
/// (sidechain) lines are skipped — they belong to a different context than the one the
/// user is watching. Only the tail of the file is read so the parse stays cheap even on
/// long-running, multi-megabyte sessions.
enum TranscriptParser {
    /// What the tail scan yields: the occupancy plus the model that produced it (used by
    /// the limit detector — e.g. Fable sessions are always 1M).
    struct Snapshot {
        let usage: ContextUsage
        let model: String?
    }

    /// Reads the last main-thread assistant usage (and its model) from the transcript at
    /// `path`. Reads at most `maxTailBytes` from the end first; if no usage line is found
    /// there (rare — only when the tail is all user/attachment/system lines), it widens to
    /// the whole file before giving up.
    static func snapshot(atPath path: String, maxTailBytes: Int = 1 << 20) -> Snapshot? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > 0 else { return nil }

        for start in scanOffsets(size: size, maxTailBytes: maxTailBytes) {
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.readToEnd() else { continue }
            if let snapshot = lastSnapshot(in: data, droppingLeadingPartial: start > 0) {
                return snapshot
            }
        }
        return nil
    }

    /// The limit as last reported by the `/context` command inside this session.
    ///
    /// Running `/context` records its output in the transcript (a `user` markdown record
    /// plus a `system` stdout record), and that output states the session's window
    /// directly — e.g. `**Tokens:** 37.7k / 1m` or `37.7k/1m tokens`. This is Claude Code
    /// itself naming the denominator, so it outranks every heuristic. Only `user`/`system`
    /// lines count — an *assistant* line quoting those strings (like a conversation about
    /// this very feature) must not be trusted. The last record wins, so a mid-session
    /// `/model` change is reflected by the next `/context` run.
    static func recordedContextLimit(atPath path: String) -> Int? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        else { return nil }
        let marker = Data("Context Usage".utf8)
        let decoder = JSONDecoder()
        var result: Int?

        var index = data.startIndex
        while index < data.endIndex {
            let lineEnd = data[index...].firstIndex(of: 0x0A) ?? data.endIndex
            defer { index = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex }
            let line = data[index..<lineEnd]
            guard line.count > marker.count,
                  line.range(of: marker) != nil,
                  let record = try? decoder.decode(ContextRecordLine.self, from: Data(line)),
                  record.type == "user" || record.type == "system",
                  let text = record.text?.lowercased()
            else { continue }
            if text.contains("/1m") || text.contains("/ 1m") {
                result = 1_000_000
            } else if text.contains("/200k") || text.contains("/ 200k") {
                result = 200_000
            }
        }
        return result
    }

    /// The session's context-window size as declared *inside* the transcript.
    ///
    /// Claude Code injects a context-awareness budget at conversation start —
    /// `<budget:token_budget>1000000</budget:token_budget>` — which is the authoritative
    /// per-session limit (it reflects the 1M opt-in, not just the model). It sits near the
    /// head of the file, so only the first `maxHeadBytes` are read.
    static func declaredTokenBudget(atPath path: String, maxHeadBytes: Int = 1 << 19) -> Int? {
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.read(upToCount: maxHeadBytes) else { return nil }
        try? handle.close()
        let text = String(decoding: data, as: UTF8.self)

        let marker = "<budget:token_budget>"
        guard let start = text.range(of: marker)?.upperBound,
              let end = text[start...].firstIndex(of: "<") else { return nil }
        return Int(text[start..<end])
    }

    /// Timestamp of the most recent **real user turn** in the transcript — the last
    /// main-thread (`isSidechain != true`) `user` line that actually carries user text (a typed
    /// prompt or a slash command's recorded output), not a `tool_result` fed back mid-response.
    ///
    /// This is the signal for "a human acted in this session", which the file's mtime is *not*:
    /// Claude Code rewrites a transcript's tail (resume markers, mode/permission lines) for a
    /// backgrounded or just-reopened session that nobody is watching, bumping mtime without any
    /// human action. Ranking on mtime therefore lets an unwatched pane overtake the focused one;
    /// ranking on the last user turn does not. Reads a single bounded tail — a recent user line
    /// is effectively always within it — and returns `nil` rather than widening to the whole
    /// (possibly multi-megabyte) file, since this runs on the main actor every refresh.
    static func lastUserTurn(atPath path: String, maxTailBytes: Int = 1 << 20) -> Date? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > 0 else { return nil }
        let start = size > UInt64(maxTailBytes) ? size - UInt64(maxTailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return nil }

        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() } // truncated first line
        let decoder = JSONDecoder()
        for slice in lines.reversed() {
            guard let line = try? decoder.decode(UserTurnLine.self, from: Data(slice)),
                  line.type == "user",
                  line.isSidechain != true,
                  line.message?.containsUserText == true, // skip tool_result-only user lines
                  let stamp = line.timestamp,
                  let date = parseTimestamp(stamp)
            else { continue }
            return date
        }
        return nil
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        iso8601WithFraction.date(from: string) ?? iso8601Plain.date(from: string)
    }

    private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Plain = ISO8601DateFormatter()

    /// Byte offsets to start reading from: the tail first, then (only if needed) the start.
    private static func scanOffsets(size: UInt64, maxTailBytes: Int) -> [UInt64] {
        size > UInt64(maxTailBytes) ? [size - UInt64(maxTailBytes), 0] : [0]
    }

    private static func lastSnapshot(in data: Data, droppingLeadingPartial: Bool) -> Snapshot? {
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        // When we started mid-file, the first line is almost certainly truncated.
        if droppingLeadingPartial, !lines.isEmpty { lines.removeFirst() }

        let decoder = JSONDecoder()
        for slice in lines.reversed() {
            guard let line = try? decoder.decode(TranscriptLine.self, from: Data(slice)),
                  line.type == "assistant",
                  line.isSidechain != true,
                  line.message?.model != "<synthetic>", // resume markers etc. — not API responses
                  let usage = line.message?.usage
            else { continue }
            let parsed = ContextUsage(
                inputTokens: usage.inputTokens ?? 0,
                cacheCreationTokens: usage.cacheCreationInputTokens ?? 0,
                cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                outputTokens: usage.outputTokens ?? 0
            )
            // A real API response always consumes input tokens; all-zero usage is another
            // synthetic-line flavor. Keep scanning past it.
            guard parsed.total > 0 else { continue }
            return Snapshot(usage: parsed, model: line.message?.model)
        }
        return nil
    }
}

/// A line that may carry a `/context` output record: `system` lines put the text in a
/// top-level `content`, `user` lines under `message.content` (string or block array).
private struct ContextRecordLine: Decodable {
    let type: String?
    let content: String?
    let message: Message?

    struct Message: Decodable {
        let content: FlexibleContent?
    }

    /// `message.content` is either a plain string or an array of `{type, text}` blocks.
    struct FlexibleContent: Decodable {
        let text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                text = string
                return
            }
            struct Block: Decodable { let text: String? }
            let blocks = (try? container.decode([Block].self)) ?? []
            text = blocks.compactMap(\.text).joined(separator: "\n")
        }
    }

    var text: String? { content ?? message?.content?.text }
}

/// A `user`-type line, decoded just enough to tell a real human turn from a `tool_result`
/// that Claude Code records under the user role mid-response. `containsUserText` is true when
/// the content is a non-empty string or an array holding at least one `text` block.
private struct UserTurnLine: Decodable {
    let type: String?
    let isSidechain: Bool?
    let timestamp: String?
    let message: Message?

    struct Message: Decodable {
        let containsUserText: Bool

        private enum CodingKeys: String, CodingKey { case content }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? container.decode(String.self, forKey: .content) {
                containsUserText = !string.isEmpty
            } else {
                struct Block: Decodable { let type: String? }
                let blocks = (try? container.decode([Block].self, forKey: .content)) ?? []
                containsUserText = blocks.contains { $0.type == "text" }
            }
        }
    }
}

/// The subset of a transcript line we care about. Unknown keys are ignored by `Decodable`,
/// so this keeps decoding as Claude Code evolves its line schema.
private struct TranscriptLine: Decodable {
    let type: String?
    let isSidechain: Bool?
    let message: Message?

    struct Message: Decodable {
        let usage: Usage?
        let model: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}
