import Foundation

/// An iPhone or iPad the game can be installed on through Xcode: paired, reachable and in Developer Mode.
public struct Device: Hashable, Identifiable, Sendable {
    /// The UDID xcodebuild and devicectl take.
    public let id: String
    public let name: String
    public let model: String
    public let osVersion: String

    /// The devices in `xcrun devicectl list devices --json-output` output.
    public static func parse(json: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let list = (root["result"] as? [String: Any])?["devices"] as? [[String: Any]]
        else { return [] }
        return list.compactMap { entry in
            let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
            let properties = entry["deviceProperties"] as? [String: Any] ?? [:]
            let connection = entry["connectionProperties"] as? [String: Any] ?? [:]
            guard hardware["platform"] as? String == "iOS",
                hardware["reality"] as? String == "physical",
                connection["pairingState"] as? String == "paired",
                connection["tunnelState"] as? String != "unavailable",
                properties["developerModeStatus"] as? String == "enabled",
                let udid = hardware["udid"] as? String
            else { return nil }
            return Device(
                id: udid,
                name: properties["name"] as? String ?? udid,
                model: hardware["marketingName"] as? String ?? hardware["deviceType"] as? String
                    ?? "",
                osVersion: properties["osVersionNumber"] as? String ?? ""
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Asks devicectl (a second or two, more when devices sleep), off the main thread.
    public static func load() async -> [Device] {
        await Task.detached {
            let output = FileManager.default.temporaryDirectory.appending(
                path: "nxplay-devices-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: output) }
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/xcrun")
            process.arguments = [
                "devicectl", "list", "devices", "--json-output", output.path, "-q",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            process.waitUntilExit()
            return (try? Data(contentsOf: output)).map(parse(json:)) ?? []
        }.value
    }
}

/// A development team of an Apple account signed in to Xcode.
public struct AppleTeam: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// A Personal Team (free account): it cannot provision the Increased Memory Limit capability.
    public let isFree: Bool

    /// The teams Xcode keeps for its signed-in accounts (Xcode > Settings > Apple Accounts).
    public static func fromXcode(
        _ defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dt.Xcode")
    ) -> [AppleTeam] {
        guard let defaults else { return [] }
        var seen = Set<String>()
        return ["IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"]
            .compactMap { defaults.dictionary(forKey: $0) }
            .flatMap { $0.values.compactMap { $0 as? [[String: Any]] }.joined() }
            .compactMap { team -> AppleTeam? in
                guard let id = team["teamID"] as? String, seen.insert(id).inserted else {
                    return nil
                }
                return AppleTeam(
                    id: id, name: team["teamName"] as? String ?? id,
                    isFree: (team["isFreeProvisioningTeam"] as? Bool) ?? false)
            }
    }
}
