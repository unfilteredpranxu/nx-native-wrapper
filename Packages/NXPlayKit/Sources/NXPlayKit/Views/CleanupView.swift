import SwiftUI

/// Tools › Remove Game Files / Remove IPAs: the removable files per game with their sizes, checkboxes, and a
/// typed confirmation before anything is deleted.
public struct CleanupView: View {
    public static func windowID(_ kind: CleanupKind) -> String { "cleanup-\(kind.rawValue)" }

    @Environment(Library.self) private var library
    @State private var cleanup: Cleanup

    public init(kind: CleanupKind) {
        _cleanup = State(initialValue: Cleanup(kind: kind))
    }

    private var kind: CleanupKind { cleanup.kind }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .gameFiles ? "Remove Game Files" : "Remove IPAs").font(.title2.bold())
            Text(
                kind == .gameFiles
                    ? "The original NSP, NSZ, XCI and XCZ files of games that are built for the Mac, and the NSPs a build converted from NSZ. The games keep playing from their builds."
                    : "The IPAs built for sideloading. Build IPA makes them again."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if cleanup.groups.isEmpty {
                ContentUnavailableView(
                    kind == .gameFiles ? "No Game Files" : "No IPAs", systemImage: "externaldrive",
                    description: Text(
                        library.root == nil
                            ? "Choose a games folder first."
                            : "Nothing to remove in \(library.root!.lastPathComponent).")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
                footer
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
        .onAppear(perform: rescan)
        .onChange(of: library.games) { rescan() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            library.refresh()
            rescan()
        }
    }

    private var list: some View {
        List {
            ForEach(cleanup.groups) { group in
                Section {
                    ForEach(group.files) { file in
                        FileRow(file: file, isOn: cleanup.selection.contains(file.url)) {
                            cleanup.toggle(file)
                        }
                        .disabled(group.blocked != nil)
                    }
                } header: {
                    GroupHeader(group: group, selected: cleanup.isSelected(group)) {
                        cleanup.toggle(group)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(
                    "Selected: \(cleanup.selection.count) of \(cleanup.groups.flatMap(\.files).count) files, \(bytes(cleanup.selectedSize))"
                )
                .fontWeight(.medium)
                Spacer()
                Text(
                    "\(bytes(cleanup.totalSize)) in \(cleanup.groups.count) game\(cleanup.groups.count == 1 ? "" : "s")"
                )
                .foregroundStyle(.secondary)
            }
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            switch cleanup.phase {
            case .done(let count, let size):
                Label(
                    "Removed \(count) file\(count == 1 ? "" : "s"), freed \(bytes(size)).",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            default:
                EmptyView()
            }
            HStack {
                TextField("Type “\(Cleanup.phrase)” to confirm", text: $cleanup.confirmation)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit(delete)
                if cleanup.phase == .deleting { ProgressView().controlSize(.small) }
                Spacer()
                Button(role: .destructive, action: delete) {
                    Text(
                        "Delete \(cleanup.selection.count) File\(cleanup.selection.count == 1 ? "" : "s")"
                    )
                }
                .disabled(!cleanup.canDelete)
            }
        }
    }

    private var warning: String {
        kind == .gameFiles
            ? "Deleted for good, not moved to the Trash. Without them a game can't be rebuilt: it keeps its current build when nxnative updates, and Install on Device and Build IPA need the files back. If this folder holds your only copy of a game, keep a backup elsewhere."
            : "Deleted for good, not moved to the Trash."
    }

    private func rescan() {
        let busy = Set(library.games.filter(library.isBusy).map(\.id))
        cleanup.scan(games: library.games, busy: busy)
    }

    private func delete() {
        guard cleanup.canDelete else { return }
        rescan()  // a game that started building meanwhile is no longer selectable
        Task {
            await cleanup.delete()
            library.refresh()
            rescan()
        }
    }

    private func bytes(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

private struct GroupHeader: View {
    let group: CleanupGroup
    let selected: Bool?
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { selected == true }, set: { _ in toggle() })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(group.blocked != nil)
                .overlay { if selected == nil { MixedMark() } }
            GameIcon(url: group.game.iconURL).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.game.name).font(.headline).foregroundStyle(.primary)
                if let blocked = group.blocked {
                    Text(blocked).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file))
                .font(.headline.monospacedDigit())
                .foregroundStyle(group.blocked == nil ? .primary : .secondary)
        }
        .padding(.vertical, 4)
    }
}

/// A partly selected game: a dash over its checkbox, as AppKit's mixed state shows.
private struct MixedMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(.primary).frame(width: 8, height: 2)
            .allowsHitTesting(false)
    }
}

private struct FileRow: View {
    let file: CleanupFile
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { isOn }, set: { _ in toggle() })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    if file.role == .converted {
                        Text(
                            "Converted from NSZ by the build, in \(file.url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)/nsp"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 26)
        .help(file.url.path)
    }
}

/// The Tools menu: opens the cleanup windows (openWindow needs a view's environment).
public struct ToolsMenu: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("Remove Game Files…") { openWindow(id: CleanupView.windowID(.gameFiles)) }
        Button("Remove IPAs…") { openWindow(id: CleanupView.windowID(.ipas)) }
    }
}
