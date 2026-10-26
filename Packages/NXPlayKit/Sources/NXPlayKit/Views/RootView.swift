import Combine
import SwiftUI

/// The main window: the games of the chosen folder above, the selected game's nxplay output below.
public struct RootView: View {
    @Environment(Library.self) private var library
    #if DEBUG
        @Environment(\.openSettings) private var openSettings
    #endif

    public init() {}

    public var body: some View {
        content
            .frame(minWidth: 720, minHeight: 540)
            .navigationTitle(library.root?.lastPathComponent ?? "NX Play")
            .navigationSubtitle(
                library.root.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
            )
            .toolbar { toolbar }
            .sheet(item: Bindable(library).transfer) { transfer in
                TransferSavesView(transfer: transfer)
            }
            .alert("Can't run nxplay", isPresented: problemShown) {
                Button("OK") {}
            } message: {
                Text(library.problem ?? "")
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                library.refresh()
                library.refreshDevices()
            }
            #if DEBUG
                .task { if library.screenshotScene == .settings { openSettings() } }
            #endif
    }

    @ViewBuilder private var content: some View {
        if library.root == nil {
            ContentUnavailableView {
                Label("No Games Folder", systemImage: "folder")
            } description: {
                Text(
                    "Choose the folder with one subfolder per game: its NSP, NSZ, XCI or XCZ files."
                )
            } actions: {
                Button("Choose Folder…") { library.chooseRoot() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            LogSplit()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            LogToggle()
            Button {
                library.chooseRoot()
            } label: {
                Label("Choose Folder", systemImage: "folder")
            }
            .help("Choose the games folder")
            Button {
                library.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Look for new games")
            Button {
                library.extractAll()
            } label: {
                Label("Extract All", systemImage: "square.and.arrow.down.on.square")
            }
            .help("Extract every game not extracted yet, one after another")
            .disabled(library.extractableGames.isEmpty)
            ControlsButton()
        }
    }

    private var problemShown: Binding<Bool> {
        Binding(get: { library.problem != nil }, set: { if !$0 { library.problem = nil } })
    }
}
