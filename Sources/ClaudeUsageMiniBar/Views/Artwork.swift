import SwiftUI
import AppKit

/// Bundled artwork, loaded once via `Bundle.module` (works under `swift run` and the .app,
/// as long as the SPM resource bundle is copied next to the binary — see `scripts/bundle.sh`).
enum Artwork {
    /// The Clawd mascot as a white-on-transparent silhouette; tint it when drawing.
    static let clawd: NSImage? = load("clawd")
    /// The Claude "spark" mark in its own coral color.
    static let spark: NSImage? = load("claude-spark")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
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
