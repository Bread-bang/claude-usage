import SwiftUI
import AppKit

@main
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
    }
}
