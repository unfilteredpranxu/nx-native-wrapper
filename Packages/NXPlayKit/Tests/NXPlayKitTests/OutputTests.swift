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

/// build_ipa_from_nsp.py's `--progress json` lines, as json.dumps writes them (the event first, ", " and ": ").
@Suite struct BuildOutputTests {
    let t = 1_793_000_000.5

    @Test func aStageItsStepsAndItsEnd() throws {
        var reader = BuildOutputReader()
        let clock = BuildOutputReader.clock(t)

        #expect(
            reader.read(
                #"{"ev": "stage", "k": 4, "n": 6, "name": "shader split", "step": "checking the inputs", "t": \#(t)}"#
            )
                == ["\(clock)[4/6] shader split · checking the inputs …"])
        var p = try #require(reader.progress)
        #expect(p.stage == 4 && p.stages == 6 && !p.finished && p.percent == nil)
        #expect(p.fraction == 3.0 / 6)

        #expect(
            reader.read(
                #"{"ev": "step", "k": 4, "name": "shader split", "step": "splitting", "t": \#(t)}"#
            ).count == 1)
        #expect(
            reader.read(
                #"{"ev": "progress", "k": 4, "name": "shader split", "step": "splitting", "done": 211200, "total": 304243, "unit": "files", "est": false, "note": "", "frac": 0.69, "eta": 4.2, "elapsed": 37.0, "t": \#(t)}"#
            ).isEmpty)  // the bar's job, not the log's
        p = try #require(reader.progress)
        #expect(p.percent == 69 && p.eta == 4.2)
        #expect(p.summary == "4/6 shader split · splitting · 69% · 0:04 left")
        #expect(abs(p.fraction - 3.69 / 6) < 1e-9)

        #expect(
            reader.read(
                #"{"ev": "stage_end", "k": 4, "name": "shader split", "ok": true, "summary": "28669 shaders", "elapsed": 377.2, "t": \#(t)}"#
            ) == ["\(clock)✓ [4/6] shader split (6:17): 28669 shaders"])
        p = try #require(reader.progress)
        #expect(p.finished && !p.isLastStageDone && p.fraction == 4.0 / 6)
    }

    @Test func aFailedStageAndTheLastOne() throws {
        var reader = BuildOutputReader()
        _ = reader.read(
            #"{"ev": "stage", "k": 6, "n": 6, "name": "Mac host", "step": "", "t": \#(t)}"#)
        #expect(
            reader.read(
                #"{"ev": "stage_end", "k": 6, "name": "Mac host", "ok": false, "summary": "", "elapsed": 3, "t": \#(t)}"#
            )
            .first?.hasSuffix("✗ [6/6] Mac host (0:03)") == true)
        #expect(reader.progress?.finished == false)  // a failed stage isn't done
        _ = reader.read(
            #"{"ev": "stage", "k": 6, "n": 6, "name": "Mac host", "step": "", "t": \#(t)}"#)
        _ = reader.read(
            #"{"ev": "stage_end", "k": 6, "name": "Mac host", "ok": true, "summary": "", "elapsed": 3, "t": \#(t)}"#
        )
        #expect(reader.progress?.isLastStageDone == true && reader.progress?.fraction == 1)
    }

    @Test func messagesAndOtherLines() {
        var reader = BuildOutputReader()
        #expect(
            reader.read(
                #"{"ev": "say", "msg": "[13:57:00] [RED] 3 file(s) could not be read\nsecond line", "t": \#(t)}"#
            )
                == ["[13:57:00] [RED] 3 file(s) could not be read", "second line"])
        #expect(
            reader.read("nxnative updated: 1 new commit, rebuilding") == [
                "nxnative updated: 1 new commit, rebuilding"
            ])
        #expect(
            reader.read("Traceback (most recent call last):") == [
                "Traceback (most recent call last):"
            ])
        #expect(reader.read(#"{"ev": "something new", "t": \#(t)}"#).isEmpty)  // a later event this build doesn't know
        #expect(reader.read(#"{"ev": broken"#) == [#"{"ev": broken"#])
        #expect(reader.progress == nil)
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
