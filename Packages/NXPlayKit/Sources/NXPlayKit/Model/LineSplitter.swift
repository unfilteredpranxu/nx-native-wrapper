import Foundation

/// Splits process output into lines. A carriage return keeps only what follows it,
/// the way a terminal shows a progress line redrawn in place.
public struct LineSplitter: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            lines.append(Self.line(pending[start..<newline]))
            start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
        return lines
    }

    public mutating func finish() -> [String] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [Self.line(pending)]
    }

    static func line(_ bytes: Data) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
        return text.split(separator: "\r").last.map(String.init) ?? ""
    }
}

/// A LineSplitter shared with a FileHandle's readability handler.
final class LockedLineSplitter: @unchecked Sendable {
    private var splitter = LineSplitter()
    private let lock = NSLock()

    func feed(_ data: Data) -> [String] { lock.withLock { splitter.feed(data) } }
    func finish() -> [String] { lock.withLock { splitter.finish() } }
}
