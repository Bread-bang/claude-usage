import SwiftUI
import AppKit

/// Keeps at most one menu-bar popup open at a time.
///
/// The app has two independent `MenuBarExtra(.window)` items (usage and context). SwiftUI
/// gives them no awareness of each other, so opening the second leaves the first's panel on
/// screen. We capture each popup's host `NSWindow` and, whenever one becomes key (or its
/// content appears), order the others out — so the menu bar behaves like the system one,
/// where opening a menu dismisses the previous.
@MainActor
final class MenuBarPopupCoordinator {
    static let shared = MenuBarPopupCoordinator()

    private var windows: [String: NSWindow] = [:]

    /// Records the popup window for `id` and starts hiding the others when it becomes key.
    /// Idempotent: re-registering the same window is a no-op (MenuBarExtra reuses it).
    func register(id: String, window: NSWindow) {
        if windows[id] === window { return }
        windows[id] = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            // The notification fires on the main thread; hop to the main actor for the
            // isolated call. (`MainActor.assumeIsolated` is macOS 14+, so use a Task.)
            Task { @MainActor in
                MenuBarPopupCoordinator.shared.hideOthers(except: id)
            }
        }
    }

    /// Order out every registered popup except `keepID`.
    func hideOthers(except keepID: String) {
        for (id, window) in windows where id != keepID && window.isVisible {
            window.orderOut(nil)
        }
    }
}

/// Captures the `NSWindow` hosting a SwiftUI menu-bar popup and registers it under `id`.
///
/// Placed in the popup content's `.background`, so its backing view lives inside the popup
/// window. The window isn't attached yet inside `makeNSView`, so registration is deferred to
/// the main actor where `view.window` is resolved.
struct PopupWindowRegistrar: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        register(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        register(from: nsView)
    }

    private func register(from view: NSView) {
        Task { @MainActor in
            guard let window = view.window else { return }
            MenuBarPopupCoordinator.shared.register(id: id, window: window)
        }
    }
}
