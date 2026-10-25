import Foundation

/// A stage line of build_ipa_from_nsp.py in `--progress lines` mode (its mode when the output is a pipe):
///
///     [07:48:00] [3/9] shader split · reading …
///     [07:48:30] [3/9] shader split · reading: 45%, 1,203/19,592 shaders, 0:30 · ETA 1:00
///     [07:49:00] ✓ [3/9] shader split (1:00): 19,592 shaders
public struct BuildProgress: Equatable, Sendable {
    public let stage: Int
    public let stages: Int
    public let title: String
    public let percent: Int?
    public let finished: Bool

    /// The whole build done so far, counting the current stage's percentage.
    public var fraction: Double {
        let within = finished ? 1 : Double(percent ?? 0) / 100
        return min(1, max(0, (Double(stage - 1) + within) / Double(stages)))
    }

    public var isLastStageDone: Bool { finished && stage == stages }

    public init?(line: String) {
        guard let match = line.firstMatch(of: #/\[(\d+)/(\d+)\]\s+(.+)$/#),
            let stage = Int(match.1), let stages = Int(match.2), stages > 0
        else { return nil }
        self.stage = stage
        self.stages = stages
        finished = line[..<match.range.lowerBound].contains("✓")

        var rest = Substring(match.3)
        var percent: Int?
        if finished {
            if let elapsed = rest.firstMatch(of: #/ \(\d+:\d{2}(?::\d{2})?\)/#) {
                rest = rest[..<elapsed.range.lowerBound]
            }
        } else if let colon = rest.range(of: ": ") {
            percent = rest[colon.upperBound...].firstMatch(of: #/(\d+)%/#).flatMap { Int($0.1) }
            rest = rest[..<colon.lowerBound]
        }
        if rest.hasSuffix(" …") { rest = rest.dropLast(2) }
        self.percent = percent
        title = rest.trimmingCharacters(in: .whitespaces)
    }
}
