import Foundation
import Testing

@testable import NXPlayKit

@Suite struct NACPTests {
    static func nacp(
        title: String, publisher: String = "Nintendo", version: String, language: Int = 0
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x4000)
        func put(_ text: String, at offset: Int) {
            bytes.replaceSubrange(offset..<offset + text.utf8.count, with: Array(text.utf8))
        }
        put(title, at: language * 0x300)
        put(publisher, at: language * 0x300 + 0x200)
        put(version, at: 0x3060)
        return Data(bytes)
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
