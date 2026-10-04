import Foundation
@testable import MarkdownPDF
import Testing

/// Oracle: the stripper is a pure function of its input, so each case states the exact
/// output expected from the rule written in ``HTMLCommentStripper``'s documentation:
/// a terminated comment outside code is deleted, a line left empty by a deletion
/// disappears, and everything else is copied byte for byte.
@Suite("HTML comment stripper")
struct HTMLCommentStripperTests {
    @Test("Text without a comment is returned unchanged", arguments: [
        "",
        "plain",
        "# Heading\n\nParagraph.\n",
        "a < b and c > d, <b>bold</b>",
        "trailing newline\n",
        "two\n\n\nblank lines\n",
    ])
    func noCommentIsIdentity(_ text: String) {
        #expect(HTMLCommentStripper.strip(text) == text)
    }

    @Test("A comment inside a line is deleted and the neighbours stay")
    func inlineComment() {
        #expect(HTMLCommentStripper.strip("one<!--say: x-->two") == "onetwo")
        #expect(HTMLCommentStripper.strip("one <!-- x --> two") == "one  two")
        #expect(HTMLCommentStripper.strip("a<!--1-->b<!--2-->c") == "abc")
        #expect(HTMLCommentStripper.strip("<!--x-->start") == "start")
    }

    @Test("A line holding only comments disappears, its neighbours stay adjacent")
    func commentOnlyLine() {
        #expect(HTMLCommentStripper.strip("a\n<!--print-only-->\nb\n") == "a\nb\n")
        #expect(HTMLCommentStripper.strip("a\n  <!--x--> <!--y-->  \nb") == "a\nb")
        #expect(HTMLCommentStripper.strip("<!--x-->") == "")
        #expect(HTMLCommentStripper.strip("<!--x-->\n") == "")
        #expect(HTMLCommentStripper.strip("a\n\n<!--x-->\n\nb") == "a\n\n\nb")
    }

    @Test("A blank line that was already blank is kept")
    func existingBlankLinesStay() {
        #expect(HTMLCommentStripper.strip("a\n\nb<!--x-->\n\nc") == "a\n\nb\n\nc")
    }

    @Test("A comment ending a line also removes the space before it")
    func trailingSpaceBeforeComment() {
        #expect(HTMLCommentStripper.strip("# Title <!--x-->\n") == "# Title\n")
    }

    @Test("A multi-line comment is deleted whole")
    func multiLineComment() {
        #expect(HTMLCommentStripper.strip("a\n<!--\nline one\nline two\n-->\nb") == "a\nb")
        #expect(HTMLCommentStripper.strip("a <!-- one\ntwo --> b") == "a  b")
    }

    @Test("The comment ends at the first terminator")
    func firstTerminatorWins() {
        #expect(HTMLCommentStripper.strip("a<!-- x --> y --> z") == "a y --> z")
        #expect(HTMLCommentStripper.strip("a<!---->b") == "ab")
        #expect(HTMLCommentStripper.strip("a<!-- <!-- nested -->b") == "ab")
    }

    @Test("An unterminated comment is literal text, not a deletion to the end of the file")
    func unterminatedComment() {
        #expect(HTMLCommentStripper.strip("a <!-- never closed\nb") == "a <!-- never closed\nb")
        #expect(HTMLCommentStripper.strip("<!--") == "<!--")
        #expect(HTMLCommentStripper.strip("x<!-->y") == "x<!-->y")
        // Terminated comments before it are still removed.
        #expect(HTMLCommentStripper.strip("<!--a-->b <!-- open") == "b <!-- open")
    }

    @Test("The page break marker survives, in every spelling the parser accepts")
    func pageBreakIsKept() {
        for marker in ["<!-- pagebreak -->", "<!--pagebreak-->", "<!-- pageBreak -->", "<!--  PAGEBREAK  -->"] {
            let text = "a\n\n\(marker)\n\nb"
            #expect(HTMLCommentStripper.strip(text) == text)
        }
        #expect(HTMLCommentStripper.strip("<!-- pagebreak now -->") == "")
    }

    @Test("Comments in inline code spans stay literal")
    func inlineCodeSpans() {
        #expect(HTMLCommentStripper.strip("see `<!--x-->` here") == "see `<!--x-->` here")
        #expect(HTMLCommentStripper.strip("``a <!--x--> `b` ``<!--y-->") == "``a <!--x--> `b` ``")
        #expect(HTMLCommentStripper.strip("`one`<!--x-->`two`") == "`one``two`")
    }

