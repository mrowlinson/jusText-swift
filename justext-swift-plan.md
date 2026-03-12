# JusText Swift Port — Implementation Plan

## Overview

Port the Python [jusText](https://github.com/miso-belica/jusText) library (v3.0.2) to Swift as a Swift Package called `JusText`. jusText is a heuristic-based boilerplate removal tool that extracts main content from HTML pages by classifying text blocks as "good" (content) or "bad" (boilerplate) using stopword density, link density, block length, and context-sensitive neighbor analysis.

The Python codebase is small (~350 lines of core logic across 4 files) but has a critical dependency on `lxml` for HTML parsing and SAX event generation. The Swift port will use `SwiftSoup` (a pure-Swift HTML parser, similar to JSoup) as the HTML parsing backend.

**License**: The original is BSD-2-Clause. Preserve attribution in all files.

---

## Architecture: Python → Swift Mapping

```
Python                          Swift
─────────────────────────────── ──────────────────────────────────
justext/paragraph.py            Sources/JusText/Paragraph.swift
justext/utils.py                Sources/JusText/Utils.swift
justext/core.py                 Sources/JusText/Core.swift
                                Sources/JusText/ParagraphMaker.swift
                                Sources/JusText/Classifier.swift
justext/__init__.py             Sources/JusText/JusText.swift (public API)
justext/stoplists/*.txt         Sources/JusText/Resources/Stoplists/*.txt
justext/__main__.py             (skip CLI — library only)
tests/                          Tests/JusTextTests/
```

---

## Step-by-step Implementation

### Step 1: Create the Swift Package scaffold

```bash
mkdir JusText && cd JusText
swift package init --name JusText --type library
```

Edit `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JusText",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "JusText", targets: ["JusText"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "JusText",
            dependencies: ["SwiftSoup"],
            resources: [.copy("Resources/Stoplists")]
        ),
        .testTarget(
            name: "JusTextTests",
            dependencies: ["JusText"]
        ),
    ]
)
```

Copy all 100 stoplist `.txt` files from the Python repo's `justext/stoplists/` directory into `Sources/JusText/Resources/Stoplists/`.

---

### Step 2: `Paragraph.swift` — The Paragraph Model

Port `justext/paragraph.py`. This is a data class holding per-block metrics.

```swift
import Foundation

/// Classification states for a paragraph
public enum ParagraphClass: String, Sendable {
    case good
    case bad
    case short
    case nearGood = "neargood"
}

/// Represents one text block extracted from HTML.
public final class Paragraph: @unchecked Sendable {
    public let domPath: String       // e.g. "body.div.p"
    public let xpath: String         // e.g. "/body[1]/div[2]/p[1]"

    public internal(set) var textNodes: [String] = []
    public internal(set) var charsCountInLinks: Int = 0
    public internal(set) var tagsCount: Int = 0

    /// Context-free class assigned during first pass
    public internal(set) var cfClass: ParagraphClass = .bad
    /// Final class after context-sensitive revision
    public internal(set) var classType: ParagraphClass = .bad
    /// Whether this paragraph is inside a heading tag
    public internal(set) var heading: Bool = false

    public var isBoilerplate: Bool { classType != .good }

    public var isHeading: Bool {
        domPath.range(of: #"\bh\d\b"#, options: .regularExpression) != nil
    }

    public var text: String {
        let joined = textNodes.joined()
        return normalizeWhitespace(joined.trimmingCharacters(in: .whitespaces))
    }

    /// Character count of the normalized text
    public var length: Int { text.count }

    public var wordsCount: Int { text.split(separator: " ").count }

    public func containsText() -> Bool { !textNodes.isEmpty }

    @discardableResult
    public func appendText(_ text: String) -> String {
        let normalized = normalizeWhitespace(text)
        textNodes.append(normalized)
        return normalized
    }

    public func stopwordsCount(_ stopwords: Set<String>) -> Int {
        text.split(separator: " ").filter { stopwords.contains($0.lowercased()) }.count
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
```

Key differences from Python:
- Uses an enum for class types instead of raw strings
- `text` is a computed property (same as Python's `@property`)
- `length` replaces Python's `__len__`

---

### Step 3: `Utils.swift` — Whitespace normalization and stoplist loading

Port `justext/utils.py`.

```swift
import Foundation

/// Normalize runs of whitespace: if a run contains \n or \r, collapse to \n; otherwise collapse to space.
func normalizeWhitespace(_ text: String) -> String {
    // Use regex replacement matching \s+ runs
    // If the match contains a newline, replace with \n, else space
    let regex = try! NSRegularExpression(pattern: "\\s+", options: [])
    let range = NSRange(text.startIndex..., in: text)
    var result = text
    // Process matches in reverse to preserve indices
    let matches = regex.matches(in: text, range: range).reversed()
    for match in matches {
        guard let matchRange = Range(match.range, in: result) else { continue }
        let matched = String(result[matchRange])
        let replacement = (matched.contains("\n") || matched.contains("\r")) ? "\n" : " "
        result.replaceSubrange(matchRange, with: replacement)
    }
    return result
}

func isBlank(_ string: String) -> Bool {
    string.isEmpty || string.allSatisfy(\.isWhitespace)
}

/// Returns the set of available built-in stoplist language names.
public func getStoplists() -> Set<String> {
    guard let url = Bundle.module.url(forResource: "Stoplists", withExtension: nil) else {
        return []
    }
    let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    return Set(files.compactMap { file in
        file.pathExtension == "txt" ? file.deletingPathExtension().lastPathComponent : nil
    })
}

/// Load a built-in stoplist by language name (e.g. "English").
/// Returns a Set of lowercased stopwords.
public func getStoplist(_ language: String) throws -> Set<String> {
    guard let url = Bundle.module.url(forResource: language, withExtension: "txt", subdirectory: "Stoplists") else {
        throw JusTextError.missingStoplist(language)
    }
    let data = try String(contentsOf: url, encoding: .utf8)
    return Set(data.components(separatedBy: .newlines).map { $0.lowercased() }.filter { !$0.isEmpty })
}
```

---

### Step 4: `ParagraphMaker.swift` — HTML DOM → Paragraph list

This is the trickiest part. The Python version uses `lxml.sax.saxify()` to walk the DOM and emit SAX events to a `ContentHandler`. In Swift with SwiftSoup, we walk the DOM tree directly using a recursive visitor or SwiftSoup's `NodeVisitor` protocol.

Port the `ParagraphMaker` class and `PathInfo` class from `justext/core.py` (lines 133–234).

```swift
import SwiftSoup

/// Tracks the current DOM path during tree walking.
struct PathInfo {
    private var elements: [(tag: String, order: Int, children: [String: Int])] = []

    var dom: String {
        elements.map(\.tag).joined(separator: ".")
    }

    var xpath: String {
        "/" + elements.map { "\($0.tag)[\($0.order)]" }.joined(separator: "/")
    }

    mutating func append(_ tagName: String) {
        var children = elements.last?.children ?? [:]
        let order = (children[tagName] ?? 0) + 1
        children[tagName] = order

        // Update parent's children dict
        if !elements.isEmpty {
            elements[elements.count - 1].children[tagName] = order
        }

        elements.append((tag: tagName, order: order, children: [:]))
    }

    mutating func pop() {
        elements.removeLast()
    }
}

/// Block-level tags that trigger paragraph breaks (matches Python's PARAGRAPH_TAGS)
let paragraphTags: Set<String> = [
    "body", "blockquote", "caption", "center", "col", "colgroup", "dd",
    "div", "dl", "dt", "fieldset", "form", "legend", "optgroup", "option",
    "p", "pre", "table", "td", "textarea", "tfoot", "th", "thead", "tr",
    "ul", "li", "h1", "h2", "h3", "h4", "h5", "h6"
]
```

The `ParagraphMaker` itself should implement `NodeVisitor` from SwiftSoup:

```swift
final class ParagraphMaker: NodeVisitor {
    private var path = PathInfo()
    private(set) var paragraphs: [Paragraph] = []
    private var current: Paragraph
    private var inLink = false
    private var lastWasBr = false

    init() {
        current = Paragraph(domPath: "", xpath: "/")
    }

    static func makeParagraphs(from root: Element) throws -> [Paragraph] {
        let maker = ParagraphMaker()
        try root.traverse(maker)
        maker.finishCurrentParagraph()
        return maker.paragraphs
    }

    private func finishCurrentParagraph() {
        if current.containsText() {
            paragraphs.append(current)
        }
        current = Paragraph(domPath: path.dom, xpath: path.xpath)
    }

    // NodeVisitor protocol
    func head(_ node: Node, _ depth: Int) throws {
        guard let element = node as? Element else {
            // Text node
            if let textNode = node as? TextNode {
                let text = textNode.getWholeText()
                guard !isBlank(text) else { return }
                let appended = current.appendText(text)
                if inLink {
                    current.charsCountInLinks += appended.count
                }
                lastWasBr = false
            }
            return
        }

        let tag = element.tagName().lowercased()
        path.append(tag)

        if paragraphTags.contains(tag) || (tag == "br" && lastWasBr) {
            if tag == "br" {
                current.tagsCount -= 1
            }
            finishCurrentParagraph()
        } else {
            lastWasBr = (tag == "br")
            if lastWasBr {
                current.appendText(" ")
            } else if tag == "a" {
                inLink = true
            }
            current.tagsCount += 1
        }
    }

    func tail(_ node: Node, _ depth: Int) throws {
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        path.pop()

        if paragraphTags.contains(tag) {
            finishCurrentParagraph()
        }
        if tag == "a" {
            inLink = false
        }
    }
}
```

**Critical note**: SwiftSoup's `NodeVisitor.head()` is called on entering a node and `tail()` on leaving — this maps directly to the Python SAX handler's `startElementNS` and `endElementNS`.

---

### Step 5: `Classifier.swift` — Classification Logic

Port the classification functions from `justext/core.py` (lines 236–372). This is the algorithm's core and should be ported nearly 1:1 since it's pure logic with no library dependencies.

**5a. Context-free classification** (`classify_paragraphs` in Python):

```swift
public struct ClassifierOptions {
    public var maxLinkDensity: Double = 0.2
    public var lengthLow: Int = 70
    public var lengthHigh: Int = 200
    public var stopwordsLow: Double = 0.30
    public var stopwordsHigh: Double = 0.32
    public var maxHeadingDistance: Int = 200
    public var noHeadings: Bool = false

    public init() {}
}
```

Implement `classifyParagraphs(_ paragraphs:, stoplist:, options:)` following the exact decision tree from the Python source (core.py lines 243-275):

1. If `linkDensity > maxLinkDensity` → `.bad`
2. If text contains `©` or `&copy` → `.bad`
3. If dom path contains `select` → `.bad`
4. If `length < lengthLow`:
   - If `charsCountInLinks > 0` → `.bad`
   - Else → `.short`
5. If `stopwordsDensity >= stopwordsHigh`:
   - If `length > lengthHigh` → `.good`
   - Else → `.nearGood`
6. If `stopwordsDensity >= stopwordsLow` → `.nearGood`
7. Else → `.bad`

Also set `paragraph.heading = !noHeadings && paragraph.isHeading`.

**5b. Context-sensitive revision** (`revise_paragraph_classification` in Python):

Port `revise_paragraph_classification` (core.py lines 307-371). This has four phases executed in order:

1. **Heading preprocessing**: Copy `cfClass` → `classType`. For headings that are `.short`, look ahead up to `maxHeadingDistance` characters for a `.good` block; if found, promote to `.nearGood`.

2. **Classify short blocks**: For each `.short` block, find prev/next neighbors (ignoring `.nearGood`). If both neighbors are `.good` → `.good`. If both `.bad` → `.bad`. If mixed, check if there's a `.nearGood` between the block and the `.bad` neighbor; if so → `.good`, else → `.bad`.

3. **Revise nearGood blocks**: For each `.nearGood`, find prev/next neighbors (ignoring `.nearGood`). If both are `.bad` → `.bad`, else → `.good`.

4. **Heading postprocessing**: For headings that ended up `.bad` but whose `cfClass` was NOT `.bad`, look ahead for a nearby `.good` block within `maxHeadingDistance`; if found → `.good`.

The neighbor-finding helper (`_get_neighbour` in Python) walks forward/backward through paragraphs skipping `.short`/`.nearGood` blocks until it finds `.good` or `.bad` (or document edge = `.bad`).

---

### Step 6: `Core.swift` — HTML Preprocessing

Port the `preprocessor()` and `html_to_dom()` functions from `justext/core.py`.

The Python version uses `lxml.html.clean.Cleaner` to strip `<script>`, `<style>`, `<head>`, comments, embedded content, and forms. In Swift with SwiftSoup:

```swift
import SwiftSoup

func preprocessHTML(_ html: String) throws -> Element {
    let doc = try SwiftSoup.parse(html)

    // Remove tags whose content should be stripped entirely
    let tagsToRemove = ["script", "style", "head", "noscript"]
    for tag in tagsToRemove {
        try doc.select(tag).remove()
    }

    // Remove HTML comments
    // (SwiftSoup handles this — comments are not Element nodes and get ignored
    //  during traversal, but explicitly remove if present as Comment nodes)
    func removeComments(_ node: Node) throws {
        for child in node.getChildNodes().reversed() {
            if child is Comment {
                try child.remove()
            } else {
                try removeComments(child)
            }
        }
    }
    try removeComments(doc)

    guard let body = doc.body() else {
        throw JusTextError.noBody
    }

    return body
}
```

**Note**: The Python `Cleaner` also removes `<form>` content and `<embed>`/`<object>` tags. The original code sets `forms: True` and `embedded: True` in the Cleaner. Replicate this by also removing those tags:

```swift
let embeddedTags = ["object", "embed", "applet", "iframe"]
for tag in embeddedTags {
    try doc.select(tag).remove()
}
// Remove form elements
try doc.select("form").remove()
```

---

### Step 7: `JusText.swift` — Public API

The main entry point, equivalent to the `justext()` function in `core.py` (lines 374-393).

```swift
public enum JusTextError: Error {
    case missingStoplist(String)
    case noBody
    case invalidOptions(String)
}

/// Main entry point. Converts HTML into classified paragraphs.
public func justext(
    htmlText: String,
    stoplist: Set<String>,
    options: ClassifierOptions = ClassifierOptions()
) throws -> [Paragraph] {
    // 1. Parse and preprocess HTML
    let body = try preprocessHTML(htmlText)

    // 2. Extract paragraphs by walking DOM
    let paragraphs = try ParagraphMaker.makeParagraphs(from: body)

    // 3. Context-free classification
    classifyParagraphs(paragraphs, stoplist: stoplist, options: options)

    // 4. Context-sensitive revision (includes heading pre/post processing)
    reviseParagraphClassification(paragraphs, maxHeadingDistance: options.maxHeadingDistance)

    return paragraphs
}

/// Convenience: load a built-in stoplist and run justext.
public func justext(
    htmlText: String,
    language: String,
    options: ClassifierOptions = ClassifierOptions()
) throws -> [Paragraph] {
    let stoplist = try getStoplist(language)
    return try justext(htmlText: htmlText, stoplist: stoplist, options: options)
}
```

---

### Step 8: Tests

Port the test files from `tests/`. Key test files to port:

**`TestClassifyParagraphs.swift`** — Port from `tests/test_classify_paragraphs.py`:
- `testMaxLinkDensity` — verify link density threshold
- `testLengthLow` — verify short block classification
- `testStopwordsHigh` — verify good vs neargood split
- `testStopwordsLow` — verify neargood vs bad split

**`TestParagraphMaker.swift`** — Port from `tests/test_sax.py`:
- Test that block-level tags create paragraph breaks
- Test `<br><br>` creates a paragraph break but single `<br>` doesn't
- Test `<a>` tag tracking for link character counts
- Test text node accumulation

**`TestUtils.swift`** — Port from `tests/test_utils.py`:
- Test `normalizeWhitespace` with mixed whitespace and newlines
- Test `isBlank` with empty, whitespace, and non-blank strings

**`TestRevision.swift`** — Port from `tests/test_classify_paragraphs.py` plus additional cases:
- Test context-sensitive reclassification of short blocks between good blocks
- Test heading promotion logic
- Test document-edge handling (edges treated as bad)

**`TestIntegration.swift`** — End-to-end tests:
- Feed a real HTML string, verify known paragraphs come back as good/bad
- Test the copyright symbol detection
- Test `<select>` detection
- Test the complete pipeline with the English stoplist

---

## File Tree (Final)

```
JusText/
├── Package.swift
├── Sources/
│   └── JusText/
│       ├── JusText.swift            # Public API: justext(), JusTextError
│       ├── Core.swift               # preprocessHTML()
│       ├── ParagraphMaker.swift     # ParagraphMaker (NodeVisitor), PathInfo
│       ├── Classifier.swift         # classifyParagraphs(), reviseParagraphClassification()
│       ├── Paragraph.swift          # Paragraph class, ParagraphClass enum
│       ├── Utils.swift              # normalizeWhitespace(), isBlank(), getStoplist()
│       └── Resources/
│           └── Stoplists/           # 100 .txt files copied from Python repo
│               ├── English.txt
│               ├── French.txt
│               └── ... (100 files)
└── Tests/
    └── JusTextTests/
        ├── TestClassifyParagraphs.swift
        ├── TestParagraphMaker.swift
        ├── TestUtils.swift
        ├── TestRevision.swift
        └── TestIntegration.swift
```

---

## Implementation Order

1. **`Package.swift`** + copy stoplists into `Resources/Stoplists/`
2. **`Utils.swift`** — no dependencies, test immediately
3. **`Paragraph.swift`** — depends only on Utils
4. **`ParagraphMaker.swift`** — depends on Paragraph, Utils, SwiftSoup
5. **`Classifier.swift`** — depends only on Paragraph (pure logic, no SwiftSoup)
6. **`Core.swift`** — depends on SwiftSoup for preprocessing
7. **`JusText.swift`** — wires everything together
8. **Tests** — write alongside each step, full integration tests last

---

## Critical Porting Notes

1. **String length semantics**: Python's `len(paragraph.text)` counts Unicode codepoints. Swift's `String.count` also counts Characters (extended grapheme clusters), which is close enough. Use `.count` consistently.

2. **The `lxml.sax.saxify` → SwiftSoup `NodeVisitor` mapping**: The Python SAX handler gets `startElementNS`/`endElementNS`/`characters` callbacks. SwiftSoup's `NodeVisitor` gives you `head(node, depth)` and `tail(node, depth)`. Text nodes appear as `TextNode` in `head()`. The mapping is direct — just check `node is Element` vs `node is TextNode` in the head callback.

3. **The `lxml.html.clean.Cleaner` replacement**: There is no equivalent in SwiftSoup. Manually remove script/style/head/form/embed tags using `doc.select(tag).remove()`. Also manually walk and remove `Comment` nodes.

4. **Copyright symbol check**: The Python code checks for `\xa9` (©) and the string `&copy` in `paragraph.text`. In Swift, check for `"\u{00A9}"` and `"&copy"`. Note: SwiftSoup will have already decoded `&copy;` to `©` in text nodes, so you may only need to check for the unicode character `©` in the normalized text.

5. **Stoplist caching**: Python uses `@lru_cache` on `define_stoplist()`. In Swift, the stoplists are already `Set<String>` — no caching needed since Set lookup is O(1). If you want to cache file loading, use a simple dictionary cache or `NSCache`.

6. **Thread safety**: Mark `Paragraph` and `ClassifierOptions` as `Sendable` where practical. The core algorithm is stateless aside from mutating the paragraph list, so it's straightforward.

7. **No CLI**: Skip porting `__main__.py`. This is a library-only port. If a CLI is wanted later, use `swift-argument-parser`.

8. **Encoding detection**: The Python version has `decode_html()` with charset meta tag sniffing. In Swift, assume the caller provides a `String` (already decoded). If raw `Data` input is needed later, add an overload that accepts `Data` and does charset detection via `String.Encoding` or a regex on the meta tag, same as the Python version.

---

## Reference: Algorithm Summary

The algorithm has 5 phases:

1. **Preprocess** — Remove script/style/head/comments/forms/embeds from DOM
2. **Segment** — Walk DOM, split on block-level tags and `<br><br>` into `Paragraph` objects, tracking text, link chars, tag counts, and DOM path
3. **Context-free classify** — Assign each paragraph to good/bad/short/nearGood based on link density, length, stopword density, copyright/select checks
4. **Context-sensitive revise** — Reclassify short/nearGood blocks based on neighbors; includes heading pre/post processing
5. **Output** — Return paragraphs; caller filters on `paragraph.isBoilerplate`

Default parameters: `maxLinkDensity=0.2, lengthLow=70, lengthHigh=200, stopwordsLow=0.30, stopwordsHigh=0.32, maxHeadingDistance=200, noHeadings=false`.
