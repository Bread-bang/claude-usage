import Foundation

/// Tolerant ISO-8601 parser. The usage endpoint emits microsecond precision with an
/// explicit offset (`2026-06-11T18:00:00.308440+00:00`), which `ISO8601DateFormatter`
/// only partially supports. We try fractional-seconds first, then plain, and as a last
/// resort trim the fractional component to milliseconds so 6-digit microseconds still parse.
enum ISO8601Parser {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = withFraction.date(from: string) { return d }
        if let d = plain.date(from: string) { return d }
        // Trim sub-millisecond digits: "...:00.308440+00:00" -> "...:00.308+00:00"
        if let trimmed = trimFractionalSeconds(string),
           let d = withFraction.date(from: trimmed) {
            return d
        }
        return nil
    }

    /// Reduces a `.ffffff` fractional component to at most three digits.
    private static func trimFractionalSeconds(_ s: String) -> String? {
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let after = s.index(after: dot)
        // Find the end of the digit run.
        var end = after
        while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
        let digits = s[after..<end]
        guard digits.count > 3 else { return nil }
        let keep = s[after..<s.index(after: s.index(after: s.index(after: dot)))]
        return String(s[..<after]) + keep + String(s[end...])
    }
}

/// Human-readable formatting helpers used by the UI.
enum UsageFormat {
    /// `39.0` -> `"39%"`. Truncates (floors for positive values) to match how Claude Code
    /// renders the same numbers (e.g. `1.55` -> `1%`). Pass `fraction: true` for 0…1 input.
    static func percent(_ value: Double, fraction: Bool = false) -> String {
        let pct = fraction ? value * 100 : value
        return "\(Int(pct))%"
    }

    /// Compact token count for the context card: `538210` -> `"538K"`,
    /// `200_000` -> `"200K"`, `1_000_000` -> `"1M"`, `1_500_000` -> `"1.5M"`.
    static func tokensCompact(_ n: Int) -> String {
        if n >= 1_000_000 {
            let m = Double(n) / 1_000_000
            return m == m.rounded() ? "\(Int(m))M" : String(format: "%.1fM", m)
        }
        if n >= 1_000 {
            return "\(Int((Double(n) / 1_000).rounded()))K"
        }
        return "\(n)"
    }

    /// Compact "time until reset": `"3h 42m"`, `"12m"`, or `"now"`.
    static func countdown(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// A reset line for a rate-limit window, mirroring Claude Code's `/usage`:
    /// same calendar day  -> `"Resets 2:59am (Asia/Seoul)"`
    /// a different day     -> `"Resets Jun 17 at 2:59am (Asia/Seoul)"`
    static func resetLine(_ date: Date?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard let date else { return nil }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let time = timeString(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Resets \(time) (\(timeZone.identifier))"
        }
        return "Resets \(dateString(date, timeZone: timeZone)) at \(time) (\(timeZone.identifier))"
    }

    /// Reset line for the usage-credits card, e.g. `"Resets Jul 1 (Asia/Seoul)"`.
    /// Extra-usage credits reset on the 1st of the next month; the API does not return this
    /// date, so we derive it from the calendar (matches Claude Code's display).
    static func creditsResetLine(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
        return "Resets \(dateString(firstOfNextMonth, timeZone: timeZone)) (\(timeZone.identifier))"
    }

    private static func timeString(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "h:mma"
        return f.string(from: date).lowercased() // "2:59am"
    }

    private static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "MMM d"
        return f.string(from: date) // "Jun 17"
    }

    /// `"$0.62 / $40.00"` for the usage-credits card.
    ///
    /// The API reports credits in **cents** (`used_credits: 62.0`, `monthly_limit: 4000`),
    /// which Claude Code shows as `$0.62 / $40.00`. We convert to the major unit and always
    /// show two decimals to match.
    static func credits(used: Double?, limit: Double?, currency: String?) -> String {
        let symbol = currencySymbol(currency)
        let usedStr = money((used ?? 0) / 100, symbol: symbol)
        guard let limit else { return usedStr }
        return "\(usedStr) / \(money(limit / 100, symbol: symbol))"
    }

    private static func money(_ value: Double, symbol: String) -> String {
        String(format: "\(symbol)%.2f", value)
    }

    private static func currencySymbol(_ code: String?) -> String {
        switch code?.uppercased() {
        case "USD", nil: return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "KRW": return "₩"
        default: return (code ?? "") + " "
        }
    }
}
