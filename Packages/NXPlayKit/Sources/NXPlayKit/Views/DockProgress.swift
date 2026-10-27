import AppKit
import SwiftUI

/// The builds' progress on the Dock icon: the app icon with a bar along its bottom while extractions,
/// rebuilds, IPAs or installs run (their average when there are several), the plain icon otherwise.
/// macOS has no Dock progress bar of its own; NSDockTile shows whatever view the app gives it.
struct DockProgress: View {
    @Environment(Library.self) private var library

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: fraction, initial: true) { DockTileView.show(fraction) }
    }

    /// 0…1 across the running builds, in whole percents (fewer Dock redraws); nil when none runs.
    private var fraction: Double? {
        let building = library.jobs.values.filter { job in
            job.status.isActive && (job.kind != .play || job.status == .queued || job.isBuilding)
        }
        guard !building.isEmpty else { return nil }
        let total = building.reduce(0.0) { sum, job in
            sum + (job.status == .queued ? 0 : job.progress?.fraction ?? 0)
        }
        return (total / Double(building.count) * 100).rounded() / 100
    }
}

/// The app icon with a progress bar over its lower part, drawn for the Dock.
final class DockTileView: NSView {
    var fraction = 0.0 { didSet { needsDisplay = true } }

    @MainActor static func show(_ fraction: Double?) {
        let tile = NSApp.dockTile
        guard let fraction else {
            if tile.contentView != nil {
                tile.contentView = nil
                tile.display()
            }
            return
        }
        let view =
            tile.contentView as? DockTileView
            ?? DockTileView(frame: NSRect(origin: .zero, size: tile.size))
        view.fraction = fraction
        tile.contentView = view
        tile.display()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        // the bar sits inside the icon's rounded square, as Xcode's and Finder's do
        let inset = bounds.width * 0.16
        let height = max(bounds.height * 0.085, 8)
        let track = NSRect(
            x: inset, y: bounds.height * 0.13, width: bounds.width - inset * 2, height: height)
        let radius = height / 2
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(
            roundedRect: track.insetBy(dx: -2, dy: -2), xRadius: radius + 2, yRadius: radius + 2
        ).fill()
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let done = max(height, track.width * min(max(fraction, 0), 1))  // always a dot, so it reads as started
        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: track.minX, y: track.minY, width: done, height: height),
            xRadius: radius, yRadius: radius
        ).fill()
    }
}
