import SwiftUI

public struct SettingsView: View {
    @Environment(Library.self) private var library

    public init() {}

    public var body: some View {
        @Bindable var library = library
        Form {
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
                    title: "nxnative repository",
                    path: $library.nxnativePath,
                    directory: true,
                    isValid: exists(library.nxnativePath, "scripts/build_ipa_from_nsp.py")
                )
                PathField(
                    title: "prod.keys", path: $library.keysPath, directory: false,
                    isValid: exists(library.keysPath))
                Toggle(
                    "Allow a Metal compiler nxnative didn't test", isOn: $library.allowOtherMetal)
                LabeledContent("Tools") {
                    SetupMenuItem()
                }
            } footer: {
                Text(
                    "nxplay pulls nxnative before each run and rebuilds a game when new commits arrive. nxnative stops a build when this Mac's Metal compiler (Xcode's) isn't the one it tested its shaders with; the toggle builds anyway, at the risk of shader glitches (nxnative issue #242)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("Game language", selection: $library.language) {
                    Text("As built").tag("")
                    Divider()
                    ForEach(GameLanguage.all) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                Toggle("Show the Metal performance HUD while playing", isOn: $library.metalHUD)
                Toggle(
                    "Start games in full screen (always from Console Mode)",
                    isOn: $library.fullScreenGames)
            } footer: {
                Text(
                    "Sets DM_LANG when a game starts. A game without the language gets the same language for another region, or keeps its build's."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                PathField(
                    title: "Save backup repository", path: $library.saveBackupPath, directory: true,
                    isValid: library.saveBackupPath.isEmpty
                        ? nil : exists(library.saveBackupPath, ".git"),
                    prompt: "None")
            } footer: {
                Text(
                    "A clone of your own private Git repository. While a game plays, NX Play copies its save into a folder named after it (the-game-name-<title ID>) once the game has saved, commits it and pushes, with your Git credentials. Empty: no backup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Picker("Apple team", selection: $library.teamID) {
                    Text(library.team.map { "Automatic (\($0.name))" } ?? "None in Xcode").tag("")
                    Divider()
                    ForEach(library.teams) { team in
                        Text(team.isFree ? "\(team.name) (Personal Team)" : team.name).tag(team.id)
                    }
                }
            } footer: {
                Text(
                    "Signs Install on Device: Xcode builds the game for your iPhone or iPad and installs it, no sideloading. Teams come from Xcode › Settings › Apple Accounts; a Personal Team builds without the Increased Memory Limit."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear { library.refreshDevices() }
        .formStyle(.grouped)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func exists(_ path: String, _ inside: String = "") -> Bool {
        let base = (path as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: inside.isEmpty ? base : base + "/" + inside)
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
