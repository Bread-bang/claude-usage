import SwiftUI
import AppKit

/// Process entry point. Branches on `--statusline` *before* any AppKit bootstrap so the
/// statusLine invocation (fired by Claude Code on every turn) stays a fast read-stdin-print-
/// exit with no menu bar item, no Dock, no event loop. Context lives in the terminal status
/// line (one per pane, always the right session); the menu bar shows account-wide usage.
@main
enum AppEntry {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--statusline") {
            StatusLineRelay.run()
            return
        }
        ClaudeUsageMiniBarApp.main()
    }
}

struct ClaudeUsageMiniBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm: UsageViewModel

    private let account = AccountInfo.loadFromClaudeConfig()

    init() {
        // Wire the dependency graph: Keychain → TokenProvider → UsageClient → ViewModel.
        let tokenProvider = TokenProvider()
        let client = UsageClient(tokenProvider: tokenProvider)
        _vm = StateObject(wrappedValue: UsageViewModel(client: client))
    }

    var body: some Scene {
        MenuBarExtra {
            UsageDropdownView(vm: vm, account: account)
        } label: {
            // The label renders the moment the app launches (it *is* the menu bar item),
            // so polling starts immediately. Hanging this on the dropdown instead would
            // delay the first fetch until the user clicks — showing "—" until then.
            MenuBarLabel(vm: vm)
                .onAppear { vm.start() }
        }
        .menuBarExtraStyle(.window) // rich SwiftUI panel rather than a plain menu
    }
}

/// Forces "agent" (accessory) activation so the app lives only in the menu bar:
/// no Dock icon, no app-switcher entry. This matters when launching the SwiftPM
/// binary directly (no Info.plist `LSUIElement`); inside a bundled .app set
/// `LSUIElement = YES` in Info.plist as well.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        // Register our statusLine command in ~/.claude/settings.json so the context line shows
        // under the prompt without the user editing anything. Non-destructive: installs only
        // into an empty-or-ours single slot, never clobbering another tool's status line.
        StatusLineInstaller.installIfPossible()
    }
}
