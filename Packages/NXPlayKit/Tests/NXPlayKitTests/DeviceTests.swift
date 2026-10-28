import Foundation
import Testing

@testable import NXPlayKit

@Suite struct DeviceTests {
    private func device(
        _ name: String, udid: String, platform: String = "iOS", reality: String = "physical",
        developerMode: String = "enabled", tunnel: String = "disconnected"
    ) -> [String: Any] {
        [
            "hardwareProperties": [
                "platform": platform, "reality": reality, "udid": udid,
                "marketingName": "iPhone 18 Pro",
            ],
            "deviceProperties": [
                "name": name, "developerModeStatus": developerMode, "osVersionNumber": "27.2",
            ],
            "connectionProperties": ["pairingState": "paired", "tunnelState": tunnel],
        ]
    }

    @Test func keepsReachableDevelopmentDevices() throws {
        let json = try JSONSerialization.data(withJSONObject: [
            "result": [
                "devices": [
                    device("Test iPhone", udid: "00008000-0000000000000001"),
                    device("iPad Pro", udid: "00008000-0000000000000002", tunnel: "connected"),
                    device("Living room", udid: "00008000-0000000000000003", platform: "tvOS"),
                    device(
                        "Kid’s iPad", udid: "00008000-0000000000000004", developerMode: "disabled"),
                    device("Away", udid: "00008000-0000000000000005", tunnel: "unavailable"),
                    device(
                        "iPhone 17", udid: "00000000-0000-0000-0000-000000000006",
                        reality: "simulated"),
                ]
            ]
        ])

        let devices = Device.parse(json: json)

        #expect(devices.map(\.name) == ["iPad Pro", "Test iPhone"])
        #expect(
            devices.last
                == Device(
                    id: "00008000-0000000000000001", name: "Test iPhone", model: "iPhone 18 Pro",
                    osVersion: "27.2"))
    }

    @Test func readsXcodesTeams() throws {
        let suite = testDefaultsName()
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { removeTestDefaults(suite) }
        defaults.set(
            [
                "account-uuid": [
                    [
                        "teamID": "ABCDE12345", "teamName": "Example Team",
                        "isFreeProvisioningTeam": false,
                    ],
                    [
                        "teamID": "FREE123456", "teamName": "Example (Personal Team)",
                        "isFreeProvisioningTeam": true,
                    ],
                ]
            ], forKey: "IDEProvisioningTeamByIdentifier")
        defaults.set(
            ["me@example.com": [["teamID": "ABCDE12345", "teamName": "Example Team"]]],
            forKey: "IDEProvisioningTeams")

        let teams = AppleTeam.fromXcode(defaults)

        #expect(teams.map(\.id) == ["ABCDE12345", "FREE123456"])
        #expect(teams.map(\.isFree) == [false, true])
        #expect(
            Library.bundleID(titleID: "010093801237C000", team: teams[0])
                == "org.nxnative.abcde12345.010093801237c000")
    }
}
