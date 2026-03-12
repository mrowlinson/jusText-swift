public enum JusTextError: Error, Sendable, Equatable {
    case missingStoplist(String)
    case noBody
}

/// Main entry point.
public func justext(
    htmlText: String,
    stoplist: Set<String>,
    options: ClassifierOptions = ClassifierOptions()
) throws -> [Paragraph] {
    let body = try preprocessHTML(htmlText)
    let paragraphs = try ParagraphMaker.makeParagraphs(from: body)
    classifyParagraphs(paragraphs, stoplist: stoplist, options: options)
    reviseParagraphClassification(paragraphs, maxHeadingDistance: options.maxHeadingDistance)
    return paragraphs
}

/// Convenience: load built-in stoplist by language name.
public func justext(
    htmlText: String,
    language: String,
    options: ClassifierOptions = ClassifierOptions()
) throws -> [Paragraph] {
    let stoplist = try getStoplist(language)
    return try justext(htmlText: htmlText, stoplist: stoplist, options: options)
}
