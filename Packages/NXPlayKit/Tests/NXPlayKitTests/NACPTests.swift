import Foundation
import Testing

@testable import NXPlayKit

@Suite struct NACPTests {
    static func nacp(
        title: String, publisher: String = "Nintendo", version: String, language: Int = 0,
        languageFlags: UInt32 = 0
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x4000)
        func put(_ text: String, at offset: Int) {
            bytes.replaceSubrange(offset..<offset + text.utf8.count, with: Array(text.utf8))
        }
        put(title, at: language * 0x300)
        put(publisher, at: language * 0x300 + 0x200)
        put(version, at: 0x3060)
        for i in 0..<4 { bytes[0x302C + i] = UInt8(truncatingIfNeeded: languageFlags >> (8 * i)) }
        return Data(bytes)
    }

    @Test func readsTheSupportedLanguages() {
        // bits 0 (en-US), 2 (ja), 14 (zh-Hans)
        let nacp = NACP(
            data: Self.nacp(title: "T", version: "1", languageFlags: 1 | 1 << 2 | 1 << 14))
        #expect(nacp?.languages == ["en-US", "ja", "zh-Hans"])
    }

    @Test func choosesThePreferredLanguageOrItsRegionalTwin() {
        func game(_ languages: [String]) -> Game {
            Game(
                folder: URL(filePath: "/g"), name: "G", titleID: nil, version: nil,
                languages: languages,
                iconURL: nil, buildFolder: nil, ipaURL: nil, hasPackages: true, state: .ready)
        }
        #expect(GameLanguage.choose("ja", for: game(["en-US", "ja"])) == "ja")
        #expect(GameLanguage.choose("en-US", for: game(["en-GB", "fr"])) == "en-GB")
        #expect(GameLanguage.choose("ko", for: game(["en-US"])) == nil)
        #expect(GameLanguage.choose("ko", for: game([])) == "ko")
        #expect(GameLanguage.choose("", for: game(["ja"])) == nil)
    }

    @Test func readsTitlePublisherAndVersion() throws {
        let nacp = try #require(NACP(data: Self.nacp(title: "Metroid Dread", version: "2.1.0")))
        #expect(nacp.title == "Metroid Dread")
        #expect(nacp.publisher == "Nintendo")
        #expect(nacp.displayVersion == "2.1.0")
    }

    @Test func takesTheFirstLanguageWithAName() {
        #expect(
            NACP(data: Self.nacp(title: "メトロイド", version: "1.0.0", language: 2))?.title == "メトロイド")
    }

    @Test func rejectsShortData() {
        #expect(NACP(data: Data(count: 0x100)) == nil)
    }
}
