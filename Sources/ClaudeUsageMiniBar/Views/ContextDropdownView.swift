import SwiftUI

/// The panel for the context battery menu-bar item.
///
/// Mirrors `UsageDropdownView`'s layout (header → content → divider → footer) so the two
/// menu-bar items feel like one app. The content is the traffic-light `ContextCard`; here,
/// unlike the menu-bar glyph, colors render fully (this isn't a template image).
struct ContextDropdownView: View {
    @ObservedObject var vm: ContextViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if vm.report != nil {
                ContextCard(report: vm.report)
            } else {
                emptyState
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 284)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "battery.50percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Claude Context")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }

    /// Shown before any usable report exists. The message depends on whether the relay hook
    /// has fired yet: nothing seen → guide the user; seen but unparsed → just wait.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.hasSeenSession {
                Label("Waiting for the first response…", systemImage: "hourglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Label("No active Claude Code session yet", systemImage: "moon.zzz")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Start (or continue) a session — context shows up on the next turn. Already-open sessions pick this up the next time they launch.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let activity = vm.report?.session.lastActivity {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(updatedText(activity: activity, now: ctx.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(vm.sessions.isEmpty ? "Not tracking" : "Tracking \(vm.sessions.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
    }

    private func updatedText(activity: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(activity))
        if seconds < 5 { return "Active just now" }
        if seconds < 60 { return "Active \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Active \(minutes)m ago" }
        return "Active \(minutes / 60)h ago"
    }
}
