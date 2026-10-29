import SwiftUI

/// Game › nxnative Notes…: what nxnative says about the game (its stage, the tested list's remark, the regression
/// harness's last green run, the opening of its profile's README) and its profile's commits since the build.
struct ProfileNotesView: View {
    let game: Game
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let profile = library.profile(game)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(profile?.name ?? game.name).font(.title2.bold())
                    if let profile {
                        facts(profile)
                        news
                        if !profile.summary.isEmpty {
                            Divider()
                            ChangelogBlocks(changelog: Changelog(markdown: profile.summary))
                        }
                    } else {
                        Text(
                            "nxnative has no profile for this game: it's packed from one guessed from its files, and may not boot."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            HStack {
                if let url = profile?.notesURL {
                    Link("Full Notes on GitHub", destination: url)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 600, height: 560)
    }

    private func facts(_ profile: GameProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(profile.headline)
            } icon: {
                Image(
                    systemName: profile.stage == .bringUp ? "hammer.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(profile.stage == .bringUp ? .orange : .green)
            }
            if profile.stage == .bringUp, let note = profile.galleryNote {
                Label(
                    "In nxnative's tested games" + (note.isEmpty ? "" : " · \(note)"),
                    systemImage: "photo.on.rectangle")
            }
            if let validated = profile.validated {
                Label("Regression-checked: \(validated)", systemImage: "checkmark.seal")
            } else if profile.hasSmokeRoute {
                Label(
                    "nxnative's regression check has a route for it", systemImage: "checkmark.seal")
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var news: some View {
        let news = library.news(game)
        if !news.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Since this build").font(.headline)
                ForEach(news) { commit in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(commit.hash).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(commit.subject).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(commit.age).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(
                    game.isKept
                        ? "The build is kept, so it plays without these until you rebuild."
                        : "The next play rebuilds with them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
