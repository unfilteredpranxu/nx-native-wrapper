import NXPlayKit
import SwiftUI

@main
struct NXPlayApp: App {
    @State private var library = Library()

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
        }

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}
