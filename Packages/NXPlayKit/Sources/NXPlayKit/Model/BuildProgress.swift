import Foundation

/// Where a build is: the stage it is in and how far that stage has come, from build_ipa_from_nsp.py's
/// `--progress json` events (nxnative's docs/frontends.md, "Building: the NSP script").
public struct BuildProgress: Equatable, Sendable {
    public let stage: Int
    public let stages: Int
    public let name: String
    /// The step within the stage ("splitting"), empty when it has none.
    public let step: String
    /// The stage's own share done, 0 to 0.99 while it runs, nil when its work can't be counted.
    public let stageFraction: Double?
    /// Seconds left in the stage, while the script can tell.
    public let eta: Double?
    public let finished: Bool

    public var title: String { step.isEmpty ? name : "\(name) · \(step)" }
    public var percent: Int? { finished ? 100 : stageFraction.map { Int(($0 * 100).rounded()) } }

    /// The whole build done so far, counting the current stage's share.
    public var fraction: Double {
        let within = finished ? 1 : stageFraction ?? 0
        return min(1, max(0, (Double(stage - 1) + within) / Double(max(stages, 1))))
    }

    public var isLastStageDone: Bool { finished && stage == stages }

    /// "4/6 shader split · splitting · 45% · 0:04 left"
    public var summary: String {
        var parts = ["\(stage)/\(stages) \(title)"]
        if !finished, let percent { parts.append("\(percent)%") }
        if !finished, let eta { parts.append("\(Self.duration(eta)) left") }
        return parts.joined(separator: " · ")
    }

    /// "0:42", "1:02:03".
    public static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Reads nxplay's output line by line: the build script's JSON events become the progress and log lines as its
/// `--progress lines` mode would print them (a stage's start and end, its steps, its messages); anything else (nxplay's
/// own lines, git's, a traceback on stderr) is shown as it is.
struct BuildOutputReader {
    private(set) var progress: BuildProgress?
    private var stage = 0, stages = 0
    private var name = "", step = ""
    private var stageFraction: Double?, eta: Double?

    /// The log lines a line of output shows; updates `progress` from an event.
    mutating func read(_ line: String) -> [String] {
        guard line.hasPrefix(#"{"ev": "#), let data = line.data(using: .utf8),
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kind = event["ev"] as? String
        else { return [line] }
        let clock = (event["t"] as? Double).map(Self.clock) ?? ""
        let k = event["k"] as? Int ?? stage
        switch kind {
        case "stage":
            stage = k
            stages = event["n"] as? Int ?? stages
            name = event["name"] as? String ?? ""
            step = event["step"] as? String ?? ""
            stageFraction = nil
            eta = nil
            publish(finished: false)
            return ["\(clock)[\(stage)/\(stages)] \(title) …"]
        case "step":
            step = event["step"] as? String ?? ""
            stageFraction = nil
            eta = nil
            publish(finished: false)
            return ["\(clock)[\(stage)/\(stages)] \(title) …"]
        case "progress":
            step = event["step"] as? String ?? step
            stageFraction = event["frac"] as? Double
            eta = event["eta"] as? Double
            publish(finished: false)
            return []
        case "stage_end":
            let ok = event["ok"] as? Bool ?? true
            let elapsed =
                (event["elapsed"] as? Double).map { " (\(BuildProgress.duration($0)))" } ?? ""
            let summary =
                (event["summary"] as? String).flatMap { $0.isEmpty ? nil : ": \($0)" } ?? ""
            let ended = event["name"] as? String ?? name
            step = ""
            eta = nil
            publish(finished: ok)
            return ["\(clock)\(ok ? "✓" : "✗") [\(k)/\(stages)] \(ended)\(elapsed)\(summary)"]
        case "say":
            return (event["msg"] as? String ?? "").split(
                separator: "\n", omittingEmptySubsequences: false
            )
            .map(String.init)
        default:
            return []  // an event this version doesn't know: the log stays readable without it
        }
    }

    private var title: String { step.isEmpty ? name : "\(name) · \(step)" }

    private mutating func publish(finished: Bool) {
        guard stage > 0 else { return }
        progress = BuildProgress(
            stage: stage, stages: max(stages, stage), name: name, step: step,
            stageFraction: stageFraction, eta: eta, finished: finished)
    }

    /// "[21:14:52] ", as the script's own lines start.
    static func clock(_ time: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "[\(formatter.string(from: Date(timeIntervalSince1970: time)))] "
    }
}
