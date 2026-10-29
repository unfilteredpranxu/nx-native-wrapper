import SwiftUI

/// Above the library once an update is staged: it installs when NX Play quits, or now.
struct UpdateBanner: View {
    let version: String
    let notes: Changelog
    @Environment(Library.self) private var library

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.circle")
            if library.quitsWhenIdle {
                Text("NX Play restarts with \(version) once the running game or build ends.")
            } else {
                Text("NX Play \(version) is ready. It installs when you quit.")
            }
            Spacer()
            WhatsNewButton(version: version, notes: notes)
            if !library.quitsWhenIdle {
                Button("Restart to Update") { library.restartToUpdate() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.blue.opacity(0.12))
    }
}

/// Settings' Updates section.
struct UpdateSettings: View {
    @Environment(Library.self) private var library

    var body: some View {
        let updater = library.updater
        LabeledContent("Version \(updater.currentVersion)") {
            HStack {
                status(updater.state)
                switch updater.state {
                case .ready(let version, let notes):
                    WhatsNewButton(version: version, notes: notes)
                    Button("Restart to Update") { library.restartToUpdate() }
                case .checking, .downloading: EmptyView()
                default: Button("Check Now") { Task { await updater.check() } }
                }
            }
        }
        .disabled(!updater.isEnabled)
    }

    @ViewBuilder private func status(_ state: AppUpdater.State) -> some View {
        switch state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate: Text("Up to date").foregroundStyle(.secondary)
        case .downloading(let version):
            ProgressView().controlSize(.small)
            Text("Downloading \(version)…").foregroundStyle(.secondary)
        case .ready(let version, _): Text("\(version) is ready").foregroundStyle(.secondary)
        case .failed(let message): Text(message).foregroundStyle(.orange).lineLimit(2)
        }
    }
}
