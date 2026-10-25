import Foundation
import Testing

@testable import NXPlayKit

@Suite struct SaveTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func comparesFileByFile() {
        let comparison = SaveComparison(
            mac: [
                SaveFile(path: "userdata/a.bmssv", size: 96, modified: t0),
                SaveFile(path: "userdata/b.bmssv", size: 10, modified: t0.addingTimeInterval(600)),
                SaveFile(path: "userdata/mac-only", size: 1, modified: t0),
                SaveFile(path: "userdata/d.bmssv", size: 5, modified: t0),
            ],
            device: [
                SaveFile(path: "userdata/a.bmssv", size: 96, modified: t0.addingTimeInterval(1)),  // within the tolerance
                SaveFile(path: "userdata/b.bmssv", size: 10, modified: t0),
                SaveFile(path: "userdata/c.bmssv", size: 7, modified: t0.addingTimeInterval(1200)),
                SaveFile(path: "userdata/d.bmssv", size: 6, modified: t0),
            ])

        let statuses = Dictionary(
            uniqueKeysWithValues: comparison.rows.map { ($0.path, "\($0.status)") })
        #expect(
            statuses == [
                "userdata/a.bmssv": "same",
                "userdata/b.bmssv": "newer(NXPlayKit.SaveComparison.Side.mac)",
                "userdata/c.bmssv": "only(NXPlayKit.SaveComparison.Side.device)",
                "userdata/d.bmssv": "differs",
                "userdata/mac-only": "only(NXPlayKit.SaveComparison.Side.mac)",
            ])
        #expect(!comparison.isIdentical)
        #expect(comparison.newer == .device)  // c.bmssv changed last
    }

    @Test func identicalAndEmpty() {
        let file = SaveFile(path: "userdata/a", size: 1, modified: t0)
        #expect(SaveComparison(mac: [file], device: [file]).isIdentical)
        #expect(SaveComparison(mac: [file], device: [file]).newer == nil)
        #expect(SaveComparison(mac: [file], device: []).newer == .mac)
    }

    @Test func listsAMacSaveFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-save-\(UUID().uuidString)/save")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "userdata"), withIntermediateDirectories: true)
        try Data(count: 96).write(to: folder.appending(path: "userdata/userdata.bmssv"))
        #expect(SaveFile.list(folder).map(\.path) == ["userdata/userdata.bmssv"])
        #expect(SaveFile.list(folder).first?.size == 96)
        #expect(SaveFile.list(folder.appending(path: "missing")).isEmpty)
    }

    @Test func readsDevicectlOutput() throws {
        let files = try JSONSerialization.data(withJSONObject: [
            "result": [
                "files": [
                    [
                        "relativePath": "log.txt", "resources": ["isDirectory": false],
                        "metadata": ["size": 4017, "lastModDate": "2026-10-25T15:24:36.000Z"],
                    ],
                    [
                        "relativePath": "save", "resources": ["isDirectory": true],
                        "metadata": ["size": 96, "lastModDate": "2026-10-25T15:24:36.000Z"],
                    ],
                    [
                        "relativePath": "save/userdata/userdata.bmssv",
                        "resources": ["isDirectory": false],
                        "metadata": ["size": 96, "lastModDate": "2026-10-25T15:04:00.000Z"],
                    ],
                    [
                        "relativePath": "save.work/userdata/userdata.bmssv",
                        "resources": ["isDirectory": false],
                        "metadata": ["size": 96, "lastModDate": "2026-10-25T15:04:00.000Z"],
                    ],
                ]
            ]
        ])
        #expect(
            DeviceCtl.parseSaveFiles(files) == [
                SaveFile(
                    path: "userdata/userdata.bmssv", size: 96,
                    modified: Date(timeIntervalSince1970: 1_792_940_640))  // 2026-10-25 15:04 UTC
            ])

        let apps = try JSONSerialization.data(withJSONObject: [
            "result": [
                "apps": [
                    [
                        "bundleIdentifier": "org.nxnative.abcde12345.010093801237c000",
                        "name": "Metroid Dread", "version": "2.1.0", "containerAccessible": true,
                    ],
                    [
                        "bundleIdentifier": "org.nxnative.010093801237c000",
                        "name": "Metroid Dread", "version": "2.1.0", "containerAccessible": false,
                    ],
                    [
                        "bundleIdentifier": "org.nxnative.abcde12345.010020d01ad24000",
                        "name": "ANIMAL WELL", "containerAccessible": true,
                    ],
                ]
            ]
        ])
        #expect(
            DeviceCtl.parseApps(apps, titleID: "010093801237C000").map(\.bundleID) == [
                "org.nxnative.abcde12345.010093801237c000"
            ])
    }
}
