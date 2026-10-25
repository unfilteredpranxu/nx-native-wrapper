import NXPlayKit
import SwiftUI

@main
struct NXPlayApp: App {
    @State private var library = Library.forLaunch()

    var body: some Scene {
        Window("NX Play", id: "main") {
            RootView()
                .environment(library)
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
        }

        Window("Game Controls", id: ControlsView.windowID) {
            ControlsView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}
