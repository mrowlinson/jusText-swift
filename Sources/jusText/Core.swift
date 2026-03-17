import SwiftSoup

public func preprocessHTML(_ html: String) throws -> Element {
    let doc = try SwiftSoup.parse(html)
    let tagsToRemove = ["script", "style", "head", "noscript",
                        "object", "embed", "applet", "iframe", "form"]
    for tag in tagsToRemove {
        try doc.select(tag).remove()
    }
    guard let body = doc.body() else { throw JusTextError.noBody }
    return body
}
