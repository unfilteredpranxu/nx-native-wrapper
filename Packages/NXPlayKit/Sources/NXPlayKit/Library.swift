import AppKit
import Foundation
import Observation
import SwiftUI

extension View {
    /// Puts the library in the environment of the app's scenes. Done inside this module: SourceKit-LSP's
    /// indexing build of NXPlayKit leaves out the conformance @Observable generates, so `.environment(library)`
    /// in the app target showed a false "requires that 'Library' conform to 'Observable'" in editors.
    public func library(_ library: Library) -> some View {
        environment(library)
    }
}

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
        static let showsLog = "showsLog"
        static let logHeight = "logHeight"
        static let viewStyle = "viewStyle"
        static let fullScreenGames = "fullScreenGames"
        static let saveBackup = "saveBackupRepository"
        static let allowOtherMetal = "allowOtherMetal"
    }

    /// The games as cards with their icons, or as a sortable list.
    public enum ViewStyle: String, CaseIterable, Sendable {
        case grid, list
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
    /// A clone of the player's private repository that saves are backed up to while games play; empty for none.
    public var saveBackupPath: String {
        didSet { defaults.set(saveBackupPath, forKey: Keys.saveBackup) }
    }
    /// Play with Apple's Metal performance HUD (nxplay --fps).
    public var metalHUD: Bool { didSet { defaults.set(metalHUD, forKey: Keys.metalHUD) } }
    /// Start games in full screen (nxplay --fullscreen); always from Console Mode.
    public var fullScreenGames: Bool {
        didSet { defaults.set(fullScreenGames, forKey: Keys.fullScreenGames) }
    }
    /// Build shaders with this Mac's Metal compiler when nxnative tested another (its --allow-other-metal):
    /// off by default, as nxnative's; a newer Xcode than nxnative's tested one stops every build otherwise.
    public var allowOtherMetal: Bool {
        didSet { defaults.set(allowOtherMetal, forKey: Keys.allowOtherMetal) }
    }
    /// Preferred game language (a DM_LANG code); empty keeps each game's build language.
    public var language: String { didSet { defaults.set(language, forKey: Keys.language) } }
    /// The Apple team that signs device installs; empty picks the first paid one Xcode knows.
    public var teamID: String { didSet { defaults.set(teamID, forKey: Keys.team) } }
    /// The log panel under the games; it opens by itself when a job fails.
    public var showsLog: Bool { didSet { defaults.set(showsLog, forKey: Keys.showsLog) } }
    /// The log panel's height in points, as last dragged.
    public var logHeight: Double { didSet { defaults.set(logHeight, forKey: Keys.logHeight) } }
    public var viewStyle: ViewStyle {
        didSet { defaults.set(viewStyle.rawValue, forKey: Keys.viewStyle) }
    }

    public internal(set) var teams: [AppleTeam] = []
    public internal(set) var devices: [Device] = []
    public private(set) var isLoadingDevices = false

    public private(set) var games: [Game] = []
    public internal(set) var jobs: [Game.ID: Job] = [:]
    public var selection: Game.ID?
    public var problem: String?
    /// The save transfer sheet, when open.
    public var transfer: SaveTransfer?
    /// Console Mode: the window full screen, the games as a carousel for the couch and a controller.
    public var consoleMode = false {
        // the carousel starts at the game played last
        didSet { if consoleMode, !oldValue { selection = navigableGames.first?.id } }
    }
    /// The controller as a remote: moves the selection, plays, toggles Console Mode.
    public let gamepad = Gamepad()
    /// Updates from GitHub releases (a released app only).
    public let updater = AppUpdater()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let saveBackup = SaveBackup()
    @ObservationIgnored private var installObservers: [any NSObjectProtocol] = []
    /// bin/install asked NX Play to quit once nothing is running, to replace it (quitWhenIdleNotification).
    public private(set) var quitsWhenIdle = false
    /// File work outside the jobs that quitting would cut short: Free Up Space deleting, a save transfer copying.
    @ObservationIgnored private var tasksInFlight = 0
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
        nxnativePath = defaults.string(forKey: Keys.nxnative) ?? AppHome.defaultNXNative
        keysPath = defaults.string(forKey: Keys.keys) ?? NSHomeDirectory() + "/.switch/prod.keys"
        saveBackupPath = defaults.string(forKey: Keys.saveBackup) ?? ""
        metalHUD = defaults.bool(forKey: Keys.metalHUD)
        fullScreenGames = defaults.bool(forKey: Keys.fullScreenGames)
        allowOtherMetal = defaults.bool(forKey: Keys.allowOtherMetal)
        language = defaults.string(forKey: Keys.language) ?? ""
        teamID = defaults.string(forKey: Keys.team) ?? ""
        showsLog = defaults.object(forKey: Keys.showsLog) as? Bool ?? true
        logHeight = defaults.object(forKey: Keys.logHeight) as? Double ?? 240
        viewStyle =
            defaults.string(forKey: Keys.viewStyle).flatMap(ViewStyle.init(rawValue:)) ?? .grid
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopAll()
                self?.updater.installOnQuit()
            }
        }
        gamepad.onCommand = { [weak self] in self?.handle($0) }
        if !isScreenshot {
            observeInstall()
            updater.start()
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

    /// nxnative or the Python environment the builds run with is missing: the app asks to run Setup.
    public private(set) var needsSetup = false

    /// What bin/setup needs to know, run from the app: our folder, the bundled project files, the paths in Settings,
    /// and a password prompt for the installers that need an administrator. A developer build keeps the checkout's
    /// layout (no NXPLAY_HOME: bin/setup as a developer runs it, without building the app).
    func setupEnvironment() -> [String: String] {
        var env = NXPlayCommand.environment(
            nxnative: (nxnativePath as NSString).expandingTildeInPath,
            keys: (keysPath as NSString).expandingTildeInPath, venv: AppHome.venv.path)
        // the bundled setup reads the files bundled beside it, for a checkout build too
        if let project = AppHome.setupProject { env["NXPLAY_PROJECT"] = project.path }
        if AppHome.sourceRoot == nil { env["NXPLAY_HOME"] = AppHome.folder.path }
        if let askpass = AppHome.setupProject?.appending(path: "askpass") {
            env["SUDO_ASKPASS"] = askpass.path
        }
        return env
    }

    public func refresh() {
        let fm = FileManager.default
        let repo = (nxnativePath as NSString).expandingTildeInPath
        needsSetup =
            !isScreenshot
            && (!fm.fileExists(atPath: repo + "/scripts/build_ipa_from_nsp.py")
                || !fm.isExecutableFile(atPath: AppHome.venv.appending(path: "bin/python3").path))
        games = root.map(GameScanner.scan(root:)) ?? []
        watchCopies()
    }

    @ObservationIgnored private var copyWatch: Task<Void, Never>?

    /// While Finder is copying a game file in, look again every few seconds, so the game turns extractable by
    /// itself when the copy completes.
    private func watchCopies() {
        guard games.contains(where: \.isCopying), copyWatch == nil else { return }
        copyWatch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            copyWatch = nil
            refresh()
        }
    }

    /// Where saves go, when Settings names a folder.
    var saveBackupRepository: URL? {
        saveBackupPath.isEmpty
            ? nil
            : URL(
                filePath: (saveBackupPath as NSString).expandingTildeInPath,
                directoryHint: .isDirectory)
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
    public func makeMacApp(_ game: Game) { run(.macApp, game) }
    public func install(_ game: Game, on device: Device) { run(.install(device), game) }

    /// Keep This Build on or off: nxplay reads the keep file before it rebuilds after an nxnative update.
    public func setKept(_ kept: Bool, _ game: Game) {
        guard let file = game.keepFile else { return }
        do {
            if kept {
                try Data(
                    "Kept by NX Play: nxnative updates don't rebuild this build; Rebuild does.\n"
                        .utf8
                )
                .write(to: file)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            problem = "Could not change Keep This Build: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Opens the save transfer for a game; the copy NX Play installs is preferred when a device has several.
    public func transferSaves(_ game: Game) {
        refreshDevices()
        var bundleID: String?
        if let team, let titleID = game.titleID {
            bundleID = Self.bundleID(titleID: titleID, team: team)
        }
        transfer = SaveTransfer(game: game, preferredBundleID: bundleID)
    }

    // MARK: - Navigation (controller, Console Mode keys)

    /// The games in the order the grid shows them, extracted first, then the rest; Console Mode only has the
    /// extracted ones, the games it can play, the last played first and the never played after them by name.
    public var navigableGames: [Game] {
        let extracted = games.filter(\.isExtracted)
        guard consoleMode else { return extracted + games.filter { !$0.isExtracted } }
        return extracted.filter { $0.lastPlayed != nil }.sorted { $0.lastPlayed! > $1.lastPlayed! }
            + extracted.filter { $0.lastPlayed == nil }
    }

    /// One step through the games; with nothing selected, the first one.
    func move(_ step: Int) {
        let games = navigableGames
        guard !games.isEmpty else { return }
        guard let index = games.firstIndex(where: { $0.id == selection }) else {
            selection = games.first?.id
            return
        }
        selection = games[min(max(index + step, 0), games.count - 1)].id
    }

    func handle(_ command: Gamepad.Command) {
        switch command {
        case .left, .up: move(-1)
        case .right, .down: move(1)
        case .confirm:
            // Play, or Extract when it can; nothing while the game is busy or still copying
            guard let game = selectedGame, !isBusy(game), game.isExtracted || game.canExtract else {
                return
            }
            primaryAction(for: game)
        case .back:
            if transfer != nil { transfer = nil } else if consoleMode { consoleMode = false }
        case .menu: consoleMode.toggle()
        }
    }

    public func extractAll() {
        for game in extractableGames { run(.extract, game, select: false) }
    }

    public func primaryAction(for game: Game) {
        game.isExtracted ? play(game) : extract(game)
    }

    private func run(_ kind: Job.Kind, _ game: Game, select: Bool = true) {
        guard !isBusy(game) else { return }
        if game.isKept, kind.rewritesTheMacBuild {
            problem = Self.keptBuildProblem
            return
        }
        guard let command = command(kind, game) else { return }
        let job = Job(kind: kind, game: game, command: command)
        job.onFinish = { [weak self] job in self?.finished(job) }
        jobs[game.id] = job
        if select { selection = game.id }
        if kind == .play {
            job.start()
            if let repo = saveBackupRepository { saveBackup.watch(job, into: repo) }
        } else {
            queue.append(job)
            startNextExtraction()
        }
    }

    func finished(_ job: Job) {
        refresh()
        // what was made, in Finder
        let made = games.first { $0.id == job.game.id }
        if job.status == .succeeded,
            let file = job.kind == .ipa ? made?.ipaURL : job.kind == .macApp ? made?.macAppURL : nil
        {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
        if case .install = job.kind { refreshDevices() }
        // a failure's reason is in its output: show it
        if case .failed = job.status {
            showsLog = true
            selection = job.game.id
            // in the background: a badge on the Dock icon until NX Play is opened again
            if !isScreenshot, NSApp?.isActive == false { NSApp.dockTile.badgeLabel = "!" }
            if !allowOtherMetal,
                job.log.lines.contains(where: { $0.text.contains(Self.otherMetalMarker) })
            {
                problem = """
                    This Mac's Metal compiler is newer than the one nxnative tested its shaders with, so nxnative \
                    stopped the build. Install the Xcode version it names, or turn on “Allow a Metal compiler \
                    nxnative didn't test” in Settings to build with this one anyway.
                    """
            }
        }
        startNextExtraction()
        quitIfIdle()
    }

    private func startNextExtraction() {
        queue.removeAll { $0.status != .queued }
        guard !jobs.values.contains(where: { $0.kind != .play && $0.status == .running }),
            let next = queue.first
        else { return }
        queue.removeFirst()
        next.start()
    }

    // MARK: - Install (bin/install)

    /// Posted by bin/install: quit as soon as no game, build or file work is running, so the app can be replaced
    /// without cutting anything short. Answered from inside the app, so nothing can start between the check and the quit.
    static let quitWhenIdleNotification = Notification.Name("com.varyform.nxplay.quitWhenIdle")
    /// Posted by bin/install when it is cancelled while waiting.
    static let stayOpenNotification = Notification.Name("com.varyform.nxplay.stayOpen")

    /// Nothing running that quitting would stop: no job (queued or running) and no file work in flight.
    public var isIdle: Bool {
        tasksInFlight == 0 && !jobs.values.contains { $0.status.isActive }
    }

    /// Runs file work that must not be cut short by bin/install's quit.
    public func inFlight(_ work: () async -> Void) async {
        tasksInFlight += 1
        await work()
        tasksInFlight -= 1
        quitIfIdle()
    }

    /// Installs the staged update now: NX Play quits once no game, build or file work runs, and opens again.
    public func restartToUpdate() {
        guard case .ready = updater.state else { return }
        updater.relaunchAfterUpdate()
        requestQuitWhenIdle(true)
    }

    func requestQuitWhenIdle(_ on: Bool) {
        quitsWhenIdle = on
        quitIfIdle()
    }

    private func observeInstall() {
        let center = DistributedNotificationCenter.default()
        installObservers = [
            (Self.quitWhenIdleNotification, true), (Self.stayOpenNotification, false),
        ].map { name, on in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestQuitWhenIdle(on) }
            }
        }
    }

    @ObservationIgnored var terminate: () -> Void = { NSApp.terminate(nil) }

    private func quitIfIdle() {
        guard quitsWhenIdle, isIdle else { return }
        terminate()
    }

    private func stopAll() {
        queue.removeAll()
        jobs.values.forEach { $0.terminate() }
    }

    private func command(_ kind: Job.Kind, _ game: Game) -> NXPlayCommand? {
        let fm = FileManager.default
        let repo = (nxnativePath as NSString).expandingTildeInPath
        let keys = (keysPath as NSString).expandingTildeInPath
        guard let script = AppHome.script else {
            problem = "The nxplay script is missing from the app bundle."
            return nil
        }
        guard fm.fileExists(atPath: repo + "/scripts/build_ipa_from_nsp.py") else {
            problem =
                "No nxnative checkout at \(repo). Open Setup to install it, or set its folder in Settings."
            return nil
        }
        // playing a ready game only needs the keys when nxnative changed and it rebuilds; nxplay says so then
        guard (kind == .play && game.state == .ready) || fm.fileExists(atPath: keys) else {
            problem = "No prod.keys at \(keys). Set the file in Settings."
            return nil
        }
        let lang = GameLanguage.choose(language, for: game).map { ["--lang", $0] } ?? []
        var environment = NXPlayCommand.environment(
            nxnative: repo, keys: keys, venv: AppHome.venv.path)
        var arguments: [String]
        switch kind {
        case .extract: arguments = ["--build-only", game.folder.path]
        case .rebuild: arguments = ["--rebuild", "--build-only", game.folder.path]
        case .ipa: arguments = ["--ipa"] + lang + [game.folder.path]
        case .macApp: arguments = ["--mac-app"] + lang + [game.folder.path]
        case .play:
            arguments =
                (metalHUD ? ["--fps"] : [])
                + (fullScreenGames || consoleMode ? ["--fullscreen"] : [])
                + lang + [game.folder.path]
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
        // an nxplay option, before the game folder (a play can rebuild too)
        if allowOtherMetal { arguments.insert("--allow-other-metal", at: 0) }
        return NXPlayCommand(script: script, arguments: arguments, environment: environment)
    }

    static let keptBuildProblem = """
        This game's build is kept. Building an IPA, a Mac app or installing on a device rewrites files the kept \
        build runs, so turn off Keep This Build first.
        """

    /// build_ipa_from_nsp.py's message when this Mac's Metal compiler isn't the tested one (dmsh_chain.lock).
    static let otherMetalMarker = "Metal compiler is not the one the shaders were tested with"

    /// App IDs are unique across all teams, so nxnative's default org.nxnative.<title ID> may already
    /// belong to someone else: put the team in it. Stable, so a reinstall updates the same app and keeps its saves.
    nonisolated static func bundleID(titleID: String, team: AppleTeam) -> String {
        "org.nxnative.\(team.id.lowercased()).\(titleID.lowercased())"
    }

}
