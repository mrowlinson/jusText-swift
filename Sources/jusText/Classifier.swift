public struct ClassifierOptions: Sendable {
    public var maxLinkDensity: Double = 0.2
    public var lengthLow: Int = 70
    public var lengthHigh: Int = 200
    public var stopwordsLow: Double = 0.30
    public var stopwordsHigh: Double = 0.32
    public var maxHeadingDistance: Int = 200
    public var noHeadings: Bool = false
    public var boilerplateKeywords: Set<String> = []
    public init() {}
}

/// Context-free classification pass.
public func classifyParagraphs(
    _ paragraphs: [Paragraph],
    stoplist: Set<String>,
    options: ClassifierOptions
) {
    for p in paragraphs {
        let linkDensity = p.linksDensity()
        let text = p.text
        let length = p.length
        let stopwordDensity = p.stopwordsDensity(stoplist)

        let cls: ParagraphClass
        if linkDensity > options.maxLinkDensity {
            cls = .bad
        } else if text.contains("\u{00A9}") || text.contains("&copy") {
            cls = .bad
        } else if p.domPath.contains("select") {
            cls = .bad
        } else if !options.boilerplateKeywords.isEmpty &&
                  options.boilerplateKeywords.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            cls = .bad
        } else if length < options.lengthLow {
            cls = p.charsCountInLinks > 0 ? .bad : .short
        } else if stopwordDensity >= options.stopwordsHigh {
            cls = length > options.lengthHigh ? .good : .nearGood
        } else if stopwordDensity >= options.stopwordsLow {
            cls = .nearGood
        } else {
            cls = .bad
        }

        p.computedLinkDensity = linkDensity
        p.computedStopwordDensity = stopwordDensity
        p.cfClass = cls
        p.classType = cls
        p.heading = !options.noHeadings && p.isHeading
    }
}

private enum Direction { case prev, next }

private func getNeighbour(
    _ i: Int,
    paragraphs: [Paragraph],
    direction: Direction,
    ignoreNearGood: Bool
) -> ParagraphClass {
    var j = direction == .prev ? i - 1 : i + 1
    while j >= 0 && j < paragraphs.count {
        let cls = paragraphs[j].classType
        if cls == .short || (ignoreNearGood && cls == .nearGood) {
            j = direction == .prev ? j - 1 : j + 1
            continue
        }
        return cls
    }
    return .bad
}

/// Context-sensitive revision pass.
public func reviseParagraphClassification(
    _ paragraphs: [Paragraph],
    maxHeadingDistance: Int
) {
    // Phase 1: copy cfClass, promote short headings with a good neighbour nearby
    for i in paragraphs.indices {
        let p = paragraphs[i]
        p.classType = p.cfClass
        if p.heading && p.classType == .short {
            var distance = 0
            var j = i + 1
            while j < paragraphs.count {
                distance += paragraphs[j].text.count
                if paragraphs[j].classType == .good && distance <= maxHeadingDistance {
                    p.classType = .nearGood
                    break
                }
                if distance > maxHeadingDistance { break }
                j += 1
            }
        }
    }

    // Phase 2: classify short paragraphs using neighbour context (stage, then apply)
    var staged: [Int: ParagraphClass] = [:]
    for i in paragraphs.indices where paragraphs[i].classType == .short {
        let prev = getNeighbour(i, paragraphs: paragraphs, direction: .prev, ignoreNearGood: true)
        let next = getNeighbour(i, paragraphs: paragraphs, direction: .next, ignoreNearGood: true)
        if prev == .good && next == .good {
            staged[i] = .good
        } else if prev == .bad && next == .bad {
            staged[i] = .bad
        } else if prev == .bad &&
            getNeighbour(i, paragraphs: paragraphs, direction: .prev, ignoreNearGood: false) == .nearGood {
            staged[i] = .good
        } else if next == .bad &&
            getNeighbour(i, paragraphs: paragraphs, direction: .next, ignoreNearGood: false) == .nearGood {
            staged[i] = .good
        } else {
            staged[i] = .bad
        }
    }
    for (i, cls) in staged { paragraphs[i].classType = cls }

    // Phase 3: revise nearGood paragraphs
    for i in paragraphs.indices where paragraphs[i].classType == .nearGood {
        let prev = getNeighbour(i, paragraphs: paragraphs, direction: .prev, ignoreNearGood: true)
        let next = getNeighbour(i, paragraphs: paragraphs, direction: .next, ignoreNearGood: true)
        paragraphs[i].classType = (prev == .bad && next == .bad) ? .bad : .good
    }

    // Phase 4: more good headings — headings that were bad but aren't cf-bad,
    //           with a good paragraph nearby
    for i in paragraphs.indices {
        let p = paragraphs[i]
        guard p.heading && p.classType == .bad && p.cfClass != .bad else { continue }
        var distance = 0
        var j = i + 1
        while j < paragraphs.count {
            distance += paragraphs[j].text.count
            if paragraphs[j].classType == .good && distance <= maxHeadingDistance {
                p.classType = .good
                break
            }
            if distance > maxHeadingDistance { break }
            j += 1
        }
    }
}
