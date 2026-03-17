import Testing
@testable import jusText

@Suite("Classifier")
struct TestClassifier {

    private func makeP(domPath: String = "body.div.p") -> Paragraph {
        Paragraph(domPath: domPath, xpath: "/body[1]/div[1]/p[1]")
    }

    private func classify(_ p: Paragraph, stoplist: Set<String> = [], options: ClassifierOptions = ClassifierOptions()) -> ParagraphClass {
        classifyParagraphs([p], stoplist: stoplist, options: options)
        return p.cfClass
    }

    // --- Context-free branches ---

    @Test func testHighLinkDensity() throws {
        let p = makeP()
        // Force high link density: all chars are link chars
        p.textNodes = ["click here now"]
        p.charsCountInLinks = 14  // length of "click here now"
        let cls = classify(p)
        #expect(cls == .bad)
    }

    @Test func testCopyrightSymbol() throws {
        let p = makeP()
        p.textNodes = [String(repeating: "word ", count: 20) + "\u{00A9}"]
        let cls = classify(p)
        #expect(cls == .bad)
    }

    @Test func testSelectDomPath() throws {
        let p = Paragraph(domPath: "body.select.option", xpath: "/body[1]/select[1]/option[1]")
        p.textNodes = [String(repeating: "word ", count: 20)]
        let cls = classify(p)
        #expect(cls == .bad)
    }

    @Test func testShortWithNoLinks() throws {
        let p = makeP()
        p.textNodes = ["short"]  // length < 70
        let cls = classify(p)
        #expect(cls == .short)
    }

    @Test func testShortWithLinks() throws {
        let p = makeP()
        p.textNodes = ["short"]
        p.charsCountInLinks = 1
        let cls = classify(p)
        #expect(cls == .bad)
    }

    @Test func testGoodHighStopwordsLongText() throws {
        let p = makeP()
        // Build text with >lengthHigh chars and many stopwords
        let stoplist: Set<String> = ["the", "a", "and", "of", "in"]
        // Make ~210 char text that's mostly stopwords
        let words = Array(repeating: "the", count: 50) + Array(repeating: "word", count: 10)
        p.textNodes = [words.joined(separator: " ")]  // > 200 chars, high stopword density
        let options = ClassifierOptions()
        classifyParagraphs([p], stoplist: stoplist, options: options)
        #expect(p.cfClass == .good)
    }

    @Test func testNearGoodHighStopwordsShortText() throws {
        let p = makeP()
        let stoplist: Set<String> = ["the", "a", "and"]
        // Text between lengthLow and lengthHigh with high stopword density
        let words = Array(repeating: "the", count: 20) + Array(repeating: "word", count: 5)
        p.textNodes = [words.joined(separator: " ")]
        classifyParagraphs([p], stoplist: stoplist, options: ClassifierOptions())
        #expect(p.cfClass == .nearGood)
    }

    // --- Context-sensitive ---

    @Test func testShortBetweenTwoGoods() throws {
        let p1 = makeP()
        let p2 = makeP()
        let p3 = makeP()
        // p1 = good, p2 = short, p3 = good
        p1.cfClass = .good; p1.classType = .good
        p2.cfClass = .short; p2.classType = .short
        p3.cfClass = .good; p3.classType = .good
        let paragraphs = [p1, p2, p3]
        reviseParagraphClassification(paragraphs, maxHeadingDistance: 200)
        #expect(p2.classType == .good)
    }

    @Test func testShortBetweenTwoBads() throws {
        let p1 = makeP()
        let p2 = makeP()
        let p3 = makeP()
        p1.cfClass = .bad; p1.classType = .bad
        p2.cfClass = .short; p2.classType = .short
        p3.cfClass = .bad; p3.classType = .bad
        let paragraphs = [p1, p2, p3]
        reviseParagraphClassification(paragraphs, maxHeadingDistance: 200)
        #expect(p2.classType == .bad)
    }

    // --- Boilerplate keywords ---

    @Test func testBoilerplateKeywordForcesBad() throws {
        let p = makeP()
        // High stopword density text that would normally be classified as good
        let stoplist: Set<String> = ["the", "a", "and", "of", "in"]
        let words = Array(repeating: "the", count: 50) + Array(repeating: "word", count: 10)
        p.textNodes = [words.joined(separator: " ") + " sign up for our newsletter"]
        var options = ClassifierOptions()
        options.boilerplateKeywords = ["sign up for our newsletter"]
        classifyParagraphs([p], stoplist: stoplist, options: options)
        #expect(p.cfClass == .bad)
    }

    @Test func testBoilerplateKeywordCaseInsensitive() throws {
        let p = makeP()
        let stoplist: Set<String> = ["the", "a", "and", "of", "in"]
        let words = Array(repeating: "the", count: 50) + Array(repeating: "word", count: 10)
        p.textNodes = [words.joined(separator: " ") + " SIGN UP FOR OUR NEWSLETTER"]
        var options = ClassifierOptions()
        options.boilerplateKeywords = ["sign up for our newsletter"]
        classifyParagraphs([p], stoplist: stoplist, options: options)
        #expect(p.cfClass == .bad)
    }

    @Test func testEmptyBoilerplateKeywordsNoEffect() throws {
        let p = makeP()
        let stoplist: Set<String> = ["the", "a", "and", "of", "in"]
        let words = Array(repeating: "the", count: 50) + Array(repeating: "word", count: 10)
        p.textNodes = [words.joined(separator: " ")]
        let options = ClassifierOptions()
        // Default empty keywords — should classify as good normally
        classifyParagraphs([p], stoplist: stoplist, options: options)
        #expect(p.cfClass == .good)
    }

    @Test func testKeywordBadDemotesAdjacentShort() throws {
        // keyword-matched bad → short → genuine bad  ⟹  short becomes bad
        let p1 = makeP()
        let p2 = makeP()
        let p3 = makeP()
        // p1: keyword-forced bad
        p1.cfClass = .bad; p1.classType = .bad
        // p2: short paragraph
        p2.cfClass = .short; p2.classType = .short
        // p3: genuine bad
        p3.cfClass = .bad; p3.classType = .bad
        reviseParagraphClassification([p1, p2, p3], maxHeadingDistance: 200)
        #expect(p2.classType == .bad)
    }

    // --- Computed density storage ---

    @Test func testComputedDensitiesStored() throws {
        let p = makeP()
        let stoplist: Set<String> = ["the", "a"]
        p.textNodes = ["the a word other"]
        p.charsCountInLinks = 3
        classifyParagraphs([p], stoplist: stoplist, options: ClassifierOptions())
        #expect(p.computedStopwordDensity == 0.5)  // 2 stopwords / 4 words
        #expect(p.computedLinkDensity == 3.0 / 16.0)  // 3 link chars / 16 total chars
    }
}
