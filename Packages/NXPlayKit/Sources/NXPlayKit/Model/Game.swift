import Foundation

/// One subfolder of the games folder: the NSPs of a game and, once built, its `<title ID>_build` folder.
public struct Game: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// Only the packages: nothing extracted yet.
        case notExtracted
        /// The game files are extracted but nxplay has not saved a Mac launcher.
        case extracted
        /// `start_mac.sh` and the Mac host are there: the game starts without a build.
        case ready
    }

    public let folder: URL
    public let name: String
    public let titleID: String?
    public let version: String?
    public let iconURL: URL?
    public let buildFolder: URL?
    public let hasPackages: Bool
    public let state: State

    public var id: String { folder.path }
    public var isExtracted: Bool { state != .notExtracted }
    public var canExtract: Bool { state == .notExtracted && hasPackages }

    public var logsFolder: URL? {
        guard let logs = buildFolder?.appending(path: "logs", directoryHint: .isDirectory),
            FileManager.default.fileExists(atPath: logs.path)
        else { return nil }
        return logs
    }
}
