import AppKit
import SwiftUI

/// The icon.jpg nx_extract saves from the game's control data, or a placeholder before extraction.
struct GameIcon: View {
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = url.flatMap(IconCache.image(at:)) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Icons decoded once per file version: the grid redraws on every job update.
@MainActor
enum IconCache {
    private static var images: [URL: (modified: Date, image: NSImage)] = [:]

    static func image(at url: URL) -> NSImage? {
        let modified =
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        if let cached = images[url], cached.modified == modified { return cached.image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images[url] = (modified, image)
        return image
    }
}
