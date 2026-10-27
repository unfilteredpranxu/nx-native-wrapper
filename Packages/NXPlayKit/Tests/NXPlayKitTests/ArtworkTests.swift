import Foundation
import Testing

@testable import NXPlayKit

@Suite struct ArtworkTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "nxplay-artwork-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// titledb's shape: {nsuid: {id, bannerUrl, …}}, with a title listed twice, one without a banner and one
    /// whose banner is on another host.
    private func titleList(banner: URL) throws -> URL {
        let list: [String: [String: Any?]] = [
            "70010000000002": [
                "id": "0100f2c0115b6000", "bannerUrl": banner.absoluteString, "name": "TotK",
            ],
            "70010000000009": ["id": "0100F2C0115B6000", "bannerUrl": "file:///elsewhere.jpg"],
            "70010000000003": ["id": "01007EF00011E000", "bannerUrl": NSNull()],
            "70010000000004": [
                "id": "010093801237C000", "bannerUrl": "https://example.com/banner.jpg",
            ],
        ]
        let url = root.appending(path: "US.en.json")
        try JSONSerialization.data(withJSONObject: list.mapValues { $0.compactMapValues { $0 } })
            .write(to: url)
        return url
    }

    @Test func downloadsTheBannersTitlesLackOnce() async throws {
        let banner = root.appending(path: "totk.jpg")
        try Data("jpeg".utf8).write(to: banner)
        let list = try titleList(banner: banner)
        let store = ArtworkStore(
            directory: root.appending(path: "Banners"), titleList: list, allowsFileURLs: true)

        let got = await store.fetch(["0100F2C0115B6000", "01007EF00011E000"])
        #expect(Array(got.keys) == ["0100F2C0115B6000"])  // the other has no banner
        #expect(try Data(contentsOf: #require(got["0100F2C0115B6000"])) == Data("jpeg".utf8))
        #expect(store.cachedBanners().keys.sorted() == ["0100F2C0115B6000"])

        // on disk: nothing to download, not even the list
        try FileManager.default.removeItem(at: list)
        #expect(await store.fetch(["0100F2C0115B6000"]).isEmpty)
        #expect(store.cachedBanners().count == 1)
    }

    @Test func takesImagesOnlyFromNintendosCDN() async throws {
        let list = try titleList(banner: root.appending(path: "missing.jpg"))
        let store = ArtworkStore(directory: root.appending(path: "Banners"), titleList: list)
        // a file URL and another host: neither is downloaded
        #expect(await store.fetch(["0100F2C0115B6000", "010093801237C000"]).isEmpty)
    }

    @Test func aTitleListedTwiceTakesItsLowestNsuidsBanner() throws {
        let banners = try #require(
            ArtworkStore.banners(
                fromTitleList: Data(contentsOf: titleList(banner: URL(filePath: "/first.jpg")))))
        #expect(banners["0100F2C0115B6000"] == "file:///first.jpg")
        #expect(banners["01007EF00011E000"] == nil)
    }
}
