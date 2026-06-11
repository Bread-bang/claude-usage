import SwiftUI

/// The panel shown when the menu bar item is clicked (MenuBarExtra `.window` style).
struct UsageDropdownView: View {
    @ObservedObject var vm: UsageViewModel
    let account: AccountInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if vm.report == nil, let error = vm.error {
                ErrorState(error: error) { vm.refreshNow() }
            } else {
                content
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 284)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Usage")
                    .font(.system(size: 13, weight: .semibold))
                if let email = account?.email {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if vm.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isVisiblyStale {
            StaleBanner(reason: vm.error?.errorDescription ?? "refresh failed")
        }

        WindowRow(title: "Current session", window: vm.report?.fiveHour)
        WindowRow(title: "Current week (all models)", window: vm.report?.sevenDay)
        WindowRow(title: "Current week (Sonnet only)", window: vm.report?.sevenDaySonnet)

        if let extra = vm.report?.extraUsage, extra.isEnabled {
            ExtraUsageRow(extra: extra)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(updatedText(now: ctx.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            settingsMenu
            Button { vm.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Menu bar shows", selection: $vm.menuBarMetric) {
                ForEach(MenuBarMetric.allCases) { Text($0.label).tag($0) }
            }
            Picker("Icon", selection: $vm.menuBarIcon) {
                ForEach(MenuBarIconOption.catalog) { option in
                    Label(option.name, systemImage: option.symbol).tag(option.symbol)
                }
            }
            Picker("Refresh every", selection: $vm.refreshInterval) {
                Text("30s").tag(TimeInterval(30))
                Text("1 min").tag(TimeInterval(60))
                Text("5 min").tag(TimeInterval(300))
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 22)
        .help("Settings")
    }

    private func updatedText(now: Date) -> String {
        guard let updated = vm.lastUpdated else { return "Never updated" }
        let seconds = Int(now.timeIntervalSince(updated))
        if seconds < 5 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        return "Updated \(minutes / 60)h ago"
    }
}

/// Shown when there is no data at all (first load failed).
private struct ErrorState: View {
    let error: UsageError
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.errorDescription ?? "Something went wrong",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(error.requiresReauth || error.isTransient ? Color.orange : Color.red)
            if error.requiresReauth {
                Text("Run Claude Code once to sign in, then this updates automatically.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if error.isTransient {
                Text("Retries automatically — no action needed.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Button("Try Again", action: retry)
                .controlSize(.small)
        }
    }
}

/// Subtle banner when showing data whose refreshes keep failing, with the actual reason.
private struct StaleBanner: View {
    let reason: String

    var body: some View {
        Label("Last known data. \(reason)", systemImage: "wifi.exclamationmark")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
