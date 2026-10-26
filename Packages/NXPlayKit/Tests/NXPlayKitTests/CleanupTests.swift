import Foundation
import Testing

@testable import NXPlayKit

@MainActor @Suite struct CleanupTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-cleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        // ready: built for the Mac; its NSZ was converted into the build's nsp/
        try write("Ready/Ready [0100000000010000][v0].nsz", size: 3000)
        try write("Ready/Ready.ipa", size: 500)
        try write("Ready/0100000000010000_build/extract/v0/icon.jpg")
        try write("Ready/0100000000010000_build/start_mac.sh")
        try write("Ready/0100000000010000_build/tools/dmhost", executable: true)
        try write("Ready/0100000000010000_build/nsp/Ready [0100000000010000][v0].nsp", size: 4000)
        // extracted, never built for the Mac
        try write("Extracted/Extracted.XCI", size: 2000)
        try write("Extracted/0100000000020000_build/extract/v0/icon.jpg")
        // only the packages
        try write("Fresh/Fresh.nsp", size: 1000)
        try write("Fresh/Fresh.ipa", size: 100)
    }

    private var games: [Game] { GameScanner.scan(root: root) }

    @Test func gameFilesOnlyGoOnceAGameIsBuiltForTheMac() throws {
        let groups = CleanupScanner.groups(.gameFiles, games: games)

        #expect(groups.map(\.game.folder.lastPathComponent) == ["Extracted", "Fresh", "Ready"])
        #expect(groups.map { $0.blocked == nil } == [false, false, true])
        let ready = try #require(groups.last)
        #expect(ready.files.map(\.role) == [.original, .converted])
        #expect(ready.files.map(\.url.pathExtension) == ["nsz", "nsp"])
        #expect(ready.size >= 7000)
        #expect(groups[0].files.map(\.url.lastPathComponent) == ["Extracted.XCI"])  // any case of the extension
    }

    @Test func ipasCanAlwaysGoUnlessTheGameIsBusy() {
        let games = self.games
        let fresh = games.first { $0.folder.lastPathComponent == "Fresh" }!
        let groups = CleanupScanner.groups(.ipas, games: games, busy: [fresh.id])

        #expect(groups.map(\.game.folder.lastPathComponent) == ["Fresh", "Ready"])
        #expect(groups.map { $0.blocked == nil } == [false, true])
        #expect(groups.flatMap(\.files).allSatisfy { $0.role == .ipa })
    }

    @Test func deletesOnlyTheConfirmedSelectionOfAllowedGames() async throws {
        let cleanup = Cleanup(kind: .gameFiles)
        cleanup.scan(games: games, busy: [])
        let ready = try #require(cleanup.groups.first { $0.blocked == nil })
        let blocked = try #require(cleanup.groups.first { $0.blocked != nil })

        cleanup.toggle(blocked)
        #expect(cleanup.selection.isEmpty)  // a blocked game's files cannot be picked
        cleanup.toggle(ready)
        #expect(cleanup.isSelected(ready) == true)
        cleanup.toggle(ready.files[1])
        #expect(cleanup.isSelected(ready) == nil)  // partly

        #expect(!cleanup.canDelete)  // not confirmed
        cleanup.confirmation = "Yes, I’m  sure!"
        #expect(cleanup.canDelete)

        await cleanup.delete()

        #expect(cleanup.phase == .done(count: 1, size: ready.files[0].size))
        #expect(!FileManager.default.fileExists(atPath: ready.files[0].url.path))
        #expect(FileManager.default.fileExists(atPath: ready.files[1].url.path))
        #expect(FileManager.default.fileExists(atPath: blocked.files[0].url.path))
        #expect(cleanup.selection.isEmpty && cleanup.confirmation.isEmpty)

        // the game keeps playing its build without the packages
        let after = GameScanner.game(at: ready.game.folder)
        #expect(after?.state == .ready)
        #expect(after?.hasPackages == false)
    }

    @Test func aRescanDropsSelectionsThatBecameBlocked() {
        let cleanup = Cleanup(kind: .ipas)
        cleanup.scan(games: games, busy: [])
        cleanup.groups.forEach(cleanup.toggle)
        #expect(cleanup.selection.count == 2)

        let fresh = games.first { $0.folder.lastPathComponent == "Fresh" }!
        cleanup.scan(games: games, busy: [fresh.id])
        #expect(cleanup.selection.map(\.lastPathComponent) == ["Ready.ipa"])
    }

    @Test func confirmationIgnoresCasePunctuationAndSpacing() {
        for text in ["yes, I'm sure", "YES IM SURE", " yes  i’m sure. "] {
            #expect(Cleanup.normalized(text) == Cleanup.normalized(Cleanup.phrase), "\(text)")
        }
        for text in ["", "yes", "I'm sure", "yes I am sure"] {
            #expect(Cleanup.normalized(text) != Cleanup.normalized(Cleanup.phrase), "\(text)")
        }
    }

    private func write(_ path: String, size: Int = 1, executable: Bool = false) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: size).write(to: url)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}
