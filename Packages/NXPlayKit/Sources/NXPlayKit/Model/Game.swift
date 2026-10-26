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
    /// Language codes the game supports (control.nacp); empty before extraction.
    public let languages: [String]
    public let iconURL: URL?
    public let buildFolder: URL?
    /// The IPA build_ipa_from_nsp.py left in the game folder (the newest, when there are several).
    public let ipaURL: URL?
    /// Install on Device's Xcode build (`<id>_build/xcode-derived-data`), kept to make the next install fast.
    /// Stored, not looked up when asked: a card redraws only when its Game changes, so a value read from disk
    /// on the fly kept showing a removed build.
    public let xcodeBuildFolder: URL?
    /// The standalone Mac app Make Mac App packed into the game folder (nxnative's --platform mac-app).
    public var macAppURL: URL? = nil
    public let hasPackages: Bool
    /// A game file Finder is still copying into the folder: nothing may build from it until it's complete.
    public var isCopying = false
    public let state: State

    public var id: String { folder.path }
    public var isExtracted: Bool { state != .notExtracted }
    public var canExtract: Bool { state == .notExtracted && hasPackages && !isCopying }
    /// Builds read the game files: a rebuild, the IPA and Install on Device (which also starts from the NSPs).
    public var canBuildFromFiles: Bool { hasPackages && !isCopying }
    /// The IPA build starts from the NSPs, whatever the Mac build left.
    public var canBuildIPA: Bool { canBuildFromFiles }

    public var logsFolder: URL? { existingFolder("logs") }

    /// The Mac host's save (DM_SAVE in the launcher), kept from run to run.
    public var saveFolder: URL? { existingFolder("run/save") }

    private func existingFolder(_ path: String) -> URL? {
        guard let folder = buildFolder?.appending(path: path, directoryHint: .isDirectory),
            FileManager.default.fileExists(atPath: folder.path)
        else { return nil }
        return folder
    }
}
