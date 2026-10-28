import Foundation
import Testing

@testable import NXPlayKit

@Suite struct UninstallTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-uninstall-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func make(_ path: String) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: url.appending(path: "file"))
        return url
    }

    @Test func listsOnlyWhatExists() throws {
        let home = root.appending(path: "home")
        let appHome = try make("home/Library/Application Support/NX Play")
        _ = try make("home/Library/Caches/com.example.nxplay")
        let bundle = try make("Applications/NX Play.app")
        let items = Uninstaller.items(
            home: home, appHome: appHome, bundle: bundle, domain: "com.example.nxplay")
        #expect(items.map(\.id) == ["home", "caches", "settings", "app"])  // no web storage or window state here
        #expect(Uninstaller.size(of: appHome) >= 4096)
    }

    @Test func readsTheBrewfile() throws {
        let brewfile = root.appending(path: "Brewfile")
        try Data(
            """
            # comment
            brew "uv"            # Python
            brew "zstd"
            cask "dotnet-sdk"    # nx_extract

            """.utf8
        ).write(to: brewfile)
        let tools = Uninstaller.brewfileTools(brewfile)
        #expect(tools.map(\.name) == ["uv", "zstd", "dotnet-sdk"])
        #expect(tools.map(\.cask) == [false, false, true])
    }

    @Test func cleansUpOnceTheAppHasQuit() async throws {
        let appHome = try make("NX Play")
        let caches = try make("Caches/x")
        let domain = "nxplay-uninstall-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.set("~/Games", forKey: "gamesRoot")
        defaults.synchronize()
        let app = Process()
        app.executableURL = URL(filePath: "/bin/sleep")
        app.arguments = ["0.5"]
        try app.run()

        Uninstaller.cleanUp(
            afterPID: app.processIdentifier, folders: [appHome, caches], domain: domain)
        try await Task.sleep(for: .milliseconds(200))
        #expect(FileManager.default.fileExists(atPath: appHome.path))  // the app still runs
        for _ in 0..<50 where FileManager.default.fileExists(atPath: appHome.path) {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!FileManager.default.fileExists(atPath: appHome.path))
        #expect(!FileManager.default.fileExists(atPath: caches.path))
        try await Task.sleep(for: .milliseconds(300))
        let plist = FileManager.default.homeDirectoryForCurrentUser.appending(
            path: "Library/Preferences/\(domain).plist")
        #expect(!FileManager.default.fileExists(atPath: plist.path))
    }
}
