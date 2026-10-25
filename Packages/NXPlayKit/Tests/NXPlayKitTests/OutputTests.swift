import Foundation
import Testing

@testable import NXPlayKit

@Suite struct LineSplitterTests {
    @Test func joinsChunksAndKeepsThePartialLine() {
        var splitter = LineSplitter()
        #expect(splitter.feed(Data("one\ntw".utf8)) == ["one"])
        #expect(splitter.feed(Data("o\nthree".utf8)) == ["two"])
        #expect(splitter.finish() == ["three"])
        #expect(splitter.finish() == [])
    }

    @Test func aCarriageReturnKeepsTheRedrawnText() {
        var splitter = LineSplitter()
        #expect(
            splitter.feed(Data("⠋ stage 1%\r⠙ stage 2%\r      \rdone\nwindows\r\n\n".utf8)) == [
                "done", "windows", "",
            ])
    }
}

@Suite struct LogBufferTests {
    @Test func dropsTheOldestLinesInBatches() {
        var log = LogBuffer(limit: 8)
        log.append((1...10).map(String.init))
        #expect(log.lines.count == 10)  // under limit + limit / 4
        log.append(["11"])
        #expect(log.lines.map(\.text) == (4...11).map(String.init))
        #expect(log.dropped == 3)
        #expect(log.total == 11)
    }
}

@Suite struct BuildProgressTests {
    @Test func stageStart() throws {
        let p = try #require(BuildProgress(line: "[07:48:00] [3/9] shader split · reading …"))
        #expect(p.stage == 3 && p.stages == 9 && !p.finished)
        #expect(p.title == "shader split · reading")
        #expect(p.percent == nil)
        #expect(p.fraction == 2.0 / 9)
    }

    @Test func stageBeat() throws {
        let p = try #require(
            BuildProgress(
                line:
                    "[07:48:30] [3/9] shader split · reading: 45%, 1,203/19,592 shaders, 0:30 · ETA 1:00"
            ))
        #expect(p.title == "shader split · reading")
        #expect(p.percent == 45)
    }

    @Test func stageEnd() throws {
        let p = try #require(
            BuildProgress(line: "[07:49:00] ✓ [9/9] Mac host (1:02:03): /x/tools/dmhost"))
        #expect(p.finished && p.isLastStageDone)
        #expect(p.title == "Mac host")
        #expect(p.fraction == 1)
    }

    @Test func otherLines() {
        #expect(BuildProgress(line: "[07:48:00] building the IPA → /x.ipa") == nil)
        #expect(BuildProgress(line: "Already up to date.") == nil)
    }
}

@Suite struct EnvironmentTests {
    @Test func putsTheToolsFirstAndDropsXcodeInjections() {
        let env = NXPlayCommand.environment(
            nxnative: "/r", keys: "/k", venv: "/w/.venv",
            base: [
                "PATH": "/usr/bin:/opt/homebrew/bin", "DYLD_INSERT_LIBRARIES": "x", "HOME": "/h",
            ],
            home: "/h"
        )
        #expect(
            env["PATH"]
                == "/h/.local/share/mise/shims:/h/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin"
        )
        #expect(env["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(env["NXNATIVE"] == "/r" && env["NX_KEYS"] == "/k" && env["HOME"] == "/h")
        #expect(env["NXPLAY_VENV"] == "/w/.venv")
    }
}
