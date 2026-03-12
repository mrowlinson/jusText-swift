import SwiftSoup

private let paragraphTags: Set<String> = [
    "body", "blockquote", "caption", "center", "col", "colgroup",
    "dd", "div", "dl", "dt", "fieldset", "form", "legend",
    "optgroup", "option", "p", "pre", "table", "td", "textarea",
    "tfoot", "th", "thead", "tr", "ul", "li",
    "h1", "h2", "h3", "h4", "h5", "h6"
]

private struct PathInfo {
    private var elements: [(tag: String, order: Int, children: [String: Int])] = []

    var dom: String { elements.map(\.tag).joined(separator: ".") }

    var xpath: String {
        "/" + elements.map { "\($0.tag)[\($0.order)]" }.joined(separator: "/")
    }

    mutating func append(_ tagName: String) {
        let count = elements.isEmpty ? 0 : (elements[elements.count - 1].children[tagName] ?? 0)
        let order = count + 1
        if !elements.isEmpty {
            elements[elements.count - 1].children[tagName] = order
        }
        elements.append((tag: tagName, order: order, children: [:]))
    }

    mutating func pop() {
        if !elements.isEmpty { elements.removeLast() }
    }
}

private final class ParagraphMakerVisitor: NodeVisitor {
    var paragraphs: [Paragraph] = []
    private var current: Paragraph
    private var path = PathInfo()
    private var br = false
    private var inLink = false

    init() {
        current = Paragraph(domPath: "", xpath: "")
    }

    func head(_ node: Node, _ depth: Int) throws {
        if let textNode = node as? TextNode {
            let text = textNode.text()
            guard !isBlank(text) else { return }
            let appended = current.appendText(text)
            if inLink { current.charsCountInLinks += appended.count }
            br = false
            return
        }

        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        path.append(tag)

        if paragraphTags.contains(tag) || (tag == "br" && br) {
            if tag == "br" { current.tagsCount -= 1 }
            startNewParagraph()
        } else {
            br = (tag == "br")
            if br {
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
            startNewParagraph()
        }
        if tag == "a" { inLink = false }
    }

    private func startNewParagraph() {
        if current.containsText() {
            paragraphs.append(current)
        }
        current = Paragraph(domPath: path.dom, xpath: path.xpath)
    }

    func finish() {
        if current.containsText() {
            paragraphs.append(current)
        }
    }
}

public enum ParagraphMaker {
    public static func makeParagraphs(from root: Element) throws -> [Paragraph] {
        let visitor = ParagraphMakerVisitor()
        try root.traverse(visitor)
        visitor.finish()
        return visitor.paragraphs
    }
}
