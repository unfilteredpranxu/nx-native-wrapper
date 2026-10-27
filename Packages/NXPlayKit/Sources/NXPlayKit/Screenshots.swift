#if DEBUG
    import AppKit
    import Foundation

    /// The README screenshots (bin/screenshots). A Debug build launched with
    /// `-NXPlayScreenshot <scene> -NXPlayScreenshotRoot <games folder> -NXPlayScreenshotReady <file>` opens one scene
    /// with the real games of that folder (their names and icons) and sample data for everything personal: paths
    /// under ~, an example Apple team and devices, a scripted build log, sample saves. It then sizes the window and
    /// writes its window number to the ready file for `screencapture -l`. Nothing runs: no nxplay, no devicectl,
    /// no Xcode accounts, and the settings go to a throwaway defaults suite.
    enum ScreenshotScene: String, CaseIterable {
        case library
        case list
        case console
        case freeUpSpace = "free-up-space"
        case settings
        case transferSaves = "transfer-saves"
    }

    @MainActor
    struct Screenshots {
        let scene: ScreenshotScene
        let root: URL
        let ready: URL

        static let windowSize = NSSize(width: 1040, height: 780)
        static let team = AppleTeam(id: "ABCDE12345", name: "Example Team", isFree: false)
        static let devices = [
            Device(
                id: "00008000-0000000000000001", name: "iPhone", model: "iPhone 17 Pro",
                osVersion: "27.0"),
            Device(
                id: "00008000-0000000000000002", name: "iPad Pro 13″",
                model: "iPad Pro 13-inch (M5)", osVersion: "27.0"),
        ]

        static func fromArguments(_ defaults: UserDefaults = .standard) -> Screenshots? {
            guard let name = defaults.string(forKey: "NXPlayScreenshot"),
                let root = defaults.string(forKey: "NXPlayScreenshotRoot"),
                let ready = defaults.string(forKey: "NXPlayScreenshotReady")
            else { return nil }
            guard let scene = ScreenshotScene(rawValue: name) else {
                fatalError(
                    "NXPlayScreenshot: no scene \(name); one of \(ScreenshotScene.allCases.map(\.rawValue))"
                )
            }
            return Screenshots(
                scene: scene, root: URL(filePath: root, directoryHint: .isDirectory),
                ready: URL(filePath: ready))
        }

        @MainActor func makeLibrary() -> Library {
            let suite = "com.varyform.nxplay.screenshots"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let library = Library(defaults: defaults, isScreenshot: true)
            library.nxnativePath = Self.tilde(Library.defaultNXNative)
            library.keysPath = "~/.switch/prod.keys"
            library.teams = [Self.team]
            library.devices = Self.devices
            library.root = root
            library.screenshotScene = scene
            library.allowOtherMetal = true
            library.showsLog = scene != .list

            // the game the scene is about: one built for the Mac, with its icon, else any extracted one
            let extracted = library.games.filter(\.isExtracted)
            guard
                let game = extracted.first(where: { $0.state == .ready && $0.iconURL != nil })
                    ?? extracted.first
            else {
                report("error: no extracted game in \(root.path)")
                return library
            }
            library.selection = game.id
            switch scene {
            case .library:
                library.jobs[game.id] = job(for: game, finished: false)
            case .list:
                library.viewStyle = .list
                library.jobs[game.id] = job(for: game, finished: false)
            case .console:
                library.gamepad.sample = ("Pro Controller", 0.8)
                // the middle of the carousel, so games show on both sides
                library.selection = extracted[extracted.count / 2].id
                library.consoleMode = true
            case .freeUpSpace, .settings:
                break  // RootView opens their windows
            case .transferSaves:
                library.jobs[game.id] = job(for: game, finished: true)
                library.transfer = transfer(for: game)
            }
            Task { @MainActor in await present(library) }
            return library
        }

        // MARK: - Sample data

        private func job(for game: Game, finished: Bool) -> Job {
            let command = NXPlayCommand(
                script: URL(filePath: "/usr/bin/true"),
                arguments: ["--rebuild", "--build-only", Self.tilde(game.folder.path)],
                environment: [:])
            let job = Job(kind: .rebuild, game: game, command: command)
            job.showScreenshot(
                buildLog(game, finished: finished), status: finished ? .succeeded : .running)
            return job
        }

        /// What `nxplay --rebuild` prints after a pull, in build_ipa_from_nsp.py's own format (--progress lines).
        private func buildLog(_ game: Game, finished: Bool) -> [String] {
            let titleID = game.titleID ?? "0100000000000000"
            let work = Self.tilde(game.buildFolder?.path ?? game.folder.path + "/\(titleID)_build")
            let version =
                game.buildFolder.flatMap {
                    GameScanner.extractVersions(in: $0).first?.lastPathComponent
                } ?? "v0"
            let yellow = "\u{1B}[33m"
            let dim = "\u{1B}[2m"
            let reset = "\u{1B}[m"
            func t(_ s: Int) -> String { String(format: "[21:14:%02d]", s) }
            var lines = [
                "nxnative updated: 2 new commits, rebuilding",
                "  \(yellow)4c1d2e9\(reset) Match verified game patches across compatible updates \(dim)(nxnative, 2 hours ago)\(reset)",
                "  \(yellow)9b70f3a\(reset) Guard Metal image atomics and reject unsupported bindings \(dim)(nxnative, 3 hours ago)\(reset)",
                "\(t(17)) game profile: \(titleID)",
                "\(t(17)) Mac-only build for development: the Mac shaders and the Mac host, no iOS shaders, Xcode project or IPA",
                "\(t(17)) work folder (extracted game files in extract/, kept for the next build): \(work)",
                "\(t(18)) base: \(game.name) [\(titleID)][v0].nsp",
                "\(t(18)) [1/6] build nx_extract …",
                "\(t(18)) ✓ [1/6] build nx_extract (0:00)",
                "\(t(18)) [2/6] extract \(version) …",
                "\(t(18)) reusing the extracted \(version): \(work)/extract/\(version)",
                "\(t(18)) ✓ [2/6] extract \(version) (0:00): reused",
                "\(t(18)) game language: en-US (American English)",
                "\(t(18)) [3/6] rewrite · checking the inputs …",
                "\(t(21)) ✓ [3/6] rewrite (0:03): main, sdk",
                "\(t(21)) [4/6] shader split · checking the inputs …",
                "\(t(21)) ✓ [4/6] shader split (0:00): 46 shaders, reused (inputs unchanged)",
                "\(t(21)) [5/6] Mac shaders · checking the inputs …",
                "\(t(22)) ✓ [5/6] Mac shaders (0:01): 46 of 46 shaders ready, reused (inputs unchanged)",
                "\(t(22)) [6/6] Mac host · building …",
                "\(t(52)) [6/6] Mac host · building: 64%, 0:30 · ETA 0:17",
            ]
            if finished {
                lines += [
                    "\(t(59)) ✓ [6/6] Mac host (0:37): \(work)/tools/dmhost",
                    "\(t(59)) done: the game runs on the Mac with this command (its save in \(work)/run/save, kept from run to run):",
                    "saved: \(work)/start_mac.sh",
                    "nxplay: done",
                ]
            }
            return lines
        }

        /// A save newer on this Mac than on the iPad, the case Transfer Saves warns about.
        @MainActor private func transfer(for game: Game) -> SaveTransfer {
            let titleID = (game.titleID ?? "").lowercased()
            let transfer = SaveTransfer(game: game, preferredBundleID: nil)
            let app = DeviceApp(
                bundleID: "org.nxnative.abcde12345.\(titleID)", name: game.name,
                version: game.version ?? "1.0")
            let now = Date.now
            transfer.device = Self.devices[1]
            transfer.apps = [app]
            transfer.app = app
            let options = SaveFile(
                path: "options.dat", size: 2_048, modified: now.addingTimeInterval(-3 * 86400))
            transfer.macFiles = [
                SaveFile(
                    path: "save.dat", size: 479_360,
                    modified: now.addingTimeInterval(-2 * 3600 - 300)),
                options,
            ]
            transfer.deviceFiles = [
                SaveFile(
                    path: "save.dat", size: 471_040,
                    modified: now.addingTimeInterval(-6 * 3600 - 1260)),
                options,
            ]
            transfer.phase = .idle
            return transfer
        }

        // MARK: - Capture

        /// Dark, frontmost, at a fixed size; then the window number of the scene's window.
        @MainActor private func present(_ library: Library) async {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            try? await Task.sleep(for: .seconds(1))
            NSApp.activate()
            let windows = NSApp.windows.filter {
                $0.isVisible && $0.sheetParent == nil && $0.level == .normal
            }
            let main = windows.max {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            }
            let ownWindow = scene == .settings || scene == .freeUpSpace
            if let main, !ownWindow {
                main.setContentSize(Self.windowSize)
                main.center()
            }
            // layout, icons, the sheet's animation; full screen and Free Up Space's measuring take longer
            try? await Task.sleep(
                for: .seconds(scene == .console || scene == .freeUpSpace ? 4 : 1.5))
            let target =
                ownWindow
                ? NSApp.windows.first {
                    $0.isVisible && $0 !== main && $0.sheetParent == nil && $0.level == .normal
                }
                : main
            target?.makeKeyAndOrderFront(nil)
            target?.makeFirstResponder(nil)  // no focused, selected text field
            try? await Task.sleep(for: .seconds(0.5))
            report(
                target.map { String($0.windowNumber) } ?? "error: no window for \(scene.rawValue)")
        }

        private func report(_ text: String) {
            try? (text + "\n").write(to: ready, atomically: true, encoding: .utf8)
        }

        static func tilde(_ path: String) -> String {
            (path as NSString).abbreviatingWithTildeInPath
        }
    }
#endif
