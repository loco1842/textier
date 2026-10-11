# JSON Viewer: is there a Swift package we should adopt?

Researched 2026-10-09. Every link below was looked at that day. GitHub facts (stars, license, last commit, latest release) come from the GitHub REST API (`gh api repos/<owner>/<repo>`) unless another source is given.

## Question and bottom line

Is there a Swift package that could replace or improve the JSON Viewer (`Sources/Textier/JSONViewer.swift`, plus `JSONDetailView`, `NodeToolbar`, `JSONTextHost` and `JSONColoring` in `EntryDetailView.swift`)?

**Bottom line: no. Keep our own viewer, and don't add a package for Text mode either.** No maintained JSON tree or folding viewer exists for macOS. The closest, JSONPreview, is iOS/tvOS only. The code-editor components (CodeEditSourceEditor, STTextView, Neon) work on character ranges, not JSON nodes, so adopting one would replace only the drawing and leave the node model, actions, escaped-JSON handling and theme mapping for us to build. What we don't know is how our own viewer performs on 5–50 MB input, so the first spike measures that instead of trying a package.

## Requirements table

Key: ✓ meets it · partial · ✗ doesn't · ? unknown/unverified. Requirement columns: 1 order-preserving/our input · 2 coloring we control · 3 folding and expand/collapse all · 4 per-node actions · 5 large JSON · 6 macOS and Swift 6 · 8 adoption cost. Requirement 7 (license and activity) is split into the last two columns.

| Candidate | 1 | 2 | 3 | 4 | 5 | 6 | 8 cost | License | Last commit / release |
|---|---|---|---|---|---|---|---|---|---|
| **Own viewer (today)** | ✓ JSONValue | ✓ VS Code themes | ✓ | ✓ | ? not measured | ✓ | none | (app has no LICENSE file yet) | — |
| JSONPreview (RakuyoKit) | ✗ parses its own string | partial (fixed color slots) | ✓ | ✗ | ? | ✗ iOS/tvOS only | n/a | MIT | 2025-04-01 / 2.3.3 |
| JSONView (quentinfasquel) | ? | ? | ? | ✗ | ? | ✗ iOS 13 | n/a | MIT | 2021-09 / none |
| SwiftJsonViewer (sheleshr) | ? | ? | ? | ✗ | ? | ? | n/a | MIT | 2024-02 (3 stars) |
| CodeEditSourceEditor + CodeEditTextView + CodeEditLanguages | ✓ (we feed text) | ✓ via `EditorTheme` / `HighlightProviding` | partial: fold ribbon, indent-based, no public fold-all API found | ✗ char ranges only | ? | partial: macOS 13+; SPI shows a Swift 6.1–6.4 matrix (passing cells not confirmed), no data-race info | high: 8+ packages (incl. SwiftTreeSitter + tree-sitter C runtime), binary xcframework, libc++, SwiftLint build plugin | MIT (Languages: no LICENSE file) | 2025-12-31 / 0.15.2 (2025-09-16) |
| STTextView | ✓ (we feed text) | ✓ (attributes / plugins) | ✗ none found | ✗ | ? (TextKit 2, "performant") | ✓ macOS 14+, zero data-race errors on SPI | medium | **GPLv3 or commercial** | 2026-10-06 / 2.4.1 (2026-09-08) |
| Neon + SwiftTreeSitter + tree-sitter-json | ✓ | ✓ token→style map | ✗ styling only | ✗ | partial: visible-range styling | ✓ macOS 10.15+, zero data-race errors on SPI | medium: C runtime + C grammar | BSD-3 / BSD-3 / MIT | 2026-08-27 / 0.6.0 (2024-01) |
| CodeEditorView (mchakravarty) | ✓ | partial (own themes) | ✗ none found | ✗ | ? | ✓ macOS 14+ | medium | Apache-2.0 | 2026-10-05 / tag 0.16.0 |
| Highlightr / HighlighterSwift / HighlightSwift | ✓ | partial (highlight.js CSS themes) | ✗ | ✗ | ? not measured; JS in JavaScriptCore, like Shiki at 100–125 ms per 50 KB (ADR-0003) | ✓ macOS | medium: JS runtime | MIT + BSD-3 (highlight.js) | Highlightr says it is unmaintained; HighlighterSwift 2026-08; HighlightSwift 2024-11 |
| Runestone | — | — | — | — | — | ✗ iOS 14 only | n/a | MIT | 2026-03-25 / 0.5.2 |
| Splash | ✗ Swift grammar only | — | ✗ | ✗ | — | ✓ | n/a | MIT | 2022-06 / 0.16.0 (2021) |
| Sourceful (twostraws) | ? | partial | ✗ | ✗ | ? | ✓ | n/a | MIT | 2023-09 |
| jsonscape / dot-json / OhMyJson (apps) | ✓ (own parsers) | own | ✓ | partial | jsonscape claims lazy outline | ✓ | copy code, not a package | MIT | all created 2026, 0–2 stars |

