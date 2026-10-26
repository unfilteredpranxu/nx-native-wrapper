import Foundation
import Observation

/// What Tools › Remove Game Files / Remove IPAs offers to delete, to free disk space.
public enum CleanupKind: String, CaseIterable, Sendable {
    /// A game's NSP / NSZ / XCI / XCZ files, and the NSPs a build converted from NSZ (`<id>_build/nsp`).
    case gameFiles = "game-files"
    case ipas
}

public struct CleanupFile: Identifiable, Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case original
        /// An NSP the build decompressed from an NSZ and keeps for the next build.
        case converted
        case ipa
    }

    public let url: URL
    /// Space on disk (allocated, so a sparse or cloned file counts what it really takes).
    public let size: Int64
    public let role: Role
    public var id: URL { url }
}

/// One game's removable files.
public struct CleanupGroup: Identifiable, Sendable {
    public let game: Game
    public let files: [CleanupFile]
    /// Why its files cannot be removed now; nil when they can.
    public let blocked: String?
    public var id: Game.ID { game.id }
    public var size: Int64 { files.reduce(0) { $0 + $1.size } }
}

public enum CleanupScanner {
    public static func groups(_ kind: CleanupKind, games: [Game], busy: Set<Game.ID> = [])
        -> [CleanupGroup]
    {
        games.compactMap { game in
            let files = files(kind, of: game)
            guard !files.isEmpty else { return nil }
            return CleanupGroup(
                game: game, files: files, blocked: blocked(kind, game, busy: busy.contains(game.id))
            )
        }
    }

    static func files(_ kind: CleanupKind, of game: Game) -> [CleanupFile] {
        func list(_ folder: URL?, _ extensions: Set<String>, _ role: CleanupFile.Role)
            -> [CleanupFile]
        {
            guard let folder else { return [] }
            return GameScanner.children(of: folder)
                .filter {
                    extensions.contains($0.pathExtension.lowercased())
                        && !GameScanner.isDirectory($0)
                }
                .map { CleanupFile(url: $0, size: size(of: $0), role: role) }
                .sorted {
                    $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                        == .orderedAscending
                }
        }
        switch kind {
        case .gameFiles:
            return list(game.folder, GameScanner.packageExtensions, .original)
                + list(
                    game.buildFolder?.appending(path: "nsp", directoryHint: .isDirectory),
                    ["nsp", "xci"], .converted)
        case .ipas:
            return list(game.folder, ["ipa"], .ipa)
        }
    }

    /// Game files go only once the game is built for the Mac: it keeps playing from its build. IPAs can always
    /// go: Build IPA makes them again. Nothing goes while the game is building or running.
    static func blocked(_ kind: CleanupKind, _ game: Game, busy: Bool) -> String? {
        if busy { return "Busy: wait until its build or game finishes." }
        guard kind == .gameFiles else { return nil }
        return switch game.state {
        case .ready: nil
        case .extracted: "Not built for the Mac yet: play it once first."
        case .notExtracted: "Not extracted: these files are the game."
        }
    }

    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }
}

/// The state of a Remove Game Files / Remove IPAs window: nothing is selected until the user picks it, and
/// deleting needs the confirmation phrase typed.
@MainActor @Observable
public final class Cleanup {
    public enum Phase: Equatable, Sendable {
        case idle, deleting
        case done(count: Int, size: Int64)
        case failed(String)
    }

    public static let phrase = "yes, I'm sure"

    public let kind: CleanupKind
    public private(set) var groups: [CleanupGroup] = []
    public var selection: Set<URL> = []
    public var confirmation = ""
    public private(set) var phase: Phase = .idle

    public init(kind: CleanupKind) {
        self.kind = kind
    }

    /// Files again from disk; the selection keeps only what can still be removed.
    public func scan(games: [Game], busy: Set<Game.ID>) {
        groups = CleanupScanner.groups(kind, games: games, busy: busy)
        selection.formIntersection(selectable)
    }

    var selectable: Set<URL> {
        Set(groups.filter { $0.blocked == nil }.flatMap { $0.files.map(\.url) })
    }

    public var selectedFiles: [CleanupFile] {
        groups.flatMap(\.files).filter { selection.contains($0.url) }
    }

    public var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    public var totalSize: Int64 { groups.reduce(0) { $0 + $1.size } }

    /// "Yes, I'm sure", "yes im sure", "YES I’M SURE": letters and single spaces compared.
    public var isConfirmed: Bool { Self.normalized(confirmation) == Self.normalized(Self.phrase) }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(
            separator: " ")
    }

    public var canDelete: Bool { !selection.isEmpty && isConfirmed && phase != .deleting }

    public func isSelected(_ group: CleanupGroup) -> Bool? {
        let urls = group.files.map(\.url)
        let count = urls.filter(selection.contains).count
        return count == 0 ? false : count == urls.count ? true : nil
    }

    /// Selects every file of the game, or none when all are selected.
    public func toggle(_ group: CleanupGroup) {
        guard group.blocked == nil else { return }
        let urls = Set(group.files.map(\.url))
        if urls.isSubset(of: selection) {
            selection.subtract(urls)
        } else {
            selection.formUnion(urls)
        }
    }

    public func toggle(_ file: CleanupFile) {
        if selection.contains(file.url) {
            selection.remove(file.url)
        } else {
            selection.insert(file.url)
        }
    }

    /// Deletes the selected files for good (not to the Trash: the point is the space). Call scan first, so a
    /// game that became busy meanwhile is skipped.
    public func delete() async {
        let files = selectedFiles
        guard canDelete, !files.isEmpty else { return }
        phase = .deleting
        let failures = await Task.detached {
            files.reduce(into: [URL: String]()) { failures, file in
                do {
                    try FileManager.default.removeItem(at: file.url)
                } catch {
                    failures[file.url] = error.localizedDescription
                }
            }
        }.value
        let removed = files.filter { failures[$0.url] == nil }
        let size = removed.reduce(0) { $0 + $1.size }
        selection = Set(failures.keys)
        confirmation = ""
        phase =
            failures.isEmpty
            ? .done(count: removed.count, size: size)
            : .failed(
                "\(removed.count) of \(files.count) removed. Not removed: "
                    + failures.map { "\($0.key.lastPathComponent) (\($0.value))" }.sorted().joined(
                        separator: "; "))
    }
}
