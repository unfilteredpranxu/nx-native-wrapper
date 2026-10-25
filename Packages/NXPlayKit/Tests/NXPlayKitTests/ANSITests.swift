import Testing

@testable import NXPlayKit

@Suite struct ANSITests {
    private func style(_ build: (inout ANSIStyle) -> Void) -> ANSIStyle {
        var style = ANSIStyle()
        build(&style)
        return style
    }

    @Test func gitDiffstat() {
        var parser = ANSIParser()
        let line = parser.parse(" README.md | 35 \u{1B}[1;32m+\u{1B}[m\u{1B}[1;31m-\u{1B}[m")
        #expect(line.text == " README.md | 35 +-")
        #expect(
            line.segments == [
                .init(text: " README.md | 35 ", style: ANSIStyle()),
                .init(
                    text: "+",
                    style: style {
                        $0.bold = true
                        $0.foreground = .standard(2)
                    }),
                .init(
                    text: "-",
                    style: style {
                        $0.bold = true
                        $0.foreground = .standard(1)
                    }),
            ])
        #expect(parser.style.isPlain)
    }

    @Test func plainLinesStayUnsegmented() {
        var parser = ANSIParser()
        #expect(parser.parse("Already up to date.") == LogLine("Already up to date."))
        #expect(parser.parse("\u{1B}[0mreset only").segments.isEmpty)
    }

    @Test func aStyleCarriesToTheNextLine() {
        var parser = ANSIParser()
        _ = parser.parse("\u{1B}[33mwarning: one")
        let next = parser.parse("two\u{1B}[0m three")
        #expect(
            next.segments.first == .init(text: "two", style: style { $0.foreground = .standard(3) })
        )
        #expect(next.segments.last == .init(text: " three", style: ANSIStyle()))
    }

    @Test func extendedColorsAndOffSwitches() {
        var parser = ANSIParser()
        let line = parser.parse("\u{1B}[38;5;208;48;2;10;20;30;4ma\u{1B}[24;39mb\u{1B}[96;101mc")
        #expect(
            line.segments.map(\.style) == [
                style {
                    $0.foreground = .palette(208)
                    $0.background = .rgb(10, 20, 30)
                    $0.underline = true
                },
                style { $0.background = .rgb(10, 20, 30) },
                style {
                    $0.foreground = .standard(14)
                    $0.background = .standard(9)
                },
            ])
        #expect(parser.parse("\u{1B}[38:5:3mx").segments.first?.style.foreground == .standard(3))
    }

    @Test func otherSequencesAreDropped() {
        var parser = ANSIParser()
        let line = parser.parse("\u{1B}]0;title\u{07}\u{1B}[2K\u{1B}[1Gdone\u{07}\tok\u{1B}=")
        #expect(line.text == "done\tok")
        #expect(line.segments.isEmpty)
    }
}
