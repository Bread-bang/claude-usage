import SwiftUI
import AppKit

/// Process entry point. Branches on `--hook-relay` *before* any AppKit bootstrap so the
/// hook-relay invocation (fired by Claude Code hooks on every turn) stays a fast, headless
/// read-stdin-write-file-exit with no menu bar item, no Dock, no event loop.
@main
enum AppEntry {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--hook-relay") {
            HookRelay.run()
            return
        }
        ClaudeUsageMiniBarApp.main()
    }
}

struct ClaudeUsageMiniBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm: UsageViewModel
    @StateObject private var contextVM = ContextViewModel()

    private let account = AccountInfo.loadFromClaudeConfig()

    init() {
        // Wire the dependency graph: Keychain → TokenProvider → UsageClient → ViewModel.
        let tokenProvider = TokenProvider()
        let client = UsageClient(tokenProvider: tokenProvider)
        _vm = StateObject(wrappedValue: UsageViewModel(client: client))
    }

    var body: some Scene {
        // Two independent menu-bar items: rate-limit usage, and the context widget.
        // Each popup registers its window with the coordinator and dismisses the other when
        // it opens, so only one panel is ever on screen at a time.
        MenuBarExtra {
            UsageDropdownView(vm: vm, account: account)
                .background(PopupWindowRegistrar(id: Self.usageID))
                .onAppear { MenuBarPopupCoordinator.shared.hideOthers(except: Self.usageID) }
        } label: {
            // The label renders the moment the app launches (it *is* the menu bar item),
            // so polling starts immediately. Hanging this on the dropdown instead would
            // delay the first fetch until the user clicks — showing "—" until then.
            MenuBarLabel(vm: vm)
                .onAppear { vm.start() }
        }
        .menuBarExtraStyle(.window) // rich SwiftUI panel rather than a plain menu

        MenuBarExtra {
            ContextDropdownView(vm: contextVM)
                .background(PopupWindowRegistrar(id: Self.contextID))
                .onAppear { MenuBarPopupCoordinator.shared.hideOthers(except: Self.contextID) }
        } label: {
            ContextMenuBarLabel(vm: contextVM)
                .onAppear { contextVM.start() }
        }
        .menuBarExtraStyle(.window)
    }

    private static let usageID = "usage"
    private static let contextID = "context"
}

/// Forces "agent" (accessory) activation so the app lives only in the menu bar:
/// no Dock icon, no app-switcher entry. This matters when launching the SwiftPM
/// binary directly (no Info.plist `LSUIElement`); inside a bundled .app set
/// `LSUIElement = YES` in Info.plist as well.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        // Register our hook-relay command in ~/.claude/settings.json so context tracking
        // works without the user editing anything. Idempotent; preserves existing hooks.
        HookInstaller.installIfNeeded()
    }
}
