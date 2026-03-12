import Foundation

/// Replace runs of whitespace with "\n" if the run contains a newline/carriage-return, else " ".
func normalizeWhitespace(_ string: String) -> String {
    guard !string.isEmpty else { return string }

    // Collect all matches in one pass, then apply in reverse so indices stay valid.
    let pattern = try! NSRegularExpression(pattern: #"\s+"#)
    let nsString = string as NSString
    let range = NSRange(location: 0, length: nsString.length)
    let matches = pattern.matches(in: string, range: range)

    var result = string
    for match in matches.reversed() {
        let matchedText = nsString.substring(with: match.range)
        let replacement = matchedText.contains("\n") || matchedText.contains("\r") ? "\n" : " "
        let swiftRange = Range(match.range, in: result)!
        result.replaceSubrange(swiftRange, with: replacement)
    }
    return result
}

func isBlank(_ string: String) -> Bool {
    string.isEmpty || string.allSatisfy(\.isWhitespace)
}

/// Return the set of available built-in stoplist language names.
public func getStoplists() -> Set<String> {
    guard let url = Bundle.module.url(forResource: "Stoplists", withExtension: nil) else {
        return []
    }
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: nil) else {
        return []
    }
    return Set(contents.compactMap { url -> String? in
        guard url.pathExtension == "txt" else { return nil }
        return url.deletingPathExtension().lastPathComponent
    })
}

/// Load a built-in stoplist by language name (e.g. "English").
public func getStoplist(_ language: String) throws -> Set<String> {
    guard let url = Bundle.module.url(
        forResource: language, withExtension: "txt", subdirectory: "Stoplists") else {
        throw JusTextError.missingStoplist(language)
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    return Set(text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty })
}
