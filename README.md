# jusText for Swift

> Swift port of **[miso-belica/jusText](https://github.com/miso-belica/jusText)**

A Swift port of the [jusText](https://github.com/miso-belica/jusText) boilerplate removal library. Extracts the main article content from HTML pages by classifying text blocks as **good** (content) or **bad** (boilerplate) using a combination of heuristics: link density, stopword density, block length, and context-sensitive neighbour analysis.

Bundled with stopword lists for **100 languages**.

---

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mrowlinson/jusText-swift.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: ["jusText"]),
]
```

---

## Usage

### Built-in stoplist (recommended)

```swift
import jusText

let html = // ... your HTML string ...
let paragraphs = try justext(htmlText: html, language: "English")

for p in paragraphs where !p.isBoilerplate {
    print(p.text)
}
```

### Custom stoplist

```swift
let stoplist: Set<String> = ["the", "a", "and", "of", "in"]
let paragraphs = try justext(htmlText: html, stoplist: stoplist)
```

### Tuning the classifier

```swift
var options = ClassifierOptions()
options.maxLinkDensity = 0.2    // blocks with more links than this → bad
options.lengthLow      = 70     // chars; below this → short
options.lengthHigh     = 200    // chars; above this + high stopwords → good
options.stopwordsLow   = 0.30   // stopword density threshold (low)
options.stopwordsHigh  = 0.32   // stopword density threshold (high)
options.noHeadings     = false  // set true to ignore heading context

let paragraphs = try justext(htmlText: html, language: "English", options: options)
```

### Available languages

```swift
let languages = getStoplists()
// Set of 100 language names, e.g. "English", "German", "French", "Spanish", …
```

---

## How it works

jusText classifies each block of text extracted from the HTML DOM using a two-pass algorithm.

**Pass 1 — context-free classification**

Each paragraph is classified independently based on:

| Condition | Class |
|---|---|
| Link density > threshold | `bad` |
| Contains © symbol | `bad` |
| Inside a `<select>` | `bad` |
| Length < `lengthLow` and has link chars | `bad` |
| Length < `lengthLow`, no links | `short` |
| Stopword density ≥ `stopwordsHigh` and long | `good` |
| Stopword density ≥ `stopwordsHigh`, short | `neargood` |
| Stopword density ≥ `stopwordsLow` | `neargood` |
| Otherwise | `bad` |

**Pass 2 — context-sensitive revision**

- `short` blocks surrounded by `good` neighbours → promoted to `good`
- `short` blocks surrounded by `bad` neighbours → stay `bad`
- `neargood` blocks with at least one `good` neighbour → promoted to `good`
- Headings near `good` content → promoted to `good`

---

## Output

Each `Paragraph` in the returned array has:

| Property | Type | Description |
|---|---|---|
| `text` | `String` | Normalised text content |
| `classType` | `ParagraphClass` | `.good`, `.bad`, `.short`, `.nearGood` |
| `isBoilerplate` | `Bool` | `true` if not `.good` |
| `heading` | `Bool` | `true` if the block is a heading element |
| `linksDensity()` | `Double` | Fraction of chars inside `<a>` tags |
| `stopwordsDensity(_:)` | `Double` | Fraction of words that are stopwords |
| `domPath` | `String` | Dot-separated DOM path, e.g. `body.article.p` |

---

## Requirements

- Swift 6.2+
- macOS 13+ / iOS 16+
- Depends on [SwiftSoup](https://github.com/scinfu/SwiftSoup) for HTML parsing

---

## Credits

Algorithm and stopword lists by [Jan Pomikálek](https://github.com/miso-belica/jusText). This is an independent Swift port.
