import Foundation
import Testing

@testable import NXPlayKit

@MainActor @Suite struct CleanupTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-cleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        // ready: built for the Mac; its NSZ was converted into the build's nsp/; installed on a device once
        try write("Ready/Ready [0100000000010000][v0].nsz", size: 3000)
        try write("Ready/Ready.ipa", size: 500)
        try write("Ready/0100000000010000_build/extract/v0/icon.jpg")
        try write("Ready/0100000000010000_build/start_mac.sh")
        try write("Ready/0100000000010000_build/tools/dmhost", executable: true)
        try write("Ready/0100000000010000_build/nsp/Ready [0100000000010000][v0].nsp", size: 4000)
        try write(
            "Ready/0100000000010000_build/xcode-derived-data/Build/Products/DmIOS.app/romfs/a.bin",
            size: 6000)
        try write(
            "Ready/0100000000010000_build/xcode-derived-data/Build/Products/DmIOS.app/romfs/b.bin",
            size: 2000)
        // extracted, never built for the Mac
        try write("Extracted/Extracted.XCI", size: 2000)
        try write("Extracted/0100000000020000_build/extract/v0/icon.jpg")
        // only the packages
        try write("Fresh/Fresh.nsp", size: 1000)
        try write("Fresh/Fresh.ipa", size: 100)
    }

    private var games: [Game] { GameScanner.scan(root: root) }
    private func game(_ name: String) -> Game {
        games.first { $0.folder.lastPathComponent == name }!
    }

    @Test func listsEveryKindPerGameWithItsOwnRules() throws {
        let groups = CleanupScanner.groups(games: games)
        #expect(groups.map(\.game.folder.lastPathComponent) == ["Extracted", "Fresh", "Ready"])

        let ready = try #require(groups.last)
        #expect(ready.files.map(\.role) == [.original, .converted, .ipa, .xcodeBuild])
        #expect(ready.files.allSatisfy { $0.blocked == nil })
        #expect(try #require(ready.files.last).size >= 8000)  // the whole Xcode build folder

        // a game that isn't built for the Mac keeps its game files, but its IPA can go
        let fresh = groups[1]
        #expect(fresh.files.map(\.role) == [.original, .ipa])
        #expect(fresh.files.map { $0.blocked == nil } == [false, true])
        #expect(groups[0].files.map(\.url.lastPathComponent) == ["Extracted.XCI"])  // any case of the extension
    }

    @Test func aBusyGameKeepsEverything() {
        let groups = CleanupScanner.groups(games: games, busy: [game("Ready").id])
        #expect(groups.last?.files.allSatisfy { $0.blocked != nil } == true)
    }

    @Test func selectsByKindByGameAndByFile() {
        let cleanup = Cleanup()
        cleanup.apply(CleanupScanner.groups(games: games))

        cleanup.toggle(.ipas)
        #expect(cleanup.selectedFiles.map(\.url.lastPathComponent) == ["Fresh.ipa", "Ready.ipa"])
        #expect(cleanup.isSelected(.ipas) == true)

        cleanup.toggle(.gameFiles)  // only the ready game's: the others are blocked
        #expect(
            cleanup.selectedFiles.filter { $0.kind == .gameFiles }.map(\.role) == [
                .original, .converted,
            ])
        #expect(cleanup.isSelected(.gameFiles) == true)

        let ready = cleanup.groups.last!
        #expect(cleanup.isSelected(ready) == nil)  // its Xcode build isn't picked
        cleanup.toggle(ready)
        #expect(cleanup.isSelected(ready) == true && cleanup.isSelected(.xcodeBuilds) == true)
        cleanup.toggle(.ipas)
        #expect(cleanup.isSelected(ready) == nil && cleanup.isSelected(.ipas) == false)
    }

    @Test func deletesOnlyTheConfirmedSelection() async throws {
        let cleanup = Cleanup()
        await cleanup.scan(games: games, busy: [])
        let ready = try #require(cleanup.groups.last)
        let xcode = try #require(ready.files.last)
        let original = ready.files[0]
        cleanup.toggle(xcode)
        cleanup.toggle(original)

        #expect(!cleanup.canDelete)  // not confirmed
        cleanup.confirmation = "Yes, I’m  sure!"
        #expect(cleanup.canDelete)
        await cleanup.delete()

        #expect(cleanup.phase == .done(count: 2, size: xcode.size + original.size))
        #expect(!FileManager.default.fileExists(atPath: xcode.url.path))  // a whole folder
        #expect(!FileManager.default.fileExists(atPath: original.url.path))
        #expect(FileManager.default.fileExists(atPath: ready.files[1].url.path))
        #expect(cleanup.selection.isEmpty && cleanup.confirmation.isEmpty)

        // the game keeps playing its build without its packages
        let after = GameScanner.game(at: ready.game.folder)
        #expect(after?.state == .ready)
        #expect(after?.hasPackages == false)
        // and the rescanned game differs from the old one, so its card redraws without the Xcode badge
        #expect(ready.game.xcodeBuildFolder != nil)
        #expect(after?.xcodeBuildFolder == nil)
        #expect(after != ready.game)
    }

    @Test func aRescanDropsSelectionsThatBecameBlocked() async {
        let cleanup = Cleanup()
        await cleanup.scan(games: games, busy: [])
        cleanup.toggle(.ipas)
        #expect(cleanup.selection.count == 2)

        await cleanup.scan(games: games, busy: [game("Fresh").id])
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
