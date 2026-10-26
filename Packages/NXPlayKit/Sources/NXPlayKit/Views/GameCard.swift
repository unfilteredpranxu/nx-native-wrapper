import SwiftUI

struct GameCard: View {
    let game: Game
    let job: Job?
    let isSelected: Bool
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameIcon(url: game.iconURL)
                .overlay(alignment: .topTrailing) { IconBadges(game: game).padding(6) }
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
        .contextMenu { GameActions(game: game) }
        .help(game.folder.path)
    }

    private var subtitle: String {
        let parts = [game.version.map { "v\($0)" }, game.titleID].compactMap(\.self)
        return parts.isEmpty ? game.folder.lastPathComponent : parts.joined(separator: " · ")
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

/// What a game has besides its build, on its icon: an IPA in its folder, an Xcode build from Install on Device.
private struct IconBadges: View {
    let game: Game

    var body: some View {
        HStack(spacing: 4) {
            if let xcode = game.xcodeBuildFolder {
                IconBadge(
                    text: "Xcode", color: .indigo,
                    help:
                        "Xcode build for Install on Device, a full copy of the game (\(xcode.deletingLastPathComponent().lastPathComponent)/xcode-derived-data). Tools › Free Up Space removes it."
                )
            }
            if let ipa = game.ipaURL {
                IconBadge(text: "IPA", color: .accentColor, help: Self.help(ipa))
            }
        }
    }

    static func help(_ ipa: URL) -> String {
        let size = (try? ipa.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return ipa.lastPathComponent
            + (size.map {
                ", " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "")
    }
}

/// Solid, to read over any artwork.
private struct IconBadge: View {
    let text: String
    let color: Color
    let help: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(Capsule().fill(color))
            .shadow(radius: 2)
            .help(help)
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
