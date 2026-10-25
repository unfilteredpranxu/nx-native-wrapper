import Foundation

/// An nxplay invocation: the script, its arguments and the environment it runs in.
public struct NXPlayCommand: Sendable {
    public var script: URL
    public var arguments: [String]
    public var environment: [String: String]

    public init(script: URL, arguments: [String], environment: [String: String]) {
        self.script = script
        self.arguments = arguments
        self.environment = environment
    }

    public var displayLine: String {
        (["nxplay"] + arguments).map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }

    /// A Finder-launched app gets launchd's bare PATH: put mise's shims, ~/.local/bin and Homebrew (dotnet,
    /// spirv-cross) in front so nxplay finds the same tools as a terminal. The Python packages come from
    /// this checkout's .venv (NXPLAY_VENV), which nxplay puts before all of them.
    public static func environment(
        nxnative: String,
        keys: String,
        venv: String? = nil,
        base: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [String: String] {
        // Xcode's debug injections (DYLD_INSERT_LIBRARIES, __XCODE_*) would load into python and the game too
        var env = base.filter {
            !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("__XCODE")
                && !$0.key.hasPrefix("__XPC_DYLD")
        }
        let preferred = [
            "\(home)/.local/share/mise/shims",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
        ]
        let current = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(
            String.init)
        env["PATH"] = (preferred + current.filter { !preferred.contains($0) }).joined(
            separator: ":")
        env["NXNATIVE"] = nxnative
        env["NX_KEYS"] = keys
        if let venv { env["NXPLAY_VENV"] = venv }
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }
}
