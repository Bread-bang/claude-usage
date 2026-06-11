import Foundation
import Combine
import SwiftUI

/// Which window drives the number shown in the menu bar.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case fiveHour
    case sevenDay
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fiveHour: return "Current session"
        case .sevenDay: return "Current week (all models)"
        }
    }
}

/// Owns the polling loop and exposes a small, render-friendly surface to SwiftUI.
///
/// It keeps the **last good report** even while a refresh is in flight or has failed,
/// so the menu bar never blanks out — it shows stale data with a subtle warning instead.
@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var report: UsageReport?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: UsageError?

    /// User-tunable refresh cadence (seconds). 60s is gentle on the API and plenty fresh
    /// for windows that move in single-percent steps.
    /// All user-tunable settings persist to UserDefaults (a disk-backed plist), so they
    /// survive relaunches. Each property loads its stored value at init and writes back
    /// on every change via `didSet`.
    @Published var refreshInterval: TimeInterval = UsageViewModel.storedRefreshInterval() {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }
    /// Which window the menu-bar number reflects.
    @Published var menuBarMetric: MenuBarMetric = UsageViewModel.storedMenuBarMetric() {
        didSet { UserDefaults.standard.set(menuBarMetric.rawValue, forKey: "menuBarMetric") }
    }
    /// SF Symbol shown in the menu bar (user-selectable).
    @Published var menuBarIcon: String =
        UserDefaults.standard.string(forKey: "menuBarIcon") ?? MenuBarIconOption.defaultSymbol {
        didSet { UserDefaults.standard.set(menuBarIcon, forKey: "menuBarIcon") }
    }

    private static func storedRefreshInterval() -> TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        return stored >= 30 ? stored : 60 // unset (0) or nonsense → default 60s
    }

    private static func storedMenuBarMetric() -> MenuBarMetric {
        guard let raw = UserDefaults.standard.string(forKey: "menuBarMetric"),
              let metric = MenuBarMetric(rawValue: raw) else { return .fiveHour }
        return metric
    }

    private let client: UsageClient
    private var pollTask: Task<Void, Never>?

    private static let cachedReportKey = "cachedUsageReport"
    private static let cachedDateKey = "cachedUsageReportDate"

    init(client: UsageClient) {
        self.client = client
        restoreCache()
    }

    /// Restores the last successful report from disk so a relaunch shows data immediately
    /// (as "Updated Xm ago") instead of a blank "Never updated" while the first poll runs —
    /// or worse, fails on a transient 429.
    private func restoreCache() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.cachedReportKey),
              let cached = try? JSONDecoder().decode(UsageReport.self, from: data) else { return }
        report = cached
        lastUpdated = defaults.object(forKey: Self.cachedDateKey) as? Date
    }

    private func persistCache(_ fresh: UsageReport, at date: Date) {
        guard let data = try? JSONEncoder().encode(fresh) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: Self.cachedReportKey)
        defaults.set(date, forKey: Self.cachedDateKey)
    }

    /// Starts the polling loop. Safe to call once; subsequent calls are no-ops.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                let interval: TimeInterval
                if let self {
                    if self.report == nil {
                        // Nothing on screen yet (cold start failed) — retry quickly.
                        interval = 15
                    } else if let error = self.error, case .rateLimited = error {
                        // The endpoint allows only a few calls per burst; after a 429,
                        // back off to twice the interval instead of poking it right away.
                        interval = self.refreshInterval * 2
                    } else {
                        interval = self.refreshInterval
                    }
                } else {
                    interval = 60
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Triggers an immediate out-of-band refresh (e.g. the user clicked "Refresh").
    func refreshNow() {
        Task { await load() }
    }

    private func load() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await client.fetch()
            let now = Date()
            report = fresh
            lastUpdated = now
            error = nil
            persistCache(fresh, at: now)
        } catch let usageError as UsageError {
            error = usageError
        } catch {
            self.error = .transport(error)
        }
    }

    // MARK: - Derived display values

    /// The window that drives the menu-bar number.
    var headlineWindow: RateLimitWindow? {
        switch menuBarMetric {
        case .fiveHour: return report?.fiveHour
        case .sevenDay: return report?.sevenDay
        }
    }

    /// Menu-bar text, e.g. `"39%"`. Falls back to a dash before the first load.
    var menuBarText: String {
        guard let window = headlineWindow else { return "—" }
        return UsageFormat.percent(window.utilization)
    }

    /// `true` when we're showing data but the most recent refresh failed.
    var isStale: Bool { error != nil && report != nil }

    /// `true` when staleness is worth *showing*: the last poll failed AND the data is old
    /// enough to matter. A single transient failure (e.g. one 429) inside the grace window
    /// stays silent — the next poll usually recovers on its own.
    var isVisiblyStale: Bool {
        guard isStale, let lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > max(refreshInterval * 2.5, 150)
    }
}
