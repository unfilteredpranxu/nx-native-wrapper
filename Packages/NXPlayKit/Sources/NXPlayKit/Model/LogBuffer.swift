/// The output of a job, capped: past the limit the oldest lines go (a game can print for hours).
public struct LogBuffer: Sendable {
    public private(set) var lines: [LogLine] = []
    /// Lines removed from the front.
    public private(set) var dropped = 0
    public let limit: Int

    public init(limit: Int = 20_000) {
        self.limit = limit
    }

    /// Lines ever appended, dropped ones included.
    public var total: Int { dropped + lines.count }
    /// The plain text, without escape sequences.
    public var text: String { lines.map(\.text).joined(separator: "\n") }

    public mutating func append(_ new: [String]) {
        append(new.map(LogLine.init))
    }

    public mutating func append(_ new: [LogLine]) {
        lines.append(contentsOf: new)
        // trim in batches so a chatty process does not shift the whole array on every line
        guard lines.count > limit + limit / 4 else { return }
        let excess = lines.count - limit
        lines.removeFirst(excess)
        dropped += excess
    }
}
