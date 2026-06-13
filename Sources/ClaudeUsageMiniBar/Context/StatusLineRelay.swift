import Foundation

/// Runs in the headless `--statusline` process Claude Code spawns to render the status line.
///
/// Claude Code feeds this command a rich JSON payload on stdin — including the live
/// `context_window` (exact token usage and window size). We read it and print a short status
/// line to stdout, which Claude renders under the prompt of the pane it belongs to. Because
/// each pane runs its own statusLine, the value is always the right one for the session you're
/// looking at — no "which session is active?" guessing, which is exactly why context lives here
/// rather than in the menu bar. Errors are swallowed and produce a blank line.
enum StatusLineRelay {
    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(StatusLinePayload.self, from: data) else { return }

        let line = render(payload)
        if !line.isEmpty { print(line) }
    }

    /// The status line we draw: `"Opus 4.8 · 11% · 113K/1M"`. Each piece is dropped when its
    /// data is absent (e.g. before the first API response Claude reports null usage).
    private static func render(_ payload: StatusLinePayload) -> String {
        var parts: [String] = []
        if let name = payload.model?.displayName ?? payload.model?.id { parts.append(name) }
        if let pct = payload.contextWindow?.usedPercentage { parts.append(UsageFormat.percent(pct)) }
        if let usage = payload.contextWindow?.currentUsage,
           let size = payload.contextWindow?.contextWindowSize {
            parts.append("\(UsageFormat.tokensCompact(usage.total))/\(UsageFormat.tokensCompact(size))")
        }
        return parts.joined(separator: " · ")
    }
}

/// The statusLine payload fields we use. Decoded with `.convertFromSnakeCase`, so JSON keys
/// like `context_window` / `current_usage` / `input_tokens` map to these camelCase properties.
/// Everything else Claude Code sends (cost, rate_limits, workspace, …) is ignored.
private struct StatusLinePayload: Decodable {
    let model: Model?
    let contextWindow: ContextWindow?

    struct Model: Decodable {
        let id: String?
        let displayName: String?
    }

    struct ContextWindow: Decodable {
        let contextWindowSize: Int?
        let usedPercentage: Double?
        let currentUsage: Usage?

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?

            /// Everything that counts against the window on the last request: cache reads +
            /// fresh cache writes + uncached input + the tokens just generated.
            var total: Int {
                (inputTokens ?? 0) + (cacheCreationInputTokens ?? 0)
                    + (cacheReadInputTokens ?? 0) + (outputTokens ?? 0)
            }
        }
    }
}
