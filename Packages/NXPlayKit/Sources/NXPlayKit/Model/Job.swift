import Foundation
import Observation

/// One nxplay run for a game: an extraction (build without starting) or a play, with its live output.
@MainActor @Observable
public final class Job: Identifiable {
    public enum Kind: Sendable {
        case extract, rebuild, play
    }

    public enum Status: Equatable, Sendable {
        case queued, running, succeeded
        case failed(Int32)
        case cancelled

        public var isActive: Bool { self == .queued || self == .running }
    }

    public let id = UUID()
    public let kind: Kind
    public let game: Game
    public private(set) var status: Status = .queued
    public private(set) var progress: BuildProgress?
    public private(set) var log = LogBuffer()

    @ObservationIgnored let command: NXPlayCommand
    @ObservationIgnored var onFinish: ((Job) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var exitCode: Int32?
    @ObservationIgnored private var outputClosed = false
    @ObservationIgnored private var cancelRequested = false
    /// Seconds between the escalating stop signals.
    @ObservationIgnored var stopGrace: TimeInterval = 5

    init(kind: Kind, game: Game, command: NXPlayCommand) {
        self.kind = kind
        self.game = game
        self.command = command
    }

    /// A build that is still going: a play job builds first when the game is not ready or nxnative changed.
    public var isBuilding: Bool {
        status == .running && progress.map { !$0.isLastStageDone } == true
    }

    func start() {
        guard status == .queued else { return }
        status = .running
        log.append(["$ " + command.displayLine])

        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = [command.script.path] + command.arguments
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let job = self
        let splitter = LockedLineSplitter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            let closed = data.isEmpty
            if closed { handle.readabilityHandler = nil }
            let lines = closed ? splitter.finish() : splitter.feed(data)
            guard closed || !lines.isEmpty else { return }
            // the main queue keeps the chunks in order
            DispatchQueue.main.async {
                MainActor.assumeIsolated { job.received(lines, closed: closed) }
            }
        }
        process.terminationHandler = { process in
            let code = process.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { job.exited(code) } }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            log.append([
                "nxplay: cannot start \(command.script.path): \(error.localizedDescription)"
            ])
            finish(.failed(-1))
        }
    }

    /// Stops the whole process tree: Process puts the child in a process group of its own, so the
    /// signals reach bash, the python build and its tools, or the game. SIGINT first (the build stops
    /// cleanly on it), then SIGTERM and SIGKILL for what ignores it or outlives bash: a script's
    /// background jobs ignore SIGINT.
    public func cancel() {
        switch status {
        case .queued:
            finish(.cancelled)
        case .running:
            guard let process, process.isRunning, !cancelRequested else { return }
            cancelRequested = true
            log.append(["nxplay: stopping…"])
            let group = process.processIdentifier
            if kill(-group, SIGINT) != 0 { process.interrupt() }
            for (step, signal) in [SIGTERM, SIGKILL].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + stopGrace * Double(step + 1)) {
                    _ = kill(-group, signal)
                }
            }
        default:
            break
        }
    }

    /// The app is quitting: no grace period.
    func terminate() {
        if status == .queued { finish(.cancelled) }
        guard let process, process.isRunning else { return }
        cancelRequested = true
        if kill(-process.processIdentifier, SIGTERM) != 0 { process.terminate() }
    }

    private func received(_ lines: [String], closed: Bool) {
        if !lines.isEmpty {
            log.append(lines)
            if let latest = lines.lazy.compactMap(BuildProgress.init(line:)).last {
                progress = latest
            }
        }
        if closed {
            outputClosed = true
            finishIfDone()
        }
    }

    private func exited(_ code: Int32) {
        exitCode = code
        finishIfDone()
        // something the game left running may hold the output open: stop waiting for it
        let job = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                job.outputClosed = true
                job.finishIfDone()
            }
        }
    }

    private func finishIfDone() {
        guard status == .running, outputClosed, let exitCode else { return }
        process?.terminationHandler = nil
        process = nil
        finish(cancelRequested ? .cancelled : exitCode == 0 ? .succeeded : .failed(exitCode))
    }

    private func finish(_ status: Status) {
        self.status = status
        switch status {
        case .succeeded: log.append(["nxplay: done"])
        case .failed(let code): log.append(["nxplay: failed (exit \(code))"])
        case .cancelled: log.append(["nxplay: cancelled"])
        default: break
        }
        onFinish?(self)
    }
}
