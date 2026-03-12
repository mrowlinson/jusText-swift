import Foundation
import jusText

let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: demo <path-to-html-file>")
    exit(1)
}

let html = try String(contentsOfFile: args[1], encoding: .utf8)
let paragraphs = try justext(htmlText: html, language: "English")

let good = paragraphs.filter { !$0.isBoilerplate }
let bad  = paragraphs.filter { $0.isBoilerplate }

print("── jusText results ─────────────────────────────────────")
print("Total paragraphs : \(paragraphs.count)")
print("Good (content)   : \(good.count)")
print("Boilerplate      : \(bad.count)")
print("────────────────────────────────────────────────────────\n")

for (i, p) in good.enumerated() {
    let preview = p.text.prefix(200)
    let suffix  = p.text.count > 200 ? "…" : ""
    print("[\(i + 1)] \(preview)\(suffix)\n")
}
