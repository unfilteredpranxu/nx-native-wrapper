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
        // only packages, and an IPA built earlier
        try touch(root.appending(path: "Wonder/game.NSZ"))
        try touch(root.appending(path: "Wonder/SMBWMobile.ipa"))
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
        #expect(metroid.ipaURL == nil)
        #expect(games[1].state == .notExtracted)
        #expect(games[1].canExtract)
        #expect(games[1].ipaURL?.lastPathComponent == "SMBWMobile.ipa")
        #expect(games[2].state == .extracted)
        #expect(games[2].hasPackages == false)
    }

    @Test func aFileFinderIsStillCopyingHoldsTheGameBack() throws {
        let nsp = root.appending(path: "Wonder/Wonder [0100000000010000][v0].nsp")
        try touch(nsp)
        // what Finder sets while copying (seen: 1984-01-24 11:00 local), then the source's date once complete
        let copying = ISO8601DateFormatter().date(from: "1984-01-24T08:00:00Z")!
        try FileManager.default.setAttributes([.creationDate: copying], ofItemAtPath: nsp.path)

        let game = try #require(GameScanner.scan(root: root).first)
        #expect(game.isCopying)
        #expect(!game.canExtract && !game.canBuildIPA)
        #expect(CleanupScanner.groups(games: [game]).first?.files.first?.blocked != nil)

        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 1_692_051_683)], ofItemAtPath: nsp.path)
        let done = try #require(GameScanner.scan(root: root).first)
        #expect(!done.isCopying && done.canExtract)
    }

    @Test func aFolderFinderIsStillCopyingHoldsTheGameBack() throws {
        // a dragged game folder: Finder marks the folder, while the file inside has today's date (seen with
        // Streets of Rage 4)
        let folder = root.appending(path: "Streets of Rage 4 [NSP]")
        try touch(folder.appending(path: "Streets of Rage 4 [0100EC9010258000][v0].nsp"))
        let copying = ISO8601DateFormatter().date(from: "1984-01-24T08:00:00Z")!
        try FileManager.default.setAttributes([.creationDate: copying], ofItemAtPath: folder.path)

        #expect(GameScanner.scan(root: root).first?.isCopying == true)

        try FileManager.default.setAttributes([.creationDate: Date.now], ofItemAtPath: folder.path)
        #expect(GameScanner.scan(root: root).first?.isCopying == false)
    }

    @Test func findsTheMacAppNxnativePacked() throws {
        try touch(root.appending(path: "Metroid/Metroid Dread [010093801237C000][v0].nsp"))
        try touch(
            root.appending(path: "Metroid/Metroid Dread.app/Contents/MacOS/dmhost"),
            executable: true)
        try touch(
            root.appending(path: "Metroid/Some Other.app/Contents/MacOS/Some Other"),
            executable: true)

        #expect(
            GameScanner.scan(root: root).first?.macAppURL?.lastPathComponent == "Metroid Dread.app")
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

    @Test func readsTheLastPlayFromTheMarkNxplayLeaves() throws {
        let folder = try build(game: "Metroid", titleID: "010093801237C000", versions: [0])
        #expect(GameScanner.scan(root: root).first?.lastPlayed == nil)

        let mark = folder.appending(path: "run/last_played")
        try touch(mark)
        let played = Date(timeIntervalSince1970: 1_790_000_000)
        try FileManager.default.setAttributes([.modificationDate: played], ofItemAtPath: mark.path)
        #expect(GameScanner.scan(root: root).first?.lastPlayed == played)
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
