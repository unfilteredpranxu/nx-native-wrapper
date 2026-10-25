import Foundation

/// The parts of a Switch control.nacp the library uses: 16 language entries of name (0x200 bytes)
/// + publisher (0x100 bytes), the supported-language bits at 0x302C and the display version at 0x3060.
public struct NACP: Equatable, Sendable {
    public let title: String?
    public let publisher: String?
    public let displayVersion: String?
    /// Language codes the game supports, in GameLanguage order; empty when the control data lists none.
    public let languages: [String]

    static let entrySize = 0x300
    static let entryCount = 16
    static let languageFlagsOffset = 0x302C
    static let displayVersionOffset = 0x3060

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.displayVersionOffset + 0x10 else { return nil }
        // the first language with a name: American English when the game has it
        let entry = (0..<Self.entryCount).lazy
            .map { $0 * Self.entrySize }
            .map { (Self.string(bytes, $0, 0x200), Self.string(bytes, $0 + 0x200, 0x100)) }
            .first { $0.0 != nil }
        title = entry?.0
        publisher = entry?.1
        displayVersion = Self.string(bytes, Self.displayVersionOffset, 0x10)
        let flags = (0..<4).reduce(UInt32(0)) {
            $0 | UInt32(bytes[Self.languageFlagsOffset + $1]) << (8 * $1)
        }
        languages = GameLanguage.all.enumerated().filter { flags >> $0.offset & 1 == 1 }.map(
            \.element.code)
    }

    public init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    static func string(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> String? {
        let field = bytes[offset..<offset + length]
        let end = field.firstIndex(of: 0) ?? field.endIndex
        let text = String(decoding: bytes[offset..<end], as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
