import AppKit
import SwiftUI

/// Console Mode: the window full screen. The selected game's eShop banner fills the upper part edge to edge, the clock
/// and controller over its top and the game's name and badges over its foot; the games as a carousel of their artwork
/// below it, button hints at the bottom. A controller, the arrow keys with Return and Esc, or the mouse drive it.
struct ConsoleView: View {
    @Environment(Library.self) private var library
    @FocusState private var focused: Bool

    static let tile = 240.0

    var body: some View {
        let games = library.navigableGames  // the extracted ones
        let selected = games.first { $0.id == library.selection } ?? games.first
        VStack(spacing: 0) {
            // the banner takes what the carousel and the hints leave: about half of the screen
            Banner(game: selected, banner: selected.flatMap(library.banner(for:)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    TopBar(gamepad: library.gamepad)
                        .padding(.horizontal, 56)
                        .padding(.top, 40)
                }
                .overlay(alignment: .bottomLeading) {
                    if let selected {
                        Caption(game: selected, job: library.job(for: selected))
                            .padding(.horizontal, 56)
                    }
                }
            if games.isEmpty {
                Text("No games ready to play yet").font(.largeTitle.bold())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(height: Carousel.height)
            } else {
                Carousel(games: games, selection: selected?.id)
            }
            // the build beside the hints, in the layout: as an overlay of the one-line hints it rose over the tiles
            HStack(alignment: .bottom, spacing: 24) {
                FooterBuild(jobs: library.buildingJobs)
                Hints(game: selected, gamepad: library.gamepad)
            }
            .animation(.easeInOut(duration: 0.25), value: library.buildingJobs.isEmpty)
            .padding(.horizontal, 56)
            .padding(.bottom, 36)
        }
        .background { Backdrop(game: selected) }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) {
            library.handle(.left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            library.handle(.right)
            return .handled
        }
        .onKeyPress(.upArrow) {
            library.handle(.up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            library.handle(.down)
            return .handled
        }
        .onKeyPress(.return) {
            library.handle(.confirm)
            return .handled
        }
        .onExitCommand { library.handle(.back) }
    }
}

/// Behind the whole screen: the selected game's cover, blurred into colour and dimmed, so the part under the banner
/// carries the game's colours rather than black. It cross-fades as the selection moves.
private struct Backdrop: View {
    let game: Game?

    var body: some View {
        // the artwork as an overlay of a flexible colour: scaledToFill would otherwise size the layout to the image
        Color.black
            .overlay {
                if let url = game?.iconURL, let image = IconCache.image(at: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 80)
                        .saturation(1.3)
                        .id(url)
                        .transition(.opacity)
                }
            }
            .overlay { Color.black.opacity(0.8) }  // dark: the tiles and the hints stand out, the colour stays
            .clipped()
            .animation(.easeInOut(duration: 0.45), value: game?.id)
    }
}

/// The selected game's eShop banner edge to edge, sharp, its lower part fading to transparent into the blurred cover
/// below, darkened behind the top bar and the name. Without one, the cover shows through. It cross-fades as the
/// selection moves.
private struct Banner: View {
    let game: Game?
    let banner: URL?

    var body: some View {
        // the artwork as an overlay of a flexible colour: scaledToFill would otherwise size the layout to the image
        Color.clear
            .overlay {
                if let banner, let image = IconCache.image(at: banner) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .id(banner)
                        .transition(.opacity)
                }
            }
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.25),
                    ], startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.6), .clear], startPoint: .leading,
                    endPoint: UnitPoint(x: 0.65, y: 0.5))
            }
            // opaque down to the middle, then fading out: the banner melts into the backdrop instead of into black
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.5), .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .animation(.easeInOut(duration: 0.45), value: game?.id)
    }
}

