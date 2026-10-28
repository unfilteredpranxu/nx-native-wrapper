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
                // on the artwork, so a build doesn't make the card taller
                .overlay(alignment: .bottom) {
                    if let job, job.showsProgress {
                        IconProgressBar(fraction: job.progressFraction)
                    }
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
        .contextMenu { GameActions(game: game) }
        .help(job.flatMap { $0.showsProgress ? $0.progressText : nil } ?? game.folder.path)
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

    var body: some View {
        HStack(spacing: 6) {
            GameBadge(game: game, job: job)
            Spacer(minLength: 4)
            GameActionButton(game: game, job: job)
        }
        .controlSize(.small)
    }
}

/// The game's state, or what its job is doing: the card's and the list's status.
struct GameBadge: View {
    let game: Game
    let job: Job?

    /// " · 64%", the whole build's, while one runs: the card's bar has no text of its own.
    private var percent: String {
        guard let job, job.status == .running, job.showsProgress, job.progress != nil else {
            return ""
        }
        return " · \(Int((job.progressFraction * 100).rounded()))%"
    }

    var body: some View {
        switch (job?.status, job?.kind) {
        case (.running?, .play?):
            Badge(text: job?.isBuilding == true ? "Building\(percent)" : "Running", color: .green)
        case (.running?, .ipa?):
            Badge(text: "Building IPA\(percent)", color: .blue)
        case (.running?, .macApp?):
            Badge(text: "Making App\(percent)", color: .blue)
        case (.running?, .install?):
            Badge(text: "Installing\(percent)", color: .blue)
        case (.running?, _):
            Badge(text: "Extracting\(percent)", color: .blue)
        case (.queued?, _):
            Badge(text: "Queued", color: .secondary)
        case (.failed?, _):
            Badge(text: "Failed", color: .red)
        default:
            if game.isCopying {
                Badge(text: "Copying…", color: .orange)
                    .help(
                        "Finder is still copying a game file here; NX Play waits until it's complete."
                    )
            } else {
                switch game.state {
                case .ready: Badge(text: "Ready", color: .green)
                case .extracted: Badge(text: "Extracted", color: .blue)
                case .notExtracted:
                    Badge(
                        text: game.hasPackages ? "Not extracted" : "No NSP files", color: .secondary
                    )
                }
            }
        }
    }
}

/// Play, Extract, or Stop / Cancel while its job runs.
struct GameActionButton: View {
    let game: Game
    let job: Job?
    @Environment(Library.self) private var library

    var body: some View {
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

    /// Title and icon, or the icon alone when there's no room for the title.
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
}

/// A build's progress and stage, while one runs (Console Mode, under the title).
struct JobProgress: View {
    let job: Job?

    var body: some View {
        if let job, job.showsProgress {
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: job.progressFraction)
                    .controlSize(.small)
                Text(job.progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// A thin bar along the bottom of a game's artwork, inside its rounded corners, on a dark track that reads over any art.
struct IconProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.55))
                Capsule().fill(Color.accentColor)
                    .frame(width: max(6, geometry.size.width * min(max(fraction, 0), 1)))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .shadow(color: .black.opacity(0.4), radius: 2)
        .accessibilityElement()
        .accessibilityLabel("Build progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// What a game has besides its build, on its icon: an IPA in its folder, an Xcode build from Install on Device.
struct IconBadges: View {
    let game: Game

    var body: some View {
        HStack(spacing: 4) {
            if game.isKept {
                IconBadge(
                    text: "Kept", symbol: "lock.fill", color: .orange,
                    help:
                        "Keep This Build: nxnative updates don't rebuild this game, so it keeps playing as it does now. Rebuild replaces it."
                )
            }
            if let app = game.macAppURL {
                IconBadge(
                    text: "App", color: .teal,
                    help:
                        "\(app.lastPathComponent): a standalone Mac app of the game, with its own save in ~/Library/Application Support/nxnative."
                )
            }
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
    /// Shown instead of the text, which VoiceOver still reads.
    var symbol: String? = nil
    let color: Color
    let help: String

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).accessibilityLabel(text)
            } else {
                Text(text)
            }
        }
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
