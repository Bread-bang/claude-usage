import SwiftUI
import AppKit

/// Renders a mock of the dropdown to a PNG for the README (`--screenshot <path>`).
///
/// Uses the real `WindowRow` component and the bundled spark artwork with fixed sample
/// numbers and no account email, so the marketing image stays faithful to the live UI.
enum ScreenshotMock {
    @MainActor
    static func render(to path: String) {
        _ = NSApplication.shared // bring AppKit up so SwiftUI text/symbols rasterize headlessly

        let renderer = ImageRenderer(content: MockDropdown().environment(\.colorScheme, .dark))
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("screenshot: render failed\n".utf8))
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("screenshot: wrote \(path) (\(Int(image.size.width))×\(Int(image.size.height)) pt)")
        } catch {
            FileHandle.standardError.write(Data("screenshot: write failed: \(error)\n".utf8))
        }
    }
}

private struct MockDropdown: View {
    // Sample numbers for the README: 80% session, 50% weekly, a lighter model-scoped week.
    private let sessionPct: Double = 80
    private let weeklyPct: Double = 50
    private let fablePct: Double = 30

    var body: some View {
        let now = Date()
        let session = RateLimitWindow(utilization: sessionPct, resetsAtRaw: iso(now.addingTimeInterval(2 * 3600)))
        let weekly = RateLimitWindow(utilization: weeklyPct, resetsAtRaw: iso(now.addingTimeInterval(6.4 * 86400)))
        let fable = RateLimitWindow(utilization: fablePct, resetsAtRaw: iso(now.addingTimeInterval(6.4 * 86400)))

        VStack(alignment: .leading, spacing: 12) {
            header
            WindowRow(title: "Current session", window: session)
            WindowRow(title: "Current week (all models)", window: weekly)
            WindowRow(title: "Current week (Fable)", window: fable)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 284)
        .background(Color(red: 0.106, green: 0.106, blue: 0.114))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let spark = Artwork.spark {
                Image(nsImage: spark).resizable().scaledToFit().frame(width: 18, height: 18)
            }
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Updated just now")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "gearshape")
            Image(systemName: "arrow.clockwise")
            Image(systemName: "power")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