private struct TopBar: View {
    let gamepad: Gamepad

    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 12) {
                Logo().frame(height: 30)
                Text("NX Play")
            }
            .font(.title2.weight(.bold))
            Spacer()
            if let name = gamepad.name {
                HStack(spacing: 6) {
                    Image(systemName: "gamecontroller")
                    Text(name)
                    if let battery = gamepad.battery {
                        Image(
                            systemName: battery > 0.75
                                ? "battery.100percent"
                                : battery > 0.5
                                    ? "battery.75percent"
                                    : battery > 0.25 ? "battery.50percent" : "battery.25percent")
                    }
                }
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
            }
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.white)
    }
}

/// The games side by side from the left edge, the selected one larger and outlined. The row moves a tile at a time,
/// only when the selection would leave the screen, so it starts at the left and ends at the right.
private struct Carousel: View {
    let games: [Game]
    let selection: Game.ID?
    @Environment(Library.self) private var library
    /// The first tile on screen.
    @State private var first = 0

    static let spacing = 40.0
    /// The caption's margin, plus what the selected tile grows by on each side, so its edge lines up with the name.
    static let margin = 56 + ConsoleView.tile * 0.09

    // A plain row moved by an exact offset, not a scroll view: a held controller direction repeats faster than the
    // scroll animation, and scrollTo on a lazy row mid-animation (its off-screen positions only estimated) stopped short
    // of the end, the last game selected off screen.
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: Self.spacing) {
                ForEach(games) { game in
                    Tile(game: game, isSelected: game.id == selection)
                        .onTapGesture(count: 2) {
                            library.selection = game.id
                            library.handle(.confirm)
                        }
                        .onTapGesture { library.selection = game.id }
                }
            }
            .padding(.horizontal, Self.margin)
            .fixedSize()
            .offset(x: offset(width: width))
            .frame(width: width, height: geometry.size.height, alignment: .leading)
            // in place when Console Mode opens; a selection that moves after that slides there
            .onAppear { follow(width: width) }
            .onChange(of: selection) {
                withAnimation(.spring(duration: 0.4, bounce: 0.15)) { follow(width: width) }
            }
            .onChange(of: width) { follow(width: width) }
            .onChange(of: games.count) { follow(width: width) }
        }
        .frame(height: Self.height)
    }

    /// How many tiles fit between the margins.
    private func fits(_ width: Double) -> Int {
        max(1, Int((width - 2 * Self.margin + Self.spacing) / (ConsoleView.tile + Self.spacing)))
    }

    /// Moves the first tile on screen just enough to keep the selection there.
    private func follow(width: Double) {
        guard let index = games.firstIndex(where: { $0.id == selection }), width > 0 else { return }
        let fits = fits(width)
        first = min(max(first, index - fits + 1), index, max(0, games.count - fits))
    }

    /// The row's shift: the first tile on screen at the left margin; at the end of the row, the last tile at the right
    /// one; a row shorter than the screen stays put.
    private func offset(width: Double) -> Double {
        let step = ConsoleView.tile + Self.spacing
        let row = 2 * Self.margin + Double(games.count) * step - Self.spacing
        guard row > width else { return 0 }
        let fits = fits(width)
        if first >= games.count - fits { return width - row }
        return -Double(first) * step
    }

    static let height = ConsoleView.tile * 1.5
}

private struct Tile: View {
    let game: Game
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.white.opacity(0.08))
            .overlay {
                if let url = game.iconURL, let image = IconCache.image(at: url) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                } else {
                    Image(systemName: "gamecontroller").font(.system(size: 64)).foregroundStyle(
                        .white.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28).strokeBorder(
                    .white.opacity(isSelected ? 0.95 : 0), lineWidth: 4)
            }
            .frame(width: ConsoleView.tile, height: ConsoleView.tile)
            // the outline and the scale mark the selection; a white glow read as a lit, foreign band
            .shadow(
                color: .black.opacity(isSelected ? 0.6 : 0.4), radius: isSelected ? 24 : 14,
                y: isSelected ? 14 : 8
            )
            .scaleEffect(isSelected ? 1.18 : 0.88)
            .opacity(isSelected ? 1 : 0.55)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: isSelected)
    }
}

