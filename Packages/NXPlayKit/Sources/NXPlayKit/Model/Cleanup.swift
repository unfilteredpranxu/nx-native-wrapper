import Foundation
import Observation

/// What Tools › Free Up Space can delete.
public enum CleanupKind: String, CaseIterable, Identifiable, Sendable {
    /// A game's NSP / NSZ / XCI / XCZ files, and the NSPs a build converted from NSZ (`<id>_build/nsp`).
    case gameFiles
    case ipas
    /// `<id>_build/xcode-derived-data`: Install on Device's build, a full copy of the game.
    case xcodeBuilds

    public var id: String { rawValue }
}

public struct CleanupFile: Identifiable, Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case original
        /// An NSP the build decompressed from an NSZ and keeps for the next build.
        case converted
        case ipa
        case xcodeBuild
    }

    public let url: URL
    /// Space on disk (allocated; a folder counts everything in it).
    public let size: Int64
    public let role: Role
    /// Why it cannot be removed now; nil when it can.
    public let blocked: String?
    public var id: URL { url }

    public var kind: CleanupKind {
        switch role {
        case .original, .converted: .gameFiles
        case .ipa: .ipas
        case .xcodeBuild: .xcodeBuilds
        }
    }
}

/// One game's removable files, of every kind.
public struct CleanupGroup: Identifiable, Sendable {
    public let game: Game
    public let files: [CleanupFile]
    public var id: Game.ID { game.id }
    public var size: Int64 { files.reduce(0) { $0 + $1.size } }
}

public enum CleanupScanner {
    /// Reads sizes from disk, a whole Xcode build included: run it off the main thread.
    public static func groups(games: [Game], busy: Set<Game.ID> = []) -> [CleanupGroup] {
        games.compactMap { game in
            let files = files(of: game, busy: busy.contains(game.id))
            return files.isEmpty ? nil : CleanupGroup(game: game, files: files)
        }
    }

    static func files(of game: Game, busy: Bool) -> [CleanupFile] {
        func list(_ folder: URL?, _ extensions: Set<String>, _ role: CleanupFile.Role)
            -> [CleanupFile]
        {
            guard let folder else { return [] }
            return GameScanner.children(of: folder)
                .filter {
                    extensions.contains($0.pathExtension.lowercased())
                        && !GameScanner.isDirectory($0)
                }
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                }
                .map {
                    CleanupFile(
                        url: $0, size: size(of: $0), role: role,
                        blocked: blocked(role, game, busy: busy))
                }
        }
        var files =
            list(game.folder, GameScanner.packageExtensions, .original)
            + list(
                game.buildFolder?.appending(path: "nsp", directoryHint: .isDirectory),
                ["nsp", "xci"], .converted)
            + list(game.folder, ["ipa"], .ipa)
        if let xcode = game.buildFolder?.appending(
            path: "xcode-derived-data", directoryHint: .isDirectory),
            GameScanner.isDirectory(xcode)
        {
            files.append(
                CleanupFile(
                    url: xcode, size: size(of: xcode), role: .xcodeBuild,
                    blocked: blocked(.xcodeBuild, game, busy: busy)))
        }
        return files
    }

    /// Game files go only once the game is built for the Mac: it keeps playing from its build. IPAs and
    /// Xcode builds can always go: Build IPA and Install on Device make them again. Nothing goes while the
    /// game is building or running.
    static func blocked(_ role: CleanupFile.Role, _ game: Game, busy: Bool) -> String? {
        if busy { return "Busy: wait until its build or game finishes." }
        guard role == .original || role == .converted else { return nil }
        return switch game.state {
        case .ready: nil
        case .extracted: "Not built for the Mac yet: play it once first."
        case .notExtracted: "Not extracted: these files are the game."
        }
    }

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
        func one(_ url: URL) -> Int64 {
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        guard GameScanner.isDirectory(url) else { return one(url) }
        let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let item = walk?.nextObject() as? URL { total += one(item) }
        return total
    }
}

/// The state of the Free Up Space window: nothing is selected until the user picks it, and deleting needs
/// the confirmation phrase typed.
@MainActor @Observable
public final class Cleanup {
    public enum Phase: Equatable, Sendable {
        case idle, scanning, deleting
        case done(count: Int, size: Int64)
        case failed(String)
    }

    public static let phrase = "yes, I'm sure"

    public private(set) var groups: [CleanupGroup] = []
    public var selection: Set<URL> = []
    public var confirmation = ""
    public private(set) var phase: Phase = .idle
    @ObservationIgnored private var scans = 0

    public init() {}

    /// Files and sizes again from disk; the selection keeps only what can still be removed.
    public func scan(games: [Game], busy: Set<Game.ID>) async {
        scans += 1
        let scan = scans
        let previous = phase
        if groups.isEmpty { phase = .scanning }
        let groups = await Task.detached { CleanupScanner.groups(games: games, busy: busy) }.value
        guard scan == scans else { return }  // a newer scan started meanwhile
        apply(groups)
        if phase == .scanning { phase = previous == .scanning ? .idle : previous }
    }

    func apply(_ groups: [CleanupGroup]) {
        self.groups = groups
        selection.formIntersection(selectable)
    }

    var files: [CleanupFile] { groups.flatMap(\.files) }
    var selectable: Set<URL> { Set(files.filter { $0.blocked == nil }.map(\.url)) }

    public var selectedFiles: [CleanupFile] { files.filter { selection.contains($0.url) } }
    public var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    public var totalSize: Int64 { groups.reduce(0) { $0 + $1.size } }

    public func files(_ kind: CleanupKind) -> [CleanupFile] { files.filter { $0.kind == kind } }
    public func size(_ kind: CleanupKind) -> Int64 { files(kind).reduce(0) { $0 + $1.size } }

    /// "Yes, I'm sure", "yes im sure", "YES I’M SURE": letters and single spaces compared.
    public var isConfirmed: Bool { Self.normalized(confirmation) == Self.normalized(Self.phrase) }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(
            separator: " ")
    }

    public var canDelete: Bool { !selection.isEmpty && isConfirmed && phase != .deleting }

    /// true: all of its selectable files, false: none, nil: some.
    public func isSelected(_ files: [CleanupFile]) -> Bool? {
        let urls = files.filter { $0.blocked == nil }.map(\.url)
        let count = urls.filter(selection.contains).count
        return count == 0 ? false : count == urls.count ? true : nil
    }

    public func isSelected(_ group: CleanupGroup) -> Bool? { isSelected(group.files) }
    public func isSelected(_ kind: CleanupKind) -> Bool? { isSelected(files(kind)) }

    /// Selects every selectable file of them, or none when all are selected.
    public func toggle(_ files: [CleanupFile]) {
        let urls = Set(files.filter { $0.blocked == nil }.map(\.url))
        if urls.isSubset(of: selection) {
            selection.subtract(urls)
        } else {
            selection.formUnion(urls)
        }
    }

    public func toggle(_ group: CleanupGroup) { toggle(group.files) }
    public func toggle(_ kind: CleanupKind) { toggle(files(kind)) }
    public func toggle(_ file: CleanupFile) { toggle([file]) }

    /// Deletes the selected files and folders for good (not to the Trash: the point is the space). Scan
    /// first, so a game that became busy meanwhile is skipped.
    public func delete() async {
        let files = selectedFiles.filter { $0.blocked == nil }
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
