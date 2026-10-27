import AppKit
import SwiftUI

/// Console Mode: the window full screen, the games as a carousel of their artwork over a blurred backdrop of
/// the selected one, its title and state below, the clock and controller up top, button hints at the bottom.
/// A controller, the arrow keys with Return and Esc, or the mouse drive it.
struct ConsoleView: View {
    @Environment(Library.self) private var library
    @FocusState private var focused: Bool

    static let tile = 240.0

    var body: some View {
        let games = library.navigableGames  // the extracted ones
        let selected = games.first { $0.id == library.selection } ?? games.first
        ZStack {
            Backdrop(game: selected)
            VStack(spacing: 0) {
                TopBar(gamepad: library.gamepad)
                    .padding(.horizontal, 56)
                    .padding(.top, 40)
                Spacer(minLength: 20)
                if games.isEmpty {
                    Text("No games ready to play yet").font(.largeTitle.bold()).foregroundStyle(
                        .white.opacity(0.7))
                } else {
                    Carousel(games: games, selection: selected?.id)
                    if let selected { Details(game: selected, job: library.job(for: selected)) }
                }
                Spacer(minLength: 20)
                Hints(game: selected, gamepad: library.gamepad)
                    .padding(.horizontal, 56)
                    .padding(.bottom, 40)
            }
        }
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

/// The selected game's artwork, blurred over the whole screen, cross-fading as the selection moves.
private struct Backdrop: View {
    let game: Game?

    var body: some View {
        // the artwork as an overlay of a flexible colour: in a ZStack, scaledToFill sized the whole screen to the
        // square image, pushing the top bar and the hints out of a wide window
        Color.black
            .overlay {
                if let url = game?.iconURL, let image = IconCache.image(at: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 70)
                        .saturation(1.4)
                        .opacity(0.75)
                        .id(url)
                        .transition(.opacity)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.25), .black.opacity(0.55), .black.opacity(0.9)],
                    startPoint: .top, endPoint: .bottom)
            }
            .animation(.easeInOut(duration: 0.45), value: game?.id)
            .clipped()
    }
}

private struct TopBar: View {
    let gamepad: Gamepad

    var body: some View {
        HStack(spacing: 20) {
            Label("NX Play", systemImage: "gamecontroller.fill")
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

/// The games side by side, the selected one larger and glowing, kept in the middle of the screen.
private struct Carousel: View {
    let games: [Game]
    let selection: Game.ID?
    @Environment(Library.self) private var library

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(games) { game in
                            Tile(game: game, isSelected: game.id == selection)
                                .id(game.id)
                                .onTapGesture(count: 2) {
                                    library.selection = game.id
                                    library.handle(.confirm)
                                }
                                .onTapGesture { library.selection = game.id }
                        }
                    }
                    // the first and last tiles can reach the middle too
                    .padding(.horizontal, max(0, (geometry.size.width - ConsoleView.tile) / 2))
                    .frame(height: geometry.size.height)
                }
                .scrollDisabled(true)
                .scrollClipDisabled()  // shadows fade out instead of ending at the carousel's edges
                .onChange(of: selection, initial: true) {
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }
        }
        .frame(height: ConsoleView.tile * 1.5)
    }
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

/// The selected game's name, what it is and what it is doing.
private struct Details: View {
    let game: Game
    let job: Job?

    var body: some View {
        VStack(spacing: 10) {
            Text(game.name)
                .font(.system(size: 44, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 12) {
                GameBadge(game: game, job: job).scaleEffect(1.3)
                if let version = game.version {
                    Text("v\(version)").foregroundStyle(.white.opacity(0.7))
                }
                if let played = game.lastPlayed {
                    Text("Played \(played, format: .relative(presentation: .named))")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .font(.title3)
            JobProgress(job: job)
                .frame(width: 380)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: game.id)
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

/// Puts the window into full screen for Console Mode and back out when it ends; leaving full screen any other
/// way (the green button, ⌃⌘F) ends Console Mode.
struct ConsoleWindowController: NSViewRepresentable {
    let consoleMode: Bool
    let exit: () -> Void

    @MainActor final class Coordinator {
        var enteredFullScreen = false
        var observer: (any NSObjectProtocol)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let state = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if state.observer == nil {
                state.observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
                ) { _ in
                    MainActor.assumeIsolated {
                        state.enteredFullScreen = false
                        exit()
                    }
                }
            }
            let isFull = window.styleMask.contains(.fullScreen)
            if consoleMode, !isFull {
                state.enteredFullScreen = true
                window.toggleFullScreen(nil)
            } else if !consoleMode, isFull, state.enteredFullScreen {
                state.enteredFullScreen = false
                window.toggleFullScreen(nil)
            }
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