## Per candidate

### Dedicated JSON viewers

- **JSONPreview** ([repo](https://github.com/RakuyoKit/JSONPreview)). Of everything we found, it comes closest to the idea behind our viewer: highlighted JSON text with fold and expand for objects and arrays, an initial folded/expanded state, links, and color slots in `HighlightColor` (README). But its `Package.swift` declares only `.iOS(.v12)` and `.tvOS(.v12)`, and its README says it "inherits from `UIView` … based on `UITextView`". It is a UIKit component with no AppKit port, so it is out. It would only be useful as a reference for drawing folds in a text view.
- **JSONView** ([repo](https://github.com/quentinfasquel/JSONView)): last push 2021-09, iOS 13 requirement per the CocoaPods listing ([pod](https://cocoapods.org/pods/JSONView)). Out.
- **SwiftJsonViewer** ([repo](https://github.com/sheleshr/SwiftJsonViewer)): 3 stars, last push 2024-02. It is a demo, not a dependency. Out.
- A Swift Package Index search for "json viewer" returned no packages ([SPI search](https://swiftpackageindex.com/search?query=json+viewer)).

### Open-source macOS JSON apps (reference code, not packages)

- **jsonscape** ([repo](https://github.com/imshaikot/jsonscape), MIT, created 2026-09-16) has an order-preserving strict parser, number literals kept verbatim, an `NSOutlineView` "Paths" view with Copy Property Path / JSONPath / Value, and per its README a lazy outline with parsing off the main thread. It has the same architecture as ours. If we ever want a "Copy JSONPath" action it is worth reading, but there is nothing in it to depend on.
- **dot-json** ([repo](https://github.com/crazythq/dot-json), MIT, SwiftUI + AppKit, "zero deps") and **OhMyJson** ([repo](https://github.com/vagabond95/OhMyJson); its README says MIT, but GitHub detects no license) are both brand-new apps with 0–2 stars.
- **OK JSON** is closed source and sold on the App Store ([listing](https://apps.apple.com/app/id1576121509)), so it is not reusable.

### CodeEditSourceEditor stack (CodeEditApp)

- **What it is.** An AppKit/SwiftUI code editor ([repo](https://github.com/CodeEditApp/CodeEditSourceEditor)) built on CodeEditTextView ([repo](https://github.com/CodeEditApp/CodeEditTextView), MIT) and CodeEditLanguages ([repo](https://github.com/CodeEditApp/CodeEditLanguages)), which ships its tree-sitter parsers, JSON included, as a prebuilt `CodeLanguagesContainer.xcframework.zip` binary target and links `c++` ([Package.swift](https://github.com/CodeEditApp/CodeEditLanguages/blob/main/Package.swift)). CodeEditLanguages also depends on SwiftTreeSitter (`from: "0.9.0"`), which brings in the tree-sitter C runtime. The other dependencies are TextFormation, CodeEditSymbols, TextStory and swift-collections, which makes eight-plus packages. The targets also declare the `SwiftLintPlugin` build plugin ([Package.swift](https://github.com/CodeEditApp/CodeEditSourceEditor/blob/main/Package.swift)). That plugin's manifest downloads SwiftLint as a `binaryTarget` artifact bundle from realm/SwiftLint releases ([Package.swift](https://github.com/lukepistrol/SwiftLintPlugin/blob/main/Package.swift)), so it would run when we build their sources.
- **Fit.** Release 0.14.0 (2025-07-02) added "an optional code folding ribbon" ([releases](https://github.com/CodeEditApp/CodeEditSourceEditor/releases)). Folding comes from a `LineFoldProvider` protocol, and the default provider is `LineIndentationFoldProvider` ([source](https://github.com/CodeEditApp/CodeEditSourceEditor/tree/main/Sources/CodeEditSourceEditor/LineFolding)). The `LineFoldModel` methods have no `public` modifier, so we found no public expand-all/collapse-all. The editor has `isEditable`/`isSelectable` flags (`SourceEditorConfiguration+Behavior.swift`). Coloring goes through a 16-slot `EditorTheme` struct, or through our own `HighlightProviding` implementation that returns `HighlightRange`s ([source](https://github.com/CodeEditApp/CodeEditSourceEditor/blob/main/Sources/CodeEditSourceEditor/Highlighting/HighlightProviding/HighlightProviding.swift)). That would let us keep our tokenizer. But `setUp` still takes a `CodeLanguage`, so the xcframework stays.
- **What it would replace.** At most `JSONTextHost`/`JSONColoring` for Text mode. Tree mode would keep everything: `JSONNode`, per-node selection, Copy Key/Key Path, Parse Inline, link Actions, the hover copy button and closing-brace rows. An editor only knows character ranges, so we would also have to map ranges back to nodes.
- **Risks.** The README says "currently in development and it is not ready for production use". There have been no commits since 2025-12-31 and no release since 0.15.2 (2025-09-16). SPI shows a Swift 6.1–6.4 build matrix (we did not confirm which cells pass) and "no data race safety information" ([SPI](https://swiftpackageindex.com/CodeEditApp/CodeEditSourceEditor)). The SourceEditor README's MIT link points at the CodeEdit *app* repo, and CodeEditLanguages has no LICENSE file (GitHub's license API returns 404). The license of the bundled grammars and of that package itself is unverified. Of all the candidates this is the heaviest dependency, and it buys one feature: folding in Text mode.

### STTextView (krzyzanowskim)

- **What it is.** A TextKit 2 replacement for NSTextView/UITextView with line numbers, find, and plugins for tree-sitter or Neon highlighting ([README](https://github.com/krzyzanowskim/STTextView)). It requires macOS 14+ and is actively maintained (commit 2026-10-06, release 2.4.1 on 2026-09-08). SPI reports zero data-race safety errors ([SPI](https://swiftpackageindex.com/krzyzanowskim/STTextView)).
- **Fit.** We found no folding in its source tree; a path search for "fold" matched nothing. It would be a faster Text mode, not a tree.
- **Blocker.** Its [LICENSE.md](https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md) is GPLv3 for open-source apps compatible with it, or a paid commercial license otherwise. That conflicts with an MIT-style app unless we take GPL for the whole app or buy the commercial license.

### Neon + SwiftTreeSitter + tree-sitter-json

- **What it is.** Neon ([repo](https://github.com/slsrepo/Neon); `github.com/ChimeHQ/Neon` now redirects there) is a text-system-independent styling engine. It maps semantic labels to styles, includes `TextViewHighlighter` for NSTextView, and does "background processing when needed to scale to large documents" (README). Its `Package.swift` uses tools 6.0 and macOS 10.15+, and pins SwiftTreeSitter to `branch: "main"`, which is unpinned. SwiftTreeSitter now lives at [tree-sitter/swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter) (BSD-3, release 0.10.0 on 2026-03-18) and depends on the tree-sitter C runtime 0.25. [tree-sitter-json](https://github.com/tree-sitter/tree-sitter-json) is MIT, with a 27.7 KB `parser.c` and last release v0.24.8 (2024-11).
- **Fit.** tree-sitter-json yields the same few token kinds (strings, numbers, true/false/null, punctuation) that our order-preserving parser already gives `JSONTokenKind` (ADR-0002). Adding it means a C runtime and a C grammar that recompute what we already have. Neon has no folding and no view. The part worth considering is visible-range styling for very large Text mode, and Neon can take any token source, ours included. Its theme helper ThemePark ([repo](https://github.com/slsrepo/ThemePark)) reads TextMate, Xcode and BBEdit themes, not the VS Code JSON themes we bundle (ADR-0003).
- **Risks.** The last release is 0.6.0 from 2024-01 ([SPI](https://swiftpackageindex.com/slsrepo/Neon)), though the main branch had activity in 2026-08. The repo moved recently. The SwiftTreeSitter dependency is on a branch, not a version.

### Ruled out quickly

- **CodeEditorView** ([repo](https://github.com/mchakravarty/CodeEditorView), Apache-2.0, macOS 14+): the README lists highlighting, minimap and messages but no folding. Its `LanguageSupport` has configurations for Agda, Cabal, Cypher, Haskell, Python, SQLite and Swift, and none for JSON. The author calls it "pre-release quality".
- **Runestone** ([repo](https://github.com/simonbs/Runestone)): `Package.swift` declares only `.iOS(.v14)`.
- **Splash** ([repo](https://github.com/JohnSundell/Splash)): a Swift-code highlighter. Last commit 2022-06, last release 2021.
- **Sourceful** ([repo](https://github.com/twostraws/Sourceful)): an NSTextView/UITextView highlighter with no pushes since 2023-09.
- **Highlightr** ([repo](https://github.com/raspu/Highlightr)): its README now opens with "As of 2026, Highlightr is no longer actively maintained" and points to **HighlighterSwift** ([repo](https://github.com/smittytone/HighlighterSwift), MIT + highlight.js BSD-3 per LICENCE.md, highlight.js 11.11.1). **HighlightSwift** ([repo](https://github.com/appstefan/HighlightSwift), MIT, last commit 2024-11) is also highlight.js on JavaScriptCore. ADR-0003 already weighed and rejected a JS highlighter (Shiki in JavaScriptCore). None of the three fold, and their themes are highlight.js CSS, not VS Code.
- **TextStory / TextFormation** ([TextStory](https://github.com/johnrbent/TextStory), [TextFormation](https://github.com/johnrbent/TextFormation); `ChimeHQ/*` redirects there): an NSTextStorage helper and typing-completion rules. They are for editing, which we don't do.

## Recommendation

**Keep the NSOutlineView viewer for Tree mode and the NSTextView for Text mode. Adopt no package.**

Why:
1. Requirements 1, 3 and 4 depend on a JSON node model: order-preserving `JSONValue`, per-node selection, Copy Key Path, Parse Inline for escaped JSON, Actions on URL and file-path values, and closing-brace rows. No macOS package provides one. Editors provide character ranges, so we would keep `JSONNode` and add a range mapping on top.
2. Coloring already comes from our tokenizer and the bundled VS Code themes (ADR-0003). tree-sitter or highlight.js would recompute the same tokens with a weaker theme story.
3. The only package with folding (CodeEditSourceEditor) self-describes as not production-ready, has been quiet for nine months, and brings a binary xcframework whose license we could not verify. The best-maintained text view (STTextView) is GPL/commercial.
4. The decision can be reversed. CodeEditSourceEditor's `HighlightProviding` and `LineFoldProvider` are public protocols we could implement from `JSONValue` if folding in Text mode ever becomes a requirement.

**What we would build instead, if needed:**
- If the spike shows Text mode is slow on big input: color only the visible range and build attributes lazily, in the same spirit as Neon's priority ranges, but without the dependency. Or cap Text mode above a size and point the user to Tree mode.
- If Tree mode is slow: decouple the expand-on-open rule from size (`isExpandedOnOpen`), and make sure expand-all on a huge subtree is bounded or confirmed.

**Throwaway spike (do this first):** measure our own viewer, because none of the candidates has published numbers for JSON at this size.
1. Generate fixtures at 5, 20 and 50 MB: one wide (an array of 200k objects), one deep (nesting 500+ levels), and one with long escaped-JSON strings.
2. In a scratch test or harness (`scripts/test.sh`), time `JSONValue.parse`, then `JSONViewer.init` + `scrollView` (`reloadData` + `expandOnOpen`), then Expand All on the root, then Text mode's `prettyPrinted` + `JSONColoring.attributedString`. Text mode colors the whole document twice (light and dark) and re-parses each string token to look for links, so it is the likely hot spot.
3. Only if Text mode is the bottleneck *and* folding there is wanted, do a second throwaway spike: CodeEditSourceEditor read-only with a `HighlightProviding` backed by our tokenizer on the 50 MB fixture. Keep it on a branch, since it adds eight-plus packages, a binary xcframework and a SwiftLint build plugin.

## Sources (all looked at 2026-10-09)

- textier: `Sources/Textier/JSONViewer.swift`, `Sources/Textier/EntryDetailView.swift`, `docs/adr/0001–0003`, `.scratch/textier-v5/spec.md`
- JSONPreview: https://github.com/RakuyoKit/JSONPreview (README, Package.swift, release 2.3.3)
- JSONView: https://github.com/quentinfasquel/JSONView · https://cocoapods.org/pods/JSONView
- SwiftJsonViewer: https://github.com/sheleshr/SwiftJsonViewer
- SPI search "json viewer": https://swiftpackageindex.com/search?query=json+viewer
- jsonscape: https://github.com/imshaikot/jsonscape · dot-json: https://github.com/crazythq/dot-json · OhMyJson: https://github.com/vagabond95/OhMyJson · OK JSON: https://apps.apple.com/app/id1576121509
- CodeEditSourceEditor: https://github.com/CodeEditApp/CodeEditSourceEditor (README, Package.swift, LineFolding/, Highlighting/HighlightProviding/, SourceEditorConfiguration/, releases) · https://swiftpackageindex.com/CodeEditApp/CodeEditSourceEditor
- CodeEditTextView: https://github.com/CodeEditApp/CodeEditTextView (Package.swift, LICENSE)
- SwiftLintPlugin: https://github.com/lukepistrol/SwiftLintPlugin (Package.swift)
- CodeEditLanguages: https://github.com/CodeEditApp/CodeEditLanguages (Package.swift, README; no LICENSE file)
- STTextView: https://github.com/krzyzanowskim/STTextView (README, Package.swift, LICENSE.md) · https://swiftpackageindex.com/krzyzanowskim/STTextView
- Neon: https://github.com/slsrepo/Neon (README, Package.swift) · https://swiftpackageindex.com/slsrepo/Neon
- SwiftTreeSitter: https://github.com/tree-sitter/swift-tree-sitter · tree-sitter-json: https://github.com/tree-sitter/tree-sitter-json
- ThemePark: https://github.com/slsrepo/ThemePark
- CodeEditorView: https://github.com/mchakravarty/CodeEditorView (README, Package.swift, Sources/LanguageSupport)
- Runestone: https://github.com/simonbs/Runestone (Package.swift)
- Splash: https://github.com/JohnSundell/Splash · Sourceful: https://github.com/twostraws/Sourceful
- Highlightr: https://github.com/raspu/Highlightr · HighlighterSwift: https://github.com/smittytone/HighlighterSwift (LICENCE.md) · HighlightSwift: https://github.com/appstefan/HighlightSwift
- TextStory: https://github.com/johnrbent/TextStory · TextFormation: https://github.com/johnrbent/TextFormation
