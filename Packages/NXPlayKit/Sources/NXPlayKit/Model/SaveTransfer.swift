import Foundation
import Observation

/// Copies one game's save between this Mac (`<title ID>_build/run/save`, the Mac host's DM_SAVE) and a device
/// (the iOS app's Documents/save), one direction at a time and only when asked. The save that gets replaced is
/// kept on this Mac first, in `run/save-backups/`. Either game must be closed: the host clones the save when the
/// game mounts it and would commit its copy over the transferred one.
@MainActor @Observable
public final class SaveTransfer: Identifiable {
    public enum Direction: Hashable, Sendable { case toMac, fromMac }

    public let id = UUID()

    public enum Phase: Equatable, Sendable {
        case idle, loading, copying
        case done(String)
        case failed(String)
    }

    public let game: Game
    public var direction: Direction = .toMac
    public var device: Device?
    public var app: DeviceApp?
    public internal(set) var apps: [DeviceApp] = []
    public internal(set) var macFiles: [SaveFile] = []
    /// nil until read from the device.
    public internal(set) var deviceFiles: [SaveFile]?
    public internal(set) var phase: Phase = .idle

    @ObservationIgnored private let preferredBundleID: String?

    public init(game: Game, preferredBundleID: String?) {
        self.game = game
        self.preferredBundleID = preferredBundleID
        macFiles = macSave.map(SaveFile.list) ?? []
    }

    public var macSave: URL? {
        game.buildFolder?.appending(path: "run/save", directoryHint: .isDirectory)
    }

    public var comparison: SaveComparison {
        SaveComparison(mac: macFiles, device: deviceFiles ?? [])
    }

    public var isBusy: Bool { phase == .loading || phase == .copying }

    /// What would be copied is empty: nothing to do.
    public var sourceIsEmpty: Bool {
        direction == .toMac ? (deviceFiles ?? []).isEmpty : macFiles.isEmpty
    }

    public var canCopy: Bool {
        app != nil && deviceFiles != nil && !isBusy && !sourceIsEmpty && macSave != nil
    }

    /// The game's copies on the chosen device, then their save.
    public func loadDevice() async {
        apps = []
        app = nil
        deviceFiles = nil
        guard let device, let titleID = game.titleID else { return }
        phase = .loading
        do {
            apps = try await DeviceCtl.apps(on: device, titleID: titleID)
            guard self.device == device else { return }  // another device was picked meanwhile
            guard let pick = apps.first(where: { $0.bundleID == preferredBundleID }) ?? apps.first
            else {
                phase = .failed(
                    "\(game.name) is not on \(device.name) with a development signature. Install it with Install on Device first."
                )
                return
            }
            app = pick
            await loadDeviceFiles()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func loadDeviceFiles() async {
        guard let device, let app else { return }
        phase = .loading
        do {
            let files = try await DeviceCtl.saveFiles(on: device, bundleID: app.bundleID)
            guard self.device == device, self.app == app else { return }
            deviceFiles = files
            phase = .idle
        } catch {
            phase = .failed(
                "Could not read the save on \(device.name): \(error.localizedDescription)")
        }
    }

    public func copy() async {
        guard canCopy, let device, let app, let macSave else { return }
        phase = .copying
        let fm = FileManager.default
        let run = macSave.deletingLastPathComponent()
        let backups = run.appending(path: "save-backups", directoryHint: .isDirectory)
        let stamp = Self.stamp.string(from: .now)
        do {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            switch direction {
            case .toMac:
                let incoming = run.appending(path: "save.incoming", directoryHint: .isDirectory)
                try? fm.removeItem(at: incoming)
                try await DeviceCtl.pullSave(from: device, bundleID: app.bundleID, to: incoming)
                guard !SaveFile.list(incoming).isEmpty else {
                    try? fm.removeItem(at: incoming)
                    throw DeviceCtl.Failure(
                        message:
                            "The save came back empty from \(device.name); this Mac's save is unchanged."
                    )
                }
                var note = ""
                if !macFiles.isEmpty {
                    let backup = backups.appending(path: "\(stamp) Mac")
                    try fm.moveItem(at: macSave, to: backup)
                    note = " The replaced Mac save is in save-backups/\(backup.lastPathComponent)."
                } else {
                    try? fm.removeItem(at: macSave)
                }
                try fm.moveItem(at: incoming, to: macSave)
                phase = .done("Copied \(device.name)'s save to this Mac.\(note)")
            case .fromMac:
                var note = ""
                if !(deviceFiles ?? []).isEmpty {
                    let backup = backups.appending(path: "\(stamp) \(Self.safeName(device.name))")
                    try await DeviceCtl.pullSave(from: device, bundleID: app.bundleID, to: backup)
                    note =
                        " The replaced save is kept on this Mac in save-backups/\(backup.lastPathComponent)."
                }
                // only the game's files (not Finder's .DS_Store): an APFS clone of each, with its date
                let outgoing = run.appending(path: "save.outgoing", directoryHint: .isDirectory)
                try? fm.removeItem(at: outgoing)
                defer { try? fm.removeItem(at: outgoing) }
                for file in macFiles {
                    let target = outgoing.appending(path: file.path)
                    try fm.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: macSave.appending(path: file.path), to: target)
                }
                try await DeviceCtl.pushSave(outgoing, to: device, bundleID: app.bundleID)
                phase = .done("Copied this Mac's save to \(device.name).\(note)")
            }
            let result = phase
            macFiles = SaveFile.list(macSave)
            await loadDeviceFiles()
            if phase == .idle { phase = result }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
