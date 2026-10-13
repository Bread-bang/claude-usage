import SwiftUI
import AppKit

/// Bundled artwork, loaded once from the SPM resource bundle that `scripts/bundle.sh`
/// copies into `Contents/Resources` — see `resources` below for why `Bundle.module`
/// cannot find it there.
enum Artwork {
    /// The Clawd mascot as a white-on-transparent silhouette; tint it when drawing.
    static let clawd: NSImage? = load("clawd")
    /// The Claude "spark" mark in its own coral color.
    static let spark: NSImage? = load("claude-spark")

    /// SwiftPM's generated `Bundle.module` looks in exactly two places: the *bundle root*
    /// of `Bundle.main` and the absolute `.build` path of the machine that compiled the
    /// binary. Neither works for a shipped .app — the bundle root is where a nested bundle
    /// would break the code-signature seal, and the build path only exists on the release
    /// machine, so `Bundle.module` traps at launch for everyone else. Resolve the bundle
    /// out of `Contents/Resources` (also the executable's directory under `swift run`) and
    /// keep `.module` as the fallback.
    private static let resources: Bundle = {
        let name = "ClaudeUsageMiniBar_ClaudeUsageMiniBar.bundle"
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()

    private static func load(_ name: String) -> NSImage? {
        guard let url = resources.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

extension Color {
    /// Claude clay / coral used to tint the Clawd silhouette in the menu bar.
    static let claudeCoral = Color(red: 0.80, green: 0.47, blue: 0.33) // ~#CC7854
}

extension NSImage {
    /// Width ÷ height, for laying the image out at a target height without distortion.
    var aspect: CGFloat { size.height > 0 ? size.width / size.height : 1 }
}
