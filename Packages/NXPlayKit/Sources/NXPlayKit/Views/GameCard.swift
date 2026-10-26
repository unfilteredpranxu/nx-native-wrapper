import SwiftUI

struct GameCard: View {
    let game: Game
    let job: Job?
    let isSelected: Bool
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameIcon(url: game.iconURL)
                .overlay(alignment: .topTrailing) {
                    if let ipa = game.ipaURL { IPABadge(url: ipa).padding(6) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GameStatus(game: game, job: job)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(
                isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(
                isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(count: 2) { library.primaryAction(for: game) }
        .simultaneousGesture(TapGesture().onEnded { library.selection = game.id })
        // macOS menus show only titles unless the label style asks for the icons too
        .contextMenu { menu.labelStyle(.titleAndIcon) }
        .help(game.folder.path)
    }

    private var subtitle: String {
        let parts = [game.version.map { "v\($0)" }, game.titleID].compactMap(\.self)
        return parts.isEmpty ? game.folder.lastPathComponent : parts.joined(separator: " · ")
    }

    @ViewBuilder private var menu: some View {
        let busy = library.isBusy(game)
        if game.isExtracted {
            Button("Play", systemImage: "play.fill") { library.play(game) }.disabled(busy)
            // a game whose original files were removed plays its build but cannot be rebuilt
            Button("Rebuild", systemImage: "hammer") { library.rebuild(game) }.disabled(
                busy || !game.hasPackages)
        } else {
            Button("Extract", systemImage: "square.and.arrow.down") { library.extract(game) }
                .disabled(busy || !game.canExtract)
        }
        Menu("Install on Device", systemImage: "apps.iphone") {
            if library.devices.isEmpty {
                Text(
                    library.isLoadingDevices
                        ? "Looking for devices…"
                        : "No device: pair one in Xcode, with Developer Mode on")
            }
            ForEach(library.devices) { device in
                Button(
                    "\(device.name) · \(device.model)",
                    systemImage: device.model.contains("iPad") ? "ipad" : "iphone"
                ) {
                    library.install(game, on: device)
                }
            }
            Divider()
            Button("Look Again", systemImage: "arrow.clockwise") { library.refreshDevices() }
        }
        .disabled(busy || !game.isExtracted || !game.canBuildIPA)
        Button(game.ipaURL == nil ? "Build IPA" : "Rebuild IPA", systemImage: "shippingbox") {
            library.buildIPA(game)
        }
        .disabled(busy || !game.canBuildIPA)
        Button("Transfer Saves…", systemImage: "arrow.left.arrow.right") {
            library.transferSaves(game)
        }
        .disabled(busy || game.titleID == nil || game.buildFolder == nil)
        if let job, job.status.isActive {
            if job.kind == .play {
                Button("Stop", systemImage: "stop.fill") { job.cancel() }
            } else {
                Button("Cancel", systemImage: "xmark") { job.cancel() }
            }
        }
        Divider()
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([game.buildFolder ?? game.folder])
        }
        if let ipa = game.ipaURL {
            Button("Show IPA in Finder", systemImage: "shippingbox") {
                NSWorkspace.shared.activateFileViewerSelecting([ipa])
            }
        }
        if let save = game.saveFolder {
            Button("Open Save Folder", systemImage: "tray.full") { NSWorkspace.shared.open(save) }
        }
        if let logs = game.logsFolder {
            Button("Open Build Logs", systemImage: "doc.text") { NSWorkspace.shared.open(logs) }
        }
    }
}

/// Title first, then the state badge and the action under it.
private struct GameStatus: View {
    let game: Game
    let job: Job?
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                badge
                Spacer(minLength: 4)
                action
            }
            .controlSize(.small)
            if let job, job.status.isActive, job.kind != .play || job.isBuilding {
                ProgressView(value: job.status == .queued ? 0 : job.progress?.fraction ?? 0)
                    .controlSize(.small)
                Text(
                    job.status == .queued ? "Waiting for the current build" : stageText(job)
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var badge: some View {
        switch (job?.status, job?.kind) {
        case (.running?, .play?):
            Badge(text: job?.isBuilding == true ? "Building" : "Running", color: .green)
        case (.running?, .ipa?):
            Badge(text: "Building IPA", color: .blue)
        case (.running?, .install?):
            Badge(text: "Installing", color: .blue)
        case (.running?, _):
            Badge(text: "Extracting", color: .blue)
        case (.queued?, _):
            Badge(text: "Queued", color: .secondary)
        case (.failed?, _):
            Badge(text: "Failed", color: .red)
        default:
            switch game.state {
            case .ready: Badge(text: "Ready", color: .green)
            case .extracted: Badge(text: "Extracted", color: .blue)
            case .notExtracted:
                Badge(text: game.hasPackages ? "Not extracted" : "No NSP files", color: .secondary)
            }
        }
    }

    @ViewBuilder private var action: some View {
        if let job, job.status.isActive {
            Button(job.kind == .play && !job.isBuilding ? "Stop" : "Cancel", role: .cancel) {
                job.cancel()
            }
        } else if game.isExtracted {
            compactButton("Play", systemImage: "play.fill") { library.play(game) }
                .buttonStyle(.borderedProminent)
        } else {
            compactButton("Extract", systemImage: "square.and.arrow.down") { library.extract(game) }
                .disabled(!game.canExtract)
        }
    }

    /// Title and icon, or the icon alone when a narrow card has no room for the title beside the badge.
    private func compactButton(
        _ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            Button(title, systemImage: systemImage, action: action)
                .labelStyle(.titleAndIcon)
            Button(title, systemImage: systemImage, action: action)
                .labelStyle(.iconOnly)
                .help(Text(title))
        }
    }

    private func stageText(_ job: Job) -> String {
        guard let progress = job.progress else { return "Starting…" }
        let percent = progress.percent.map { " · \($0)%" } ?? ""
        return "\(progress.stage)/\(progress.stages) \(progress.title)\(percent)"
    }
}

/// On the icon of a game whose IPA is in its folder: solid, to read over any artwork.
private struct IPABadge: View {
    let url: URL

    var body: some View {
        Text("IPA")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.accentColor))
            .shadow(radius: 2)
            .help(help)
    }

    private var help: String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return url.lastPathComponent
            + (size.map {
                ", " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "")
    }
}

struct Badge: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
