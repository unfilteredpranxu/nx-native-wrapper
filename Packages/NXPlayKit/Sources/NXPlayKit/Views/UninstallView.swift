import SwiftUI

/// NX Play › Uninstall NX Play…: what goes, with its size, what stays, and one button.
public struct UninstallView: View {
    public static let windowID = "uninstall"

    @Environment(Library.self) private var library
    @State private var uninstaller = Uninstaller()

    public init() {}

    public var body: some View {
        @Bindable var uninstaller = uninstaller
        VStack(alignment: .leading, spacing: 14) {
            Text("Uninstall NX Play").font(.title2.bold())
            Text("Removes everything NX Play put on this Mac, then quits.")
                .foregroundStyle(.secondary)

            GroupBox("Removed") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(uninstaller.items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: icon(item.kind)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let size = item.size, size > 0 {
                                Text(
                                    ByteCountFormatter.string(
                                        fromByteCount: size, countStyle: .file)
                                )
                                .monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !uninstaller.tools.isEmpty {
                        Divider()
                        Toggle(isOn: $uninstaller.removeTools) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Also remove the Homebrew tools Setup installs")
                                Text(
                                    "\(uninstaller.tools.joined(separator: ", ")). Leave this off if anything else uses them."
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("Kept") {
                VStack(alignment: .leading, spacing: 4) {
                    kept(
                        "Your games folder: the games, their builds and the saves in them",
                        library.root)
                    kept(
                        "prod.keys",
                        URL(filePath: (library.keysPath as NSString).expandingTildeInPath))
                    if !library.saveBackupPath.isEmpty {
                        kept(
                            "The save backup repository",
                            URL(filePath: (library.saveBackupPath as NSString).expandingTildeInPath)
                        )
                    }
                    kept("Homebrew itself", nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            if case .failed(let message) = uninstaller.phase {
                Text(message).foregroundStyle(.red)
            }
            if !uninstaller.log.lines.isEmpty {
                LogTextView(jobID: logID, log: uninstaller.log)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                if !library.isIdle {
                    Text("Stop the running games and builds first.").foregroundStyle(.secondary)
                }
                Spacer()
                switch uninstaller.phase {
                case .removingTools:
                    ProgressView().controlSize(.small)
                    Text("Removing the Homebrew tools…").foregroundStyle(.secondary)
                case .finishing:
                    ProgressView().controlSize(.small)
                default:
                    Button("Uninstall", role: .destructive) {
                        Task {
                            await uninstaller.uninstall(environment: library.setupEnvironment())
                        }
                    }
                    .disabled(!library.isIdle)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await uninstaller.measure() }
    }

    @State private var logID = UUID()

    private func icon(_ kind: Uninstaller.Item.Kind) -> String {
        switch kind {
        case .folder: "folder"
        case .settings: "gearshape"
        case .app: "trash"
        }
    }

    private func kept(_ title: String, _ url: URL?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "checkmark").foregroundStyle(.green).frame(width: 18)
            Text(title)
            if let url {
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

/// The app menu's Uninstall NX Play….
public struct UninstallMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("Uninstall NX Play…") { openWindow(id: UninstallView.windowID) }
    }
}
