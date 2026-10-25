import Foundation
import Testing

@testable import NXPlayKit

@Suite struct GameScannerTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func findsGamesByStateAndSkipsOtherFolders() throws {
        // ready: launcher + executable Mac host, base and update extracted
        let ready = try build(game: "Metroid", titleID: "010093801237C000", versions: [0, 327680])
        try touch(ready.appending(path: "start_mac.sh"))
        try touch(ready.appending(path: "tools/dmhost"), executable: true)
        // extracted, no launcher
        _ = try build(
            game: "Zelda (NSP)", titleID: "01007EF00011E000", versions: [786432], title: nil)
        // only packages
        try touch(root.appending(path: "Wonder/game.NSZ"))
        // nothing of a game
        try touch(root.appending(path: "Music/01. Track.mp3"))
        try touch(root.appending(path: "Music/0100000000000000_notabuild/x"))

        let games = GameScanner.scan(root: root)

        #expect(games.map(\.name) == ["Metroid Dread", "Wonder", "Zelda (NSP)"])
        let metroid = try #require(games.first)
        #expect(metroid.state == .ready)
        #expect(metroid.titleID == "010093801237C000")
        #expect(metroid.version == "2.1.0")
        #expect(metroid.iconURL?.path.hasSuffix("extract/v327680/icon.jpg") == true)
        #expect(games[1].state == .notExtracted)
        #expect(games[1].canExtract)
        #expect(games[2].state == .extracted)
        #expect(games[2].hasPackages == false)
    }

    @Test func aLauncherWithoutTheMacHostIsNotReady() throws {
        let folder = try build(game: "Metroid", titleID: "010093801237C000", versions: [0])
        try touch(folder.appending(path: "start_mac.sh"))
        #expect(GameScanner.scan(root: root).first?.state == .extracted)
    }

    @Test func iconFallsBackToAnOlderVersion() throws {
        let folder = try build(game: "Metroid", titleID: "010093801237C000", versions: [0])
        try FileManager.default.createDirectory(
            at: folder.appending(path: "extract/v65536/RomFS"), withIntermediateDirectories: true)
        #expect(GameScanner.scan(root: root).first?.iconURL?.path.hasSuffix("v0/icon.jpg") == true)
    }

    // MARK: - Fixtures

    private func build(
        game: String, titleID: String, versions: [Int], title: String? = "Metroid Dread"
    ) throws -> URL {
        let folder = root.appending(path: "\(game)/\(titleID)_build", directoryHint: .isDirectory)
        for version in versions {
            let extract = folder.appending(path: "extract/v\(version)")
            try FileManager.default.createDirectory(
                at: extract.appending(path: "RomFS"), withIntermediateDirectories: true)
            try touch(extract.appending(path: "icon.jpg"))
            if let title {
                try NACPTests.nacp(title: title, version: "2.1.0").write(
                    to: extract.appending(path: "control.nacp"))
            }
        }
        return folder
    }

    private func touch(_ url: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}
