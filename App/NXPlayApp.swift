import NXPlayKit
import SwiftUI

@main
struct NXPlayApp: App {
    @State private var library = Library.forLaunch()

    var body: some Scene {
        Window("NX Play", id: "main") {
            RootView()
                .library(library)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Games Folder…") { library.chooseRoot() }
                    .keyboardShortcut("o")
                Button("Refresh") { library.refresh() }
                    .keyboardShortcut("r")
            }
            CommandGroup(before: .help) {
                ControlsButton()
            }
            CommandMenu("Tools") {
                ToolsMenu()
            }
        }

        Window("Remove Game Files", id: CleanupView.windowID(.gameFiles)) {
            CleanupView(kind: .gameFiles)
                .library(library)
        }
        .defaultSize(width: 720, height: 640)

        Window("Remove IPAs", id: CleanupView.windowID(.ipas)) {
            CleanupView(kind: .ipas)
                .library(library)
        }
        .defaultSize(width: 720, height: 520)

        Window("Game Controls", id: ControlsView.windowID) {
            ControlsView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .library(library)
        }
    }
}
