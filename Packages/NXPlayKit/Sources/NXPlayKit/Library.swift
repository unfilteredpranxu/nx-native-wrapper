import AppKit
import Foundation
import Observation

/// The app's state: the games folder, its games, and the nxplay jobs. Extractions run one at a time
/// (each is a full build); plays start at once.
@MainActor @Observable
public final class Library {
    enum Keys {
        static let root = "gamesRoot"
        static let nxnative = "nxnativePath"
        static let keys = "keysPath"
        static let metalHUD = "metalHUD"
        static let language = "language"
    }

    public var root: URL? {
        didSet {
            defaults.set(root?.path, forKey: Keys.root)
            selection = nil
            refresh()
        }
    }
    public var nxnativePath: String { didSet { defaults.set(nxnativePath, forKey: Keys.nxnative) } }
    public var keysPath: String { didSet { defaults.set(keysPath, forKey: Keys.keys) } }
    /// Play with Apple's Metal performance HUD (nxplay --fps).
    public var metalHUD: Bool { didSet { defaults.set(metalHUD, forKey: Keys.metalHUD) } }
    /// Preferred game language (a DM_LANG code); empty keeps each game's build language.
    public var language: String { didSet { defaults.set(language, forKey: Keys.language) } }

    public private(set) var games: [Game] = []
    public private(set) var jobs: [Game.ID: Job] = [:]
    public var selection: Game.ID?
    public var problem: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        root = defaults.string(forKey: Keys.root).map {
            URL(filePath: $0, directoryHint: .isDirectory)
        }
        nxnativePath = defaults.string(forKey: Keys.nxnative) ?? Self.defaultNXNative
        keysPath = defaults.string(forKey: Keys.keys) ?? NSHomeDirectory() + "/.switch/prod.keys"
        metalHUD = defaults.bool(forKey: Keys.metalHUD)
        language = defaults.string(forKey: Keys.language) ?? ""
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
        refresh()
    }

    // MARK: - Games

    public func refresh() {
        games = root.map(GameScanner.scan(root:)) ?? []
    }

    public func chooseRoot() {
        if let url = PathPicker.choose(directory: true, startingAt: root?.path) { root = url }
    }

    public var selectedGame: Game? {
        games.first { $0.id == selection } ?? selection.flatMap { jobs[$0]?.game }
    }

    public var extractableGames: [Game] {
        games.filter { $0.canExtract && !isBusy($0) }
    }

    public func job(for game: Game) -> Job? { jobs[game.id] }

    public func isBusy(_ game: Game) -> Bool { jobs[game.id]?.status.isActive == true }

    // MARK: - Jobs

    public func play(_ game: Game) { run(.play, game) }
    public func extract(_ game: Game) { run(.extract, game) }
    public func rebuild(_ game: Game) { run(.rebuild, game) }
    public func buildIPA(_ game: Game) { run(.ipa, game) }

    public func extractAll() {
        for game in extractableGames { run(.extract, game, select: false) }
    }

    public func primaryAction(for game: Game) {
        game.isExtracted ? play(game) : extract(game)
    }

    private func run(_ kind: Job.Kind, _ game: Game, select: Bool = true) {
        guard !isBusy(game), let command = command(kind, game) else { return }
        let job = Job(kind: kind, game: game, command: command)
        job.onFinish = { [weak self] job in
            guard let self else { return }
            refresh()
            if job.kind == .ipa, job.status == .succeeded,
                let ipa = games.first(where: { $0.id == job.game.id })?.ipaURL
            {
                NSWorkspace.shared.activateFileViewerSelecting([ipa])
            }
            startNextExtraction()
        }
        jobs[game.id] = job
        if select { selection = game.id }
        if kind == .play {
            job.start()
        } else {
            queue.append(job)
            startNextExtraction()
        }
    }

    private func startNextExtraction() {
        queue.removeAll { $0.status != .queued }
        guard !jobs.values.contains(where: { $0.kind != .play && $0.status == .running }),
            let next = queue.first
        else { return }
        queue.removeFirst()
        next.start()
    }

    private func stopAll() {
        queue.removeAll()
        jobs.values.forEach { $0.terminate() }
    }

    private func command(_ kind: Job.Kind, _ game: Game) -> NXPlayCommand? {
        let fm = FileManager.default
        let repo = (nxnativePath as NSString).expandingTildeInPath
        let keys = (keysPath as NSString).expandingTildeInPath
        guard let script = Self.script else {
            problem = "The nxplay script is missing from the app bundle."
            return nil
        }
        guard fm.fileExists(atPath: repo + "/scripts/build_ipa_from_nsp.py") else {
            problem = "No nxnative checkout at \(repo). Set its folder in Settings."
            return nil
        }
        // playing a ready game only needs the keys when nxnative changed and it rebuilds; nxplay says so then
        guard (kind == .play && game.state == .ready) || fm.fileExists(atPath: keys) else {
            problem = "No prod.keys at \(keys). Set the file in Settings."
            return nil
        }
        var arguments: [String] =
            switch kind {
            case .extract: ["--build-only"]
            case .rebuild: ["--rebuild", "--build-only"]
            case .ipa:
                ["--ipa"] + (GameLanguage.choose(language, for: game).map { ["--lang", $0] } ?? [])
            case .play:
                (metalHUD ? ["--fps"] : [])
                    + (GameLanguage.choose(language, for: game).map { ["--lang", $0] } ?? [])
            }
        arguments.append(game.folder.path)
        return NXPlayCommand(
            script: script, arguments: arguments,
            environment: NXPlayCommand.environment(nxnative: repo, keys: keys))
    }

    // MARK: - Locations

    /// This repository, baked into Info.plist at build time (NXSourceRoot = $(SRCROOT)).
    static var sourceRoot: URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "NXSourceRoot") as? String,
            !path.isEmpty, !path.contains("$(")
        else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// nxplay looks for nxnative beside this repository; so does the app.
    static var defaultNXNative: String {
        sourceRoot?.deletingLastPathComponent().appending(path: "nxnative").path
            ?? NSHomeDirectory() + "/projects/nxnative"
    }

    static var script: URL? {
        Bundle.main.url(forResource: "nxplay", withExtension: nil)
            ?? sourceRoot?.appending(path: "nxplay")
    }
}
