import Foundation
import Testing

@testable import NXPlayKit

@MainActor @Suite struct SetupTests {
    @Test func readsTheReportBySection() {
        var parser = SetupParser()
        for line in [
            "", "Mac", "  ✓ Apple silicon", "", "Tools",
            "  ✗ Homebrew is not installed: install it from https://brew.sh",
            "==> Downloading https://ghcr.io/…", "Using zstd", "", "Python (.venv)",
            "  ! uv is not installed: brew install uv", "1 problem to fix; then check again.",
        ] {
            parser.read(line)
        }
        #expect(parser.items.map(\.section) == ["Mac", "Tools", "Python"])
        #expect(parser.items.map(\.state) == [.ok, .missing, .warning])
        #expect(
            parser.items[1].text == "Homebrew is not installed: install it from https://brew.sh")
    }

    @Test func runsTheScriptAndReportsTheResult() async throws {
        let script = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-setup-\(UUID().uuidString)")
        try Data(
            """
            echo
            echo Tools
            echo "  ✓ Homebrew tools (Brewfile)"
            [ "$1" = --check ] && { echo "  ✗ the Python packages are missing: uv sync --locked ($NXPLAY_HOME)"; exit 1; }
            echo "  ✓ Python with nxnative's packages"

            """.utf8
        ).write(to: script)
        let setup = Setup(script: script, environment: { ["NXPLAY_HOME": "/home"] })
        var finished = 0
        setup.onFinish = { finished += 1 }

        setup.check()
        for _ in 0..<100 where setup.succeeded == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(setup.succeeded == false && finished == 1)
        #expect(
            setup.missing.map(\.text) == [
                "the Python packages are missing: uv sync --locked (/home)"
            ])

        setup.install()
        for _ in 0..<100 where setup.phase != .idle || finished < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(setup.succeeded == true)
        #expect(setup.missing.isEmpty && setup.items.count == 2)
        #expect(setup.log.lines.contains { $0.text.contains("Python with nxnative's packages") })
    }
}
