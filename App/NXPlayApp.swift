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
            CommandGroup(before: .toolbar) {
                ViewStyleMenuItems()
                    .library(library)
                Divider()
                LogMenuItem()
                    .library(library)
                ConsoleMenuItem()
                    .library(library)
                Divider()
            }
            CommandGroup(before: .help) {
                ControlsButton()
            }
            CommandMenu("Game") {
                GameMenu()
                    .library(library)
            }
            CommandMenu("Tools") {
                ToolsMenu()
            }
        }

        Window("Free Up Space", id: CleanupView.windowID) {
            CleanupView()
                .library(library)
        }
        .defaultSize(width: 760, height: 680)

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
