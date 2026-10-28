import SwiftUI

/// The Settings window, one tab per subject: each tab is only as tall as its own settings, so the window fits a small
/// screen (all of them on one page ran under the Dock on a laptop).
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PlayingSettings()
                .tabItem { Label("Playing", systemImage: "gamecontroller") }
            SaveSettings()
                .tabItem { Label("Saves", systemImage: "externaldrive") }
            DeviceSettings()
                .tabItem { Label("Devices", systemImage: "iphone") }
            UpdatesTab()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
    }
}

/// A tab's page: a grouped form at the window's width, as tall as its content.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: 600)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Footer: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

private func exists(_ path: String, _ inside: String = "") -> Bool {
    let base = (path as NSString).expandingTildeInPath
    return FileManager.default.fileExists(atPath: inside.isEmpty ? base : base + "/" + inside)
}

/// Where the games, nxnative and the keys are, and the tools the builds need.
private struct GeneralSettings: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        SettingsPage {
            Section {
                LabeledContent("Games folder") {
                    HStack {
                        Text(
                            library.root.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                                ?? "None"
                        )
                        .foregroundStyle(library.root == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        Button("Choose…") { library.chooseRoot() }
                    }
                }
                PathField(
                    title: "prod.keys", path: $library.keysPath, directory: false,
                    isValid: exists(library.keysPath))
            }
            Section {
                PathField(
                    title: "nxnative repository",
                    path: $library.nxnativePath,
                    directory: true,
                    isValid: exists(library.nxnativePath, "scripts/build_ipa_from_nsp.py")
                )
                Toggle(
                    "Allow a Metal compiler nxnative didn't test", isOn: $library.allowOtherMetal)
                LabeledContent("Tools") {
                    SetupMenuItem()
                }
            } footer: {
                Footer(
                    "nxplay pulls nxnative before each run and rebuilds a game when new commits arrive. nxnative stops a build when this Mac's Metal compiler (Xcode's) isn't the one it tested its shaders with; the toggle builds anyway, at the risk of shader glitches (nxnative issue #242)."
                )
            }
        }
    }
}

/// How games start.
private struct PlayingSettings: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        SettingsPage {
            Section {
                Picker("Game language", selection: $library.language) {
                    Text("As built").tag("")
                    Divider()
                    ForEach(GameLanguage.all) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                Toggle(
                    "Start games in full screen (always from Console Mode)",
                    isOn: $library.fullScreenGames)
                Toggle("Show the Metal performance HUD while playing", isOn: $library.metalHUD)
            } footer: {
                Footer(
                    "Sets DM_LANG when a game starts. A game without the language gets the same language for another region, or keeps its build's."
                )
            }
        }
    }
}

/// Save backup to the player's own repository.
private struct SaveSettings: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        SettingsPage {
            Section {
                PathField(
                    title: "Save backup repository", path: $library.saveBackupPath, directory: true,
                    isValid: library.saveBackupPath.isEmpty
                        ? nil : exists(library.saveBackupPath, ".git"),
                    prompt: "None")
            } footer: {
                Footer(
                    "A clone of your own private Git repository. While a game plays, NX Play copies its save into a folder named after it (the-game-name-<title ID>) once the game has saved, commits it and pushes, with your Git credentials. Empty: no backup."
                )
            }
        }
    }
}

/// Install on Device's signing.
private struct DeviceSettings: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        SettingsPage {
            Section {
                Picker("Apple team", selection: $library.teamID) {
                    Text(library.team.map { "Automatic (\($0.name))" } ?? "None in Xcode").tag("")
                    Divider()
                    ForEach(library.teams) { team in
                        Text(team.isFree ? "\(team.name) (Personal Team)" : team.name).tag(team.id)
                    }
                }
            } footer: {
                Footer(
                    "Signs Install on Device: Xcode builds the game for your iPhone or iPad and installs it, no sideloading. Teams come from Xcode › Settings › Apple Accounts; a Personal Team builds without the Increased Memory Limit."
                )
            }
        }
        .onAppear { library.refreshDevices() }
    }
}

private struct UpdatesTab: View {
    @Environment(Library.self) private var library

    var body: some View {
        SettingsPage {
            Section {
                UpdateSettings()
            } footer: {
                Footer(
                    library.updater.isEnabled
                        ? "NX Play looks for a new release on GitHub at launch and once a day, and downloads it. It installs when you quit, or now with Restart to Update."
                        : "This copy was built from the source: update it with git pull and bin/install."
                )
            }
        }
    }
}

private struct PathField: View {
    let title: LocalizedStringKey
    @Binding var path: String
    let directory: Bool
    /// Nil for an optional field left empty: no mark.
    let isValid: Bool?
    var prompt: LocalizedStringKey? = nil

    var body: some View {
        LabeledContent(title) {
            HStack {
                TextField(title, text: $path, prompt: prompt.map { Text($0) })
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                if let isValid {
                    Image(
                        systemName: isValid
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isValid ? .green : .orange)
                    .help(isValid ? "Found" : "Not found")
                }
                Button("Choose…") {
                    if let url = PathPicker.choose(directory: directory, startingAt: path) {
                        path = url.path
                    }
                }
            }
        }
    }
}
