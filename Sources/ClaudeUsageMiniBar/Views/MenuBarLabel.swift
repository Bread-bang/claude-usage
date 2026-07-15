import SwiftUI

/// A selectable menu-bar glyph. All symbols are verified to render on macOS 13+.
struct MenuBarIconOption: Identifiable, Hashable {
    /// Stored id / render key. Usually an SF Symbol name; `clawdSymbol` is a sentinel meaning
    /// "draw the bundled Clawd image, tinted".
    let symbol: String
    let name: String
    /// SF Symbol shown in the settings picker (the Clawd sentinel isn't a real symbol).
    let pickerSymbol: String

    init(symbol: String, name: String, pickerSymbol: String? = nil) {
        self.symbol = symbol
        self.name = name
        self.pickerSymbol = pickerSymbol ?? symbol
    }

    var id: String { symbol }

    /// Sentinel for the bundled Clawd mascot image.
    static let clawdSymbol = "clawd"
    static let defaultSymbol = clawdSymbol

    static let catalog: [MenuBarIconOption] = [
        .init(symbol: clawdSymbol,                               name: "Clawd", pickerSymbol: "pawprint.fill"),
        .init(symbol: "gauge.open.with.lines.needle.33percent",  name: "Speedometer"),
        .init(symbol: "gauge.with.dots.needle.bottom.50percent", name: "Round gauge"),
        .init(symbol: "chart.pie.fill",                          name: "Pie chart"),
        .init(symbol: "chart.bar.fill",                          name: "Bar chart"),
        .init(symbol: "bolt.fill",                               name: "Bolt"),
        .init(symbol: "sparkles",                                name: "Sparkles")
    ]
}

/// The content rendered *in the menu bar itself*: a small glyph + the headline
/// percentage, e.g. `◔ 39%`. Switches to a warning glyph when data is stale.
///
/// **Why this renders an image:** MenuBarExtra forces the system status-bar font on any
/// `Text` in its label — `.font(...)` modifiers are silently ignored (verified empirically:
/// a 7pt font rendered identically to 13pt). To control typography, we render the whole
/// label into a template `NSImage` ourselves and hand the menu bar a plain image, which
/// the system cannot restyle. `isTemplate` keeps it adapting to light/dark menu bars.
struct MenuBarLabel: View {
    /// Typography for the rendered label — tweak freely; these are honoured exactly.
    private enum Style {
        static let iconSize: CGFloat = 14
        static let textSize: CGFloat = 12
        static let spacing: CGFloat = 5
    }

    @ObservedObject var vm: UsageViewModel

    var body: some View {
        if symbolName == MenuBarIconOption.clawdSymbol, let clawd = Artwork.clawd {
            Image(nsImage: Self.renderClawd(clawd, text: vm.menuBarText))
        } else {
            Image(nsImage: Self.render(symbol: symbolName, text: vm.menuBarText))
        }
    }

    private var symbolName: String {
        if vm.report == nil && vm.error != nil { return "exclamationmark.triangle.fill" }
        if vm.isVisiblyStale { return "wifi.exclamationmark" }
        return vm.menuBarIcon
    }

    @MainActor
    private static func render(symbol: String, text: String) -> NSImage {
        let label = HStack(spacing: Style.spacing) {
            Image(systemName: symbol)
                .font(.system(size: Style.iconSize, weight: .medium))
            Text(text)
                .font(.system(size: Style.textSize, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundColor(.black) // full-alpha mask; actual tint comes from isTemplate

        let renderer = ImageRenderer(content: label)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// Clawd (coral) + the percentage (white) in one colored image. A single rendered image
    /// is used because a MenuBarExtra label with two side-by-side images only shows the first.
    /// The number is white (not template-adaptive) per the requested look; it reads on the
    /// dark menu bar. Every field is colored explicitly, so `isTemplate` stays false.
    @MainActor
    private static func renderClawd(_ clawd: NSImage, text: String) -> NSImage {
        let label = HStack(spacing: Style.spacing) {
            Image(nsImage: clawd)
                .renderingMode(.template) // silhouette alpha as mask, filled with the tint
                .resizable()
                .scaledToFit()
                .frame(width: Style.iconSize * clawd.aspect, height: Style.iconSize)
                .foregroundColor(.claudeCoral)
            Text(text)
                .font(.system(size: Style.textSize, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.white)
        }

        let renderer = ImageRenderer(content: label)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false
        return image
    }
}
