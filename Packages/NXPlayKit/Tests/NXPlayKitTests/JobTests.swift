import Foundation
import Testing

@testable import NXPlayKit

/// Job against stand-in scripts for nxplay.
@MainActor @Suite struct JobTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-job-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func streamsOutputProgressAndTheExitCode() async throws {
        let job = try job(
            running: """
                echo "args: $*"
                echo "[11:00:00] [2/4] shader split · reading: 50%, 1/2 shaders" >&2
                exit 3
                """, arguments: ["--build-only", "/games/A"])

        job.start()
        try await finished(job)

        #expect(job.status == .failed(3))
        #expect(job.log.lines.contains("args: --build-only /games/A"))
        #expect(job.progress?.stage == 2 && job.progress?.percent == 50)
        #expect(job.log.lines.last == "nxplay: failed (exit 3)")
    }

    @Test func cancelStopsTheWholeProcessTree() async throws {
        let pidFile = folder.appending(path: "child.pid")
        let job = try job(
            running: """
                sleep 60 &
                echo $! > '\(pidFile.path)'
                echo started
                wait
                """)

        job.stopGrace = 0.2
        job.start()
        try await until { job.log.lines.contains("started") }
        let child = try #require(
            Int32(
                String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(
                    in: .whitespacesAndNewlines)))
        job.cancel()
        try await finished(job)

        #expect(job.status == .cancelled)
        // the background child ignores SIGINT: the SIGTERM after it ends it
        try await until { kill(child, 0) != 0 }
    }

    private func job(running body: String, arguments: [String] = []) throws -> Job {
        let script = folder.appending(path: "nxplay")
        try ("#!/bin/bash\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
        let game = Game(
            folder: folder, name: "Test", titleID: nil, version: nil, iconURL: nil,
            buildFolder: nil, hasPackages: true, state: .notExtracted)
        return Job(
            kind: .extract, game: game,
            command: NXPlayCommand(
                script: script, arguments: arguments,
                environment: ProcessInfo.processInfo.environment))
    }

    private func finished(_ job: Job) async throws {
        try await until { !job.status.isActive }
    }

    private func until(timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
