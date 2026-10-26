import AppKit
import SwiftUI

/// The games above, the log below, split by a divider that remembers where it was dragged (VSplitView
/// can neither report nor restore its position). The log can be hidden; it opens by itself when a job fails.
struct LogSplit: View {
    @Environment(Library.self) private var library
    /// The height while dragging; saved to the library when the drag ends.
    @State private var dragHeight: Double?
    @State private var dragStart: Double?

    static let minLog = 120.0
    static let minGames = 220.0

    var body: some View {
        GeometryReader { geometry in
            let height = clamped(dragHeight ?? library.logHeight, in: geometry.size.height)
            VStack(spacing: 0) {
                Group {
                    switch library.viewStyle {
                    case .grid: GameGrid()
                    case .list: GameList()
                    }
                }
                .frame(maxHeight: .infinity)
                if library.showsLog {
                    divider(in: geometry.size.height)
                    LogPanel()
                        .frame(height: height)
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }

    private func divider(in total: Double) -> some View {
        Divider()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)  // a grab area taller than the line
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? clamped(library.logHeight, in: total)
                        dragStart = start
                        dragHeight = clamped(start - drag.translation.height, in: total)
                    }
                    .onEnded { _ in
                        if let dragHeight { library.logHeight = dragHeight.rounded() }
                        dragHeight = nil
                        dragStart = nil
                    }
            )
            .padding(.vertical, -3)
    }

    /// Room for both: the games keep at least minGames, the log at least minLog.
    private func clamped(_ height: Double, in total: Double) -> Double {
        min(max(height, Self.minLog), max(Self.minLog, total - Self.minGames))
    }
}

/// Show or hide the log: the toolbar button.
struct LogToggle: View {
    @Environment(Library.self) private var library

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { library.showsLog.toggle() }
        } label: {
            Label(
                library.showsLog ? "Hide Log" : "Show Log",
                systemImage: "rectangle.bottomthird.inset.filled")
        }
        .help(library.showsLog ? "Hide the log (⇧⌘Y)" : "Show the log (⇧⌘Y)")
    }
}

/// View › Show / Hide Log, ⇧⌘Y (Xcode's shortcut for its debug area).
public struct LogMenuItem: View {
    @Environment(Library.self) private var library

    public init() {}

    public var body: some View {
        Button(library.showsLog ? "Hide Log" : "Show Log") {
            withAnimation(.snappy(duration: 0.2)) { library.showsLog.toggle() }
        }
        .keyboardShortcut("y", modifiers: [.command, .shift])
    }
}