/// The selected game's name, badges and what it is doing, at the foot of the banner.
private struct Caption: View {
    let game: Game
    let job: Job?
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(game.name)
                .font(.system(size: 64, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: 1000, alignment: .leading)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
            HStack(spacing: 10) {
                GameBadge(game: game, job: job).scaleEffect(1.3).padding(.horizontal, 10)
                if let profile = library.profile(game) {
                    switch profile.stage {
                    case .tested, .profiled:
                        Pill(text: "Known game", symbol: "checkmark", color: .green)
                    case .bringUp:
                        Pill(text: "In bring-up", symbol: "hammer.fill", color: .orange)
                    }
                } else if game.titleID != nil {
                    Pill(text: "No profile", symbol: "questionmark", color: .gray)
                }
                let news = library.news(game).count
                if news > 0 {
                    Pill(text: "\(news) new from nxnative", symbol: "sparkles", color: .blue)
                }
                if game.isKept { Pill(text: "Kept", symbol: "lock.fill", color: .orange) }
                if let version = game.version {
                    Text("v\(version)").foregroundStyle(.white.opacity(0.75))
                }
                if let played = game.lastPlayed {
                    Text("Played \(played, format: .relative(presentation: .named))")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .font(.title3)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.2), value: game.id)
    }
}

/// A badge sized for the couch: solid, to read over any banner.
private struct Pill: View {
    let text: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(Capsule().fill(color.opacity(0.9)))
    }
}

/// The footer's left: the build running (a game that needs a rebuild before it plays, or any other), whichever game is
/// selected, so the banner's caption keeps its place. Several builds: the running one, with how many there are.
private struct FooterBuild: View {
    let jobs: [Job]

    static let bar = 520.0

    var body: some View {
        let job = jobs.first
        // the spinner and the title, the bar with its percentage, the stage: the text lines end where the bar does.
        // Drawn without a build too, invisible: its space stays, so the banner and the tiles don't move as builds
        // start and end.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // no spinning while nothing builds: the placeholder only holds the space
                if job != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
                Text(
                    job.map { $0.kind == .play ? "Building \($0.game.name)" : $0.game.name } ?? " "
                )
                .fontWeight(.semibold)
                if jobs.count > 1 {
                    Text("+\(jobs.count - 1) more").foregroundStyle(.white.opacity(0.6))
                        .layoutPriority(1)
                }
            }
            .font(.title3)
            .frame(width: Self.bar, alignment: .leading)
            HStack(spacing: 14) {
                ProgressView(value: job?.progressFraction ?? 0)
                    .tint(.white)
                    .frame(width: Self.bar)
                Text("\(Int(((job?.progressFraction ?? 0) * 100).rounded()))%")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            Text(job?.progressText ?? " ")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: Self.bar, alignment: .leading)
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.white)
        .opacity(job == nil ? 0 : 1)
        .accessibilityHidden(job == nil)
    }
}

/// What the buttons do, with the connected controller's own symbols, or the keys without one.
private struct Hints: View {
    let game: Game?
    let gamepad: Gamepad

    var body: some View {
        HStack(spacing: 32) {
            Spacer()
            hint(gamepad.symbol(for: .left) ?? "arrow.left.arrow.right", "Choose")
            if game != nil {
                hint(gamepad.symbol(for: .confirm) ?? "return", "Play")
            }
            hint(gamepad.symbol(for: .back) ?? "escape", "Exit")
        }
        .font(.title3.weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
    }

    private func hint(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.title2)
            Text(title)
        }
    }
}

/// The toolbar button.
struct ConsoleToggle: View {
    @Environment(Library.self) private var library

    var body: some View {
        Button {
            library.consoleMode.toggle()
        } label: {
            Label("Console Mode", systemImage: "gamecontroller")
        }
        .help("Console Mode: full screen, for a controller (⇧⌘F, or the controller's Menu button)")
    }
}

/// View › Console Mode, ⇧⌘F.
public struct ConsoleMenuItem: View {
    @Environment(Library.self) private var library

    public init() {}

    public var body: some View {
        Button(library.consoleMode ? "Exit Console Mode" : "Console Mode") {
            library.consoleMode.toggle()
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
    }
}
