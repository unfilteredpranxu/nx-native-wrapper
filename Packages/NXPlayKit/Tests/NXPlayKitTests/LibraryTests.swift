import Foundation
import Testing

@testable import NXPlayKit

@MainActor @Suite struct LibraryTests {
    private func library() -> Library {
        let suite = "nxplay-tests-\(UUID().uuidString)"
        return Library(defaults: UserDefaults(suiteName: suite)!, isScreenshot: true)  // no devicectl
    }

    private func job(_ name: String, _ status: Job.Status) -> Job {
        let game = Game(
            folder: URL(filePath: "/games/\(name)"), name: name, titleID: nil, version: nil,
            languages: [],
            iconURL: nil, buildFolder: nil, ipaURL: nil, xcodeBuildFolder: nil, hasPackages: true,
            state: .ready)
        let job = Job(
            kind: .rebuild, game: game,
            command: NXPlayCommand(
                script: URL(filePath: "/usr/bin/true"), arguments: [], environment: [:]))
        job.showScreenshot(["output"], status: status)
        return job
    }

    @Test func aFailedJobOpensTheLogOnItsGame() {
        let library = library()
        library.showsLog = false
        library.selection = "/games/Other"

        library.finished(job("Done", .succeeded))
        #expect(!library.showsLog && library.selection == "/games/Other")  // success leaves it alone

        library.finished(job("Broken", .failed(1)))
        #expect(library.showsLog)
        #expect(library.selection == "/games/Broken")
    }

    @Test func theLogStateIsRemembered() {
        let suite = "nxplay-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let first = Library(defaults: defaults, isScreenshot: true)
        #expect(first.showsLog && first.logHeight == 240 && first.viewStyle == .grid)  // defaults
        first.showsLog = false
        first.logHeight = 333
        first.viewStyle = .list

        let next = Library(defaults: defaults, isScreenshot: true)
        #expect(!next.showsLog && next.logHeight == 333 && next.viewStyle == .list)
    }
}
