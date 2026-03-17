public enum ParagraphClass: String, Sendable {
    case good, bad, short, nearGood = "neargood"
}

public final class Paragraph: @unchecked Sendable {
    public let domPath: String
    public let xpath: String
    public internal(set) var textNodes: [String] = []
    public internal(set) var charsCountInLinks: Int = 0
    public internal(set) var tagsCount: Int = 0
    public internal(set) var cfClass: ParagraphClass = .bad
    public internal(set) var classType: ParagraphClass = .bad
    public internal(set) var heading: Bool = false
    public internal(set) var computedStopwordDensity: Double = 0
    public internal(set) var computedLinkDensity: Double = 0

    public var isBoilerplate: Bool { classType != .good }

    public var isHeading: Bool {
        domPath.range(of: #"\bh\d\b"#, options: .regularExpression) != nil
    }

    /// Join all textNodes with "", strip leading/trailing whitespace, then normalize whitespace.
    public var text: String {
        let joined = textNodes.joined()
        return normalizeWhitespace(joined.trimmingCharacters(in: .whitespaces))
    }

    /// Character count of the normalized text (mirrors Python's __len__).
    public var length: Int { text.count }

    public var wordsCount: Int { text.split(separator: " ").count }

    public func containsText() -> Bool { !textNodes.isEmpty }

    @discardableResult
    public func appendText(_ s: String) -> String {
        let n = normalizeWhitespace(s)
        textNodes.append(n)
        return n
    }

    public func stopwordsCount(_ stopwords: Set<String>) -> Int {
        text.split(separator: " ").filter { stopwords.contains(String($0).lowercased()) }.count
    }

    public func stopwordsDensity(_ stopwords: Set<String>) -> Double {
        guard wordsCount > 0 else { return 0 }
        return Double(stopwordsCount(stopwords)) / Double(wordsCount)
    }

    public func linksDensity() -> Double {
        guard length > 0 else { return 0 }
        return Double(charsCountInLinks) / Double(length)
    }

    init(domPath: String, xpath: String) {
        self.domPath = domPath
        self.xpath = xpath
    }
}
