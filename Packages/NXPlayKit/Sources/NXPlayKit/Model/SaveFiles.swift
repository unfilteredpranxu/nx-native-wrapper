import Foundation

/// One file of a game save: its path inside the save folder, size and last change.
public struct SaveFile: Hashable, Sendable {
    public let path: String
    public let size: Int
    public let modified: Date

    public init(path: String, size: Int, modified: Date) {
        self.path = path
        self.size = size
        self.modified = modified
    }

    /// The files under a save folder on this Mac; none when it does not exist. Hidden files (Finder's
    /// .DS_Store) are not the game's: they are neither compared nor copied to a device.
    public static func list(_ folder: URL) -> [SaveFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard
            let walk = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        let base = folder.resolvingSymlinksInPath().path + "/"
        return walk.compactMap { item -> SaveFile? in
            guard let url = item as? URL, let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true
            else { return nil }
            let path = url.resolvingSymlinksInPath().path
            return SaveFile(
                path: path.hasPrefix(base)
                    ? String(path.dropFirst(base.count)) : url.lastPathComponent,
                size: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.path < $1.path }
    }
}

/// The Mac's save beside a device's, file by file.
public struct SaveComparison: Sendable {
    public enum Side: Sendable { case mac, device }

    public enum Status: Sendable {
        case same
        case newer(Side)
        case only(Side)
        /// Same time, different size: neither can be called newer.
        case differs
    }

    public struct Row: Identifiable, Sendable {
        public let path: String
        public let mac: SaveFile?
        public let device: SaveFile?
        public let status: Status
        public var id: String { path }
    }

    public let rows: [Row]

    /// Copies keep the modification time; the device reports whole seconds.
    static let tolerance: TimeInterval = 2

    public init(mac: [SaveFile], device: [SaveFile]) {
        let macFiles = Dictionary(mac.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let deviceFiles = Dictionary(device.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        rows = Set(macFiles.keys).union(deviceFiles.keys).sorted().map { path in
            let (m, d) = (macFiles[path], deviceFiles[path])
            let status: Status =
                switch (m, d) {
                case (let m?, let d?):
                    if abs(m.modified.timeIntervalSince(d.modified)) < Self.tolerance {
                        m.size == d.size ? .same : .differs
                    } else {
                        .newer(m.modified > d.modified ? .mac : .device)
                    }
                case (_?, nil): .only(.mac)
                default: .only(.device)
                }
            return Row(path: path, mac: m, device: d, status: status)
        }
    }

    public var isIdentical: Bool {
        rows.allSatisfy { if case .same = $0.status { true } else { false } }
    }

    /// The latest change on each side.
    public func latest(_ side: Side) -> Date? {
        rows.compactMap { side == .mac ? $0.mac?.modified : $0.device?.modified }.max()
    }

    /// The side whose save changed last, when the two differ.
    public var newer: Side? {
        guard !isIdentical else { return nil }
        switch (latest(.mac), latest(.device)) {
        case (let m?, let d?): return m >= d ? .mac : .device
        case (_?, nil): return .mac
        case (nil, _?): return .device
        default: return nil
        }
    }
}
