import Testing
@testable import jusText

@Suite("Integration")
struct TestIntegration {

    private let sampleHTML = """
    <!DOCTYPE html>
    <html>
    <head><title>Test Page</title></head>
    <body>
    <nav><a href="/">Home</a> | <a href="/about">About</a> | <a href="/contact">Contact</a></nav>
    <header><h1>Article Title</h1></header>
    <main>
      <article>
        <p>This is the first paragraph of the main article content. It contains many words
        and has a good amount of text that should be classified as good content by the
        jusText algorithm because it has sufficient length and meaningful words.</p>
        <p>Here is another substantial paragraph in the article body. The content here
        discusses a topic in detail and provides useful information to the reader. This
        kind of content is what jusText is designed to extract from web pages, filtering
        out navigation, headers, and other boilerplate elements that surround it.</p>
      </article>
    </main>
    <footer>
      <a href="/privacy">Privacy Policy</a> |
      <a href="/terms">Terms of Service</a> |
      <a href="/sitemap">Sitemap</a>
    </footer>
    </body>
    </html>
    """

    @Test func testFullPipelineEnglish() throws {
        let paragraphs = try justext(htmlText: sampleHTML, language: "English")
        #expect(!paragraphs.isEmpty)

        // Nav links should be boilerplate (bad — high link density)
        let navParagraphs = paragraphs.filter { $0.domPath.contains("nav") }
        for p in navParagraphs {
            #expect(p.isBoilerplate, "Nav paragraph should be boilerplate: \(p.text)")
        }

        // Footer links should be boilerplate
        let footerParagraphs = paragraphs.filter { $0.domPath.contains("footer") }
        for p in footerParagraphs {
            #expect(p.isBoilerplate, "Footer paragraph should be boilerplate: \(p.text)")
        }

        // Main article paragraphs should be good content
        let goodParagraphs = paragraphs.filter { !$0.isBoilerplate }
        #expect(!goodParagraphs.isEmpty, "Should have at least one good paragraph")
    }

    @Test func testStoplistLoading() throws {
        let stoplists = getStoplists()
        #expect(stoplists.count == 100)
        #expect(stoplists.contains("English"))
        #expect(stoplists.contains("German"))
        #expect(stoplists.contains("French"))
    }

    @Test func testMissingStoplistThrows() throws {
        #expect(throws: JusTextError.missingStoplist("Klingon")) {
            _ = try getStoplist("Klingon")
        }
    }

    @Test func testCustomStoplist() throws {
        let stoplist: Set<String> = ["the", "a", "and", "of", "in", "is", "that", "this",
                                      "are", "for", "to", "it", "with", "by", "from", "or"]
        let paragraphs = try justext(htmlText: sampleHTML, stoplist: stoplist)
        #expect(!paragraphs.isEmpty)
        let goodParagraphs = paragraphs.filter { !$0.isBoilerplate }
        #expect(!goodParagraphs.isEmpty)
    }

    @Test func testEmptyHTML() throws {
        let paragraphs = try justext(htmlText: "<html><body></body></html>", language: "English")
        #expect(paragraphs.isEmpty)
    }
}
