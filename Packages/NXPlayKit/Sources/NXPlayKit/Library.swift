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
        static let team = "teamID"
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
    /// The Apple team that signs device installs; empty picks the first paid one Xcode knows.
    public var teamID: String { didSet { defaults.set(teamID, forKey: Keys.team) } }

    public internal(set) var teams: [AppleTeam] = []
    public internal(set) var devices: [Device] = []
    public private(set) var isLoadingDevices = false

    public private(set) var games: [Game] = []
    public internal(set) var jobs: [Game.ID: Job] = [:]
    public var selection: Game.ID?
    public var problem: String?
    /// The save transfer sheet, when open.
    public var transfer: SaveTransfer?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    /// Screenshot mode (Screenshots.swift): sample teams and devices that Xcode and devicectl must not replace.
    @ObservationIgnored let isScreenshot: Bool
    #if DEBUG
        /// The scene screenshot mode shows; RootView opens the Settings window for it.
        var screenshotScene: ScreenshotScene?
    #endif

    /// The library the app starts with: a Debug build launched by bin/screenshots shows sample data instead.
    public static func forLaunch() -> Library {
        #if DEBUG
            if let screenshots = Screenshots.fromArguments() { return screenshots.makeLibrary() }
        #endif
        return Library()
    }

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, isScreenshot: false)
    }

    init(defaults: UserDefaults, isScreenshot: Bool) {
        self.defaults = defaults
        self.isScreenshot = isScreenshot
        root = defaults.string(forKey: Keys.root).map {
            URL(filePath: $0, directoryHint: .isDirectory)
        }
        nxnativePath = defaults.string(forKey: Keys.nxnative) ?? Self.defaultNXNative
        keysPath = defaults.string(forKey: Keys.keys) ?? NSHomeDirectory() + "/.switch/prod.keys"
        metalHUD = defaults.bool(forKey: Keys.metalHUD)
        language = defaults.string(forKey: Keys.language) ?? ""
        teamID = defaults.string(forKey: Keys.team) ?? ""
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
        refresh()
        refreshDevices()
    }

    // MARK: - Devices

    public var team: AppleTeam? {
        teams.first { $0.id == teamID } ?? teams.first { !$0.isFree } ?? teams.first
    }

    /// Xcode's teams and the reachable devices; on launch, on activation and after an install.
    public func refreshDevices() {
        guard !isScreenshot else { return }
        teams = AppleTeam.fromXcode()
        guard !isLoadingDevices else { return }
        isLoadingDevices = true
        Task {
            devices = await Device.load()
            isLoadingDevices = false
        }
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
    public func install(_ game: Game, on device: Device) { run(.install(device), game) }

    /// Opens the save transfer for a game; the copy NX Play installs is preferred when a device has several.
    public func transferSaves(_ game: Game) {
        refreshDevices()
        var bundleID: String?
        if let team, let titleID = game.titleID {
            bundleID = Self.bundleID(titleID: titleID, team: team)
        }
        transfer = SaveTransfer(game: game, preferredBundleID: bundleID)
    }

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
            if case .install = job.kind { refreshDevices() }
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
        let lang = GameLanguage.choose(language, for: game).map { ["--lang", $0] } ?? []
        var environment = NXPlayCommand.environment(
            nxnative: repo, keys: keys, venv: Self.venv?.path)
        var arguments: [String]
        switch kind {
        case .extract: arguments = ["--build-only", game.folder.path]
        case .rebuild: arguments = ["--rebuild", "--build-only", game.folder.path]
        case .ipa: arguments = ["--ipa"] + lang + [game.folder.path]
        case .play: arguments = (metalHUD ? ["--fps"] : []) + lang + [game.folder.path]
        case .install(let device):
            guard let team, let titleID = game.titleID else {
                problem =
                    "No Apple developer team in Xcode. Add your account in Xcode › Settings › Apple Accounts."
                return nil
            }
            arguments =
                ["--device", device.id] + lang + [game.folder.path]
                + [
                    "--team-id", team.id, "--bundle-id",
                    Self.bundleID(titleID: titleID, team: team),
                ]
            // a Personal Team cannot provision the Increased Memory Limit capability: build without it
            if team.isFree { environment["DM_ENTITLEMENTS"] = "" }
        }
        return NXPlayCommand(script: script, arguments: arguments, environment: environment)
    }

    /// App IDs are unique across all teams, so nxnative's default org.nxnative.<title ID> may already
    /// belong to someone else: put the team in it. Stable, so a reinstall updates the same app and keeps its saves.
    nonisolated static func bundleID(titleID: String, team: AppleTeam) -> String {
        "org.nxnative.\(team.id.lowercased()).\(titleID.lowercased())"
    }

    // MARK: - Locations

    /// This repository, baked into Info.plist at build time (NXSourceRoot = $(SRCROOT)).
    static var sourceRoot: URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "NXSourceRoot") as? String,
            !path.isEmpty, !path.contains("$(")
        else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Where nxplay looks too: ./nxnative in this checkout (bin/setup clones it there), else beside it.
    static var defaultNXNative: String {
        guard let sourceRoot else { return NSHomeDirectory() + "/projects/nxnative" }
        let inside = sourceRoot.appending(path: "nxnative")
        return FileManager.default.fileExists(atPath: inside.path)
            ? inside.path : sourceRoot.deletingLastPathComponent().appending(path: "nxnative").path
    }

    /// The checkout's Python environment (bin/setup: uv sync); the bundled nxplay cannot find it by itself.
    static var venv: URL? { sourceRoot?.appending(path: ".venv", directoryHint: .isDirectory) }

    static var script: URL? {
        Bundle.main.url(forResource: "nxplay", withExtension: nil)
            ?? sourceRoot?.appending(path: "nxplay")
    }
}