    @Test("A code span can cross a line but not a blank line")
    func codeSpanAcrossLines() {
        #expect(HTMLCommentStripper.strip("`a\n<!--x-->` b") == "`a\n<!--x-->` b")
        // The backtick never closes inside its paragraph, so it is plain text.
        #expect(HTMLCommentStripper.strip("`a <!--x-->\n\nb`") == "`a\n\nb`")
    }

    @Test("A backtick run opens a span only for a run of the same length")
    func backtickRunLength() {
        #expect(HTMLCommentStripper.strip("``a ` <!--x--> b``") == "``a ` <!--x--> b``")
        #expect(HTMLCommentStripper.strip("`a <!--x--> ``b`` c") == "`a  ``b`` c")
    }

    @Test("A backslash-escaped marker is not a comment, and an escaped backtick opens no span")
    func escapes() {
        #expect(HTMLCommentStripper.strip(#"\<!--x-->"#) == #"\<!--x-->"#)
        #expect(HTMLCommentStripper.strip(#"\`<!--x-->`"#) == #"\`"# + "`")
    }

    @Test("Fenced code blocks are copied verbatim, with both fence characters")
    func fencedBlocks() {
        let backtick = "a\n```html\n<!-- keep -->\n<!--\nmulti\n-->\n```\n<!--drop-->\nb"
        #expect(HTMLCommentStripper.strip(backtick) == "a\n```html\n<!-- keep -->\n<!--\nmulti\n-->\n```\nb")
        let tilde = "~~~\n<!-- keep -->\n~~~\n<!-- drop -->x"
        #expect(HTMLCommentStripper.strip(tilde) == "~~~\n<!-- keep -->\n~~~\nx")
    }

    @Test("An unclosed fence keeps everything after it, as the parser does")
    func unclosedFence() {
        #expect(HTMLCommentStripper.strip("```\n<!-- keep -->\nmore") == "```\n<!-- keep -->\nmore")
    }

    @Test("A fence inside a block quote or a list item protects its content")
    func fencesInContainers() {
        #expect(HTMLCommentStripper.strip("> ```\n> <!-- keep -->\n> ```\n<!--x-->y") == "> ```\n> <!-- keep -->\n> ```\ny")
        #expect(HTMLCommentStripper.strip("- ```\n  <!-- keep -->\n  ```\n- a<!--x-->") == "- ```\n  <!-- keep -->\n  ```\n- a")
        #expect(HTMLCommentStripper.strip("1. ```\n   <!-- keep -->\n   ```") == "1. ```\n   <!-- keep -->\n   ```")
    }

    @Test("Comments in lists, tables and headings are removed from the cell or item only")
    func containers() {
        #expect(HTMLCommentStripper.strip("- a<!--x-->\n- <!--y-->b") == "- a\n- b")
        #expect(HTMLCommentStripper.strip("| a<!--x--> | b |\n|---|---|\n| <!--y-->c | d |") == "| a | b |\n|---|---|\n| c | d |")
        #expect(HTMLCommentStripper.strip("## Part <!--x--> two") == "## Part  two")
        #expect(HTMLCommentStripper.strip("> quote<!--x--> text") == "> quote text")
    }

    @Test("Marker pairs drop the markers and keep what is between them")
    func markerPairs() {
        let text = "Before.\n\n<!--print-only-->\n| a | b |\n|---|---|\n| 1 | 2 |\n<!--/print-only-->\n\nAfter."
        #expect(HTMLCommentStripper.strip(text) == "Before.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter.")
    }

    @Test("Windows and old Mac line endings are normalized to newlines")
    func lineEndings() {
        #expect(HTMLCommentStripper.strip("a\r\n<!--x-->\r\nb") == "a\nb")
        #expect(HTMLCommentStripper.strip("a\r<!--x-->\rb") == "a\nb")
    }

    @Test("Non-ASCII text and surrogate-range scalars survive")
    func unicode() {
        #expect(HTMLCommentStripper.strip("caf\u{E9}<!--x--> \u{1F600} \u{3053}\u{3093}") == "caf\u{E9} \u{1F600} \u{3053}\u{3093}")
    }

    @Test("A long document with many comments is linear, not quadratic")
    func scales() {
        let line = "word <!--say: w--> word `<!--k-->` word\n"
        let input = String(repeating: line, count: 20000)
        let expected = String(repeating: "word  word `<!--k-->` word\n", count: 20000)
        #expect(HTMLCommentStripper.strip(input) == expected)
    }
}
