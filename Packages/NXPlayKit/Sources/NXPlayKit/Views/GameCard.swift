import SwiftUI

struct GameCard: View {
    let game: Game
    let job: Job?
    let isSelected: Bool
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameIcon(url: game.iconURL)
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
        .contextMenu { menu }
        .help(game.folder.path)
    }

    private var subtitle: String {
        let parts = [game.version.map { "v\($0)" }, game.titleID].compactMap(\.self)
        return parts.isEmpty ? game.folder.lastPathComponent : parts.joined(separator: " · ")
    }

    @ViewBuilder private var menu: some View {
        let busy = library.isBusy(game)
        if game.isExtracted {
            Button("Play") { library.play(game) }.disabled(busy)
            Button("Rebuild") { library.rebuild(game) }.disabled(busy)
        } else {
            Button("Extract") { library.extract(game) }.disabled(busy || !game.canExtract)
        }
        if let job, job.status.isActive {
            Button(job.kind == .play ? "Stop" : "Cancel") { job.cancel() }
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([game.buildFolder ?? game.folder])
        }
        if let save = game.saveFolder {
            Button("Open Save Folder") { NSWorkspace.shared.open(save) }
        }
        if let logs = game.logsFolder {
            Button("Open Build Logs") { NSWorkspace.shared.open(logs) }
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
                    job.status == .queued ? "Waiting for the current extraction" : stageText(job)
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
            Button("Play", systemImage: "play.fill") { library.play(game) }
                .buttonStyle(.borderedProminent)
        } else {
            Button("Extract", systemImage: "square.and.arrow.down") { library.extract(game) }
                .disabled(!game.canExtract)
        }
    }

    private func stageText(_ job: Job) -> String {
        guard let progress = job.progress else { return "Starting…" }
        let percent = progress.percent.map { " · \($0)%" } ?? ""
        return "\(progress.stage)/\(progress.stages) \(progress.title)\(percent)"
    }
}

struct Badge: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
