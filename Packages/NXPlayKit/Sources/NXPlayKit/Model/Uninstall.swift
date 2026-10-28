import AppKit
import Foundation
import Observation

/// NX Play › Uninstall NX Play…: everything NX Play put on this Mac, and only that. Its folder (what Setup installed:
/// nxnative, Python, uv's cache, a staged update), its settings, caches and saved window state, and the app, which goes
/// to the Trash; the Homebrew tools Setup installed only when asked, since other software may use them. Never the
/// games folder (the games, their builds and the Mac saves in them), prod.keys or the save backup repository: those
/// are the player's. A checkout build's .venv and nxnative are the checkout's and stay too.
///
/// The app quits to finish: settings and window state are written as an app quits, so a shell that outlives it
/// removes them, with the folders, once it has exited.
@MainActor @Observable
public final class Uninstaller {
    public struct Item: Identifiable, Sendable {
        public enum Kind: Sendable { case folder, settings, app }
        public let id: String
        public let title: String
        public let detail: String
        public let kind: Kind
        public let url: URL?
        public var size: Int64?
    }

    public enum Phase: Equatable, Sendable {
        case idle, removingTools, finishing
        case failed(String)
    }

    public private(set) var items: [Item] = []
    /// The Brewfile's tools that are installed now (Setup installs them; something else may have, too).
    public private(set) var tools: [String] = []
    public var removeTools = false
    public private(set) var phase: Phase = .idle
    public private(set) var log = LogBuffer()

    let home: URL
    let appHome: URL
    let bundle: URL
    let domain: String

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, appHome: URL = AppHome.folder,
        bundle: URL = Bundle.main.bundleURL,
        domain: String = Bundle.main.bundleIdentifier ?? "com.varyform.nxplay"
    ) {
        self.home = home
        self.appHome = appHome
        self.bundle = bundle
        self.domain = domain
        items = Self.items(home: home, appHome: appHome, bundle: bundle, domain: domain)
    }

    /// What there is to remove, existing items only; sizes come later (measure).
    nonisolated static func items(home: URL, appHome: URL, bundle: URL, domain: String) -> [Item] {
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        let fm = FileManager.default
        var items: [Item] = []
        func folder(_ id: String, _ title: String, _ detail: String, _ url: URL) {
            guard fm.fileExists(atPath: url.path) else { return }
            items.append(Item(id: id, title: title, detail: detail, kind: .folder, url: url))
        }
        folder(
            "home", "NX Play's folder", "nxnative, Python and its packages, a downloaded update",
            appHome)
        folder(
            "caches", "Caches", "Downloaded artwork and web caches",
            library.appending(path: "Caches/\(domain)"))
        folder(
            "http", "Web storage", "Cookies and caches of GitHub requests",
            library.appending(path: "HTTPStorages/\(domain)"))
        folder(
            "state", "Window state", "Where the windows were",
            library.appending(path: "Saved Application State/\(domain).savedState"))
        items.append(
            Item(
                id: "settings", title: "Settings",
                detail: "The games folder, the paths and every choice in Settings",
                kind: .settings, url: library.appending(path: "Preferences/\(domain).plist")))
        items.append(
            Item(
                id: "app", title: "NX Play", detail: "The app, moved to the Trash", kind: .app,
                url: bundle))
        return items
    }

    /// Sizes of the folders and the app; the Brewfile tools installed now.
    public func measure() async {
        let measured = await Task.detached { [items] in
            items.map { item -> Item in
                var item = item
                item.size = item.url.map(Self.size(of:))
                return item
            }
        }.value
        items = measured
        let listed = await Task.detached { Self.installedTools() }.value
        tools = listed
    }

    nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        guard
            let files = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: Array(keys))
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Homebrew

    /// The Brewfile bundled with the setup: its formulae and casks.
    nonisolated static func brewfileTools(
        _ brewfile: URL? = AppHome.setupProject?.appending(path: "Brewfile")
    )
        -> [(name: String, cask: Bool)]
    {
        guard let brewfile, let text = try? String(contentsOf: brewfile, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").compactMap { line in
            guard let match = line.firstMatch(of: /^(brew|cask)\s+"([^"]+)"/) else { return nil }
            return (String(match.2), match.1 == "cask")
        }
    }

    nonisolated static func installedTools() -> [String] {
        guard let brew = brewPath else { return [] }
        let installed = Set(
            Self.run(brew, ["list", "-1", "--formula"]).output.split(separator: "\n").map(
                String.init)
                + Self.run(brew, ["list", "-1", "--cask"]).output.split(separator: "\n").map(
                    String.init))
        return brewfileTools().map(\.name).filter(installed.contains)
    }

    nonisolated static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(
            where: FileManager.default.isExecutableFile)
    }

    // MARK: - Uninstall

    /// Removes the tools when asked, moves the app to the Trash, and quits; the shell started here removes the rest
    /// once NX Play has exited.
    public func uninstall(environment: [String: String]) async {
        guard phase != .removingTools, phase != .finishing else { return }
        phase = .idle
        log = LogBuffer()
        if removeTools, !tools.isEmpty, let brew = Self.brewPath {
            phase = .removingTools
            let casks = Set(Self.brewfileTools().filter(\.cask).map(\.name))
            let formulae = tools.filter { !casks.contains($0) }
            let caskList = tools.filter(casks.contains)
            for (kind, names) in [("--formula", formulae), ("--cask", caskList)]
            where !names.isEmpty {
                log.append(["$ brew uninstall \(kind) \(names.joined(separator: " "))"])
                let result = await Task.detached {
                    Self.run(brew, ["uninstall", kind] + names, environment: environment)
                }.value
                log.append(result.output.split(separator: "\n").map(String.init))
                if result.code != 0 {
                    phase = .failed(
                        "Homebrew couldn't remove every tool. NX Play is still installed; see the details."
                    )
                    return
                }
            }
        }
        phase = .finishing
        let folders = items.filter { $0.kind == .folder }.compactMap(\.url)
        Self.cleanUp(afterPID: getpid(), folders: folders, domain: domain)
        do {
            try FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        } catch {
            log.append([
                "The app couldn't go to the Trash (\(error.localizedDescription)): drag it there yourself."
            ])
        }
        NSApp?.terminate(nil)
    }

    /// Once the process has exited: the folders go, and so do the settings (through cfprefsd, which caches them).
    nonisolated static func cleanUp(afterPID pid: Int32, folders: [URL], domain: String) {
        let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            domain="$1"; shift
            for folder in "$@"; do rm -rf "$folder"; done
            /usr/bin/defaults delete "$domain" 2>/dev/null
            rm -f "$HOME/Library/Preferences/$domain.plist"
            exit 0
            """
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script, "cleanup", domain] + folders.map(\.path)
        try? process.run()
    }

    nonisolated static func run(
        _ tool: String, _ arguments: [String], environment: [String: String]? = nil
    )
        -> (code: Int32, output: String)
    {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
