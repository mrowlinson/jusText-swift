import Testing
import SwiftSoup
@testable import jusText

@Suite("ParagraphMaker")
struct TestParagraphMaker {

    private func makeParagraphs(html: String) throws -> [Paragraph] {
        let body = try preprocessHTML(html)
        return try ParagraphMaker.makeParagraphs(from: body)
    }

    @Test func testNoParagraphs() throws {
        let paragraphs = try makeParagraphs(html: "<html><body></body></html>")
        #expect(paragraphs.count == 0)
    }

    @Test func testBasic() throws {
        // h1 + p (with em and span inline) + p  →  3 paragraphs
        let html = """
        <html><body>
        <h1>Header</h1>
        <p><em>text</em> and <span>some other words</span> that I have in my head now</p>
        <p>Second paragraph</p>
        </body></html>
        """
        let paragraphs = try makeParagraphs(html: html)
        #expect(paragraphs.count == 3)

        let h1 = paragraphs[0]
        #expect(h1.text == "Header")
        #expect(h1.wordsCount == 1)
        // h1 is a paragraphTag so it's not counted in tagsCount; em and span are counted
        // but the h1 itself is not, so tagsCount should be 0 for h1 text (no inline tags in h1)
        #expect(h1.tagsCount == 0)

        let p1 = paragraphs[1]
        #expect(p1.text == "text and some other words that I have in my head now")
        #expect(p1.wordsCount == 12)
        // em and span are inline tags, each counted once
        #expect(p1.tagsCount == 2)
    }

    @Test func testWhitespaceHandling() throws {
        // Adjacent inline elements should not have extra spaces inserted between them
        let html = "<html><body><p><span>pre</span><span>in</span><span>post</span></p></body></html>"
        let paragraphs = try makeParagraphs(html: html)
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "preinpost")
    }

    @Test func testMultipleLineBreak() throws {
        // <br><br> should create two paragraphs
        let html = "<html><body><p>First<br><br>Second</p></body></html>"
        let paragraphs = try makeParagraphs(html: html)
        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].text == "First")
        #expect(paragraphs[1].text == "Second")
    }

    @Test func testLinks() throws {
        let html = """
        <html><body><p>Visit <a href="#">click here</a> for more.</p></body></html>
        """
        let paragraphs = try makeParagraphs(html: html)
        #expect(paragraphs.count == 1)
        let p = paragraphs[0]
        // "click here" is 10 chars; link chars should be counted
        #expect(p.charsCountInLinks == 10)
    }
}
