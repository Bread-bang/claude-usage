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

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
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
