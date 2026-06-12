import SwiftUI

/// The context widget rendered *in the menu bar*: `scroll 61%`.
///
/// Uses the same ImageRenderer + isTemplate trick as `MenuBarLabel` — MenuBarExtra silently
/// ignores `.font()` on live SwiftUI views, so we bake the label into an NSImage ourselves.
struct ContextMenuBarLabel: View {
    @ObservedObject var vm: ContextViewModel

    private enum Style {
        static let iconSize: CGFloat = 14
        static let textSize: CGFloat = 12
        static let spacing: CGFloat = 5
    }

    var body: some View {
        Image(nsImage: Self.render(text: vm.menuBarText))
    }

    @MainActor
    private static func render(text: String) -> NSImage {
        let label = HStack(spacing: Style.spacing) {
            Image(systemName: "scroll")
                .font(.system(size: Style.iconSize, weight: .medium))
            Text(text)
                .font(.system(size: Style.textSize, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundColor(.black)

        let renderer = ImageRenderer(content: label)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
