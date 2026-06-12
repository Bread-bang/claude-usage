import SwiftUI

extension Color {
    /// Traffic-light tint for a 0…100 utilization value.
    static func forUtilization(_ value: Double) -> Color {
        switch value {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }
}

/// A rounded progress bar tinted by utilization.
struct UsageBar: View {
    let fraction: Double      // 0…1
    let utilization: Double   // 0…100, drives the color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.14))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.forUtilization(utilization))
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: 9)
    }
}

private enum RowStyle {
    static let title = Font.system(size: 12, weight: .bold, design: .monospaced)
    static let value = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let caption = Font.system(size: 10, weight: .regular, design: .monospaced)
}

/// One rate-limit window in Claude Code `/usage` style:
/// title → `[bar]  NN% used` → `Resets …`.
struct WindowRow: View {
    let title: String
    let window: RateLimitWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(RowStyle.title)
                .lineLimit(1)
            HStack(spacing: 8) {
                UsageBar(fraction: window?.fraction ?? 0,
                         utilization: window?.utilization ?? 0)
                Text(window.map { "\(UsageFormat.percent($0.utilization)) used" } ?? "—")
                    .font(RowStyle.value)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if let reset = UsageFormat.resetLine(window?.resetsAt) {
                Text(reset)
                    .font(RowStyle.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The pay-as-you-go credits row: `[bar] NN% used` then `$x / $y spent · Resets …`.
struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Usage credits")
                .font(RowStyle.title)
                .lineLimit(1)
            HStack(spacing: 8) {
                UsageBar(fraction: min(max((extra.utilization ?? 0) / 100, 0), 1),
                         utilization: extra.utilization ?? 0)
                Text("\(UsageFormat.percent(extra.utilization ?? 0)) used")
                    .font(RowStyle.value)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Text(subline)
                .font(RowStyle.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subline: String {
        let spent = UsageFormat.credits(used: extra.usedCredits,
                                        limit: extra.monthlyLimit,
                                        currency: extra.currency)
        return "\(spent) spent · \(UsageFormat.creditsResetLine())"
    }
}

/// The context-window card: `[bar]  53% · 538K/1M` then the active session's project.
/// Mirrors `WindowRow` styling so it reads as part of the same panel.
struct ContextCard: View {
    let report: ContextReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Context (current session)")
                .font(RowStyle.title)
                .lineLimit(1)
            HStack(spacing: 8) {
                UsageBar(fraction: report?.fraction ?? 0,
                         utilization: Double(report?.percent ?? 0))
                Text(valueText)
                    .font(RowStyle.value)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Text(subline)
                .font(RowStyle.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var valueText: String {
        guard let report else { return "—" }
        return "\(report.percent)% · \(UsageFormat.tokensCompact(report.occupied))/\(UsageFormat.tokensCompact(report.limit))"
    }

    private var subline: String {
        guard let report else { return "Waiting for an active session…" }
        let project = (report.session.cwd as NSString?)?.lastPathComponent
        return project.map { "in \($0)" } ?? "active session"
    }
}
