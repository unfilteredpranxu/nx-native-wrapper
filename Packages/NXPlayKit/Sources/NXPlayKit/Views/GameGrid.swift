import SwiftUI

/// Extracted games first, with their icons; then the ones still to extract.
struct GameGrid: View {
    @Environment(Library.self) private var library

    private let columns = [
        GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 16, alignment: .top)
    ]

    var body: some View {
        let extracted = library.games.filter(\.isExtracted)
        let remaining = library.games.filter { !$0.isExtracted }
        ScrollViewReader { proxy in
            ScrollView {
                if library.games.isEmpty {
                    ContentUnavailableView(
                        "No Games",
                        systemImage: "gamecontroller",
                        description: Text("No subfolder here holds NSP, NSZ, XCI or XCZ files.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !extracted.isEmpty {
                            section("Extracted", extracted)
                        }
                        if !remaining.isEmpty {
                            section("Not Extracted", remaining, extractAll: true)
                        }
                    }
                    .padding(20)
                }
            }
            .background(.background)
            // a controller moves the selection: keep it in view
            .onChange(of: library.selection) {
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(library.selection) }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, _ games: [Game], extractAll: Bool = false)
        -> some View
    {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title3.bold())
                Text("\(games.count)").foregroundStyle(.secondary)
                Spacer()
                if extractAll {
                    Button("Extract All") { library.extractAll() }
                        .disabled(library.extractableGames.isEmpty)
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(games) { game in
                    GameCard(
                        game: game, job: library.job(for: game),
                        isSelected: library.selection == game.id
                    )
                    .id(game.id)
                }
            }
        }
    }
}
