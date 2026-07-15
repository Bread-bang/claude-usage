import Foundation

/// Strongly typed model of `GET https://api.anthropic.com/api/oauth/usage`.
///
/// The live endpoint returns a number of nullable "bucket" fields beyond the four
/// the UI cares about (`seven_day_oauth_apps`, `seven_day_cowork`, `tangelo`,
/// `iguana_necktie`, …). Unknown keys are ignored by `Decodable`, and every modelled
/// window is optional, so the app keeps working even as Anthropic adds or renames buckets.
///
/// Example payload:
/// ```json
/// {
///   "five_hour":        { "utilization": 39.0, "resets_at": "2026-06-11T18:00:00.308440+00:00" },
///   "seven_day":        { "utilization": 44.0, "resets_at": "2026-06-16T18:00:00.308466+00:00" },
///   "seven_day_sonnet": { "utilization": 0.0,  "resets_at": null },
///   "seven_day_opus":   null,
///   "extra_usage":      { "is_enabled": true, "monthly_limit": 4000, "used_credits": 62.0,
///                          "utilization": 1.55, "currency": "USD", "disabled_reason": null }
/// }
/// ```
struct UsageReport: Codable, Sendable, Equatable {
    /// Rolling 5-hour session window — the primary signal shown in the menu bar.
    let fiveHour: RateLimitWindow?
    /// Rolling 7-day window across all models.
    let sevenDay: RateLimitWindow?
    /// 7-day window scoped to Sonnet.
    let sevenDaySonnet: RateLimitWindow?
    /// 7-day window scoped to Opus (often null on plans without a separate Opus cap).
    let sevenDayOpus: RateLimitWindow?
    /// Pay-as-you-go "extra usage" credits, when enabled on the account.
    let extraUsage: ExtraUsage?
    /// Server-provided limit entries (newer API shape). Model-scoped weekly caps (e.g. Fable)
    /// live here rather than in the legacy top-level `seven_day_sonnet`/`seven_day_opus`
    /// fields, and each entry carries a `severity` the UI colors by. `nil` on older servers.
    let limits: [UsageLimit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
        case limits
    }
}

extension UsageReport {
    /// First `limits[]` entry of a given `kind` (e.g. `"session"`, `"weekly_all"`).
    /// Used to attach the server's `severity` to the legacy top-level windows.
    func limit(kind: String) -> UsageLimit? { limits?.first { $0.kind == kind } }

    /// Model-scoped weekly caps (`kind == "weekly_scoped"`), e.g. Fable. One row each.
    var weeklyScopedLimits: [UsageLimit] {
        (limits ?? []).filter { $0.kind == "weekly_scoped" && $0.percent.isFinite }
    }
}

/// One entry of the `limits[]` array from the usage endpoint.
///
/// Example:
/// ```json
/// { "kind": "weekly_scoped", "group": "weekly", "percent": 68, "severity": "normal",
///   "resets_at": "2026-07-14T18:00:00+00:00", "is_active": false,
///   "scope": { "model": { "id": null, "display_name": "Fable" } } }
/// ```
struct UsageLimit: Codable, Sendable, Equatable, Identifiable {
    /// `"session"`, `"weekly_all"`, `"weekly_scoped"`, …
    let kind: String
    /// `"session"` / `"weekly"` grouping hint.
    let group: String?
    /// Percentage consumed, 0…100 (the API sends an integer such as `68`).
    let percent: Double
    /// Server's own assessment: `"normal"`, `"warning"`, … Drives the bar color when present.
    let severity: String?
    /// ISO-8601 reset timestamp as sent by the server. Kept raw for parse tolerance.
    let resetsAtRaw: String?
    /// Present only on model-/surface-scoped entries.
    let scope: LimitScope?
    /// Whether the server currently considers this limit the binding/active one.
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, severity, scope
        case resetsAtRaw = "resets_at"
        case isActive = "is_active"
    }

    var id: String { "\(kind)|\(scope?.model?.displayName ?? "")" }
    /// Model display name for scoped entries (e.g. `"Fable"`).
    var modelName: String? { scope?.model?.displayName }
    var resetsAt: Date? { ISO8601Parser.date(from: resetsAtRaw) }
    var fraction: Double { min(max(percent / 100.0, 0), 1) }
}

/// The `scope` object on a `UsageLimit` (model / surface the limit applies to).
struct LimitScope: Codable, Sendable, Equatable {
    let model: LimitModel?
}

/// The `scope.model` object.
struct LimitModel: Codable, Sendable, Equatable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// A single rate-limit window: how much of the allowance is consumed and when it resets.
struct RateLimitWindow: Codable, Sendable, Equatable {
    /// Percentage of the window consumed, 0…100 (the API sends e.g. `39.0`).
    let utilization: Double
    /// ISO-8601 reset timestamp as sent by the server, or `nil` when the window is idle.
    /// Kept as the raw string so date-format fragility never breaks decoding.
    let resetsAtRaw: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAtRaw = "resets_at"
    }

    /// Parsed reset instant, tolerant of microsecond precision and timezone offsets.
    var resetsAt: Date? { ISO8601Parser.date(from: resetsAtRaw) }

    /// Utilization clamped to a 0…1 fraction, convenient for progress bars.
    var fraction: Double { min(max(utilization / 100.0, 0), 1) }
}

/// Pay-as-you-go credit usage (the "extra usage" card).
struct ExtraUsage: Codable, Sendable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?
    let disabledReason: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
        case disabledReason = "disabled_reason"
    }
}
